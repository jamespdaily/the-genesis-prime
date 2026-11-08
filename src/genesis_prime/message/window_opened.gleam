//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x023D (window_opened), client to server: the client says a UI
//// window was opened (telemetry): the window id, the character id, the time it
//// was open, three more 64-bit values and the window name; nothing the player
//// sees depends on it. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x23d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x023D

/// The body of message 0x023D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WindowOpened {
  WindowOpened(
    field_1: Int,
    window_id: Int,
    character_id: Int,
    field_4: Int,
    open_time: Int,
    field_6: Int,
    field_7: Int,
    field_8: Int,
    window_name: List(Int),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WindowOpened) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 6)
  |> bit_stream.write_unsigned("window_id", message.window_id, 10)
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_unsigned("field_4", message.field_4, 64)
  |> bit_stream.write_unsigned("open_time", message.open_time, 64)
  |> bit_stream.write_unsigned("field_6", message.field_6, 64)
  |> bit_stream.write_unsigned("field_7", message.field_7, 64)
  |> bit_stream.write_unsigned("field_8", message.field_8, 64)
  |> bit_stream.write_wide_units("window_name", message.window_name)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WindowOpened, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use #(window_id, reader) <- result.try(bit_stream.read_unsigned(reader, 10))
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(open_time, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(window_name, reader) <- result.try(bit_stream.read_wide_units(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WindowOpened(
    field_1:,
    window_id:,
    character_id:,
    field_4:,
    open_time:,
    field_6:,
    field_7:,
    field_8:,
    window_name:,
  ))
}
