//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x063B (move_speed_setting), client to server: the player's
//// movement speed setting, 0 to 2, which the client sends after 0xF1 and on
//// each change of the setting. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x63b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x063B

/// The body of message 0x063B, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type MoveSpeedSetting {
  MoveSpeedSetting(move_speed: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: MoveSpeedSetting) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("move_speed", message.move_speed, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(MoveSpeedSetting, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(move_speed, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(MoveSpeedSetting(move_speed:))
}
