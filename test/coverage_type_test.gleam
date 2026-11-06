//// The coverage measure's view of the spell effect and prerequisite types: which
//// types are handled (derived from the decode each rule's dispatch reads), which
//// are decoded and missing, and the starting abilities' column. Expected values
//// and their sources:
//// - The types the server reads: effect types 1 (VitalModifier), 8 (Damage), 17
////   (Fluff), 26 (Proxy) and 80 (SpellForceRemove), which `Spell4Effects.effectType.N`
////   and `Spell.CodeEnumSpellEffectType.damage` name, and prerequisite types 15, 28,
////   37, 50, 59, 71, 73 and 179 (`Prerequisite.prerequisiteTypeId.N`); a type the
////   client's condition check has no case for fails in the client and in the server
////   (`0x1404a2100`).
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
import genesis_prime/coverage/measurement.{HandledWithGap, Measured}
import genesis_prime/coverage/starting_ability.{MissingRow}
import genesis_prime/game/spell_plan.{Spell}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_key
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
  list.filter(lines, fn(line) { measurement.is_handled(line.status) })
  |> list.map(fn(line) { line.type_number })
  |> list.sort(int.compare)
}

pub fn the_effect_types_the_measure_handles_are_1_3_4_8_11_17_26_73_80_83_and_84_test() -> Nil {
  use <- owned_test.run(10_000)
  assert handled_over(
      engine: engine_named("Spell effects"),
      types: numbers(from: 1, to: 200),
    )
    == [1, 3, 4, 8, 11, 17, 26, 73, 80, 83, 84]
    as "the server reads VitalModifier 1 (Spell4Effects.effectType.1), ForcedMove 3 for the rows aimed at the caster (Spell4Effects.effectType.3.player), CCStateSet 4 (Spell4Effects.effectType.4), Damage 8, UnitPropertyModifier 11 for the rows aimed at the caster (Spell4Effects.effectType.11.change), Fluff 17 (Spell4Effects.effectType.17), Proxy 26 (Spell4Effects.effectType.26), ModifySpellCooldown 73 for the rows aimed at the caster (Spell4Effects.effectType.73) SpellForceRemove 80 (Spell4Effects.effectType.80), Stealth 83 (Spell4Effects.effectType.83) and RemoveStealth 84 (Spell4Effects.effectType.84) for the rows aimed at the caster; every other type is unread"
}

pub fn the_prerequisite_types_the_measure_handles_are_the_nine_read_and_those_with_no_case_test() -> Nil {
  use <- owned_test.run(10_000)
  assert handled_over(
      engine: engine_named("Prerequisites"),
      types: numbers(from: 1, to: 295),
    )
    == [
      15, 17, 21, 28, 32, 37, 45, 50, 57, 58, 59, 71, 72, 73, 75, 116, 132, 144,
      156, 157, 158, 161, 165, 179, 181, 202, 247, 249, 257, 258, 274, 282, 284,
    ]
    as "the server reads 15, 28, 37, 50, 59 (Prerequisite.prerequisiteTypeId.50 and .59), 71, 73, 116 (the unit's stealth, Prerequisite.prerequisiteTypeId.116) and 179 (the unit's difficulty, 0x14049eeb0, which the creature attack's load reads), and fails the 24 types the client's check has no case for as the client does (0x1404a2100: 17, 21, 32, 45, 57, 58, 72, 75, 132, 144, 156, 157, 158, 161, 165, 181, 202, 247, 249, 257, 258, 274, 282, 284)"
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
  assert missing_of("Spell effects") == [14, 90]
    as "the trace's effect types of the starting abilities that no rule reads: proc 14 and charges 90; forced move 3, property modifier 11 and cooldown change 73 are read for the rows aimed at the caster and listed as partial"
  assert missing_of("Spend-scaled costs") == [2, 5, 9, 10, 11]
    as "the innate cost EMM ids besides 4 and 7 that the rows hold"
  assert missing_of("Prerequisites") == [43, 108]
    as "the trace's prerequisite types the server cannot decide: quest log 43 and facing 108; stealth 116 is read"
}

pub fn a_partial_type_is_handled_and_carries_the_gap_it_states_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(
      ..engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      partial: [
        Missing(type_number: 7, reason: "a gap", fact_key: "a.key"),
      ],
      missing: [],
    )
  let measured =
    measurement.from_values(engine: declared, values: [7, 2, 7], starting: [])
  let assert Measured(types:, conflicts:, breaches:, ..) = measured
    as "the engine's source is a table"
  let assert Ok(seven) = list.find(types, fn(line) { line.type_number == 7 })
  assert seven.status
    == HandledWithGap(reason: "a gap", fact_key: "a.key", unread_rows: 0)
    as "a partial type is handled, and its line holds the gap's reason and key"
  assert measurement.is_handled(status: seven.status)
  assert conflicts == [] && breaches == []
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 7: 2 rows (66.67%); handled with a gap, 0 of its 2 rows not read: a gap (a.key)",
  )
    as "the checklist marks it [x] and lists its reason"
  assert string.contains(text, "1 of 2 types handled (66.67% of rows)")
    as "a partial type counts among the types handled"
}

