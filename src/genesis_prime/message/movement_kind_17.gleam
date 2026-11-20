//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 17, the unit's
//// rotation follows a chain of authored splines: the spline ids (32 bits each,
//// a count in 10 bits), the speed as a 16-bit half float, the start position
//// along the chain, the takeoff height and the landing height as 32-bit
//// floats, a 4-bit walk mode, a 32-bit time offset in ms, 32 bits of chain
//// flags and the blend bit. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind17 {
  MovementKind17(
    spline_ids: List(Int),
    speed: Int,
    start_position: Int,
    takeoff_height: Int,
    landing_height: Int,
    mode: Int,
    time_offset: Int,
    chain_flags: Int,
    blends: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind17) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 17, 5)
  |> bit_stream.write_unsigned_array("spline_ids", record.spline_ids, 10, 32)
  |> bit_stream.write_unsigned("speed", record.speed, 16)
  |> bit_stream.write_float32_bits("start_position", record.start_position)
  |> bit_stream.write_float32_bits("takeoff_height", record.takeoff_height)
  |> bit_stream.write_float32_bits("landing_height", record.landing_height)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("chain_flags", record.chain_flags, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind17, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 17))
  use #(spline_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    10,
    32,
  ))
  use #(speed, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(start_position, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(takeoff_height, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(landing_height, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(mode, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(chain_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind17(
      spline_ids:,
      speed:,
      start_position:,
      takeoff_height:,
      landing_height:,
      mode:,
      time_offset:,
      chain_flags:,
      blends:,
    ),
    reader,
  ))
}
