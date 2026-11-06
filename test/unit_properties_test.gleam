//// A player's properties (`genesis_prime/game/unit_properties`). Expected values come
//// from these places:
//// - `Spell4Effects.effectType.11.change`: a modifier changes x to
////   x * dataBits02 + dataBits03 (+ dataBits04 * level); Sprint 1921 (1.0, 0.5) and
////   42597 (0.0, 1.5) both give 1.5 from MoveSpeedMultiplier's default 1.0, and
////   135954 (1.0, 0.08) raises BaseCritChance by 0.08.
//// - `UnitProperty2` defaults (`table_rows -- UnitProperty2 7 41 100 102 127 134`):
////   BaseHealth 1.0, ShieldCapacityMax 0.0, MoveSpeedMultiplier 1.0, BaseCritChance
////   0.0, CriticalHitSeverityMultiplier 1.5, FallingDamageMultiplier 1.0.
//// - The server's choices, which the module's doc names: several modifiers on one
////   property apply to the base in the order they started, and one source is held
////   once.
//// - `opcode.0x93a`: an entry is the id, then the base and the value as 32-bit floats.

import client_tables
import genesis_prime/game/unit_properties.{
  type Properties, type Source, Changed, Modifier, Source,
}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import genesis_prime/table/loader/store
import genesis_prime/table/unit_property2
import gleam/list
import owned_key
import owned_test
import planted_table
import properties_support
import spell_tables
import unitest

const move_speed = UnitProperty2Id(100)

const crit_chance = UnitProperty2Id(102)

const base_health = UnitProperty2Id(7)

/// A player of level 5 whose 0x262 lists nothing: every property at the client's default.
fn fresh() -> Properties {
  properties_support.fresh(level: 5)
}

fn modifier(
  property property: id.UnitProperty2Id,
  multiplier multiplier: Float,
  flat flat: Float,
) -> unit_properties.Modifier {
  Modifier(property:, mode: 3, multiplier:, flat:, per_level: 0.0)
}

fn source(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(effect_id))
}

pub fn a_property_no_0x262_lists_starts_at_its_table_default_test() -> Nil {
  use <- owned_test.run(5000)
  let properties = fresh()
  assert unit_properties.base(properties:, property: move_speed) == 1.0
  assert unit_properties.value(properties:, property: move_speed) == 1.0
  assert unit_properties.value(properties:, property: UnitProperty2Id(127))
    == 1.5
}

pub fn a_property_a_0x262_lists_takes_its_base_and_value_test() -> Nil {
  use <- owned_test.run(5000)
  let bits = float32.to_bits(300.0)
  let properties =
    unit_properties.new(
      defaults: properties_support.defaults(),
      listed: [UnitProperty(property_id: 7, base: bits, value: bits)],
      level: 1,
    )
  assert unit_properties.base(properties:, property: base_health) == 300.0
  assert unit_properties.value(properties:, property: base_health) == 300.0
}

pub fn one_modifier_sets_x_times_the_multiplier_plus_the_flat_amount_test() -> Nil {
  use <- owned_test.run(5000)
  // Sprint 1921: (1.0, 0.5) on MoveSpeedMultiplier.
  let #(sprint, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 1),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.5),
    )
  assert unit_properties.value(properties: sprint, property: move_speed) == 1.5
  // 42597: (0.0, 1.5) gives the same 1.5 from a base of 1.0.
  let #(other, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 2),
      modifier: modifier(property: move_speed, multiplier: 0.0, flat: 1.5),
    )
  assert unit_properties.value(properties: other, property: move_speed) == 1.5
  // 135954: (1.0, 0.08) on BaseCritChance, base 0.0.
  let #(crit, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 135_954),
      modifier: modifier(property: crit_chance, multiplier: 1.0, flat: 0.08),
    )
  assert unit_properties.value(properties: crit, property: crit_chance) == 0.08
  assert unit_properties.base(properties: crit, property: crit_chance) == 0.0
    as "a modifier changes the value and never the base"
}

pub fn a_modifier_adds_its_amount_for_each_level_of_the_player_test() -> Nil {
  use <- owned_test.run(5000)
  // The rule x * multiplier + flat + per_level * level, for a player of level 5, with the
  // values of the client's row 61528 (`table_rows -- Spell4Effects 61528`): property 41,
  // mode 1, dataBits02 1.0, dataBits03 80.0 and dataBits04 35.0, on ShieldCapacityMax's
  // default 0.0: 0.0 * 1.0 + 80.0 + 35.0 * 5.
  let #(leveled, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 61_528),
      modifier: Modifier(
        property: UnitProperty2Id(41),
        mode: 1,
        multiplier: 1.0,
        flat: 80.0,
        per_level: 35.0,
      ),
    )
  assert unit_properties.value(
      properties: leveled,
      property: UnitProperty2Id(41),
    )
    == 255.0
}

