//// The ability points a level has (`genesis_prime/game/ability_points`), on the client's
//// committed rows. Expected values come from these places.
//// - `XpPerLevel.abilityPointsPerLevel`: 0 for IDs 1 to 9 and 1 for IDs 10 to 50, 41 in
////   all up to level 50 (`table_rows -- XpPerLevel`). The client never adds the column up;
////   the server's total of a level is the sum of the rows from ID 1 to the level.
//// - `opcode.0x169`: the first value is the points to spend and the second the total.
////   The server saves no tier, so every point is unspent and the two are equal until
////   tier spending exists.

import ability_points_support as support
import client_tables
import fixture_tables
import genesis_prime/game/ability_points
import gleam/list
import owned_test
import planted_table.{Integer}
import unitest

/// A level and the total of the points its rows add up to.
type Total {
  Total(level: Int, total: Int, why: String)
}

fn totals() -> List(Total) {
  [
    Total(1, 0, "ID 1 gives none"),
    Total(9, 0, "IDs 1 to 9 give none"),
    Total(10, 1, "ID 10 gives the first"),
    Total(11, 2, "ID 11 gives one more"),
    Total(50, 41, "IDs 10 to 50 give 41"),
  ]
}

/// A rise and the frames it sends: none when the totals are equal, else the new level's.
type Rise {
  Rise(from: Int, to: Int, frames: List(#(Int, Int)), why: String)
}

fn rises() -> List(Rise) {
  [
    Rise(1, 2, [], "levels 1 and 2 hold 0 and 0"),
    Rise(9, 10, [#(1, 1)], "the first point comes at 10"),
    Rise(
      8,
      11,
      [#(2, 2)],
      "a gain over several levels sends the last level's total",
    ),
    Rise(10, 11, [#(2, 2)], "one more at 11"),
    Rise(49, 50, [#(41, 41)], "one more at 50"),
    Rise(50, 50, [], "the same level holds the same total"),
  ]
}

pub fn the_points_a_level_has_are_the_sum_of_the_rows_up_to_it_and_all_are_unspent_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(totals(), fn(case_) {
    assert ability_points.total(tables:, level: case_.level) == case_.total
      as case_.why
    assert support.points_in(frames: [
        ability_points.frame(tables:, level: case_.level),
      ])
      == [#(case_.total, case_.total)]
      as "opcode.0x169: the server saves no tier, so the points to spend are the total"
  })
  list.each(rises(), fn(rise) {
    assert support.points_in(frames: ability_points.after_rise(
        tables:,
        from_level: rise.from,
        to_level: rise.to,
      ))
      == rise.frames
      as rise.why
  })
  // Rows 1 to 3 give 0, 2 and 3 points: the sum is read from the rows, not fixed.
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "XpPerLevel",
      id: 2,
      with: [#("abilityPointsPerLevel", Integer(2))],
    )
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "XpPerLevel", id: 3, with: [
      #("abilityPointsPerLevel", Integer(3)),
    ])
  use planted <- fixture_tables.on_rows(rows:, reaching: [])
  assert ability_points.total(tables: planted, level: 3) == 5
    as "0 + 2 + 3 from the planted rows"
  assert ability_points.total(tables: planted, level: 2) == 2
    as "0 + 2 from the planted rows"
}

pub fn the_clients_rows_give_41_points_by_level_50_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert list.map([10, 11, 50], fn(level) {
      ability_points.total(tables:, level:)
    })
    == [1, 2, 41]
    as "XpPerLevel.abilityPointsPerLevel on the client's own table"
}
