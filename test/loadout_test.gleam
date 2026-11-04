//// What a character of each class holds on entering the world, from the client's
//// tables (`genesis_prime/game/loadout`, `genesis_prime/game/item_property`).
//// Expected values come from these places.
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
////   feet 4, hands 5, shield 15 (`novice_tables.bag_index_of`).
//// - The worn visuals (`opcode.0x262.worn_visuals`, `Item2.novice_visuals`,
////   FindItemDisplaySourceEntry `0x140444130`): one per armor piece and the
////   weapon, in the ItemSlot id of its type (1 chest, 2 legs, 4 shoulder, 5
////   feet, 6 hands, 20 weapon), with the display of the ItemDisplaySourceEntry
////   row of its item source, item type and power level, and none for the
////   shield or for an item whose Item2 flags hold 0x4000.
//// - The starting abilities (`SpellLevel.spell4Id`, `opcode.0x111.ability_bag`):
////   the level-1 rows of the class with no prerequisite, in the order of their
////   ids, each as the Spell4Base id of its Spell4 row: Warrior 18309, 37968,
////   38017; Engineer 26468, 25473, 25635; Esper 19102, 19019, 19022; Medic
////   38201, 16322, 26543; Stalker 23148, 23161, 23173; Spellslinger 27638,
////   20684, 20325.
//// - Health: CreatureLevel row 1's Base Health 135.97 and the armor's 600, 736
////   at level 1 (`player.level1_base_health`, `0x14040e3d0`); at level 9, the
////   planted CreatureLevel row 9's 2295.49 and 600, 2895 (the same rule).
//// - The formulas: a value is computed from the rows, so a changed GameFormula
////   row changes it; each changed value below is worked by hand from the
////   formula of the address in its message.
//// - The load: a missing row the formulas read fails the load, with the table
////   and the id in the reason.

import character_tables
import client_tables
import genesis_prime/game/item_property.{Shield}
import genesis_prime/game/loadout.{type Loadout, Equipped}
import genesis_prime/game/worn_visual
import genesis_prime/table/character_creation
import genesis_prime/table/creature_level
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  ClassId, Item2Id, ItemDisplayId, ItemSlotId, Spell4BaseId,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_display_source_entry
import genesis_prime/table/item_slot
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import novice_tables
import owned_key
import owned_test
import planted_table
import unitest

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

fn assault_and_support(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, faction, loadout) {
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

pub fn a_novice_sets_ratings_are_203_0625_assault_and_55_6875_support_for_every_class_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  assault_and_support(tables: character_tables.shared())
}

pub fn a_novice_sets_ratings_are_203_0625_assault_and_55_6875_support_for_every_class_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assault_and_support(tables: client_tables.shared())
}

fn armor_and_health(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, faction, loadout) {
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

pub fn a_novice_sets_armor_is_250_for_heavy_200_for_medium_and_150_for_light_armor_and_its_base_health_600_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  armor_and_health(tables: character_tables.shared())
}

pub fn a_novice_sets_armor_is_250_for_heavy_200_for_medium_and_150_for_light_armor_and_its_base_health_600_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  armor_and_health(tables: client_tables.shared())
}

fn shield(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, _faction, loadout) {
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
  })
}

pub fn a_novice_sets_shield_is_450_with_mitigation_0_625_regeneration_0_15_and_reboot_5125_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  shield(tables: character_tables.shared())
}

pub fn a_novice_sets_shield_is_450_with_mitigation_0_625_regeneration_0_15_and_reboot_5125_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  shield(tables: client_tables.shared())
}

fn weapons_and_abilities(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, faction, loadout) {
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

pub fn a_loadout_is_the_classes_weapon_in_slot_16_and_its_three_level_1_spells_in_spell_level_order_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  weapons_and_abilities(tables: character_tables.shared())
}

pub fn a_loadout_is_the_classes_weapon_in_slot_16_and_its_three_level_1_spells_in_spell_level_order_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  weapons_and_abilities(tables: client_tables.shared())
}

fn health(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, _faction, loadout) {
    assert loadout.max_health(tables:, loadout:, level: 1) == Ok(736)
      as {
        "player.level1_base_health: the "
        <> class.name
        <> "'s 135.97 (CreatureLevel row 1) and 600 (the armor) round to 736"
      }
  })
}