pub fn two_modifiers_on_one_property_apply_in_the_order_they_started_test() -> Nil {
  use <- owned_test.run(5000)
  let double = modifier(property: move_speed, multiplier: 2.0, flat: 0.0)
  let add_half = modifier(property: move_speed, multiplier: 1.0, flat: 0.5)
  // The server's choice: start order, so double then add is (1 * 2) + 0.5.
  let #(first, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 1),
      modifier: double,
    )
  let #(both, _) =
    unit_properties.apply(
      properties: first,
      source: source(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  assert unit_properties.value(properties: both, property: move_speed) == 2.5
  // The other start order is (1 + 0.5) * 2.
  let #(first, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  let #(both, _) =
    unit_properties.apply(
      properties: first,
      source: source(cast_id: 1, effect_id: 1),
      modifier: double,
    )
  assert unit_properties.value(properties: both, property: move_speed) == 3.0
}

pub fn ending_a_modifier_works_the_value_out_again_from_the_base_test() -> Nil {
  use <- owned_test.run(5000)
  let double = modifier(property: move_speed, multiplier: 2.0, flat: 0.0)
  let add_half = modifier(property: move_speed, multiplier: 1.0, flat: 0.5)
  let #(properties, _) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 1),
      modifier: double,
    )
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: source(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  let #(without_first, _) =
    unit_properties.remove(
      properties:,
      source: source(cast_id: 1, effect_id: 1),
    )
  assert unit_properties.value(properties: without_first, property: move_speed)
    == 1.5
    as "the second modifier stays applied to the base"
  let #(without_both, _) =
    unit_properties.remove(
      properties: without_first,
      source: source(cast_id: 2, effect_id: 2),
    )
  assert unit_properties.value(properties: without_both, property: move_speed)
    == 1.0
}

pub fn a_change_reports_only_the_properties_whose_value_changed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(properties, same) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 1),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.0),
    )
  assert same == [] as "a modifier that leaves the value as it was reports none"
  let #(properties, started) =
    unit_properties.apply(
      properties:,
      source: source(cast_id: 2, effect_id: 2),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.5),
    )
  assert started == [Changed(property: move_speed, base: 1.0, value: 1.5)]
    as "the entry holds the base and the new value; no other property is named"
  let #(_, ended) =
    unit_properties.remove(
      properties:,
      source: source(cast_id: 2, effect_id: 2),
    )
  assert ended == [Changed(property: move_speed, base: 1.0, value: 1.0)]
}

pub fn a_source_applied_twice_is_held_once_test() -> Nil {
  use <- owned_test.run(5000)
  let same = source(cast_id: 1, effect_id: 1)
  let add_half = modifier(property: move_speed, multiplier: 1.0, flat: 0.5)
  let #(once, _) =
    unit_properties.apply(properties: fresh(), source: same, modifier: add_half)
  let #(twice, changed) =
    unit_properties.apply(properties: once, source: same, modifier: add_half)
  assert unit_properties.value(properties: twice, property: move_speed) == 1.5
  assert changed == []
  let #(ended, _) = unit_properties.remove(properties: twice, source: same)
  assert unit_properties.value(properties: ended, property: move_speed) == 1.0
    as "one removal takes off the one modifier"
}

pub fn removing_a_source_that_is_not_held_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(properties, changed) =
    unit_properties.remove(
      properties: fresh(),
      source: source(cast_id: 9, effect_id: 9),
    )
  assert changed == []
  assert unit_properties.value(properties:, property: move_speed) == 1.0
}

pub fn the_entries_carry_the_id_the_base_and_the_value_as_32_bit_floats_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x93a: an entry is the id (8 bits), the base and the value as floats.
  assert unit_properties.entries(changed: [
      Changed(property: crit_chance, base: 0.0, value: 0.25),
    ])
    == [UnitProperty(property_id: 102, base: 0x00000000, value: 0x3E800000)]
}

