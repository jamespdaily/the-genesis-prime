//// Where a new character starts (`genesis_prime/game/start_place`). Expected
//// values come from these places.
//// - The client's tutorial text names where each start lands: records
////   Quest2.10528.links (Exile Veteran: 42074 for Human and Granok, 41641 for
////   Aurin and Mordesh, by the race groups in quest 10528's text) and
////   Quest2.10530.links (Dominion Veteran: 42148 and 8223), and the Novice
////   start's row 51596 is a guess (Quest2.10513: it faces the first quest
////   circle). The Dominion race split (Cassian and Mechari 42148, Draken and
////   Chua 8223) is a retail record, wildstaronline-archive "Destiny" and
////   "Levian Bay". Level 50 (5) has no row: every Level 50 CharacterCreation
////   row costs account currency, which a create refuses first (decision D7).
//// - The client's own WorldLocation2 rows: the world, zone, position and
////   facing quaternion of each, as `character_tables` plants them
////   (`character_tables_test` compares them with the real file) and as the
////   real table holds them.
//// - The client's QuaternionToEulerAngles 0x1401b2fe0 and
////   RotationMatrixToEulerAngles 0x1401b2ed0 (their records), emulated at the
////   points the tests name and at each start row's facing, whose results are
////   compared to the bit.
//// - The faction ids 166 (Dominion) and 167 (Exile) and the race ids of
////   CharacterCreation (Human or Cassian 1, Granok 3, Aurin 4, Draken 5,
////   Mechari 12, Chua 13, Mordesh 16).
//// - The load's requirement (`genesis_prime/table/loader/store`): a row missing
////   from WorldLocation2 fails the table load.

import character_support
import character_tables
import client_tables
import genesis_prime/game/start_place.{
  type Start, Level50, Novice, OtherStart, Veteran,
}
import genesis_prime/message/float32
import genesis_prime/table/character_creation as creation_table
import genesis_prime/table/id.{RaceId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world_location2
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/list
import owned_test
import place_support
import planted_table.{Float, Integer}
import unitest

const dominion = 166

const exile = 167

/// Each start of each race and faction with the row the client's text gives it:
/// start, faction, race, the WorldLocation2 row and the record that names it.
fn starts() -> List(#(Start, Int, Int, Int, String)) {
  let novice = "Quest2.10513 (a guess: it faces the first quest circle)"
  let exile_links = "Quest2.10528.links and the race groups of its text"
  let dominion_links =
    "Quest2.10530.links; the race split is the retail record wildstaronline-archive 'Destiny' and 'Levian Bay'"
  list.flatten([
    list.map([1, 3, 4, 16], fn(race) { #(Novice, exile, race, 51_596, novice) }),
    list.map([1, 5, 12, 13], fn(race) {
      #(Novice, dominion, race, 51_596, novice)
    }),
    [
      #(Veteran, exile, 1, 42_074, exile_links),
      #(Veteran, exile, 3, 42_074, exile_links),
      #(Veteran, exile, 4, 41_641, exile_links),
      #(Veteran, exile, 16, 41_641, exile_links),
      #(Veteran, dominion, 1, 42_148, dominion_links),
      #(Veteran, dominion, 12, 42_148, dominion_links),
      #(Veteran, dominion, 5, 8223, dominion_links),
      #(Veteran, dominion, 13, 8223, dominion_links),
    ],
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
    let #(start, faction_id, race_id, row_id, record) = start
    let assert Ok(place) =
      start_place.of(tables:, faction_id:, race_id: RaceId(race_id), start:)
      as {
        "start "
        <> start_name(start)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ", race "
        <> int.to_string(race_id)
        <> " has a place"
      }
    assert character_tables.is_the_place_of(
      place:,
      row: character_tables.start_row(row_id),
    )
      as {
        "start "
        <> start_name(start)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ", race "
        <> int.to_string(race_id)
        <> " begins at WorldLocation2 row "
        <> int.to_string(row_id)
        <> " ("
        <> record
        <> "), facing the client's yaw of the row"
      }
  })
}

pub fn a_place_in_world_0_cannot_be_made_test() -> Nil {
  use <- owned_test.run(5000)
  assert start_place.place(
      world_id: 0,
      world_zone_id: 6009,
      x: 1.0,
      y: 2.0,
      z: 3.0,
      facing: start_place.unturned,
    )
    == Error(Nil)
    as "world 0 is no World row, which 0xAD needs (opcode.0xad), so no place is in it"
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 6009,
      x: 1.0,
      y: 2.0,
      z: 3.0,
      facing: start_place.unturned,
    )
    as "a place in a world is made"
  assert #(
      start_place.world_id(place),
      start_place.world_zone_id(place),
      start_place.x(place),
      start_place.y(place),
      start_place.z(place),
    )
    == #(3460, 6009, 1.0, 2.0, 3.0)
}

pub fn a_start_whose_world_location2_row_is_in_world_0_has_no_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared_with_novice_start_in_world_0()
  assert start_place.of(
      tables:,
      faction_id: exile,
      race_id: RaceId(1),
      start: Novice,
    )
    == Error(Nil)
    as "the Novice row's World is 0, which is no World row (opcode.0xad)"
  let assert Ok(veteran) =
    start_place.of(
      tables:,
      faction_id: exile,
      race_id: RaceId(1),
      start: Veteran,
    )
    as "the Veteran row (42074, Quest2.10528.links), in World 426, still has its place"
  assert character_tables.is_the_place_of(
    place: veteran,
    row: character_tables.start_row(42_074),
  )
    as "the Veteran place is the client's row 42074"
}

