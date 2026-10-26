//// decode(encode(message)) is the message, for random values within each
//// field's width, 1,000 cases for each Milestone 1 message. The widths are the
//// ones in the schema, which cites the client's reader or writer of each
//// field; a counted text is at most 250 characters (opcode.0x592), a realm
//// list holds up to a few realms and groups of a few texts, and a whole inner
//// frame is its 32-bit length counting itself and then that many bytes less 4.
//// A counted text draws up to 120 characters, so up to 240 UTF-16 units.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/character_select_start.{CharacterSelectStart}
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/close_notice.{CloseNotice}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/ping.{Ping}
import genesis_prime/message/pong.{Pong}
import genesis_prime/message/realm_entry.{type RealmEntry, RealmEntry}
import genesis_prime/message/realm_handoff.{RealmHandoff}
import genesis_prime/message/realm_list.{RealmList}
import genesis_prime/message/realm_select_start.{RealmSelectStart}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/text_group.{type TextGroup, TextGroup}
import genesis_prime/message/world_message.{WorldMessage}
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

pub fn server_hello_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x3",
    seed: 20_261_101,
    draw: fn(state) {
      let #(build, state) = message_support.unsigned(state:, bits: 32)
      let #(field_2, state) = message_support.unsigned(state:, bits: 32)
      let #(field_3, state) = message_support.unsigned(state:, bits: 32)
      let #(field_4, state) = message_support.unsigned(state:, bits: 32)
      let #(field_5, state) = message_support.unsigned(state:, bits: 64)
      let #(field_6, state) = message_support.unsigned(state:, bits: 16)
      let #(field_7, state) = message_support.unsigned(state:, bits: 5)
      let #(message_table_checksum, state) =
        message_support.unsigned(state:, bits: 32)
      let #(field_9, state) = message_support.unsigned(state:, bits: 32)
      let #(field_10, state) = message_support.unsigned(state:, bits: 64)
      let #(field_11, state) = message_support.unsigned(state:, bits: 32)
      #(
        ServerHello(
          build:,
          field_2:,
          field_3:,
          field_4:,
          field_5:,
          field_6:,
          field_7:,
          message_table_checksum:,
          field_9:,
          field_10:,
          field_11:,
        ),
        state,
      )
    },
    encode: server_hello.encode,
    decode: server_hello.decode,
  )
}

pub fn login_request_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x592",
    seed: 20_261_102,
    draw: fn(state) {
      let #(build, state) = message_support.unsigned(state:, bits: 32)
      let #(files_digest, state) = message_support.unsigned(state:, bits: 64)
      let #(account_name, state) = message_support.text(state:, longest: 120)
      let #(field_4, state) = message_support.guid(state:)
      let #(field_5, state) = message_support.guid(state:)
      let #(field_6, state) = message_support.unsigned(state:, bits: 32)
      let #(field_7, state) = message_support.unsigned(state:, bits: 32)
      let #(field_8, state) = message_support.unsigned(state:, bits: 32)
      let #(field_9, state) = message_support.unsigned(state:, bits: 32)
      let #(processor_manufacturer, state) = message_support.field_text(state:)
      let #(processor_name, state) = message_support.field_text(state:)
      let #(processor_description, state) = message_support.field_text(state:)
      let #(processor_family, state) =
        message_support.unsigned(state:, bits: 32)
      let #(processor_level, state) = message_support.unsigned(state:, bits: 32)
      let #(processor_revision, state) =
        message_support.unsigned(state:, bits: 32)
      let #(processor_clock_speed, state) =
        message_support.unsigned(state:, bits: 32)
      let #(processor_core_count, state) =
        message_support.unsigned(state:, bits: 32)
      let #(memory_mebibytes, state) =
        message_support.unsigned(state:, bits: 32)
      let #(video_adapter_description, state) =
        message_support.field_text(state:)
      let #(video_adapter_vendor_id, state) =
        message_support.unsigned(state:, bits: 32)
      let #(video_adapter_device_id, state) =
        message_support.unsigned(state:, bits: 32)
      let #(video_adapter_subsystem_id, state) =
        message_support.unsigned(state:, bits: 32)
      let #(video_adapter_revision, state) =
        message_support.unsigned(state:, bits: 32)
      let #(video_adapter_memory_mebibytes, state) =
        message_support.unsigned(state:, bits: 32)
      let #(processor_architecture, state) =
        message_support.unsigned(state:, bits: 32)
      let #(windows_version, state) = message_support.unsigned(state:, bits: 32)
      let #(service_pack, state) = message_support.unsigned(state:, bits: 32)
      let #(os_flags, state) = message_support.unsigned(state:, bits: 32)
      let #(realm_data_center_id, state) =
        message_support.unsigned(state:, bits: 32)
      #(
        LoginRequest(
          build:,
          files_digest:,
          account_name:,
          field_4:,
          field_5:,
          field_6:,
          field_7:,
          field_8:,
          field_9:,
          processor_manufacturer:,
          processor_name:,
          processor_description:,
          processor_family:,
          processor_level:,
          processor_revision:,
          processor_clock_speed:,
          processor_core_count:,
          memory_mebibytes:,
          video_adapter_description:,
          video_adapter_vendor_id:,
          video_adapter_device_id:,
          video_adapter_subsystem_id:,
          video_adapter_revision:,
          video_adapter_memory_mebibytes:,
          processor_architecture:,
          windows_version:,
          service_pack:,
          os_flags:,
          realm_data_center_id:,
        ),
        state,
      )
    },
    encode: login_request.encode,
    decode: login_request.decode,
  )
}

