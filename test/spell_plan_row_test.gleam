//// What the plan makes of one effect row (`genesis_prime/game/spell_plan` `read_row`), the
//// decision its lists and the coverage measure are both made from. Expected values come
//// from these places.
//// - `cast.condition_gate` (`genesis_prime/game/cast`): a row behind a target apply
////   prerequisite is applied by no go, and a `TickingShieldHeal` is held, since each tick
////   needs a 0x7f8 the server does not send (`Spell4Effects.effectType.118`).
//// - `proc_read`: a Proc of a kind other than 217, 218, 44 and 0 is in no list and the load
////   goes on (`Spell4Effects.effectType.14`).
//// - The plan's Proxy rule: a Proxy whose dataBits00 names no spell makes no child, so the
////   plan holds none (`Spell4Effects.effectType.26`).
//// - `Spell4.innateCostEMMId0`: a cost with an EMM id of 4 or 7 on a slot cost spends every
////   point held, which gives each effect of the spell a tag the rule must read (0 or 1).
//// The rows are planted on Telekinetic Strike's spell (`spell_tables`).

import fixture_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/spell_plan.{
  Applied, Held, LeftOut, PlannedProc, PlannedProxy, ProcOfAnotherKind,
  ProxyNamesNoSpell, ReadByArea,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import owned_test
import planted_table.{type Cell, Float, Integer}
import spell_tables

/// 1.0 as 32 float bits.
const one_as_float_bits = 1_065_353_216

/// A planted row of Telekinetic Strike's spell.
fn row(
  id id: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  spell_tables.effect_row_with(id:, effect_type:, target_flags:, columns:)
}

/// The rows of the planted spell, one for each kind the plan lists, and the five the plan
/// holds or leaves out: ids 90001 to 90012 are read, 90013 is behind a target apply
/// prerequisite, 90014 is a periodic heal, 90015 is a Proc of kind 12 and 90016 a Proxy
/// with dataBits00 0.
fn planted() -> List(List(Cell)) {
  [
    row(id: 90_001, effect_type: 1, target_flags: 1, columns: [
      #("dataBits00", Integer(6)),
      #("dataBits02", Integer(5)),
    ]),
    row(id: 90_002, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
    ]),
    row(id: 90_003, effect_type: 80, target_flags: 1, columns: [
      #("dataBits00", Integer(2)),
      #("dataBits01", Integer(32_893)),
    ]),
    row(id: 90_004, effect_type: 4, target_flags: 2, columns: [
      #("durationTime", Integer(1000)),
    ]),
    row(id: 90_005, effect_type: 11, target_flags: 1, columns: [
      #("dataBits00", Integer(7)),
      #("durationTime", Integer(5000)),
    ]),
    row(id: 90_006, effect_type: 3, target_flags: 1, columns: []),
    row(id: 90_007, effect_type: 73, target_flags: 1, columns: [
      #("dataBits02", Integer(0)),
    ]),
    row(id: 90_008, effect_type: 83, target_flags: 1, columns: []),
    row(id: 90_009, effect_type: 84, target_flags: 1, columns: []),
    row(id: 90_010, effect_type: 118, target_flags: 1, columns: [
      #("dataBits00", Integer(one_as_float_bits)),
      #("parameterType00", Integer(22)),
      #("parameterValue00", Float(0.3)),
    ]),
    row(
      id: 90_011,
      effect_type: 14,
      target_flags: 1,
      columns: proc_columns(kind: 217),
    ),
    row(id: 90_012, effect_type: 26, target_flags: 1, columns: [
      #("dataBits00", Integer(30_900)),
    ]),
    row(id: 90_013, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
      #("prerequisiteIdTargetApply", Integer(11_311)),
    ]),
    row(id: 90_014, effect_type: 118, target_flags: 1, columns: [
      #("dataBits00", Integer(one_as_float_bits)),
      #("parameterType00", Integer(22)),
      #("parameterValue00", Float(0.3)),
      #("tickTime", Integer(1000)),
      #("durationTime", Integer(8000)),
    ]),
    row(
      id: 90_015,
      effect_type: 14,
      target_flags: 1,
      columns: proc_columns(kind: 12),
    ),
    row(id: 90_016, effect_type: 26, target_flags: 1, columns: [
      #("dataBits00", Integer(0)),
    ]),
  ]
}

