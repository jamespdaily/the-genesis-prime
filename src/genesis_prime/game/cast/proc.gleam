//// The procs and passives a cast holds, and the breaking of stealth.
////
//// - **A player's stealth** is the Stealth rows (effect type 83) its casts hold on it,
////   by cast id and effect id (`State.stealth`), kept with whether damage ends each
////   (`spell_plan.Breaks`); the player is stealthed while it holds any (`cast_state.stealthed`).
////   A go lists each Stealth row of its phase whose gate passes against the caster in
////   the caster's target info and holds the caster's node until it is removed (a Stealth
////   row with no durationTime lasts until removed), and adds its source; a RemoveStealth
////   row (type 84) ends every source. After the go's effects, a spell whose
////   `stealth_change` ends stealth at that go (value 0 at each go, value 1 at the cast's
////   last) ends every source of the other casts (`Spell4.spellCastStealthChange.break`;
////   the server's rule): the cast of each loses its node on the caster as a type 80 removal takes it off (0x811, and
////   the 0x7fe of a lingering cast of a method the client keeps, `node_off`; a Normal
////   cast the client destroys with the 0x811), so the buff that stands for the stealth
////   never outlives it. A node that leaves the caster takes its cast's sources
////   with it (`effects_ended`), `cast.blow_taken` ends the sources damage breaks, and
////   death and leaving drop all. Each input (a press, a timer, a go, the player's death,
////   a blow) compares the stealth before and after and ends with one `StealthChanged`
////   when it moved, so the connection's 0x8f5 follows the 0x811 and 0x7fe it causes and
////   precedes the procs it fires. A
////   caster's type 116 prerequisite reads the stealth as it stood before the go's own
////   effects, as every gate does (`cast_tick.subject_of`).
//// - **A player's procs** are the Proc rows (effect type 14, `spell_plan.ProcRow`) its casts hold on
////   it, by cast id and effect id (`State.procs`), each with the times it fired at. A go lists each
////   Proc row of its phase whose gate passes in the caster's target info and holds the caster's node
////   until the row's life ends, as a Stealth row does (`Spell4Effects.effectType.14.lifetime`), and
////   adds its source; a source leaves where a stealth source leaves (`effects_ended`), at the
////   caster's death but for the standing spells', and at leaving. Each input ends in `cast.settled`,
////   which records its events as pending (`State.pending`), in order: the input's own (`Died` for
////   `cast.died`, `LeftCombat` for `cast.combat_left`, and the hits of the strike round a go or a tick
////   settles, `hit_events`), a `LandsHeal` for each Heal change its effects start on the caster,
////   and its stealth change (`EnteredStealth` or `LeftStealth`). A hit is an event for each
////   damage description that landed on a creature: `LandsHit`, `LandsMeleeHit` when the spell is of
////   school 1, `LandsCritical` for a critical and `Kills` for a kill (a guess:
////   `Spell4Effects.effectType.14.client_evaluation`); a spell that only selects a unit raises none.
////   A creature's blow on the holder raises `TakesDamage` when it lowered the holder's absorbs,
////   shield or health, `SuffersCritical` for a critical, `ShieldDepleted` when it took the shield
////   to 0 and `DeflectsAttack` for a deflect, each with the creature as the other unit and its
////   attack spell as the event's spell (`blow_events`).
////   The rule decides nothing about a draw: the connection asks `proc_draws_needed` how many
////   chance words and gate rolls the pending events need, one draw for all, and hands them to
////   `cast.procs_fire`, which matches each event, in order and then source order, against the proc rows
////   held when the input's own work was done (the server's choice, `.dataBits00.217_218`, `.0_44`):
////   a proc whose node the same input took off does not fire, and one the input applied does.
////   `proc.decide` checks, in this order, the limit (at most `count` fires in any `window_ms`, a
////   fire exactly `window_ms` after the last allowed, the server's choice of the edge,
////   `Spell4Effects.effectType.14.limits`), the filter, the holder gate, the event gate and the
////   chance (a word's fraction below the chance fires; a chance of 1.0 takes no word). A fire is
////   counted at the event; a proc with a delay starts a timer (`Due.ProcDue`) that casts the
////   spell when it fires, and the holder's cast ending cancels the timers of its procs. The cast
////   starts as a child's does, from the caster at its aim (`.dataBits03`): a 0x7ff with the holder's
////   spell as root and parent and no 0x7fd (`opcode.0x7ff.root_parent`). Its go and finish are
////   inputs of their own, so a fire's events are matched in a later step and no proc cascades inside
////   one. A spell whose caster condition refuses the caster's life (row 1, mask 225, refuses a dead
////   caster: `Spell4.spell4ConditionsIdCaster`, `cast.dead_player`) does not fire and records no
////   fire, with a debug line. A death leaves a standing spell's procs with its cast and ends every
////   other cast before the procs are matched, so a `Died` proc of any other cast is never held: its
////   go writes a debug line (the plan cannot tell a standing spell, so the rule enforces it,
////   `procs_held`); a camp drops the procs and their fire times.
////   A Proc row held by the player the press named or by each ally the round hit is held by that
////   player: the go tells it as a change that applies nothing (`held_changes.Awaits`,
////   `cast_control.modifiers_armed`) and the caster keeps one entry for it by source and holder
////   (`State.procs`). The caster's own events match its own entries alone (`proc_draws_needed`,
////   `cast.procs_fire`); an ally's entry leaves with the change on that ally
////   (`cast_control.ended_where`), and the caster's node leaving drops the caster's own entries
////   alone (`procs_dropped`).
//// - **A unit that leaves the caster's sight** takes its nodes with it on the client
////   (`0x1404550d0`), so the rule drops them too and a lingering cast left with no node
////   ends with its 0x7fe (`unit_removed`).
//// - **A standing spell** (the innate passive, then the worn items' equip spells) is a cast the client never makes:
////   `cast.standing_changed` starts it at each join with a 0x7ff and no 0x7fd, as `Passive`, which starts no global
////   cooldown, is never the current cast, opens no threshold and runs no check of the
////   caster. Its go runs as any cast's, and the cast lingers with no 0x7fe, even when
////   no node of it lives, for the whole stay. The three passives hold caster condition
////   row 4 (mask 0: alive or dead) and propertyFlags 0x100 (the cast stays when its
////   caster is removed), so a death leaves it with its nodes and modifiers
////   (`Class.spell4IdInnateAbilityPassive00`, `Spell4.spell4ConditionsIdCaster`;
////   the server's choice for what death does to a cast no press made), and a camp, which
////   leaves every cast, drops it, so the next join starts it again.
////
//// What happens at each failure point of a cast:
////
//// | Point | What happens |
//// |---|---|
//// | a 0x9a body the client's reader refuses, or a cast id of 0 | the connection ends, nothing written |
//// | a 0x4db body the client's reader refuses | the connection ends, nothing written |
//// | a 0x4db whose bag index holds no ability | 0x7fc {0, 0, 4} for held 1, a debug line for held 0 |
//// | a 0x4db held 1 of the ability already held | the same hold: nothing written |
//// | a held cast refused, at the first press or a repeat | the 0x7fc, and the hold ends |
//// | the repeat timer fires after the release | nothing: the release cancelled it, and a firing that was already sent finds no hold |
//// | a press whose bag index the player does not hold | 0x7fc {client id, 0, 4} |
//// | a press past the last stage of an open threshold | 0x7fc {client id, the ability, 4} |
//// | a refusal of the client's own checks | 0x7fc with the result; nothing else changes |
//// | a spell whose cost has an EMM id the server does not read | 0x7fc with the cost's result, a warning once for the spell on the connection; nothing is paid |
//// | a cast with a cost ends before its first go: a 0x801, the caster's death or leaving | nothing is paid and nothing is sent for the cost; its reservation ends with the cast |
//// | a press needs points that a live cast has reserved | 0x7fc with the cost's result, as for a slot that holds too little |
//// | a threshold row's class cost of a vital the class's slots hold nothing of (a Charged Shot release at 0 Spell Power) | 0x7fc with 175; nothing is paid |
//// | the slot holds less than a live cast reserved when its first go comes (the Esper's empty, the Warrior's drain) | the go pays what the slot holds, down to 0 |
//// | a 0x801 ends a cast while the round of its first go is open | the cost was paid as the strike began; the round's answer finds no live cast: no go is written, the hits stand |
//// | a press whose CasterCast or TargetCast fails | 0x7fc {client id, spell, 151 or 281}, after every other check; nothing else changes |
//// | a press whose cast condition is of a type the server does not read | 0x7fc 151 or 281, a warning once for the spell |
//// | a held press, or a held key's repeat, whose cast condition fails when it starts | 0x7fc {client id, or 0 for a key, spell, 151}; nothing started, a key's hold ends |
//// | a caster requirement fails and the spell's waiver passes | the requirement is waived; the next is checked |
//// | a caster requirement fails and its waiver is not read | 0x7fc with the requirement's result, a warning once for the spell |
//// | a lasting cast's persistence fails | 0x7f9 {cast id, 282 or 283, caster, 0}, 0x7fe, CastFinished to each viewer; timers and modifiers end; the current cast clears; a press held for it starts |
//// | a persistence not read, or a target persistence on a creature | the cast goes on; a debug line once for the spell |
//// | two casts whose persistence fails in one input, or one that fails because the other ended | both end in that input, the lower cast id first |
//// | a persistence check while the player is leaving or dead | nothing: `cast_tick.left` and `cast.died` have already dropped every cast |
//// | a press while one is held | 0x7fc 13 |
//// | a press of a spell whose caster conditions mask Ability Restriction while the caster holds it | 0x7fc 302, ahead of the cooldowns; a spell whose mask lacks bit 27 passes |
//// | a go gives the caster Ability Restriction | 0x87f to the caster and its audience, once for the effect; a `RestrictionEnd` timer at the row's delay plus duration, none for flag 2; the cast lingers until its persistence ends (the server reads no ride, so the hoverboard's ends in the go's own input) |
//// | a `RestrictionEnd` fires for a state the caster holds | 0x880 with the cast and the instance id of its 0x87f, before the cast's node ends; a row of duration 0 without flag 2 ends in the go's own step |
//// | a cast that holds Ability Restriction ends (its persistence fails, a type 80 removal takes its node off, its node ends by time) | the `RestrictionEnd` timers cancelled, and 0x880 for a state the row's end has not already ended, after the 0x7f9 or the 0x811; a death or a leave drops the state and writes nothing |
//// | a 0x805 result 3 of an activate cast of castMethod 5 | nothing: the interaction only began |
//// | a 0x805 result 1 before or after the cast time has run | the go and the finish at the later of the two: at the answer, or at the go's timer when the answer came first |
//// | a 0x805 result 0 or 2 | 0x7f9 146, 0x7fe, the go's timer cancelled; no go and no `Activated` |
//// | a 0x805 for a cast that is not live (the client's 0 as a finish closes its window) | nothing; a debug line |
//// | a 0x805 for a live cast that waits for no answer, naming another spell, or with a result of 4 to 7 | the connection ends |
//// | a go lists a heal while the caster's vital is full | the description carries the whole amount as its overheal; the vital writes nothing (genesis_prime/game/player_life) |
//// | a heal's timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing lands |
//// | a heal's start and its node's end fire in either order | the heal lands once, in the step of whichever is delivered first |
//// | a go lists an absorb and its connection restarts before the start | no pool: the connection enters with none and the client is created again |
//// | an absorb's start timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing starts |
//// | an absorb's end timer fires after the pool was used up, or the death dropped it | the end writes nothing (genesis_prime/game/player_life) |
//// | a go of the cast arms its absorb while the earlier go's pool is held | the pool is refilled to the new amount, its end timer set again |
//// | an absorb's end and a blow reach the connection in one millisecond | arrival order: the pool soaks and then ends, or ends first |
//// | a go adds a Stealth source while the stack cap of its spell takes the first cast off | one source left, one 0x811, no `StealthChanged` |
//// | a go of a spell that ends stealth after the stealth ended | nothing to end, nothing written |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` after one of its goes and before its last | the other casts' stealth ends as the cast stops, the 0x811 and the change after the cast's own end |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` before its first go | the stealth stays held, nothing written |
//// | the caster dies stealthed | every cast ends, the sources drop, `StealthChanged` last |
//// | the player leaves stealthed | the sources drop, nothing is written |
//// | a proc's trigger happens inside its window | nothing is cast, no fire is recorded |
//// | a proc's chance word is not below its chance | nothing is cast, no fire is recorded |
//// | a go's hit names a creature with no damage description | no event, no proc fires |
//// | a hit's trigger is matched while its proc's delay runs | the fire is counted at the event; the cast starts when its `ProcDue` timer fires, and is cancelled with the holder's cast |
//// | a proc's trigger and the removal of its holder's node in one input | the removed proc does not fire: procs are matched after the input's work |
//// | a proc's trigger happens for a caster its spell's condition refuses (a dead caster) | a debug line naming the row and the spell, no cast and no fire recorded |
//// | a go of a cast that is not a standing spell's applies a `Died` proc | the proc is not held, with a debug line: a death ends the cast before it could fire |
//// | the caster dies in combat | `cast.combat_left`, then `cast.died`: 63366 twice, each under its own limit |
//// | the caster camps or leaves stealthed | the procs drop with every cast, nothing is cast or written |
//// | a press with 500 ms or less of the current cast left | held, nothing written; taken at the go or finish that clears the current cast |
//// | a 0x801 for a cast that is not live, or one already finished | no change, a debug line |
//// | a 0x801 (0, 0) naming no open threshold | no change, a debug line |
//// | a 0x801 with a reason and bit the client never sends | the connection ends |
//// | a parent cast finishes with a child's timer pending | the child starts when its timer fires, with the root and parent it was made with |
//// | a threshold's window ends with taps left | the threshold closes, nothing is written, the cooldown starts |
//// | the player camps with casts, children or a threshold pending | every timer is cancelled and nothing is written: the viewers' clients drop the cast with the unit (the connection writes each viewer's 0x7fe before its 0x355) |
//// | the caster's connection ends, a key held | its timers and the hold end with it; the map's `Gone` removes the unit from each viewer, which finishes its casts first |
//// | the caster dies with casts live | each ends with its timers cancelled and 0x7fe to the caster and its audience; the hold and every other timer end, but the standing spells' casts, their nodes, modifiers and pending children (`cast.died`) |
//// | a standing spell stops standing | its cast ends with its 0x7fe, live or lingering, and its modifiers, procs and pending children end with it (`cast.standing_changed`) |
//// | the innate passive's plan is missing | a warning and no cast: the plans hold every class's passive, or the load fails (`connection/casting.standing_wanted`) |
//// | a timer fires after its cast ended | a go finds no live cast and does nothing; the cast's end cancels its go timers |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |
//// | a go lists a lasting effect, the last go leaves a node with life | the cast lingers with no 0x7fe; the timer of its earliest ending node starts |
//// | a lingering cast's timer fires with no node ended, or after a removal took the cast off | nothing is written; the timer starts again for the nodes left, or finds no cast |
//// | two nodes of a lingering cast end at the same time | one 0x811 naming both units |
//// | a removal and a lingering cast's timer in one step | the removal first; the timer finds nothing |
//// | the caster dies with a lingering cast | its 0x7fe to the caster and the audience, with the live casts' (server choice: the client has no death path) |
//// | the caster leaves with a lingering cast | every timer is cancelled and nothing is written; each viewer's 0x355 ends the cast on its client |
//// | the client cancels a cast that holds a node with life left | its pending gos are cancelled and it lingers, with no 0x7fe until the node ends |
//// | a live cast's node ends while the cast goes on | 0x811 for the unit; the cast's later gos go on |
//// | a unit holding a node of a cast leaves the caster's sight | the node is dropped with no frame; a lingering cast left with no node ends with its 0x7fe |

