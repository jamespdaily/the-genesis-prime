//// The message schema as data: every message body and record, its fields in
//// wire order with each field's width or kind and the fact-file key that
//// proves it. The schema file is `src/genesis_prime/message/schema.toml`; this
//// module reads it for the generator and for the rule that every field names
//// its evidence.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import tom.{type Toml}

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
  /// A count in `count_bits` bits, then that many unsigned values of `bits`
  /// bits each.
  ArrayOfUnsigned(count_bits: Int, bits: Int)
  /// A count in `count_bits` bits, then that many 32-bit floats kept as their
  /// bits.
  ArrayOfFloat32(count_bits: Int)
  /// Unsigned values of `bits` bits each, as many as the earlier array field
  /// `counted_by` holds, with no count of their own.
  UnsignedArrayCountedBy(counted_by: String, bits: Int)
  /// A value of `bits` bits that is always `value`. It is no field of the
  /// type: the encoder writes it, and the decoder refuses any other value.
  Constant(bits: Int, value: Int)
}

/// Why the schema file is not a schema.
pub type SchemaError {
  /// The text is not TOML.
  NotToml
  /// A table lacks a key it needs.
  MissingKey(table: String, key: String)
  /// A key holds a value of another type, or outside the range the key allows.
  WrongTypeOfKey(table: String, key: String)
  /// A field's kind is none the generator writes.
  UnknownKind(field: String, kind: String)
  /// A message's direction is neither `client_to_server` nor
  /// `server_to_client`.
  UnknownDirection(message: String, direction: String)
  /// An array field names a record the schema does not hold.
  UnknownRecord(field: String, record: String)
  /// A field is counted by a field that is not an array before it in the same
  /// message or record.
  UnknownCountField(field: String, counted_by: String)
}

/// Reads the text of the schema file.
pub fn parse(text: String) -> Result(Schema, SchemaError) {
  use document <- result.try(tom.parse(text) |> result.replace_error(NotToml))
  use record_tables <- result.try(tables(
    table: document,
    owner: "schema",
    key: "record",
  ))
  use message_tables <- result.try(tables(
    table: document,
    owner: "schema",
    key: "message",
  ))
  use record_names <- result.try(
    list.try_map(record_tables, fn(table) {
      string_of(table:, owner: "record", key: "name")
    }),
  )
  use records <- result.try(
    list.try_map(record_tables, parse_record(_, record_names)),
  )
  use messages <- result.try(
    list.try_map(message_tables, parse_message(_, record_names)),
  )
  Ok(Schema(messages:, records:))
}

fn parse_message(
  table: Dict(String, Toml),
  record_names: List(String),
) -> Result(Message, SchemaError) {
  use name <- result.try(string_of(table:, owner: "message", key: "name"))
  use id <- result.try(int_of(table:, owner: name, key: "id"))
  use direction_name <- result.try(string_of(
    table:,
    owner: name,
    key: "direction",
  ))
  use direction <- result.try(case direction_name {
    "client_to_server" -> Ok(ClientToServer)
    "server_to_client" -> Ok(ServerToClient)
    other -> Error(UnknownDirection(message: name, direction: other))
  })
  use evidence <- result.try(string_of(table:, owner: name, key: "evidence"))
  use summary <- result.try(string_of(table:, owner: name, key: "summary"))
  use fields <- result.try(parse_fields(
    owner: table,
    owner_name: name,
    record_names:,
  ))
  Ok(Message(id:, name:, direction:, evidence:, summary:, fields:))
}

fn parse_record(
  table: Dict(String, Toml),
  record_names: List(String),
) -> Result(Record, SchemaError) {
  use name <- result.try(string_of(table:, owner: "record", key: "name"))
  use evidence <- result.try(string_of(table:, owner: name, key: "evidence"))
  use summary <- result.try(string_of(table:, owner: name, key: "summary"))
  use fields <- result.try(parse_fields(
    owner: table,
    owner_name: name,
    record_names:,
  ))
  Ok(Record(name:, evidence:, summary:, fields:))
}

