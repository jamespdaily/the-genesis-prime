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
import genesis_prime/table/id.{
  CharacterCreationId, CharacterCustomizationId, CharacterCustomizationLabelId,
  WorldLocation2Id,
}
import genesis_prime/table/world_location2
import gleam/list
import gleam/pair
import owned_test
import unitest

pub fn the_planted_character_creation_rows_are_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let ids = [21, 338, 339, 466, 530, 536, 539]
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
  list.each([2, 9, 10], fn(id) {
    let get = fn(tables) {
      character_customization.get(tables:, id: CharacterCustomizationId(id))
    }
    assert get(planted) == get(real)
      as "CharacterCustomization: the planted row is the real row"
  })
  list.each([2, 21, 22], fn(id) {
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
  assert list.all(character_customization.all(real), fn(row) { row.gender < 2 })
    as "the client's CharacterCustomization table has rows for genders 0 and 1 only"
}

pub fn the_planted_start_places_are_the_clients_world_location2_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let ids = list.map(character_tables.start_locations(), pair.first)
  assert list.length(world_location2.all(planted)) == list.length(ids)
    as "the planted table holds exactly the start places"
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
        row.world_id,
        row.world_zone_id,
      )
    }
    assert get(planted) == get(real)
      as "WorldLocation2: the planted row has the real row's id, position, world and zone"
  })
}