import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/state.{
  type Aimed, type Aside, type Caster, type Due, type Effect, type HeldProc,
  type Holder, type Live, type ProcHold, type StandingKey, type State,
  type Struck, Activated, Aside, CancelTimer, CasterChangeEnding,
  CasterChangeEnds, CasterChangeStarts, ChargeLevel, CooldownEnding,
  CooldownModifierEnds, CooldownModifierStarts, CreatureControlsEnd,
  CreatureDespawns, CreatureHoldsUnitStates, Deflected, FindProxyTickUnits,
  Finish, ForcedMoveStart, ForcedMoveStarts, Gain, Go, Heal, HeldChange,
  HeldProc, Hit, HitCaster, HitCreature, HitOtherPlayer, HitPlayer, Immune, Log,
  Look, ModifierEnd, ModifierStart, NodesEnd, OtherPlayerCastWent,
  OtherPlayerChangeEnds, OtherPlayerChangeStarts, Pay, PlayerChangeEnd, ProcDue,
  ProcHold, QuestAdvanceDue, QuestAdvanced, RepeatHeld, RestrictionEnd, Send,
  ShortcutCast, StartChild, StartHeld, StartTimer, State, StateEnd,
  StealthChanged, Strike, TargetChangeEnds, TargetChangeStarts,
  TargetModifierStart, Tell, Tick, TickStrike, WindowEnd,
} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/cooldown
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/proc
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties
import genesis_prime/gap
import genesis_prime/message/crowd_control_state
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{type Spell4Id, Spell4Id}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The events of the heals an input's effects start on the caster: for each `Heal` change
/// in order, a `LandsHeal` and then a `ReceivesHeal`, since the caster is the one who
/// heals and the one healed (a heal aimed at another unit starts no change on the caster
/// and raises neither). Two readings are guesses: a heal that moves nothing is one as well,
/// and a heal of the shields or of any other vital counts as a heal as a health heal
/// does (the client reads no Proc row to say what a heal is,
/// `Spell4Effects.effectType.14.dataBits00`). The event's spell is the spell of the cast
/// whose row healed, as `after` holds it or, for a cast the input ended, `before`.
/// `LandsCriticalHeal` is never raised: no heal is rolled a critical.
pub fn heals_landed(
  before before: State,
  after after: State,
  effects effects: List(Effect),
) -> List(proc.Event) {
  list.flat_map(effects, fn(effect) {
    case effect {
      CasterChangeStarts(source:, change: Heal(..)) -> {
        let spell =
          option.map(
            option.from_result(
              result.lazy_or(
                cast_state.holder_of(cast: after, cast_id: source.cast_id),
                fn() {
                  cast_state.holder_of(cast: before, cast_id: source.cast_id)
                },
              ),
            ),
            fn(holder) { event_spell(spell: holder.spell) },
          )
        [
          proc.Event(
            trigger: spell_plan.LandsHeal,
            other_unit: None,
            spell:,
            holder: None,
          ),
          proc.Event(
            trigger: spell_plan.ReceivesHeal,
            other_unit: None,
            spell:,
            holder: None,
          ),
        ]
      }
      CasterChangeStarts(change: HeldChange(..), ..)
      | CasterChangeStarts(change: Look(..), ..) -> []
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | FindProxyTickUnits(..)
      | Pay(..)
      | Gain(..)
      | CasterChangeEnds(..)
      | OtherPlayerChangeStarts(..)
      | OtherPlayerChangeEnds(..)
      | OtherPlayerCastWent(..)
      | TargetChangeStarts(..)
      | TargetChangeEnds(..)
      | CreatureControlsEnd(..)
      | ForcedMoveStarts(..)
      | CreatureDespawns(..)
      | CreatureHoldsUnitStates(..)
      | Activated(..)
      | ShortcutCast(..)
      | QuestAdvanced(..)
      | StealthChanged(..) -> []
    }
  })
}

