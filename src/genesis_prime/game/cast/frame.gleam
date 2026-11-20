//// The messages the cast rule writes to the client and the frames it tells the viewers: a cast starting, going and finishing, a refusal, ticks, removed targets, crowd control and the combat log.
////
//// - **The cast bar and cooldowns** are the client's own: 0x7fd and 0x7ff start
////   the caster's global cooldown (`0x14046afc0`, kinds 0 and 1), and a go starts
////   the spell's own (`0x14046b1e0`), so the server sends no 0x804. The server
////   keeps the same, to refuse what the client would: the global cooldown from the
////   accept for the SpellCoolDown time, the spell's own where its method says
////   (`spell_plan.CooldownStart`, `0x14053e5a0`), the child casts none (kind 3).

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast/state.{
  type Aimed, type Caster, type CreatureEffect, type Effect, type Listed,
  type Refusal, type State, type Struck, Deflected, Hit, Immune, NoClientCastId,
  NoInteractionWaits, NoItemSpell, NotDecoded, NotSentByClient, Send, StateEnd,
  UnknownAnswer, UnknownCancel, WrongAnswerSpell,
} as cast_state
import genesis_prime/game/cast/target_info
import genesis_prime/game/hit
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/telegraph_entries.{type Opening}
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_immunity.{CombatLogImmunity}
import genesis_prime/message/combat_log_interrupted.{CombatLogInterrupted}
import genesis_prime/message/combat_log_modify_interrupt_armor.{
  CombatLogModifyInterruptArmor,
}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/miss_reason
import genesis_prime/message/spell_cast_confirmed.{SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick.{type SpellEffectTick}
import genesis_prime/message/spell_failed.{SpellFailed}
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo, SpellGo}
import genesis_prime/message/spell_miss.{SpellMiss}
import genesis_prime/message/spell_missed.{type SpellMissed, SpellMissed}
import genesis_prime/message/spell_stack_removed.{type SpellStackRemoved}
import genesis_prime/message/spell_started.{type SpellStarted, SpellStarted}
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/message/spell_targets_removed.{type SpellTargetsRemoved}
import genesis_prime/message/spell_threshold_closed.{SpellThresholdClosed}
import genesis_prime/message/spell_threshold_index.{SpellThresholdIndex}
import genesis_prime/message/spell_threshold_opened.{SpellThresholdOpened}
import genesis_prime/message/unit_cc_state_applied.{UnitCcStateApplied}
import genesis_prime/message/unit_cc_state_ended.{UnitCcStateEnded}
import genesis_prime/message/unit_tether_anchor.{UnitTetherAnchor}
import genesis_prime/table/id.{type Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// 0x07F9 for a cast of `unit_id` that failed with `result`, the bit 0 (`opcode.0x7f9`).
pub fn failed_frame(
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
  unit_id unit_id: Int,
) -> Frame {
  let assert Ok(body) =
    spell_failed.encode(SpellFailed(cast_id:, result:, unit_id:, cut_visuals: 0))
    as "a cast id of 32 bits, a result of 9, a unit id of 32 and a bit fit the message"
  Frame(message_id: spell_failed.message_id, body:)
}

/// 0x881: the tether anchor of the unit the receiving client controls is this unit
/// (`opcode.0x881`).
pub fn tether_anchor_frame(anchor_unit_id anchor_unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_tether_anchor.encode(UnitTetherAnchor(anchor_unit_id:))
    as "a unit id of 32 bits fits the message"
  Frame(message_id: unit_tether_anchor.message_id, body:)
}

/// 0x87f: the unit holds the crowd-control state, the effect of the go that gave it
/// `instance_id` (`opcode.0x87f`, `cc_state.instance_id`).
pub fn control_applied_frame(
  unit_id unit_id: Int,
  state state: CrowdControlState,
  instance_id instance_id: Int,
) -> Frame {
  let assert Ok(body) =
    unit_cc_state_applied.encode(UnitCcStateApplied(
      unit_id:,
      state:,
      instance_id:,
    ))
    as "unit ids and instance ids of 32 bits and a state of 5 fit the message"
  Frame(message_id: unit_cc_state_applied.message_id, body:)
}

/// 0x880: the unit's crowd-control state of that cast and instance ends, its last bit
/// 0 (`opcode.0x880`, `cc_state.end`).
pub fn control_ended_frame(
  unit_id unit_id: Int,
  state state: CrowdControlState,
  cast_id cast_id: Int,
  instance_id instance_id: Int,
) -> Frame {
  let assert Ok(body) =
    unit_cc_state_ended.encode(UnitCcStateEnded(
      unit_id:,
      state:,
      cast_id:,
      instance_id:,
      keeps_flag_4_entries: 0,
    ))
    as "unit ids, a cast id and an instance id of 32 bits, a state of 5 and a bit fit the message"
  Frame(message_id: unit_cc_state_ended.message_id, body:)
}

/// The caster's combat log of the states a go landed: an entry for each (0x247 of
/// type 1, removed 0), with the type 19 entry of the interrupt right after it for a state
/// that broke a cast (`strike_tell.ControlLanded.interrupted`), and a timer for each state's end entry (removed 1) at the time
/// the creature holds it until (`opcode.0x247.cc_state`). A state's end entry is never
/// written for a unit the caster's client stopped showing: `cast_proc.unit_removed` cancels it.
pub fn states_logged(
  cast cast: State,
  caster caster: Caster,
  spell4_id spell4_id: Spell4Id,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.controls, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(landed, unit_id) = entry
    let state = landed.tell.row.state
    let #(cast, _, start) =
      cast_state.armed(
        cast:,
        due: StateEnd(spell4_id:, unit_id:, state:),
        after_ms: int.max(0, landed.ends_at_ms - now_ms),
      )
    #(
      cast,
      list.flatten([
        effects,
        [
          Send(frame: control_logged_frame(
            caster_unit_id: caster.unit_id,
            unit_id:,
            spell4_id:,
            state:,
            removed: False,
          )),
        ],
        case landed.interrupted {
          Some(strike_tell.Interrupted(spell4_id: interrupted)) -> [
            Send(frame: interrupt_logged_frame(
              caster_unit_id: caster.unit_id,
              unit_id:,
              interrupting_spell4_id: spell4_id,
              interrupted_spell4_id: interrupted,
            )),
          ]
          None -> []
        },
        [start],
      ]),
    )
  })
}

