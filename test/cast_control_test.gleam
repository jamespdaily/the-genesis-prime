//// The cast rule (`genesis_prime/game/cast`) for the crowd-control states a go landed:
//// what the go lists, the node the caster's cast keeps for the state's life, and the
//// caster's combat log. The creature's answer is given as it comes back
//// (`cast.Hit`'s `controls`), the spell is planted and the clock is driven. Expected
//// values come from these places:
//// - Kick's CCStateSet row 140382 (`Spell4Effects.140382`): delayTime 166 ms,
////   durationTime 3000 ms, a Knockdown; the creature holds it from its arrival until
////   delay plus duration (`creature_control`), which is the end time the answer carries.
//// - `cc_state.instance_id`: the go's effect info for the state names the instance id
////   the strike gave, which the creature's 0x87f carries too.
//// - `cc_state.end` and `cast.target_node_end`: the client ends no node on time, so the
////   cast's 0x7fe waits until the node's life is over.
//// - `Unit.CodeEnumCCState` 27 (Ability Restriction) and `CheckSpellCCConditions`
////   (`0x1403b2c40`, called by `CheckCastCaster`, `0x1403afb10`, at `0x1403affa2`): a
////   caster that holds state 27 is refused a spell whose Spell4CCConditions mask has bit 27,
////   with the result 302 (Caster_CannotBe_AbilityRestriction); the check comes after the
////   test for a cast in progress (13) and before the cooldowns (15). Kick's caster row is
////   4 (mask 218960747, bit 27 set), Crush's child 42297's is 2 (mask 0)
////   (`Spell4.58591`, `Spell4.42297`, `Spell4CCConditions.4`, `Spell4CCConditions.2`).
//// - `opcode.0x247.cc_state`: combat log type 1 names the state, whether it was removed,
////   the Interrupt Armor it hit, the result and the cast data (caster, target, Spell4,
////   combat result). The coordinator's decision on the issue: the caster writes it with
////   the go (removed 0) and when the state ends (removed 1), and none when the unit left
////   its sight first (`cast.unit_removed`).

import cast_support as support
import crowd_control_support
import genesis_prime/client_connection
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/crowd_control
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{type Spell, Spell}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_modify_interrupt_armor.{
  CombatLogModifyInterruptArmor,
}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_result
import genesis_prime/message/crowd_control_state.{
  type CrowdControlState, AbilityRestriction, Knockdown, Root, Silence, Stun,
  Tether,
}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_failed
import genesis_prime/message/spell_go
import genesis_prime/message/spell_targets_removed
import genesis_prime/message/unit_cc_state_applied
import genesis_prime/message/unit_cc_state_ended.{
  type UnitCcStateEnded, UnitCcStateEnded,
}
import genesis_prime/message/unit_tether_anchor
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import prerequisite_support

/// Kick's spell, base 3, planted with no effect of its own: what a go lists comes from
/// the creature's answer.
fn kick_plans() -> spell_plan.Plans {
  support.with_spells(plans: support.plans(), spells: [
    support.child(spell4_id: 58_591, base: 3),
  ])
}

const bag_of_base_3 = 11

/// Kick pressed at 1000 whose round closed at `go_ms` having struck unit 20, which took
/// the Knockdown until `ends_at_ms`.
fn kicked(
  go_ms go_ms: Int,
  ends_at_ms ends_at_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  support.answered_by(state:, effects:, at: go_ms, struck: [
    cast.Hit(
      unit_id: 20,
      unit: cast.HitCreature(life: 1, struck_at_ms: 0),
      descriptions: [],
      controls: [
        crowd_control_support.kick_landed(ends_at_ms:),
      ],
      armor_removed: 0,
    ),
  ])
}

fn logged(
  effects effects: List(Effect),
) -> List(combat_log_entry.CombatLogEntry) {
  list.map(
    support.frames_of(message_id: combat_log.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = combat_log.decode(frame.body)
        as "a 0x247 the rule wrote decodes"
      decoded.entry
    },
  )
}

