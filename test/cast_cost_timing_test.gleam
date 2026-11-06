//// When a spell's innate cost is paid (`genesis_prime/game/cast` with
//// `genesis_prime/game/class_resource`): checked at the accept against the slot less
//// what live casts have reserved, reserved on the live cast, and paid at the cast's
//// first go. Expected values come from these places, each named at its assertion:
//// - `Spell4.innateCost0.timing`: the client checks a cost only before it sends a
////   press, never lowers a resource itself and shows only what 0x935 says, so when to
////   pay is the server's; Jim's retail video shows Gamma Rays' Actuators dropping
////   when its beams go off.
//// - The client's rows (`table_rows -- Spell4 29874 32809 58832 38779`): Gamma Rays
////   costs 2 of type 18 (the Medic's slots 1 to 5) with a cast time of 1250 ms, Mind
////   Burst 1 of type 6 with EMM id 4, Impale 35 of type 8 with a first phase at 0 ms,
////   Discharge is a channel whose pulses begin after an initial delay.
//// - `opcode.0x801`: reason 11 (SpellInterrupted) with the bit 1 is what a jump sends.
//// - `Spell4CastResult.vital_cost`: a cost the slot cannot meet is refused with the
////   cost's result (55 for the Medic's last slot, 51 for the Esper's Psi Points).
//// - The class resource's own rules (`genesis_prime/game/class_resource`): the
////   Esper's empty runs while the slot holds above 0, the Medic's refill starts from a
////   payment made out of combat.
//// - The design of the step: at one go the cost is paid before that go's gains
////   (the server's choice).

import cast_support as support
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/class_resource.{type Resources, Payment}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type Plans, type Spell, Spell}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/step.{type TimerId}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import spell_tables

const mind_burst = 2

const gamma_rays = 6

/// 2^31 + 7 x 2^11: the caster 7's first cast id.
const first_cast = 2_147_497_984

fn holding(class_id class_id: Int, points points: Int) -> Resources {
  support.holding(class_id, int.to_float(points))
}

fn medic_holding(points points: Int) -> cast.Caster {
  support.caster_holding(resources: holding(class_id: 4, points:))
}

fn esper_holding(points points: Int) -> cast.Caster {
  support.caster_holding(resources: holding(class_id: 3, points:))
}

/// Gamma Rays as a cast that leaves the caster free and starts no cooldown, so a
/// second press meets only its cost.
fn free_gamma_rays() -> Spell {
  Spell(
    ..support.ability(base: 16_322),
    free_while_live: True,
    global_cooldown: spell_plan.GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
  )
}

fn plans_with(spell spell: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [spell])
}

/// The go timer a press started, with its wait.
fn go_timer(effects effects: List(Effect)) -> #(TimerId, Int) {
  let assert [first, ..] = support.started_timers(effects:)
    as "a cast with a cast time starts a timer for its go"
  first
}

/// Discharge with the cost of 3 of slot 1 its row does not hold, so a channel's first
/// pulse has a cost to pay.
fn charging_discharge() -> Spell {
  Spell(..support.ability(base: 38_201), costs: [
    spell_plan.SlotCost(slot: 1, amount: 3, result: 51),
  ])
}

/// The timer fires at `ms` and the go's round closes on nobody.
fn went(
  state state: cast.State,
  caster caster: cast.Caster,
  timer timer: TimerId,
  at ms: Int,
) -> #(cast.State, List(Effect)) {
  let #(state, raw) =
    cast.timer_fired(cast: state, timer:, caster:, now: support.at(ms:))
  support.answered_as(
    caster:,
    state:,
    effects: raw,
    at: ms,
    struck: [],
    rolls: [],
  )
}

// ---- 1: the accept reserves, the first go pays ----

