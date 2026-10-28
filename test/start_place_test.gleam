//// Where a new character starts (`genesis_prime/game/start_place`). Expected
//// values come from these places.
//// - Jim's world database (wildstar-knowledge, world-data/start_location.tsv):
////   the WorldLocation2 row of each
////   start of each race and faction. Novice (characterCreationStartEnum 4):
////   row 51596 for every race and faction. Veteran (3): Exile Human and
////   Granok 1594, Aurin and Mordesh 37015; Dominion Cassian and Mechari
////   18987, Draken and Chua 8223. Level 50 (5): Exile 53050, Dominion 53051.
//// - The client's own WorldLocation2 rows: the world, zone and position of
////   each, as `character_tables` plants them (`character_tables_test` compares
////   them with the real file) and as the real table holds them.
//// - The faction ids 166 (Dominion) and 167 (Exile) and the race ids of
////   CharacterCreation (Human or Cassian 1, Granok 3, Aurin 4, Draken 5,
////   Mechari 12, Chua 13, Mordesh 16).
//// - The load's requirement (`genesis_prime/table/loader/store`): a row missing
////   from WorldLocation2 fails the table load.

import character_tables
import client_tables
import genesis_prime/game/appearance
import genesis_prime/game/character_creation
import genesis_prime/game/start_place.{
  type Place, type Start, Level50, Novice, OtherStart, Place, Veteran,
}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/store.{NewCharacter}
import genesis_prime/table/character_creation as creation_table
import genesis_prime/table/id.{RaceId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world_location2
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/pair
import owned_test
import planted_table.{Float, Integer}
import unitest

const dominion = 166

const exile = 167

/// The place of the WorldLocation2 row, as the client's row holds it
/// (`character_tables.start_locations`).
fn place_of_row(row_id: Int) -> Place {
  let assert Ok(place) =
    list.key_find(character_tables.start_locations(), row_id)
    as "the test names a row the planted tables hold"
  place
}

/// Each start of each race and faction with the row Jim's world database
/// gives it: start, faction, race and the WorldLocation2 row.
fn starts() -> List(#(Start, Int, Int, Int)) {
  list.flatten([
    list.map([1, 3, 4, 16], fn(race) { #(Novice, exile, race, 51_596) }),
    list.map([1, 5, 12, 13], fn(race) { #(Novice, dominion, race, 51_596) }),
    [
      #(Veteran, exile, 1, 1594),
      #(Veteran, exile, 3, 1594),
      #(Veteran, exile, 4, 37_015),
      #(Veteran, exile, 16, 37_015),
      #(Veteran, dominion, 1, 18_987),
      #(Veteran, dominion, 12, 18_987),
      #(Veteran, dominion, 5, 8223),
      #(Veteran, dominion, 13, 8223),
    ],
    list.map([1, 3, 4, 16], fn(race) { #(Level50, exile, race, 53_050) }),
    list.map([1, 5, 12, 13], fn(race) { #(Level50, dominion, race, 53_051) }),
  ])
}

fn start_name(start: Start) -> String {
  case start {
    Veteran -> "Veteran"
    Novice -> "Novice"
    Level50 -> "Level 50"
    OtherStart(enum_value:) -> "other " <> int.to_string(enum_value)
  }
}

pub fn each_start_of_each_race_and_faction_is_the_place_of_its_world_location2_row_on_planted_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  list.each(starts(), fn(start) {
    let #(start, faction_id, race_id, row_id) = start
    assert start_place.of(
        tables:,
        faction_id:,
        race_id: RaceId(race_id),
        start:,
      )
      == Ok(place_of_row(row_id))
      as {
        "start "
        <> start_name(start)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ", race "
        <> int.to_string(race_id)
        <> " begins at WorldLocation2 row "
        <> int.to_string(row_id)
        <> " (Jim's world database)"
      }
  })
}

pub fn a_start_race_or_faction_with_no_row_has_no_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let none = fn(faction_id, race_id, start) {
    start_place.of(tables:, faction_id:, race_id: RaceId(race_id), start:)
  }
  assert none(exile, 1, OtherStart(0)) == Error(Nil)
    as "the Arkship start (0) has no start place in Jim's world database"
  assert none(exile, 1, OtherStart(6)) == Error(Nil)
    as "a start the database does not know"
  assert none(165, 1, Veteran) == Error(Nil)
    as "a faction that is neither Dominion nor Exile"
  assert none(exile, 5, Veteran) == Error(Nil)
    as "Draken is a Dominion race: no Exile Draken has a start"
  assert none(dominion, 3, Level50) == Error(Nil)
    as "Granok is an Exile race: no Dominion Granok has a start"
  assert none(exile, 9, Novice) == Error(Nil) as "race 9 is no player race"
}

pub fn each_start_of_each_race_and_faction_is_the_place_of_its_world_location2_row_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(starts(), fn(start) {
    let #(start, faction_id, race_id, row_id) = start
    let assert Ok(row) =
      world_location2.get(tables:, id: WorldLocation2Id(row_id))
      as "the row exists in the client's table"
    assert start_place.of(
        tables:,
        faction_id:,
        race_id: RaceId(race_id),
        start:,
      )
      == Ok(Place(
        world_id: row.world_id,
        world_zone_id: row.world_zone_id,
        x: row.position0,
        y: row.position1,
        z: row.position2,
      ))
      as "the place is the client's row: its World, WorldZone and position"
  })
}

pub fn every_enabled_character_creation_row_of_a_start_has_a_start_place_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    list.filter(creation_table.all(tables), fn(row) {
      row.enabled
      && !row.costume_only
      && list.contains(
        [Novice, Veteran, Level50],
        start_place.start(enum_value: row.character_creation_start_enum),
      )
    })
  assert rows != [] as "the client's table has enabled rows of these starts"
  list.each(rows, fn(row) {
    assert start_place.of(
        tables:,
        faction_id: row.faction_id,
        race_id: creation_table.race_id(row),
        start: start_place.start(enum_value: row.character_creation_start_enum),
      )
      != Error(Nil)
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " is an enabled start of a race and faction, so it has a place"
      }
  })
}

pub fn a_create_of_each_start_of_each_race_and_faction_saves_the_place_of_its_world_location2_row_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    list.filter(creation_table.all(tables), fn(row) {
      row.enabled
      && !row.costume_only
      && list.contains(
        [Novice, Veteran, Level50],
        start_place.start(enum_value: row.character_creation_start_enum),
      )
    })
  list.each(rows, fn(row) {
    let assert Ok(#(_, _, _, row_id)) =
      list.find(starts(), fn(start) {
        start.0
        == start_place.start(enum_value: row.character_creation_start_enum)
        && start.1 == row.faction_id
        && start.2 == row.race_id
      })
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " is a start of a race and faction Jim's world database lists"
      }
    // The row's entitlement and cost gate the create, which this test is not
    // about: the place is what it reads.
    let open =
      creation_table.CharacterCreation(
        ..row,
        entitlement_id_required: 0,
        account_currency_amount_cost: 0,
      )
    let request =
      CreateCharacter(
        creation_id: row.id,
        name: "Ab Cd",
        path: 0,
        customisation_labels: [],
        customisation_values: [],
        bone_values: list.repeat(
          0,
          appearance.bone_count(
            tables:,
            race_id: creation_table.race_id(row),
            sex: row.sex,
          ),
        ),
      )
    let expected = place_of_row(row_id)
    let assert Ok(NewCharacter(
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
      ..,
    )) = character_creation.check_row(tables, open, request)
      as {
        "a create of CharacterCreation row "
        <> int.to_string(row.id)
        <> " passes the checks"
      }
    assert Place(
        world_id:,
        world_zone_id:,
        x: position_x,
        y: position_y,
        z: position_z,
      )
      == expected
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " (start "
        <> int.to_string(row.character_creation_start_enum)
        <> ", faction "
        <> int.to_string(row.faction_id)
        <> ", race "
        <> int.to_string(row.race_id)
        <> ") saves the place of WorldLocation2 row "
        <> int.to_string(row_id)
      }
  })
}

/// The WorldLocation2 file with the rows of these ids, each with a position,
/// world and zone of 1.
fn world_location2_file(ids: List(Int)) -> #(String, BitArray) {
  let rows =
    list.map(ids, fn(id) {
      planted_table.row(world_location2.schema, [
        #("ID", Integer(id)),
        #("position0", Float(1.0)),
        #("worldId", Integer(1)),
        #("worldZoneId", Integer(1)),
      ])
    })
  #(
    world_location2.schema.file,
    planted_table.bytes(planted_table.table(world_location2.schema, rows)),
  )
}