/// A `SpendsResource` event for each payment the effects take from the caster's class
/// resource. A guess: the event names no spell, so a group filter never matches it (a
/// payment does not say which spell it is for, and no client code reads a Proc row,
/// `Spell4Effects.effectType.14.dataBits00`).
pub fn resources_spent(effects effects: List(Effect)) -> List(proc.Event) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Pay(..) ->
        Ok(proc.Event(
          trigger: spell_plan.SpendsResource,
          other_unit: None,
          spell: None,
          holder: None,
        ))
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | FindProxyTickUnits(..)
      | Gain(..)
      | CasterChangeStarts(..)
      | CasterChangeEnds(..)
      | OtherPlayerChangeStarts(..)
      | OtherPlayerChangeEnds(..)
      | OtherPlayerCastWent(..)
      | TargetChangeStarts(..)
      | TargetChangeEnds(..)
      | CreatureControlsEnd(..)
      | ForcedMoveStarts(..)
      | CreatureDespawns(..)
      | CreatureHoldsUnitStates(..)
      | Activated(..)
      | ShortcutCast(..)
      | QuestAdvanced(..)
      | StealthChanged(..) -> Error(Nil)
    }
  })
}

/// The events a strike round's units give the holder, in the round's order: for each
/// description of the damage that landed on a creature, a hit, a melee hit when the spell is
/// of school 1, a critical when the description's combat result is a critical (and a finisher
/// critical, which the row's group filter narrows to finishers) and a kill
/// when it killed the creature, so a go with two damage rows on one creature raises two
/// hits and a spell that only selects a unit (no description) raises none; then a taunt
/// landed for each Taunt state the creature took, a guarded creature's included. A
/// deflected unit raises a deflect and no hit, and an immune one no hit, and a player
/// a creature's attack hit, or another player healed, is not the holder's strike (a guess for each description
/// counting, for a deflect, an immunity, a finisher critical and a taunt: no client code
/// reads a Proc row, `Spell4Effects.effectType.14.client_evaluation`).
pub fn hit_events(
  spell spell: Spell,
  struck struck: List(Struck),
) -> List(proc.Event) {
  let on = fn(unit_id, trigger) {
    proc.Event(
      trigger:,
      other_unit: Some(unit_id),
      spell: Some(event_spell(spell:)),
      holder: None,
    )
  }
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, unit: HitCreature(..), descriptions:, controls:, ..) ->
        list.append(
          list.flat_map(descriptions, fn(description) {
            list.map(hit_triggers(spell:, description:), on(unit_id, _))
          }),
          taunts_landed(unit_id:, controls:, on:),
        )
      Immune(unit_id:, unit: HitCreature(..), controls:, ..) ->
        taunts_landed(unit_id:, controls:, on:)
      Deflected(unit_id:) -> [on(unit_id, spell_plan.FoeDeflects)]
      Hit(unit: HitPlayer, ..)
      | Immune(unit: HitPlayer, ..)
      | Hit(unit: HitOtherPlayer(..), ..)
      | Immune(unit: HitOtherPlayer(..), ..)
      | Hit(unit: HitCaster(..), ..)
      | Immune(unit: HitCaster(..), ..) -> []
    }
  })
}

