//// Facts about the client's own files that tests of the planted tables rely on:
//// the labels and genders the client holds, and the spawns the planted content
//// tables select against the client's. Skipped where `GENESIS_NO_CLIENT=1`, as
//// every test of the real files is.

import character_tables
import client_tables
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/id.{CharacterCustomizationLabelId}
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

pub fn the_planted_creature_and_faction_rows_select_the_spawns_the_clients_rows_select_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Every faction a test plants (the player factions 166 and 167, 189, 174, 219,
  // 1441, 1442 and no faction) for both training creatures, selected against the
  // planted content tables and against the client's own: the spawns that start
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
    )
  let real =
    spawn.select(rows:, tables: client_tables.every_table(), formulas:, kinds:)
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
