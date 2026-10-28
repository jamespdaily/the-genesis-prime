//// Writes the Gleam codec of every message and record in the schema: one
//// module for each under `src/genesis_prime/message/`, with its type, and for
//// a message `encode` and `decode`, for a record `write` and `read`; and the
//// `client_message` module, which decodes a message the client sends by its
//// number. The text is already in `gleam format`'s layout, so a regenerated
//// file equals the committed one byte for byte, and `mismatches` names each
//// file that does not.

import genesis_prime/message_schema.{
  type Field, type Kind, type Message, type NamedValues, type Record,
  type Schema,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

/// One generated file: its path from the repository root and its text.
pub type GeneratedFile {
  GeneratedFile(path: String, text: String)
}

/// How a committed file differs from the generated one.
pub type Mismatch {
  /// The committed text differs from what the schema generates.
  Edited(path: String)
  /// The schema generates a file that is not committed.
  Missing(path: String)
  /// A committed generated file is not in what the schema generates.
  Stale(path: String)
}

/// The start of the first line of every generated file, which marks a file as
/// generated and so as one that `mismatches` compares.
pub const generated_marker = "//// Generated from `schema.toml`"

/// The longest line `gleam format` leaves whole.
const width = 80

const directory = "src/genesis_prime/message"

/// The schema file the codec is generated from.
pub const schema_path = "src/genesis_prime/message/schema.toml"

/// Why the schema or the committed files could not be read.
pub type ReadFailure {
  /// A file could not be read.
  NotRead(path: String, error: simplifile.FileError)
  /// A folder could not be listed.
  NotListed(path: String, error: simplifile.FileError)
  /// The schema file is not a schema.
  NotASchema(path: String, error: message_schema.SchemaError)
}

/// The files the schema file generates.
pub fn generated_files() -> Result(List(GeneratedFile), ReadFailure) {
  use text <- result.try(
    simplifile.read(schema_path)
    |> result.map_error(NotRead(path: schema_path, error: _)),
  )
  use schema <- result.map(
    message_schema.parse(text)
    |> result.map_error(NotASchema(path: schema_path, error: _)),
  )
  generate(schema)
}

/// The `.gleam` files committed in the codec's folder.
pub fn committed_files() -> Result(List(GeneratedFile), ReadFailure) {
  use paths <- result.try(
    simplifile.get_files(directory)
    |> result.map_error(NotListed(path: directory, error: _)),
  )
  paths
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.try_map(fn(path) {
    simplifile.read(path)
    |> result.map(fn(text) { GeneratedFile(path:, text:) })
    |> result.map_error(NotRead(path:, error: _))
  })
}

/// A sentence that says which file or folder failed and why, for a person.
pub fn describe_failure(failure: ReadFailure) -> String {
  case failure {
    NotRead(path:, error:) ->
      "could not read " <> path <> ": " <> simplifile.describe_error(error)
    NotListed(path:, error:) ->
      "could not list " <> path <> ": " <> simplifile.describe_error(error)
    NotASchema(path:, error:) -> path <> ": " <> message_schema.describe(error)
  }
}

/// The files the schema generates: a module for each message, then each
/// record, then each type of named values, then the client message module.
pub fn generate(schema: Schema) -> List(GeneratedFile) {
  list.flatten([
    list.map(schema.messages, fn(message) {
      GeneratedFile(
        path: directory <> "/" <> message.name <> ".gleam",
        text: message_module(message),
      )
    }),
    list.map(schema.records, fn(record) {
      GeneratedFile(
        path: directory <> "/" <> record.name <> ".gleam",
        text: record_module(record),
      )
    }),
    list.map(values_types(schema), fn(named_values) {
      GeneratedFile(
        path: directory <> "/" <> values_module(named_values) <> ".gleam",
        text: values_module_text(named_values),
      )
    }),
    [
      GeneratedFile(
        path: directory <> "/client_message.gleam",
        text: client_message_module(schema.messages),
      ),
    ],
  ])
}

/// Each way the committed files differ from the generated ones. A committed
/// file counts only when it holds the generated marker, so the hand-written
/// bit stream module is never stale.
pub fn mismatches(
  generated generated: List(GeneratedFile),
  committed committed: List(GeneratedFile),
) -> List(Mismatch) {
  let missing_or_edited =
    list.filter_map(generated, fn(file) {
      case list.find(committed, fn(found) { found.path == file.path }) {
        Error(Nil) -> Ok(Missing(file.path))
        Ok(found) if found.text == file.text -> Error(Nil)
        Ok(_) -> Ok(Edited(file.path))
      }
    })
  let stale =
    list.filter_map(committed, fn(file) {
      let is_generated = string.starts_with(file.text, generated_marker)
      let is_known = list.any(generated, fn(known) { known.path == file.path })
      case is_generated && !is_known {
        True -> Ok(Stale(file.path))
        False -> Error(Nil)
      }
    })
  list.append(missing_or_edited, stale)
}

fn message_module(message: Message) -> String {
  let type_name = camel(message.name)
  let direction = case message.direction {
    message_schema.ClientToServer -> "client to server"
    message_schema.ServerToClient -> "server to client"
    message_schema.Both -> "either direction"
  }
  let head =
    wrap(
      "////",
      "Message "
        <> hex_id(message.id)
        <> " ("
        <> message.name
        <> "), "
        <> direction
        <> ": "
        <> message.summary
        <> ". Its fields are listed in `schema.toml` with the client's evidence, and the fact file's `"
        <> message.evidence
        <> "` names the message.",
    )
  let type_doc = case held(message.fields) {
    [] ->
      wrap(
        "///",
        "The body of message " <> hex_id(message.id) <> ", which is empty.",
      )
    _ ->
      wrap(
        "///",
        "The body of message "
          <> hex_id(message.id)
          <> ", its fields in wire order. A field named `field_N` is the Nth of the body and has no use the client's code shows.",
      )
  }
  let unused = case held(message.fields) {
    [] -> "_"
    _ -> ""
  }
  let encode_head =
    function_head(
      name: "encode",
      parameters: [unused <> "message: " <> type_name],
      returns: "Result(BitArray, EncodeError)",
    )
  let decode_head =
    function_head(
      name: "decode",
      parameters: ["body: BitArray"],
      returns: "Result(" <> type_name <> ", DecodeError)",
    )
  let encode_body = [
    "  bit_stream.new_writer()",
    ..list.flatten([
      list.flat_map(message.fields, write_step(_, "message")),
      ["  |> bit_stream.finish"],
    ])
  ]
  lines_to_text(
    list.flatten([
      header(head),
      imports(message.fields, ["DecodeError", "EncodeError"]),
      [
        "/// The message's number.",
        "pub const message_id = " <> hex_id(message.id),
        "",
      ],
      type_doc,
      type_declaration(type_name, message.fields),
      [""],
      wrap(
        "///",
        "The message as the bytes of its body, or the first field that cannot be written.",
      ),
      encode_head,
      encode_body,
      ["}", ""],
      wrap(
        "///",
        "The message read from the bytes of a body, or why they are not one.",
      ),
      decode_head,
      decode_body(message.fields, type_name),
      ["}"],
    ]),
  )
}

fn record_module(record: Record) -> String {
  let type_name = camel(record.name)
  let head =
    wrap(
      "////",
      "A record inside a message body: "
        <> record.summary
        <> ". Its fields are listed in `schema.toml` with the client's evidence, and the fact file's `"
        <> record.evidence
        <> "` names the record.",
    )
  lines_to_text(
    list.flatten([
      header(head),
      imports(record.fields, ["DecodeError", "Reader", "Writer"]),
      wrap(
        "///",
        "The record's fields in wire order. A field named `field_N` is the Nth of the record and has no use the client's code shows.",
      ),
      type_declaration(type_name, record.fields),
      [""],
      ["/// Writes the record's fields to the stream."],
      function_head(
        name: "write",
        parameters: ["writer writer: Writer", "record record: " <> type_name],
        returns: "Writer",
      ),
      ["  writer", ..list.flat_map(record.fields, write_step(_, "record"))],
      ["}", ""],
      ["/// Reads the record from the stream, and the stream after it."],
      function_head(
        name: "read",
        parameters: ["reader: Reader"],
        returns: "Result(#(" <> type_name <> ", Reader), DecodeError)",
      ),
      read_steps(record.fields),
      construct_with_reader(record.fields, type_name),
      ["}"],
    ]),
  )
}

/// The module of every message the client sends: a variant for each message
/// that travels client to server or either way, in the schema's order, and the
/// decoder that picks a body's decoder by its message's number.
fn client_message_module(messages: List(Message)) -> String {
  let sent =
    list.filter(messages, fn(message) {
      message.direction != message_schema.ServerToClient
    })
  let head =
    wrap(
      "////",
      "Every message the client sends, by its number: a variant for each message of the schema that travels client to server or either way, `decode` to read a body by its message's number, `encode` to write it back and `message_id` to name it. A number no such message has is reported as unknown.",
    )
  let module_imports =
    list.sort(sent, fn(left, right) { string.compare(left.name, right.name) })
    |> list.flat_map(fn(message) {
      type_import(module: message.name, type_name: camel(message.name))
    })
  lines_to_text(
    list.flatten([
      header(head),
      [
        "import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}",
      ],
      module_imports,
      [""],
      ["/// A message the client sends, decoded: one variant for each message."],
      ["pub type ClientMessage {"],
      list.map(sent, fn(message) {
        let name = camel(message.name)
        "  " <> name <> "(message: " <> name <> ")"
      }),
      ["}", ""],
      ["/// Why a body is not a message the client sends."],
      ["pub type ClientMessageError {"],
      ["  /// No message the client sends has this number."],
      ["  UnknownMessage(message_id: Int)"],
      ["  /// The body is not the message its number names."],
      ["  Malformed(message_id: Int, error: DecodeError)"],
      ["}", ""],
      wrap(
        "///",
        "The message a body holds, read by the decoder of the message its number names.",
      ),
      function_head(
        name: "decode",
        parameters: ["message_id message_id: Int", "body body: BitArray"],
        returns: "Result(ClientMessage, ClientMessageError)",
      ),
      ["  case message_id {"],
      list.flat_map(sent, fn(message) {
        case_arm(pattern: hex_id(message.id), head: "decoded", arguments: [
          "body",
          "message_id",
          message.name <> ".decode",
          camel(message.name),
        ])
      }),
      ["    _ -> Error(UnknownMessage(message_id:))", "  }", "}", ""],
      wrap(
        "///",
        "The bytes of a message's body, or the first field that cannot be written.",
      ),
      function_head(
        name: "encode",
        parameters: ["message: ClientMessage"],
        returns: "Result(BitArray, EncodeError)",
      ),
      ["  case message {"],
      list.flat_map(sent, fn(message) {
        case_arm(
          pattern: camel(message.name) <> "(message:)",
          head: message.name <> ".encode",
          arguments: ["message"],
        )
      }),
      ["  }", "}", ""],
      ["/// The number of a message."],
      ["pub fn message_id(message: ClientMessage) -> Int {"],
      ["  case message {"],
      list.map(sent, fn(message) {
        "    "
        <> camel(message.name)
        <> "(..) -> "
        <> message.name
        <> ".message_id"
      }),
      ["  }", "}", ""],
      [
        "fn decoded(",
        "  body: BitArray,",
        "  message_id: Int,",
        "  decode: fn(BitArray) -> Result(message, DecodeError),",
        "  variant: fn(message) -> ClientMessage,",
        ") -> Result(ClientMessage, ClientMessageError) {",
        "  case decode(body) {",
        "    Ok(message) -> Ok(variant(message))",
        "    Error(error) -> Error(Malformed(message_id:, error:))",
        "  }",
        "}",
      ],
    ]),
  )
}

/// A case arm `pattern -> call` as `gleam format` lays it out: on one line when
/// it fits, with the call alone on the next line, or with the call's arguments
/// one to a line.
fn case_arm(
  pattern pattern: String,
  head head: String,
  arguments arguments: List(String),
) -> List(String) {
  let inner = head <> "(" <> string.join(arguments, ", ") <> ")"
  let one = "    " <> pattern <> " -> " <> inner
  case string.length(one) <= width, string.length("      " <> inner) <= width {
    True, _ -> [one]
    False, True -> ["    " <> pattern <> " ->", "      " <> inner]
    False, False ->
      list.flatten([
        ["    " <> pattern <> " ->"],
        call(indent: 6, head:, arguments:, tail: ""),
      ])
  }
}

/// The types of named values the schema's fields use, each once, in the order
/// the fields first use them.
fn values_types(schema: Schema) -> List(NamedValues) {
  list.append(
    list.flat_map(schema.messages, fn(message) { message.fields }),
    list.flat_map(schema.records, fn(record) { record.fields }),
  )
  |> list.filter_map(fn(field) { option.to_result(field.named_values, Nil) })
  |> list.unique
}

/// The name of the module of a type of named values: the type's name in snake
/// case.
fn values_module(named_values: NamedValues) -> String {
  string.to_graphemes(named_values.type_name)
  |> list.index_map(fn(letter, index) {
    case letter != string.lowercase(letter) && index > 0 {
      True -> "_" <> string.lowercase(letter)
      False -> string.lowercase(letter)
    }
  })
  |> string.concat
}

/// The module of a type of named values: the type with a case for each value
/// and `Other` for any value the schema does not name, and the two functions
/// the codecs use to write and read it as a number.
fn values_module_text(named_values: NamedValues) -> String {
  let type_name = named_values.type_name
  let head =
    wrap(
      "////",
      "The values of "
        <> type_name
        <> " that `schema.toml` names, each with the evidence for its meaning, and `Other` for any value it does not name.",
    )
  lines_to_text(
    list.flatten([
      header(head),
      wrap("///", "The values of a field, as the client's code names them."),
      ["pub type " <> type_name <> " {"],
      list.flat_map(named_values.values, fn(value) {
        let evidence = case value.evidence {
          Some(key) -> ", the fact file's `" <> key <> "`"
          None -> ""
        }
        list.flatten([
          wrap(
            "  ///",
            "The value " <> int.to_string(value.value) <> evidence <> ".",
          ),
          ["  " <> camel(value.name)],
        ])
      }),
      ["  /// A value the schema does not name.", "  Other(Int)", "}", ""],
      ["/// The number the encoder writes for a value."],
      function_head(
        name: "to_value",
        parameters: ["value: " <> type_name],
        returns: "Int",
      ),
      ["  case value {"],
      list.map(named_values.values, fn(value) {
        "    " <> camel(value.name) <> " -> " <> int.to_string(value.value)
      }),
      ["    Other(number) -> number", "  }", "}", ""],
      ["/// The value for a number the decoder read."],
      function_head(
        name: "from_value",
        parameters: ["number: Int"],
        returns: type_name,
      ),
      ["  case number {"],
      list.map(named_values.values, fn(value) {
        "    " <> int.to_string(value.value) <> " -> " <> camel(value.name)
      }),
      ["    other -> Other(other)", "  }", "}"],
    ]),
  )
}

fn header(description: List(String)) -> List(String) {
  list.flatten([
    [
      generated_marker <> " by `genesis_prime/generate_messages`;",
      "//// never edited by hand.",
      "////",
    ],
    description,
    [""],
  ])
}

/// The import lines: the bit stream module with the types the code names, each
/// record module an array field reads, and `gleam/result`.
fn imports(fields: List(Field), types: List(String)) -> List(String) {
  let uses_endpoint =
    list.any(fields, fn(field) { field.kind == message_schema.Endpoint })
  let named = case uses_endpoint {
    True -> ["Endpoint", ..types]
    False -> types
  }
  let sorted = list.sort(named, string.compare)
  let items = string.join(list.map(sorted, fn(name) { "type " <> name }), ", ")
  let bit_stream_line =
    "import genesis_prime/message/bit_stream.{" <> items <> "}"
  let bit_stream_import = case string.length(bit_stream_line) > width {
    True -> [
      "import genesis_prime/message/bit_stream.{",
      "  " <> items <> ",",
      "}",
    ]
    False -> [bit_stream_line]
  }
  let modules =
    list.filter_map(fields, fn(field) {
      case field.kind, field.named_values {
        message_schema.ArrayOfRecord(record:, ..), _ ->
          Ok(#(record, camel(record)))
        _, Some(named_values) ->
          Ok(#(values_module(named_values), named_values.type_name))
        _, None -> Error(Nil)
      }
    })
    |> list.unique
    |> list.sort(fn(first, second) { string.compare(first.0, second.0) })
  let module_imports =
    list.flat_map(modules, fn(module) {
      type_import(module: module.0, type_name: module.1)
    })
  list.flatten([bit_stream_import, module_imports, ["import gleam/result", ""]])
}

/// The import of one type from a message module, as `gleam format` lays it
/// out: on one line when it fits, else with the type on a line of its own.
fn type_import(
  module module: String,
  type_name type_name: String,
) -> List(String) {
  let path = "import genesis_prime/message/" <> module <> ".{"
  let item = "type " <> type_name
  case string.length(path <> item <> "}") <= width {
    True -> [path <> item <> "}"]
    False -> [path, "  " <> item <> ",", "}"]
  }
}

fn type_declaration(type_name: String, fields: List(Field)) -> List(String) {
  let declaration = case held(fields) {
    [] -> ["  " <> type_name]
    _ ->
      call(
        indent: 2,
        head: type_name,
        arguments: list.map(held(fields), fn(field) {
          field.name <> ": " <> field_type(field)
        }),
        tail: "",
      )
  }
  list.flatten([["pub type " <> type_name <> " {"], declaration, ["}"]])
}

fn field_type(field: Field) -> String {
  case field.named_values {
    Some(named_values) -> named_values.type_name
    None -> kind_type(field.kind)
  }
}

fn kind_type(kind: Kind) -> String {
  case kind {
    message_schema.Unsigned(..)
    | message_schema.UnsignedBelow(..)
    | message_schema.Float32 -> "Int"
    message_schema.WideText | message_schema.CountedWideText(..) -> "String"
    message_schema.Guid
    | message_schema.RawBytes(..)
    | message_schema.WholeFrame -> "BitArray"
    message_schema.Endpoint -> "Endpoint"
    message_schema.ArrayOfWideText(..) -> "List(String)"
    message_schema.ArrayOfRecord(record:, ..) -> "List(" <> camel(record) <> ")"
    message_schema.ArrayOfUnsigned(..)
    | message_schema.ArrayOfFloat32(..)
    | message_schema.UnsignedArrayCountedBy(..) -> "List(Int)"
    message_schema.Constant(..) -> "Int"
  }
}

/// The fields a generated type holds: every field but the constants, which the
/// encoder writes and the decoder checks.
fn held(fields: List(Field)) -> List(Field) {
  list.filter(fields, fn(field) {
    case field.kind {
      message_schema.Constant(..) -> False
      _ -> True
    }
  })
}

/// The pipeline step that writes a field of the value held in `owner`.
fn write_step(field: Field, owner: String) -> List(String) {
  let name = "\"" <> field.name <> "\""
  let value = case field.named_values {
    Some(named_values) ->
      values_module(named_values)
      <> ".to_value("
      <> owner
      <> "."
      <> field.name
      <> ")"
    None -> owner <> "." <> field.name
  }
  let #(function, arguments) = case field.kind {
    message_schema.Unsigned(bits:) -> #("write_unsigned", [
      name,
      value,
      int.to_string(bits),
    ])
    message_schema.UnsignedBelow(bits:, limit:) -> #("write_unsigned_below", [
      name,
      value,
      int.to_string(bits),
      int.to_string(limit),
    ])
    message_schema.Float32 -> #("write_float32_bits", [name, value])
    message_schema.WideText -> #("write_wide_text", [name, value])
    message_schema.CountedWideText(max_units:) -> #("write_counted_wide_text", [
      name,
      value,
      int.to_string(max_units),
    ])
    message_schema.Guid -> #("write_guid", [name, value])
    message_schema.Endpoint -> #("write_endpoint", [name, value])
    message_schema.RawBytes(count:) -> #("write_raw_bytes", [
      name,
      value,
      int.to_string(count),
    ])
    message_schema.WholeFrame -> #("write_whole_frame", [name, value])
    message_schema.ArrayOfWideText(count_bits:) -> #("write_wide_texts", [
      name,
      value,
      int.to_string(count_bits),
    ])
    message_schema.ArrayOfRecord(count_bits:, record:) -> #("write_array", [
      name,
      value,
      int.to_string(count_bits),
      record <> ".write",
    ])
    message_schema.ArrayOfUnsigned(count_bits:, bits:) -> #(
      "write_unsigned_array",
      [name, value, int.to_string(count_bits), int.to_string(bits)],
    )
    message_schema.ArrayOfFloat32(count_bits:) -> #("write_float32_array", [
      name,
      value,
      int.to_string(count_bits),
    ])
    message_schema.UnsignedArrayCountedBy(counted_by:, bits:) -> #(
      "write_unsigned_array_like",
      [name, value, owner <> "." <> counted_by, int.to_string(bits)],
    )
    message_schema.Constant(bits:, value: constant) -> #("write_constant", [
      name,
      int.to_string(constant),
      int.to_string(bits),
    ])
  }
  call(indent: 2, head: "|> bit_stream." <> function, arguments:, tail: "")
}