/// A taunt landed event for each Taunt state a unit took.
fn taunts_landed(
  unit_id unit_id: Int,
  controls controls: List(strike_tell.ControlLanded),
  on on: fn(Int, spell_plan.Trigger) -> proc.Event,
) -> List(proc.Event) {
  list.filter_map(controls, fn(control) {
    case control.tell.row.state == crowd_control_state.Taunt {
      True -> Ok(on(unit_id, spell_plan.LandsTaunt))
      False -> Error(Nil)
    }
  })
}

/// A creature's blow on the holder, as the connection tells the cast rule (it maps
/// genesis_prime/game/player_life's `Took`, which this module does not import). `striker`
/// is the creature's unit and `spell` its attack spell.
pub type BlowTaken {
  /// The blow landed. `lowered` says the absorbs, the shield or the health fell, `critical`
  /// that a description of the blow is a critical, even when the absorbs took all of it, and
  /// `shield_depleted` that the shield went from above 0 to 0 (guesses for the three:
  /// no client code reads a Proc row, `Spell4Effects.effectType.14.client_evaluation`).
  BlowLanded(
    striker: Int,
    spell: proc.EventSpell,
    lowered: Bool,
    critical: Bool,
    shield_depleted: Bool,
  )
  /// The holder deflected the blow.
  BlowDeflected(striker: Int, spell: proc.EventSpell)
}

/// Whether the blow lowered the holder's absorbs, shield or health: a deflect lowers none.
pub fn lowers(blow blow: BlowTaken) -> Bool {
  case blow {
    BlowLanded(lowered:, ..) -> lowered
    BlowDeflected(..) -> False
  }
}

/// The events a creature's blow on the holder raises, in order: `TakesDamage` when it
/// lowered something, `SuffersCritical` for a critical and `ShieldDepleted` when it took the
/// shield to 0, or `DeflectsAttack` for a deflect. Each names the creature as the other unit
/// and its attack spell as the spell.
pub fn blow_events(blow blow: BlowTaken) -> List(proc.Event) {
  let on = fn(trigger) {
    proc.Event(
      trigger:,
      other_unit: Some(blow.striker),
      spell: Some(blow.spell),
      holder: None,
    )
  }
  case blow {
    BlowLanded(lowered:, critical:, shield_depleted:, ..) ->
      list.flatten([
        case lowered {
          True -> [on(spell_plan.TakesDamage)]
          False -> []
        },
        case critical {
          True -> [on(spell_plan.SuffersCritical)]
          False -> []
        },
        case shield_depleted {
          True -> [on(spell_plan.ShieldDepleted)]
          False -> []
        },
      ])
    BlowDeflected(..) -> [on(spell_plan.DeflectsAttack)]
  }
}

