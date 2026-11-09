//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x023C (watchdog_report), client to server: the client's report to
//// the world server of its own integrity watchdog (telemetry): two 64-bit
//// values, a 32-bit signed integer, three floats and a 32-bit value; nothing
//// the player sees depends on it. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x23c.body` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x023C

/// The body of message 0x023C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WatchdogReport {
  WatchdogReport(
    field_1: Int,
    field_2: Int,
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
    field_7: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WatchdogReport) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 64)
  |> bit_stream.write_unsigned("field_2", message.field_2, 64)
  |> bit_stream.write_unsigned("field_3", message.field_3, 32)
  |> bit_stream.write_float32_bits("field_4", message.field_4)
  |> bit_stream.write_float32_bits("field_5", message.field_5)
  |> bit_stream.write_float32_bits("field_6", message.field_6)
  |> bit_stream.write_unsigned("field_7", message.field_7, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WatchdogReport, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WatchdogReport(
    field_1:,
    field_2:,
    field_3:,
    field_4:,
    field_5:,
    field_6:,
    field_7:,
  ))
}