pub fn a_start_race_or_faction_with_no_row_has_no_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let none = fn(faction_id, race_id, start) {
    start_place.of(tables:, faction_id:, race_id: RaceId(race_id), start:)
  }
  assert none(exile, 1, OtherStart(0)) == Error(Nil)
    as "the Arkship start (0) has no start place (no row of the client names it)"
  assert none(exile, 1, OtherStart(6)) == Error(Nil)
    as "a start no row of the client names"
  assert none(165, 1, Veteran) == Error(Nil)
    as "a faction that is neither Dominion nor Exile"
  assert none(exile, 5, Veteran) == Error(Nil)
    as "Draken is a Dominion race: no Exile Draken has a start"
  assert none(dominion, 3, Veteran) == Error(Nil)
    as "Granok is an Exile race: no Dominion Granok has a start"
  assert none(exile, 1, Level50) == Error(Nil)
    as "no Level 50 start has a place: every Level 50 row costs account currency, which a create refuses first"
  assert none(dominion, 1, Level50) == Error(Nil)
    as "no Level 50 start has a place, of either faction"
  assert none(exile, 9, Novice) == Error(Nil) as "race 9 is no player race"
}

pub fn each_start_of_each_race_and_faction_is_the_place_of_its_world_location2_row_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(starts(), fn(start) {
    let #(start, faction_id, race_id, row_id, record) = start
    let assert Ok(row) =
      world_location2.get(tables:, id: WorldLocation2Id(row_id))
      as "the row exists in the client's table"
    let assert Ok(place) =
      start_place.of(tables:, faction_id:, race_id: RaceId(race_id), start:)
      as "the start has a place"
    assert start_place.turned(place, start_place.unturned)
      == place_support.at(
        world_id: row.world_id,
        world_zone_id: row.world_zone_id,
        x: row.position0,
        y: row.position1,
        z: row.position2,
      )
      as {
        "the place is the client's row "
        <> int.to_string(row_id)
        <> " ("
        <> record
        <> "): its World, WorldZone and position"
      }
    assert character_tables.is_the_place_of(
      place:,
      row: character_tables.start_row(row_id),
    )
      as {
        "row "
        <> int.to_string(row_id)
        <> " faces the client's yaw (QuaternionToEulerAngles 0x1401b2fe0)"
      }
  })
}

pub fn every_enabled_character_creation_row_of_a_start_has_a_start_place_in_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = character_support.novice_and_veteran_rows(tables)
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
  let rows = character_support.novice_and_veteran_rows(tables)
  list.each(rows, fn(row) {
    let assert Ok(#(_, _, _, row_id, _)) =
      list.find(starts(), fn(start) {
        start.0
        == start_place.start(enum_value: row.character_creation_start_enum)
        && start.1 == row.faction_id
        && start.2 == row.race_id
      })
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " is a start of a race and faction the client's text names a row for"
      }
    let character = character_support.new_character_of_row(tables:, row:)
    assert character_tables.is_the_place_of(
      place: character.place,
      row: character_tables.start_row(row_id),
    )
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
  planted_table.file(world_location2.schema, rows)
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
    derivations: [],
  )
}

pub fn the_table_load_fails_when_a_start_places_row_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  let all = list.map(character_tables.start_rows(), fn(row) { row.id })
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
    as "the client's WorldLocation2 holds rows 8223, 41641, 42074, 42148 and 51596; the shared tables loaded with this requirement among the server's"
}

pub fn every_level_50_row_of_the_clients_table_costs_account_currency_so_a_create_refuses_it_before_its_start_place_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    list.filter(creation_table.all(tables), fn(row) {
      start_place.start(enum_value: row.character_creation_start_enum)
      == Level50
    })
  assert rows != [] as "the client's table has Level 50 rows"
  list.each(rows, fn(row) {
    assert row.account_currency_amount_cost != 0
      as {
        "fact CharacterCreation.xp: Level50 rows cost account currency 13, amount 1; CharacterCreation row "
        <> int.to_string(row.id)
        <> " is one"
      }
  })
}

