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
////   after the last gain, in and out of combat (a server choice), ticked once a second
////   (a server choice); the Esper's Psi Points go to 0 ten seconds after it leaves
////   combat (a retail record).
//// - The design's rows of migrations 0011, 0012 and 0018, with their names and units.
//// - The design of issue 945 (a server choice): Focus is a pool of 1000 points at every
////   level plus what worn items add (UnitProperty2 5), held by the classes whose level
////   grants cost it, full at entry and when coming back; it recovers each 500 ms
////   (GameFormula 88) by the maximum x the share x 0.5, the share being UnitProperty2 108
////   out of combat and the curve of GameFormula 1237 over properties 107 and 6 in
////   combat (`FUN_1404602f0`, `GetFocusRegenNonCombat` 0x14064ac80); a 0x935 of stat 1
////   (`ApplyUnitStat` 0x1403d9a60 case 1) tells each change, Focus being slot -1.

import class_resource_support
import client_tables
import content_support
import database_support
import fixture_tables
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/class_resource.{
  type Effect, type Resource, type Resources, CancelTimer, Changed, Gain,
  Payment, Resource, Row, StartTimer,
}
import genesis_prime/step
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/float
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import qcheck
import unitest

fn design_rows() -> List(class_resource.Row) {
  class_resource_support.rows()
}

fn resource_of(class_id: Int) -> Resource {
  class_resource_support.resource_of(class_id)
}

fn new(class_id: Int) -> Resources {
  class_resource_support.resources_of(class_id)
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
    let resources = new(class_id)
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
    as "Relentless Strikes' 180 (Spell4Effects 127603 dataBits02) as one 0x935; the drain waits 1.5 s after the last gain (a server choice, issue 418); no drain ran, so none is cancelled"
  assert class_resource.value(resources:, slot: 1) == 180.0
}

pub fn a_gain_is_clamped_to_the_max_test() -> Nil {
  use <- owned_test.run(5000)
  let resources =
    class_resource.new(
      resource: Resource(..resource_of(1), start: 900.0),
      properties: class_resource_support.properties_of(
        class_id: 1,
        changes: [],
        level: 1,
      ),
    )
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
    as "150 a second (a server choice, issue 418), a tick each second (the server's choice): 180 - 150"
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
  let assert Error(refusals) =
    class_resource.select(rows:, tables: fixture_tables.shared())
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
  let assert Error(refusals) =
    class_resource.select(rows:, tables: fixture_tables.shared())
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
  let assert Error(refusals) =
    class_resource.select(rows:, tables: fixture_tables.shared())
  assert list.sort(names_of(refusals), string.compare) == ["1 decay", "6 max"]
}

pub fn a_regen_missing_a_part_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    design_rows()
    |> list.filter(fn(row) {
      !{ row.class_id == 5 && row.name == "regen_tick_ms" }
    })
  let assert Error(refusals) =
    class_resource.select(rows:, tables: fixture_tables.shared())
  assert names_of(refusals) == ["5 regen_tick_ms"]
}

pub fn a_warrior_with_a_drain_row_missing_and_an_esper_without_its_empty_wait_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.filter(design_rows(), fn(row) {
      !{ row.class_id == 1 && row.name == "drain_after_ms" }
      && !{ row.class_id == 3 && row.name == "empty_after_combat_ms" }
    })
  let assert Error(refusals) =
    class_resource.select(rows:, tables: fixture_tables.shared())
  assert list.sort(names_of(refusals), string.compare)
    == ["1 drain_after_ms", "3 empty_after_combat_ms"]
    as "the Warrior's drain needs its amount, period, tick and wait, and the Esper its wait after combat (issue 418)"
}

pub fn a_migrated_database_holds_the_designs_rows_each_with_its_source_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_class_resource.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == design_rows()
    as "the rows of migrations 0011, 0012, 0018 and 0048, in class and name order: the values tables of the designs of issues 403, 418, 419 and 945"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where source in ('client', 'retail_record', 'server_choice')",
    )
    == 22
    as "each row is the client's, a retail record or a server choice"
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
    == 11
    as "the Medic's refill, the three ticks, the Warrior's drain amount, period and wait, the Engineer's empty wait and the three Focus pools are the server's choices"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where name = 'focus_pool' and class_id in (3, 4, 7) and value = 1000 and unit = 'points' and source = 'server_choice'",
    )
    == 3
    as "the Esper, Medic and Spellslinger each hold a flat 1000-point pool, a flat pool the server chose: the level-6 costs of 137 to 152 rule out a pool growing with level"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'decay', 1, 'metres', 'server_choice')",
        "class_resource_unit_is_known",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (32, 'max', 1, 'points', 'server_choice')",
        "class_resource_class_id_is_in_5_bits",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 'NaN', 'points', 'server_choice')",
        "class_resource_value_is_finite",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (5, 'max', 1, 'points', 'server_choice')",
        "class_resource_pkey",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 1, 'points', 'nobody')",
        "class_resource_source_is_a_content_source",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'nobody_listed', 1, 'points', 'server_choice')",
        "class_resource_name_has_its_unit",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 0, 'points', 'server_choice')",
        "class_resource_value_is_positive",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', -1, 'points', 'server_choice')",
        "class_resource_value_is_positive",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'regen_tick_ms', 2.5, 'ms', 'server_choice')",
        "class_resource_time_is_whole_ms",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 10, 'ms', 'server_choice')",
        "class_resource_name_has_its_unit",
      ),
      #(
        "insert into class_resource (class_id, name, value, unit, source) values (6, 'drain_tick_ms', 10, 'points', 'server_choice')",
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

