//// Facts about the client's own files that tests of the committed and planted
//// tables rely on: the labels and genders the client holds, the content tables
//// the content load reads from the committed rows, and the spawns they select
//// against the client's. Skipped where `GENESIS_NO_CLIENT=1`, as
//// every test of the real files is.

import character_tables
import client_tables
import genesis_prime/game/vendor
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/creature2
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/id.{
  CharacterCustomizationLabelId, Creature2Id, Spell4Id,
}
import genesis_prime/table/spell4
import genesis_prime/table/world
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/list
import owned_test
import rating_support
import spawn_support
import unitest

pub fn the_clients_labels_end_at_27_and_its_customization_rows_hold_genders_0_and_1_only_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  assert character_customization_label.get(
      tables: real,
      id: CharacterCustomizationLabelId(28),
    )
    == Error(Nil)
    as "the client's CharacterCustomizationLabel has no row 28, which tests use as a label with no row"
  assert list.all(character_customization.all(real), fn(row) { row.gender < 2 })
    as "the client's CharacterCustomization table has rows for genders 0 and 1 only"
}

// T3c-1 test 2
pub fn the_content_tables_are_the_content_load_of_the_committed_files_over_the_shared_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let content = character_tables.content_tables()
  // The client's Faction2 holds 1189 rows and Faction2Relationship 1964, and the
  // tests' maps run in the 7 Worlds the fixture keeps
  // (`fixture_tables_test`, against the client's own tables).
  assert list.length(faction2.all(content)) == 1189
    as "the content load read the committed Faction2 file"
  assert list.length(faction2_relationship.all(content)) == 1964
    as "the content load read the committed Faction2Relationship file"
  assert list.map(world.all(content), fn(row) { world.id(row).value })
    == [22, 51, 426, 870, 990, 1387, 3460]
    as "the content load read the committed World file: the fixture's World ids"
  assert character_tables.content_worlds()
    == [22, 51, 426, 870, 990, 1387, 3460]
    as "the worlds a test's map may run in are the fixture's World ids"
  assert list.map(creature2_outfit_info.all(content), fn(row) {
      creature2_outfit_info.id(row).value
    })
    == [7475, 7912, 8952, 8979, 9350, 9351]
    as "Creature2OutfitInfo holds the rows the committed outfit groups point to, 8952 being the one Dorian Walker's group points to"
  let shared = character_tables.shared()
  assert creature2.get(tables: content, id: Creature2Id(73_464))
    == creature2.get(tables: shared, id: Creature2Id(73_464))
    as "the shared load's rows are in the content load's tables as they were"
  assert spell4.get(tables: content, id: Spell4Id(5649))
    == spell4.get(tables: shared, id: Spell4Id(5649))
    as "the shared load's spell rows are in the content load's tables as they were"
}

pub fn the_committed_creature_and_faction_rows_select_the_spawns_the_clients_rows_select_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Every faction a test names (the player factions 166 and 167, 189, 174, 219,
  // 1441, 1442 and no faction) for both training creatures, selected against the
  // committed content tables and against the client's own: the spawns that start
  // carry the same values, and the coverage is the same.
  let rows =
    list.index_map([0, 166, 167, 189, 174, 219, 1441, 1442], fn(faction, index) {
      list.map([73_464, 73_465], fn(creature) {
        spawn.Row(
          ..spawn_support.beast_row(number: index * 2 + creature - 73_463),
          creature_id: creature,
          display_info_id: case creature {
            73_464 -> 26_565
            _ -> 26_578
          },
          faction_id: faction,
          base_faction_id: faction,
        )
      })
    })
    |> list.flatten
  let formulas = rating_support.formulas()
  let kinds = spawn_support.kinds()
  let planted =
    spawn.select(
      rows:,
      tables: character_tables.content_tables(),
      formulas:,
      kinds:,
      vendors: vendor.none(),
    )
  let real =
    spawn.select(
      rows:,
      tables: client_tables.every_table(),
      formulas:,
      kinds:,
      vendors: vendor.none(),
    )
  assert planted.refusals == [] && real.refusals == []
    as "no row is refused by either"
  assert planted.coverage == real.coverage
    as "the same rows start and are left out, for the same reasons"
  let assert Ok(planted_world) = dict.get(planted.worlds, 3460)
  let assert Ok(real_world) = dict.get(real.worlds, 3460)
  assert planted_world.by_id == real_world.by_id
    as "the spawns that start carry the same values: Base Health, level, faction, display"
  assert dict.has_key(planted_world.by_id, SpawnId(1)) == False
    as "faction 0 is left out in both"
}
