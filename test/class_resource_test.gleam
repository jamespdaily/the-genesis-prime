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
//// - The design's rows of migration 0011, with their names and units.

import class_resource_support
import content_support
import database_support
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/class_resource.{
  type Effect, type Resource, type Resources, CancelTimer, Changed, Payment, Row,
  StartTimer,
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
  let class_resource_timer = timer
  let assert True = class_resource.owns(timer: class_resource_timer)
    as "the rule starts only its own timers"
  case class_resource_timer == class_resource.regen_timer {
    True -> 1
    False -> 2
  }
}

/// The regen timer, numbered 1 in `started` and `cancelled`.
const regen = 1

/// The refill timer, numbered 2.
const refill = 2

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

// ---- 14: the content rows ----

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

pub fn an_unknown_class_name_or_unit_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.append(design_rows(), [
      Row(class_id: 6, name: "max", value: 10.0, unit: "points"),
      Row(class_id: 1, name: "decay", value: 10.0, unit: "points"),
    ])
    |> list.map(fn(row) {
      case row.class_id == 2 && row.name == "max" {
        True -> Row(..row, unit: "ms")
        False -> row
      }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert list.sort(names_of(refusals), string.compare)
    == ["1 decay", "2 max", "6 max"]
}

pub fn a_regen_missing_a_part_or_a_value_not_above_0_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    design_rows()
    |> list.filter(fn(row) {
      !{ row.class_id == 5 && row.name == "regen_tick_ms" }
    })
    |> list.map(fn(row) {
      case row.class_id, row.name {
        4, "refill_after_combat_ms" -> Row(..row, value: 0.0)
        7, "regen_tick_ms" -> Row(..row, value: 2.5)
        3, "max" -> Row(..row, value: -1.0)
        _, _ -> row
      }
    })
  let assert Error(refusals) = class_resource.select(rows:)
  assert list.sort(names_of(refusals), string.compare)
    == [
      "3 max",
      "4 refill_after_combat_ms",
      "5 regen_tick_ms",
      "7 regen_tick_ms",
    ]
}

pub fn a_migrated_database_holds_the_designs_rows_each_with_its_source_and_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_class_resource.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == design_rows()
    as "migration 0011's rows, in class and name order: the design's values table"
  assert content_support.count(
      database:,
      sql: "select count(*) from class_resource where source in ('client', 'retail_record', 'server_choice') and reason is not null",
    )
    == 13
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
    == 3
    as "the Medic's refill and the two ticks are the server's choices"
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
        "insert into class_resource (class_id, name, value, unit, source, reason) values (6, 'max', 1, 'metres', 'server_choice', 'x')",
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
