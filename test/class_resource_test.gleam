//// The class resource rule (`genesis_prime/game/class_resource`): each class's
//// resource held, paid, refilled over time, stopped by death and set to its start
//// by coming back, and the content rows it is selected from. Expected values come
//// from these places, never from the rule:
//// - The step's design (issue 403, the Design artifact's values table): Warrior
////   slot 1 max 1000 start 0; Engineer slot 1 max 100 start 0; Esper slot 1 max 5
////   start 0; Medic slot 1 max 4 start 4, all 4 back 3 s after leaving combat (a
////   server choice); Stalker slot 3 max 100 start 100, +7 a second in and out of
////   combat (a retail record); Spellslinger slot 4 max 100 start 100, +25 each 12
////   seconds in and out of combat (a retail record), each ticked once a second (a
////   server choice), clamped to the max, a full slot sending nothing.
//// - The client: a resource slot is a 32-bit float the server sets by 0x935
////   (`opcode.0x935`, `opcode.0x262.resource_stats`); the starts are the client's
////   texts (`LocalizedEnum.CRB_StalkerResource`).
//// - The design of issue 418 (its Design artifact's Evidence): a gain is the
////   VitalModifier's dataBits02 into the slot of its vital (`Spell4Effects.effectType.1`),
////   clamped to the max; the Warrior's Kinetic Energy drains 150 a second from 1.5 s
////   after the last gain, in and out of combat (Jim's choice), ticked once a second
////   (a server choice); the Esper's Psi Points go to 0 ten seconds after it leaves
////   combat (a retail record).
//// - The design's rows of migrations 0011, 0012 and 0018, with their names and units.

import class_resource_support
import content_support
import database_support
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/class_resource.{
  type Effect, type Resource, type Resources, CancelTimer, Changed, Gain,
  Payment, Resource, Row, StartTimer,
}
import genesis_prime/step
import gleam/float
import gleam/list
import gleam/string
import owned_test

fn design_rows() -> List(class_resource.Row) {
  class_resource_support.rows()
}

fn resource_of(class_id: Int) -> Resource {
  class_resource_support.resource_of(class_id)
}

fn new(class_id: Int) -> Resources {
  class_resource.new(resource: resource_of(class_id))
}

fn changes(effects: List(Effect)) -> List(#(Int, Float)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Changed(slot:, value:) -> Ok(#(slot, value))
      StartTimer(..) | CancelTimer(..) -> Error(Nil)
    }
  })
}

fn started(effects: List(Effect)) -> List(#(Int, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      StartTimer(timer:, after_ms:) -> Ok(#(timer_number(timer), after_ms))
      Changed(..) | CancelTimer(..) -> Error(Nil)
    }
  })
}

fn cancelled(effects: List(Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      CancelTimer(timer:) -> Ok(timer_number(timer))
      Changed(..) | StartTimer(..) -> Error(Nil)
    }
  })
}

fn timer_number(timer: step.TimerId) -> Int {
  let assert True = class_resource.owns(timer:)
    as "the rule starts only its own timers"
  let step.TimerId(number) = timer
  number
}

/// The regen timer, numbered 4 in `started` and `cancelled`.
const regen = 4

/// The refill timer, numbered 5.
const refill = 5

/// The Warrior's drain timer, numbered 6.
const drain = 6

/// The Esper's empty timer, numbered 7.
const empty = 7

fn pay(
  resources resources: Resources,
  slot slot: Int,
  amount amount: Int,
) -> #(Resources, List(Effect)) {
  class_resource.pay(resources:, payments: [Payment(slot:, amount:)])
}

fn tick(resources: Resources) -> #(Resources, List(Effect)) {
  class_resource.timer_fired(resources:, timer: class_resource.regen_timer)
}

// ---- 9: start values ----

