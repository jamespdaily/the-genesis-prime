//// The classes' resources the tests' connections are made with: the rows of
//// migration 0011, as the step's design gives them (issue 403, the Design
//// artifact's values table), selected as the content load selects them. A test's
//// expected values name the design or the client, never this module.

import genesis_prime/game/class_resource.{type Classes, type Resource, Row}
import genesis_prime/table/id.{ClassId}

/// The rows of migration 0011.
pub fn rows() -> List(class_resource.Row) {
  [
    Row(class_id: 1, name: "max", value: 1000.0, unit: "points"),
    Row(class_id: 2, name: "max", value: 100.0, unit: "points"),
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
  let assert Ok(classes) = class_resource.select(rows: rows())
    as "migration 0011's rows select"
  classes
}

/// The resource of the class with this Class id.
pub fn resource_of(class_id: Int) -> Resource {
  let assert Ok(resource) =
    class_resource.of_class(classes: classes(), class_id: ClassId(class_id))
    as "a playable class has a resource"
  resource
}
