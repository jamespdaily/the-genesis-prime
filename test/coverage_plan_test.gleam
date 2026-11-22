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
import genesis_prime/coverage/effect_row
import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, HandledWithGap, Measured,
}
import genesis_prime/game/activate
import genesis_prime/game/effect_row_read
import genesis_prime/game/spell_plan
import genesis_prime/table/id
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
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
  assert rows - unread == 6630 as "6,630 of 7,185 rows are read"
  assert unread == 555
    as "scratch count over `table_rows -- Spell4Effects effectType=4`, by the first gate `spell_plan.read_row` refuses a row on: no dataBits00 is outside 0 to 27; 205 aimed at another unit last until removed (flags bit 2, #803); 194 sit behind an apply prerequisite with a condition type the server has not decoded (#818); 101 aimed past the caster sit behind a target apply prerequisite whose condition reads what a struck creature holds (#569, #851); 47 hold a persistence or suspend prerequisite (#787); 1 aims by the flag 9 (#336); and 7 more, otherwise read, hold a phaseFlags of 0, which no phase selects (`in_phase`, rows 90868, 90869, 90870, 101384, 102242, 108117 and 113426): 555 of 7,185"
}

pub fn the_measure_counts_the_gains_the_plan_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 1)
  assert rows == 2049 as "scratch count: effectType=1 holds 2,049 rows"
  assert unread == 816
    as "scratch count by `spell_plan.read_row` over every row of the type (1,233 read and 93 held, a ticking gain the cast rule does not apply, the other 723 left out or refused): 816 of 2,049; the 1,367 this test held before no longer matched the plan on main either. The reasons of before: 1,326 rows hold a targetFlags other than 1 or a dataBits00 other than 6 or 8 (`read_row`), and 41 more hold a tickTime, which the plan keeps as a `TickingGain` and the cast rule does not apply (190 rows tick, 303 tick or aim at another unit): 1,367 of 2,049. A gain behind a target apply prerequisite is read when it aims at the caster and the gate's types are decoded: 69113 (vital 8, target apply 390, one condition of type 28) is the one such row, and no caster-aimed gain of vital 6 or 8 holds a caster apply prerequisite with an undecoded type"
  assert #(starting, starting_unread) == #(13, 1)
    as "scratch count over the starting rows: the periodic Proxies 121345 and 178429 start 71371 and 32822, one type 1 row each, so 13; scratch count over the 196 starting rows: 11 hold type 1 and 228918, the Medic's, ticks every 2000 ms"
}

pub fn the_measure_counts_the_damage_rows_the_area_load_refuses_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, starting_unread) = counted(type_number: 8)
  assert rows == 29_445 as "scratch count: effectType=8 holds 29,445 rows"
  assert unread == 2385
    as "count over `table_rows -- Spell4Effects effectType=8`, by the first gate that refuses a row (`spell_plan.read_row`, then the error `spell_area.damage_row_of` returns): 455 hold a formula parameter of a kind the formula does not read (the weapon types 6 and 9 and the passed-in value 18; the vital kinds 7, 8, 14 to 17, 19, 21 to 23, 25 and 26 are read, #791), 847 sit behind a target apply prerequisite the plan cannot check (#815, #818, #569, #851), 705 periodic rows last until removed (flags bit 2, #803), 115 aim by a flag the area load does not read, 15 hold a phaseFlags of 0, which no phase selects (`in_phase`), and 248 load but aim at their caster alone, which strikes nobody (#831): 2,385 of 29,445. The 993 fewer than the 3,378 before: 1,524 fewer for a formula parameter, 108 more behind a prerequisite, 175 more until removed and 248 more aimed at the caster alone (#831)"
  assert starting_unread == 0
    as "the area load builds every damage row of the starting abilities' spells"
}

