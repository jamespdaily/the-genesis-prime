//// The development chat commands' grammar (`genesis_prime/game/dev_command`):
//// which `!` lines are commands and which are refused. The commands are a test
//// tool of the server's own choosing (for the play container), so the expected
//// values are the design's choices, stated by the module's doc comment: `!` then a word, then
//// its arguments split at spaces; `summon` takes one whole decimal number, a
//// Creature2 id, and then optionally a second, the level; the word is read as typed, in lower case; a line the grammar
//// refuses is answered, never said. The one Creature2 id, 75048, is Commander
//// Durek's, the live check's creature.

import genesis_prime/game/dev_command.{
  SummonLevelIsNotAWholeNumber, SummonTakesACreature2Id, UnknownCommand,
}
import genesis_prime/message/bit_stream
import genesis_prime/table/id.{Creature2Id}
import gleam/list
import gleam/option.{None, Some}
import owned_test

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
}
