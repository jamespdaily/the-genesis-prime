//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x023D (statistic_event), client to server: the client's statistics
//// event (telemetry): an event category (35 from every sender), an event id
//// (the store's events, a window's time open, the interface reloaded), six
//// 64-bit values (the first is the sender's character id; the second and sixth
//// are 0; the third to fifth depend on the event) and the event's text;
//// nothing the player sees depends on it. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x23d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x023D

/// The body of message 0x023D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type StatisticEvent {
  StatisticEvent(
    category: Int,
    event_id: Int,
    character_id: Int,
    zero_value_2: Int,
    event_value_3: Int,
    event_value_4: Int,
    event_value_5: Int,
    zero_value_6: Int,
    event_text: List(Int),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: StatisticEvent) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("category", message.category, 6)
  |> bit_stream.write_unsigned("event_id", message.event_id, 10)
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_unsigned("zero_value_2", message.zero_value_2, 64)
  |> bit_stream.write_unsigned("event_value_3", message.event_value_3, 64)
  |> bit_stream.write_unsigned("event_value_4", message.event_value_4, 64)
  |> bit_stream.write_unsigned("event_value_5", message.event_value_5, 64)
  |> bit_stream.write_unsigned("zero_value_6", message.zero_value_6, 64)
  |> bit_stream.write_wide_units("event_text", message.event_text)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(StatisticEvent, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(category, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use #(event_id, reader) <- result.try(bit_stream.read_unsigned(reader, 10))
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(zero_value_2, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(event_value_3, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(event_value_4, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(event_value_5, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(zero_value_6, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(event_text, reader) <- result.try(bit_stream.read_wide_units(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(StatisticEvent(
    category:,
    event_id:,
    character_id:,
    zero_value_2:,
    event_value_3:,
    event_value_4:,
    event_value_5:,
    zero_value_6:,
    event_text:,
  ))
}
