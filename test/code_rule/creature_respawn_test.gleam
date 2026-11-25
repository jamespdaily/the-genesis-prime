//// A creature's next life is its map's, never its own process's. Expected value is the
//// rule (Design run A, 4.1): a creature that lay dead until its corpse timer tells its map
//// it expired and stops, so no creature module holds a time it stood again at, a check of
//// a tell against it, a fight or guard input for standing again, or a function that shows
//// it again in place. A name of the in-process respawn in the world map's folder is a
//// breach, reported at its line. The rule is shown on a planted file, then read over the
//// real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

const world_map_directory = "src/genesis_prime/world_map"

/// The names of the creature's in-process respawn: the time it stood again at, the check of
/// a tell against it, the corpse timer's outcome, the fight's and the guard's inputs for it,
/// and the function that showed the creature again.
const stood_again_names = [
  "stood_again_ms", "struck_before_this_life", "StandsAgain", "StoodAgain",
  "Stands", "shown_again",
]

/// Whether a character belongs to a name.
fn is_name_character(character: String) -> Bool {
  case character {
    "_" -> True
    _ ->
      string.lowercase(character) != string.uppercase(character)
      || is_digit(character)
  }
}

fn is_digit(character: String) -> Bool {
  case int.parse(character) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

/// Whether the text holds `word` as a name: not as a part of a longer one.
fn names_word(text text: String, word word: String) -> Bool {
  case string.split(text, word) {
    [] | [_] -> False
    [first, ..rest] -> follows_as_a_name(before: first, parts: rest)
  }
}

fn follows_as_a_name(before before: String, parts parts: List(String)) -> Bool {
  case parts {
    [] -> False
    [part, ..later] -> {
      let ends_a_name = case list.last(string.to_graphemes(before)) {
        Ok(character) -> is_name_character(character)
        Error(Nil) -> False
      }
      let starts_a_name = case string.to_graphemes(part) {
        [character, ..] -> is_name_character(character)
        [] -> False
      }
      case ends_a_name || starts_a_name {
        False -> True
        True -> follows_as_a_name(before: part, parts: later)
      }
    }
  }
}

/// The lines of the file that name one of the in-process respawn's names, each with the
/// line's number.
fn stands_again_in(file file: SourceFile) -> List(Int) {
  string.split(file.text, "\n")
  |> list.index_map(fn(line, index) { #(index + 1, line) })
  |> list.filter(fn(numbered) {
    list.any(stood_again_names, fn(word) { names_word(text: numbered.1, word:) })
  })
  |> list.map(fn(numbered) { numbered.0 })
}

pub fn a_creature_never_stands_again_in_its_own_process_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: world_map_directory <> "/creature.gleam", lines: [
      "fn corpse() {",
      "  StandsAgain(life:) -> stood_again(state:, now_ms:)",
      "}",
      "",
      "fn fight() {",
      "  creature_fight.StoodAgain",
      "}",
      "",
      "fn guard() {",
      "  creature_guard.Stands",
      "}",
      "",
      "fn tells() {",
      "  struck_before_this_life(state:, struck_at_ms:)",
      "}",
      "",
      "fn shown() {",
      "  shown_again(state:)",
      "}",
      "",
      "fn the_time() {",
      "  State(..state, stood_again_ms: Some(now_ms))",
      "}",
      "",
      "fn other_names() {",
      "  NameStands -> Expires",
      "  my_stood_again_ms",
      "}",
    ])
  assert stands_again_in(file: planted_file) == [2, 6, 10, 14, 18, 22]
    as "each name of the in-process respawn is found at its line, and a longer name that holds one is not"
  assert list.flat_map(source.files(under: world_map_directory), fn(file) {
      list.map(stands_again_in(file:), fn(line) {
        file.path <> ":" <> int.to_string(line)
      })
    })
    == []
    as "no module of the world map holds a creature that stands again in its own process"
}
