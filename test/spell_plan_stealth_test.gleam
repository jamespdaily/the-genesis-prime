//// The Stealth and RemoveStealth effects of the plan and a spell's stealth change
//// (`genesis_prime/game/spell_plan` `StealthRow`, `RemoveStealthRow`, `StealthChange`).
//// Expected values come from these places:
//// - `Spell4Effects.effectType.83`: a Stealth row aimed at the caster (targetFlags 1)
////   holds the stealth until it is removed when flags have bit 2 and it has no durationTime;
////   dataBits02 0 means damage ends it and 1 means it does not. The Stalker's rows are
////   83834 in Spell4 38784 (flags 2, dataBits02 0, caster apply prerequisite 16152, phase
////   flags 1) and 95774 (flags 2, dataBits02 1, 16153), as `table_rows -- Spell4Effects
////   spellId=38784` prints them.
//// - `Spell4Effects.effectType.84`: a RemoveStealth row ends its target's stealth.
//// - `Spell4.spellCastStealthChange`: 1 on Impale 38779, 0 on its Proxies' children 39426
////   and 39427 and on 38783, 2 on 46073, 38784 and Impale's Fluff child 70775.
//// - `Spell4Conditions.conditionMask.16`: the client's stealth test in a caster or target
////   conditions row; the server does not check results 65 and 114, so a planned spell
////   that names such a row fails the load.
//// - The server's load rules (the plan's doc): a Stealth or RemoveStealth row aimed other
////   than at the caster alone, behind a target apply prerequisite, or (a Stealth row) with
////   a delayTime or durationTime, fails the load, and so does a stealth change or a
////   dataBits02 the plan has no case for.

import client_tables
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  type Spell as PlannedSpell, Always, BrokenByDamage, EndsStealth, GatedOnCaster,
  KeepsStealth, KeptOnDamage, RemoveStealthRow, StealthRow,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import owned_test