pub fn a_level_1_players_health_is_736_for_every_class_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  health(tables: character_tables.shared())
}

pub fn a_level_1_players_health_is_736_for_every_class_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  health(tables: client_tables.shared())
}

pub fn a_players_health_is_the_creature_level_rows_base_health_of_its_level_plus_the_armors_600_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(4), faction_id: 166)
    as "class 4 faction 166 has a set"
  assert loadout.max_health(tables:, loadout:, level: 9) == Ok(2895)
    as "the planted CreatureLevel row 9's 2295.49 and 600, 2895"
  assert loadout.max_health(tables:, loadout:, level: 51) == Error(Nil)
    as "no CreatureLevel row 51 is planted, nor does the client's table hold a level above 50 a character can have"
}

/// The planted files with one GameFormula row changed.
fn files_with_formula(
  formula formula: novice_tables.Formula,
) -> List(#(String, BitArray)) {
  let formulas =
    list.map(novice_tables.formulas(), fn(planted) {
      case planted.id == formula.id {
        True -> formula
        False -> planted
      }
    })
  files_with_formulas(formulas:)
}

fn files_with_formulas(
  formulas formulas: List(novice_tables.Formula),
) -> List(#(String, BitArray)) {
  list.map(character_tables.files(), fn(file) {
    case file.0 == game_formula.schema.file {
      True ->
        planted_table.file(
          game_formula.schema,
          list.flatten([
            character_tables.game_formula_rows(
              ids: [character_tables.highest_level_formula],
              highest: 50,
            ),
            list.map(formulas, novice_tables.game_formula_row),
          ]),
        )
      False -> file
    }
  })
}

