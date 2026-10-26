//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00F2 (terrain_loaded), client to server: sent once while the
//// world loads, when the terrain near the player is ready and the world has
//// had message 0xF1. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xf2` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00F2

/// The body of message 0x00F2, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type TerrainLoaded {
  TerrainLoaded(field_1: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: TerrainLoaded) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(TerrainLoaded, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(TerrainLoaded(field_1:))
}
