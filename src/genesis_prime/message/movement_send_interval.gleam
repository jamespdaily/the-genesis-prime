//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00F1 (movement_send_interval), server to client: sets the
//// interval at which the client sends the player's movement commands. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0xf1` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00F1

/// The body of message 0x00F1, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type MovementSendInterval {
  MovementSendInterval(
    world_difficulty: Int,
    world_prime_level: Int,
    world_flags: Int,
    interval_milliseconds: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: MovementSendInterval) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("world_difficulty", message.world_difficulty, 2)
  |> bit_stream.write_unsigned(
    "world_prime_level",
    message.world_prime_level,
    32,
  )
  |> bit_stream.write_unsigned("world_flags", message.world_flags, 8)
  |> bit_stream.write_unsigned(
    "interval_milliseconds",
    message.interval_milliseconds,
    32,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(MovementSendInterval, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(world_difficulty, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    2,
  ))
  use #(world_prime_level, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(world_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(interval_milliseconds, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(MovementSendInterval(
    world_difficulty:,
    world_prime_level:,
    world_flags:,
    interval_milliseconds:,
  ))
}