/// The spell of an event as a proc's filter reads it.
pub fn event_spell(spell spell: Spell) -> proc.EventSpell {
  proc.EventSpell(
    spell4_id: spell.spell4_id,
    groups: spell.groups,
    school: spell.school,
  )
}

/// The triggers one damage description of a strike on a creature raises.
fn hit_triggers(
  spell spell: Spell,
  description description: hit.Description,
) -> List(spell_plan.Trigger) {
  let critical = hit.is_critical(description)
  list.flatten([
    [spell_plan.LandsHit],
    case spell.school {
      1 -> [spell_plan.LandsMeleeHit]
      _ -> []
    },
    case critical {
      True -> [spell_plan.LandsCritical, spell_plan.LandsFinisherCritical]
      False -> []
    },
    case description.damage.killed != 0 {
      True -> [spell_plan.Kills]
      False -> []
    },
  ])
}

/// Whether an input raised events the held procs have not been matched against yet.
pub fn has_pending(cast cast: State) -> Bool {
  cast.pending != []
}

/// The words and the gate rolls the connection draws before the pending events are matched
/// (`cast.procs_fire`): for each pending event, each held proc of its trigger takes what
/// `proc.draws_needed` gives, whether or not an earlier check stops it, so the count is
/// exact. A state with nothing pending needs none.
pub fn proc_draws_needed(cast cast: State) -> #(Int, Int) {
  list.fold(cast.pending, #(0, 0), fn(total, event) {
    list.fold(dict.to_list(cast.procs), total, fn(total, entry) {
      let #(hold, held) = entry
      case fires_for(hold:, held:, event:) {
        True -> {
          let #(words, rolls) = proc.draws_needed(row: held.row)
          #(total.0 + words, total.1 + rolls)
        }
        False -> total
      }
    })
  })
}

/// Whether the held proc `held`, held as `hold`, is one the event `event` fires: the row waits
/// for the event's trigger, and the entry is held on the unit the event is of (the caster's own
/// entry for its own events, the entry for an ally for that ally's). `procs_fire` and
/// `proc_draws_needed` both ask it, so the entries that fire are the entries that draw.
pub fn fires_for(
  hold hold: ProcHold,
  held held: HeldProc,
  event event: proc.Event,
) -> Bool {
  hold.holder == event.holder && held.row.trigger == event.trigger
}

/// The units the pending events concern besides the caster, which the event gates read:
/// the connection takes their poses, checklist indexes and kinds from its picture of the
/// caster's world for `cast.procs_fire`.
pub fn pending_units(cast cast: State) -> List(Int) {
  list.filter_map(cast.pending, fn(event) {
    option.to_result(event.other_unit, Nil)
  })
  |> list.unique
}

/// The debug line that says a proc's spell is not cast because its caster condition refuses a
/// caster of the life the caster has, or none.
pub fn proc_refusal(
  caster caster: Caster,
  row row: spell_plan.ProcRow,
  holder_spell4_id holder_spell4_id: Spell4Id,
) -> Option(Effect) {
  cast_gate.life_refusal(
    kind: "Proc",
    effect_id: row.effect_id,
    holder_spell4_id:,
    spell: row.spell,
    caster:,
  )
}

/// The Proc rows of a go that stand on the caster (`aimed.reached`: its own rows, and a row held
/// by the primary target in a press at oneself), each held by the cast `cast_id` from this go
/// on; a row the cast already holds keeps its fires, as a later go of the same cast is the same
/// node. The rows on other players are held where they are told (`cast_control.modifiers_armed`).
pub fn procs_held(
  cast cast: State,
  cast_id cast_id: Int,
  caster caster: Caster,
  aimed aimed: Aimed,
) -> #(State, List(Effect)) {
  let #(never, held) =
    list.partition(
      list.filter_map(
        cast_state.rows_reached(
          reached: aimed.reached,
          as_kind: spell_plan.as_proc,
        ),
        fn(found) {
          case { found.0 }.unit_id == caster.unit_id {
            True -> Ok(found.1)
            False -> Error(Nil)
          }
        },
      ),
      fn(row) {
        row.trigger == spell_plan.Died
        && !cast_state.is_standing(cast:, cast_id:)
      },
    )
  let procs =
    list.fold(held, cast.procs, fn(procs, row) {
      let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
      dict.upsert(procs, ProcHold(source:, holder: None), fn(found) {
        case found {
          Some(already) -> already
          None -> HeldProc(row:, fires_ms: [])
        }
      })
    })
  #(
    State(..cast, procs:),
    list.map(never, fn(row) {
      Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of kind 0 is held by a cast that is not a standing cast, which a death ends before the proc is matched, so it is not held",
      )
    }),
  )
}

/// The cast's nodes after some left: a lingering cast with none left is dropped; any
/// other keeps the nodes it has, with its `NodesEnd` timer started again for them.
pub fn nodes_left(
  cast cast: State,
  cast_id cast_id: Int,
  holder holder: Holder,
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder.lingering && dict.is_empty(nodes) {
    True -> {
      let #(cast, cancels) = cast_tick.cancel_nodes_end(cast:, cast_id:)
      #(
        standing_cleared(
          cast: State(..cast, lingering: dict.delete(cast.lingering, cast_id)),
          cast_id:,
        ),
        cancels,
      )
    }
    False ->
      cast_tick.rearmed(
        cast: cast_tick.with_nodes(cast:, cast_id:, nodes:),
        cast_id:,
        now_ms:,
      )
  }
}

