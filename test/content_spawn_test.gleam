//// The spawn table as the server reads it (`genesis_prime/content/spawn`): the
//// one query and the persistent term of each world. Expected values come from
//// these places.
//// - Migration 0008 (`priv/migrations/0008_spawn.sql`): a migrated database holds
////   the 27 Virtual Defense Daguns of the Novice training simulation (Creature2
////   73465, faction 1442 = Creature2.factionId, display 26578 =
////   Creature2DisplayGroupEntry 27216, no stats), in world 3460.
//// - The design of the world spawns (the Design artifact of issue 375, section 1):
////   a selection's spawns are put once, one term for each world, and read by the
////   world's id; a world with none has no term and no spawns.

import content_support
import database_support
import genesis_prime/content/spawn as content_spawn
import genesis_prime/world_map/spawn.{Selection}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_key
import owned_test
import spawn_support

/// The rows of the spawn table of a migrated database of the test's own.
fn rows_of_a_migrated_database() -> List(spawn.Row) {
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_spawn.rows(db: content_support.connect(database:))
    as "the query ran"
  rows
}

pub fn the_one_query_reads_every_row_of_a_migrated_database_the_27_daguns_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = rows_of_a_migrated_database()
  assert list.length(rows) == 27
    as "migration 0008 inserts the 27 Daguns and nothing else"
  assert list.all(rows, fn(row) {
    row.entity_type == 0
    && row.creature_id == 73_465
    && row.world_id == 3460
    && row.faction_id == 1442
    && row.base_faction_id == 1442
    && row.display_info_id == 26_578
    && row.outfit_info_id == 0
    && row.health == None
    && row.level == None
  })
    as "each is a NonPlayer Virtual Defense Dagun of world 3460 with its client faction and display, and no stats"
  assert list.map(rows, fn(row) { row.id })
    == {
      int.range(from: 1, to: 28, with: [], run: fn(ids, number) {
        [SpawnId(number), ..ids]
      })
      |> list.reverse
    }
    as "in id order, which the identity column gave from 1"
}

pub fn a_selections_worlds_are_put_once_and_read_back_by_world_test() -> Nil {
  use <- owned_test.run(5000)
  let key = owned_key.new_fixture_key()
  let beasts =
    spawn.world_spawns(
      spawns: [
        spawn_support.battle_beast(number: 1, x: 0.0),
        spawn_support.battle_beast(number: 2, x: 100.0),
      ],
      objects: [],
    )
  content_spawn.put(
    key:,
    selection: Selection(
      worlds: dict.from_list([#(3460, beasts), #(22, spawn.no_spawns())]),
      refusals: [],
      out_of_range_levels: [],
      coverage: [],
      visibility: dict.new(),
    ),
  )
  assert content_spawn.world(key:, world_id: 3460) == beasts
    as "the world's term is what was put"
  assert content_spawn.world(key:, world_id: 22) == spawn.no_spawns()
    as "a world of the World table with no spawn that starts has an empty term"
}

pub fn spawn_counts_count_rows_per_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // The `spawn` table holds one row for each spawn, with its creature_id and world_id
  // (`content/sql/load_spawns.sql`): a creature in two worlds has two rows.
  let in_world = fn(row: spawn.Row, world_id) { spawn.Row(..row, world_id:) }
  let survivor = fn(number) {
    spawn.Row(..spawn_support.beast_row(number:), creature_id: 11_070)
  }
  let other =
    spawn.Row(..spawn_support.beast_row(number: 3), creature_id: 23_568)
  assert content_spawn.counts(rows: [
      in_world(survivor(1), 22),
      in_world(survivor(2), 51),
      other,
    ])
    == dict.from_list([#(11_070, 2), #(23_568, 1)])
    as "two rows of creature 11070 in two worlds and one of 23568"
}