// ---- Focus ----

/// The Focus timer, numbered 14 in `started` and `cancelled`.
const focus_timer = 14

fn focus_tick(resources: Resources) -> #(Resources, List(Effect)) {
  class_resource.timer_fired(resources:, timer: class_resource.focus_timer)
}

fn focus_of(resources: Resources) -> Float {
  class_resource.value(resources:, slot: class_resource.focus_slot)
}

fn near(first: Float, second: Float) -> Bool {
  float.loosely_equals(first, second, tolerating: 0.001)
}

pub fn the_running_timers_are_one_set_and_left_and_died_cancel_each_in_timer_id_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(slinger, _) = pay(resources: new(7), slot: 4, amount: 10)
  let #(slinger, focus_started) = pay(resources: slinger, slot: -1, amount: 15)
  assert started(focus_started) == [#(focus_timer, 500)]
    as "the first Focus payment below the pool starts its timer, GameFormula 88's 500 ms"
  let #(_, left) = class_resource.left(resources: slinger)
  assert cancelled(left) == [regen, focus_timer]
    as "a Spellslinger's slot regeneration (4) and its Focus (14), in timer-id order"
  let #(_, died) = class_resource.died(resources: slinger)
  assert cancelled(died) == [regen, focus_timer]
  let #(medic, refilling) = pay(resources: new(4), slot: 1, amount: 1)
  assert started(refilling) == [#(refill, 3000)]
  let #(_, left) = class_resource.left(resources: medic)
  assert cancelled(left) == [refill] as "a Medic's refill after combat (5)"
  let #(_, none) = class_resource.left(resources: new(5))
  assert none == [] as "no timer running: nothing to cancel"
}

pub fn owns_names_each_timer_of_the_rule_and_no_other_connection_timer_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([4, 5, 6, 7, 14], fn(number) {
    assert class_resource.owns(timer: step.TimerId(number))
      as "the rule's own timers: the regeneration, refill, drain, empty and Focus"
  })
  list.each([1, 2, 3, 8, 9, 10, 11, 12, 13, 1000], fn(number) {
    assert !class_resource.owns(timer: step.TimerId(number))
      as "the save, claim and strike timers (state.gleam, login.gleam, strike.gleam), the life's and the departures' (player_life.gleam, departures.gleam) and the cast rule's from 1000 belong to others"
  })
}

pub fn focus_is_a_second_vital_reached_as_slot_minus_1_and_a_class_slot_payment_never_touches_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(medic, _) = pay(resources: new(4), slot: 1, amount: 1)
  assert focus_of(medic) == 1000.0
    as "a payment of the Medic's slot 1 leaves Focus alone"
  assert class_resource.value(resources: medic, slot: 1) == 3.0
  let #(medic, _) = pay(resources: new(4), slot: -1, amount: 20)
  assert class_resource.value(resources: medic, slot: 1) == 4.0
    as "a payment of Focus leaves the Medic's Actuators alone"
  assert focus_of(medic) == 980.0
  let warrior = new(1)
  assert focus_of(warrior) == 0.0
    && class_resource.max(resources: warrior, slot: -1) == 0.0
    as "a Warrior holds no Focus: a value and a maximum of 0"
  let #(slinger, _) = pay(resources: new(7), slot: 4, amount: 10)
  let #(slinger, _) = pay(resources: slinger, slot: -1, amount: 15)
  assert class_resource.value(resources: slinger, slot: 4) == 90.0
    && focus_of(slinger) == 985.0
    as "a Spellslinger holds Spell Power at slot 4 and Focus at slot -1, each paid apart"
}

