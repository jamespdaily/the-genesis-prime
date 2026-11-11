//// The coverage measure's view of the spell effect and prerequisite types: which
//// types are handled (derived from the decode each rule's dispatch reads), which
//// are decoded and missing, and the starting abilities' column. Expected values
//// and their sources:
//// - The types the server reads: effect types 1 (VitalModifier), 8 (Damage), 17
////   (Fluff), 26 (Proxy) and 80 (SpellForceRemove), which `Spell4Effects.effectType.N`
////   and `Spell.CodeEnumSpellEffectType.damage` name, and prerequisite types 4, 15, 28,
////   37, 50, 59, 71, 73, 179, 243 (which always fails) and 250
////   (`Prerequisite.prerequisiteTypeId.N`); a type the client's condition check has no
////   case for fails in the client and in the server (`0x1404a2100`).
//// - The starting abilities' counts are the issue's measured walk of 2026-11-05 over
////   SpellLevel (level 1, no prerequisite), Spell4, Spell4Effects, Spell4Thresholds
////   and Prerequisite (18 abilities reach 65 spells, 120 effect rows and 39
////   prerequisite conditions), less what a level-1 character does not reach or the
////   server does not check, with the counts by type written out below:
////   - the runner columns (`Spell4.prerequisiteIdRunner00`, `prerequisiteIdRunner01`)
////     hold seven prerequisites no other column names: 4918, 11153, 13653, 19411,
////     20117, 24090 and 41834, 13 conditions (`table_rows -- Prerequisite ...`);
////   - five Proxies start a child behind a gate on the spell of an AMP
////     (EldanAugmentation 863, 340, 440 and 102 name Spell4 59436, 57027, 41594 and
////     59208, which LevelUpUnlock 26 offers at level 10): 208128 and 208198 of Spell4
////     38780 (Prerequisite 37037), 135961 of 32809 (23344), 200542 of 30900 (35913)
////     and 177873 of 53865 (24582). Their six spells hold six effect rows: 208199
////     (type 17), 208200 (14), 135954 (11), 210256 (26), 200468 (17) and 147971 (17).
//// - The decoded and missing types, with each reason, are the fact file's records
////   (`Spell4Effects.effectType.N`, `Prerequisite.prerequisiteTypeId.N`).

import client_tables
import coverage_support
import genesis_prime/coverage
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine.{
  type EngineDeclaration, EngineDeclaration, Listed, Missing,
}
import genesis_prime/coverage/level_one_gate
import genesis_prime/coverage/measurement.{
  type Measurement, HandledWithGap, Measured,
}
import genesis_prime/coverage/starting_ability.{MissingRow}
import genesis_prime/game/spell_plan.{Spell}
import genesis_prime/table/class
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_slot
import genesis_prime/table/loader/store
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/unit_property2
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import owned_test
import planted_table
import simplifile
import spell_tables
import unitest

/// The tables the plan's decision about an effect row reads, planted with no row beside
/// the Spell4Effects rows given, so a row that names a prerequisite, a spell, a spell group,
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

pub fn the_effect_types_the_measure_handles_are_1_3_4_7_8_11_14_17_18_26_29_52_64_73_80_81_83_84_112_118_and_145_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  assert handled_over(
      engine: coverage_support.engine_named("Spell effects"),
      types: numbers(from: 1, to: 200),
    )
    == [
      1,
      3,
      4,
      7,
      8,
      11,
      14,
      17,
      18,
      26,
      29,
      52,
      64,
      73,
      80,
      81,
      83,
      84,
      112,
      118,
      145,
    ]
    as "the server reads VitalModifier 1 (Spell4Effects.effectType.1), ForcedMove 3 for the rows aimed at the caster (Spell4Effects.effectType.3.player), CCStateSet 4 (Spell4Effects.effectType.4), Activate 7 (Spell4Effects.effectType.7, the activate spell of a creature the player right-clicked), Damage 8, UnitPropertyModifier 11 for the rows aimed at the caster or at struck units (Spell4Effects.effectType.11.change), Fluff 17 (Spell4Effects.effectType.17), Scale 18 (Spell4Effects.effectType.18), Proxy 26 (Spell4Effects.effectType.26), ShieldOverload 64 for the rows aimed at the area (Spell4Effects.effectType.64), ModifySpellCooldown 73 for the rows aimed at the caster (Spell4Effects.effectType.73) SpellForceRemove 80 (Spell4Effects.effectType.80), RavelSignal 81 (Spell4Effects.effectType.81), Stealth 83 (Spell4Effects.effectType.83), RemoveStealth 84 (Spell4Effects.effectType.84), DisguiseOutfit 112 for the rows aimed at the caster (Spell4Effects.effectType.112), UnitPropertyConversion 145 for the rows aimed at the caster (Spell4Effects.effectType.145) and Proc 14 (Spell4Effects.effectType.14) for the rows aimed at the caster, HealShields 118 (Spell4Effects.effectType.118) for the rows that reach the caster, and ModifyInterruptArmor 52 (Spell4Effects.effectType.52) and Absorption 29 (Spell4Effects.effectType.29) for the rows that reach the caster; every other type is unread"
}

