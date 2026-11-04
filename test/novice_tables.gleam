//// The tables the Novice loadout reads (`genesis_prime/game/loadout`), planted
//// for the tests of the game rule and world entry, which run where the client's
//// files are absent. Each row is a row of the client's own tables with the
//// columns the server reads (`novice_tables_test` compares each with the real
//// row where the client is present); every other column is 0.
////
//// - The twelve PreTutorial CharacterCreation rows (start 4) that are the first
////   of each class and faction (466, 468, 469, 470, 471, 472, 478, 479, 480,
////   481, 484 and 485), with their item columns: the five armor pieces, the
////   shield and the weapon.
//// - The 44 Item2 rows those columns name, with their Item2Type, Item2Family,
////   Item2Category and ItemSlot rows.
//// - GameFormula rows 67, 547, 548, 549, 1260, 1261, 1265, 1266, 1286 and 1288, which
////   the item formulas and the sheet's power read, with the client's values.
//// - CreatureLevel rows 1 to 50, the levels a character can have, with their Base
////   Health.
//// - The 18 SpellLevel rows of level 1 with no prerequisite and class 1's rows
////   921 (level 4) and 928 (level 16, with a prerequisite), and the Spell4 rows
////   of the 18 level-1 spells, each with its Spell4Base id.

import genesis_prime/table/character_creation
import genesis_prime/table/creature_level
import genesis_prime/table/game_formula
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_slot
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/int
import gleam/list
import planted_table.{type Cell, Boolean, Float, Integer}

/// A Novice set the planted CharacterCreation rows hold: the row, its class and
/// faction, the five armor pieces, the shield and the weapon.
pub type Set {
  Set(
    creation_id: Int,
    class_id: Int,
    faction_id: Int,
    race_id: Int,
    sex: Int,
    items: List(Int),
    weapon: Int,
  )
}

/// The planted sets, with the items in the order of the row's item columns
/// (itemId0, itemId01, itemId02, itemId03, itemId04, itemId05, itemId06).
pub fn sets() -> List(Set) {
  [
    Set(
      creation_id: 466,
      class_id: 1,
      faction_id: 167,
      race_id: 1,
      sex: 1,
      items: [81_344, 81_359, 81_345, 8534, 81_346, 81_380, 81_381],
      weapon: 81_346,
    ),
    Set(
      creation_id: 468,
      class_id: 2,
      faction_id: 167,
      race_id: 1,
      sex: 0,
      items: [81_344, 81_359, 81_345, 8534, 81_347, 81_380, 81_381],
      weapon: 81_347,
    ),
    Set(
      creation_id: 469,
      class_id: 3,
      faction_id: 167,
      race_id: 1,
      sex: 0,
      items: [81_363, 81_362, 81_364, 8534, 81_351, 81_375, 81_376],
      weapon: 81_351,
    ),
    Set(
      creation_id: 470,
      class_id: 4,
      faction_id: 167,
      race_id: 1,
      sex: 0,
      items: [81_360, 81_358, 81_361, 8534, 81_348, 81_374, 81_378],
      weapon: 81_348,
    ),
    Set(
      creation_id: 471,
      class_id: 5,
      faction_id: 167,
      race_id: 1,
      sex: 0,
      items: [81_360, 81_358, 81_361, 8534, 81_349, 81_374, 81_378],
      weapon: 81_349,
    ),
    Set(
      creation_id: 472,
      class_id: 7,
      faction_id: 167,
      race_id: 1,
      sex: 0,
      items: [81_363, 81_362, 81_364, 8534, 81_350, 81_375, 81_376],
      weapon: 81_350,
    ),
    Set(
      creation_id: 478,
      class_id: 1,
      faction_id: 166,
      race_id: 1,
      sex: 1,
      items: [81_366, 81_365, 81_367, 8535, 81_352, 81_389, 81_390],
      weapon: 81_352,
    ),
    Set(
      creation_id: 479,
      class_id: 2,
      faction_id: 166,
      race_id: 1,
      sex: 0,
      items: [81_366, 81_365, 81_367, 8535, 81_353, 81_389, 81_390],
      weapon: 81_353,
    ),
    Set(
      creation_id: 480,
      class_id: 5,
      faction_id: 166,
      race_id: 1,
      sex: 0,
      items: [81_369, 81_368, 81_370, 8535, 81_355, 81_383, 81_387],
      weapon: 81_355,
    ),
    Set(
      creation_id: 481,
      class_id: 7,
      faction_id: 166,
      race_id: 1,
      sex: 1,
      items: [81_372, 81_371, 81_373, 8535, 81_356, 81_384, 81_385],
      weapon: 81_356,
    ),
    Set(
      creation_id: 484,
      class_id: 4,
      faction_id: 166,
      race_id: 1,
      sex: 0,
      items: [81_369, 81_368, 81_370, 8535, 81_354, 81_383, 81_387],
      weapon: 81_354,
    ),
    Set(
      creation_id: 485,
      class_id: 3,
      faction_id: 166,
      race_id: 1,
      sex: 0,
      items: [81_372, 81_371, 81_373, 8535, 81_357, 81_384, 81_385],
      weapon: 81_357,
    ),
  ]
}

