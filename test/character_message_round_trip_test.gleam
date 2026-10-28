//// decode(encode(message)) is the message, for random values within each
//// field's width, 1,000 cases for each message of character select and entering
//// the world. The widths are the ones in the schema, which cites the client's
//// reader or writer of each field. A list is up to a few items long, a count
//// is as wide as the schema's, and a list with no count of its own is as long
//// as the list that counts it.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{
  type CharacterListEntry, CharacterListEntry,
}
import genesis_prime/message/choose_realm.{ChooseRealm}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_carrier.{CreateCharacterCarrier}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat, UnitStat}
import gleam/int
import message_support
import owned_test

const cases = 1000

fn round_trips(
  name name: String,
  seed seed: Int,
  draw draw: fn(Int) -> #(a, Int),
  encode encode: fn(a) -> Result(BitArray, EncodeError),
  decode decode: fn(BitArray) -> Result(a, DecodeError),
) -> Nil {
  let checked =
    int.range(from: 0, to: cases, with: #(seed, 0), run: fn(state, number) {
      let #(random, checked) = state
      let #(message, random) = draw(random)
      let assert Ok(bytes) = encode(message)
        as {
          name
          <> " case "
          <> int.to_string(number)
          <> ": every field is within its width, so the message encodes"
        }
      assert decode(bytes) == Ok(message)
        as {
          name
          <> " case "
          <> int.to_string(number)
          <> ": the bytes decode to the message encoded"
        }
      assert encode(message) == Ok(bytes)
        as {
          name
          <> " case "
          <> int.to_string(number)
          <> ": encoding is repeatable"
        }
      #(random, checked + 1)
    })
  assert checked.1 == cases as "every generated case was checked"
}

fn unsigned_list(
  state state: Int,
  most most: Int,
  bits bits: Int,
) -> #(List(Int), Int) {
  let #(count, state) = message_support.up_to(state:, most:)
  message_support.draw_list(state:, count:, draw: fn(state) {
    message_support.unsigned(state:, bits:)
  })
}

fn item_visual(state: Int) -> #(ItemVisual, Int) {
  let #(slot, state) = message_support.unsigned(state:, bits: 7)
  let #(display_id, state) = message_support.unsigned(state:, bits: 15)
  let #(item_color_set_id, state) = message_support.unsigned(state:, bits: 14)
  let #(dye, state) = message_support.unsigned(state:, bits: 32)
  #(ItemVisual(slot:, display_id:, item_color_set_id:, dye:), state)
}

fn item_visuals(state: Int) -> #(List(ItemVisual), Int) {
  let #(count, state) = message_support.up_to(state:, most: 4)
  message_support.draw_list(state:, count:, draw: item_visual)
}

fn unit_stat(state: Int) -> #(UnitStat, Int) {
  let #(stat_id, state) = message_support.unsigned(state:, bits: 5)
  let #(value, state) = message_support.unsigned(state:, bits: 32)
  #(UnitStat(stat_id:, value:), state)
}

fn unit_stats(state: Int) -> #(List(UnitStat), Int) {
  let #(count, state) = message_support.up_to(state:, most: 4)
  message_support.draw_list(state:, count:, draw: unit_stat)
}

fn unit_position_command(state: Int) -> #(UnitPositionCommand, Int) {
  let #(x, state) = message_support.unsigned(state:, bits: 32)
  let #(y, state) = message_support.unsigned(state:, bits: 32)
  let #(z, state) = message_support.unsigned(state:, bits: 32)
  let #(blends, state) = message_support.unsigned(state:, bits: 1)
  #(UnitPositionCommand(x:, y:, z:, blends:), state)
}

fn unit_position_commands(state: Int) -> #(List(UnitPositionCommand), Int) {
  let #(count, state) = message_support.up_to(state:, most: 4)
  message_support.draw_list(state:, count:, draw: unit_position_command)
}

fn unit_property(state: Int) -> #(UnitProperty, Int) {
  let #(property_id, state) = message_support.unsigned(state:, bits: 8)
  let #(field_2, state) = message_support.unsigned(state:, bits: 32)
  let #(value, state) = message_support.unsigned(state:, bits: 32)
  #(UnitProperty(property_id:, field_2:, value:), state)
}

fn unit_properties(state: Int) -> #(List(UnitProperty), Int) {
  let #(count, state) = message_support.up_to(state:, most: 4)
  message_support.draw_list(state:, count:, draw: unit_property)
}

