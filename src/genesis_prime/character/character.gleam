//// A player's character as the server saves it, and the character a player
//// asks to create. A character belongs to one account. Its race, class,
//// gender and faction are the CharacterCreation row's it was made from, copied
//// when it is made.

import genesis_prime/map/position.{type Position}
import genesis_prime/map/unit.{type Newcomer, Newcomer}
import genesis_prime/message/character_list_entry.{
  type CharacterListEntry, CharacterListEntry,
}
import genesis_prime/message/float32
import gleam/bool

/// Where a character stands: the World row it is in, the world zone and the
/// position (the three numbers message 0x117 and message 0xAD carry).
pub type Place {
  Place(world_id: Int, world_zone_id: Int, position: Position)
}

/// What a create request carries beyond the creation row and the name: the
/// customisation the player chose, as the client sends it. The bone values are
/// the bits of 32-bit floats.
pub type Appearance {
  Appearance(
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
  )
}

/// A saved character. `id` is the 64-bit number the client's messages name it
/// by, given by the database. `gender` is the CharacterCreation row's `sex`.
pub type Character {
  Character(
    id: Int,
    account_id: Int,
    name: String,
    creation_id: Int,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    experience: Int,
    level: Int,
    path: Int,
    place: Place,
    appearance: Appearance,
    requires_rename: Bool,
    disabled: Bool,
  )
}

/// A character to save: everything of a `Character` but the id the database
/// gives it, and the flags a new character has unset.
pub type NewCharacter {
  NewCharacter(
    account_id: Int,
    name: String,
    creation_id: Int,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    experience: Int,
    level: Int,
    path: Int,
    place: Place,
    appearance: Appearance,
  )
}

/// The character as one entry of the character list (message 0x117), with no
/// item visuals, no last logout time and the fields whose meaning the client's
/// code does not show set to 0.
pub fn list_entry(character character: Character) -> CharacterListEntry {
  CharacterListEntry(
    character_id: character.id,
    name: character.name,
    gender: character.gender,
    race_id: character.race_id,
    class_id: character.class_id,
    faction_id: character.faction_id,
    level: character.level,
    body_visuals: [],
    worn_visuals: [],
    world_id: character.place.world_id,
    world_zone_id: character.place.world_zone_id,
    field_12: 0,
    position_x: float32.to_bits(character.place.position.x),
    position_y: float32.to_bits(character.place.position.y),
    position_z: float32.to_bits(character.place.position.z),
    field_16: 0,
    field_17: 0,
    path: character.path,
    disabled: bit(character.disabled),
    requires_rename: bit(character.requires_rename),
    field_21: 0,
    customisation_labels: character.appearance.customisation_labels,
    customisation_values: character.appearance.customisation_values,
    bone_values: character.appearance.bone_values,
    last_logged_out_days: 0,
  )
}

/// A flag as the single bit the client's list holds.
fn bit(flag: Bool) -> Int {
  use <- bool.guard(when: flag, return: 1)
  0
}

/// The character as it joins a map: the facts observers need to create its
/// unit, and where it stands.
pub fn newcomer(character character: Character) -> Newcomer {
  Newcomer(
    character_id: character.id,
    name: character.name,
    race_id: character.race_id,
    class_id: character.class_id,
    gender: character.gender,
    path: character.path,
    position: character.place.position,
  )
}