/// A Proc row that casts Spell4 30900, whose columns the plan reads: chance 1.0, a window
/// of 500 ms, a count of 1 and a durationTime for its life.
fn proc_columns(kind kind: Int) -> List(#(String, Cell)) {
  [
    #("dataBits00", Integer(kind)),
    #("dataBits01", Integer(30_900)),
    #("dataBits02", Integer(one_as_float_bits)),
    #("dataBits04", Integer(500)),
    #("dataBits05", Integer(1)),
    #("durationTime", Integer(5000)),
  ]
}

/// Whether the client's Spell4Effects table holds a row of this id.
fn client_row(id id: Int) -> Bool {
  list.any(spell_tables.fixture_rows().spell4_effects, fn(row) {
    row == [Integer(id), ..list.drop(row, 1)]
  })
}

/// Whether this id lies between these two and is not an id of a client row.
fn planted_between(id id: Int, low low: Int, high high: Int) -> Bool {
  id >= low && id < high && !client_row(id:)
}

/// The client's rows with these effect rows added, each of an id the client's table
/// does not hold.
fn rows_with(effects effects: List(List(Cell))) -> spell_tables.Rows {
  let rows = spell_tables.fixture_rows()
  list.each(effects, fn(effect) {
    let assert [Integer(id), ..] = effect as "a planted row holds its ID first"
    assert !client_row(id:)
      as "a planted id the client's table holds would replace the client's row"
  })
  spell_tables.Rows(
    ..rows,
    spell4_effects: spell_tables.sorted_by_id(list.append(
      effects,
      rows.spell4_effects,
    )),
  )
}

pub fn a_planted_spell_lists_the_applied_and_held_rows_and_the_measure_counts_only_the_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = rows_with(effects: planted())
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
    as "the planted spell loads: every row of it is read or left out"
  assert spell_tables.listed_effect_ids(spell:)
    |> list.filter(planted_between(id: _, low: 90_000, high: 91_000))
    |> list.sort(int.compare)
    == [
      90_001, 90_002, 90_003, 90_004, 90_005, 90_006, 90_007, 90_008, 90_009,
      90_010, 90_011, 90_012, 90_013, 90_014,
    ]
    as "the lists hold the twelve read rows, the row behind a target apply prerequisite (90013, held and applied by no go, `cast.condition_gate`) and the periodic heal (90014, a `TickingShieldHeal`); the Proc of kind 12 (`proc_read`) and the Proxy that names no spell are in no list"
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let spell_groups = spell_plan.spell_groups(tables:)
      let effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) {
          planted_between(id: effect.id, low: 90_000, high: 91_000)
        })
      let read = fn(effect: Spell4Effects) {
        spell_plan.read_row(
          tables:,
          spell_groups:,
          place: spell_tables.pressed,
          effect:,
        )
      }
      let verdicts =
        list.map(effects, fn(effect) {
          let kind = case read(effect) {
            Ok(Applied(..)) -> "applied"
            Ok(Held(..)) -> "held"
            Ok(LeftOut(..)) -> "left out"
            Ok(ReadByArea) -> "area"
            Error(error) -> "refused: " <> spell_plan.describe(error:)
          }
          #(effect.id, kind)
        })
      assert verdicts
        == list.append(
          list.map(
            [
              90_001, 90_002, 90_003, 90_004, 90_005, 90_006, 90_007, 90_008,
              90_009, 90_010, 90_011, 90_012,
            ],
            fn(id) { #(id, "applied") },
          ),
          [
            #(90_013, "held"),
            #(90_014, "held"),
            #(90_015, "left out"),
            #(90_016, "left out"),
          ],
        )
        as "the rule each row checks: a gate behind a target apply prerequisite, a periodic heal, a Proc of a kind not read and a Proxy that names no spell"
      let assert Ok(Applied(PlannedProc(..))) =
        read(first_of(effects:, id: 90_011))
        as "the Proc of kind 217 is read and its spell is planned from the reading"
      assert read(first_of(effects:, id: 90_015))
        == Ok(LeftOut(why: ProcOfAnotherKind(kind: 12)))
      assert read(first_of(effects:, id: 90_016))
        == Ok(LeftOut(why: ProxyNamesNoSpell))
      let assert Ok(Applied(PlannedProxy(..))) =
        read(first_of(effects:, id: 90_012))
        as "the Proxy that names a spell is read"
      assert effect_row.unread_by_type(tables:, effects:)
        == dict.from_list([#(17, 1), #(118, 1), #(14, 1), #(26, 1)])
        as "the measure counts only the rows a go applies as read: one Fluff behind a target prerequisite, the periodic heal, the Proc of kind 12 and the Proxy with dataBits00 0 are not"
    },
  )
}

fn first_of(effects effects: List(Spell4Effects), id id: Int) -> Spell4Effects {
  let assert Ok(found) = list.find(effects, fn(effect) { effect.id == id })
    as "the planted row is there"
  found
}

