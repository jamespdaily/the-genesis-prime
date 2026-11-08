//// The Novice sets the loadout equips (`genesis_prime/game/loadout`): the twelve
//// CharacterCreation rows of the PreTutorial start, each with its items, and what
//// each set wears.

import fixture_tables
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import gleam/int
import gleam/list

/// A Novice set: its CharacterCreation row, its class and faction, its race and
/// sex, its seven items (the five armor pieces, the shield and the weapon), and
/// the weapon.
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

/// The twelve sets, with the items in the order of the row's item columns
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

// The bag index of an item type is the lowest bit of the equipped slot flags of
// its ItemSlot (`ItemSlot.equippedSlotFlags`, GetSlot 0x140418a50), which the
// client's own map from a bag index back to its ItemSlot agrees with
// (0x140c39050).

/// The bag index a Novice item of this Item2Type is equipped at. Chest types 15,
/// 8 and 1 are 0; legs 16, 9 and 2 are 1; shoulder 18, 11 and 4 are 3; feet 19,
/// 12 and 5 are 4; hands 20, 13 and 6 are 5; the shield type 53 is 15 and the
/// weapon types are 16.
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
/// order: the five armor pieces, the shield and the weapon. The bag index is of
/// the Item2Type the client's Item2 row of the item holds.
pub fn equipped_of(set set: Set) -> List(#(Int, Int)) {
  list.map(set.items, fn(item_id) {
    let assert Ok(item) =
      item2.get(tables: fixture_tables.shared(), id: Item2Id(item_id))
      as "the client's Item2 holds each item of a set"
    #(item_id, bag_index_of(type_id: item.item2_type_id))
  })
  |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
}

/// The ItemSlot ids of a set's visuals in the order the loadout lists them:
/// chest, legs, shoulder, feet, hands and the weapon.
pub const worn_slots = [1, 2, 4, 5, 6, 20]

/// The displays of a class's set of a faction, in the order of `worn_slots`:
/// Warrior and Engineer wear heavy armor, Medic and Stalker medium, Esper and
/// Spellslinger light, and each class its own weapon. They are the displays of
/// the ItemDisplaySourceEntry rows of itemSourceId 75 for faction 167 and 76 for
/// faction 166.
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

/// The slot and display of each visual a class's set of a faction wears.
pub fn worn_visuals(
  class_id class_id: Int,
  faction_id faction_id: Int,
) -> List(#(Int, Int)) {
  list.zip(worn_slots, worn_displays(class_id:, faction_id:))
}
