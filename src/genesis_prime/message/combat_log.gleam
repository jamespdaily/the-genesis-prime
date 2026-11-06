//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0247 (combat_log), server to client: a combat log entry: the type
//// in 6 bits picks the entry's layout, and the client's reader fails a type
//// above 35; the schema holds types 1 (crowd-control state), 2 (state break),
//// 22 (death), 23 (resurrect) and 24 (stealth), and a spell hit's line is made
//// by the client from its damage description. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x247` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/combat_log_entry.{type CombatLogEntry}
import gleam/result

/// The message's number.
pub const message_id = 0x0247

/// The body of message 0x0247, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CombatLog {
  CombatLog(entry: CombatLogEntry)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CombatLog) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> combat_log_entry.write(message.entry)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CombatLog, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(entry, reader) <- result.try(combat_log_entry.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CombatLog(entry:))
}
