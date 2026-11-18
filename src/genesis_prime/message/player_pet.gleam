//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one of the player's pets, kept by its unit
//// id (GetPlayerPets), then an 18-bit value no reader was found for, the valid
//// stances mask and the current stance as a one-bit mask. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x14008cee0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type PlayerPet {
  PlayerPet(
    unit_id: Int,
    /// Open: What reads a pet's 18-bit value? No reader was found among the
    /// functions that touch the pet map (0x1403c08d0 adds an entry;
    /// 0x14008cee0.unread_values).
    /// Safe by `opcode.0x25e.safe_body`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    field_2: Int,
    /// Safe by `opcode.0x25e.safe_body`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    valid_stance_mask: Int,
    /// Safe by `opcode.0x25e.safe_body`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    stance_mask: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: PlayerPet) -> Writer {
  writer
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("field_2", record.field_2, 18)
  |> bit_stream.write_unsigned("valid_stance_mask", record.valid_stance_mask, 5)
  |> bit_stream.write_unsigned("stance_mask", record.stance_mask, 5)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(PlayerPet, Reader), DecodeError) {
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(valid_stance_mask, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    5,
  ))
  use #(stance_mask, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  Ok(#(PlayerPet(unit_id:, field_2:, valid_stance_mask:, stance_mask:), reader))
}
