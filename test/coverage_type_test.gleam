//// The coverage measure's view of the spell effect and prerequisite types: which
//// types are handled (derived from the decode each rule's dispatch reads), which
//// are decoded and missing, and the starting abilities' column. Expected values
//// and their sources:
//// - The types the server reads: effect types 1 (VitalModifier), 8 (Damage) and
////   26 (Proxy), which `Spell4Effects.effectType.1`, `Spell.CodeEnumSpellEffectType.damage`
////   and `Spell4Effects.effectType.26` name, and prerequisite types 15, 28, 37, 71,
////   73 and 179 (`Prerequisite.prerequisiteTypeId.N`); a type the client's condition
////   check has no case for fails in the client and in the server (`0x1404a2100`).
//// - The starting abilities' counts are the issue's measured walk of 2026-11-05 over
////   SpellLevel (level 1, no prerequisite), Spell4, Spell4Effects, Spell4Thresholds
////   and Prerequisite: 18 abilities reach 65 spells, 120 effect rows and 26
////   prerequisites, with the counts by type written out below.
//// - The decoded and missing types, with each reason, are the fact file's records
////   (`Spell4Effects.effectType.N`, `Prerequisite.prerequisiteTypeId.N`).

import client_tables
import genesis_prime/coverage
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine.{
  type EngineDeclaration, EngineDeclaration, Listed, Missing,
}
import genesis_prime/coverage/measurement.{Handled, Measured}
import genesis_prime/coverage/starting_ability.{MissingRow}
import genesis_prime/game/spell_plan.{Spell}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import planted_table
import simplifile
import spell_tables
import unitest

fn engine_named(name: String) -> EngineDeclaration {
  let assert Ok(found) =
    list.find(engine.all(), fn(declaration) { declaration.name == name })
    as { "no engine is named " <> name }
  found
}

/// The numbers from `from` to `to`, both included.
fn numbers(from from: Int, to to: Int) -> List(Int) {
  int.range(from: to, to: from - 1, with: [], run: fn(found, number) {
    [number, ..found]
  })
}

/// The types of the engine the measure marks handled, over one row of each of
/// these types.
fn handled_over(
  engine engine: EngineDeclaration,
  types types: List(Int),
) -> List(Int) {
  let assert Measured(types: lines, ..) =
    measurement.from_values(engine:, values: types, starting: [])
    as "the engine's source is a table"
  list.filter(lines, fn(line) { line.status == Handled })
  |> list.map(fn(line) { line.type_number })
  |> list.sort(int.compare)
}

pub fn the_effect_types_the_measure_handles_are_1_8_and_26_test() -> Nil {
  use <- owned_test.run(10_000)
  assert handled_over(
      engine: engine_named("Spell effects"),
      types: numbers(from: 1, to: 200),
    )
    == [1, 8, 26]
    as "the server reads VitalModifier 1 (Spell4Effects.effectType.1), Damage 8 and Proxy 26 (Spell4Effects.effectType.26); every other type is unread"
}

pub fn the_prerequisite_types_the_measure_handles_are_the_six_read_and_those_with_no_case_test() -> Nil {
  use <- owned_test.run(10_000)
  assert handled_over(
      engine: engine_named("Prerequisites"),
      types: numbers(from: 1, to: 295),
    )
    == [
      15, 17, 21, 28, 32, 37, 45, 57, 58, 71, 72, 73, 75, 132, 144, 156, 157,
      158, 161, 165, 179, 181, 202, 247, 249, 257, 258, 274, 282, 284,
    ]
    as "the server reads 15, 28, 37, 71, 73 and 179 (the unit's difficulty, 0x14049eeb0, which the creature attack's load reads), and fails the 24 types the client's check has no case for as the client does (0x1404a2100: 17, 21, 32, 45, 57, 58, 72, 75, 132, 144, 156, 157, 158, 161, 165, 181, 202, 247, 249, 257, 258, 274, 282, 284)"
}

// ---- the starting abilities' column ----