fn character_list_entry(state: Int) -> #(CharacterListEntry, Int) {
  let #(character_id, state) = message_support.unsigned(state:, bits: 64)
  let #(name, state) = message_support.field_text(state:)
  let #(gender, state) = message_support.unsigned(state:, bits: 2)
  let #(race_id, state) = message_support.unsigned(state:, bits: 5)
  let #(class_id, state) = message_support.unsigned(state:, bits: 5)
  let #(faction_id, state) = message_support.unsigned(state:, bits: 32)
  let #(level, state) = message_support.unsigned(state:, bits: 32)
  let #(body_visuals, state) = item_visuals(state)
  let #(worn_visuals, state) = item_visuals(state)
  let #(world_id, state) = message_support.unsigned(state:, bits: 15)
  let #(world_zone_id, state) = message_support.unsigned(state:, bits: 15)
  let #(field_12, state) = message_support.unsigned(state:, bits: 14)
  let #(position_x, state) = message_support.unsigned(state:, bits: 32)
  let #(position_y, state) = message_support.unsigned(state:, bits: 32)
  let #(position_z, state) = message_support.unsigned(state:, bits: 32)
  let #(field_16, state) = message_support.unsigned(state:, bits: 32)
  let #(field_17, state) = message_support.unsigned(state:, bits: 32)
  let #(path, state) = message_support.unsigned(state:, bits: 3)
  let #(disabled, state) = message_support.unsigned(state:, bits: 1)
  let #(requires_rename, state) = message_support.unsigned(state:, bits: 1)
  let #(costume_slot_mask, state) = message_support.unsigned(state:, bits: 32)
  let #(count, state) = message_support.up_to(state:, most: 15)
  let #(costume_item_ids, state) =
    message_support.draw_list(state:, count:, draw: fn(state) {
      message_support.unsigned(state:, bits: 32)
    })
  let #(costume_dyes, state) =
    message_support.draw_list(state:, count:, draw: fn(state) {
      message_support.unsigned(state:, bits: 32)
    })
  let #(bone_values, state) = unsigned_list(state:, most: 5, bits: 32)
  let #(last_logged_out_days, state) =
    message_support.unsigned(state:, bits: 32)
  #(
    CharacterListEntry(
      character_id:,
      name:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      level:,
      body_visuals:,
      worn_visuals:,
      world_id:,
      world_zone_id:,
      field_12:,
      position_x:,
      position_y:,
      position_z:,
      field_16:,
      field_17:,
      path:,
      disabled:,
      requires_rename:,
      costume_slot_mask:,
      costume_item_ids:,
      costume_dyes:,
      bone_values:,
      last_logged_out_days:,
    ),
    state,
  )
}

pub fn character_list_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x117",
    seed: 20_261_201,
    draw: fn(state) {
      let #(server_time, state) = message_support.unsigned(state:, bits: 64)
      let #(count, state) = message_support.up_to(state:, most: 3)
      let #(characters, state) =
        message_support.draw_list(state:, count:, draw: character_list_entry)
      let #(enabled_creation_ids, state) =
        unsigned_list(state:, most: 4, bits: 32)
      let #(disabled_creation_ids, state) =
        unsigned_list(state:, most: 4, bits: 32)
      let #(realm_id, state) = message_support.unsigned(state:, bits: 14)
      let #(pending_removal_realm_id, state) =
        message_support.unsigned(state:, bits: 14)
      let #(pending_removal_character_id, state) =
        message_support.unsigned(state:, bits: 64)
      let #(pending_removal_time, state) =
        message_support.unsigned(state:, bits: 32)
      let #(reservations, state) = message_support.unsigned(state:, bits: 32)
      let #(max_characters, state) = message_support.unsigned(state:, bits: 32)
      let #(field_11, state) = message_support.unsigned(state:, bits: 32)
      let #(faction_restriction, state) =
        message_support.unsigned(state:, bits: 14)
      let #(free_level_50_available, state) =
        message_support.unsigned(state:, bits: 1)
      #(
        CharacterList(
          server_time:,
          characters:,
          enabled_creation_ids:,
          disabled_creation_ids:,
          realm_id:,
          pending_removal_realm_id:,
          pending_removal_character_id:,
          pending_removal_time:,
          reservations:,
          max_characters:,
          field_11:,
          faction_restriction:,
          free_level_50_available:,
        ),
        state,
      )
    },
    encode: character_list.encode,
    decode: character_list.decode,
  )
}

pub fn create_character_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x25b",
    seed: 20_261_202,
    draw: fn(state) {
      let #(creation_id, state) = message_support.unsigned(state:, bits: 32)
      let #(name, state) = message_support.field_text(state:)
      let #(path, state) = message_support.unsigned(state:, bits: 3)
      let #(count, state) = message_support.up_to(state:, most: 20)
      let #(customisation_labels, state) =
        message_support.draw_list(state:, count:, draw: fn(state) {
          message_support.unsigned(state:, bits: 32)
        })
      let #(customisation_values, state) =
        message_support.draw_list(state:, count:, draw: fn(state) {
          message_support.unsigned(state:, bits: 32)
        })
      let #(bone_values, state) = unsigned_list(state:, most: 8, bits: 32)
      #(
        CreateCharacter(
          creation_id:,
          name:,
          path:,
          customisation_labels:,
          customisation_values:,
          bone_values:,
        ),
        state,
      )
    },
    encode: create_character.encode,
    decode: create_character.decode,
  )
}

