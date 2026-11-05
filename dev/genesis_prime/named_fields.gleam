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

import genesis_prime/message_generator.{type ReadFailure, NotASchema, NotRead}
import genesis_prime/message_schema.{type Schema}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// The field names of each generated message and record type, by its type
/// name.
pub opaque type Names {
  Names(by_type: Dict(String, List(String)))
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
      list.map(entry.1, fn(field) { field.name }),
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
      let rendered = list.map(arguments, render(_, names))
      let fields = dict.get(names.by_type, head) |> result.unwrap([])
      let shown = case list.length(fields) == list.length(rendered) {
        True ->
          list.map2(fields, rendered, fn(field, text) { field <> ": " <> text })
        False -> rendered
      }
      head <> "(" <> string.join(shown, ", ") <> ")"
    }
  }
}
