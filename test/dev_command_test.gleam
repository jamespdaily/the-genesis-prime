//// The development chat commands' grammar (`genesis_prime/game/dev_command`):
//// which `!` lines are commands and which are refused. The commands are a test
//// tool of the server's own choosing (for the play container), so the expected
//// values are the design's choices, stated by the module's doc comment: `!` then a word, then
//// its arguments split at spaces; `summon` takes one whole decimal number, a
//// Creature2 id, and then optionally a second, the level; the word is read as typed, in lower case; a line the grammar
//// refuses is answered, never said. The one Creature2 id, 75048, is Commander
//// Durek's, the live check's creature. `level` and `xp` each take one whole
//// decimal number. The highest level is 50 (GameFormula 145 dataint0) and the
//// experience of level 50 is 26,360,090 (XpPerLevel row 50, minXpForLevel). `quest` takes one
//// whole decimal number, a Quest2 id, and the word `done`; Quest2 5972 is a row of the
//// fixture and 999999 is none (the client refuses an unknown quest: `opcode.0x35c`,
//// FindQuestById fails 0xa00b0001).

import fixture_tables
import genesis_prime/game/dev_command.{
  AxisX, AxisY, AxisZ, CompleteQuest, Coordinates, CurrencyAmountAboveCap,
  CurrencyAmountAboveColumn, CurrencyTakesATypeAndAnAmount,
  CurrencyTypeIsNotKept, ExperienceOutOfRange, ExperienceTakesAWholeNumber,
  GiveItem, Go, GoTakesAPlace, ItemCountIsZero, ItemHasNoRow, ItemIsAProxy,
  ItemTakesAnItem2IdAndACount, LevelOutOfRange, LevelTakesAWholeNumber, Named,
  NoQuest2Row, PositionOutsideTheBox, QuestTakesAQuest2IdAndDone,
  RaiseToExperience, RaiseToLevel, SummonLevelIsNotAWholeNumber,
  SummonTakesACreature2Id, UnknownCommand, WorldHasNoRow, WorldLocation2HasNoRow,
  WorldZoneHasNoRow,
}
import genesis_prime/game/start_place
import genesis_prime/message/bit_stream
import genesis_prime/table/id.{Creature2Id, CurrencyTypeId, Item2Id, Quest2Id}
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import planted_table.{Float, Integer}
import qcheck

fn parsed(text: String) -> Result(dev_command.Command, dev_command.Refusal) {
  dev_command.parse(text: bit_stream.utf16_units(text))
}

pub fn a_line_is_a_command_only_when_its_first_unit_is_a_bang_test() -> Nil {
  use <- owned_test.run(5000)
  assert dev_command.is_command(text: bit_stream.utf16_units("!summon 75048"))
    as "the grammar: `!` first"
  assert dev_command.is_command(text: bit_stream.utf16_units("!"))
  assert !dev_command.is_command(text: bit_stream.utf16_units(" !summon 75048"))
    as "a line that opens with a space is a line to say"
  assert !dev_command.is_command(text: bit_stream.utf16_units("Hello!"))
  assert !dev_command.is_command(text: [])
}

pub fn summon_takes_a_creature2_id_and_an_optional_level_as_whole_decimal_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  assert parsed("!summon 75048")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: None))
    as "the grammar: summon takes one whole decimal number, and with no level the summon is as before"
  assert parsed("!summon 0") == Ok(dev_command.Summon(Creature2Id(0), None))
    as "the number is any whole number: whether a Creature2 row has it is the map's check"
  assert parsed("!summon 007") == Ok(dev_command.Summon(Creature2Id(7), None))
    as "leading zeros are still a decimal number"
  assert parsed("!summon 75048 3")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: Some(3)))
    as "the grammar: a second whole decimal number is the level"
  assert parsed("!summon  75048   03 ")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: Some(3)))
    as "spaces split the words and leading zeros are still a decimal number"
  assert parsed("!summon 75048 0")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: Some(0)))
    as "the level is any whole number: whether a CreatureLevel row has it is the map's check"
}

pub fn level_and_experience_take_whole_decimal_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("!level 4", Ok(RaiseToLevel(level: 4)), "a level is one whole number"),
      #(
        "!xp 2859",
        Ok(RaiseToExperience(experience: 2859)),
        "an experience is one whole number",
      ),
      #("!level", Error(LevelTakesAWholeNumber), "no argument"),
      #("!level 4 5", Error(LevelTakesAWholeNumber), "two arguments"),
      #("!xp 1x", Error(ExperienceTakesAWholeNumber), "a letter in the number"),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
}