pub fn a_partial_type_no_rule_reads_is_a_conflict_and_an_unused_one_a_breach_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(
      ..engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      partial: [
        Missing(type_number: 2, reason: "a gap", fact_key: "a.key"),
        Missing(type_number: 99, reason: "a gap", fact_key: "a.key"),
      ],
      missing: [],
    )
  let assert Measured(conflicts:, breaches:, ..) =
    measurement.from_values(engine: declared, values: [7, 2, 7], starting: [])
    as "the engine's source is a table"
  assert list.contains(conflicts, 2)
    as "2 is listed partial and no rule reads it: the measure fails"
  assert breaches == [99]
    as "no row uses 99, so listing it as partial is a declaration no data supports"
}

pub fn the_effect_types_3_11_73_83_and_84_are_partial_with_a_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let declared = engine_named("Spell effects")
  assert declared.partial
    == [
      Missing(
        type_number: 3,
        reason: "rows, or parts of rows, aimed at another unit: the next step",
        fact_key: "Spell4Effects.effectType.3",
      ),
      Missing(
        type_number: 11,
        reason: "rows, or parts of rows, aimed at another unit: the next step",
        fact_key: "Spell4Effects.effectType.11",
      ),
      Missing(
        type_number: 73,
        reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps",
        fact_key: "Spell4Effects.effectType.73",
      ),
      Missing(
        type_number: 83,
        reason: "rows aimed at another unit, which hold no stealth the server keeps",
        fact_key: "Spell4Effects.effectType.83",
      ),
      Missing(
        type_number: 84,
        reason: "rows aimed at another unit, whose stealth the server does not hold",
        fact_key: "Spell4Effects.effectType.84",
      ),
    ]
  assert has_record(facts:, key: "Spell4Effects.effectType.3")
  assert has_record(facts:, key: "Spell4Effects.effectType.11")
  assert has_record(facts:, key: "Spell4Effects.effectType.73")
  assert has_record(facts:, key: "Spell4Effects.effectType.83")
  assert has_record(facts:, key: "Spell4Effects.effectType.84")
  assert engine.handles(engine: declared, type_number: 3)
    && engine.handles(engine: declared, type_number: 11)
    && engine.handles(engine: declared, type_number: 73)
    && engine.handles(engine: declared, type_number: 83)
    && engine.handles(engine: declared, type_number: 84)
    as "types 3, 11, 73, 83 and 84 are handled, with the gap"
}

pub fn the_type_3_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects.targetFlags: bit 1 is the caster; the plan reads a type 3 row that
  // includes it (flags 1, 3, 5 and 7) and leaves out one aimed only at others (2, 4 and
  // 6), which the server's 0x638 would move (Spell4Effects.effectType.3.other_unit).
  // Planted: five type 3 rows, flags 1, 5, 2, 4 and 6, and one type 8 row.
  let row = fn(id, type_, flags) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
    ])
  }
  use folder <- planted_table.in_folder([
    planted_table.file(spell4_effects.schema, [
      row(1, 3, 1),
      row(2, 3, 5),
      row(3, 3, 2),
      row(4, 3, 4),
      row(5, 3, 6),
      row(6, 8, 4),
    ]),
  ])
  let assert Ok(tables) =
    store.load(
      under: owned_key.new(),
      from: folder,
      entries: [spell4_effects.entry()],
      requirements: [],
      derivations: [],
    )
    as "a planted Spell4Effects table loads"
  let measured =
    measurement.measure(
      EngineDeclaration(
        ..engine_named("Spell effects"),
        starting_abilities: None,
      ),
      tables,
    )
  store.unload(tables)
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(three) = list.find(types, fn(line) { line.type_number == 3 })
  assert three.rows == 5
  assert three.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit: the next step",
      fact_key: "Spell4Effects.effectType.3",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read: only the caster rows count as handled"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 3: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit: the next step (Spell4Effects.effectType.3)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (50.0% of rows)")
    as "the handled rows are the type 8 row and the two type 3 rows the plan reads: 3 of 6"
  assert string.contains(text, "3 rows of the handled types not read")
}

