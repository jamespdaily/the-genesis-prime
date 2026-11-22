//// The coverage measure's view of the spell effect and prerequisite types: which
//// types are handled (derived from the decode each rule's dispatch reads), which
//// are decoded and missing, and the starting abilities' column. Expected values
//// and their sources:
//// - The types the server reads: effect types 1 (VitalModifier), 8 (Damage), 17
////   (Fluff), 26 (Proxy) and 80 (SpellForceRemove), which `Spell4Effects.effectType.N`
////   and `Spell.CodeEnumSpellEffectType.damage` name, and prerequisite types 4, 15, 28,
////   37, 50, 59, 60, 71, 73, 179, 243 (which always fails) and 250
////   (`Prerequisite.prerequisiteTypeId.N`); a type the client's condition check has no
////   case for fails in the client and in the server (`0x1404a2100`).
//// - The rows of a type are counted from the client's Spell4Effects table
////   (`table_rows -- Spell4Effects effectType=N`); how many of them the plan reads is
////   not pinned, only that the type states its gap and its counts are bounded.
//// - The parts of the starting abilities' trees the measure leaves out are tied to the
////   client's rows: the runner columns (`Spell4.prerequisiteIdRunner00`, `01`) name
////   prerequisites no other column of a reached spell names, and a Proxy starts a child
////   behind a gate whose condition needs the cast of an AMP's spell
////   (`EldanAugmentation.spell4IdAugment`), which `LevelUpUnlock.26` offers above level 1.
//// - The decoded and missing types, with each reason, are the fact file's records
////   (`Spell4Effects.effectType.N`, `Prerequisite.prerequisiteTypeId.N`).

import client_tables
import coverage_support
import fixture_tables
import genesis_prime/coverage
import genesis_prime/coverage/checklist
import genesis_prime/coverage/effect_row
import genesis_prime/coverage/engine.{
  type EngineDeclaration, EngineDeclaration, Listed, Missing,
}
import genesis_prime/coverage/level_one_gate
import genesis_prime/coverage/measurement.{
  type Measurement, HandledWithGap, Measured,
}
import genesis_prime/coverage/starting_ability.{MissingRow}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{Spell}
import genesis_prime/table/class
import genesis_prime/table/creature2
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  EldanAugmentationId, LevelUpUnlockId, PrerequisiteId, Spell4EffectsId,
  Spell4Id,
}
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_slot
import genesis_prime/table/item_special
import genesis_prime/table/level_up_unlock
import genesis_prime/table/loader/store
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell_phase
import genesis_prime/table/unit_property2
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import owned_test
import planted_table
import spell_tables
import unitest

/// The tables the plan's decision about an effect row reads (`spell_plan.sources_of`
/// reads Spell4Effects, SpellPhase, Spell4Thresholds and Spell4GroupList, and the activate
/// cast reads GameFormula, Creature2 and ItemSpecial), planted with no
/// row beside the Spell4Effects rows given, so a row that names a prerequisite, a spell, a spell group,
/// a property or a display finds none (`spell_plan.read_row`). A planted row that leaves
/// phaseFlags out holds -1, every phase, as the client's rows do; a row with phaseFlags 0 is
/// selected by no phase and is not read.
fn planted_files(
  rows rows: List(List(planted_table.Cell)),
) -> List(#(String, BitArray)) {
  let phase_column =
    list.index_fold(spell4_effects.schema.columns, 0, fn(found, column, index) {
      case column.name == "phaseFlags" {
        True -> index
        False -> found
      }
    })
  let in_every_phase =
    list.map(rows, fn(row) {
      list.index_map(row, fn(cell, index) {
        case index == phase_column, cell {
          True, planted_table.Integer(0) -> planted_table.Integer(-1)
          True, _ | False, _ -> cell
        }
      })
    })
  [
    planted_table.file(spell4_effects.schema, in_every_phase),
    planted_table.file(spell4.schema, []),
    planted_table.file(spell4_base.schema, []),
    planted_table.file(spell4_group_list.schema, []),
    planted_table.file(class.schema, []),
    planted_table.file(prerequisite_table.schema, []),
    planted_table.file(positional_requirement.schema, []),
    planted_table.file(unit_property2.schema, []),
    planted_table.file(item_display.schema, []),
    planted_table.file(item2_type.schema, []),
    planted_table.file(item_slot.schema, []),
    planted_table.file(spell4_thresholds.schema, []),
    planted_table.file(spell_phase.schema, []),
    planted_table.file(game_formula.schema, []),
    planted_table.file(creature2.schema, []),
    planted_table.file(item_special.schema, []),
  ]
}

fn planted_entries() -> List(store.Entry) {
  [
    spell4_effects.entry(),
    spell4.entry(),
    spell4_base.entry(),
    spell4_group_list.entry(),
    class.entry(),
    prerequisite_table.entry(),
    positional_requirement.entry(),
    unit_property2.entry(),
    item_display.entry(),
    item2_type.entry(),
    item_slot.entry(),
    spell4_thresholds.entry(),
    spell_phase.entry(),
    game_formula.entry(),
    creature2.entry(),
    item_special.entry(),
  ]
}

/// The measure of the effect types over these planted Spell4Effects rows, with no starting
/// abilities.
fn measure_planted(rows rows: List(List(planted_table.Cell))) -> Measurement {
  measure_planted_over(files: planted_files(rows:))
}

/// The same over these planted files, which hold the tables `planted_files` names.
fn measure_planted_over(files files: List(#(String, BitArray))) -> Measurement {
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    store.read(
      from: folder,
      entries: planted_entries(),
      requirements: [],
      derivations: [],
    )
    as "the planted tables load"
  measurement.measure(
    EngineDeclaration(
      ..coverage_support.engine_named("Spell effects"),
      starting_abilities: None,
    ),
    tables,
  )
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

// ---- the decoded and missing types ----

pub fn each_decoded_type_not_handled_is_listed_with_its_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  list.each(["Spell effects", "Spend-scaled costs", "Prerequisites"], fn(name) {
    let declared = coverage_support.engine_named(name)
    coverage_support.assert_gaps_stated(
      declared:,
      gaps: declared.missing,
      handled: False,
    )
  })
}

pub fn a_partial_type_is_handled_and_carries_the_gap_it_states_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let declared =
    EngineDeclaration(
      ..coverage_support.engine_named("Quest objectives"),
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
  use <- unitest.tag("coverage")
  let declared =
    EngineDeclaration(
      ..coverage_support.engine_named("Quest objectives"),
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

const lasting_gap =
  "rows aimed by a flag with bit 8 or by 3, 5 or 7 in a spell that hits no foes or behind an apply prerequisite whose conditions the plan cannot check, which the plan refuses"

const force_remove_gap =
  "rows aimed by a flag with bit 8 or by 3, 5 or 7 in a spell that hits no foes, behind an apply prerequisite whose conditions the plan cannot check, with differing stack counts (dataBits03 and dataBits04) or a selector that names no spell group, Spell4 or Spell4Base, which the plan refuses"

const signal_gap =
  "rows aimed by a flag with bit 8 or by 3, 5 or 7 in a spell that hits no foes or behind an apply prerequisite whose conditions the plan cannot check, which the plan refuses; the script a signal stands for is not in the client"

const conversion_gap =
  "the share is added to the source's value after the type 11 changes, in start order; whether the source is its base or its total and when the share is recomputed are not read"

pub fn each_effect_type_listed_partial_is_handled_with_a_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let facts = coverage_support.fact_file()
  let declared = coverage_support.engine_named("Spell effects")
  coverage_support.assert_gaps_stated(
    declared:,
    gaps: declared.partial,
    handled: True,
  )
  assert coverage_support.has_record(facts:, key: "spell.heal_result_log")
  assert coverage_support.has_record(facts:, key: "0x1405d6880.delayed_apply")
}

pub fn the_spell_effect_engine_reads_type_76_and_names_its_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let facts = coverage_support.fact_file()
  let declared = coverage_support.engine_named("Spell effects")
  assert handled_over(engine: declared, types: [76]) == [76]
    as "Spell.CodeEnumSpellEffectType value 76 'ItemVisualSwap' (Spell4Effects.effectType.76): the decode names it, so the measure counts it handled"
  let assert [gap] =
    list.filter(declared.partial, fn(missing) { missing.type_number == 76 })
    as "the engine states one gap for type 76"
  assert gap.fact_key == "Spell4Effects.effectType.76"
  assert string.contains(gap.reason, "delayTime")
    as "the gap names the rows the client does not apply: those with a delayTime"
  assert string.contains(gap.reason, "0x1405d6880.delayed_apply")
    as "and the record that says why"
  assert coverage_support.has_record(facts:, key: gap.fact_key)
  assert coverage_support.has_record(facts:, key: "0x1405d6880.delayed_apply")
    as "InitSpellEffect 0x1405d6880 calls the apply slot only when the delay is 0"
}

pub fn the_type_3_rows_aimed_at_other_units_behind_a_target_prerequisite_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Spell4Effects.targetFlags: bit 1 is the caster, 2 the cast's target, 4 the units the
  // area struck and 6 both. The plan reads a type 3 row aimed at the caster or at those
  // units (Spell4Effects.effectType.3.other_unit) and refuses one aimed at them behind a
  // target apply prerequisite. Planted: type 3 rows with flags 1, 5, 2, 4 and 6,
  // two more with flags 2 and 4 behind target apply prerequisite 11311, and one type 8 row.
  let row = fn(id, type_, flags, prerequisite) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
      #("prerequisiteIdTargetApply", planted_table.Integer(prerequisite)),
    ])
  }
  let measured =
    measure_planted_over(
      files: planted_files_naming(rows: [
        row(1, 3, 1, 0),
        row(2, 3, 5, 0),
        row(3, 3, 2, 0),
        row(4, 3, 4, 0),
        row(5, 3, 6, 0),
        row(6, 3, 2, 11_311),
        row(7, 3, 4, 11_311),
        row(8, 8, 4, 0),
      ]),
    )
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(three) = list.find(types, fn(line) { line.type_number == 3 })
  assert three.rows == 7
  assert three.status
    == HandledWithGap(
      reason: "rows aimed at another unit behind a target apply prerequisite, which the plan refuses; rows behind a prerequisite whose conditions the plan cannot check",
      fact_key: "Spell4Effects.effectType.3",
      unread_rows: 2,
    )
    as "only the two rows behind the target prerequisite are not read; the rows aimed at the caster, the target and the area are"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 3: 7 rows (87.5%); handled with a gap, 2 of its 7 rows not read: rows aimed at another unit behind a target apply prerequisite, which the plan refuses; rows behind a prerequisite whose conditions the plan cannot check (Spell4Effects.effectType.3)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (75.0% of rows)")
    as "the handled rows are the type 8 row and the five type 3 rows the plan reads: 6 of 8"
  assert string.contains(text, "2 rows of the handled types not read")
}