/// A unit that is no ASCII digit and no space (which would split the word).
fn not_a_digit(unit: Int) -> Int {
  use <- bool.guard(unit >= 0x30 && unit <= 0x39 || unit == 0x20, 0x41)
  unit
}

pub fn a_number_with_any_other_unit_than_an_ascii_digit_is_refused_or_checked_not_crashed_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let digits =
    qcheck.generic_list(
      qcheck.bounded_int(from: 0x30, to: 0x39),
      qcheck.bounded_int(from: 0, to: 4),
    )
  use #(level_word, before, bad, after) <- qcheck.given(qcheck.tuple4(
    qcheck.bool(),
    digits,
    qcheck.map(qcheck.bounded_int(from: 0, to: 0xFFFF), not_a_digit),
    digits,
  ))
  let word = case level_word {
    True -> "!level "
    False -> "!xp "
  }
  let text = list.flatten([bit_stream.utf16_units(word), before, [bad], after])
  assert dev_command.parse(text:)
    == Error(case level_word {
      True -> LevelTakesAWholeNumber
      False -> ExperienceTakesAWholeNumber
    })
    as "the grammar: a number is ASCII digits only, whatever unit sits among them"
}

pub fn item_takes_an_item2_id_and_an_optional_count_as_whole_decimal_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "!item 90021",
        Ok(GiveItem(item2_id: Item2Id(90_021), count: 1)),
        "no count is a count of 1",
      ),
      #(
        "!item 90021 3",
        Ok(GiveItem(item2_id: Item2Id(90_021), count: 3)),
        "an Item2 id and a count",
      ),
      #("!item", Error(ItemTakesAnItem2IdAndACount), "no argument"),
      #("!item 1 2 3", Error(ItemTakesAnItem2IdAndACount), "three arguments"),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
}

pub fn quest_takes_a_quest2_id_and_the_word_done_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "!quest 5972 done",
        Ok(CompleteQuest(quest2_id: Quest2Id(5972))),
        "a Quest2 id and the word done",
      ),
      #(
        "!quest 5972",
        Error(QuestTakesAQuest2IdAndDone),
        "no word after the id",
      ),
      #("!quest", Error(QuestTakesAQuest2IdAndDone), "no argument"),
      #(
        "!quest 5972 finish",
        Error(QuestTakesAQuest2IdAndDone),
        "a word other than done",
      ),
      #("!quest 5972 Done", Error(QuestTakesAQuest2IdAndDone), "read as typed"),
      #(
        "!quest x done",
        Error(QuestTakesAQuest2IdAndDone),
        "an id that is no number",
      ),
      #(
        "!quest 5972 done now",
        Error(QuestTakesAQuest2IdAndDone),
        "a third word",
      ),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
}

fn currency(type_id: Int, amount: Int) -> dev_command.Command {
  dev_command.SetCurrency(currency_type_id: CurrencyTypeId(type_id), amount:)
}

pub fn currency_takes_a_type_and_an_amount_as_whole_decimal_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "!currency 1 5000",
        Ok(currency(1, 5000)),
        "a currency type and an amount, each one whole decimal number",
      ),
      #(
        "!currency 1",
        Error(CurrencyTakesATypeAndAnAmount),
        "the amount is missing: a usage refusal",
      ),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
}

/// A `!go` to World 22 and WorldZone 1189, rows of the client's tables, at a position.
fn at(x x: Int, y y: Int, z z: Int) -> dev_command.Command {
  Go(destination: Coordinates(world_id: 22, world_zone_id: 1189, x:, y:, z:))
}

