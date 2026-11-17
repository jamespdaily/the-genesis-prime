//// A player's casts, a feature of the game connection's rule
//// (genesis_prime/game/connection) as movement and chat are: the press of an
//// ability on the action bar, the answers the client expects, the cast bar and
//// cooldowns it keeps, the cast's go and finish, the child casts a Proxy effect
//// starts, the thresholds of a RapidTap or ChargeRelease ability, and the cast's
//// end when the client cancels it. The caster's connection owns its casts and
//// sends every message about them; it tells the connections that see its player
//// the same news, which they write for a cast they know.
////
//// ```
//// client                    connection (this rule)                         viewers' connections
//// 0x9a press ──────────────▶ decode; bag index ─▶ the ability's tree (genesis_prime/game/spell_plan)
////                            an open threshold of the ability ─▶ the stage its index names
////                            a refusal of the client's own checks ──▶ 0x7fc {client id, Spell4 id, result}
////                            the spell's cast conditions last (CasterCast 151, TargetCast 281)
////                            accepted: id k = mint(unit, n); the gcd starts
//// ◀── 0x7fd {client id, k, caster}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
//// ◀── 0x816 {ability, ability, 0, k}   a RapidTap or ChargeRelease ability's first press opens its threshold
//// ◀── 0x817 {ability, index}           the next tap's stage, or the next charge level (a timer)
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the spell's own cooldown starts at the go its method names
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// ◀── 0x814 {ability, bit}  the last tap or the release closes the threshold
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to all
////
//// each input in the world ─▶ `persisted`: a lasting cast whose persistence stopped holding
////                            ends ──▶ 0x7f9 {k, 282 or 283, caster, 0}, then 0x7fe {k}; Tell(each viewer, CastFinished)
////
//// each input ─────────────▶ `settled`: the stealth change ──▶ StealthChanged (0x8f5), then the procs held for the
////                            input's events (its own: Died, LeftCombat or a hit's; then EnteredStealth or LeftStealth) cast
////                            their spells ──▶ 0x7ff {k, root and parent the holder's spell}, no 0x7fd
////
//// 0x4db held 1 ────────────▶ the ability is held: the same press, with the id k minted and no 0x7fd
////                            its cast over and its cooldowns run ─▶ the same press again (StartTimer(repeat))
//// 0x4db held 0 ────────────▶ the ability is not held: the repeat timer cancelled; a charge fires its stage
//// ```
////
//// - **The go** is 0x7f4 with the cast id, the ignore-cooldown bit 0, the caster's
////   place as the destination, no target, no position and no missile, and the
////   phase (`opcode.0x7f4`): a go that names no target carries no damage, which
////   the next step adds. A Multiphase spell's phase is the phase's index and a
////   channel's the pulse's (`opcode.0x7f4.phase`). Each go is followed by the
////   spell's Proxies of that phase, and the finish, 0x7fe, comes after the last go,
////   at once for a spell that is not Multiphase. A channel ends at the later of its
////   finish timer and the close of its last go's strike round, so the client has
////   all of its gos before the 0x7fe (`cast.channel_sequence`).
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a caster
////   apply prerequisite or one its dataBits06 names starts only when each passes
////   against the caster at the go (`cast_gate.proxy_gates`). One behind a target apply
////   prerequisite as well starts a child on a unit only when that prerequisite passes
////   too, for each unit separately (`children`, `cast_tick.target_gate`): the target first and
////   the caster second (`Spell4Effects.prerequisiteIdTargetApply`), the struck unit as
////   the caster's picture shows it when the round closes (`went`'s `poses`; a unit it no
////   longer shows decides nothing and leaves a debug line), or the caster on its own
////   point for a Proxy aimed at it. The target gate takes no roll. A child's timer is
////   its own: the parent's finish
////   leaves the pending children, which start 100 ms after it (Crush), and only
////   the player leaving the world cancels them.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) with the 0x816 value for an open ChargeRelease threshold
////   (`opcode.0x801`). It clears the caster's current cast, whatever cast that is,
////   and the cast ends with its go timers cancelled and 0x7fe to the caster and the
////   audience, no strike; the base cast of a charge ends its threshold too, with
////   0x814 before its 0x7fe. A cast that is not live is a debug line. Any other
////   reason or bit is one the client never sends, and ends the connection.
//// - **The audience** of a cast is the caster's viewers when it starts; its go and
////   finish go to them. A viewer writes a 0x7ff only when its client shows the
////   caster, and a go, or a finish, only for a cast it wrote
////   (genesis_prime/game/connection). The threshold messages go to the caster only.