pub fn each_class_starts_with_the_slot_max_and_value_the_design_gives_test() -> Nil {
  use <- owned_test.run(5000)
  let expected = [
    #(1, 1, 1000.0, 0.0),
    #(2, 1, 100.0, 0.0),
    #(3, 1, 5.0, 0.0),
    #(4, 1, 4.0, 4.0),
    #(5, 3, 100.0, 100.0),
    #(7, 4, 100.0, 100.0),
  ]
  list.each(expected, fn(class) {
    let #(class_id, slot, max, start) = class
    let resource = resource_of(class_id)
    assert resource.slot == slot as "the slot the class bar reads (0x14064fdb0)"
    assert resource.max == max as "the design's maximum"
    assert resource.start == start
      as "full or empty by the client's text (LocalizedEnum.CRB_StalkerResource)"
    let resources = class_resource.new(resource:)
    assert class_resource.value(resources:, slot:) == start
    assert class_resource.max(resources:, slot:) == max
    assert class_resource.value(resources:, slot: slot + 1) == 0.0
      && class_resource.max(resources:, slot: slot + 1) == 0.0
      as "a slot the class does not hold is 0 with a maximum of 0 (0x140454380, UnitProperty2.ResourceMax_0)"
  })
}

// ---- 10: paying ----

pub fn a_payment_lowers_the_slot_by_the_cost_and_sends_one_change_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, effects) = pay(resources: new(5), slot: 3, amount: 35)
  assert changes(effects) == [#(3, 65.0)]
    as "Impale's 35 of 100 Suit Power: one 0x935 of slot 3 at 65"
  assert class_resource.value(resources:, slot: 3) == 65.0
  let #(_, effects) = pay(resources: new(4), slot: 1, amount: 2)
  assert changes(effects) == [#(1, 2.0)] as "Gamma Rays' 2 of 4 Actuators"
}

// ---- 11: refill over time ----

pub fn suit_power_refills_7_a_second_in_and_out_of_combat_to_100_and_a_full_slot_sends_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, paid) = pay(resources: new(5), slot: 3, amount: 32)
  assert started(paid) == [#(regen, 1000)]
    as "a slot below its max ticks each second"
  let #(resources, first) = tick(resources)
  assert changes(first) == [#(3, 75.0)] as "68 + 7 a second"
  assert started(first) == [#(regen, 1000)]
  let #(resources, _) =
    class_resource.combat_changed(resources:, in_combat: True)
  let #(resources, in_combat) = tick(resources)
  assert changes(in_combat) == [#(3, 82.0)] as "in combat too"
  let #(resources, _) = tick(resources)
  let #(resources, _) = tick(resources)
  let #(resources, last) = tick(resources)
  assert changes(last) == [#(3, 100.0)] as "96 + 7 is clamped to the max"
  assert started(last) == [] as "a full slot needs no more ticks"
  let #(_, full) = tick(resources)
  assert full == [] as "a full slot sends nothing"
}

pub fn spell_power_refills_25_each_12_seconds_a_tick_a_second_in_and_out_of_combat_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, paid) = pay(resources: new(7), slot: 4, amount: 25)
  assert changes(paid) == [#(4, 75.0)]
  assert started(paid) == [#(regen, 1000)]
  let #(resources, first) = tick(resources)
  assert changes(first) == [#(4, 77.08333587646484)]
    as "25 each 12 seconds is 25/12 a second: 75 and 25/12 is 77.0833..., and the nearest 32-bit float, the form the client holds (0x429A2AAB), is 77.08333587646484"
  let #(resources, _) =
    class_resource.combat_changed(resources:, in_combat: True)
  let resources =
    list.fold(list.repeat(Nil, 11), resources, fn(resources, _) {
      tick(resources).0
    })
  assert float.loosely_equals(
    class_resource.value(resources:, slot: 4),
    100.0,
    tolerating: 0.001,
  )
    as "12 seconds from 75 is a full circle back"
  let #(resources, _) = tick(resources)
  assert class_resource.value(resources:, slot: 4) == 100.0
    as "clamped to the max"
  assert tick(resources).1 == [] as "a full slot sends nothing"
}

// ---- 12: the Medic's refill after combat ----

pub fn actuators_fill_to_4_three_seconds_after_the_combat_flag_clears_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(4), in_combat: True)
  let #(resources, paid) = pay(resources:, slot: 1, amount: 2)
  assert started(paid) == [] as "no refill in combat"
  let #(resources, left) =
    class_resource.combat_changed(resources:, in_combat: False)
  assert started(left) == [#(refill, 3000)] as "3 s after leaving combat"
  let #(resources, filled) =
    class_resource.timer_fired(resources:, timer: class_resource.refill_timer)
  assert changes(filled) == [#(1, 4.0)] as "all 4, in one 0x935"
  assert class_resource.value(resources:, slot: 1) == 4.0
}

pub fn combat_again_within_the_3_seconds_cancels_the_refill_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(4), in_combat: True)
  let #(resources, _) = pay(resources:, slot: 1, amount: 2)
  let #(resources, _) =
    class_resource.combat_changed(resources:, in_combat: False)
  let #(resources, again) =
    class_resource.combat_changed(resources:, in_combat: True)
  assert cancelled(again) == [refill]
  let #(resources, late) =
    class_resource.timer_fired(resources:, timer: class_resource.refill_timer)
  assert late == []
    as "a refill timer that fires after its cancel changes nothing"
  assert class_resource.value(resources:, slot: 1) == 2.0
}

pub fn a_medic_paying_out_of_combat_refills_3_seconds_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, paid) = pay(resources: new(4), slot: 1, amount: 2)
  assert started(paid) == [#(refill, 3000)]
    as "out of combat the actuators come back as they do on leaving it (the server's choice: \"regenerate while out of combat\", 500710)"
  let #(resources, more) = pay(resources:, slot: 1, amount: 2)
  assert started(more) == [] as "one refill waits at a time"
  let #(_, filled) =
    class_resource.timer_fired(resources:, timer: class_resource.refill_timer)
  assert changes(filled) == [#(1, 4.0)]
}

// ---- 13: death and coming back ----

pub fn death_stops_the_timers_and_coming_back_sets_the_slot_to_its_start_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = pay(resources: new(5), slot: 3, amount: 35)
  let #(resources, _) = pay(resources:, slot: 3, amount: 35)
  let #(resources, died) = class_resource.died(resources:)
  assert cancelled(died) == [regen]
  assert changes(died) == [] as "death sends no change"
  let #(resources, late) = tick(resources)
  assert late == [] as "a tick that fires after death changes nothing"
  let #(resources, back) = class_resource.came_back(resources:)
  assert changes(back) == [#(3, 100.0)]
    as "back at the Stalker's start, full (as health and shield come back full)"
  assert started(back) == []
  assert class_resource.value(resources:, slot: 3) == 100.0
}

pub fn a_warrior_coming_back_at_its_start_sends_no_change_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = class_resource.died(resources: new(1))
  let #(_, back) = class_resource.came_back(resources:)
  assert back == [] as "0 Kinetic Energy is already its start"
}

pub fn a_medic_dying_with_its_refill_pending_has_it_cancelled_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = pay(resources: new(4), slot: 1, amount: 2)
  let #(resources, died) = class_resource.died(resources:)
  assert cancelled(died) == [refill]
  let #(_, back) = class_resource.came_back(resources:)
  assert changes(back) == [#(1, 4.0)]
}

pub fn leaving_the_world_cancels_every_timer_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = pay(resources: new(5), slot: 3, amount: 35)
  let #(_, left) = class_resource.left(resources:)
  assert left == [CancelTimer(timer: class_resource.regen_timer)]
}

// ---- issue 418: gains, the Warrior's drain and the Esper's empty ----

fn gain(
  resources resources: Resources,
  slot slot: Int,
  amount amount: Int,
) -> #(Resources, List(Effect)) {
  class_resource.gain(resources:, gains: [Gain(slot:, amount:)])
}

