//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00FB (impact_severity), client to server: one float the client
//// sends after a flush of its movement, when the impact severity its movement
//// physics has added up for the player is above 0: a unitless measure of how
//// hard the player hit something, not a height. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `opcode.0xfb`
//// names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00FB

/// The body of message 0x00FB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ImpactSeverity {
  ImpactSeverity(impact_severity: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ImpactSeverity) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_float32_bits("impact_severity", message.impact_severity)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: ImpactSeverity) -> BitArray {
  bit_stream.must(encode(message), "impact_severity")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ImpactSeverity, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(impact_severity, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ImpactSeverity(impact_severity:))
}
