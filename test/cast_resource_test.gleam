//// A press checked against and paid from the caster's class resource
//// (`genesis_prime/game/cast` with `genesis_prime/game/class_resource`). Expected
//// values come from these places, each named at its assertion:
//// - The client's checks: CheckInnateCost `0x1403b3320` (types 5 to 11 read slots 0
////   to 6 as whole numbers, refused 50 + the slot), CheckClassResourceCost
////   `0x1405e7980` (type 18 passes at the first of the class's slots of that vital
////   whose value less the cost lies in [0, its max], else the last one's result),
////   CheckCasterVitalRequirements `0x1403b1780` and CompareByEval `0x1407a1750`,
////   and their order, `0x1403afb10.order` (the cooldowns, the requirements, the
////   innate costs, then the weapon).
//// - The client's rows (`table_rows -- Spell4 38779 41276 32809 29874 58524`):
////   Impale 35 of type 8, Electrocute 8 of type 6, Mind Burst 1 of type 6, Gamma
////   Rays 2 of type 18 (the Medic's slots 1 to 5), Rampage slot 1 at least 250.
//// - The step's design (issue 403): the classes' maxima and starts. A cost is paid at
////   the cast's first go, which is the accept for a spell that goes at once
////   (`cast_cost_timing_test`).
//// The bag indices are `cast_support.abilities`'.

import cast_support as support
import class_resource_support
import genesis_prime/game/cast
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/class_resource.{type Resources, Payment, Resource}
import genesis_prime/game/spell_plan.{type Spell, Requirement, Spell}
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

const mind_burst = 2

const gamma_rays = 6

const electrocute = 7

const kick = 3

/// What a press of the bag index by a caster holding `resources` gives: the
/// refusals written and the payments taken, at the accept or at the go the press
/// leads to (a cost is paid at the cast's first go, `cast_cost_timing_test`).
fn press(
  resources resources: Resources,
  bag_index bag_index: Int,
) -> #(List(Int), List(class_resource.Payment)) {
  press_in(plans: support.plans(), resources:, bag_index:)
}

fn press_in(
  plans plans: spell_plan.Plans,
  resources resources: Resources,
  bag_index bag_index: Int,
) -> #(List(Int), List(class_resource.Payment)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster_holding(resources:),
      bag_index:,
      target: 0,
      at: 1000,
    )
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  let effects =
    list.append(
      effects,
      list.flat_map(steps, fn(step: #(Int, List(cast_state.Effect))) { step.1 }),
    )
  #(support.refusal_results(effects:), support.payments(effects:))
}

// ---- 4: costs in a fixed slot ----

pub fn impale_is_accepted_with_35_suit_power_and_paid_and_refused_53_at_34_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(
      resources: support.holding(class_id: 5, value: 100.0),
      bag_index: support.impale,
    )
    == #([], [Payment(slot: 3, amount: 35)])
    as "0x1403b3320: slot 3 at 100 holds 35; Impale's first phase is at 0 ms, so its cost is paid at the accept (cast_cost_timing_test)"
  assert press(
      resources: support.holding(class_id: 5, value: 35.0),
      bag_index: support.impale,
    )
    == #([], [Payment(slot: 3, amount: 35)])
  assert press(
      resources: support.holding(class_id: 5, value: 34.9),
      bag_index: support.impale,
    )
    == #([53], [])
    as "0x1403b3320: the slot is read as a whole number, 34 < 35, refused 53 (CasterVitalCostResource3)"
}

pub fn electrocute_and_mind_burst_are_refused_51_at_their_empty_start_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(
      resources: class_resource_support.new(
        resource: class_resource_support.resource_of(2),
      ),
      bag_index: electrocute,
    )
    == #([51], [])
    as "an Engineer starts with 0 Volatility (472510); 8 of slot 1 gives 51"
  assert press(
      resources: class_resource_support.new(
        resource: class_resource_support.resource_of(3),
      ),
      bag_index: mind_burst,
    )
    == #([51], [])
    as "an Esper starts with 0 Psi Points (500718); 1 of slot 1 gives 51"
}

// ---- 5: the class mechanic's cost ----