/// A unit the caster's client shows is removed from it (a 0x355 for a unit it was
/// shown): the client destroys that unit's nodes then (`0x1404550d0`), so the
/// unit's nodes are dropped from the live and lingering casts, and nothing is
/// written for them; a lingering cast left with no node sends its finish and is
/// dropped, and one that keeps nodes has its `NodesEnd` timer started again. This
/// bounds the casts that linger by the units in sight, so the caster's cast ids
/// (`cast_state.mint`) cannot run out. A property modifier a dropped cast node held on a creature
/// ends with it (`TargetChangeEnds`), since nothing else would end it.
pub fn unit_removed(
  cast cast: State,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        StateEnd(unit_id: waiting, ..) -> waiting == unit_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | PlayerChangeEnd(..)
        | ModifierEnd(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | ProcDue(..)
        | QuestAdvanceDue(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  list.filter(cast_state.holders(cast:), fn(entry) {
    dict.has_key({ entry.1 }.nodes, unit_id)
  })
  |> list.fold(#(cast, cancels), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(cast_id, holder) = entry
    let nodes = dict.delete(holder.nodes, unit_id)
    let #(cast, ticks) = cast_tick.ticks_dropped(cast:, cast_id:, unit_id:)
    let #(cast, on_units) = cast_control.unit_unseen(cast:, cast_id:, unit_id:)
    let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
    let ends = case holder.lingering && dict.is_empty(nodes) {
      True -> cast_tick.finished_effects(cast_id:, audience: holder.audience)
      False -> []
    }
    #(cast, list.flatten([effects, ticks, on_units, left, ends]))
  })
}

/// The standing spells' delayed proc fires dropped with the timers of what a death set aside,
/// and their timers cancelled: the holder is gone, so no cast follows for its hit (a fire the
/// death itself makes is armed after this, by the proc pass).
pub fn proc_fires_dropped(
  aside aside: List(Aside),
) -> #(List(Aside), List(Effect)) {
  let dropped =
    list.map(aside, fn(set_aside) {
      let #(fires, kept) =
        list.partition(set_aside.timers, fn(entry) {
          case entry.1 {
            ProcDue(..) -> True
            Go(..)
            | Finish(..)
            | NodesEnd(..)
            | Tick(..)
            | ModifierStart(..)
            | ModifierEnd(..)
            | RestrictionEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | TargetModifierStart(..)
            | ForcedMoveStart(..)
            | PlayerChangeEnd(..)
            | StartChild(..)
            | StateEnd(..)
            | QuestAdvanceDue(..)
            | StartHeld
            | RepeatHeld
            | WindowEnd(..)
            | ChargeLevel(..) -> False
          }
        })
      #(
        Aside(..set_aside, timers: kept),
        list.map(fires, fn(entry) { CancelTimer(timer: entry.0) }),
      )
    })
  #(
    list.map(dropped, fn(entry) { entry.0 }),
    list.flat_map(dropped, fn(entry) { entry.1 }),
  )
}

/// The cast without each standing spell's cast, timers, stealth sources and procs, and what
/// was taken out, in cast id order.
pub fn standing_set_aside(cast cast: State) -> #(State, List(Aside)) {
  dict.to_list(cast.standing)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.fold(#(cast, []), fn(so_far, entry) {
    let #(cast, asides) = so_far
    case one_set_aside(cast:, id: entry.0, key: entry.1) {
      #(cast, Some(aside)) -> #(cast, list.append(asides, [aside]))
      #(cast, None) -> #(cast, asides)
    }
  })
}

/// The cast without the standing cast `id`, its timers, stealth sources and procs, and what
/// was taken out, when it has a cast.
fn one_set_aside(
  cast cast: State,
  id id: Int,
  key key: StandingKey,
) -> #(State, Option(Aside)) {
  let live = dict.get(cast.casts, id) |> option.from_result
  let lingering = dict.get(cast.lingering, id) |> option.from_result
  let #(timers, rest) =
    dict.to_list(cast.timers)
    |> list.partition(fn(entry) {
      belongs_to_standing(due: entry.1, id:, spell4_id: Spell4Id(key.spell4_id))
    })
  let #(stealth, others) = cast_tick.split_cast(held: cast.stealth, cast_id: id)
  let #(procs, other_procs) = procs_split(held: cast.procs, cast_id: id)
  case live, lingering {
    None, None -> #(cast, None)
    _, _ -> #(
      State(
        ..cast,
        casts: dict.delete(cast.casts, id),
        lingering: dict.delete(cast.lingering, id),
        timers: dict.from_list(rest),
        stealth: others,
        procs: other_procs,
        on_units: dict.delete(cast.on_units, id),
      ),
      Some(Aside(
        id:,
        key:,
        live:,
        lingering:,
        timers:,
        stealth:,
        procs:,
        on_units: dict.get(cast.on_units, id) |> result.unwrap([]),
      )),
    )
  }
}

/// The cast with what `standing_set_aside` took out put back.
pub fn standing_restored(cast cast: State, aside aside: List(Aside)) -> State {
  list.fold(aside, cast, fn(cast, set_aside) {
    let Aside(
      id:,
      key:,
      live:,
      lingering:,
      timers:,
      stealth:,
      procs:,
      on_units:,
    ) = set_aside
    State(
      ..cast,
      on_units: case on_units {
        [] -> cast.on_units
        [_, ..] -> dict.insert(cast.on_units, id, on_units)
      },
      casts: case live {
        Some(live) -> dict.insert(cast.casts, id, live)
        None -> cast.casts
      },
      lingering: case lingering {
        Some(lingering) -> dict.insert(cast.lingering, id, lingering)
        None -> cast.lingering
      },
      timers: dict.merge(cast.timers, dict.from_list(timers)),
      stealth: dict.merge(cast.stealth, dict.from_list(stealth)),
      procs: dict.merge(cast.procs, dict.from_list(procs)),
      standing: dict.insert(cast.standing, id, key),
    )
  })
}

/// The timers of a standing spell's tree still pending when its cast ends because the spell
/// no longer stands, cancelled: a child it was about to start does not start.
pub fn standing_timers_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
  key key: StandingKey,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    belongs_to_standing(due:, id: cast_id, spell4_id: Spell4Id(key.spell4_id))
  })
}

/// Whether a timer belongs to a standing spell's own tree: one of its cast `id`, a modifier
/// or cooldown effect of that cast, or the start of a child whose root is its spell. A child
/// is matched by its root alone, so a cast that is not standing and has the same root spell
/// would have its children taken as the standing spell's.
fn belongs_to_standing(
  due due: Due,
  id id: Int,
  spell4_id spell4_id: Spell4Id,
) -> Bool {
  case due {
    Go(cast_id:, ..)
    | Finish(cast_id:)
    | NodesEnd(cast_id:)
    | Tick(cast_id:, ..) -> cast_id == id
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | RestrictionEnd(source:)
    | ProcDue(source:, ..)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> source.cast_id == id
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) ->
      on.source.cast_id == id
    PlayerChangeEnd(source:, ..) -> source.cast_id == id
    StartChild(root:, ..) -> root == spell4_id
    StateEnd(..)
    | QuestAdvanceDue(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..) -> False
  }
}

