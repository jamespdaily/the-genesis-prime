//// The prerequisite evaluator (`genesis_prime/game/prerequisite`): a Prerequisite
//// row read as the client reads it, and checked against a subject: the live casts
//// it is a target of, whether it is in combat, its vitals and its rolls. Expected
//// values come from these places:
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite 24581
////   24582 43811 43812`), copied into `row_24581` and the others below.
//// - The client's evaluator: `Prerequisite.flags` and `0x1404a5190` (conditions cut
////   at the first type 0; flags bit 0 makes OR; an empty row passes under AND and
////   fails under OR), `0x1404a1ca0` (AND or OR of the kept conditions),
////   `Prerequisite.prerequisiteTypeId.15` and `0x1404a4ec0` (type 15: comparison 1
////   passes when a live cast of the value's Spell4 targets the unit, 2 when none
////   does, any other fails), and `0x1404a2100` (a type with no case, such as 17,
////   fails).
//// - The unit's difficulty, type 179 (`0x14049eeb0`): compared with the condition's
////   objectId, not its value, and read only where the subject holds a difficulty.
//// - The client's comparison `0x1404a2090` (1 equal, 2 not equal, 3 greater, 4 at
////   least, 5 less, 6 at most, unsigned 32-bit; any other fails) and its types
////   `Prerequisite.prerequisiteTypeId.28` (in combat: comparison 1 in, 2 out),
////   `.37` (a roll of 1 + floor(100 r) with r in [0, 1)), `.71` and `0x1404a4e30`
////   (percentage of the maximum, in 32-bit floats; 0 of 0 is not a number, which
////   is equal and nothing else) and `.73` (the current value cut toward zero).

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{
  type Subject, AtLeast, AtMost, Equal, Fails, Greater, Less, NeverRelation,
  NotEqual, NotRead, Passes, Subject, Vital,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support

/// Row 24581, Relentless Strikes' +180: (15, 2, 0, 42908), then type 0 with
/// comparison 2 and value 60947.
fn row_24581() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 24_581, flags: 0, conditions: [
    #(15, 2, 0, 42_908),
    #(0, 2, 0, 60_947),
  ])
}

/// Row 24582, the +200: (15, 2, 0, 42908), (15, 2, 0, 60947), (15, 1, 0, 59208).
fn row_24582() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 24_582, flags: 0, conditions: [
    #(15, 2, 0, 42_908),
    #(15, 2, 0, 60_947),
    #(15, 1, 0, 59_208),
  ])
}

/// Row 43811, Energize's +4: (15, 2, 732, 58999).
fn row_43811() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 43_811, flags: 0, conditions: [
    #(15, 2, 732, 58_999),
  ])
}

/// Row 43812, Energize's ticking +1: (15, 1, 0, 58999).
fn row_43812() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 43_812, flags: 0, conditions: [
    #(15, 1, 0, 58_999),
  ])
}

/// A subject under no cast, out of combat, holding no vital, difficulty or stealth,
/// with no roll.
fn bare() -> Subject {
  Subject(
    under: [],
    second_unit: None,
    in_combat: False,
    vitals: dict.new(),
    rolls: [],
    difficulty: None,
    stealthed: None,
    resource_slots: None,
    positions: prerequisite.NotPlaced,
    factions: None,
    player: None,
    quests: None,
    creature_index: None,
    seen: prerequisite.WholeUnit,
  )
}

fn check(
  row: prerequisite_table.Prerequisite,
  under: List(Int),
) -> prerequisite.Verdict {
  prerequisite_support.check(
    row: row,
    subject: Subject(
      ..bare(),
      under: list.map(under, fn(spell4_id) {
        lasting.Held(
          spell4_id: Spell4Id(spell4_id),
          caster: 0,
          count: 0,
          groups: [],
        )
      }),
    ),
  )
}

// ---- 11 ----