fn entry(removed removed: Int) -> combat_log_entry.CombatLogEntry {
  combat_log_entry.CcState(CombatLogCcState(
    state: Knockdown,
    removed:,
    interrupt_armor_hit: 0,
    result: crowd_control_result.Ok,
    diminishing_returns_id: 0,
    caster_unit_id: 7,
    target_unit_id: 20,
    spell4_id: 58_591,
    combat_result: combat_result.Hit,
  ))
}

pub fn a_go_lists_a_state_the_creature_took_with_the_instance_id_its_strike_gave_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 20
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 140_382,
        instance_id: 28_673,
        delay_ms: 166,
        field_4: 0,
        result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
      ),
    ]
    as "Spell4Effects.140382's delay 166 and the instance id the strike gave, which the 0x87f carries too (cc_state.instance_id)"
}

pub fn a_creature_that_took_no_state_has_no_effect_listed_for_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_by(state:, effects:, at: 1000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [],
        armor_removed: 0,
      ),
    ])
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.effects == []
    as "armor above 0 or a dead creature answers Landed with no state: nothing is listed"
  assert logged(effects:) == [] as "and nothing is logged"
}

pub fn the_cast_lingers_until_the_states_own_end_and_then_sends_its_0x7fe_test() -> Nil {
  use <- owned_test.run(5000)
  // The round waited 900 ms for a slow creature: the go is at 1900 and the creature
  // holds the state until 4166 (its arrival at 1000, plus 166, plus 3000).
  let #(state, effects) = kicked(go_ms: 1900, ends_at_ms: 4166)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the cast's 0x7fe waits for the node (cast.target_node_end)"
  let assert [frame, ..] =
    support.frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "the press was confirmed"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  let due =
    list.filter(support.started_timers(effects:), fn(started) {
      started.1 == 2266
    })
  assert list.length(due) == 2
    as "the node and the state's end entry both end at the creature's 4166, 2266 ms after the go and not 3166 ms after it"
  let finished =
    list.flat_map(due, fn(started) {
      let #(_, effects) = support.fired(state:, timer: started.0, at: 4166)
      support.finished_ids(support.writes(effects:))
    })
  assert finished == [confirmed.server_cast_id]
    as "when the node's life is over the cast sends its 0x7fe"
}

pub fn the_caster_logs_the_state_with_its_go_and_again_when_it_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  assert logged(effects:) == [entry(removed: 0)]
    as "type 1, removed 0, with the go: the caster, the creature and Kick (opcode.0x247.cc_state)"
  let ends =
    list.filter(support.started_timers(effects:), fn(started) {
      started.1 == 3166
    })
  assert list.length(ends) == 2
    as "a timer for the node's end and one for the state's end entry, both at the creature's end"
  let ended =
    list.flat_map(ends, fn(started) {
      let #(_, effects) = support.fired(state:, timer: started.0, at: 4166)
      logged(effects:)
    })
  assert ended == [entry(removed: 1)]
    as "exactly one of the two timers writes the end entry: type 1, removed 1"
}

pub fn a_unit_that_left_the_casters_sight_gets_no_end_entry_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  let ends =
    list.map(
      list.filter(support.started_timers(effects:), fn(started) {
        started.1 == 3166
      }),
      fn(started) { started.0 },
    )
  let #(state, removed) =
    cast.unit_removed(cast: state, unit_id: 20, now_ms: 2000)
  assert list.any(support.cancelled_timers(effects: removed), fn(timer) {
    list.contains(ends, timer)
  })
    as "the client dropped the unit with its 0x355, so the end entry's timer is cancelled"
  let ended =
    list.flat_map(ends, fn(timer) {
      let #(_, effects) = support.fired(state:, timer:, at: 4166)
      logged(effects:)
    })
  assert ended == [] as "and a timer that fires late writes nothing"
}

