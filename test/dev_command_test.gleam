//// The development chat commands' grammar (`genesis_prime/game/dev_command`):
//// which `!` lines are commands and which are refused. The commands are a test
//// tool of the server's own choosing (for the play container), so the expected
//// values are the design's choices, stated by the module's doc comment: `!` then a word, then
//// its arguments split at spaces; `summon` takes one whole decimal number, a
//// Creature2 id, and then optionally a second, the level; the word is read as typed, in lower case; a line the grammar
//// refuses is answered, never said. The one Creature2 id, 75048, is Commander
//// Durek's, the live check's creature. `level` and `xp` each take one whole
//// decimal number. The highest level is 50 (GameFormula 145 dataint0) and the
//// experience of level 50 is 26,360,090 (XpPerLevel row 50, minXpForLevel).

import fixture_tables
import genesis_prime/game/dev_command.{
  CurrencyAmountAboveCap, CurrencyAmountAboveColumn,
  CurrencyTakesATypeAndAnAmount, CurrencyTypeIsNotKept, ExperienceOutOfRange,
  ExperienceTakesAWholeNumber, LevelOutOfRange, LevelTakesAWholeNumber,
  RaiseToExperience, RaiseToLevel, SummonLevelIsNotAWholeNumber,
  SummonTakesACreature2Id, UnknownCommand,
}
import genesis_prime/message/bit_stream
import genesis_prime/table/id.{Creature2Id, CurrencyTypeId}
import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import owned_test
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

pub fn summon_with_one_whole_decimal_number_is_the_summon_of_that_creature2_id_test() -> Nil {
  use <- owned_test.run(5000)
  assert parsed("!summon 75048")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: None))
    as "the grammar: summon takes one whole decimal number, and with no level the summon is as before"
  assert parsed("!summon 0") == Ok(dev_command.Summon(Creature2Id(0), None))
    as "the number is any whole number: whether a Creature2 row has it is the map's check"
  assert parsed("!summon 007") == Ok(dev_command.Summon(Creature2Id(7), None))
    as "leading zeros are still a decimal number"
}

pub fn summon_with_a_second_whole_decimal_number_is_the_summon_of_that_creature2_id_at_that_level_test() -> Nil {
  use <- owned_test.run(5000)
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

pub fn summon_with_a_level_that_is_not_one_whole_decimal_number_is_refused_naming_the_level_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("!summon 75048 x", "not a number"),
      #("!summon 75048 3x", "a number with a letter"),
      #("!summon 75048 -3", "a minus sign"),
      #("!summon 75048 +3", "a plus sign"),
      #("!summon 75048 3.5", "a fraction"),
      #("!summon 75048 0x10", "hexadecimal"),
      #("!summon 75048 ٣", "an Arabic-Indic digit"),
    ],
    fn(row) {
      assert parsed(row.0) == Error(SummonLevelIsNotAWholeNumber) as row.1
    },
  )
  assert parsed("!summon x 3") == Error(SummonTakesACreature2Id)
    as "a creature that is no number is the usage refusal whatever the level is"
  assert parsed("!summon 75048 3 4") == Error(SummonTakesACreature2Id)
    as "a third word is more than the grammar takes"
}

pub fn spaces_around_and_between_the_words_make_no_difference_test() -> Nil {
  use <- owned_test.run(5000)
  assert parsed("!summon    75048  ")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: None))
    as "the grammar splits at spaces: a run of them is one split, and a trailing one holds no argument"
}

pub fn summon_with_no_number_or_anything_but_one_whole_decimal_number_is_the_usage_refusal_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("!summon", "no argument"),
      #("!summon ", "only spaces after it"),
      #("!summon x", "not a number"),
      #("!summon 7x", "a number with a letter"),
      #("!summon -5", "a minus sign"),
      #("!summon +5", "a plus sign"),
      #("!summon 7.5", "a fraction"),
      #("!summon 0x10", "hexadecimal"),
      #(
        "!summon ٣",
        "an Arabic-Indic digit, which is no decimal digit of the grammar",
      ),
      #("!summon 1 2 3", "three arguments"),
    ],
    fn(row) {
      assert parsed(row.0) == Error(SummonTakesACreature2Id) as row.1
    },
  )
  assert dev_command.parse(text: [
      0x21,
      0x73,
      0x75,
      0x6D,
      0x6D,
      0x6F,
      0x6E,
      0x20,
      0xD800,
    ])
    == Error(SummonTakesACreature2Id)
    as "an argument that is not valid UTF-16 is not a number, and the line is still the summon's, answered with its usage"
}