fn drain_fired(resources: Resources) -> #(Resources, List(Effect)) {
  class_resource.timer_fired(resources:, timer: class_resource.drain_timer)
}

fn empty_fired(resources: Resources) -> #(Resources, List(Effect)) {
  class_resource.timer_fired(resources:, timer: class_resource.empty_timer)
}

pub fn a_warriors_gain_of_180_from_0_is_one_change_and_starts_the_drain_wait_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, effects) = gain(resources: new(1), slot: 1, amount: 180)
  assert effects
    == [
      Changed(slot: 1, value: 180.0),
      StartTimer(timer: class_resource.drain_timer, after_ms: 1500),
    ]
    as "Relentless Strikes' 180 (Spell4Effects 127603 dataBits02) as one 0x935; the drain waits 1.5 s after the last gain (Jim's choice, issue 418); no drain ran, so none is cancelled"
  assert class_resource.value(resources:, slot: 1) == 180.0
}

pub fn a_gain_is_clamped_to_the_max_test() -> Nil {
  use <- owned_test.run(5000)
  let resources =
    class_resource.new(resource: Resource(..resource_of(1), start: 900.0))
  let #(resources, effects) = gain(resources:, slot: 1, amount: 180)
  assert changes(effects) == [#(1, 1000.0)]
    as "900 + 180 is clamped to the Warrior's 1000 (migration 0011)"
  assert class_resource.value(resources:, slot: 1) == 1000.0
}

pub fn a_gain_while_the_drain_waits_cancels_and_restarts_the_wait_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = gain(resources: new(1), slot: 1, amount: 180)
  let #(_, again) = gain(resources:, slot: 1, amount: 180)
  assert again
    == [
      Changed(slot: 1, value: 360.0),
      CancelTimer(timer: class_resource.drain_timer),
      StartTimer(timer: class_resource.drain_timer, after_ms: 1500),
    ]
    as "1.5 s after the last gain: one drain timer only"
}

