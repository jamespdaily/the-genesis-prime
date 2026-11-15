//// The effect measure counts an effect row as read exactly when the plan loads it, on the
//// client's tables. Each expected count is a scratch count: a Python count of the rows
//// printed by `gleam run -m genesis_prime/table_rows -- Spell4Effects effectType=N`, written
//// apart from the plan's code from the rules each row is held to (the plan's doc comments
//// and `genesis_prime/game/cast`'s gates), and the same rows for the starting abilities'
//// column, whose 215 rows are the ids the coverage walk reaches
//// (`genesis_prime/coverage/starting_ability`).

import client_tables
import coverage_support
import database_support
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, HandledWithGap, Measured,
}
import genesis_prime/table/spell4_effects
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

pub fn coverage_counts_the_crowd_control_rows_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, _) = counted(type_number: 4)
  assert rows == 7185 as "scratch count: effectType=4 holds 7,185 rows"
  assert rows - unread == 6330
    as "6,330 of 7,185 rows are read, 2,994 more than the 3,336 read before the 28 states"
  assert unread == 855
    as "scratch count over `table_rows -- Spell4Effects effectType=4`: no dataBits00 is outside 0 to 27; 618 rows hold an apply prerequisite (#787); of the rest, 9 aim by the union flags 3, 5 and 7 (#794) and 1 by 9 (#336); of the rest, 179 aimed at another unit last until removed (flags bit 2, #803) and 41 more hold a persistence or suspend prerequisite there (#787): 848; and 7 more, otherwise read, hold a phaseFlags of 0, which no phase selects (`in_phase`, rows 90868, 90869, 90870, 101384, 102242, 108117 and 113426): 855 of 7,185"
}

pub fn the_measure_counts_the_gains_the_plan_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 1)
  assert rows == 2049 as "scratch count: effectType=1 holds 2,049 rows"
  assert unread == 1367
    as "scratch count: 1,326 rows hold a targetFlags other than 1 or a dataBits00 other than 6 or 8 (`read_row`), and 41 more hold a tickTime, which the plan keeps as a `TickingGain` and the cast rule does not apply (190 rows tick, 303 tick or aim at another unit): 1,367 of 2,049. A gain behind a target apply prerequisite is read when it aims at the caster and the gate's types are decoded: 69113 (vital 8, target apply 390, one condition of type 28) is the one such row, and no caster-aimed gain of vital 6 or 8 holds a caster apply prerequisite with an undecoded type"
  assert #(starting, starting_unread) == #(11, 1)
    as "scratch count over the 196 starting rows: 11 hold type 1 and 228918, the Medic's, ticks every 2000 ms"
}

pub fn the_measure_counts_the_damage_rows_the_area_load_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, starting_unread) = counted(type_number: 8)
  assert rows == 29_445 as "scratch count: effectType=8 holds 29,445 rows"
  assert unread == 2652
    as "scratch count: 12,293 rows were not read while the formula read only the types 0, 10, 12 and 13; 8,128 of them were refused only for a parameter of type 1 to 5 or 11, which the formula now reads (`damage.unread`), and of those 109 aim other than 1, 2, 4 or 6, 377 more hold a tickTime, which the area load leaves out, and 4 more hold a phaseFlags of 0, which no phase selects (`in_phase`), so the other 7,638 are read; the 412 rows that name type 6 or 9, the caster's Weapon and Weapon DPS (#807), stay refused (a scratch script over `table_rows -- Spell4Effects effectType=8`): 4,655 of 29,445 while no periodic row was read, and 2,003 of the 2,854 rows with a tickTime are read now (`coverage_counts_the_periodic_rows_test`): 2,652 of 29,445"
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
  assert #(starting, starting_unread) == #(81, 2)
    as "scratch count over the starting rows: 72 of type 26 and the 9 Proxy rows of 76002, the alternate Spell Surge swaps 43468 for (Spell4.spell4IdMechanicAlternateSpell), and 121345 and 178429 hold a dataBits00 of 0"
}