pub fn a_later_go_does_not_move_the_nodes_end_past_the_states_own_end_test() -> Nil {
  use <- owned_test.run(5000)
  // A Multiphase spell: its first go lands the Knockdown, held until 4000, and its
  // second go, at 2000, adds a Fluff effect of 100 ms. `lasting.given` arms the Fluff
  // effect again from the second go, but the state ends when the creature says.
  let phased =
    spell_plan.Spell(
      ..support.child(spell4_id: 58_591, base: 3),
      method: spell_plan.Multiphase,
      phase_delays_ms: [0, 1000],
      lasting: [
        spell_plan.Lasting(
          effect_id: Spell4EffectsId(9),
          phase_flags: 2,
          aim: spell_plan.AimsAtArea,
          row: lasting.LastingRow(
            delay_ms: 0,
            duration_ms: 100,
            until_removed: False,
          ),
          condition: spell_plan.Always,
          tag: spend.always,
        ),
      ],
    )
  let plans = support.with_spells(plans: support.plans(), spells: [phased])
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, first) =
    support.answered_by(state:, effects: pressed, at: 1000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [
          crowd_control_support.kick_landed(ends_at_ms: 4000),
        ],
        armor_removed: 0,
      ),
    ])
  let assert [#(go, 1000)] =
    list.filter(support.started_timers(effects: first), fn(started) {
      started.1 == 1000
    })
    as "the second go waits 1000 ms"
  let #(state, going) = support.fired_raw(state:, timer: go, at: 2000)
  let #(_, second) =
    support.answered_by(state:, effects: going, at: 2000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [],
        armor_removed: 0,
      ),
    ])
  let afters =
    list.map(support.started_timers(effects: second), fn(started) { started.1 })
  assert list.contains(afters, 2000)
    as "the node ends at the state's 4000, 2000 ms after the second go"
  assert !list.contains(afters, 3000)
    as "and not at 2000 + 3000, which re-arming the state as an effect would give"
}

// ---- Ability Restriction on the caster ----

/// Kick, the real ability at bag index 3 (`cast_support.abilities`).
const bag_of_kick = 3

const bag_of_base_1 = 8

/// A planted spell of base 3 whose go gives the caster Ability Restriction until its cast
/// ends, as the hoverboard's ride 85563 does with its CCStateSet 224967 (targetFlags 1,
/// flags 2, dataBits00 27); its caster persistence is the caster in combat.
fn restricting() -> Spell {
  restricting_by(row: restriction_row(duration_ms: 0, until_removed: True))
}

/// The state-27 row of a planted spell: no delay, `duration_ms` long, or until removed.
fn restriction_row(
  duration_ms duration_ms: Int,
  until_removed until_removed: Bool,
) -> crowd_control.Row {
  crowd_control.Row(
    state: AbilityRestriction,
    delay_ms: 0,
    duration_ms:,
    armor_removed: 0,
    until_removed:,
  )
}

/// The planted spell of base 3 and caster persistence in combat whose go gives the caster
/// the state `row` describes.
fn restricting_by(row row: crowd_control.Row) -> Spell {
  Spell(
    ..support.child(spell4_id: 7010, base: 3),
    caster_persistence: Some(
      prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
    ),
    controls: [
      spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(224_967),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row:,
        tag: spend.always,
      ),
    ],
  )
}

/// The planted spell whose state row ends `row_ms` after the go while a Fluff row of the
/// same spell keeps the cast's node on the caster for `node_ms`.
fn restricting_shorter_than_its_node(
  row_ms row_ms: Int,
  node_ms node_ms: Int,
) -> Spell {
  Spell(
    ..restricting_by(row: restriction_row(
      duration_ms: row_ms,
      until_removed: False,
    )),
    lasting: [
      spell_plan.Lasting(
        effect_id: Spell4EffectsId(224_968),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: node_ms,
          until_removed: False,
        ),
        condition: spell_plan.Always,
        tag: spend.always,
      ),
    ],
  )
}

/// A planted spell of base 1 with a cast bar and 1000 ms of cast time: its cast is the
/// caster's current cast until its go.
fn casting_for_a_second() -> Spell {
  Spell(
    ..support.child(spell4_id: 7011, base: 1),
    cast_time_ms: 1000,
    cast_bar: spell_plan.ShowsCastBar,
  )
}