pub fn the_drain_takes_150_a_tick_and_stops_at_0_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = gain(resources: new(1), slot: 1, amount: 180)
  let #(resources, first) = drain_fired(resources)
  assert first
    == [
      Changed(slot: 1, value: 30.0),
      StartTimer(timer: class_resource.drain_timer, after_ms: 1000),
    ]
    as "150 a second (Jim's choice, issue 418), a tick each second (the server's choice): 180 - 150"
  let #(resources, last) = drain_fired(resources)
  assert last == [Changed(slot: 1, value: 0.0)]
    as "30 - 150 is clamped to 0, and an empty slot ticks no more"
  assert drain_fired(resources).1 == []
    as "a drain timer that fires with none running changes nothing"
}

pub fn a_drain_timer_fired_after_its_cancel_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) = gain(resources: new(1), slot: 1, amount: 180)
  let #(resources, left) = class_resource.left(resources:)
  assert cancelled(left) == [drain]
  let #(resources, late) = drain_fired(resources)
  assert late == []
  assert class_resource.value(resources:, slot: 1) == 180.0
}

pub fn an_esper_leaving_combat_with_3_psi_points_empties_10_seconds_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(3), in_combat: True)
  let #(resources, gained) = gain(resources:, slot: 1, amount: 3)
  assert gained == [Changed(slot: 1, value: 3.0)]
    as "an Esper's gain starts no drain"
  let #(resources, left) =
    class_resource.combat_changed(resources:, in_combat: False)
  assert started(left) == [#(empty, 10_000)]
    as "Psi Points go to 0 ten seconds after combat (retail record, marcleoseguin.com 2014-08-13)"
  let #(resources, emptied) = empty_fired(resources)
  assert emptied == [Changed(slot: 1, value: 0.0)]
  assert class_resource.value(resources:, slot: 1) == 0.0
}

pub fn an_esper_back_in_combat_during_the_wait_keeps_its_points_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(3), in_combat: True)
  let #(resources, _) = gain(resources:, slot: 1, amount: 3)
  let #(resources, _) =
    class_resource.combat_changed(resources:, in_combat: False)
  let #(resources, again) =
    class_resource.combat_changed(resources:, in_combat: True)
  assert again == [CancelTimer(timer: class_resource.empty_timer)]
  let #(resources, late) = empty_fired(resources)
  assert late == [] as "a late fire after the cancel changes nothing"
  assert class_resource.value(resources:, slot: 1) == 3.0
}

