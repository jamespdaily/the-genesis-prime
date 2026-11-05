//// A decoded message as text with its fields named from the schema. The
//// runtime's inspect prints a record's fields by position only, so the text of
//// each constructor of a message or record the schema holds is given the names
//// of the fields its generated type holds, in order:
////
//// ```
//// UnitCreatePlayer(1, 1, "Tess")  ─▶ UnitCreatePlayer(unit_id: 1, character_id: 1, name: "Tess")
//// ```
////
//// The text is read as the inspect of a Gleam value prints it: a string in
//// double quotes with backslash escapes, a list in `[]`, a tuple in `#()`, a bit
//// array in `<<>>`, and a word (a number, or a constructor with its arguments
//// in `()`). A constructor whose argument count is not its type's field count
//// is printed by position, and text this reading does not take is printed as
//// it is.
////
//// A field the schema says is a float (`float32`, or an array of them) is held
//// as its 32 bits, so its number is followed by the float those bits hold:
////
//// ```
//// UnitFloatStatChanged(4097, 5, 1108082688)  ─▶ ... value: 1108082688 (35.0)
//// ```
////
//// Bits that are infinity or not a number hold no float and print alone.

import genesis_prime/message/float32
import genesis_prime/message_generator.{type ReadFailure, NotASchema, NotRead}
import genesis_prime/message_schema.{type Kind, type Schema}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// The fields of each generated message and record type, by its type name:
/// each field's name and how its value is shown.
pub opaque type Names {
  Names(by_type: Dict(String, List(Shown)))
}

/// A field of a generated type: its name and how its value is shown.
type Shown {
  Shown(name: String, form: Form)
}

/// How a field's value is shown.
type Form {
  /// As the text of the value.
  Plain
  /// A number that holds a float's 32 bits: the number, then the float.
  FloatBits
  /// A list of numbers that each hold a float's 32 bits.
  FloatBitsList
}

fn form_of(kind: Kind) -> Form {
  case kind {
    message_schema.Float32 -> FloatBits
    message_schema.ArrayOfFloat32(..) -> FloatBitsList
    message_schema.Unsigned(..)
    | message_schema.UnsignedBelow(..)
    | message_schema.HalfFloatAtLeast(..)
    | message_schema.WideText
    | message_schema.WideUnits
    | message_schema.CountedWideText(..)
    | message_schema.Guid
    | message_schema.Endpoint
    | message_schema.RawBytes(..)
    | message_schema.WholeFrame
    | message_schema.ArrayOfWideText(..)
    | message_schema.ArrayOfRecord(..)
    | message_schema.ArrayOfUnsigned(..)
    | message_schema.UnsignedArrayCountedBy(..)
    | message_schema.ArrayOfRecordCountedBy(..)
    | message_schema.Constant(..)
    | message_schema.OneRecord(..) -> Plain
  }
}

/// The field names of every message and record of the schema file the codec
/// is generated from, read from the repository's root.
pub fn from_schema_file() -> Result(Names, ReadFailure) {
  let path = message_generator.schema_path
  use text <- result.try(
    simplifile.read(path) |> result.map_error(NotRead(path:, error: _)),
  )
  message_schema.parse(text)
  |> result.map(names)
  |> result.map_error(NotASchema(path:, error: _))
}

/// The field names of every message and record of the schema.
fn names(schema: Schema) -> Names {
  let messages =
    list.map(schema.messages, fn(message) {
      #(message.name, message_schema.held(message.fields))
    })
  let records =
    list.map(schema.records, fn(record) {
      #(record.name, message_schema.held(record.fields))
    })
  list.append(messages, records)
  |> list.map(fn(entry) {
    #(
      message_schema.type_name(entry.0),
      list.map(entry.1, fn(field) {
        Shown(name: field.name, form: form_of(field.kind))
      }),
    )
  })
  |> dict.from_list
  |> Names
}

