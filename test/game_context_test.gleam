//// What the rules of character select and entering the world read, made from
//// the client's own tables: the CharacterCreation row by id, the level an
//// experience gives (GetLevelForExperience 0x140029820: the highest level is
//// GameFormula row 145's dataint0, 50, and the level is the ID of the last
//// XpPerLevel record, by position, whose minXpForLevel the experience
//// reaches), and the World
//// rows that exist (the client fails to load a world with no row, opcode.0xad).
//// The rows are the client's real files, so the tests skip where
//// `GENESIS_NO_CLIENT=1`.

import client_tables
import environment
import genesis_prime/character/character.{Place}
import genesis_prime/character/character_slots
import genesis_prime/character/customisation
import genesis_prime/game/game_context
import genesis_prime/game/game_session.{type Context}
import genesis_prime/map/position.{Position}
import genesis_prime/table/character_creation
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world
import gleam/list
import owned_test
import unitest

const server_time = 0x01D9F00000000000

const realm_id = 0x99

fn context(tables: table_store.Tables) -> Context {
  game_context.build(
    tables:,
    start: fn(_row) {
      Ok(Place(world_id: 8, world_zone_id: 9, position: Position(0.0, 0.0, 0.0)))
    },
    customisation: customisation.of(tables),
    character_slots: character_slots.hybrid(tables),
    realm_id:,
    server_time:,
  )
}

pub fn every_row_of_the_clients_character_creation_table_is_found_by_its_id_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let context = context(tables)
  let rows = character_creation.all(tables)
  assert rows != [] as "CharacterCreation.tbl holds rows"
  list.each(rows, fn(row) {
    assert context.select.creation(row.id) == Ok(row)
      as "the row of an id is the table's row"
  })
  assert context.select.creation(-1) == Error(Nil)
    as "an id the table has no row for is no row"
}

pub fn the_level_an_experience_gives_is_the_xp_per_level_rows_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let context = context(client_tables.shared())
  assert context.select.level_of(0) == 1
    as "GetLevelForExperience: XpPerLevel record 0 starts at 0 experience"
  assert context.select.level_of(654) == 1
    as "XpPerLevel ID 2 starts at 655, so 654 is still level 1"
  assert context.select.level_of(655) == 2 as "XpPerLevel ID 2 starts at 655"
  assert context.select.level_of(1709) == 2
    as "XpPerLevel ID 3 starts at 1710, so 1709 is still level 2"
  assert context.select.level_of(1710) == 3
    as "XpPerLevel ID 3 starts at 1710; CharacterCreation's Nexus rows start with 1710"
  assert context.select.level_of(340_950) == 20
    as "CharacterCreation's Demo02 rows start with 340950, level 20"
  assert context.select.level_of(936_310) == 25
    as "CharacterCreation's Demo01 rows start with 936310, level 25"
  assert context.select.level_of(26_360_090) == 50
    as "XpPerLevel ID 50 starts at 26360090, and the highest level is 50"
  assert context.select.level_of(2_147_483_647) == 50
    as "the records after ID 50 hold 2147483647, so the level stops at 50 (GameFormula row 145's dataint0)"
}

pub fn every_character_creation_row_starts_a_character_on_a_level_of_the_table_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let context = context(tables)
  list.each(character_creation.all(tables), fn(row) {
    let level = context.select.level_of(row.xp)
    assert level >= 1 && level <= 50
      as "GetLevelForExperience gives every CharacterCreation row's experience a level from 1 to 50"
  })
}

pub fn a_world_exists_when_the_clients_world_table_has_its_row_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let context = context(tables)
  let rows = world.all(tables)
  assert rows != [] as "World.tbl holds rows"
  list.each(rows, fn(row) {
    assert context.entry.world_exists(row.id)
      as "a World row is a world the client can load"
  })
  assert !context.entry.world_exists(-1)
    as "opcode.0xad: a World id with no row fails the client's load"
}

pub fn the_time_the_realm_and_the_starting_place_are_the_ones_given_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let context = context(tables)
  assert context.select.server_time == server_time
    && context.select.realm_id == realm_id
    && context.entry.realm_id == realm_id
    as "the time and the realm are the connection's"
  let assert [row, ..] = character_creation.all(tables) as "a row"
  assert context.select.start(row)
    == Ok(Place(
      world_id: 8,
      world_zone_id: 9,
      position: Position(0.0, 0.0, 0.0),
    ))
    as "the starting place is the one the settings gave"
}
