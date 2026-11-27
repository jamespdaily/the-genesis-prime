//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0805 (client_side_interaction_result), client to server: how the
//// player's client-side interaction of a cast went: the server's cast id, the
//// result (3 when the interaction starts, then one of 1, 0 or 2), and the
//// cast's Spell4Base id plus 1; the client reads no answer. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x805` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/interaction_result.{type InteractionResult}
import gleam/result

/// The message's number.
pub const message_id = 0x0805

/// The body of message 0x0805, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ClientSideInteractionResult {
  ClientSideInteractionResult(
    cast_id: Int,
    result: InteractionResult,
    spell4_base_id_plus_one: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  message: ClientSideInteractionResult,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned(
    "result",
    interaction_result.to_value(message.result),
    3,
  )
  |> bit_stream.write_unsigned(
    "spell4_base_id_plus_one",
    message.spell4_base_id_plus_one,
    32,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(
  body: BitArray,
) -> Result(ClientSideInteractionResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  let result = interaction_result.from_value(result)
  use #(spell4_base_id_plus_one, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientSideInteractionResult(cast_id:, result:, spell4_base_id_plus_one:))
}
