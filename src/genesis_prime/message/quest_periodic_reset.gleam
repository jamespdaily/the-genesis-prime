//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0362 (quest_periodic_reset), server to client: periodic quests
//// reset: the reset time and the periods that reset (bit 1 daily, 2 weekly, 4
//// monthly, 8 yearly, the questRepeatPeriodEnum 1 to 4); a time equal to the
//// one held does nothing, a different one re-rolls the periodic quest offers
//// seeded by it and frees the done quests of the flagged periods. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x362` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0362

/// The body of message 0x0362, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestPeriodicReset {
  QuestPeriodicReset(reset_time: Int, periods: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestPeriodicReset) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("reset_time", message.reset_time, 64)
  |> bit_stream.write_unsigned("periods", message.periods, 4)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestPeriodicReset, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(reset_time, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(periods, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestPeriodicReset(reset_time:, periods:))
}