pub fn any_other_word_is_an_unknown_command_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("!", "a bang alone"),
      #("! summon 75048", "a space after the bang"),
      #("!teleport 1", "a word with no command"),
      #("!Summon 75048", "the word is read as typed, in lower case"),
      #("!summons 75048", "a longer word"),
      #("!summo 75048", "a shorter word"),
      #("!!summon 75048", "two bangs"),
    ],
    fn(row) {
      assert parsed(row.0) == Error(UnknownCommand) as row.1
    },
  )
}

pub fn the_answers_to_a_refused_line_say_what_was_wrong_test() -> Nil {
  use <- owned_test.run(5000)
  assert dev_command.describe(refusal: UnknownCommand) == "unknown command"
    as "the design: an unknown `!` command answers \"unknown command\""
  assert dev_command.describe(refusal: SummonTakesACreature2Id)
    == "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3"
    as "the design: a malformed !summon answers its usage"
  assert dev_command.describe(refusal: SummonLevelIsNotAWholeNumber)
    == "!summon's level is a whole number, as !summon 75048 3"
    as "the design: a level that is no whole number answers what it takes"
  assert dev_command.describe(refusal: LevelOutOfRange(level: 51, highest: 50))
    == "!level 51 is outside the levels 1 to 50"
    as "the design: a level out of range names the command, the value and the range"
  assert dev_command.describe(refusal: ExperienceOutOfRange(
      experience: 26_360_091,
      highest: 26_360_090,
    ))
    == "!xp 26360091 is above the experience of the highest level, 26360090"
    as "the design: an experience out of range names the command, the value and the top"
  assert dev_command.describe(refusal: LevelTakesAWholeNumber)
    == "!level takes one whole number, a level, as !level 10"
    as "the design: a malformed !level answers its usage"
  assert dev_command.describe(refusal: ExperienceTakesAWholeNumber)
    == "!xp takes one whole number, a total experience, as !xp 2860"
    as "the design: a malformed !xp answers its usage"
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
  list.each(
    [
      #("!level -4", Error(LevelTakesAWholeNumber), "a sign"),
      #("!level 4.5", Error(LevelTakesAWholeNumber), "a fraction"),
      #("!level \u{FF14}", Error(LevelTakesAWholeNumber), "a full-width digit"),
      #(
        "!xp \u{0664}\u{0662}",
        Error(ExperienceTakesAWholeNumber),
        "Arabic-Indic digits",
      ),
      #(
        "!level 99999999999999999999",
        Ok(RaiseToLevel(level: 99_999_999_999_999_999_999)),
        "a number of any length parses: its table check refuses it",
      ),
      #(
        "!xp 99999999999999999999",
        Ok(RaiseToExperience(experience: 99_999_999_999_999_999_999)),
        "a number of any length parses: its table check refuses it",
      ),
    ],
    fn(row) {
      assert parsed(row.0) == row.1 as row.2
    },
  )
  let tables = fixture_tables.shared()
  assert dev_command.checked(
      command: RaiseToLevel(level: 99_999_999_999_999_999_999),
      tables:,
    )
    == Error(LevelOutOfRange(level: 99_999_999_999_999_999_999, highest: 50))
    as "GameFormula 145: the highest level is 50"
  assert dev_command.checked(
      command: RaiseToExperience(experience: 99_999_999_999_999_999_999),
      tables:,
    )
    == Error(ExperienceOutOfRange(
      experience: 99_999_999_999_999_999_999,
      highest: 26_360_090,
    ))
    as "XpPerLevel row 50: the highest minXpForLevel is 26360090"
}

