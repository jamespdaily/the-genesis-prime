//// What a character of each class holds on entering the world, from the client's
//// rows (`genesis_prime/game/loadout`, `genesis_prime/game/item_property`),
//// read as the shared tables (`fixture_tables`). A test that needs another row
//// edits the client's row (`changed`, `added`, `without` below) and loads the
//// rows. Expected values come from these places.
//// - The Novice sets: `Item2.novice_set`, `0x14040df10` (a weapon's ratings and
////   an armor piece's), `0x14040e340` (armor), `0x14040e3d0` (Base Health) and
////   `0x14040dbf0` (the shield): every set's weapon gives Assault Rating
////   167.0625 and Support Rating 55.6875; its five armor pieces Assault Rating
////   9.0 + 9.0 + 7.2 + 5.4 + 5.4, so 203.0625 and 55.6875 in all; Armor 250
////   (Warrior, Engineer: heavy), 200 (Medic, Stalker: medium) or 150 (Esper,
////   Spellslinger: light); Base Health 600; the shield ShieldCapacityMax 450,
////   ShieldRegenPct 0.15, ShieldMitigationMax 0.625 and ShieldRebootTime 5125.
////   The client works in 32-bit floats, so a sum differs from these in its
////   fifth digit (the client's own 203.06248); a test takes it within 0.001.
//// - The weapons by class and faction (CharacterCreation itemId04 of the
////   PreTutorial rows, `Item2.novice_set`): Warrior 81346 / 81352 (factions 167
////   / 166), Engineer 81347 / 81353, Esper 81351 / 81357, Medic 81348 / 81354,
////   Stalker 81349 / 81355, Spellslinger 81350 / 81356. The weapon's equipped
////   slot is 16: its ItemSlot (WeaponPrimary, 20) holds the flags 0x10000, bit
////   16 (`0x14040df10`, `lua.ActionBarFrame.InitializeBars`).
//// - The armor and the shield: each is held at location 0 at the bag index of
////   the lowest bit of its ItemSlot's equipped slot flags (`ItemSlot.
////   equippedSlotFlags`, GetSlot `0x140418a50`): chest 0, legs 1, shoulder 3,
////   feet 4, hands 5, shield 15. `sets()` lists each set's items from the
////   PreTutorial CharacterCreation row, with the bag index of their ItemSlot.
//// - The worn visuals (`opcode.0x262.worn_visuals`, `Item2.novice_visuals`,
////   FindItemDisplaySourceEntry `0x140444130`): one per armor piece and the
////   weapon, in the ItemSlot id of its type (1 chest, 2 legs, 4 shoulder, 5
////   feet, 6 hands, 20 weapon), with the display of the ItemDisplaySourceEntry
////   row of its item source, item type and power level, and none for the
////   shield or for an item whose Item2 flags hold 0x4000. `sets()` lists them.
//// - The starting abilities (`SpellLevel.spell4Id`, `opcode.0x111.ability_bag`):
////   the level-1 rows of the class with no prerequisite, in the order of their
////   ids, each as the Spell4Base id of its Spell4 row: Warrior 18309, 37968,
////   38017; Engineer 26468, 25473, 25635; Esper 19102, 19019, 19022; Medic
////   38201, 16322, 26543; Stalker 23148, 23161, 23173; Spellslinger 27638,
////   20684, 20325.
//// - Health: the armor's Base Health, 600 (`0x14040e3d0`); the level's rows are
////   gear_test's.
//// - The formulas: a value is computed from the rows, so a changed GameFormula
////   row changes it; each changed value below is worked by hand from the
////   formula of the address in its message.
//// - The load: a missing row the formulas read fails the load, with the table
////   and the id in the reason.

import fixture_tables
import genesis_prime/game/gear
import genesis_prime/game/item_property.{Shield}
import genesis_prime/game/loadout.{type Loadout, Equipped}
import genesis_prime/game/worn_visual
import genesis_prime/store.{HeldItem}
import genesis_prime/table/id.{
  ClassId, Item2Id, ItemDisplayId, ItemSlotId, Spell4BaseId,
}
import genesis_prime/table/loader/store as table_store
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import planted_table.{Float, Integer}

/// A class of the Novice sets: its id, its name, its armor and its weapons
/// (faction 167, faction 166) and abilities.
type Class {
  Class(
    id: Int,
    name: String,
    armor: Float,
    weapon_167: Int,
    weapon_166: Int,
    abilities: List(Int),
  )
}