pub fn create_character_carrier_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x25c",
    seed: 20_261_203,
    draw: fn(state) {
      let #(inner_frame, state) = message_support.frame(state:)
      #(CreateCharacterCarrier(inner_frame:), state)
    },
    encode: create_character_carrier.encode,
    decode: create_character_carrier.decode,
  )
}

pub fn create_character_result_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0xdc",
    seed: 20_261_204,
    draw: fn(state) {
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      let #(field_2, state) = message_support.unsigned(state:, bits: 32)
      let #(result, state) = message_support.unsigned(state:, bits: 6)
      #(CreateCharacterResult(character_id:, field_2:, result:), state)
    },
    encode: create_character_result.encode,
    decode: create_character_result.decode,
  )
}

pub fn play_character_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x7dd",
    seed: 20_261_205,
    draw: fn(state) {
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      #(PlayCharacter(character_id:), state)
    },
    encode: play_character.encode,
    decode: play_character.decode,
  )
}

pub fn play_character_refused_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x162",
    seed: 20_261_206,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 3)
      #(PlayCharacterRefused(field_1:), state)
    },
    encode: play_character_refused.encode,
    decode: play_character_refused.decode,
  )
}

pub fn delete_character_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x352",
    seed: 20_261_207,
    draw: fn(state) {
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      #(DeleteCharacter(character_id:), state)
    },
    encode: delete_character.encode,
    decode: delete_character.decode,
  )
}

pub fn delete_character_result_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0xe6",
    seed: 20_261_208,
    draw: fn(state) {
      let #(result, state) = message_support.unsigned(state:, bits: 6)
      let #(field_2, state) = message_support.unsigned(state:, bits: 32)
      #(DeleteCharacterResult(result:, field_2:), state)
    },
    encode: delete_character_result.encode,
    decode: delete_character_result.decode,
  )
}

pub fn rename_character_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x786",
    seed: 20_261_209,
    draw: fn(state) {
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      let #(name, state) = message_support.field_text(state:)
      #(RenameCharacter(character_id:, name:), state)
    },
    encode: rename_character.encode,
    decode: rename_character.decode,
  )
}

pub fn rename_character_result_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x14b",
    seed: 20_261_210,
    draw: fn(state) {
      let #(result, state) = message_support.unsigned(state:, bits: 6)
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      let #(name, state) = message_support.field_text(state:)
      #(RenameCharacterResult(result:, character_id:, name:), state)
    },
    encode: rename_character_result.encode,
    decode: rename_character_result.decode,
  )
}

pub fn max_character_level_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x36",
    seed: 20_261_211,
    draw: fn(state) {
      let #(highest_level, state) = message_support.unsigned(state:, bits: 32)
      #(MaxCharacterLevel(highest_level:), state)
    },
    encode: max_character_level.encode,
    decode: max_character_level.decode,
  )
}

pub fn disconnect_notice_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x36a",
    seed: 20_261_212,
    draw: fn(state) {
      let #(reason, state) = message_support.unsigned(state:, bits: 5)
      #(DisconnectNotice(reason:), state)
    },
    encode: disconnect_notice.encode,
    decode: disconnect_notice.decode,
  )
}

pub fn choose_realm_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x7df",
    seed: 20_261_213,
    draw: fn(state) {
      let #(realm_id, state) = message_support.unsigned(state:, bits: 32)
      #(ChooseRealm(realm_id:), state)
    },
    encode: choose_realm.encode,
    decode: choose_realm.decode,
  )
}

