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
////   its sight first (`cast_proc.unit_removed`).

import cast_support as support
import crowd_control_support
import genesis_prime/game/cast
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Effect, type State} as cast_state
import genesis_prime/game/crowd_control
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{type Spell, GlobalCooldown, Spell}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_immunity.{CombatLogImmunity}
import genesis_prime/message/combat_log_interrupted.{CombatLogInterrupted}
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
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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

/// Kick pressed at 1000 whose round closed at `go_ms` having struck these units: the cast's
/// state and the effects of its go.
fn kick_answered(
  go_ms go_ms: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  support.answered_by(state:, effects:, at: go_ms, struck:)
}

/// Kick pressed at 1000 whose round closed at `go_ms` having struck unit 20, which took
/// the Knockdown until `ends_at_ms`.
fn kicked(
  go_ms go_ms: Int,
  ends_at_ms ends_at_ms: Int,
) -> #(State, List(Effect)) {
  kick_answered(go_ms:, struck: [
    cast_state.Hit(
      unit_id: 20,
      unit: cast_state.HitCreature(life: 1),
      descriptions: [],
      controls: [
        crowd_control_support.kick_landed(ends_at_ms:),
      ],
      armor_removed: 0,
      ticking: [],
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
        lifetime_ms: 0,
        result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
      ),
    ]
    as "Spell4Effects.140382's delay 166 and the instance id the strike gave, which the 0x87f carries too (cc_state.instance_id)"
}

pub fn a_creature_that_took_no_state_has_no_effect_listed_for_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    kick_answered(go_ms: 1000, struck: [
      cast_state.Hit(
        unit_id: 20,
        unit: cast_state.HitCreature(life: 1),
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
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
    cast_proc.unit_removed(cast: state, unit_id: 20, now_ms: 2000)
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
    support.with_effects(
      spell: spell_plan.Spell(
        ..support.child(spell4_id: 58_591, base: 3),
        method: spell_plan.Multiphase,
        phase_delays_ms: [0, 1000],
      ),
      kinds: [
        spell_plan.LastingEffect(spell_plan.Lasting(
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
        )),
      ],
    )
  let plans = support.with_spells(plans: support.plans(), spells: [phased])
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, first) =
    support.answered_by(state:, effects: pressed, at: 1000, struck: [
      cast_state.Hit(
        unit_id: 20,
        unit: cast_state.HitCreature(life: 1),
        descriptions: [],
        controls: [
          crowd_control_support.kick_landed(ends_at_ms: 4000),
        ],
        armor_removed: 0,
        ticking: [],
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
      cast_state.Hit(
        unit_id: 20,
        unit: cast_state.HitCreature(life: 1),
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
      ),
    ])
  let afters =
    list.map(support.started_timers(effects: second), fn(started) { started.1 })
  assert list.contains(afters, 2000)
    as "the node ends at the state's 4000, 2000 ms after the second go"
  assert !list.contains(afters, 3000)
    as "and not at 2000 + 3000, which re-arming the state as an effect would give"
}

const bag_of_base_2 = 10

/// What unit 20, a creature of life 1 struck at 0, answers a round that gave it these states.
fn creature_20_took(
  controls controls: List(strike_tell.ControlLanded),
) -> List(cast_state.Struck) {
  [
    support.hit_with(
      unit_id: 20,
      unit: cast_state.HitCreature(life: 1),
      descriptions: [],
      controls:,
      ticking: [],
    ),
  ]
}

/// A planted spell of base 3 and Spell4 58591 whose go lists a Fluff effect of 5000 ms on
/// each unit it struck: a node with a life and no crowd-control state.
fn fluff_of_base_3() -> Spell {
  support.with_effects(spell: support.child(spell4_id: 58_591, base: 3), kinds: [
    spell_plan.LastingEffect(spell_plan.Lasting(
      effect_id: Spell4EffectsId(9),
      phase_flags: -1,
      aim: spell_plan.AimsAtArea,
      row: lasting.LastingRow(
        delay_ms: 0,
        duration_ms: 5000,
        until_removed: False,
      ),
      condition: spell_plan.Always,
      tag: spend.always,
    )),
  ])
}

/// The cast id of the first press, and the effects of the second, when `plans` are pressed
/// at the bags and each press's round gives unit 20 the states of `took`, the first at 1000
/// and the second at 2000.
fn pressed_twice(
  plans plans: spell_plan.Plans,
  bags bags: #(Int, Int),
  took took: #(List(strike_tell.ControlLanded), List(strike_tell.ControlLanded)),
) -> #(Int, List(Effect)) {
  let press = fn(state, bag_index, ms) {
    support.pressed_raw_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index:,
      target: 0,
      at: ms,
    )
  }
  let #(state, pressed) = press(cast_state.new(), bags.0, 1000)
  let first_id = support.pressed_id(effects: pressed)
  let #(state, _) =
    support.answered_by(
      state:,
      effects: pressed,
      at: 1000,
      struck: creature_20_took(controls: took.0),
    )
  let #(state, pressed) = press(state, bags.1, 2000)
  let #(_, second) =
    support.answered_by(
      state:,
      effects: pressed,
      at: 2000,
      struck: creature_20_took(controls: took.1),
    )
  #(first_id, second)
}