/// 0x247 of type 19: the caster's spell interrupted the unit's cast of
/// `interrupted_spell4_id`. The client prints '<unit> is interrupted while casting
/// <spell> by <caster>'s <interrupting spell>' from it. The cast result is
/// SpellInterrupted as the cast's 0x7f9 gives, which the client prints only for a unit that
/// interrupts itself, and the combat result is a choice, Hit, which the client shows to no
/// one (`opcode.0x247.interrupted`).
fn interrupt_logged_frame(
  caster_unit_id caster_unit_id: Int,
  unit_id unit_id: Int,
  interrupting_spell4_id interrupting_spell4_id: Spell4Id,
  interrupted_spell4_id interrupted_spell4_id: Spell4Id,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.Interrupted(CombatLogInterrupted(
          interrupting_spell4_id: interrupting_spell4_id.value,
          cast_result: cast_result.SpellInterrupted,
          caster_unit_id:,
          target_unit_id: unit_id,
          spell4_id: interrupted_spell4_id.value,
          combat_result: combat_result.Hit,
        )),
      ),
    )
    as "unit ids and Spell4 ids that fit their fields"
  Frame(message_id: combat_log.message_id, body:)
}

/// 0x247 of type 1: the state set on the unit by the caster's spell, or ended. The
/// Interrupt Armor it hit is 0 and its result Ok: a creature takes a state only with no
/// armor, and no diminishing returns apply (`opcode.0x247.cc_state`).
pub fn control_logged_frame(
  caster_unit_id caster_unit_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Spell4Id,
  state state: CrowdControlState,
  removed removed: Bool,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.CcState(CombatLogCcState(
          state:,
          removed: case removed {
            True -> 1
            False -> 0
          },
          interrupt_armor_hit: 0,
          result: crowd_control_result.Ok,
          diminishing_returns_id: 0,
          caster_unit_id:,
          target_unit_id: unit_id,
          spell4_id: spell4_id.value,
          combat_result: combat_result.Hit,
        )),
      ),
    )
    as "unit ids and a Spell4 id that fit their fields"
  Frame(message_id: combat_log.message_id, body:)
}