/// Crush's child 42297, caster conditions row 2 (`Spell4.42297`): its mask is 0.
fn unmasked() -> Spell {
  Spell(..support.child(spell4_id: 42_297, base: 1), caster_cc_mask: 0)
}

fn fighting() -> cast.Caster {
  support.caster_in_combat(in_combat: True)
}

/// The state after the restricting spell is pressed at 1000 by a caster in combat, with
/// its effects.
fn restricted(plans plans: spell_plan.Plans) -> #(State, List(Effect)) {
  support.press_by(
    plans:,
    state: cast.new(),
    caster: fighting(),
    bag: 11,
    at: 1000,
  )
}

pub fn a_press_while_restricted_is_refused_with_302_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([restricting(), casting_for_a_second()])
  let #(state, first) =
    support.press_by(
      plans:,
      state: cast.new(),
      caster: fighting(),
      bag: bag_of_kick,
      at: 1000,
    )
  assert support.refusal_results(effects: first) == []
    as "Kick passes while the caster holds no state"
  let #(state, held) =
    support.press_by(plans:, state:, caster: fighting(), bag: 11, at: 2000)
  assert support.refusal_results(effects: held) == []
    as "the restricting spell's own conditions (caster row 0, no mask) let it through"
  let #(_, refused) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 3000,
    )
  assert support.refusals(effects: refused)
    == [cast_result.CasterCannotBeAbilityRestriction]
    as "Kick's caster row 4 masks state 27 (bit 27 of 218960747): refused 302, though its cooldown of 20000 ms from the go at 1000 has 18 s left, which alone would refuse 15: CheckSpellCCConditions comes before CheckSpellCooldowns (0x1403afb10)"
  // A cast in progress is refused first (0x1403afb10 tests it before the state).
  let #(state, _) =
    support.press_by(
      plans:,
      state: cast.new(),
      caster: fighting(),
      bag: 11,
      at: 1000,
    )
  let #(state, _) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 1500,
    )
  let #(_, casting) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 1600,
    )
  assert support.refusal_results(effects: casting) == [13]
    as "a cast of 1000 ms in progress (900 ms left, outside the queue window) is refused 13 Already_Casting, ahead of 302 (0x1403afb10)"
}

pub fn a_press_of_an_unmasked_spell_passes_while_restricted_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([restricting(), unmasked()])
  let #(state, _) = restricted(plans:)
  let #(_, effects) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.refusal_results(effects: effects) == []
    as "Spell4.42297's caster row 2 has ccStateMask 0: state 27 does not refuse it"
  let #(_, kick) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 2000,
    )
  assert support.refusals(effects: kick)
    == [cast_result.CasterCannotBeAbilityRestriction]
    as "while Kick, whose row masks bit 27, is refused: the state is held"
}

pub fn the_restriction_ends_with_0x880_when_its_cast_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([restricting()])
  let #(state, pressed) = restricted(plans:)
  let assert [applied] =
    support.frames_of(
      message_id: unit_cc_state_applied.message_id,
      effects: pressed,
    )
    as "the go shows the state once (opcode.0x87f)"
  let assert Ok(applied) = unit_cc_state_applied.decode(applied.body)
  let #(state, refused) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 2000,
    )
  assert support.refusals(effects: refused)
    == [cast_result.CasterCannotBeAbilityRestriction]
    as "the state is held until its cast ends"
  let #(state, ended) =
    cast.persisted(
      cast: state,
      caster: support.caster_in_combat(in_combat: False),
      now: support.at(ms: 3000),
    )
  let assert [ending] =
    support.frames_of(
      message_id: unit_cc_state_ended.message_id,
      effects: ended,
    )
    as "the cast ends with its persistence, and the state ends with one 0x880 (opcode.0x880)"
  assert list.filter(written_ids(effects: ended), fn(id) {
      id == spell_failed.message_id || id == unit_cc_state_ended.message_id
    })
    == [spell_failed.message_id, unit_cc_state_ended.message_id]
    as "the 0x7f9 that fails the cast comes first, then the state's 0x880"
  let assert Ok(ending) = unit_cc_state_ended.decode(ending.body)
  assert ending
    == UnitCcStateEnded(
      unit_id: 7,
      state: AbilityRestriction,
      cast_id: support.pressed_id(effects: pressed),
      instance_id: applied.instance_id,
      keeps_flag_4_entries: 0,
    )
    as "the caster, state 27, the cast and the instance id the 0x87f gave (cc_state.end)"
  let #(_, later) =
    support.press_by(
      plans:,
      state:,
      caster: support.caster_in_combat(in_combat: False),
      bag: bag_of_kick,
      at: 4000,
    )
  assert support.refusal_results(effects: later) == []
    as "the state is gone: Kick is no longer refused 302"
}

