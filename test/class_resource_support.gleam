//// The classes' resources the tests' connections are made with: the rows of
//// migrations 0011, 0012, 0018 and 0048, as the steps' designs give them (issues 403,
//// 418, 419 and 945, their values), selected as the content load selects them, and
//// the player's properties a class enters with. A test's expected values name the
//// design or the client, never this module.

import fixture_tables
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/shared/class_resource.{
  type Classes, type Resource, type Resources, Row,
}
import genesis_prime/shared/unit_properties.{type Properties}
import genesis_prime/table/id.{ClassId}
import gleam/list
import gleam/result
import properties_support

/// The rows of migrations 0011, 0012, 0018 and 0048, in class and name order.
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
    Row(class_id: 3, name: "focus_pool", value: 1000.0, unit: "points"),
    Row(class_id: 3, name: "max", value: 5.0, unit: "points"),
    Row(class_id: 4, name: "focus_pool", value: 1000.0, unit: "points"),
    Row(class_id: 4, name: "max", value: 4.0, unit: "points"),
    Row(class_id: 4, name: "refill_after_combat_ms", value: 3000.0, unit: "ms"),
    Row(class_id: 5, name: "max", value: 100.0, unit: "points"),
    Row(class_id: 5, name: "regen_amount", value: 7.0, unit: "points"),
    Row(class_id: 5, name: "regen_period_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 5, name: "regen_tick_ms", value: 1000.0, unit: "ms"),
    Row(class_id: 7, name: "focus_pool", value: 1000.0, unit: "points"),
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

/// The base pool of Focus the rows give the class, 0 for a class with no row.
pub fn focus_pool_of(class_id: Int) -> Float {
  list.find(rows(), fn(row) {
    row.class_id == class_id && row.name == "focus_pool"
  })
  |> result.map(fn(row) { row.value })
  |> result.unwrap(0.0)
}

/// A level-`level` player's properties as entry makes them for the class: every
/// UnitProperty2 default, with property 5 (BaseFocusPool) at the class's pool, the
/// dash's two (38 ResourceMax_7 at 200, the maximum the client's rows give: eight spells
/// take 200 off it to disable dashing and four add 100, and 39 ResourceRegenMultiplier_7
/// at 1, the factor the refill is multiplied by) and each of `changes` (property id,
/// base and value alike) in place of what is there.
pub fn properties_of(
  class_id class_id: Int,
  changes changes: List(#(Int, Float)),
  level level: Int,
) -> Properties {
  let pool = case focus_pool_of(class_id) {
    0.0 -> [#(38, 200.0), #(39, 1.0)]
    points -> [#(5, points), #(38, 200.0), #(39, 1.0)]
  }
  let kept =
    list.filter(pool, fn(entry) {
      !list.any(changes, fn(change) { change.0 == entry.0 })
    })
  unit_properties.new(
    defaults: properties_support.defaults(),
    listed: list.map(list.append(kept, changes), fn(entry) {
      let bits = float32.to_bits(entry.1)
      UnitProperty(property_id: entry.0, base: bits, value: bits)
    }),
    level:,
  )
}

/// A level-1 player of the class as it enters the world with no gear and no modifier.
pub fn resources_of(class_id: Int) -> Resources {
  resources_with(class_id:, changes: [], level: 1)
}

/// A player of the class entering the world at `level` with these properties changed
/// (`properties_of`).
pub fn resources_with(
  class_id class_id: Int,
  changes changes: List(#(Int, Float)),
  level level: Int,
) -> Resources {
  class_resource.new(
    resource: resource_of(class_id),
    properties: properties_of(class_id:, changes:, level:),
  )
}

/// A player entering the world with this resource and no property changed: every
/// UnitProperty2 default at level 1, so a class that holds Focus holds none (property 5
/// at 0). For tests of a resource that is not about Focus.
pub fn new(resource resource: Resource) -> Resources {
  class_resource.new(resource:, properties: properties_support.fresh(level: 1))
}