pub fn row_24581_passes_with_no_live_cast_and_fails_under_overdrive_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24581(), []) == Passes
    as "comparison 2 on 42908: no cast of Overdrive targets the Warrior"
  assert check(row_24581(), [42_908]) == Fails
    as "a live cast of Overdrive 42908 targets the Warrior: comparison 2 fails"
}

// ---- 12 ----

pub fn row_24582_fails_with_none_live_and_passes_under_59208_alone_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24582(), []) == Fails
    as "its third condition, comparison 1 on 59208, finds no cast"
  assert check(row_24582(), [59_208]) == Passes
    as "not under 42908 nor 60947, and under 59208"
  assert check(row_24582(), [59_208, 60_947]) == Fails
    as "under 60947 its second condition fails"
}

// ---- 13 ----

pub fn rows_43811_and_43812_exclude_each_other_on_power_cadence_test() -> Nil {
  use <- owned_test.run(5000)
  assert #(check(row_43811(), []), check(row_43812(), [])) == #(Passes, Fails)
    as "not under Power Cadence 58999: the +4 passes, the ticking +1 fails"
  assert #(check(row_43811(), [58_999]), check(row_43812(), [58_999]))
    == #(Fails, Passes)
    as "under 58999: the other way round; objectId 732 is not read"
}

// ---- 14 ----

pub fn the_row_is_cut_at_its_first_type_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24581(), [60_947]) == Passes
    as "row 24581's second condition (comparison 2, value 60947) has type 0, so it is dropped (0x1404a5190): 60947 live changes nothing"
  let cut =
    prerequisite_support.row(id: 1, flags: 0, conditions: [
      #(15, 2, 0, 10),
      #(0, 0, 0, 0),
      #(15, 1, 0, 11),
    ])
  assert check(cut, []) == Passes
    as "a condition after a type 0 is dropped too, whatever it holds"
}

pub fn flags_bit_0_makes_the_row_pass_when_any_condition_does_test() -> Nil {
  use <- owned_test.run(5000)
  let conditions = [#(15, 1, 0, 10), #(15, 1, 0, 11)]
  assert check(prerequisite_support.row(id: 1, flags: 0, conditions:), [10])
    == Fails
    as "AND: 11 is not live"
  assert check(prerequisite_support.row(id: 1, flags: 1, conditions:), [10])
    == Passes
    as "flags bit 0: OR"
  assert check(prerequisite_support.row(id: 1, flags: 1, conditions:), [])
    == Fails
    as "OR with no condition passing"
  assert check(prerequisite_support.row(id: 1, flags: 2, conditions:), [10])
    == Fails
    as "only bit 0 is read: flags 2 is AND"
}

pub fn a_row_with_no_kept_condition_passes_under_and_and_fails_under_or_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(prerequisite_support.row(id: 1, flags: 0, conditions: []), [])
    == Passes
  assert check(prerequisite_support.row(id: 1, flags: 1, conditions: []), [])
    == Fails
}

pub fn an_unread_type_is_not_read_and_a_type_with_no_client_case_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(43, 1, 0, 1),
      ]),
      [],
    )
    == NotRead(prerequisite_type: 43)
    as "type 43 (the quest log) has a case in the client (0x1404a2100, Prerequisite.prerequisiteTypeId.43) that the server does not read"
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [#(17, 1, 0, 0)]),
      [],
    )
    == Fails
    as "type 17 has no case in the client: it fails (0x1404a2100)"
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [#(296, 1, 0, 0)]),
      [],
    )
    == Fails
    as "a type above 295 fails (0x1404a2100)"
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(15, 1, 0, 10),
        #(59, 1, 42_569, 2),
      ]),
      [],
    )
    == Fails
    as "under AND a failed condition decides the row whatever an unread one would give"
  assert check(
      prerequisite_support.row(id: 1, flags: 1, conditions: [
        #(59, 1, 42_569, 2),
        #(15, 1, 0, 10),
      ]),
      [10],
    )
    == Passes
    as "under OR a passing condition decides the row whatever an unread one would give"
}