pub fn the_measure_counts_a_proxy_that_names_no_spell_or_aims_elsewhere_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 26)
  assert rows == 16_929 as "scratch count: effectType=26 holds 16,929 rows"
  let tables = client_tables.shared()
  let rows_of_type =
    list.filter(spell4_effects.all(tables), fn(row) { row.effect_type == 26 })
  let names_no_spell =
    list.count(rows_of_type, fn(row) {
      row.data_bits00 == 0
      && spell4.get(tables:, id: id.Spell4Id(row.data_bits01)) == Error(Nil)
    })
  let periodic_left_out =
    list.count(rows_of_type, fn(row) {
      let named =
        row.data_bits00 != 0
        || spell4.get(tables:, id: id.Spell4Id(row.data_bits01)) != Error(Nil)
      let aimed_at_the_area = list.contains([4, 6], row.target_flags)
      let until_removed = int.bitwise_and(row.flags, 2) != 0
      named
      && row.tick_time > 0
      && { aimed_at_the_area || { until_removed && row.target_flags < 4 } }
    })
  assert names_no_spell == 107
    as "scratch count: 1,808 rows hold a dataBits00 of 0 and 1,701 of them name a Spell4 row in dataBits01 (`Spell4Effects.effectType.26.periodic`), 107 name none"
  assert unread == names_no_spell + periodic_left_out + 213 + 9
    as "the rows the plan leaves out or refuses, counted from the rows here: those that name no Spell4 row, the periodic ones aimed at the area (flags 4 and 6) or until removed (flags bit 2, aimed at the caster by 1, 2 or 3), 213 more refused for their aim (a flag with bit 8, or 3, 5 or 7 in a spell that hits no foes, `FriendlyAreaNotRead`; scratch count over `spell_plan.read_row`) and 9 held for a phaseFlags of 0, which no phase selects: 1,352 of 16,929"
  assert #(starting, starting_unread) == #(82, 0)
    as "scratch count over the starting rows: 72 of type 26 and the 9 Proxy rows of 76002, the alternate Spell Surge swaps 43468 for (Spell4.spell4IdMechanicAlternateSpell), 121345 and 178429 (read since their spell is named in dataBits01 and they tick) and the Proxy 200548 of 32822, which the periodic Proxy 178429 starts"
}