fn parse_fields(
  owner owner: Dict(String, Toml),
  owner_name owner_name: String,
  record_names record_names: List(String),
) -> Result(List(Field), SchemaError) {
  use field_tables <- result.try(tables(
    table: owner,
    owner: owner_name,
    key: "fields",
  ))
  use fields <- result.try(
    list.try_map(field_tables, parse_field(table: _, owner_name:, record_names:)),
  )
  use Nil <- result.try(check_counted_by(fields))
  Ok(fields)
}

/// Every field that is counted by another is counted by an array field before
/// it, so a decoder has read the count when it needs it.
fn check_counted_by(fields: List(Field)) -> Result(Nil, SchemaError) {
  check_counted_by_loop(fields:, earlier_arrays: [])
}

fn check_counted_by_loop(
  fields fields: List(Field),
  earlier_arrays earlier_arrays: List(String),
) -> Result(Nil, SchemaError) {
  case fields {
    [] -> Ok(Nil)
    [field, ..rest] ->
      case field.kind {
        UnsignedArrayCountedBy(counted_by:, ..) ->
          case list.contains(earlier_arrays, counted_by) {
            True -> check_counted_by_loop(fields: rest, earlier_arrays:)
            False -> Error(UnknownCountField(field: field.name, counted_by:))
          }
        ArrayOfWideText(..)
        | ArrayOfRecord(..)
        | ArrayOfUnsigned(..)
        | ArrayOfFloat32(..) ->
          check_counted_by_loop(fields: rest, earlier_arrays: [
            field.name,
            ..earlier_arrays
          ])
        Unsigned(..)
        | Float32
        | WideText
        | CountedWideText(..)
        | Guid
        | Endpoint
        | RawBytes(..)
        | WholeFrame
        | Constant(..) -> check_counted_by_loop(fields: rest, earlier_arrays:)
      }
  }
}

fn parse_field(
  table table: Dict(String, Toml),
  owner_name owner_name: String,
  record_names record_names: List(String),
) -> Result(Field, SchemaError) {
  use name <- result.try(string_of(table:, owner: owner_name, key: "name"))
  use kind_name <- result.try(string_of(table:, owner: name, key: "kind"))
  use kind <- result.try(parse_kind(
    table:,
    field: name,
    kind: kind_name,
    record_names:,
  ))
  Ok(Field(
    name:,
    kind:,
    evidence: optional_string(table, "evidence"),
    named_by: optional_string(table, "named_by"),
  ))
}

fn parse_kind(
  table table: Dict(String, Toml),
  field field: String,
  kind kind: String,
  record_names record_names: List(String),
) -> Result(Kind, SchemaError) {
  case kind {
    "unsigned" -> {
      use bits <- result.try(int_in(
        table:,
        owner: field,
        key: "bits",
        least: 1,
        most: 64,
      ))
      Ok(Unsigned(bits:))
    }
    "float32" -> Ok(Float32)
    "wide_text" -> Ok(WideText)
    "counted_wide_text" -> {
      use max_units <- result.try(int_in(
        table:,
        owner: field,
        key: "max_units",
        least: 1,
        most: 65_534,
      ))
      Ok(CountedWideText(max_units:))
    }
    "guid" -> Ok(Guid)
    "endpoint" -> Ok(Endpoint)
    "raw_bytes" -> {
      use count <- result.try(int_in(
        table:,
        owner: field,
        key: "count",
        least: 1,
        most: 65_535,
      ))
      Ok(RawBytes(count:))
    }
    "whole_frame" -> Ok(WholeFrame)
    "array" -> parse_array(table:, field:, record_names:)
    "constant" -> {
      use bits <- result.try(int_in(
        table:,
        owner: field,
        key: "bits",
        least: 1,
        most: 64,
      ))
      use value <- result.try(int_in(
        table:,
        owner: field,
        key: "value",
        least: 0,
        most: int.bitwise_shift_left(1, bits) - 1,
      ))
      Ok(Constant(bits:, value:))
    }
    other -> Error(UnknownKind(field:, kind: other))
  }
}