pub fn a_type_15_comparison_other_than_1_or_2_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [#(15, 3, 0, 10)]),
      [10],
    )
    == Fails
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [#(15, 0, 0, 10)]),
      [],
    )
    == Fails
}

// ---- the comparisons, 28, 37, 71 and 73 ----

pub fn each_comparison_from_1_to_6_decides_at_below_and_above_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  let verdicts = fn(code) {
    [4, 5, 6]
    |> list.map(fn(measured) {
      prerequisite.compare(
        relation: prerequisite.relation_of(code:),
        measured:,
        value: 5,
      )
    })
  }
  assert verdicts(1) == [False, True, False] as "0x1404a2090: 1 is equal"
  assert verdicts(2) == [True, False, True] as "0x1404a2090: 2 is not equal"
  assert verdicts(3) == [False, False, True]
    as "0x1404a2090: 3 is greater than the value"
  assert verdicts(4) == [False, True, True] as "0x1404a2090: 4 is at least"
  assert verdicts(5) == [True, False, False]
    as "0x1404a2090: 5 is less than the value"
  assert verdicts(6) == [True, True, False] as "0x1404a2090: 6 is at most"
  assert verdicts(0) == [False, False, False]
    as "0x1404a2090: any other comparison is false, 0 among them"
  assert verdicts(7) == [False, False, False]
    as "0x1404a2090: 7 is another comparison"
  assert list.map([1, 2, 3, 4, 5, 6, 7], fn(code) {
      prerequisite.relation_of(code:)
    })
    == [Equal, NotEqual, Greater, AtLeast, Less, AtMost, NeverRelation(code: 7)]
    as "the codes in the order 0x1404a2090 gives them"
}

pub fn comparisons_read_unsigned_32_bit_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite.compare(relation: Greater, measured: -1, value: 5)
    as "0x1404a2090 compares unsigned: -1 is 0xFFFFFFFF, above 5"
  assert prerequisite.compare(
    relation: Equal,
    measured: 4_294_967_295,
    value: -1,
  )
    as "a value stored as -1 is 0xFFFFFFFF"
}

pub fn type_28_passes_in_combat_by_comparison_1_and_out_of_it_by_comparison_2_test() -> Nil {
  use <- owned_test.run(5000)
  let in_combat = Subject(..bare(), in_combat: True)
  let comparison = fn(code) {
    prerequisite_support.row(id: 903, flags: 0, conditions: [#(28, code, 0, 0)])
  }
  assert #(
      prerequisite_support.check(row: comparison(1), subject: in_combat),
      prerequisite_support.check(row: comparison(2), subject: in_combat),
    )
    == #(Passes, Fails)
    as "Prerequisite.prerequisiteTypeId.28: in combat, comparison 1 passes and 2 fails"
  assert #(
      prerequisite_support.check(row: comparison(1), subject: bare()),
      prerequisite_support.check(row: comparison(2), subject: bare()),
    )
    == #(Fails, Passes)
    as "out of combat the reverse"
  assert prerequisite_support.check(row: comparison(3), subject: in_combat)
    == Fails
    as "any other comparison fails"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(28, 1, 24, 7),
      ]),
      subject: in_combat,
    )
    == Passes
    as "the objectId and the value are not read (24 conditions hold an objectId and 26 a value)"
}

