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
////   `go` takes a World id, a WorldZone id and x, y, z (each coordinate with an
////   optional leading `-`), or one WorldLocation2 id.
////   `quest` takes one whole decimal number, a Quest2 id, and the word `done`.
//// - **The tables' refusals** are `checked`'s: a level outside 1 to the highest
////   level (GameFormula 145 dataint0), an experience above the highest
////   level's minXpForLevel (its XpPerLevel row), compared as whole numbers, a
////   quest with no Quest2 row (the client refuses a quest it has no row for,
////   FindQuestById 0xa00b0001); for `go`, a World, WorldZone or WorldLocation2 id
////   with no row and a position outside the box the client clamps a unit's drawn
////   position to (x and z -32768 to 32768, y -2048 to 2048, `0x1405b5070`),
////   compared as whole numbers so a number of any length is a refusal. A named
////   place is checked by its row's own world, zone and position, as a coordinate
////   place is.
//// - **A word with no command**, and a command whose arguments are not what it
////   takes, are each answered with a system line, never as a Say line, so a
////   mistyped command is not said aloud to the players who see the speaker.

import genesis_prime/game/level
import genesis_prime/game/start_place
import genesis_prime/table/id.{
  type Creature2Id, type Quest2Id, Creature2Id, Quest2Id, WorldId,
  WorldLocation2Id, WorldZoneId, XpPerLevelId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/world
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import genesis_prime/table/xp_per_level
import gleam/float
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
  /// `!go <World id> <WorldZone id> <x> <y> <z>` or `!go <WorldLocation2 id>`:
  /// place the player at once at that place.
  Go(destination: Destination)
  /// `!quest <Quest2 id> done`: complete that quest in the player's log, with the
  /// follow-ups a turn-in's completion has and none of the quest's own rewards.
  CompleteQuest(quest2_id: Quest2Id)
}

/// Where a `!go` places the player.
pub type Destination {
  /// A World, a WorldZone and a position, each coordinate a whole number of any
  /// length until `checked` has compared it with the box.
  Coordinates(world_id: Int, world_zone_id: Int, x: Int, y: Int, z: Int)
  /// The place a WorldLocation2 row holds: its world, zone, position and facing.
  Named(world_location2_id: Int)
}

/// One of the three axes of a position.
pub type Axis {
  AxisX
  AxisY
  AxisZ
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
  /// The word is `go`, but what follows is not a World id, a WorldZone id and
  /// three coordinates, or one WorldLocation2 id.
  GoTakesAPlace
  /// No World row has the id.
  WorldHasNoRow(world_id: Int)
  /// No WorldZone row has the id.
  WorldZoneHasNoRow(world_zone_id: Int)
  /// No WorldLocation2 row has the id.
  WorldLocation2HasNoRow(world_location2_id: Int)
  /// The coordinate on `axis`, whole, is outside the box the client clamps a
  /// unit's drawn position to.
  PositionOutsideTheBox(axis: Axis, coordinate: Int)
  /// The word is `quest`, but what follows is not one whole number and the word
  /// `done`, and nothing more.
  QuestTakesAQuest2IdAndDone
  /// The quest has no Quest2 row.
  NoQuest2Row(quest2_id: Quest2Id)
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
    [command, ..arguments] if command == go_word ->
      case arguments {
        [location] ->
          decimal(units: location)
          |> result.map(fn(id) {
            Go(destination: Named(world_location2_id: id))
          })
          |> result.replace_error(GoTakesAPlace)
        [world_id, world_zone_id, x, y, z] ->
          case
            decimal(units: world_id),
            decimal(units: world_zone_id),
            signed_decimal(units: x),
            signed_decimal(units: y),
            signed_decimal(units: z)
          {
            Ok(world_id), Ok(world_zone_id), Ok(x), Ok(y), Ok(z) ->
              Ok(
                Go(destination: Coordinates(
                  world_id:,
                  world_zone_id:,
                  x:,
                  y:,
                  z:,
                )),
              )
            _, _, _, _, _ -> Error(GoTakesAPlace)
          }
        [] | [_, _] | [_, _, _] | [_, _, _, _] | [_, _, _, _, _, ..] ->
          Error(GoTakesAPlace)
      }
    [command, ..arguments] if command == quest_word ->
      case arguments {
        [quest, done] if done == done_word ->
          decimal(units: quest)
          |> result.map(fn(number) {
            CompleteQuest(quest2_id: Quest2Id(number))
          })
          |> result.replace_error(QuestTakesAQuest2IdAndDone)
        [] | [_] | [_, _] | [_, _, _, ..] -> Error(QuestTakesAQuest2IdAndDone)
      }
    [_, ..] | [] -> Error(UnknownCommand)
  }
}

/// The command the tables allow, or the refusal that names what they do not
/// hold: a level outside 1 to the highest level, an experience above the
/// highest level's minXpForLevel, compared as whole numbers so a number of any
/// length is a refusal; for a `!go`, a World, WorldZone or WorldLocation2 with no
/// row, and a position outside the box, in that order; for a `!quest`, a quest with
/// no Quest2 row.
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
    Go(destination:) ->
      go_refusal(destination:, tables:)
      |> option.map(Error)
      |> option.unwrap(Ok(command))
    CompleteQuest(quest2_id:) ->
      case quest2.get(tables:, id: quest2_id) {
        Ok(_) -> Ok(command)
        Error(Nil) -> Error(NoQuest2Row(quest2_id:))
      }
  }
}