pub fn a_spend_all_spell_refuses_an_effect_tag_the_rule_does_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mind Burst's Spell4 32809 spends every point of slot 1 (innateCostEMMId0 4 on a
  // cost of type 6, `Spell4.32809`). Its damage effects 61993 and 61994 hold
  // emmComparison 0 in the client's rows; no client row holds a 2, and the server's
  // load refuses one (`spell_plan_spend_test`), so the two effects here are those rows
  // as records with emmComparison 2 and 1, read without a load.
  let tables = fixture_tables.shared()
  let assert Ok(mind_burst) = spell4.get(tables:, id: Spell4Id(32_809))
    as "Mind Burst is in the client's rows"
  assert spell_plan.spends_all(tables:, row: mind_burst)
    as "innateCostEMMId0 4 on a slot cost is a spend of every point held"
  let effect_of = fn(id) {
    let assert Ok(found) =
      list.find(spell4_effects.all(tables), fn(effect) { effect.id == id })
      as "the client's row is there"
    found
  }
  let refused =
    Spell4Effects(..effect_of(61_993), emm_comparison: 2, emm_value: 0)
  let read = Spell4Effects(..effect_of(61_994), emm_comparison: 1, emm_value: 0)
  let effects = [refused, read]
  let spends = spell_plan.RowPlace(struck_by: None, spends_all: True)
  assert spell_plan.read_row(
      tables:,
      spell_groups: spell_plan.spell_groups(tables:),
      place: spends,
      effect: refused,
    )
    == Error(spell_plan.SpendComparisonNotRead(
      spell4_id: 32_809,
      effect_id: refused.id,
      comparison: 2,
    ))
    as "emmComparison 2 chooses nothing the rule reads (Spell4Effects.emmComparison)"
  assert spell_plan.read_row(
      tables:,
      spell_groups: spell_plan.spell_groups(tables:),
      place: spends,
      effect: read,
    )
    == Ok(ReadByArea)
    as "emmComparison 1 is read"
  assert effect_row.unread_by_type(tables:, effects:)
    == dict.from_list([#(8, 1)])
    as "the measure counts the refused row not read and the other read, the spell's cost read from its Spell4 row"
}

pub fn a_row_whose_tables_lack_its_prerequisite_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // A Fluff row whose prerequisiteIdCasterApply names Prerequisite 99, which the planted
  // table has no row for: the plan fails the load with NoRow and the measure counts the row
  // not read, and goes on.
  let planted_row =
    row(id: 90_021, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
      #("prerequisiteIdCasterApply", Integer(99)),
    ])
  let rows = rows_with(effects: [planted_row])
  assert spell_tables.derivation_result(reaching: [#("SpellLevel", 647)], rows:)
    |> result.is_error
    as "the plan's load fails on the row"
  assert spell_tables.planned_strike(rows:)
    == Error(spell_plan.NoRow(table: "Prerequisite", id: 99))
    as "Spell4Effects.prerequisiteIdCasterApply names a Prerequisite row the table lacks"
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) { effect.id == 90_021 })
      assert effect_row.unread_by_type(tables:, effects:)
        == dict.from_list([#(17, 1)])
        as "the measure counts the row not read, without stopping"
    },
  )
}

pub fn a_row_whose_prerequisites_nest_each_other_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 910 nests 911 and 911 nests 910 (a type 11 condition's objectId names the
  // nested row, `Prerequisite.prerequisiteTypeId.11`), and a Fluff row names 910 as its
  // caster apply prerequisite: the plan's load refuses the cycle and the measure counts the
  // row not read.
  let planted_row =
    row(id: 90_031, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
      #("prerequisiteIdCasterApply", Integer(910)),
    ])
  let rows =
    spell_tables.Rows(
      ..rows_with(effects: [planted_row]),
      prerequisites: spell_tables.sorted_by_id([
        spell_tables.prerequisite_row(id: 910, flags: 0, conditions: [
          #(11, 1, 911, 0),
        ]),
        spell_tables.prerequisite_row(id: 911, flags: 0, conditions: [
          #(11, 1, 910, 0),
        ]),
        ..spell_tables.fixture_rows().prerequisites
      ]),
    )
  assert spell_tables.planned_strike(rows:)
    == Error(spell_plan.PrerequisiteCycle(path: [910, 911, 910]))
    as "the rows nest each other round a cycle"
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) { effect.id == 90_031 })
      assert effect_row.unread_by_type(tables:, effects:)
        == dict.from_list([#(17, 1)])
        as "the measure counts the row not read, without stopping"
    },
  )
}