pub fn gamma_rays_passes_at_2_actuators_is_refused_55_at_1_and_at_3_with_a_max_of_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(
      resources: support.holding(class_id: 4, value: 2.0),
      bag_index: gamma_rays,
    )
    == #([], [Payment(slot: 1, amount: 2)])
    as "0x1405e7980: 2 - 2 = 0 lies in [0, 4]; slot 1 is the slot that passed and pays"
  assert press(
      resources: support.holding(class_id: 4, value: 1.0),
      bag_index: gamma_rays,
    )
    == #([55], [])
    as "1 - 2 < 0 in slot 1, and slots 2 to 5 hold 0: the last of them, slot 5, gives 55"
  let max_0 =
    class_resource_support.new(
      resource: Resource(
        ..class_resource_support.resource_of(4),
        max: 0.0,
        start: 3.0,
      ),
    )
  assert press(resources: max_0, bag_index: gamma_rays) == #([55], [])
    as "0x1405e7980: 3 - 2 = 1 is above a maximum of 0, so the maximum bounds it: 55"
}

// ---- 5b: a class cost is the caster's class's ----

/// Kick with these innate costs in place of its own none: a press of it is checked
/// against and pays them.
fn press_costing(
  costs costs: List(spell_plan.Cost),
  resources resources: Resources,
) -> #(List(Int), List(class_resource.Payment)) {
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      Spell(..support.ability(base: 38_017), costs:),
    ])
  press_in(plans:, resources:, bag_index: kick)
}

pub fn a_spellslinger_spell_power_cost_passes_at_its_amount_and_is_refused_54_below_test() -> Nil {
  use <- owned_test.run(5000)
  let cost = [spell_plan.ClassVitalCost(vital: 19, amount: 25)]
  assert press_costing(costs: cost, resources: support.holding(7, 25.0))
    == #([], [Payment(slot: 4, amount: 25)])
    as "Class 7 vitalEnumResource04 is 19, so 0x1405e7980 reads slot 4: 25 - 25 = 0 lies in [0, 100] and slot 4 pays"
  assert press_costing(costs: cost, resources: support.holding(7, 24.0))
    == #([54], [])
    as "24 - 25 < 0 in slot 4, the only slot naming 19: refused 50 + 4"
  assert press_costing(costs: cost, resources: support.holding(7, 100.0))
    == #([], [Payment(slot: 4, amount: 25)])
    as "a full slot pays too: 75 lies in [0, 100]"
}

pub fn a_class_cost_is_checked_against_the_casters_class_test() -> Nil {
  use <- owned_test.run(5000)
  assert press_costing(
      costs: [spell_plan.ClassVitalCost(vital: 19, amount: 25)],
      resources: support.holding(1, 1000.0),
    )
    == #([], [])
    as "Class 1's slots name no vital 19 (vitalEnumResource00 to 07 are 5, 4, 6, 6, 4, 4, 4, 16): 0x1405e7980 passes and pays nothing"
  let medic_cost = [spell_plan.ClassVitalCost(vital: 18, amount: 2)]
  assert press_costing(costs: medic_cost, resources: support.holding(4, 2.0))
    == #([], [Payment(slot: 1, amount: 2)])
    as "Class 4's slots 1 to 5 name 18: slot 1 holds 2, 2 - 2 = 0 lies in [0, 4]"
  assert press_costing(costs: medic_cost, resources: support.holding(4, 1.0))
    == #([55], [])
    as "none of slots 1 to 5 passes at 1; the last, slot 5, gives 55"
  assert press_costing(costs: medic_cost, resources: support.holding(7, 100.0))
    == #([], [])
    as "Class 7's slots name no vital 18: it passes and pays nothing"
}

pub fn a_warrior_kinetic_energy_cost_above_its_value_is_refused_56_test() -> Nil {
  use <- owned_test.run(5000)
  let cost = [spell_plan.ClassVitalCost(vital: 4, amount: 150)]
  assert press_costing(costs: cost, resources: support.holding(1, 100.0))
    == #([56], [])
    as "Class 1's slots 1, 4, 5 and 6 name 4; none passes at 100, and the last, slot 6, gives 50 + 6"
  assert press_costing(costs: cost, resources: support.holding(1, 150.0))
    == #([], [Payment(slot: 1, amount: 150)])
    as "slot 1 holds 150 and 150 - 150 = 0 lies in [0, 1000]"
}

