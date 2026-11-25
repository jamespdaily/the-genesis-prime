//// What the plan makes of one effect row (`genesis_prime/game/spell_plan` `read_row`), the
//// decision its lists and the coverage measure are both made from. Expected values come
//// from these places.
//// - `cast.condition_gate` (`genesis_prime/game/cast`): a row behind a target apply
////   prerequisite is applied by no go.
//// - `genesis_prime/game/ticking`: a `TickingHeal` with a tickTime and a life of at least
////   one tick is applied, each tick its own 0x7f8 (`Spell4Effects.effectType.118`).
//// - `proc_read`: a Proc of a kind other than 217, 218, 44 and 0 is in no list and the load
////   goes on (`Spell4Effects.effectType.14`).
//// - The plan's Proxy rule: a Proxy whose dataBits00 names no spell makes no child, so the
////   plan holds none (`Spell4Effects.effectType.26`).
//// - `Spell4.innateCostEMMId0`: a cost with an EMM id of 4 or 7 on a slot cost spends every
////   point held, which gives each effect of the spell a tag the rule must read (0 or 1).
//// The rows are planted on Telekinetic Strike's spell (`spell_tables`).

import client_tables
import fixture_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/spell_plan.{
  Applied, Held, LeftOut, ProcOfAnotherKind, ProxyNamesNoSpell, ReadByActivation,
  ReadByArea, ReadProc, ReadProxy,
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
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// A planted row of Telekinetic Strike's spell.
fn row(
  id id: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  spell_tables.effect_row_with(id:, effect_type:, target_flags:, columns:)
}

/// Whether this id lies between these two and is not an id of a client row.
fn planted_between(id id: Int, low low: Int, high high: Int) -> Bool {
  id >= low && id < high && !spell_tables.client_row(id:)
}

pub fn a_planted_spell_lists_the_applied_and_held_rows_and_the_measure_counts_only_the_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows =
    spell_tables.rows_with_effects(effects: spell_tables.planted_effects())
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
    as "the planted spell loads: every row of it is read or left out"
  assert spell_tables.listed_effect_ids(spell:)
    |> list.filter(planted_between(id: _, low: 90_000, high: 91_000))
    |> list.sort(int.compare)
    == [
      90_001, 90_002, 90_003, 90_004, 90_005, 90_006, 90_007, 90_009, 90_010,
      90_011, 90_012, 90_013, 90_014, 90_018, 90_019,
    ]
    as "the lists hold the twelve read rows, the row behind a target apply prerequisite (90013, which a go applies to the units that pass it), the periodic heal (90014, a `TickingHeal` that ticks every 1000 ms for 8000 ms) and the Proxy that names its spell in dataBits01 (90019, `proxy_named`); the Proc of kind 27 (`proc_read`, a kind not read) and the Proxy that names no spell, in dataBits00 or dataBits01, are in no list"
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let sources = spell_plan.sources_of(tables:)
      let effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) {
          planted_between(id: effect.id, low: 90_000, high: 91_000)
        })
      let read = fn(effect: Spell4Effects) {
        spell_plan.read_row(
          tables:,
          sources:,
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
            Ok(ReadByActivation) -> "activation"
            Error(error) -> "refused: " <> spell_plan.describe(error:)
          }
          #(effect.id, kind)
        })
      assert verdicts
        == list.append(
          list.map(
            [
              90_001, 90_002, 90_003, 90_004, 90_005, 90_006, 90_007, 90_009,
              90_010, 90_011, 90_012, 90_013,
            ],
            fn(id) { #(id, "applied") },
          ),
          [
            #(90_014, "applied"),
            #(90_015, "left out"),
            #(90_016, "left out"),
            #(90_018, "applied"),
            #(90_019, "applied"),
          ],
        )
        as "the rule each row checks: a row behind a target apply prerequisite is applied, a periodic heal with a tickTime is applied, a Proc of a kind not read and a Proxy that names no spell are left out, and a Proxy that names its spell in dataBits01 is applied"
      let assert Ok(Applied(ReadProc(..))) =
        read(first_of(effects:, id: 90_011))
        as "the Proc of kind 217 is read and its spell is planned from the reading"
      assert read(first_of(effects:, id: 90_015))
        == Ok(LeftOut(why: ProcOfAnotherKind(kind: 3)))
      assert read(first_of(effects:, id: 90_016))
        == Ok(LeftOut(why: ProxyNamesNoSpell))
      let assert Ok(Applied(ReadProxy(..))) =
        read(first_of(effects:, id: 90_012))
        as "the Proxy that names a spell is read"
      let assert Ok(Applied(ReadProxy(..))) =
        read(first_of(effects:, id: 90_019))
        as "the Proxy that names its spell in dataBits01 is read"
      assert effect_row.unread_by_type(tables:, effects:)
        == dict.from_list([#(14, 1), #(26, 1)])
        as "the measure counts only the rows a go applies as read: the Proc of kind 27 and the Proxy that names no spell are not, and the Fluff behind a target prerequisite, the periodic heal and the Proxy that names its spell in dataBits01 are read"
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
  assert spell_plan.spends_all(row: mind_burst)
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
  let spends =
    spell_plan.RowPlace(
      struck_by: None,
      spends_all: True,
      hits_foes: False,
      throws_target: False,
      finds_allies: False,
      ends_as_aura: False,
    )
  assert spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
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
      sources: spell_plan.sources_of(tables:),
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
  let rows = spell_tables.rows_with_effects(effects: [planted_row])
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
      ..spell_tables.rows_with_effects(effects: [planted_row]),
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
  // neither (`lasting.has_life`). Planted: a type 11, 145 and 52 row each with and
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
    rows: spell_tables.rows_with_effects(effects:),
    body: fn(tables) {
      let planted_effects =
        spell4_effects.all(tables)
        |> list.filter(fn(effect) {
          planted_between(id: effect.id, low: 90_100, high: 92_000)
        })
      let sources = spell_plan.sources_of(tables:)
      let verdicts =
        list.map(planted_effects, fn(effect) {
          let reading =
            spell_plan.read_row(
              tables:,
              sources:,
              place: spell_tables.pressed,
              effect:,
            )
          #(effect.id, case reading {
            Ok(Applied(..)) -> "applied"
            Ok(Held(..)) -> "held"
            Ok(LeftOut(..))
            | Ok(ReadByArea)
            | Ok(ReadByActivation)
            | Error(..) -> "other"
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
  let rows = spell_tables.rows_with_effects(effects:)
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
      let sources = spell_plan.sources_of(tables:)
      let read = fn(id) {
        spell_plan.read_row(
          tables:,
          sources:,
          place: spell_tables.pressed,
          effect: first_of(effects: planted_effects, id:),
        )
      }
      let assert Ok(Held(..)) = read(92_001)
        as "a lasting row no phase selects is held"
      let assert Ok(Held(ReadProxy(..))) = read(92_002)
        as "so is a Proxy, and its child is still planned"
      assert read(92_003) == Ok(LeftOut(why: spell_plan.InNoPhase))
      let assert Ok(Applied(..)) = read(92_004)
      assert effect_row.unread_by_type(tables:, effects: planted_effects)
        == dict.from_list([#(17, 1), #(26, 1), #(8, 1)])
        as "the measure counts the three rows no phase selects not read, and the Fluff of -1 read"
    },
  )
}

/// The spell of a level-20 class ability that holds row 86849, a type 11 BaseHealth row
/// with the parameters 12 (0.19), 13 (0.19) and 10 (16.59)
/// (`table_rows -- Spell4Effects 86849`).
const spell_with_parameters = 39_566

pub fn a_modifier_row_whose_parameters_have_factors_is_not_read_on_the_clients_spell_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: spell_with_parameters,
      chain: [],
    )
    == Error(spell_plan.ParameterNotRead(
      spell4_id: spell_with_parameters,
      effect_id: 86_849,
      row: spell_plan.ModifierRow,
      parameter_kind: 12,
    ))
    as "row 86849's parameter 12 has the factor 0.19, and the plan does not read a stat modifier's parameter factors"
}

pub fn no_level_one_or_innate_ability_holds_a_modifier_row_with_a_parameter_factor_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let held =
    dict.values(spell_plan.plans(tables))
    |> list.flat_map(fn(spell) {
      spell_plan.tree(spell:, started: fn(_) { True })
    })
    |> list.map(fn(member) { member.spell4_id.value })
    |> list.unique
    |> list.flat_map(fn(spell4_id) {
      spell_plan.effects_of(sources:, spell4_id:)
    })
    |> list.filter(fn(effect) {
      effect.effect_type == 11
      && list.any(
        [
          effect.parameter_value00,
          effect.parameter_value01,
          effect.parameter_value02,
          effect.parameter_value03,
        ],
        fn(value) { value != 0.0 },
      )
    })
    |> list.map(fn(effect) { effect.id })
  assert held == []
    as "the trees of the level-1 abilities and the innates hold no type 11 row with a parameter factor, so refusing one fails no load"
}