/// 0x247 of type 18: the unit took no damage from the caster's spell because it is
/// immune to it. The client shows the 'Immune' line and floater from it alone; the
/// combat result is a choice, Hit, which the client shows to no one
/// (`opcode.0x247.immunity`).
pub fn immunity_logged_frame(
  caster_unit_id caster_unit_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Spell4Id,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.Immunity(CombatLogImmunity(
          caster_unit_id:,
          target_unit_id: unit_id,
          spell4_id: spell4_id.value,
          combat_result: combat_result.Hit,
        )),
      ),
    )
    as "unit ids and a Spell4 id that fit their fields"
  Frame(message_id: combat_log.message_id, body:)
}

/// 0x247 of type 14: the unit lost `amount` of its Interrupt Armor to the caster's
/// spell; the combat result is a choice, Hit (`opcode.0x247.modify_interrupt_armor`).
pub fn armor_logged_frame(
  caster_unit_id caster_unit_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Spell4Id,
  amount amount: Int,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.ModifyInterruptArmor(
          CombatLogModifyInterruptArmor(
            amount:,
            caster_unit_id:,
            target_unit_id: unit_id,
            spell4_id: spell4_id.value,
            combat_result: combat_result.Hit,
          ),
        ),
      ),
    )
    as "unit ids and a Spell4 id that fit their fields"
  Frame(message_id: combat_log.message_id, body:)
}

/// 0x7ff for a cast that starts: the caster is its own primary target
/// (`Spell4TargetMechanics.targetType`), the lists are empty (`spell.empty_lists`),
/// the 16-bit value is the level of the item whose use started the cast, 0 for a cast
/// that no item started (`opcode.0x7ff.caster_item_level`), and the two bits are the
/// decode's safe values (`opcode.0x7ff.own_cast`, `opcode.0x7ff.activate`). The activate
/// bit is set only for the creature's own activate cast, never for an item's cast at a
/// creature (`opcode.0x7ff.activate`: only `CastActivateSpell` sets it).
pub fn started_message(
  id id: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  caster caster: Caster,
  activating activating: Bool,
  caster_item_level caster_item_level: Int,
) -> SpellStarted {
  SpellStarted(
    cast_id: id,
    spell4_id: spell.spell4_id.value,
    root_spell4_id: root.value,
    parent_spell4_id: case parent {
      Some(parent) -> parent.value
      None -> 0
    },
    caster_unit_id: caster.unit_id,
    caster_item_level:,
    primary_target_unit_id: primary_target,
    position: telegraph_entries.position_of(place: caster.place),
    yaw: cast_state.yaw_of(place: caster.place),
    initial_positions: [],
    telegraph_positions: [],
    own_cast: 1,
    creature_activate: case activating {
      True -> 1
      False -> 0
    },
  )
}