pub fn gamma_rays_pays_its_actuators_at_its_go_and_not_at_the_press_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = medic_holding(points: 4)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed) == []
    as "Spell4.29874 costs 2 of 4 Actuators: accepted"
  assert support.payments(effects: pressed) == []
    as "Spell4.innateCost0.timing: no cost is taken at the accept, so no 0x935"
  let #(timer, after_ms) = go_timer(effects: pressed)
  assert after_ms == 1250 as "Spell4.29874 castTime 1250"
  let #(_, going) = went(state:, caster:, timer:, at: 2250)
  assert support.payments(effects: going) == [Payment(slot: 1, amount: 2)]
    as "the first go pays the 2 Actuators (retail video: they drop when the beams go off)"
  let #(left, changes) =
    class_resource.pay(
      resources: caster.resources,
      payments: support.payments(effects: going),
    )
  assert class_resource.value(resources: left, slot: 1) == 2.0
  assert list.filter(changes, fn(change) {
      case change {
        class_resource.Changed(..) -> True
        class_resource.StartTimer(..) | class_resource.CancelTimer(..) -> False
      }
    })
    == [class_resource.Changed(slot: 1, value: 2.0)]
    as "opcode.0x935: one 0x935 of slot 1 with the new value, 4 less 2"
}

pub fn a_cast_pays_once_at_its_first_go_and_not_at_a_later_one_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = esper_holding(points: 5)
  let discharge = charging_discharge()
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: plans_with(spell: discharge),
      state: cast.new(),
      caster:,
      bag_index: support.discharge,
      target: 0,
      at: 1000,
    )
  assert support.payments(effects: pressed) == []
    as "the accept reserves, it does not pay"
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  let assert [first, ..later] = steps as "a channel has several pulses"
  assert support.payments(effects: first.1) == [Payment(slot: 1, amount: 3)]
    as "a Channeled spell pays at its first pulse"
  assert list.flat_map(later, fn(step) { support.payments(effects: step.1) })
    == []
    as "the later pulses pay nothing: the cost is the cast's, taken once"
}

// ---- 2: a cast that ends before its go pays nothing ----

pub fn a_gamma_rays_cancelled_by_a_jump_before_its_go_pays_nothing_and_frees_its_actuators_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = medic_holding(points: 2)
  let plans = plans_with(spell: free_gamma_rays())
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  let #(go, _) = go_timer(effects: pressed)
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans:,
      state:,
      cast_id: first_cast,
      reason: cast_result.from_value(11),
      bit: 1,
      at: 1500,
    )
  assert support.payments(effects: cancelled) == []
    as "opcode.0x801: a cast the client cancels before its go takes nothing"
  assert list.contains(support.cancelled_timers(effects: cancelled), go)
    as "the cancelled cast's go timer is cancelled, so no go comes to pay"
  let #(_, again) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 5000,
    )
  assert support.refusal_results(effects: again) == []
    as "the 2 Actuators the cancelled cast held are free: a press that needs exactly 2 is accepted, not refused 55"
}

pub fn a_caster_that_dies_before_the_go_pays_nothing_for_a_channel_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = esper_holding(points: 5)
  let discharge = charging_discharge()
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: plans_with(spell: discharge),
      state: cast.new(),
      caster:,
      bag_index: support.discharge,
      target: 0,
      at: 1000,
    )
  let #(state, died) = cast.died(cast: state, now: support.at(ms: 1100))
  assert support.payments(effects: list.append(pressed, died)) == []
    as "death before the first pulse: nothing was paid, at the press or at the death"
  let #(pulse, _) = go_timer(effects: pressed)
  let #(_, after) = went(state:, caster:, timer: pulse, at: 1410)
  assert support.payments(effects: after) == []
    as "a pulse timer that fires after the death finds no live cast and pays nothing"
}

pub fn a_caster_that_leaves_before_the_go_pays_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = medic_holding(points: 4)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  let #(state, left) = cast.left(cast: state)
  assert support.payments(effects: list.append(pressed, left)) == []
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, going) = went(state:, caster:, timer:, at: 2250)
  assert support.payments(effects: going) == []
    as "a go that finds no live cast has no go and takes nothing"
}

