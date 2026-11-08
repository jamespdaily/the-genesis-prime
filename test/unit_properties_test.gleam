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

import cast_support
import fixture_tables
import genesis_prime/game/unit_properties.{type Properties, Change, Changed}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{UnitProperty2Id}
import genesis_prime/table/loader/store
import genesis_prime/table/unit_property2
import gleam/int
import gleam/list
import owned_test
import planted_table
import properties_support
import spawn_support

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
  Change(property:, mode: 3, multiplier:, flat:, per_level: 0.0)
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
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.5),
    )
  assert unit_properties.value(properties: sprint, property: move_speed) == 1.5
  // 42597: (0.0, 1.5) gives the same 1.5 from a base of 1.0.
  let #(other, _) =
    unit_properties.apply(
      properties: fresh(),
      source: cast_support.source_of(cast_id: 1, effect_id: 2),
      modifier: modifier(property: move_speed, multiplier: 0.0, flat: 1.5),
    )
  assert unit_properties.value(properties: other, property: move_speed) == 1.5
  // 135954: (1.0, 0.08) on BaseCritChance, base 0.0.
  let #(crit, _) =
    unit_properties.apply(
      properties: fresh(),
      source: cast_support.source_of(cast_id: 1, effect_id: 135_954),
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
      source: cast_support.source_of(cast_id: 1, effect_id: 61_528),
      modifier: Change(
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
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: double,
    )
  let #(both, _) =
    unit_properties.apply(
      properties: first,
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  assert unit_properties.value(properties: both, property: move_speed) == 2.5
  // The other start order is (1 + 0.5) * 2.
  let #(first, _) =
    unit_properties.apply(
      properties: fresh(),
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  let #(both, _) =
    unit_properties.apply(
      properties: first,
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
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
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: double,
    )
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
      modifier: add_half,
    )
  let #(without_first, _) =
    unit_properties.remove(
      properties:,
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
    )
  assert unit_properties.value(properties: without_first, property: move_speed)
    == 1.5
    as "the second modifier stays applied to the base"
  let #(without_both, _) =
    unit_properties.remove(
      properties: without_first,
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
    )
  assert unit_properties.value(properties: without_both, property: move_speed)
    == 1.0
}

pub fn a_change_reports_only_the_properties_whose_value_changed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(properties, same) =
    unit_properties.apply(
      properties: fresh(),
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.0),
    )
  assert same == [] as "a modifier that leaves the value as it was reports none"
  let #(properties, started) =
    unit_properties.apply(
      properties:,
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
      modifier: modifier(property: move_speed, multiplier: 1.0, flat: 0.5),
    )
  assert started == [Changed(property: move_speed, base: 1.0, value: 1.5)]
    as "the entry holds the base and the new value; no other property is named"
  let #(_, ended) =
    unit_properties.remove(
      properties:,
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
    )
  assert ended == [Changed(property: move_speed, base: 1.0, value: 1.0)]
}

pub fn a_source_applied_twice_is_held_once_test() -> Nil {
  use <- owned_test.run(5000)
  let same = cast_support.source_of(cast_id: 1, effect_id: 1)
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
      source: cast_support.source_of(cast_id: 9, effect_id: 9),
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
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: modifier(property: crit_chance, multiplier: 1.0, flat: 0.25),
    )
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: cast_support.source_of(cast_id: 1, effect_id: 2),
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

pub fn gates_row_sets_falling_damage_to_0_and_the_property_is_held_and_sent_test() -> Nil {
  use <- owned_test.run(5000)
  // 67777: multiplier 0.0 and flat 0.0 on FallingDamageMultiplier (134), whose default
  // is 1.0. The properties hold the 0.0 and report it so it is sent; no rule reads
  // property 134 (falling damage is not handled), which `unit_properties` states.
  let falling = UnitProperty2Id(134)
  let #(properties, changed) =
    unit_properties.apply(
      properties: fresh(),
      source: cast_support.source_of(cast_id: 1, effect_id: 67_777),
      modifier: modifier(property: falling, multiplier: 0.0, flat: 0.0),
    )
  assert unit_properties.value(properties:, property: falling) == 0.0
  assert changed == [Changed(property: falling, base: 1.0, value: 0.0)]
    as "base 1.0, value 0.0: the entry the client is sent"
  let #(properties, ended) =
    unit_properties.remove(
      properties:,
      source: cast_support.source_of(cast_id: 1, effect_id: 67_777),
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
    store.read(
      from: folder,
      entries: [unit_property2.entry()],
      requirements: [],
      derivations: [unit_properties.derivation()],
    )
  case loaded {
    Ok(tables) -> {
      let defaults = unit_properties.defaults(tables:)
      Ok(defaults)
    }
    Error(error) -> Error(error)
  }
}

/// The defaultValue of the UnitProperty2 rows the server's rules name, as the client's
/// table holds them (`table_rows -- UnitProperty2 7 8 35 36 41 42 44 47 60 100 102 104
/// 127 134 175 177`).
const client_defaults = [
  #(7, 1.0),
  #(8, 1.0),
  #(35, 0.0),
  #(36, 0.0),
  #(41, 0.0),
  #(42, 0.0),
  #(44, 0.0),
  #(47, 0.0),
  #(60, 0.0),
  #(100, 1.0),
  #(102, 0.0),
  #(104, 0.0),
  #(127, 1.5),
  #(134, 1.0),
  #(175, 0.0),
  #(177, 500.0),
]

pub fn defaults_come_from_the_clients_unit_property_rows_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(defaults) =
    loaded_with(rows: fixture_tables.committed_rows(unit_property2.schema))
    as "the client's UnitProperty2 rows hold every property the rules read"
  assert list.length(defaults) == 200
    as "one default for each of the client's 200 UnitProperty2 rows"
  assert list.map(defaults, fn(default) { { default.0 }.value })
    |> list.sort(int.compare)
    == list.map(defaults, fn(default) { { default.0 }.value })
    as "in id order"
  list.each(client_defaults, fn(property) {
    assert list.key_find(defaults, UnitProperty2Id(property.0))
      == Ok(property.1)
      as "the row's defaultValue is the default"
  })
}

