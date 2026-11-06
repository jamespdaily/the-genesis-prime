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

import genesis_prime/coverage/effect_row
import genesis_prime/game/spell_plan.{
  Applied, Held, LeftOut, PlannedProc, PlannedProxy, ProcOfAnotherKind,
  ProxyNamesNoSpell, ReadByArea,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
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

fn rows_with(effects effects: List(List(Cell))) -> spell_tables.Rows {
  let rows = spell_tables.rows()
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
    |> list.filter(fn(id) { id >= 90_000 && id < 91_000 })
    |> list.sort(int.compare)
    == [
      90_001, 90_002, 90_003, 90_004, 90_005, 90_006, 90_007, 90_008, 90_009,
      90_010, 90_011, 90_012, 90_013, 90_014,
    ]
    as "the lists hold the twelve read rows, the row behind a target apply prerequisite (90013, held and applied by no go, `cast.condition_gate`) and the periodic heal (90014, a `TickingShieldHeal`); the Proc of kind 12 (`proc_read`) and the Proxy that names no spell are in no list"
  spell_tables.with_loaded(rows:, body: fn(tables) {
    let spell_groups = spell_plan.spell_groups(tables:)
    let effects =
      spell4_effects.all(tables)
      |> list.filter(fn(effect) { effect.id >= 90_000 && effect.id < 91_000 })
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
  })
}

fn first_of(effects effects: List(Spell4Effects), id id: Int) -> Spell4Effects {
  let assert Ok(found) = list.find(effects, fn(effect) { effect.id == id })
    as "the planted row is there"
  found
}

pub fn a_spend_all_spell_refuses_an_effect_tag_the_rule_does_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mind Burst's planted Spell4 32809 spends every point of slot 1 (innateCostEMMId0 4 on a
  // cost of type 6, `Spell4.32809`), and its damage effects 61993 and 61994 hold
  // emmComparison 2 and 1 (`spell_tables.rows_with_mind_burst_spend`).
  let rows =
    spell_tables.rows_with_mind_burst_spend(emm_id: 4, cost: #(6, 1), damage: [
      #(2, 0, 4),
      #(1, 0, 4),
    ])
  spell_tables.with_loaded(rows:, body: fn(tables) {
    let assert Ok(mind_burst) = spell4.get(tables:, id: Spell4Id(32_809))
      as "the planted Mind Burst"
    assert spell_plan.spends_all(tables:, row: mind_burst)
      as "innateCostEMMId0 4 on a slot cost is a spend of every point held"
    let effects =
      spell4_effects.all(tables)
      |> list.filter(fn(effect) {
        effect.spell_id == 32_809 && effect.effect_type == 8
      })
    let assert [refused, read] = effects
      as "the planted spell holds the two damage effects"
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
    assert result.is_error(spell_plan.build(tables:))
      as "the plan of the spell fails its load on the row"
  })
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
  assert spell_tables.derivation_result(rows:)
    |> result.is_error
    as "the plan's load fails on the row"
  assert spell_tables.planned_strike(rows:)
    == Error(spell_plan.NoRow(table: "Prerequisite", id: 99))
    as "Spell4Effects.prerequisiteIdCasterApply names a Prerequisite row the table lacks"
  spell_tables.with_loaded(rows:, body: fn(tables) {
    let effects =
      spell4_effects.all(tables)
      |> list.filter(fn(effect) { effect.id == 90_021 })
    assert effect_row.unread_by_type(tables:, effects:)
      == dict.from_list([#(17, 1)])
      as "the measure counts the row not read, without stopping"
  })
}
