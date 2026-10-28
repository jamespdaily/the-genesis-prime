//// A value wider than its field, or a list that its message cannot count, is
//// refused when the message is encoded, whichever message it is in. The client's
//// own writers mask a wide value to the field's low bits
//// (vector.0x140336380.fields `(0xFF, 4)` -> `0f`), so a value that does not fit
//// is a mistake the server would otherwise hide. The widths are each field's in
//// the schema.

import genesis_prime/message/bit_stream
import genesis_prime/message/character_list_entry.{CharacterListEntry}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import owned_test

pub fn a_create_character_path_wider_than_3_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let request =
    CreateCharacter(
      creation_id: 7,
      name: "Ab Cd",
      path: 3,
      customisation_labels: [],
      customisation_values: [],
      bone_values: [],
    )
  assert create_character.encode(CreateCharacter(..request, path: 8))
    == Error(bit_stream.ValueDoesNotFit("path", 3, 8))
    as "WriteMessage025BBody 0x14007EB30: the path is 3 bits"
  assert create_character.encode(
      CreateCharacter(..request, creation_id: 0x1_0000_0000),
    )
    == Error(bit_stream.ValueDoesNotFit("creation_id", 32, 0x1_0000_0000))
    as "WriteMessage025BBody 0x14007EB30: the creation id is 32 bits"
}

pub fn a_create_character_with_values_for_other_labels_than_it_has_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let request =
    CreateCharacter(
      creation_id: 7,
      name: "Ab Cd",
      path: 0,
      customisation_labels: [1, 2],
      customisation_values: [3],
      bone_values: [],
    )
  assert create_character.encode(request)
    == Error(bit_stream.ItemCountDisagrees("customisation_values", 2, 1))
    as "opcode.0x25b: one value for each label, as the client's writer writes them"
}

pub fn a_character_with_16_customisations_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let sixteen = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let entry =
    CharacterListEntry(
      character_id: 1,
      name: "Ab Cd",
      gender: 0,
      race_id: 1,
      class_id: 1,
      faction_id: 166,
      level: 1,
      body_visuals: [],
      worn_visuals: [],
      world_id: 1,
      world_zone_id: 1,
      field_12: 0,
      position_x: 0,
      position_y: 0,
      position_z: 0,
      field_16: 0,
      field_17: 0,
      path: 0,
      disabled: 0,
      requires_rename: 0,
      costume_slot_mask: 0,
      costume_item_ids: sixteen,
      costume_dyes: sixteen,
      bone_values: [],
      last_logged_out_days: 0,
    )
  assert bit_stream.new_writer()
    |> character_list_entry.write(entry)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("costume_item_ids", 4, 16))
    as "ReadCharacterListEntry 0x14007F720: a character's customisation count is 4 bits, so 15 at most"
}

pub fn an_item_visual_slot_wider_than_7_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let visual =
    ItemVisual(slot: 128, display_id: 0, item_color_set_id: 0, dye: 0)
  assert bit_stream.new_writer()
    |> item_visual.write(visual)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("slot", 7, 128))
    as "ReadItemVisual 0x1400AB890: the slot is 7 bits"
}

pub fn a_result_wider_than_6_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert create_character_result.encode(CreateCharacterResult(
      character_id: 1,
      field_2: 0,
      result: 64,
    ))
    == Error(bit_stream.ValueDoesNotFit("result", 6, 64))
    as "ReadMessage00DCBody 0x14007FD50: the result is 6 bits"
}

pub fn a_terrain_loaded_value_wider_than_15_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert terrain_loaded.encode(TerrainLoaded(field_1: 0x8000))
    == Error(bit_stream.ValueDoesNotFit("field_1", 15, 0x8000))
    as "vector.opcode.0xf2.body: the client writes the low 15 bits of its value (0xFFFF1234 as 0x1234); the server refuses a value that does not fit rather than mask it"
}

pub fn a_destroyed_unit_flag_wider_than_one_bit_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert unit_destroyed.encode(UnitDestroyed(unit_id: 1, field_2: 2))
    == Error(bit_stream.ValueDoesNotFit("field_2", 1, 2))
    as "ReadUint32AndBitBody 0x14007C340: one bit"
}
