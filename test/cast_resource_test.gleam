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
//// - The step's design (issue 403): the classes' maxima and starts, and Jim's answer
////   that a cost is paid at the accept.
//// The bag indices are `cast_support.abilities`'.

import cast_support as support
import class_resource_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/class_resource.{type Resources, Payment, Resource}
import genesis_prime/game/spell_plan.{type Spell, Requirement, Spell}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/message/spell_cast_refused
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

const mind_burst = 2

const gamma_rays = 6

const electrocute = 7

const kick = 3

/// The resource of the class with its slot at `value`.
fn holding(class_id: Int, value: Float) -> Resources {
  class_resource.new(
    resource: Resource(
      ..class_resource_support.resource_of(class_id),
      start: value,
    ),
  )
}

fn refusal_results(frames: List(Frame)) -> List(CastResult) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_cast_refused.message_id {
      True -> {
        let assert Ok(refused) = spell_cast_refused.decode(frame.body)
          as "0x7fc decodes"
        Ok(refused.result)
      }
      False -> Error(Nil)
    }
  })
}

/// What a press of the bag index by a caster holding `resources` gives: the
/// refusals written and the payments taken.
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
  let #(_, effects) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster_holding(resources:),
      bag_index:,
      target: 0,
      at: 1000,
    )
  #(
    list.map(refusal_results(support.writes(effects:)), cast_result.to_value),
    support.payments(effects:),
  )
}

// ---- 4: costs in a fixed slot ----

pub fn impale_is_accepted_with_35_suit_power_and_paid_and_refused_53_at_34_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(resources: holding(5, 100.0), bag_index: support.impale)
    == #([], [Payment(slot: 3, amount: 35)])
    as "0x1403b3320: slot 3 at 100 holds 35; the cost is paid at the accept (Jim's answer, Q5)"
  assert press(resources: holding(5, 35.0), bag_index: support.impale)
    == #([], [Payment(slot: 3, amount: 35)])
  assert press(resources: holding(5, 34.9), bag_index: support.impale)
    == #([53], [])
    as "0x1403b3320: the slot is read as a whole number, 34 < 35, refused 53 (CasterVitalCostResource3)"
}

pub fn electrocute_and_mind_burst_are_refused_51_at_their_empty_start_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(
      resources: class_resource.new(
        resource: class_resource_support.resource_of(2),
      ),
      bag_index: electrocute,
    )
    == #([51], [])
    as "an Engineer starts with 0 Volatility (472510); 8 of slot 1 gives 51"
  assert press(
      resources: class_resource.new(
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
  assert press(resources: holding(4, 2.0), bag_index: gamma_rays)
    == #([], [Payment(slot: 1, amount: 2)])
    as "0x1405e7980: 2 - 2 = 0 lies in [0, 4]; slot 1 is the slot that passed and pays"
  assert press(resources: holding(4, 1.0), bag_index: gamma_rays) == #([55], [])
    as "1 - 2 < 0 in slot 1, and slots 2 to 5 hold 0: the last of them, slot 5, gives 55"
  let max_0 =
    class_resource.new(
      resource: Resource(
        ..class_resource_support.resource_of(4),
        max: 0.0,
        start: 3.0,
      ),
    )
  assert press(resources: max_0, bag_index: gamma_rays) == #([55], [])
    as "0x1405e7980: 3 - 2 = 1 is above a maximum of 0, so the maximum bounds it: 55"
}

// ---- 6: the caster requirement ----

pub fn rampage_is_refused_51_at_249_kinetic_energy_and_accepted_at_250_test() -> Nil {
  use <- owned_test.run(5000)
  assert press(resources: holding(1, 249.0), bag_index: support.rampage)
    == #([51], [])
    as "0x1403b1780: type 6 (slot 1) at least 250 (eval 2); 249 fails with 51, and the waiver (prerequisite 19750) never passes: the server holds no prerequisite engine"
  assert press(resources: holding(1, 250.0), bag_index: support.rampage)
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
    class_resource.new(
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
    class_resource.new(
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
  assert press_in(plans: both, resources: holding(5, 0.0), bag_index: kick)
    == #([51], [])
    as "0x1403afb10.order: the requirement before the innate cost: 51, not 53"
  let #(state, _) =
    support.pressed_in(
      plans: support.plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: kick,
      target: 0,
      at: 1000,
    )
  let assert [result] =
    refusal_results(
      support.writes(effects: {
        support.pressed_raw_in(
          plans: both,
          state:,
          caster: support.caster_holding(resources: holding(1, 0.0)),
          bag_index: kick,
          target: 0,
          at: 2000,
        ).1
      }),
    )
    as "one refusal"
  assert cast_result.to_value(result) == 15
    as "0x1403afb10.order: the cooldowns before the requirement: Kick's own 20 s cooldown runs, 15"
  let unarmed =
    cast.Caster(..support.caster_holding(holding(5, 0.0)), weapon: None)
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster: unarmed,
      bag_index: support.impale,
      target: 0,
      at: 1000,
    )
  assert list.map(
      refusal_results(support.writes(effects:)),
      cast_result.to_value,
    )
    == [53]
    as "0x1403afb10.order: the innate cost before the weapon: Impale needs the weapon, and 53 comes first"
}

pub fn a_press_refused_for_its_cost_pays_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.pressed_raw(
      state: cast.new(),
      caster: support.caster_holding(holding(5, 20.0)),
      bag_index: support.impale,
      target: 0,
      at: 1000,
    )
  assert support.payments(effects:) == []
  assert list.map(
      refusal_results(support.writes(effects:)),
      cast_result.to_value,
    )
    == [53]
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
  let caster = support.caster_holding(resources: holding(5, 40.0))
  let take = fn(state, message, body, at) {
    let assert Ok(taken) =
      cast.take(
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
      cast.new(),
      cast.Pressed,
      support.press_body(client_cast_id: 8, bag_index: 0, target: 0, press: 1),
      1000,
    )
  // Impale pressed with 450 ms of it left is held for the go that clears it, and
  // its key held down waits behind the held press.
  let #(state, _) =
    take(
      state,
      cast.Pressed,
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
      cast.KeyHeld,
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
  let assert [cast.Strike(asked:)] = fired as "the go is asked"
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
  assert list.map(
      refusal_results(support.writes(effects:)),
      cast_result.to_value,
    )
    == [53]
    as "the hold's press meets the 5 the first left, not the 40 the step began with: 53"
}