import genesis_prime/client_connection
import genesis_prime/game/activate
import genesis_prime/game/area
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/persist as cast_persist
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{
  type Aimed, type AimedPress, type Applied, type Caster, type Effect, type Fact,
  type HeldProc, type Holder, type Interaction, type Listed, type Live,
  type Message, type Reached, type Refusal, type Resolution, type Restricting,
  type Role, type State, type Struck, type TargetVerdict, type TickAsked,
  type UsedUnit, Accept, Activated, Activating, Activation, Aimed, AimedPress,
  AnswerSucceeded, Answered, AwaitingAnswer, Base, Cancelled, CannotTell,
  CastClears, CasterChangeEnds, CasterChangeStarts, ChargeLevel, Child,
  CooldownEnds, CooldownKept, CooldownModifierEnds, CooldownModifierStarts,
  Deflected, Finish, ForcedMoveStart, GateFails, Go, GoAsked, Healing, Held,
  HeldProc, Hit, Hold, HoldForCast, Holding, Immune, ItemsIssue, KeyHeld,
  Lingering, Listed, Live, Log, ModifierEnd, ModifierStart, NoClientCastId,
  NoInteraction, NoInteractionWaits, NoItemSpell, NodesEnd, NotBuilt, NotDecoded,
  NotSentByClient, Passive, Plain, PrerequisitesIssue, Pressed, PressedAt,
  ProcDue, Reached, Refuse, RepeatHeld, Resolution, ResourceMoved,
  RestrictionEnd, Send, Shortcut, ShortcutCast, SpellsIssue, Stage, StartChild,
  StartHeld, StartedMoving, Starts, State, StateEnd, StealthChanged, Strike,
  TargetModifierStart, Tell, Threshold, Tick, UnbuiltItemCharges,
  UnbuiltItemSpell, UnbuiltShortcut, UnbuiltSpell, UnknownAnswer, UnknownCancel,
  UnreadItemPrerequisite, UnreadLinkPrerequisite, UnreadPrerequisite,
  UnreadShortcutPick, UsedUnit, WindowEnd, WrongAnswerSpell,
} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/class_resource.{type Payment}
import genesis_prime/game/cooldown
import genesis_prime/game/item_use
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/proc
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/unit_properties
import genesis_prime/message/ability_hold
import genesis_prime/message/cancel_cast.{type CancelCast}
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_activate
import genesis_prime/message/cast_objective_ability
import genesis_prime/message/cast_result
import genesis_prime/message/client_activate_unit
import genesis_prime/message/client_side_interaction_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/interaction_result
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/item_use as item_use_message
import genesis_prime/step.{type Now, type TimerId, LogDebug, LogInfo, LogWarning}
import genesis_prime/table/id.{
  type Item2Id, type Spell4BaseId, type Spell4Id, Spell4EffectsId,
}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// The caster's 0x9a, 0x4DB or 0x801, decoded and decided: the new state and what
/// the connection must do, or the refusal that ends the connection. `now` is the
/// time of the input; the plans give each ability's tree.
pub fn take(
  cast cast: State,
  message message: Message,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  case message {
    Pressed -> pressed(cast:, body:, caster:, plans:, now:)
    KeyHeld -> key_held(cast:, body:, caster:, plans:, now:)
    Cancelled ->
      cancelled(cast:, body:, caster:, now:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
    Answered ->
      answered(cast:, body:, caster:, now_ms:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
  }
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

/// The caster's 0x97, the right-click of a unit, decoded and decided: the client's cast
/// of the unit's activate spell (`opcode.0x97`). `target_of` says what the unit the
/// message names is to the caster's connection (its picture), and `caster_radius` is the
/// hit radius of the caster's own body, which the range check takes beside the target's.
/// The spell is the creature's pick (genesis_prime/game/activate `pick`); a cast that
/// cannot start is refused with the result the client names, and one that can runs as any
/// cast does, for the activate cast time (`cast_press.activation_spell`), and its last go raises `Activated`.
pub fn activate(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  activation_pressed(
    cast:,
    body:,
    caster:,
    activations:,
    target_of:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

/// The caster's 0x943, the use of an item the client sends from StartItemUseCast
/// (`opcode.0x943`), decoded and decided: the client's cast of the item's spell at the unit
/// it names. `held_at` says which item the caster holds at a place, `check` is the client's
/// own checks of the item (genesis_prime/game/item_use `check`, given the target's
/// checklist index), `target_of` says what the unit the message names is to the caster's
/// connection, and `in_cast_group` whether the unit is in a TargetGroup (the spell's cast
/// group, which the client does not test). A use the client would not have sent ends the
/// connection; one it sends and refuses is refused with its result; one the server has no
/// plan for (the item's spell has no Activate effect) is refused as not built; the others
/// run as an activate cast does, and the go raises `Activated` for the unit.
pub fn use_item(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  held_at held_at: fn(ItemPlace) -> Option(Item2Id),
  check check: fn(
    Item2Id,
    ItemPlace,
    Option(Int),
    fn(Int) -> prerequisite.Verdict,
  ) -> Result(Spell4Id, item_use.Refusal),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  item_used(
    cast:,
    body:,
    caster:,
    held_at:,
    check:,
    activations:,
    target_of:,
    in_cast_group:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

fn item_used(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  held_at held_at: fn(ItemPlace) -> Option(Item2Id),
  check check: fn(
    Item2Id,
    ItemPlace,
    Option(Int),
    fn(Int) -> prerequisite.Verdict,
  ) -> Result(Spell4Id, item_use.Refusal),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    item_use_message.decode(body)
    |> client_connection.decoded(message_id: item_use_message.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let unit_id = press.target_unit_id
  let target = target_of(unit_id)
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case held_at(press.item) {
    None -> refusal(0, cast_result.ItemBad)
    Some(item) ->
      case
        check(
          item,
          press.second_item,
          // Another player's unit has no checklist index: the client's quest check reads
          // -1 for it (`0x140398cc0`).
          case target {
            activate.Usable(checklist_index:, ..) -> Some(checklist_index)
            activate.AnotherPlayer -> Some(-1)
            activate.Unseen -> None
          },
          activate.checker(
            activations:,
            subject: cast_tick.subject_of(cast:, caster:),
          ),
        )
      {
        Error(item_use.NoItemSpell) -> Error(NoItemSpell)
        Error(item_use.NotSentByClient) -> Error(NotSentByClient)
        Error(item_use.Declined(spell4_id:, result:)) ->
          refusal(spell4_id.value, result)
        Error(item_use.Charged(spell4_id:, max_charges:)) ->
          cast_press.not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: spell4_id.value,
            key: UnbuiltItemCharges(item_id: item.value),
            result: cast_result.IllegalSpellCast,
            why: "(Item2 "
              <> int.to_string(item.value)
              <> ") has maxCharges "
              <> int.to_string(max_charges)
              <> ", which the server does not hold: the client refuses an item with no charges left with 25",
            issue: ItemsIssue,
          )
        Error(item_use.UnreadPrerequisite(spell4_id:, prerequisite_type:)) ->
          cast_press.not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: spell4_id.value,
            key: UnreadItemPrerequisite(prerequisite_type:),
            result: cast_result.IllegalSpellCast,
            why: "is gated by a prerequisite of the type "
              <> int.to_string(prerequisite_type)
              <> ", which the server does not read",
            issue: PrerequisitesIssue,
          )
        Ok(spell4_id) ->
          item_spell_cast(
            cast:,
            caster:,
            caster_radius:,
            now_ms:,
            client_cast_id:,
            unit_id:,
            target:,
            activations:,
            in_cast_group:,
            spell4_id: spell4_id.value,
          )
      }
  }
}

/// The cast of an item's spell, which the item's checks let through, at the unit the
/// press names (`item_used`): refused as not built when the spell has no Activate effect,
/// refused 91 for a unit not shown and 100 for another player. At a creature the target's
/// life and states come first (`cast_press.target_state_refusal`), then 89 for a unit the spell's cast
/// group refuses (`activate.passes_cast_group`), else the activate cast of the unit, which
/// refuses by range (`0x1403b2240` tests in that order).
fn item_spell_cast(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  target target: activate.Target,
  activations activations: activate.Activations,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  spell4_id spell4_id: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case activate.planned_of(activations:, spell4_id:) {
    Error(Nil) ->
      cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltItemSpell(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "has no Activate effect, which is all the server counts an item's use through",
        issue: ItemsIssue,
      )
    Ok(activate.NoSpell4Row) -> refusal(spell4_id, cast_result.SpellUnknown)
    Ok(activate.CannotBePlanned(why:)) ->
      cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltItemSpell(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "cannot be planned: " <> why,
        issue: SpellsIssue,
      )
    Ok(activate.Planned(spell:, effects:, dropped:, limits:, cast_group_id:)) ->
      // A creature's `withheld` and `ClosedLink` are what the client's interact menu does
      // not offer; an item's use never goes through that menu, and a closed link only
      // gates the objectives `by_item` leaves uncounted.
      case target {
        activate.Unseen -> refusal(spell4_id, cast_result.NoTarget)
        activate.AnotherPlayer ->
          refusal(spell4_id, cast_result.TargetIsNotUseable)
        activate.Usable(
          creature_id:,
          creature:,
          checklist_index:,
          body: unit,
          alive:,
          held:,
          ..,
        ) ->
          case cast_press.target_state_refusal(spell:, alive:, held:) {
            Some(result) -> refusal(spell4_id, result)
            None ->
              case
                item_cast_group(
                  cast:,
                  caster:,
                  client_cast_id:,
                  unit_id:,
                  spell4_id:,
                  cast_group_id:,
                  creature:,
                  checklist_index:,
                  activations:,
                  in_cast_group:,
                )
              {
                Error(taken) -> taken
                Ok(Nil) ->
                  activation_reached(
                    cast:,
                    caster:,
                    caster_radius:,
                    now_ms:,
                    client_cast_id:,
                    unit_id:,
                    creature_id:,
                    creature:,
                    target: unit,
                    alive:,
                    by_item: True,
                    spell:,
                    cast_time_ms: spell.cast_time_ms,
                    effects:,
                    dropped:,
                    limits:,
                  )
              }
          }
      }
  }
}

/// The client's cast-group check of an item's spell at a creature (`activate.passes_cast_group`):
/// `Ok` when the cast goes on, else the answer to the press.
fn item_cast_group(
  cast cast: State,
  caster caster: Caster,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  activations activations: activate.Activations,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> Result(Nil, Result(#(State, List(Effect)), Refusal)) {
  case
    cast_group_of(
      cast:,
      caster:,
      activations:,
      unit_id:,
      spell4_id:,
      cast_group_id:,
      creature:,
      checklist_index:,
      in_cast_group:,
    )
  {
    activate.InCastGroup -> Ok(Nil)
    activate.OutsideCastGroup ->
      Error(
        Ok(
          #(cast, [
            cast_frame.refused(
              client_cast_id:,
              spell4_id:,
              result: cast_result.TargetGroup,
            ),
          ]),
        ),
      )
    activate.CastGroupUnread(prerequisite_type:) ->
      Error(cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnreadPrerequisite(prerequisite_type:),
        result: cast_result.IllegalSpellCast,
        why: "of a creature activates through a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
        issue: PrerequisitesIssue,
      ))
  }
}

/// The caster's 0x9d, the press of the button a type 11 objective gave it (`opcode.0x9d`),
/// decoded and decided. A spell the caster holds no button for is refused with result 1
/// (`UnableToCreateSpell`), as the client refuses a press of a shortcut it does not hold
/// (`0x14039b340`); one of the self-aimed spells the objectives name casts on the caster
/// as any cast does, and its first go raises `ShortcutCast`. A spell that takes a unit
/// (targetType 1, 3, 5 or 8) is checked against the unit the press names in the order the
/// client checks it (`aimed_shortcut`) and starts on that unit; its first go raises
/// `ShortcutCast` with the unit. `target_of` says what a unit the press names is,
/// `in_cast_group` whether a unit is in a TargetGroup, and `activations` hold the
/// creatures' activate picks, which a cast group reads.
pub fn shortcut(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  held held: Set(Int),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  shortcut_pressed(
    cast:,
    body:,
    caster:,
    shortcuts:,
    held:,
    activations:,
    target_of:,
    in_cast_group:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

fn shortcut_pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  held held: Set(Int),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_objective_ability.decode(body)
    |> client_connection.decoded(message_id: cast_objective_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let spell4_id = press.spell4_id
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  use <- bool.guard(
    when: !set.contains(held, spell4_id),
    return: refusal(cast_result.UnableToCreateSpell),
  )
  case shortcut_spell.planned_of(shortcuts:, spell4_id:) {
    Error(Nil) | Ok(shortcut_spell.NoSpell4Row) ->
      refusal(cast_result.SpellUnknown)
    Ok(shortcut_spell.CannotBePlanned(why:)) ->
      cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltShortcut(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "cannot be planned: " <> why,
        issue: SpellsIssue,
      )
    Ok(shortcut_spell.Planned(spell:)) ->
      accepted_and_started(
        cast:,
        caster:,
        now_ms:,
        client_cast_id:,
        spell: cast_press.shortcut_spell_of(spell:),
        primary_target: caster.unit_id,
        role: Shortcut(
          interaction: cast_press.interaction_of(spell:),
          aimed: None,
        ),
        target_subject: None,
        dropping: fn(cast) { #(cast, []) },
      )
    Ok(shortcut_spell.Aimed(spell:, aim:)) ->
      aimed_shortcut(
        cast:,
        caster:,
        caster_radius:,
        now_ms:,
        client_cast_id:,
        unit_id: press.target_unit_id,
        spell:,
        aim:,
        activations:,
        target_of:,
        in_cast_group:,
      )
  }
}

/// A press of a quest button's spell that takes a unit, at the unit the press names,
/// refused in the order the client's checks give (`0x1403ae8c0`, `0x1403b2240`,
/// `0x1403b44b0`): 91 for no unit or one the picture does not show; 32 for the caster
/// itself; 106 or 107 and 108 for the unit's life and combat; 102 for a player the spell
/// refuses (answered first for a player, whose life and combat are not held); 89 for a
/// unit outside the spell's cast group; the result of the first crowd-control state the
/// unit holds that the spell's target row masks (122 for Stun, and so on); the range's
/// 104, 105 or 183, measured with the spell's own limits; then the spell's CasterCast and TargetCast (151, 281), read as
/// any cast's with the unit as the TargetCast's first unit. Then started on
/// the unit. A player or the caster itself reaches the client's player faction test, which
/// the server does not build, and another player's life and combat are not held: those
/// are refused 285 as not built. The target states the server does not hold (96
/// invulnerable, 140 zone, 98 vital, 92 immunity) are not checked: a gap in the issue
/// "Spells work in depth on the real client: cast times, telegraphs, buffs, crowd control
/// and ticking effects".
fn aimed_shortcut(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  spell spell: Spell,
  aim aim: shortcut_spell.Aim,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  let press =
    AimedPress(
      cast:,
      caster:,
      caster_radius:,
      now_ms:,
      client_cast_id:,
      unit_id:,
      spell:,
      aim:,
      activations:,
      in_cast_group:,
      held: [],
      unit_states: [],
    )
  case unit_id == caster.unit_id, target_of(unit_id) {
    True, _ -> cast_press.aimed_at_the_caster(press:)
    False, activate.Unseen ->
      cast_press.press_refused(press:, result: cast_result.NoTarget)
    False, activate.AnotherPlayer -> cast_press.aimed_at_a_player(press:)
    False,
      activate.Usable(
        creature_id:,
        creature:,
        checklist_index:,
        body:,
        alive:,
        in_combat:,
        held:,
        unit_states:,
        ..,
      )
    ->
      aimed_at_a_creature(
        press: AimedPress(..press, held:, unit_states:),
        creature_id:,
        creature:,
        checklist_index:,
        target_body: body,
        alive:,
        in_combat:,
      )
  }
}

/// A creature or object: the unit states it is shown to hold, then life, then combat, then
/// the crowd-control states it holds, then cast group and range, then the spell's own
/// conditions and the start. The unit-state test comes first where the client's own
/// invulnerability result does (`0x1403b2240` line 44, result 96, before every other target
/// check); that 306 and 308 stand in the same place is a server guess.
fn aimed_at_a_creature(
  press press: AimedPress,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  use <- cast_press.unit_state_refusal(press:)
  case cast_press.life_and_combat_refusal(press:, alive:, in_combat:) {
    Some(result) -> cast_press.press_refused(press:, result:)
    None -> {
      use <- cast_press.target_held(press:)
      aimed_in_group(
        press:,
        creature_id:,
        creature:,
        checklist_index:,
        target_body:,
        alive:,
        in_combat:,
      )
    }
  }
}

fn aimed_in_group(
  press press: AimedPress,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  case
    cast_group_of(
      cast: press.cast,
      caster: press.caster,
      activations: press.activations,
      unit_id: press.unit_id,
      spell4_id: press.spell.spell4_id.value,
      cast_group_id: press.aim.cast_group_id,
      creature:,
      checklist_index:,
      in_cast_group: press.in_cast_group,
    )
  {
    activate.InCastGroup ->
      aimed_in_range(press:, creature_id:, target_body:, alive:, in_combat:)
    activate.OutsideCastGroup ->
      cast_press.press_refused(press:, result: cast_result.TargetGroup)
    activate.CastGroupUnread(prerequisite_type:) ->
      cast_press.press_unbuilt(
        press:,
        key: UnreadShortcutPick(prerequisite_type:),
        why: "names a creature whose activate pick rests on a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
      )
  }
}

/// The client's cast-group check of a cast of `spell4_id` at the creature `unit_id`: the
/// creature's activate pick for the caster, read as `activate.passes_cast_group` needs it.
fn cast_group_of(
  cast cast: State,
  caster caster: Caster,
  activations activations: activate.Activations,
  unit_id unit_id: Int,
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> activate.CastGroup {
  activate.passes_cast_group(
    spell4_id:,
    cast_group_id:,
    creature:,
    picked: activate.pick(
      creature:,
      default_spell: activations.default_spell,
      check: activate.checker(
        activations:,
        subject: cast_press.subject_for_use(
          cast:,
          caster:,
          unit_id:,
          checklist_index:,
        ),
      ),
    ),
    in_cast_group: in_cast_group(_, unit_id),
  )
}

fn aimed_in_range(
  press press: AimedPress,
  creature_id creature_id: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  case
    activate.range_of(
      limits: press.aim.limits,
      caster: activate.Body(
        place: press.caster.place,
        radius: press.caster_radius,
      ),
      target: target_body,
    )
  {
    activate.TooClose ->
      cast_press.press_refused(press:, result: cast_result.TargetRangeMin)
    activate.TooFar ->
      cast_press.press_refused(press:, result: cast_result.TargetRangeMax)
    activate.TooHigh ->
      cast_press.press_refused(press:, result: cast_result.TargetRangeVertical)
    activate.Within ->
      accepted_and_started(
        cast: press.cast,
        caster: press.caster,
        now_ms: press.now_ms,
        client_cast_id: press.client_cast_id,
        spell: cast_press.shortcut_spell_of(spell: press.spell),
        primary_target: press.unit_id,
        role: Shortcut(
          interaction: cast_press.interaction_of(spell: press.spell),
          aimed: Some(PressedAt(unit_id: press.unit_id, alive_at_press: alive)),
        ),
        target_subject: Some(cast_tick.target_subject_of(
          cast: press.cast,
          caster: press.caster,
          unit_id: press.unit_id,
          creature_id:,
          in_combat:,
          place: target_body.place,
        )),
        dropping: fn(cast) { #(cast, []) },
      )
  }
}

/// The caster's 0xb3, the client's use of a unit whose creature has no activate spell
/// (`opcode.0xb3`, `0x14039d4a0`): no cast and no delay, so the use is `Activated` at
/// once. `unit_of` says what the unit the message names is, or `Error(Nil)` for a unit
/// that is no creature or object the caster's client shows. The client sends 0xb3 only
/// from its click of an offered interaction within reach (`0x14039d2c0`, range
/// `activate.use_limits`) and only when the creature's pick is spell 0 (`0x14039d510`),
/// so a dead creature, a unit out of reach, one the server does not offer, one whose pick is
/// a spell and one the server cannot pick for are logged and change nothing.
pub fn activate_unit(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  unit_of unit_of: fn(Int) -> Result(UsedUnit, Nil),
  caster_radius caster_radius: Float,
) -> Result(List(Effect), Refusal) {
  use used <- result.map(
    client_activate_unit.decode(body)
    |> client_connection.decoded(message_id: client_activate_unit.message_id)
    |> result.map_error(NotDecoded),
  )
  let unit_id = used.unit_id
  let declined = fn(why) {
    [
      Log(
        level: LogWarning,
        text: "the use of unit "
          <> int.to_string(unit_id)
          <> " (0xb3) "
          <> why
          <> ": it counts for nothing",
      ),
    ]
  }
  case unit_of(unit_id) {
    Error(Nil) -> declined("names no creature or object the client shows")
    Ok(UsedUnit(alive: False, ..)) ->
      declined("names a creature that is dead: its interaction is not offered")
    Ok(UsedUnit(link: activate.ClosedLink, ..)) ->
      declined(
        "names a creature whose link to an objective is closed: the client offers it nothing",
      )
    Ok(UsedUnit(link: activate.UnreadLink(prerequisite_type:), ..)) ->
      declined(
        "names a creature whose link to an objective rests on a prerequisite of the type "
        <> int.to_string(prerequisite_type)
        <> ", which the server does not read",
      )
    Ok(UsedUnit(
      creature_id:,
      creature:,
      checklist_index:,
      body: unit,
      offered:,
      link: activate.NoLink,
      ..,
    ))
    | Ok(UsedUnit(
        creature_id:,
        creature:,
        checklist_index:,
        body: unit,
        offered:,
        link: activate.OpenLink,
        ..,
      )) ->
      case
        activate.range_of(
          limits: activate.use_limits,
          caster: activate.Body(place: caster.place, radius: caster_radius),
          target: unit,
        ),
        offered
      {
        activate.Within, True -> {
          let subject =
            cast_press.subject_for_use(
              cast:,
              caster:,
              unit_id:,
              checklist_index:,
            )
          case
            activate.pick(
              creature:,
              default_spell: activations.default_spell,
              check: activate.checker(activations:, subject:),
            )
          {
            activate.NoActivateSpell -> [
              Activated(
                unit_id:,
                creature_id:,
                alive_at_press: True,
                by_item: False,
              ),
            ]
            activate.Picked(spell4_id:) ->
              declined(
                "names a creature whose activate spell is "
                <> int.to_string(spell4_id)
                <> ", which the client casts with 0x97",
              )
            activate.Unread(prerequisite_type:) ->
              declined(
                "names a creature that activates through a prerequisite of the type "
                <> int.to_string(prerequisite_type)
                <> ", which the server does not read",
              )
          }
        }
        activate.Within, False ->
          declined(
            "names a unit that is not offered: no open objective counts a use of it, or its bit is set",
          )
        activate.TooClose, _ | activate.TooFar, _ | activate.TooHigh, _ ->
          declined("names a unit out of the interaction range")
      }
  }
}

fn activation_pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_activate.decode(body)
    |> client_connection.decoded(message_id: cast_activate.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case target_of(press.target_unit_id) {
    activate.Unseen -> refusal(0, cast_result.CasterMustHaveTarget)
    activate.AnotherPlayer -> refusal(0, cast_result.NoTarget)
    activate.Usable(withheld: Some(withheld), ..) ->
      Ok(
        #(cast, [
          Log(
            level: LogWarning,
            text: "the activate cast of unit "
              <> int.to_string(press.target_unit_id)
              <> case withheld {
              activate.HostileToPlayer -> " names a unit hostile to the player"
              activate.InCombat -> " names a unit in combat"
            }
              <> ": the client offers it nothing, so it is refused with "
              <> int.to_string(cast_result.to_value(
              cast_result.TargetIsNotUseable,
            )),
          ),
          cast_frame.refused(
            client_cast_id:,
            spell4_id: 0,
            result: cast_result.TargetIsNotUseable,
          ),
        ]),
      )
    activate.Usable(link: activate.ClosedLink, ..) ->
      Ok(
        #(cast, [
          Log(
            level: LogWarning,
            text: "the activate cast of unit "
              <> int.to_string(press.target_unit_id)
              <> " names a creature whose link to an objective is closed: the client offers it nothing, so it is refused with "
              <> int.to_string(cast_result.to_value(
              cast_result.TargetIsNotUseable,
            )),
          ),
          cast_frame.refused(
            client_cast_id:,
            spell4_id: 0,
            result: cast_result.TargetIsNotUseable,
          ),
        ]),
      )
    activate.Usable(link: activate.UnreadLink(prerequisite_type:), ..) ->
      cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id: 0,
        key: UnreadLinkPrerequisite(prerequisite_type:),
        result: cast_result.IllegalSpellCast,
        why: "of a creature whose link to an objective rests on a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
        issue: PrerequisitesIssue,
      )
    activate.Usable(
      creature_id:,
      creature:,
      checklist_index:,
      link: activate.NoLink,
      body: target,
      alive:,
      in_combat: _,
      held:,
      unit_states: _,
      withheld: None,
    )
    | activate.Usable(
        creature_id:,
        creature:,
        checklist_index:,
        link: activate.OpenLink,
        body: target,
        alive:,
        in_combat: _,
        held:,
        unit_states: _,
        withheld: None,
      ) -> {
      let subject =
        cast_press.subject_for_use(
          cast:,
          caster:,
          unit_id: press.target_unit_id,
          checklist_index:,
        )
      let picked =
        activate.pick(
          creature:,
          default_spell: activations.default_spell,
          check: activate.checker(activations:, subject:),
        )
      case picked {
        activate.NoActivateSpell -> refusal(0, cast_result.TargetIsNotUseable)
        activate.Unread(prerequisite_type:) ->
          cast_press.not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: 0,
            key: UnreadPrerequisite(prerequisite_type:),
            result: cast_result.IllegalSpellCast,
            why: "of a creature activates through a prerequisite of the type "
              <> int.to_string(prerequisite_type)
              <> ", which the server does not read",
            issue: PrerequisitesIssue,
          )
        activate.Picked(spell4_id:) ->
          case activate.planned_of(activations:, spell4_id:) {
            Error(Nil) | Ok(activate.NoSpell4Row) ->
              refusal(spell4_id, cast_result.SpellUnknown)
            Ok(activate.CannotBePlanned(why:)) ->
              cast_press.not_built_refusal(
                cast:,
                client_cast_id:,
                spell4_id:,
                key: UnbuiltSpell(spell4_id:),
                result: cast_result.IllegalSpellCast,
                why: "cannot be planned: " <> why,
                issue: SpellsIssue,
              )
            Ok(activate.Planned(spell:, effects:, dropped:, limits:, ..)) ->
              activation_in_range(
                cast:,
                caster:,
                caster_radius:,
                now_ms:,
                client_cast_id:,
                unit_id: press.target_unit_id,
                creature_id:,
                creature:,
                target:,
                alive:,
                held:,
                by_item: False,
                spell:,
                cast_time_ms: activate.cast_time_for(
                  creature:,
                  spell4_id: spell.spell4_id.value,
                ),
                effects:,
                dropped:,
                limits:,
              )
          }
      }
    }
  }
}

/// An activate cast of a planned spell at a creature or object, for the cast time given:
/// refused by the target's life and states (`cast_press.target_state_refusal`), then with the range's
/// result when the caster stands out of the limits the creature and the spell hold, else
/// started (`0x1403b2240` tests the life and the states before the range).
fn activation_in_range(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  target target: activate.Body,
  alive alive: Bool,
  held held: List(CrowdControlState),
  by_item by_item: Bool,
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
  effects effects: List(activate.ActivateEffect),
  dropped dropped: activate.Dropped,
  limits limits: activate.Limits,
) -> Result(#(State, List(Effect)), Refusal) {
  case cast_press.target_state_refusal(spell:, alive:, held:) {
    Some(result) ->
      Ok(
        #(cast, [
          cast_frame.refused(
            client_cast_id:,
            spell4_id: spell.spell4_id.value,
            result:,
          ),
        ]),
      )
    None ->
      activation_reached(
        cast:,
        caster:,
        caster_radius:,
        now_ms:,
        client_cast_id:,
        unit_id:,
        creature_id:,
        creature:,
        target:,
        alive:,
        by_item:,
        spell:,
        cast_time_ms:,
        effects:,
        dropped:,
        limits:,
      )
  }
}

/// An activate cast whose target's life and states, and cast group, let it through: refused
/// with the range's result when the caster stands out of the limits the creature and the
/// spell hold, else started.
fn activation_reached(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  target target: activate.Body,
  alive alive: Bool,
  by_item by_item: Bool,
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
  effects effects: List(activate.ActivateEffect),
  dropped dropped: activate.Dropped,
  limits limits: activate.Limits,
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case
    activate.range_of(
      limits: activate.limits_for(creature:, spell4_id:, spell: limits),
      caster: activate.Body(place: caster.place, radius: caster_radius),
      target:,
    )
  {
    activate.TooClose -> refusal(cast_result.TargetRangeMin)
    activate.TooFar -> refusal(cast_result.TargetRangeMax)
    activate.TooHigh -> refusal(cast_result.TargetRangeVertical)
    activate.Within ->
      activation_started(
        cast:,
        caster:,
        now_ms:,
        client_cast_id:,
        unit_id:,
        creature_id:,
        alive_at_press: alive,
        by_item:,
        spell: cast_press.activation_spell(spell:, cast_time_ms:),
        interaction: cast_press.interaction_of(spell:),
        effects:,
        dropped:,
      )
  }
}

/// The activate cast of `unit_id` under the same checks as a press of its spell, then
/// started: the verdict's holds are refusals here, since the client does not send the
/// cast again.
fn activation_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  alive_at_press alive_at_press: Bool,
  by_item by_item: Bool,
  spell spell: Spell,
  interaction interaction: Interaction,
  effects effects: List(activate.ActivateEffect),
  dropped dropped: activate.Dropped,
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  accepted_and_started(
    cast:,
    caster:,
    now_ms:,
    client_cast_id:,
    spell:,
    primary_target: unit_id,
    role: Activation(
      activating: Activating(
        unit_id:,
        creature_id:,
        alive_at_press:,
        by_item:,
        effects:,
      ),
      interaction:,
    ),
    target_subject: None,
    dropping: fn(cast) {
      cast_press.rows_dropped(
        cast:,
        spell4_id:,
        unit_id:,
        creature_id:,
        dropped:,
      )
    },
  )
}

/// A cast the client sent a cast id for (an activate or a shortcut cast), under the same
/// checks as a press of its spell, then started in `role`: the verdict's holds are
/// refusals, since the client does not send the cast again. `dropping` is what the start
/// leaves to log, after the payments and before the start's own effects.
fn accepted_and_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  spell spell: Spell,
  primary_target primary_target: Int,
  role role: Role,
  target_subject target_subject: Option(prerequisite.Subject),
  dropping dropping: fn(State) -> #(State, List(Effect)),
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  use <- bool.guard(
    when: cast_press.answer_is_out(cast:),
    return: refusal(cast_result.SpellAlreadyCasting),
  )
  case
    cast_press.verdict(
      cast:,
      caster:,
      spell:,
      now_ms:,
      is_release: False,
      target_subject:,
    )
  {
    Refuse(result:) -> refusal(result)
    Hold(..) -> refusal(cast_result.SpellGlobalCooldown)
    HoldForCast -> refusal(cast_result.SpellAlreadyCasting)
    NotBuilt(result:, why:, issue:) ->
      cast_press.not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: case role {
          Shortcut(..) -> UnbuiltShortcut(spell4_id:)
          Child | Base(..) | Stage(..) | Passive | Activation(..) ->
            UnbuiltSpell(spell4_id:)
        },
        result:,
        why:,
        issue:,
      )
    Accept(paid:) -> {
      let #(taken, reserved) = case cast_cost.pays_at_accept(spell:) {
        True -> #(cast_cost.paying(payments: paid.payments), [])
        False -> #([], paid.payments)
      }
      let #(cast, started) =
        start(
          cast:,
          caster:,
          now_ms:,
          spell:,
          root: spell.spell4_id,
          parent: None,
          primary_target:,
          client_cast_id: Some(client_cast_id),
          role:,
          spent: paid.spent,
          reserved:,
        )
      let #(cast, dropped) = dropping(cast)
      Ok(#(cast, list.flatten([taken, dropped, started])))
    }
  }
}

