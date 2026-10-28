//// Which table's id a column holds, read from the column's name. A column
//// holds the id of a table when its snake-case name is the table's
//// snake-case name, `_id`, and then the end of the name, a digit or an
//// underscore: `spell4_id_attack_primary00` holds Spell4 ids and
//// `localized_text_id` LocalizedText ids. When more than one table's name fits,
//// the longest wins.

import gleam/dict.{type Dict}
import gleam/list
import gleam/string

/// A table the generator knows: its snake-case name, as it appears in a
/// column's name, and its type name.
pub type Table {
  Table(snake: String, type_name: String)
}

/// The tables by their snake-case names, which `referenced_table` looks up.
pub fn index(tables: List(Table)) -> Dict(String, Table) {
  list.map(tables, fn(table) { #(table.snake, table) }) |> dict.from_list
}

/// The table whose id the column holds, or an error when the column's name
/// follows no table's name with `_id`. Only the starts of the name that end
/// before an id word are looked up, longest first.
pub fn referenced_table(
  column column: String,
  tables tables: Dict(String, Table),
) -> Result(Table, Nil) {
  let words = string.split(column, "_")
  case list.any(words, is_id_word) {
    False -> Error(Nil)
    True ->
      starts_before_id_words(words:, before: [], starts: [])
      |> list.find_map(dict.get(tables, _))
  }
}

/// The starts of the name that stop before an id word, as snake case, the
/// longest first. `before` holds the words already passed, in reverse.
fn starts_before_id_words(
  words words: List(String),
  before before: List(String),
  starts starts: List(String),
) -> List(String) {
  case words {
    [] -> starts
    [word, ..rest] -> {
      let starts = case before != [] && is_id_word(word) {
        True -> [string.join(list.reverse(before), "_"), ..starts]
        False -> starts
      }
      starts_before_id_words(words: rest, before: [word, ..before], starts:)
    }
  }
}

/// Whether the column's name has the word `id` in it, alone or with a digit
/// after it: a column that names an id of some table.
pub fn names_an_id(column: String) -> Bool {
  string.split(column, "_") |> list.any(is_id_word)
}

/// `id`, or `id` and a digit and whatever follows it, as in `id00`.
fn is_id_word(word: String) -> Bool {
  case string.to_graphemes(word) {
    ["i", "d"] -> True
    ["i", "d", digit, ..] -> string.contains("0123456789", digit)
    _ -> False
  }
}