pub fn go_takes_a_place_by_coordinates_or_by_a_world_location2_row_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "!go 22 1189 -5438 -966 -1093",
        Ok(at(x: -5438, y: -966, z: -1093)),
        "a world, a zone and three coordinates, a sign allowed on a coordinate",
      ),
      #(
        "!go 8300",
        Ok(Go(destination: Named(world_location2_id: 8300))),
        "a row",
      ),
      #("!go", Error(GoTakesAPlace), "no argument"),
      #("!go 22 1189 1 2", Error(GoTakesAPlace), "four arguments"),
      #("!go 22 1189 1 2 3 4 5 6", Error(GoTakesAPlace), "eight arguments"),
      #("!go 1.5", Error(GoTakesAPlace), "a fraction as the row"),
      #("!go 22 1189 - 2 3", Error(GoTakesAPlace), "a sign alone"),
      #("!go 22 1189 --1 2 3", Error(GoTakesAPlace), "two signs"),
      #("!go -22 1189 1 2 3", Error(GoTakesAPlace), "a sign on the world id"),
      #("!go 22 -1189 1 2 3", Error(GoTakesAPlace), "a sign on the zone id"),
      #("!go -8300", Error(GoTakesAPlace), "a sign on a row's id"),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
}

/// A line parsed, then checked against the fixture's tables, as the connection does.
fn refused(text: String) -> Result(dev_command.Command, dev_command.Refusal) {
  use command <- result.try(parsed(text))
  dev_command.checked(command:, tables: fixture_tables.shared())
}

