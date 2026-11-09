//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0919 (currency_changed), server to client: a currency's new total
//// (a total, not a change): the kind, 0 to 13 for the currency types 1 to 14
//// (credits are kind 0; the client logs and drops the kinds 14 to 21, and the
//// kinds 22 and up are not currencies), the total and two 32-bit values the
//// currency kinds do not read. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x919` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0919

/// The body of message 0x0919, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CurrencyChanged {
  CurrencyChanged(
    kind: Int,
    total: Int,
    /// Safe by `opcode.0x919`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_3: Int,
    /// Safe by `opcode.0x919`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CurrencyChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("kind", message.kind, 5)
  |> bit_stream.write_unsigned("total", message.total, 64)
  |> bit_stream.write_unsigned("field_3", message.field_3, 32)
  |> bit_stream.write_unsigned("field_4", message.field_4, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CurrencyChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(total, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CurrencyChanged(kind:, total:, field_3:, field_4:))
}
