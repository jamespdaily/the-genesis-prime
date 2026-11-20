//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 6, the unit
//// moves along a chain of authored splines (the taxi flight path): the spline
//// ids (32 bits each, a count in 10 bits), the speed as a 16-bit half float,
//// the start position along the chain as a 32-bit float, the takeoff height
//// and the landing height as 32-bit floats, an offset of three 16-bit half
//// floats, a 4-bit walk mode, a 32-bit time offset in ms, 32 bits of chain
//// flags, the blend bit and one bit the client reads and never uses. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind6 {
  MovementKind6(
    spline_ids: List(Int),
    speed: Int,
    start_position: Int,
    takeoff_height: Int,
    landing_height: Int,
    offset_x: Int,
    offset_y: Int,
    offset_z: Int,
    mode: Int,
    time_offset: Int,
    chain_flags: Int,
    blends: Int,
    unread_14: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind6) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 6, 5)
  |> bit_stream.write_unsigned_array("spline_ids", record.spline_ids, 10, 32)
  |> bit_stream.write_unsigned("speed", record.speed, 16)
  |> bit_stream.write_float32_bits("start_position", record.start_position)
  |> bit_stream.write_float32_bits("takeoff_height", record.takeoff_height)
  |> bit_stream.write_float32_bits("landing_height", record.landing_height)
  |> bit_stream.write_unsigned("offset_x", record.offset_x, 16)
  |> bit_stream.write_unsigned("offset_y", record.offset_y, 16)
  |> bit_stream.write_unsigned("offset_z", record.offset_z, 16)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("chain_flags", record.chain_flags, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
  |> bit_stream.write_unsigned("unread_14", record.unread_14, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind6, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 6))
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
  use #(offset_x, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(offset_y, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(offset_z, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(mode, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(chain_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(unread_14, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind6(
      spline_ids:,
      speed:,
      start_position:,
      takeoff_height:,
      landing_height:,
      offset_x:,
      offset_y:,
      offset_z:,
      mode:,
      time_offset:,
      chain_flags:,
      blends:,
      unread_14:,
    ),
    reader,
  ))
}