pub fn a_line_the_grammar_or_the_tables_refuse_is_refused_and_answered_with_what_was_wrong_test() -> Nil {
  use <- owned_test.run(60_000)
  let column_limit = 9_223_372_036_854_775_807
  let huge_digits = string.repeat("9", times: 400)
  let assert Ok(huge) = int.parse(huge_digits)
  list.each(
    [
      #(
        "!teleport 1",
        UnknownCommand,
        "unknown command",
        "a word with no command",
      ),
      #(
        "!Summon 75048",
        UnknownCommand,
        "unknown command",
        "the word is read as typed, in lower case",
      ),
      #("!summons 75048", UnknownCommand, "unknown command", "a longer word"),
      #("!summo 75048", UnknownCommand, "unknown command", "a shorter word"),
      #("!!summon 75048", UnknownCommand, "unknown command", "two bangs"),
      #(
        "!summon x 3",
        SummonTakesACreature2Id,
        "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3",
        "a creature that is no number is the usage refusal whatever the level is",
      ),
      #(
        "!summon 7x",
        SummonTakesACreature2Id,
        "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3",
        "a creature that is no number",
      ),
      #(
        "!summon 75048 3x",
        SummonLevelIsNotAWholeNumber,
        "!summon's level is a whole number, as !summon 75048 3",
        "a level that is no number",
      ),
      #(
        "!level",
        LevelTakesAWholeNumber,
        "!level takes one whole number, a level, as !level 10",
        "no argument",
      ),
      #(
        "!xp 1x",
        ExperienceTakesAWholeNumber,
        "!xp takes one whole number, a total experience, as !xp 2860",
        "a letter in the number",
      ),
      #(
        "!level 0",
        LevelOutOfRange(level: 0, highest: 50),
        "!level 0 is outside the levels 1 to 50",
        "level 0 is below the first level",
      ),
      #(
        "!level 51",
        LevelOutOfRange(level: 51, highest: 50),
        "!level 51 is outside the levels 1 to 50",
        "GameFormula 145: the highest level is 50",
      ),
      #(
        "!level 99999999999999999999",
        LevelOutOfRange(level: 99_999_999_999_999_999_999, highest: 50),
        "!level 99999999999999999999 is outside the levels 1 to 50",
        "a number of any length parses and the table check refuses it",
      ),
      #(
        "!xp 26360091",
        ExperienceOutOfRange(experience: 26_360_091, highest: 26_360_090),
        "!xp 26360091 is above the experience of the highest level, 26360090",
        "XpPerLevel row 50: one above the highest minXpForLevel",
      ),
      #(
        "!item 1 2 3",
        ItemTakesAnItem2IdAndACount,
        "!item takes an Item2 id and an optional count, as !item 90021 or !item 90021 3",
        "three arguments",
      ),
      #(
        "!item 999999999",
        ItemHasNoRow(item2_id: Item2Id(999_999_999)),
        "!item 999999999 is no row of the Item2 table",
        "no Item2 row has the id",
      ),
      #(
        "!item 29213",
        ItemIsAProxy(item2_id: Item2Id(29_213)),
        "!item does not give a proxy item (29213): the client reads its stack limit and its deletable flag from another item, and the server reads the item's own row",
        "Item2 29213 has the proxy flag 0x4000",
      ),
      #(
        "!item 90021 0",
        ItemCountIsZero,
        "!item's count is at least 1",
        "a count of 0 gives nothing",
      ),
      #(
        "!quest 5972",
        QuestTakesAQuest2IdAndDone,
        "!quest takes a Quest2 id and the word done, as !quest 5972 done",
        "no word after the id",
      ),
      #(
        "!quest 999999 done",
        NoQuest2Row(quest2_id: Quest2Id(999_999)),
        "!quest 999999 names no Quest2 row",
        "the client refuses a quest it has no row for",
      ),
      #(
        "!currency 1",
        CurrencyTakesATypeAndAnAmount,
        "!currency takes a currency type and an amount, as !currency 1 5000",
        "the amount is missing",
      ),
      #(
        "!currency 8 1",
        CurrencyTypeIsNotKept(currency_type_id: 8),
        "!currency 8 is no currency type the client keeps (1 to 7 and 9 to 14)",
        "CurrencyType has no row 8",
      ),
      #(
        "!currency 1 500001",
        CurrencyAmountAboveCap(
          currency_type_id: 1,
          amount: 500_001,
          cap: 500_000,
        ),
        "!currency 1 500001 is above the most that currency holds, 500000",
        "GameFormula 1115 dataint0: the credits cap is 500,000",
      ),
      #(
        "!currency 1 9223372036854775808",
        CurrencyAmountAboveColumn(
          amount: column_limit + 1,
          highest: column_limit,
        ),
        "!currency amount 9223372036854775808 is above the most a total can hold, 9223372036854775807",
        "the character_currency.amount column is a bigint, tested before the cap",
      ),
      #(
        "!go 22 1189 1 2",
        GoTakesAPlace,
        "!go takes a World id, a WorldZone id and x y z, as !go 22 1189 -5438 -966 -1093, or a WorldLocation2 id, as !go 8300",
        "four arguments",
      ),
      #(
        "!go 99999 1189 0 0 0",
        WorldHasNoRow(world_id: 99_999),
        "!go: World 99999 is not in the client's tables",
        "no World row has the id",
      ),
      #(
        "!go 22 999999 0 0 0",
        WorldZoneHasNoRow(world_zone_id: 999_999),
        "!go: WorldZone 999999 is not in the client's tables",
        "no WorldZone row has the id",
      ),
      #(
        "!go 99999999",
        WorldLocation2HasNoRow(world_location2_id: 99_999_999),
        "!go: WorldLocation2 99999999 is not in the client's tables",
        "no WorldLocation2 row has the id",
      ),
      #(
        "!go 99999 999999 40000 0 0",
        WorldHasNoRow(world_id: 99_999),
        "!go: World 99999 is not in the client's tables",
        "the world is refused before the zone, and the zone before the position",
      ),
      #(
        "!go 22 999999 40000 0 0",
        WorldZoneHasNoRow(world_zone_id: 999_999),
        "!go: WorldZone 999999 is not in the client's tables",
        "the zone is refused before the position",
      ),
      #(
        "!go 22 1189 " <> huge_digits <> " 2 3",
        PositionOutsideTheBox(axis: AxisX, coordinate: huge),
        "!go: x " <> huge_digits <> " is outside -32768 to 32768",
        "a coordinate of any length parses and the box refuses it as a whole number, with no conversion to a float",
      ),
      #(
        "!go 22 1189 0 -2049 0",
        PositionOutsideTheBox(axis: AxisY, coordinate: -2049),
        "!go: y -2049 is outside -2048 to 2048",
        "one beyond the client's clamp on y",
      ),
    ],
    fn(row) {
      let #(line, refusal, description, reason) = row
      assert refused(line) == Error(refusal) as reason
      assert dev_command.describe(refusal:) == description as reason
    },
  )
}

/// The first id of the WorldLocation2 rows the named-place test adds, above every row of the fixture.
const planted_first = 59_001