pub fn the_prerequisite_types_the_measure_handles_are_the_thirty_five_read_and_those_with_no_case_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  assert handled_over(
      engine: coverage_support.engine_named("Prerequisites"),
      types: numbers(from: 1, to: 295),
    )
    == [
      1, 2, 3, 4, 6, 10, 11, 15, 17, 21, 22, 23, 26, 28, 32, 33, 34, 35, 36, 37,
      39, 43, 45, 50, 52, 57, 58, 59, 64, 68, 69, 71, 72, 73, 74, 75, 94, 108,
      109, 116, 125, 129, 132, 144, 156, 157, 158, 161, 165, 179, 181, 202, 243,
      247, 249, 250, 257, 258, 274, 282, 284,
    ]
    as "the server reads 4 (the unit's current faction, Prerequisite.prerequisiteTypeId.4), 11 (a nested prerequisite, Prerequisite.prerequisiteTypeId.11), 15, 28, 37, 50, 59 (Prerequisite.prerequisiteTypeId.50 and .59), 64 (a resource slot, Prerequisite.prerequisiteTypeId.64), 71, 73, 108 (where the second unit stands around the first, Prerequisite.prerequisiteTypeId.108), the player's own facts 1 (its level), 2 (its race), 3 (its class), 10 (its gender), 26 (its zone), 39 (that it is a player), 52 (its path) and 109 (its World), which a cast and the equip check decide alike (Prerequisite.prerequisiteTypeId.1, .2, .3, .10, .26, .39, .52 and .109), 116 (the unit's stealth, Prerequisite.prerequisiteTypeId.116), the quest log's types 6 (a quest's state, Prerequisite.prerequisiteTypeId.6), 68 (an objective done), 43 (an objective open, Prerequisite.prerequisiteTypeId.43), 22, 23 and 33 to 36 (an objective's progress, Prerequisite.prerequisiteTypeId.22) and 94 (Prerequisite.prerequisiteTypeId.94), 69 (a challenge active), 74 (a challenge unlocked) and 125 (a challenge in cooldown), which read as clear with no record (Prerequisite.prerequisiteTypeId.69, .74 and .125), 129 (under a spell of a group, Prerequisite.prerequisiteTypeId.129) 179 (the unit's difficulty, 0x14049eeb0, which the creature attack's load reads), 243 (which the client's check always fails, Prerequisite.prerequisiteTypeId.243) and 250 (the unit's base faction, Prerequisite.prerequisiteTypeId.250), and fails the 24 types the client's check has no case for as the client does (0x1404a2100: 17, 21, 32, 45, 57, 58, 72, 75, 132, 144, 156, 157, 158, 161, 165, 181, 202, 247, 249, 257, 258, 274, 282, 284)"
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
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert starting_counts(engine: coverage_support.engine_named("Spell effects"))
    == [
      #(1, 11),
      #(3, 1),
      #(4, 6),
      #(8, 36),
      #(11, 16),
      #(14, 7),
      #(17, 12),
      #(18, 1),
      #(24, 1),
      #(26, 72),
      #(29, 1),
      #(52, 1),
      #(73, 9),
      #(80, 10),
      #(81, 1),
      #(83, 2),
      #(90, 4),
      #(112, 2),
      #(118, 2),
      #(145, 1),
    ]
    as "the 114 rows of the 18 abilities' walk (26 Proxy 49, 8 damage 36, 17 8, 4 6, 73 5, 1 VitalModifier 4, 80 3, 11 1, 3 1, 90 1: Deja Vu 228968, whose gate 44174 names no AMP spell) and the 76 rows of the 20 spells the class innates reach under the same gates, counted from `table_rows -- Spell4Effects spellId=<id>` of 46867, 42908, 44926, 47866, 47860, 52371, 70599, 45000, 46297, 58586, 70369, 76766, 69450, 46073, 38784, 38783, 45057, 60724, 47273 and 47439: 1 7, 11 11, 14 7, 17 4, 18 1, 24 1, 26 23, 29 1, 52 1, 73 3, 80 6, 81 1, 83 2, 90 3, 112 2, 118 2, 145 1: 190 effect rows, and the 6 rows of the spells the Stalker's procs cast (`table_rows -- Spell4Effects spellId=60769 79932 63366`): 80 1 (147136), 11 4 (210998, 212528, 212529, 212530) and 73 1 (159134): 196 effect rows"
}

pub fn the_starting_abilities_column_holds_the_issues_prerequisite_counts_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert starting_counts(engine: coverage_support.engine_named("Prerequisites"))
    == [
      #(11, 5),
      #(15, 32),
      #(28, 3),
      #(37, 1),
      #(50, 12),
      #(59, 4),
      #(64, 4),
      #(73, 2),
      #(108, 2),
      #(109, 2),
      #(116, 5),
      #(129, 3),
      #(243, 2),
      #(250, 2),
    ]
    as "the 26 conditions of the 18 abilities' walk (15 12, 28 1, 37 1, 50 3, 59 4, 73 1, 108 2, 116 2: the 39 conditions less the runner columns' 13) and the 46 the 20 innate spells add, each prerequisite counted once however many columns name it (counted from `table_rows -- Prerequisite` of the ids their Spell4 and Spell4Effects columns name): 11 3, 15 19, 28 2 (903 is named by an ability's spell already), 50 9, 64 2, 73 1, 109 2, 116 3, 129 1, 243 2, 250 2: 72 conditions; and the 7 conditions of the rows those nest (type 11, followed once each: `table_rows -- Prerequisite 30012 30010 38897 29795 12939`: 12939 holds a 129, 30010 an 11 and a 15, 38897 an 11 and a 129, 29795 two 64): 11 2, 15 1, 64 2, 129 2, which gives 79 conditions"
}

pub fn the_starting_abilities_and_innates_reach_79_spells_with_the_gates_a_level_1_character_can_open_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let assert Ok(spells) =
    starting_ability.spells(tables: client_tables.every_table())
    as "the client's tables hold the rows the walk names"
  assert list.length(spells) == 82
    as "the three spells the Stalker passive's procs cast (60769, 79932 and 63366) are in its tree; the 18 level-1 abilities reach 65 spells with every gate open, less the six spells below the five Proxies behind AMP gates (79220, 79229, 57030, 41869 with 77116, and 60947); Deja Vu's 87353 behind a gate that names no AMP stays; the nine innate roots add 20 (Class.spell4IdInnateAbilityActive00.trees, less the ten behind closed gates)"
}

// ---- the decoded and missing types ----

