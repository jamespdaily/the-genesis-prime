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
//// - The 42 ItemDisplaySourceEntry rows of the sources 75 (faction 167) and 76
////   (faction 166) for the item types the sets use, and the ItemDisplay rows
////   their displays name (`Item2.novice_visuals`).
//// - GameFormula rows 67, 547, 548, 549, 1260, 1261, 1265, 1266, 1286 and 1288, which
////   the item formulas and the sheet's power read, with the client's values.
//// - CreatureLevel rows 1 to 50, the levels a character can have, with their Base
////   Health.
//// - The 18 SpellLevel rows of level 1 with no prerequisite and class 1's rows
////   921 (level 4) and 928 (level 16, with a prerequisite), and the Spell4 rows
////   of the 18 level-1 spells, each with its Spell4Base id.

import genesis_prime/table/character_creation
import genesis_prime/table/class
import genesis_prime/table/creature_level
import genesis_prime/table/game_formula
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_display_source_entry
import genesis_prime/table/item_slot
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/telegraph_damage
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import planted_table.{type Cell, Boolean, Float, Integer}
import spell_tables

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
/// percentage, the rest of a Novice item: power level 2, no budget, no
/// stat, no item display and no equipped slot flags of its own, and the item
/// source of its faction's sets (`source_of`) except a shield's, which has none.
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

/// The Item2Type of a shield, the one type the Novice sets hold that no
/// ItemDisplaySourceEntry row names.
const shield_type = 53

/// The itemSourceId of a Novice item: 75 for the sets of faction 167, 76 for
/// those of faction 166, and none for a shield.
fn source_of(item item: Item) -> Int {
  use <- bool.guard(item.type_id == shield_type, 0)
  let assert Ok(set) =
    list.find(sets(), fn(set) { list.contains(set.items, item.id) })
    as "every planted item is in a set"
  case set.faction_id {
    167 -> 75
    _ -> 76
  }
}

/// The planted Item2 rows, in id order.
pub fn item2_rows() -> List(List(Cell)) {
  items()
  |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  |> list.map(item2_row(item: _, display: 0, flags: None))
}

/// The planted Item2 rows with the item `id` holding the item display and the
/// flags given, the rest as they are planted.
pub fn item2_rows_with(
  id id: Int,
  display display: Int,
  flags flags: Int,
) -> List(List(Cell)) {
  items()
  |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  |> list.map(fn(item) {
    case item.id == id {
      True -> item2_row(item:, display:, flags: Some(flags))
      False -> item2_row(item:, display: 0, flags: None)
    }
  })
}

fn item2_row(
  item item: Item,
  display display: Int,
  flags flags: Option(Int),
) -> List(Cell) {
  planted_table.row(item2.schema, [
    #("ID", Integer(item.id)),
    #("item2FamilyId", Integer(item.family)),
    #("item2CategoryId", Integer(item.category)),
    #("item2TypeId", Integer(item.type_id)),
    #("itemDisplayId", Integer(display)),
    #("itemSourceId", Integer(source_of(item:))),
    #("powerLevel", Integer(2)),
    #("flags", Integer(option.unwrap(flags, item.flags))),
    #("supportPowerPercentage", Float(item.support)),
  ])
}

/// The bag index a Novice item of the Item2Type is equipped at: the lowest bit
/// of the equipped slot flags of its ItemSlot (`ItemSlot.equippedSlotFlags`,
/// GetSlot 0x140418a50), which the client's own map from a bag index back to its
/// ItemSlot agrees with (0x140c39050). Chest types 15, 8 and 1 are 0; legs 16,
/// 9 and 2 are 1; shoulder 18, 11 and 4 are 3; feet 19, 12 and 5 are 4; hands
/// 20, 13 and 6 are 5; the shield type 53 is 15 and the weapon types are 16.
pub fn bag_index_of(type_id type_id: Int) -> Int {
  case type_id {
    15 | 8 | 1 -> 0
    16 | 9 | 2 -> 1
    18 | 11 | 4 -> 3
    19 | 12 | 5 -> 4
    20 | 13 | 6 -> 5
    53 -> 15
    45 | 46 | 48 | 51 | 79 | 204 -> 16
    _ -> panic as "the Novice sets hold no other item type"
  }
}