/// The message ids of what the effects write to the client, in order.
fn written_ids(effects effects: List(Effect)) -> List(Int) {
  list.map(support.writes(effects:), fn(frame) { frame.message_id })
}

/// The cast id and the instance id of the one 0x87f a press showed.
fn shown_state(effects effects: List(Effect)) -> #(Int, Int) {
  let assert [applied] =
    support.frames_of(message_id: unit_cc_state_applied.message_id, effects:)
    as "the go shows the state once (opcode.0x87f)"
  let assert Ok(applied) = unit_cc_state_applied.decode(applied.body)
  #(support.pressed_id(effects:), applied.instance_id)
}

/// The one 0x880 the effects hold, decoded.
fn ended_state(effects effects: List(Effect)) -> UnitCcStateEnded {
  let assert [ending] =
    support.frames_of(message_id: unit_cc_state_ended.message_id, effects:)
    as "the state ends with one 0x880 (opcode.0x880)"
  let assert Ok(ending) = unit_cc_state_ended.decode(ending.body)
  ending
}

pub fn a_timed_restriction_ends_with_its_row_before_its_node_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      restricting_shorter_than_its_node(row_ms: 1500, node_ms: 4000),
    ])
  let #(state, pressed) = restricted(plans:)
  let #(cast_id, instance_id) = shown_state(effects: pressed)
  let assert [#(row_end, 1500)] =
    list.filter(support.started_timers(effects: pressed), fn(started) {
      started.1 == 1500
    })
    as "the state's own timer waits its row's duration (the client's CCStateSet lifetime is delay plus duration, 0x1405d6880), apart from the node's 4000"
  let #(state, held) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 2000,
    )
  assert support.refusals(effects: held)
    == [cast_result.CasterCannotBeAbilityRestriction]
    as "before the row's end the state is held"
  let #(state, ended) =
    support.fired_raw_as(caster: fighting(), state:, timer: row_end, at: 2500)
  assert ended_state(effects: ended)
    == UnitCcStateEnded(
      unit_id: 7,
      state: AbilityRestriction,
      cast_id:,
      instance_id:,
      keeps_flag_4_entries: 0,
    )
    as "the row's end sends the 0x880 with the cast and the instance id the 0x87f gave, though the node lasts 1500 ms more (cc_state.end)"
  let #(state, after) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 3000,
    )
  assert support.refusal_results(effects: after) == []
    as "after the row's end Kick is accepted: the client dropped the state with the 0x880"
  let assert [#(node_end, 4000)] =
    list.filter(support.started_timers(effects: pressed), fn(started) {
      started.1 == 4000
    })
    as "the node ends 4000 ms after the go"
  let #(_, later) =
    support.fired_raw_as(caster: fighting(), state:, timer: node_end, at: 5000)
  assert support.frames_of(
      message_id: unit_cc_state_ended.message_id,
      effects: later,
    )
    == []
    as "the node's later end sends no second 0x880"
}

pub fn a_restriction_row_of_duration_0_without_flag_2_ends_at_its_go_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      restricting_by(row: restriction_row(duration_ms: 0, until_removed: False)),
    ])
  let #(state, pressed) = restricted(plans:)
  let #(cast_id, instance_id) = shown_state(effects: pressed)
  let assert [#(row_end, 0)] = support.started_timers(effects: pressed)
    as "the row lives its delay 0 plus its duration 0 (0x1405d6880), and the client never ends a state itself: the server's own timer of 0 ms does"
  let #(state, ended) =
    support.fired_raw_as(caster: fighting(), state:, timer: row_end, at: 1000)
  assert ended_state(effects: ended)
    == UnitCcStateEnded(
      unit_id: 7,
      state: AbilityRestriction,
      cast_id:,
      instance_id:,
      keeps_flag_4_entries: 0,
    )
    as "the state ends with its 0x880"
  let #(_, after) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 2000,
    )
  assert support.refusal_results(effects: after) == []
    as "Kick is accepted: the state is gone"
}