pub fn a_push_off_of_a_node_that_holds_a_state_tells_the_creature_to_end_that_casts_states_test() -> Nil {
  use <- owned_test.run(5000)
  // The client ends a state only with a 0x880 (`cc_state.end`), and a 0x811 that destroys
  // the node leaves it, so the cast rule tells the creature, which holds the state, when a
  // later cast of the stack takes the node off. Kick's Knockdown row 140382 stands for any
  // state; the stack rule is the server's (`lasting.pushed_off`; the group's cap is
  // `Spell4StackGroup.stackCap`, row 1771 of Restrictor's snare is 1).
  let kicked = [crowd_control_support.kick_landed(ends_at_ms: 4166)]
  let stacking = lasting.Stack(group_id: 5, cap: 1)
  let other_group = lasting.Stack(group_id: 6, cap: 1)
  let stacked = fn(spell4_id, base, stack) {
    spell_plan.Spell(..support.child(spell4_id:, base:), stack:)
  }
  list.each(
    [
      #(
        "the same spell pressed again takes its first cast's node off, a cap of 0 keeping one cast per spell",
        kick_plans(),
        #(bag_of_base_3, bag_of_base_3),
        #(kicked, kicked),
        #(True, True),
      ),
      #(
        "a second spell of a stack group with a cap of 1 takes the first spell's node off",
        support.with_spells(plans: support.plans(), spells: [
          stacked(58_591, 3, stacking),
          stacked(58_592, 2, stacking),
        ]),
        #(bag_of_base_3, bag_of_base_2),
        #(kicked, kicked),
        #(True, True),
      ),
      #(
        "a spell of another stack group takes nothing off",
        support.with_spells(plans: support.plans(), spells: [
          stacked(58_591, 3, stacking),
          stacked(58_592, 2, other_group),
        ]),
        #(bag_of_base_3, bag_of_base_2),
        #(kicked, kicked),
        #(False, False),
      ),
      #(
        "a node that holds a Fluff effect and no state leaves nothing to end",
        support.with_spells(plans: support.plans(), spells: [fluff_of_base_3()]),
        #(bag_of_base_3, bag_of_base_3),
        #([], kicked),
        #(True, False),
      ),
    ],
    fn(row) {
      let #(why, plans, bags, took, outcome) = row
      let #(pushed, ends) = outcome
      let #(first_id, second) = pressed_twice(plans:, bags:, took:)
      assert list.contains(
          support.removed_targets(support.writes(effects: second)),
          #(first_id, [20]),
        )
        == pushed
        as { "the first cast's node is taken off with a 0x811 or not: " <> why }
      assert support.controls_ended(effects: second)
        == case ends {
          True -> [
            cast_state.CreatureControlsEnd(
              unit_id: 20,
              life: 1,
              cast_id: first_id,
            ),
          ]
          False -> []
        }
        as why
    },
  )
}

// ---- Ability Restriction on the caster ----

/// Kick, the real ability at bag index 3 (`cast_support.abilities`).
const bag_of_kick = 3

const bag_of_base_1 = 8