/// The set's items equipped at location 0, each with its bag index, in bag
/// order: the five armor pieces, the shield and the weapon.
pub fn equipped_of(set set: Set) -> List(#(Int, Int)) {
  list.map(set.items, fn(item_id) {
    let assert Ok(item) = list.find(items(), fn(item) { item.id == item_id })
      as "every item of a set is planted"
    #(item_id, bag_index_of(type_id: item.type_id))
  })
  |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
}

/// One planted ItemDisplaySourceEntry: its id, item source, item type, the
/// levels it holds for and the display it gives.
pub type SourceEntry {
  SourceEntry(
    id: Int,
    source: Int,
    type_id: Int,
    min_level: Int,
    max_level: Int,
    display: Int,
  )
}

/// The client's entries of the Novice sources for the item types the sets use,
/// each for levels 1 to 3 (`Item2.novice_visuals`).
pub fn source_entries() -> List(SourceEntry) {
  [
    #(4527, 75, 51, 119),
    #(4528, 75, 204, 3407),
    #(4529, 75, 46, 1354),
    #(4530, 75, 48, 3380),
    #(4531, 75, 79, 3279),
    #(4532, 75, 45, 22),
    #(4534, 75, 18, 530),
    #(4535, 75, 15, 3838),
    #(4536, 75, 16, 3840),
    #(4537, 75, 19, 3841),
    #(4538, 75, 20, 3839),
    #(4540, 75, 11, 4148),
    #(4541, 75, 8, 48),
    #(4542, 75, 9, 50),
    #(4543, 75, 12, 47),
    #(4544, 75, 13, 46),
    #(4546, 75, 4, 3885),
    #(4547, 75, 1, 3233),
    #(4548, 75, 2, 3234),
    #(4549, 75, 5, 3235),
    #(4550, 75, 6, 84),
    #(4551, 76, 51, 120),
    #(4552, 76, 204, 3409),
    #(4553, 76, 46, 1355),
    #(4554, 76, 48, 1063),
    #(4555, 76, 79, 3280),
    #(4556, 76, 45, 38),
    #(4558, 76, 18, 4179),
    #(4559, 76, 15, 3842),
    #(4560, 76, 16, 3844),
    #(4561, 76, 19, 3845),
    #(4562, 76, 20, 3843),
    #(4564, 76, 11, 4158),
    #(4565, 76, 8, 4106),
    #(4566, 76, 9, 4107),
    #(4567, 76, 12, 4105),
    #(4568, 76, 13, 4104),
    #(4570, 76, 4, 3884),
    #(4571, 76, 1, 3239),
    #(4572, 76, 2, 3240),
    #(4573, 76, 5, 3241),
    #(4574, 76, 6, 84),
  ]
  |> list.map(fn(entry) {
    SourceEntry(
      id: entry.0,
      source: entry.1,
      type_id: entry.2,
      min_level: 1,
      max_level: 3,
      display: entry.3,
    )
  })
}

/// The planted ItemDisplaySourceEntry row of an entry.
pub fn source_entry_row(entry: SourceEntry) -> List(Cell) {
  planted_table.row(item_display_source_entry.schema, [
    #("ID", Integer(entry.id)),
    #("itemSourceId", Integer(entry.source)),
    #("item2TypeId", Integer(entry.type_id)),
    #("itemMinLevel", Integer(entry.min_level)),
    #("itemMaxLevel", Integer(entry.max_level)),
    #("itemDisplayId", Integer(entry.display)),
  ])
}

/// The planted ItemDisplaySourceEntry rows, in id order.
pub fn source_entry_rows() -> List(List(Cell)) {
  list.map(source_entries(), source_entry_row)
}

/// The planted ItemDisplay rows of the displays the entries name, in id order:
/// the id alone, which is all the server reads of a display.
pub fn item_display_rows() -> List(List(Cell)) {
  list.map(source_entries(), fn(entry) { entry.display })
  |> list.unique
  |> list.sort(int.compare)
  |> list.map(item_display_row)
}