/// Takes the node off the caster of each cast that holds a source damage breaks
/// (`cast.blow_taken`); nothing when the caster holds none.
pub fn broken_by_damage(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let sources =
    dict.filter(cast.stealth, fn(_, breaks) {
      breaks == spell_plan.BrokenByDamage
    })
    |> dict.keys
  stealth_ended(cast:, caster:, sources:, now_ms:)
}

/// The casts that hold the stealth sources taken off the caster, oldest cast first, each
/// as a type 80 removal takes a cast off a unit (`node_off`: 0x811, and the 0x7fe of a
/// lingering cast of a method the client keeps), which drops every source of the cast
/// with its node (`effects_ended`).
pub fn stealth_ended(
  cast cast: State,
  caster caster: Caster,
  sources sources: List(unit_properties.Source),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let removals =
    list.map(sources, fn(source) { source.cast_id })
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(fn(cast_id) {
      lasting.NodeOff(cast_id:, unit_id: caster.unit_id)
    })
  apply_removals(cast:, removals:, now_ms:)
}

/// Each property modifier the caster's casts may still hold, told ended in order: those
/// of the spells of its live and lingering casts, in cast id order, and those whose end
/// a timer waits for, in timer order; each once.
pub fn modifiers_pending(cast cast: State) -> List(Effect) {
  let held =
    list.flat_map(cast_state.holders(cast:), fn(entry) {
      list.map(cast_control.caster_rows(spell: { entry.1 }.spell), fn(row) {
        unit_properties.Source(cast_id: entry.0, effect_id: row.effect_id)
      })
    })
  let waiting =
    cast_state.timers_in_order(cast:)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        ModifierEnd(source:) -> Ok(source)
        ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | PlayerChangeEnd(..)
        | ProcDue(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | QuestAdvanceDue(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> Error(Nil)
      }
    })
  list.unique(list.append(held, waiting))
  |> list.map(fn(source) { CasterChangeEnds(source:) })
}

/// The effects of the cast `cast_id` ended when its node on the caster is among the
/// nodes that leave `unit_ids`, whether taken off or ended by time.
pub fn caster_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  effects_ended(cast:, cast_id:, spell:)
}

/// The effects of the cast `cast_id` ended, as its node leaves the caster: each source
/// of its spell's rows has its timers cancelled, and its stealth sources are dropped
/// (`stealth_dropped`). A property modifier that lasts until
/// removed or whose start or end a timer waited for is told ended, and a modifier whose
/// own end already fired is not told again. A cooldown effect is taken out of the kept
/// list; the cooldowns it changed stay changed, as on the client.
pub fn effects_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let endings =
    list.append(
      list.map(cast_control.caster_rows(spell:), fn(row) {
        CasterChangeEnding(
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
          until_removed: row.row.until_removed,
        )
      }),
      list.map(
        spell_plan.payloads(spell:, as_kind: spell_plan.as_cooldown_modifier),
        fn(row) {
          CooldownEnding(source: unit_properties.Source(
            cast_id:,
            effect_id: row.effect_id,
          ))
        },
      ),
    )
  let #(cast, effects) =
    list.fold(endings, #(cast, []), fn(so_far, ending) {
      let #(cast, effects) = so_far
      let waits_for_the_ending = fn(due) {
        case ending {
          CasterChangeEnding(source:, ..) ->
            cast_state.waits_for_caster_change(due:, source:)
          CooldownEnding(source:) -> cast_state.source_of(due:) == Some(source)
        }
      }
      let held = list.any(dict.values(cast.timers), waits_for_the_ending)
      let #(cast, cancels) =
        cast_state.cancel_timers(cast:, matching: waits_for_the_ending)
      case ending {
        CasterChangeEnding(source:, until_removed:) if until_removed || held -> #(
          cast,
          list.flatten([effects, cancels, [CasterChangeEnds(source:)]]),
        )
        CasterChangeEnding(..) -> #(cast, list.append(effects, cancels))
        CooldownEnding(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          list.append(effects, cancels),
        )
      }
    })
  let #(cast, heal_cancels) = cast_tick.pending_heals_cancelled(cast:, cast_id:)
  let #(restrictions, others) =
    cast_tick.split_cast(held: cast.restrictions, cast_id:)
  let cast = State(..cast, restrictions: others)
  let #(cast, restriction_cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        RestrictionEnd(source:) | ProcDue(source:, ..) ->
          source.cast_id == cast_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | PlayerChangeEnd(..)
        | ModifierEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | QuestAdvanceDue(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  #(
    procs_dropped(cast: stealth_dropped(cast:, cast_id:), cast_id:),
    list.flatten([
      effects,
      heal_cancels,
      restriction_cancels,
      cast_control.restrictions_ended(held: restrictions, cast_id:),
    ]),
  )
}

/// The stealth sources of the cast `cast_id` dropped, as its node leaves the caster: the
/// stealth lasts as long as the node that holds it.
fn stealth_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, stealth: cast_tick.without_cast(held: cast.stealth, cast_id:))
}

/// The Proc rows the caster holds itself for the cast `cast_id` dropped, as its node leaves the
/// caster: a proc is held as long as the node that holds it. The rows the cast holds on allies
/// stay with the changes on those allies (`cast_control.ended_where`).
fn procs_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(
    ..cast,
    procs: dict.filter(cast.procs, fn(hold, _) {
      hold.source.cast_id != cast_id || hold.holder != None
    }),
  )
}

/// The Proc rows held for the cast `cast_id`, on the caster or on allies, and the rows the
/// caster holds for other casts.
fn procs_split(
  held held: Dict(ProcHold, HeldProc),
  cast_id cast_id: Int,
) -> #(List(#(ProcHold, HeldProc)), Dict(ProcHold, HeldProc)) {
  let #(of_cast, others) =
    dict.to_list(held)
    |> list.partition(fn(entry) { { entry.0 }.source.cast_id == cast_id })
  #(of_cast, dict.from_list(others))
}