pub fn challenge_with_no_record_is_not_in_cooldown_test() -> Nil {
  use <- owned_test.run(5000)
  let comparison = fn(code) {
    prerequisite_support.row(id: 903, flags: 0, conditions: [
      #(125, code, 328, 0),
    ])
  }
  assert #(
      prerequisite_support.check(row: comparison(1), subject: bare()),
      prerequisite_support.check(row: comparison(2), subject: bare()),
      prerequisite_support.check(row: comparison(3), subject: bare()),
    )
    == #(Fails, Passes, Fails)
    as "Prerequisite.prerequisiteTypeId.125, 0x14049fac0: a challenge the server has sent no record for is not in cooldown, so comparison 1 fails, 2 passes and any other fails"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 9358, flags: 1, conditions: [
        #(125, 2, 328, 0),
        #(11, 1, 328, 0),
      ]),
      subject: bare(),
    )
    == Passes
    as "Prerequisite 9358 (type 125 comparison 2 on challenge 328, or nested row 328, which has no row and fails) passes through its first condition"
}

pub fn challenge_with_no_record_is_not_active_and_not_unlocked_test() -> Nil {
  use <- owned_test.run(5000)
  let comparisons = fn(type_id) {
    let row = fn(code) {
      prerequisite_support.row(id: 903, flags: 0, conditions: [
        #(type_id, code, 328, 0),
      ])
    }
    #(
      prerequisite_support.check(row: row(1), subject: bare()),
      prerequisite_support.check(row: row(2), subject: bare()),
      prerequisite_support.check(row: row(3), subject: bare()),
    )
  }
  assert comparisons(69) == #(Fails, Passes, Fails)
    as "Prerequisite.prerequisiteTypeId.69, 0x14048d530: a challenge with no record is not active, so comparison 1 fails, 2 passes and any other fails"
  assert comparisons(74) == #(Fails, Passes, Fails)
    as "Prerequisite.prerequisiteTypeId.74, 0x14048d5a0: a challenge with no record has its flag clear, so comparison 1 fails, 2 passes and any other fails"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 18_822, flags: 1, conditions: [
        #(74, 2, 328, 0),
        #(69, 1, 328, 0),
      ]),
      subject: bare(),
    )
    == Passes
    as "Prerequisite 18822 (type 74 comparison 2 on challenge 328, or type 69 comparison 1 on it) passes through its first condition"
}

pub fn type_37_compares_its_roll_with_the_value_by_the_comparison_test() -> Nil {
  use <- owned_test.run(5000)
  let chance =
    prerequisite_support.row(id: 4585, flags: 0, conditions: [#(37, 6, 0, 50)])
  let rolled = fn(roll) {
    prerequisite_support.check(
      row: chance,
      subject: Subject(..bare(), rolls: [roll]),
    )
  }
  assert #(rolled(49), rolled(50), rolled(51)) == #(Passes, Passes, Fails)
    as "row 4585: comparison 6, value 50, so a roll of 50 or less passes: a chance of value / 100"
  assert prerequisite.rolls_needed(
      prerequisite: prerequisite_support.loaded(id: chance.id, rows: [chance]),
    )
    == 1
    as "one roll for the one type 37 condition"
  assert prerequisite.rolls_needed(
      prerequisite: prerequisite_support.loaded(id: 24_582, rows: [row_24582()]),
    )
    == 0
    as "a row with no type 37 condition takes no roll"
}

pub fn each_type_37_condition_takes_a_roll_of_its_own_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let both =
    prerequisite_support.row(id: 1, flags: 0, conditions: [
      #(37, 6, 0, 50),
      #(37, 4, 0, 90),
    ])
  assert prerequisite.rolls_needed(
      prerequisite: prerequisite_support.loaded(id: 1, rows: [both]),
    )
    == 2
  assert prerequisite_support.check(
      row: both,
      subject: Subject(..bare(), rolls: [10, 95]),
    )
    == Passes
    as "Prerequisite.prerequisiteTypeId.37: the client draws each time a condition is tested: 10 is at most 50 and 95 at least 90"
  assert prerequisite_support.check(
      row: both,
      subject: Subject(..bare(), rolls: [95, 10]),
    )
    == Fails
    as "the first roll is the first condition's"
  assert prerequisite_support.check(row: both, subject: bare())
    == NotRead(prerequisite_type: 37)
    as "no roll given is a roll the server does not have"
}

pub fn a_draw_of_4_bytes_makes_a_roll_of_1_plus_the_floor_of_100_times_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite.rolls_of(bytes: <<0:size(32)>>) == [1]
    as "Prerequisite.prerequisiteTypeId.37: a draw of 0 makes 1 + floor(0)"
  assert prerequisite.rolls_of(bytes: <<0xFFFFFFFF:size(32)>>) == [100]
    as "a draw just under 1 makes 1 + floor(99.99999998)"
  assert prerequisite.rolls_of(bytes: <<0x80000000:size(32)>>) == [51]
    as "a draw of 0.5 makes 1 + 50"
  assert prerequisite.rolls_of(bytes: <<0x7FFFFFFF:size(32)>>) == [50]
    as "a draw just under 0.5 makes 1 + 49"
  assert prerequisite.rolls_of(bytes: <<0:size(32), 0x80000000:size(32)>>)
    == [1, 51]
    as "4 bytes for each roll, in order"
  assert prerequisite.roll_bytes == 4 as "a roll is 4 bytes"
}

