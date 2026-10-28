//// Which table's id a column holds, read from the column's name. A column
//// holds the id of a table when its snake-case name is the table's
//// snake-case name, `_id`, and then the end of the name, a digit or an
//// underscore: `spell4_id_attack_primary00` holds Spell4 ids and
//// `localized_text_id` LocalizedText ids. When more than one table's name fits,
//// the longest wins.

import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// A table the generator knows: its snake-case name, as it appears in a
/// column's name, and its type name.
pub type Table {
  Table(snake: String, type_name: String)
}

/// The table whose id the column holds, or an error when the column's name
/// follows no table's name with `_id`.
pub fn referenced_table(
  column column: String,
  tables tables: List(Table),
) -> Result(Table, Nil) {
  tables
  |> list.filter(fn(table) { holds_id_of(column:, snake: table.snake) })
  |> list.sort(fn(first, second) {
    int.compare(string.length(second.snake), string.length(first.snake))
  })
  |> list.first
}

fn holds_id_of(column column: String, snake snake: String) -> Bool {
  let prefix = snake <> "_id"
  case string.starts_with(column, prefix) {
    False -> False
    True ->
      case
        string.pop_grapheme(string.drop_start(column, string.length(prefix)))
      {
        Error(Nil) -> True
        Ok(#("_", _)) -> True
        Ok(#(next, _)) -> result.is_ok(int.parse(next))
      }
  }
}

/// Whether the column's name has the word `id` in it, as `id` alone or with
/// digits after it: a column that names an id of some table.
pub fn names_an_id(column: String) -> Bool {
  string.split(column, "_")
  |> list.any(fn(word) {
    word == "id"
    || {
      string.starts_with(word, "id") && is_number(string.drop_start(word, 2))
    }
  })
}

fn is_number(text: String) -> Bool {
  string.to_graphemes(text)
  |> list.all(fn(grapheme) { result.is_ok(int.parse(grapheme)) })
  && text != ""
}