pub fn a_removal_that_ends_the_node_sends_one_0x880_after_its_0x811_and_cancels_the_rows_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let removing =
    Spell(..unmasked(), removes: [
      spell_plan.ForceRemove(
        effect_id: Spell4EffectsId(196_521),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        selector: lasting.Spell(Spell4Id(7010)),
        count: 1,
        condition: spell_plan.Always,
        tag: spend.always,
      ),
    ])
  let plans =
    support.plans_of([
      restricting_shorter_than_its_node(row_ms: 6000, node_ms: 8000),
      removing,
    ])
  let #(state, pressed) = restricted(plans:)
  let #(cast_id, instance_id) = shown_state(effects: pressed)
  let #(state, removal) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert list.filter(written_ids(effects: removal), fn(id) {
      id == spell_targets_removed.message_id
      || id == unit_cc_state_ended.message_id
    })
    == [spell_targets_removed.message_id, unit_cc_state_ended.message_id]
    as "the removal takes the cast's node off the caster with its 0x811, and the state ends with one 0x880 after it (opcode.0x811)"
  assert ended_state(effects: removal)
    == UnitCcStateEnded(
      unit_id: 7,
      state: AbilityRestriction,
      cast_id:,
      instance_id:,
      keeps_flag_4_entries: 0,
    )
    as "the caster, state 27, the cast and the instance id the 0x87f gave"
  assert support.timer_numbers(timers: support.cancelled_timers(
      effects: removal,
    ))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: pressed), fn(started) {
        started.0
      }),
    )
    as "the row's end and the node's end, the two timers the press started, are cancelled"
  let assert [#(row_end, 6000), ..] =
    list.sort(support.started_timers(effects: pressed), fn(first, second) {
      int.compare(first.1, second.1)
    })
  let #(_, stale) =
    support.fired_raw_as(caster: fighting(), state:, timer: row_end, at: 7000)
  assert support.writes(effects: stale) == []
    as "a delivery of the row's timer after the removal finds no state and writes nothing"
}

// ---- Every state on the caster ----

/// A planted spell of base 3 whose go gives the caster each state of `states` until its
/// cast ends: one CCStateSet row aimed at the caster for each, its own effect id.
fn holding(states states: List(CrowdControlState)) -> Spell {
  Spell(
    ..restricting(),
    controls: list.index_map(states, fn(state, index) {
      spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(224_967 + index),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: crowd_control.Row(
          state:,
          delay_ms: 0,
          duration_ms: 0,
          armor_removed: 0,
          until_removed: True,
        ),
        tag: spend.always,
      )
    }),
  )
}

/// A planted spell of base 1 whose caster conditions row has the mask `mask`.
fn masking(mask mask: Int) -> Spell {
  Spell(..support.child(spell4_id: 7012, base: 1), caster_cc_mask: mask)
}

/// Spell4CCConditions row 5's ccStateMask: bit 4 (Silence) among its bits.
const row_5_mask = 218_960_755

/// Spell4CCConditions row 6's ccStateMask: bits 2 (Root) and 27 (Ability Restriction)
/// among its bits.
const row_6_mask = 219_943_903

