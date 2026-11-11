//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00DD (currency_gained), server to client: a gain of a currency,
//// for the chat line "You receive X" and the loot window's recent gains (it
//// changes no total; 0x0919 sets that): the currency type id (1 for credits,
//// never 0), the amount gained (read signed; 0 or less does nothing) and the
//// part of the amount that came from Signature (above 0 shows "from Signature"
//// in the line). Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xdd` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00DD

/// The body of message 0x00DD, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CurrencyGained {
  CurrencyGained(currency_type_id: Int, amount: Int, signature_amount: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CurrencyGained) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("currency_type_id", message.currency_type_id, 4)
  |> bit_stream.write_unsigned("amount", message.amount, 64)
  |> bit_stream.write_unsigned("signature_amount", message.signature_amount, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CurrencyGained, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(currency_type_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    4,
  ))
  use #(amount, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(signature_amount, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CurrencyGained(currency_type_id:, amount:, signature_amount:))
}