pub fn unit_create_player_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x262",
    seed: 20_261_214,
    draw: fn(state) {
      let #(unit_id, state) = message_support.unsigned(state:, bits: 32)
      let #(character_id, state) = message_support.unsigned(state:, bits: 64)
      let #(realm_id, state) = message_support.unsigned(state:, bits: 14)
      let #(name, state) = message_support.field_text(state:)
      let #(race_id, state) = message_support.unsigned(state:, bits: 5)
      let #(class_id, state) = message_support.unsigned(state:, bits: 5)
      let #(gender, state) = message_support.unsigned(state:, bits: 2)
      let #(field_9, state) = message_support.unsigned(state:, bits: 64)
      let #(field_10, state) = unsigned_list(state:, most: 4, bits: 32)
      let #(field_11, state) = message_support.field_text(state:)
      let #(field_12, state) = message_support.unsigned(state:, bits: 4)
      let #(field_13, state) = unsigned_list(state:, most: 4, bits: 64)
      let #(field_14, state) = unsigned_list(state:, most: 4, bits: 32)
      let #(path, state) = message_support.unsigned(state:, bits: 3)
      let #(field_16, state) = message_support.unsigned(state:, bits: 8)
      let #(field_17, state) = message_support.unsigned(state:, bits: 14)
      let #(field_18, state) = message_support.unsigned(state:, bits: 8)
      let #(stats, state) = unit_stats(state)
      let #(server_time_estimate_start, state) =
        message_support.unsigned(state:, bits: 32)
      let #(movement_commands, state) = unit_position_commands(state)
      let #(properties, state) = unit_properties(state)
      let #(item_visuals, state) = item_visuals(state)
      let #(field_25, state) = message_support.unsigned(state:, bits: 32)
      let #(faction_id, state) = message_support.unsigned(state:, bits: 14)
      let #(base_faction_id, state) = message_support.unsigned(state:, bits: 14)
      let #(field_28, state) = message_support.unsigned(state:, bits: 32)
      let #(field_29, state) = message_support.unsigned(state:, bits: 64)
      let #(field_31, state) = message_support.unsigned(state:, bits: 1)
      let #(field_33, state) = message_support.unsigned(state:, bits: 64)
      let #(field_34, state) = message_support.unsigned(state:, bits: 14)
      let #(field_36, state) = message_support.unsigned(state:, bits: 32)
      let #(field_37, state) = message_support.unsigned(state:, bits: 18)
      let #(field_38, state) = message_support.unsigned(state:, bits: 14)
      let #(field_39, state) = message_support.unsigned(state:, bits: 17)
      let #(field_40, state) = message_support.unsigned(state:, bits: 15)
      #(
        UnitCreatePlayer(
          unit_id:,
          character_id:,
          realm_id:,
          name:,
          race_id:,
          class_id:,
          gender:,
          field_9:,
          field_10:,
          field_11:,
          field_12:,
          field_13:,
          field_14:,
          path:,
          field_16:,
          field_17:,
          field_18:,
          stats:,
          server_time_estimate_start:,
          movement_commands:,
          properties:,
          item_visuals:,
          field_25:,
          faction_id:,
          base_faction_id:,
          field_28:,
          field_29:,
          field_31:,
          field_33:,
          field_34:,
          field_36:,
          field_37:,
          field_38:,
          field_39:,
          field_40:,
        ),
        state,
      )
    },
    encode: unit_create_player.encode,
    decode: unit_create_player.decode,
  )
}

pub fn client_control_granted_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x636",
    seed: 20_261_401,
    draw: fn(state) {
      let #(echo_value, state) = message_support.unsigned(state:, bits: 32)
      let #(reset_movement, state) = message_support.unsigned(state:, bits: 1)
      let #(unit_id, state) = message_support.unsigned(state:, bits: 32)
      #(ClientControlGranted(echo_value:, reset_movement:, unit_id:), state)
    },
    encode: client_control_granted.encode,
    decode: client_control_granted.decode,
  )
}

pub fn client_control_echoed_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x635",
    seed: 20_261_402,
    draw: fn(state) {
      let #(echo_value, state) = message_support.unsigned(state:, bits: 32)
      #(ClientControlEchoed(echo_value:), state)
    },
    encode: client_control_echoed.encode,
    decode: client_control_echoed.decode,
  )
}

pub fn unit_is_player_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x19b",
    seed: 20_261_215,
    draw: fn(state) {
      let #(unit_id, state) = message_support.unsigned(state:, bits: 32)
      let #(field_2, state) = message_support.unsigned(state:, bits: 32)
      #(UnitIsPlayer(unit_id:, field_2:), state)
    },
    encode: unit_is_player.encode,
    decode: unit_is_player.decode,
  )
}

pub fn terrain_loaded_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0xf2",
    seed: 20_261_216,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 15)
      #(TerrainLoaded(field_1:), state)
    },
    encode: terrain_loaded.encode,
    decode: terrain_loaded.decode,
  )
}

pub fn player_entered_world_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x61",
    seed: 20_261_217,
    draw: fn(state) { #(PlayerEnteredWorld, state) },
    encode: player_entered_world.encode,
    decode: player_entered_world.decode,
  )
}

pub fn unit_destroyed_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x355",
    seed: 20_261_218,
    draw: fn(state) {
      let #(unit_id, state) = message_support.unsigned(state:, bits: 32)
      let #(field_2, state) = message_support.unsigned(state:, bits: 1)
      #(UnitDestroyed(unit_id:, field_2:), state)
    },
    encode: unit_destroyed.encode,
    decode: unit_destroyed.decode,
  )
}