/// What an input did, with `StealthChanged` after its own effects when the caster's stealth
/// is not what it was in `cast`, the state before the input: one per input, however many
/// Stealth rows came and went. The input's events are recorded as pending, to be matched
/// against the held procs once the connection has drawn what they need
/// (`cast_proc.proc_draws_needed`, `procs_fire`), in this order: `own` are the input's own events,
/// then a heal and a receipt for each `Heal` change the input's effects start on the
/// caster, then the events the input raised as it ran (`UsesAbility` in `start`), then a
/// `SpendsResource` for each payment among its effects, then the stealth change. `step` is
/// the input's own work.
fn settled(
  cast cast: State,
  own own: List(proc.Event),
  step step: fn() -> #(State, List(Effect)),
) -> #(State, List(Effect)) {
  let #(after, effects) = step()
  let #(stealth, moved) = case
    cast_state.stealthed(cast: after) == cast_state.stealthed(cast:)
  {
    True -> #([], [])
    False -> {
      let stealthed = cast_state.stealthed(cast: after)
      let change = case stealthed {
        True -> spell_plan.EnteredStealth
        False -> spell_plan.LeftStealth
      }
      #([proc.Event(trigger: change, other_unit: None, spell: None)], [
        StealthChanged(stealthed:),
      ])
    }
  }
  let before_count = list.length(cast.pending)
  let events =
    list.flatten([
      own,
      cast_proc.heals_landed(before: cast, after:, effects:),
      list.drop(after.pending, before_count),
      cast_proc.resources_spent(effects:),
      stealth,
    ])
  #(
    State(
      ..after,
      pending: list.append(list.take(after.pending, before_count), events),
    ),
    list.append(effects, moved),
  )
}

/// The state with the events the facts raise appended to the pending ones, in the facts'
/// order. A resource that changed at all raises `ResourceCrosses`, and a fall of the
/// Stalker's suit power also `SuitPowerDrops`; the proc's own holder gate then decides
/// whether the value is the one it waits for, on the holder as it is after the change
/// (`procs_fire`). Two readings are guesses: the change of any slot is an event of kind 87,
/// and the gate is not asked whether the value was on the other side before, so a change
/// that stays inside or goes on past the gated range raises the event too (no client code
/// reads a Proc row, `Spell4Effects.effectType.14.dataBits00`).
pub fn raised(cast cast: State, facts facts: List(Fact)) -> State {
  let events =
    list.flat_map(facts, fn(fact) {
      case fact {
        StartedMoving -> [
          proc.Event(
            trigger: spell_plan.StartsMoving,
            other_unit: None,
            spell: None,
          ),
        ]
        ResourceMoved(slot:, from:, to:) if from != to ->
          list.flatten([
            [
              proc.Event(
                trigger: spell_plan.ResourceCrosses,
                other_unit: None,
                spell: None,
              ),
            ],
            case slot == cast_state.suit_power_slot && to <. from {
              True -> [
                proc.Event(
                  trigger: spell_plan.SuitPowerDrops,
                  other_unit: None,
                  spell: None,
                ),
              ]
              False -> []
            },
          ])
        ResourceMoved(..) -> []
      }
    })
  State(..cast, pending: list.append(cast.pending, events))
}

/// The held procs fire for the pending events, in the order they happened; within an event,
/// in source order, the cast id and then the effect id, which is row order for one holder. The
/// events are cleared. A proc whose node the input took off is not held, and one the input
/// applied is. `draws` are the 32-bit words and `rolls` the gate rolls drawn for
/// `cast_proc.proc_draws_needed`, taken in the order the procs are matched; `poses`, `indexes` and
/// `units` are those of `cast_proc.pending_units` as `went` takes them, which an event gate against the
/// event's unit reads. A fire's own go is an input of its own, so it raises its own events then
/// and no event raised here is matched in this pass.
pub fn procs_fire(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  draws draws: List(Int),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  let events = cast.pending
  let cast = State(..cast, pending: [])
  let ordered =
    dict.to_list(cast.procs)
    |> list.sort(fn(first, second) {
      int.compare({ first.0 }.cast_id, { second.0 }.cast_id)
      |> order.break_tie(int.compare(
        { first.0 }.effect_id.value,
        { second.0 }.effect_id.value,
      ))
    })
  let #(cast, effects, _, _) =
    list.fold(events, #(cast, [], draws, rolls), fn(so_far, event) {
      let #(cast, effects, draws, rolls) = so_far
      list.filter(ordered, fn(entry) {
        { entry.1 }.row.trigger == event.trigger
      })
      |> list.fold(#(cast, effects, draws, rolls), fn(so_far, entry) {
        let #(cast, effects, draws, rolls) = so_far
        let source = entry.0
        let row = { entry.1 }.row
        let #(words, roll_count) = proc.draws_needed(row:)
        let #(taken, draws) = list.split(draws, words)
        let #(own_rolls, rolls) = list.split(rolls, roll_count)
        let #(cast, more) = case dict.get(cast.procs, source) {
          Error(Nil) -> #(cast, [])
          Ok(held) ->
            proc_matched(
              cast:,
              caster:,
              now_ms: now.monotonic_ms,
              event:,
              source:,
              held:,
              draw: option.from_result(list.first(taken)),
              rolls: own_rolls,
              poses:,
              indexes:,
              units:,
            )
        }
        #(cast, list.append(effects, more), draws, rolls)
      })
    })
  #(cast, effects)
}

/// One held proc against one event of its trigger: what `proc.decide` gives, carried out. The
/// holder's subject is the caster as `cast_tick.subject_of` has it, and the event's the struck unit as
/// a Proxy's target gate reads it (`cast_tick.struck_subject`), or the caster again for an event with
/// no other unit.
fn proc_matched(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  event event: proc.Event,
  source source: unit_properties.Source,
  held held: HeldProc,
  draw draw: Option(Int),
  rolls rolls: List(Int),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> #(State, List(Effect)) {
  let row = held.row
  case cast_state.holder_of(cast:, cast_id: source.cast_id) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " is held by the cast "
          <> int.to_string(source.cast_id)
          <> ", which is neither live nor lingering, so it does not fire",
      ),
    ])
    Ok(holder) -> {
      let holder_subject = cast_tick.subject_of(cast:, caster:)
      let event_subject = case event.other_unit {
        Some(unit) ->
          cast_tick.struck_subject(
            cast:,
            caster:,
            primary_target: unit,
            poses:,
            indexes:,
            units:,
          )
        None -> holder_subject
      }
      case
        proc.decide(
          row:,
          fires_ms: held.fires_ms,
          now_ms:,
          event:,
          holder_unit: caster.unit_id,
          holder_subject:,
          event_subject:,
          draw:,
          rolls:,
        )
      {
        proc.Fires(at:, delay_ms:) ->
          proc_fires(
            cast:,
            caster:,
            now_ms:,
            source:,
            held:,
            holder:,
            at:,
            delay_ms:,
          )
        proc.CannotTell(why:) -> #(cast, [Log(level: LogDebug, text: why)])
        proc.OutOfLimit
        | proc.FilteredOut
        | proc.HolderGateFails
        | proc.EventGateFails
        | proc.MissedChance -> #(cast, [])
      }
    }
  }
}

/// A proc that fires: refused for a caster of a life its spell's caster condition does not
/// allow (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`), which writes a debug line
/// and records no fire; else recorded as a fire at the event, and its spell cast at `at` at
/// once or, with a delay, when `ProcDue` runs out. The cast starts as a child of the holder's
/// spell does: the holder's spell is its root and parent, no 0x7fd.
fn proc_fires(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  held held: HeldProc,
  holder holder: Holder,
  at at: Int,
  delay_ms delay_ms: Int,
) -> #(State, List(Effect)) {
  let row = held.row
  case cast_proc.proc_refusal(caster:, row:, holder:) {
    Some(refusal) -> #(cast, [refusal])
    None -> {
      let cast =
        State(
          ..cast,
          procs: dict.insert(
            cast.procs,
            source,
            HeldProc(row:, fires_ms: [
              now_ms,
              ..proc.counted(limit: row.limit, fires_ms: held.fires_ms, now_ms:)
            ]),
          ),
        )
      case delay_ms {
        0 -> proc_started(cast:, caster:, now_ms:, row:, holder:, at:)
        _ -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: ProcDue(source:, row:, at:),
              after_ms: delay_ms,
            )
          #(cast, [start])
        }
      }
    }
  }
}

/// The cast of a proc's spell at the unit `at`, started as a child of the holder's spell.
fn proc_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  row row: spell_plan.ProcRow,
  holder holder: Holder,
  at at: Int,
) -> #(State, List(Effect)) {
  start(
    cast:,
    caster:,
    now_ms:,
    spell: row.spell,
    root: holder.spell.spell4_id,
    parent: Some(holder.spell.spell4_id),
    primary_target: at,
    client_cast_id: None,
    role: Child,
    spent: None,
    reserved: [],
  )
}

/// A fire's delay ran out: its spell is cast, unless its holder's cast has ended since or the
/// caster's life is one the spell refuses now.
fn proc_due(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  row row: spell_plan.ProcRow,
  at at: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id: source.cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(holder) ->
      case cast_proc.proc_refusal(caster:, row:, holder:) {
        Some(refusal) -> #(cast, [refusal])
        None -> proc_started(cast:, caster:, now_ms:, row:, holder:, at:)
      }
  }
}

/// A step's result with the held press started when the step cleared the current
/// cast it waited for.
fn released(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = cast_cost.after_payments(caster:, effects:)
  case cast.held {
    Some(Held(client_cast_id:, resolution:, until: CastClears)) ->
      case cast.current {
        None -> {
          let #(cast, started) =
            press_of(
              cast: State(..cast, held: None),
              caster:,
              now_ms:,
              client_cast_id:,
              resolution:,
            )
          #(cast, list.append(effects, started))
        }
        Some(_) -> taken
      }
    Some(Held(until: CooldownEnds, ..)) | None -> taken
  }
}

fn pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_ability.decode(body)
    |> client_connection.decoded(message_id: cast_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  use <- bool.guard(
    when: press.press == 0,
    return: Ok(
      #(cast, [
        Log(
          level: LogInfo,
          text: "a press with the press bit 0 is a console setting's, which is not built",
        ),
      ]),
    ),
  )
  case cast_press.ability_at(caster:, plans:, bag_index: press.bag_index) {
    Error(Nil) ->
      Ok(
        #(cast, [
          cast_frame.refused_unknown(
            client_cast_id: press.client_cast_id,
            spell4_id: 0,
          ),
        ]),
      )
    Ok(plain) -> {
      let ability = cast_press.surged(cast:, caster:, ability: plain)
      case
        cast_press.resolved(
          cast:,
          caster:,
          bag_spell: plain.spell4_id,
          ability:,
        )
      {
        Error(Nil) ->
          Ok(
            #(cast, [
              cast_frame.refused_unknown(
                client_cast_id: press.client_cast_id,
                spell4_id: ability.spell4_id.value,
              ),
            ]),
          )
        Ok(resolution) ->
          Ok(press_of(
            cast:,
            caster:,
            now_ms: now.monotonic_ms,
            client_cast_id: Some(press.client_cast_id),
            resolution:,
          ))
      }
    }
  }
}

/// The key of an ability goes down (held 1) or up (held 0). The client's reader
/// refuses a body longer or shorter than the message (`opcode.0x4db`), which ends
/// the connection, and a bag index with no ability is answered as a 0x9a's is,
/// with the client cast id 0 the client shows with no pending cast
/// (`cast.hold_stop`).
fn key_held(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use change <- result.try(
    ability_hold.decode(body)
    |> client_connection.decoded(message_id: ability_hold.message_id)
    |> result.map_error(NotDecoded),
  )
  let now_ms = now.monotonic_ms
  Ok(
    case
      cast_press.ability_at(caster:, plans:, bag_index: change.bag_index),
      change.held == 1
    {
      Error(Nil), True -> #(cast, [
        cast_frame.refused_unknown(client_cast_id: 0, spell4_id: 0),
      ])
      Error(Nil), False -> #(cast, [
        Log(
          level: LogDebug,
          text: "the key of the bag index "
            <> int.to_string(change.bag_index)
            <> ", which holds no ability, comes up",
        ),
      ])
      Ok(ability), True -> cast_press.key_down(cast:, ability:)
      Ok(ability), False -> key_up(cast:, caster:, ability:, now_ms:)
    },
  )
}

/// The ability's key comes up: its repeats stop, and the cast under way is left to
/// end. A ChargeRelease ability with its threshold open fires its charged stage, as
/// a 0x9a release does: the bag ability is swapped as a press swaps it, and the open
/// threshold is found by the swapped spell as a press finds it.
fn key_up(
  cast cast: State,
  caster caster: Caster,
  ability plain: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == plain.spell4_id ->
      cast_press.stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
  let ability = cast_press.surged(cast:, caster:, ability: plain)
  case cast_press.threshold_of(cast:, ability:) {
    Ok(Threshold(ability: charging, ..))
      if charging.method == spell_plan.ChargeRelease
    ->
      case
        cast_press.resolved(
          cast:,
          caster:,
          bag_spell: plain.spell4_id,
          ability:,
        )
      {
        Error(Nil) -> #(cast, [
          cast_frame.refused_unknown(
            client_cast_id: 0,
            spell4_id: charging.spell4_id.value,
          ),
          ..cancels
        ])
        Ok(resolution) -> {
          let #(cast, released) =
            press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
          #(cast, list.append(cancels, released))
        }
      }
    Ok(_) | Error(Nil) -> #(cast, cancels)
  }
}