pub fn each_decoded_type_not_handled_is_listed_with_its_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let missing_of = fn(name) {
    let declared = coverage_support.engine_named(name)
    list.each(declared.missing, fn(missing) {
      assert missing.reason != ""
        as {
          name <> " type " <> int.to_string(missing.type_number) <> ": a reason"
        }
      assert coverage_support.has_record(facts:, key: missing.fact_key)
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
  assert missing_of("Spell effects") == [90]
    as "the trace's effect type of the starting abilities that no rule reads: charges 90; proc 14 is read for the kinds the holder's own events make and listed as partial; forced move 3, property modifier 11 and cooldown change 73 are read for the rows aimed at the caster and listed as partial"
  assert missing_of("Spend-scaled costs") == [2, 5, 9, 10, 11]
    as "the innate cost EMM ids besides 4 and 7 that the rows hold"
  assert missing_of("Prerequisites") == []
    as "no prerequisite type of the trace is left that the server cannot decide: the quest log's types, 43 among them, are read from the checking player's log (Prerequisite.prerequisiteTypeId.43), and stealth 116 and position 108 are read"
}

pub fn a_partial_type_is_handled_and_carries_the_gap_it_states_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  "rows aimed by flags the plan refuses or behind a target prerequisite (#336), which no go applies"

const force_remove_gap =
  "rows aimed by flags the plan refuses, behind a target prerequisite (#336), with differing stack counts (dataBits03 and dataBits04) or a selector that names no spell group, Spell4 or Spell4Base, which no go applies or the plan refuses"

const signal_gap =
  "rows aimed by flags the plan refuses or behind a target prerequisite (#336), which no go applies; the script a signal stands for is not in the client"

const conversion_gap =
  "the share is added to the source's value after the type 11 changes, in start order; whether the source is its base or its total and when the share is recomputed are not read"

pub fn the_effect_types_3_11_14_17_18_29_52_64_73_80_81_83_84_112_118_and_145_are_partial_with_a_reason_and_a_fact_key_the_file_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let declared = coverage_support.engine_named("Spell effects")
  assert declared.partial
    == [
      Missing(
        type_number: 1,
        reason: "rows aimed at another unit, changing a vital other than 6 and 8, behind a target apply prerequisite or periodic (tickTime), which the plan refuses or holds and no go applies",
        fact_key: "Spell4Effects.effectType.1",
      ),
      Missing(
        type_number: 3,
        reason: "rows, or parts of rows, aimed at another unit (#336); rows behind a target apply prerequisite, which no go applies (#336)",
        fact_key: "Spell4Effects.effectType.3",
      ),
      Missing(
        type_number: 4,
        reason: "rows holding a state other than Stun and Knockdown, aimed at the caster or by a flag the plan refuses, or behind an apply prerequisite, which the plan refuses",
        fact_key: "Spell4Effects.effectType.4",
      ),
      Missing(
        type_number: 8,
        reason: "rows with a formula parameter a player's value does not read, aimed by a flag the area load refuses, or with a multiplier that is not a finite number, which the area load refuses",
        fact_key: "0x140566ad0",
      ),
      Missing(
        type_number: 11,
        reason: "rows aimed at another player, which the cast applies to creatures only (#570, under #336); rows behind a target apply prerequisite, which no go applies (#336)",
        fact_key: "Spell4Effects.effectType.11",
      ),
      Missing(
        type_number: 14,
        reason: "kinds other than entering and leaving stealth, leaving combat and dying, and rows with a chance, a filter, a gate, another unit or a delay, which the plan refuses",
        fact_key: "Spell4Effects.effectType.14",
      ),
      Missing(
        type_number: 17,
        reason: lasting_gap,
        fact_key: "Spell4Effects.effectType.17",
      ),
      Missing(
        type_number: 18,
        reason: lasting_gap,
        fact_key: "Spell4Effects.effectType.18",
      ),
      Missing(
        type_number: 26,
        reason: "rows whose dataBits00 names no spell (the plan holds no Proxy for them) or that are aimed by a flag the plan refuses",
        fact_key: "Spell4Effects.effectType.26",
      ),
      Missing(
        type_number: 29,
        reason: "rows aimed only at other units, periodic (tickTime), with no lifetime, with a formula parameter the plan refuses, whose amount is 0 for every caster (which of dataBits00 and dataBits01 is the amount when the other is 0 is not read), behind a target apply prerequisite, or aimed at the primary target of a spell a Proxy starts on each struck unit, whose pool the server does not hold",
        fact_key: "Spell4Effects.effectType.29",
      ),
      Missing(
        type_number: 52,
        reason: "rows aimed at the units a go strikes, or at the primary target of a spell started on each struck unit, whose armor the server does not hold",
        fact_key: "Spell4Effects.effectType.52",
      ),
      Missing(
        type_number: 64,
        reason: "rows aimed at the caster or its target, whose shield the server does not hold at 0",
        fact_key: "Spell4Effects.effectType.64",
      ),
      Missing(
        type_number: 73,
        reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite, which no go applies (#336)",
        fact_key: "Spell4Effects.effectType.73",
      ),
      Missing(
        type_number: 80,
        reason: force_remove_gap,
        fact_key: "Spell4Effects.effectType.80",
      ),
      Missing(
        type_number: 81,
        reason: signal_gap,
        fact_key: "Spell4Effects.effectType.81",
      ),
      Missing(
        type_number: 83,
        reason: "rows aimed at another unit, behind a target prerequisite or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
        fact_key: "Spell4Effects.effectType.83",
      ),
      Missing(
        type_number: 84,
        reason: "rows aimed at another unit or behind a target prerequisite, which the plan refuses",
        fact_key: "Spell4Effects.effectType.84",
      ),
      Missing(
        type_number: 112,
        reason: disguise_gap,
        fact_key: "Spell4Effects.effectType.112",
      ),
      Missing(
        type_number: 118,
        reason: "rows aimed at another unit, periodic (tickTime), behind a target apply prerequisite or with a formula parameter the plan refuses",
        fact_key: "Spell4Effects.effectType.118",
      ),
      Missing(
        type_number: 145,
        reason: conversion_gap,
        fact_key: "Spell4Effects.effectType.145",
      ),
    ]
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.29")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.52")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.64")
  assert coverage_support.has_record(
    facts:,
    key: "Spell4Effects.effectType.118",
  )
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.3")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.11")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.14")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.17")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.18")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.73")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.80")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.81")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.83")
  assert coverage_support.has_record(facts:, key: "Spell4Effects.effectType.84")
  assert coverage_support.has_record(
    facts:,
    key: "Spell4Effects.effectType.112",
  )
  assert coverage_support.has_record(
    facts:,
    key: "Spell4Effects.effectType.145",
  )
  assert engine.handles(engine: declared, type_number: 3)
    && engine.handles(engine: declared, type_number: 11)
    && engine.handles(engine: declared, type_number: 14)
    && engine.handles(engine: declared, type_number: 52)
    && engine.handles(engine: declared, type_number: 64)
    && engine.handles(engine: declared, type_number: 118)
    && engine.handles(engine: declared, type_number: 73)
    && engine.handles(engine: declared, type_number: 83)
    && engine.handles(engine: declared, type_number: 84)
    && engine.handles(engine: declared, type_number: 112)
    && engine.handles(engine: declared, type_number: 17)
    && engine.handles(engine: declared, type_number: 52)
    && engine.handles(engine: declared, type_number: 18)
    && engine.handles(engine: declared, type_number: 80)
    && engine.handles(engine: declared, type_number: 81)
    && engine.handles(engine: declared, type_number: 145)
    as "types 3, 11, 14, 17, 18, 52, 64, 73, 80, 81, 83, 84, 112, 118 and 145 are handled, with the gap"
}

