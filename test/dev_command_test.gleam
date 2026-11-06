//// The development chat commands' grammar (`genesis_prime/game/dev_command`):
//// which `!` lines are commands and which are refused. The client has no such
//// commands (it sends every chat line as typed), so the expected values are the
//// design's choices, stated by the module's doc comment: `!` then a word, then
//// its arguments split at spaces; `summon` takes one whole decimal number, a
//// Creature2 id; the word is read as typed, in lower case; a line the grammar
//// refuses is answered, never said. The one Creature2 id, 75048, is Commander
//// Durek's, the live check's creature.

import genesis_prime/game/dev_command.{SummonTakesACreature2Id, UnknownCommand}
import genesis_prime/message/bit_stream
import genesis_prime/table/id.{Creature2Id}
import gleam/list
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
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048)))
    as "the grammar: summon takes one whole decimal number"
  assert parsed("!summon 0") == Ok(dev_command.Summon(Creature2Id(0)))
    as "the number is any whole number: whether a Creature2 row has it is the map's check"
  assert parsed("!summon 007") == Ok(dev_command.Summon(Creature2Id(7)))
    as "leading zeros are still a decimal number"
}

pub fn spaces_around_and_between_the_words_make_no_difference_test() -> Nil {
  use <- owned_test.run(5000)
  assert parsed("!summon    75048  ")
    == Ok(dev_command.Summon(creature2_id: Creature2Id(75_048)))
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
      #("!summon 1 2", "two arguments"),
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
    == "!summon takes one Creature2 id, as !summon 75048"
    as "the design: a malformed !summon answers its usage"
}