/// The planted spell of global cooldown kind 2 (`cast_support.blocked_only`), at bag index
/// 10: refused while a global cooldown runs, starting none.
const bag_of_the_blocked = 10

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
  support.with_effects(
    spell: Spell(
      ..support.child(spell4_id: 7010, base: 3),
      caster_persistence: Some(
        prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    ),
    kinds: [
      spell_plan.ControlEffect(spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(224_967),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row:,
        condition: spell_plan.Always,
        tag: spend.always,
        move: None,
      )),
    ],
  )
}

/// The planted spell whose state row ends `row_ms` after the go while a Fluff row of the
/// same spell keeps the cast's node on the caster for `node_ms`.
fn restricting_shorter_than_its_node(
  row_ms row_ms: Int,
  node_ms node_ms: Int,
) -> Spell {
  support.with_effects(
    spell: restricting_by(row: restriction_row(
      duration_ms: row_ms,
      until_removed: False,
    )),
    kinds: [
      spell_plan.LastingEffect(spell_plan.Lasting(
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
      )),
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

fn fighting() -> cast_state.Caster {
  support.caster_in_combat(in_combat: True)
}

/// The state after the restricting spell is pressed at 1000 by a caster in combat, with
/// its effects.
fn restricted(plans plans: spell_plan.Plans) -> #(State, List(Effect)) {
  support.press_by(
    plans:,
    state: cast_state.new(),
    caster: fighting(),
    bag: 11,
    at: 1000,
  )
}

/// `restricting()` with its state row behind a type 37 caster gate of Prerequisite 792's
/// shape (comparison 6 on 24, as `cast_forced_move_test` has it): the row takes one roll.
fn restricting_by_chance() -> Spell {
  let spell = restricting()
  support.with_effects(
    spell: spell,
    kinds: list.map(
      list.map(
        spell_plan.payloads(spell:, as_kind: spell_plan.as_control),
        fn(control) {
          spell_plan.CrowdControl(
            ..control,
            condition: spell_plan.GatedOnCaster(gates: [
              prerequisite_support.single(id: 792, condition: #(37, 6, 0, 24)),
            ]),
          )
        },
      ),
      spell_plan.ControlEffect,
    ),
  )
}

pub fn a_restriction_behind_a_type_37_caster_gate_takes_one_roll_and_is_applied_when_it_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([restricting_by_chance()])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: fighting(),
      bag_index: 11,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "the restriction row's caster gate has one type 37 condition: the go draws one roll for it"
  let went = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: fighting(),
        state:,
        effects: raw,
        at: 1000,
        struck: [],
        rolls: [roll],
      )
    list.length(support.frames_of(
      message_id: unit_cc_state_applied.message_id,
      effects:,
    ))
  }
  assert went(24) == 1
    as "a roll of 24 passes comparison 6 on 24: the caster is given the state"
  assert went(25) == 0
    as "a roll of 25 fails the caster gate: the state is not applied"
}

