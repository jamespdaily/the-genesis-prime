//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00D5 (world_entry_options), client to server: the client's
//// world-entry options, which it sends once after it applies 0xF1: its input
//// flags (4 bits), whether its combat log hides other players (1 bit) and the
//// kinds of combat log entry it hides (14 bits of flags). Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xd5` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00D5

/// The body of message 0x00D5, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WorldEntryOptions {
  WorldEntryOptions(
    input_flags: Int,
    combat_log_hides_other_players: Int,
    combat_log_hidden_kinds: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WorldEntryOptions) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("input_flags", message.input_flags, 4)
  |> bit_stream.write_unsigned(
    "combat_log_hides_other_players",
    message.combat_log_hides_other_players,
    1,
  )
  |> bit_stream.write_unsigned(
    "combat_log_hidden_kinds",
    message.combat_log_hidden_kinds,
    14,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: WorldEntryOptions) -> BitArray {
  bit_stream.must(encode(message), "world_entry_options")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WorldEntryOptions, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(input_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(combat_log_hides_other_players, reader) <- result.try(
    bit_stream.read_unsigned(reader, 1),
  )
  use #(combat_log_hidden_kinds, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WorldEntryOptions(
    input_flags:,
    combat_log_hides_other_players:,
    combat_log_hidden_kinds:,
  ))
}
