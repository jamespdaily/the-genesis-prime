//// The four messages of 0x0262 each read as themselves through the server's
//// message reader, which tries the messages that share the number in turn.
//// Expected values come from these places.
//// - The 6 bits after the 32-bit unit id are the unit type, which decides what
////   the rest of the body is (0x140096fa0; opcode.0x262): 20 a player, 0 a
////   creature, 10, 11 and 32 a static object, 23 a ghost.
//// - The bodies are the vectors of `character_message_vector_test` (the player,
////   vector.opcode.0x262.player) and of `combat_message_vector_test` (the
////   creature, the static objects of types 10, 11 and 32, and the ghost), each
////   checked there against its schema layout.

import genesis_prime/message/server_message
import genesis_prime/message/static_unit_type
import gleam/list
import message_support
import owned_test

const player_body =
  "0110000014c2814101c180404026a010042006000230044006104418171615141312110121000000044700640015706e6c6a686664628220000080458501800012000000000000400300005003d800370000003838383838383838d3d2d2d2d2d2d2d2ca046208000080088022c008c01100"

const creature_body =
  "01 10 00 00 00 be 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00"

const static_10_body =
  "01 20 00 00 ca fa 47 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00"

const static_11_body =
  "02 20 00 00 cb 5c 46 04 00 41 11 00 00 00 00 00 00 00 20 04 00 e0 c0 30 00 b4 16 31 00 b0 e9 10 07 00 00 fc 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 b4 10 2d 00 00 00 00 00 00 00 00 00 00 00 00 50 e2 59 d1 48 a4 0d 00 00 8d 14 00 00 00 00 00 00 00 40 f1 19 15 00"

const static_32_body =
  "03 20 00 00 20 c7 47 00 00 02 a0 1b 00 00 a0 18 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 10 70 00 00 d0 3d 04 00 d0 3d 04 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00"

const ghost_body =
  "02 10 00 00 17 c2 81 41 01 c1 80 40 40 26 a0 10 04 20 06 00 02 30 04 40 06 30 44 18 17 16 15 14 13 12 11 04 47 00 64 00 15 50 4e 4c 4a 48 46 44 42 02 9a 19 99 98 aa 00 00 00 00 00 00 08 01 00 38 30 0c 00 ad 45 0c 00 6c 3a c4 01 00 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 38 05 4e 01 00 00 00 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00"

/// The name of the message the server's reader makes of a body of 0x0262.
fn read_as(hex: String) -> String {
  let assert Ok(message) =
    server_message.decode(0x0262, message_support.hex(hex))
    as "the body of 0x0262 reads as one of its messages"
  server_message.name(message)
}

pub fn a_player_reads_as_a_player_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_as(player_body) == "unit_create_player"
}

pub fn a_creature_reads_as_a_creature_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_as(creature_body) == "unit_create_creature"
}

pub fn a_ghost_reads_as_a_ghost_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_as(ghost_body) == "unit_create_ghost"
}

pub fn a_static_object_of_each_of_its_three_types_reads_as_a_static_object_test() -> Nil {
  use <- owned_test.run(5000)
  let types =
    [static_10_body, static_11_body, static_32_body]
    |> list.map(fn(hex) {
      let assert Ok(server_message.UnitCreateStatic(message:)) =
        server_message.decode(0x0262, message_support.hex(hex))
        as "the body reads as a static object"
      message.unit_type
    })
  assert types
    == [
      static_unit_type.Simple,
      static_unit_type.Platform,
      static_unit_type.SimpleCollidable,
    ]
    as "types 10, 11 and 32"
}
