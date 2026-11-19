//// Pressing, holding and charging an ability: the thresholds, the key's repeats and the refusals of a press.
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is a
////   console setting's; the press is logged and ignored. A bag index the player
////   does not hold is answered 0x7fc with Spell4 id 0 and result 4
////   (`0x14039a040`; the server's choice, which the client allows).
//// - **The hold** is 0x4db: the client sends it instead of 0x9a under its default
////   hold-to-continue-casting setting, once with held 1 at key down and once with
////   held 0 at key up, with no cast id of its own (`opcode.0x4db`). A held 1 is the
////   same press as a 0x9a's with two differences: the server mints the cast id and
////   writes 0x7ff in place of 0x7fd (a 0x7fd names a pending cast the client does
////   not make), and a refusal is a 0x7fc with client cast id 0
////   (`cast.hold_answer`). The client holds no repeat timer, so while the key is
////   held the server casts the ability again, when its last cast is over and the
////   global cooldown it started, the ability's own cooldown and its groups have ended, on a
////   timer of the rule; a press behind another cast waits for its end, never
////   refused 13, which the client hides under the setting (`cast.hold_repeat`; the
////   server's choice). A second ability's held 1 replaces the held one, and a second
////   held 1 of the held ability is the same hold. Held 0 ends the repeats and cuts
////   no cast or channel short; for a ChargeRelease ability it fires the charged
////   stage, and a RapidTap ability's repeats are its next stages inside its
////   threshold (`cast.hold_by_method`, `cast.hold_stop`). A refused repeat ends the
////   hold, and so does a 0x801 naming the hold's last cast (the server's choice: a
////   cancel is the player's intent to stop, so a cancelled charge neither restarts
////   nor fires at the held 0 that follows). A bag index with no ability is answered as a 0x9a's is.
//// - **The target** of every cast is the caster: no level-1 ability needs a
////   target the client picks (`Spell4TargetMechanics.targetType`: the client makes
////   the caster the target of a spell of kind 0, 2, 6 or 7 before it sends), so
////   the press's target is not read, and the target checks of the client (91, 105)
////   wait for the first ability that needs one. Who a spell strikes is the area its
////   effects name, which a later step reads.
//// - **The current cast** is the client's: a cast whose spell shows a cast bar
////   (`spell_plan.shows_cast_bar`) is the caster's current cast from its start. Its
////   go clears it for a Normal cast with a cast time and no parent, and a cast
////   that is itself the current cast clears it at its go unless its method is
////   Multiphase, ChargeRelease or PressHold or it is a channel; any cast's finish
////   clears it, and a 0x801 clears it whatever cast it names. The client refuses
////   a press with 13 only against it, and not when its spell is free while live or
////   the pressed spell ignores casting (`cast.current_cast`, `Spell4.propertyFlags`,
////   `0x1403afb10`). The server keeps the same in `current`.
//// - **A press during the current cast is the server's choice.** The client itself
////   never refuses an ability press with 13 and never queues one behind its current
////   cast: its casting test runs only for a request whose word 0x14 is non-zero,
////   which a press leaves 0 (`cast.press_queue`). The server models that unused test
////   with the same window as the cooldown queue: a press with more than 500 ms of
////   the current cast left (its start plus its duration, `spell_plan.duration_ms`,
////   less the time now) is refused 13, and one with 500 ms or less left is held and
////   starts at the go or finish that clears the current cast, not from a timer. A
////   cast that has no end of its own, a charge held until its release, always
////   refuses.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A press with more left
////   of the global cooldown, the spell's own cooldown or one of its cooldown groups is
////   refused 14, 15 or 16, whichever of those runs last in that order
////   (`cast_cost.cooldown_refusal`). A second press
////   while one is held is refused 13 (the server's choice). The held press keeps
////   the stage it resolved to when it came, as the client does. The release of a
////   ChargeRelease threshold is resolved before any caster check, so a held press
////   neither refuses it nor is changed by it (`0x1403bfd60`).
//// - **A RapidTap threshold** opens with the first tap's 0x816 and lasts the
////   ability's thresholdTime from a timer the server mirrors, since the client
////   closes it by itself then (`opcode.0x816`). Each later tap casts the stage at
////   the threshold's index, with root the ability and parent the ability
////   (`cast.stage_root_parent`), and the next index goes in 0x817; the last stage
////   closes the threshold with 0x814 and the bit set, which starts the ability's
////   cooldown. The window ending closes it, writes nothing and starts the cooldown
////   (`opcode.0x814`, `opcode.0x817`, `0x1403bfd60`).
//// - **A ChargeRelease threshold** opens with the first press's 0x816; the press's
////   cast, the base cast, stays live with no go until the release or a cancel
////   (`cast.charge_release_base`). Each later row's thresholdDuration after the
////   one before, a timer sends the next level in 0x817. The release is the next
////   press, which casts the row at the level reached; its first go starts the
////   ability's cooldown, and after its finish 0x814 closes the threshold and the
////   base cast ends with 0x7fe. The client marks the charge full at the ability's
////   thresholdTime and sends nothing, so the server holds the charge until a
////   release or a cancel.

