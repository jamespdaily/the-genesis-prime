//// The message schema as data: every message body, record and union, its
//// fields in wire order with each field's width or kind and the fact-file key
//// that proves it. The schema file is `src/genesis_prime/message/schema.toml`; this
//// module reads it for the generator and for the rule that every field names
//// its evidence.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tom.{type Toml}

/// Every message, every record and every union the schema holds.
pub type Schema {
  Schema(messages: List(Message), records: List(Record), unions: List(Union))
}

/// Which way a message travels.
pub type Direction {
  ClientToServer
  ServerToClient
  /// Either side sends it, such as the network layer's pong.
  Both
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

/// An item of a list that is one of several records, picked by the item's
/// leading kind, such as one movement command. The kind is the first
/// `tag_bits` bits of the item, and each variant's record reads them again as
/// its first field, a constant of that kind.
pub type Union {
  Union(
    name: String,
    evidence: String,
    summary: String,
    tag_bits: Int,
    variants: List(Variant),
  )
}

/// One variant of a union: the kind that picks it, its name (the constructor
/// the generated type gives it), the record that reads it and, when the kind
/// has a name beyond its number, the fact-file key that gives it.
pub type Variant {
  Variant(tag: Int, name: String, record: String, named_by: Option(String))
}

/// One field: its name, how its value is written, the fact-file key that gives
/// its width, the key that says what it is when it has a name beyond its
/// position, and, for a field with no name, the key that shows the value the
/// server sends is safe. A field with no `evidence` is read as such, so the
/// rule that every field names its evidence can report it.
pub type Field {
  Field(
    name: String,
    kind: Kind,
    evidence: Option(String),
    named_by: Option(String),
    safe_by: Option(String),
  )
}

/// The values of an unsigned field that the schema names: the name of the
/// custom type the generator writes for the field, and each value with its
/// name. Any other value the field holds is the type's `Other` case.
pub type NamedValues {
  NamedValues(type_name: String, values: List(Value))
}

/// One named value: its number, its name and the fact-file key that shows the
/// client gives it that meaning. A value with no `evidence` is read as such,
/// so the rule that every value names its evidence can report it.
pub type Value {
  Value(value: Int, name: String, evidence: Option(String))
}

/// How a field's value is written on the wire.
pub type Kind {
  /// An unsigned value of 1 to 64 bits, with the values the client's code names
  /// when it names any: only an unsigned value has them.
  Unsigned(bits: Int, values: Option(NamedValues))
  /// An unsigned value of `bits` bits that is below `limit`: the encoder
  /// refuses a value at or above it and the decoder fails on one.
  UnsignedBelow(bits: Int, limit: Int)
  /// A 32-bit float kept as its bits.
  Float32
  /// A wide text with a 7-bit or 15-bit count.
  WideText
  /// A wide text as its UTF-16 units, each kept as it was read (`List(Int)`),
  /// for a text the server relays and measures in units.
  WideUnits
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
  /// A count in `count_bits` bits, then that many of the named record or
  /// union.
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
  /// Records of the named record, as many as the earlier array field
  /// `counted_by` holds, with no count of their own.
  ArrayOfRecordCountedBy(counted_by: String, record: String)
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
  /// A message's direction is none of `client_to_server`, `server_to_client`
  /// and `both`.
  UnknownDirection(message: String, direction: String)
  /// An array field names a record the schema does not hold.
  UnknownRecord(field: String, record: String)
  /// A field is counted by a field that is not an array before it in the same
  /// message or record.
  UnknownCountField(field: String, counted_by: String)
  /// Two variants of a union have one kind.
  DuplicateTag(union: String, tag: Int)
  /// Two variants of a union have one name.
  DuplicateVariantName(union: String, name: String)
  /// A variant names a record the schema does not hold.
  UnknownVariantRecord(union: String, variant: String, record: String)
  /// A variant's record does not start with a constant of the variant's kind
  /// in the union's `tag_bits` bits, so the record could not read the kind its
  /// union picked it by.
  VariantKindDisagrees(union: String, variant: String)
  /// A field lists values and is not an unsigned value.
  ValuesOnOtherKind(field: String)
  /// A field lists one number for two values.
  DuplicateValue(field: String, value: Int)
  /// A field gives one name to two values.
  DuplicateValueName(field: String, name: String)
  /// A field names a value `other`, which is the case of the type's own
  /// fallback.
  ValueNamedOther(field: String)
  /// Two fields have one `values_type` and different lists of values, so the
  /// type is two things.
  ConflictingValues(type_name: String)
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
  use union_tables <- result.try(
    case tables(table: document, owner: "schema", key: "union") {
      Error(MissingKey(..)) -> Ok([])
      found -> found
    },
  )
  use record_names <- result.try(
    list.try_map(record_tables, fn(table) {
      string_of(table:, owner: "record", key: "name")
    }),
  )
  use union_names <- result.try(
    list.try_map(union_tables, fn(table) {
      string_of(table:, owner: "union", key: "name")
    }),
  )
  let item_names = list.append(record_names, union_names)
  use records <- result.try(
    list.try_map(record_tables, parse_record(_, item_names)),
  )
  use unions <- result.try(list.try_map(union_tables, parse_union(_, records)))
  use messages <- result.try(
    list.try_map(message_tables, parse_message(_, item_names)),
  )
  use Nil <- result.try(check_values_types(messages:, records:))
  Ok(Schema(messages:, records:, unions:))
}

fn parse_union(
  table: Dict(String, Toml),
  records: List(Record),
) -> Result(Union, SchemaError) {
  use name <- result.try(string_of(table:, owner: "union", key: "name"))
  use evidence <- result.try(string_of(table:, owner: name, key: "evidence"))
  use summary <- result.try(string_of(table:, owner: name, key: "summary"))
  use tag_bits <- result.try(int_in(
    table:,
    owner: name,
    key: "tag_bits",
    least: 1,
    most: 32,
  ))
  use variant_tables <- result.try(tables(table:, owner: name, key: "variants"))
  use variants <- result.try(
    list.try_map(variant_tables, parse_variant(_, tag_bits)),
  )
  use Nil <- result.try(check_variants_are_distinct(union: name, variants:))
  use Nil <- result.try(
    list.try_each(variants, fn(variant) {
      check_variant_record(union: name, tag_bits:, records:, variant:)
    }),
  )
  Ok(Union(name:, evidence:, summary:, tag_bits:, variants:))
}

fn parse_variant(
  table: Dict(String, Toml),
  tag_bits: Int,
) -> Result(Variant, SchemaError) {
  use name <- result.try(string_of(table:, owner: "variant", key: "name"))
  use tag <- result.try(int_in(
    table:,
    owner: name,
    key: "tag",
    least: 0,
    most: int.bitwise_shift_left(1, tag_bits) - 1,
  ))
  use record <- result.try(string_of(table:, owner: name, key: "record"))
  Ok(Variant(tag:, name:, record:, named_by: optional_string(table, "named_by")))
}

/// Where two items of a list share what must be unique: the number of the
/// later one, or its name when the numbers differ.
type Clash {
  SameNumber(number: Int)
  SameName(name: String)
}

/// The first item that has the number or the name of an item before it, with
/// the number checked first.
fn find_clash(
  items items: List(item),
  number number: fn(item) -> Int,
  name name: fn(item) -> String,
) -> Result(Nil, Clash) {
  find_clash_after(items:, number:, name:, seen: [])
}

fn find_clash_after(
  items items: List(item),
  number number: fn(item) -> Int,
  name name: fn(item) -> String,
  seen seen: List(item),
) -> Result(Nil, Clash) {
  case items {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case
        list.any(seen, fn(earlier) { number(earlier) == number(item) }),
        list.any(seen, fn(earlier) { name(earlier) == name(item) })
      {
        True, _ -> Error(SameNumber(number(item)))
        False, True -> Error(SameName(name(item)))
        False, False ->
          find_clash_after(items: rest, number:, name:, seen: [item, ..seen])
      }
  }
}

fn check_variants_are_distinct(
  union union: String,
  variants variants: List(Variant),
) -> Result(Nil, SchemaError) {
  find_clash(
    items: variants,
    number: fn(variant) { variant.tag },
    name: fn(variant) { variant.name },
  )
  |> result.map_error(fn(clash) {
    case clash {
      SameNumber(number:) -> DuplicateTag(union:, tag: number)
      SameName(name:) -> DuplicateVariantName(union:, name:)
    }
  })
}

/// A variant's record is one of the schema's, and starts with the constant its
/// union picked it by.
fn check_variant_record(
  union union: String,
  tag_bits tag_bits: Int,
  records records: List(Record),
  variant variant: Variant,
) -> Result(Nil, SchemaError) {
  case list.find(records, fn(record) { record.name == variant.record }) {
    Error(Nil) ->
      Error(UnknownVariantRecord(
        union:,
        variant: variant.name,
        record: variant.record,
      ))
    Ok(record) ->
      case record.fields {
        [Field(kind: Constant(bits:, value:), ..), ..]
          if bits == tag_bits && value == variant.tag
        -> Ok(Nil)
        _ -> Error(VariantKindDisagrees(union:, variant: variant.name))
      }
  }
}

/// Every field that names a `values_type` lists the same values as every
/// other field with that name, so each type is one module.
fn check_values_types(
  messages messages: List(Message),
  records records: List(Record),
) -> Result(Nil, SchemaError) {
  let named =
    list.append(
      list.flat_map(messages, fn(message) { message.fields }),
      list.flat_map(records, fn(record) { record.fields }),
    )
    |> list.filter_map(fn(field) { option.to_result(named_values(field:), Nil) })
  list.try_fold(named, [], fn(seen: List(NamedValues), values) {
    case
      list.find(seen, fn(earlier) { earlier.type_name == values.type_name })
    {
      Ok(earlier) if earlier != values ->
        Error(ConflictingValues(values.type_name))
      Ok(_) -> Ok(seen)
      Error(Nil) -> Ok([values, ..seen])
    }
  })
  |> result.replace(Nil)
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
    "both" -> Ok(Both)
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
        ArrayOfRecordCountedBy(counted_by:, ..) ->
          case list.contains(earlier_arrays, counted_by) {
            True ->
              check_counted_by_loop(fields: rest, earlier_arrays: [
                field.name,
                ..earlier_arrays
              ])
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
        | UnsignedBelow(..)
        | Float32
        | WideText
        | WideUnits
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
  use Nil <- result.try(case kind {
    Unsigned(..) -> Ok(Nil)
    UnsignedBelow(..)
    | Float32
    | WideText
    | WideUnits
    | CountedWideText(..)
    | Guid
    | Endpoint
    | RawBytes(..)
    | WholeFrame
    | ArrayOfWideText(..)
    | ArrayOfRecord(..)
    | ArrayOfUnsigned(..)
    | ArrayOfFloat32(..)
    | UnsignedArrayCountedBy(..)
    | ArrayOfRecordCountedBy(..)
    | Constant(..) -> refuse_values(table:, field: name)
  })
  Ok(Field(
    name:,
    kind:,
    evidence: optional_string(table, "evidence"),
    named_by: optional_string(table, "named_by"),
    safe_by: optional_string(table, "safe_by"),
  ))
}

/// The values a field's kind names, none for any kind but an unsigned one.
pub fn named_values(field field: Field) -> Option(NamedValues) {
  case field.kind {
    Unsigned(values:, ..) -> values
    UnsignedBelow(..)
    | Float32
    | WideText
    | WideUnits
    | CountedWideText(..)
    | Guid
    | Endpoint
    | RawBytes(..)
    | WholeFrame
    | ArrayOfWideText(..)
    | ArrayOfRecord(..)
    | ArrayOfUnsigned(..)
    | ArrayOfFloat32(..)
    | UnsignedArrayCountedBy(..)
    | ArrayOfRecordCountedBy(..)
    | Constant(..) -> None
  }
}

/// A field of a kind that holds no named values lists none.
fn refuse_values(
  table table: Dict(String, Toml),
  field field: String,
) -> Result(Nil, SchemaError) {
  case tom.get_array(table, ["values"]) {
    Error(tom.NotFound(_)) -> Ok(Nil)
    Error(tom.WrongType(..)) -> Error(WrongTypeOfKey(field, "values"))
    Ok(_) -> Error(ValuesOnOtherKind(field))
  }
}

/// The named values of an unsigned field of `bits` bits, when it lists any:
/// each value is below `2^bits`, with no number and no name twice.
fn parse_named_values(
  table table: Dict(String, Toml),
  field field: String,
  bits bits: Int,
) -> Result(Option(NamedValues), SchemaError) {
  case tom.get_array(table, ["values"]) {
    Error(tom.NotFound(_)) -> Ok(None)
    Error(tom.WrongType(..)) -> Error(WrongTypeOfKey(field, "values"))
    Ok(_) -> {
      use type_name <- result.try(string_of(
        table:,
        owner: field,
        key: "values_type",
      ))
      use Nil <- result.try(case upper_camel_case(type_name) {
        True -> Ok(Nil)
        False -> Error(WrongTypeOfKey(field, "values_type"))
      })
      use value_tables <- result.try(tables(table:, owner: field, key: "values"))
      use values <- result.try(
        list.try_map(value_tables, parse_value(table: _, field:, bits:)),
      )
      use Nil <- result.try(
        case list.any(values, fn(value) { value.name == "other" }) {
          True -> Error(ValueNamedOther(field))
          False -> Ok(Nil)
        },
      )
      use Nil <- result.try(check_values_are_distinct(field:, values:))
      Ok(Some(NamedValues(type_name:, values:)))
    }
  }
}

/// A capital letter and then letters and digits: a Gleam type name, from which
/// the module's name is made.
fn upper_camel_case(name: String) -> Bool {
  case string.to_graphemes(name) {
    [first, ..rest] ->
      first != string.lowercase(first)
      && list.all([first, ..rest], fn(letter) {
        string.contains(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
          letter,
        )
      })
    [] -> False
  }
}

fn parse_value(
  table table: Dict(String, Toml),
  field field: String,
  bits bits: Int,
) -> Result(Value, SchemaError) {
  use value <- result.try(int_in(
    table:,
    owner: field,
    key: "value",
    least: 0,
    most: int.bitwise_shift_left(1, bits) - 1,
  ))
  use name <- result.try(string_of(table:, owner: field, key: "name"))
  Ok(Value(value:, name:, evidence: optional_string(table, "evidence")))
}

fn check_values_are_distinct(
  field field: String,
  values values: List(Value),
) -> Result(Nil, SchemaError) {
  find_clash(items: values, number: fn(value) { value.value }, name: fn(value) {
    value.name
  })
  |> result.map_error(fn(clash) {
    case clash {
      SameNumber(number:) -> DuplicateValue(field:, value: number)
      SameName(name:) -> DuplicateValueName(field:, name:)
    }
  })
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
      use values <- result.try(parse_named_values(table:, field:, bits:))
      Ok(Unsigned(bits:, values:))
    }
    "unsigned_below" -> {
      use bits <- result.try(int_in(
        table:,
        owner: field,
        key: "bits",
        least: 1,
        most: 64,
      ))
      use limit <- result.try(int_in(
        table:,
        owner: field,
        key: "limit",
        least: 1,
        most: int.bitwise_shift_left(1, bits),
      ))
      Ok(UnsignedBelow(bits:, limit:))
    }
    "float32" -> Ok(Float32)
    "wide_text" -> Ok(WideText)
    "wide_units" -> Ok(WideUnits)
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
/// floats, unsigned values of `element_bits` bits, records or unions.
fn parse_array(
  table table: Dict(String, Toml),
  field field: String,
  record_names record_names: List(String),
) -> Result(Kind, SchemaError) {
  use element <- result.try(string_of(table:, owner: field, key: "element"))
  case optional_string(table, "counted_by") {
    Some(counted_by) -> {
      case element, list.contains(record_names, element) {
        "unsigned", _ -> {
          use bits <- result.map(element_bits(table:, field:))
          UnsignedArrayCountedBy(counted_by:, bits:)
        }
        _, True -> Ok(ArrayOfRecordCountedBy(counted_by:, record: element))
        _, False -> Error(UnknownRecord(field:, record: element))
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
    DuplicateTag(union:, tag:) ->
      union <> " gives the kind " <> int.to_string(tag) <> " to two variants"
    DuplicateVariantName(union:, name:) ->
      union <> " gives the name " <> name <> " to two variants"
    UnknownVariantRecord(union:, variant:, record:) ->
      union
      <> " has the variant "
      <> variant
      <> " of the record "
      <> record
      <> ", which the schema lacks"
    VariantKindDisagrees(union:, variant:) ->
      union
      <> " has the variant "
      <> variant
      <> ", whose record does not start with a constant of its kind in the union's width"
    ValuesOnOtherKind(field:) ->
      field <> " lists values and is not an unsigned value"
    DuplicateValue(field:, value:) ->
      field <> " lists the value " <> int.to_string(value) <> " twice"
    DuplicateValueName(field:, name:) ->
      field <> " gives the name " <> name <> " to two values"
    ValueNamedOther(field:) ->
      field <> " names a value other, which is its type's own fallback"
    ConflictingValues(type_name:) ->
      type_name <> " is the values type of fields with different values"
  }
}