pub fn a_new_healer_holds_its_focus_at_the_maximum_of_property_5_and_a_class_with_none_holds_0_test() -> Nil {
  use <- owned_test.run(5000)
  // Class id, what gear adds to property 5, the Focus held and its maximum.
  [
    #(4, 0.0, 1000.0),
    #(3, 0.0, 1000.0),
    #(7, 0.0, 1000.0),
    #(4, 150.0, 1150.0),
    #(1, 0.0, 0.0),
    #(2, 0.0, 0.0),
    #(5, 0.0, 0.0),
  ]
  |> list.each(fn(row) {
    let #(class_id, gear, held) = row
    let changes = case gear {
      0.0 -> []
      points -> [#(5, class_resource_support.focus_pool_of(class_id) +. points)]
    }
    let resources =
      class_resource_support.resources_with(class_id:, changes:, level: 1)
    assert focus_of(resources) == held
      as "full at entry (a server choice): the maximum of property 5, the pool plus gear; a class with no Focus holds 0"
    assert class_resource.max(resources:, slot: -1) == held
  })
}

pub fn a_focus_payment_lowers_the_pool_by_the_points_and_sends_one_change_and_a_payment_below_the_maximum_starts_the_timer_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(medic, first) = pay(resources: new(4), slot: -1, amount: 15)
  assert first
    == [
      Changed(slot: -1, value: 985.0),
      StartTimer(timer: class_resource.focus_timer, after_ms: 500),
    ]
    as "0x935 of stat 1 (opcode.0x935), and the first tick GameFormula 88 dataint0 later"
  let #(_, second) = pay(resources: medic, slot: -1, amount: 10)
  assert second == [Changed(slot: -1, value: 975.0)]
    as "a second payment starts no second timer"
  let #(emptied, over) = pay(resources: new(4), slot: -1, amount: 1200)
  assert focus_of(emptied) == 0.0
  assert over
    == [
      Changed(slot: -1, value: 0.0),
      StartTimer(timer: class_resource.focus_timer, after_ms: 500),
    ]
    as "a payment past the pool clamps at 0"
  let #(warrior, ignored) = pay(resources: new(1), slot: -1, amount: 15)
  assert ignored == [] && focus_of(warrior) == 0.0
    as "a class with no Focus ignores a payment of it"
}

pub fn each_500_ms_tick_adds_the_maximum_times_the_share_times_one_half_and_stops_at_full_test() -> Nil {
  use <- owned_test.run(5000)
  let again = StartTimer(timer: class_resource.focus_timer, after_ms: 500)
  // Name, properties changed, in combat, points paid, then what the tick sends.
  [
    #("out of combat", [], False, 100, [Changed(-1, 905.5), again]),
    #("in combat, no rating", [], True, 100, [Changed(-1, 905.5), again]),
    #("a pool of 1500", [#(5, 1500.0)], False, 100, [
      Changed(-1, 1408.25),
      again,
    ]),
    #("a value of 998", [], False, 2, [Changed(-1, 1000.0)]),
  ]
  |> list.each(fn(row) {
    let #(name, changes, in_combat, paid, sent) = row
    let resources =
      class_resource_support.resources_with(class_id: 4, changes:, level: 1)
    let #(resources, _) = class_resource.combat_changed(resources:, in_combat:)
    let #(resources, _) = pay(resources:, slot: -1, amount: paid)
    let #(_, effects) = focus_tick(resources)
    assert effects == sent
      as {
        name
        <> ": maximum x 0.011 x 500 ms x 0.001 (UnitProperty2 107 and 108 defaults, GameFormula 88), clamped to the maximum, a full pool starting no timer"
      }
  })
  let #(_, full) = focus_tick(new(4))
  assert full == [] as "a full pool with no timer running sends nothing"
}