pub fn a_stalker_suit_power_cost_is_refused_53_and_type_13_is_refused_52_test() -> Nil {
  use <- owned_test.run(5000)
  assert press_costing(
      costs: [spell_plan.ClassVitalCost(vital: 12, amount: 101)],
      resources: support.holding(5, 100.0),
    )
    == #([53], [])
    as "Class 5's slot 3 alone names 12: 100 - 101 < 0, refused 50 + 3"
  assert press_costing(
      costs: [spell_plan.ClassVitalCost(vital: 12, amount: 100)],
      resources: support.holding(5, 100.0),
    )
    == #([], [Payment(slot: 3, amount: 100)])
    as "slot 3 holds 100 and 100 - 100 = 0 lies in [0, 100]"
  assert press_costing(
      costs: [spell_plan.ClassVitalCost(vital: 13, amount: 1)],
      resources: support.holding(5, 100.0),
    )
    == #([52], [])
    as "Class 5's slots 1 and 2 name 13 and hold 0 with a maximum of 0: neither passes, and the last, slot 2, gives 50 + 2"
}

pub fn a_type_14_cost_passes_for_every_class_and_pays_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 3, 4, 5, 7], fn(class_id) {
    assert press_costing(
        costs: [spell_plan.ClassVitalCost(vital: 14, amount: 3)],
        resources: support.holding(class_id, 1.0),
      )
      == #([], [])
      as "no Class row's vitalEnumResource00 to 07 names 14, so 0x1405e7980 passes and pays nothing"
  })
}

// ---- 5c: a threshold row's class cost ----

pub fn a_row_class_cost_passes_at_its_amount_is_refused_54_below_and_175_at_0_test() -> Nil {
  use <- owned_test.run(5000)
  let cost = [spell_plan.RowClassCost(vital: 19, amount: 25)]
  assert press_costing(costs: cost, resources: support.holding(7, 25.0))
    == #([], [Payment(slot: 4, amount: 25)])
    as "0x1403c0620: 25 is at most the 25 the slot holds"
  assert press_costing(costs: cost, resources: support.holding(7, 24.0))
    == #([54], [])
    as "24 < 25; ClassVitalSlot 0x1405e78c0 is slot 4, the first naming 19 above 0, and VitalCostResult 0x1403d3650 gives 50 + 4"
  assert press_costing(costs: cost, resources: support.holding(7, 0.0))
    == #([175], [])
    as "no slot naming 19 holds above 0: VitalCostResult gives 175"
}

pub fn a_medic_row_cost_at_empty_actuators_is_refused_175_where_the_innate_cost_is_refused_55_test() -> Nil {
  use <- owned_test.run(5000)
  assert press_costing(
      costs: [spell_plan.RowClassCost(vital: 18, amount: 1)],
      resources: support.holding(4, 0.0),
    )
    == #([175], [])
    as "0x1403c0620 with every actuator at 0: ClassVitalSlot finds no slot above 0, 175"
  assert press_costing(
      costs: [spell_plan.ClassVitalCost(vital: 18, amount: 1)],
      resources: support.holding(4, 0.0),
    )
    == #([55], [])
    as "0x1405e7980 on the same state: no slot passes, the last, slot 5, gives 55"
}

pub fn a_row_cost_has_no_maximum_and_a_vital_the_class_lacks_is_refused_175_test() -> Nil {
  use <- owned_test.run(5000)
  assert press_costing(
      costs: [spell_plan.RowClassCost(vital: 19, amount: 0)],
      resources: support.holding(7, 0.0),
    )
    == #([], [])
    as "0x1403c0620: a cost of 0 passes, and takes nothing"
  let above_its_max =
    class_resource_support.new(
      resource: Resource(
        ..class_resource_support.resource_of(4),
        max: 0.0,
        start: 3.0,
      ),
    )
  assert press_costing(
      costs: [spell_plan.RowClassCost(vital: 18, amount: 2)],
      resources: above_its_max,
    )
    == #([], [Payment(slot: 1, amount: 2)])
    as "0x1403c0620 has no maximum test: 3 holds 2, where the innate cost 3 - 2 = 1 above a maximum of 0 is refused 55"
  assert press_costing(
      costs: [spell_plan.RowClassCost(vital: 14, amount: 1)],
      resources: support.holding(7, 100.0),
    )
    == #([175], [])
    as "Class 7 has no slot naming 14, so the vital holds 0 and VitalCostResult gives 175"
}

// ---- 6: the caster requirement ----