/// The CharacterCreation rows of the sets: PreTutorial rows (start 4), enabled,
/// with no entitlement and no cost.
pub fn creation_rows() -> List(List(Cell)) {
  list.map(sets(), fn(set) {
    let columns = [
      "itemId0", "itemId01", "itemId02", "itemId03", "itemId04", "itemId05",
      "itemId06",
    ]
    planted_table.row(
      character_creation.schema,
      list.flatten([
        [
          #("ID", Integer(set.creation_id)),
          #("classId", Integer(set.class_id)),
          #("raceId", Integer(set.race_id)),
          #("sex", Integer(set.sex)),
          #("factionId", Integer(set.faction_id)),
          #("enabled", Boolean(True)),
          #("characterCreationStartEnum", Integer(4)),
        ],
        list.zip(columns, set.items)
          |> list.map(fn(pair) { #(pair.0, Integer(pair.1)) }),
      ]),
    )
  })
}

/// One planted Item2: its id, family, category, type and support power
/// percentage, the rest of a Novice item: power level 2, flags 1, no budget, no
/// stat and no equipped slot flags of its own.
type Item {
  Item(
    id: Int,
    family: Int,
    category: Int,
    type_id: Int,
    support: Float,
    flags: Int,
  )
}

fn items() -> List(Item) {
  [
    Item(8534, 15, 7, 53, 0.0, 1),
    Item(8535, 15, 7, 53, 0.0, 1),
    Item(81_344, 1, 3, 16, -1.0, 1),
    Item(81_345, 1, 3, 19, -1.0, 1),
    Item(81_346, 2, 8, 51, -0.5, 1),
    Item(81_347, 2, 108, 204, -0.5, 1),
    Item(81_348, 2, 12, 79, -0.5, 1),
    Item(81_349, 2, 24, 48, -0.5, 1),
    Item(81_350, 2, 16, 45, -0.5, 1),
    Item(81_351, 2, 22, 46, -0.5, 1),
    Item(81_352, 2, 8, 51, -0.5, 1),
    Item(81_353, 2, 108, 204, -0.5, 1),
    Item(81_354, 2, 12, 79, -0.5, 1),
    Item(81_355, 2, 24, 48, -0.5, 1),
    Item(81_356, 2, 16, 45, -0.5, 1),
    Item(81_357, 2, 22, 46, -0.5, 1),
    Item(81_358, 1, 2, 8, -1.0, 1),
    Item(81_359, 1, 3, 15, -1.0, 1),
    Item(81_360, 1, 2, 9, -1.0, 1),
    Item(81_361, 1, 2, 12, -1.0, 1),
    Item(81_362, 1, 1, 1, -1.0, 1),
    Item(81_363, 1, 1, 2, -1.0, 1),
    Item(81_364, 1, 1, 5, -1.0, 1),
    Item(81_365, 1, 3, 15, -1.0, 1),
    Item(81_366, 1, 3, 16, -1.0, 1),
    Item(81_367, 1, 3, 19, -1.0, 1),
    Item(81_368, 1, 2, 8, -1.0, 1),
    Item(81_369, 1, 2, 9, -1.0, 1),
    Item(81_370, 1, 2, 12, -1.0, 1),
    Item(81_371, 1, 1, 1, -1.0, 1),
    Item(81_372, 1, 1, 2, -1.0, 1),
    Item(81_373, 1, 1, 5, -1.0, 1),
    Item(81_374, 1, 2, 13, -1.0, 1),
    Item(81_375, 1, 1, 6, -1.0, 1),
    Item(81_376, 1, 1, 4, -1.0, 0),
    Item(81_378, 1, 2, 11, -1.0, 1),
    Item(81_380, 1, 3, 20, -1.0, 1),
    Item(81_381, 1, 3, 18, -1.0, 1),
    Item(81_383, 1, 2, 13, -1.0, 1),
    Item(81_384, 1, 1, 6, -1.0, 1),
    Item(81_385, 1, 1, 4, -1.0, 0),
    Item(81_387, 1, 2, 11, -1.0, 1),
    Item(81_389, 1, 3, 20, -1.0, 1),
    Item(81_390, 1, 3, 18, -1.0, 1),
  ]
}

/// The planted Item2 rows, in id order.
pub fn item2_rows() -> List(List(Cell)) {
  items()
  |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  |> list.map(fn(item) {
    planted_table.row(item2.schema, [
      #("ID", Integer(item.id)),
      #("item2FamilyId", Integer(item.family)),
      #("item2CategoryId", Integer(item.category)),
      #("item2TypeId", Integer(item.type_id)),
      #("powerLevel", Integer(2)),
      #("flags", Integer(item.flags)),
      #("supportPowerPercentage", Float(item.support)),
    ])
  })
}

/// The planted Item2Type rows: id and the ItemSlot the type names.
pub fn item2_type_rows() -> List(List(Cell)) {
  [
    #(1, 1),
    #(2, 2),
    #(4, 4),
    #(5, 5),
    #(6, 6),
    #(8, 1),
    #(9, 2),
    #(11, 4),
    #(12, 5),
    #(13, 6),
    #(15, 1),
    #(16, 2),
    #(18, 4),
    #(19, 5),
    #(20, 6),
    #(45, 20),
    #(46, 20),
    #(48, 20),
    #(51, 20),
    #(53, 43),
    #(79, 20),
    #(204, 20),
  ]
  |> list.map(fn(pair) {
    planted_table.row(item2_type.schema, [
      #("ID", Integer(pair.0)),
      #("itemSlotId", Integer(pair.1)),
    ])
  })
}

/// The planted Item2Family rows: id and flags (0x4e0, which hold 0x400).
pub fn item2_family_rows() -> List(List(Cell)) {
  list.map([1, 2, 15], fn(id) {
    planted_table.row(item2_family.schema, [
      #("ID", Integer(id)),
      #("flags", Integer(1248)),
    ])
  })
}

/// The planted Item2Category rows: id and armorModifier.
pub fn item2_category_rows() -> List(List(Cell)) {
  [
    #(1, 0.75),
    #(2, 1.0),
    #(3, 1.25),
    #(7, 1.0),
    #(8, 1.0),
    #(12, 1.0),
    #(16, 1.0),
    #(22, 1.0),
    #(24, 1.0),
    #(108, 0.0),
  ]
  |> list.map(fn(pair) {
    planted_table.row(item2_category.schema, [
      #("ID", Integer(pair.0)),
      #("armorModifier", Float(pair.1)),
    ])
  })
}

/// The planted ItemSlot rows: id, equippedSlotFlags and armorModifier.
pub fn item_slot_rows() -> List(List(Cell)) {
  [
    #(1, 1, 1.25),
    #(2, 2, 1.25),
    #(4, 8, 1.0),
    #(5, 16, 0.75),
    #(6, 32, 0.75),
    #(20, 65_536, 0.75),
    #(43, 32_768, 1.0),
  ]
  |> list.map(fn(row) {
    planted_table.row(item_slot.schema, [
      #("ID", Integer(row.0)),
      #("equippedSlotFlags", Integer(row.1)),
      #("armorModifier", Float(row.2)),
    ])
  })
}

/// One GameFormula row the item formulas read: its id, dataint0, dataint01, and
/// datafloat0 to datafloat03, as the client's row holds them.
pub type Formula {
  Formula(
    id: Int,
    dataint0: Int,
    dataint01: Int,
    float0: Float,
    float01: Float,
    float02: Float,
    float03: Float,
  )
}

/// The client's GameFormula rows the item formulas and the health rule read.
pub fn formulas() -> List(Formula) {
  [
    Formula(67, 0, 0, 0.0, 0.0, 60.0, 1.0),
    Formula(547, 0, 0, 0.0, 0.0, 20.0, 1.0),
    Formula(548, 0, 0, 0.0, 0.0, 225.0, 1.0),
    Formula(549, 0, 0, 0.0, 0.0, 3.5999999046325684, 1.0),
    Formula(1260, 0, 0, 0.75, 1.25, 0.05000000074505806, 0.25),
    Formula(1261, 10_000, 250, 0.25, 1.0, 0.0, 0.0),
    Formula(1265, 0, 0, 0.25, 0.009999999776482582, 25.0, 25.0),
    Formula(1266, 0, 0, 0.25, 0.25, 0.0, 0.0),
    Formula(1286, 50, 0, 1000.0, 0.0, 6.800000190734863, 1.0),
    Formula(1288, 0, 0, 0.0, 0.0, 132.0, 1.0),
  ]
}

/// The planted GameFormula row of a formula.
pub fn game_formula_row(formula: Formula) -> List(Cell) {
  planted_table.row(game_formula.schema, [
    #("ID", Integer(formula.id)),
    #("dataint0", Integer(formula.dataint0)),
    #("dataint01", Integer(formula.dataint01)),
    #("datafloat0", Float(formula.float0)),
    #("datafloat01", Float(formula.float01)),
    #("datafloat02", Float(formula.float02)),
    #("datafloat03", Float(formula.float03)),
  ])
}

/// The planted CreatureLevel rows 1 to 50: id and Base Health (property 7).
pub fn creature_level_rows() -> List(List(Cell)) {
  [
    #(1, 135.97027587890625),
    #(2, 216.53298950195312),
    #(3, 342.0863342285156),
    #(4, 569.6982421875),
    #(5, 735.8614501953125),
    #(6, 913.8118286132812),
    #(7, 1334.08056640625),
    #(8, 1715.159423828125),
    #(9, 2295.487548828125),
    #(10, 2777.490966796875),
    #(11, 3282.781982421875),
    #(12, 3826.12841796875),
    #(13, 4648.9853515625),
    #(14, 5128.69970703125),
    #(15, 6062.69677734375),
    #(16, 6781.31005859375),
    #(17, 7900.27587890625),
    #(18, 8795.77734375),
    #(19, 9776.603515625),
    #(20, 10_341.634765625),
    #(21, 11_134.140625),
    #(22, 12_012.7529296875),
    #(23, 12_495.0),
    #(24, 13_018.65625),
    #(25, 13_751.9755859375),
    #(26, 14_278.71875),
    #(27, 14_698.8134765625),
    #(28, 15_329.076171875),
    #(29, 16_371.4599609375),
    #(30, 17_350.00390625),
    #(31, 17_880.962890625),
    #(32, 18_390.791015625),
    #(33, 18_953.154296875),
    #(34, 19_546.228515625),
    #(35, 20_768.439453125),
    #(36, 21_485.65234375),
    #(37, 22_024.443359375),
    #(38, 23_204.66796875),
    #(39, 23_802.775390625),
    #(40, 25_488.08984375),
    #(41, 26_641.208984375),
    #(42, 27_681.95703125),
    #(43, 28_893.3828125),
    #(44, 30_785.15625),
    #(45, 31_909.65625),
    #(46, 32_825.56640625),
    #(47, 34_290.4609375),
    #(48, 35_420.49609375),
    #(49, 37_185.62109375),
    #(50, 39_706.17578125),
  ]
  |> list.map(fn(pair) {
    planted_table.row(creature_level.schema, [
      #("ID", Integer(pair.0)),
      #("unitPropertyValue07", Float(pair.1)),
    ])
  })
}

/// The planted SpellLevel rows: id, class, level, prerequisite and Spell4 id.
pub fn spell_level_rows() -> List(List(Cell)) {
  [
    #(631, 4, 1, 0, 58_832),
    #(647, 3, 1, 0, 32_893),
    #(766, 3, 1, 0, 32_809),
    #(780, 5, 1, 0, 38_765),
    #(807, 5, 1, 0, 38_779),
    #(808, 5, 1, 0, 38_791),
    #(919, 1, 1, 0, 32_078),
    #(920, 1, 1, 0, 58_524),
    #(921, 1, 4, 0, 32_128),
    #(925, 1, 1, 0, 58_591),
    #(928, 1, 16, 24_580, 53_599),
    #(1011, 7, 1, 0, 43_468),
    #(1036, 7, 1, 0, 34_718),
    #(1086, 4, 1, 0, 29_874),
    #(1089, 4, 1, 0, 42_352),
    #(1111, 2, 1, 0, 42_276),
    #(1185, 2, 1, 0, 41_276),
    #(1188, 2, 1, 0, 41_438),
    #(1236, 7, 1, 0, 34_355),
    #(1239, 3, 1, 0, 32_812),
  ]
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.map(fn(row) {
    planted_table.row(spell_level.schema, [
      #("ID", Integer(row.0)),
      #("classId", Integer(row.1)),
      #("characterLevel", Integer(row.2)),
      #("prerequisiteId", Integer(row.3)),
      #("spell4Id", Integer(row.4)),
    ])
  })
}

/// The Spell4 rows of the nine level-1 spells of classes 1, 2 and 4, each with
/// its Spell4Base id.
pub fn spell4_ids_and_bases() -> List(#(Int, Int)) {
  [
    #(29_874, 16_322),
    #(32_078, 18_309),
    #(32_809, 19_019),
    #(32_812, 19_022),
    #(32_893, 19_102),
    #(34_355, 20_325),
    #(34_718, 20_684),
    #(38_765, 23_148),
    #(38_779, 23_161),
    #(38_791, 23_173),
    #(41_276, 25_473),
    #(41_438, 25_635),
    #(42_276, 26_468),
    #(42_352, 26_543),
    #(43_468, 27_638),
    #(58_524, 37_968),
    #(58_591, 38_017),
    #(58_832, 38_201),
  ]
}

/// The planted Spell4 rows.
pub fn spell4_rows() -> List(List(Cell)) {
  list.map(spell4_ids_and_bases(), fn(pair) {
    planted_table.row(spell4.schema, [
      #("ID", Integer(pair.0)),
      #("spell4BaseIdBaseSpell", Integer(pair.1)),
    ])
  })
}

/// The planted files of the tables only the loadout reads, each by its file
/// name.
pub fn files() -> List(#(String, BitArray)) {
  [
    planted_table.file(item2.schema, item2_rows()),
    planted_table.file(item2_type.schema, item2_type_rows()),
    planted_table.file(item2_family.schema, item2_family_rows()),
    planted_table.file(item2_category.schema, item2_category_rows()),
    planted_table.file(item_slot.schema, item_slot_rows()),
    planted_table.file(creature_level.schema, creature_level_rows()),
    planted_table.file(spell4.schema, spell4_rows()),
    planted_table.file(spell_level.schema, spell_level_rows()),
  ]
}
