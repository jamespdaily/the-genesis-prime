//// The planted character tables (`character_tables`) against the client's own
//// files: every row the tests plant is the real row in the columns the server
//// reads, so the rule tests that run without the client carry the client's
//// values. Skipped where `GENESIS_NO_CLIENT=1`, as every test of the real
//// files is.

import character_tables
import client_tables
import genesis_prime/table/character_creation
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  CharacterCreationId, CharacterCustomizationId, CharacterCustomizationLabelId,
  GameFormulaId, WorldLocation2Id,
}
import genesis_prime/table/world_location2
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/list
import owned_test
import rating_support
import spawn_support
import unitest

pub fn the_planted_character_creation_rows_are_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let ids = [
    21, 338, 339, 359, 466, 468, 469, 470, 471, 472, 478, 479, 480, 481, 484,
    485, 530, 536, 539,
  ]
  assert list.length(character_creation.all(planted)) == list.length(ids)
    as "the planted table holds exactly the rows the tests use"
  list.each(ids, fn(id) {
    let get = fn(tables) {
      let assert Ok(row) =
        character_creation.get(tables:, id: CharacterCreationId(id))
        as "the row exists"
      #(
        row.id,
        row.class_id,
        row.race_id,
        row.sex,
        row.faction_id,
        row.costume_only,
        row.enabled,
        row.character_creation_start_enum,
        row.xp,
        row.account_currency_type_id_cost,
        row.account_currency_amount_cost,
        row.entitlement_id_required,
      )
    }
    assert get(planted) == get(real)
      as "CharacterCreation: the planted row has the real row's columns"
  })
}

pub fn the_planted_customization_rows_and_labels_are_the_clients_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  list.each([2, 9, 10, 603, 604], fn(id) {
    let get = fn(tables) {
      character_customization.get(tables:, id: CharacterCustomizationId(id))
    }
    assert get(planted) == get(real)
      as "CharacterCustomization: the planted row is the real row"
  })
  list.each([2, 21, 22, 26, 27], fn(id) {
    let get = fn(tables) {
      let assert Ok(label) =
        character_customization_label.get(
          tables:,
          id: CharacterCustomizationLabelId(id),
        )
        as "the label exists"
      #(label.id, label.faction2_id)
    }
    assert get(planted) == get(real)
      as "CharacterCustomizationLabel: the planted label has the real id and faction"
  })
  assert character_customization_label.get(
      tables: real,
      id: CharacterCustomizationLabelId(28),
    )
    == Error(Nil)
    as "the client's CharacterCustomizationLabel has no row 28, which the planted tests use as a label with no row"
  assert list.all(character_customization.all(real), fn(row) { row.gender < 2 })
    as "the client's CharacterCustomization table has rows for genders 0 and 1 only"
}

pub fn the_planted_start_places_are_the_clients_world_location2_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let ids = list.map(character_tables.start_rows(), fn(row) { row.id })
  assert list.length(world_location2.all(planted))
    == list.length(ids) + list.length(character_tables.circle_ids)
    as "the planted table holds exactly the start places and the objective circles"
  list.each(ids, fn(id) {
    let get = fn(tables) {
      let assert Ok(row) =
        world_location2.get(tables:, id: WorldLocation2Id(id))
        as "the row exists"
      #(
        row.id,
        row.position0,
        row.position1,
        row.position2,
        row.facing0,
        row.facing1,
        row.facing2,
        row.facing3,
        row.world_id,
        row.world_zone_id,
      )
    }
    assert get(planted) == get(real)
      as "WorldLocation2: the planted row has the real row's id, position, facing, world and zone"
  })
}

pub fn the_planted_level_rows_are_the_clients_game_formula_and_xp_per_level_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let formula = fn(tables) {
    game_formula.get(
      tables:,
      id: GameFormulaId(character_tables.highest_level_formula),
    )
  }
  assert formula(planted) == formula(real)
    as "GameFormula row 145: the planted row is the real row (dataint0 50)"
  let minimums = fn(tables) {
    xp_per_level.all(tables)
    |> list.take(list.length(character_tables.min_xp_for_level()))
    |> list.map(fn(row) { #(row.id, row.min_xp_for_level) })
  }
  assert minimums(planted) == minimums(real)
    as "XpPerLevel: the planted records are the real records 1 to 51, with the real minXpForLevel"
  assert list.length(xp_per_level.all(planted))
    == list.length(character_tables.min_xp_for_level())
    as "the planted table holds exactly the records the level rule reads"
}

pub fn the_planted_objective_circles_are_the_clients_world_location2_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  list.each(character_tables.circle_ids, fn(id) {
    let get = fn(tables) {
      let assert Ok(row) =
        world_location2.get(tables:, id: WorldLocation2Id(id))
        as "the row exists"
      #(
        row.id,
        row.radius,
        row.position0,
        row.position1,
        row.position2,
        row.world_id,
        row.world_zone_id,
      )
    }
    assert get(planted) == get(real)
      as "WorldLocation2: the planted circle has the real row's id, radius, position, world and zone"
  })
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
  let planted =
    spawn.select(rows:, tables: character_tables.content_tables(), formulas:)
  let real = spawn.select(rows:, tables: client_tables.every_table(), formulas:)
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