/// The `use` line that reads a field and binds it with the reader after it.
fn read_step(field: Field) -> List(String) {
  let #(function, arguments) = case field.kind {
    message_schema.Unsigned(bits:) -> #("read_unsigned", [
      "reader",
      int.to_string(bits),
    ])
    message_schema.UnsignedBelow(bits:, limit:) -> #("read_unsigned_below", [
      "reader",
      "\"" <> field.name <> "\"",
      int.to_string(bits),
      int.to_string(limit),
    ])
    message_schema.Float32 -> #("read_float32_bits", ["reader"])
    message_schema.WideText -> #("read_wide_text", ["reader"])
    message_schema.CountedWideText(max_units:) -> #("read_counted_wide_text", [
      "reader",
      int.to_string(max_units),
    ])
    message_schema.Guid -> #("read_guid", ["reader"])
    message_schema.Endpoint -> #("read_endpoint", ["reader"])
    message_schema.RawBytes(count:) -> #("read_raw_bytes", [
      "reader",
      int.to_string(count),
    ])
    message_schema.WholeFrame -> #("read_whole_frame", ["reader"])
    message_schema.ArrayOfWideText(count_bits:) -> #("read_wide_texts", [
      "reader",
      int.to_string(count_bits),
    ])
    message_schema.ArrayOfRecord(count_bits:, record:) -> #("read_array", [
      "reader",
      int.to_string(count_bits),
      record <> ".read",
    ])
    message_schema.ArrayOfUnsigned(count_bits:, bits:) -> #(
      "read_unsigned_array",
      ["reader", int.to_string(count_bits), int.to_string(bits)],
    )
    message_schema.ArrayOfFloat32(count_bits:) -> #("read_float32_array", [
      "reader",
      int.to_string(count_bits),
    ])
    message_schema.UnsignedArrayCountedBy(counted_by:, bits:) -> #(
      "read_unsigned_array_like",
      ["reader", counted_by, int.to_string(bits)],
    )
    message_schema.Constant(bits:, value:) -> #("read_constant", [
      "reader",
      "\"" <> field.name <> "\"",
      int.to_string(bits),
      int.to_string(value),
    ])
  }
  let pattern = case field.kind {
    message_schema.Constant(..) -> "reader"
    _ -> "#(" <> field.name <> ", reader)"
  }
  let read =
    use_line(pattern:, call_head: "bit_stream." <> function, arguments:)
  case field.named_values {
    Some(named_values) ->
      list.append(read, [
        "  let "
        <> field.name
        <> " = "
        <> values_module(named_values)
        <> ".from_value("
        <> field.name
        <> ")",
      ])
    None -> read
  }
}

