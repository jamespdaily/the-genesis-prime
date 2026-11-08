//// The level an amount of experience is (`genesis_prime/game/level`).
//// Expected values come from these places.
//// - The client's GetLevelForExperience 0x140029820 (fact `0x140029820`): the
////   highest level is GameFormula row 145's dataint0 (50); the level is the
////   highest XpPerLevel ID from 1 to that whose minXpForLevel is at most the
////   experience, taking the records by position; an experience below the first
////   record's minXpForLevel or above the record at the highest level's gives
////   -3, which is no level.
//// - The client's XpPerLevel records (the shared load): minXpForLevel 0, 655,
////   1710, ..., 26360090 (ID 50), 2147483647 from ID 51 on.
//// - The load's requirement (`genesis_prime/table/loader/store`): a missing
////   GameFormula row 145 or a missing XpPerLevel record fails the table load.

import fixture_tables
import genesis_prime/game/level
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/int
import gleam/list
import owned_test
import planted_table.{Integer}

/// The amounts of experience and the levels the client's data gives them
/// (fact `0x140029820`: 0 to 654 is 1, 655 is 2, 1710 is 3, 26360090 and above
/// is 50).
fn levels() -> List(#(Int, Int)) {
  [
    #(0, 1),
    #(654, 1),
    #(655, 2),
    #(1709, 2),
    #(1710, 3),
    #(26_360_089, 49),
    #(26_360_090, 50),
    #(2_147_483_647, 50),
  ]
}

pub fn an_amount_of_experience_is_the_highest_level_whose_minimum_it_reaches_in_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(levels(), fn(pair) {
    let #(experience, expected) = pair
    assert level.for_experience(tables:, experience:) == Ok(expected)
      as {
        "GetLevelForExperience 0x140029820: experience "
        <> int.to_string(experience)
        <> " is level "
        <> int.to_string(expected)
      }
  })
}

pub fn an_amount_outside_the_first_and_the_highest_record_is_no_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  assert level.for_experience(tables:, experience: -1) == Error(Nil)
    as "0x140029870 jl: an amount below record 0's minXpForLevel gives -3, which is no level"
  assert level.for_experience(tables:, experience: 2_147_483_648) == Error(Nil)
    as "0x140029875 jg: an amount above the record at the highest level's minXpForLevel (2147483647) gives -3"
}

/// The client's rows without the rows of `table` with these ids.
fn without(table table: String, ids ids: List(Int)) -> fixture_tables.Rows {
  let assert Ok(rows) =
    list.try_fold(ids, fixture_tables.rows(), fn(rows, id) {
      fixture_tables.remove(rows:, table:, id:)
    })
    as "the client's table holds each of these rows"
  rows
}

/// The load of the level's two tables from these rows, with the level's
/// requirements.
fn load(
  rows rows: fixture_tables.Rows,
) -> Result(table_store.Tables, table_store.LoadError) {
  fixture_tables.edited(
    rows:,
    entries: [game_formula.entry(), xp_per_level.entry()],
    requirements: level.requirements(),
    derivations: [],
  )
}

pub fn the_highest_level_is_game_formula_row_145s_first_number_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's row 145 holds 50; it is edited to 3, so the 4 records from
  // the first to the one at level 3 are the ones taken.
  use tables <- fixture_tables.changed(table: "GameFormula", id: 145, with: [
    #("dataint0", Integer(3)),
  ])
  assert level.highest_level(tables) == Ok(3)
    as "0x14002983e: the highest level is GameFormula row 145's dataint0"
  assert level.for_experience(tables:, experience: 2860) == Ok(3)
    as "0x140029854: the records are taken from record 0 to the record at the highest level (3), so level 3 is the highest, at the record's own minXpForLevel 2860"
  assert level.for_experience(tables:, experience: 2861) == Error(Nil)
    as "0x140029875 jg: above the record at the highest level's minXpForLevel is -3"
  assert level.for_experience(tables:, experience: 1710) == Ok(3)
    as "1710 is ID 3 when the highest level is 3"
}

pub fn the_table_load_fails_when_game_formula_row_145_or_a_record_to_the_highest_level_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(_) = load(rows: fixture_tables.rows())
    as "row 145 and the records to the highest level load"
  assert load(rows: without(table: "GameFormula", ids: [145]))
    == Error(table_store.RowMissing(
      from_table: "the server's starting level",
      column: "GameFormula id",
      to_table: "GameFormula",
      id: 145,
    ))
    as "0x140029834: the highest level is read from GameFormula row 145, so a load without it fails (the client would take 1)"
  assert load(rows: without(
      table: "XpPerLevel",
      ids: int.range(from: 51, to: 202, with: [], run: fn(ids, id) {
        [id, ..ids]
      }),
    ))
    == Error(table_store.RowMissing(
      from_table: "the server's starting level",
      column: "XpPerLevel record number",
      to_table: "XpPerLevel",
      id: 51,
    ))
    as "0x14002985e: the record at the highest level (the 51st) is read, so a load with 50 records fails"
}

pub fn the_client_has_the_rows_the_level_needs_so_the_servers_table_load_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  assert list.flat_map(level.requirements(), fn(requirement) {
      requirement.missing(tables)
    })
    == []
    as "the client's GameFormula holds row 145 and XpPerLevel its 201 records; the shared tables loaded with these requirements among the server's"
}