/// The inspected text of a constructor of one argument, such as a dispatch
/// module's variant, as its argument's text with its fields named.
pub fn inside(text text: String, names names: Names) -> String {
  case value(string.to_graphemes(text)) {
    Ok(#(Call(arguments: [argument], ..), [])) -> render(argument, names)
    Ok(#(_, _)) | Error(Nil) -> text
  }
}

/// A value of the inspected text, read.
type Node {
  /// A number or a constructor with no arguments, or a string or bit array,
  /// kept as written.
  Word(text: String)
  /// A constructor with its arguments; `#` for a tuple.
  Call(head: String, arguments: List(Node))
  ListOf(items: List(Node))
}

fn value(characters: List(String)) -> Result(#(Node, List(String)), Nil) {
  case characters {
    ["\"", ..rest] -> quoted(rest, ["\""])
    ["[", ..rest] ->
      items(characters: rest, close: "]", read: [])
      |> result.map(fn(read) { #(ListOf(read.0), read.1) })
    ["#", "(", ..rest] ->
      items(characters: rest, close: ")", read: [])
      |> result.map(fn(read) { #(Call("#", read.0), read.1) })
    ["<", "<", ..rest] -> bits(rest, ["<", "<"])
    _ -> {
      let #(word, rest) = word(characters, [])
      case word, rest {
        "", _ -> Error(Nil)
        _, ["(", ..after] ->
          items(characters: after, close: ")", read: [])
          |> result.map(fn(read) { #(Call(word, read.0), read.1) })
        _, _ -> Ok(#(Word(word), rest))
      }
    }
  }
}

/// The items of a list or the arguments of a call, up to `close`.
fn items(
  characters characters: List(String),
  close close: String,
  read read: List(Node),
) -> Result(#(List(Node), List(String)), Nil) {
  case characters, read {
    [first, ..rest], [] if first == close -> Ok(#([], rest))
    _, _ -> {
      use #(item, rest) <- result.try(value(characters))
      let read = [item, ..read]
      case rest {
        [",", " ", ..after] -> items(characters: after, close:, read:)
        [last, ..after] if last == close -> Ok(#(list.reverse(read), after))
        _ -> Error(Nil)
      }
    }
  }
}

fn quoted(
  characters: List(String),
  kept: List(String),
) -> Result(#(Node, List(String)), Nil) {
  case characters {
    ["\\", escaped, ..rest] -> quoted(rest, [escaped, "\\", ..kept])
    ["\"", ..rest] ->
      Ok(#(Word(string.concat(list.reverse(["\"", ..kept]))), rest))
    [character, ..rest] -> quoted(rest, [character, ..kept])
    [] -> Error(Nil)
  }
}

fn bits(
  characters: List(String),
  kept: List(String),
) -> Result(#(Node, List(String)), Nil) {
  case characters {
    [">", ">", ..rest] ->
      Ok(#(Word(string.concat(list.reverse([">", ">", ..kept]))), rest))
    [character, ..rest] -> bits(rest, [character, ..kept])
    [] -> Error(Nil)
  }
}

/// The characters up to the next that ends a word.
fn word(
  characters: List(String),
  kept: List(String),
) -> #(String, List(String)) {
  case characters {
    [character, ..rest] ->
      case list.contains(["(", ")", "[", "]", ",", " ", "\""], character) {
        True -> #(string.concat(list.reverse(kept)), characters)
        False -> word(rest, [character, ..kept])
      }
    [] -> #(string.concat(list.reverse(kept)), [])
  }
}

fn render(node: Node, names: Names) -> String {
  case node {
    Word(text:) -> text
    ListOf(items:) ->
      "[" <> string.join(list.map(items, render(_, names)), ", ") <> "]"
    Call(head:, arguments:) -> {
      let fields = dict.get(names.by_type, head) |> result.unwrap([])
      let shown = case list.length(fields) == list.length(arguments) {
        True ->
          list.map2(fields, arguments, fn(field, argument) {
            field.name
            <> ": "
            <> render_field(node: argument, form: field.form, names:)
          })
        False -> list.map(arguments, render(_, names))
      }
      head <> "(" <> string.join(shown, ", ") <> ")"
    }
  }
}

/// The text of a field's value, with the float its bits hold after each number
/// of a float field.
fn render_field(
  node node: Node,
  form form: Form,
  names names: Names,
) -> String {
  case form, node {
    FloatBits, Word(text:) -> text <> float_after(text)
    FloatBitsList, ListOf(items:) ->
      "["
      <> string.join(
        list.map(items, fn(item) {
          render_field(node: item, form: FloatBits, names:)
        }),
        ", ",
      )
      <> "]"
    FloatBits, Call(..)
    | FloatBits, ListOf(..)
    | FloatBitsList, Word(..)
    | FloatBitsList, Call(..)
    | Plain, Word(..)
    | Plain, Call(..)
    | Plain, ListOf(..)
    -> render(node, names)
  }
}

/// ` (35.0)` for the text of a number whose 32 bits hold the float 35.0, and
/// nothing for a text that is no such number.
fn float_after(text: String) -> String {
  case
    int.parse(text)
    |> result.try(float32.bits)
    |> result.try(float32.value)
  {
    Ok(held) -> " (" <> float.to_string(held) <> ")"
    Error(Nil) -> ""
  }
}