fn loaded(
  files files: List(#(String, BitArray)),
) -> Result(table_store.Tables, table_store.LoadError) {
  use folder <- planted_table.in_folder(files)
  server_table.load_under(under: owned_key.new(), from: folder)
}

/// The Warrior of faction 166's loadout in tables loaded from the files, which
/// are unloaded after.
fn warrior_in(files files: List(#(String, BitArray))) -> #(Loadout, Int) {
  let assert Ok(tables) = loaded(files:)
    as "the planted tables with a changed GameFormula row load"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "class 1 faction 166 has a set"
  let assert Ok(health) = loadout.max_health(tables:, loadout:, level: 1)
    as "CreatureLevel row 1 is planted"
  table_store.unload(tables)
  #(loadout, health)
}

pub fn a_changed_formula_row_changes_the_weapons_ratings_the_armors_ratings_the_armor_the_health_and_the_shield_test() -> Nil {
  use <- owned_test.run(60_000)
  let formula = fn(id) {
    let assert Ok(row) =
      list.find(novice_tables.formulas(), fn(planted) { planted.id == id })
      as "the planted GameFormula row exists"
    row
  }
  let #(weapon_slope_doubled, _) =
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(1288), float02: 264.0),
    ))
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
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(549), float02: 7.5),
    ))
  assert close(
    value: armor_slope_doubled.properties.assault_rating,
    to: 242.0625,
  )
    as "0x14041da70: GameFormula 549 at 7.5 gives each piece 7.5 x 2 x its slot's modifier, 75.0 over the set's modifiers (1.25 + 1.25 + 1 + 0.75 + 0.75 = 5), and leaves the weapon's 167.0625"
  let #(factor_raised, _) =
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(1265), float0: 0.5),
    ))
  assert close(value: factor_raised.properties.assault_rating, to: 221.625)
    as "0x14040df10: GameFormula 1265's first value 0.5 gives the weapon v = 0.75 x 264 x 1.25 = 247.5, Assault Rating 185.625, and the armor's 36.0 (b = -1 leaves its factor 1)"
  assert close(value: factor_raised.properties.support_rating, to: 61.875)
    as "0x14040df10: a quarter of 247.5"
  let #(armor_curve_doubled, _) =
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(547), float02: 40.0),
    ))
  assert close(value: armor_curve_doubled.properties.armor, to: 500.0)
    as "0x14041deb0: GameFormula 547 at 40 doubles the heavy set's armor to 500"
  let #(health_curve_doubled, health) =
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(67), float02: 120.0),
    ))
  assert close(value: health_curve_doubled.properties.base_health, to: 1200.0)
    as "GameFormula 67 at 120 doubles the armor's Base Health to 1200"
  assert health == 1336 as "135.97 and 1200 round to 1336"
  let #(shield_curve_doubled, _) =
    warrior_in(files: files_with_formula(
      formula: novice_tables.Formula(..formula(548), float02: 450.0),
    ))
  let assert Some(doubled) = shield_curve_doubled.properties.shield
    as "the set still holds a shield"
  assert close(value: doubled.capacity_max, to: 900.0)
    && close(value: doubled.mitigation_max, to: 0.625)
    && close(value: doubled.regen_percent, to: 0.15)
    && doubled.reboot_time_ms == 5125
    as "0x14041d850: GameFormula 548 at 450 doubles the shield's capacity to 900 and changes no other shield value"
  let #(shield_factors_changed, _) =
    warrior_in(
      files: files_with_formulas(
        formulas: list.map(novice_tables.formulas(), fn(row) {
          case row.id {
            1260 ->
              novice_tables.Formula(
                ..row,
                float0: 1.5,
                float01: 2.5,
                float02: 0.1,
                float03: 0.5,
              )
            1261 ->
              novice_tables.Formula(
                ..row,
                dataint0: 20_000,
                dataint01: 500,
                float0: 0.5,
                float01: 2.0,
              )
            _ -> row
          }
        }),
      ),
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

/// The planted files with the rows of the schema's table replaced.
fn files_replacing(
  schema schema: tbl_file.Schema,
  rows rows: List(List(planted_table.Cell)),
) -> List(#(String, BitArray)) {
  files_replacing_all(changes: [#(schema, rows)])
}

/// The planted files with the rows of each changed table replaced.
fn files_replacing_all(
  changes changes: List(#(tbl_file.Schema, List(List(planted_table.Cell)))),
) -> List(#(String, BitArray)) {
  list.map(character_tables.files(), fn(file) {
    case list.find(changes, fn(change) { { change.0 }.file == file.0 }) {
      Ok(#(schema, rows)) -> planted_table.file(schema, rows)
      Error(Nil) -> file
    }
  })
}

/// Why the load of the planted files fails, as the reason the loadouts could
/// not be built.
fn why_the_load_fails(files files: List(#(String, BitArray))) -> String {
  let assert Error(table_store.DerivationFailed(name: "Loadouts", reason:)) =
    loaded(files:)
    as "the load without a row the loadouts read fails in their build"
  reason
}

pub fn a_missing_formula_row_fails_the_load_naming_the_table_and_the_id_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([67, 547, 548, 549, 1260, 1261, 1265, 1286, 1288], fn(id) {
    let reason =
      why_the_load_fails(
        files: files_with_formulas(
          formulas: list.filter(novice_tables.formulas(), fn(row) {
            row.id != id
          }),
        ),
      )
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
fn a_load_without_the_row_fails(
  schema schema: tbl_file.Schema,
  rows rows: List(List(planted_table.Cell)),
  id id: Int,
  table table: String,
) -> Nil {
  let reason =
    why_the_load_fails(files: files_replacing(
      schema:,
      rows: planted_table.without(rows:, ids: [id]),
    ))
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
  a_load_without_the_row_fails(
    schema: item2_category.schema,
    rows: novice_tables.item2_category_rows(),
    id: 3,
    table: "Item2Category",
  )
  a_load_without_the_row_fails(
    schema: item_slot.schema,
    rows: novice_tables.item_slot_rows(),
    id: 20,
    table: "ItemSlot",
  )
  a_load_without_the_row_fails(
    schema: item2.schema,
    rows: novice_tables.item2_rows(),
    id: 81_352,
    table: "Item2",
  )
  a_load_without_the_row_fails(
    schema: item2_type.schema,
    rows: novice_tables.item2_type_rows(),
    id: 51,
    table: "Item2Type",
  )
  a_load_without_the_row_fails(
    schema: item2_family.schema,
    rows: novice_tables.item2_family_rows(),
    id: 2,
    table: "Item2Family",
  )
  a_load_without_the_row_fails(
    schema: creature_level.schema,
    rows: novice_tables.creature_level_rows(),
    id: 17,
    table: "CreatureLevel",
  )
  a_load_without_the_row_fails(
    schema: spell4.schema,
    rows: novice_tables.spell4_rows(),
    id: 58_591,
    table: "Spell4",
  )
}

pub fn a_class_with_no_level_1_spell_row_or_a_createable_class_and_faction_with_no_novice_set_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails(files: files_replacing(
      schema: spell_level.schema,
      rows: planted_table.without(rows: novice_tables.spell_level_rows(), ids: [
        631,
        1086,
        1089,
      ]),
    ))
  assert string.contains(reason, "SpellLevel")
    && string.contains(reason, "class 4")
    as { "no level-1 SpellLevel row for class 4: " <> reason }
  let reason =
    why_the_load_fails(files: files_replacing(
      schema: character_creation.schema,
      rows: planted_table.without(rows: character_tables.creation_rows(), ids: [
        478,
      ]),
    ))
  assert string.contains(reason, "CharacterCreation")
    && string.contains(reason, "class 1")
    && string.contains(reason, "faction 166")
    as {
      "CharacterCreation row 359 (class 1, faction 166, start 3) is a row a player can make, and without row 478 its class and faction have no Novice set: "
      <> reason
    }
}

pub fn a_formula_with_no_value_at_the_power_level_fails_the_load_naming_the_formula_and_the_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let formula = fn(id) {
    let assert Ok(row) =
      list.find(novice_tables.formulas(), fn(planted) { planted.id == id })
      as "the planted GameFormula row exists"
    row
  }
  let reason =
    why_the_load_fails(files: files_with_formula(
      formula: novice_tables.Formula(..formula(549), dataint0: 5, float03: 0.5),
    ))
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

/// The set's armor pieces and shield held at location 0: the item and the bag
/// index of the lowest bit of its ItemSlot's flags, in bag order.
fn equipped_armor(
  class class: Class,
  faction faction: Int,
) -> List(loadout.Equipped) {
  let assert Ok(set) =
    list.find(novice_tables.sets(), fn(set) {
      set.class_id == class.id && set.faction_id == faction
    })
    as "the planted sets hold every class and faction"
  novice_tables.equipped_of(set:)
  |> list.filter(fn(pair) { pair.0 != weapon_of(class:, faction:) })
  |> list.map(fn(pair) { Equipped(item: Item2Id(pair.0), bag_index: pair.1) })
}

fn armor_bag_indexes(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, faction, loadout) {
    assert loadout.armor == equipped_armor(class:, faction:)
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

pub fn a_loadouts_armor_is_its_five_pieces_and_shield_at_the_bag_index_of_their_slot_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  armor_bag_indexes(tables: character_tables.shared())
}

pub fn a_loadouts_armor_is_its_five_pieces_and_shield_at_the_bag_index_of_their_slot_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  armor_bag_indexes(tables: client_tables.shared())
}

/// The planted ItemSlot rows with the slot `id` holding these equipped slot
/// flags.
fn item_slot_rows_with(
  id id: Int,
  flags flags: Int,
) -> List(List(planted_table.Cell)) {
  list.map(novice_tables.item_slots(), fn(slot) {
    case slot.0 == id {
      True -> #(id, flags, slot.2)
      False -> slot
    }
  })
  |> list.map(novice_tables.item_slot_row)
}

pub fn a_changed_item_slot_row_changes_the_bag_index_of_the_pieces_of_its_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(tables) =
    loaded(files: files_replacing(
      schema: item_slot.schema,
      rows: item_slot_rows_with(id: 1, flags: 4096),
    ))
    as "the planted tables with a changed ItemSlot row load"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "class 1 faction 166 has a set"
  table_store.unload(tables)
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
  let reason =
    why_the_load_fails(files: files_replacing(
      schema: item_slot.schema,
      rows: item_slot_rows_with(id: 2, flags: 0),
    ))
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

fn worn_visuals(tables tables: table_store.Tables) -> Nil {
  every_set(tables:, check: fn(class, faction, loadout) {
    assert worn_of(loadout:)
      == novice_tables.worn_visuals(class_id: class.id, faction_id: faction)
      as {
        "opcode.0x262.worn_visuals: the "
        <> class.name
        <> " of faction "
        <> int.to_string(faction)
        <> " wears its five pieces and its weapon, and nothing for the shield (slot 43, display 0)"
      }
  })
}

pub fn a_loadouts_worn_visuals_are_its_five_pieces_and_weapon_in_the_slot_and_display_of_each_set_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  worn_visuals(tables: character_tables.shared())
}

pub fn a_loadouts_worn_visuals_are_its_five_pieces_and_weapon_in_the_slot_and_display_of_each_set_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  worn_visuals(tables: client_tables.shared())
}

/// The rows of tables to plant in place of the planted ones.
type Changes =
  List(#(tbl_file.Schema, List(List(planted_table.Cell))))

/// The Warrior of faction 167's loadout in tables loaded from the planted files
/// with these tables replaced.
fn warrior_167_in(changes changes: Changes) -> Loadout {
  let assert Ok(tables) = loaded(files: files_replacing_all(changes:))
    as "the planted tables with the changed rows load"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 167)
    as "class 1 faction 167 has a set"
  table_store.unload(tables)
  loadout
}

/// The planted entries with the one of id `id` replaced by `entry` and the
/// entries `added` appended, as rows.
fn entries_with(
  replacing id: Int,
  by entry: novice_tables.SourceEntry,
  added added: List(novice_tables.SourceEntry),
) -> List(List(planted_table.Cell)) {
  list.map(novice_tables.source_entries(), fn(planted) {
    case planted.id == id {
      True -> entry
      False -> planted
    }
  })
  |> list.append(added)
  |> list.map(novice_tables.source_entry_row)
}

/// The planted ItemDisplay rows and one for each of these displays.
fn displays_with(
  displays displays: List(Int),
) -> List(List(planted_table.Cell)) {
  list.append(
    novice_tables.item_display_rows(),
    list.map(displays, novice_tables.item_display_row),
  )
}

pub fn a_changed_item_display_source_entry_changes_the_visual_of_its_item_test() -> Nil {
  use <- owned_test.run(60_000)
  let chest = novice_tables.SourceEntry(4535, 75, 15, 1, 3, 3999)
  let loadout =
    warrior_167_in(changes: [
      #(
        item_display_source_entry.schema,
        entries_with(replacing: 4535, by: chest, added: []),
      ),
      #(item_display.schema, displays_with(displays: [3999])),
    ])
  assert worn_of(loadout:)
    == [#(1, 3999), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 119)]
    as "0x140444130: the chest 81359 (source 75, type 15) takes the display of the entry's row, here 3999, and no other piece changes"
}

pub fn the_entry_whose_levels_hold_the_items_power_level_gives_its_display_test() -> Nil {
  use <- owned_test.run(60_000)
  let displays = displays_with(displays: [3998])
  let low = novice_tables.SourceEntry(4535, 75, 15, 1, 3, 3998)
  let high = novice_tables.SourceEntry(9001, 75, 15, 3, 5, 3838)
  let first_holds =
    warrior_167_in(changes: [
      #(
        item_display_source_entry.schema,
        entries_with(replacing: 4535, by: low, added: [high]),
      ),
      #(item_display.schema, displays),
    ])
  assert list.first(worn_of(loadout: first_holds)) == Ok(#(1, 3998))
    as "0x140444130: the item's power level is 2, which levels 1 to 3 hold and 3 to 5 do not"
  let second_holds =
    warrior_167_in(changes: [
      #(
        item_display_source_entry.schema,
        entries_with(
          replacing: 4535,
          by: novice_tables.SourceEntry(..low, min_level: 3, max_level: 5),
          added: [novice_tables.SourceEntry(..high, min_level: 1, max_level: 3)],
        ),
      ),
      #(item_display.schema, displays),
    ])
  assert list.first(worn_of(loadout: second_holds)) == Ok(#(1, 3838))
    as "0x140444130: the entry whose levels hold the power level is the one found, whichever comes first"
}

pub fn an_item_with_a_display_of_its_own_is_drawn_with_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let loadout =
    warrior_167_in(changes: [
      #(
        item2.schema,
        novice_tables.item2_rows_with(id: 81_359, display: 3996, flags: 1),
      ),
      #(item_display.schema, displays_with(displays: [3996])),
    ])
  assert worn_of(loadout:)
    == [#(1, 3996), #(2, 3840), #(4, 530), #(5, 3841), #(6, 3839), #(20, 119)]
    as "opcode.0x262.worn_visuals: an Item2 itemDisplayId that is not 0 is the display, and the source's entries are not looked at"
}

/// The planted Item2 rows and one more, item 99001, of the heavy chest type 15
/// and the source 75, which no set holds, with these flags.
fn item2_rows_and_a_chest_with(
  flags flags: Int,
) -> List(List(planted_table.Cell)) {
  list.append(novice_tables.item2_rows(), [
    planted_table.row(item2.schema, [
      #("ID", planted_table.Integer(99_001)),
      #("item2FamilyId", planted_table.Integer(1)),
      #("item2CategoryId", planted_table.Integer(3)),
      #("item2TypeId", planted_table.Integer(15)),
      #("itemSourceId", planted_table.Integer(75)),
      #("powerLevel", planted_table.Integer(2)),
      #("flags", planted_table.Integer(flags)),
      #("supportPowerPercentage", planted_table.Float(-1.0)),
    ]),
  ])
}

/// The visual of item 99001 with these flags, in tables loaded from the planted
/// files and that item.
fn visual_of_a_chest_with(
  flags flags: Int,
) -> Result(option.Option(worn_visual.WornVisual), worn_visual.WornVisualError) {
  let assert Ok(tables) =
    loaded(files: files_replacing(
      schema: item2.schema,
      rows: item2_rows_and_a_chest_with(flags:),
    ))
    as "the planted tables with an item no set holds load"
  let visual = worn_visual.of_item(tables:, item2_id: 99_001)
  table_store.unload(tables)
  visual
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
    why_the_load_fails_with(changes: [
      #(
        item2.schema,
        novice_tables.item2_rows_with(id: 81_359, display: 0, flags: 0x4001),
      ),
    ])
  assert string.contains(reason, "item 81359")
    && string.contains(reason, "0x4000")
    as {
      "FillItemInfo 0x1404445d0 takes most of the item's fields from GameFormula 1214's proxy item when its flags hold 0x4000, a path the properties do not follow, so the load refuses the item: "
      <> reason
    }
}

/// Why the load of the planted files with these tables replaced fails.
fn why_the_load_fails_with(changes changes: Changes) -> String {
  why_the_load_fails(files: files_replacing_all(changes:))
}

pub fn a_novice_item_with_no_item_display_source_entry_for_its_source_type_and_level_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let reason =
    why_the_load_fails_with(changes: [
      #(
        item_display_source_entry.schema,
        list.filter(novice_tables.source_entries(), fn(entry) {
          entry.id != 4535
        })
          |> list.map(novice_tables.source_entry_row),
      ),
    ])
  assert string.contains(reason, "ItemDisplaySourceEntry")
    && string.contains(reason, "item source 75")
    && string.contains(reason, "item type 15")
    && string.contains(reason, "power level 2")
    as {
      "0x140444130: the heavy chest of source 75 has no entry, so the item has no display: "
      <> reason
    }
  let out_of_range = novice_tables.SourceEntry(4535, 75, 15, 3, 5, 3838)
  let reason =
    why_the_load_fails_with(changes: [
      #(
        item_display_source_entry.schema,
        entries_with(replacing: 4535, by: out_of_range, added: []),
      ),
    ])
  assert string.contains(reason, "item source 75")
    && string.contains(reason, "power level 2")
    as {
      "0x140444130: an entry whose levels do not hold the power level is none: "
      <> reason
    }
}

pub fn a_display_with_no_item_display_row_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  a_load_without_the_row_fails(
    schema: item_display.schema,
    rows: novice_tables.item_display_rows(),
    id: 3838,
    table: "ItemDisplay",
  )
}