pub fn the_type_3_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  let measured =
    measure_planted(rows: [
      row(1, 3, 1),
      row(2, 3, 5),
      row(3, 3, 2),
      row(4, 3, 4),
      row(5, 3, 6),
      row(6, 8, 4),
    ])
  let assert Measured(types:, ..) = measured as "the planted table is measured"
  let assert Ok(three) = list.find(types, fn(line) { line.type_number == 3 })
  assert three.rows == 5
  assert three.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit (#336); rows behind a target apply prerequisite, which no go applies (#336)",
      fact_key: "Spell4Effects.effectType.3",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read: only the caster rows count as handled"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 3: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit (#336); rows behind a target apply prerequisite, which no go applies (#336) (Spell4Effects.effectType.3)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (50.0% of rows)")
    as "the handled rows are the type 8 row and the two type 3 rows the plan reads: 3 of 6"
  assert string.contains(text, "3 rows of the handled types not read")
}

pub fn the_type_11_rows_behind_a_target_prerequisite_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
      reason: "rows aimed at another player, which the cast applies to creatures only (#570, under #336); rows behind a target apply prerequisite, which no go applies (#336)",
      fact_key: "Spell4Effects.effectType.11",
      unread_rows: 1,
    )
    as "only the row behind the target prerequisite is not read; the rows aimed at the caster, the target and the area are"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 11: 5 rows (83.33%); handled with a gap, 1 of its 5 rows not read: rows aimed at another player, which the cast applies to creatures only (#570, under #336); rows behind a target apply prerequisite, which no go applies (#336) (Spell4Effects.effectType.11)",
  )
    as "the line lists the rows left out with the gap's reason"
  assert string.contains(text, "2 of 2 types handled (83.33% of rows)")
    as "the handled rows are the type 8 row and the four type 11 rows the plan reads: 5 of 6"
  assert string.contains(text, "1 row of the handled types not read")
}

pub fn the_type_73_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
      reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite, which no go applies (#336)",
      fact_key: "Spell4Effects.effectType.73",
      unread_rows: 3,
    )
    as "three of the five rows aim only at others and are not read"
  let text = checklist.render([measured])
  assert string.contains(
    text,
    "- [x] type 73: 5 rows (83.33%); handled with a gap, 3 of its 5 rows not read: rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite, which no go applies (#336) (Spell4Effects.effectType.73)",
  )
    as "the line lists the rows left out with the gap's reason"
}

pub fn the_clients_522_type_73_rows_count_487_handled_and_35_not_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let assert Measured(types:, ..) =
    measurement.measure(
      coverage_support.engine_named("Spell effects"),
      client_tables.every_table(),
    )
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 73 })
  assert line.rows == 522
    as "table_rows -- Spell4Effects effectType=73: 522 rows"
  assert measurement.is_handled(line.status)
  assert line.status
    == HandledWithGap(
      reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite, which no go applies (#336)",
      fact_key: "Spell4Effects.effectType.73",
      unread_rows: 35,
    )
    as "targetFlags 1 in 480 rows and 3 in 8 include the caster (488); 2 in 30 rows and 4 in 4 aim only at others (34 not handled), and one of the 488, 73611, stands behind a target apply prerequisite, which no go applies (scratch count of effectType=73): 487 handled, 35 not"
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

/// The measure of planted type 118 or 64 rows beside a type 8 row, for the line of the
/// type given, each row as (targetFlags, tickTime, parameterType00): Spell4Effects.targetFlags
/// bit 1 is the caster, 2 the primary target and 4 the area; the plan reads a type 118 row
/// that reaches the caster, is not periodic and has a formula the caster's value reads, and
/// a type 64 row aimed at the area alone.
fn measured_shield_rows(
  type_ type_: Int,
  rows rows: List(#(Int, Int, Int)),
) -> measurement.Measurement {
  let row = fn(id, type_, flags, tick, parameter) {
    planted_table.row(spell4_effects.schema, [
      #("ID", planted_table.Integer(id)),
      #("effectType", planted_table.Integer(type_)),
      #("targetFlags", planted_table.Integer(flags)),
      #("tickTime", planted_table.Integer(tick)),
      #("parameterType00", planted_table.Integer(parameter)),
      #("parameterValue00", planted_table.Float(0.3)),
    ])
  }
  measure_planted(
    rows: list.append(
      list.index_map(rows, fn(planted, index) {
        row(index + 1, type_, planted.0, planted.1, planted.2)
      }),
      [row(99, 8, 4, 0, 0)],
    ),
  )
}

pub fn the_measure_counts_ticking_and_refused_heal_shields_rows_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  // Planted: four type 118 rows, one for each case the plan leaves out or refuses and
  // one it reads: flags 4 (aimed at the area), flags 1 with a tickTime of 1000
  // (periodic), flags 1 with parameter type 18 (a passed-in value) and flags 1 with
  // parameter type 22 (target missing shield); and a type 64 pair, flags 4 and 2.
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 118, rows: [
      #(4, 0, 22),
      #(1, 1000, 16),
      #(1, 0, 18),
      #(1, 0, 22),
    ])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 118 })
  assert line.rows == 4
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit, periodic (tickTime), behind a target apply prerequisite or with a formula parameter the plan refuses",
      fact_key: "Spell4Effects.effectType.118",
      unread_rows: 3,
    )
    as "the area row is aimed at others, the periodic row is held and not applied, and the kind 18 row fails the plan's formula: three of four are not read"
  let assert Measured(types:, ..) =
    measured_shield_rows(type_: 64, rows: [#(4, 0, 0), #(2, 0, 0)])
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

pub fn the_type_83_rows_aimed_at_other_units_or_timed_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
      reason: "rows aimed at another unit, behind a target prerequisite or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
      fact_key: "Spell4Effects.effectType.83",
      unread_rows: 3,
    )
    as "two of the four rows aim only at others and the timed one is refused by the plan: three are not read"
}