pub fn rampage_is_refused_51_at_249_kinetic_energy_and_accepted_at_250_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(
      resources: support.holding(class_id: 1, value: 249.0),
      bag_index: support.rampage,
    )
    == #([51], [])
    as "0x1403b1780: type 6 (slot 1) at least 250 (eval 2); 249 fails with 51 unless the waiver (prerequisite 19750, under Overdrive 42908) passes, which it does not for a caster under no cast (the waiver's own cases are cast_prerequisite_test)"
  assert press(
      resources: support.holding(class_id: 1, value: 250.0),
      bag_index: support.rampage,
    )
    == #([], [])
    as "250 meets it; a requirement takes nothing"
}

/// Kick with one requirement of slot 1 in place of its own none.
fn kick_requiring(requirement: spell_plan.Requirement) -> spell_plan.Plans {
  support.with_spells(plans: support.plans(), spells: [
    Spell(..support.ability(base: 38_017), requirements: [requirement]),
  ])
}

pub fn each_comparison_reads_as_compare_by_eval_on_the_amount_and_on_the_percentage_test() -> Nil {
  use <- owned_test.run(5000)
  // Slot 1 at 500 of a maximum of 1000: 50 percent (0x1403b1780).
  let resources =
    class_resource_support.new(
      resource: Resource(..class_resource_support.resource_of(1), start: 500.0),
    )
  let cases = [
    #(spell_plan.Amount, spell_plan.Equal, 500, True),
    #(spell_plan.Amount, spell_plan.Equal, 499, False),
    #(spell_plan.Amount, spell_plan.Greater, 499, True),
    #(spell_plan.Amount, spell_plan.Greater, 500, False),
    #(spell_plan.Amount, spell_plan.AtLeast, 500, True),
    #(spell_plan.Amount, spell_plan.AtLeast, 501, False),
    #(spell_plan.Amount, spell_plan.Less, 501, True),
    #(spell_plan.Amount, spell_plan.Less, 500, False),
    #(spell_plan.Amount, spell_plan.AtMost, 500, True),
    #(spell_plan.Amount, spell_plan.AtMost, 499, False),
    #(spell_plan.PercentOfMax, spell_plan.Equal, 50, True),
    #(spell_plan.PercentOfMax, spell_plan.Greater, 50, False),
    #(spell_plan.PercentOfMax, spell_plan.AtLeast, 50, True),
    #(spell_plan.PercentOfMax, spell_plan.Less, 51, True),
    #(spell_plan.PercentOfMax, spell_plan.AtMost, 49, False),
    #(spell_plan.PercentOfMax, spell_plan.NeverPasses(eval: 10), 0, False),
  ]
  list.each(cases, fn(case_) {
    let #(measure, comparison, value, passes) = case_
    let plans =
      kick_requiring(Requirement(
        slot: 1,
        measure:,
        comparison:,
        value:,
        result: 51,
      ))
    let #(refused, _) = press_in(plans:, resources:, bag_index: kick)
    assert { refused == [] } == passes
      as { "0x1407a1750 against " <> int.to_string(value) }
  })
}

pub fn a_percentage_of_a_maximum_of_0_passes_only_above_or_at_least_for_a_slot_above_0_test() -> Nil {
  use <- owned_test.run(5000)
  let at = fn(value) {
    class_resource_support.new(
      resource: Resource(
        ..class_resource_support.resource_of(1),
        max: 0.0,
        start: value,
      ),
    )
  }
  let passes = fn(resources, comparison) {
    let plans =
      kick_requiring(Requirement(
        slot: 1,
        measure: spell_plan.PercentOfMax,
        comparison:,
        value: 1000,
        result: 51,
      ))
    press_in(plans:, resources:, bag_index: kick).0 == []
  }
  assert passes(at(3.0), spell_plan.AtLeast)
    as "0x1403b1780 divides by the maximum as a float: 3 of 0 is infinitely many percent"
  assert !passes(at(3.0), spell_plan.Less)
  assert !passes(at(0.0), spell_plan.AtLeast)
    as "0 of 0 is no number, which every comparison of 0x1407a1750 fails"
}

// ---- 8: the client's order, and nothing paid for a refusal ----

/// Kick with Rampage's requirement and Impale's cost.
fn kick_with_a_requirement_and_a_cost() -> Spell {
  Spell(
    ..support.ability(base: 38_017),
    requirements: support.ability(base: 37_968).requirements,
    costs: support.ability(base: 23_161).costs,
  )
}

