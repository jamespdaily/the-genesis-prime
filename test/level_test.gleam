//// The level an amount of experience is (`genesis_prime/game/level`).
//// Expected values come from these places.
//// - The client's GetLevelForExperience 0x140029820 (fact `0x140029820`): the
////   highest level is GameFormula row 145's dataint0 (50); the level is the
////   highest XpPerLevel ID from 1 to that whose minXpForLevel is at most the
////   experience, taking the records by position; an experience below the first
////   record's minXpForLevel or above the record at the highest level's gives
////   -3, which is no level.
//// - The client's XpPerLevel records, planted by `character_tables`
////   (`character_tables_test` compares them with the real file): minXpForLevel
////   0, 655, 1710, ..., 26360090 (ID 50), 2147483647 from ID 51 on.
//// - The load's requirement (`genesis_prime/table/loader/store`): a missing
////   GameFormula row 145 or a missing XpPerLevel record fails the table load.

import character_tables
import client_tables
import genesis_prime/game/level
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/erlang/reference
import gleam/int
import gleam/list
import owned_test
import planted_table
import unitest

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

pub fn an_amount_of_experience_is_the_highest_level_whose_minimum_it_reaches_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
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

pub fn an_amount_of_experience_is_the_highest_level_whose_minimum_it_reaches_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(levels(), fn(pair) {
    let #(experience, expected) = pair
    assert level.for_experience(tables:, experience:) == Ok(expected)
      as {
        "GetLevelForExperience 0x140029820 on the client's XpPerLevel: experience "
        <> int.to_string(experience)
        <> " is level "
        <> int.to_string(expected)
      }
  })
}

pub fn an_amount_outside_the_first_and_the_highest_record_is_no_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert level.for_experience(tables:, experience: -1) == Error(Nil)
    as "0x140029870 jl: an amount below record 0's minXpForLevel gives -3, which is no level"
  assert level.for_experience(tables:, experience: 2_147_483_648) == Error(Nil)
    as "0x140029875 jg: an amount above the record at the highest level's minXpForLevel (2147483647) gives -3"
}

/// Loads a GameFormula table of the rows with these ids, whose dataint0 is
/// `highest`, and an XpPerLevel table of these minimums, with the level's
/// requirements.
fn load(
  formula_ids formula_ids: List(Int),
  highest highest: Int,
  minimums minimums: List(Int),
) -> Result(table_store.Tables, table_store.LoadError) {
  use folder <- planted_table.in_folder([
    planted_table.file(
      game_formula.schema,
      character_tables.game_formula_rows(ids: formula_ids, highest:),
    ),
    planted_table.file(
      xp_per_level.schema,
      character_tables.xp_per_level_rows(minimums),
    ),
  ])
  table_store.load(
    under: reference.new(),
    from: folder,
    entries: [game_formula.entry(), xp_per_level.entry()],
    requirements: level.requirements(),
    derivations: [],
  )
}

pub fn the_highest_level_is_game_formula_row_145s_first_number_test() -> Nil {
  use <- owned_test.run(60_000)
  let minimums = list.take(character_tables.min_xp_for_level(), 4)
  let assert Ok(tables) = load(formula_ids: [145], highest: 3, minimums:)
    as "a GameFormula row 145 of 3 and 4 XpPerLevel records load"
  assert level.for_experience(tables:, experience: 2860) == Ok(3)
    as "0x140029854: the records are taken from record 0 to the record at the highest level (3), so level 3 is the highest, at the record's own minXpForLevel 2860"
  assert level.for_experience(tables:, experience: 2861) == Error(Nil)
    as "0x140029875 jg: above the record at the highest level's minXpForLevel is -3"
  assert level.for_experience(tables:, experience: 1710) == Ok(3)
    as "1710 is ID 3 when the highest level is 3"
  table_store.unload(tables)
}

pub fn the_table_load_fails_when_game_formula_row_145_or_a_record_to_the_highest_level_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  let all = character_tables.min_xp_for_level()
  let assert Ok(tables) = load(formula_ids: [145], highest: 50, minimums: all)
    as "row 145 and the 51 records load"
  table_store.unload(tables)
  assert load(formula_ids: [1, 144], highest: 50, minimums: all)
    == Error(table_store.RowMissing(
      from_table: "the server's starting level",
      column: "GameFormula id",
      to_table: "GameFormula",
      id: 145,
    ))
    as "0x140029834: the highest level is read from GameFormula row 145, so a load without it fails (the client would take 1)"
  assert load(formula_ids: [145], highest: 50, minimums: list.take(all, 50))
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
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert list.flat_map(level.requirements(), fn(requirement) {
      requirement.missing(tables)
    })
    == []
    as "the client's GameFormula holds row 145 and XpPerLevel its 201 records; the shared tables loaded with these requirements among the server's"
}