pub fn the_type_84_rows_aimed_only_at_other_units_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  // Planted: two type 84 rows, flags 1 and 2, and one type 8 row. A RemoveStealth row's
  // durationTime is not a timed stealth and the plan does not refuse it.
  let assert Measured(types:, ..) =
    measured_stealth_rows(type_: 84, rows: [#(1, 5000), #(2, 0)])
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 84 })
  assert line.rows == 2
  assert line.status
    == HandledWithGap(
      reason: "rows aimed at another unit or behind a target prerequisite, which the plan refuses",
      fact_key: "Spell4Effects.effectType.84",
      unread_rows: 1,
    )
    as "one of the two rows aims only at others and is not read"
}

pub fn the_clients_74_type_83_rows_count_51_not_read_and_its_9_type_84_rows_4_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let assert Measured(types:, ..) =
    measurement.measure(
      coverage_support.engine_named("Spell effects"),
      client_tables.every_table(),
    )
    as "the engine's source is a table"
  let assert Ok(stealth) = list.find(types, fn(line) { line.type_number == 83 })
  assert stealth.rows == 74
    as "table_rows -- Spell4Effects effectType=83: 74 rows"
  assert stealth.status
    == HandledWithGap(
      reason: "rows aimed at another unit, behind a target prerequisite or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
      fact_key: "Spell4Effects.effectType.83",
      unread_rows: 51,
    )
    as "23 of the 74 rows are read: targetFlags 1 is the caster in 63 rows, 2 in 7 and 4 in 4 aim only at others (11), 38 of the caster rows hold a durationTime or delayTime, and 2 more of the untimed ones hold a target apply prerequisite (`table_rows -- Spell4Effects effectType=83`, columns targetFlags, delayTime, durationTime and prerequisiteIdTargetApply): 11 + 38 + 2 = 51"
  let assert Ok(remove) = list.find(types, fn(line) { line.type_number == 84 })
  assert remove.rows == 9 as "table_rows -- Spell4Effects effectType=84: 9 rows"
  assert remove.status
    == HandledWithGap(
      reason: "rows aimed at another unit or behind a target prerequisite, which the plan refuses",
      fact_key: "Spell4Effects.effectType.84",
      unread_rows: 4,
    )
    as "targetFlags 1 in 5 rows is the caster; 2 in 3 rows and 4 in 1 aim only at others"
}

pub fn a_type_both_handled_and_listed_missing_is_a_conflict_and_an_unused_missing_type_a_breach_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
    "| Quest objectives (#48) | 4 | 8 | 3 | 1 | 2 of 4 |",
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
    derivations: [spell_plan.derivation()],
    body:,
  )
}