import genesis_prime/game/activate
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/state.{
  type AimedPress, type Caster, type Effect, type Interaction, type Refusal,
  type Resolution, type Role, type State, type Threshold, type Unbuilt,
  type Verdict, Activation, AnswerSucceeded, AwaitingAnswer, Base, CancelTimer,
  CannotTell, ChargeLevel, Child, CooldownModifierEnds, CooldownModifierStarts,
  DroppedControls, DroppedDespawns, DroppedSignals, DroppedUnitStates, Finish,
  ForcedMoveStart, GateFails, Go, Hold, HoldForCast, Holding, Log, ModifierEnd,
  ModifierStart, NoInteraction, NodesEnd, NotBuilt, Passive, ProcDue,
  QuestAdvanceDue, Refuse, RepeatHeld, Resolution, RestrictionEnd, Shortcut,
  Stage, StartChild, StartHeld, Starts, State, StateEnd, TargetModifierStart,
  Tick, UnbuiltItemSpell, UnbuiltPlayerTarget, UnbuiltShortcut, UnbuiltSpell,
  Unheld, Unpaid, UnreadItemPrerequisite, UnreadLinkPrerequisite,
  UnreadPrerequisite, UnreadShortcutPick, UnreadSpend, WindowEnd,
} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/crowd_control
import genesis_prime/game/prerequisite
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/unit_properties
import genesis_prime/game/unit_state
import genesis_prime/gap
import genesis_prime/message/cast_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/step.{type TimerId, LogDebug, LogWarning}
import genesis_prime/table/id.{type Spell4EffectsId, type Spell4Id}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string

/// What a press is refused or cast without, because the server does not build what the cast
/// needs: the sentence of each kind of `NotBuilt` or `Dropped*` key, then the limits of the
/// press and of the activate cast's timing.
pub fn gaps() -> List(gap.Entry) {
  [
    "A spell cast at another player's unit is refused, because the server holds no other player's life, combat, faction or race to test it by, so an effect a player casts on another player does not land on that player.",
    "A spell whose cast condition, caster requirement's waiver or creature pick is of a prerequisite type the server does not read is refused.",
    "A spell the server cannot plan, whose cast method is not built, or whose innate cost is in a vital the server does not hold or is spent by an EMM id it does not read, is refused.",
    "A crowd-control state on another unit that lasts until removed is dropped from a cast, because no rule of the server ends it when its spell ends.",
    "A press at a creature is not refused for an invulnerable, zone, vital or immunity state of its target that the server does not hold.",
    "An activate cast of a Channeled spell whose activate time is not the channel's maximum time is cast as a Normal spell, with one go after the cast time, because the times the client picks for the channel's gos are not settled.",
  ]
  |> list.map(fn(missing) { gap.Entry(area: "Casting", missing:) })
}

/// The plan's spell as a quest button's cast casts it: a castMethod 5 spell waits for the
/// client's answer without a cast time of its own, any other as planned.
pub fn shortcut_spell_of(spell spell: Spell) -> Spell {
  case interaction_of(spell:) {
    AwaitingAnswer -> activation_spell(spell:, cast_time_ms: 0)
    NoInteraction | AnswerSucceeded -> spell
  }
}

pub fn press_refused(
  press press: AimedPress,
  result result: cast_result.CastResult,
) -> Result(#(State, List(Effect)), Refusal) {
  Ok(
    #(press.cast, [
      cast_frame.refused(
        client_cast_id: press.client_cast_id,
        spell4_id: press.spell.spell4_id.value,
        result:,
      ),
    ]),
  )
}

pub fn press_unbuilt(
  press press: AimedPress,
  key key: Unbuilt,
  why why: String,
) -> Result(#(State, List(Effect)), Refusal) {
  not_built_refusal(
    cast: press.cast,
    client_cast_id: press.client_cast_id,
    spell4_id: press.spell.spell4_id.value,
    key:,
    result: cast_result.IllegalSpellCast,
    why:,
  )
}

fn press_at_player_unbuilt(
  press press: AimedPress,
  why why: String,
) -> Result(#(State, List(Effect)), Refusal) {
  press_unbuilt(
    press:,
    key: UnbuiltPlayerTarget(spell4_id: press.spell.spell4_id.value),
    why:,
  )
}