pub fn the_type_11_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects.targetFlags: bit 1 is the caster; the plan reads a type 11 row that
  // includes it (flags 1, 3, 5 and 7) and leaves out one aimed only at others (2, 4 and 6).
  // Planted: five type 11 rows, flags 1, 3, 2, 4 and 6, and one type 8 row.
  let row = fn(id, type_, flags) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
    ])
  }
  use folder <- planted_table.in_folder([
    planted_table.file(spell4_effects.schema, [
      row(1, 11, 1),
      row(2, 11, 3),
      row(3, 11, 2),
      row(4, 11, 4),
      row(5, 11, 6),
      row(6, 8, 4),
    ]),
  ])
  let assert Ok(tables) =
    store.load(
      under: owned_key.new(),
      from: folder,
      entries: [spell4_effects.entry()],
      requirements: [],
      derivations: [],
    )
    as "a planted Spell4Effects table loads"
  let measured =
    measurement.measure(
      EngineDeclaration(
        ..engine_named("Spell effects"),
        starting_abilities: None,
      ),
      tables,
    )
  store.unload(tables)
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(eleven) = list.find(types, fn(line) { line.type_number == 11 })
  assert eleven.rows == 5
  assert eleven.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit: the next step",
      fact_key: "Spell4Effects.effectType.11",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 11: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit: the next step (Spell4Effects.effectType.11)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (50.0% of rows)")
    as "the handled rows are the type 8 row and the two type 11 rows the plan reads: 3 of 6"
  assert string.contains(text, "3 rows of the handled types not read")
}

pub fn the_type_73_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects.targetFlags: bit 1 is the caster; the plan reads a type 73 row that
  // includes it (flags 1, 3, 5 and 7) and leaves out one aimed only at others (2, 4 and
  // 6), whose cooldowns no server rule keeps. Planted: five type 73 rows, flags 1, 3, 2,
  // 4 and 4, and one type 8 row.
  let row = fn(id, type_, flags) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
    ])
  }
  use folder <- planted_table.in_folder([
    planted_table.file(spell4_effects.schema, [
      row(1, 73, 1),
      row(2, 73, 3),
      row(3, 73, 2),
      row(4, 73, 4),
      row(5, 73, 4),
      row(6, 8, 4),
    ]),
  ])
  let assert Ok(tables) =
    store.load(
      under: owned_key.new(),
      from: folder,
      entries: [spell4_effects.entry()],
      requirements: [],
      derivations: [],
    )
    as "a planted Spell4Effects table loads"
  let measured =
    measurement.measure(
      EngineDeclaration(
        ..engine_named("Spell effects"),
        starting_abilities: None,
      ),
      tables,
    )
  store.unload(tables)
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 73 })
  assert line.rows == 5
  assert line.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps",
      fact_key: "Spell4Effects.effectType.73",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 73: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps (Spell4Effects.effectType.73)",
  )
    as "the line lists the rows left out with the gap's reason"
}

pub fn the_clients_522_type_73_rows_count_488_handled_and_34_not_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let assert Measured(types:, ..) =
    measurement.measure(
      engine_named("Spell effects"),
      client_tables.every_table(),
    )
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 73 })
  assert line.rows == 522
    as "table_rows -- Spell4Effects effectType=73: 522 rows"
  assert measurement.is_handled(line.status)
  assert line.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps",
      fact_key: "Spell4Effects.effectType.73",
      unread_rows: 34,
    )
    as "targetFlags 1 in 480 rows and 3 in 8 include the caster (488 handled); 2 in 30 rows and 4 in 4 aim only at others (34 not handled)"
}

/// The measure of planted type 83 or 84 rows beside a type 8 row, for the line of the
/// type given: Spell4Effects.targetFlags bit 1 is the caster, and the plan reads a Stealth
/// or RemoveStealth row that includes it and leaves out one aimed only at others.
fn measured_stealth_rows(
  type_ type_: Int,
  flags flags: List(Int),
) -> measurement.Measurement {
  let row = fn(id, type_, flags) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
    ])
  }
  use folder <- planted_table.in_folder([
    planted_table.file(
      spell4_effects.schema,
      list.append(
        list.index_map(flags, fn(flag, index) { row(index + 1, type_, flag) }),
        [row(99, 8, 4)],
      ),
    ),
  ])
  let assert Ok(tables) =
    store.load(
      under: owned_key.new(),
      from: folder,
      entries: [spell4_effects.entry()],
      requirements: [],
      derivations: [],
    )
    as "a planted Spell4Effects table loads"
  let measured =
    measurement.measure(
      EngineDeclaration(
        ..engine_named("Spell effects"),
        starting_abilities: None,
      ),
      tables,
    )
  store.unload(tables)
  measured
}