pub fn the_measure_reads_a_row_behind_a_target_prerequisite_only_when_its_gate_is_read_for_every_kind_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert counted(type_number: 3).1 == 289
    as "scratch count: 276 rows aim only at other units behind a target apply prerequisite, which the plan refuses (#815), 3 more aim at them with a phaseFlags of 0, which no phase selects (`in_phase`: 98983, 99149 and 101212), and 10 aim at the caster only, 5 behind a target apply prerequisite of type 95 or 56, which the plan does not read (56101, 56102, 56104, 56107 and 119554; the other 9 of the 14 rows aimed at the caster behind one, the first 48817, hold types it reads and are read) and 5 with a phaseFlags of 0: 289 of 4,645 (2,553 while a row aimed at others was refused, and the 2,264 of the 2,267 that hold no target apply prerequisite are read now)"
  assert counted(type_number: 11).1 == 307
    as "scratch count over `table_rows -- Spell4Effects effectType=11` and `-- UnitProperty2`: every row aimed at the caster, the target or the area is read (targetFlags with bit 1 set 12,603: 1 12,154, 3 92, 5 339, 7 18; 2 6,025, 4 951, 6 526), except 258 of the 679 behind a target apply prerequisite (the other 421, the first 38480, hold only types the plan reads, and a row aimed past the caster none that reads a struck unit's own state; the 258 hold a type it does not read or, aimed past the caster, one that does), 6 aimed at the area with a phaseFlags of 0, which no phase selects (`in_phase`), and 45 more, aimed by a flag it reads with a phase and no target apply prerequisite, behind a caster apply prerequisite that holds a type the plan does not read (a go cannot tell whether the caster passes it; the 2 other rows with such a caster apply, 180971 and 220435, hold a target apply of an unread type and are among the 258): 309 of 20,105, less 50886 and 53038, aimed past the caster behind Prerequisite 7224, whose one condition is type 50, which a struck subject decides now (`prerequisite_struck_test`): 307 of 20,105"
  assert counted(type_number: 10).1 == 1056
    as "scratch count over `table_rows -- Spell4Effects effectType=10`: 1,623 of 3,098 rows were not read while the caster formula refused the types 1 to 6, 9 and 11 (783 aimed only at other units, 574 periodic or behind a target apply prerequisite, 136 aimed at a struck unit and 130 for a formula parameter); 168 rows name one of those types, and 63 of them are read now, while 43 aim only at other units (targetFlags without bit 1 and other than 2, 41315, 61047, 71750, 75235 and 78822 aimed at the target and the area), 37 tick, 20 sit behind a target apply prerequisite, 56242 aims at the primary target of a struck child, and 48846, 77296, 78128 and 78130 name type 6 or 9, the caster's Weapon and Weapon DPS (#807), which the caster formula still refuses: 1,560 of 3,098 while no periodic heal was read, and 494 of the 770 rows with a tickTime are read now (`coverage_counts_the_periodic_rows_test`): 1,066 of 3,098 while every row behind a target apply prerequisite was refused; of the 153 behind one, 140 hold a type the plan does not read or, aimed past the caster, one that reads a struck unit's own state, 3 are refused on another gate and 10 are read now (58547, 67780, 67781, 98066, 99381, 143023, 148244, 187322, 187371 and 226821): 1,056 of 3,098"
  assert counted(type_number: 73).1 == 34
    as "scratch count: 34 aimed at other units; 73611, behind a target apply prerequisite of a type the plan reads, is read: 34 of 522"
  assert counted(type_number: 29).1 == 257
    as "scratch count over `table_rows -- Spell4Effects effectType=29`: 281 rows were not read while the caster formula refused the types 1 to 6, 9 and 11; 36 name one of them, and 19 of those, which name only types 1 to 5 and 11, are read now (37819, 46275, 49743, 55209, 55221 to 55223, 60926, 60972, 68969, 71040, 71531, 84494, 98864, 128174, 192661, 192742, 192750 and 202474), while 7 aim only at other units (targetFlags 4: 61863, 84972 to 84976, which also name type 9, Weapon DPS, and 151682), 2 sit behind a target apply prerequisite (99097, 187349) and 8 aim at the primary target of a struck child (182593, 185789, 185921, 185929, 185948, 185952, 198533, 207993): 262 of 581 while every row behind a target apply prerequisite was refused; 7 of the 21 behind one hold only types the plan reads and are read now (99097, 121403, 121421, 121443, 121456, 121469 and 187349), and the other 14 stay refused, 2 of them on another gate: 255 of 581; 2 more, otherwise read, hold a caster apply prerequisite with a type the plan does not read (scratch count: none aims by another flag, holds a phaseFlags of 0 or a target apply): 257 of 581"
  assert counted(type_number: 118).1 == 83
    as "scratch count over `table_rows -- Spell4Effects effectType=118`: 97 that aim at the area, tick, hold a formula parameter the caster's value does not read (18) or aim at the primary target of a struck child, and 4 more behind a target apply prerequisite (179980, 179981, 179986 and 179987): 101 of 262. 20 rows name a type 1 to 6, 9 or 11, none of them 6 or 9; 9 of them are read now (91349, 91948, 92154, 94299, 95700, 100585, 100606, 117476 and 166368), while 6 aim only at other units (targetFlags 4, 112119 also behind a target apply prerequisite), 4 tick (112027, 185920, 185928, 207992) and 131652 sits behind a target apply prerequisite; that was 101 of 262 while no periodic heal was read, and 17 of the 41 rows with a tickTime are read now (`coverage_counts_the_periodic_rows_test`): 84 of 262 while every row behind a target apply prerequisite was refused; 131652, aimed at the caster behind a gate of type 71, which the plan reads, is read now, and the other 17 of the 18 behind one stay refused: 83 of 262"
}