pub fn a_press_while_restricted_is_refused_with_302_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([restricting(), casting_for_a_second()])
  let #(state, first) =
    support.press_by(
      plans:,
      state: cast_state.new(),
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
      state: cast_state.new(),
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
    support.with_effects(spell: unmasked(), kinds: [
      spell_plan.RemoveEffect(spell_plan.ForceRemove(
        effect_id: Spell4EffectsId(196_521),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        selector: lasting.Spell(Spell4Id(7010)),
        count: 1,
        condition: spell_plan.Always,
        tag: spend.always,
      )),
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
  support.with_effects(
    spell: restricting(),
    kinds: list.map(
      list.index_map(states, fn(state, index) {
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
          condition: spell_plan.Always,
          tag: spend.always,
          move: None,
        )
      }),
      spell_plan.ControlEffect,
    ),
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
      state: cast_state.new(),
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
  // The same spell as a kind 0 one, which starts a 1000 ms global cooldown when it goes and
  // which the kind 2 spell waits for.
  let gated =
    Spell(
      ..masking(mask: row_5_mask),
      global_cooldown: GlobalCooldown(
        refused_while_running: True,
        starts_for_ms: Some(1000),
      ),
    )
  let gated_plans = support.plans_of([holding(states: [Silence]), gated])
  let #(started, _) =
    support.press_by(
      plans: gated_plans,
      state: cast_state.new(),
      caster: fighting(),
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(_, behind) =
    support.press_by(
      plans: gated_plans,
      state: started,
      caster: fighting(),
      bag: bag_of_the_blocked,
      at: 1100,
    )
  assert support.refusal_results(effects: behind) == [14]
    as "the control: the spell that went started its global cooldown, so the kind 2 spell 100 ms later is refused 14"
  let #(silenced, _) = restricted(plans: gated_plans)
  let #(after, gated_refusal) =
    support.press_by(
      plans: gated_plans,
      state: silenced,
      caster: fighting(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.refusal_results(effects: gated_refusal) == [81]
    as "the kind 0 spell is refused 81 as the other is"
  let #(_, after_refusal) =
    support.press_by(
      plans: gated_plans,
      state: after,
      caster: fighting(),
      bag: bag_of_the_blocked,
      at: 2100,
    )
  assert support.refusal_results(effects: after_refusal) == []
    as "0x1403b2c40's result clears the client's global cooldown, and the refused press started none on the server: the kind 2 spell 100 ms after it is not refused 14"
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
    support.with_effects(
      spell: restricting_by(row: crowd_control.Row(
        state: Stun,
        delay_ms: 500,
        duration_ms: 2000,
        armor_removed: 0,
        until_removed: False,
      )),
      kinds: list.map(
        spell_plan.payloads(
          spell: restricting_shorter_than_its_node(row_ms: 0, node_ms: 4000),
          as_kind: spell_plan.as_lasting,
        ),
        spell_plan.LastingEffect,
      ),
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
  let assert [go] =
    support.frames_of(message_id: spell_go.message_id, effects: pressed)
  let assert Ok(go) = spell_go.decode(go.body)
  let restriction =
    unit_news.CasterRestrictionApplied(
      cast_id: go.cast_id,
      state: Stun,
      instance_id: told.instance_id,
    )
  assert list.contains(support.tells(effects: pressed), restriction)
    as "and so is the map, once, with the cast's id and the same instance id"
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
  let assert [unit_news.CasterRestrictionEnded(..)] =
    support.tells(effects: ended)
    as "and the map is told it ends, once"
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
  let unit = cast_state.HitCreature(life: 1)
  let #(_, effects) =
    kick_answered(go_ms: 1000, struck: [
      case immune {
        True ->
          cast_state.Immune(
            unit_id: 20,
            unit:,
            controls: [],
            armor_removed:,
            ticking: [],
          )
        False ->
          cast_state.Hit(
            unit_id: 20,
            unit:,
            descriptions: [],
            controls: [],
            armor_removed:,
            ticking: [],
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
  let assert [go] =
    support.frames_of(message_id: spell_go.message_id, effects: pressed)
  let assert Ok(go) = spell_go.decode(go.body)
  assert list.contains(
    support.tells(effects: pressed),
    unit_news.CasterRestrictionApplied(
      cast_id: go.cast_id,
      state: Tether,
      instance_id: applied_instance(effects: pressed),
    ),
  )
    as "the map is told the state as for any other, and no news of an anchor exists: a 0x881 names no unit, so only the caster gets one"
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

pub fn a_controls_row_aimed_at_the_caster_and_past_it_appears_in_both_readers_test() -> Nil {
  use <- owned_test.run(5000)
  // `Spell4Effects.targetFlags` 3 names the caster and the primary target, so the one
  // state is the caster's restriction and a creature's state alike
  // (`spell_plan.reaches_caster`, `spell_plan.reaches_past_caster`).
  let row =
    spell_plan.CrowdControl(
      effect_id: Spell4EffectsId(60_607),
      phase_flags: -1,
      aim: spell_plan.AimsAtCasterAndPrimaryTarget,
      row: restriction_row(duration_ms: 3000, until_removed: False),
      condition: spell_plan.Always,
      tag: spend.always,
      move: None,
    )
  let spell =
    support.with_effects(spell: support.child(spell4_id: 7010, base: 3), kinds: [
      spell_plan.ControlEffect(row),
    ])
  let #(applied, _, _) =
    cast_control.lasting_applied(
      spell:,
      phase: 0,
      spent: None,
      subject: prerequisite_support.holding(held: [], second_unit: None),
      told: fn(_) { False },
      rolls: [],
    )
  assert cast_state.passed_of(applied:, as_kind: spell_plan.as_control) == [row]
    as "the restrictions: a row that names the caster is among the caster's states"
  assert spell_plan.controls_in_phase(spell:, phase: 0, spent: None) == [row]
    as "the strike's controls: a row that names the primary target is among the creatures' states"
}

/// Kick's Knockdown that landed on a unit, which broke the charge `broke` if it names one.
fn knockdown_breaking(broke broke: Option(Int)) -> strike_tell.ControlLanded {
  strike_tell.ControlLanded(
    ..crowd_control_support.kick_landed(ends_at_ms: 4166),
    interrupted: option.map(broke, fn(spell4_id) {
      strike_tell.Interrupted(spell4_id: Spell4Id(spell4_id))
    }),
  )
}

fn state_line(target target: Int) -> combat_log_entry.CombatLogEntry {
  combat_log_entry.CcState(CombatLogCcState(
    state: Knockdown,
    removed: 0,
    interrupt_armor_hit: 0,
    result: crowd_control_result.Ok,
    diminishing_returns_id: 0,
    caster_unit_id: 7,
    target_unit_id: target,
    spell4_id: 58_591,
    combat_result: combat_result.Hit,
  ))
}

fn interrupt_line(
  target target: Int,
  broke broke: Int,
) -> combat_log_entry.CombatLogEntry {
  combat_log_entry.Interrupted(CombatLogInterrupted(
    interrupting_spell4_id: 58_591,
    cast_result: cast_result.SpellInterrupted,
    caster_unit_id: 7,
    target_unit_id: target,
    spell4_id: broke,
    combat_result: combat_result.Hit,
  ))
}

type InterruptRow {
  InterruptRow(
    reason: String,
    struck: List(cast_state.Struck),
    logged: List(combat_log_entry.CombatLogEntry),
  )
}

pub fn a_go_logs_type_19_after_the_type_1_of_the_state_that_broke_a_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let unit = cast_state.HitCreature(life: 1)
  let hit = fn(unit_id, broke) {
    cast_state.Hit(
      unit_id:,
      unit:,
      descriptions: [],
      controls: [knockdown_breaking(broke:)],
      armor_removed: 0,
      ticking: [],
    )
  }
  [
    InterruptRow(
      reason: "a hit whose state broke the Sim-Turret's charge: the type 1 line, then type 19 with Kick as the interrupter",
      struck: [hit(20, Some(85_469))],
      logged: [
        state_line(target: 20),
        interrupt_line(target: 20, broke: 85_469),
      ],
    ),
    InterruptRow(
      reason: "an immune creature whose state broke a charge: its immunity line (type 18), the type 1 line, then type 19",
      struck: [
        cast_state.Immune(
          unit_id: 20,
          unit:,
          controls: [knockdown_breaking(broke: Some(85_469))],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      logged: [
        combat_log_entry.Immunity(CombatLogImmunity(
          caster_unit_id: 7,
          target_unit_id: 20,
          spell4_id: 58_591,
          combat_result: combat_result.Hit,
        )),
        state_line(target: 20),
        interrupt_line(target: 20, broke: 85_469),
      ],
    ),
    InterruptRow(
      reason: "a go over two broken creatures: one type 19 line each, each after its own type 1 line",
      struck: [hit(20, Some(85_469)), hit(21, Some(55_317))],
      logged: [
        state_line(target: 20),
        interrupt_line(target: 20, broke: 85_469),
        state_line(target: 21),
        interrupt_line(target: 21, broke: 55_317),
      ],
    ),
    InterruptRow(
      reason: "an unmarked state: the type 1 line alone",
      struck: [hit(20, None)],
      logged: [state_line(target: 20)],
    ),
  ]
  |> list.each(fn(row) {
    assert logged(effects: kick_answered(go_ms: 1000, struck: row.struck).1)
      == row.logged
      as row.reason
  })
}