/// A step's result with the held ability cast again when the step left nothing in
/// its way: its last cast is over, the caster's current cast is, and no timer waits
/// for a cooldown (`cast.hold_repeat`).
fn continued(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = cast_cost.after_payments(caster:, effects:)
  case cast.holding {
    Some(Holding(ability:, repeat_timer: None, last_cast:)) -> {
      let #(cast, more) =
        repeated(cast:, caster:, now_ms:, ability:, last_cast:)
      #(cast, list.append(effects, more))
    }
    Some(Holding(repeat_timer: Some(_), ..)) | None -> taken
  }
}

/// The held ability's next cast: a refusal when no stage is left, nothing while its
/// last cast or the caster's current cast is under way, a timer while a cooldown
/// runs, else the press itself.
fn repeated(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  ability plain: Spell,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let ability = cast_press.surged(cast:, caster:, ability: plain)
  case
    cast_press.resolved(cast:, caster:, bag_spell: plain.spell4_id, ability:)
  {
    Error(Nil) -> cast_press.no_stage_left(cast:, ability:)
    Ok(resolution) ->
      next_cast(cast:, caster:, now_ms:, resolution:, last_cast:)
  }
}

fn next_cast(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  resolution resolution: Resolution,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let last_cast_is_live =
    option.map(last_cast, dict.has_key(cast.casts, _)) == Some(True)
  let blocked =
    last_cast_is_live
    || cast_cost.casting(cast)
    && !resolution.spell.ignores_casting
    || option.is_some(cast.held)
  let wait_ms = case last_cast {
    Some(_) ->
      cast_press.cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:)
    None -> 0
  }
  case blocked, wait_ms > 0 {
    True, _ -> #(cast, [])
    False, True -> repeat_after(cast:, wait_ms:)
    False, False ->
      press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
  }
}

/// The held ability waits `wait_ms` for its cooldowns on a timer of its own.
fn repeat_after(
  cast cast: State,
  wait_ms wait_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, timer, start) =
    cast_state.armed(cast:, due: RepeatHeld, after_ms: wait_ms)
  #(
    State(
      ..cast,
      holding: option.map(cast.holding, fn(holding) {
        Holding(..holding, repeat_timer: Some(timer))
      }),
    ),
    [start],
  )
}

/// What a press of a spell comes to: the client's refusal, a held press or a
/// cast that starts. A press with no client cast id is a held key's (0x4DB): the
/// server mints the cast id, no 0x7fd is written, a refusal carries the client
/// cast id 0, and a cooldown or a current cast is waited for by the hold itself.
fn press_of(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let #(cast, effects) =
    press_resolved(
      cast:,
      caster:,
      now_ms:,
      client_cast_id:,
      resolution: Resolution(..resolution, logs: []),
    )
  #(cast, list.append(resolution.logs, effects))
}

/// A resolved press: the 285 refusal of a spell with no threshold time that no Proxy
/// replaced (the client tests the resolved spell, `0x1403c0144`, fact `cast.proxy_press`),
/// else the verdict on the spell. A Proxy of such a press is cast as the press itself
/// (`Base` of the Proxy's spell), so a Proxy with a threshold of its own opens it.
fn press_resolved(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let spell = resolution.spell
  let is_release = cast_press.is_release(resolution:)
  let held = option.is_some(cast.held)
  let refusal = fn(result) {
    cast_frame.refused(
      client_cast_id: option.unwrap(client_cast_id, 0),
      spell4_id: spell.spell4_id.value,
      result:,
    )
  }
  let judged = case
    resolution.stage == None
    && spell_plan.lacks_threshold_time(
      method: spell.method,
      threshold_ms: spell.threshold_ms,
    )
  {
    True -> Refuse(result: cast_result.IllegalSpellCast)
    False ->
      cast_press.verdict(
        cast:,
        caster:,
        spell:,
        now_ms:,
        is_release:,
        target_subject: None,
      )
  }
  case judged {
    Accept(paid:) -> {
      let payments = paid.payments
      let cast = case client_cast_id {
        Some(_) -> cast
        None ->
          cast_press.hold_started(
            cast:,
            ability: resolution.ability,
            cast_id: cast_state.next_cast_id(cast:, caster:),
          )
      }
      let #(taken, reserved) = case cast_cost.pays_at_accept(spell:) {
        True -> #(cast_cost.paying(payments:), [])
        False -> #([], payments)
      }
      let #(cast, started) = case resolution.stage {
        None ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: None,
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Base(
              ability: case resolution.proxied {
                True -> spell
                False -> resolution.ability
              },
              bag_spell: resolution.bag_spell,
            ),
            spent: paid.spent,
            reserved:,
          )
        Some(index) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: Some(resolution.ability.spell4_id),
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Stage(ability: resolution.ability, index:),
            spent: paid.spent,
            reserved:,
          )
      }
      #(cast, list.append(taken, started))
    }
    Refuse(result:) ->
      cast_press.refused_hold(
        cast:,
        client_cast_id:,
        ability: resolution.ability,
        effects: [
          refusal(result),
        ],
      )
    NotBuilt(result:, why:, issue:) ->
      case set.contains(cast.logged, UnbuiltSpell(spell.spell4_id.value)) {
        True ->
          cast_press.refused_hold(
            cast:,
            client_cast_id:,
            ability: resolution.ability,
            effects: [refusal(result)],
          )
        False ->
          cast_press.refused_hold(
            cast: State(
              ..cast,
              logged: set.insert(
                cast.logged,
                UnbuiltSpell(spell.spell4_id.value),
              ),
            ),
            client_cast_id:,
            ability: resolution.ability,
            effects: [
              Log(
                level: LogWarning,
                text: "the ability with Spell4 "
                  <> int.to_string(spell.spell4_id.value)
                  <> " "
                  <> why
                  <> ", the issue "
                  <> cast_press.issue_name(issue:)
                  <> ": it is refused with "
                  <> int.to_string(cast_result.to_value(result)),
              ),
              refusal(result),
            ],
          )
      }
    Hold(..) | HoldForCast if is_release && held -> #(cast, [
      refusal(cast_result.SpellAlreadyCasting),
    ])
    Hold(wait_ms:) ->
      case client_cast_id, is_release {
        None, False -> repeat_after(cast:, wait_ms:)
        Some(_), _ | None, True -> {
          let #(cast, _, start) =
            cast_state.armed(cast:, due: StartHeld, after_ms: wait_ms)
          #(
            State(
              ..cast,
              held: Some(Held(client_cast_id:, resolution:, until: CooldownEnds)),
            ),
            [start],
          )
        }
      }
    HoldForCast ->
      case client_cast_id, is_release {
        None, False -> #(cast, [])
        Some(_), _ | None, True -> #(
          State(
            ..cast,
            held: Some(Held(client_cast_id:, resolution:, until: CastClears)),
          ),
          [],
        )
      }
  }
}

fn cancelled(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use cancel <- result.try(
    cancel_cast.decode(body)
    |> client_connection.decoded(message_id: cancel_cast.message_id)
    |> result.map_error(NotDecoded),
  )
  let reason = cast_result.to_value(cancel.reason)
  use <- bool.guard(
    when: !{
      { reason == 6 || reason == 11 }
      && cancel.field_3 == 1
      || reason == 0
      && cancel.field_3 == 0
    },
    return: Error(UnknownCancel(reason:, bit: cancel.field_3)),
  )
  // A cancel is the player's intent to stop: the cast it names ends the hold that
  // started it (the server's choice), so nothing restarts or fires after it.
  let #(cast, stopped) =
    cast_press.stop_holding_cast(cast:, cast_id: cancel.cast_id)
  let #(cast, effects) =
    cancelling(cast:, cancel:, caster:, now_ms: now.monotonic_ms)
  Ok(#(cast, list.append(stopped, effects)))
}

/// The client's 0x805, the answer of the interaction an activate cast of castMethod 5
/// opened (`opcode.0x805.fields`): 3 says it began and changes nothing; 1 sends the go
/// at once, cancelling the go that waited for the cast time; 0 and 2 fail the cast with 146
/// (ClientSideInteractionFail), which ends it with no go. An answer for a cast that is not
/// live is dropped, since the client sends 0 when a finish closes its window
/// (`opcode.0x7fe.csi`); one for a live cast that waits for no answer, one that names
/// another spell or a result the client never sends is refused.
fn answered(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use answer <- result.try(
    client_side_interaction_result.decode(body)
    |> client_connection.decoded(
      message_id: client_side_interaction_result.message_id,
    )
    |> result.map_error(NotDecoded),
  )
  let cast_id = answer.cast_id
  use <- bool.guard(
    when: interaction_result.to_value(answer.result) > 3,
    return: Error(
      UnknownAnswer(result: interaction_result.to_value(answer.result)),
    ),
  )
  case dict.get(cast.casts, cast_id) {
    Error(Nil) ->
      Ok(
        #(cast, [
          Log(
            level: LogDebug,
            text: "the client answered the interaction of the cast "
              <> int.to_string(cast_id)
              <> ", which is not live",
          ),
        ]),
      )
    Ok(live) ->
      case live.interaction {
        AwaitingAnswer -> answer_taken(cast:, caster:, now_ms:, answer:, live:)
        NoInteraction | AnswerSucceeded -> Error(NoInteractionWaits(cast_id:))
      }
  }
}

/// The answer of a live cast that waits for one, once its spell is the one it names.
fn answer_taken(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  answer answer: client_side_interaction_result.ClientSideInteractionResult,
  live live: Live,
) -> Result(#(State, List(Effect)), Refusal) {
  let cast_id = answer.cast_id
  let expected = live.spell.spell4_base_id.value + 1
  use <- bool.guard(
    when: answer.spell4_base_id_plus_one != expected,
    return: Error(WrongAnswerSpell(
      cast_id:,
      sent: answer.spell4_base_id_plus_one,
      expected:,
    )),
  )
  case answer.result {
    interaction_result.Started ->
      Ok(
        #(cast, [
          Log(
            level: LogDebug,
            text: "the client's interaction of the cast "
              <> int.to_string(cast_id)
              <> " began",
          ),
        ]),
      )
    interaction_result.Other(..) ->
      Error(UnknownAnswer(result: interaction_result.to_value(answer.result)))
    interaction_result.Succeeded -> {
      let succeeded = Live(..live, interaction: AnswerSucceeded)
      let cast =
        State(..cast, casts: dict.insert(cast.casts, cast_id, succeeded))
      let #(cast, cancelled) =
        cast_state.cancel_timers(cast:, matching: fn(due) {
          due == Go(cast_id:, phase: 0)
        })
      let #(cast, going) = asked(cast:, caster:, now_ms:, cast_id:, phase: 0)
      Ok(#(cast, list.append(cancelled, going)))
    }
    interaction_result.Failed | interaction_result.CancelledBeforeStart ->
      Ok(persistence_end(
        cast:,
        caster:,
        now_ms:,
        cast_id:,
        result: cast_result.ClientSideInteractionFail,
      ))
  }
}

/// What a cancel the client may send ends: an open charge with its threshold, or
/// a live cast.
fn cancelling(
  cast cast: State,
  cancel cancel: CancelCast,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let reason = cast_result.to_value(cancel.reason)
  case reason == 0, cast_press.open_charge_of(cast:, cast_id: cancel.cast_id) {
    True, None -> #(State(..cast, current: None), [
      Log(
        level: LogDebug,
        text: "the client ended the threshold of the cast "
          <> int.to_string(cancel.cast_id)
          <> ", which is not open",
      ),
    ])
    True, Some(threshold) | False, Some(threshold) ->
      // The client clears the player's current cast before it sends, whatever cast
      // that is (`cast.current_cast`); the base cast of the charge ends with the
      // threshold.
      close_threshold(
        cast: State(..cast, current: None),
        ability: threshold.ability,
        now_ms:,
      )
    False, None -> {
      let cast = State(..cast, current: None)
      case dict.get(cast.casts, cancel.cast_id) {
        Error(Nil) -> #(cast, [
          Log(
            level: LogDebug,
            text: "the client ended the cast "
              <> int.to_string(cancel.cast_id)
              <> ", which is not live",
          ),
        ])
        Ok(live) ->
          end_live_cast(cast:, caster:, cast_id: cancel.cast_id, live:, now_ms:)
      }
    }
  }
}

/// A live cast the client cancelled stops: its waiting go and finish timers are
/// cancelled and it ends as after its last go (`finish_or_linger`): a cancel ends no
/// buff, so a cast that holds a node with life left lingers. A cast of
/// `EndsStealthAfterLastGo` that stops after at least one go and before its last ends
/// the other casts' stealth as it stops, since the goes that ran applied their effects;
/// one that stops before any go keeps it (`Spell4.spellCastStealthChange.break`; the
/// server's choice for the stop, the client giving no case). A death or leaving drops
/// every source already, so a 0x801 is the only stop that reaches this.
fn end_live_cast(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = cast_press.stop_pending(cast:, cast_id:)
  let #(cast, finished) = finish_or_linger(cast:, cast_id:, live:, now_ms:)
  let stopped_early =
    live.spell.stealth_change == spell_plan.EndsStealthAfterLastGo
    && live.gone > 0
    && live.gone < spell_plan.go_count(spell: live.spell)
  let #(cast, broken) = case stopped_early {
    True ->
      cast_proc.stealth_ended(
        cast:,
        caster:,
        sources: cast_press.other_casts_sources(cast:, cast_id:),
        now_ms:,
      )
    False -> #(cast, [])
  }
  #(cast, list.flatten([cancels, finished, broken]))
}

/// A timer of the rule fired: a go, a finish, a child cast, the held press or a
/// threshold's time.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [])
  released(
    taken: fire(cast:, timer:, caster:, now:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A channel's finish timer fired: the cast ends, or, when a go's strike round is still
/// open, waits for that round, since the go's 0x7f4 comes before the 0x7fe
/// (`cast.channel_sequence`). The go that closes the last round ends it, and the
/// round's deadline bounds the wait (`strike`).
fn finish_fired(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) ->
      case live.gone < spell_plan.go_count(spell: live.spell) {
        True -> #(
          State(
            ..cast,
            casts: dict.insert(
              cast.casts,
              cast_id,
              Live(..live, finish_due: True),
            ),
          ),
          [],
        )
        False -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
      }
  }
}

fn fire(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  case dict.get(cast.timers, timer) {
    Error(Nil) -> #(cast, [])
    Ok(due) -> {
      let cast = State(..cast, timers: dict.delete(cast.timers, timer))
      let now_ms = now.monotonic_ms
      case due {
        Go(cast_id:, phase:) -> asked(cast:, caster:, now_ms:, cast_id:, phase:)
        Tick(cast_id:, ..) ->
          cast_tick.ticks_due(cast:, caster:, now_ms:, cast_id:)
        Finish(cast_id:) -> finish_fired(cast:, cast_id:, now_ms:)
        StartChild(root:, parent:, proxy:, primary_target:) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root:,
            parent: Some(parent),
            primary_target:,
            client_cast_id: None,
            role: Child,
            spent: None,
            reserved: [],
          )
        NodesEnd(cast_id:) -> {
          let #(cast, ticks) =
            cast_tick.ticks_due(cast:, caster:, now_ms:, cast_id:)
          let #(cast, ended) = nodes_ended(cast:, cast_id:, now_ms:)
          #(cast, list.append(ticks, ended))
        }
        StateEnd(spell4_id:, unit_id:, state:) -> #(cast, [
          Send(frame: cast_frame.control_logged_frame(
            caster_unit_id: caster.unit_id,
            unit_id:,
            spell4_id:,
            state:,
            removed: True,
          )),
        ])
        ModifierStart(source:, change:) -> #(cast, [
          CasterChangeStarts(source:, change:),
        ])
        ModifierEnd(source:) -> #(cast, [CasterChangeEnds(source:)])
        RestrictionEnd(source:) ->
          cast_control.restriction_ended(cast:, source:)
        TargetModifierStart(on:, modifier:, struck_at_ms:) ->
          cast_control.target_modifier_started(
            cast:,
            on:,
            modifier:,
            struck_at_ms:,
          )
        ForcedMoveStart(on:, move:, struck_at_ms:) ->
          cast_control.throw_started(cast:, on:, move:, struck_at_ms:)
        CooldownModifierStarts(source:, modifier:, kept:) ->
          cooldown_applied(cast:, source:, modifier:, kept:, now_ms:)
        CooldownModifierEnds(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          [],
        )
        ProcDue(source:, row:, at:) ->
          proc_due(cast:, caster:, now_ms:, source:, row:, at:)
        RepeatHeld -> #(cast_press.repeat_fired(cast:, timer:), [])
        StartHeld ->
          case cast.held {
            None -> #(cast, [])
            Some(Held(client_cast_id:, resolution:, ..)) ->
              press_of(
                cast: State(..cast, held: None),
                caster:,
                now_ms:,
                client_cast_id:,
                resolution:,
              )
          }
        WindowEnd(spell4_id:) -> window_ended(cast:, spell4_id:, now_ms:)
        ChargeLevel(spell4_id:, level:) ->
          charge_level_reached(cast:, spell4_id:, level:)
      }
    }
  }
}