/// The rows of each type among the starting abilities, as the measure gives them,
/// by type number.
fn starting_counts(engine engine: EngineDeclaration) -> List(#(Int, Int)) {
  let tables = client_tables.every_table()
  let assert Measured(types:, ..) = measurement.measure(engine, tables)
    as "the engine's source is a table"
  list.filter_map(types, fn(line) {
    case line.starting_abilities {
      0 -> Error(Nil)
      rows -> Ok(#(line.type_number, rows))
    }
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

pub fn the_starting_abilities_column_holds_the_issues_effect_counts_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  assert starting_counts(engine: engine_named("Spell effects"))
    == [
      #(1, 4),
      #(3, 1),
      #(4, 6),
      #(8, 36),
      #(11, 2),
      #(14, 1),
      #(17, 11),
      #(26, 50),
      #(73, 5),
      #(80, 3),
      #(90, 1),
    ]
    as "the issue's walk: 26 Proxy 50, 8 damage 36, 17 11, 4 6, 73 5, 1 VitalModifier 4, 80 3, 11 2, 3 1, 14 1, 90 1: 120 effect rows"
}

pub fn the_starting_abilities_column_holds_the_issues_prerequisite_counts_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  assert starting_counts(engine: engine_named("Prerequisites"))
    == [
      #(15, 17),
      #(28, 2),
      #(37, 1),
      #(43, 2),
      #(50, 3),
      #(59, 4),
      #(71, 1),
      #(73, 4),
      #(108, 2),
      #(116, 3),
    ]
    as "the issue's walk: 15 17, 59 4, 73 4, 50 3, 116 3, 28 2, 108 2, 43 2, 71 1, 37 1: 39 conditions of 26 prerequisites"
}

pub fn the_starting_abilities_reach_65_spells_gated_children_included_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  assert list.length(
      starting_ability.spells(tables: client_tables.every_table()),
    )
    == 65
    as "the issue's walk: the 18 level-1 abilities reach 65 spells, a Proxy's child behind a gate among them"
}

// ---- the decoded and missing types ----

/// The key of a record in the fact file, as it opens the record's table.
fn has_record(facts facts: String, key key: String) -> Bool {
  string.contains(facts, "[\"" <> key <> "\"]")
}

pub fn each_decoded_type_not_handled_is_listed_with_its_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let missing_of = fn(name) {
    let declared = engine_named(name)
    list.each(declared.missing, fn(missing) {
      assert missing.reason != ""
        as {
          name <> " type " <> int.to_string(missing.type_number) <> ": a reason"
        }
      assert has_record(facts:, key: missing.fact_key)
        as {
          name
          <> " type "
          <> int.to_string(missing.type_number)
          <> ": the fact file holds no record "
          <> missing.fact_key
        }
      assert !engine.handles(engine: declared, type_number: missing.type_number)
        as {
          name
          <> " type "
          <> int.to_string(missing.type_number)
          <> " is listed missing and handled"
        }
    })
    list.map(declared.missing, fn(missing) { missing.type_number })
    |> list.sort(int.compare)
  }
  assert missing_of("Spell effects") == [3, 4, 11, 14, 17, 73, 80, 90]
    as "the trace's effect types of the starting abilities that no rule reads: forced move 3, crowd control 4, property modifier 11, proc 14, lasting effect 17, cooldown change 73, forced removal 80 and charges 90"
  assert missing_of("Prerequisites") == [43, 50, 59, 108, 116]
    as "the trace's prerequisite types the server cannot decide yet: quest log 43, spell by caster 50, stack count 59, facing 108 and stealth 116"
}

pub fn a_type_both_handled_and_listed_missing_is_a_conflict_and_an_unused_missing_type_a_breach_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(
      ..engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      missing: [
        Missing(type_number: 7, reason: "a reason", fact_key: "a.key"),
        Missing(type_number: 99, reason: "a reason", fact_key: "a.key"),
      ],
    )
  let assert Measured(conflicts:, breaches:, ..) =
    measurement.from_values(engine: declared, values: [7, 2, 7], starting: [])
    as "the engine's source is a table"
  assert conflicts == [7]
    as "7 is handled and also listed as missing: the measure fails"
  assert breaches == [99]
    as "no row uses 99, so listing it as missing is a declaration no data supports"
}

pub fn the_checklist_marks_handled_missing_and_undecoded_types_with_the_starting_abilities_rows_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(
      ..engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      missing: [
        Missing(type_number: 2, reason: "needs a thing", fact_key: "Some.key"),
      ],
      starting_abilities: None,
    )
  let measured =
    measurement.from_values(
      engine: declared,
      values: [7, 0, 2, 7, 5, 7, 0, 9, 2, 7, 0],
      starting: [7, 7, 2, 5],
    )
  let text = checklist.render([measured])
  assert string.contains(
    text,
    string.join(
      [
        "- [x] type 7: 4 rows (50.0%), 2 rows in the starting abilities",
        "- [~] type 2: 2 rows (25.0%), 1 row in the starting abilities; decoded, not handled: needs a thing (Some.key)",
        "- [ ] type 5: 1 row (12.5%), 1 row in the starting abilities",
        "- [ ] type 9: 1 row (12.5%)",
      ],
      "\n",
    ),
  )
    as "[x] handled, [~] decoded and not handled with its reason and fact key, [ ] not decoded; the starting abilities' rows when there are any"
  assert string.contains(
    text,
    "8 rows over 4 types; 3 zero values left out; 1 of 4 types handled (50.0% of rows); 1 decoded and missing; starting abilities: 2 of 4 rows handled",
  )
    as "type 7 is handled with 4 of the 8 rows, 1 type is decoded and missing, and the starting abilities hold 4 rows of which type 7's 2 are handled"
  assert string.contains(
    checklist.totals([measured]),
    "| Quest objectives (#48) | 4 | 8 | 3 | 1 | 2 of 4 |",
  )
    as "the totals row carries the starting abilities' rows handled"
}