pub fn the_measure_reads_a_row_behind_a_target_prerequisite_only_when_its_gate_is_read_for_every_kind_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert counted(type_number: 3).1 == 135
    as "scratch count over `table_rows -- Spell4Effects effectType=3`, by the first gate `spell_plan.read_row` refuses a row on: 65 sit behind a target apply prerequisite with a condition type the server has not decoded (#815, #818), 62 aimed past the caster sit behind a target apply prerequisite whose condition reads what a struck creature holds (#815, #569, #851), and 8 hold a phaseFlags of 0, which no phase selects (`in_phase`: 90439, 98983, 99149, 101212, 101931, 105077, 124745 and 179492): 135 of 4,645"
  assert counted(type_number: 11).1 == 569
    as "scratch count over `table_rows -- Spell4Effects effectType=11` and `-- UnitProperty2`, by the first gate `spell_plan.read_row` refuses a row on: 224 aimed past the caster sit behind a target apply prerequisite whose condition reads what a struck creature holds (#569, #851), 69 behind an apply prerequisite with a condition type the server has not decoded (#818), 6 hold a phaseFlags of 0, which no phase selects (`in_phase`: 101147, 106027, 188388, 188389, 188390 and 188391), and 270 hold a parameter of a type other than 0 with a factor (the rows of `table_rows -- Spell4Effects effectType=11` with a parameterValue00 to 03 that is not 0.0 beside a parameterType that is not 0: by the type of the first such parameter, 18 in 219, 12 in 11, 13 in 8, 1 in 6, 3, 15, 11 and 2 in 5 each, and 6 and 4 in 3 each; by targetFlags, 1 in 224, 2 in 29, 4 in 12, 5 in 3 and 6 in 2; rows 128380 and 128381 hold a value on type 0 and are read; the plan refuses them as `ParameterNotRead`, since no rule reads a stat modifier's parameter factors into its amount): 569 of 20,105"
  assert counted(type_number: 10).1 == 1050
    as "1,035 of 3,098 and 15 more: heals in children that Proxies naming them in dataBits01 start on each struck unit, whose heal on that unit is not built (30794, 53489, 59631 and 12 more; scratch count over `spell_plan.read_row`, which now follows the name a Proxy holds in dataBits01 (`proxy_named`)). The 1,035: scratch count over `table_rows -- Spell4Effects effectType=10`: 1,623 of 3,098 rows were not read while the caster formula refused the types 1 to 6, 9 and 11 (783 aimed only at other units, 574 periodic or behind a target apply prerequisite, 136 aimed at a struck unit and 130 for a formula parameter); 168 rows name one of those types, and 63 of them are read now, while 43 aim only at other units (targetFlags without bit 1 and other than 2, 41315, 61047, 71750, 75235 and 78822 aimed at the target and the area), 37 tick, 20 sit behind a target apply prerequisite, 56242 aims at the primary target of a struck child, and 48846, 77296, 78128 and 78130 name type 6 or 9, the caster's Weapon and Weapon DPS (#807), which the caster formula still refuses: 1,560 of 3,098 while no periodic heal was read, and 494 of the 770 rows with a tickTime are read now (`coverage_counts_the_periodic_rows_test`): 1,066 of 3,098 while every row behind a target apply prerequisite was refused; of the 153 behind one, 140 hold a type the plan does not read or, aimed past the caster, one that reads a struck unit's own state, 3 are refused on another gate and 10 are read now (58547, 67780, 67781, 98066, 99381, 143023, 148244, 187322, 187371 and 226821): 1,056 of 3,098 Then the plan read the passed-in value (type 18): 21 of the 31 Heal rows holding the parameter are read now (14 with no tickTime and 7 that tick), the other 10 refused on the other gates (scratch count over `table_rows -- Spell4Effects effectType=10`): 1,035 of 3,098."
  assert counted(type_number: 73).1 == 34
    as "scratch count: 34 aimed at other units; 73611, behind a target apply prerequisite of a type the plan reads, is read: 34 of 522"
  assert counted(type_number: 29).1 == 242
    as "scratch count over `table_rows -- Spell4Effects effectType=29`: 281 rows were not read while the caster formula refused the types 1 to 6, 9 and 11; 36 name one of them, and 19 of those, which name only types 1 to 5 and 11, are read now (37819, 46275, 49743, 55209, 55221 to 55223, 60926, 60972, 68969, 71040, 71531, 84494, 98864, 128174, 192661, 192742, 192750 and 202474), while 7 aim only at other units (targetFlags 4: 61863, 84972 to 84976, which also name type 9, Weapon DPS, and 151682), 2 sit behind a target apply prerequisite (99097, 187349) and 8 aim at the primary target of a struck child (182593, 185789, 185921, 185929, 185948, 185952, 198533, 207993): 262 of 581 while every row behind a target apply prerequisite was refused; 7 of the 21 behind one hold only types the plan reads and are read now (99097, 121403, 121421, 121443, 121456, 121469 and 187349), and the other 14 stay refused, 2 of them on another gate: 255 of 581; 2 more, otherwise read, hold a caster apply prerequisite with a type the plan does not read (scratch count: none aims by another flag, holds a phaseFlags of 0 or a target apply): 257 of 581 Then the plan read the passed-in value (type 18): 15 of the 17 Absorption rows holding the parameter are read now, the other 2 refused on the other gates: 242 of 581."
  assert counted(type_number: 118).1 == 73
    as "71 and 2 more: heals in children that Proxies naming them in dataBits01 start on each struck unit (60928 and 61236), whose heal on that unit is not built; the 71: scratch count over `table_rows -- Spell4Effects effectType=118`: 97 that aim at the area, tick, hold a formula parameter the caster's value does not read (18) or aim at the primary target of a struck child, and 4 more behind a target apply prerequisite (179980, 179981, 179986 and 179987): 101 of 262. 20 rows name a type 1 to 6, 9 or 11, none of them 6 or 9; 9 of them are read now (91349, 91948, 92154, 94299, 95700, 100585, 100606, 117476 and 166368), while 6 aim only at other units (targetFlags 4, 112119 also behind a target apply prerequisite), 4 tick (112027, 185920, 185928, 207992) and 131652 sits behind a target apply prerequisite; that was 101 of 262 while no periodic heal was read, and 17 of the 41 rows with a tickTime are read now (`coverage_counts_the_periodic_rows_test`): 84 of 262 while every row behind a target apply prerequisite was refused; 131652, aimed at the caster behind a gate of type 71, which the plan reads, is read now, and the other 17 of the 18 behind one stay refused: 83 of 262 Then the plan read the passed-in value (type 18): 12 of the 13 HealShields rows holding the parameter are read now (6 with no tickTime and 6 that tick), the other refused on the other gates: 71 of 262."
}