/// The place `destination` names for a player facing `facing`: the position as
/// given with that facing for coordinates, the row's own facing for a named place.
/// A destination `checked` allowed always has a place; the refusal is the one
/// `checked` gives for what the place lacks.
pub fn place_of(
  destination destination: Destination,
  facing facing: start_place.Facing,
  tables tables: table_store.Tables,
) -> Result(start_place.Place, Refusal) {
  case destination {
    Coordinates(world_id:, world_zone_id:, x:, y:, z:) ->
      start_place.place(
        world_id:,
        world_zone_id:,
        x: int.to_float(x),
        y: int.to_float(y),
        z: int.to_float(z),
        facing:,
      )
      |> result.replace_error(WorldHasNoRow(world_id:))
    Named(world_location2_id:) -> {
      use row <- result.try(named_row(world_location2_id:, tables:))
      start_place.of_row(row:)
      |> result.replace_error(WorldHasNoRow(world_id: row.world_id))
    }
  }
}

/// The first refusal of a `!go` destination, or `None` when the tables allow it.
fn go_refusal(
  destination destination: Destination,
  tables tables: table_store.Tables,
) -> Option(Refusal) {
  case destination {
    Coordinates(world_id:, world_zone_id:, x:, y:, z:) ->
      located(world_id:, world_zone_id:, tables:, outside: [
        #(AxisX, x, x < -x_limit || x > x_limit),
        #(AxisY, y, y < -y_limit || y > y_limit),
        #(AxisZ, z, z < -z_limit || z > z_limit),
      ])
    Named(world_location2_id:) ->
      case named_row(world_location2_id:, tables:) {
        Error(refusal) -> Some(refusal)
        Ok(row) ->
          located(
            world_id: row.world_id,
            world_zone_id: row.world_zone_id,
            tables:,
            outside: [
              #(
                AxisX,
                float.truncate(row.position0),
                row.position0 <. int.to_float(-x_limit)
                  || row.position0 >. int.to_float(x_limit),
              ),
              #(
                AxisY,
                float.truncate(row.position1),
                row.position1 <. int.to_float(-y_limit)
                  || row.position1 >. int.to_float(y_limit),
              ),
              #(
                AxisZ,
                float.truncate(row.position2),
                row.position2 <. int.to_float(-z_limit)
                  || row.position2 >. int.to_float(z_limit),
              ),
            ],
          )
      }
  }
}

/// The refusal for a world or zone with no row, or else for the first axis whose
/// coordinate is outside the box (`outside`: the axis, its whole number, and
/// whether it is outside).
fn located(
  world_id world_id: Int,
  world_zone_id world_zone_id: Int,
  tables tables: table_store.Tables,
  outside outside: List(#(Axis, Int, Bool)),
) -> Option(Refusal) {
  case
    world.get(tables:, id: WorldId(world_id)),
    world_zone.get(tables:, id: WorldZoneId(world_zone_id))
  {
    Error(Nil), _ -> Some(WorldHasNoRow(world_id:))
    Ok(_), Error(Nil) -> Some(WorldZoneHasNoRow(world_zone_id:))
    Ok(_), Ok(_) ->
      list.find(outside, fn(axis) { axis.2 })
      |> result.map(fn(axis) {
        PositionOutsideTheBox(axis: axis.0, coordinate: axis.1)
      })
      |> option.from_result
  }
}

/// The WorldLocation2 row of a named place, or the refusal that it has none.
fn named_row(
  world_location2_id world_location2_id: Int,
  tables tables: table_store.Tables,
) -> Result(world_location2.WorldLocation2, Refusal) {
  world_location2.get(tables:, id: WorldLocation2Id(world_location2_id))
  |> result.replace_error(WorldLocation2HasNoRow(world_location2_id:))
}

/// The box a position is clamped to by the client (`0x1405b5070`): x and z to
/// 32768 either way, y to 2048.
const x_limit = 32_768

const z_limit = 32_768

const y_limit = 2048

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

/// `!go` as the UTF-16 units the client sends.
const go_word = [0x21, 0x67, 0x6F]

/// `!quest` as the UTF-16 units the client sends.
const quest_word = [0x21, 0x71, 0x75, 0x65, 0x73, 0x74]

/// `done` as the UTF-16 units the client sends.
const done_word = [0x64, 0x6F, 0x6E, 0x65]

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

/// The whole number the units spell, with one optional leading `-` before its
/// digits (`decimal`): `-` alone and `--1` are no number.
fn signed_decimal(units units: List(Int)) -> Result(Int, Nil) {
  case units {
    [0x2D, ..digits] -> decimal(units: digits) |> result.map(int.negate)
    [_, ..] | [] -> decimal(units:)
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
    GoTakesAPlace ->
      "!go takes a World id, a WorldZone id and x y z, as !go 22 1189 -5438 -966 -1093, or a WorldLocation2 id, as !go 8300"
    WorldHasNoRow(world_id:) ->
      "!go: World "
      <> int.to_string(world_id)
      <> " is not in the client's tables"
    WorldZoneHasNoRow(world_zone_id:) ->
      "!go: WorldZone "
      <> int.to_string(world_zone_id)
      <> " is not in the client's tables"
    WorldLocation2HasNoRow(world_location2_id:) ->
      "!go: WorldLocation2 "
      <> int.to_string(world_location2_id)
      <> " is not in the client's tables"
    PositionOutsideTheBox(axis:, coordinate:) -> {
      let #(name, limit) = case axis {
        AxisX -> #("x", x_limit)
        AxisY -> #("y", y_limit)
        AxisZ -> #("z", z_limit)
      }
      "!go: "
      <> name
      <> " "
      <> int.to_string(coordinate)
      <> " is outside "
      <> int.to_string(-limit)
      <> " to "
      <> int.to_string(limit)
    }
    QuestTakesAQuest2IdAndDone ->
      "!quest takes a Quest2 id and the word done, as !quest 5972 done"
    NoQuest2Row(quest2_id: Quest2Id(value:)) ->
      "!quest " <> int.to_string(value) <> " names no Quest2 row"
  }
}