pub fn an_esper_gaining_out_of_combat_starts_the_empty_wait_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, first) = gain(resources: new(3), slot: 1, amount: 1)
  assert first
    == [
      Changed(slot: 1, value: 1.0),
      StartTimer(timer: class_resource.empty_timer, after_ms: 10_000),
    ]
    as "Psi Points go to 0 ten seconds after combat (retail record, marcleoseguin.com 2014-08-13), also for points gained after the combat flag cleared"
  let #(resources, second) = gain(resources:, slot: 1, amount: 1)
  assert second == [Changed(slot: 1, value: 2.0)]
    as "a gain does not restart a running wait: no second start, no cancel"
  let #(resources, emptied) = empty_fired(resources)
  assert emptied == [Changed(slot: 1, value: 0.0)]
  assert class_resource.value(resources:, slot: 1) == 0.0
}

pub fn an_esper_leaving_combat_with_0_starts_no_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(3), in_combat: True)
  let #(_, left) = class_resource.combat_changed(resources:, in_combat: False)
  assert left == []
}

pub fn death_cancels_the_drain_and_empty_timers_and_coming_back_sets_0_test() -> Nil {
  use <- owned_test.run(5000)
  let #(warrior, _) = gain(resources: new(1), slot: 1, amount: 180)
  let #(warrior, died) = class_resource.died(resources: warrior)
  assert cancelled(died) == [drain]
  assert changes(died) == []
  let #(warrior, late) = drain_fired(warrior)
  assert late == [] as "a drain that fires after death changes nothing"
  let #(_, back) = class_resource.came_back(resources: warrior)
  assert back == [Changed(slot: 1, value: 0.0)]
    as "back at the Warrior's start, 0 (500714)"
  let #(esper, _) =
    class_resource.combat_changed(resources: new(3), in_combat: True)
  let #(esper, _) = gain(resources: esper, slot: 1, amount: 2)
  let #(esper, _) =
    class_resource.combat_changed(resources: esper, in_combat: False)
  let #(esper, died) = class_resource.died(resources: esper)
  assert cancelled(died) == [empty]
  let #(esper, _) = empty_fired(esper)
  assert class_resource.value(resources: esper, slot: 1) == 2.0
  let #(esper, back) = class_resource.came_back(resources: esper)
  assert back == [Changed(slot: 1, value: 0.0)]
  let #(dead_again, _) = class_resource.died(resources: esper)
  let #(_, back_again) = class_resource.came_back(resources: dead_again)
  assert back_again == [] as "already at its start, 0: no change sent"
}

// ---- issue 419: the Engineer's Volatility empties after combat ----

pub fn an_engineer_leaving_combat_with_30_volatility_empties_5_seconds_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(2), in_combat: True)
  let #(resources, gained) = gain(resources:, slot: 1, amount: 30)
  assert gained == [Changed(slot: 1, value: 30.0)]
    as "a gain in combat starts no wait"
  let #(resources, left) =
    class_resource.combat_changed(resources:, in_combat: False)
  assert left == [StartTimer(timer: class_resource.empty_timer, after_ms: 5000)]
    as "Volatility's 34688 lasts 5000 ms after leaving combat, then 34693 removes 100 (Spell4.34630); no 0x935 before the wait ends"
  let #(resources, emptied) = empty_fired(resources)
  assert emptied == [Changed(slot: 1, value: 0.0)]
    as "one change of slot 1 to 0 when the wait ends"
  assert class_resource.value(resources:, slot: 1) == 0.0
}