pub fn a_combat_flag_change_changes_the_share_at_the_next_tick_and_restarts_no_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let medic =
    class_resource_support.resources_with(
      class_id: 4,
      changes: [#(6, 450.0)],
      level: 6,
    )
  let #(medic, _) = pay(resources: medic, slot: -1, amount: 100)
  let #(medic, entered) =
    class_resource.combat_changed(resources: medic, in_combat: True)
  assert entered == [] as "combat starting restarts no timer and sends nothing"
  let #(medic, in_combat) = focus_tick(medic)
  assert changes(in_combat) == [#(-1, 909.25)]
    as "rating 450 at level 6 on base 0.011: 0.0075 + 0.011 of 1000 x 0.5 = 9.25"
  let #(medic, left) =
    class_resource.combat_changed(resources: medic, in_combat: False)
  assert left == [] as "combat ending restarts no timer"
  let #(_, out_of_combat) = focus_tick(medic)
  assert changes(out_of_combat) == [#(-1, 914.75)]
    as "out of combat property 108 alone: 5.5 (GetFocusRegenNonCombat 0x14064ac80)"
  let #(slinger, _) = pay(resources: new(7), slot: 4, amount: 10)
  let #(slinger, _) = pay(resources: slinger, slot: -1, amount: 100)
  let #(slinger, entered) =
    class_resource.combat_changed(resources: slinger, in_combat: True)
  let #(slinger, left) =
    class_resource.combat_changed(resources: slinger, in_combat: False)
  assert entered == [] && left == []
    as "the Spellslinger's slot regenerates in and out of combat: combat touches neither timer"
  let #(_, cancels) = class_resource.left(resources: slinger)
  assert cancelled(cancels) == [regen, focus_timer]
}

pub fn a_spellslinger_regenerates_spell_power_and_focus_on_two_timers_neither_starting_or_stopping_the_other_test() -> Nil {
  use <- owned_test.run(5000)
  let #(slinger, slot_started) = pay(resources: new(7), slot: 4, amount: 10)
  assert started(slot_started) == [#(regen, 1000)]
  let #(slinger, focus_started) = pay(resources: slinger, slot: -1, amount: 15)
  assert started(focus_started) == [#(focus_timer, 500)]
    as "both below their maximums: two timers"
  let #(slinger, slot_tick) = tick(slinger)
  assert started(slot_tick) == [#(regen, 1000)] && cancelled(slot_tick) == []
    as "the slot's tick restarts its own timer and leaves Focus's running"
  let #(slinger, focus_ticked) = focus_tick(slinger)
  assert started(focus_ticked) == [#(focus_timer, 500)]
    && changes(focus_ticked) == [#(-1, 990.5)]
  let #(_, cancels) = class_resource.left(resources: slinger)
  assert cancelled(cancels) == [regen, focus_timer]
  let #(slinger, _) = pay(resources: new(7), slot: 4, amount: 10)
  let #(slinger, _) = pay(resources: slinger, slot: -1, amount: 2)
  let #(slinger, full) = focus_tick(slinger)
  assert full == [Changed(slot: -1, value: 1000.0)]
    as "998 + 5.5 clamps to the pool: one change and no restart"
  let #(_, cancels) = class_resource.left(resources: slinger)
  assert cancelled(cancels) == [regen]
    as "Focus at its maximum stopped its timer and left the slot's"
}

pub fn a_maximum_that_falls_below_the_value_clamps_it_with_one_change_and_one_that_rises_starts_the_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let followed = fn(resources, maximum) {
    class_resource.properties_followed(
      resources:,
      properties: class_resource_support.properties_of(
        class_id: 4,
        changes: [#(5, maximum)],
        level: 1,
      ),
    )
  }
  let #(medic, _) = pay(resources: new(4), slot: -1, amount: 50)
  let #(medic, lowered) = followed(medic, 900.0)
  assert lowered
    == [
      Changed(slot: -1, value: 900.0),
      CancelTimer(timer: class_resource.focus_timer),
    ]
    as "1000 to 900 at 950 held: one 0x935 at the new maximum, and the timer of a pool now full stops"
  assert class_resource.max(resources: medic, slot: -1) == 900.0
  let #(_, raised) = followed(new(4), 1100.0)
  assert raised
    == [StartTimer(timer: class_resource.focus_timer, after_ms: 500)]
    as "1000 to 1100 at 1000 held: below the new maximum, no change to send"
  let #(medic, _) = pay(resources: new(4), slot: -1, amount: 200)
  let #(_, kept) = followed(medic, 900.0)
  assert kept == [] as "a lowered maximum above the value held changes nothing"
}

type Moved {
  Moved(
    name: String,
    properties: List(#(Int, Float)),
    level: Int,
    in_combat: Bool,
    maximum: Float,
    tick_adds: Float,
    needed_for_100: Int,
  )
}

pub fn each_property_the_focus_vital_reads_changes_its_number_when_the_properties_follow_test() -> Nil {
  use <- owned_test.run(5000)
  let none = Moved("none moved", [], 1, False, 1000.0, 5.5, 100)
  [
    none,
    Moved(
      ..none,
      name: "5 BaseFocusPool",
      properties: [#(5, 1500.0)],
      maximum: 1500.0,
      tick_adds: 8.25,
    ),
    Moved(
      ..none,
      name: "6 RatingFocusRecovery in combat",
      properties: [#(6, 450.0)],
      level: 6,
      in_combat: True,
      tick_adds: 9.25,
    ),
    Moved(..none, name: "6 out of combat", properties: [#(6, 450.0)], level: 6),
    Moved(
      ..none,
      name: "6 at level 50: a lower curve",
      properties: [#(6, 450.0)],
      level: 50,
      in_combat: True,
      tick_adds: 5.95,
    ),
    Moved(
      ..none,
      name: "56 RatingIntensity",
      properties: [#(56, 300.0)],
      level: 6,
      needed_for_100: 107,
    ),
    Moved(
      ..none,
      name: "158 BaseIntensity",
      properties: [#(158, 0.5)],
      needed_for_100: 150,
    ),
    Moved(
      ..none,
      name: "107 BaseFocusRecoveryInCombat in combat",
      properties: [#(107, 0.02)],
      in_combat: True,
      tick_adds: 10.0,
    ),
    Moved(..none, name: "107 out of combat", properties: [#(107, 0.02)]),
    Moved(
      ..none,
      name: "108 BaseFocusRecoveryOutofCombat out of combat",
      properties: [#(108, 0.02)],
      tick_adds: 10.0,
    ),
    Moved(
      ..none,
      name: "108 in combat",
      properties: [#(108, 0.02)],
      in_combat: True,
    ),
    Moved(
      ..none,
      name: "135 FocusCostModifier",
      properties: [#(135, 0.5)],
      needed_for_100: 50,
    ),
  ]
  |> list.each(fn(row) {
    let #(resources, _) = pay(resources: new(4), slot: -1, amount: 500)
    let #(resources, _) =
      class_resource.combat_changed(resources:, in_combat: row.in_combat)
    let #(resources, _) =
      class_resource.properties_followed(
        resources:,
        properties: class_resource_support.properties_of(
          class_id: 4,
          changes: row.properties,
          level: row.level,
        ),
      )
    assert class_resource.max(resources:, slot: -1) == row.maximum
      as {
        row.name
        <> ": the maximum is property 5's value (GetMaxFocus 0x14064a810)"
      }
    let before = focus_of(resources)
    let #(resources, _) = focus_tick(resources)
    assert near(focus_of(resources) -. before, row.tick_adds)
      as {
        row.name
        <> ": the tick adds the maximum x the share x 0.5 (FUN_1404602f0, 0x14064ac80)"
      }
    assert class_resource.focus_required(resources:, amount: 100)
      == row.needed_for_100
      as {
        row.name
        <> ": the cost is int(m x 100 + 0.5), m from properties 135, 56 and 158 (FUN_140462a90)"
      }
  })
  let held = new(4)
  let #(same, nothing) =
    class_resource.properties_followed(
      resources: held,
      properties: class_resource_support.properties_of(
        class_id: 4,
        changes: [],
        level: 1,
      ),
    )
  assert nothing == [] && same == held
    as "a follow with nothing changed sends nothing"
}

pub fn death_cancels_the_timers_coming_back_refills_to_the_maximum_and_a_timer_after_the_cancel_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(medic, _) = pay(resources: new(4), slot: -1, amount: 100)
  let #(medic, died) = class_resource.died(resources: medic)
  assert cancelled(died) == [focus_timer] && changes(died) == []
    as "death cancels the running Focus timer and sends nothing"
  let #(medic, late) = focus_tick(medic)
  assert late == [] as "a tick that fires after death changes nothing"
  assert focus_of(medic) == 900.0
  let #(medic, back) = class_resource.came_back(resources: medic)
  assert back == [Changed(slot: -1, value: 1000.0)]
    as "back at the maximum, as health and shield come back full"
  let #(medic, late) = focus_tick(medic)
  assert late == [] as "a stale tick after coming back changes nothing"
  let #(medic, died) = class_resource.died(resources: medic)
  assert died == []
  let #(medic, back) = class_resource.came_back(resources: medic)
  assert back == [] as "coming back at the maximum sends nothing"
  let #(medic, _) = pay(resources: medic, slot: -1, amount: 100)
  let #(medic, left) = class_resource.left(resources: medic)
  assert cancelled(left) == [focus_timer] && changes(left) == []
    as "leaving cancels the timer and sends nothing"
  let #(_, late) = focus_tick(medic)
  assert late == [] as "a tick after leaving changes nothing"
}

type Event {
  PayFocus(points: Int)
  FocusTicks
  MaximumBecomes(points: Float)
  CombatChanges(in_combat: Bool)
  Dies
  ComesBack
  PaySpellPower(points: Int)
  SpellPowerTicks
}

fn event_of(drawn: #(Int, Int)) -> Event {
  let #(kind, number) = drawn
  case kind {
    0 -> PayFocus(points: number)
    1 -> FocusTicks
    2 -> MaximumBecomes(points: int.to_float(500 + number % 1001))
    3 -> CombatChanges(in_combat: number % 2 == 0)
    4 -> Dies
    5 -> ComesBack
    6 -> PaySpellPower(points: number % 30)
    _ -> SpellPowerTicks
  }
}

/// The Spellslinger after the event, the Focus maximum it holds and whether it lives.
fn after(
  event event: Event,
  state state: #(Resources, Float, Bool),
) -> #(Resources, Float, Bool) {
  let #(resources, maximum, alive) = state
  case event {
    PayFocus(points:) -> #(
      pay(resources:, slot: -1, amount: points).0,
      maximum,
      alive,
    )
    FocusTicks -> #(focus_tick(resources).0, maximum, alive)
    MaximumBecomes(points:) -> #(
      class_resource.properties_followed(
        resources:,
        properties: class_resource_support.properties_of(
          class_id: 7,
          changes: [#(5, points)],
          level: 1,
        ),
      ).0,
      points,
      alive,
    )
    CombatChanges(in_combat:) -> #(
      class_resource.combat_changed(resources:, in_combat:).0,
      maximum,
      alive,
    )
    Dies -> #(class_resource.died(resources:).0, maximum, False)
    ComesBack -> #(class_resource.came_back(resources:).0, maximum, True)
    PaySpellPower(points:) -> #(
      pay(resources:, slot: 4, amount: points).0,
      maximum,
      alive,
    )
    SpellPowerTicks -> #(tick(resources).0, maximum, alive)
  }
}

pub fn focus_stays_between_0_and_the_maximum_through_any_sequence_of_payments_ticks_and_property_changes_test() -> Nil {
  use <- owned_test.run(30_000)
  qcheck.given(
    qcheck.list_from(qcheck.tuple2(
      qcheck.bounded_int(from: 0, to: 7),
      qcheck.bounded_int(from: 0, to: 1200),
    )),
    fn(drawn) {
      list.fold(
        list.map(drawn, event_of),
        #(new(7), 1000.0, True),
        fn(state, event) {
          let #(resources, maximum, alive) = after(event:, state:)
          let held = focus_of(resources)
          assert held >=. 0.0 && held <=. maximum
            as "Focus stays within [0, the maximum]"
          let spell_power = class_resource.value(resources:, slot: 4)
          assert spell_power >=. 0.0 && spell_power <=. 100.0
            as "the Spellslinger's slot behaves as before"
          let running =
            list.contains(
              cancelled(class_resource.left(resources:).1),
              focus_timer,
            )
          assert running == { alive && held <. maximum }
            as "the Focus timer runs exactly while the pool is below its maximum and the player lives"
          #(resources, maximum, alive)
        },
      )
      Nil
    },
  )
}

pub fn a_class_that_holds_focus_with_no_pool_row_is_refused_by_name_and_a_pool_row_of_another_class_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let without =
    list.filter(design_rows(), fn(row) {
      !{ row.class_id == 4 && row.name == "focus_pool" }
    })
  let assert Error([refused]) =
    class_resource.select(rows: without, tables: fixture_tables.shared())
  assert refused
    == Refusal(
      table: "class_resource",
      row: RowName("4 focus_pool"),
      rule: "the table has no such row, which this class needs",
    )
    as "the Medic's level grants cost Focus, so it needs its pool"
  let with_extra =
    list.append(design_rows(), [
      Row(class_id: 1, name: "focus_pool", value: 1000.0, unit: "points"),
    ])
  let assert Error([refused]) =
    class_resource.select(rows: with_extra, tables: fixture_tables.shared())
  assert refused
    == Refusal(
      table: "class_resource",
      row: RowName("1 focus_pool"),
      rule: "the server holds no Focus for that class",
    )
    as "no level grant of the Warrior costs Focus"
}

/// Whether a Spell4 row costs Focus (type 15) in either innate column.
fn costs_focus(row row: spell4.Spell4) -> Bool {
  { row.innate_cost_type0 == 15 && row.innate_cost0 != 0 }
  || { row.innate_cost_type1 == 15 && row.innate_cost1 != 0 }
}

/// The Spell4Base ids of the level grants (no prerequisite) of the class whose Spell4 costs
/// Focus.
fn focus_grant_bases(
  tables tables: table_store.Tables,
  class_id class_id: Int,
) -> set.Set(Int) {
  list.filter_map(spell_level.all(tables), fn(grant) {
    let ClassId(grant_class) = spell_level.class_id(grant)
    let assert Ok(row) = spell4.get(tables:, id: spell_level.spell4_id(grant))
      as "a level grant names a Spell4 row"
    case
      grant_class == class_id && grant.prerequisite_id == 0 && costs_focus(row:)
    {
      True -> Ok(row.spell4_base_id_base_spell)
      False -> Error(Nil)
    }
  })
  |> set.from_list
}

pub fn the_classes_that_hold_focus_are_those_whose_level_grants_cost_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // Per class that has any: the number of bases of its level grants that cost Focus.
  let by_class =
    list.filter_map(class_resource.playable_class_ids(), fn(class_id) {
      case set.size(focus_grant_bases(tables:, class_id:)) {
        0 -> Error(Nil)
        count -> Ok(#(class_id, count))
      }
    })
  assert by_class == [#(3, 11), #(4, 10), #(7, 10)]
    as "Esper, Medic and Spellslinger: SpellLevel rows with no prerequisite whose Spell4 costs type 15"
  assert class_resource.focus_class_ids() == [3, 4, 7]
    as "the classes the server gives a pool are those the tables say"
}

// ---- Focus and class vital gains ----

fn gained(
  resources resources: Resources,
  gains gains: List(class_resource.Gain),
) -> #(Resources, List(Effect)) {
  class_resource.gain(resources:, gains:)
}

/// A healer of the class whose Focus maximum is `pool` and who holds `held` (below it) of it,
/// its Focus timer running.
fn holding_focus(
  class_id class_id: Int,
  pool pool: Float,
  held held: Int,
) -> Resources {
  pay(
    resources: class_resource_support.resources_with(
      class_id:,
      changes: [#(5, pool)],
      level: 1,
    ),
    slot: -1,
    amount: float.truncate(pool) - held,
  ).0
}

pub fn a_focus_gain_raises_the_pool_by_points_or_a_share_of_the_maximum_clamps_keeps_the_timer_and_changes_nothing_for_the_dead_or_a_class_with_none_test() -> Nil {
  use <- owned_test.run(5000)
  let focus_timer = class_resource.focus_timer
  let dead =
    class_resource.died(resources: holding_focus(
      class_id: 4,
      pool: 1000.0,
      held: 500,
    )).0
  // Name, the resources, the gains, the changes (slot, value) and the timers started and
  // cancelled. Points are dataBits02; a share is the fraction of the maximum, 0.04 for
  // Meditate (text 243889 "Restore 4% of your maximum Focus"): 40 of 1000, 50 of 1250.
  [
    #(
      "points",
      holding_focus(class_id: 4, pool: 1000.0, held: 500),
      [Gain(slot: -1, amount: 80)],
      [#(-1, 580.0)],
      [],
      [],
      "80 points of Focus (Rations): one change; the timer already runs below the pool",
    ),
    #(
      "a share of 1000",
      holding_focus(class_id: 4, pool: 1000.0, held: 500),
      [class_resource.FocusShare(share: 0.04)],
      [#(-1, 540.0)],
      [],
      [],
      "4 percent of a maximum of 1000 is 40",
    ),
    #(
      "a share of 1250",
      holding_focus(class_id: 4, pool: 1250.0, held: 500),
      [class_resource.FocusShare(share: 0.04)],
      [#(-1, 550.0)],
      [],
      [],
      "4 percent of an item-raised maximum of 1250 is 50, not 40: the share is of property 5's value",
    ),
    #(
      "a gain that fills the pool",
      holding_focus(class_id: 4, pool: 1000.0, held: 990),
      [Gain(slot: -1, amount: 50)],
      [#(-1, 1000.0)],
      [],
      [focus_timer],
      "990 + 50 is clamped to the 1000 maximum, and the full pool needs no timer",
    ),
    #(
      "a share that fills the pool",
      holding_focus(class_id: 4, pool: 1000.0, held: 900),
      [class_resource.FocusShare(share: 1.0)],
      [#(-1, 1000.0)],
      [],
      [focus_timer],
      "a share of 1.0 is the whole maximum",
    ),
    #(
      "a share of 0",
      holding_focus(class_id: 4, pool: 1000.0, held: 500),
      [class_resource.FocusShare(share: 0.0)],
      [],
      [],
      [],
      "nothing moved: no change is sent",
    ),
    #(
      "the dead",
      dead,
      [Gain(slot: -1, amount: 80), class_resource.FocusShare(share: 0.04)],
      [],
      [],
      [],
      "a dead player gains nothing (the guard stands before the Focus branch)",
    ),
    #(
      "a class with no Focus: points",
      new(1),
      [Gain(slot: -1, amount: 80)],
      [],
      [],
      [],
      "a Warrior holds 0 of a maximum of 0 and ignores the gain",
    ),
    #(
      "a class with no Focus: a share",
      new(1),
      [class_resource.FocusShare(share: 0.04)],
      [],
      [],
      [],
      "a Warrior ignores a share too",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, resources, gains, expected, starts, cancels, why) = row
    let #(_, effects) = gained(resources:, gains:)
    assert changes(effects) == expected as { name <> ": " <> why }
    assert started(effects) == list.map(starts, fn(timer) { #(14, timer) })
      as { name <> ": no timer starts" }
    assert list.filter(effects, fn(effect) {
        effect == CancelTimer(timer: focus_timer)
      })
      == list.map(cancels, fn(timer) { CancelTimer(timer:) })
      as {
        name <> ": the Focus timer is cancelled exactly when the pool fills"
      }
  })
}

pub fn a_class_vital_gain_goes_to_the_slot_naming_the_vital_clamps_at_each_step_and_is_dropped_by_a_class_without_it_test() -> Nil {
  use <- owned_test.run(5000)
  let medic_holding = fn(actuators) {
    class_resource.new(
      resource: Resource(..resource_of(4), start: actuators),
      properties: class_resource_support.properties_of(
        class_id: 4,
        changes: [],
        level: 1,
      ),
    )
  }
  let #(spent, step_changes) =
    gained(resources: medic_holding(2.0), gains: [
      class_resource.ClassVitalGain(vital: 18, amount: -4),
      class_resource.ClassVitalGain(vital: 18, amount: 2),
    ])
  // Class.vitalEnumResource01 is 18 for the Medic (slot 1), 4 for the Warrior (slot 1), 19
  // for the Spellslinger at slot 4 (vitalEnumResource04) and 0 for the Esper's slot 1.
  assert changes(step_changes) == [#(1, 0.0), #(1, 2.0)]
    as "2 Actuators less 4 clamp at 0, then the +2 lands: the order of the rows decides the 2 left"
  assert class_resource.value(resources: spent, slot: 1) == 2.0
  let #(slinger, _) = pay(resources: new(7), slot: 4, amount: 50)
  [
    #(
      "an Esper does not hold vital 18",
      new(3),
      class_resource.ClassVitalGain(vital: 18, amount: 3),
      [],
    ),
    #(
      "a Spellslinger's vital 19 lands in slot 4 (stat 6)",
      slinger,
      class_resource.ClassVitalGain(vital: 19, amount: 30),
      [#(4, 80.0)],
    ),
    #(
      "a Spellslinger does not hold vital 4",
      slinger,
      class_resource.ClassVitalGain(vital: 4, amount: 30),
      [],
    ),
    #(
      "a Warrior's vital 4 lands in slot 1",
      new(1),
      class_resource.ClassVitalGain(vital: 4, amount: 50),
      [#(1, 50.0)],
    ),
    #(
      "a Warrior does not hold vital 19",
      new(1),
      class_resource.ClassVitalGain(vital: 19, amount: 50),
      [],
    ),
  ]
  |> list.each(fn(row) {
    let #(name, resources, gain, expected) = row
    assert changes(gained(resources:, gains: [gain]).1) == expected as name
  })
}

pub fn one_call_with_a_class_vital_gain_and_a_focus_share_changes_the_class_slot_first_and_a_focus_only_gain_restarts_no_drain_test() -> Nil {
  use <- owned_test.run(5000)
  let recharge = [
    class_resource.FocusShare(share: 0.05),
    class_resource.ClassVitalGain(vital: 18, amount: -4),
  ]
  let medic =
    class_resource.new(
      resource: Resource(..resource_of(4), start: 2.0),
      properties: class_resource_support.properties_of(
        class_id: 4,
        changes: [],
        level: 1,
      ),
    )
  let medic = pay(resources: medic, slot: -1, amount: 500).0
  let #(_, effects) = gained(resources: medic, gains: recharge)
  assert changes(effects) == [#(1, 0.0), #(-1, 550.0)]
    as "Recharge's pair, listed Focus first: the class slot changes first, then Focus, one change each"
  // A resource that drains (the Warrior's) and holds Focus: no class has both, so the
  // Warrior's row takes a Medic's Focus.
  let draining =
    class_resource.new(
      resource: Resource(..resource_of(1), focus: resource_of(4).focus),
      properties: class_resource_support.properties_of(
        class_id: 4,
        changes: [],
        level: 1,
      ),
    )
  let draining = pay(resources: draining, slot: -1, amount: 500).0
  let drain_timer = class_resource.drain_timer
  let #(_, focus_only) =
    gained(resources: draining, gains: [class_resource.FocusShare(share: 0.05)])
  assert changes(focus_only) == [#(-1, 550.0)]
  assert !list.contains(
    list.map(focus_only, fn(effect) {
      case effect {
        StartTimer(timer:, ..) | CancelTimer(timer:) -> Ok(timer)
        Changed(..) -> Error(Nil)
      }
    }),
    Ok(drain_timer),
  )
    as "a gain of Focus alone is no gain of the slot: the drain's wait is not restarted"
  let #(_, with_slot) =
    gained(resources: draining, gains: [
      class_resource.FocusShare(share: 0.05),
      Gain(slot: 1, amount: 180),
    ])
  assert started(with_slot) == [#(6, 1500)]
    as "a gain that lands in the class slot restarts the drain's wait, whatever else the call holds"
}
