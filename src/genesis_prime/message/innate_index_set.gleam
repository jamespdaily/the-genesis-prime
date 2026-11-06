//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x019F (innate_index_set), server to client: the player's current
//// innate: the index of its Class innate slot, which the client takes when it
//// is below its unlocked count and its slot holds an active spell, pointing
//// the innate button at that spell; until one arrives the client's index is 4,
//// which names no slot. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x19f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x019F

/// The body of message 0x019F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type InnateIndexSet {
  InnateIndexSet(innate_index: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: InnateIndexSet) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("innate_index", message.innate_index, 2)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(InnateIndexSet, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(innate_index, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(InnateIndexSet(innate_index:))
}