/// 0x7f4 for a go: a target info for each Hit unit in the order of the round, with
/// target flags 0 (`opcode.0x7f4.target_info`), each with the damage that landed, no
/// position and no missile (`opcode.0x7f4`, `spell.empty_lists`). A deflected unit has
/// no info: the 0x7fb shows it.
pub fn go_message(
  cast_id cast_id: Int,
  phase phase: Int,
  place place: Place,
  struck struck: List(Struck),
  listed listed: List(#(Int, List(Listed))),
) -> SpellGo {
  let hits =
    list.filter_map(struck, fn(one) {
      case one {
        Hit(unit_id:, descriptions:, ..) -> Ok(#(unit_id, descriptions))
        Immune(unit_id:, ..) -> Ok(#(unit_id, []))
        Deflected(..) -> Error(Nil)
      }
    })
  let unstruck =
    list.filter(listed, fn(entry) {
      result.is_error(list.key_find(hits, entry.0))
    })
    |> list.map(fn(entry) { #(entry.0, []) })
  SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: telegraph_entries.position_of(place:),
    targets: list.append(hits, unstruck)
      |> list.index_map(fn(hit, index) {
        struck_target(
          index:,
          unit_id: hit.0,
          descriptions: hit.1,
          listed: list.key_find(listed, hit.0) |> result.unwrap([]),
        )
      }),
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase:,
  )
}

/// The refusal of a press that names no ability, or no stage left of one: result 4
/// (`0x14039a040`), the same answer to a 0x9a and to a 0x4db.
pub fn refused_unknown(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
) -> Effect {
  refused(client_cast_id:, spell4_id:, result: cast_result.SpellUnknown)
}

/// The refusal of a cast as an effect that writes it: `refused_frame`.
pub fn refused(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  result result: cast_result.CastResult,
) -> Effect {
  Send(frame: refused_frame(client_cast_id:, spell4_id:, result:))
}

/// The 0x07FC that refuses the cast the client numbered `client_cast_id` of the spell with
/// `result`.
pub fn refused_frame(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  result result: cast_result.CastResult,
) -> Frame {
  let assert Ok(body) =
    spell_cast_refused.encode(SpellCastRefused(
      client_cast_id:,
      spell4_id:,
      result:,
    ))
    as "a cast id of 32 bits, a Spell4 id of 18 and a result of 9 fit the message"
  Frame(message_id: spell_cast_refused.message_id, body:)
}

/// 0x07FD for the press's cast: the client's id, the server's, the caster as its
/// primary target and the position and yaw the 0x7ff holds.
pub fn confirmed_frame(
  client_cast_id client_cast_id: Int,
  start start: SpellStarted,
) -> Frame {
  let assert Ok(body) =
    spell_cast_confirmed.encode(
      SpellCastConfirmed(
        client_cast_id:,
        server_cast_id: start.cast_id,
        primary_target_unit_id: start.primary_target_unit_id,
        position: start.position,
        yaw: start.yaw,
        initial_positions: [],
        telegraph_positions: [],
      ),
    )
    as "a cast id of 32 bits and floats fit the message, and the rule sends no list"
  Frame(message_id: spell_cast_confirmed.message_id, body:)
}

/// 0x0816 for a threshold that opens: the ability's spell as the opened spell, the bag
/// ability that was pressed as the second spell the client matches a press against (the
/// same spell unless Spell Surge swapped it), 0 for the third (the opened spell's own
/// cooldowns), and the base cast's id as the value the client sends back
/// (`opcode.0x816`).
pub fn opened_frame(
  spell4_id spell4_id: Spell4Id,
  bag_spell bag_spell: Spell4Id,
  cast_id cast_id: Int,
) -> Frame {
  let assert Ok(body) =
    spell_threshold_opened.encode(SpellThresholdOpened(
      spell4_id: spell4_id.value,
      resolving_spell4_id: bag_spell.value,
      cooldown_spell4_id: 0,
      cancel_cast_id: cast_id,
    ))
    as "Spell4 ids of 18 bits and a cast id of 32 fit the message"
  Frame(message_id: spell_threshold_opened.message_id, body:)
}

/// 0x0817 for the index the next press casts (`opcode.0x817`).
pub fn index_frame(spell4_id spell4_id: Spell4Id, index index: Int) -> Frame {
  let assert Ok(body) =
    spell_threshold_index.encode(SpellThresholdIndex(
      spell4_id: spell4_id.value,
      index:,
    ))
    as "a Spell4 id of 18 bits and a stage index of 8 fit the message"
  Frame(message_id: spell_threshold_index.message_id, body:)
}

/// 0x0814 for a threshold that closes, with the bit that starts the cooldowns
/// (`opcode.0x814`).
pub fn closed_frame(
  spell4_id spell4_id: Spell4Id,
  start_cooldowns start_cooldowns: Int,
) -> Frame {
  let assert Ok(body) =
    spell_threshold_closed.encode(SpellThresholdClosed(
      spell4_id: spell4_id.value,
      start_cooldowns:,
    ))
    as "a Spell4 id of 18 bits and a bit fit the message"
  Frame(message_id: spell_threshold_closed.message_id, body:)
}

/// 0x7ff for a creature's cast of its attack spell on its target, from where it
/// stands: the target is the cast's primary target, which the client draws a client-placed
/// target row on (`0x140546e60.placement_branches`), the spell its own root, and the
/// safe values are a player's cast's (`started_message`). The positions are the
/// `opening` of the spell's server-placed telegraph rows, which the client draws only
/// from them (`0x140546e60`, `spell.telegraph_position`), those of the caster and of the
/// target; a spell with none is sent `telegraph_entries.none`. A row the client places on
/// the caster or the target itself needs no
/// entry: it draws it from the caster's own place and facing each frame (Spell4Telegraph
/// 57886 for 85469 and 57885 for 86978, each TelegraphDamage row 16212: a rectangle 3 wide
/// and 30 long, targetTypeFlags 1, `0x14054b1b0.follows_caster`), which a 0x7ff yaw does
/// not turn.
pub fn creature_started(
  cast_id cast_id: Int,
  spell4_id spell4_id: Int,
  caster_unit_id caster_unit_id: Int,
  target_unit_id target_unit_id: Int,
  place place: Place,
  opening opening: Opening,
) -> SpellStarted {
  SpellStarted(
    cast_id:,
    spell4_id:,
    root_spell4_id: spell4_id,
    parent_spell4_id: 0,
    caster_unit_id:,
    caster_item_level: 0,
    primary_target_unit_id: target_unit_id,
    position: telegraph_entries.position_of(place:),
    yaw: cast_state.yaw_of(place:),
    initial_positions: opening.initial_positions,
    telegraph_positions: opening.telegraph_positions,
    own_cast: 1,
    creature_activate: 0,
  )
}

/// 0x7f4 for the go of a creature's cast with the phase `phase`, with the units its round
/// struck (none for a go that strikes no one), as a player's go is written (`go_message`).
pub fn creature_went(
  cast_id cast_id: Int,
  phase phase: Int,
  place place: Place,
  struck struck: List(Struck),
) -> SpellGo {
  go_message(cast_id:, phase:, place:, struck:, listed: [])
}

/// 0x7f4 for the one go, phase 0, of a creature's cast that applies effects to one unit, as the
/// unit's one target info lists them: each effect with its instance id, delay 0 and lifetime
/// (`lifetime_ms`, `opcode.0x7f4.effect_time`) and no result of its own (`SpellEffectBit`), in the
/// order given.
pub fn creature_applied(
  cast_id cast_id: Int,
  place place: Place,
  target_unit_id target_unit_id: Int,
  effects effects: List(CreatureEffect),
) -> SpellGo {
  SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: telegraph_entries.position_of(place:),
    targets: [
      target_info.target(
        index: 0,
        unit_id: target_unit_id,
        instance_count: 1,
        combat_result: combat_result.Hit,
        effects: list.map(effects, fn(effect) {
          target_info.effect(
            effect_id: effect.effect_id,
            instance_id: effect.instance_id,
            delay_ms: 0,
            lifetime_ms: effect.lifetime_ms,
            result: target_info.bit(),
          )
        }),
      ),
    ],
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase: 0,
  )
}

/// 0x7fb for the units a creature's go missed, or none (`missed_message`).
pub fn creature_missed(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  missed_message(cast_id:, struck:)
}

/// 0x07FF for a cast that starts, which the caster's rule tells each viewer as
/// news and each viewer's connection writes the same way.
pub fn started_frame(start start: SpellStarted) -> Frame {
  let assert Ok(body) = spell_started.encode(start)
    as "a cast id of 32 bits, Spell4 ids of 18 and a unit id of 32 fit the message, and the rule sends no list"
  Frame(message_id: spell_started.message_id, body:)
}

/// 0x07F4 for a cast that goes off, written by the caster's rule and by each
/// viewer's connection the same way.
pub fn went_frame(go go: SpellGo) -> Frame {
  let assert Ok(body) = spell_go.encode(go)
    as "a cast id of 32 bits and a phase of 8 fit the message, and the rule sends no list"
  Frame(message_id: spell_go.message_id, body:)
}

/// 0x07F8 for one tick of a periodic row of a cast on a unit, written by the caster's
/// rule and by each viewer's connection the same way (`opcode.0x7f8`).
pub fn ticked_frame(tick tick: SpellEffectTick) -> Frame {
  let assert Ok(body) = spell_effect_tick.encode(tick)
    as "a cast id of 32 bits, a Spell4Effects id of 19 and a tick's few descriptions fit the message"
  Frame(message_id: spell_effect_tick.message_id, body:)
}

/// 0x07F9 for a cast of `unit_id` that was interrupted: result 11 and the bit 0, written
/// by each viewer's connection before the cast's 0x7fe (`opcode.0x7f9`).
pub fn interrupted_frame(cast_id cast_id: Int, unit_id unit_id: Int) -> Frame {
  failed_frame(cast_id:, result: cast_result.SpellInterrupted, unit_id:)
}

/// 0x07FE for a cast that ends, written by the caster's rule and by each
/// viewer's connection the same way (`opcode.0x7fe`).
pub fn finished_frame(cast_id cast_id: Int) -> Frame {
  let assert Ok(body) = spell_finished.encode(SpellFinished(cast_id:))
    as "a cast id of 32 bits fits the message"
  Frame(message_id: spell_finished.message_id, body:)
}

/// 0x0811 for a cast taken off some units, written by the caster's rule and by each
/// viewer's connection the same way (`opcode.0x811`).
pub fn targets_removed_frame(removed removed: SpellTargetsRemoved) -> Frame {
  let assert Ok(body) = spell_targets_removed.encode(removed)
    as "a cast id of 32 bits and at most a few unit ids of 32 fit the message"
  Frame(message_id: spell_targets_removed.message_id, body:)
}

/// 0x0813 for a cast that loses one stack on a unit, written by the caster's rule and
/// by each viewer's connection the same way (`opcode.0x813`).
pub fn stack_removed_frame(removed removed: SpellStackRemoved) -> Frame {
  let assert Ok(body) = spell_stack_removed.encode(removed)
    as "a cast id and a unit id of 32 bits fit the message"
  Frame(message_id: spell_stack_removed.message_id, body:)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoClientCastId ->
      "0x009A, 0x0097 or 0x009D names the client's cast id 0, which its counter never gives"
    UnknownCancel(reason:, bit:) ->
      "0x0801 holds the reason "
      <> int.to_string(reason)
      <> " and the bit "
      <> int.to_string(bit)
      <> ", which the client never sends together"
    UnknownAnswer(result:) ->
      "0x0805 holds the result "
      <> int.to_string(result)
      <> ", which the client never sends"
    NoInteractionWaits(cast_id:) ->
      "0x0805 answers the cast "
      <> int.to_string(cast_id)
      <> ", which waits for no interaction's answer"
    WrongAnswerSpell(cast_id:, sent:, expected:) ->
      "0x0805 for the cast "
      <> int.to_string(cast_id)
      <> " holds the spell word "
      <> int.to_string(sent)
      <> " in place of "
      <> int.to_string(expected)
    NoItemSpell ->
      "0x0943 names an item that has no spell, which the client answers itself"
    NotSentByClient ->
      "0x0943 names a second item the client does not send for the item's spell"
  }
}

/// One struck unit's info in a go: its place in the list, target flags 0
/// (`opcode.0x7f4.target_info`), the combat result of the strike, and an effect
/// info for each landed blow with its damage description and delay. The instance
/// count and the effects' instance ids number from 1 (kept by the client, no reader
/// traced), except a crowd-control state's, which is the id its tell gave
/// (genesis_prime/game/crowd_control `instance_id`).
fn struck_target(
  index index: Int,
  unit_id unit_id: Int,
  descriptions descriptions: List(hit.Description),
  listed listed: List(Listed),
) -> SpellTargetInfo {
  target_info.target(
    index:,
    unit_id:,
    instance_count: 1,
    combat_result: case list.any(descriptions, hit.is_critical) {
      True -> combat_result.Critical
      False -> combat_result.Hit
    },
    effects: list.append(
      list.index_map(descriptions, fn(description, effect_index) {
        target_info.effect(
          effect_id: description.spell4_effects_id,
          instance_id: effect_index + 1,
          delay_ms: description.delay_ms,
          lifetime_ms: 0,
          result: spell_effect_result.Damage(SpellEffectDamage(
            description: description.damage,
          )),
        )
      }),
      list.index_map(listed, fn(effect, effect_index) {
        target_info.effect(
          effect_id: effect.effect_id.value,
          instance_id: option.unwrap(
            effect.instance_id,
            list.length(descriptions) + effect_index + 1,
          ),
          delay_ms: effect.delay_ms,
          lifetime_ms: 0,
          result: case effect.damage {
            Some(description) ->
              spell_effect_result.Damage(SpellEffectDamage(description:))
            None -> target_info.bit()
          },
        )
      }),
    ),
  )
}

/// 0x7fb for the deflected units of a go, or none when none was deflected: each
/// entry has reason 0 (Dodge, which the client shows as Deflect) and time 0
/// (`opcode.0x7fb`, `opcode.0x7fb.time`).
pub fn missed_message(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  case
    list.filter_map(struck, fn(one) {
      case one {
        Deflected(unit_id:) ->
          Ok(SpellMiss(unit_id:, reason: miss_reason.Dodge, time_ms: 0))
        Hit(..) | Immune(..) -> Error(Nil)
      }
    })
  {
    [] -> None
    misses -> Some(SpellMissed(cast_id:, misses:))
  }
}

/// 0x07FB for a cast whose targets were missed, written by the caster's rule and by
/// each viewer's connection the same way.
pub fn missed_frame(missed missed: SpellMissed) -> Frame {
  let assert Ok(body) = spell_missed.encode(missed)
    as "a cast id of 32 bits, a unit id of 32 and a reason of 4 fit the message"
  Frame(message_id: spell_missed.message_id, body:)
}