pub fn a_cast_cancelled_while_the_round_of_its_go_is_open_still_pays_for_the_hits_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = medic_holding(points: 4)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  let #(timer, _) = go_timer(effects: pressed)
  let #(state, raw) =
    cast.timer_fired(cast: state, timer:, caster:, now: support.at(ms: 2250))
  let assert [cast.Pay(payments:), cast.Strike(asked:)] = raw
    as "the go begins its strike: creatures apply the round's hits as soon as they are told, so the cost is paid with it"
  assert payments == [Payment(slot: 1, amount: 2)]
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans: support.plans(),
      state:,
      cast_id: asked.cast_id,
      reason: cast_result.from_value(11),
      bit: 1,
      at: 2260,
    )
  assert support.payments(effects: cancelled) == []
    as "the cancel inside the open round pays nothing more: the reservation was paid with the strike"
  let #(_, answered) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2300),
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
  assert answered == []
    as "the cast ended before the round closed: no go is written, and nothing is paid twice"
}

// ---- 3: a reservation is checked against ----

pub fn a_second_press_is_refused_at_its_accept_for_points_a_live_cast_has_reserved_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_with(spell: free_gamma_rays())
  let caster = medic_holding(points: 3)
  let #(state, first) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: first) == []
  let #(_, second) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1100,
    )
  assert support.refusal_results(effects: second) == [55]
    as "3 Actuators held, 2 reserved by the first cast: the second needs 2 of the 1 left, refused with the cost's result as an unreserved press is (CasterVitalCostResource5)"
  assert support.payments(effects: second) == []
}

pub fn two_presses_that_the_slot_meets_together_are_both_accepted_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_with(spell: free_gamma_rays())
  let caster = medic_holding(points: 4)
  let #(state, _) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  let #(_, second) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1100,
    )
  assert support.refusal_results(effects: second) == []
    as "4 Actuators meet 2 and 2: the reservation holds back only what the first cast needs"
}

// ---- 4: an instant spell pays at its accept ----

pub fn an_instant_spell_pays_at_its_accept_before_it_writes_anything_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster: support.caster_holding(resources: holding(
        class_id: 5,
        points: 100,
      )),
      bag_index: support.impale,
      target: 0,
      at: 1000,
    )
  let assert [cast.Pay(payments:), cast.Send(..), ..] = effects
    as "Impale's first phase is at 0 ms, so its accept and go are one step and the cost is the step's first effect"
  assert payments == [Payment(slot: 3, amount: 35)]
    as "Spell4.38779 costs 35 of type 8 (slot 3)"
}

// ---- 5: a spend of every point is fixed at the accept ----

/// Mind Burst with the cast time of 1250 ms its row does not hold, so its go comes
/// after its accept.
fn slow_mind_burst() -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.plans_with_mind_burst_spend(),
      base: id.Spell4BaseId(19_019),
    )
    as "the planted Esper holds Mind Burst with its spend"
  Spell(..spell, cast_time_ms: 1250)
}

/// The slow Mind Burst as a cast that leaves the caster free and starts no cooldown,
/// so a second press meets only its cost.
fn free_burst() -> Spell {
  Spell(
    ..slow_mind_burst(),
    free_while_live: True,
    global_cooldown: spell_plan.GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
  )
}

/// The slow Mind Burst with a cost of `amount` of slot 1 in place of its spend.
fn spender(amount amount: Int) -> Spell {
  Spell(..slow_mind_burst(), costs: [
    spell_plan.SlotCost(slot: 1, amount:, result: 51),
  ])
}