pub fn a_prerequisite_a_spell_column_names_that_the_table_lacks_is_a_missing_row_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
  assert closed_by(flags: 0, conditions: [#(15, 1, 0, amp_spell)])
    == Ok(needs_amp())
    as "type 15, comparison 1: the unit is a target of a live cast of the AMP spell, which a level-1 character has not unlocked (LevelUpUnlock 26 offers AMPs at level 10)"
  assert closed_by(flags: 0, conditions: [#(50, 1, 0, amp_spell)])
    == Ok(needs_amp())
    as "type 50, comparison 1: the same under a cast of the AMP spell by the caster"
}

pub fn a_condition_that_needs_no_amp_cast_can_open_at_level_1_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
  assert level_one_gate.row_closed(
      gates: level_one_gate.gates(amps: [#(amp_spell, 863)], amp_level: 1),
      row: gate_row(flags: 0, conditions: [#(15, 1, 0, amp_spell)]),
    )
    == Error(Nil)
    as "the level comes from LevelUpUnlock row 26; at level 1 a new character holds the AMP's spell as far as the measure can tell"
}

pub fn a_level_condition_a_level_1_character_fails_cannot_open_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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

pub fn the_clients_starting_abilities_leave_out_the_runner_prerequisites_and_the_proxies_behind_amp_gates_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let assert Ok(left) =
    starting_ability.left_out(tables: client_tables.every_table())
  assert list.filter_map(left, fn(part) {
      case part {
        starting_ability.RunnerColumnsOnly(prerequisite_id:, conditions:, ..) ->
          Ok(#(prerequisite_id, conditions))
        starting_ability.ProxyGateClosed(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.InnateSlotClosed(..) -> Error(Nil)
      }
    })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    == [
      #(4918, 3),
      #(6527, 1),
      #(11_153, 1),
      #(13_653, 2),
      #(19_411, 2),
      #(24_090, 2),
      #(26_645, 3),
      #(41_834, 2),
    ]
    as "the runner columns name Prerequisite 4918, 6527 (Spell4 46073's runner, type 116), 11153, 13653, 19411, 24090, 26645 (Spell4 47273's runner, types 28, 64 and 11) and 41834 and no other column of a reached spell does: 16 conditions; 20117, which Spell4 34718 and 43468 name as a runner, is also Spell4Effects 111668's caster apply gate (Spell Surge 47273), so it is counted"
  assert list.filter_map(left, fn(part) {
      case part {
        starting_ability.ProxyGateClosed(
          proxy_effect_id:,
          child:,
          gate:,
          why:,
          ..,
        ) -> Ok(#(proxy_effect_id, child, gate, why))
        starting_ability.RunnerColumnsOnly(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.InnateSlotClosed(..) -> Error(Nil)
      }
    })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    == [
      #(
        135_961,
        57_030,
        23_344,
        level_one_gate.NeedsAmp(
          spell4_id: 57_027,
          eldan_augmentation_id: 340,
          level: 10,
        ),
      ),
      #(
        136_726,
        79_697,
        23_478,
        level_one_gate.NeedsAmp(
          spell4_id: 57_326,
          eldan_augmentation_id: 615,
          level: 10,
        ),
      ),
      #(
        137_177,
        57_443,
        23_519,
        level_one_gate.NeedsAmp(
          spell4_id: 57_442,
          eldan_augmentation_id: 512,
          level: 10,
        ),
      ),
      #(
        147_848,
        60_915,
        24_548,
        level_one_gate.NeedsAmp(
          spell4_id: 59_077,
          eldan_augmentation_id: 45,
          level: 10,
        ),
      ),
      #(
        173_872,
        60_868,
        28_773,
        level_one_gate.NeedsAmp(
          spell4_id: 59_312,
          eldan_augmentation_id: 802,
          level: 10,
        ),
      ),
      #(
        177_873,
        60_947,
        24_582,
        level_one_gate.NeedsAmp(
          spell4_id: 59_208,
          eldan_augmentation_id: 102,
          level: 10,
        ),
      ),
      #(
        200_542,
        41_869,
        35_913,
        level_one_gate.NeedsAmp(
          spell4_id: 41_594,
          eldan_augmentation_id: 440,
          level: 10,
        ),
      ),
      #(
        204_548,
        78_078,
        36_531,
        level_one_gate.NeedsAmp(
          spell4_id: 41_590,
          eldan_augmentation_id: 450,
          level: 10,
        ),
      ),
      #(
        205_537,
        78_307,
        26_149,
        level_one_gate.NeedsAmp(
          spell4_id: 56_725,
          eldan_augmentation_id: 499,
          level: 10,
        ),
      ),
      #(
        208_128,
        79_220,
        37_037,
        level_one_gate.NeedsAmp(
          spell4_id: 59_436,
          eldan_augmentation_id: 863,
          level: 10,
        ),
      ),
      #(
        208_198,
        79_229,
        37_037,
        level_one_gate.NeedsAmp(
          spell4_id: 59_436,
          eldan_augmentation_id: 863,
          level: 10,
        ),
      ),
      #(
        208_380,
        83_850,
        37_077,
        level_one_gate.NeedsAmp(
          spell4_id: 59_417,
          eldan_augmentation_id: 881,
          level: 10,
        ),
      ),
      #(
        210_822,
        79_875,
        37_438,
        level_one_gate.NeedsAmp(
          spell4_id: 59_136,
          eldan_augmentation_id: 157,
          level: 10,
        ),
      ),
      #(
        228_915,
        60_718,
        24_356,
        level_one_gate.NeedsAmp(
          spell4_id: 58_946,
          eldan_augmentation_id: 681,
          level: 10,
        ),
      ),
      #(
        228_917,
        60_796,
        24_445,
        level_one_gate.NeedsAmp(
          spell4_id: 58_914,
          eldan_augmentation_id: 650,
          level: 10,
        ),
      ),
    ]
    as "fifteen Proxies start a child behind a gate whose condition (type 50 or 15, comparison 1) names an AMP's spell, each AMP offered at level 10 by LevelUpUnlock 26: five of the 18 abilities and ten of the class innates (Spell4Effects 136726, 137177, 147848, 173872, 204548, 205537, 208380, 210822, 228915 and 228917, with the Prerequisite and EldanAugmentation rows of `table_rows`)"
  assert list.contains(
    left,
    starting_ability.ProxyGateClosed(
      proxy_effect_id: 208_198,
      parent: 38_780,
      child: 79_229,
      gate: 37_037,
      why: level_one_gate.NeedsAmp(
        spell4_id: 59_436,
        eldan_augmentation_id: 863,
        level: 10,
      ),
      spells: [79_229],
      effects: [#(208_200, 14)],
    ),
  )
    as "Proxy 208198 of Spell4 38780 starts 79229, which holds the Proc 208200 alone (Spell4Effects spellId=79229)"
  let tables = client_tables.every_table()
  let castable =
    dict.values(spell_plan.plans(tables:))
    |> list.flat_map(fn(ability) {
      spell_plan.tree(spell: ability, started: fn(_) { True })
    })
    |> list.map(fn(spell) { spell.spell4_id.value })
  assert list.all([59_436, 57_027, 41_594, 59_208], fn(amp_spell) {
    !list.contains(castable, amp_spell)
  })
    as "no level-1 ability's tree, with every gate open, casts an AMP spell a closed gate names, so only its AMP could hold it"
}

pub fn deja_vu_stays_because_its_gate_names_spells_no_amp_holds_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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