pub fn a_table_missing_a_row_the_rules_read_fails_the_load_by_name_test() -> Nil {
  use <- owned_test.run(10_000)
  // Row 8, HealthRegenMultiplier, is read by the regeneration.
  assert loaded_with(
      rows: planted_table.without(
        rows: fixture_tables.committed_rows(unit_property2.schema),
        ids: [8],
      ),
    )
    == Error(store.DerivationFailed(
      name: "UnitPropertyDefaults",
      reason: "the table UnitProperty2 has no row 8, which the player's rules read",
    ))
}

// A creature's properties (`unit_properties.of_creature` over the bases the load builds).
// The expected bases are the client's formula (`0x1404585c0`) worked by hand in 32-bit
// floats from the committed rows of Creature2 73464, the Virtual Battle Beast, at level 1:
// its Creature2OverrideProperties value when one is listed (40 is 1.0, 42 is 0.0); else
// the UnitProperty2 defaultValue when the row's flags have bit 0 set (181 and 191) or the
// id is 197 or above; else the CreatureLevel value (the row of the level below 100, row 101
// at the column id - 100 from 100) times the archetype's, the difficulty's and the tier's
// unitPropertyMultiplier at the id, each product held as a 32-bit float
// (`table_rows -- CreatureLevel 1 101`, `Creature2ArcheType`, `Creature2Difficulty`,
// `Creature2Tier`, `UnitProperty2`).
const beast_bases = [
  #(0, 10.466758728027344),
  #(7, 52.6204948425293),
  #(26, 0.0),
  #(27, 0.0),
  #(28, 0.0),
  #(35, 41.867034912109375),
  #(36, 41.867034912109375),
  #(40, 1.0),
  #(42, 0.0),
  #(44, 0.0),
  #(100, 1.0),
  #(101, 0.01600000075995922),
  #(102, 0.01600000075995922),
  #(105, 0.0),
  #(127, 1.2750000953674316),
  #(132, 1.0),
  #(133, 1.0),
  #(138, 1.0),
  #(139, 1.0),
  #(140, 1.0),
  #(141, 1.0),
  #(142, 1.0),
  #(143, 1.0),
  #(144, 0.0),
  #(145, 0.0),
  #(146, 0.0),
  #(150, 0.0),
  #(159, 1.0),
  #(160, 1.0),
  #(161, 1.0),
  #(162, 1.0),
  #(163, 1.0),
  #(164, 0.0),
  #(181, 1.0),
  #(191, 1.0),
  #(195, 0.0),
  #(196, 0.0),
  #(197, 0.0),
  #(199, 0.0),
]

pub fn creature_bases_match_virtual_battle_beast_test() -> Nil {
  use <- owned_test.run(10_000)
  let bases = spawn_support.loaded_beast().bases
  assert list.map(bases, fn(base) { { base.0 }.value })
    == int.range(from: 199, to: -1, with: [], run: fn(ids, id) { [id, ..ids] })
    as "one base for each of the client's 200 UnitProperty2 ids, in id order"
  list.each(beast_bases, fn(expected) {
    assert list.key_find(bases, UnitProperty2Id(expected.0)) == Ok(expected.1)
      as "the client's formula's number for the Beast"
  })
  let properties = unit_properties.of_creature(bases:, level: 1)
  assert unit_properties.value(properties:, property: base_health)
    == 52.6204948425293
    as "a creature's value starts at its base"
}

pub fn two_casters_sources_both_count_test() -> Nil {
  use <- owned_test.run(5000)
  // Today's rule, which the module's doc names as a gap (#569 builds the stacking of the
  // client's Spell4StackGroup rule): two casters' modifiers on one property each count,
  // in start order, and taking one off leaves the other applied.
  let properties =
    unit_properties.of_creature(
      bases: spawn_support.loaded_beast().bases,
      level: 1,
    )
  let slow = modifier(property: move_speed, multiplier: 0.5, flat: 0.0)
  let #(first, _) =
    unit_properties.apply(
      properties:,
      source: cast_support.source_of(cast_id: 1, effect_id: 7),
      modifier: slow,
    )
  let #(both, _) =
    unit_properties.apply(
      properties: first,
      source: cast_support.source_of(cast_id: 2, effect_id: 7),
      modifier: slow,
    )
  assert unit_properties.value(properties: both, property: move_speed) == 0.25
    as "1.0 halved by each of two casters' slows"
  let #(left, _) =
    unit_properties.remove(
      properties: both,
      source: cast_support.source_of(cast_id: 1, effect_id: 7),
    )
  assert unit_properties.value(properties: left, property: move_speed) == 0.5
}