pub fn the_overlay_puts_the_current_value_of_a_modified_property_in_a_0x262_list_test() -> Nil {
  use <- owned_test.run(5000)
  let bits = float32.to_bits(300.0)
  let listed = [
    UnitProperty(property_id: 7, base: bits, value: bits),
    UnitProperty(property_id: 42, base: bits, value: bits),
  ]
  let properties =
    unit_properties.new(
      defaults: properties_support.defaults(),
      listed:,
      level: 1,
    )
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: source(cast_id: 1, effect_id: 1),
      modifier: modifier(property: crit_chance, multiplier: 1.0, flat: 0.25),
    )
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: source(cast_id: 1, effect_id: 2),
      modifier: modifier(property: base_health, multiplier: 1.0, flat: 100.0),
    )
  assert unit_properties.overlay(listed:, properties:)
    == [
      UnitProperty(property_id: 7, base: bits, value: float32.to_bits(400.0)),
      UnitProperty(property_id: 42, base: bits, value: bits),
      UnitProperty(property_id: 102, base: 0x00000000, value: 0x3E800000),
    ]
    as "a listed property keeps its place unless a modifier holds it; one the 0x262 does not list is added; in id order"
  assert unit_properties.overlay(listed: [], properties: fresh()) == []
    as "no modifier live: nothing is added"
}

pub fn the_test_support_defaults_are_the_clients_unitproperty2_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // UnitProperty2 8, 102, 104, 127 and 177 are the defaults the hit rule and the
  // regeneration read (0x140463e80, `UnitProperty2.176`); each planted default is the
  // client's row.
  let real = unit_properties.defaults(tables: client_tables.shared())
  list.each(properties_support.defaults(), fn(planted) {
    assert list.key_find(real, planted.0) == Ok(planted.1)
      as "a planted default is the client's"
  })
}

pub fn gates_row_sets_falling_damage_to_0_and_the_property_is_held_and_sent_test() -> Nil {
  use <- owned_test.run(5000)
  // 67777: multiplier 0.0 and flat 0.0 on FallingDamageMultiplier (134), whose default
  // is 1.0. The properties hold the 0.0 and report it so it is sent; no rule reads
  // property 134 (falling damage is not handled), which `unit_properties` states.
  let falling = UnitProperty2Id(134)
  let #(properties, changed) =
    unit_properties.apply(
      properties: fresh(),
      source: source(cast_id: 1, effect_id: 67_777),
      modifier: modifier(property: falling, multiplier: 0.0, flat: 0.0),
    )
  assert unit_properties.value(properties:, property: falling) == 0.0
  assert changed == [Changed(property: falling, base: 1.0, value: 0.0)]
    as "base 1.0, value 0.0: the entry the client is sent"
  let #(properties, ended) =
    unit_properties.remove(
      properties:,
      source: source(cast_id: 1, effect_id: 67_777),
    )
  assert unit_properties.value(properties:, property: falling) == 1.0
  assert ended == [Changed(property: falling, base: 1.0, value: 1.0)]
}

/// The load of planted UnitProperty2 rows with the defaults derivation, the folder and
/// the tables gone when the result is returned.
fn loaded_with(
  rows rows: List(List(planted_table.Cell)),
) -> Result(List(#(id.UnitProperty2Id, Float)), store.LoadError) {
  use folder <- planted_table.in_folder([
    planted_table.file(unit_property2.schema, rows),
  ])
  let loaded =
    store.load(
      under: owned_key.new(),
      from: folder,
      entries: [unit_property2.entry()],
      requirements: [],
      derivations: [unit_properties.derivation()],
    )
  case loaded {
    Ok(tables) -> {
      let defaults = unit_properties.defaults(tables:)
      store.unload(tables)
      Ok(defaults)
    }
    Error(error) -> Error(error)
  }
}

pub fn the_defaults_are_built_once_at_load_from_every_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(defaults) = loaded_with(rows: spell_tables.unit_property_rows())
    as "the planted rows hold every property the rules read"
  assert defaults == properties_support.defaults()
    as "each row's defaultValue, in id order"
}

pub fn a_table_missing_a_row_the_rules_read_fails_the_load_by_name_test() -> Nil {
  use <- owned_test.run(10_000)
  // Row 8, HealthRegenMultiplier, is read by the regeneration.
  assert loaded_with(
      rows: planted_table.without(rows: spell_tables.unit_property_rows(), ids: [
        8,
      ]),
    )
    == Error(store.DerivationFailed(
      name: "UnitPropertyDefaults",
      reason: "the table UnitProperty2 has no row 8, which the player's rules read",
    ))
}