/// The caster itself: refused 32 unless the spell's flags let it be its own primary
/// target, and then it reaches the client's player faction test, which is not built.
pub fn aimed_at_the_caster(
  press press: AimedPress,
) -> Result(#(State, List(Effect)), Refusal) {
  case spell_effect.has_flag(flags: press.aim.mechanics_flags, bit: 2) {
    False ->
      press_refused(press:, result: cast_result.CasterCannotBePrimaryTarget)
    True ->
      press_at_player_unbuilt(
        press:,
        why: "names the caster itself, which the client's player faction test judges",
      )
  }
}

/// Another player's unit: a spell that refuses a player refuses every player (the
/// client's 106, 108 and 102 all refuse, and the connection holds no player's life or
/// combat to tell which); a spell that tests life or combat, or reaches the player
/// faction test, is not built.
pub fn aimed_at_a_player(
  press press: AimedPress,
) -> Result(#(State, List(Effect)), Refusal) {
  let tests_life_or_combat =
    press.spell.target_death != spell_plan.AliveOrDead
    || press.aim.target_combat == shortcut_spell.OutOfCombatOnly
  case
    spell_effect.has_flag(flags: press.aim.valid_targets, bit: 1),
    tests_life_or_combat
  {
    True, _ -> press_refused(press:, result: cast_result.TargetCannotBePlayer)
    False, True ->
      press_at_player_unbuilt(
        press:,
        why: "names another player, whose life and combat the connection does not hold",
      )
    False, False ->
      case press.aim.cast_group_id {
        0 ->
          press_at_player_unbuilt(
            press:,
            why: "names another player, who reaches the client's player faction test",
          )
        _ ->
          press_at_player_unbuilt(
            press:,
            why: "names another player and a cast group, which tests a player by its faction and race",
          )
      }
  }
}