pub fn type_71_compares_the_vitals_percentage_of_its_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  let held = fn(current, maximum) {
    Subject(..bare(), vitals: dict.from_list([#(6, Vital(current:, maximum:))]))
  }
  let comparison = fn(code) {
    prerequisite_support.row(id: 4918, flags: 0, conditions: [
      #(71, code, 6, 50),
    ])
  }
  assert list.map([1, 2, 3, 4, 5, 6], fn(code) {
      prerequisite_support.check(
        row: comparison(code),
        subject: held(50.0, 100.0),
      )
    })
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "0x1404a4e30: 50 of 100 is 50 percent, equal to the value 50 under 1, 4 and 6 and under no other"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(71, 3, 6, 33),
      ]),
      subject: held(1.0, 3.0),
    )
    == Passes
    as "1 of 3 is 33.333332 percent in 32-bit floats, above 33"
  assert prerequisite_support.check(row: comparison(1), subject: held(0.0, 0.0))
    == Passes
    as "0x1404a4e30: 0 of 0 is not a number, which counts as equal"
  assert list.map([2, 3, 4, 5, 6], fn(code) {
      prerequisite_support.check(row: comparison(code), subject: held(0.0, 0.0))
    })
    == [Fails, Fails, Fails, Fails, Fails]
    as "and fails every other comparison"
}