/// The round of a go closed with `struck`, the units it named in the order of its
/// selection: the go's 0x7f4 with a target info for each (target flags 0), the
/// 0x7fb of the deflected ones, the spell's own cooldown at its first go, the
/// Proxies of the phase (a Proxy aimed at each struck unit starts one child for each
/// Hit unit and none for a deflect, and none for a Proxy whose gate against the
/// caster does not pass) and the finish after the last go. A cast that is no longer
/// live, because the client ended it while the round was open, has no go and writes
/// nothing: the hits stand, and they raise their events (`cast_proc.hit_events`) for the spell of the
/// cast while it is held, else for `spell`, the go's spell as the areas name it by its
/// Spell4 id (`GoAsked.spell4_id`); a go the areas do not name strikes nobody. `poses` are
/// the Hit units' ground points and yaws as the caster's picture holds them when the round
/// closes, by unit id, which a Proxy's target gate reads (`children`); a Hit unit with none is not shown any more. `indexes` are the
/// checklist indexes their 0x262 carried, by unit id, which a type 94 condition of that gate
/// reads; a unit with none has no creature in the check. `units` are what each unit is, by
/// unit id (`prerequisite.FirstUnit`), which a type 38 condition of that gate reads; a unit
/// with none is unknown to the check. `rolls` are the
/// rolls the go's type 37 conditions take (`cast_gate.rolls_needed`), in the order the conditions
/// are checked. `gates_passed` are the effect ids of the gates each struck unit passed, by unit
/// id (genesis_prime/game/strike `Went`): a go row with a gate on the struck creature
/// (`spell_plan.StruckGate`) starts and is listed on a unit only when that unit's entry lists the
/// row, whichever part of the row's aim names the unit, the primary target included, and
/// whatever the round's outcome for it: a unit that deflected still has its entry, and a unit
/// that refused or never answered has none, so a gated row applies on it never. A row with no
/// gate is unaffected.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  spell asked_spell: Result(Spell, Nil),
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  let own =
    cast_state.holder_of(cast:, cast_id:)
    |> result.map(fn(holder) { holder.spell })
    |> result.lazy_or(fn() { asked_spell })
    |> result.map(fn(spell) { cast_proc.hit_events(spell:, struck:) })
    |> result.unwrap([])
  use <- settled(cast:, own:)
  released(
    taken: go(
      cast:,
      caster:,
      now_ms: now.monotonic_ms,
      cast_id:,
      phase:,
      struck:,
      gates_passed:,
      poses:,
      indexes:,
      units:,
      rolls:,
    ),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A go of a live cast is asked: its first go pays the cast's reserved costs, then
/// the connection selects its targets and strikes them, and answers with `went` when
/// the round closes. A cast that is not live has no go, and an activate cast of
/// castMethod 5 has none until the client has answered 1 (`answered` asks again).
fn asked(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(Live(interaction: AwaitingAnswer, ..)) -> #(cast, [])
    Ok(live) -> {
      // The first go pays what the accept reserved as its strike begins: creatures
      // apply the round's hits as soon as they are told, so they are always paid for,
      // and the go's gates and gains read the paid caster (the server's choice: the
      // order at one go is not recorded).
      let reserved = live.reserved
      let live = Live(..live, reserved: [])
      let cast = State(..cast, casts: dict.insert(cast.casts, cast_id, live))
      case live.activation {
        // An activate cast selects no targets: its go names the activated unit alone.
        Some(_) -> {
          let #(cast, going) =
            go(
              cast:,
              caster:,
              now_ms:,
              cast_id:,
              phase:,
              struck: [],
              gates_passed: dict.new(),
              poses: dict.new(),
              indexes: dict.new(),
              units: dict.new(),
              rolls: [],
            )
          #(cast, list.append(cast_cost.paying(payments: reserved), going))
        }
        None -> #(
          cast,
          list.append(cast_cost.paying(payments: reserved), [
            Strike(asked: GoAsked(
              cast_id:,
              phase:,
              spell4_id: live.spell.spell4_id,
              primary_target: live.primary_target,
              spent: live.spent,
            )),
          ]),
        )
      }
    }
  }
}

/// The earliest node of the cast `cast_id` has ended, live or lingering: the nodes
/// whose life is over are dropped and written 0x811, and the timer starts again for the
/// next end. A lingering cast left with no node ends with its 0x7fe instead. A cast
/// that holds nothing any more has no frame. The ticks of an ended node stop with it.
fn nodes_ended(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(ended, kept) =
        cast_tick.ended_and_kept(
          nodes: holder.nodes,
          ticking: holder.ticking,
          now_ms:,
        )
      case ended {
        [] -> cast_tick.rearmed(cast:, cast_id:, now_ms:)
        [_, ..] -> {
          let #(cast, ticks) =
            cast_tick.ticks_dropped_on(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, started) =
            cooldowns_started_at_node_end(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: cast_state.sorted_units(ended),
              now_ms:,
            )
          let #(cast, healed) =
            cast_tick.heals_landed_at_node_end(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, modifiers) =
            cast_proc.caster_modifiers_ended(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, on_creatures) =
            cast_control.creature_modifiers_ended(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, left) =
            cast_proc.nodes_left(
              cast:,
              cast_id:,
              holder:,
              nodes: dict.from_list(kept),
              now_ms:,
            )
          #(
            cast,
            list.flatten([
              ticks,
              cast_tick.nodes_ended_frames(cast_id:, holder:, ended:, kept:),
              started,
              healed,
              modifiers,
              on_creatures,
              left,
            ]),
          )
        }
      }
    }
  }
}

/// A tick's strike round closed (genesis_prime/game/strike `Ticked`): a landed tick
/// writes the 0x7f8 to the caster and tells the audience `CastTicked`, and a killing one
/// then drops the unit's ticks; a deflected or immune tick writes nothing and the ticks
/// go on; a refused tick or one left out at the deadline (`None`) writes nothing and
/// drops the unit's ticks. A tick whose row was dropped while its round was open, or
/// whose schedule a later go started again, writes nothing. A node end that waited for
/// the round goes on (`nodes_ended`).
pub fn ticked(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  asked asked: TickAsked,
  struck struck: Option(Struck),
) -> #(State, List(Effect)) {
  // A landed tick of a row the cast still holds raises the events of a hit (a guess: no
  // source says a periodic damage tick is a hit for a Proc).
  let own = case
    struck,
    cast_state.holder_of(cast:, cast_id: asked.cast_id)
    |> result.try(fn(holder) {
      dict.get(
        holder.ticking,
        cast_state.tick_key(unit_id: asked.unit_id, effect_id: asked.effect_id),
      )
      |> result.map(fn(_) { holder })
    })
  {
    Some(one), Ok(holder) ->
      cast_proc.hit_events(spell: holder.spell, struck: [one])
    _, _ -> []
  }
  use <- settled(cast:, own:)
  released(
    taken: tick_closed(cast:, now_ms: now.monotonic_ms, asked:, struck:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

fn tick_closed(
  cast cast: State,
  now_ms now_ms: Int,
  asked asked: TickAsked,
  struck struck: Option(Struck),
) -> #(State, List(Effect)) {
  let cast_id = asked.cast_id
  let key =
    cast_state.tick_key(unit_id: asked.unit_id, effect_id: asked.effect_id)
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) ->
      case dict.get(holder.ticking, key) {
        Error(Nil) -> #(cast, [])
        Ok(row) -> {
          let cast =
            cast_tick.with_ticking(
              cast:,
              cast_id:,
              ticking: dict.insert(
                holder.ticking,
                key,
                cast_state.round_closed(row:),
              ),
            )
          let #(cast, landed) =
            cast_tick.tick_outcome(
              cast:,
              audience: holder.audience,
              row:,
              asked:,
              struck:,
              now_ms:,
            )
          let #(cast, ended) = nodes_ended(cast:, cast_id:, now_ms:)
          #(cast, list.append(landed, ended))
        }
      }
  }
}

/// The caster died: each live cast ends with its timers cancelled and 0x7fe to
/// the caster and the audience that was told its start, in cast id order, and its nodes
/// with it, where a 0x801 lets them linger (`end_live_cast`); then the held press, the hold and every open
/// threshold end, and every other timer is cancelled, as when the player leaves
/// (`cast_tick.left`). The client does not end its own casts when it dies (not read,
/// `0x14045e740`), so the server's 0x7fe is the end its viewers see. Every stealth
/// source drops, and a stealthed caster's `StealthChanged` comes after the casts'
/// 0x7fe, followed by the casts of the procs the death fires: the `Died` procs first,
/// then those for the stealth it ended. The innate passive's cast is the one cast it
/// leaves: it stays live or lingering with its nodes, its modifiers, its pending timers,
/// its stealth sources and its procs, and nothing is written for it
/// (`cast_proc.passive_set_aside`); the delayed fires of its procs are the exception, dropped with
/// their timers cancelled, since the holder they wait for is gone (`cast_proc.proc_fires_dropped`).
pub fn died(
  cast cast: State,
  caster _caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [
    proc.Event(trigger: spell_plan.Died, other_unit: None, spell: None),
  ])
  all_ended(cast:, now:)
}

/// The caster left combat: the combat flag of its life (genesis_prime/game/player_life
/// `CombatLeft`) went off. The only effects are the casts of the procs held for it.
pub fn combat_left(
  cast cast: State,
  caster _caster: Caster,
  now _now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [
    proc.Event(trigger: spell_plan.LeftCombat, other_unit: None, spell: None),
  ])
  #(cast, [])
}

/// The end of an input in the world: each live or lingering cast whose spell's
/// persistence condition no longer holds ends, in cast id order, the lowest first,
/// checked again after each end (it can break another's condition), and a press held
/// for the current cast it cleared starts. The client never evaluates a persistence
/// column (`Spell4.prerequisiteIdCasterPersistence`), so when to check and how to end
/// are the server's: after every input, which is exact and needs no timer. A cast ends
/// with 0x7f9 {cast id, 282 or 283, the caster, 0}, which destroys its nodes and so ends
/// its buff, then the 0x7fe that takes it out of the client's table, and is told to the
/// audience as a finish (`opcode.0x7f9`, `cast.target_node_end`). CasterPersistence
/// (282) is checked before TargetPersistence (283), the caster the first unit and the
/// cast's primary target the second; TargetPersistence is checked only for a cast the
/// caster itself is the target of, since no creature's state is held here. A press held
/// for the current cast it cleared starts, and a held key repeats, as after any input;
/// the casts they start are checked in turn. A condition
/// of a type not read, a roll (none is drawn) and a creature target keep the cast, with
/// one debug line for the spell.
///
/// Gap (#336): the hoverboard's ride 85563 holds Ability Restriction under a persistence
/// of "under 85562" (Prerequisite 41771), and 85562's SummonMount (type 36) is not read,
/// so no node of 85562 is held and the ride ends in the input of its own go: the client
/// is shown 0x87f, 0x7f9 and 0x880 at once, and a press is refused 302 only while the
/// go's own input is taken. The ride closes this.
pub fn persisted(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [])
  let now_ms = now.monotonic_ms
  let #(cast, ended) = persistence_ended(cast:, caster:, now_ms:, done: [])
  let #(cast, effects) =
    released(taken: #(cast, ended), caster:, now_ms:)
    |> continued(caster:, now_ms:)
  // A press the end let start, or a repeat of a held key, starts a cast whose own
  // persistence may already fail.
  let #(cast, more) =
    persistence_ended(
      cast:,
      caster: cast_cost.after_payments(caster:, effects:),
      now_ms:,
      done: [],
    )
  #(cast, list.append(effects, more))
}

/// The casts that fail their persistence ended one at a time, the lowest cast id first,
/// until none fails.
fn persistence_ended(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  done done: List(Effect),
) -> #(State, List(Effect)) {
  let subject = cast_tick.subject_of(cast:, caster:)
  let #(cast, logs, failing) =
    cast_persist.first_failing_persistence(
      cast:,
      caster:,
      subject:,
      holders: cast_state.holders(cast:),
      logs: [],
    )
  case failing {
    None -> #(cast, list.append(done, logs))
    Some(#(cast_id, result)) -> {
      let #(cast, ended) =
        persistence_end(cast:, caster:, now_ms:, cast_id:, result:)
      persistence_ended(
        cast:,
        caster:,
        now_ms:,
        done: list.flatten([done, logs, ended]),
      )
    }
  }
}

/// A cast whose persistence failed ends as a death ends one cast: 0x7f9 with the
/// result, its go, finish, tick and NodesEnd timers cancelled, its property modifiers and
/// cooldown effects ended, the current cast cleared when it was this one, an open
/// threshold it is the base cast of closed as a 0x801 closes it, and its 0x7fe to the
/// caster and the audience.
fn persistence_end(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
) -> #(State, List(Effect)) {
  let failure =
    cast_persist.failed_effect(cast_id:, result:, unit_id: caster.unit_id)
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ -> {
      let #(cast, cancels) = cast_press.stop_pending(cast:, cast_id:)
      let #(cast, ticks) = cast_tick.ticks_all_dropped(cast:, cast_id:)
      let #(cast, nodes) = cast_tick.cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) =
        cast_proc.effects_ended(cast:, cast_id:, spell: live.spell)
      let #(cast, on_creatures) =
        cast_control.creature_modifiers_all_ended(cast:, cast_id:)
      let #(cast, finished) = case cast_press.open_charge_of(cast:, cast_id:) {
        Some(threshold) ->
          close_threshold(cast:, ability: threshold.ability, now_ms:)
        None -> finish(cast:, cast_id:, live:, now_ms:)
      }
      #(
        cast,
        list.flatten([
          [failure],
          cancels,
          ticks,
          nodes,
          ended,
          on_creatures,
          finished,
        ]),
      )
    }
    Error(Nil), Ok(lingering) -> {
      let #(cast, ticks) = cast_tick.ticks_all_dropped(cast:, cast_id:)
      let cast = State(..cast, lingering: dict.delete(cast.lingering, cast_id))
      let #(cast, nodes) = cast_tick.cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) =
        cast_proc.effects_ended(cast:, cast_id:, spell: lingering.spell)
      let #(cast, on_creatures) =
        cast_control.creature_modifiers_all_ended(cast:, cast_id:)
      #(
        cast_proc.passive_cleared(cast:, cast_id:),
        list.flatten([
          [failure],
          ticks,
          nodes,
          ended,
          on_creatures,
          cast_tick.finished_effects(cast_id:, audience: lingering.audience),
        ]),
      )
    }
    Error(Nil), Error(Nil) -> #(cast, [])
  }
}

/// The player's innate passive, the plans' spell of this Spell4Base, starts: a cast of
/// the player's own with its caster as root, no parent and its primary target, written
/// as 0x7ff with no 0x7fd, which runs no check of the caster and starts no global
/// cooldown (`Passive`). It starts at each join, alive or dead. A base the plans do not
/// hold is a warning and no cast.
pub fn passive_started(
  cast cast: State,
  caster caster: Caster,
  plans plans: Plans,
  base base: Spell4BaseId,
  now now: Now,
) -> #(State, List(Effect)) {
  case spell_plan.in_plans(plans:, base:) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the innate passive with Spell4Base "
          <> int.to_string(base.value)
          <> " is in no plan, so it is not started",
      ),
    ])
    Ok(spell) ->
      start(
        cast:,
        caster:,
        now_ms: now.monotonic_ms,
        spell:,
        root: spell.spell4_id,
        parent: None,
        primary_target: caster.unit_id,
        client_cast_id: None,
        role: Passive,
        spent: None,
        reserved: [],
      )
  }
}

