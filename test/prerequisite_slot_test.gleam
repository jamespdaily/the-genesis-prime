//// Prerequisite type 64, the first unit's resource slot (`genesis_prime/game/prerequisite`).
//// Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.64` (`0x1404a24ad`): the objectId is the unit's
////   resource slot by number (0 to 10; 11 or more reads 0.0), compared as a float
////   with the value made a float from a signed 32-bit number (`cvtdq2ps`), by
////   comparisons 1 equal, 2 not equal, 3 greater, 4 at least, 5 less, 6 at most;
////   any other fails. A slot the class does not use stays 0 (`class_resource`,
////   `0x140454380`).
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite
////   36425 29484`): 36425 is (64, 4, objectId 4, value 25), the Spell Surge buff's
////   persistence; Spellslinger slot 4 is Spell Power (`Class 7`, vitalEnumResource04
////   19).
//// - The server's choice (the prerequisite module's doc): a creature's side holds no
////   resource slots, which gives `NotRead(64)`.

import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, Passes, Subject,
}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support as support

/// A subject whose class holds only slot 4, at this value.
fn spell_power(value value: Float) -> Subject {
  Subject(
    ..support.holding(held: [], second_unit: None),
    resource_slots: Some(dict.from_list([#(4, value)])),
  )
}

fn verdict(
  condition condition: #(Int, Int, Int, Int),
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: support.single(id: 1, condition:), subject:)
}

pub fn slot_4_at_25_passes_at_least_25_and_24_9_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(condition: #(64, 4, 4, 25), subject: spell_power(value: 25.0))
    == Passes
    as "Prerequisite 36425: slot 4 at least 25; 25.0 meets it"
  assert verdict(condition: #(64, 4, 4, 25), subject: spell_power(value: 24.9))
    == Fails
    as "24.9 does not"
}

pub fn comparisons_1_to_6_on_25_against_25_each_give_their_result_and_7_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let verdicts =
    list.map([1, 2, 3, 4, 5, 6, 7, 0], fn(comparison) {
      verdict(
        condition: #(64, comparison, 4, 25),
        subject: spell_power(value: 25.0),
      )
    })
  assert verdicts == [Passes, Fails, Fails, Passes, Fails, Passes, Fails, Fails]
    as "25.0 against 25: equal, at least and at most hold; not equal, greater and less do not; 7 and 0 have no case and fail (0x1404a24ad)"
}

pub fn a_slot_the_class_does_not_hold_reads_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(condition: #(64, 1, 1, 0), subject: spell_power(value: 25.0))
    == Passes
    as "a Spellslinger's slot 1 holds nothing: 'equal 0' passes"
  assert verdict(condition: #(64, 3, 1, 0), subject: spell_power(value: 25.0))
    == Fails
    as "and 'greater than 0' fails"
}

pub fn slot_11_and_above_read_0_whatever_is_held_there_test() -> Nil {
  use <- owned_test.run(5000)
  let holding_11 =
    Subject(
      ..support.holding(held: [], second_unit: None),
      resource_slots: Some(dict.from_list([#(11, 40.0), #(12, 7.0)])),
    )
  assert verdict(condition: #(64, 1, 11, 0), subject: holding_11) == Passes
    as "0x1404a24bd: a slot of 11 or more is not read from the unit; it is 0.0"
  assert verdict(condition: #(64, 1, 12, 0), subject: holding_11) == Passes
    as "so is 12"
}

pub fn a_value_of_minus_1_is_read_signed_test() -> Nil {
  use <- owned_test.run(5000)
  // The table's column may hold the number as -1 or as 4294967295: the same 32 bits.
  assert list.map([-1, 4_294_967_295], fn(value) {
      verdict(condition: #(64, 3, 4, value), subject: spell_power(value: 0.0))
    })
    == [Passes, Passes]
    as "0.0 is greater than -1, which cvtdq2ps makes of the 32 bits 0xFFFFFFFF; read unsigned it would be 4294967295"
}

pub fn a_creatures_subject_reads_no_slot_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(
      condition: #(64, 4, 4, 25),
      subject: support.holding(held: [], second_unit: None),
    )
    == NotRead(prerequisite_type: 64)
    as "a subject that holds no resource slots, a creature's side, is not read"
}