pub fn a_position_is_bounded_to_the_box_the_client_bounds_a_unit_to_and_nothing_else_changes_test() -> Nil {
  use <- owned_test.run(10_000)
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 40_000.0,
      y: -3000.0,
      z: -1.0e9,
    )
  let bounded = start_place.within_the_worlds_box(place)
  assert #(
      start_place.x(bounded),
      start_place.y(bounded),
      start_place.z(bounded),
    )
    == #(32_768.0, -2048.0, -32_768.0)
    as "0x1405b5070: x and z are bounded to -32768 and 32768, y to -2048 and 2048"
  assert start_place.within_the_worlds_box(place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: -32_768.0,
      y: 2048.0,
      z: 32_768.0,
    ))
    == place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: -32_768.0,
      y: 2048.0,
      z: 32_768.0,
    )
    as "0x1405b5070: a position on the box's edge is inside it"
  assert #(
      start_place.world_id(bounded),
      start_place.world_zone_id(bounded),
      start_place.facing(bounded),
    )
    == #(3460, 6009, start_place.unturned)
    as "only the position is bounded"
}

/// Checks a facing against the yaw, pitch and roll the client gives, each to
/// the 32-bit float the client holds it in.
fn assert_facing(
  facing facing: start_place.Facing,
  yaw yaw: Float,
  pitch pitch: Float,
  roll roll: Float,
  because why: String,
) -> Nil {
  assert #(
      float32.to_bits(facing.yaw),
      float32.to_bits(facing.pitch),
      float32.to_bits(facing.roll),
    )
    == #(float32.to_bits(yaw), float32.to_bits(pitch), float32.to_bits(roll))
    as why
}

pub fn a_quaternion_of_no_turn_and_of_a_turn_about_one_axis_gives_the_clients_yaw_pitch_and_roll_test() -> Nil {
  use <- owned_test.run(5000)
  let facing_of = fn(x, y, z, w) {
    start_place.facing_of_quaternion(x:, y:, z:, w:)
  }
  // The pitch is asin(-m21): where m21 is +0 the client's -m21 is -0 and its
  // asin is -0 (0x80000000), as its emulated pitch is for every start row
  // that turns about y alone (record 0x1401b2fe0).
  assert_facing(
    facing: facing_of(0.0, 0.0, 0.0, 1.0),
    yaw: 0.0,
    pitch: -0.0,
    roll: 0.0,
    because: "0x1401b2fe0 emulated: the identity (0, 0, 0, 1) gives (0, 0, 0)",
  )
  // sin(0.25) and cos(0.25): a turn of 0.5 about an axis is (sin t/2, cos t/2).
  let sine = 0.24740395925452294
  let cosine = 0.9689124217106447
  assert_facing(
    facing: facing_of(0.0, sine, 0.0, cosine),
    yaw: 0.5,
    pitch: -0.0,
    roll: 0.0,
    because: "0x1401b2fe0 emulated: (0, sin .25, 0, cos .25), a turn of 0.5 about y, gives (0.5, 0, 0)",
  )
  assert_facing(
    facing: facing_of(sine, 0.0, 0.0, cosine),
    yaw: 0.0,
    pitch: 0.5,
    roll: 0.0,
    because: "0x1401b2fe0 emulated: (sin .25, 0, 0, cos .25), a turn of 0.5 about x, gives (0, 0.5, 0)",
  )
  assert_facing(
    facing: facing_of(0.0, 0.0, sine, cosine),
    yaw: 0.0,
    pitch: -0.0,
    roll: 0.5,
    because: "0x1401b2fe0 emulated: (0, 0, sin .25, cos .25), a turn of 0.5 about z, gives (0, 0, 0.5)",
  )
}

