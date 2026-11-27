//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x016F (innate_index_chosen), client to server: the player switches
//// to an innate: the Class slot, 0 to 2, which the client has already switched
//// its own index and button to; the client never sends the index it already
//// holds. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x16f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x016F

/// The body of message 0x016F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type InnateIndexChosen {
  InnateIndexChosen(innate_index: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: InnateIndexChosen) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("innate_index", message.innate_index, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(InnateIndexChosen, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(innate_index, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(InnateIndexChosen(innate_index:))
}
