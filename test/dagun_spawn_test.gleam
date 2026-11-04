//// The 27 Virtual Defense Daguns of migration 0008 (`priv/migrations/0008_spawn.sql`).
//// Expected values come from these places.
//// - The client's own circles (fact `Quest2.10518`, `Quest2.10524`): the Exile
////   objective circle is WorldLocation2 51739 and the Dominion one 52898, each of
////   radius 55; the circle's centre is read from the client's row (planted, and
////   guarded against the real row by `character_tables_test`).
//// - Jim's world database (`spawn.tsv` rows 29113 to 29139, the planted fixture):
////   the 27 points of the Virtual Battle Beast, in the Exile circle. The Dagun has
////   no record anywhere, so each of its points is the offset of one of those rows
////   from the Exile circle's centre, applied to the Dominion circle's centre, a
////   server's choice the migration's reason states.

import character_tables
import content_support
import database_support
import genesis_prime/import_world_data
import genesis_prime/table/id.{WorldLocation2Id}
import genesis_prime/table/world_location2
import gleam/float
import gleam/list
import gleam/string
import owned_test

/// The x, y and z of each spawn of the source, in the order of the world
/// database's row ids for the beasts and of the ids for the Daguns.
fn points(
  database database: String,
  source source: String,
) -> List(#(Float, Float, Float)) {
  content_support.psql(
    database:,
    sql: "select x || ' ' || y || ' ' || z from spawn where source = '"
      <> source
      <> "' order by id",
  )
  |> string.split("\n")
  |> list.map(fn(line) {
    let assert [x, y, z] = string.split(line, " ") as "three numbers"
    #(number(x), number(y), number(z))
  })
}

fn number(text: String) -> Float {
  let assert Ok(value) = float.parse(text) as { "a decimal number: " <> text }
  value
}

pub fn each_dagun_stands_at_the_offset_of_a_beast_point_from_the_exile_circles_centre_inside_the_dominion_circle_test() -> Nil {
  use <- owned_test.run(120_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder: content_support.fixture_folder,
    )
    as "the planted file imports"
  let tables = character_tables.shared()
  let assert Ok(exile) = world_location2.get(tables, WorldLocation2Id(51_739))
    as "the Exile circle"
  let assert Ok(dominion) =
    world_location2.get(tables, WorldLocation2Id(52_898))
    as "the Dominion circle"
  let beasts = points(database:, source: "world_database")
  let daguns = points(database:, source: "server_choice")
  assert list.length(beasts) == 27 && list.length(daguns) == 27
    as "27 beasts of the planted file and 27 Daguns of the migration"
  list.zip(beasts, daguns)
  |> list.each(fn(pair) {
    let #(beast, dagun) = pair
    let expected = #(
      dominion.position0 +. { beast.0 -. exile.position0 },
      dominion.position1 +. { beast.1 -. exile.position1 },
      dominion.position2 +. { beast.2 -. exile.position2 },
    )
    assert float.absolute_value(dagun.0 -. expected.0) <. 0.001
      && float.absolute_value(dagun.1 -. expected.1) <. 0.001
      && float.absolute_value(dagun.2 -. expected.2) <. 0.001
      as "the Dagun is the beast's offset from the Exile circle's centre applied to the Dominion circle's"
    let dx = dagun.0 -. dominion.position0
    let dy = dagun.1 -. dominion.position1
    let dz = dagun.2 -. dominion.position2
    assert dx *. dx +. dy *. dy +. dz *. dz
      <=. dominion.radius *. dominion.radius
      as "and lies inside the Dominion circle (radius 55)"
  })
  assert content_support.count(
      database:,
      sql: "select count(*) from spawn where source = 'server_choice' and reason like 'the offset of world-database row 291%'",
    )
    == 27
    as "each reason names the world-database row whose offset it takes"
}