/// An array field: the count is in `count_bits` bits or is the length of
/// an earlier array (`counted_by`), and the elements are wide texts, 32-bit
/// floats, unsigned values of `element_bits` bits or records.
fn parse_array(
  table table: Dict(String, Toml),
  field field: String,
  record_names record_names: List(String),
) -> Result(Kind, SchemaError) {
  use element <- result.try(string_of(table:, owner: field, key: "element"))
  case optional_string(table, "counted_by") {
    Some(counted_by) -> {
      use bits <- result.try(element_bits(table:, field:))
      case element {
        "unsigned" -> Ok(UnsignedArrayCountedBy(counted_by:, bits:))
        other -> Error(UnknownKind(field:, kind: "array of " <> other))
      }
    }
    None -> {
      use count_bits <- result.try(int_in(
        table:,
        owner: field,
        key: "count_bits",
        least: 1,
        most: 64,
      ))
      parse_counted_array(table:, field:, element:, count_bits:, record_names:)
    }
  }
}

fn parse_counted_array(
  table table: Dict(String, Toml),
  field field: String,
  element element: String,
  count_bits count_bits: Int,
  record_names record_names: List(String),
) -> Result(Kind, SchemaError) {
  case element, list.contains(record_names, element) {
    "wide_text", _ -> Ok(ArrayOfWideText(count_bits:))
    "float32", _ -> Ok(ArrayOfFloat32(count_bits:))
    "unsigned", _ -> {
      use bits <- result.map(element_bits(table:, field:))
      ArrayOfUnsigned(count_bits:, bits:)
    }
    _, True -> Ok(ArrayOfRecord(count_bits:, record: element))
    _, False -> Error(UnknownRecord(field:, record: element))
  }
}

fn element_bits(
  table table: Dict(String, Toml),
  field field: String,
) -> Result(Int, SchemaError) {
  int_in(table:, owner: field, key: "element_bits", least: 1, most: 64)
}

fn tables(
  table table: Dict(String, Toml),
  owner owner: String,
  key key: String,
) -> Result(List(Dict(String, Toml)), SchemaError) {
  case tom.get_array(table, [key]) {
    Ok(items) ->
      list.try_map(items, fn(item) {
        tom.as_table(item) |> result.replace_error(WrongTypeOfKey(owner, key))
      })
    Error(tom.NotFound(_)) -> Error(MissingKey(owner, key))
    Error(tom.WrongType(..)) -> Error(WrongTypeOfKey(owner, key))
  }
}

fn string_of(
  table table: Dict(String, Toml),
  owner owner: String,
  key key: String,
) -> Result(String, SchemaError) {
  case tom.get_string(table, [key]) {
    Ok(value) -> Ok(value)
    Error(tom.NotFound(_)) -> Error(MissingKey(owner, key))
    Error(tom.WrongType(..)) -> Error(WrongTypeOfKey(owner, key))
  }
}

fn int_of(
  table table: Dict(String, Toml),
  owner owner: String,
  key key: String,
) -> Result(Int, SchemaError) {
  case tom.get_int(table, [key]) {
    Ok(value) -> Ok(value)
    Error(tom.NotFound(_)) -> Error(MissingKey(owner, key))
    Error(tom.WrongType(..)) -> Error(WrongTypeOfKey(owner, key))
  }
}

fn int_in(
  table table: Dict(String, Toml),
  owner owner: String,
  key key: String,
  least least: Int,
  most most: Int,
) -> Result(Int, SchemaError) {
  use value <- result.try(int_of(table:, owner:, key:))
  case value >= least && value <= most {
    True -> Ok(value)
    False -> Error(WrongTypeOfKey(owner, key))
  }
}

fn optional_string(table: Dict(String, Toml), key: String) -> Option(String) {
  tom.get_string(table, [key]) |> option.from_result
}

/// What is wrong with the schema file, in a sentence.
pub fn describe(error: SchemaError) -> String {
  case error {
    NotToml -> "the file is not TOML"
    MissingKey(table:, key:) -> table <> " has no " <> key
    WrongTypeOfKey(table:, key:) ->
      table <> " has a " <> key <> " of the wrong type or outside its range"
    UnknownKind(field:, kind:) -> field <> " has the unknown kind " <> kind
    UnknownDirection(message:, direction:) ->
      message <> " has the unknown direction " <> direction
    UnknownRecord(field:, record:) ->
      field <> " names the record " <> record <> ", which the schema lacks"
    UnknownCountField(field:, counted_by:) ->
      field
      <> " is counted by "
      <> counted_by
      <> ", which is no array field before it"
  }
}