// ---- rows a starting ability's tree names that the tables lack ----

/// The planted rows with Energize's Spell4 row (69450, a level-1 ability of the
/// Medic) naming this Prerequisite id in its runner column, which the plan's load
/// does not read.
fn rows_naming(prerequisite_id prerequisite_id: Int) -> spell_tables.Rows {
  let rows = spell_tables.rows_with_energize()
  spell_tables.Rows(
    ..rows,
    spell4: spell_tables.sorted_by_id([
      spell_tables.method_spell_row(
        id: 69_450,
        base: 46_615,
        cast_time: 0,
        cooldown: 30_000,
        kind: 3,
        global: 0,
        cost: #(0, 0),
        more: [#("prerequisiteIdRunner00", prerequisite_id)],
      ),
      ..planted_table.without(rows.spell4, ids: [69_450])
    ]),
  )
}

fn with_trees_loaded(
  rows rows: spell_tables.Rows,
  body body: fn(store.Tables) -> a,
) -> a {
  spell_tables.with_loaded_deriving(
    rows:,
    derivations: [spell_plan.derivation()],
    body:,
  )
}

pub fn a_prerequisite_a_spell_column_names_that_the_table_lacks_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let lacking =
    MissingRow(
      table: "Prerequisite",
      id: 77_777,
      named_by: "Spell4 69450 column prerequisiteIdRunner00",
    )
  assert with_trees_loaded(
      rows: rows_naming(prerequisite_id: 77_777),
      body: fn(tables) { starting_ability.prerequisite_types(tables) },
    )
    == Error([lacking])
    as "Spell4 69450 names Prerequisite 77777 in prerequisiteIdRunner00 and the table has no such row: it is reported with the row and the column, not left out of the starting abilities' types"
  assert with_trees_loaded(
      rows: rows_naming(prerequisite_id: 43_811),
      body: starting_ability.prerequisite_types,
    )
    == with_trees_loaded(
      rows: spell_tables.rows_with_energize(),
      body: starting_ability.prerequisite_types,
    )
    as "a row the table holds, 43811, which Energize's effect 228910 already names, counts once however many columns name it"
}

pub fn a_spell_of_the_tree_the_spell4_table_lacks_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  assert with_trees_loaded(rows: spell_tables.rows(), body: fn(tables) {
      let assert [spell, ..] = starting_ability.spells(tables:)
        as "the planted abilities hold spells"
      starting_ability.prerequisite_types_of(tables:, spells: [
        Spell(..spell, spell4_id: Spell4Id(123_456)),
      ])
    })
    == Error([
      MissingRow(
        table: "Spell4",
        id: 123_456,
        named_by: "a spell of a starting ability's tree",
      ),
    ])
    as "a spell of a tree with no Spell4 row is reported, not skipped"
}

pub fn a_missing_row_fails_the_measure_with_the_row_named_test() -> Nil {
  use <- owned_test.run(10_000)
  let measured =
    with_trees_loaded(
      rows: rows_naming(prerequisite_id: 77_777),
      body: fn(tables) {
        measurement.measure(engine_named("Prerequisites"), tables)
      },
    )
  let assert Measured(missing_rows:, ..) = measured
    as "the Prerequisite table is a source"
  assert missing_rows
    == [
      MissingRow(
        table: "Prerequisite",
        id: 77_777,
        named_by: "Spell4 69450 column prerequisiteIdRunner00",
      ),
    ]
    as "the measure keeps the missing row"
  assert list.any(coverage.breaches([measured]), fn(line) {
    string.contains(
      line,
      "Prerequisites reaches rows the client's tables lack: Prerequisite 77777, named by Spell4 69450 column prerequisiteIdRunner00, is not in the client's tables",
    )
  })
    as "the tool's breaches, which end it with exit 1, name the row"
}