pub fn a_quaternion_with_the_matrix_at_the_poles_gives_pitch_of_a_quarter_turn_roll_0_and_the_yaw_of_its_first_row_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x1401b2ed0: m21 below -0.99999 gives pitch +pi/2 (0x3fc90fdb), roll 0 and
  // yaw atan2(-m02, m00); m21 above 0.99999 gives pitch -pi/2 (0xbfc90fdb).
  // The quaternions turn 0.5 about y after a quarter turn about x, with the
  // quarter turn either way, so the yaw atan2(-m02, m00) is 0.5.
  assert_facing(
    facing: start_place.facing_of_quaternion(
      x: 0.6851245437674767,
      y: 0.17494101728127348,
      z: -0.17494101728127345,
      w: 0.6851245437674768,
    ),
    yaw: 0.5,
    pitch: 1.5707963705062866,
    roll: 0.0,
    because: "0x1401b2ed0: m21 is -1, below -0.99999: pitch +pi/2, roll 0, yaw atan2(-m02, m00) = 0.5",
  )
  assert_facing(
    facing: start_place.facing_of_quaternion(
      x: -0.6851245437674767,
      y: 0.17494101728127348,
      z: 0.17494101728127345,
      w: 0.6851245437674768,
    ),
    yaw: 0.5,
    pitch: -1.5707963705062866,
    roll: 0.0,
    because: "0x1401b2ed0: m21 is 1, above 0.99999: pitch -pi/2, roll 0, yaw atan2(-m02, m00) = 0.5",
  )
  // A turn about x of t has m21 = -sin t: 1.56 (sin 0.99994) is inside the
  // threshold and gives pitch 1.56; 1.57 (sin 0.9999997) is beyond it and
  // gives pi/2, not 1.57, with the yaw atan2(-m02, m00) of m02 = +0: -0.
  assert_facing(
    facing: start_place.facing_of_quaternion(
      x: 0.7032794192004103,
      y: 0.0,
      z: 0.0,
      w: 0.7109135380122773,
    ),
    yaw: 0.0,
    pitch: 1.56,
    roll: 0.0,
    because: "0x1401b2ed0: m21 = -0.99994 is not below -0.99999, so pitch is asin(-m21) = 1.56",
  )
  assert_facing(
    facing: start_place.facing_of_quaternion(
      x: 0.706825181105366,
      y: 0.0,
      z: 0.0,
      w: 0.7073882691671998,
    ),
    yaw: -0.0,
    pitch: 1.5707963705062866,
    roll: 0.0,
    because: "0x1401b2ed0: m21 = -0.9999997 is below -0.99999, so pitch is pi/2, not 1.57",
  )
}

pub fn the_pole_threshold_is_compared_with_the_matrix_entry_as_the_32_bit_float_the_client_holds_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x1401b2ed0 compares a 32-bit m21 with -0.99999 (0xbf7fff58, as a 32-bit
  // float -0.9999899864196777). These turns about x have m21 = -0.99998999642
  // and its mirror, 1e-8 beyond the threshold as 64-bit floats and within half a
  // 32-bit step (3e-8) of it, so as 32-bit floats m21 equals the threshold,
  // which is not beyond it: the pitch is asin(-m21), +-1.5663, not +-pi/2.
  let below =
    start_place.facing_of_quaternion(
      x: 0.7055235909303883,
      y: 0.0,
      z: 0.0,
      w: 0.7086864346385432,
    )
  let above =
    start_place.facing_of_quaternion(
      x: -0.7055235909303883,
      y: 0.0,
      z: 0.0,
      w: 0.7086864346385432,
    )
  assert float.absolute_value(below.pitch -. 1.5663232) <. 1.0e-4
    as "0x1401b2ed0: a 32-bit m21 equal to -0.99999 is not below it, so the pitch is asin(-m21), 1.5663, not pi/2"
  assert float.absolute_value(above.pitch +. 1.5663232) <. 1.0e-4
    as "0x1401b2ed0: a 32-bit m21 equal to 0.99999 is not above it, so the pitch is asin(-m21), -1.5663, not -pi/2"
}

pub fn each_start_rows_facing_gives_the_yaw_pitch_and_roll_the_client_gives_to_the_bit_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(character_tables.start_rows(), fn(row) {
    let #(x, y, z, w) = row.quaternion
    assert character_tables.facing_bits(start_place.facing_of_quaternion(
        x:,
        y:,
        z:,
        w:,
      ))
      == row.facing_bits
      as {
        "row "
        <> int.to_string(row.id)
        <> ": the yaw, pitch and roll bits QuaternionToEulerAngles 0x1401b2fe0 returns in the emulator"
      }
  })
}

pub fn each_start_rows_facing_in_the_clients_tables_gives_the_yaw_pitch_and_roll_the_client_gives_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(character_tables.start_rows(), fn(expected) {
    let assert Ok(row) =
      world_location2.get(tables:, id: WorldLocation2Id(expected.id))
      as "the row exists in the client's table"
    let facing =
      start_place.facing_of_quaternion(
        x: row.facing0,
        y: row.facing1,
        z: row.facing2,
        w: row.facing3,
      )
    assert character_tables.facing_bits(facing) == expected.facing_bits
      as {
        "row "
        <> int.to_string(expected.id)
        <> ": the client's own facing gives the bits QuaternionToEulerAngles gives in the emulator"
      }
  })
}
