//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x023F (network_report), client to server: the client's report to
//// the world server of its network statistics (telemetry): the mean round-trip
//// time in milliseconds, the bytes received and sent per minute, and the known
//// unit count times 2 plus a flag bit; nothing the player sees depends on it.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x23f.body` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x023F

/// The body of message 0x023F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type NetworkReport {
  NetworkReport(
    mean_round_trip_ms: Int,
    bytes_received_per_minute: Int,
    bytes_sent_per_minute: Int,
    known_unit_count: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: NetworkReport) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "mean_round_trip_ms",
    message.mean_round_trip_ms,
    32,
  )
  |> bit_stream.write_unsigned(
    "bytes_received_per_minute",
    message.bytes_received_per_minute,
    32,
  )
  |> bit_stream.write_unsigned(
    "bytes_sent_per_minute",
    message.bytes_sent_per_minute,
    32,
  )
  |> bit_stream.write_unsigned("known_unit_count", message.known_unit_count, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(NetworkReport, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(mean_round_trip_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(bytes_received_per_minute, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(bytes_sent_per_minute, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(known_unit_count, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(NetworkReport(
    mean_round_trip_ms:,
    bytes_received_per_minute:,
    bytes_sent_per_minute:,
    known_unit_count:,
  ))
}