pub fn login_accepted_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x591",
    seed: 20_261_103,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 32)
      #(LoginAccepted(field_1:), state)
    },
    encode: login_accepted.encode,
    decode: login_accepted.decode,
  )
}

pub fn game_server_handoff_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x3db",
    seed: 20_261_104,
    draw: fn(state) {
      let #(game_server, state) = message_support.endpoint(state:)
      let #(session_key, state) = message_support.guid(state:)
      let #(field_3, state) = message_support.unsigned(state:, bits: 32)
      let #(realm_name, state) = message_support.field_text(state:)
      let #(field_5, state) = message_support.unsigned(state:, bits: 32)
      let #(field_6, state) = message_support.unsigned(state:, bits: 2)
      let #(field_7, state) = message_support.unsigned(state:, bits: 21)
      #(
        GameServerHandoff(
          game_server:,
          session_key:,
          field_3:,
          realm_name:,
          field_5:,
          field_6:,
          field_7:,
        ),
        state,
      )
    },
    encode: game_server_handoff.encode,
    decode: game_server_handoff.decode,
  )
}

pub fn game_hello_reply_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x58f",
    seed: 20_261_105,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 32)
      let #(session_key, state) = message_support.guid(state:)
      let #(field_3, state) = message_support.unsigned(state:, bits: 64)
      let #(account_name, state) = message_support.field_text(state:)
      let #(field_5, state) = message_support.unsigned(state:, bits: 32)
      #(
        GameHelloReply(
          field_1:,
          session_key:,
          field_3:,
          account_name:,
          field_5:,
        ),
        state,
      )
    },
    encode: game_hello_reply.encode,
    decode: game_hello_reply.decode,
  )
}

pub fn character_select_start_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x7e0",
    seed: 20_261_106,
    draw: fn(state) { #(CharacterSelectStart, state) },
    encode: character_select_start.encode,
    decode: character_select_start.decode,
  )
}

pub fn enter_world_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0xad",
    seed: 20_261_107,
    draw: fn(state) {
      let #(world_id, state) = message_support.unsigned(state:, bits: 15)
      let #(position_x, state) = message_support.unsigned(state:, bits: 32)
      let #(position_y, state) = message_support.unsigned(state:, bits: 32)
      let #(position_z, state) = message_support.unsigned(state:, bits: 32)
      let #(field_5, state) = message_support.unsigned(state:, bits: 32)
      let #(field_6, state) = message_support.unsigned(state:, bits: 32)
      #(
        EnterWorld(
          world_id:,
          position_x:,
          position_y:,
          position_z:,
          field_5:,
          field_6:,
        ),
        state,
      )
    },
    encode: enter_world.encode,
    decode: enter_world.decode,
  )
}

pub fn realm_select_start_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x7a4",
    seed: 20_261_108,
    draw: fn(state) { #(RealmSelectStart, state) },
    encode: realm_select_start.encode,
    decode: realm_select_start.decode,
  )
}

fn realm_entry(state: Int) -> #(RealmEntry, Int) {
  let #(realm_id, state) = message_support.unsigned(state:, bits: 32)
  let #(name, state) = message_support.field_text(state:)
  let #(note_text_id, state) = message_support.unsigned(state:, bits: 32)
  let #(flags, state) = message_support.unsigned(state:, bits: 32)
  let #(pvp_type, state) = message_support.unsigned(state:, bits: 2)
  let #(status, state) = message_support.unsigned(state:, bits: 3)
  let #(population, state) = message_support.unsigned(state:, bits: 3)
  let #(field_8, state) = message_support.unsigned(state:, bits: 32)
  let #(field_9, state) = message_support.bytes(state:, count: 16)
  let #(field_10, state) = message_support.unsigned(state:, bits: 14)
  let #(count, state) = message_support.unsigned(state:, bits: 32)
  let #(last_played, state) = message_support.field_text(state:)
  let #(field_13, state) = message_support.unsigned(state:, bits: 64)
  let #(field_14, state) = message_support.unsigned(state:, bits: 16)
  let #(field_15, state) = message_support.unsigned(state:, bits: 16)
  let #(field_16, state) = message_support.unsigned(state:, bits: 16)
  let #(field_17, state) = message_support.unsigned(state:, bits: 16)
  #(
    RealmEntry(
      realm_id:,
      name:,
      note_text_id:,
      flags:,
      pvp_type:,
      status:,
      population:,
      field_8:,
      field_9:,
      field_10:,
      count:,
      last_played:,
      field_13:,
      field_14:,
      field_15:,
      field_16:,
      field_17:,
    ),
    state,
  )
}