pub fn the_type_11_rows_behind_a_target_prerequisite_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Spell4Effects.targetFlags: bit 1 is the caster, 2 the cast's target, 4 the units the
  // area struck and 6 both. The plan reads a type 11 row aimed at the caster or at those
  // units and holds one behind a target apply prerequisite, which no go applies.
  // Planted: five type 11 rows of property 1, which UnitProperty2 holds a row for, with a
  // durationTime (a row with no life is held), flags 1, 2, 4, 6 and 2, the last behind
  // target apply prerequisite 11311, and one type 8 row.
  let row = fn(id, type_, flags, prerequisite) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
      #("dataBits00", planted_table.Integer(1)),
      #("durationTime", planted_table.Integer(5000)),
      #("prerequisiteIdTargetApply", planted_table.Integer(prerequisite)),
    ])
  }
  let measured =
    measure_planted_over(
      files: planted_files_naming(rows: [
        row(1, 11, 1, 0),
        row(2, 11, 2, 0),
        row(3, 11, 4, 0),
        row(4, 11, 6, 0),
        row(5, 11, 2, 11_311),
        row(6, 8, 4, 0),
      ]),
    )
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(eleven) = list.find(types, fn(line) { line.type_number == 11 })
  assert eleven.rows == 5
  assert eleven.status
    == HandledWithGap(
      reason: "rows aimed at another player, which the cast applies to creatures only; rows behind an apply prerequisite whose conditions the plan cannot check, which the plan refuses; rows with a parameter that has a factor, which the plan refuses (`ParameterNotRead`) because no rule reads a stat modifier's parameter factors into its amount (the work that builds that reading closes this gap)",
      fact_key: "Spell4Effects.effectType.11",
      unread_rows: 1,
    )
    as "only the row behind the target prerequisite is not read; the rows aimed at the caster, the target and the area are"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 11: 5 rows (83.33%); handled with a gap, 1 of its 5 rows not read: rows aimed at another player, which the cast applies to creatures only; rows behind an apply prerequisite whose conditions the plan cannot check, which the plan refuses; rows with a parameter that has a factor, which the plan refuses (`ParameterNotRead`) because no rule reads a stat modifier's parameter factors into its amount (the work that builds that reading closes this gap) (Spell4Effects.effectType.11)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (83.33% of rows)")
    as "the handled rows are the type 8 row and the four type 11 rows the plan reads: 5 of 6"
  assert string.contains(text, "1 row of the handled types not read")
}

pub fn the_type_73_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
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
  let measured =
    measure_planted(rows: [
      row(1, 73, 1),
      row(2, 73, 3),
      row(3, 73, 2),
      row(4, 73, 4),
      row(5, 73, 4),
      row(6, 8, 4),
    ])
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 73 })
  assert line.rows == 5
  assert line.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite whose conditions the plan cannot check, which the plan refuses",
      fact_key: "Spell4Effects.effectType.73",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 73: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite whose conditions the plan cannot check, which the plan refuses (Spell4Effects.effectType.73)",
  )
    as "the line lists the rows left out with the gap's reason"
}

pub fn the_clients_522_type_73_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  assert coverage_support.partial_line("Spell effects", type_number: 73).rows
    == 522
    as "table_rows -- Spell4Effects effectType=73: 522 rows"
}

/// The measure of planted type 83 or 84 rows beside a type 8 row, for the line of the
/// type given, each row as (targetFlags, durationTime): Spell4Effects.targetFlags bit 1 is
/// the caster, and the plan reads a Stealth or RemoveStealth row aimed at the caster alone
/// and, for a Stealth row, with no delayTime or durationTime.
fn measured_stealth_rows(
  type_ type_: Int,
  rows rows: List(#(Int, Int)),
) -> measurement.Measurement {
  let row = fn(id, type_, flags, duration) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
      #("durationTime", planted_table.Integer(duration)),
    ])
  }
  measure_planted(
    rows: list.append(
      list.index_map(rows, fn(planted, index) {
        row(index + 1, type_, planted.0, planted.1)
      }),
      [row(99, 8, 4, 0)],
    ),
  )
}

/// One planted row for `measured_shield_rows`, by the columns the plan and the area load
/// read: targetFlags (Spell4Effects.targetFlags bit 1 is the caster, 2 the primary target
/// and 4 the area), tickTime, durationTime, flags (bit 2: until removed) and
/// parameterType00.
type PlantedRow {
  PlantedRow(
    aim: Int,
    tick_ms: Int,
    duration_ms: Int,
    flags: Int,
    parameter: Int,
  )
}

/// A planted row that is not periodic.
fn once(aim aim: Int, parameter parameter: Int) -> PlantedRow {
  PlantedRow(aim:, tick_ms: 0, duration_ms: 0, flags: 0, parameter:)
}

/// The measure of planted type 118, 64 or 8 rows beside a type 8 row, for the line of the
/// type given: the plan reads a type 118 row that reaches the caster, has a formula the
/// caster's value reads and, when periodic, a life of whole ticks; a type 64 row aimed at
/// the area alone; and a type 8 row that is not periodic or has a life of whole ticks.
fn measured_shield_rows(
  type_ type_: Int,
  rows rows: List(PlantedRow),
) -> measurement.Measurement {
  let row = fn(id, type_, planted: PlantedRow) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(planted.aim)),
      #("tickTime", planted_table.Integer(planted.tick_ms)),
      #("durationTime", planted_table.Integer(planted.duration_ms)),
      #("flags", planted_table.Integer(planted.flags)),
      #("parameterType00", planted_table.Integer(planted.parameter)),
      #("parameterValue00", planted_table.Float(0.3)),
    ])
  }
  measure_planted(
    rows: list.append(
      list.index_map(rows, fn(planted, index) { row(index + 1, type_, planted) }),
      [row(99, 8, once(aim: 4, parameter: 0))],
    ),
  )
}

pub fn the_measure_counts_ticking_and_refused_heal_shields_rows_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted: five type 118 rows, two the plan leaves out and three it reads: flags 4
  // (aimed at the area); flags 1 with a tickTime of 1000 and a durationTime of 3000
  // (three ticks); flags 1 with a tickTime of 1000, no durationTime and flags bit 2
  // (until removed); flags 1 with parameter type 18 (a passed-in value, which
  // `damage.unread_on_caster` reads as the caster's `passed_in`); and flags 1 with
  // parameter type 22 (target missing shield). And a type 64 pair, flags
  // 4 and 2.
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 118, rows: [
      once(aim: 4, parameter: 22),
      PlantedRow(
        aim: 1,
        tick_ms: 1000,
        duration_ms: 3000,
        flags: 0,
        parameter: 16,
      ),
      PlantedRow(aim: 1, tick_ms: 1000, duration_ms: 0, flags: 2, parameter: 16),
      once(aim: 1, parameter: 18),
      once(aim: 1, parameter: 22),
    ])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 118 })
  assert line.rows == 5
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit, periodic rows that last until removed (flags bit 2), rows behind an apply prerequisite whose conditions the plan cannot check or with a formula parameter the plan refuses",
      fact_key: "Spell4Effects.effectType.118",
      unread_rows: 2,
    )
    as "the area row is aimed at others and the periodic row that lasts until removed is left out: two of five are not read; the periodic row of three ticks and the kind 18 row (a passed-in value the plan reads) are read"
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 64, rows: [
      once(aim: 4, parameter: 0),
      once(aim: 2, parameter: 0),
    ])
  let assert Ok(overload) =
    list.find(types, fn(line) { line.type_number == 64 })
  assert overload.status
    == HandledWithGap(
      reason: "rows aimed at the caster or its target, whose shield the server does not hold at 0",
      fact_key: "Spell4Effects.effectType.64",
      unread_rows: 1,
    )
    as "the row aimed at the primary target is not read; the one aimed at the area is"
}

pub fn the_measure_counts_a_periodic_damage_row_that_lasts_until_removed_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted: three type 8 rows aimed at the area, one with a tickTime of 1000 and a
  // durationTime of 3000, one with a tickTime of 1000 and flags bit 2 (until removed) and
  // one with no tickTime, and the type 8 row of the helper, aimed at the area with no
  // tickTime.
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 8, rows: [
      PlantedRow(
        aim: 4,
        tick_ms: 1000,
        duration_ms: 3000,
        flags: 0,
        parameter: 0,
      ),
      PlantedRow(aim: 4, tick_ms: 1000, duration_ms: 0, flags: 2, parameter: 0),
      once(aim: 4, parameter: 0),
    ])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 8 })
  assert line.rows == 4
  assert line.status
    == HandledWithGap(
      reason: "rows with a formula parameter a player's value does not read (the weapon types 6 and 9, the passed-in value 18), aimed by a flag the area load refuses, or with a multiplier that is not a finite number, which the area load refuses; periodic rows that last until removed (flags bit 2), which the area load leaves out; rows aimed at their caster alone, which load and strike nobody",
      fact_key: "0x140566ad0",
      unread_rows: 1,
    )
    as "the periodic row of three ticks strikes once for each tick and is read; the one that lasts until removed has no schedule and is left out"
}

pub fn the_type_8_rows_naming_only_vital_kinds_are_counted_as_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Spell4Effects.targetFlags bit 1 is the caster, 2 the primary target and 4 the area;
  // parameterType00 7 is the target's max health, 23 the caster's health and 18 a
  // passed-in value (0x140566ad0). Planted: kind 7 aimed at the area, kind 23 aimed at the
  // primary target, kind 18 aimed at the area, and kind 7 aimed at the caster alone, which
  // loads but strikes nobody. The helper adds a plain row aimed at the area.
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 8, rows: [
      once(aim: 4, parameter: 7),
      once(aim: 2, parameter: 23),
      once(aim: 4, parameter: 18),
      once(aim: 1, parameter: 7),
    ])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 8 })
  assert line.rows == 5
  let assert HandledWithGap(reason:, unread_rows:, ..) = line.status
    as "the type 8 line keeps a gap"
  assert unread_rows == 2
    as "the kind 18 row and the row aimed at the caster alone are not read; the vital kinds 7 and 23 are"
  assert !string.contains(reason, "vital")
    as "the gap no longer names the vital kinds as unread"
  assert string.contains(reason, "rows aimed at their caster alone")
    as "the caster-alone rows are named"
  assert !string.contains(reason, "#") as "the reason names no issue"
}