pub fn a_mind_burst_fixes_n_at_its_accept_and_its_go_pays_the_points_n_was_fixed_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = plans_with(spell: slow_mind_burst())
  let pressing = esper_holding(points: 3)
  let at_the_go = esper_holding(points: 5)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: pressing,
      bag_index: mind_burst,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed) == []
  assert support.payments(effects: pressed) == []
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, raw) =
    cast.timer_fired(
      cast: state,
      timer:,
      caster: at_the_go,
      now: support.at(ms: 2250),
    )
  let assert [cast.Pay(payments:), cast.Strike(asked:)] = raw
    as "the go pays, then its strike is asked"
  assert payments == [Payment(slot: 1, amount: 3)]
    as "Spell4.innateCostEMMId0 4: the go pays the 3 points n was fixed on"
  assert asked.spent == Some(2)
    as "Spell4Effects.emmComparison: n is the 3 points held at the accept less the base cost of 1; the 5 held at the go do not move it"
  let area =
    spell_tables.mind_burst_area(damage: spell_tables.mind_burst_damage)
  let assert Ok(phase) =
    spell_area.phase(spell: area, phase: asked.phase, spent: asked.spent)
    as "Mind Burst has one phase"
  assert list.map(phase.damage, fn(effect) { effect.effect_id.value })
    == [61_995]
    as "Spell4.32809: the damage row whose emmValue is n = 2 is Spell4Effects 61995, the only one the go's strike holds"
}

pub fn a_spend_of_every_point_takes_what_is_held_less_what_a_live_cast_has_reserved_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      free_gamma_rays(),
      free_burst(),
    ])
  let caster = esper_holding(points: 4)
  let #(state, rays) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: rays) == []
    as "Gamma Rays costs 2 (class vital 18, the Esper's slot 1 passes at 4 - 2 = 2): reserved, not paid"
  let #(state, burst) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: mind_burst,
      target: 0,
      at: 1100,
    )
  assert support.refusal_results(effects: burst) == []
    as "0x1403b3320 checks the base cost of 1 against the 2 points not reserved"
  let #(timer, _) = go_timer(effects: burst)
  let #(_, raw) =
    cast.timer_fired(cast: state, timer:, caster:, now: support.at(ms: 2350))
  let assert [cast.Pay(payments:), cast.Strike(asked:)] = raw
    as "the go pays, then its strike is asked"
  assert asked.spent == Some(1)
    as "n is the 4 held less the 2 reserved, less the base cost of 1"
  assert payments == [Payment(slot: 1, amount: 2)]
    as "the go pays the 2 points n was fixed on"
}

pub fn a_spend_of_every_point_leaves_nothing_for_a_second_press_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = plans_with(spell: free_burst())
  let caster = esper_holding(points: 4)
  let take = fn(state, at) {
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: mind_burst,
      target: 0,
      at:,
    )
  }
  let #(state, first) = take(cast.new(), 1000)
  let #(timer, _) = go_timer(effects: first)
  let #(state, second) = take(state, 1100)
  assert support.refusal_results(effects: second) == [51]
    as "the first cast reserved all 4 points: the second meets 0 against the base cost of 1, refused 51 (0x1403b3320)"
  let #(_, going) = went(state:, caster:, timer:, at: 2250)
  assert support.payments(effects: going) == [Payment(slot: 1, amount: 4)]
}

// ---- 7: the class resource's timers see a reservation as held ----

pub fn the_esper_empty_runs_for_points_a_live_cast_has_reserved_and_the_go_pays_what_is_left_test() -> Nil {
  use <- owned_test.run(5000)
  let in_combat =
    class_resource.combat_changed(
      resources: holding(class_id: 3, points: 3),
      in_combat: True,
    ).0
  let caster = support.caster_holding(resources: in_combat)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: plans_with(spell: spender(amount: 3)),
      state: cast.new(),
      caster:,
      bag_index: mind_burst,
      target: 0,
      at: 1000,
    )
  assert support.payments(effects: pressed) == []
  let #(resources, cleared) =
    class_resource.combat_changed(resources: in_combat, in_combat: False)
  assert cleared
    == [
      class_resource.StartTimer(
        timer: class_resource.empty_timer,
        after_ms: 10_000,
      ),
    ]
    as "the slot still holds the 3 points the cast reserved, so the Esper's empty waits for them (a retail record, 500718)"
  let #(resources, emptied) =
    class_resource.timer_fired(resources:, timer: class_resource.empty_timer)
  assert emptied == [class_resource.Changed(slot: 1, value: 0.0)]
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, going) =
    went(state:, caster: support.caster_holding(resources:), timer:, at: 2250)
  let #(paid, _) =
    class_resource.pay(resources:, payments: support.payments(effects: going))
  assert class_resource.value(resources: paid, slot: 1) == 0.0
    as "the go pays what it can: a slot the empty has taken to 0 stays at 0, never below"
}

