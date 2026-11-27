//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x06BC (player_path), server to client: gives the client the
//// player's path, its experience on each of the four paths, the unlocked paths
//// and the days since the last path change, after message 0x19B has set the
//// player. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x6bc` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x06BC

/// The body of message 0x06BC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayerPath {
  PlayerPath(
    path: Int,
    soldier_experience: Int,
    settler_experience: Int,
    scientist_experience: Int,
    explorer_experience: Int,
    unlocked_paths: Int,
    last_path_change_days: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayerPath) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("path", message.path, 3)
  |> bit_stream.write_unsigned(
    "soldier_experience",
    message.soldier_experience,
    32,
  )
  |> bit_stream.write_unsigned(
    "settler_experience",
    message.settler_experience,
    32,
  )
  |> bit_stream.write_unsigned(
    "scientist_experience",
    message.scientist_experience,
    32,
  )
  |> bit_stream.write_unsigned(
    "explorer_experience",
    message.explorer_experience,
    32,
  )
  |> bit_stream.write_unsigned("unlocked_paths", message.unlocked_paths, 4)
  |> bit_stream.write_float32_bits(
    "last_path_change_days",
    message.last_path_change_days,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayerPath, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(path, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(soldier_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(settler_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(scientist_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(explorer_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(unlocked_paths, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    4,
  ))
  use #(last_path_change_days, reader) <- result.try(
    bit_stream.read_float32_bits(reader),
  )
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayerPath(
    path:,
    soldier_experience:,
    settler_experience:,
    scientist_experience:,
    explorer_experience:,
    unlocked_paths:,
    last_path_change_days:,
  ))
}