/// The client's 106 and 107 for the target's life, then its 108 for combat.
pub fn life_and_combat_refusal(
  press press: AimedPress,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Option(cast_result.CastResult) {
  case press.spell.target_death, alive {
    spell_plan.CannotBeDead, False -> Some(cast_result.TargetCannotBeDead)
    spell_plan.MustBeDead, True -> Some(cast_result.TargetMustBeDead)
    spell_plan.CannotBeDead, True
    | spell_plan.MustBeDead, False
    | spell_plan.AliveOrDead, _
    ->
      case press.aim.target_combat, in_combat {
        shortcut_spell.OutOfCombatOnly, True ->
          Some(cast_result.TargetCannotBeInCombat)
        shortcut_spell.OutOfCombatOnly, False
        | shortcut_spell.CombatAllowed, _
        -> None
      }
  }
}

/// The client's crowd-control check of the target (`0x1403b2240`): a state the unit holds
/// that the spell's target mask names refuses the press with that state's target result,
/// after the target's life and combat and before the cast group and the range.
pub fn target_held(
  press press: AimedPress,
  otherwise otherwise: fn() -> Result(#(State, List(Effect)), Refusal),
) -> Result(#(State, List(Effect)), Refusal) {
  case
    crowd_control.first_masked(
      mask: press.spell.target_cc_mask,
      held: press.held,
    )
  {
    Ok(state) ->
      press_refused(
        press:,
        result: cast_result.from_value(crowd_control.target_result(state:)),
      )
    Error(Nil) -> otherwise()
  }
}

/// The target's unit-state check, before its life and combat as the client's invulnerability
/// result comes first among the target checks (`0x1403b2240`): a hostile press at a creature
/// that the picture shows holding an `Invulnerable` state is refused with 306, and a
/// beneficial press at one holding an `ImmuneToBeneficial` state with 308
/// (genesis_prime/game/unit_state `cast_refusal`). A press is beneficial by the target
/// mechanics flag bit 0 of its aim (`Spell4TargetMechanics.flags`), a server guess; any other
/// press goes on to `otherwise`. A picture that lags is safe: the creature decides the strike.
pub fn unit_state_refusal(
  press press: AimedPress,
  otherwise otherwise: fn() -> Result(#(State, List(Effect)), Refusal),
) -> Result(#(State, List(Effect)), Refusal) {
  case
    unit_state.cast_refusal(
      held: press.unit_states,
      beneficial: int.bitwise_and(press.aim.mechanics_flags, 1) == 1,
    )
  {
    Some(result) -> press_refused(press:, result:)
    None -> otherwise()
  }
}

/// The subject of the prerequisites a use of a creature checks: the caster, with the
/// creature's unit as the second unit and its checklist index as the unit's 0x262
/// carried it, standing nowhere (type 108 reads no arc of a use). The activate pick and
/// the creature's link to an objective check their prerequisites for it.
pub fn subject_for_use(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
  checklist_index checklist_index: Int,
) -> prerequisite.Subject {
  prerequisite.counting(
    subject: prerequisite.Subject(
      ..cast_tick.subject_of(cast:, caster:),
      second_unit: Some(unit_id),
      positions: prerequisite.NotPlaced,
    ),
    checklist_index:,
  )
}

/// The result `0x1403b2240` gives first for an activate cast at a creature: 106 or 107 when
/// the target's life is not the one its Spell4 target row allows, then the target result of
/// the first state the creature holds that the spell's target mask names. `None` when the
/// target's life and states let the cast go on to its cast group and range.
pub fn target_state_refusal(
  spell spell: Spell,
  alive alive: Bool,
  held held: List(CrowdControlState),
) -> Option(cast_result.CastResult) {
  case spell.target_death, alive {
    spell_plan.CannotBeDead, False -> Some(cast_result.TargetCannotBeDead)
    spell_plan.MustBeDead, True -> Some(cast_result.TargetMustBeDead)
    spell_plan.CannotBeDead, True
    | spell_plan.MustBeDead, False
    | spell_plan.AliveOrDead, _
    ->
      crowd_control.first_masked(mask: spell.target_cc_mask, held:)
      |> result.map(fn(state) {
        cast_result.from_value(crowd_control.target_result(state:))
      })
      |> option.from_result
  }
}

/// What the client's interaction of a cast of the spell has to answer: a castMethod 5
/// spell waits for it.
pub fn interaction_of(spell spell: Spell) -> Interaction {
  use <- bool.guard(
    when: spell.method == spell_plan.ClientSideInteraction,
    return: AwaitingAnswer,
  )
  NoInteraction
}

/// The plan's spell as an activate cast casts it, with the cast time the client takes for
/// it: the creature's `activateSpellCastTime` when the creature lists the spell and it is
/// not 0, else the spell's own castTime (`0x1407a1680`, `0x14054e340`, GetActivateCastTime;
/// `activate.cast_time_for`). A Normal spell, and a spell of any other
/// built method, goes once after that time with the cast bar shown, whatever its phases or
/// channel are. A Channeled spell whose activate time is its channelMaxTime keeps its
/// channel: the client replaces only the cast's duration and keeps the go count of the
/// channel (`0x14053d1f0.activate_channel`, `cast.channel_sequence`), so its gos and its
/// finish are the channel's. A castMethod 5 spell casts the same way as a Normal one, its bar
/// shown only when that time is not 0 (`opcode.0x7ff.csi_cast_bar`); its go also waits for
/// the client's answer (`cast.asked`). A spell whose method is not built is left as it is, so
/// the verdict refuses it.
///
/// A Channeled spell whose activate time is not its channelMaxTime (one whose own
/// castTime is 0 with no creature time, or a creature time other than the channel's) is
/// cast as a Normal spell: the client keeps its go count and the times the server picks
/// for them are not settled.
pub fn activation_spell(
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
) -> Spell {
  let interaction = spell.method == spell_plan.ClientSideInteraction
  use <- bool.guard(
    when: !cast_cost.is_built(spell.method) && !interaction,
    return: spell,
  )
  let cast_time_ms = case cast_time_ms {
    0 -> spell.cast_time_ms
    creature_time -> creature_time
  }
  case spell.channel {
    Some(channel)
      if spell.method == spell_plan.Channeled
      && cast_time_ms == channel.max_time_ms
    ->
      spell_plan.Spell(
        ..spell,
        cast_time_ms:,
        cast_bar: spell_plan.ShowsCastBar,
        phase_delays_ms: [],
        stages: [],
      )
    Some(_) | None ->
      spell_plan.Spell(
        ..spell,
        method: spell_plan.Normal,
        cast_time_ms:,
        cast_bar: case interaction && cast_time_ms == 0 {
          True -> spell_plan.HidesCastBar
          False -> spell_plan.ShowsCastBar
        },
        phase_delays_ms: [],
        channel: None,
        stages: [],
      )
  }
}

/// The log of the rows an activate cast drops, the first time for the spell, one line for
/// the RavelSignal rows, one for the DespawnUnit rows and one for the UnitStateSet rows: the
/// server has no script to start for the first, and the activate cast strikes no unit, so
/// there is no creature for the second to remove or the third to hold a state on
/// (`activate.activate_rows_of`).
pub fn rows_dropped(
  cast cast: State,
  spell4_id spell4_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  dropped dropped: activate.Dropped,
) -> #(State, List(Effect)) {
  let #(cast, signals) =
    dropped_once(
      cast:,
      key: DroppedSignals(spell4_id:),
      spell4_id:,
      unit_id:,
      creature_id:,
      kind: "RavelSignal",
      effect_ids: dropped.signals,
      why: "the server has no script to start for them",
    )
  let #(cast, despawns) =
    dropped_once(
      cast:,
      key: DroppedDespawns(spell4_id:),
      spell4_id:,
      unit_id:,
      creature_id:,
      kind: "DespawnUnit",
      effect_ids: dropped.despawns,
      why: "the activate cast strikes no unit for them to remove",
    )
  let #(cast, unit_states) =
    dropped_once(
      cast:,
      key: DroppedUnitStates(spell4_id:),
      spell4_id:,
      unit_id:,
      creature_id:,
      kind: "UnitStateSet",
      effect_ids: dropped.unit_states,
      why: "the activate cast strikes no unit for them to hold a state on",
    )
  #(cast, list.flatten([signals, despawns, unit_states]))
}

/// The log of the `effect_ids` an activate cast drops, once for the `key`.
fn dropped_once(
  cast cast: State,
  key key: Unbuilt,
  spell4_id spell4_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  kind kind: String,
  effect_ids effect_ids: List(Spell4EffectsId),
  why why: String,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: effect_ids == [] || set.contains(cast.logged, key),
    return: #(cast, []),
  )
  #(State(..cast, logged: set.insert(cast.logged, key)), [
    Log(
      level: LogWarning,
      text: "the activate cast of Spell4 "
        <> int.to_string(spell4_id)
        <> " at unit "
        <> int.to_string(unit_id)
        <> " (Creature2 "
        <> int.to_string(creature_id)
        <> ") drops the "
        <> kind
        <> " effects "
        <> string.join(
        list.map(effect_ids, fn(effect_id) { int.to_string(effect_id.value) }),
        ", ",
      )
        <> ": "
        <> why,
    ),
  ])
}