pub fn the_warriors_drain_runs_down_points_a_live_cast_has_reserved_and_the_go_pays_what_is_left_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, started) =
    class_resource.gain(resources: holding(class_id: 1, points: 100), gains: [
      class_resource.Gain(slot: 1, amount: 200),
    ])
  assert class_resource.value(resources:, slot: 1) == 300.0
  assert list.contains(
    started,
    class_resource.StartTimer(timer: class_resource.drain_timer, after_ms: 1500),
  )
    as "a gain starts the Warrior's drain, 1500 ms after it (Jim's choice, migration 0012)"
  let caster = support.caster_holding(resources:)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: plans_with(spell: spender(amount: 200)),
      state: cast.new(),
      caster:,
      bag_index: mind_burst,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed) == []
  assert support.payments(effects: pressed) == []
  let #(resources, first_tick) =
    class_resource.timer_fired(resources:, timer: class_resource.drain_timer)
  assert class_resource.value(resources:, slot: 1) == 150.0
    as "the drain takes its 150 a tick (migration 0012) from the 300 the slot still holds"
  assert list.contains(
    first_tick,
    class_resource.Changed(slot: 1, value: 150.0),
  )
  let #(resources, _) =
    class_resource.timer_fired(resources:, timer: class_resource.drain_timer)
  assert class_resource.value(resources:, slot: 1) == 0.0
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, going) =
    went(state:, caster: support.caster_holding(resources:), timer:, at: 2250)
  let #(paid, _) =
    class_resource.pay(resources:, payments: support.payments(effects: going))
  assert class_resource.value(resources: paid, slot: 1) == 0.0
    as "the go pays what the slot holds, down to 0, never below"
}

pub fn the_medic_refill_starts_at_the_payment_and_not_at_the_press_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = medic_holding(points: 4)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.plans(),
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  assert support.payments(effects: pressed) == []
    as "the accept changes no slot, so no timer of the class resource starts"
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, going) = went(state:, caster:, timer:, at: 2250)
  let #(_, effects) =
    class_resource.pay(
      resources: caster.resources,
      payments: support.payments(effects: going),
    )
  assert list.contains(
    effects,
    class_resource.StartTimer(
      timer: class_resource.refill_timer,
      after_ms: 3000,
    ),
  )
    as "class_resource: the Medic's refill starts from a payment made out of combat, 3 s (500710)"
}

// ---- at one go the cost comes before the gains ----

pub fn a_go_pays_its_cost_before_it_gives_its_gains_test() -> Nil {
  use <- owned_test.run(5000)
  let giving =
    Spell(..support.ability(base: 16_322), gains: [
      spell_plan.Gain(
        effect_id: Spell4EffectsId(1),
        slot: 1,
        amount: 1,
        phase_flags: 1,
        prerequisite: None,
        tag: spend.always,
      ),
    ])
  let caster = medic_holding(points: 4)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: plans_with(spell: giving),
      state: cast.new(),
      caster:,
      bag_index: gamma_rays,
      target: 0,
      at: 1000,
    )
  let #(timer, _) = go_timer(effects: pressed)
  let #(_, going) = went(state:, caster:, timer:, at: 2250)
  let resources = cast.after_payments(caster:, effects: going).resources
  assert class_resource.value(resources:, slot: 1) == 3.0
    as "the design: 4 less the cost 2 is 2, and the go's +1 makes 3; a gain first would clamp at the maximum 4 and leave 2"
}