pub fn coverage_counts_the_periodic_rows_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, starting, starting_unread) = counted(type_number: 8)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 8)
  assert rows - unread == 24_988 + ticking - until_removed - no_tick - 76
    as "the 24,988 rows read of the 26,591 that hold no tickTime (the other 1,603 are refused for a formula parameter the formula does not read, 438, an aim the area load does not read, 114, a target apply prerequisite the plan cannot check, #815, 834, a phaseFlags of 0, 10, or because they load but aim at their caster alone, 207, #831), and the rows holding a tickTime (2,854) but those that last until removed (flags bit 2, #803) and those with no whole tick in their durationTime (`ticking.schedule_of`), counted from the table here; less the 76 periodic rows the area load refuses on its other gates (count over `table_rows -- Spell4Effects effectType=8`, by `spell_plan.read_row` and `spell_area.damage_row_of`: of the periodic rows not read, those that do not last until removed and hold a formula parameter the formula does not read (17), a phaseFlags of 0 (5), or a target apply prerequisite the plan cannot check, #815 (13), and 41 that load but aim at their caster alone, #831): 27,060 read"
  assert #(starting, starting_unread) == #(41, 0)
    as "the area load builds every damage row of the starting abilities' spells, the periodic ones among them: the 36 of before and the 5 of the trees Spell Surge's alternates 34719 and 76002 reach (79679, 34766, 34767, 76003 and 76004, one damage row each)"
  let #(rows, unread, _, _) = counted(type_number: 10)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 10)
  assert rows - unread == 1560 + ticking - until_removed - no_tick - 227
    as "the 1,560 rows read while no periodic heal was (the 1,538 of before, the 8 that hold no tickTime behind a target apply prerequisite the plan reads and the 14 more that hold a type 18 parameter, which the plan reads since the passed-in value is built: 14 of the 23 such rows with no tickTime, the other 9 refused on the other gates), and the rows holding a tickTime (770) but those that last until removed and those with no whole tick, counted from the table here; less the 227 periodic heals the plan refuses on the heal rule's other gates (the 212 of before and 15 heals in children that Proxies naming them in dataBits01 start on each struck unit) (7 of the 8 that hold a type 18 parameter are read now) (scratch count over `table_rows -- Spell4Effects effectType=10`, by `spell_plan` heals and `damage.unread`: 18 are made on a struck unit, `HealOnStruckUnit`, #570, and 201 that do not last until removed aim only at other units, #570, hold a formula parameter the caster's formula does not read or sit behind a target apply prerequisite the plan cannot check; 143023 and 226821, periodic and behind one it reads, are applied): 2,063 read"
  let #(rows, unread, _, _) = counted(type_number: 118)
  let #(ticking, until_removed, no_tick) = periodic_rows(type_number: 118)
  assert rows - unread == 168 + ticking - until_removed - no_tick - 8
    as "the same over `table_rows -- Spell4Effects effectType=118`: the 168 read (the 161 of before, 131652, behind a target apply prerequisite the plan reads, and the 6 with no tickTime that hold a type 18 parameter, which the plan reads since the passed-in value is built), and the 41 rows holding a tickTime but those that last until removed and those with no whole tick, counted here; less 8 refused on the other gates (the 6 of before and 2 heals in children that Proxies naming them in dataBits01 start on each struck unit; 6 of the 7 periodic rows that hold a type 18 parameter are read now; of the 12 before, 5 made on a struck unit, #570, and 7 that do not last until removed and hold a formula parameter the caster's formula does not read or aim by 4): 190 read"
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
  assert counted(type_number: 80).1 == 375
    as "scratch count over `table_rows -- Spell4Effects effectType=80`, in the order the plan checks a row: 58 aimed by a flag other than 1, 2, 4 and 6, 35 more whose dataBits00 and dataBits01 name no spell group (685 group ids in Spell4GroupList), Spell4 or Spell4Base, 220 more whose dataBits03 and dataBits04 differ, 77 more behind a target apply prerequisite that holds a type the plan does not read or, aimed past the caster, one that reads a struck unit's own state (145 of the 243 behind one are read), and 9 more, otherwise read, behind a caster apply prerequisite that holds a type the plan does not read (a go cannot tell whether the caster passes it): 399 of 2,294, less 181558 (Prerequisite 30070), 204279 (15243) and 222419 (40421), each behind a target apply whose one condition is type 50, which a struck subject decides now (`prerequisite_struck_test`): 396 of 2,294; the 57 aimed by 3, 5 or 7 (#794): 21 are read now, 26 stay refused in a spell that hits no foes (`FriendlyAreaNotRead`, #834) and 10 on another gate (a selector that names no row, 8 rows, a Spell4 the table lacks, 30731, and 76677 behind a target apply prerequisite); the other 10 of the 31 the flags alone would free (the brief) were counted before those gates: 375 of 2,294"
}