/// The log of the crowd-control rows the plan drops from a spell (`Spell.dropped_controls`),
/// the first time a cast of the spell starts: each holds a state on another unit until
/// removed, which no rule of the server ends when the spell ends, so the cast lands none
/// of them.
pub fn controls_dropped(
  cast cast: State,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let key = DroppedControls(spell4_id: spell.spell4_id.value)
  case spell.dropped_controls == [] || set.contains(cast.logged, key) {
    True -> #(cast, [])
    False -> #(State(..cast, logged: set.insert(cast.logged, key)), [
      Log(
        level: LogWarning,
        text: "the cast of Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> " drops the crowd-control effects "
          <> string.join(
          list.map(spell.dropped_controls, fn(effect_id) {
            int.to_string(effect_id.value)
          }),
          ", ",
        )
          <> ", each a state on another unit held until removed, which the server does not end with its spell",
      ),
    ])
  }
}

/// A right-click refused because the server does not build what the cast needs: the
/// refusal, with a log the first time for `key`.
pub fn not_built_refusal(
  cast cast: State,
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  key key: Unbuilt,
  result result: cast_result.CastResult,
  why why: String,
) -> Result(#(State, List(Effect)), Refusal) {
  let refusal = cast_frame.refused(client_cast_id:, spell4_id:, result:)
  let what = case key {
    UnbuiltShortcut(..) | UnreadShortcutPick(..) | UnbuiltPlayerTarget(..) ->
      "the shortcut cast of Spell4 "
    UnbuiltItemSpell(..) | UnreadItemPrerequisite(..) ->
      "the use of an item whose spell is Spell4 "
    UnbuiltSpell(..)
    | UnreadPrerequisite(..)
    | UnreadLinkPrerequisite(..)
    | DroppedSignals(..)
    | DroppedDespawns(..)
    | DroppedUnitStates(..)
    | DroppedControls(..) -> "the activate cast of Spell4 "
  }
  case set.contains(cast.logged, key) {
    True -> Ok(#(cast, [refusal]))
    False ->
      Ok(
        #(State(..cast, logged: set.insert(cast.logged, key)), [
          Log(
            level: LogWarning,
            text: what
              <> int.to_string(spell4_id)
              <> " "
              <> why
              <> ": it is refused with "
              <> int.to_string(cast_result.to_value(result)),
          ),
          refusal,
        ]),
      )
  }
}

/// The spell a press of the ability casts: under Spell Surge, the alternate the ability
/// names when the player's book holds it, else the ability itself. The client makes the
/// swap inside the press, before the threshold step, so an open threshold is looked for
/// under the swapped ability (`CastAbilityBagSpell` `0x14039a040`, `SpellslingerSurgedSpell`
/// `0x1405e7e50`, `IsSpellSurgeActive` `0x1405e7d10`, `GetAbilityBookSpell` `0x1403bad30`).
pub fn surged(
  cast cast: State,
  caster caster: Caster,
  ability ability: Spell,
) -> Spell {
  case ability.alternate {
    Some(alternate) ->
      case
        list.contains(caster.book, alternate.spell4_base_id)
        && list.any(
          cast_tick.holds_on(cast:, unit_id: caster.unit_id),
          fn(hold) { hold.spell4_id == caster.surge_spell },
        )
      {
        True -> alternate
        False -> ability
      }
    None -> ability
  }
}