/// The planted ItemDisplay row of a display.
pub fn item_display_row(display: Int) -> List(Cell) {
  planted_table.row(item_display.schema, [#("ID", Integer(display))])
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

/// The ItemSlot ids of a Novice set's visuals in the order the loadout lists
/// them: chest, legs, shoulder, feet, hands and the weapon
/// (`opcode.0x262.worn_visuals`).
pub const worn_slots = [1, 2, 4, 5, 6, 20]

/// The displays of a class's set of a faction, in the order of `worn_slots`
/// (`Item2.novice_visuals`, from the ItemDisplaySourceEntry rows of itemSourceId
/// 75 for faction 167 and 76 for faction 166): Warrior and Engineer wear heavy
/// armor, Medic and Stalker medium, Esper and Spellslinger light, and each class
/// its own weapon.
pub fn worn_displays(
  class_id class_id: Int,
  faction_id faction_id: Int,
) -> List(Int) {
  case class_id, faction_id {
    1, 167 -> [3838, 3840, 530, 3841, 3839, 119]
    1, _ -> [3842, 3844, 4179, 3845, 3843, 120]
    2, 167 -> [3838, 3840, 530, 3841, 3839, 3407]
    2, _ -> [3842, 3844, 4179, 3845, 3843, 3409]
    3, 167 -> [3233, 3234, 3885, 3235, 84, 1354]
    3, _ -> [3239, 3240, 3884, 3241, 84, 1355]
    4, 167 -> [48, 50, 4148, 47, 46, 3279]
    4, _ -> [4106, 4107, 4158, 4105, 4104, 3280]
    5, 167 -> [48, 50, 4148, 47, 46, 3380]
    5, _ -> [4106, 4107, 4158, 4105, 4104, 1063]
    7, 167 -> [3233, 3234, 3885, 3235, 84, 22]
    7, _ -> [3239, 3240, 3884, 3241, 84, 38]
    _, _ -> panic as "the Novice sets are of the six classes"
  }
}

/// The slot and display of each visual a class's set of a faction wears, as the
/// Novice set draws them (`opcode.0x262.worn_visuals`).
pub fn worn_visuals(
  class_id class_id: Int,
  faction_id faction_id: Int,
) -> List(#(Int, Int)) {
  list.zip(worn_slots, worn_displays(class_id:, faction_id:))
}

/// The planted ItemSlot rows' values: id, equippedSlotFlags and armorModifier.
pub fn item_slots() -> List(#(Int, Int, Float)) {
  [
    #(1, 1, 1.25),
    #(2, 2, 1.25),
    #(4, 8, 1.0),
    #(5, 16, 0.75),
    #(6, 32, 0.75),
    #(20, 65_536, 0.75),
    #(43, 32_768, 1.0),
  ]
}

/// The planted ItemSlot row of a slot's values.
pub fn item_slot_row(slot: #(Int, Int, Float)) -> List(Cell) {
  planted_table.row(item_slot.schema, [
    #("ID", Integer(slot.0)),
    #("equippedSlotFlags", Integer(slot.1)),
    #("armorModifier", Float(slot.2)),
  ])
}

/// The planted ItemSlot rows.
pub fn item_slot_rows() -> List(List(Cell)) {
  list.map(item_slots(), item_slot_row)
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

/// The client's GameFormula rows the item formulas, the health rule and the hit rule's
/// ratings read: 1230 strikethrough, 1231 crit chance, 1232 crit severity, 1234
/// mitigation, 1235 deflect, 1236 critical deflect, 1245 glance chance and 1271 glance
/// amount are the hit rule's (`genesis_prime/game/rating`; `rating_support` builds the
/// rule's formulas from them).
pub fn formulas() -> List(Formula) {
  [
    Formula(67, 0, 0, 0.0, 0.0, 60.0, 1.0),
    Formula(547, 0, 0, 0.0, 0.0, 20.0, 1.0),
    Formula(548, 0, 0, 0.0, 0.0, 225.0, 1.0),
    Formula(549, 0, 0, 0.0, 0.0, 3.5999999046325684, 1.0),
    Formula(712, 0, 0, 70.0, 100.0, 1.0, 1.0),
    Formula(1230, 0, 100, 50.0, 0.003, 30.0, 5000.0),
    Formula(1231, 0, 100, 50.0, 0.0025, 30.0, 7000.0),
    Formula(1232, 0, 300, 50.0, 0.01, 250.0, 5500.0),
    Formula(1234, 0, 75, 50.0, 0.008, 0.0, 7250.0),
    Formula(1235, 0, 100, 50.0, 0.0015, 30.0, 7000.0),
    Formula(1236, 0, 100, 50.0, 0.0025, 100.0, 778.0),
    Formula(1245, 0, 100, 50.0, 0.005792, 60.0, 4000.0),
    Formula(1260, 0, 0, 0.75, 1.25, 0.05000000074505806, 0.25),
    Formula(1261, 10_000, 250, 0.25, 1.0, 0.0, 0.0),
    Formula(1265, 0, 0, 0.25, 0.009999999776482582, 25.0, 25.0),
    Formula(1266, 0, 0, 0.25, 0.25, 0.0, 0.0),
    Formula(1271, 0, 100, 50.0, 0.0055, 75.0, 4000.0),
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
    #("datafloat04", Float(fifth_float(formula.id))),
  ])
}

/// GameFormula's datafloat04, which no planted formula reads: 0 in every row the planted
/// tables hold but the crit severity's, 1232, whose row holds 105.0.
fn fifth_float(id: Int) -> Float {
  case id {
    1232 -> 105.0
    _ -> 0.0
  }
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
  |> list.map(fn(row) {
    case row {
      [Integer(1), ..] ->
        planted_table.row(creature_level.schema, [
          #("ID", Integer(1)),
          #("unitPropertyValue00", Float(15.392292022705078)),
          #("unitPropertyValue07", Float(135.97027587890625)),
          #("unitPropertyValue35", Float(61.56916809082031)),
        ])
      _ -> row
    }
  })
  |> list.append([
    planted_table.row(creature_level.schema, [
      #("ID", Integer(101)),
      #("unitPropertyValue00", Float(1.0)),
      #("unitPropertyValue01", Float(0.05)),
      #("unitPropertyValue02", Float(0.05)),
      #("unitPropertyValue27", Float(1.5)),
    ]),
  ])
}

/// The files with the creature auto-attack's Spell4 and Spell4Effects rows added
/// (`creature_attack_spell4_rows`, `creature_attack_effect_rows`), for a load that
/// selects spawns, whose attack is their kind's spell. The attack's effect ids make
/// a Spell4Effects table of over a megabyte (a slot for each id up to 184777): the
/// shared planted load holds it, and a test's own load that selects spawns passes
/// `padding` True for one more empty row, so its table is never the same size as the
/// shared one, which the literal-area check would take for one table loaded twice
/// (`literal_area.tables_held_twice`).
pub fn with_creature_attack(
  files files: List(#(String, BitArray)),
  padding padding: Bool,
) -> List(#(String, BitArray)) {
  with_creature_attack_multiplier(
    files:,
    padding:,
    multiplier_bits: 1_065_353_216,
  )
}

/// `with_creature_attack`, with the attack effects' dataBits00 set to
/// `multiplier_bits` in place of the float 1.0's: a synthetic row, for a test of a
/// multiplier the load refuses.
pub fn with_creature_attack_multiplier(
  files files: List(#(String, BitArray)),
  padding padding: Bool,
  multiplier_bits multiplier_bits: Int,
) -> List(#(String, BitArray)) {
  let effects =
    list.flatten([
      spell4_effects_rows(),
      creature_attack_effect_rows_of(multiplier_bits:),
      case padding {
        True -> [
          planted_table.row(spell4_effects.schema, [#("ID", Integer(184_778))]),
        ]
        False -> []
      },
    ])
  list.map(files, fn(file) {
    case file.0 {
      name if name == spell4.schema.file ->
        planted_table.file(
          spell4.schema,
          list.append(creature_attack_spell4_rows(), spell4_rows())
            |> list.sort(by_id),
        )
      name if name == spell4_effects.schema.file ->
        planted_table.file(spell4_effects.schema, list.sort(effects, by_id))
      _ -> file
    }
  })
}

/// The creature auto-attack the creature kinds name, Spell4 5649 (`Spell4.5649`):
/// range 5.0, no base spell planted (no player casts it).
pub fn creature_attack_spell4_rows() -> List(List(Cell)) {
  [
    planted_table.row(spell4.schema, [
      #("ID", Integer(5649)),
      #("targetMaxRange", Float(5.0)),
    ]),
  ]
}

/// Spell 5649's two Physical damage effects on its target, the client's rows
/// (`Spell4Effects.184741`): 184741, Strength 0.55 and Assault Power 0.55, for a
/// caster of difficulty at most 6 (prerequisite 30526), and 184777, 0.8 each, for
/// difficulty at least 7 (30527); dataBits00 the float 1.0, threatMultiplier 1.0.
pub fn creature_attack_effect_rows() -> List(List(Cell)) {
  creature_attack_effect_rows_of(multiplier_bits: 1_065_353_216)
}

fn creature_attack_effect_rows_of(
  multiplier_bits multiplier_bits: Int,
) -> List(List(Cell)) {
  [#(184_741, 30_526, 0.550000011920929), #(184_777, 30_527, 0.800000011920929)]
  |> list.map(fn(effect) {
    planted_table.row(spell4_effects.schema, [
      #("ID", Integer(effect.0)),
      #("spellId", Integer(5649)),
      #("targetFlags", Integer(2)),
      #("effectType", Integer(8)),
      #("damageType", Integer(1)),
      #("flags", Integer(128)),
      #("dataBits00", Integer(multiplier_bits)),
      #("threatMultiplier", Float(1.0)),
      #("prerequisiteIdCasterApply", Integer(effect.1)),
      #("parameterType00", Integer(1)),
      #("parameterType01", Integer(12)),
      #("parameterValue00", Float(effect.2)),
      #("parameterValue01", Float(effect.2)),
      #("phaseFlags", Integer(-1)),
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

/// Paralytic Surge's Spell4AoeTargetConstraints row: 173 (`Spell4.42352.area`).
const paralytic_surge_area = 173

/// The planted Spell4Effects row of Paralytic Surge's damage: the client's row 96125
/// (Tech damage, aimed at the area, in every phase: 0.0935 Assault Power + 0.0935
/// Support Power + 8.14 per level, dataBits00 the float 1.0), the one spell the
/// loadout's tests strike with, so a bot can kill a planted creature.
pub fn spell4_effects_rows() -> List(List(Cell)) {
  [
    spell_tables.damage_effect_row(
      id: 96_125,
      spell: 42_352,
      damage_type: 2,
      target_flags: 4,
      delay: 0,
      multiplier_bits: 1_065_353_216,
      parameters: [
        #(12, 0.09350000321865082),
        #(13, 0.09350000321865082),
        #(10, 8.140000343322754),
      ],
    ),
  ]
}

/// The planted Spell4AoeTargetConstraints row 173 (`Spell4.42352.area`): 5 units, 0 to
/// 15 m, 180 degrees, Closest.
pub fn spell4_aoe_target_constraints_rows() -> List(List(Cell)) {
  [
    spell_tables.aoe_row(
      id: paralytic_surge_area,
      angle: 180.0,
      count: 5,
      max_range: 15.0,
    ),
  ]
}

/// The planted Spell4ValidTargets row 1: bitmask 0, the alive (`Spell4ValidTargets.targetBitmask`).
pub fn spell4_valid_targets_rows() -> List(List(Cell)) {
  [spell_tables.valid_targets_row(bitmask: 0)]
}

/// The planted Spell4 rows.
pub fn spell4_rows() -> List(List(Cell)) {
  list.map(spell4_ids_and_bases(), fn(pair) {
    planted_table.row(spell4.schema, [
      #("ID", Integer(pair.0)),
      #("spell4BaseIdBaseSpell", Integer(pair.1)),
      #(
        "spell4AoeTargetConstraintsId",
        Integer(case pair.0 {
          42_352 -> paralytic_surge_area
          _ -> 0
        }),
      ),
    ])
  })
}

/// The planted Spell4Base rows of the same spells: the Normal cast method and
/// nothing else, so each spell is one cast with no cost, no cooldown and no
/// child.
pub fn spell4_base_rows() -> List(List(Cell)) {
  list.map(spell4_ids_and_bases(), fn(pair) {
    planted_table.row(spell4_base.schema, [
      #("ID", Integer(pair.1)),
      #(
        "spell4ValidTargetId",
        Integer(case pair.0 {
          42_352 -> 1
          _ -> 0
        }),
      ),
    ])
  })
}

/// Every planted row holds its ID in its first cell.
fn by_id(first: List(Cell), second: List(Cell)) -> order.Order {
  let assert [Integer(first_id), ..] = first
    as "a planted row holds its ID first"
  let assert [Integer(second_id), ..] = second
    as "a planted row holds its ID first"
  int.compare(first_id, second_id)
}

/// The planted files of the spell tables with the trees of `spell_tables` (each
/// the client's own rows) in place of the plain Normal casts; Paralytic Surge,
/// 42352, stays one instant Normal cast. A table keeps a slot for each id up to
/// its highest, so the Spell4Effects file, whose rows have ids up to 196522, is
/// about 1.5 MB: only the tests that cast an ability of another method load these
/// (`character_tables.shared_with_spell_trees`), and the plain `files` stay small.
pub fn spell_tree_files() -> List(#(String, BitArray)) {
  let rows = spell_tables.rows()
  [
    planted_table.file(
      spell4.schema,
      list.append(rows.spell4, [
        planted_table.row(spell4.schema, [
          #("ID", Integer(42_352)),
          #("spell4BaseIdBaseSpell", Integer(26_543)),
        ]),
      ])
        |> list.sort(by_id),
    ),
    planted_table.file(
      spell4_base.schema,
      list.append(rows.spell4_base, [
        planted_table.row(spell4_base.schema, [#("ID", Integer(26_543))]),
      ])
        |> list.sort(by_id),
    ),
    planted_table.file(spell4_effects.schema, rows.spell4_effects),
    planted_table.file(spell4_thresholds.schema, rows.spell4_thresholds),
    planted_table.file(
      spell4_aoe_target_constraints.schema,
      rows.spell4_aoe_target_constraints,
    ),
    planted_table.file(spell4_telegraph.schema, rows.spell4_telegraph),
    planted_table.file(telegraph_damage.schema, rows.telegraph_damage),
    planted_table.file(spell_phase.schema, rows.spell_phases),
    planted_table.file(spell_cool_down.schema, rows.spell_cool_downs),
    planted_table.file(class.schema, rows.classes),
  ]
}

/// The planted files of the tables only the loadout and the spell plans read,
/// each by its file name.
pub fn files() -> List(#(String, BitArray)) {
  [
    planted_table.file(item2.schema, item2_rows()),
    planted_table.file(item2_type.schema, item2_type_rows()),
    planted_table.file(item2_family.schema, item2_family_rows()),
    planted_table.file(item2_category.schema, item2_category_rows()),
    planted_table.file(item_slot.schema, item_slot_rows()),
    planted_table.file(item_display_source_entry.schema, source_entry_rows()),
    planted_table.file(item_display.schema, item_display_rows()),
    planted_table.file(creature_level.schema, creature_level_rows()),
    planted_table.file(spell4.schema, spell4_rows()),
    planted_table.file(spell4_base.schema, spell4_base_rows()),
    planted_table.file(spell4_effects.schema, spell4_effects_rows()),
    planted_table.file(
      spell4_aoe_target_constraints.schema,
      spell4_aoe_target_constraints_rows(),
    ),
    planted_table.file(spell4_telegraph.schema, []),
    planted_table.file(telegraph_damage.schema, []),
    planted_table.file(spell4_valid_targets.schema, spell4_valid_targets_rows()),
    planted_table.file(spell4_thresholds.schema, []),
    planted_table.file(spell_phase.schema, []),
    planted_table.file(spell_cool_down.schema, []),
    planted_table.file(class.schema, []),
    planted_table.file(spell_level.schema, spell_level_rows()),
  ]
}
