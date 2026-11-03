//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0968 (account_entitlements), server to client: the entitlements
//// the account holds, each with its count; character select adds the
//// BaseCharacterSlots (12) count to its slots. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x968` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/held_entitlement.{type HeldEntitlement}
import gleam/result

/// The message's number.
pub const message_id = 0x0968

/// The body of message 0x0968, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type AccountEntitlements {
  AccountEntitlements(entitlements: List(HeldEntitlement))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: AccountEntitlements) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_array(
    "entitlements",
    message.entitlements,
    32,
    held_entitlement.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(AccountEntitlements, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(entitlements, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    held_entitlement.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(AccountEntitlements(entitlements:))
}
