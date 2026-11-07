//// The effect measure counts an effect row as read exactly when the plan loads it, on the
//// client's tables. Each expected count is a scratch count: a Python count of the rows
//// printed by `gleam run -m genesis_prime/table_rows -- Spell4Effects effectType=N`, written
//// apart from the plan's code from the rules each row is held to (the plan's doc comments
//// and `genesis_prime/game/cast`'s gates), and the same rows for the starting abilities'
//// column, whose 196 rows are the ids the coverage walk reaches
//// (`genesis_prime/coverage/starting_ability`).

import client_tables
import coverage_support
import database_support
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, HandledWithGap, Measured,
}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

fn spell_effects() -> EngineDeclaration {
  let assert Ok(found) =
    list.find(engine.all(), fn(declaration) {
      declaration.name == "Spell effects"
    })
    as "the effect engine is declared"
  found
}

/// The measure of the effect types over the client's tables, taken once per run.
fn measured() -> Measurement {
  database_support.once("coverage_plan_effects", fn() {
    measurement.measure(spell_effects(), client_tables.every_table())
  })
}

fn line_of(type_number type_number: Int) -> TypeLine {
  let assert Measured(types:, ..) = measured()
    as "the engine's source is a table"
  let assert Ok(line) =
    list.find(types, fn(line) { line.type_number == type_number })
    as "the type is in use"
  line
}

/// The rows of a type, the rows of it that are not read, and the same for the starting
/// abilities, with the gap the line states.
fn counted(type_number type_number: Int) -> #(Int, Int, Int, Int) {
  let line = line_of(type_number:)
  let assert HandledWithGap(unread_rows:, ..) = line.status
    as {
      "type " <> int.to_string(type_number) <> " is handled with a stated gap"
    }
  #(line.rows, unread_rows, line.starting_abilities, line.starting_unread)
}

// ---- the counts on the client's tables ----

pub fn the_measure_counts_the_crowd_control_rows_the_plan_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, _) = counted(type_number: 4)
  assert rows == 7185 as "scratch count: effectType=4 holds 7,185 rows"
  assert unread == 3872
    as "scratch count: 3,412 rows hold a dataBits00 other than 0 or 8 (Spell4Effects 609 holds 1), the aim is other than 2, 4 or 6 in 141 more and 319 more hold an apply prerequisite (`read_row`): 3,872 of 7,185"
}

pub fn the_measure_counts_the_gains_the_plan_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 1)
  assert rows == 2049 as "scratch count: effectType=1 holds 2,049 rows"
  assert unread == 1368
    as "scratch count: 1,327 rows hold a targetFlags other than 1, a dataBits00 other than 6 or 8 or a target apply prerequisite (`read_row`), and 41 more hold a tickTime, which the plan keeps as a `TickingGain` and the cast rule does not apply (190 rows tick, 303 tick or aim at another unit): 1,368 of 2,049"
  assert #(starting, starting_unread) == #(11, 1)
    as "scratch count over the 196 starting rows: 11 hold type 1 and 228918, the Medic's, ticks every 2000 ms"
}

pub fn the_measure_counts_the_damage_rows_the_area_load_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, starting_unread) = counted(type_number: 8)
  assert rows == 29_445 as "scratch count: effectType=8 holds 29,445 rows"
  assert unread == 10_136
    as "scratch count: 9,995 rows hold a formula parameter whose value is not 0 and whose type is not 0, 10, 12 or 13 (`damage.unread`) and 136 more aim other than 1, 2, 4 or 6; no multiplier is infinite or not a number; and 5 more, otherwise read, hold a phaseFlags of 0, which no phase selects (`in_phase`): 10,136 of 29,445"
  assert starting_unread == 0
    as "the area load builds every damage row of the starting abilities' spells"
}

pub fn the_measure_counts_a_proxy_that_names_no_spell_or_aims_elsewhere_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 26)
  assert rows == 16_929 as "scratch count: effectType=26 holds 16,929 rows"
  assert unread == 1986
    as "scratch count: 1,808 rows hold a dataBits00 of 0, which names no spell (`Spell4Effects.effectType.26` counts the same 1,808), 170 more aim by a flag other than 1, 2, 4 and 6 and 8 more, otherwise read, hold a phaseFlags of 0, which no phase selects: 1,986 of 16,929"
  assert #(starting, starting_unread) == #(72, 2)
    as "scratch count over the starting rows: 72 of type 26, and 121345 and 178429 hold a dataBits00 of 0"
}