/// Whether the held key is the ability's own or the alternate it is swapped for.
fn is_held(held held: Spell, ability ability: Spell) -> Bool {
  held.spell4_id == ability.spell4_id
  || option.map(held.alternate, fn(alternate) { alternate.spell4_id })
  == Some(ability.spell4_id)
}

/// The ability the player holds at the bag index, as the plans have it.
pub fn ability_at(
  caster caster: Caster,
  plans plans: Plans,
  bag_index bag_index: Int,
) -> Result(Spell, Nil) {
  list.drop(caster.abilities, bag_index)
  |> list.first
  |> result.try(fn(base) { spell_plan.in_plans(plans:, base:) })
}

/// The ability becomes the one held: a second key down of the ability already held
/// is the same hold, and the newest ability's key replaces the held one, whose
/// cast under way ends by itself (the server's choice: the client sends each key
/// its own key up, and gives no way to hold two). Its first cast is made by
/// `cast.continued`, once the caster is free.
pub fn key_down(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id -> #(
      cast,
      [],
    )
    Some(_) | None -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(
        State(
          ..cast,
          holding: Some(Holding(ability:, repeat_timer: None, last_cast: None)),
        ),
        cancels,
      )
    }
  }
}

/// No ability is held: the timer that waits to repeat is cancelled.
pub fn stop_holding(cast cast: State) -> #(State, List(Effect)) {
  case cast.holding {
    None -> #(cast, [])
    Some(Holding(repeat_timer:, ..)) -> {
      let #(cast, cancels) = case repeat_timer {
        Some(timer) -> #(
          State(..cast, timers: dict.delete(cast.timers, timer)),
          [CancelTimer(timer:)],
        )
        None -> #(cast, [])
      }
      #(State(..cast, holding: None), cancels)
    }
  }
}

/// The timer of the held ability's repeat fired: it waits no longer, unless the
/// hold ended or moved on to another timer.
pub fn repeat_fired(cast cast: State, timer timer: TimerId) -> State {
  State(
    ..cast,
    holding: option.map(cast.holding, fn(holding) {
      case holding.repeat_timer == Some(timer) {
        True -> Holding(..holding, repeat_timer: None)
        False -> holding
      }
    }),
  )
}

/// A held RapidTap ability whose threshold has no stage at its index: refused, as
/// a 0x9a press is, and the hold ends.
pub fn no_stage_left(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_holding(cast:)
  #(
    cast,
    list.append(cancels, [
      cast_frame.refused_unknown(
        client_cast_id: 0,
        spell4_id: ability.spell4_id.value,
      ),
    ]),
  )
}

/// How long a held ability waits before it casts again: until the global cooldown
/// its last cast started, the spell's own cooldown and its cooldown groups have all ended, whether or
/// not the global cooldown would refuse the spell (the server's choice,
/// `cast.hold_repeat`). Every level-1 ability and stage starts a global cooldown or
/// has a cooldown of its own, so a repeat is never at once; a later ability with
/// neither would recast as soon as its cast ended.
pub fn cooldown_wait_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> Int {
  let left = cast_cost.cooldowns_left(cast:, spell:, now_ms:)
  let global_left =
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
    |> option.unwrap(0)
  int.max(global_left, int.max(left.own_ms, left.group_ms))
}

/// The open threshold a press finds, as the client finds it: the one whose second spell
/// is the swapped ability, else the one keyed by the swapped ability
/// (`ResolveThresholdSpell` `0x1403bfd60`, `FindThresholdBySecondSpell` `0x1403c0190`).
/// A charge opened under Spell Surge is found when Surge has ended by its second spell,
/// the bag ability the 0x816 named.
pub fn threshold_of(
  cast cast: State,
  ability ability: Spell,
) -> Result(Threshold, Nil) {
  case
    list.find(dict.values(cast.thresholds), fn(threshold) {
      threshold.bag_spell == ability.spell4_id
    })
  {
    Ok(threshold) -> Ok(threshold)
    Error(Nil) -> dict.get(cast.thresholds, ability.spell4_id.value)
  }
}

/// What a press of the ability casts: through its open threshold the stage at the
/// threshold's index, the ability's own spell at -1, and none past the last stage
/// (`0x1403bfd60`); with no threshold open, the ability's own spell, or for an ability
/// with no threshold time the spell of the first Proxy its caster passes
/// (`ResolveProxyByCasterApply` `0x1403d3520`, fact `cast.proxy_press`).
pub fn resolved(
  cast cast: State,
  caster caster: Caster,
  bag_spell bag_spell: Spell4Id,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case threshold_of(cast:, ability:), ability.press_proxies {
    Error(Nil), [_, ..] -> {
      let #(proxy, logs) =
        first_passing(
          proxies: ability.press_proxies,
          subject: cast_tick.subject_of(cast:, caster:),
          logs: [],
        )
      Ok(case proxy {
        Some(spell) ->
          Resolution(
            spell:,
            ability:,
            bag_spell:,
            stage: None,
            proxied: True,
            logs:,
          )
        None ->
          Resolution(
            spell: ability,
            ability:,
            bag_spell:,
            stage: None,
            proxied: False,
            logs:,
          )
      })
    }
    Error(Nil), [] | Ok(_), _ ->
      resolved_by_threshold(cast:, bag_spell:, ability:)
  }
}