pub fn a_property_row_with_no_life_is_held_whatever_its_type_test() -> Nil {
  use <- owned_test.run(60_000)
  // `lasting.has_life`: a durationTime or flags bit 2; the cast rule drops a modifier with
  // neither (`modifier_has_life`). Planted: a type 11, 145 and 52 row each with and
  // without a durationTime, aimed at the caster.
  let timed = [#("durationTime", Integer(5000))]
  let rows = [
    #(11, [#("dataBits00", Integer(7))]),
    #(145, [#("dataBits00", Integer(7)), #("dataBits01", Integer(8))]),
    #(52, [#("dataBits00", Integer(1))]),
  ]
  let effects =
    list.flat_map(rows, fn(planted) {
      let #(effect_type, columns) = planted
      [
        row(
          id: 90_100 + effect_type,
          effect_type:,
          target_flags: 1,
          columns: list.append(timed, columns),
        ),
        row(id: 91_100 + effect_type, effect_type:, target_flags: 1, columns:),
      ]
    })
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows: rows_with(effects:),
    body: fn(tables) {
      let planted_effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) {
          planted_between(id: effect.id, low: 90_100, high: 92_000)
        })
      let spell_groups = spell_plan.spell_groups(tables:)
      let verdicts =
        list.map(planted_effects, fn(effect) {
          let reading =
            spell_plan.read_row(
              tables:,
              spell_groups:,
              place: spell_tables.pressed,
              effect:,
            )
          #(effect.id, case reading {
            Ok(Applied(..)) -> "applied"
            Ok(Held(..)) -> "held"
            Ok(LeftOut(..)) | Ok(ReadByArea) | Error(..) -> "other"
          })
        })
      assert verdicts
        == [
          #(90_152, "applied"),
          #(90_111, "applied"),
          #(90_245, "applied"),
          #(91_152, "held"),
          #(91_111, "held"),
          #(91_245, "held"),
        ]
        |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
        as "a row with a durationTime is applied, one with no life is held: the plan lists both"
      assert effect_row.unread_by_type(tables:, effects: planted_effects)
        == dict.from_list([#(52, 1), #(11, 1), #(145, 1)])
        as "the measure counts the three rows with no life not read"
    },
  )
}

pub fn a_row_no_phase_selects_is_held_and_a_damage_row_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // `in_phase`: bit n of phaseFlags is phase n, so phaseFlags 0 is no phase and no go
  // applies the row; what the client means by 0 is not known. Planted: a Fluff row, a Proxy
  // to Spell4 30900 and a damage row with phaseFlags 0, and the same Fluff row with -1.
  let none = [#("phaseFlags", Integer(0))]
  let effects = [
    row(id: 92_001, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
      ..none
    ]),
    row(id: 92_002, effect_type: 26, target_flags: 1, columns: [
      #("dataBits00", Integer(30_900)),
      ..none
    ]),
    row(id: 92_003, effect_type: 8, target_flags: 2, columns: none),
    row(id: 92_004, effect_type: 17, target_flags: 1, columns: [
      #("durationTime", Integer(5000)),
    ]),
  ]
  let rows = rows_with(effects:)
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
    as "the planted spell loads"
  assert spell_tables.listed_effect_ids(spell:)
    |> list.filter(planted_between(id: _, low: 92_000, high: 93_000))
    |> list.sort(int.compare)
    == [92_001, 92_002, 92_004]
    as "the plan lists the Fluff and the Proxy of phaseFlags 0, which no phase applies, beside the Fluff of -1; the damage row is in no list"
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let planted_effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) {
          planted_between(id: effect.id, low: 92_000, high: 93_000)
        })
      let spell_groups = spell_plan.spell_groups(tables:)
      let read = fn(id) {
        spell_plan.read_row(
          tables:,
          spell_groups:,
          place: spell_tables.pressed,
          effect: first_of(effects: planted_effects, id:),
        )
      }
      let assert Ok(Held(..)) = read(92_001)
        as "a lasting row no phase selects is held"
      let assert Ok(Held(PlannedProxy(..))) = read(92_002)
        as "so is a Proxy, and its child is still planned"
      assert read(92_003) == Ok(LeftOut(why: spell_plan.InNoPhase))
      let assert Ok(Applied(..)) = read(92_004)
      assert effect_row.unread_by_type(tables:, effects: planted_effects)
        == dict.from_list([#(17, 1), #(26, 1), #(8, 1)])
        as "the measure counts the three rows no phase selects not read, and the Fluff of -1 read"
    },
  )
}