fn text_group(state: Int) -> #(TextGroup, Int) {
  let #(field_1, state) = message_support.unsigned(state:, bits: 32)
  let #(count, state) = message_support.up_to(state:, most: 6)
  let #(texts, state) =
    message_support.draw_list(state:, count:, draw: fn(state) {
      message_support.field_text(state:)
    })
  #(TextGroup(field_1:, texts:), state)
}

pub fn realm_list_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x761",
    seed: 20_261_109,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 64)
      let #(realm_count, state) = message_support.up_to(state:, most: 5)
      let #(realms, state) =
        message_support.draw_list(state:, count: realm_count, draw: realm_entry)
      let #(group_count, state) = message_support.up_to(state:, most: 4)
      let #(text_groups, state) =
        message_support.draw_list(state:, count: group_count, draw: text_group)
      #(RealmList(field_1:, realms:, text_groups:), state)
    },
    encode: realm_list.encode,
    decode: realm_list.decode,
  )
}

pub fn realm_handoff_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x7a1",
    seed: 20_261_110,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 32)
      let #(session_key, state) = message_support.guid(state:)
      let #(realm_server, state) = message_support.endpoint(state:)
      let #(field_4, state) = message_support.unsigned(state:, bits: 1)
      let #(realm_name, state) = message_support.field_text(state:)
      let #(field_6, state) = message_support.unsigned(state:, bits: 32)
      let #(field_7, state) = message_support.unsigned(state:, bits: 2)
      let #(field_8, state) = message_support.unsigned(state:, bits: 21)
      #(
        RealmHandoff(
          field_1:,
          session_key:,
          realm_server:,
          field_4:,
          realm_name:,
          field_6:,
          field_7:,
          field_8:,
        ),
        state,
      )
    },
    encode: realm_handoff.encode,
    decode: realm_handoff.decode,
  )
}

pub fn movement_send_interval_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0xf1",
    seed: 20_261_111,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 2)
      let #(field_2, state) = message_support.unsigned(state:, bits: 32)
      let #(field_3, state) = message_support.unsigned(state:, bits: 8)
      let #(interval_milliseconds, state) =
        message_support.unsigned(state:, bits: 32)
      #(
        MovementSendInterval(
          field_1:,
          field_2:,
          field_3:,
          interval_milliseconds:,
        ),
        state,
      )
    },
    encode: movement_send_interval.encode,
    decode: movement_send_interval.decode,
  )
}

pub fn client_wrapper_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x244",
    seed: 20_261_112,
    draw: fn(state) {
      let #(inner_frame, state) = message_support.frame(state:)
      #(ClientWrapper(inner_frame:), state)
    },
    encode: client_wrapper.encode,
    decode: client_wrapper.decode,
  )
}

pub fn world_message_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x38c",
    seed: 20_261_113,
    draw: fn(state) {
      let #(field_1, state) = message_support.unsigned(state:, bits: 5)
      let #(inner_frame, state) = message_support.frame(state:)
      #(WorldMessage(field_1:, inner_frame:), state)
    },
    encode: world_message.encode,
    decode: world_message.decode,
  )
}

pub fn ping_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x0",
    seed: 20_261_114,
    draw: fn(state) {
      let #(sequence_number, state) = message_support.up_to(state:, most: 19)
      #(Ping(sequence_number:), state)
    },
    encode: ping.encode,
    decode: ping.decode,
  )
}

pub fn pong_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x1",
    seed: 20_261_115,
    draw: fn(state) {
      let #(sequence_number, state) = message_support.unsigned(state:, bits: 8)
      #(Pong(sequence_number:), state)
    },
    encode: pong.encode,
    decode: pong.decode,
  )
}

pub fn close_notice_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  round_trips(
    name: "message 0x2",
    seed: 20_261_116,
    draw: fn(state) { #(CloseNotice, state) },
    encode: close_notice.encode,
    decode: close_notice.decode,
  )
}