pub fn coverage_counts_the_periodic_rows_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 8)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 8)
  assert rows - unread == 24_790 + ticking - until_removed - no_tick - 145
    as "the 24,790 rows read while no periodic row was, and the rows holding a tickTime (2,854) but those that last until removed (flags bit 2, #803) and those with no whole tick in their durationTime (`ticking.schedule_of`), counted from the table here; less the 145 periodic rows the area load refuses on its other gates (scratch count over `table_rows -- Spell4Effects effectType=8`, by `spell_area.damage_row_of`: of the 851 periodic rows not read, those that do not last until removed and hold a formula parameter the formula does not read, a phaseFlags of 0 or an aim by 10): 26,793 read"
  assert #(starting, starting_unread) == #(41, 0)
    as "the area load builds every damage row of the starting abilities' spells, the periodic ones among them: the 36 of before and the 5 of the trees Spell Surge's alternates 34719 and 76002 reach (79679, 34766, 34767, 76003 and 76004, one damage row each)"
  let #(rows, unread, _, _) = counted(type_number: 10)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 10)
  assert rows - unread == 1546 + ticking - until_removed - no_tick - 219
    as "the 1,546 rows read while no periodic heal was (the 1,538 of before and the 8 that hold no tickTime behind a target apply prerequisite the plan reads), and the rows holding a tickTime (770) but those that last until removed and those with no whole tick, counted from the table here; less the 219 periodic heals the plan refuses on the heal rule's other gates (scratch count over `table_rows -- Spell4Effects effectType=10`, by `spell_plan` heals and `damage.caster_unread`: 18 are made on a struck unit, `HealOnStruckUnit`, #570, and 201 that do not last until removed aim only at other units, #570, hold a formula parameter the caster's formula does not read or sit behind a target apply prerequisite the plan cannot check; 143023 and 226821, periodic and behind one it reads, are applied): 2,042 read"
  let #(rows, unread, _, _) = counted(type_number: 118)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 118)
  assert rows - unread == 162 + ticking - until_removed - no_tick - 12
    as "the same over `table_rows -- Spell4Effects effectType=118`: the 162 read before (the 161 of before and 131652, behind a target apply prerequisite the plan reads), and the 41 rows holding a tickTime but those that last until removed and those with no whole tick, counted here; less 12 refused on the other gates (5 made on a struck unit, #570, and 7 that do not last until removed and hold a formula parameter the caster's formula does not read or aim by 4): 178 read"
}

