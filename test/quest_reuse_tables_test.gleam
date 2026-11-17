//// Which objectives count the same unit again, over the client's whole tables, for every
//// type that counts a use of a unit or a cast at one. Expected values come from these
//// places.
//// - `QuestObjective.type.12`, `.23`, `.11`, `.32` and `.5`: the client keeps no per-unit
////   record of any of them (`0x1405517a0` makes none a checklist), so one count for each
////   unit is the server's choice, and an objective whose creatures have fewer spawns than
////   its count would then never finish: those count the same unit again (Jim,
////   2026-11-15 for type 12; one rule for every type since).
//// - The units of each objective are the creatures it counts (`objective_units`), and
////   the spawn counts below are the play spawn table's as of 2026-11-17 (Jim's world
////   database rows, a retail source; `spawn.tsv` read for the creatures each objective
////   counts):
////
////   | Objective | Type | Count | Creature2 (spawn rows) | Supply |
////   |---|---|---|---|---|
////   | 4470 | 12 | 3 | 11070 (16) | 16 |
////   | 8093 | 12 | 3 | 23568 (1) | 1 |
////   | 16373 | 12 | 4 | 52832 (1) | 1 |
////   | 16557 | 12 | 4 | 54338 (1) | 1 |
////   | 6692 | 12 | 10 | 22429 (6) | 6 |
////   | 4813 | 32 | 6 | 12919 (23) | 23 |
////   | 8403 | 32 | 7 | 25019 (5) | 5 |
////   | 15980 | 5 | 3 | 19277 (12) | 12 |
////   | 9817 | 5 | 4 | 28453, 40156, 40157 (1 each) | 3 |
////   | 13589 | 5 | 4 | 35876 (1) | 1 |
////   | 8448 | 23 | 3 | 24683 (2), 24684 (4), 24685 (1) | 7 |
////   | 16372 | 23 | 5 | 52836 (1), 53001 (1) | 2 |
////   | 12801 | 23 | 5 | 33127 (3), 33255 (0) | 3 |
////   | 11555 | 11 | 4 | 31474 (2) | 2 |
////   | 15363 | 11 | 8 | 41884 (2) | 2 |
////   | 10488 | 11 | 5 | no reward pane: any unit counts | unlisted |
////
////   The ids and counts are `table_rows -- QuestObjective <id>...`.

import client_tables
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_units
import genesis_prime/table/quest_objective
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import owned_test
import unitest

pub fn reused_objectives_are_those_with_too_few_units_for_every_type_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let spawn_counts =
    dict.from_list([
      #(11_070, 16),
      #(23_568, 1),
      #(52_832, 1),
      #(54_338, 1),
      #(22_429, 6),
      #(12_919, 23),
      #(25_019, 5),
      #(19_277, 12),
      #(28_453, 1),
      #(40_156, 1),
      #(40_157, 1),
      #(35_876, 1),
      #(24_683, 2),
      #(24_684, 4),
      #(24_685, 1),
      #(52_836, 1),
      #(53_001, 1),
      #(33_127, 3),
      #(31_474, 2),
      #(41_884, 2),
    ])
  let reused = objective_units.reused(tables:, spawn_counts:)
  let short = [
    #(8093, "type 12, one station for a count of 3"),
    #(16_373, "type 12, one unit for a count of 4"),
    #(16_557, "type 12, one unit for a count of 4"),
    #(6692, "type 12, 6 units for a count of 10"),
    #(8403, "type 32, 5 units for a count of 7"),
    #(9817, "type 5, 3 units for a count of 4"),
    #(13_589, "type 5, 1 unit for a count of 4"),
    #(16_372, "type 23, 2 units for a count of 5"),
    #(12_801, "type 23, 3 units for a count of 5"),
    #(11_555, "type 11, 2 units for a count of 4"),
    #(15_363, "type 11, 2 units for a count of 8"),
  ]
  list.each(short, fn(objective) {
    assert set.contains(reused, objective.0)
      as { "objective " <> objective.1 <> " is reused" }
  })
  let enough = [
    #(4470, "type 12, 16 units for a count of 3"),
    #(4813, "type 32, 23 crates for a count of 6"),
    #(15_980, "type 5, 12 units for a count of 3"),
    #(8448, "type 23, 7 units for a count of 3"),
    #(10_488, "type 11 with no reward pane, which any unit counts"),
  ]
  list.each(enough, fn(objective) {
    assert !set.contains(reused, objective.0)
      as { "objective " <> objective.1 <> " counts each unit once" }
  })
}

pub fn a_type_12_objective_of_count_1_is_never_reused_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let reused = objective_units.reused(tables:, spawn_counts: dict.new())
  let single_use =
    list.filter(quest_objective.all(tables), fn(row) {
      result.is_ok(objective_kind.used_creature(objective_kind.of_row(row)))
      && row.count <= 1
    })
  assert list.length(single_use) == 1059
    as "QuestObjective has 1055 rows of type 12 with count 1 and 4 with count 0"
  assert list.all(single_use, fn(row) { !set.contains(reused, row.id) })
    as "no objective of count 1 or 0 is reused, even with no spawns, since one unit finishes it"
}

pub fn reused_unit_objectives_are_those_with_too_few_units_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  // Rows 8093, 16373, 16557 and 6692 name Creature2 23568, 52832, 54338 and 22429
  // (`table_rows -- QuestObjective 4470 8093 16373 16557 6692`); row 4470 names Creature2
  // 11070 with count 3: the type 12 rows, as the rule first read them (Jim, 2026-11-15).
  let spawn_counts =
    dict.from_list([
      #(11_070, 16),
      #(23_568, 1),
      #(52_832, 1),
      #(54_338, 1),
      #(22_429, 6),
    ])
  let reused = objective_units.reused(tables:, spawn_counts:)
  assert set.contains(reused, 8093)
    && set.contains(reused, 16_373)
    && set.contains(reused, 16_557)
    && set.contains(reused, 6692)
    as "the objectives whose creature has fewer spawns than the count are reused"
  assert !set.contains(reused, 4470)
    as "objective 4470 has 16 spawns for a count of 3, so it counts each unit once"
}