/// The nodes a go gives, one for each unit a Fluff row aims at or a crowd-control state
/// landed on: count 1 and the longest life of its rows with the effects the cast's node on
/// the unit already holds (`lasting.given`: a later go keeps and re-arms them, as on the
/// client, `opcode.0x7f4.instance_count`), and at least until the time the creature
/// holds each state, which no later go moves; a unit left with no effect that has a life
/// and no state holds no node of the cast. A node on a creature the go's round struck
/// carries that round's life and time (`lasting.StruckCreature`); a node on a unit the
/// round did not hit as a creature keeps the stamp of the one it replaces.
pub fn nodes_given(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  struck struck: List(Struck),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id), cast_tick.nodes_aimed(aimed:) {
    Error(Nil), _ | _, [] -> #(cast, [])
    Ok(live), units -> {
      let given =
        units
        |> list.map(fn(unit_id) {
          #(
            unit_id,
            cast_tick.node_of(
              spell: live.spell,
              held: dict.get(live.nodes, unit_id) |> option.from_result,
              aimed:,
              unit_id:,
              started_ms: live.started_ms,
              now_ms:,
            )
              |> result.map(struck_by(node: _, struck:)),
          )
        })
      let #(cast, pushed) =
        list.fold(given, #(cast, []), fn(so_far, entry) {
          case entry.1 {
            Ok(node) -> pushed_by(so_far:, cast_id:, live:, node:, now_ms:)
            Error(Nil) -> so_far
          }
        })
      let nodes = case dict.get(cast.casts, cast_id) {
        Ok(current) -> current.nodes
        Error(Nil) -> live.nodes
      }
      let nodes =
        list.fold(given, nodes, fn(nodes, entry) {
          case entry.1 {
            Ok(node) -> dict.insert(nodes, entry.0, node)
            Error(Nil) -> dict.delete(nodes, entry.0)
          }
        })
      #(cast_tick.with_nodes(cast:, cast_id:, nodes:), pushed)
    }
  }
}

/// The node with the round that struck its unit as a creature, when the go's round struck
/// it as one; a node the round did not hit as a creature keeps the stamp it has.
fn struck_by(
  node node: lasting.Node,
  struck struck: List(Struck),
) -> lasting.Node {
  case cast_gate.creature_hit(struck:, unit_id: node.unit_id) {
    Ok(#(life, struck_at_ms)) ->
      lasting.Node(
        ..node,
        struck: Some(lasting.StruckCreature(life:, struck_at_ms:)),
      )
    Error(Nil) -> node
  }
}

/// A node the go gives a unit its cast holds none on yet makes a new cast on that
/// unit, which pushes the caster's oldest casts of its stack off the unit at the cap
/// (Jim's decision, `lasting.pushed_off`); a unit the cast holds a node on already is a
/// later go of the same cast, which pushes nothing. A pushed cast whose node holds
/// crowd-control states on a creature takes them with it
/// (`cast_control.creature_controls_ended`).
fn pushed_by(
  so_far so_far: #(State, List(Effect)),
  cast_id cast_id: Int,
  live live: Live,
  node node: lasting.Node,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: dict.has_key(live.nodes, node.unit_id),
    return: so_far,
  )
  let #(cast, effects) = so_far
  let #(holds, kept) =
    cast_control.others_on(cast:, cast_id:, unit_id: node.unit_id)
  let removals =
    lasting.pushed_off(
      holds:,
      kept:,
      spell4_id: live.spell.spell4_id,
      stack: live.spell.stack,
      unit_id: node.unit_id,
    )
  let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
  #(
    cast,
    list.flatten([
      effects,
      more,
      cast_control.creature_controls_ended(holds:, removals:),
    ]),
  )
}

/// What a removal does to the casts, in order: a cast that loses its whole node on a
/// unit is written 0x811 and keeps no node there, one that loses a stack is written
/// 0x813 and keeps its node one count lower. A lingering cast left with no node is
/// dropped, and, when its cast method is one the client keeps with no target
/// (Channeled, ChanneledField, Multiphase or 10), ends with its 0x7fe after the 0x811
/// (`opcode.0x811`).
pub fn apply_removals(
  cast cast: State,
  removals removals: List(lasting.Removal),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(removals, #(cast, []), fn(so_far, removal) {
    let #(cast, effects) = so_far
    let #(cast, more) = case removal {
      lasting.NodeOff(cast_id:, unit_id:) ->
        node_off(cast:, cast_id:, unit_id:, now_ms:)
      lasting.StackOff(cast_id:, unit_id:) ->
        cast_tick.stack_off(cast:, cast_id:, unit_id:)
    }
    #(cast, list.append(effects, more))
  })
}

/// A cast loses its whole node on a unit: 0x811 for the unit, with the cast destroyed on
/// the client when it has no node left and its method is not one the client keeps; a
/// lingering cast with none left is dropped, with its 0x7fe after the 0x811 when the
/// client keeps a cast of its method.
fn node_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(cast, ticks) = cast_tick.ticks_dropped(cast:, cast_id:, unit_id:)
      let nodes = dict.delete(holder.nodes, unit_id)
      let emptied = dict.is_empty(nodes)
      let kept = cast_tick.keeps_without_target(method: holder.spell.method)
      let removed =
        cast_tick.targets_removed_effects(
          cast_id:,
          unit_ids: [unit_id],
          audience: holder.audience,
          destroyed: emptied && !kept,
        )
      let #(cast, modifiers) =
        caster_modifiers_ended(cast:, cast_id:, spell: holder.spell, unit_ids: [
          unit_id,
        ])
      let #(cast, on_units) =
        cast_control.units_ended(cast:, cast_id:, unit_ids: [unit_id])
      let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
      let ends = case holder.lingering && emptied && kept {
        True -> cast_tick.finished_effects(cast_id:, audience: holder.audience)
        False -> []
      }
      #(cast, list.flatten([ticks, removed, modifiers, on_units, left, ends]))
    }
  }
}

/// The cast without the standing spell's cast id `cast_id` when it has left both `casts` and
/// `lingering`, so that no later cast the caster mints the same id for is taken for a standing
/// spell's.
pub fn standing_cleared(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, standing: dict.delete(cast.standing, cast_id))
}

/// What the procs of the casts never see.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Casting",
      missing: "A heal is never a critical heal: the server rolls no critical for a heal, so a proc that waits for a critical heal never fires.",
    ),
  ]
}