pub fn type_73_compares_the_current_value_cut_toward_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let held =
    Subject(
      ..bare(),
      vitals: dict.from_list([#(6, Vital(current: 99.9, maximum: 1000.0))]),
    )
  let comparison = fn(code, value) {
    prerequisite_support.row(id: 11_153, flags: 0, conditions: [
      #(73, code, 6, value),
    ])
  }
  assert prerequisite_support.check(row: comparison(1, 99), subject: held)
    == Passes
    as "Prerequisite.prerequisiteTypeId.73: 99.9 is cut to 99, equal to 99"
  assert prerequisite_support.check(row: comparison(1, 100), subject: held)
    == Fails
    as "it is not rounded to 100"
  assert prerequisite_support.check(row: comparison(4, 100), subject: held)
    == Fails
    as "row 11153's comparison 4 on 100: 99 is not at least 100"
}

pub fn type_71_with_something_held_of_a_zero_maximum_is_beyond_every_value_test() -> Nil {
  use <- owned_test.run(5000)
  let held =
    Subject(
      ..bare(),
      vitals: dict.from_list([#(6, Vital(current: 5.0, maximum: 0.0))]),
    )
  let comparison = fn(code) {
    prerequisite_support.row(id: 1, flags: 0, conditions: [#(71, code, 6, 100)])
  }
  assert list.map([1, 2, 3, 4, 5, 6], fn(code) {
      prerequisite_support.check(row: comparison(code), subject: held)
    })
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "0x1404a4e30: 5 of 0 is 500 over 0, positive infinity in 32-bit floats, above the value 100 under 2, 3 and 4 and under no other"
}

pub fn type_179_compares_the_units_difficulty_with_the_object_id_not_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  let of_difficulty = fn(difficulty) {
    Subject(..bare(), difficulty: Some(difficulty))
  }
  let comparison = fn(code) {
    prerequisite_support.row(id: 30_526, flags: 0, conditions: [
      #(179, code, 6, 99),
    ])
  }
  assert list.map([1, 2, 3, 4, 5, 6], fn(code) {
      prerequisite_support.check(
        row: comparison(code),
        subject: of_difficulty(6),
      )
    })
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "0x14049eeb0: difficulty 6 against the objectId 6 is equal, at least and at most"
  assert list.map([1, 2, 3, 4, 5, 6], fn(code) {
      prerequisite_support.check(
        row: comparison(code),
        subject: of_difficulty(7),
      )
    })
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "difficulty 7 is above the objectId 6, whatever the value 99 holds"
  assert list.map([0, 7], fn(code) {
      prerequisite_support.check(
        row: comparison(code),
        subject: of_difficulty(6),
      )
    })
    == [Fails, Fails]
    as "0x1404a2090: a comparison other than 1 to 6 fails"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 30_527, flags: 0, conditions: [
        #(179, 4, 7, 0),
      ]),
      subject: of_difficulty(6),
    )
    == Fails
    as "row 30527 (at least 7) fails a creature of difficulty 6"
}

pub fn type_179_with_no_difficulty_held_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 30_526, flags: 0, conditions: [
        #(179, 6, 6, 0),
      ]),
      subject: bare(),
    )
    == NotRead(prerequisite_type: 179)
    as "a subject with no unit difficulty, a player's, leaves type 179 to the client"
}

pub fn a_vital_the_server_does_not_hold_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(73, 1, 15, 0),
      ]),
      subject: bare(),
    )
    == NotRead(prerequisite_type: 73)
    as "no vital is held, so type 73 cannot read vital 15 (Focus), which no rule of the server holds"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(71, 1, 1, 100),
      ]),
      subject: bare(),
    )
    == NotRead(prerequisite_type: 71)
    as "type 71 of Health with none held"
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 1, conditions: [
        #(73, 1, 15, 0),
        #(28, 2, 0, 0),
      ]),
      subject: bare(),
    )
    == Passes
    as "under OR a passing condition decides the row whatever an unread vital would give"
}

pub fn the_types_the_server_decides_are_those_is_read_names_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.filter(types_up_to_300(), fn(type_id) {
      prerequisite.is_read(type_id:)
    })
    == [
      0, 1, 2, 3, 4, 6, 10, 11, 15, 17, 21, 22, 23, 26, 28, 32, 33, 34, 35, 36,
      37, 39, 43, 45, 50, 52, 57, 58, 59, 64, 68, 69, 71, 72, 73, 74, 75, 94,
      108, 109, 116, 125, 129, 132, 144, 156, 157, 158, 161, 165, 179, 181, 202,
      243, 247, 249, 250, 257, 258, 274, 282, 284, 296, 297, 298, 299, 300,
    ]
    as "the types the server reads (1 to 4, 6, 10, 11, 15, 22, 23, 26, 28, 33 to 37, 39, 43, 50, 52, 59, 64, 68, 69, 71, 73, 74, 94, 108, 109, 116, 125, 129, 179, 243, 250; Prerequisite.prerequisiteTypeId.1, .2, .3, .4, .6, .10, .11, .22, .26, .39, .43, .52, .64, .68, .69, .74, .94, .108, .109, .116, .129, .243, .250) and the types the client's check has no case for, which it fails as the client does (0x1404a2100: 0, those 24 and those above 295)"
}

fn types_up_to_300() -> List(Int) {
  int.range(from: 300, to: -1, with: [], run: fn(types, type_id) {
    [type_id, ..types]
  })
}
