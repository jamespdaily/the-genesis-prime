//// A record inside a message body: one realm of the realm list. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x1400ac130` names the record.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record and has no use the client's code shows.
pub type RealmEntry {
  RealmEntry(
    realm_id: Int,
    name: String,
    note_text_id: Int,
    flags: Int,
    pvp_type: Int,
    status: Int,
    population: Int,
    field_8: Int,
    field_9: BitArray,
    field_10: Int,
    count: Int,
    last_played: String,
    field_13: Int,
    field_14: Int,
    field_15: Int,
    field_16: Int,
    field_17: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer: Writer, record: RealmEntry) -> Writer {
  todo
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(RealmEntry, Reader), DecodeError) {
  todo
}