pub fn the_measure_totals_match_the_plan_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let text = checklist.render([measured()])
  assert string.contains(text, "11574 rows of the handled types not read")
    as "the sum of the types' scratch counts: 1 816, 3 135, 4 555, 8 2,385, 10 1,050, 11 569, 26 1,352, 29 242, 73 34, 80 375 and 118 73 (the tests above), 17 221, 81 316, 14 1,490 and 18 6 (`coverage_type_test`), 76 122, 83 49, 97 588 (the despawn test above), 42 32 (the measure's count: rows aimed at the area or with no aim), 15 732 (`coverage_type_test`: 231 the plan leaves out or refuses and 501 it applies that refuse nothing), 35 134 (`coverage_type_test`: 24 aimed at another unit, 109 with no duration and 1 selected by no phase), and the counts that stay as they were: 52 2, 64 35, 84 4, 112 199 and 145 0 (the existing `coverage_type_test` values), and 95 58 (the 37 rows aimed at the primary target and the 21 at the area, targetFlags 2 and 4; `table_rows -- Spell4Effects effectType=95`)"
  assert string.contains(text, "starting abilities: 213 of 220 rows handled")
    as "the periodic Proxies 121345 and 178429 are read and start 71371 and 32822 (3 rows, 213 of 220 handled); scratch count over the 217 starting rows (the 196 of before, the 19 rows of the trees Spell Surge's alternates reach and the 2 rows of Spell4 72838, which the Proc 178239 casts since issue 828, all of handled types and read): 6 are not read for lack of a handled type or row (the Proc row 123744 the plan skips, 90 four times and 24; the Stalker's 91018, behind a target apply prerequisite the plan reads, is read) and 3 more are not read (the Warrior's 210834, which ticks on the caster, is read): Proxies 121345 and 178429 (dataBits00 0) and the Medic's ticking gain 228918"
}

pub fn the_coverage_measure_counts_the_type_3_rows_the_plan_refuses_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let #(rows, unread, _, _) = counted(type_number: 3)
  assert rows == 4645
    as "`table_rows -- Spell4Effects effectType=3`: 4,645 rows"
  assert unread == 135
    as "the rows the plan refuses, by gate: 65 behind a target apply prerequisite with a condition type the server has not decoded, 62 aimed past the caster behind one whose condition reads what a struck creature holds and 8 with a phaseFlags of 0, with no union row, since each reads its caster part"
  let assert HandledWithGap(reason:, fact_key:, ..) =
    line_of(type_number: 3).status
  assert fact_key == "Spell4Effects.effectType.3"
  assert string.contains(
      reason,
      "aimed at another unit behind a target apply prerequisite",
    )
    && !string.contains(reason, "#")
    as "the gap names the rows still unread and no issue"
  assert !string.contains(reason, "bit 8")
    as "the rows aimed at other units are no longer the gap"
}