pub fn the_starting_abilities_totals_hold_184_of_196_effect_rows_and_79_of_79_conditions_handled_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let totals =
    checklist.totals(
      list.map(
        [
          coverage_support.engine_named("Spell effects"),
          coverage_support.engine_named("Prerequisites"),
        ],
        fn(declared) { measurement.measure(declared, tables) },
      ),
    )
  assert string.contains(
    totals,
    "| Spell effects (#49) | 133 | 131200 | 18 | 21 | 184 of 196 |",
  )
    as "196 effect rows are left, 12 of them not handled (the two Proc rows the plan skips, 90 x4, 118 once (the Warrior's periodic row 210834, held and not applied), 24 once, the Stalker's 91018 of type 81, behind target apply prerequisite 11311, the two Proxies 121345 and 178429 whose dataBits00 is 0, and the Medic's gain 228918, which ticks every 2000 ms (scratch count over the 196 rows the coverage walk reaches); the five other Proc rows, the Medic's row 228914, 109482 of type 18, 229304 of type 145, the Esper's type 52 row 199192 and its type 29 row 178144, aimed at the caster with a durationTime, are read, and the two ExoSuit rows of type 112, 112543 and 178142, aimed at the caster with a durationTime and a display, are read too); the whole-game columns are the walk's of 2026-11-05, with types 14, 18, 29, 52, 64, 81, 83, 84, 112, 118 and 145 handled beside the nine"
  assert string.contains(
    totals,
    "| Prerequisites (#47) | 232 | 49184 | 47209 | 38 | 79 of 79 |",
  )
    as "79 conditions are left, all handled: types 4, 243 and 250 are read beside the fourteen handled before (Prerequisite.prerequisiteTypeId.4, .243, .250), and the equip check decides 10 and 109 (Prerequisite.prerequisiteTypeId.10 and .109), so 19 types were handled before the quest log; it adds 6, 22, 23, 33 to 36, 43, 68 and 94 (Prerequisite.prerequisiteTypeId.6, .22, .43, .68 and .94), which the client's table uses, so 29 types are handled; a cast now gives its subject the player (its gender, World and zones), so 10 and 109 are read in every row, and the player's level, race, class, zone, kind and path add 1, 2, 3, 26, 39 and 52 (Prerequisite.prerequisiteTypeId.1, .2, .3, .26, .39 and .52), so 35 types are handled; the activate pick reads 125, a challenge in cooldown (Prerequisite.prerequisiteTypeId.125), so 36 types are handled; the link of a creature to an objective reads 69 and 74, a challenge active and unlocked (Prerequisite.prerequisiteTypeId.69 and .74), so 38 types are handled"
}

pub fn the_fact_file_holds_the_records_the_starting_reach_rules_cite_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
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

pub fn the_innate_cost_emm_ids_the_measure_handles_are_4_and_7_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  assert handled_over(
      engine: coverage_support.engine_named("Spend-scaled costs"),
      types: numbers(from: 1, to: 30),
    )
    == [4, 7]
    as "the server reads ids 4 and 7 as a spend of every point held (Spell4.innateCostEMMId0); every other id is an unread spend"
}

pub fn the_other_emm_ids_are_decoded_and_missing_with_the_reason_and_the_fact_key_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let declared = coverage_support.engine_named("Spend-scaled costs")
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
    measurement.measure(
      coverage_support.engine_named("Spend-scaled costs"),
      tables,
    )
    as "the engine's source is a table"
  list.map(types, fn(line) { #(line.type_number, line.rows) })
}

pub fn the_spend_engine_counts_the_ids_of_both_columns_and_the_starting_abilities_hold_4_once_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert emm_rows()
    == [#(4, 49), #(7, 46), #(10, 3), #(5, 2), #(9, 2), #(2, 1), #(11, 1)]
    as "Spell4.innateCostEMMId0: 4 on 45 rows, 7 on 46, 5 and 9 on 2 each, 2 and 11 on 1 each; innateCostEMMId1: 4 on 6, 10 on 3, 7 on 1: 4 holds 51 and 7 47, less the three rows whose id sits beside no cost (45155 and 48782 with 4, 42075 with 7, counted as empty slots), so 49, 46 and 3 for 10"
  assert starting_counts(engine: coverage_support.engine_named(
      "Spend-scaled costs",
    ))
    == [#(4, 1)]
    as "Spell4.innateCostEMMId0: of the 65 spells the 18 level-1 abilities reach only Mind Burst (32809, id 4) holds one"
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
      #("dataBits02", planted_table.Integer(planted.2)),
      #("dataBits03", planted_table.Integer(1)),
      #("dataBits04", planted_table.Integer(planted.3)),
      #("dataBits05", planted_table.Integer(1)),
    ])
  }
  measure_planted(
    rows: list.index_map(rows, fn(planted, index) { row(index + 1, planted) }),
  )
}

const proc_gap =
  "kinds other than entering and leaving stealth, leaving combat and dying, and rows with a chance, a filter, a gate, another unit or a delay, which the plan refuses"

pub fn a_proc_row_the_plan_skips_or_refuses_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  // Planted: 217 aimed at the caster (read), 218 aimed at the caster and the target
  // (flags 3: the plan refuses the unit), kind 12 (skipped: the next step), kind 0 with
  // chance 0.5 (refused), kind 44 with a window of -1 (refused) and kind 217 aimed only at
  // another unit (flags 2).
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
      unread_rows: 5,
    )
    as "Spell4Effects.effectType.14: only the first row is read; the second, fourth and fifth are refused by the plan, the third is skipped and the last aims only at another unit"
}