/// The spell of the first Proxy of a press, in row order, whose caster apply prerequisite
/// the subject passes, and a debug line for each gate the server cannot decide, which
/// does not pass. A press draws no roll: a gate that needs one is refused at load.
fn first_passing(
  proxies proxies: List(spell_plan.PressProxy),
  subject subject: prerequisite.Subject,
  logs logs: List(Effect),
) -> #(Option(Spell), List(Effect)) {
  case proxies {
    [] -> #(None, list.reverse(logs))
    [proxy, ..rest] ->
      case
        cast_gate.gates_gate(
          gates: [proxy.gate],
          subject:,
          rolls: [],
          what: "the Proxy effect " <> int.to_string(proxy.effect_id.value),
          outcome: "so a press does not cast it",
        )
      {
        #(Starts, _) -> #(Some(proxy.spell), list.reverse(logs))
        #(GateFails, _) -> first_passing(proxies: rest, subject:, logs:)
        #(CannotTell(why:), _) ->
          first_passing(proxies: rest, subject:, logs: [
            Log(level: LogDebug, text: why),
            ..logs
          ])
      }
  }
}

/// What a press of the ability casts when only its threshold decides: the stage of its
/// open threshold, else its own spell.
pub fn resolved_by_threshold(
  cast cast: State,
  bag_spell bag_spell: Spell4Id,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case threshold_of(cast:, ability:) {
    Error(Nil) ->
      Ok(
        Resolution(
          spell: ability,
          ability:,
          bag_spell:,
          stage: None,
          proxied: False,
          logs: [],
        ),
      )
    Ok(threshold) ->
      spell_plan.stage_at(spell: threshold.ability, index: threshold.index)
      |> result.map(fn(spell) {
        Resolution(
          spell:,
          ability: threshold.ability,
          bag_spell:,
          stage: case threshold.index < 0 {
            True -> None
            False -> Some(threshold.index)
          },
          proxied: False,
          logs: [],
        )
      })
  }
}

