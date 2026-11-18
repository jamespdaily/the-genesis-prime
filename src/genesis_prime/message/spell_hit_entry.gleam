//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one hit entry of a damage description: the
//// raw damage, the amount, the overheal, the absorption, the shield, the
//// glance amount and the overkill, 32 bits each, and a 3-bit kind, of which 2
//// and 3 make a multi-hit line and any other a deflect line. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x1400945e0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellHitEntry {
  SpellHitEntry(
    raw_damage: Int,
    amount: Int,
    overheal: Int,
    absorption: Int,
    shield: Int,
    glance: Int,
    overkill: Int,
    kind: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellHitEntry) -> Writer {
  writer
  |> bit_stream.write_unsigned("raw_damage", record.raw_damage, 32)
  |> bit_stream.write_unsigned("amount", record.amount, 32)
  |> bit_stream.write_unsigned("overheal", record.overheal, 32)
  |> bit_stream.write_unsigned("absorption", record.absorption, 32)
  |> bit_stream.write_unsigned("shield", record.shield, 32)
  |> bit_stream.write_unsigned("glance", record.glance, 32)
  |> bit_stream.write_unsigned("overkill", record.overkill, 32)
  |> bit_stream.write_unsigned("kind", record.kind, 3)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellHitEntry, Reader), DecodeError) {
  use #(raw_damage, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(amount, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(overheal, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(absorption, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(shield, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(glance, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(overkill, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  Ok(#(
    SpellHitEntry(
      raw_damage:,
      amount:,
      overheal:,
      absorption:,
      shield:,
      glance:,
      overkill:,
      kind:,
    ),
    reader,
  ))
}
