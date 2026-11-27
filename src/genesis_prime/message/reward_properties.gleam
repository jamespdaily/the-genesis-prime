//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x092C (reward_properties), server to client: the player's reward
//// properties, each with its data and value: the client keeps them in a map by
//// property and data, and equipping a bag reads BagSlots (26) and BankSlots
//// (13) from it. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x92c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/reward_property_entry.{type RewardPropertyEntry}
import gleam/result

/// The message's number.
pub const message_id = 0x092C

/// The body of message 0x092C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type RewardProperties {
  RewardProperties(properties: List(RewardPropertyEntry))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: RewardProperties) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_array(
    "properties",
    message.properties,
    8,
    reward_property_entry.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RewardProperties, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(properties, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    reward_property_entry.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(RewardProperties(properties:))
}