/// The caster's casts, press, hold, thresholds and timers ended by its death.
fn all_ended(cast cast: State, now now: Now) -> #(State, List(Effect)) {
  let #(cast, aside) = cast_proc.passive_set_aside(cast:)
  let #(aside, fires_dropped) = cast_proc.proc_fires_dropped(aside:)
  let #(cast, ended) =
    dict.to_list(cast.casts)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.fold(#(cast, []), fn(so_far, entry) {
      let #(cast, effects) = so_far
      let #(cast, cancels) = cast_press.stop_pending(cast:, cast_id: entry.0)
      let #(cast, more) =
        finish(cast:, cast_id: entry.0, live: entry.1, now_ms: now.monotonic_ms)
      #(cast, list.flatten([effects, cancels, more]))
    })
  // A lingering cast ends with its 0x7fe when its caster dies: the server's choice,
  // since the client has no path that ends a buff on a unit's death
  // (`cast.target_node_end`).
  let lingering_ended =
    dict.to_list(cast.lingering)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      cast_tick.finished_effects(
        cast_id: entry.0,
        audience: { entry.1 }.audience,
      )
    })
  let modifiers_ended = cast_proc.modifiers_pending(cast:)
  let #(cast, cancelled) = cast_tick.left(cast:)
  #(
    cast_proc.passive_restored(cast:, aside:),
    list.flatten([
      fires_dropped,
      ended,
      lingering_ended,
      modifiers_ended,
      cancelled,
    ]),
  )
}

/// A creature's blow reached the caster, landed or deflected (genesis_prime/game/player_life
/// `BlowTaken`). Each cast that holds a stealth source damage breaks loses its node on the
/// caster when the blow lowered its absorbs, shield or health, as a type 80 removal takes it
/// off, and the input ends with `StealthChanged` when the caster is no longer stealthed; a
/// deflect, or a landed blow that lowered nothing, breaks none. A source kept on damage
/// stays (`Spell4Effects.effectType.83`: dataBits02). The blow's events are pending for the
/// procs of blows taken (`cast_proc.blow_events`).
pub fn blow_taken(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  blow blow: cast_proc.BlowTaken,
) -> #(State, List(Effect)) {
  stealth_after_blow(
    cast:,
    caster:,
    now:,
    events: cast_proc.blow_events(blow:),
    lowered: cast_proc.lowers(blow:),
  )
}

/// A creature's blow on the caster whose attack spell the tables could not give the groups
/// and school of: it raises no events for the procs, and breaks stealth as `blow_taken`
/// does. `lowered` says the blow lowered the absorbs, the shield or the health.
pub fn blow_taken_without_spell(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  lowered lowered: Bool,
) -> #(State, List(Effect)) {
  stealth_after_blow(cast:, caster:, now:, events: [], lowered:)
}

/// The stealth rule of a blow taken, shared by both: only a blow that lowered something
/// breaks the sources damage breaks.
fn stealth_after_blow(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  events events: List(proc.Event),
  lowered lowered: Bool,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: events)
  case lowered {
    True -> cast_proc.broken_by_damage(cast:, caster:, now_ms: now.monotonic_ms)
    False -> #(cast, [])
  }
}

/// A cast of the spell starts: its id, the start written to the caster (0x7fd for
/// a press, 0x7ff for a child) and told to the audience, the global cooldown, the
/// threshold's message and timers when the cast opens or moves one, the timer of
/// each later go and of a channel's finish, and the first go at once when it has
/// no wait.
fn start(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  client_cast_id client_cast_id: Option(Int),
  role role: Role,
  spent spent: Option(Int),
  reserved reserved: List(Payment),
) -> #(State, List(Effect)) {
  let id = cast_state.next_cast_id(cast:, caster:)
  let audience = caster.audience
  let go_times = spell_plan.go_times_ms(spell:)
  let gos =
    list.index_map(go_times, fn(wait_ms, phase) {
      #(wait_ms, Go(cast_id: id, phase:))
    })
    |> list.filter(fn(go) { go.0 > 0 })
  let finishing = case spell_plan.finish_after_ms(spell:) {
    Some(wait_ms) -> [#(wait_ms, Finish(cast_id: id))]
    None -> []
  }
  let #(cast, timer_effects) =
    list.fold(list.append(gos, finishing), #(cast, []), fn(so_far, wait) {
      let #(cast, effects) = so_far
      let #(cast, _, start) =
        cast_state.armed(cast:, due: wait.1, after_ms: wait.0)
      #(cast, list.append(effects, [start]))
    })
  let start_message =
    cast_frame.started_message(
      id:,
      spell:,
      root:,
      parent:,
      primary_target:,
      caster:,
      activating: case role {
        Activation(..) -> True
        Child | Base(..) | Stage(..) | Passive | Shortcut(..) -> False
      },
    )
  let live =
    Live(
      spell:,
      spent:,
      reserved:,
      root:,
      parent:,
      primary_target:,
      audience:,
      gone: 0,
      started_ms: now_ms,
      stage_of: case role {
        Stage(ability:, ..) -> Some(ability)
        Child | Base(..) | Passive | Activation(..) | Shortcut(..) -> None
      },
      closes_threshold: cast_press.closes_threshold(role:),
      nodes: dict.new(),
      ticking: dict.new(),
      activation: case role {
        Activation(activating:, ..) -> Some(activating)
        Child | Base(..) | Stage(..) | Passive | Shortcut(..) -> None
      },
      interaction: case role {
        Activation(interaction:, ..) | Shortcut(interaction:, ..) -> interaction
        Child | Base(..) | Stage(..) | Passive -> NoInteraction
      },
      shortcut: case role {
        Shortcut(..) -> True
        Child | Base(..) | Stage(..) | Passive | Activation(..) -> False
      },
      aimed: case role {
        Shortcut(aimed:, ..) -> aimed
        Child | Base(..) | Stage(..) | Passive | Activation(..) -> None
      },
      finish_due: False,
    )
  let global_ends = case role, spell.global_cooldown.starts_for_ms {
    Passive, _ -> cast.global_cooldown_ends_ms
    Child, Some(wait_ms)
    | Base(..), Some(wait_ms)
    | Stage(..), Some(wait_ms)
    | Activation(..), Some(wait_ms)
    | Shortcut(..), Some(wait_ms)
    -> Some(now_ms + wait_ms)
    Child, None
    | Base(..), None
    | Stage(..), None
    | Activation(..), None
    | Shortcut(..), None
    -> cast.global_cooldown_ends_ms
  }
  let cast =
    State(
      ..cast,
      presses: cast.presses + 1,
      global_cooldown_ends_ms: global_ends,
      casts: dict.insert(cast.casts, id, live),
      pending: case role {
        Base(..) | Stage(..) ->
          list.append(cast.pending, [
            proc.Event(
              trigger: spell_plan.UsesAbility,
              other_unit: None,
              spell: Some(cast_proc.event_spell(spell:)),
            ),
          ])
        Child | Passive | Activation(..) | Shortcut(..) -> cast.pending
      },
      passive: case role {
        Passive -> Some(id)
        Child | Base(..) | Stage(..) | Activation(..) | Shortcut(..) ->
          cast.passive
      },
      current: case
        role != Passive
        && spell_plan.shows_cast_bar(spell:, pressed: root == spell.spell4_id)
      {
        True -> Some(id)
        False -> cast.current
      },
    )
  let to_caster = case client_cast_id {
    Some(client_cast_id) ->
      cast_frame.confirmed_frame(client_cast_id:, start: start_message)
    None -> cast_frame.started_frame(start: start_message)
  }
  let told =
    list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastStarted(start: start_message),
      )
    })
  let #(cast, threshold_effects) = threshold_step(cast:, role:, cast_id: id)
  let #(cast, dropped_effects) = cast_press.controls_dropped(cast:, spell:)
  let opening =
    list.flatten([
      dropped_effects,
      [Send(frame: to_caster)],
      told,
      threshold_effects,
      timer_effects,
    ])
  case go_times {
    [0, ..] -> {
      let #(cast, going) = asked(cast:, caster:, now_ms:, cast_id: id, phase: 0)
      #(cast, list.append(opening, going))
    }
    _ -> #(cast, opening)
  }
}

/// The threshold's part of a cast's start: the ability's own spell opens one
/// (0x816, with its time or its charge timer), and a tap that is not the last
/// moves the index of a RapidTap one (0x817).
fn threshold_step(
  cast cast: State,
  role role: Role,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case role {
    Child | Passive | Activation(..) | Shortcut(..) -> #(cast, [])
    Base(ability:, bag_spell:) ->
      case spell_plan.opens_threshold(spell: ability) {
        True -> open_threshold(cast:, ability:, bag_spell:, cast_id:)
        False -> #(cast, [])
      }
    Stage(ability:, index:) ->
      case dict.get(cast.thresholds, ability.spell4_id.value) {
        Error(Nil) -> #(cast, [])
        Ok(threshold) -> {
          let next = index + 1
          case
            ability.method == spell_plan.RapidTap
            && next < list.length(ability.stages)
          {
            True -> #(
              State(
                ..cast,
                thresholds: dict.insert(
                  cast.thresholds,
                  ability.spell4_id.value,
                  Threshold(..threshold, index: next),
                ),
              ),
              [
                Send(frame: cast_frame.index_frame(
                  spell4_id: ability.spell4_id,
                  index: next,
                )),
              ],
            )
            False -> #(cast, [])
          }
        }
      }
  }
}

/// The ability's first press opens its threshold at index 0: 0x816 with the base
/// cast's id, and the timer of its time (RapidTap) or of its first charge level
/// (ChargeRelease).
fn open_threshold(
  cast cast: State,
  ability ability: Spell,
  bag_spell bag_spell: Spell4Id,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      thresholds: dict.insert(
        cast.thresholds,
        ability.spell4_id.value,
        Threshold(ability:, bag_spell:, index: 0, cast_id:),
      ),
    )
  let opened =
    Send(frame: cast_frame.opened_frame(
      spell4_id: ability.spell4_id,
      bag_spell:,
      cast_id:,
    ))
  case ability.method {
    spell_plan.RapidTap -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: WindowEnd(spell4_id: ability.spell4_id.value),
          after_ms: ability.threshold_ms,
        )
      #(cast, [opened, start])
    }
    spell_plan.ChargeRelease -> {
      let #(cast, waiting) = charge_timer(cast:, ability:, level: 1)
      #(cast, [opened, ..waiting])
    }
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Multiphase
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> #(cast, [opened])
  }
}

/// The timer of the charge level `level`, after the row's thresholdDuration, when
/// the ability has that row.
fn charge_timer(
  cast cast: State,
  ability ability: Spell,
  level level: Int,
) -> #(State, List(Effect)) {
  case list.drop(ability.stages, level) |> list.first {
    Error(Nil) -> #(cast, [])
    Ok(stage) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: ChargeLevel(spell4_id: ability.spell4_id.value, level:),
          after_ms: stage.duration_ms,
        )
      #(cast, [start])
    }
  }
}

/// The charge reaches `level`: 0x817, and the timer of the next level.
fn charge_level_reached(
  cast cast: State,
  spell4_id spell4_id: Int,
  level level: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let cast =
        State(
          ..cast,
          thresholds: dict.insert(
            cast.thresholds,
            spell4_id,
            Threshold(..threshold, index: level),
          ),
        )
      let #(cast, waiting) =
        charge_timer(cast:, ability: threshold.ability, level: level + 1)
      #(cast, [
        Send(frame: cast_frame.index_frame(
          spell4_id: threshold.ability.spell4_id,
          index: level,
        )),
        ..waiting
      ])
    }
  }
}

/// A RapidTap threshold's time ran out: the client closes it by itself, so the
/// server writes nothing, closes its own and starts the ability's cooldown
/// (`opcode.0x816`).
fn window_ended(
  cast cast: State,
  spell4_id spell4_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> #(
      start_cooldown(
        cast: State(..cast, thresholds: dict.delete(cast.thresholds, spell4_id)),
        spell: threshold.ability,
        now_ms:,
      ),
      [],
    )
  }
}

/// The ability's threshold closes: its timers are cancelled and 0x814 is sent. A
/// RapidTap one starts the ability's cooldown with the bit; a ChargeRelease one
/// ends its base cast with 0x7fe after the 0x814.
fn close_threshold(
  cast cast: State,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let key = ability.spell4_id.value
  case dict.get(cast.thresholds, key) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let #(cast, cancels) =
        cast_state.cancel_timers(cast:, matching: fn(due) {
          case due {
            WindowEnd(spell4_id:) | ChargeLevel(spell4_id:, ..) ->
              spell4_id == key
            Go(..)
            | Finish(..)
            | StartChild(..)
            | NodesEnd(..)
            | StateEnd(..)
            | ModifierStart(..)
            | TargetModifierStart(..)
            | ForcedMoveStart(..)
            | ModifierEnd(..)
            | RestrictionEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | ProcDue(..)
            | StartHeld
            | RepeatHeld
            | Tick(..) -> False
          }
        })
      let cast = State(..cast, thresholds: dict.delete(cast.thresholds, key))
      case ability.method {
        spell_plan.RapidTap -> #(
          start_cooldown(cast:, spell: ability, now_ms:),
          list.append(cancels, [
            Send(frame: cast_frame.closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 1,
            )),
          ]),
        )
        spell_plan.ChargeRelease -> {
          let closed =
            Send(frame: cast_frame.closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 0,
            ))
          let #(cast, ended) =
            end_base_cast(cast:, cast_id: threshold.cast_id, now_ms:)
          #(cast, list.flatten([cancels, [closed], ended]))
        }
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> #(cast, cancels)
      }
    }
  }
}

/// The base cast of a charge ends with its 0x7fe, when it is still live.
fn end_base_cast(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Ok(base) -> finish(cast:, cast_id:, live: base, now_ms:)
    Error(Nil) -> #(cast, [])
  }
}

