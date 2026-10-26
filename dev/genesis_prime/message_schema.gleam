//// The message schema as data: every message body and record, its fields in
//// wire order with each field's width or kind and the fact-file key that
//// proves it. The schema file is `src/genesis_prime/message/schema.toml`; this
//// module reads it for the generator and for the rule that every field names
//// its evidence.

import gleam/option.{type Option}

/// Every message and every record the schema holds.
pub type Schema {
  Schema(messages: List(Message), records: List(Record))
}

/// Which way a message travels.
pub type Direction {
  ClientToServer
  ServerToClient
}

/// One message: its number, its name, which way it travels, the fact-file key
/// of its record and a sentence on what the client does with it.
pub type Message {
  Message(
    id: Int,
    name: String,
    direction: Direction,
    evidence: String,
    summary: String,
    fields: List(Field),
  )
}

/// A part of a message body that has fields of its own and repeats in an
/// array, such as one realm of the realm list.
pub type Record {
  Record(name: String, evidence: String, summary: String, fields: List(Field))
}

/// One field: its name, how its value is written, the fact-file key that gives
/// its width, and the key that says what it is when it has a name beyond its
/// position. A field with no `evidence` is read as such, so the rule that
/// every field names its evidence can report it.
pub type Field {
  Field(
    name: String,
    kind: Kind,
    evidence: Option(String),
    named_by: Option(String),
  )
}

/// How a field's value is written on the wire.
pub type Kind {
  /// An unsigned value of 1 to 64 bits.
  Unsigned(bits: Int)
  /// A 32-bit float kept as its bits.
  Float32
  /// A wide text with a 7-bit or 15-bit count.
  WideText
  /// A wide text with a 16-bit count and a terminating zero, of at most
  /// `max_units` units.
  CountedWideText(max_units: Int)
  /// A 16-byte GUID.
  Guid
  /// An IPv4 address in 32 bits and a port in 16.
  Endpoint
  /// A fixed number of raw bytes at the bit position.
  RawBytes(count: Int)
  /// A whole inner frame after a move to the next whole byte.
  WholeFrame
  /// A count in `count_bits` bits, then that many wide texts.
  ArrayOfWideText(count_bits: Int)
  /// A count in `count_bits` bits, then that many of the named record.
  ArrayOfRecord(count_bits: Int, record: String)
}

/// Why the schema file is not a schema.
pub type SchemaError {
  NotToml
  MissingKey(table: String, key: String)
  WrongTypeOfKey(table: String, key: String)
  UnknownKind(field: String, kind: String)
  UnknownDirection(message: String, direction: String)
  UnknownRecord(field: String, record: String)
}

/// Reads the text of the schema file.
pub fn parse(text: String) -> Result(Schema, SchemaError) {
  todo
}