/// The ability's hold has started the cast `cast_id`, so its cooldowns are waited
/// for from now on and no longer refused.
pub fn hold_started(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> State {
  case cast.holding {
    Some(Holding(ability: held, ..) as holding) ->
      case is_held(held:, ability:) {
        True ->
          State(
            ..cast,
            holding: Some(Holding(..holding, last_cast: Some(cast_id))),
          )
        False -> cast
      }
    None -> cast
  }
}

/// A refusal of a press written; a refused held key stops its hold, which the
/// client does not know (it shows the failure and goes on holding).
pub fn refused_hold(
  cast cast: State,
  client_cast_id client_cast_id: Option(Int),
  ability ability: Spell,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  case client_cast_id, cast.holding {
    None, Some(Holding(ability: held, ..)) ->
      case is_held(held:, ability:) {
        True -> {
          let #(cast, cancels) = stop_holding(cast:)
          #(cast, list.append(cancels, effects))
        }
        False -> #(cast, effects)
      }
    Some(_), _ | None, None -> #(cast, effects)
  }
}

/// Whether the press is the release of a ChargeRelease threshold: the client has
/// resolved it through the open threshold before any caster check, so a held press
/// does not refuse it (`0x1403bfd60`).
pub fn is_release(resolution resolution: Resolution) -> Bool {
  case resolution.stage {
    Some(_) -> resolution.ability.method == spell_plan.ChargeRelease
    None -> False
  }
}

pub fn verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  now_ms now_ms: Int,
  is_release is_release: Bool,
  target_subject target_subject: Option(prerequisite.Subject),
) -> Verdict {
  let refused_life = spell_plan.refused_life(spell:, dead: caster.dead)
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesDead),
    return: Refuse(result: cast_result.CasterCannotBeDead),
  )
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesLiving),
    return: Refuse(result: cast_result.from_value(
      cast_state.caster_must_be_dead,
    )),
  )
  use <- bool.guard(
    when: option.is_some(cast.held) && !is_release,
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(
    when: !cast_cost.is_built(spell.method),
    return: NotBuilt(
      result: cast_result.IllegalSpellCast,
      why: "is not cast by a method that is built",
    ),
  )
  use <- bool.guard(
    when: cast_cost.casting(cast) && !spell.ignores_casting,
    return: case time_left_of_current_cast(cast:, now_ms:) {
      Some(left_ms) if left_ms <= cast_state.queue_window_ms -> HoldForCast
      Some(_) | None -> Refuse(result: cast_result.SpellAlreadyCasting)
    },
  )
  use <- cast_cost.refuse_when(cast_cost.restricted(cast:, spell:))
  let left = cast_cost.cooldowns_left(cast:, spell:, now_ms:)
  use <- cast_cost.refuse_when(cast_cost.cooldown_refusal(
    left:,
    window_ms: cast_state.queue_window_ms,
  ))
  case
    cast_tick.requirement_refusal(cast:, caster:, spell:),
    cast_cost.costs_paid(
      costs: spell.costs,
      resources: cast_cost.unreserved(cast:, resources: caster.resources),
    )
  {
    Some(refusal), _ -> refusal
    None, Error(Unpaid(result:)) ->
      Refuse(result: cast_result.from_value(result))
    None, Error(Unheld(result:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost of a vital the server does not hold",
      )
    None, Error(UnreadSpend(result:, emm_id:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost spent by the EMM id "
          <> int.to_string(emm_id)
          <> ", which the server does not read",
      )
    None, Ok(paid) ->
      case
        cast_cost.lacks_the_weapon(spell:, caster:),
        cast_cost.longest_left_ms(left:)
      {
        True, _ -> Refuse(result: cast_result.WeaponSlot)
        False, 0 ->
          cast_tick.cast_conditions(
            cast:,
            caster:,
            spell:,
            paid:,
            target_subject:,
          )
        False, wait_ms -> Hold(wait_ms:)
      }
  }
}

/// The time the caster's current cast has left, in milliseconds, from its start
/// and its duration (`cast.press_queue`); none when it has no end of its own,
/// such as a charge held until its release, or an interaction whose bar has run and
/// whose answer is still out.
fn time_left_of_current_cast(
  cast cast: State,
  now_ms now_ms: Int,
) -> Option(Int) {
  use cast_id <- option.then(cast.current)
  use live <- option.then(dict.get(cast.casts, cast_id) |> option.from_result)
  let bar_running = go_waits(cast:, cast_id:)
  case live.interaction {
    AwaitingAnswer if !bar_running -> None
    AwaitingAnswer | NoInteraction | AnswerSucceeded ->
      spell_plan.duration_ms(spell: live.spell)
      |> option.map(fn(duration_ms) {
        int.max(0, live.started_ms + duration_ms - now_ms)
      })
  }
}

/// Whether a live cast waits for the answer of its interaction, with or without a bar.
pub fn answer_is_out(cast cast: State) -> Bool {
  list.any(dict.values(cast.casts), fn(live) {
    case live.interaction {
      AwaitingAnswer -> True
      NoInteraction | AnswerSucceeded -> False
    }
  })
}

/// Whether the cast's go timer is still to fire: the cast time has not run.
fn go_waits(cast cast: State, cast_id cast_id: Int) -> Bool {
  list.any(dict.values(cast.timers), fn(due) { due == Go(cast_id:, phase: 0) })
}

/// The hold whose last cast is `cast_id` ends.
pub fn stop_holding_cast(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(last_cast: Some(last), ..)) if last == cast_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
}

/// The stealth sources held by casts other than `cast_id`: a cast's own sources are
/// never ended by its own stealth change.
pub fn other_casts_sources(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(unit_properties.Source) {
  list.filter(dict.keys(cast.stealth), fn(source) { source.cast_id != cast_id })
}

/// The go and finish timers a live cast waits on, cancelled.
pub fn stop_pending(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      Go(cast_id: waiting, ..) | Finish(cast_id: waiting) -> waiting == cast_id
      StartChild(..)
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
      | QuestAdvanceDue(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> False
    }
  })
}

/// The open threshold whose base cast is `cast_id`: the 32-bit value the 0x816
/// carried, which the client names in a 0x801 (`opcode.0x816`).
pub fn open_charge_of(
  cast cast: State,
  cast_id cast_id: Int,
) -> Option(Threshold) {
  dict.values(cast.thresholds)
  |> list.find(fn(threshold) {
    threshold.cast_id == cast_id
    && threshold.ability.method == spell_plan.ChargeRelease
  })
  |> option.from_result
}

/// Whether the finish of a cast that is a stage closes its ability's threshold: a
/// release always does, a tap only when it is the last stage.
pub fn closes_threshold(role role: Role) -> Bool {
  case role {
    Child(..) | Base(..) | Passive | Activation(..) | Shortcut(..) -> False
    Stage(ability:, index:) ->
      case ability.method {
        spell_plan.ChargeRelease -> True
        spell_plan.RapidTap -> index + 1 >= list.length(ability.stages)
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> False
      }
  }
}
