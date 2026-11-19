//// The development chat commands: a Say line that starts with `!`, read as a
//// command when the setting `dev_commands` is on (genesis_prime/game_settings),
//// and a Say line as any other when it is off. A server choice: a test tool for
//// the play container, so a tester can start a creature without a database
//// edit; every command reaches the client as the Say line it sent and a system
//// line the server answers it with.
////
//// ```
//// Say "!level 4" ─▶ chat: setting on, channel Say, text starts with `!`
////                   parse ─▶ RaiseToLevel(4) ─▶ checked(tables) ─▶ chat.RunCommand ─▶ the connection runs it
////                   parse or checked ─▶ Refusal                 ─▶ one system line (`describe`)
//// ```
////
//// - **The grammar** is `!` then a word, then its arguments, split at spaces.
////   `summon` takes one whole decimal number, a Creature2 id, and then
////   optionally a second, the level; the word is read as typed, in lower case.
////   Whether a CreatureLevel row has the level is the map's check.
////   `level` takes one whole decimal number, a level, and `xp` one, a total
////   experience; a number has any length, so the tables refuse one too large.
//// - **The tables' refusals** are `checked`'s: a level outside 1 to the highest
////   level (GameFormula 145 dataint0) and an experience above the highest
////   level's minXpForLevel (its XpPerLevel row), compared as whole numbers.
//// - **A word with no command**, and a command whose arguments are not what it
////   takes, are each answered with a system line, never as a Say line, so a
////   mistyped command is not said aloud to the players who see the speaker.

import genesis_prime/game/level
import genesis_prime/table/id.{
  type Creature2Id, type CurrencyTypeId, Creature2Id, XpPerLevelId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A development command.
pub type Command {
  /// `!summon <Creature2 id>` or `!summon <Creature2 id> <level>`: start that
  /// creature at the player's place and facing as a run-only spawn
  /// (genesis_prime/world_map/map `Summon`), at the level when there is one and
  /// else at its own minLevel.
  Summon(creature2_id: Creature2Id, level: Option(Int))
  /// `!level <n>`: raise the player's experience to the least that level has
  /// (XpPerLevel minXpForLevel), with the client's own gain and level rise.
  RaiseToLevel(level: Int)
  /// `!xp <total>`: raise the player's experience to that total, with the
  /// client's own gain and, when it crosses a level, level rise.
  RaiseToExperience(experience: Int)
  /// `!currency <type> <amount>`: set the player's total of that currency to the
  /// amount, saved at once (genesis_prime/store `SetCurrency`), and give the client
  /// the new total (`opcode.0x919`). The total may be lower than the one held.
  SetCurrency(currency_type_id: CurrencyTypeId, amount: Int)
}

/// A `!currency` total asked of the store, kept while its answer is awaited: the
/// currency type and the total the player held before it, from which the answer's
/// frames and line are made. The new total is the answer's.
pub type Grant {
  Grant(currency_type_id: Int, held: Int)
}

/// Why a `!` line is no command.
pub type Refusal {
  /// The word after `!` is no command.
  UnknownCommand
  /// The word is `summon`, but what follows is not a whole number for the
  /// Creature2 id, or one and a level, and nothing more.
  SummonTakesACreature2Id
  /// The word is `summon` with a Creature2 id, and its second word is not a whole
  /// number.
  SummonLevelIsNotAWholeNumber
  /// The word is `level`, but what follows is not one whole number.
  LevelTakesAWholeNumber
  /// The word is `xp`, but what follows is not one whole number.
  ExperienceTakesAWholeNumber
  /// The level is below 1 or above `highest`, the highest level.
  LevelOutOfRange(level: Int, highest: Int)
  /// The experience is above `highest`, the highest level's minXpForLevel.
  ExperienceOutOfRange(experience: Int, highest: Int)
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
        [creature] -> summon(creature:, level: None)
        [creature, level] ->
          case decimal(units: creature), decimal(units: level) {
            Ok(number), Ok(level) ->
              Ok(Summon(creature2_id: Creature2Id(number), level: Some(level)))
            Ok(_), Error(Nil) -> Error(SummonLevelIsNotAWholeNumber)
            Error(Nil), _ -> Error(SummonTakesACreature2Id)
          }
        [] | [_, _, _, ..] -> Error(SummonTakesACreature2Id)
      }
    [command, ..arguments] if command == level_word ->
      case arguments {
        [level] ->
          decimal(units: level)
          |> result.map(RaiseToLevel)
          |> result.replace_error(LevelTakesAWholeNumber)
        [] | [_, _, ..] -> Error(LevelTakesAWholeNumber)
      }
    [command, ..arguments] if command == experience_word ->
      case arguments {
        [experience] ->
          decimal(units: experience)
          |> result.map(RaiseToExperience)
          |> result.replace_error(ExperienceTakesAWholeNumber)
        [] | [_, _, ..] -> Error(ExperienceTakesAWholeNumber)
      }
    [_, ..] | [] -> Error(UnknownCommand)
  }
}