/// The client's rows of the type that hold a tickTime, those of them that last until
/// removed (flags bit 2) and those of the rest with no whole tick in their durationTime.
fn periodic_rows(type_number type_number: Int) -> #(Int, Int, Int) {
  let ticking =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(row) {
      row.effect_type == type_number && row.tick_time > 0
    })
  let #(until_removed, lasting) =
    list.partition(ticking, fn(row) { int.bitwise_and(row.flags, 2) != 0 })
  let no_tick =
    list.count(lasting, fn(row) { row.duration_time / row.tick_time < 1 })
  #(list.length(ticking), list.length(until_removed), no_tick)
}

pub fn the_measure_counts_a_force_remove_whose_selector_names_no_row_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert counted(type_number: 80).1 == 396
    as "scratch count over `table_rows -- Spell4Effects effectType=80`, in the order the plan checks a row: 58 aimed by a flag other than 1, 2, 4 and 6, 35 more whose dataBits00 and dataBits01 name no spell group (685 group ids in Spell4GroupList), Spell4 or Spell4Base, 220 more whose dataBits03 and dataBits04 differ, 77 more behind a target apply prerequisite that holds a type the plan does not read or, aimed past the caster, one that reads a struck unit's own state (145 of the 243 behind one are read), and 9 more, otherwise read, behind a caster apply prerequisite that holds a type the plan does not read (a go cannot tell whether the caster passes it): 399 of 2,294, less 181558 (Prerequisite 30070), 204279 (15243) and 222419 (40421), each behind a target apply whose one condition is type 50, which a struck subject decides now (`prerequisite_struck_test`): 396 of 2,294"
}

pub fn the_measure_totals_match_the_plan_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let text = checklist.render([measured()])
  assert string.contains(text, "12728 rows of the handled types not read")
    as "the sum of the types' scratch counts: 1 1,367, 3 289, 4 855, 8 2,652, 10 1,056, 11 307, 26 1,986, 29 257, 73 34, 80 396 and 118 83 (the tests above), 17 400, 81 383 and 14 2,366 (`coverage_type_test`), 18 8, 83 49, and the counts that stay as they were: 52 2, 64 35, 84 4, 112 199 and 145 0 (the existing `coverage_type_test` values)"
  assert string.contains(text, "starting abilities: 205 of 215 rows handled")
    as "scratch count over the 215 starting rows (the 196 of before and the 19 rows of the trees Spell Surge's alternates reach, all of handled types and read): 7 are not read for lack of a handled type or row (the two Proc rows the plan skips, 90 four times and 24; the Stalker's 91018, behind a target apply prerequisite the plan reads, is read) and 3 more are not read (the Warrior's 210834, which ticks on the caster, is read): Proxies 121345 and 178429 (dataBits00 0) and the Medic's ticking gain 228918"
}

pub fn the_coverage_measure_leaves_295_type_3_rows_unread_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, _) = counted(type_number: 3)
  assert rows == 4645
    as "`table_rows -- Spell4Effects effectType=3`: 4,645 rows"
  assert unread == 289
    as "the brief counted 295 (276 behind a target apply prerequisite, 10 union rows, 9 caster rows behind one); a scratch count of the rows the plan refuses gives 276 aimed at others behind a target apply prerequisite, 3 aimed at others with a phaseFlags of 0 (98983, 99149, 101212) and 10 aimed at the caster only, and no union row, since each reads its caster part"
  let assert HandledWithGap(reason:, fact_key:, ..) =
    line_of(type_number: 3).status
  assert fact_key == "Spell4Effects.effectType.3"
  assert string.contains(
      reason,
      "aimed at another unit behind a target apply prerequisite",
    )
    && string.contains(reason, "(#815)")
    as "the gap names the rows still unread and the issue that will read them"
  assert !string.contains(reason, "(#336)")
    as "the rows aimed at other units are no longer the gap"
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
