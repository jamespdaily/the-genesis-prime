//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0092 (camp_countdown), server to client: starts the client's camp
//// with a countdown in milliseconds, or cancels it; the signature bonuses the
//// exit window shows are sent as 0 until the server has a source for them. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x92` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0092

/// The body of message 0x0092, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CampCountdown {
  CampCountdown(
    countdown_ms: Int,
    cancel: Int,
    experience: Int,
    elder_points: Int,
    currencies: BitArray,
    account_currencies: BitArray,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CampCountdown) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("countdown_ms", message.countdown_ms, 32)
  |> bit_stream.write_unsigned("cancel", message.cancel, 1)
  |> bit_stream.write_unsigned("experience", message.experience, 32)
  |> bit_stream.write_unsigned("elder_points", message.elder_points, 32)
  |> bit_stream.write_raw_bytes("currencies", message.currencies, 120)
  |> bit_stream.write_raw_bytes(
    "account_currencies",
    message.account_currencies,
    152,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CampCountdown, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(countdown_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(cancel, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(experience, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(elder_points, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(currencies, reader) <- result.try(bit_stream.read_raw_bytes(reader, 120))
  use #(account_currencies, reader) <- result.try(bit_stream.read_raw_bytes(
    reader,
    152,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CampCountdown(
    countdown_ms:,
    cancel:,
    experience:,
    elder_points:,
    currencies:,
    account_currencies:,
  ))
}
