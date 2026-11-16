//// Which use-a-creature objectives (QuestObjective type 12) count the same unit again,
//// over the client's whole tables. Expected values come from these places.
//// - `QuestObjective.type.12`: `data` is a Creature2 id and `count` the uses that finish
////   it. The client keeps no per-unit record of one (`0x1405517a0` makes no type 12 a
////   checklist), so one count for each unit is the server's choice, and an objective whose
////   creature has fewer spawns than its count would then never finish: those count the
////   same unit again (Jim, 2026-11-15).
//// - Rows 8093, 16373, 16557 and 6692 name Creature2 23568, 52832, 54338 and 22429
////   (`table_rows -- QuestObjective 4470 8093 16373 16557 6692`); row 4470 names
////   Creature2 11070 with count 3.
//// - The spawn counts below are the play spawn table's as of 2026-11-15 (Jim's world
////   database rows, a retail source): Creature2 11070 has 16 spawns, 23568, 52832 and
////   54338 one each and 22429 six.

import client_tables
import genesis_prime/game/objective_kind
import genesis_prime/game/quest_log
import genesis_prime/table/quest_objective
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import owned_test
import unitest

pub fn reused_unit_objectives_are_those_with_too_few_units_test() -> Nil {
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
    ])
  let reused = quest_log.reused_unit_objectives(tables:, spawn_counts:)
  assert set.contains(reused, 8093)
    && set.contains(reused, 16_373)
    && set.contains(reused, 16_557)
    && set.contains(reused, 6692)
    as "the objectives whose creature has fewer spawns than the count are reused"
  assert !set.contains(reused, 4470)
    as "objective 4470 has 16 spawns for a count of 3, so it counts each unit once"
}

pub fn a_type_12_objective_of_count_1_is_never_reused_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let reused =
    quest_log.reused_unit_objectives(tables:, spawn_counts: dict.new())
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