pub fn a_level_or_experience_the_tables_do_not_hold_is_refused_by_checked_before_anything_is_asked_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(
    [
      #(
        RaiseToLevel(level: 0),
        Error(LevelOutOfRange(level: 0, highest: 50)),
        "level 0 is below the first level",
      ),
      #(
        RaiseToLevel(level: 51),
        Error(LevelOutOfRange(level: 51, highest: 50)),
        "level 51 is above GameFormula 145's 50",
      ),
      #(RaiseToLevel(level: 1), Ok(RaiseToLevel(level: 1)), "level 1"),
      #(RaiseToLevel(level: 50), Ok(RaiseToLevel(level: 50)), "level 50"),
      #(
        RaiseToExperience(experience: 26_360_090),
        Ok(RaiseToExperience(experience: 26_360_090)),
        "level 50's own minXpForLevel",
      ),
      #(
        RaiseToExperience(experience: 26_360_091),
        Error(ExperienceOutOfRange(experience: 26_360_091, highest: 26_360_090)),
        "one above level 50's minXpForLevel",
      ),
    ],
    fn(row) {
      assert dev_command.checked(command: row.0, tables:) == row.1 as row.2
    },
  )
  assert dev_command.checked(
      command: dev_command.Summon(
        creature2_id: Creature2Id(75_048),
        level: None,
      ),
      tables:,
    )
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048), level: None))
    as "a summon's rows are the map's check"
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

pub fn a_currency_value_the_tables_do_not_hold_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let column_limit = 9_223_372_036_854_775_807
  list.each(
    [
      #(currency(1, 5000), Ok(currency(1, 5000)), "credits: CurrencyType row 1"),
      #(currency(2, 5000), Ok(currency(2, 5000)), "Renown: CurrencyType row 2"),
      #(
        currency(8, 1),
        Error(CurrencyTypeIsNotKept(currency_type_id: 8)),
        "CurrencyType has no row 8",
      ),
      #(
        currency(15, 1),
        Error(CurrencyTypeIsNotKept(currency_type_id: 15)),
        "CurrencyType has no row 15: the client keeps types 1 to 14",
      ),
      #(
        currency(1, 500_000),
        Ok(currency(1, 500_000)),
        "GameFormula 1115 dataint0: the credits cap, 500,000",
      ),
      #(
        currency(1, 500_001),
        Error(CurrencyAmountAboveCap(
          currency_type_id: 1,
          amount: 500_001,
          cap: 500_000,
        )),
        "one above the credits cap",
      ),
      #(
        currency(2, 5001),
        Error(CurrencyAmountAboveCap(
          currency_type_id: 2,
          amount: 5001,
          cap: 5000,
        )),
        "GameFormula 1116 dataint0: the Renown cap, 5,000",
      ),
      #(
        currency(5, 12_001),
        Error(CurrencyAmountAboveCap(
          currency_type_id: 5,
          amount: 12_001,
          cap: 12_000,
        )),
        "CurrencyType row 5: capAmount 12000",
      ),
      #(
        currency(3, 1_000_000_000_000),
        Ok(currency(3, 1_000_000_000_000)),
        "CurrencyType row 3: capAmount 0, no cap",
      ),
      #(
        currency(3, column_limit + 1),
        Error(CurrencyAmountAboveColumn(
          amount: column_limit + 1,
          highest: column_limit,
        )),
        "the character_currency.amount column is a bigint: 2^63 - 1",
      ),
    ],
    fn(row) {
      assert dev_command.checked(command: row.0, tables:) == row.1 as row.2
    },
  )
}

pub fn a_currency_amount_of_any_length_is_refused_by_the_column_limit_not_by_a_crash_test() -> Nil {
  use <- owned_test.run(5000)
  let amount = 99_999_999_999_999_999_999
  assert parsed("!currency 1 99999999999999999999") == Ok(currency(1, amount))
    as "a number of any length parses: its check refuses it"
  assert dev_command.checked(
      command: currency(1, amount),
      tables: fixture_tables.shared(),
    )
    == Error(CurrencyAmountAboveColumn(
      amount:,
      highest: 9_223_372_036_854_775_807,
    ))
    as "the column's 63-bit limit is tested before the credits cap, which the amount is also above"
}
