//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x023E (graphics_report), client to server: the client's graphics
//// statistics (telemetry): four averaged frame values then four raw values,
//// sent about once per eight frames while the world is shown. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x23e` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x023E

/// The body of message 0x023E, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type GraphicsReport {
  GraphicsReport(
    average_1: Int,
    average_2: Int,
    average_3: Int,
    average_4: Int,
    raw_1: Int,
    raw_2: Int,
    raw_3: Int,
    raw_4: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GraphicsReport) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_float32_bits("average_1", message.average_1)
  |> bit_stream.write_float32_bits("average_2", message.average_2)
  |> bit_stream.write_float32_bits("average_3", message.average_3)
  |> bit_stream.write_float32_bits("average_4", message.average_4)
  |> bit_stream.write_float32_bits("raw_1", message.raw_1)
  |> bit_stream.write_float32_bits("raw_2", message.raw_2)
  |> bit_stream.write_float32_bits("raw_3", message.raw_3)
  |> bit_stream.write_float32_bits("raw_4", message.raw_4)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GraphicsReport, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(average_1, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(average_2, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(average_3, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(average_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(raw_1, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(raw_2, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(raw_3, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(raw_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(GraphicsReport(
    average_1:,
    average_2:,
    average_3:,
    average_4:,
    raw_1:,
    raw_2:,
    raw_3:,
    raw_4:,
  ))
}
