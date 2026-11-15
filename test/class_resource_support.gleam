//// The classes' resources the tests' connections are made with: the rows of
//// migrations 0011, 0012 and 0018, as the steps' designs give them (issues 403, 418
//// and 419, their Design artifacts' values), selected as the content load selects
//// them. A test's expected values name the design or the client, never this module.

import fixture_tables
import genesis_prime/game/class_resource.{type Classes, type Resource, Row}
import genesis_prime/table/id.{ClassId}
import gleam/list

/// The rows of migrations 0011, 0012 and 0018, in class and name order.
pub fn rows() -> List(class_resource.Row) {
  [
    Row(class_id: 1, name: "drain_after_ms", value: 1500.0, unit: "ms"),
    Row(class_id: 1, name: "drain_amount", value: 150.0, unit: "points"),
    Row(class_id: 1, name: "drain_period_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 1, name: "drain_tick_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 1, name: "max", value: 1000.0, unit: "points"),
    Row(class_id: 2, name: "empty_after_combat_ms", value: 5000.0, unit: "ms"),
    Row(class_id: 2, name: "max", value: 100.0, unit: "points"),
    Row(class_id: 3, name: "empty_after_combat_ms", value: 10_000.0, unit: "ms"),
    Row(class_id: 3, name: "max", value: 5.0, unit: "points"),
    Row(class_id: 4, name: "max", value: 4.0, unit: "points"),
    Row(class_id: 4, name: "refill_after_combat_ms", value: 3000.0, unit: "ms"),
    Row(class_id: 5, name: "max", value: 100.0, unit: "points"),
    Row(class_id: 5, name: "regen_amount", value: 7.0, unit: "points"),
    Row(class_id: 5, name: "regen_period_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 5, name: "regen_tick_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 7, name: "max", value: 100.0, unit: "points"),
    Row(class_id: 7, name: "regen_amount", value: 25.0, unit: "points"),
    Row(class_id: 7, name: "regen_period_ms", value: 12_000.0, unit: "ms"),
    Row(class_id: 7, name: "regen_tick_ms", value: 1000.0, unit: "ms"),
  ]
}

/// The rows selected.
pub fn classes() -> Classes {
  let assert Ok(classes) =
    class_resource.select(rows: rows(), tables: fixture_tables.shared())
    as "the migrations' rows select"
  classes
}

/// The rows selected with the Spellslinger's slot emptied `empty_after_combat_ms`
/// after combat ends (10 000 ms, as the Esper's): test data, since the Spellslinger
/// has no such wait, that gives a test a way to empty Spell Power through its timer.
pub fn spellslinger_emptying_after_combat() -> Classes {
  let assert Ok(classes) =
    class_resource.select(
      rows: list.append(rows(), [
        Row(
          class_id: 7,
          name: "empty_after_combat_ms",
          value: 10_000.0,
          unit: "ms",
        ),
      ]),
      tables: fixture_tables.shared(),
    )
    as "the planted rows and the wait select"
  classes
}

/// The resource of the class with this Class id.
pub fn resource_of(class_id: Int) -> Resource {
  let assert Ok(resource) =
    class_resource.of_class(classes: classes(), class_id: ClassId(class_id))
    as "a playable class has a resource"
  resource
}