pub fn a_caster_holding_a_masked_state_is_refused_its_result_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([holding(states: [Silence]), masking(mask: row_5_mask)])
  let #(held, _) =
    support.press_by(
      plans: support.plans_of([masking(mask: row_5_mask)]),
      state: cast.new(),
      caster: fighting(),
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(_, free) =
    support.press_by(
      plans: support.plans_of([masking(mask: row_5_mask)]),
      state: held,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 3000,
    )
  assert support.refusal_results(effects: free) == []
    as "a caster holding no state is not refused by row 5"
  let #(state, _) = restricted(plans:)
  let #(_, refused) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.refusal_results(effects: refused) == [81]
    as "Silence is held and row 5's mask 218960755 has bit 4: Caster_CannotBe_Silenced (81), whose 0x7fc clears the client's global cooldown (CheckSpellCCConditions 0x1403b2c40, Spell4CCConditions.results)"
  let #(_, kick) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_kick,
      at: 2000,
    )
  assert support.refusal_results(effects: kick) == []
    as "Kick's caster row 4 (mask 218960747) has no bit 4: a held Silence does not refuse it"
}

pub fn the_lowest_held_state_gives_the_result_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      holding(states: [AbilityRestriction, Root]),
      masking(mask: row_6_mask),
    ])
  let #(state, _) = restricted(plans:)
  let #(_, refused) =
    support.press_by(
      plans:,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.refusal_results(effects: refused) == [77]
    as "row 6's mask has bits 2 and 27 and the caster holds Root (2) and Ability Restriction (27): the check takes the lowest bit first, Caster_CannotBe_Rooted (77), not 302 (0x1403b2c40's order)"
  let alone =
    support.plans_of([
      holding(states: [AbilityRestriction]),
      masking(mask: row_6_mask),
    ])
  let #(state, _) = restricted(plans: alone)
  let #(_, only) =
    support.press_by(
      plans: alone,
      state:,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.refusal_results(effects: only) == [302]
    as "Ability Restriction alone gives its own result, 302"
}

pub fn a_caster_aimed_state_of_any_kind_is_told_and_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let timed =
    Spell(
      ..restricting_by(row: crowd_control.Row(
        state: Stun,
        delay_ms: 500,
        duration_ms: 2000,
        armor_removed: 0,
        until_removed: False,
      )),
      lasting: restricting_shorter_than_its_node(row_ms: 0, node_ms: 4000).lasting,
    )
  let plans = support.plans_of([timed])
  let #(state, pressed) = restricted(plans:)
  let applied = unit_cc_state_applied.decode
  let assert [frame] =
    support.frames_of(
      message_id: unit_cc_state_applied.message_id,
      effects: pressed,
    )
    as "the caster is told the state once (opcode.0x87f)"
  let assert Ok(told) = applied(frame.body)
  assert told.unit_id == 7 && told.state == Stun
    as "the caster's own unit holds a Stun"
  assert list.contains(support.tells(effects: pressed), #(
      ConnectionId(2),
      client_connection.CrowdControlApplied(
        state: Stun,
        instance_id: told.instance_id,
      ),
    ))
    && list.contains(support.tells(effects: pressed), #(
      ConnectionId(3),
      client_connection.CrowdControlApplied(
        state: Stun,
        instance_id: told.instance_id,
      ),
    ))
    as "and so is each connection of the go's audience, with the same instance id"
  let assert [go] =
    support.frames_of(message_id: spell_go.message_id, effects: pressed)
  let assert Ok(go) = spell_go.decode(go.body)
  assert list.any(go.targets, fn(info) {
    info.unit_id == 7
    && list.any(info.effects, fn(effect) {
      effect.spell4_effects_id == 224_967
      && effect.instance_id == told.instance_id
      && effect.delay_ms == 500
    })
  })
    as "the go lists the state on the caster with its delay and the instance id"
  let assert [#(row_end, 2500)] =
    list.filter(support.started_timers(effects: pressed), fn(started) {
      started.1 == 2500
    })
    as "the state ends at its delay 500 plus its duration 2000 (0x1405d6880)"
  let #(_, ended) =
    support.fired_raw_as(caster: fighting(), state:, timer: row_end, at: 3500)
  assert ended_state(effects: ended).state == Stun
    as "the end is a 0x880 of the Stun (opcode.0x880)"
  assert list.map(support.tells(effects: ended), fn(tell) { tell.0 })
    == [ConnectionId(2), ConnectionId(3)]
    as "and the audience is told it ends"
  let until_removed = support.plans_of([holding(states: [Stun])])
  let #(state, _) = restricted(plans: until_removed)
  let #(_, ended) =
    cast.persisted(
      cast: state,
      caster: support.caster_in_combat(in_combat: False),
      now: support.at(ms: 3000),
    )
  assert ended_state(effects: ended).state == Stun
    as "a row with flag 2 lasts until its cast's node ends, which the end of its persistence brings"
}