fn classes() -> List(Class) {
  [
    Class(1, "Warrior", 250.0, 81_346, 81_352, [18_309, 37_968, 38_017]),
    Class(2, "Engineer", 250.0, 81_347, 81_353, [26_468, 25_473, 25_635]),
    Class(3, "Esper", 150.0, 81_351, 81_357, [19_102, 19_019, 19_022]),
    Class(4, "Medic", 200.0, 81_348, 81_354, [38_201, 16_322, 26_543]),
    Class(5, "Stalker", 200.0, 81_349, 81_355, [23_148, 23_161, 23_173]),
    Class(7, "Spellslinger", 150.0, 81_350, 81_356, [27_638, 20_684, 20_325]),
  ]
}

const factions = [167, 166]

/// What a Novice set holds, from the PreTutorial CharacterCreation rows of the
/// class and faction (rows 466 to 485), the Item2 rows they name, Item2Type's
/// ItemSlot, ItemSlot's equipped slot flags and the ItemDisplaySourceEntry rows
/// of the items' source, type and power level (the display of Item2 is 0 for
/// each): the armor pieces and the shield as item and bag index in bag order,
/// and the worn visuals as slot and display in slot order.
type Held {
  Held(
    class_id: Int,
    faction_id: Int,
    armor: List(#(Int, Int)),
    worn: List(#(Int, Int)),
  )
}

fn sets() -> List(Held) {
  [
    Held(
      1,
      167,
      [
        #(81_359, 0),
        #(81_344, 1),
        #(81_381, 3),
        #(81_345, 4),
        #(81_380, 5),
        #(8534, 15),
      ],
      [#(1, 3838), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 119)],
    ),
    Held(
      1,
      166,
      [
        #(81_365, 0),
        #(81_366, 1),
        #(81_390, 3),
        #(81_367, 4),
        #(81_389, 5),
        #(8535, 15),
      ],
      [#(1, 3842), #(2, 3844), #(4, 4179), #(5, 3845), #(6, 3843), #(20, 120)],
    ),
    Held(
      2,
      167,
      [
        #(81_359, 0),
        #(81_344, 1),
        #(81_381, 3),
        #(81_345, 4),
        #(81_380, 5),
        #(8534, 15),
      ],
      [#(1, 3838), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 3407)],
    ),
    Held(
      2,
      166,
      [
        #(81_365, 0),
        #(81_366, 1),
        #(81_390, 3),
        #(81_367, 4),
        #(81_389, 5),
        #(8535, 15),
      ],
      [#(1, 3842), #(2, 3844), #(4, 4179), #(5, 3845), #(6, 3843), #(20, 3409)],
    ),
    Held(
      3,
      167,
      [
        #(81_362, 0),
        #(81_363, 1),
        #(81_376, 3),
        #(81_364, 4),
        #(81_375, 5),
        #(8534, 15),
      ],
      [#(1, 3233), #(2, 3234), #(4, 3885), #(5, 3235), #(6, 84), #(20, 1354)],
    ),
    Held(
      3,
      166,
      [
        #(81_371, 0),
        #(81_372, 1),
        #(81_385, 3),
        #(81_373, 4),
        #(81_384, 5),
        #(8535, 15),
      ],
      [#(1, 3239), #(2, 3240), #(4, 3884), #(5, 3241), #(6, 84), #(20, 1355)],
    ),
    Held(
      4,
      167,
      [
        #(81_358, 0),
        #(81_360, 1),
        #(81_378, 3),
        #(81_361, 4),
        #(81_374, 5),
        #(8534, 15),
      ],
      [#(1, 48), #(2, 50), #(4, 4148), #(5, 47), #(6, 46), #(20, 3279)],
    ),
    Held(
      4,
      166,
      [
        #(81_368, 0),
        #(81_369, 1),
        #(81_387, 3),
        #(81_370, 4),
        #(81_383, 5),
        #(8535, 15),
      ],
      [#(1, 4106), #(2, 4107), #(4, 4158), #(5, 4105), #(6, 4104), #(20, 3280)],
    ),
    Held(
      5,
      167,
      [
        #(81_358, 0),
        #(81_360, 1),
        #(81_378, 3),
        #(81_361, 4),
        #(81_374, 5),
        #(8534, 15),
      ],
      [#(1, 48), #(2, 50), #(4, 4148), #(5, 47), #(6, 46), #(20, 3380)],
    ),
    Held(
      5,
      166,
      [
        #(81_368, 0),
        #(81_369, 1),
        #(81_387, 3),
        #(81_370, 4),
        #(81_383, 5),
        #(8535, 15),
      ],
      [#(1, 4106), #(2, 4107), #(4, 4158), #(5, 4105), #(6, 4104), #(20, 1063)],
    ),
    Held(
      7,
      167,
      [
        #(81_362, 0),
        #(81_363, 1),
        #(81_376, 3),
        #(81_364, 4),
        #(81_375, 5),
        #(8534, 15),
      ],
      [#(1, 3233), #(2, 3234), #(4, 3885), #(5, 3235), #(6, 84), #(20, 22)],
    ),
    Held(
      7,
      166,
      [
        #(81_371, 0),
        #(81_372, 1),
        #(81_385, 3),
        #(81_373, 4),
        #(81_384, 5),
        #(8535, 15),
      ],
      [#(1, 3239), #(2, 3240), #(4, 3884), #(5, 3241), #(6, 84), #(20, 38)],
    ),
  ]
}

fn held(class class: Class, faction faction: Int) -> Held {
  let assert Ok(set) =
    list.find(sets(), fn(set) {
      set.class_id == class.id && set.faction_id == faction
    })
    as "the client's rows hold a Novice set for every class and faction"
  set
}

/// Whether a value is the source's decimal, to 1e-6. The rows hold 32-bit floats,
/// so GameFormula 549's 3.6 is 3.5999999046 (the client's 7.1999998 at power level
/// 2), and a sum of armor pieces differs from its decimal by about 1e-7; no value
/// the formulas give is within 1e-6 of another a test expects.
fn close(value value: Float, to expected: Float) -> Bool {
  float.absolute_value(value -. expected) <. 1.0e-6
}

fn weapon_of(class class: Class, faction faction: Int) -> Int {
  case faction {
    167 -> class.weapon_167
    _ -> class.weapon_166
  }
}

/// Each class and faction's loadout in the tables, with the class for its name.
fn every_set(
  tables tables: table_store.Tables,
  check check: fn(Class, Int, Loadout) -> Nil,
) -> Nil {
  list.each(classes(), fn(class) {
    list.each(factions, fn(faction) {
      let assert Ok(loadout) =
        loadout.of(tables:, class_id: ClassId(class.id), faction_id: faction)
        as {
          "the tables hold a Novice set for class "
          <> class.name
          <> " faction "
          <> int.to_string(faction)
        }
      check(class, faction, loadout)
    })
  })
}

pub fn a_novice_sets_ratings_are_203_0625_assault_and_55_6875_support_for_every_class_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(tables: fixture_tables.shared(), check: fn(class, faction, loadout) {
    let properties = loadout.properties
    assert close(value: properties.assault_rating, to: 203.0625)
      as {
        "0x14040df10: the weapon's 167.0625 and the armor's 36.0 give a "
        <> class.name
        <> " of faction "
        <> int.to_string(faction)
        <> " Assault Rating 203.0625, not "
        <> float.to_string(properties.assault_rating)
      }
    assert close(value: properties.support_rating, to: 55.6875)
      as "0x14040df10: the weapon's Support Rating 55.6875 and none from the armor"
  })
}

pub fn a_novice_sets_armor_is_250_for_heavy_200_for_medium_and_150_for_light_armor_and_its_base_health_600_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(tables: fixture_tables.shared(), check: fn(class, faction, loadout) {
    assert close(value: loadout.properties.armor, to: class.armor)
      as {
        "0x14040e340: the "
        <> class.name
        <> "'s armor of faction "
        <> int.to_string(faction)
        <> " is "
        <> float.to_string(class.armor)
      }
    assert close(value: loadout.properties.base_health, to: 600.0)
      as "0x14040e3d0: the armor's Base Health is 150 + 150 + 120 + 90 + 90 for every class"
  })
}

pub fn a_novice_sets_shield_is_450_with_mitigation_0_625_regeneration_0_15_and_reboot_5125_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(
    tables: fixture_tables.shared(),
    check: fn(class, _faction, loadout) {
      let assert Some(Shield(
        capacity_max:,
        regen_percent:,
        mitigation_max:,
        reboot_time_ms:,
      )) = loadout.properties.shield
        as { "0x14040dbf0: the " <> class.name <> "'s set holds a shield item" }
      assert close(value: capacity_max, to: 450.0)
        as "0x14040dbf0: ShieldCapacityMax is GameFormula 548's curve at power level 2, 225 x 2"
      assert close(value: mitigation_max, to: 0.625)
        as "0x14040dbf0: ShieldMitigationMax at the budget's middle is 0.625"
      assert close(value: regen_percent, to: 0.15)
        as "0x14040dbf0: ShieldRegenPct at the budget's middle is 0.15"
      assert reboot_time_ms == 5125
        as "0x14040dbf0: ShieldRebootTime at the budget's middle is 5125"
    },
  )
}

pub fn a_loadout_is_the_classes_weapon_in_slot_16_and_its_three_level_1_spells_in_spell_level_order_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(tables: fixture_tables.shared(), check: fn(class, faction, loadout) {
    assert loadout.weapon == Item2Id(weapon_of(class:, faction:))
      as {
        "CharacterCreation itemId04: the "
        <> class.name
        <> " of faction "
        <> int.to_string(faction)
        <> " holds weapon "
        <> int.to_string(weapon_of(class:, faction:))
      }
    assert loadout.weapon_slot == 16
      as "ItemSlot 20 WeaponPrimary holds the flags 0x10000, bit 16: the weapon is equipped in slot 16"
    assert loadout.abilities == list.map(class.abilities, Spell4BaseId)
      as {
        "SpellLevel.spell4Id: the "
        <> class.name
        <> "'s three level-1 spells as their Spell4Base ids, in the order of the SpellLevel ids"
      }
  })
}

// ---- edits of the client's rows ----

/// The rows with the cells of one row replaced.
fn changed(
  rows rows: fixture_tables.Rows,
  table table: String,
  id id: Int,
  with cells: List(#(String, planted_table.Cell)),
) -> fixture_tables.Rows {
  let assert Ok(rows) = fixture_tables.change(rows:, table:, id:, with: cells)
    as "the client's rows hold the row and its columns"
  rows
}

/// The rows with one more row, `id`, a copy of `copy_of` with these cells.
fn added(
  rows rows: fixture_tables.Rows,
  table table: String,
  copy_of copy_of: Int,
  id id: Int,
  with cells: List(#(String, planted_table.Cell)),
) -> fixture_tables.Rows {
  let assert Ok(rows) =
    fixture_tables.add(rows:, table:, copy_of:, id:, with: cells)
    as "the client's rows hold the row to copy and its columns, and not the new id"
  rows
}

/// The rows without the row `id` of the table.
fn without(
  rows rows: fixture_tables.Rows,
  table table: String,
  id id: Int,
) -> fixture_tables.Rows {
  let assert Ok(rows) = fixture_tables.remove(rows:, table:, id:)
    as "the client's rows hold the row"
  rows
}

/// The client's rows with one GameFormula row's cells changed.
fn formula_changed(
  id id: Int,
  with cells: List(#(String, planted_table.Cell)),
) -> fixture_tables.Rows {
  changed(rows: fixture_tables.rows(), table: "GameFormula", id:, with: cells)
}

/// The Warrior of faction 166's loadout and level 1 health in the tables of these
/// rows.
fn warrior_in(rows rows: fixture_tables.Rows) -> #(Loadout, Int) {
  let assert Ok(tables) = fixture_tables.load(rows:)
    as "the client's rows with a changed row load"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "class 1 faction 166 has a set"
  let worn =
    gear.of_items(
      tables:,
      level: 1,
      items: list.index_map(
        [
          Equipped(item: loadout.weapon, bag_index: loadout.weapon_slot),
          ..loadout.armor
        ],
        fn(equipped, index) {
          HeldItem(
            item_guid: index + 1,
            item2_id: equipped.item,
            location: 0,
            bag_index: equipped.bag_index,
            stack_count: 1,
            random_stats: 0,
          )
        },
      ),
    )
  let assert Ok(health) = gear.max_health(tables:, gear: worn, level: 1)
    as "CreatureLevel row 1 is the client's"
  #(loadout, health)
}

pub fn a_changed_formula_row_changes_the_weapons_ratings_the_armors_ratings_the_armor_the_health_and_the_shield_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(weapon_slope_doubled, _) =
    warrior_in(
      rows: formula_changed(id: 1288, with: [#("datafloat02", Float(264.0))]),
    )
  assert close(
    value: weapon_slope_doubled.properties.assault_rating,
    to: 370.125,
  )
    as "0x14041dc90: GameFormula 1288 at 264 gives the weapon v = 0.75 x 528 x 1.125 = 445.5, of which 0.75 is Assault Rating, 334.125, and the armor's 36.0"
  assert close(
    value: weapon_slope_doubled.properties.support_rating,
    to: 111.375,
  )
    as "0x14040df10: a quarter of 445.5 is Support Rating"
  let #(armor_slope_doubled, _) =
    warrior_in(
      rows: formula_changed(id: 549, with: [#("datafloat02", Float(7.5))]),
    )
  assert close(
    value: armor_slope_doubled.properties.assault_rating,
    to: 242.0625,
  )
    as "0x14041da70: GameFormula 549 at 7.5 gives each piece 7.5 x 2 x its slot's modifier, 75.0 over the set's modifiers (1.25 + 1.25 + 1 + 0.75 + 0.75 = 5), and leaves the weapon's 167.0625"
  let #(factor_raised, _) =
    warrior_in(
      rows: formula_changed(id: 1265, with: [#("datafloat0", Float(0.5))]),
    )
  assert close(value: factor_raised.properties.assault_rating, to: 221.625)
    as "0x14040df10: GameFormula 1265's first value 0.5 gives the weapon v = 0.75 x 264 x 1.25 = 247.5, Assault Rating 185.625, and the armor's 36.0 (b = -1 leaves its factor 1)"
  assert close(value: factor_raised.properties.support_rating, to: 61.875)
    as "0x14040df10: a quarter of 247.5"
  let #(armor_curve_doubled, _) =
    warrior_in(
      rows: formula_changed(id: 547, with: [#("datafloat02", Float(40.0))]),
    )
  assert close(value: armor_curve_doubled.properties.armor, to: 500.0)
    as "0x14041deb0: GameFormula 547 at 40 doubles the heavy set's armor to 500"
  let #(health_curve_doubled, health) =
    warrior_in(
      rows: formula_changed(id: 67, with: [#("datafloat02", Float(120.0))]),
    )
  assert close(value: health_curve_doubled.properties.base_health, to: 1200.0)
    as "GameFormula 67 at 120 doubles the armor's Base Health to 1200"
  assert health == 1336 as "135.97 and 1200 round to 1336"
  let #(shield_curve_doubled, _) =
    warrior_in(
      rows: formula_changed(id: 548, with: [#("datafloat02", Float(450.0))]),
    )
  let assert Some(doubled) = shield_curve_doubled.properties.shield
    as "the set still holds a shield"
  assert close(value: doubled.capacity_max, to: 900.0)
    && close(value: doubled.mitigation_max, to: 0.625)
    && close(value: doubled.regen_percent, to: 0.15)
    && doubled.reboot_time_ms == 5125
    as "0x14041d850: GameFormula 548 at 450 doubles the shield's capacity to 900 and changes no other shield value"
  let #(shield_factors_changed, _) =
    warrior_in(
      rows: formula_changed(id: 1260, with: [
        #("datafloat0", Float(1.5)),
        #("datafloat01", Float(2.5)),
        #("datafloat02", Float(0.1)),
        #("datafloat03", Float(0.5)),
      ])
      |> changed(table: "GameFormula", id: 1261, with: [
        #("dataint0", Integer(20_000)),
        #("dataint01", Integer(500)),
        #("datafloat0", Float(0.5)),
        #("datafloat01", Float(2.0)),
      ]),
    )
  let assert Some(changed) = shield_factors_changed.properties.shield
    as "the set still holds a shield"
  assert close(value: changed.capacity_max, to: 900.0)
    as "0x14041d420: GameFormula 1260 at 1.5 and 2.5 gives the capacity factor 1.5 + (2.5 - 1.5) x 0.5 = 2.0, 450 x 2"
  assert close(value: changed.regen_percent, to: 0.3)
    as "0x14041d540: 1260's third and fourth values 0.1 and 0.5 give 0.1 + 0.4 x 0.5 = 0.3"
  assert close(value: changed.mitigation_max, to: 1.25)
    as "0x14041d660: GameFormula 1261's first values 0.5 and 2.0 give 0.5 + 1.5 x 0.5 = 1.25"
  assert changed.reboot_time_ms == 10_250
    as "0x14041d780: 1261's dataint0 20000 and dataint01 500 give 500 + 19500 x 0.5 = 10250"
}

/// Why the load of these rows fails, as the reason the loadouts could not be
/// built.
fn why_the_load_fails(rows rows: fixture_tables.Rows) -> String {
  let assert Error(table_store.DerivationFailed(name: "Loadouts", reason:)) =
    fixture_tables.load(rows:)
    as "the load without a row the loadouts read fails in their build"
  reason
}

pub fn a_missing_formula_row_fails_the_load_naming_the_table_and_the_id_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([67, 547, 548, 549, 1260, 1261, 1265, 1286, 1288], fn(id) {
    let reason =
      why_the_load_fails(rows: without(
        rows: fixture_tables.rows(),
        table: "GameFormula",
        id:,
      ))
    assert string.contains(reason, "GameFormula")
      && string.contains(reason, "row " <> int.to_string(id))
      as {
        "the load fails without GameFormula row "
        <> int.to_string(id)
        <> " and says so: "
        <> reason
      }
  })
}

/// A load without one row of a table fails, and its reason names the table and
/// the row.
fn a_load_without_the_row_fails(table table: String, id id: Int) -> Nil {
  let reason =
    why_the_load_fails(rows: without(rows: fixture_tables.rows(), table:, id:))
  assert string.contains(reason, table)
    && string.contains(reason, "row " <> int.to_string(id))
    as {
      "the load fails without "
      <> table
      <> " row "
      <> int.to_string(id)
      <> ": "
      <> reason
    }
}

pub fn a_missing_item_category_item_slot_item_or_spell4_row_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  a_load_without_the_row_fails(table: "Item2Category", id: 3)
  a_load_without_the_row_fails(table: "ItemSlot", id: 20)
  a_load_without_the_row_fails(table: "Item2", id: 81_352)
  a_load_without_the_row_fails(table: "Item2Type", id: 51)
  a_load_without_the_row_fails(table: "Item2Family", id: 2)
  a_load_without_the_row_fails(table: "CreatureLevel", id: 17)
  a_load_without_the_row_fails(table: "Spell4", id: 58_591)
}

pub fn a_class_with_no_level_1_spell_row_or_a_createable_class_and_faction_with_no_novice_set_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails(
      rows: list.fold([631, 1086, 1089], fixture_tables.rows(), fn(rows, id) {
        without(rows:, table: "SpellLevel", id:)
      }),
    )
  assert string.contains(reason, "SpellLevel")
    && string.contains(reason, "class 4")
    as { "no level-1 SpellLevel row for class 4: " <> reason }
  // The PreTutorial rows of class 1 and faction 166 (start 4); the rows a player
  // can make for it (start 3, row 359 and others) stay.
  let reason =
    why_the_load_fails(
      rows: list.fold(
        [478, 487, 490, 494, 503, 507, 533],
        fixture_tables.rows(),
        fn(rows, id) { without(rows:, table: "CharacterCreation", id:) },
      ),
    )
  assert string.contains(reason, "CharacterCreation")
    && string.contains(reason, "class 1")
    && string.contains(reason, "faction 166")
    as {
      "CharacterCreation row 359 (class 1, faction 166, start 3) is a row a player can make, and without the PreTutorial rows its class and faction have no Novice set: "
      <> reason
    }
}

pub fn a_formula_with_no_value_at_the_power_level_fails_the_load_naming_the_formula_and_the_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails(
      rows: formula_changed(id: 549, with: [
        #("dataint0", Integer(5)),
        #("datafloat03", Float(0.5)),
      ]),
    )
  assert string.contains(reason, "GameFormula 549")
    && string.contains(reason, "power level 2")
    as {
      "0x14041da70: a negative offset (2 - 5) to the power 0.5 has no value, and the reason names the formula and the level, not an item: "
      <> reason
    }
}

pub fn an_items_guid_differs_for_each_character_location_and_bag_index_test() -> Nil {
  use <- owned_test.run(5000)
  assert loadout.item_guid(character_number: 42, location: 1, bag_index: 5)
    == 42 * 2_199_023_255_552 + 4_294_967_296 + 5
    as "the guid packs the character above 41 bits, the location (9 bits) in bits 32 to 40 and the bag index (32 bits) below"
  assert loadout.item_guid(character_number: 42, location: 0, bag_index: 256)
    != loadout.item_guid(character_number: 42, location: 1, bag_index: 0)
    as "a bag index of 256 is not a location of 1"
  assert loadout.item_guid(character_number: 42, location: 4, bag_index: 0)
    != loadout.item_guid(character_number: 43, location: 4, bag_index: 0)
    as "another character's item has another guid"
}

// ---- the armor held, and what is worn ----

pub fn a_loadouts_armor_is_its_five_pieces_and_shield_at_the_bag_index_of_their_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(tables: fixture_tables.shared(), check: fn(class, faction, loadout) {
    assert loadout.armor
      == list.map(held(class:, faction:).armor, fn(pair) {
        Equipped(item: Item2Id(pair.0), bag_index: pair.1)
      })
      as {
        "ItemSlot.equippedSlotFlags: the "
        <> class.name
        <> " of faction "
        <> int.to_string(faction)
        <> " holds its chest at 0, legs at 1, shoulder at 3, feet at 4, hands at 5 and shield at 15"
      }
    assert list.length(loadout.armor) == 6
      as "CharacterCreation: a Novice set holds five armor pieces and a shield besides its weapon"
  })
}

pub fn a_changed_item_slot_row_changes_the_bag_index_of_the_pieces_of_its_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  // ItemSlot 1 (ArmorChest) holds the flags 1; they are edited to 4096.
  let #(loadout, _) =
    warrior_in(
      rows: changed(
        rows: fixture_tables.rows(),
        table: "ItemSlot",
        id: 1,
        with: [
          #("equippedSlotFlags", Integer(4096)),
        ],
      ),
    )
  assert loadout.armor
    == [
      Equipped(Item2Id(81_366), 1),
      Equipped(Item2Id(81_390), 3),
      Equipped(Item2Id(81_367), 4),
      Equipped(Item2Id(81_389), 5),
      Equipped(Item2Id(81_365), 12),
      Equipped(Item2Id(8535), 15),
    ]
    as "GetSlot 0x140418a50: ArmorChest's flags 0x1000 put the chest 81365 at the lowest bit, 12, and leave the other pieces where their slots' flags put them"
}

pub fn an_item_whose_slot_has_no_equipped_slot_flag_fails_the_load_naming_the_item_test() -> Nil {
  use <- owned_test.run(60_000)
  // ItemSlot 2 (ArmorLegs) holds the flags 2; they are edited to 0.
  let reason =
    why_the_load_fails(
      rows: changed(
        rows: fixture_tables.rows(),
        table: "ItemSlot",
        id: 2,
        with: [
          #("equippedSlotFlags", Integer(0)),
        ],
      ),
    )
  assert string.contains(reason, "item 81344")
    && string.contains(reason, "equipped slot")
    as {
      "GetSlot 0x140418a50 gives no slot to an item with no flag below bit 31, so the held item has no bag index: "
      <> reason
    }
}

/// What a loadout's worn visuals are, as slot and display.
fn worn_of(loadout loadout: Loadout) -> List(#(Int, Int)) {
  list.map(loadout.visuals, fn(visual) {
    #(visual.slot.value, visual.display.value)
  })
}

pub fn a_loadouts_worn_visuals_are_its_five_pieces_and_weapon_in_the_slot_and_display_of_each_set_test() -> Nil {
  use <- owned_test.run(60_000)
  every_set(tables: fixture_tables.shared(), check: fn(class, faction, loadout) {
    assert worn_of(loadout:) == held(class:, faction:).worn
      as {
        "opcode.0x262.worn_visuals: the "
        <> class.name
        <> " of faction "
        <> int.to_string(faction)
        <> " wears its five pieces and its weapon, and nothing for the shield (slot 43, display 0)"
      }
  })
}

/// The Warrior of faction 167's loadout in the tables of these rows.
fn warrior_167_in(rows rows: fixture_tables.Rows) -> Loadout {
  let assert Ok(tables) = fixture_tables.load(rows:)
    as "the client's rows with the changed rows load"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 167)
    as "class 1 faction 167 has a set"
  loadout
}

/// The client's rows with these displays added, each a copy of ItemDisplay row
/// 3838 with an id of its own.
fn with_displays(
  rows rows: fixture_tables.Rows,
  displays displays: List(Int),
) -> fixture_tables.Rows {
  list.fold(displays, rows, fn(rows, display) {
    added(rows:, table: "ItemDisplay", copy_of: 3838, id: display, with: [])
  })
}

pub fn a_changed_item_display_source_entry_changes_the_visual_of_its_item_test() -> Nil {
  use <- owned_test.run(60_000)
  // ItemDisplaySourceEntry 4535 (source 75, type 15, levels 1 to 3) gives the
  // display 3838; it is edited to 3999, a display of its own.
  let loadout =
    warrior_167_in(
      rows: changed(
        rows: with_displays(rows: fixture_tables.rows(), displays: [3999]),
        table: "ItemDisplaySourceEntry",
        id: 4535,
        with: [#("itemDisplayId", Integer(3999))],
      ),
    )
  assert worn_of(loadout:)
    == [#(1, 3999), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 119)]
    as "0x140444130: the chest 81359 (source 75, type 15) takes the display of the entry's row, here 3999, and no other piece changes"
}

pub fn the_entry_whose_levels_hold_the_items_power_level_gives_its_display_test() -> Nil {
  use <- owned_test.run(60_000)
  // Entry 4535 holds levels 1 to 3 and the display 3838; it is edited to give
  // 3998, and an entry 9001 of the same source and type is added with levels 3
  // to 5 and the display 3838.
  let rows = with_displays(rows: fixture_tables.rows(), displays: [3998])
  let first_holds =
    warrior_167_in(
      rows: rows
      |> changed(table: "ItemDisplaySourceEntry", id: 4535, with: [
        #("itemDisplayId", Integer(3998)),
      ])
      |> added(table: "ItemDisplaySourceEntry", copy_of: 4535, id: 9001, with: [
        #("itemMinLevel", Integer(3)),
        #("itemMaxLevel", Integer(5)),
        #("itemDisplayId", Integer(3838)),
      ]),
    )
  assert list.first(worn_of(loadout: first_holds)) == Ok(#(1, 3998))
    as "0x140444130: the item's power level is 2, which levels 1 to 3 hold and 3 to 5 do not"
  let second_holds =
    warrior_167_in(
      rows: rows
      |> added(
        table: "ItemDisplaySourceEntry",
        copy_of: 4535,
        id: 9001,
        with: [],
      )
      |> changed(table: "ItemDisplaySourceEntry", id: 4535, with: [
        #("itemDisplayId", Integer(3998)),
        #("itemMinLevel", Integer(3)),
        #("itemMaxLevel", Integer(5)),
      ]),
    )
  assert list.first(worn_of(loadout: second_holds)) == Ok(#(1, 3838))
    as "0x140444130: the entry whose levels hold the power level is the one found, whichever comes first"
}

pub fn an_item_with_a_display_of_its_own_is_drawn_with_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Item2 81359 (the chest) holds the display 0; it is edited to 3996, a display
  // of its own.
  let loadout =
    warrior_167_in(
      rows: changed(
        rows: with_displays(rows: fixture_tables.rows(), displays: [3996]),
        table: "Item2",
        id: 81_359,
        with: [#("itemDisplayId", Integer(3996))],
      ),
    )
  assert worn_of(loadout:)
    == [#(1, 3996), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 119)]
    as "opcode.0x262.worn_visuals: an Item2 itemDisplayId that is not 0 is the display, and the source's entries are not looked at"
}

/// The visual of item 99001, a copy of the heavy chest 81359 (type 15, source 75,
/// flags 1) that no set holds, with these flags.
fn visual_of_a_chest_with(
  flags flags: Int,
) -> Result(option.Option(worn_visual.WornVisual), worn_visual.WornVisualError) {
  let assert Ok(tables) =
    fixture_tables.load(
      rows: added(
        rows: fixture_tables.rows(),
        table: "Item2",
        copy_of: 81_359,
        id: 99_001,
        with: [#("flags", Integer(flags))],
      ),
    )
    as "the client's rows with an item no set holds load"
  worn_visual.of_item(tables:, item2_id: 99_001)
}

pub fn an_item_whose_flags_hold_0x4000_is_never_dressed_test() -> Nil {
  use <- owned_test.run(60_000)
  assert visual_of_a_chest_with(flags: 0x4001) == Ok(None)
    as "0x140444130: an item whose flags hold 0x4000 has no display entry, so no visual, though its source and type have an entry"
  assert visual_of_a_chest_with(flags: 1)
    == Ok(
      Some(worn_visual.WornVisual(
        slot: ItemSlotId(1),
        display: ItemDisplayId(3838),
      )),
    )
    as "the same item without the flag is dressed: ItemSlot 1 and the display of the entry of source 75 and type 15, 3838"
}

pub fn a_novice_item_whose_flags_hold_0x4000_is_not_read_and_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails(
      rows: changed(
        rows: fixture_tables.rows(),
        table: "Item2",
        id: 81_359,
        with: [
          #("flags", Integer(0x4001)),
        ],
      ),
    )
  assert string.contains(reason, "item 81359")
    && string.contains(reason, "0x4000")
    as {
      "FillItemInfo 0x1404445d0 takes most of the item's fields from GameFormula 1214's proxy item when its flags hold 0x4000, a path the properties do not follow, so the load refuses the item: "
      <> reason
    }
}

pub fn a_novice_item_with_no_item_display_source_entry_for_its_source_type_and_level_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails(rows: without(
      rows: fixture_tables.rows(),
      table: "ItemDisplaySourceEntry",
      id: 4535,
    ))
  assert string.contains(reason, "ItemDisplaySourceEntry")
    && string.contains(reason, "item source 75")
    && string.contains(reason, "item type 15")
    && string.contains(reason, "power level 2")
    as {
      "0x140444130: the heavy chest of source 75 has no entry, so the item has no display: "
      <> reason
    }
  // Entry 4535 holds levels 1 to 3; they are edited to 3 to 5.
  let reason =
    why_the_load_fails(
      rows: changed(
        rows: fixture_tables.rows(),
        table: "ItemDisplaySourceEntry",
        id: 4535,
        with: [#("itemMinLevel", Integer(3)), #("itemMaxLevel", Integer(5))],
      ),
    )
  assert string.contains(reason, "item source 75")
    && string.contains(reason, "power level 2")
    as {
      "0x140444130: an entry whose levels do not hold the power level is none: "
      <> reason
    }
}

pub fn a_display_with_no_item_display_row_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  a_load_without_the_row_fails(table: "ItemDisplay", id: 3838)
}
