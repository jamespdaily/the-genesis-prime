//// The required-value rule: no code line of a play script says `${name:?word}`
//// or `${name?word}`, the expansion `/bin/bash` 3.2 (what launchd runs on a
//// Mac) ends with status 0 in a script that sets an EXIT trap, because the
//// trap already sees `$?` as 0. A script refuses a missing value with
//// `refuse` of `dev/play_service/lib.sh`, which ends with status 1.
////
//// ```text
//// file lines (comments skipped) -> split at "${" -> name, then "?" or ":?" -> breaches
//// ```
////
//// - A line whose first mark is `#` is a comment and is not read.
//// - After `${` come an optional `!` and the name's letters, digits and `_`;
////   a `?` next, or a `:` and then `?`, is the breach. `${x:-y}`, `${x:+y}`,
////   `${#x}` and `${x}` are not.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import gleam/string

const rule_name =
  "a ${name:?word} expansion, which bash 3.2 ends with status 0 under an EXIT trap"

/// Each code line of the file that holds a `${name:?` or `${name?` expansion.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  file.text
  |> string.split("\n")
  |> list.index_map(fn(text, index) { #(index + 1, text) })
  |> list.filter(fn(numbered) {
    let #(_, text) = numbered
    !string.starts_with(string.trim_start(text), "#") && requires_a_value(text)
  })
  |> list.map(fn(numbered) {
    Breach(path: file.path, line: numbered.0, rule: rule_name)
  })
}

fn requires_a_value(text: String) -> Bool {
  text
  |> string.split("${")
  |> list.drop(1)
  |> list.any(fn(after) {
    let after = case string.starts_with(after, "!") {
      True -> string.drop_start(after, 1)
      False -> after
    }
    case string.to_graphemes(drop_name(after)) {
      ["?", ..] -> True
      [":", "?", ..] -> True
      _ -> False
    }
  })
}

/// The text after the leading letters, digits and underscores.
fn drop_name(text: String) -> String {
  case string.pop_grapheme(text) {
    Ok(#(grapheme, rest)) ->
      case
        string.contains(
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
          grapheme,
        )
      {
        True -> drop_name(rest)
        False -> text
      }
    Error(Nil) -> text
  }
}
