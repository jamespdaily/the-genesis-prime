//// When the client draws a TelegraphDamage row of a cast
//// (`genesis_prime/game/telegraph_window`), on the client's committed rows. Expected values come
//// from these places.
//// - `TelegraphDamage.telegraphTimeStartMs`: a row appears once the cast is `telegraphTimeStartMs`
////   old and goes once it is `telegraphTimeEndMs` old (0: no end), counted from the 0x7ff;
////   displayFlags 4 shows it before the first go and 8 from the first go; a row with no end goes
////   at the first go at or after it appears when its displayFlags lacks 8, else at the cast's
////   finish; flag 0x40 or 0x100 is never drawn (`0x140542d90`).
//// - A row counts as drawn at a go equal to its end: a marked guess, since the client's order of a
////   row's end and the go is not read (`TelegraphDamage.telegraphTimeStartMs`, its gap).
//// - The rows and go times, by `table_rows -- TelegraphDamage N` and `-- SpellPhase
////   spell4IdOwner=N`: Ice Breath 55635 gos at 2,600, 3,000, 3,500 and 3,800 ms; Claw Slam 55632
////   2,900 and 3,300; 34286 2,000 to 5,500 in steps of 500; 45746 1,400, 2,600, 3,600 and
////   4,600; 47033 1,500, 2,500, 2,750 and 3,200; 39943 500, 1,500, 1,600, 1,650 and 1,700.

import fixture_tables
import genesis_prime/game/telegraph_window
import genesis_prime/table/id.{TelegraphDamageId}
import genesis_prime/table/telegraph_damage
import gleam/int
import gleam/list
import owned_test
import planted_table.{Integer}

const ice_breath = [2600, 3000, 3500, 3800]

const claw_slam = [2900, 3300]

const spell_34286 = [2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500]

const spell_45746 = [1400, 2600, 3600, 4600]

const spell_47033 = [1500, 2500, 2750, 3200]

const spell_39943 = [500, 1500, 1600, 1650, 1700]

const savage_shred = [0, 1, 200, 700, 1200, 1700, 2800]

const ground_pound = [200, 666, 1100, 1600]

const suppressing_fire = [250, 500, 750, 1000, 1250, 1500, 1750, 2000]

pub fn a_hit_row_is_drawn_at_a_go_by_its_time_window_and_display_flags_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case: the row, the spell's go times, a go, whether the client draws the row then, and why.
  [
    #(7956, ice_breath, 1, True, "0 to 3,200 ms holds go 1 at 3,000"),
    #(7956, ice_breath, 2, False, "3,200 ms is before go 2 at 3,500"),
    #(7957, ice_breath, 0, True, "500 to 3,800 ms holds go 0 at 2,600"),
    #(7957, ice_breath, 1, True, "and go 1"),
    #(7957, ice_breath, 2, True, "and go 2"),
    #(7957, ice_breath, 3, True, "go 3 at 3,800 is its end: the marked guess"),
    #(7877, claw_slam, 0, True, "no end, displayFlags 15: drawn from the start"),
    #(7877, claw_slam, 1, True, "to the finish, the last go"),
    #(
      344,
      spell_34286,
      0,
      True,
      "no end, displayFlags 4: goes at the first go, 2,000",
    ),
    #(344, spell_34286, 1, False, "gone at the second go"),
    #(
      14_534,
      spell_34286,
      0,
      True,
      "2,000 to 6,000, displayFlags 8: its start is go 0",
    ),
    #(14_534, spell_34286, 1, True, "and it runs on"),
    #(4526, spell_45746, 1, True, "1,000 to 2,600: go 1 at 2,600 is its end"),
    #(4527, spell_45746, 1, True, "2,600 to 3,600: go 1 is its start"),
    #(4527, spell_45746, 2, True, "go 2 at 3,600 is its end"),
    #(4527, spell_45746, 3, False, "4,600 is past its end"),
    #(
      5009,
      spell_47033,
      2,
      False,
      "1,500 to 2,700 ended 50 ms before go 2 at 2,750",
    ),
    #(5010, spell_47033, 2, False, "as 5009"),
    #(10_908, spell_39943, 1, False, "flag 0x40, a twin, is never drawn"),
    #(
      1061,
      savage_shred,
      0,
      True,
      "no end, displayFlags 14: bit 8 shows it from the first go, at 0",
    ),
    #(1061, savage_shred, 6, True, "and to the finish"),
    #(
      145,
      ground_pound,
      0,
      True,
      "0 to 1,800, displayFlags 14: drawn at go 0, 200",
    ),
    #(
      7108,
      suppressing_fire,
      0,
      True,
      "0 to 1,500, displayFlags 12: drawn at go 0, 250",
    ),
    #(7108, suppressing_fire, 7, False, "1,500 ms is before the pulse at 2,000"),
  ]
  |> list.each(fn(found) {
    let #(row_id, go_times_ms, go, drawn, reason) = found
    let assert Ok(row) =
      telegraph_damage.get(
        tables: fixture_tables.shared(),
        id: TelegraphDamageId(row_id),
      )
      as "the fixture holds the row"
    assert telegraph_window.drawn_at(row:, go_times_ms:, go:) == drawn
      as {
        "row "
        <> int.to_string(row_id)
        <> " at go "
        <> int.to_string(go)
        <> ": "
        <> reason
      }
  })
  // Synthetic: row 1061 (start 0, no end) with displayFlags 4 in place of 14. It appears at 0,
  // the cast's first go, and bit 4 shows a row before the first go only: it is never drawn at
  // go 0 (`0x140542d90`).
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 1061,
    with: [#("displayFlags", Integer(4))],
  )
  let assert Ok(row) =
    telegraph_damage.get(tables:, id: TelegraphDamageId(1061))
    as "the changed row is there"
  assert !telegraph_window.drawn_at(row:, go_times_ms: savage_shred, go: 0)
    as "a row with displayFlags 4 alone is never drawn at a first go at 0"
}

pub fn a_row_that_appears_from_the_first_go_without_display_flag_8_is_never_drawn_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: row 4527 (2,600 to 3,600 ms, displayFlags 14) over spell 45746's gos at 1,400,
  // 2,600, 3,600 and 4,600 ms has displayFlags 4 in place of 14. It appears at 2,600, after the
  // first go, and bit 4 shows a row before the first go only: the client never draws it
  // (`0x140542d90`, `TelegraphDamage.telegraphTimeStartMs`).
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 4527,
    with: [#("displayFlags", Integer(4))],
  )
  let assert Ok(row) =
    telegraph_damage.get(tables:, id: TelegraphDamageId(4527))
    as "the changed row is there"
  list.each([0, 1, 2, 3], fn(go) {
    assert !telegraph_window.drawn_at(row:, go_times_ms: spell_45746, go:)
      as { "go " <> int.to_string(go) <> " draws none of it" }
  })
}