pub fn a_press_failing_two_checks_gets_the_first_the_clients_order_gives_test() -> Nil {
  use <- owned_test.run(5000)
  let both =
    support.with_spells(plans: support.plans(), spells: [
      kick_with_a_requirement_and_a_cost(),
    ])
  assert press_in(
      plans: both,
      resources: support.holding(class_id: 5, value: 0.0),
      bag_index: kick,
    )
    == #([51], [])
    as "0x1403afb10.order: the requirement before the innate cost: 51, not 53"
  let #(state, _) =
    support.pressed_in(
      plans: support.plans(),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: kick,
      target: 0,
      at: 1000,
    )
  let assert [result] =
    support.refusal_results(
      effects: support.pressed_raw_in(
        plans: both,
        state:,
        caster: support.caster_holding(resources: support.holding(
          class_id: 1,
          value: 0.0,
        )),
        bag_index: kick,
        target: 0,
        at: 2000,
      ).1,
    )
    as "one refusal"
  assert result == 15
    as "0x1403afb10.order: the cooldowns before the requirement: Kick's own 20 s cooldown runs, 15"
  let unarmed =
    cast_state.Caster(
      ..support.caster_holding(support.holding(class_id: 5, value: 0.0)),
      weapon: None,
    )
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast_state.new(),
      caster: unarmed,
      bag_index: support.impale,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects:) == [53]
    as "0x1403afb10.order: the innate cost before the weapon: Impale needs the weapon, and 53 comes first"
}

pub fn a_press_refused_for_its_cost_pays_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.pressed_raw(
      state: cast_state.new(),
      caster: support.caster_holding(support.holding(class_id: 5, value: 20.0)),
      bag_index: support.impale,
      target: 0,
      at: 1000,
    )
  assert support.payments(effects:) == []
  assert support.refusal_results(effects:) == [53]
}

// ---- 10: one payment is never spent twice ----

/// Impale as a spell with no global cooldown and no cast bar of its own, so a
/// second press of it in the same step meets only its cost.
fn quick_impale() -> Spell {
  Spell(
    ..support.child(spell4_id: 38_779, base: 23_161),
    costs: support.ability(base: 23_161).costs,
  )
}

pub fn two_presses_accepted_in_one_step_cannot_spend_one_payment_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.with_spells(plans: support.plans(), spells: [quick_impale()])
  let caster =
    support.caster_holding(resources: support.holding(class_id: 5, value: 40.0))
  let take = fn(state, message, body, at) {
    let assert Ok(taken) =
      cast.take(
        target_of: support.nothing_shown,
        cast: state,
        message:,
        body:,
        caster:,
        plans:,
        now: support.at(ms: at),
      )
      as "taken"
    taken
  }
  // Telekinetic Strike's 1250 ms cast bar is the current cast from 1000.
  let #(state, started) =
    take(
      cast_state.new(),
      cast_state.Pressed,
      support.press_body(client_cast_id: 8, bag_index: 0, target: 0, press: 1),
      1000,
    )
  // Impale pressed with 450 ms of it left is held for the go that clears it, and
  // its key held down waits behind the held press.
  let #(state, _) =
    take(
      state,
      cast_state.Pressed,
      support.press_body(
        client_cast_id: 9,
        bag_index: support.impale,
        target: 0,
        press: 1,
      ),
      1800,
    )
  let #(state, _) =
    take(
      state,
      cast_state.KeyHeld,
      support.hold_body(bag_index: support.impale, target: 0, held: 1),
      1900,
    )
  let assert [#(go_timer, _), ..] = support.started_timers(effects: started)
  let #(state, fired) =
    cast.timer_fired(
      cast: state,
      timer: go_timer,
      caster:,
      now: support.at(ms: 2250),
    )
  let assert [cast_state.Strike(asked:)] = fired as "the go is asked"
  // The go's round closes and clears the current cast: the held press and then
  // the hold's press are both taken in this one step, against 40 Suit Power.
  let #(_, effects) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2250),
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
  assert support.payments(effects:) == [Payment(slot: 3, amount: 35)]
    as "the held press pays 35 of 40"
  assert support.refusal_results(effects:) == [53]
    as "the hold's press meets the 5 the first left, not the 40 the step began with: 53"
}