import planted_table.{type Cell, Integer}
import prerequisite_support
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`), carrying the planted rows of these tests.
const strike = 32_893

const strike_base = 19_102

/// The base of the Stalker's Stealth toggle, 46073, and Impale's.
const toggle_base = 30_075

const impale_base = 23_161

/// A row of effect type `type_` on Telekinetic Strike, aimed by `target_flags`, in every
/// phase, with these columns beside its id, spell and type.
fn effect_row(
  id id: Int,
  type_ type_: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(type_)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
    #("flags", Integer(2)),
  ]
  planted_table.row(
    spell4_effects.schema,
    list.append(
      list.filter(defaults, fn(default) {
        !list.any(columns, fn(given) { given.0 == default.0 })
      }),
      columns,
    ),
  )
}

fn with_row(row row: List(Cell)) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  spell_tables.Rows(
    ..rows,
    spell4_effects: spell_tables.sorted_by_id([row, ..rows.spell4_effects]),
  )
}

fn planned(
  rows rows: spell_tables.Rows,
) -> Result(PlannedSpell, spell_plan.PlanError) {
  spell_tables.with_loaded(rows:, body: fn(tables) {
    case spell_plan.build(tables:) {
      Ok(plans) -> {
        let assert Ok(spell) =
          spell_plan.in_plans(plans:, base: Spell4BaseId(strike_base))
          as "the plans hold Telekinetic Strike"
        Ok(spell)
      }
      Error(error) -> Error(error)
    }
  })
}

fn plan_error(rows rows: spell_tables.Rows) -> spell_plan.PlanError {
  let assert Error(error) = planned(rows:) as "the build fails"
  error
}

fn with_column(
  row row: List(Cell),
  name name: String,
  cell cell: Cell,
) -> List(Cell) {
  list.zip(spell4.schema.columns, row)
  |> list.map(fn(pair) {
    case pair.0.name == name {
      True -> cell
      False -> pair.1
    }
  })
}

/// The planted rows with Telekinetic Strike's Spell4 row changed in one column.
fn rows_with_strike(name name: String, cell cell: Cell) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  spell_tables.Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [Integer(32_893), ..] -> with_column(row:, name:, cell:)
        other -> other
      }
    }),
  )
}

fn plans_spell(base base: Int) -> PlannedSpell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.plans_with_stealth(),
      base: Spell4BaseId(base),
    )
    as "the planted plans hold the ability"
  spell
}

// ---- the rows of the plan ----

pub fn the_toggles_two_stealth_rows_and_its_spells_stealth_changes_are_read_as_the_rows_hold_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let toggle = plans_spell(base: toggle_base)
  assert toggle.stealth_change == KeepsStealth
    as "46073 holds spellCastStealthChange 2 (Spell4.spellCastStealthChange)"
  let assert [on, cancel] = list.map(toggle.proxies, fn(proxy) { proxy.spell })
  assert on.spell4_id.value == 38_784
  assert cancel.spell4_id.value == 38_783
  assert on.stealth_change == KeepsStealth
    as "38784 holds 2: the toggle's own spells do not end the stealth they make"
  assert cancel.stealth_change == EndsStealth
    as "38783 holds 0, and 0 ends stealth (Spell4.spellCastStealthChange.break)"
  assert on.stealth
    == [
      StealthRow(
        effect_id: Spell4EffectsId(83_834),
        phase_flags: 1,
        breaks: BrokenByDamage,
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        condition: GatedOnCaster(gates: [
          prerequisite_support.single(id: 16_152, condition: #(50, 2, 0, 59_389)),
        ]),
        tag: spend.EqualTo(value: 0),
      ),
      StealthRow(
        effect_id: Spell4EffectsId(95_774),
        phase_flags: 1,
        breaks: KeptOnDamage,
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        condition: GatedOnCaster(gates: [
          prerequisite_support.single(id: 16_153, condition: #(50, 1, 0, 59_389)),
        ]),
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "83834 breaks on damage (dataBits02 0) behind 16152 and 95774 is kept (dataBits02 1) behind 16153; both last until removed (flags 2, no durationTime)"
  assert on.remove_stealth == []
  assert cancel.stealth == []
  assert plans_spell(base: impale_base).stealth_change == EndsStealth
    as "Impale 38779 holds 1, and 1 ends stealth"
}

pub fn impales_tree_in_the_clients_tables_ends_stealth_in_all_but_its_fluff_child_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Impale 38779 holds 1, its Proxies' children 39426 and 39427 hold 0 and its Fluff
  // child 70775 holds 2 (`table_rows -- Spell4 38779 39426 39427 70775`).
  let assert Ok(impale) =
    spell_plan.in_plans(
      plans: spell_plan.plans(client_tables.shared()),
      base: Spell4BaseId(impale_base),
    )
    as "the client's plans hold Impale"
  let changes =
    list.map(spell_plan.tree(spell: impale, started: fn(_) { True }), fn(spell) {
      #(spell.spell4_id.value, spell.stealth_change)
    })
    |> list.unique
  assert list.sort(changes, fn(first, second) { int.compare(first.0, second.0) })
    == [
      #(38_779, EndsStealth),
      #(39_426, EndsStealth),
      #(39_427, EndsStealth),
      #(70_775, KeepsStealth),
    ]
    as "the tree of Impale: 1, 0, 0 and 2"
}

pub fn a_remove_stealth_row_aimed_at_the_caster_is_read_in_its_phases_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // A type 84 row of the client aimed at the caster (targetFlags 1): the planted row
  // has no prerequisite and every phase (Spell4Effects.effectType.84).
  let assert Ok(spell) =
    planned(
      rows: with_row(
        row: effect_row(id: 99_841, type_: 84, target_flags: 1, columns: []),
      ),
    )
  assert spell.remove_stealth
    == [
      RemoveStealthRow(
        effect_id: Spell4EffectsId(99_841),
        phase_flags: -1,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
}

// ---- what fails the load ----

pub fn a_stealth_row_with_a_duration_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // 683 ms is the shortest durationTime of the client's timed Stealth rows
  // (Spell4Effects.effectType.83): timed stealth is not built.
  assert plan_error(
      rows: with_row(
        row: effect_row(id: 99_831, type_: 83, target_flags: 1, columns: [
          #("durationTime", Integer(683)),
        ]),
      ),
    )
    == spell_plan.StealthTimedNotRead(spell4_id: strike, effect_id: 99_831)
}

pub fn a_stealth_row_aimed_at_the_area_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // targetFlags 4 is the area: the client's type 83 rows hold 1, 2 and 4.
  assert plan_error(
      rows: with_row(
        row: effect_row(id: 99_832, type_: 83, target_flags: 4, columns: []),
      ),
    )
    == spell_plan.StealthAimNotRead(
      spell4_id: strike,
      effect_id: 99_832,
      target_flags: 4,
    )
}

pub fn a_remove_stealth_row_aimed_at_the_primary_target_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // targetFlags 2 is the primary target: three of the client's type 84 rows hold it.
  assert plan_error(
      rows: with_row(
        row: effect_row(id: 99_842, type_: 84, target_flags: 2, columns: []),
      ),
    )
    == spell_plan.StealthAimNotRead(
      spell4_id: strike,
      effect_id: 99_842,
      target_flags: 2,
    )
}

pub fn a_stealth_row_behind_a_target_prerequisite_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // 33144 is a target apply prerequisite three of the client's type 83 rows hold.
  assert plan_error(
      rows: with_row(
        row: effect_row(id: 99_833, type_: 83, target_flags: 1, columns: [
          #("prerequisiteIdTargetApply", Integer(33_144)),
        ]),
      ),
    )
    == spell_plan.StealthTargetPrerequisiteNotRead(
      spell4_id: strike,
      effect_id: 99_833,
    )
}

pub fn a_stealth_row_with_a_databits02_that_is_not_0_or_1_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's type 83 rows hold 0 (47) and 1 (27): dataBits02 says whether damage
  // ends the stealth (Spell4Effects.effectType.83).
  assert plan_error(
      rows: with_row(
        row: effect_row(id: 99_834, type_: 83, target_flags: 1, columns: [
          #("dataBits02", Integer(2)),
        ]),
      ),
    )
    == spell_plan.StealthBreaksNotRead(
      spell4_id: strike,
      effect_id: 99_834,
      value: 2,
    )
}

pub fn a_stealth_change_of_3_fails_the_load_naming_the_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's column holds 0, 1 and 2 on every row (Spell4.spellCastStealthChange).
  assert plan_error(rows: rows_with_strike(
      name: "spellCastStealthChange",
      cell: Integer(3),
    ))
    == spell_plan.StealthChangeNotRead(spell4_id: strike, value: 3)
}

pub fn a_caster_conditions_row_with_the_stealth_bit_fails_the_load_naming_the_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // A planted Spell4Conditions row 12 of mask 16 (bit 4, 1 << 4: the stealth test,
  // Spell4Conditions.conditionMask.16), named by Telekinetic Strike's caster column.
  let rows =
    rows_with_strike(name: "spell4ConditionsIdCaster", cell: Integer(12))
  assert plan_error(
      rows: spell_tables.Rows(
        ..rows,
        spell4_conditions: spell_tables.sorted_by_id(list.append(
          rows.spell4_conditions,
          spell_tables.spell4_conditions_rows_of(masks: [#(12, 16)]),
        )),
      ),
    )
    == spell_plan.StealthConditionNotRead(
      spell4_id: strike,
      spell4_conditions_id: 12,
    )
}