/// The command the tables allow, or the refusal that names what they do not
/// hold: a level outside 1 to the highest level and an experience above the
/// highest level's minXpForLevel, compared as whole numbers so a number of any
/// length is a refusal.
pub fn checked(
  command command: Command,
  tables tables: table_store.Tables,
) -> Result(Command, Refusal) {
  case command {
    Summon(..) -> Ok(command)
    RaiseToLevel(level:) -> {
      let assert Ok(highest) = level.highest_level(tables)
        as "the load requires GameFormula row 145"
      case level >= 1 && level <= highest {
        True -> Ok(command)
        False -> Error(LevelOutOfRange(level:, highest:))
      }
    }
    RaiseToExperience(experience:) -> {
      let assert Ok(highest_level) = level.highest_level(tables)
        as "the load requires GameFormula row 145"
      let assert Ok(top) =
        xp_per_level.get(tables:, id: XpPerLevelId(highest_level))
        as "the load requires the XpPerLevel row of the highest level"
      case experience <= top.min_xp_for_level {
        True -> Ok(command)
        False ->
          Error(ExperienceOutOfRange(experience:, highest: top.min_xp_for_level))
      }
    }
    SetCurrency(..) ->
      panic as "the tables' refusals of !currency are not written"
  }
}

/// The summon of the creature the units spell, at the level when there is one.
fn summon(
  creature creature: List(Int),
  level level: Option(Int),
) -> Result(Command, Refusal) {
  decimal(units: creature)
  |> result.map(fn(number) { Summon(creature2_id: Creature2Id(number), level:) })
  |> result.replace_error(SummonTakesACreature2Id)
}

/// `!summon` as the UTF-16 units the client sends.
const summon_word = [0x21, 0x73, 0x75, 0x6D, 0x6D, 0x6F, 0x6E]

/// `!level` as the UTF-16 units the client sends.
const level_word = [0x21, 0x6C, 0x65, 0x76, 0x65, 0x6C]

/// `!xp` as the UTF-16 units the client sends.
const experience_word = [0x21, 0x78, 0x70]

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
      "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3"
    SummonLevelIsNotAWholeNumber ->
      "!summon's level is a whole number, as !summon 75048 3"
    LevelTakesAWholeNumber ->
      "!level takes one whole number, a level, as !level 10"
    ExperienceTakesAWholeNumber ->
      "!xp takes one whole number, a total experience, as !xp 2860"
    LevelOutOfRange(level:, highest:) ->
      "!level "
      <> int.to_string(level)
      <> " is outside the levels 1 to "
      <> int.to_string(highest)
    ExperienceOutOfRange(experience:, highest:) ->
      "!xp "
      <> int.to_string(experience)
      <> " is above the experience of the highest level, "
      <> int.to_string(highest)
  }
}