pub fn an_engineer_back_in_combat_during_the_wait_keeps_its_volatility_and_leaving_again_waits_anew_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(2), in_combat: True)
  let #(resources, _) = gain(resources:, slot: 1, amount: 30)
  let #(resources, _) =
    class_resource.combat_changed(resources:, in_combat: False)
  let #(resources, again) =
    class_resource.combat_changed(resources:, in_combat: True)
  assert again == [CancelTimer(timer: class_resource.empty_timer)]
    as "34630's 11835 gives no drain in combat (Spell4.34630)"
  let #(resources, late) = empty_fired(resources)
  assert late == [] as "a fire after the cancel changes nothing"
  assert class_resource.value(resources:, slot: 1) == 30.0
  let #(_, left_again) =
    class_resource.combat_changed(resources:, in_combat: False)
  assert started(left_again) == [#(empty, 5000)]
    as "73621 casts 34688 again on each leaving of combat: a new 5000 ms wait"
}

pub fn an_engineer_leaving_combat_at_0_starts_no_wait_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, _) =
    class_resource.combat_changed(resources: new(2), in_combat: True)
  let #(_, left) = class_resource.combat_changed(resources:, in_combat: False)
  assert left == [] as "an empty slot has nothing to drain"
}

pub fn an_engineers_death_cancels_the_wait_and_coming_back_sets_0_with_a_change_only_when_it_moved_test() -> Nil {
  use <- owned_test.run(5000)
  let #(engineer, _) =
    class_resource.combat_changed(resources: new(2), in_combat: True)
  let #(engineer, _) = gain(resources: engineer, slot: 1, amount: 45)
  let #(engineer, _) =
    class_resource.combat_changed(resources: engineer, in_combat: False)
  let #(engineer, died) = class_resource.died(resources: engineer)
  assert cancelled(died) == [empty]
  let #(engineer, late) = empty_fired(engineer)
  assert late == [] as "a wait that fires after the death changes nothing"
  assert class_resource.value(resources: engineer, slot: 1) == 45.0
  let #(engineer, back) = class_resource.came_back(resources: engineer)
  assert back == [Changed(slot: 1, value: 0.0)]
    as "back at the start, empty (LocalizedEnum.CRB_StalkerResource)"
  let #(dead_again, _) = class_resource.died(resources: engineer)
  let #(_, back_again) = class_resource.came_back(resources: dead_again)
  assert back_again == [] as "already at 0: no change sent"
}

pub fn an_engineer_leaving_the_world_during_the_wait_cancels_it_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(engineer, _) =
    class_resource.combat_changed(resources: new(2), in_combat: True)
  let #(engineer, _) = gain(resources: engineer, slot: 1, amount: 45)
  let #(engineer, _) =
    class_resource.combat_changed(resources: engineer, in_combat: False)
  let #(engineer, left) = class_resource.left(resources: engineer)
  assert left == [CancelTimer(timer: class_resource.empty_timer)]
  let #(_, late) = empty_fired(engineer)
  assert late == [] as "a wait that fires after the leave changes nothing"
}

pub fn an_engineer_gaining_out_of_combat_waits_5_seconds_and_the_threat_that_follows_cancels_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(resources, gained) = gain(resources: new(2), slot: 1, amount: 15)
  assert gained
    == [
      Changed(slot: 1, value: 15.0),
      StartTimer(timer: class_resource.empty_timer, after_ms: 5000),
    ]
    as "points held out of combat wait 5000 ms to empty"
  let #(_, threatened) =
    class_resource.combat_changed(resources:, in_combat: True)
  assert threatened == [CancelTimer(timer: class_resource.empty_timer)]
    as "the creature's Threatened that follows its answer ends the wait: the opener's 15 stay"
}

// ---- 14: the content rows ----