pub fn the_type_83_rows_aimed_at_other_units_or_timed_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted: four type 83 rows, flags 1, 2, 4 and 1 with a durationTime of 8000, and one
  // type 8 row.
  let assert Measured(types:, ..) =
    measured_stealth_rows(type_: 83, rows: [
      #(1, 0),
      #(2, 0),
      #(4, 0),
      #(1, 8000),
    ])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 83 })
  assert line.rows == 4
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit, behind a target prerequisite whose conditions the plan cannot check or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
      fact_key: "Spell4Effects.effectType.83",
      unread_rows: 3,
    )
    as "two of the four rows aim only at others and the timed one is refused by the plan: three are not read"
}

pub fn type_42_rows_are_counted_read_by_their_aim_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Seven type 42 rows (flags, amount, durationTime): the caster, the primary target alone and
  // the caster with the primary target are read; the area, the primary target with the area, an
  // amount of 0 and a duration the client does not read are not.
  let rows =
    list.index_map(
      [
        #(1, 1, 0),
        #(2, 1, 0),
        #(3, 1, 0),
        #(4, 1, 0),
        #(6, 1, 0),
        #(1, 0, 0),
        #(1, 1, 1000),
      ],
      fn(planted, index) {
        spell4_effects.Spell4Effects(
          ..spell_tables.blank_effect(
            id: index + 1,
            spell: 1,
            effect_type: 42,
            target_flags: planted.0,
          ),
          data_bits02: planted.1,
          duration_time: planted.2,
        )
      },
    )
  assert effect_row.unread_by_type(
      tables: fixture_tables.shared(),
      effects: rows,
    )
    |> dict.get(42)
    == Ok(4)
    as "the rows aimed at the area, with an amount of 0 and with a duration are not read: four of seven"
  let assert Ok(declared) =
    list.find(coverage_support.engine_named("Spell effects").partial, fn(type_) {
      type_.type_number == 42
    })
  assert declared.fact_key == "Spell4Effects.effectType.42"
    as "the type is handled with the gap its reason names and the fact the file holds"
}

pub fn the_type_84_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted: two type 84 rows, flags 1 and 2, and one type 8 row. A RemoveStealth row's
  // durationTime is not a timed stealth and the plan does not refuse it.
  let assert Measured(types:, ..) =
    measured_stealth_rows(type_: 84, rows: [#(1, 5000), #(2, 0)])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 84 })
  assert line.rows == 2
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit or behind a target prerequisite whose conditions the plan cannot check, which the plan refuses",
      fact_key: "Spell4Effects.effectType.84",
      unread_rows: 1,
    )
    as "one of the two rows aims only at others and is not read"
}

pub fn the_clients_74_type_83_rows_and_9_type_84_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  assert coverage_support.partial_line("Spell effects", type_number: 83).rows
    == 74
    as "table_rows -- Spell4Effects effectType=83: 74 rows"
  assert coverage_support.partial_line("Spell effects", type_number: 84).rows
    == 9
    as "table_rows -- Spell4Effects effectType=84: 9 rows"
}

pub fn a_type_both_handled_and_listed_missing_is_a_conflict_and_an_unused_missing_type_a_breach_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let declared =
    EngineDeclaration(
      ..coverage_support.engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      partial: [],
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
  use <- unitest.tag("coverage")
  let declared =
    EngineDeclaration(
      ..coverage_support.engine_named("Quest objectives"),
      handled: Listed(ids: [7]),
      partial: [],
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
    "| Quest objectives | 4 | 8 | 3 | 1 | 2 of 4 |",
  )
    as "the totals row carries the starting abilities' rows handled"
}

// ---- rows a starting ability's tree names that the tables lack ----

/// The client's rows with Energize's Spell4 row naming these Prerequisite ids in
/// these columns. No client row names a prerequisite the table lacks, so the edit
/// is the fault.
fn rows_with_energize_naming(
  columns columns: List(#(String, Int)),
) -> spell_tables.Rows {
  let rows = spell_tables.fixture_rows()
  spell_tables.Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [planted_table.Integer(69_450), ..] ->
          list.fold(columns, row, fn(row, column) {
            spell_tables.with_column(
              row:,
              name: column.0,
              cell: planted_table.Integer(column.1),
            )
          })
        other -> other
      }
    }),
  )
}