fn read_steps(fields: List(Field)) -> List(String) {
  list.flat_map(fields, read_step)
}

fn decode_body(fields: List(Field), type_name: String) -> List(String) {
  case fields {
    [] -> [
      "  bit_stream.new_reader(body)",
      "  |> bit_stream.finish_reading",
      "  |> result.replace(" <> type_name <> ")",
    ]
    _ ->
      list.flatten([
        ["  let reader = bit_stream.new_reader(body)"],
        read_steps(fields),
        ["  use Nil <- result.try(bit_stream.finish_reading(reader))"],
        construct(fields, type_name),
      ])
  }
}

/// `Ok(Name(field:, ..))`, on one line when it fits.
fn construct(fields: List(Field), type_name: String) -> List(String) {
  let labels = list.map(held(fields), fn(field) { field.name <> ":" })
  let one = "  Ok(" <> type_name <> "(" <> string.join(labels, ", ") <> "))"
  case string.length(one) <= width {
    True -> [one]
    False ->
      list.flatten([
        ["  Ok(" <> type_name <> "("],
        list.map(labels, fn(label) { "    " <> label <> "," }),
        ["  ))"],
      ])
  }
}

/// `Ok(#(Name(field:, ..), reader))`, on one line when it fits.
fn construct_with_reader(
  fields: List(Field),
  type_name: String,
) -> List(String) {
  let labels = list.map(held(fields), fn(field) { field.name <> ":" })
  let one =
    "  Ok(#(" <> type_name <> "(" <> string.join(labels, ", ") <> "), reader))"
  case string.length(one) <= width {
    True -> [one]
    False ->
      list.flatten([
        ["  Ok(#("],
        call(indent: 4, head: type_name, arguments: labels, tail: ","),
        ["    reader,", "  ))"],
      ])
  }
}