pub fn the_type_83_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  // Planted: three type 83 rows, flags 1, 2 and 4, and one type 8 row.
  let assert Measured(types:, ..) =
    measured_stealth_rows(type_: 83, flags: [1, 2, 4])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 83 })
  assert line.rows == 3
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit, which hold no stealth the server keeps",
      fact_key: "Spell4Effects.effectType.83",
      unread_rows: 2,
    )
    as "two of the three rows aim only at others and are not read"
}

pub fn the_type_84_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  // Planted: two type 84 rows, flags 1 and 2, and one type 8 row.
  let assert Measured(types:, ..) =
    measured_stealth_rows(type_: 84, flags: [1, 2])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 84 })
  assert line.rows == 2
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit, whose stealth the server does not hold",
      fact_key: "Spell4Effects.effectType.84",
      unread_rows: 1,
    )
    as "one of the two rows aims only at others and is not read"
}

pub fn the_clients_74_type_83_rows_and_9_type_84_rows_have_11_and_4_aimed_only_at_others_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let assert Measured(types:, ..) =
    measurement.measure(
      engine_named("Spell effects"),
      client_tables.every_table(),
    )
    as "the engine's source is a table"
  let assert Ok(stealth) = list.find(types, fn(line) { line.type_number == 83 })
  assert stealth.rows == 74
    as "table_rows -- Spell4Effects effectType=83: 74 rows"
  assert stealth.status
    == HandledWithGap(
      reason: "rows aimed at another unit, which hold no stealth the server keeps",
      fact_key: "Spell4Effects.effectType.83",
      unread_rows: 11,
    )
    as "targetFlags 1 in 63 rows is the caster; 2 in 7 rows and 4 in 4 aim only at others, so the gap is real and the partial entry stays"
  let assert Ok(remove) = list.find(types, fn(line) { line.type_number == 84 })
  assert remove.rows == 9 as "table_rows -- Spell4Effects effectType=84: 9 rows"
  assert remove.status
    == HandledWithGap(
      reason: "rows aimed at another unit, whose stealth the server does not hold",
      fact_key: "Spell4Effects.effectType.84",
      unread_rows: 4,
    )
    as "targetFlags 1 in 5 rows is the caster; 2 in 3 rows and 4 in 1 aim only at others"
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

// ---- the spend-scaled costs ----

pub fn the_innate_cost_emm_ids_the_measure_handles_are_4_and_7_test() -> Nil {
  use <- owned_test.run(10_000)
  assert handled_over(
      engine: engine_named("Spend-scaled costs"),
      types: numbers(from: 1, to: 30),
    )
    == [4, 7]
    as "the server reads ids 4 and 7 as a spend of every point held (Spell4.innateCostEMMId0); every other id is an unread spend"
}

pub fn the_other_emm_ids_are_decoded_and_missing_with_the_reason_and_the_fact_key_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared = engine_named("Spend-scaled costs")
  assert list.map(declared.missing, fn(missing) { missing.type_number })
    |> list.sort(int.compare)
    == [2, 5, 9, 10, 11]
    as "Spell4.innateCostEMMId0: the ids the rows hold besides 4 and 7 are 2, 5, 9, 10 and 11"
  list.each(declared.missing, fn(missing) {
    assert missing.reason
      == "the id's meaning is not in the client; only 4 and 7 have the Psi Point layout"
    assert missing.fact_key == "Spell4.innateCostEMMId0"
  })
}

/// The rows of each innate cost EMM id in both columns of Spell4, as the measure
/// gives them, heaviest first.
fn emm_rows() -> List(#(Int, Int)) {
  let tables = client_tables.every_table()
  let assert Measured(types:, ..) =
    measurement.measure(engine_named("Spend-scaled costs"), tables)
    as "the engine's source is a table"
  list.map(types, fn(line) { #(line.type_number, line.rows) })
}

pub fn the_spend_engine_counts_the_ids_of_both_columns_and_the_starting_abilities_hold_4_once_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  assert emm_rows()
    == [#(4, 49), #(7, 46), #(10, 3), #(5, 2), #(9, 2), #(2, 1), #(11, 1)]
    as "Spell4.innateCostEMMId0: 4 on 45 rows, 7 on 46, 5 and 9 on 2 each, 2 and 11 on 1 each; innateCostEMMId1: 4 on 6, 10 on 3, 7 on 1: 4 holds 51 and 7 47, less the three rows whose id sits beside no cost (45155 and 48782 with 4, 42075 with 7, counted as empty slots), so 49, 46 and 3 for 10"
  assert starting_counts(engine: engine_named("Spend-scaled costs"))
    == [#(4, 1)]
    as "Spell4.innateCostEMMId0: of the 65 spells the 18 level-1 abilities reach only Mind Burst (32809, id 4) holds one"
}