pub fn a_named_place_is_checked_as_a_coordinate_one_is_test() -> Nil {
  use <- owned_test.run(60_000)
  let planted = [
    #([], Ok(Nil), "a row whose world, zone and position the tables hold"),
    #(
      [#("worldId", Integer(0))],
      Error(WorldHasNoRow(world_id: 0)),
      "a row in world 0, which `start_place.of_row` refuses, is refused as World 0 is",
    ),
    #(
      [#("worldZoneId", Integer(999_999))],
      Error(WorldZoneHasNoRow(world_zone_id: 999_999)),
      "a row whose zone has no WorldZone row",
    ),
    #(
      [#("worldId", Integer(99_999))],
      Error(WorldHasNoRow(world_id: 99_999)),
      "a row whose world has no World row",
    ),
    #(
      [#("position0", Float(40_000.0))],
      Error(PositionOutsideTheBox(axis: AxisX, coordinate: 40_000)),
      "a row at x 40000, outside the box",
    ),
  ]
  let rows =
    list.index_fold(planted, fixture_tables.rows(), fn(rows, row, index) {
      let assert Ok(rows) =
        fixture_tables.add(
          rows:,
          table: "WorldLocation2",
          copy_of: 8300,
          id: planted_first + index,
          with: row.0,
        )
        as "row 8300 is committed and its columns are the table's"
      rows
    })
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  list.index_fold(planted, Nil, fn(_, row, index) {
    let command =
      Go(destination: Named(world_location2_id: planted_first + index))
    let expected = case row.1 {
      Ok(Nil) -> Ok(command)
      Error(refusal) -> Error(refusal)
    }
    assert dev_command.checked(command:, tables:) == expected as row.2
  })
}

pub fn every_edge_of_the_position_box_is_accepted_and_one_beyond_it_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  use #(axis, negative, first, second) <- qcheck.given(qcheck.tuple4(
    qcheck.bounded_int(from: 0, to: 2),
    qcheck.bool(),
    qcheck.bounded_int(from: -2048, to: 2048),
    qcheck.bounded_int(from: -2048, to: 2048),
  ))
  // The box of the client's clamp: x and z 32768, y 2048 (`0x1405b5070`).
  let #(name, limit) = case axis {
    0 -> #(AxisX, 32_768)
    1 -> #(AxisY, 2048)
    _ -> #(AxisZ, 32_768)
  }
  let sign = case negative {
    True -> -1
    False -> 1
  }
  let placed = fn(value: Int) {
    case name {
      AxisX -> at(x: value, y: first, z: second)
      AxisY -> at(x: first, y: value, z: second)
      AxisZ -> at(x: first, y: second, z: value)
    }
  }
  assert dev_command.checked(command: placed(sign * limit), tables:)
    == Ok(placed(sign * limit))
    as "the edge is inside the box, whatever the other axes hold"
  assert dev_command.checked(command: placed(sign * { limit + 1 }), tables:)
    == Error(PositionOutsideTheBox(axis: name, coordinate: sign * { limit + 1 }))
    as "one whole number beyond the edge is outside it, whatever the other axes hold"
}

pub fn a_coordinate_go_keeps_the_facing_it_is_given_and_a_named_go_takes_the_rows_facing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let facing = start_place.Facing(yaw: 1.5, pitch: 0.25, roll: -0.5)
  let assert Ok(coordinates) =
    dev_command.place_of(
      destination: Coordinates(
        world_id: 22,
        world_zone_id: 1189,
        x: -5438,
        y: -966,
        z: -1093,
      ),
      facing:,
      tables:,
    )
  assert start_place.world_id(coordinates) == 22
  assert start_place.world_zone_id(coordinates) == 1189
  assert #(
      start_place.x(coordinates),
      start_place.y(coordinates),
      start_place.z(coordinates),
    )
    == #(-5438.0, -966.0, -1093.0)
    as "the coordinates, whole, as the place's position"
  assert start_place.facing(coordinates) == facing
    as "a coordinate go keeps the facing it is given"
  let assert Ok(named) =
    dev_command.place_of(
      destination: Named(world_location2_id: 8300),
      facing:,
      tables:,
    )
  assert start_place.world_id(named) == 870 as "WorldLocation2 8300: world 870"
  assert start_place.world_zone_id(named) == 1227
    as "WorldLocation2 8300: zone 1227"
  assert #(start_place.x(named), start_place.y(named), start_place.z(named))
    == #(-7700.970703125, -941.0088500976562, -659.29150390625)
    as "WorldLocation2 8300's position"
  let row_facing = start_place.facing(named)
  // The row's quaternion (0, -0.66819, 0, 0.74399) is a turn about y of 2 atan2(y, w).
  assert float.absolute_value(row_facing.yaw +. 1.4635471) <. 0.000001
    as "the row's own facing, not the one given"
  assert float.absolute_value(row_facing.pitch) <. 0.000001
  assert float.absolute_value(row_facing.roll) <. 0.000001
}
