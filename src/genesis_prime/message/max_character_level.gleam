//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0036 (max_character_level), server to client: the highest
//// character level the account has reached, which the client keeps in
//// character select. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x36` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0036

/// The body of message 0x0036, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type MaxCharacterLevel {
  MaxCharacterLevel(highest_level: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: MaxCharacterLevel) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("highest_level", message.highest_level, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(MaxCharacterLevel, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(highest_level, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(MaxCharacterLevel(highest_level:))
}
