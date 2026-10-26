//// A saved character as the messages show it: one entry of the character list
//// (message 0x117) and the facts a map needs to create its unit. Each field is
//// the character's own as ReadCharacterListEntry 0x14007F720 names it
//// (opcode.0x117); the fields whose meaning the client's code does not show
//// are 0, and the list carries no item visuals and no last logout time.

import character_support
import genesis_prime/character/character.{Appearance, Character}
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{Newcomer}
import genesis_prime/message/character_list_entry.{CharacterListEntry}
import owned_test

pub fn a_character_is_listed_with_its_own_name_race_class_gender_faction_and_level_test() -> Nil {
  use <- owned_test.run(5000)
  let saved =
    Character(
      ..character_support.character(id: 0x0102030405060708, name: "Ab Cd"),
      requires_rename: True,
      disabled: True,
    )
  assert character.list_entry(saved)
    == CharacterListEntry(
      character_id: 0x0102030405060708,
      name: "Ab Cd",
      gender: 1,
      race_id: 1,
      class_id: 3,
      faction_id: 167,
      level: 3,
      body_visuals: [],
      worn_visuals: [],
      world_id: 51,
      world_zone_id: 9,
      field_12: 0,
      position_x: 0x3F800000,
      position_y: 0xC0200000,
      position_z: 0x42C88000,
      field_16: 0,
      field_17: 0,
      path: 2,
      disabled: 1,
      requires_rename: 1,
      field_21: 0,
      customisation_labels: [1, 2],
      customisation_values: [3, 4],
      bone_values: [0x3F800000, 0xBF000000],
      last_logged_out_days: 0,
    )
    as "opcode.0x117 and ReadCharacterListEntry 0x14007F720: id, name, gender, race, class, faction, level, world, zone, the position's three floats (1.0, -2.5 and 100.25 are 0x3F800000, 0xC0200000 and 0x42C88000, vector.opcode.0xad.body), path, the disabled and rename bits, the labels and values and the bones"
}

pub fn a_character_with_no_flags_lists_both_bits_as_0_test() -> Nil {
  use <- owned_test.run(5000)
  let entry =
    character.list_entry(character_support.character(id: 5, name: "Ab Cd"))
  assert entry.disabled == 0 && entry.requires_rename == 0
    as "opcode.0x117: bDisabled and bRequiresRename are single bits, clear for a character that is neither"
}

pub fn a_character_joins_a_map_with_what_its_observers_need_test() -> Nil {
  use <- owned_test.run(5000)
  let saved =
    Character(
      ..character_support.character(id: 0x0102030405060708, name: "Ab Cd"),
      appearance: Appearance([], [], []),
    )
  assert character.newcomer(saved)
    == Newcomer(
      character_id: 0x0102030405060708,
      name: "Ab Cd",
      race_id: 1,
      class_id: 3,
      gender: 1,
      path: 2,
      faction_id: 167,
      position: Position(x: 1.0, y: -2.5, z: 100.25),
    )
    as "opcode.0x262 and ReadUnitCreatePlayerData 0x1400962D0: a player's unit carries the character id, name, race, class, gender and path"
}