/// The spell's own cooldown starts now, unless it is running already or the spell
/// has none. Its group cooldowns do not start: the server keeps none, so it is never
/// stricter than the client.
fn start_cooldown(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> State {
  State(
    ..cast,
    cooldowns: cooldown.start(
      book: cast.cooldowns,
      keys: cooldown.keys(
        spell4_id: spell.spell4_id,
        spell4_base_id: spell.spell4_base_id,
        spell_groups: spell.groups,
        cooldown_groups: spell.cooldown_groups,
      ),
      cooldown_ms: spell.cooldown_ms,
      now_ms:,
    ),
  )
}

/// The go of phase `phase` of a live cast, with the units its round struck: 0x7f4 to
/// the caster and the audience, then the 0x7fb of the deflected ones (the client
/// accepts either order and drops a miss after the finish, `cast.miss_order`), the
/// spell's own cooldown at the go its method names, the current cast cleared as the
/// client does, the Proxies of the phase whose gates pass, and the finish after the
/// last go. A cast that is not live has no go.
fn go(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      let spell = live.spell
      let go_count = spell_plan.go_count(spell:)
      let cast = case spell.cooldown_start {
        spell_plan.AtFirstGo if live.gone == 0 ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtLastGo if live.gone + 1 == go_count ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtFirstGo | spell_plan.AtLastGo | spell_plan.NotAtAGo -> cast
      }
      let cast = case live.stage_of {
        Some(ability)
          if spell.method == spell_plan.ChargeRelease && live.gone == 0
        -> start_cooldown(cast:, spell: ability, now_ms:)
        Some(_) | None -> cast
      }
      let current = case cast_gate.clears_current(cast:, live:, cast_id:) {
        True -> None
        False -> cast.current
      }
      let live = Live(..live, gone: live.gone + 1)
      let cast =
        State(..cast, current:, casts: dict.insert(cast.casts, cast_id, live))
      // The subject is read once here, before the children start and before the
      // finish: every gate of this go decides on the state before the go's own effects.
      let subject = cast_tick.subject_of(cast:, caster:)
      let #(starting, gate_logs, rolls) =
        cast_gate.proxy_gates(
          proxies: cast_gate.proxies_with_targets(
            spell:,
            phase:,
            struck:,
            spent: live.spent,
          ),
          subject:,
          rolls:,
        )
      let #(gains, rolls) =
        cast_gate.gains_given(
          spell:,
          phase:,
          starting:,
          subject:,
          rolls:,
          spent: live.spent,
        )
      let #(applied, lasting_logs, rolls) =
        cast_control.lasting_applied(
          spell:,
          phase:,
          spent: live.spent,
          subject:,
          rolls:,
        )
      let #(cast, restricting) =
        cast_control.restrictions_numbered(
          cast:,
          caster:,
          cast_id:,
          live:,
          applied:,
        )
      let aimed =
        aimed_at(
          applied:,
          caster:,
          live:,
          struck:,
          gates_passed:,
          phase:,
          restricting:,
          target_verdict: cast_tick.target_verdict_on(
            cast:,
            caster:,
            subject:,
            poses:,
            indexes:,
            units:,
          ),
          rolls:,
        )
      let go_message =
        cast_frame.go_message(
          cast_id:,
          phase:,
          place: caster.place,
          struck:,
          listed: aimed.units,
        )
      let missed = cast_frame.missed_message(cast_id:, struck:)
      let going =
        list.flatten([
          [Send(frame: cast_frame.went_frame(go: go_message))],
          list.map(map.sorted_connections(live.audience), fn(viewer) {
            Tell(to: viewer, news: client_connection.CastWent(go: go_message))
          }),
          case missed {
            Some(missed) -> [
              Send(frame: cast_frame.missed_frame(missed:)),
              ..list.map(map.sorted_connections(live.audience), fn(viewer) {
                Tell(to: viewer, news: client_connection.CastMissed(missed:))
              })
            ]
            None -> []
          },
        ])
      let immune =
        list.filter_map(struck, fn(one) {
          case one {
            Immune(unit_id:, ..) ->
              Ok(
                Send(frame: cast_frame.immunity_logged_frame(
                  caster_unit_id: caster.unit_id,
                  unit_id:,
                  spell4_id: spell.spell4_id,
                )),
              )
            Hit(..) | Deflected(..) -> Error(Nil)
          }
        })
      let armor_logged =
        list.filter_map(struck, fn(one) {
          case one {
            Hit(unit_id:, armor_removed:, ..)
              | Immune(unit_id:, armor_removed:, ..)
              if armor_removed > 0
            ->
              Ok(
                Send(frame: cast_frame.armor_logged_frame(
                  caster_unit_id: caster.unit_id,
                  unit_id:,
                  spell4_id: spell.spell4_id,
                  amount: armor_removed,
                )),
              )
            Hit(..) | Immune(..) | Deflected(..) -> Error(Nil)
          }
        })
      let shown = cast_control.restrictions_shown(restricting:, caster:, live:)
      let #(cast, removed) = removed_by_go(cast:, aimed:, now_ms:)
      let #(cast, logged) =
        cast_frame.states_logged(
          cast:,
          caster:,
          spell4_id: spell.spell4_id,
          aimed:,
          now_ms:,
        )
      let #(cast, given) =
        cast_proc.nodes_given(cast:, cast_id:, aimed:, now_ms:)
      let #(cast, ticks) =
        cast_tick.ticks_armed(
          cast:,
          cast_id:,
          go: live.gone,
          from_ms: now_ms,
          rows: aimed.ticking,
        )
      let #(cast, never_held) = cast_proc.procs_held(cast:, cast_id:, applied:)
      let #(cast, modifying) =
        cast_control.modifiers_armed(cast:, cast_id:, caster:, aimed:, struck:)
      let #(cast, throwing) =
        cast_control.struck_moves_armed(
          cast:,
          cast_id:,
          reached: aimed.reached,
          struck:,
        )
      let despawning =
        cast_control.despawns_told(
          cast:,
          reached: aimed.reached,
          struck:,
          went_at_ms: now_ms,
        )
      let unit_states =
        cast_control.unit_states_told(
          cast:,
          reached: aimed.reached,
          struck:,
          went_at_ms: now_ms,
        )
      let #(cast, healing) = cast_heal.heals_armed(cast:, cast_id:, aimed:)
      let #(cast, restriction_timers) =
        cast_control.restrictions_armed(cast:, cast_id:, restricting:)
      let #(cast, cooldowns) =
        cooldowns_armed(
          cast:,
          cast_id:,
          aimed:,
          longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
          now_ms:,
        )
      let #(cast, children, _) =
        list.fold(starting, #(cast, [], aimed.rolls_left), fn(so_far, proxy) {
          let #(cast, effects, rolls) = so_far
          let #(cast, more, rolls) =
            children(
              cast:,
              caster:,
              now_ms:,
              live:,
              proxy:,
              struck:,
              subject:,
              poses:,
              indexes:,
              units:,
              rolls:,
            )
          #(cast, list.append(effects, more), rolls)
        })
      let #(cast, stealth) =
        stealth_changed_by_go(
          cast:,
          caster:,
          cast_id:,
          spell:,
          applied:,
          last_go: live.gone >= go_count,
          now_ms:,
        )
      let #(cast, finished) = case
        live.gone == go_count
        && {
          live.finish_due || option.is_none(spell_plan.finish_after_ms(spell:))
        }
      {
        True ->
          case dict.get(cast.casts, cast_id) {
            Ok(live) -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
            Error(Nil) -> #(cast, [])
          }
        False -> #(cast, [])
      }
      // A cast that goes on after this go has its `NodesEnd` timer started for the
      // earliest end of its nodes; one that ended or lingers did that in its end.
      let #(cast, armed) = case
        cast_tick.nodes_aimed(aimed:) != [] && dict.has_key(cast.casts, cast_id)
      {
        True -> cast_tick.rearmed(cast:, cast_id:, now_ms:)
        False -> #(cast, [])
      }
      // The activation is applied by the cast's last go: a channel's Activate row is
      // delayed to it (Spell4Effects 10256, delayTime 2999 of a 3000 ms channel), though
      // the first go lists the row (phaseFlags 1). A cast stopped before its last go
      // activates nothing: the server's choice, since the client's own handling of the
      // Activate effect (`Spell4Effects.effectType.7`) is not read here for a stopped
      // channel.
      let activated = case live.activation {
        Some(Activating(unit_id:, creature_id:, alive_at_press:, by_item:, ..))
          if live.gone == go_count
        -> [Activated(unit_id:, creature_id:, alive_at_press:, by_item:)]
        Some(_) | None -> []
      }
      // The first go of a quest button's cast counts the objective: a later go of the
      // same cast counts nothing more.
      let counted = case live.shortcut && live.gone == 1 {
        True -> [
          ShortcutCast(spell4_id: spell.spell4_id.value, target: live.aimed),
        ]
        False -> []
      }
      #(
        cast,
        list.flatten([
          going,
          immune,
          armor_logged,
          shown,
          logged,
          removed,
          given,
          ticks,
          never_held,
          modifying,
          throwing,
          despawning,
          unit_states,
          healing,
          restriction_timers,
          cooldowns,
          gains,
          gate_logs,
          lasting_logs,
          aimed.reach_logs,
          children,
          stealth,
          finished,
          activated,
          counted,
          armed,
        ]),
      )
    }
  }
}

/// What a go does to the caster's stealth, after the go's other effects: each Stealth row
/// that applied adds its source (the cast `cast_id`, the row's effect) with the row's
/// `Breaks`; a RemoveStealth row that applied ends every source; then a spell whose
/// `stealth_change` ends stealth at this go (`EndsStealthAtEachGo`, or
/// `EndsStealthAfterLastGo` when `last_go`) ends the sources of the other casts. A cast
/// never ends the sources of its own Stealth rows, whichever go applied them. A source
/// ends as `cast.stealth` loses it and its cast's node leaves the caster, as `cast_proc.node_off`
/// takes a type 80 removal's (0x811, and the 0x7fe of a lingering cast of a method the
/// client keeps). A go with no row, and no source to end, changes nothing.
///
/// A cast of `EndsStealthAfterLastGo` that stops before its last go does not reach this
/// for the goes it missed; `end_live_cast` ends the stealth when it stops after a go.
fn stealth_changed_by_go(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  spell spell: Spell,
  applied applied: Applied,
  last_go last_go: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let stealth = cast_state.passed_of(applied:, as_kind: spell_plan.as_stealth)
  let remove_stealth =
    cast_state.passed_of(applied:, as_kind: spell_plan.as_remove_stealth)
  case cast_state.stealthed(cast:), stealth, remove_stealth {
    False, [], [] -> #(cast, [])
    _, _, _ -> {
      let cast =
        State(
          ..cast,
          stealth: list.fold(stealth, cast.stealth, fn(held, row) {
            dict.insert(
              held,
              unit_properties.Source(cast_id:, effect_id: row.effect_id),
              row.breaks,
            )
          }),
        )
      let #(cast, removed) = case remove_stealth {
        [] -> #(cast, [])
        [_, ..] ->
          cast_proc.stealth_ended(
            cast:,
            caster:,
            sources: dict.keys(cast.stealth),
            now_ms:,
          )
      }
      let #(cast, broken) = case spell.stealth_change, last_go {
        spell_plan.EndsStealthAtEachGo, _
        | spell_plan.EndsStealthAfterLastGo, True
        ->
          cast_proc.stealth_ended(
            cast:,
            caster:,
            sources: cast_press.other_casts_sources(cast:, cast_id:),
            now_ms:,
          )
        spell_plan.EndsStealthAfterLastGo, False | spell_plan.KeepsStealth, _ -> #(
          cast,
          [],
        )
      }
      #(cast, list.append(removed, broken))
    }
  }
}

/// Whether a go of phase `phase` lists the activation's Activate effect. A channel lists
/// it only at the go its phaseFlags name: Spell4Effects 10256 has phaseFlags 1, the first
/// go (`cast.channel_sequence`). A spell cast as a Normal one goes once, so it lists every
/// row, whatever phase the row names (an activate cast drops the phases,
/// `cast_press.activation_spell`).
fn activation_listed_at(
  live live: Live,
  phase phase: Int,
) -> fn(activate.ActivateEffect) -> Bool {
  fn(effect: activate.ActivateEffect) {
    live.spell.method != spell_plan.Channeled
    || spell_effect.has_flag(
      flags: effect.phase_flags,
      bit: spell_effect.phase_bit(phase:),
    )
  }
}

/// The walk of `reached_by`: the effects reached so far in rank order, the debug lines of
/// the target gates in the order the effects were walked, and the rolls left.
type Walk {
  Walk(reached: List(Reached), logs: List(Effect), rolls: List(Int))
}

/// The units each applied effect reaches, walking the effects in rank order, which is the order
/// their target gates draw rolls in. A row aimed at units is taken to each unit its aim names
/// that stands past the struck gates and the row's target apply prerequisite (`reach_units`);
/// a row that stands on the caster alone is kept on the caster.
fn reached_by(
  applied applied: Applied,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  target_verdict target_verdict: TargetVerdict,
  rolls rolls: List(Int),
) -> Walk {
  list.fold(
    applied.passed,
    Walk(reached: [], logs: [], rolls:),
    fn(walk, planned) {
      case planned.kind {
        spell_plan.ProxyEffect(..)
        | spell_plan.GainEffect(..)
        | spell_plan.RemoveStealthEffect(..)
        | spell_plan.ControlEffect(..) -> walk
        spell_plan.LastingEffect(lasting: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(_) { True },
            condition: row.condition,
            what: "the lasting effect " <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.RemoveEffect(remove: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(_) { True },
            condition: row.condition,
            what: "the SpellForceRemove effect "
              <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.ModifierEffect(modifier: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: spell_plan.modifier_aim(modifier: row),
            stands: fn(entry) {
              cast_gate.modifier_applies(
                row: entry.0,
                unit_id: entry.1,
                caster:,
                struck:,
              )
            },
            condition: row.condition,
            what: "the "
              <> cast_control.modifier_kind_named(row:)
              <> " effect "
              <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.StruckMoveEffect(struck_move: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(entry) {
              result.is_ok(cast_gate.creature_hit(struck:, unit_id: entry.1))
            },
            condition: row.condition,
            what: "the ForcedMove effect " <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.DespawnEffect(despawn: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(entry) {
              result.is_ok(cast_gate.creature_hit(struck:, unit_id: entry.1))
            },
            condition: row.condition,
            what: "the DespawnUnit effect "
              <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.UnitStateEffect(unit_state: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(entry) {
              result.is_ok(cast_gate.creature_hit(struck:, unit_id: entry.1))
            },
            condition: row.condition,
            what: "the UnitStateSet effect "
              <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.HealEffect(heal: row) ->
          reach_units(
            walk:,
            planned:,
            row:,
            aim: row.aim,
            stands: fn(_) { True },
            condition: row.condition,
            what: "the Heal or HealShields effect "
              <> int.to_string(row.effect_id.value),
            caster:,
            live:,
            struck:,
            gates_passed:,
            target_verdict:,
          )
        spell_plan.ForcedMoveEffect(..)
        | spell_plan.CooldownEffect(..)
        | spell_plan.StealthEffect(..)
        | spell_plan.ProcEffect(..) ->
          Walk(
            ..walk,
            reached: list.append(walk.reached, [
              Reached(effect: planned, unit_id: caster.unit_id, product: Plain),
            ]),
          )
      }
    },
  )
}

/// The walk after one row: an entry for the row on each unit its aim names that `stands`,
/// passes the struck gates and passes the row's target apply prerequisite, a debug line for
/// each the server cannot tell, and the rolls left (`cast_gate.reaching`).
fn reach_units(
  walk walk: Walk,
  planned planned: spell_effect.PlannedEffect(spell_plan.Kind),
  row row: row,
  aim aim: spell_plan.Aim,
  stands stands: fn(#(row, Int)) -> Bool,
  condition condition: spell_plan.Condition,
  what what: String,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  target_verdict target_verdict: TargetVerdict,
) -> Walk {
  let #(entries, logs, rolls) =
    cast_gate.rows_with_units(
      rows: [row],
      aim: fn(_) { aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> list.filter(stands)
    |> cast_gate.passing_struck_gates(
      effect_id: fn(_) { planned.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(_) { condition },
      what: fn(_) { what },
      target_verdict:,
      rolls: walk.rolls,
    )
  Walk(
    reached: list.append(
      walk.reached,
      list.map(entries, fn(entry) {
        Reached(effect: planned, unit_id: entry.1, product: Plain)
      }),
    ),
    logs: list.append(walk.logs, logs),
    rolls:,
  )
}

/// What the reach stage made of each effect it reached beside its unit, and the debug lines
/// of the heals it left: a heal on the caster is worked out (`cast_heal.healed_on`) and a
/// cooldown row is told whether it is kept for the cooldowns that start later
/// (`cast_control.cooldown_kept`); any other effect stands as it is.
fn products_made(
  reached reached: List(Reached),
  caster caster: Caster,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> #(List(Reached), List(Effect)) {
  let made =
    list.map(reached, fn(entry) {
      case entry.effect.kind {
        spell_plan.HealEffect(heal: row) -> {
          let #(product, logs) =
            cast_heal.healed_on(row:, unit_id: entry.unit_id, caster:)
          #(Reached(..entry, product:), logs)
        }
        spell_plan.CooldownEffect(modifier: row) -> #(
          Reached(
            ..entry,
            product: CooldownKept(kept: cast_control.cooldown_kept(
              row:,
              longer_of_delay_and_duration:,
            )),
          ),
          [],
        )
        spell_plan.ProxyEffect(..)
        | spell_plan.GainEffect(..)
        | spell_plan.LastingEffect(..)
        | spell_plan.RemoveEffect(..)
        | spell_plan.ModifierEffect(..)
        | spell_plan.ForcedMoveEffect(..)
        | spell_plan.StruckMoveEffect(..)
        | spell_plan.StealthEffect(..)
        | spell_plan.RemoveStealthEffect(..)
        | spell_plan.ProcEffect(..)
        | spell_plan.ControlEffect(..)
        | spell_plan.DespawnEffect(..)
        | spell_plan.UnitStateEffect(..) -> #(entry, [])
      }
    })
  #(
    list.map(made, fn(entry) { entry.0 }),
    list.flat_map(made, fn(entry) { entry.1 }),
  )
}

/// What a go reaches: the effects it reaches (`reached_by`) with what the reach stage made
/// of each (`products_made`), the units the go lists them on and the crowd-control states
/// and restrictions it holds, with the rolls the target gates left.
pub fn aimed_at(
  applied applied: Applied,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  phase phase: Int,
  restricting restricting: List(Restricting),
  target_verdict target_verdict: TargetVerdict,
  rolls rolls: List(Int),
) -> Aimed {
  let walk =
    reached_by(
      applied:,
      caster:,
      live:,
      struck:,
      gates_passed:,
      target_verdict:,
      rolls:,
    )
  let #(reached, heal_logs) =
    products_made(
      reached: walk.reached,
      caster:,
      longer_of_delay_and_duration: live.spell.longer_of_delay_and_duration,
    )
  let rolls = walk.rolls
  let controls = cast_control.controls_landed(struck:)
  let restrictions = list.map(restricting, fn(one) { #(one, caster.unit_id) })
  let ticking =
    list.append(
      cast_heal.ticking_struck(struck: cast_gate.struck_gates_applied(
        struck:,
        spell: live.spell,
        gates_passed:,
      )),
      cast_heal.ticking_heals(reached:, caster:),
    )
  let listed =
    list.flatten([
      reached_listed(reached:),
      list.map(ticking, fn(row) {
        #(
          row.unit_id,
          Listed(
            effect_id: row.effect_id,
            delay_ms: row.schedule.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(controls, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: Spell4EffectsId(entry.0.tell.effect_id),
            delay_ms: entry.0.tell.row.delay_ms,
            instance_id: Some(entry.0.tell.instance_id),
            damage: None,
          ),
        )
      }),
      list.map(restrictions, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.row.effect_id,
            delay_ms: entry.0.row.row.delay_ms,
            instance_id: Some(entry.0.instance_id),
            damage: None,
          ),
        )
      }),
      case live.activation {
        Some(Activating(unit_id:, effects:, ..)) ->
          effects
          |> list.filter(activation_listed_at(live:, phase:))
          |> list.map(fn(effect) {
            #(
              unit_id,
              Listed(
                effect_id: effect.effect_id,
                delay_ms: effect.delay_ms,
                instance_id: None,
                damage: None,
              ),
            )
          })
        None -> []
      },
    ])
  let units =
    list.fold(listed, [], fn(units: List(#(Int, List(Listed))), entry) {
      case list.key_find(units, entry.0) {
        Ok(on_unit) ->
          list.key_set(units, entry.0, list.append(on_unit, [entry.1]))
        Error(Nil) -> list.append(units, [#(entry.0, [entry.1])])
      }
    })
  Aimed(
    units:,
    reached:,
    reach_logs: list.append(walk.logs, heal_logs),
    controls:,
    restrictions:,
    ticking:,
    rolls_left: rolls,
  )
}

/// What the effects a go reached are listed as on their units, in the order the client's
/// list shows them: a Stealth row, a Proc row, a Fluff row, a property modifier, a forced
/// move on the caster, a struck move, a cooldown row, a SpellForceRemove row and a heal that
/// lands on the caster, each kind's rows in the order they were reached. This is not the
/// plan's rank order, so the kind's place is named here. An effect the go does not list (a
/// Proxy, a gain, a RemoveStealth, a crowd-control state, a periodic or another unit's
/// heal) is left out.
fn reached_listed(reached reached: List(Reached)) -> List(#(Int, Listed)) {
  reached
  |> list.filter_map(fn(entry) {
    let listed = fn(place: Int, delay_ms: Int, damage: Option(_)) {
      Ok(#(
        place,
        entry.unit_id,
        Listed(
          effect_id: entry.effect.effect_id,
          delay_ms:,
          instance_id: None,
          damage:,
        ),
      ))
    }
    case entry.effect.kind, entry.product {
      spell_plan.StealthEffect(stealth: row), _ ->
        listed(0, row.row.delay_ms, None)
      spell_plan.ProcEffect(proc: row), _ -> listed(1, row.row.delay_ms, None)
      spell_plan.LastingEffect(lasting: row), _ ->
        listed(2, row.row.delay_ms, None)
      spell_plan.ModifierEffect(modifier: row), _ ->
        listed(3, row.row.delay_ms, None)
      spell_plan.ForcedMoveEffect(forced_move: row), _ ->
        listed(4, row.delay_ms, None)
      spell_plan.StruckMoveEffect(struck_move: row), _ ->
        listed(5, row.delay_ms, None)
      spell_plan.CooldownEffect(modifier: row), _ ->
        listed(6, row.row.delay_ms, None)
      spell_plan.RemoveEffect(..), _ -> listed(7, 0, None)
      spell_plan.HealEffect(..), Healing(healed:) ->
        listed(8, healed.delay_ms, Some(cast_heal.heal_description(healed:)))
      spell_plan.HealEffect(..), Plain
      | spell_plan.HealEffect(..), CooldownKept(..)
      | spell_plan.ProxyEffect(..), _
      | spell_plan.GainEffect(..), _
      | spell_plan.RemoveStealthEffect(..), _
      | spell_plan.DespawnEffect(..), _
      | spell_plan.UnitStateEffect(..), _
      | spell_plan.ControlEffect(..), _
      -> Error(Nil)
    }
  })
  |> list.index_map(fn(entry, index) { #(entry, index) })
  |> list.sort(fn(a, b) {
    int.compare(a.0.0, b.0.0)
    |> order.break_tie(int.compare(a.1, b.1))
  })
  |> list.map(fn(entry) { #(entry.0.1, entry.0.2) })
}

/// The type 80 effects of a go taken off the units they aim at, in order: each takes
/// the matching casts of the caster off the unit, oldest first, and writes 0x811 or
/// 0x813 for each (`opcode.0x811`, `opcode.0x813`).
fn removed_by_go(
  cast cast: State,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.reached, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    case entry.effect.kind {
      spell_plan.RemoveEffect(remove: row) -> {
        let unit_id = entry.unit_id
        let removals =
          lasting.removals(
            holds: cast_tick.holds_on(cast:, unit_id:),
            selector: row.selector,
            count: row.count,
            unit_id:,
          )
        let #(cast, more) = cast_proc.apply_removals(cast:, removals:, now_ms:)
        #(cast, list.append(effects, more))
      }
      spell_plan.ProxyEffect(..)
      | spell_plan.GainEffect(..)
      | spell_plan.LastingEffect(..)
      | spell_plan.ModifierEffect(..)
      | spell_plan.ForcedMoveEffect(..)
      | spell_plan.StruckMoveEffect(..)
      | spell_plan.CooldownEffect(..)
      | spell_plan.StealthEffect(..)
      | spell_plan.RemoveStealthEffect(..)
      | spell_plan.ProcEffect(..)
      | spell_plan.HealEffect(..)
      | spell_plan.ControlEffect(..)
      | spell_plan.DespawnEffect(..)
      | spell_plan.UnitStateEffect(..) -> so_far
    }
  })
}

/// The cooldown effects a go applies, each armed from this go: the effect of an
/// earlier go of the cast is armed again, its timers cancelled and started anew. A row
/// with no delay takes effect in this step and any other on a timer of its delay. A row
/// is kept for the cooldowns that start later when it is `cast_control.cooldown_kept`; a kept row is
/// dropped on a timer at the end of its lifetime, unless it never ends.
fn cooldowns_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.reached, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    case spell_plan.as_cooldown_modifier(entry.effect.kind) {
      Ok(row) -> {
        let assert CooldownKept(kept:) = entry.product
          as "the reach stage tells each cooldown row whether it is kept"
        let #(cast, armed) =
          cooldown_row_armed(
            cast:,
            cast_id:,
            row:,
            kept:,
            longer_of_delay_and_duration:,
            now_ms:,
          )
        #(cast, list.append(effects, armed))
      }
      Error(Nil) -> so_far
    }
  })
}

/// One cooldown row armed from this go: its earlier timers cancelled, its start applied
/// at once or on a timer of its delay, and, when it is kept and not until removed, its drop on
/// a timer at the end of its lifetime.
fn cooldown_row_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.CooldownModifier,
  kept kept: Bool,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
  let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
  let lifetime_ms =
    lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
  let #(cast, starting) = case row.row.delay_ms > 0 {
    True -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: CooldownModifierStarts(source:, modifier: row.modifier, kept:),
          after_ms: row.row.delay_ms,
        )
      #(cast, [start])
    }
    False ->
      cooldown_applied(cast:, source:, modifier: row.modifier, kept:, now_ms:)
  }
  let #(cast, ending) = case kept && !row.row.until_removed {
    True -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: CooldownModifierEnds(source:),
          after_ms: lifetime_ms,
        )
      #(cast, [start])
    }
    False -> #(cast, [])
  }
  #(cast, list.flatten([cancels, starting, ending]))
}

