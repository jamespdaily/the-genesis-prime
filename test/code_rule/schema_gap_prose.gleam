//// A gap of a message is a `gaps` entry of the schema, which the generator writes as
//// the module's `gaps()`, so the coverage measure prints it. The prose of the schema
//// (a message's, record's or union's `summary`, the `open` question of a field or a
//// variant, and the `question` of an open tag) says what the client does and never
//// states a gap.
////
//// ```text
//// schema.toml lines -> text after a prose key -> those with the word gap -> breaches
//// ```
////
//// - A prose key is `summary = "`, `open = "` or `question = "`; a field's `open` sits
////   inside an inline table, so the key is found anywhere on the line, and the text read
////   is what follows it to the end of the line.
//// - The word is `gap` or `gaps` in any case, with no letter beside it. The entry key
////   `gaps = [` and the entries' own sentences are not prose.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import gleam/string

const rule_name = "a schema text that states a gap in prose"

const prose_keys = ["summary = \"", "open = \"", "question = \""]

/// Each line of the schema file whose prose holds the word gap, at its line.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  file.text
  |> string.split("\n")
  |> list.index_map(fn(text, index) { #(index + 1, text) })
  |> list.filter_map(fn(numbered) {
    let #(line, text) = numbered
    case list.any(prose_after_keys(text), says_gap) {
      True -> Ok(Breach(path: file.path, line:, rule: rule_name))
      False -> Error(Nil)
    }
  })
}

/// What follows each prose key found on the line.
fn prose_after_keys(text: String) -> List(String) {
  list.filter_map(prose_keys, fn(key) {
    case string.split_once(text, key) {
      Ok(#(_, prose)) -> Ok(prose)
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Whether the text holds the word gap or gaps, in any case, with no letter beside it.
fn says_gap(text: String) -> Bool {
  text
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(grapheme) {
    case string.contains("abcdefghijklmnopqrstuvwxyz", grapheme) {
      True -> grapheme
      False -> " "
    }
  })
  |> string.concat
  |> string.split(" ")
  |> list.any(fn(word) { word == "gap" || word == "gaps" })
}
