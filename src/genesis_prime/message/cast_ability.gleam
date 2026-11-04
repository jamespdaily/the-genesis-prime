//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x009A (cast_ability), client to server: the client casts the spell
//// of an ability bag slot: its own id for the cast, the bag index the
//// ability's item was added at (message 0x111 with location 4), the target
//// unit id (0 for none) and a bit that is 1 for a press and 0 only under a
//// console setting; a cast placed on the ground is message 0x9b, which the
//// schema does not hold. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x9a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x009A

/// The body of message 0x009A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CastAbility {
  CastAbility(
    client_cast_id: Int,
    bag_index: Int,
    target_unit_id: Int,
    press: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CastAbility) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> bit_stream.write_unsigned("bag_index", message.bag_index, 16)
  |> bit_stream.write_unsigned("target_unit_id", message.target_unit_id, 32)
  |> bit_stream.write_unsigned("press", message.press, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CastAbility, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(press, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CastAbility(client_cast_id:, bag_index:, target_unit_id:, press:))
}