/// A cooldown effect takes effect: it is kept for the cooldowns that start later when
/// `kept`, and the running cooldowns it picks change. When one did, a press held for a
/// cooldown and the hold's repeat wait again for the new end (`waits_rearmed`).
fn cooldown_applied(
  cast cast: State,
  source source: unit_properties.Source,
  modifier modifier: cooldown.Modifier,
  kept kept: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let book = case kept {
    True -> cooldown.keep(book: cast.cooldowns, source:, modifier:)
    False -> cast.cooldowns
  }
  let changed = cooldown.modify(book:, modifier:, now_ms:)
  let cast = State(..cast, cooldowns: changed)
  case changed == book {
    True -> #(cast, [])
    False -> waits_rearmed(cast:, now_ms:)
  }
}

/// The wait of a press held for a cooldown's end and of the held ability's repeat is
/// worked out again after a cooldown moved: each timer is cancelled and started for the
/// new wait, which is a timer of 0 ms when the cooldown ended, so the step's own messages
/// go out first. The press waits for the end wherever it moves (the server's choice,
/// `cast.hold_repeat`).
fn waits_rearmed(
  cast cast: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, held) = case cast.held {
    Some(Held(resolution:, until: CooldownEnds, ..)) -> {
      let #(global_left, own_left) =
        cast_cost.cooldown_left_ms(cast:, spell: resolution.spell, now_ms:)
      let #(cast, cancels) =
        cast_state.cancel_timers(cast:, matching: fn(due) { due == StartHeld })
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: StartHeld,
          after_ms: int.max(global_left, own_left),
        )
      #(cast, list.append(cancels, [start]))
    }
    Some(Held(until: CastClears, ..)) | None -> #(cast, [])
  }
  let #(cast, repeating) = case cast.holding {
    Some(Holding(ability:, repeat_timer: Some(_), ..)) ->
      case
        cast_press.resolved_by_threshold(
          cast:,
          bag_spell: ability.spell4_id,
          ability:,
        )
      {
        Ok(resolution) -> {
          let #(cast, cancels) =
            cast_state.cancel_timers(cast:, matching: fn(due) {
              due == RepeatHeld
            })
          let #(cast, start) =
            repeat_after(
              cast:,
              wait_ms: cast_press.cooldown_wait_ms(
                cast:,
                spell: resolution.spell,
                now_ms:,
              ),
            )
          #(cast, list.append(cancels, start))
        }
        Error(Nil) -> #(cast, [])
      }
    Some(Holding(repeat_timer: None, ..)) | None -> #(cast, [])
  }
  #(cast, list.append(held, repeating))
}

/// The cooldown effects of the cast `cast_id` that a timer still waits to start, taken
/// effect as the caster's node ends by time, because a node lives at least as long as
/// every row's delay from the same go, so the row's start falls in the millisecond of
/// the node's end or before it. A node taken off, by a removal, a death or a leave, does
/// not apply them: the client's 0x811 or 0x7fe destroys the pending effect.
fn cooldowns_started_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  list.fold(spell.effects, #(cast, []), fn(so_far, planned) {
    let #(cast, effects) = so_far
    case planned.kind {
      spell_plan.CooldownEffect(modifier: row) -> {
        let #(cast, started) =
          cooldown_row_started(cast:, cast_id:, row:, now_ms:)
        #(cast, list.append(effects, started))
      }
      spell_plan.ProxyEffect(..)
      | spell_plan.GainEffect(..)
      | spell_plan.LastingEffect(..)
      | spell_plan.RemoveEffect(..)
      | spell_plan.ModifierEffect(..)
      | spell_plan.ForcedMoveEffect(..)
      | spell_plan.StruckMoveEffect(..)
      | spell_plan.StealthEffect(..)
      | spell_plan.RemoveStealthEffect(..)
      | spell_plan.ProcEffect(..)
      | spell_plan.HealEffect(..)
      | spell_plan.ControlEffect(..)
      | spell_plan.DespawnEffect(..)
      | spell_plan.UnitStateEffect(..) -> #(cast, effects)
    }
  })
}

/// One cooldown row whose start a timer still waits for: the timer is cancelled and the
/// start taken effect now; a row with no timer waiting has nothing to start.
fn cooldown_row_started(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.CooldownModifier,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      due
      == CooldownModifierStarts(source:, modifier: row.modifier, kept: False)
    })
  case cancels {
    [] -> #(cast, [])
    [_, ..] -> {
      let #(cast, applied) =
        cooldown_applied(
          cast:,
          source:,
          modifier: row.modifier,
          kept: False,
          now_ms:,
        )
      #(cast, list.append(cancels, applied))
    }
  }
}

/// A Proxy of a go: a Proxy aimed at the area starts one child for each Hit unit of
/// the round and none for a deflect, any other starts one on the caster. A Proxy behind a
/// target gate starts a child on a unit only when the gate passes against that unit, once
/// for each unit, in the order of the units, each check taking the rolls its gate needs
/// (`cast_tick.target_gate`); the rolls left follow the effects.
fn children(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  struck struck: List(Struck),
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect), List(Int)) {
  let targets = case proxy.target {
    spell_plan.OnCaster -> [caster.unit_id]
    spell_plan.OnEachStruck -> cast_gate.hit_units(struck:)
  }
  list.fold(targets, #(cast, [], rolls), fn(so_far, primary_target) {
    let #(cast, effects, rolls) = so_far
    let #(gate, rolls) =
      cast_tick.target_gate(
        cast:,
        proxy:,
        caster:,
        primary_target:,
        subject:,
        poses:,
        indexes:,
        units:,
        rolls:,
      )
    case gate {
      Starts -> {
        let #(cast, more) =
          child(cast:, caster:, now_ms:, live:, proxy:, primary_target:)
        #(cast, list.append(effects, more), rolls)
      }
      GateFails -> #(cast, effects, rolls)
      CannotTell(why:) -> #(
        cast,
        list.append(effects, [Log(level: LogDebug, text: why)]),
        rolls,
      )
    }
  })
}

/// One child of a Proxy: it starts at once for no delay, else after it from a timer
/// of its own. The Proxy's gate has passed at the go (`cast_gate.proxy_gates`).
fn child(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  primary_target primary_target: Int,
) -> #(State, List(Effect)) {
  case proxy.delay_ms > 0 {
    False ->
      start(
        cast:,
        caster:,
        now_ms:,
        spell: proxy.spell,
        root: live.root,
        parent: Some(live.spell.spell4_id),
        primary_target:,
        client_cast_id: None,
        role: Child,
        spent: None,
        reserved: [],
      )
    True -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: StartChild(
            root: live.root,
            parent: live.spell.spell4_id,
            primary_target:,
            proxy:,
          ),
          after_ms: proxy.delay_ms,
        )
      #(cast, [start])
    }
  }
}

/// A live cast ends: 0x7fe to the caster and the audience, and the cast is no
/// longer live nor the caster's current cast. A channel starts its cooldown here
/// too (`0x14053e1b0`), and a stage that closes its ability's threshold does that
/// after its 0x7fe.
fn finish(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, ticks) = cast_tick.ticks_all_dropped(cast:, cast_id:)
  let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
  #(
    cast_proc.passive_cleared(cast:, cast_id:),
    list.flatten([
      ticks,
      cast_tick.finished_effects(cast_id:, audience: live.audience),
      closed,
    ]),
  )
}

/// Every step of a live cast's end but its 0x7fe: the cast is no longer live nor the
/// caster's current cast, a channel starts its cooldown (`0x14053e1b0`), and a stage
/// that closes its ability's threshold does that, with what the close writes.
fn finish_steps(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      casts: dict.delete(cast.casts, cast_id),
      current: case cast.current == Some(cast_id) {
        True -> None
        False -> cast.current
      },
    )
  let cast = case live.spell.method, live.spell.cooldown_phase {
    spell_plan.Channeled, _ -> start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, Some(phase) if live.gone > phase ->
      start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, _ -> cast
    spell_plan.Normal, _
    | spell_plan.PressHold, _
    | spell_plan.ChanneledField, _
    | spell_plan.ClientSideInteraction, _
    | spell_plan.RapidTap, _
    | spell_plan.ChargeRelease, _
    | spell_plan.Transactional, _
    | spell_plan.OtherMethod(..), _
    -> cast
  }
  case live.stage_of, live.closes_threshold {
    Some(ability), True -> close_threshold(cast:, ability:, now_ms:)
    Some(_), False | None, True | None, False -> #(cast, [])
  }
}

/// A live cast that has gone for the last time ends, or lingers when a node of it
/// still has life: every step of its end runs, and only its 0x7fe waits until its
/// last node ends (`cast.target_node_end`). A node whose life is over when the cast
/// starts to linger is written 0x811 at once. The innate passive's cast lingers even
/// when no node of it lives, so it ends with no 0x7fe, and only when its last node is
/// taken off.
fn finish_or_linger(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(ended, kept) =
    cast_tick.ended_and_kept(nodes: live.nodes, ticking: live.ticking, now_ms:)
  case kept, cast.passive == Some(cast_id) {
    [], False -> finish(cast:, cast_id:, live:, now_ms:)
    [], True | [_, ..], _ -> {
      let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
      let cast =
        State(
          ..cast,
          lingering: dict.insert(
            cast.lingering,
            cast_id,
            Lingering(
              spell: live.spell,
              audience: live.audience,
              started_ms: live.started_ms,
              primary_target: live.primary_target,
              nodes: dict.from_list(kept),
              ticking: live.ticking,
            ),
          ),
        )
      let #(cast, ticks) =
        cast_tick.ticks_dropped_on(
          cast:,
          cast_id:,
          unit_ids: cast_state.sorted_units(ended),
        )
      let #(cast, armed) = cast_tick.rearmed(cast:, cast_id:, now_ms:)
      let expired = case ended {
        [] -> []
        [_, ..] ->
          cast_tick.targets_removed_effects(
            cast_id:,
            unit_ids: cast_state.sorted_units(ended),
            audience: live.audience,
            destroyed: False,
          )
      }
      #(cast, list.flatten([ticks, expired, armed, closed]))
    }
  }
}