/// A call on one line when it fits, else one argument to a line.
fn call(
  indent indent: Int,
  head head: String,
  arguments arguments: List(String),
  tail tail: String,
) -> List(String) {
  let margin = string.repeat(" ", indent)
  let one = margin <> head <> "(" <> string.join(arguments, ", ") <> ")" <> tail
  case string.length(one) <= width {
    True -> [one]
    False ->
      list.flatten([
        [margin <> head <> "("],
        list.map(arguments, fn(argument) { margin <> "  " <> argument <> "," }),
        [margin <> ")" <> tail],
      ])
  }
}

/// A `use pattern <- result.try(call(arguments))` as `gleam format` lays it
/// out: on one line when the line without its last parenthesis fits, with the
/// call alone on the next line, or with the call's arguments one to a line.
fn use_line(
  pattern pattern: String,
  call_head call_head: String,
  arguments arguments: List(String),
) -> List(String) {
  let inner = call_head <> "(" <> string.join(arguments, ", ") <> ")"
  let one = "  use " <> pattern <> " <- result.try(" <> inner <> ")"
  let hugging = "  use " <> pattern <> " <- result.try(" <> call_head <> "("
  case string.length(one) <= width + 1, string.length(hugging) <= width {
    True, _ -> [one]
    False, True ->
      list.flatten([
        [hugging],
        list.map(arguments, fn(argument) { "    " <> argument <> "," }),
        ["  ))"],
      ])
    False, False -> [
      "  use " <> pattern <> " <- result.try(",
      "    " <> inner <> ",",
      "  )",
    ]
  }
}

