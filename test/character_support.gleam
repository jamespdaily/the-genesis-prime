//// Characters, creation rows and contexts for the tests of character select
//// and entering the world. The values are planted; what a test asserts about
//// them cites the client's record that gives the rule.

import genesis_prime/character/character.{
  type Character, Appearance, Character, Place,
}
import genesis_prime/character/customisation.{Customisation}
import genesis_prime/character/select
import genesis_prime/map/position.{Position}
import genesis_prime/table/character_creation.{type CharacterCreation}
import gleam/dict
import gleam/list

/// The account the characters belong to unless a test says another.
pub const account_id = 7

/// A character of the account at a place in world 51.
pub fn character(id id: Int, name name: String) -> Character {
  Character(
    id:,
    account_id:,
    name:,
    creation_id: 277,
    gender: 1,
    race_id: 1,
    class_id: 3,
    faction_id: 167,
    experience: 1710,
    level: 3,
    path: 2,
    place: Place(
      world_id: 51,
      world_zone_id: 9,
      position: Position(x: 1.0, y: -2.5, z: 100.25),
    ),
    appearance: Appearance(
      customisation_labels: [1, 2],
      customisation_values: [3, 4],
      bone_values: [0x3F800000, 0xBF000000],
    ),
    requires_rename: False,
    disabled: False,
  )
}

/// A CharacterCreation row a character can be made from: enabled, needing no
/// entitlement and costing nothing.
pub fn creation_row() -> CharacterCreation {
  character_creation.CharacterCreation(
    id: 277,
    class_id: 3,
    race_id: 1,
    sex: 1,
    faction_id: 167,
    costume_only: False,
    item_id0: 0,
    item_id01: 0,
    item_id02: 0,
    item_id03: 0,
    item_id04: 0,
    item_id05: 0,
    item_id06: 0,
    item_id07: 0,
    item_id08: 0,
    item_id09: 0,
    item_id010: 0,
    item_id011: 0,
    item_id012: 0,
    item_id013: 0,
    item_id014: 0,
    item_id015: 0,
    enabled: True,
    character_creation_start_enum: 1,
    xp: 1710,
    account_currency_type_id_cost: 0,
    account_currency_amount_cost: 0,
    entitlement_id_required: 0,
  )
}

/// The place a character made from a row starts at in these tests.
pub fn start_place() -> character.Place {
  Place(
    world_id: 51,
    world_zone_id: 9,
    position: Position(x: 1.0, y: -2.5, z: 100.25),
  )
}

/// The server's time in these tests, as a Windows FILETIME.
pub const server_time = 0x01D9F00000000000

/// The realm the connection is on in these tests.
pub const realm_id = 0x99

/// A context whose table holds the given rows, whose experience gives level 3
/// from 1710 and level 50 above 26,360,090 (XpPerLevel rows 3 and 50: 1710
/// and 26360090 minimum experience), and that has a starting place for every
/// row.
pub fn context(rows rows: List(CharacterCreation)) -> select.Context {
  select.Context(
    creation: fn(id) { list.find(rows, fn(row) { row.id == id }) },
    start: fn(_row) { Ok(start_place()) },
    customisation: customisation(),
    character_slots: 100,
    level_of: fn(experience) {
      case experience >= 26_360_090 {
        True -> 50
        False -> 3
      }
    },
    server_time:,
    realm_id:,
  )
}

/// What the planted tables say a request may carry: the planted CharacterCreation
/// row's race 1 and sex 1 have 2 bone values, labels 1 and 2 are for no faction,
/// label 3 is for faction 166 and label 4 for faction 167 (the planted row's),
/// and a request holds at most 27 labels and 48 bone values.
pub fn customisation() -> customisation.Customisation {
  Customisation(
    bone_counts: dict.from_list([#(#(1, 1), 2)]),
    label_factions: dict.from_list([#(1, 0), #(2, 0), #(3, 166), #(4, 167)]),
    most_bones: 48,
    most_labels: 27,
  )
}
