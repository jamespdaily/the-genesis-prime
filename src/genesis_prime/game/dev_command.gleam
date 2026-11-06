//// The development chat commands: a Say line that starts with `!`, read as a
//// command when the setting `dev_commands` is on (genesis_prime/game_settings),
//// and a Say line as any other when it is off. A server choice: a test tool for
//// the play container, so a tester can start a creature without a database
//// edit; every command reaches the client as the Say line it sent and a system
//// line the server answers it with.
////
//// ```
//// Say "!summon 75048"  ─▶ chat: setting on, channel Say, text starts with `!`
////                          parse ─▶ Summon(Creature2Id 75048) ─▶ chat.AskSummon ─▶ the connection asks the map
////                          parse ─▶ Refusal                   ─▶ one system line (`describe`)
//// ```
////
//// - **The grammar** is `!` then a word, then its arguments, split at spaces.
////   `summon` takes one whole decimal number, a Creature2 id; the word is read
////   as typed, in lower case.
//// - **A word with no command**, and a command whose arguments are not what it
////   takes, are each answered with a system line, never as a Say line, so a
////   mistyped command is not said aloud to the players who see the speaker.

import genesis_prime/table/id.{type Creature2Id, Creature2Id}
import gleam/list
import gleam/result

/// A development command.
pub type Command {
  /// `!summon <Creature2 id>`: start that creature at the player's place and
  /// facing as a run-only spawn (genesis_prime/world_map/map `Summon`).
  Summon(creature2_id: Creature2Id)
}

/// Why a `!` line is no command.
pub type Refusal {
  /// The word after `!` is no command.
  UnknownCommand
  /// The word is `summon`, but what follows is not exactly one whole number.
  SummonTakesACreature2Id
}

/// Whether the text is a command line: its first UTF-16 unit is `!`.
pub fn is_command(text text: List(Int)) -> Bool {
  case text {
    [0x21, ..] -> True
    _ -> False
  }
}

/// The command a `!` line holds, or why it holds none.
pub fn parse(text text: List(Int)) -> Result(Command, Refusal) {
  case words(units: text, word: [], found: []) {
    [command, ..arguments] if command == summon_word ->
      case arguments {
        [argument] ->
          decimal(units: argument)
          |> result.map(fn(number) { Summon(creature2_id: Creature2Id(number)) })
          |> result.replace_error(SummonTakesACreature2Id)
        [] | [_, _, ..] -> Error(SummonTakesACreature2Id)
      }
    [_, ..] | [] -> Error(UnknownCommand)
  }
}

/// `!summon` as the UTF-16 units the client sends.
const summon_word = [0x21, 0x73, 0x75, 0x6D, 0x6D, 0x6F, 0x6E]

/// The words of the units, split at spaces (0x20), in order: a run of spaces is
/// one split, and spaces at either end hold no word.
fn words(
  units units: List(Int),
  word word: List(Int),
  found found: List(List(Int)),
) -> List(List(Int)) {
  case units, word {
    [], [] -> list.reverse(found)
    [], [_, ..] -> list.reverse([list.reverse(word), ..found])
    [0x20, ..rest], [] -> words(units: rest, word: [], found:)
    [0x20, ..rest], [_, ..] ->
      words(units: rest, word: [], found: [list.reverse(word), ..found])
    [unit, ..rest], _ -> words(units: rest, word: [unit, ..word], found:)
  }
}

/// The whole number the units spell in decimal: ASCII digits only, at least
/// one, so no sign, fraction, prefix or other script's digit.
fn decimal(units units: List(Int)) -> Result(Int, Nil) {
  case units {
    [] -> Error(Nil)
    [_, ..] ->
      list.try_fold(units, 0, fn(number, unit) {
        case unit >= 0x30 && unit <= 0x39 {
          True -> Ok(number * 10 + unit - 0x30)
          False -> Error(Nil)
        }
      })
  }
}

/// The text of the system line that answers a refused command.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    UnknownCommand -> "unknown command"
    SummonTakesACreature2Id ->
      "!summon takes one Creature2 id, as !summon 75048"
  }
}