/// A public function's first line, its parameters one to a line when they do
/// not fit.
fn function_head(
  name name: String,
  parameters parameters: List(String),
  returns returns: String,
) -> List(String) {
  let one =
    "pub fn "
    <> name
    <> "("
    <> string.join(parameters, ", ")
    <> ") -> "
    <> returns
    <> " {"
  case string.length(one) <= width {
    True -> [one]
    False ->
      list.flatten([
        ["pub fn " <> name <> "("],
        list.map(parameters, fn(parameter) { "  " <> parameter <> "," }),
        [") -> " <> returns <> " {"],
      ])
  }
}

/// Fills lines up to the width, each starting with the prefix.
fn wrap(prefix: String, text: String) -> List(String) {
  let words = string.split(text, " ")
  let #(lines, last) =
    list.fold(words, #([], prefix), fn(state, word) {
      let #(lines, current) = state
      let next = current <> " " <> word
      case string.length(next) > width && current != prefix {
        True -> #([current, ..lines], prefix <> " " <> word)
        False -> #(lines, next)
      }
    })
  list.reverse([last, ..lines])
}

fn lines_to_text(lines: List(String)) -> String {
  string.join(lines, "\n") <> "\n"
}

fn camel(name: String) -> String {
  string.split(name, "_")
  |> list.map(string.capitalise)
  |> string.join("")
}

fn hex_id(id: Int) -> String {
  "0x" <> string.pad_start(int.to_base16(id), 4, "0")
}
