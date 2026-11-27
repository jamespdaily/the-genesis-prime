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
    integrity_key: Int,
    keyed_player_unit_checksum: Int,
    longest_clock_step_ms: Int,
    clock_fit_intercept: Int,
    clock_fit_slope_ms: Int,
    clock_fit_residual: Int,
    keyed_movement_sum: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WatchdogReport) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("integrity_key", message.integrity_key, 64)
  |> bit_stream.write_unsigned(
    "keyed_player_unit_checksum",
    message.keyed_player_unit_checksum,
    64,
  )
  |> bit_stream.write_unsigned(
    "longest_clock_step_ms",
    message.longest_clock_step_ms,
    32,
  )
  |> bit_stream.write_float32_bits(
    "clock_fit_intercept",
    message.clock_fit_intercept,
  )
  |> bit_stream.write_float32_bits(
    "clock_fit_slope_ms",
    message.clock_fit_slope_ms,
  )
  |> bit_stream.write_float32_bits(
    "clock_fit_residual",
    message.clock_fit_residual,
  )
  |> bit_stream.write_unsigned(
    "keyed_movement_sum",
    message.keyed_movement_sum,
    32,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: WatchdogReport) -> BitArray {
  bit_stream.must(encode(message), "watchdog_report")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WatchdogReport, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(integrity_key, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(keyed_player_unit_checksum, reader) <- result.try(
    bit_stream.read_unsigned(reader, 64),
  )
  use #(longest_clock_step_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(clock_fit_intercept, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(clock_fit_slope_ms, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(clock_fit_residual, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(keyed_movement_sum, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WatchdogReport(
    integrity_key:,
    keyed_player_unit_checksum:,
    longest_clock_step_ms:,
    clock_fit_intercept:,
    clock_fit_slope_ms:,
    clock_fit_residual:,
    keyed_movement_sum:,
  ))
}