/// Kick pressed at 1000 whose round closed at 1000 having struck unit 20 for no
/// description and no state, taking `armor_removed` interrupt armor off it.
fn struck_for_armor(
  armor_removed armor_removed: Int,
  immune immune: Bool,
) -> List(combat_log_entry.CombatLogEntry) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let unit = cast.HitCreature(life: 1, struck_at_ms: 0)
  let #(_, effects) =
    support.answered_by(state:, effects:, at: 1000, struck: [
      case immune {
        True -> cast.Immune(unit_id: 20, unit:, controls: [], armor_removed:)
        False ->
          cast.Hit(
            unit_id: 20,
            unit:,
            descriptions: [],
            controls: [],
            armor_removed:,
          )
      },
    ])
  logged(effects:)
}

fn armor_entry(amount amount: Int) -> combat_log_entry.CombatLogEntry {
  combat_log_entry.ModifyInterruptArmor(CombatLogModifyInterruptArmor(
    amount:,
    caster_unit_id: 7,
    target_unit_id: 20,
    spell4_id: 58_591,
    combat_result: combat_result.Hit,
  ))
}

pub fn armor_destroyed_is_logged_to_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  assert struck_for_armor(armor_removed: 2, immune: False)
    == [armor_entry(amount: 2)]
    as "a strike that took 2 armor logs type 14 with the amount, the caster, the unit and the spell (opcode.0x247.modify_interrupt_armor)"
  assert struck_for_armor(armor_removed: 0, immune: False) == []
    as "a strike that took none logs nothing"
  assert list.contains(
    struck_for_armor(armor_removed: 2, immune: True),
    armor_entry(amount: 2),
  )
    as "a guarded creature's armor change is logged as well"
}

pub fn a_tether_tells_its_anchor_before_its_state_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, pressed) =
    restricted(plans: support.plans_of([holding(states: [Tether])]))
  let ids =
    list.map(support.writes(effects: pressed), fn(frame) { frame.message_id })
  let #(_, from_anchor) =
    list.split_while(ids, fn(id) { id != unit_tether_anchor.message_id })
  assert list.take(from_anchor, 2)
    == [unit_tether_anchor.message_id, unit_cc_state_applied.message_id]
    as "a Tether aimed at the caster sends the 0x881 to the caster right before the 0x87f of the state (opcode.0x881)"
  let assert [frame] =
    support.frames_of(
      message_id: unit_tether_anchor.message_id,
      effects: pressed,
    )
  let assert Ok(anchor) = unit_tether_anchor.decode(frame.body)
  assert anchor.anchor_unit_id == 7
    as "the anchor is the caster's own unit: the message sets the anchor of the unit the client controls and names no other unit"
  assert list.contains(support.tells(effects: pressed), #(
    ConnectionId(2),
    client_connection.CrowdControlApplied(
      state: Tether,
      instance_id: applied_instance(effects: pressed),
    ),
  ))
    as "the audience is told the state as for any other, and no news of an anchor exists: a 0x881 names no unit, so only the caster gets one"
  let #(_, stunned) =
    restricted(plans: support.plans_of([holding(states: [Stun])]))
  assert support.frames_of(
      message_id: unit_tether_anchor.message_id,
      effects: stunned,
    )
    == []
    as "a state other than Tether sends none"
}

/// The instance id of the 0x87f the effects write.
fn applied_instance(effects effects: List(Effect)) -> Int {
  let assert [frame] =
    support.frames_of(message_id: unit_cc_state_applied.message_id, effects:)
    as "one 0x87f"
  let assert Ok(told) = unit_cc_state_applied.decode(frame.body)
  told.instance_id
}