pub fn an_engineer_without_its_empty_wait_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.filter(design_rows(), fn(row) {
      !{ row.class_id == 2 && row.name == "empty_after_combat_ms" }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert names_of(refusals) == ["2 empty_after_combat_ms"]
    as "the Engineer empties after combat as the Esper does, so it needs its wait (issue 419)"
}

fn names_of(refusals: List(Refusal)) -> List(String) {
  list.map(refusals, fn(refused) {
    let assert Refusal(table: "class_resource", row: RowName(name), ..) =
      refused
      as "a class resource row is refused by its class and name"
    name
  })
}

pub fn a_class_with_no_max_row_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.filter(design_rows(), fn(row) {
      !{ row.class_id == 5 && row.name == "max" }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert names_of(refusals) == ["5 max"]
    as "every playable class needs its maximum"
}

pub fn an_unknown_class_or_name_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.append(design_rows(), [
      Row(class_id: 6, name: "max", value: 10.0, unit: "points"),
      Row(class_id: 1, name: "decay", value: 10.0, unit: "points"),
    ])
  let assert Error(refusals) = class_resource.select(rows:)
  assert list.sort(names_of(refusals), string.compare) == ["1 decay", "6 max"]
}

pub fn a_regen_missing_a_part_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    design_rows()
    |> list.filter(fn(row) {
      !{ row.class_id == 5 && row.name == "regen_tick_ms" }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert names_of(refusals) == ["5 regen_tick_ms"]
}

pub fn a_warrior_with_a_drain_row_missing_and_an_esper_without_its_empty_wait_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.filter(design_rows(), fn(row) {
      !{ row.class_id == 1 && row.name == "drain_after_ms" }
      && !{ row.class_id == 3 && row.name == "empty_after_combat_ms" }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert list.sort(names_of(refusals), string.compare)
    == ["1 drain_after_ms", "3 empty_after_combat_ms"]
    as "the Warrior's drain needs its amount, period, tick and wait, and the Esper its wait after combat (issue 418)"
}

pub fn a_migrated_database_holds_the_designs_rows_each_with_its_source_and_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_class_resource.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == design_rows()
    as "the rows of migrations 0011, 0012 and 0018, in class and name order: the values tables of the designs of issues 403, 418 and 419"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where source in ('client', 'retail_record', 'server_choice') and reason is not null",
    )
    == 19
    as "each row is the client's, a retail record or a server choice and states its reason"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where source = 'client' and class_id in (3, 4) and name = 'max'",
    )
    == 2
    as "the Esper's 5 pips and the Medic's 4 nodes are what the client draws, so the client is their source"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where source = 'server_choice'",
    )
    == 8
    as "the Medic's refill, the three ticks, the Warrior's drain amount, period and wait (Jim's choices) and the Engineer's empty wait (Jim's decision, issue 419) are the server's"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 1, 'points', 'server_choice')",
        "class_resource_other_source_states_its_reason",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'decay', 1, 'metres', 'server_choice', 'x')",
        "class_resource_unit_is_known",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (32, 'max', 1, 'points', 'server_choice', 'x')",
        "class_resource_class_id_is_in_5_bits",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', 'NaN', 'points', 'server_choice', 'x')",
        "class_resource_value_is_finite",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (5, 'max', 1, 'points', 'server_choice', 'x')",
        "class_resource_pkey",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', 1, 'points', 'nobody', 'x')",
        "class_resource_source_is_a_content_source",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'nobody_listed', 1, 'points', 'server_choice', 'x')",
        "class_resource_name_has_its_unit",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', 0, 'points', 'server_choice', 'x')",
        "class_resource_value_is_positive",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', -1, 'points', 'server_choice', 'x')",
        "class_resource_value_is_positive",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'regen_tick_ms', 2.5, 'ms', 'server_choice', 'x')",
        "class_resource_time_is_whole_ms",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', 10, 'ms', 'server_choice', 'x')",
        "class_resource_name_has_its_unit",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'drain_tick_ms', 10, 'points', 'server_choice', 'x')",
        "class_resource_name_has_its_unit",
      ),
    ],
    fn(bad) {
      let assert Error(failed) =
        database_support.psql(
          with: database_support.settings(),
          database:,
          arguments: ["-c", bad.0],
        )
        as "the database refuses the row"
      assert string.contains(failed.output, bad.1)
        as "the refusal names its constraint"
    },
  )
}