/// Loads the planted WorldLocation2 rows of `ids` with the start places'
/// requirement.
fn load_with_rows(
  ids: List(Int),
) -> Result(table_store.Tables, table_store.LoadError) {
  use folder <- planted_table.in_folder([world_location2_file(ids)])
  table_store.load(
    under: reference.new(),
    from: folder,
    entries: [world_location2.entry()],
    requirements: [start_place.requirement()],
  )
}

pub fn the_table_load_fails_when_a_start_places_row_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  let all = list.map(character_tables.start_locations(), pair.first)
  let assert Ok(tables) = load_with_rows(all)
    as "every row of the start places loads"
  table_store.unload(tables)
  list.each(all, fn(missing) {
    assert load_with_rows(list.filter(all, fn(id) { id != missing }))
      == Error(table_store.RowMissing(
        from_table: "the server's start places",
        column: "WorldLocation2 id",
        to_table: "WorldLocation2",
        id: missing,
      ))
      as {
        "WorldLocation2 row "
        <> int.to_string(missing)
        <> " is a start place, so a load without it fails, naming it"
      }
  })
}

pub fn the_client_has_every_start_places_row_so_the_servers_table_load_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert start_place.requirement().missing(tables) == []
    as "the client's WorldLocation2 holds rows 1594, 8223, 18987, 37015, 51596, 53050 and 53051; the shared tables loaded with this requirement among the server's"
}