pub fn the_clients_3498_proc_rows_count_43_read_and_the_stalkers_5_of_its_7_reached_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let assert Measured(types:, ..) =
    measurement.measure(coverage_support.engine_named("Spell effects"), tables)
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 14 })
  assert line.rows == 3498
    as "table_rows -- Spell4Effects effectType=14: 3,498 rows"
  assert line.status
    == HandledWithGap(
      reason: proc_gap,
      fact_key: "Spell4Effects.effectType.14",
      unread_rows: 3455,
    )
    as "43 rows are read: of the 83 rows of kinds 217, 218, 44 and 0, 30 aim at another unit (targetFlags other than 1), 9 hold a dataBits04 of -1 and 1 a delayTime; every other row is of a kind not read"
  assert line.starting_abilities == 7
    as "the 7 Proc rows a level-1 character reaches (Spell4Effects.effectType.14.level_one)"
  let assert Ok(left) = starting_ability.left_out(tables:)
  assert list.filter_map(left, fn(part) {
      case part {
        starting_ability.ProcKindNotRead(..) -> Ok(part)
        starting_ability.RunnerColumnsOnly(..)
        | starting_ability.ProxyGateClosed(..)
        | starting_ability.InnateSlotClosed(..) -> Error(Nil)
      }
    })
    == [
      starting_ability.ProcKindNotRead(
        spell4_id: 52_371,
        effect_id: 123_744,
        kind: 12,
        casts: 52_370,
      ),
      starting_ability.ProcKindNotRead(
        spell4_id: 38_784,
        effect_id: 178_239,
        kind: 16,
        casts: 72_838,
      ),
    ]
    as "Spell4Effects.effectType.14.level_one: 123744 (kind 12, casts 52370) and 178239 (kind 16, casts 72838) are the two of the 7 reached rows the plan does not read, so 5 are"
  let report = coverage.left_out_report(tables:)
  assert string.contains(report, "Proc effect 123744 of Spell4 52371")
    && string.contains(report, "kind 12")
    && string.contains(report, "Spell4 52370")
    as "the report names the row, its holder, its kind and the spell it casts"
  assert string.contains(report, "Proc effect 178239 of Spell4 38784")
    && string.contains(report, "kind 16")
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
  use <- unitest.tags(["dev_tool", "coverage"])
  // Planted per type: flags 1 (read), 6 (read), 3 (the plan refuses the aim), 7 (the same),
  // 1 behind target apply prerequisite 11311 (not applied) and 3 behind one (both).
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
          unread_rows: 4,
        )
        as "Spell4Effects.targetFlags 1, 2, 4 and 6 are read and 3 and 7 are not; an effect behind a target apply prerequisite is not applied: 4 of the 6 rows are not read"
    },
  )
}

pub fn a_type_80_row_with_differing_stack_counts_is_counted_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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
  use <- unitest.tags(["dev_tool", "coverage"])
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

pub fn the_clients_rows_of_types_18_81_and_145_count_14_658_and_0_not_read_and_17_and_80_455_and_535_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let assert Measured(types:, ..) =
    measurement.measure(
      coverage_support.engine_named("Spell effects"),
      client_tables.every_table(),
    )
    as "the engine's source is a table"
  let counted = fn(type_number) {
    let assert Ok(line) =
      list.find(types, fn(line) { line.type_number == type_number })
      as "the type is in use"
    let assert HandledWithGap(unread_rows:, ..) = line.status
      as "the type is handled with a gap"
    #(line.rows, unread_rows, line.starting_abilities, line.starting_unread)
  }
  assert counted(18) == #(531, 14, 1, 0)
    as "table_rows -- Spell4Effects effectType=18: 531 rows, 5 aimed by flags 3 or 7 and 9 behind a target apply prerequisite; 109482 is the one starting row, aimed at the caster with no prerequisite"
  assert counted(81) == #(5262, 658, 1, 1)
    as "effectType=81: 5,262 rows, 84 aimed by flags other than 1, 2, 4 and 6 and 555 behind a target apply prerequisite, 5 of them both (634), and 24 more, otherwise read, with a phaseFlags of 0, which no phase selects (scratch count); 91018 is the one starting row, behind prerequisite 11311"
  assert counted(145) == #(6, 0, 1, 0)
    as "effectType=145: 6 rows, all aimed at the caster; 229304 is the one starting row"
  assert counted(17).0 == 10_790 && counted(17).1 == 455
    as "effectType=17: 10,790 rows, 375 aimed by other flags or behind a target apply prerequisite and 80 more, otherwise read, with a phaseFlags of 0, which no phase selects (scratch count)"
  assert counted(80).0 == 2294 && counted(80).1 == 535
    as "effectType=80: 2,294 rows, 503 aimed by other flags, behind a target apply prerequisite or with dataBits03 and dataBits04 differing (232 differ, 47969 the first), and 32 more whose selector names no spell group, Spell4 or Spell4Base (scratch count against the Spell4GroupList, Spell4 and Spell4Base ids, the first 59302)"
}

// ---- the disguises (type 112) ----

const disguise_gap =
  "rows with an outfit (0x905), no display, aimed at another unit, behind a target prerequisite or with no life, which the plan refuses or no go applies"

pub fn the_type_112_rows_the_plan_does_not_read_are_counted_as_not_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
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

pub fn the_clients_358_disguise_rows_count_159_read_and_the_two_exosuit_rows_among_the_starting_abilities_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let assert Measured(types:, ..) =
    measurement.measure(coverage_support.engine_named("Spell effects"), tables)
    as "the engine's source is a table"
  let assert Ok(line) = list.find(types, fn(line) { line.type_number == 112 })
  assert line.rows == 358
    as "table_rows -- Spell4Effects effectType=112: 358 rows"
  assert line.status
    == HandledWithGap(
      reason: disguise_gap,
      fact_key: "Spell4Effects.effectType.112",
      unread_rows: 199,
    )
    as "159 rows are read: of the 358, 104 aim only at other units (targetFlags 2, 4 or 6), 90 of the 254 that include the caster hold an outfit (dataBits00 or dataBits08), 2 name no display and 3 have no life (no durationTime and no flags bit 2), counted from table_rows"
  assert line.starting_abilities == 2
    as "the two ExoSuit rows 112543 and 178142 of Spell4 47860 (Spell4Effects.effectType.112)"
}

pub fn type_23_is_handled_with_no_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let assert Ok(facts) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file is in the repository"
  let declared = coverage_support.engine_named("Quest objectives")
  let assert Listed(ids:) = declared.handled
    as "the quest objective engine lists its handled types"
  assert list.contains(ids, 23)
    as "type 23 is handled: a use of a unit of the objective's group counts it, once for each unit (QuestObjective.type.23)"
  assert list.find(declared.partial, fn(gap) { gap.type_number == 23 })
    == Error(Nil)
    as "no gap is open for type 23: each unit of the set counts once"
  assert string.contains(facts, "[\"QuestObjective.type.23\"]")
    as "the fact the type rests on is a record the fact file holds"
}