pub fn coverage_counts_the_union_rows_as_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let effects = spell4_effects.all(client_tables.shared())
  let sources = spell_plan.sources_of(tables:)
  let place_of = effect_row_read.places(tables:, effects:)
  let union_rows =
    list.filter(effects, fn(row) {
      list.contains([3, 5, 7], row.target_flags)
      && list.contains([4, 8, 17, 18, 26, 80, 81], row.effect_type)
    })
  let read =
    list.filter(union_rows, fn(row) {
      effect_row_read.is_read(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
    })
  let friendly_area =
    list.filter(union_rows, fn(row) {
      spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
      == Error(spell_plan.FriendlyAreaNotRead(
        spell4_id: row.spell_id,
        effect_id: row.id,
        target_flags: row.target_flags,
      ))
    })
  assert by_type(read)
    == [#(4, 8), #(8, 19), #(17, 169), #(18, 2), #(26, 2), #(80, 21), #(81, 59)]
    as "scratch count, a row-by-row comparison of the plan on main (every one of these rows refused, `aim_of` read 1 to 7 as 1, 2, 4, 6 only) with this one: 280 of the 294 rows the brief counted by their flags alone are read now (274 before the vital kinds were read, #791, which 6 damage rows aimed by 3, 5 or 7 name); of the other 14, 1 damage row (type 8) fails the area load on its other gates, 10 force removes (type 80) fail theirs (a selector that names no row, a missing Spell4, a target apply prerequisite) and 3 rows (type 81) sit behind an apply prerequisite the plan cannot check (25911, 26254, 26256)"
  assert by_type(friendly_area)
    == [#(17, 84), #(18, 3), #(26, 212), #(80, 26), #(81, 21)]
    as "scratch count over the same rows, the 45 more of type 26 being the Proxies that name their spell in dataBits01, which were left out as naming no spell and are read now (`proxy_named`): 346 rows; before them 301 rows aimed by 3, 5 or 7 in a spell that hits no foes (a row of kind Damage or CrowdControl aimed by 2 to 7) are refused for their area bit (#834), the brief's 301 by type"
  let unread = effect_row.unread_by_type(tables:, effects:)
  let unread_of = fn(type_number) {
    let assert Ok(count) = dict.get(unread, type_number)
      as "the type still has rows the plan does not read"
    count
  }
  assert list.map([1, 3, 10, 11, 29, 52, 118], unread_of)
    == [816, 135, 1050, 569, 242, 2, 73]
    as "the rows unread by type 1, 3, 10, 11, 29, 52 and 118 (the counts of the tests above): the union reading moves none of them (no absorb or Interrupt Armor row aimed by flags 3 or 7 sits in a spell a Proxy starts on each struck unit, no_absorb_or_armor_row_aimed_by_flags_3_or_7_is_in_a_child_started_on_each_struck_unit_test)"
  let proxies_naming_no_spell =
    list.filter(union_rows, fn(row) {
      row.effect_type == 26
      && spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
      == Ok(spell_plan.LeftOut(why: spell_plan.ProxyNamesNoSpell))
    })
  assert list.length(proxies_naming_no_spell) == 4
    as "the Proxy rows aimed by 3, 5 or 7 whose dataBits00 names no spell were 49 (the brief's count); 45 of them name a Spell4 row in dataBits01, are read as a Proxy since then (`proxy_named`) and refused with the rows of the friendly area above (212 less 167), and 4 name none: the union reading changes which unit a row reaches, not which Proxy names a spell"
}

/// How many of the rows hold each effect type, as #(type, count) in type order.
fn by_type(rows: List(spell4_effects.Spell4Effects)) -> List(#(Int, Int)) {
  rows
  |> list.group(fn(row) { row.effect_type })
  |> dict.map_values(fn(_, group) { list.length(group) })
  |> dict.to_list
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
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
  let assert Ok(proxy) =
    list.find(declared.partial, fn(gap) { gap.type_number == 26 })
    as "type 26 is partial"
  assert string.contains(
    proxy.reason,
    "cast their spell on the area or until removed (the plan does not start it)",
  )
    as "the gap names the periodic Proxies the plan leaves out by name, the area and until removed ones"
  assert !string.contains(
    proxy.reason,
    "whose dataBits00 is 0, which name their spell",
  )
    as "a Proxy that names its spell in dataBits01 is no longer the gap: the plan starts it"
}

pub fn type_97_rows_are_each_read_left_out_or_refused_by_name_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let effects = spell4_effects.all(tables)
  let rows = list.filter(effects, fn(row) { row.effect_type == 97 })
  assert list.length(rows) == 855
    as "scratch count: effectType=97 holds 855 rows"
  let sources = spell_plan.sources_of(tables:)
  let place_of = effect_row_read.places(tables:, effects:)
  let readings =
    list.map(rows, fn(row) {
      spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
    })
  let count = fn(wanted) { list.count(readings, wanted) }
  assert count(fn(reading) {
      reading
      == Ok(spell_plan.LeftOut(why: spell_plan.DespawnAimedAtTheCasterOnly))
    })
    == 329
    as "scratch count: targetFlags 1 (the caster alone) on 329 of the 855 rows"
  assert count(fn(reading) {
      reading
      == Ok(
        spell_plan.LeftOut(why: spell_plan.DespawnDataNotRead(
          column: "dataBits00",
        )),
      )
    })
    == 13
    as "scratch count: 13 rows aimed past the caster hold a dataBits00 other than 0 (value 1 on 10, 2 on 2 and 247248 on 1; 6 of them hold a dataBits01 too, which the plan names second)"
  assert count(fn(reading) {
      reading
      == Ok(
        spell_plan.LeftOut(why: spell_plan.DespawnDataNotRead(
          column: "dataBits01",
        )),
      )
    })
    == 23
    as "scratch count: 23 rows aimed past the caster hold a dataBits01 other than 0 and a dataBits00 of 0"
  let refused =
    list.filter_map(readings, fn(reading) {
      case reading {
        Error(spell_plan.ApplyPrerequisiteNotRead(prerequisite_type:, ..)) ->
          Ok(prerequisite_type)
        Ok(_) -> Error(Nil)
        Error(error) ->
          panic as {
            "a type 97 row fails its spell's plan for another reason: "
            <> spell_plan.describe(error:)
          }
      }
    })
    |> list.sort(int.compare)
  assert refused == [12, 30, 30, 30, 30, 30, 30, 44, 44]
    as "scratch count over the 33 rows behind a target apply prerequisite (aimed past the caster, data 0): Prerequisite 681 holds a type 12 condition (1 row, 185775), 19142 a type 30 (6 rows, 128693 and 128730 to 128750) and 28978 a type 44 (2 rows, 174684 and 183268), none of which the server decodes (#818)"
  assert count(fn(reading) {
      case reading {
        Ok(spell_plan.Applied(..)) -> True
        Ok(_) -> False
        Error(spell_plan.ApplyPrerequisiteNotRead(..)) -> False
        Error(error) ->
          panic as {
            "a type 97 row fails its spell's plan for another reason: "
            <> spell_plan.describe(error:)
          }
      }
    })
    == 481
    as "scratch count: 526 rows aim past the caster, 36 hold data, 9 are refused: 481 are applied by a go (213 of them in a spell that holds an Activate row, which the activate cast drops, and 268 in other spells)"
  assert count(fn(reading) {
      case reading {
        Ok(spell_plan.Held(..))
        | Ok(spell_plan.ReadByArea)
        | Ok(spell_plan.ReadByActivation) -> True
        Ok(spell_plan.Applied(..)) | Ok(spell_plan.LeftOut(..)) -> False
        Error(..) -> False
      }
    })
    == 0
    as "no row is held, left to the area or left to the activation: no row of the type has a phaseFlags of 0 aimed past the caster"
}

pub fn type_15_rows_are_each_read_left_out_or_refused_by_name_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let effects = spell4_effects.all(tables)
  let rows = list.filter(effects, fn(row) { row.effect_type == 15 })
  assert list.length(rows) == 752
    as "scratch count: effectType=15 holds 752 rows"
  assert list.count(rows, fn(row) {
      spell4.get(tables:, id: id.Spell4Id(row.spell_id)) == Error(Nil)
    })
    == 17
    as "scratch count: 17 rows name a spell with no Spell4 row, which the measure counts by their own columns, as it counts any row"
  let sources = spell_plan.sources_of(tables:)
  let place_of = effect_row_read.places(tables:, effects:)
  let readings =
    list.map(rows, fn(row) {
      #(
        row,
        spell_plan.read_row(
          tables:,
          sources:,
          place: place_of(row.spell_id),
          effect: row,
        ),
      )
    })
  let count = fn(wanted) { list.count(readings, fn(read) { wanted(read.1) }) }
  assert count(fn(reading) {
      reading
      == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateAimedAtTheCasterOnly))
    })
    == 177
    as "scratch count: targetFlags 1 (the caster alone) on 177 of the 752 rows (172 of spells with a Spell4 row)"
  assert count(fn(reading) {
      reading == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateUntilRemoved))
    })
    == 48
    as "scratch count: 48 rows aimed past the caster hold flags bit 2 (44 of spells with a Spell4 row)"
  assert count(fn(reading) {
      reading
      == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateBehindPersistence))
    })
    == 3
    as "scratch count: 3 rows aimed past the caster, timed, hold a target persistence prerequisite (13428): rows 114394, 229948 and 230846"
  assert count(fn(reading) {
      reading
      == Ok(
        spell_plan.LeftOut(why: spell_plan.UnitStateDataNotRead(
          column: "dataBits01",
        )),
      )
    })
    == 2
    as "scratch count: 2 rows aimed past the caster, timed, with a dataBits01 that is not 0 (row 191112's state 23 among them) and no other column"
  let applied =
    list.filter_map(readings, fn(read) {
      case read.1 {
        Ok(spell_plan.Applied(..)) -> Ok({ read.0 }.data_bits00)
        Ok(spell_plan.Held(..))
        | Ok(spell_plan.ReadByArea)
        | Ok(spell_plan.ReadByActivation)
        | Ok(spell_plan.LeftOut(..))
        | Error(..) -> Error(Nil)
      }
    })
  let rest =
    list.filter(readings, fn(read) {
      case read.1 {
        Ok(spell_plan.Applied(..))
        | Ok(spell_plan.LeftOut(why: spell_plan.UnitStateAimedAtTheCasterOnly))
        | Ok(spell_plan.LeftOut(why: spell_plan.UnitStateUntilRemoved))
        | Ok(spell_plan.LeftOut(why: spell_plan.UnitStateBehindPersistence))
        | Ok(spell_plan.LeftOut(why: spell_plan.UnitStateDataNotRead(..))) ->
          False
        Ok(_) | Error(..) -> True
      }
    })
  assert list.map(rest, fn(read) { #({ read.0 }.id, read.1) })
    == [
      #(
        229_781,
        Error(spell_plan.TargetPrerequisiteReadsStruckUnit(
          spell4_id: 86_810,
          effect_id: 229_781,
          prerequisite_type: 1,
        )),
      ),
    ]
    as "every other row is read by a go or refused: row 229781 (state 6, targetFlags 2) is behind Prerequisite 4106, a type 1 condition that reads the casts a struck creature holds, which no creature holds yet (#569), so the plan refuses its spell"
  assert list.length(applied) == 521
    as "scratch count: 752 less 177, 48, 3, 2 and 1 is 521 rows a go applies"
  let by_state =
    list.group(applied, fn(state) { state })
    |> dict.to_list
    |> list.map(fn(group) { #(group.0, list.length(group.1)) })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  assert by_state
    == [
      #(0, 1),
      #(1, 498),
      #(6, 6),
      #(13, 3),
      #(14, 3),
      #(15, 3),
      #(17, 1),
      #(18, 1),
      #(22, 3),
      #(23, 2),
    ]
    as "scratch count over the applied rows' dataBits00: state 1 (Block) on 498, 6 on 6 (7 less the refused row 229781), 13 to 15 on 3 each, 17 and 18 on 1 each, 22 on 3, 23 on 2 and 0 on 1"
}

pub fn no_type_15_row_past_the_caster_sits_in_an_activated_spell_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let activated = activate.activated_spell_ids(tables:, sources:)
  assert set.size(activated) > 0
    as "the activated set holds the creature activate columns, the item use spells and the default spell"
  let held =
    list.filter(spell4_effects.all(tables), fn(row) {
      row.effect_type == 15
      && row.target_flags != 1
      && set.contains(activated, row.spell_id)
    })
  assert list.map(held, fn(row) { row.id }) == []
    as "scratch count: no UnitStateSet row aimed past the caster is in a spell a creature's activate column, an item's use or the default activate spell names, so the activate cast's drop of such a row changes no activation of the client's data"
}