pub fn the_measure_counts_rows_behind_a_target_prerequisite_as_not_read_for_every_kind_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert counted(type_number: 3).1 == 2562
    as "scratch count: 2,543 rows aim only at other units, 14 more, the first 48817, aim at the caster behind a target apply prerequisite (the cast applies no `GatedOnTarget` row, `cast.condition_gate`) and 5 more hold a phaseFlags of 0, which no phase selects (`in_phase`): 2,562 of 4,645"
  assert counted(type_number: 11).1 == 7638
    as "scratch count: 7,502 aimed at other units and 136 more behind a target apply prerequisite, the first 42729: 7,638 of 20,105"
  assert counted(type_number: 73).1 == 35
    as "scratch count: 34 aimed at other units and 1 more, 73611, behind a target apply prerequisite: 35 of 522"
  assert counted(type_number: 118).1 == 110
    as "scratch count: 106 that aim at the area, tick, hold a formula parameter the caster's value does not read or aim at the primary target of a struck child, and 4 more behind a target apply prerequisite (179980, 179981, 179986 and 179987): 110 of 262"
}

pub fn the_measure_counts_a_force_remove_whose_selector_names_no_row_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert counted(type_number: 80).1 == 535
    as "scratch count: 503 rows aimed by refused flags, behind a target apply prerequisite or with dataBits03 and dataBits04 differing, and 32 more whose dataBits01 names no spell group (686 of the Spell4GroupList rows' ids), Spell4 or Spell4Base, the first 59302: 535 of 2,294"
}

pub fn the_measure_totals_match_the_plan_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let text = checklist.render([measured()])
  assert string.contains(text, "33396 rows of the handled types not read")
    as "the sum of the types' scratch counts: 1 1,368, 3 2,562, 4 3,872, 8 10,136, 11 7,638, 26 1,986, 73 35, 80 535 and 118 110 (the tests above), 17 455 and 81 658 (the 375 and 634 of before and 80 and 24 rows, otherwise read, with phaseFlags 0), and the counts this step leaves as they were: 14 3,455, 18 14, 29 281, 52 2, 64 35, 83 51, 84 4, 112 199 and 145 0 (the existing `coverage_type_test` values, which the step does not move)"
  assert string.contains(text, "starting abilities: 184 of 196 rows handled")
    as "scratch count over the 196 starting rows: 9 were not read before (the two Proc rows the plan skips, 90 four times, 24, the Warrior's 210834 and 91018) and 3 are not read now: Proxies 121345 and 178429 (dataBits00 0) and the Medic's ticking gain 228918"
}

// ---- the gaps the engine states ----

pub fn types_1_4_8_and_26_state_their_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let declared = spell_effects()
  let fact_keys = [
    #(1, "Spell4Effects.effectType.1"),
    #(4, "Spell4Effects.effectType.4"),
    #(8, "0x140566ad0"),
    #(26, "Spell4Effects.effectType.26"),
  ]
  list.each(fact_keys, fn(expected) {
    let #(type_number, fact_key) = expected
    let assert Ok(gap) =
      list.find(declared.partial, fn(gap) { gap.type_number == type_number })
      as {
        "type " <> int.to_string(type_number) <> " is handled with a stated gap"
      }
    assert gap.fact_key == fact_key
      as "the gap cites the client's reading: the type's own record, and for the damage rows the formula's parameters (0x140566ad0)"
    assert coverage_support.has_record(facts:, key: fact_key)
      as { "the fact file holds " <> fact_key }
    assert engine.handles(engine: declared, type_number:)
  })
  let assert Ok(remove) =
    list.find(declared.partial, fn(gap) { gap.type_number == 80 })
    as "type 80 is partial"
  assert !string.contains(remove.reason, "is not counted")
    as "a selector that names no row is counted not read, since the measure holds the tables"
}