/// The same naming one Prerequisite id in one column.
fn rows_naming(
  column column: String,
  prerequisite_id prerequisite_id: Int,
) -> spell_tables.Rows {
  rows_with_energize_naming(columns: [#(column, prerequisite_id)])
}

fn with_trees_loaded(
  rows rows: spell_tables.Rows,
  body body: fn(store.Tables) -> a,
) -> a {
  spell_tables.with_loaded_deriving(
    rows:,
    reaching: [#("SpellLevel", 1086)],
    derivations: [spell_plan.derivation(area_checked: spell_area.checker)],
    body:,
  )
}

pub fn a_prerequisite_a_spell_column_names_that_the_table_lacks_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let lacking =
    MissingRow(
      table: "Prerequisite",
      id: 77_777,
      named_by: "Spell4 69450 column prerequisiteIdAoeTarget",
    )
  assert with_trees_loaded(
      rows: rows_naming(
        column: "prerequisiteIdAoeTarget",
        prerequisite_id: 77_777,
      ),
      body: fn(tables) { starting_ability.prerequisite_types(tables) },
    )
    == Error([lacking])
    as "Spell4 69450 names Prerequisite 77777 in prerequisiteIdAoeTarget and the table has no such row: it is reported with the row and the column, not left out of the starting abilities' types"
  assert with_trees_loaded(
      rows: rows_naming(
        column: "prerequisiteIdAoeTarget",
        prerequisite_id: 43_811,
      ),
      body: starting_ability.prerequisite_types,
    )
    == with_trees_loaded(
      rows: spell_tables.fixture_rows(),
      body: starting_ability.prerequisite_types,
    )
    as "a row the table holds, 43811, which Energize's effect 228910 already names, counts once however many columns name it"
}

pub fn a_spell_of_the_tree_the_spell4_table_lacks_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert with_trees_loaded(rows: spell_tables.fixture_rows(), body: fn(tables) {
      let assert Ok([spell, ..]) = starting_ability.spells(tables:)
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
  use <- unitest.tag("coverage")
  let measured =
    with_trees_loaded(
      rows: rows_naming(
        column: "prerequisiteIdAoeTarget",
        prerequisite_id: 77_777,
      ),
      body: fn(tables) {
        measurement.measure(
          coverage_support.engine_named("Prerequisites"),
          tables,
        )
      },
    )
  let assert Measured(missing_rows:, ..) = measured
    as "the Prerequisite table is a source"
  assert missing_rows
    == [
      MissingRow(
        table: "Prerequisite",
        id: 77_777,
        named_by: "Spell4 69450 column prerequisiteIdAoeTarget",
      ),
    ]
    as "the measure keeps the missing row"
  assert list.any(coverage.breaches([measured]), fn(line) {
    string.contains(
      line,
      "Prerequisites reaches rows the client's tables lack: Prerequisite 77777, named by Spell4 69450 column prerequisiteIdAoeTarget, is not in the client's tables",
    )
  })
    as "the tool's breaches, which end it with exit 1, name the row"
}

// ---- what a level-1 character reaches and the server checks ----

/// The Spell4 of the AMP 'D+U - Inlaid B' (EldanAugmentation 863, a Stalker AMP),
/// which Prerequisite 37037 names (`table_rows -- EldanAugmentation 863`).
const amp_spell = 59_436

/// A Spell4 that no EldanAugmentation row names, one of the two Deja Vu's gate
/// 44174 names (`table_rows -- Prerequisite 44174`).
const other_spell = 87_333

/// What the gates read as the client's rows hold it: EldanAugmentation 863 names
/// the AMP spell and LevelUpUnlock 26 offers AMPs at level 10.
fn amp_gates() -> level_one_gate.Gates {
  level_one_gate.gates(amps: [#(amp_spell, 863)], amp_level: 10)
}

fn needs_amp() -> level_one_gate.Closed {
  level_one_gate.NeedsAmp(
    spell4_id: amp_spell,
    eldan_augmentation_id: 863,
    level: 10,
  )
}

/// A Prerequisite row as the client holds it: its flags and up to three conditions
/// as (type, comparison, objectId, value), the others empty.
fn gate_row(
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> prerequisite_table.Prerequisite {
  let padded = list.append(conditions, list.repeat(#(0, 0, 0, 0), 3))
  let assert [first, second, third, ..] = padded as "three conditions"
  prerequisite_table.Prerequisite(
    id: 1,
    flags:,
    prerequisite_type_id0: first.0,
    prerequisite_type_id1: second.0,
    prerequisite_type_id2: third.0,
    prerequisite_comparison_id0: first.1,
    prerequisite_comparison_id1: second.1,
    prerequisite_comparison_id2: third.1,
    object_id0: first.2,
    object_id1: second.2,
    object_id2: third.2,
    value0: first.3,
    value1: second.3,
    value2: third.3,
    localized_text_id_failure: 0,
  )
}

fn closed_by(
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> Result(level_one_gate.Closed, Nil) {
  level_one_gate.row_closed(
    gates: amp_gates(),
    row: gate_row(flags:, conditions:),
  )
}

pub fn a_condition_that_needs_the_cast_of_an_amp_spell_cannot_open_at_level_1_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert closed_by(flags: 0, conditions: [#(15, 1, 0, amp_spell)])
    == Ok(needs_amp())
    as "type 15, comparison 1: the unit is a target of a live cast of the AMP spell, which a level-1 character has not unlocked (LevelUpUnlock 26 offers AMPs at level 10)"
  assert closed_by(flags: 0, conditions: [#(50, 1, 0, amp_spell)])
    == Ok(needs_amp())
    as "type 50, comparison 1: the same under a cast of the AMP spell by the caster"
}

pub fn a_condition_that_needs_no_amp_cast_can_open_at_level_1_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert closed_by(flags: 0, conditions: [#(15, 2, 0, amp_spell)]) == Error(Nil)
    as "type 15, comparison 2: not under a cast of the AMP spell, which is true at level 1 (Prerequisite 24581 reads so)"
  assert closed_by(flags: 0, conditions: [#(15, 1, 0, other_spell)])
    == Error(Nil)
    as "a spell no EldanAugmentation names has no level to wait for"
  assert closed_by(flags: 0, conditions: [#(28, 1, 0, 0)]) == Error(Nil)
    as "a type the measure has no level evidence for leaves the gate open"
}

pub fn an_or_gate_is_closed_only_when_every_condition_is_and_an_and_gate_when_one_is_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert closed_by(flags: 1, conditions: [
      #(15, 1, 0, amp_spell),
      #(15, 1, 0, other_spell),
    ])
    == Error(Nil)
    as "an OR row (flags bit 0) passes when any condition does, as Prerequisite 44174 reads: Deja Vu's gate"
  assert closed_by(flags: 1, conditions: [
      #(15, 1, 0, amp_spell),
      #(50, 1, 0, amp_spell),
    ])
    == Ok(needs_amp())
    as "an OR row of two conditions that both need the AMP cast cannot pass"
  assert closed_by(flags: 0, conditions: [
      #(15, 1, 0, other_spell),
      #(15, 1, 0, amp_spell),
    ])
    == Ok(needs_amp())
    as "an AND row passes only when every condition does"
  assert closed_by(flags: 1, conditions: []) == Ok(level_one_gate.EmptyOrRow)
    as "an OR row with no kept condition fails (0x1404a1ca0), so a Proxy behind it never starts"
  assert closed_by(flags: 0, conditions: []) == Error(Nil)
    as "an AND row with no kept condition passes"
}

pub fn an_amp_spell_condition_can_open_when_the_amp_unlock_is_offered_at_level_1_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert level_one_gate.row_closed(
      gates: level_one_gate.gates(amps: [#(amp_spell, 863)], amp_level: 1),
      row: gate_row(flags: 0, conditions: [#(15, 1, 0, amp_spell)]),
    )
    == Error(Nil)
    as "the level comes from LevelUpUnlock row 26; at level 1 a new character holds the AMP's spell as far as the measure can tell"
}

pub fn a_level_condition_a_level_1_character_fails_cannot_open_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert closed_by(flags: 0, conditions: [#(1, 4, 0, 2)])
    == Ok(level_one_gate.FailsAtLevelOne(comparison: 4, value: 2))
    as "type 1 compares the unit's level (0x1404a2100, GetUnitFormulaLevel 0x1403b5030) by comparison 4, at least: 1 is not at least 2"
  assert closed_by(flags: 0, conditions: [#(1, 3, 0, 1)])
    == Ok(level_one_gate.FailsAtLevelOne(comparison: 3, value: 1))
    as "comparison 3, greater than: 1 is not greater than 1"
  assert closed_by(flags: 0, conditions: [#(1, 5, 0, 1)])
    == Ok(level_one_gate.FailsAtLevelOne(comparison: 5, value: 1))
    as "comparison 5, less than: 1 is not less than 1 (0x1404a2090)"
}

pub fn a_level_condition_a_level_1_character_passes_can_open_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  assert closed_by(flags: 0, conditions: [#(1, 4, 0, 1)]) == Error(Nil)
    as "comparison 4: 1 is at least 1"
  assert closed_by(flags: 0, conditions: [#(1, 1, 0, 1)]) == Error(Nil)
    as "comparison 1: 1 equals 1"
  assert closed_by(flags: 0, conditions: [#(1, 6, 0, 10)]) == Error(Nil)
    as "comparison 6, at most: 1 is at most 10"
}

const closed_proxy = 990_001

const closed_child = 990_100

const closed_grandchild = 990_200

const second_column_proxy = 990_011

const second_column_child = 990_110

const open_proxy = 990_021

const open_child = 990_120

/// A Proxy effect of Energize (69450, a level-1 ability) that starts `child`,
/// behind a caster apply prerequisite and a dataBits06 prerequisite (0 for none).
fn proxy_of_energize(
  id id: Int,
  child child: Int,
  caster_apply caster_apply: Int,
  data_bits06 data_bits06: Int,
  order order: Int,
) -> List(planted_table.Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", planted_table.Integer(id)),
    #("spellId", planted_table.Integer(69_450)),
    #("targetFlags", planted_table.Integer(1)),
    #("effectType", planted_table.Integer(26)),
    #("phaseFlags", planted_table.Integer(-1)),
    #("dataBits00", planted_table.Integer(child)),
    #("dataBits06", planted_table.Integer(data_bits06)),
    #("prerequisiteIdCasterApply", planted_table.Integer(caster_apply)),
    #("orderIndex", planted_table.Integer(order)),
  ])
}

/// A spell of a planted tree, with Energize's base.
fn tree_spell(id id: Int) -> List(planted_table.Cell) {
  spell_tables.method_spell_row(
    id:,
    base: 46_615,
    cast_time: 0,
    cooldown: 0,
    kind: 0,
    global: 0,
    cost: #(0, 0),
    more: [],
  )
}

/// A Fluff row (type 17) of a planted spell.
fn tree_effect(
  id id: Int,
  spell spell: Int,
  type_ type_: Int,
  data data: Int,
  order order: Int,
) -> List(planted_table.Cell) {
  spell_tables.effect_row(
    id:,
    spell:,
    type_:,
    target_flags: 1,
    delay: 0,
    phases: -1,
    data:,
    order:,
  )
}

/// The planted rows with three Proxies of Energize, each starting a child that holds
/// a Fluff row:
/// - 990001 behind Prerequisite 990300, a type 15 on the AMP spell, to 990100, whose
///   own Proxy starts 990200;
/// - 990011 behind an open caster apply prerequisite (990301, not under the AMP
///   spell) and a dataBits06 prerequisite on the AMP spell (990302), to 990110;
/// - 990021 behind that open prerequisite and a dataBits06 prerequisite on a spell
///   no AMP names (990303), to 990120.
/// EldanAugmentation 863 names the AMP spell and LevelUpUnlock 26 is offered at
/// level 10, as the client's rows hold them.
fn rows_with_three_proxies() -> spell_tables.Rows {
  let rows = spell_tables.fixture_rows()
  spell_tables.Rows(
    ..rows,
    spell4: spell_tables.sorted_by_id([
      tree_spell(id: closed_child),
      tree_spell(id: closed_grandchild),
      tree_spell(id: second_column_child),
      tree_spell(id: open_child),
      ..rows.spell4
    ]),
    spell4_effects: spell_tables.sorted_by_id([
      proxy_of_energize(
        id: closed_proxy,
        child: closed_child,
        caster_apply: 990_300,
        data_bits06: 0,
        order: 20,
      ),
      proxy_of_energize(
        id: second_column_proxy,
        child: second_column_child,
        caster_apply: 990_301,
        data_bits06: 990_302,
        order: 21,
      ),
      proxy_of_energize(
        id: open_proxy,
        child: open_child,
        caster_apply: 990_301,
        data_bits06: 990_303,
        order: 22,
      ),
      tree_effect(
        id: 990_101,
        spell: closed_child,
        type_: 17,
        data: 0,
        order: 0,
      ),
      tree_effect(
        id: 990_102,
        spell: closed_child,
        type_: 26,
        data: closed_grandchild,
        order: 1,
      ),
      tree_effect(
        id: 990_201,
        spell: closed_grandchild,
        type_: 17,
        data: 0,
        order: 0,
      ),
      tree_effect(
        id: 990_111,
        spell: second_column_child,
        type_: 17,
        data: 0,
        order: 0,
      ),
      tree_effect(id: 990_121, spell: open_child, type_: 17, data: 0, order: 0),
      ..rows.spell4_effects
    ]),
    prerequisites: spell_tables.sorted_by_id([
      spell_tables.prerequisite_row(id: 990_300, flags: 0, conditions: [
        #(15, 1, 0, amp_spell),
      ]),
      spell_tables.prerequisite_row(id: 990_301, flags: 0, conditions: [
        #(15, 2, 0, amp_spell),
      ]),
      spell_tables.prerequisite_row(id: 990_302, flags: 0, conditions: [
        #(15, 1, 0, amp_spell),
      ]),
      spell_tables.prerequisite_row(id: 990_303, flags: 0, conditions: [
        #(15, 1, 0, other_spell),
      ]),
      ..rows.prerequisites
    ]),
    eldan_augmentations: [
      spell_tables.eldan_augmentation_row(id: 863, class: 5, spell: amp_spell),
    ],
  )
}

pub fn a_proxy_behind_a_gate_that_cannot_open_is_left_out_with_its_subtree_whichever_gate_column_holds_it_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let assert Ok(spells) =
    with_trees_loaded(
      rows: rows_with_three_proxies(),
      body: starting_ability.spells,
    )
    as "the planted rows hold what the walk names"
  let ids = list.map(spells, fn(spell) { spell.spell4_id.value })
  assert list.contains(ids, 69_450) as "Energize itself is reached"
  assert !list.contains(ids, closed_child)
    as "the caster apply gate needs a cast of the AMP spell"
  assert !list.contains(ids, closed_grandchild)
    as "what is below a child left out is left out with it"
  assert !list.contains(ids, second_column_child)
    as "the Proxy starts only when its caster apply prerequisite and its dataBits06 prerequisite both pass (Spell4Effects.effectType.26.dataBits06)"
  assert list.contains(ids, open_child)
    as "a dataBits06 prerequisite on a spell no AMP names leaves the Proxy open"
}

pub fn each_proxy_left_out_is_listed_with_its_gate_and_what_is_below_it_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let assert Ok(left) =
    with_trees_loaded(rows: rows_with_three_proxies(), body: fn(tables) {
      starting_ability.left_out(tables:)
    })
    as "the planted rows hold what the walk names"
  let left =
    list.filter(left, fn(part) {
      case part {
        starting_ability.ProxyGateClosed(proxy_effect_id: id, ..) ->
          id >= 990_000
        starting_ability.RunnerColumnsOnly(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.ProcLeftOut(..)
        | starting_ability.InnateSlotClosed(..) -> False
      }
    })
  assert left
    == [
      starting_ability.ProxyGateClosed(
        proxy_effect_id: closed_proxy,
        parent: 69_450,
        child: closed_child,
        gate: 990_300,
        why: needs_amp(),
        spells: [closed_child, closed_grandchild],
        effects: [#(990_101, 17), #(990_102, 26), #(990_201, 17)],
      ),
      starting_ability.ProxyGateClosed(
        proxy_effect_id: second_column_proxy,
        parent: 69_450,
        child: second_column_child,
        gate: 990_302,
        why: needs_amp(),
        spells: [second_column_child],
        effects: [#(990_111, 17)],
      ),
    ]
    as "the Proxy, its parent, its child, the gate that is closed and the AMP, and every spell and effect row below it"
  let assert [line, _] =
    list.map(left, fn(part) {
      starting_ability.describe_left_out(left_out: part)
    })
  assert string.contains(line, "Proxy effect 990001 of Spell4 69450")
    as "the line names the Proxy and its parent"
  assert string.contains(line, "starts Spell4 990100")
    as "the line names the child"
  assert string.contains(line, "Prerequisite 990300")
    as "the line names the gate"
  assert string.contains(line, "EldanAugmentation 863")
    as "the line names the AMP"
  assert string.contains(line, "level 10 (LevelUpUnlock 26)")
    as "the line names the level and the row it comes from"
  assert string.contains(
    level_one_gate.describe(
      gate: 5,
      closed: level_one_gate.FailsAtLevelOne(comparison: 4, value: 2),
    ),
    "needs level 2",
  )
    as "a level condition says the level it needs"
}

pub fn a_missing_amp_unlock_row_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let rows = rows_with_three_proxies()
  assert with_trees_loaded(
      rows: spell_tables.Rows(..rows, level_up_unlocks: []),
      body: fn(tables) { starting_ability.spells(tables:) },
    )
    == Error([
      MissingRow(
        table: "LevelUpUnlock",
        id: 26,
        named_by: "the AMP unlock the measure reads the level of an AMP spell from",
      ),
    ])
    as "the measure cannot tell when an AMP spell is held without the AMP unlock's row, and says so"
}

// The shape of Prerequisite 41834 (`table_rows -- Prerequisite 41834`: flags 1, two
// type 43 conditions on Quest2 10518 and 10524, objective 4). The client's own
// spells name 41834 in runner columns (Spell4 32812, 34355, 38791, 41438, 42352 and
// 58591, column prerequisiteIdRunner01).

/// The id of a planted copy of that shape, an id no client row holds.
const quest_copy = 990_410

fn with_quest_copy(rows rows: spell_tables.Rows) -> spell_tables.Rows {
  spell_tables.Rows(
    ..rows,
    prerequisites: spell_tables.sorted_by_id([
      spell_tables.prerequisite_row(id: quest_copy, flags: 1, conditions: [
        #(43, 1, 10_518, 4),
        #(43, 1, 10_524, 4),
      ]),
      ..rows.prerequisites
    ]),
  )
}

fn rows_naming_quest_copy(column column: String) -> spell_tables.Rows {
  with_quest_copy(rows: rows_naming(column:, prerequisite_id: quest_copy))
}

/// How many conditions of this type the walk counts over these rows.
fn type_count(rows rows: spell_tables.Rows, number number: Int) -> Int {
  let assert Ok(types) =
    with_trees_loaded(rows:, body: starting_ability.prerequisite_types)
    as "the rows hold what the walk names"
  list.count(types, fn(type_number) { type_number == number })
}

/// What the walk counts over the client's rows alone.
fn client_type_count(number number: Int) -> Int {
  type_count(rows: spell_tables.fixture_rows(), number:)
}

pub fn a_prerequisite_only_the_runner_columns_name_is_not_counted_and_is_listed_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let assert #(types, Ok(left), report) =
    with_trees_loaded(
      rows: rows_naming_quest_copy(column: "prerequisiteIdRunner01"),
      body: fn(tables) {
        #(
          starting_ability.prerequisite_types(tables),
          starting_ability.left_out(tables:),
          coverage.left_out_report(tables:),
        )
      },
    )
    as "the planted rows hold what the walk names"
  let assert Ok(types) = types as "the rows the planted tree names are held"
  assert list.count(types, fn(type_number) { type_number == 43 })
    == client_type_count(number: 43)
    as "the runner column's two type 43 conditions are not counted (the client reads a runner column only to show a prompt on the ability button, Spell4.prerequisiteIdRunner00)"
  let mine =
    list.filter(left, fn(part) {
      case part {
        starting_ability.RunnerColumnsOnly(prerequisite_id: id, ..) ->
          id == quest_copy
        starting_ability.ProxyGateClosed(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.ProcLeftOut(..)
        | starting_ability.InnateSlotClosed(..) -> False
      }
    })
  assert mine
    == [
      starting_ability.RunnerColumnsOnly(
        prerequisite_id: quest_copy,
        conditions: 2,
        named_by: ["Spell4 69450 column prerequisiteIdRunner01"],
      ),
    ]
    as "the runner column alone names the copy: it is listed with the column and its two conditions"
  let assert [part] = mine as "one part is left out"
  let sentence =
    "Prerequisite 990410 (2 conditions) is named only by Spell4 69450 column prerequisiteIdRunner01: the client reads a runner column only to show a prompt on the ability button (Spell4.prerequisiteIdRunner00)"
  assert starting_ability.describe_left_out(left_out: part) == sentence
    as "the sentence names the prerequisite, its conditions, the column and why a runner column is not counted"
  assert string.contains(
      report,
      "Starting abilities, left out of the counts above:\n- ",
    )
    && string.contains(report, "\n- " <> sentence)
    as "the measure prints the heading and one line for each part left out"
}

/// The planted rows with Spell4 69450 naming these Prerequisite ids in the area
/// columns, which the plan's load does not read, and these Prerequisite rows (id,
/// flags, conditions as (type, comparison, objectId, value)).
fn rows_nesting(
  named named: List(Int),
  prerequisites prerequisites: List(#(Int, Int, List(#(Int, Int, Int, Int)))),
) -> spell_tables.Rows {
  let rows =
    rows_with_energize_naming(columns: list.zip(
      ["prerequisiteIdAoeTarget", "prerequisiteIdAoePreferredTarget"],
      named,
    ))
  spell_tables.Rows(
    ..rows,
    prerequisites: spell_tables.sorted_by_id(list.append(
      list.map(prerequisites, fn(row) {
        spell_tables.prerequisite_row(
          id: row.0,
          flags: row.1,
          conditions: row.2,
        )
      }),
      rows.prerequisites,
    )),
  )
}

pub fn a_nested_prerequisite_is_followed_and_each_row_counts_once_however_many_nest_it_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // 990900 nests 990901 and 990902, which nests 990901 again; a second column names
  // 990901 directly. 990901 holds a type 243 and a type 129 (Prerequisite 12939's
  // type). The client's rows hold conditions of these types too, so each count is
  // what the planted rows add to the client's own.
  let rows =
    rows_nesting(named: [990_900, 990_901], prerequisites: [
      #(990_900, 0, [#(11, 1, 990_901, 0), #(11, 2, 990_902, 0)]),
      #(990_901, 0, [#(243, 1, 0, 100), #(129, 2, 313, 0)]),
      #(990_902, 0, [#(11, 1, 990_901, 0)]),
    ])
  let assert Ok(types) =
    with_trees_loaded(rows:, body: starting_ability.prerequisite_types)
    as "the planted rows hold what the walk names"
  let added = fn(number) {
    list.count(types, fn(type_number) { type_number == number })
    - client_type_count(number:)
  }
  assert added(11) == 3
    as "the type 11 conditions of 990900 (two) and 990902 (one) are each counted"
  assert added(243) == 1 && added(129) == 1
    as "990901's two conditions are counted once: three rows nest it and a column names it, and a prerequisite counts once (Prerequisite.prerequisiteTypeId.11: the client evaluates each nested row whole)"
}

pub fn a_nested_id_with_no_row_is_not_a_missing_row_and_a_cycle_ends_the_walk_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let rows =
    rows_nesting(named: [990_903, 990_910], prerequisites: [
      #(990_903, 0, [#(11, 1, 77_777, 0)]),
      #(990_910, 0, [#(11, 1, 990_911, 0)]),
      #(990_911, 0, [#(11, 1, 990_910, 0)]),
    ])
  let assert Ok(types) =
    with_trees_loaded(rows:, body: starting_ability.prerequisite_types)
    as "a nested id the table lacks is no error: the client's evaluator fails it (0x1404a1ca0), so there is nothing to count"
  assert list.count(types, fn(type_number) { type_number == 11 })
    - client_type_count(number: 11)
    == 3
    as "990903's one condition and the two rows of the cycle count once each"
}

pub fn a_runner_column_naming_a_row_the_table_lacks_is_not_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let #(types, left) =
    with_trees_loaded(
      rows: rows_naming(
        column: "prerequisiteIdRunner00",
        prerequisite_id: 77_777,
      ),
      body: fn(tables) {
        #(
          starting_ability.prerequisite_types(tables),
          starting_ability.left_out(tables:),
        )
      },
    )
  assert result.is_ok(types)
    as "nothing reads a runner column, so a row it names that the table lacks is not an error"
  let assert Ok(left) = left
  assert !list.any(left, fn(part) {
    string.contains(starting_ability.describe_left_out(left_out: part), "77777")
  })
    as "and the row is not listed: there is nothing to count"
}

pub fn a_prerequisite_a_runner_column_and_another_column_name_is_counted_and_not_left_out_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let both =
    with_quest_copy(
      rows: rows_with_energize_naming(columns: [
        #("prerequisiteIdRunner00", quest_copy),
        #("prerequisiteIdCasterCast", quest_copy),
      ]),
    )
  let assert #(Ok(types), left) =
    with_trees_loaded(rows: both, body: fn(tables) {
      #(
        starting_ability.prerequisite_types(tables),
        starting_ability.left_out(tables:),
      )
    })
    as "the planted rows hold what the walk names"
  assert list.count(types, fn(type_number) { type_number == 43 })
    - client_type_count(number: 43)
    == 2
    as "a column the measure reads names the copy too, so its two type 43 conditions are counted"
  let assert Ok(left) = left
  assert !list.any(left, fn(part) {
    string.contains(
      starting_ability.describe_left_out(left_out: part),
      "Prerequisite 990410",
    )
  })
    as "and the copy is not left out"
}

/// The spells of the AMPs (`EldanAugmentation.spell4IdAugment`) that a condition of the
/// Prerequisite row `prerequisite_id` needs a cast of: a type 15 or 50 condition of
/// comparison 1 (`Prerequisite.prerequisiteTypeId.15`, `.50`), read from the row's own
/// columns.
fn amp_spells_the_gate_needs(
  tables tables: store.Tables,
  prerequisite_id prerequisite_id: Int,
) -> List(Int) {
  let amps =
    list.map(eldan_augmentation.all(tables), fn(row) { row.spell4_id_augment })
  case prerequisite_table.get(tables:, id: PrerequisiteId(prerequisite_id)) {
    Ok(row) ->
      [
        #(
          row.prerequisite_type_id0,
          row.prerequisite_comparison_id0,
          row.value0,
        ),
        #(
          row.prerequisite_type_id1,
          row.prerequisite_comparison_id1,
          row.value1,
        ),
        #(
          row.prerequisite_type_id2,
          row.prerequisite_comparison_id2,
          row.value2,
        ),
      ]
      |> list.filter_map(fn(condition) {
        case condition {
          #(15, 1, value) | #(50, 1, value) ->
            case list.contains(amps, value) {
              True -> Ok(value)
              False -> Error(Nil)
            }
          _ -> Error(Nil)
        }
      })
    Error(Nil) -> []
  }
}

/// The Prerequisite ids the columns of a reached Spell4 row and of its effect rows name
/// besides the runner columns, which the measure counts: the Spell4 row's cast, persistence
/// and area columns, an effect's apply, persistence and suspend columns, and a Proxy's
/// dataBits06 gate.
fn counted_prerequisite_columns(
  tables tables: store.Tables,
  reached reached: List(spell4.Spell4),
) -> List(Int) {
  let reached_ids = list.map(reached, fn(row) { row.id })
  let from_spells =
    list.flat_map(reached, fn(row) {
      [
        row.prerequisite_id_caster_cast,
        row.prerequisite_id_target_cast,
        row.prerequisite_id_caster_persistence,
        row.prerequisite_id_target_persistence,
        row.prerequisite_id_aoe_target,
        row.prerequisite_id_aoe_preferred_target,
      ]
    })
  let from_effects =
    list.filter(spell4_effects.all(tables), fn(effect) {
      list.contains(reached_ids, effect.spell_id)
    })
    |> list.flat_map(fn(effect) {
      let gate = case effect.effect_type {
        26 -> [effect.data_bits06]
        _ -> []
      }
      [
        effect.prerequisite_id_caster_apply,
        effect.prerequisite_id_target_apply,
        effect.prerequisite_id_caster_persistence,
        effect.prerequisite_id_target_persistence,
        effect.prerequisite_id_target_suspend,
        ..gate
      ]
    })
  list.append(from_spells, from_effects)
}

pub fn the_clients_starting_abilities_list_each_left_out_part_by_the_rows_that_name_it_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let left = coverage_support.left_out()
  let assert Ok(unlock) = level_up_unlock.get(tables:, id: LevelUpUnlockId(26))
    as "LevelUpUnlock.26: the AMP System unlock row"
  assert unlock.level > 1
    as "LevelUpUnlock.26 offers AMPs above level 1, so a level-1 character holds none"
  let assert Ok(abilities) = starting_ability.spells(tables:)
    as "the client's tables hold the rows the walk names"
  let reached_spells = list.map(abilities, fn(spell) { spell.spell4_id.value })
  let castable =
    dict.values(spell_plan.plans(tables:))
    |> list.flat_map(fn(ability) {
      spell_plan.tree(spell: ability, started: fn(_) { True })
    })
    |> list.map(fn(spell) { spell.spell4_id.value })
  // The Proxies behind a gate that needs the cast of an AMP spell.
  let closed_proxies =
    list.filter_map(left, fn(part) {
      case part {
        starting_ability.ProxyGateClosed(..) -> Ok(part)
        starting_ability.RunnerColumnsOnly(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.ProcLeftOut(..)
        | starting_ability.InnateSlotClosed(..) -> Error(Nil)
      }
    })
  assert closed_proxies != []
    as "the client's level-1 trees hold Proxies behind a gate that needs an AMP's cast"
  list.each(closed_proxies, fn(part) {
    let assert starting_ability.ProxyGateClosed(
      proxy_effect_id:,
      parent:,
      child:,
      gate:,
      why:,
      spells:,
      effects:,
    ) = part
    let label = "Proxy " <> int.to_string(proxy_effect_id)
    let assert Ok(proxy) =
      spell4_effects.get(tables:, id: Spell4EffectsId(proxy_effect_id))
      as { label <> " is a Spell4Effects row" }
    assert proxy.effect_type == 26 && proxy.spell_id == parent
      as { label <> " is a type 26 row of Spell4 " <> int.to_string(parent) }
    assert child
      == case proxy.data_bits00 {
        0 -> proxy.data_bits01
        named -> named
      }
      as {
        label
        <> " starts Spell4 "
        <> int.to_string(child)
        <> ": its dataBits00, or its dataBits01 when dataBits00 is 0"
      }
    assert proxy.prerequisite_id_caster_apply == gate
      || proxy.data_bits06 == gate
      as { label <> ": the gate is a caster apply or dataBits06 column" }
    let assert level_one_gate.NeedsAmp(
      spell4_id: amp_spell,
      eldan_augmentation_id:,
      level:,
    ) = why
      as { label <> ": the gate is closed by an AMP" }
    assert list.contains(
      amp_spells_the_gate_needs(tables:, prerequisite_id: gate),
      amp_spell,
    )
      as {
        label
        <> ": the gate's condition needs a cast of Spell4 "
        <> int.to_string(amp_spell)
      }
    let assert Ok(augmentation) =
      eldan_augmentation.get(
        tables:,
        id: EldanAugmentationId(eldan_augmentation_id),
      )
      as { label <> ": the part's EldanAugmentation row" }
    assert augmentation.spell4_id_augment == amp_spell
      as { label <> ": EldanAugmentation names the AMP's spell" }
    assert level == unlock.level
      as { label <> ": the AMP is offered at LevelUpUnlock 26's level" }
    list.each(effects, fn(pair) {
      let assert Ok(effect) =
        spell4_effects.get(tables:, id: Spell4EffectsId(pair.0))
        as { label <> ": a left-out effect row is a Spell4Effects row" }
      assert effect.effect_type == pair.1
        && list.contains(spells, effect.spell_id)
        as {
          label
          <> ": effect "
          <> int.to_string(pair.0)
          <> " is a row of type "
          <> int.to_string(pair.1)
          <> " in a spell left out"
        }
    })
    assert !list.contains(castable, amp_spell)
      as {
        label
        <> ": no level-1 ability's tree, with every gate open, casts the AMP spell, so only its AMP could hold it"
      }
  })
  // The converse: every Proxy row of a reached spell with a caster gate that needs an
  // AMP's cast is listed.
  let gated_proxies =
    list.filter(spell4_effects.all(tables), fn(effect) {
      effect.effect_type == 26
      && list.contains(reached_spells, effect.spell_id)
      && {
        amp_spells_the_gate_needs(
          tables:,
          prerequisite_id: effect.prerequisite_id_caster_apply,
        )
        != []
        || amp_spells_the_gate_needs(
          tables:,
          prerequisite_id: effect.data_bits06,
        )
        != []
      }
    })
    |> list.map(fn(effect) { effect.id })
    |> list.sort(int.compare)
  assert gated_proxies != []
    as "the Proxy rows of reached spells include some whose gate needs an AMP's cast"
  assert gated_proxies
    == list.map(closed_proxies, fn(part) {
      let assert starting_ability.ProxyGateClosed(proxy_effect_id:, ..) = part
      proxy_effect_id
    })
    |> list.sort(int.compare)
    as "the Proxy rows of reached spells whose gate needs an AMP's cast are exactly the Proxies the measure leaves out"
  // The runner columns.
  let reached_rows =
    list.filter_map(reached_spells, fn(spell) {
      spell4.get(tables:, id: Spell4Id(spell))
    })
  let runner_ids =
    list.flat_map(reached_rows, fn(row) {
      [row.prerequisite_id_runner00, row.prerequisite_id_runner01]
    })
    |> list.filter(fn(prerequisite_id) {
      prerequisite_id != 0
      && result.is_ok(prerequisite_table.get(
        tables:,
        id: PrerequisiteId(prerequisite_id),
      ))
    })
  let counted_columns =
    counted_prerequisite_columns(tables:, reached: reached_rows)
  let runner_only =
    list.filter(runner_ids, fn(prerequisite_id) {
      !list.contains(counted_columns, prerequisite_id)
    })
    |> list.unique
    |> list.sort(int.compare)
  let listed_runner_pairs =
    list.filter_map(left, fn(part) {
      case part {
        starting_ability.RunnerColumnsOnly(prerequisite_id:, conditions:, ..) ->
          Ok(#(prerequisite_id, conditions))
        starting_ability.ProxyGateClosed(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.ProcLeftOut(..)
        | starting_ability.InnateSlotClosed(..) -> Error(Nil)
      }
    })
  assert listed_runner_pairs != []
    as "the client's level-1 trees name Prerequisites only a runner column holds"
  list.each(listed_runner_pairs, fn(pair) {
    let assert Ok(row) =
      prerequisite_table.get(tables:, id: PrerequisiteId(pair.0))
      as { "Prerequisite " <> int.to_string(pair.0) <> " is a row" }
    assert list.count(
        [
          row.prerequisite_type_id0,
          row.prerequisite_type_id1,
          row.prerequisite_type_id2,
        ],
        fn(type_id) { type_id != 0 },
      )
      == pair.1
      as {
        "Prerequisite "
        <> int.to_string(pair.0)
        <> " holds as many conditions as the part says"
      }
    assert list.contains(runner_ids, pair.0)
      as {
        "Prerequisite "
        <> int.to_string(pair.0)
        <> " is named by a runner column of a reached spell"
      }
  })
  assert list.sort(
      list.map(listed_runner_pairs, fn(pair) { pair.0 }),
      int.compare,
    )
    == runner_only
    as "the Prerequisites a runner column of a reached spell names and no other column of a reached spell or its effects names are exactly the runner parts"
  // Each part is in the report.
  let report = coverage.left_out_report(tables:)
  list.each(left, fn(part) {
    assert string.contains(
      report,
      "- " <> starting_ability.describe_left_out(left_out: part),
    )
      as "the report holds a line for each part the measure leaves out"
  })
}

pub fn deja_vu_stays_because_its_gate_names_spells_no_amp_holds_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let assert Ok(spells) = starting_ability.spells(tables:)
  assert list.any(spells, fn(spell) { spell.spell4_id.value == 87_353 })
    as "Proxy 230116 of Mind Burst 32809 starts 87353, which holds Deja Vu 228968 (type 90), behind Prerequisite 44174: type 15 on Spell4 87333 or on 87334"
  assert list.all([87_333, 87_334], fn(spell) {
    !list.any(eldan_augmentation.all(tables), fn(amp) {
      amp.spell4_id_augment == spell
    })
  })
    as "no EldanAugmentation row names 87333 or 87334, so neither is an AMP spell with a level to wait for"
}

pub fn the_fact_file_holds_the_records_the_starting_reach_rules_cite_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let facts = coverage_support.fact_file()
  assert coverage_support.has_record(
    facts:,
    key: "Spell4.prerequisiteIdRunner00",
  )
    as "the runner columns' prompt, which the measure leaves out"
  assert coverage_support.has_record(facts:, key: "LevelUpUnlock.26")
    as "the AMP System unlock whose level the gates read"
  assert coverage_support.has_record(
    facts:,
    key: "Prerequisite.prerequisiteTypeId.1",
  )
    as "the level condition a level-1 character can fail"
  assert coverage_support.has_record(
    facts:,
    key: "EldanAugmentation.spell4IdAugment",
  )
    as "the spell an AMP adds"
}

// ---- the spend-scaled costs ----

/// The rows of each innate cost EMM id in both columns of Spell4, as the measure
/// gives them, heaviest first.
fn emm_rows() -> List(#(Int, Int)) {
  let assert Measured(types:, ..) =
    coverage_support.measured("Spend-scaled costs")
    as "the engine's source is a table"
  list.map(types, fn(line) { #(line.type_number, line.rows) })
}

pub fn the_spend_engine_counts_the_ids_of_both_columns_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  assert emm_rows()
    == [#(4, 49), #(7, 46), #(10, 3), #(5, 2), #(9, 2), #(2, 1), #(11, 1)]
    as "Spell4.innateCostEMMId0: 4 on 45 rows, 7 on 46, 5 and 9 on 2 each, 2 and 11 on 1 each; innateCostEMMId1: 4 on 6, 10 on 3, 7 on 1: 4 holds 51 and 7 47, less the three rows whose id sits beside no cost (45155 and 48782 with 4, 42075 with 7, counted as empty slots), so 49, 46 and 3 for 10"
}

// ---- the Proc effects (type 14) ----

/// The measure of the effect types over these planted type 14 rows, each as (targetFlags,
/// dataBits00, dataBits02, dataBits04): a Proc row the plan reads holds chance 1.0 (bits
/// 1065353216), a window and a kind of the holder's own events.
fn measured_proc_rows(
  rows rows: List(#(Int, Int, Int, Int)),
) -> measurement.Measurement {
  let row = fn(id, planted: #(Int, Int, Int, Int)) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(14)),
      #("flags", planted_table.Integer(2)),
      #("targetFlags", planted_table.Integer(planted.0)),
      #("dataBits00", planted_table.Integer(planted.1)),
      #("dataBits01", planted_table.Integer(1)),
      #("dataBits02", planted_table.Integer(planted.2)),
      #("dataBits03", planted_table.Integer(1)),
      #("dataBits04", planted_table.Integer(planted.3)),
      #("dataBits05", planted_table.Integer(1)),
    ])
  }
  // Spell4 1, the spell each row casts: a Proc row naming a spell with no row is left out.
  measure_planted_over(
    files: planted_files(
      rows: list.index_map(rows, fn(planted, index) { row(index + 1, planted) }),
    )
    |> planted_table.replacing(spell4.schema, [
      planted_table.row(spell4.schema, [#("ID", planted_table.Integer(1))]),
    ]),
  )
}

const proc_gap =
  "kinds other than entering and leaving stealth, leaving combat, dying, the hits, criticals, kills and heals the holder lands, and using an ability, spending or changing the class resource, receiving a heal, a deflect, a finisher critical, a taunt landed, starting to move, and the damage, critical, deflect and depleted shield a creature's blow deals the holder (the other kinds the texts name are not raised), and rows held by another unit, behind a persistence or target apply prerequisite, with a group and no filter kind, with an aim of 32 or above, with no life or naming a Spell4 the tables lack, which the plan leaves out or refuses"

pub fn a_proc_row_the_plan_skips_or_refuses_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted: 217 aimed at the caster (read), 218 aimed at the caster and the target
  // (flags 3: left out), kind 12 (read), kind 0 with chance 0.5 (read), kind 44 with a
  // window of -1 (read) and kind 217 aimed only at another unit (flags 2: left out).
  let assert Measured(types:, ..) =
    measured_proc_rows(rows: [
      #(1, 217, 1_065_353_216, 500),
      #(3, 218, 1_065_353_216, 500),
      #(1, 12, 1_065_353_216, 500),
      #(1, 0, 1_056_964_608, 1000),
      #(1, 44, 1_065_353_216, -1),
      #(2, 217, 1_065_353_216, 500),
    ])
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 14 })
  assert line.rows == 6
  assert line.status
    == HandledWithGap(
      reason: proc_gap,
      fact_key: "Spell4Effects.effectType.14",
      unread_rows: 2,
    )
    as "Spell4Effects.effectType.14: the first, third, fourth and fifth rows are read (kinds 217, 12, 0 with chance 0.5 and 44 with a window of -1); the second aims at the caster and the target and the last only at another unit, which the plan leaves out"
}

pub fn the_clients_3498_proc_rows_count_with_a_stated_gap_and_each_left_out_proc_part_names_its_row_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let line = coverage_support.partial_line("Spell effects", type_number: 14)
  assert line.rows == 3498
    as "table_rows -- Spell4Effects effectType=14: 3,498 rows"
  let proc_row = fn(effect_id, spell4_id, casts) {
    let assert Ok(row) =
      spell4_effects.get(tables:, id: Spell4EffectsId(effect_id))
      as "a Proc part names a Spell4Effects row of the client"
    assert row.effect_type == 14 && row.spell_id == spell4_id
      as "the part's row is a type 14 row of its spell"
    assert row.data_bits01 == casts
      as "Spell4Effects.effectType.14: the spell a Proc casts is its dataBits01"
    row
  }
  assert list.any(coverage_support.left_out(), fn(part) {
    case part {
      starting_ability.ProcLeftOut(..) | starting_ability.ProcKindNotRead(..) ->
        True
      starting_ability.RunnerColumnsOnly(..)
      | starting_ability.ProxyGateClosed(..)
      | starting_ability.InnateSlotClosed(..) -> False
    }
  })
    as "the client's level-1 trees hold Proc rows the plan leaves out"
  list.each(coverage_support.left_out(), fn(part) {
    case part {
      starting_ability.ProcLeftOut(spell4_id:, effect_id:, casts:, ..) -> {
        proc_row(effect_id, spell4_id, casts)
        Nil
      }
      starting_ability.ProcKindNotRead(spell4_id:, effect_id:, kind:, casts:) -> {
        assert proc_row(effect_id, spell4_id, casts).data_bits00 == kind
          as "Spell4Effects.effectType.14: the kind of a Proc is its dataBits00"
      }
      starting_ability.RunnerColumnsOnly(..)
      | starting_ability.ProxyGateClosed(..)
      | starting_ability.InnateSlotClosed(..) -> Nil
    }
  })
}

// ---- the lasting effects (types 17, 18, 80 and 81) and the conversions (145) ----

/// The measure of the effect types over these planted rows of one type, each as
/// (targetFlags, prerequisiteIdTargetApply).
fn measured_rows_of(
  effect_type effect_type: Int,
  rows rows: List(#(Int, Int)),
) -> measurement.Measurement {
  let row = fn(id, planted: #(Int, Int)) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(effect_type)),
      #("targetFlags", planted_table.Integer(planted.0)),
      #("prerequisiteIdTargetApply", planted_table.Integer(planted.1)),
      ..named_columns(effect_type:)
    ])
  }
  measure_planted_over(
    files: planted_files_naming(
      rows: list.index_map(rows, fn(planted, index) { row(index + 1, planted) }),
    ),
  )
}

/// The columns a type 80 or type 145 row holds beside its aim, which name a row of a table
/// the plan reads: a type 80 row names the spell group 5 (dataBits00 1, dataBits01 5), a type
/// 145 row converts property 1 into property 1 (`planted_files_naming`).
fn named_columns(
  effect_type effect_type: Int,
) -> List(#(String, planted_table.Cell)) {
  case effect_type {
    80 -> [
      #("dataBits00", planted_table.Integer(1)),
      #("dataBits01", planted_table.Integer(5)),
    ]
    145 -> [
      #("dataBits00", planted_table.Integer(1)),
      #("dataBits01", planted_table.Integer(1)),
      #("durationTime", planted_table.Integer(5000)),
    ]
    _ -> []
  }
}

/// The planted files with the spell group 5 in a Spell4GroupList row and the property 1 in a
/// UnitProperty2 row, which the rows of `named_columns` name.
fn planted_files_naming(
  rows rows: List(List(planted_table.Cell)),
) -> List(#(String, BitArray)) {
  planted_files(rows:)
  |> planted_table.replacing(spell4_group_list.schema, [
    planted_table.row(spell4_group_list.schema, [
      #("ID", planted_table.Integer(1)),
      #("spellGroupId00", planted_table.Integer(5)),
    ]),
  ])
  |> planted_table.replacing(unit_property2.schema, [
    planted_table.row(unit_property2.schema, [
      #("ID", planted_table.Integer(1)),
    ]),
  ])
}

pub fn a_lasting_row_aimed_by_other_flags_or_behind_a_target_prerequisite_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Planted per type: flags 1 (read), 6 (read), 3 (read: the caster and the primary target),
  // 7 (refused: its area bit in a spell that hits no foes, #834), 1 behind target apply
  // prerequisite 11311 (not applied) and 3 behind one (both).
  let rows = [#(1, 0), #(6, 0), #(3, 0), #(7, 0), #(1, 11_311), #(3, 11_311)]
  list.each(
    [
      #(17, lasting_gap),
      #(18, lasting_gap),
      #(80, force_remove_gap),
      #(81, signal_gap),
    ],
    fn(planted) {
      let assert Measured(types:, ..) =
        measured_rows_of(effect_type: planted.0, rows:)
        as "the engine's source is a table"
      let assert Ok(line) =
        list.find(types, fn(line) { line.type_number == planted.0 })
      assert line.rows == 6
      assert line.status
        == HandledWithGap(
          reason: planted.1,
          fact_key: "Spell4Effects.effectType." <> int.to_string(planted.0),
          unread_rows: 3,
        )
        as "Spell4Effects.targetFlags 1, 2, 3, 4 and 6 are read and 7, which holds the area, is not in a spell that hits no foes; an effect behind a target apply prerequisite is not applied: 3 of the 6 rows are not read"
    },
  )
}

pub fn a_type_80_row_with_differing_stack_counts_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // The plan reads a type 80 row's count only where dataBits03 and dataBits04 agree
  // (Spell4Effects.effectType.80): planted rows with counts 1 and 1, 0 and 0, 1 and 2.
  let row = fn(id, count_03, count_04) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(80)),
      #("targetFlags", planted_table.Integer(1)),
      #("dataBits03", planted_table.Integer(count_03)),
      #("dataBits04", planted_table.Integer(count_04)),
      ..named_columns(effect_type: 80)
    ])
  }
  let assert Measured(types:, ..) =
    measure_planted_over(
      files: planted_files_naming(rows: [
        row(1, 1, 1),
        row(2, 0, 0),
        row(3, 1, 2),
      ]),
    )
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 80 })
  assert line.status
    == HandledWithGap(
      reason: force_remove_gap,
      fact_key: "Spell4Effects.effectType.80",
      unread_rows: 1,
    )
    as "the plan refuses the row whose counts differ, so one of the three is not read"
}

pub fn a_conversion_row_aimed_only_at_another_unit_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let assert Measured(types:, ..) =
    measured_rows_of(effect_type: 145, rows: [#(1, 0), #(2, 0)])
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 145 })
  assert line.status
    == HandledWithGap(
      reason: conversion_gap,
      fact_key: "Spell4Effects.effectType.145",
      unread_rows: 1,
    )
    as "Spell4Effects.effectType.145: a row aimed at the caster is read, one aimed only at another unit is not"
}

pub fn the_clients_rows_of_types_18_81_145_17_and_80_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  list.each(
    [#(18, 531), #(81, 5262), #(145, 6), #(17, 10_790), #(80, 2294)],
    fn(pair) {
      let line =
        coverage_support.partial_line("Spell effects", type_number: pair.0)
      assert line.rows == pair.1
        as {
          "table_rows -- Spell4Effects effectType="
          <> int.to_string(pair.0)
          <> ": "
          <> int.to_string(pair.1)
          <> " rows"
        }
    },
  )
}

// ---- the disguises (type 112) ----

const disguise_gap =
  "rows with an outfit (0x905), no display, aimed at another unit, behind a target prerequisite or with no life, which the plan refuses or no go applies"

pub fn the_type_112_rows_the_plan_does_not_read_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // Spell4Effects.effectType.112: a row is read when its flags include the caster (bit 1),
  // it names no outfit (dataBits00 and dataBits08 are 0) and names a display (dataBits01 or
  // dataBits02), no target apply prerequisite stands before it, and it has a life (a
  // durationTime or flags bit 2). Planted: seven type 112 rows, of which the first two
  // are read, and one type 8 row.
  let row = fn(
    id: Int,
    flags: Int,
    columns: List(#(String, planted_table.Cell)),
  ) {
    let defaults = [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(112)),
      #("targetFlags", planted_table.Integer(flags)),
      #("dataBits02", planted_table.Integer(4807)),
      #("durationTime", planted_table.Integer(10_250)),
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
  // The displays 4807 and 119 are ItemDisplay rows of item type 346 (slot 64) and 51
  // (slot 20), as the client holds them (`spell_plan_disguise_test`).
  let rows = [
    row(1, 1, []),
    row(2, 3, [
      #("dataBits02", planted_table.Integer(0)),
      #("dataBits01", planted_table.Integer(119)),
      #("durationTime", planted_table.Integer(0)),
      #("flags", planted_table.Integer(2)),
    ]),
    row(3, 2, []),
    row(4, 1, [#("dataBits00", planted_table.Integer(5))]),
    row(5, 1, [#("dataBits02", planted_table.Integer(0))]),
    row(6, 1, [#("prerequisiteIdTargetApply", planted_table.Integer(5))]),
    row(7, 1, [#("durationTime", planted_table.Integer(0))]),
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(8)),
      #("effectType", planted_table.Integer(8)),
    ]),
  ]
  let display = fn(id, item2_type) {
    planted_table.row(item_display.schema, [
      #("ID", planted_table.Integer(id)),
      #("item2TypeId", planted_table.Integer(item2_type)),
    ])
  }
  let item_type = fn(id, slot) {
    planted_table.row(item2_type.schema, [
      #("ID", planted_table.Integer(id)),
      #("itemSlotId", planted_table.Integer(slot)),
    ])
  }
  let measured =
    measure_planted_over(
      files: planted_files(rows:)
      |> planted_table.replacing(item_display.schema, [
        display(119, 51),
        display(4807, 346),
      ])
      |> planted_table.replacing(item2_type.schema, [
        item_type(51, 20),
        item_type(346, 64),
      ])
      |> planted_table.replacing(item_slot.schema, [
        planted_table.row(item_slot.schema, [
          #("ID", planted_table.Integer(20)),
        ]),
        planted_table.row(item_slot.schema, [
          #("ID", planted_table.Integer(64)),
        ]),
      ]),
    )
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 112 })
  assert line.rows == 7
  assert line.status
    == HandledWithGap(
      reason: disguise_gap,
      fact_key: "Spell4Effects.effectType.112",
      unread_rows: 5,
    )
    as "row 3 aims only at another unit, 4 holds an outfit, 5 names no display, 6 stands behind a target prerequisite and 7 has no life: five of the seven are not read"
}

pub fn the_clients_358_disguise_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 112)
  assert line.rows == 358
    as "table_rows -- Spell4Effects effectType=112: 358 rows"
}

pub fn type_23_is_handled_with_no_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  let facts = coverage_support.fact_file()
  let declared = coverage_support.engine_named("Quest objectives")
  assert engine.handles(engine: declared, type_number: 23)
    as "type 23 is handled: a use of a unit of the objective's group counts it, once for each unit (QuestObjective.type.23)"
  assert list.find(declared.partial, fn(gap) { gap.type_number == 23 })
    == Error(Nil)
    as "no gap is open for type 23: each unit of the set counts once"
  assert string.contains(facts, "[\"QuestObjective.type.23\"]")
    as "the fact the type rests on is a record the fact file holds"
}

pub fn the_despawn_type_is_counted_read_by_the_rows_the_plan_applies_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 97)
  assert line.rows == 855
    as "table_rows -- Spell4Effects effectType=97: 855 rows"
  let tables = client_tables.every_table()
  let proxy_children =
    list.filter(spell4_effects.all(client_tables.shared()), fn(row) {
      row.effect_type == 97
      && list.contains([44_132, 44_133, 44_134, 44_135], row.spell_id)
    })
  assert list.length(proxy_children) == 4
    as "table_rows -- Spell4Effects spellId=44132 shows one despawn row (101441, targetFlags 2); Creature2 20119 names the spell in an activate column and Spell4Effects 101432 (a Proxy, type 26) of Spell4 44115 starts it; spells 44133 to 44135 hold one each"
  assert effect_row.unread_by_type(tables:, effects: proxy_children)
    == dict.new()
    as "a dropped row of a Proxy child is applied by the Proxy's route, so it is read"
}

pub fn the_clients_752_unit_state_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 15)
  assert line.rows == 752
    as "table_rows -- Spell4Effects effectType=15: 752 rows"
}

pub fn the_clients_3288_type_35_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 35)
  assert line.rows == 3288
    as "table_rows -- Spell4Effects effectType=35: 3288 rows"
}

pub fn the_fixtures_type_35_rows_are_counted_by_the_plans_reading_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let delays =
    list.filter(spell4_effects.all(tables), fn(row) {
      row.effect_type == 35
      && list.contains(
        [55_296, 55_317, 55_327, 55_330, 55_635, 66_285],
        row.spell_id,
      )
    })
  assert list.sort(list.map(delays, fn(row) { row.id }), int.compare)
    == [131_926, 131_968, 131_989, 131_995, 132_758, 166_492]
    as "each of Spell4 55296, 55317, 55327, 55330, 55635 and 66285 holds one delay row: 131926, 131968, 131989, 131995, 132758 and 166492"
  assert effect_row.unread_by_type(tables:, effects: delays) == dict.new()
    as "each aims at the caster alone with a duration and a phase: the plan reads it"
  let planted =
    list.map(delays, fn(row) {
      spell4_effects.Spell4Effects(..row, target_flags: 2)
    })
  assert effect_row.unread_by_type(tables:, effects: planted)
    == dict.from_list([#(35, 6)])
    as "the same rows aimed at the target are left out by name, so not read"
}

pub fn the_fixtures_unit_state_rows_are_read_only_with_a_reading_and_a_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // The fixture holds no type 15 row, so each is a fixture delay row (a Spell4 row the
  // tables hold, with a phase) turned into a timed state aimed at the target with no
  // other column set.
  let unit_states = fn(state, duration_time) {
    list.filter(spell4_effects.all(tables), fn(row) { row.effect_type == 35 })
    |> list.map(fn(row) {
      spell4_effects.Spell4Effects(
        ..row,
        effect_type: 15,
        target_flags: 2,
        flags: 0,
        tick_time: 0,
        duration_time:,
        data_bits00: state,
        data_bits01: 0,
        data_bits02: 0,
        data_bits03: 0,
        data_bits04: 0,
        data_bits05: 0,
        data_bits06: 0,
        data_bits07: 0,
        data_bits08: 0,
        data_bits09: 0,
        prerequisite_id_caster_apply: 0,
        prerequisite_id_target_apply: 0,
        prerequisite_id_caster_persistence: 0,
        prerequisite_id_target_persistence: 0,
        prerequisite_id_target_suspend: 0,
      )
    })
  }
  let rows = unit_states(6, 1000)
  assert rows != [] as "the fixture holds rows to plant"
  assert effect_row.unread_by_type(tables:, effects: rows) == dict.new()
    as "state 6 (Invulnerable) held for a duration refuses casts, so the plan applies the row and the measure reads it"
  assert effect_row.unread_by_type(tables:, effects: unit_states(0, 1000))
    == dict.from_list([#(15, list.length(rows))])
    as "state 0 has no reading, so the row refuses nothing and is not read"
  assert effect_row.unread_by_type(tables:, effects: unit_states(6, 0))
    == dict.from_list([#(15, list.length(rows))])
    as "a row with no duration is never held, so it is not read"
}

pub fn the_planted_tables_hold_every_table_the_plan_and_the_activate_cast_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("coverage")
  // One plain type 8 row aimed at the area is read by the plan, so the measure counts it
  // handled. The measure reads the plan's sources and the activate cast's spells over the
  // planted tables first, and a table of theirs that `planted_files` leaves out ends the
  // read with "no table X in the tables".
  let assert Measured(types:, ..) =
    measure_planted(rows: [
      planted_table.row(spell4_effects.schema, [
        #("ID", planted_table.Integer(1)),
        #("effectType", planted_table.Integer(8)),
        #("targetFlags", planted_table.Integer(4)),
      ]),
    ])
    as "the planted tables load and the measure reads them"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 8 })
  assert line.rows == 1 as "the one planted row of type 8"
  assert measurement.is_handled(line.status)
    as "a type 8 row aimed at the area is read by the plan"
}
