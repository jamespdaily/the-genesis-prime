//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x097F (premium_tier), server to client: the account's premium
//// tier, which the client keeps as the tier AccountItemLib.GetPremiumTier
//// gives from then on; sent before the entitlements, since 0x968 refreshes the
//// tier and an unset one drops from 255 to 0 (Basic). Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x97f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x097F

/// The body of message 0x097F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PremiumTier {
  PremiumTier(tier: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PremiumTier) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("tier", message.tier, 5)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PremiumTier, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(tier, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PremiumTier(tier:))
}
