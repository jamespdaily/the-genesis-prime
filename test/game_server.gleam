//// The whole server started for the tests that play over TCP: the login's two
//// listeners and the game listener on free ports, the client's own
//// CharacterCreation, XpPerLevel and World tables loaded from its files, a
//// database of the test's own, and a game clock the test plants so the
//// server's time in message 0x117 is exact. The starting place of a new
//// character is planted too: no client table or code holds one.

import client_tables
import genesis_prime/character/character.{type Place, Place}
import genesis_prime/character/character_slots
import genesis_prime/character/customisation
import genesis_prime/game/service as game_service
import genesis_prime/login/account
import genesis_prime/login/auth_session
import genesis_prime/login/handoff
import genesis_prime/login/service
import genesis_prime/map/position.{Position}
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import genesis_prime/shutdown
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/reward_property_premium_modifier
import genesis_prime/table/world
import genesis_prime/table/xp_per_level
import gleam/erlang/process.{type Name}
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/option.{None}
import login_client
import template_database

/// How long a test waits for the server to open its ports, in milliseconds.
const wait_ms = 5000

/// The server's time in these tests, as a Windows FILETIME.
pub const server_time = 0x01D9F00000000000

/// The realm the connections are on in these tests.
pub const realm_id = 0x99

/// The facts of the client's tables the tests plant their expectations on:
/// `bone_count` is the bone values a create request for the row's race and sex
/// carries (opcode.0x25b.counts).
pub type Facts {
  Facts(
    creation: CharacterCreation,
    world_id: Int,
    experience_levels: List(#(Int, Int)),
    bone_count: Int,
  )
}

/// The running server: the ports it opened, what the tests reach into and the
/// facts of the tables.
pub type Running {
  Running(
    ports: login_client.Ports,
    game_port: Int,
    session_keys: Name(handoff.Message(account.Identity)),
    game: game_service.Settings,
    shutdown: shutdown.Settings,
    facts: Facts,
  )
}

/// The tables the game server reads.
fn tables() -> List(table_store.Entry) {
  [
    character_creation.entry(),
    character_customization_label.entry(),
    customization_parameter.entry(),
    customization_parameter_map.entry(),
    game_formula.entry(),
    reward_property_premium_modifier.entry(),
    world.entry(),
    xp_per_level.entry(),
  ]
}

/// The place a new character starts at in these tests, in a world the client's
/// table holds.
pub fn start_place(world_id world_id: Int) -> Place {
  Place(world_id:, world_zone_id: 9, position: Position(x: 1.5, y: 2.5, z: 3.5))
}

/// The facts of the client's tables: a CharacterCreation row an account may
/// make a character from (enabled, no entitlement, no account currency), a
/// World row, and every XpPerLevel row as its level and the experience it
/// starts at.
pub fn facts() -> Facts {
  let assert Ok(tables) =
    table_store.load(
      under: reference.new(),
      from: client_tables.folder(),
      entries: tables(),
      requirements: [],
    )
    as "the client's tables did not load"
  let assert Ok(creation) =
    list.find(character_creation.all(tables), fn(row) {
      row.enabled
      && row.entitlement_id_required == 0
      && row.account_currency_amount_cost == 0
    })
    as "CharacterCreation.tbl holds a row an account can make a character from"
  let assert [first_world, ..] = world.all(tables) as "World.tbl holds rows"
  Facts(
    creation:,
    bone_count: customisation.bone_count(
      customisation.of(tables),
      creation.race_id,
      creation.sex,
    ),
    world_id: first_world.id,
    experience_levels: xp_per_level.all(tables)
      |> list.filter(fn(row) { row.id <= 50 })
      |> list.map(fn(row) { #(row.id, row.min_xp_for_level) }),
  )
}

/// The level the client's tables give an experience: the highest XpPerLevel ID
/// up to the highest level, 50 (GameFormula row 145's dataint0), whose minimum
/// experience it reaches (GetLevelForExperience 0x140029820).
pub fn level_of(facts facts: Facts, experience experience: Int) -> Int {
  let reached =
    list.filter(facts.experience_levels, fn(row) { row.1 <= experience })
  let assert Ok(level) =
    list.map(reached, fn(row) { row.0 })
    |> list.sort(fn(first, second) { int.compare(second, first) })
    |> list.first
    as "the experience reaches a level of the table"
  level
}

/// Starts the server on free ports with the test's database, and waits for its
/// three listeners to open.
pub fn start(
  database database: template_database.Database,
  answer_deadline_ms answer_deadline_ms: Int,
) -> Running {
  start_with(database:, answer_deadline_ms:, change: fn(settings) { settings })
}

/// Starts the server as `start` does, with the game's settings changed by
/// `change` first, such as the deadlines of a second login.
pub fn start_with(
  database database: template_database.Database,
  answer_deadline_ms answer_deadline_ms: Int,
  change change: fn(game_service.Settings) -> game_service.Settings,
) -> Running {
  let facts = facts()
  let pool_settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("game_tcp_pool"),
      pool_size: 4,
    )
  let defaults = template_database.tree_settings(pool_settings)
  let ports = process.new_subject()
  let login =
    service.Settings(
      ..defaults.login,
      sts: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("sts", port))
      }),
      auth: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("auth", port))
      }),
      auth_login: auth_session.Settings(
        game_server: Endpoint(address: 0x7F000001, port: 0),
        realm_name: "Nexus",
        expected_files_digest: None,
      ),
    )
  // Only the world the tests play in has a map's names: every world of the
  // client's table would make thousands of names in each test's server.
  let game =
    change(
      game_service.Settings(
        ..defaults.game,
        opened: fn(port) { process.send(ports, #("game", port)) },
        realm_id:,
        start: fn(_tables, _row) { Ok(start_place(world_id: facts.world_id)) },
        customisation: customisation.of,
        character_slots: character_slots.hybrid,
        clock: fn() { server_time },
        answer_deadline_ms:,
        worlds: fn(_tables) { [facts.world_id] },
      ),
    )
  let assert Ok(_) =
    server.start(
      server.Settings(
        ..defaults,
        tables: server.TableSettings(
          key: reference.new(),
          folder: client_tables.folder(),
          entries: tables(),
          requirements: [],
        ),
        login:,
        game:,
      ),
    )
    as "the server's tree did not start"
  let opened = receive_ports(ports:, remaining: 3, opened: [])
  let assert Ok(sts_port) = list.key_find(opened, "sts")
    as "the STS listener opened"
  let assert Ok(auth_port) = list.key_find(opened, "auth")
    as "the auth listener opened"
  let assert Ok(game_port) = list.key_find(opened, "game")
    as "the game listener opened"
  Running(
    ports: login_client.Ports(sts_port:, auth_port:),
    game_port:,
    session_keys: login.session_keys.name,
    game:,
    shutdown: defaults.shutdown,
    facts:,
  )
}

fn receive_ports(
  ports ports: process.Subject(#(String, Int)),
  remaining remaining: Int,
  opened opened: List(#(String, Int)),
) -> List(#(String, Int)) {
  case remaining {
    0 -> opened
    _ -> {
      let assert Ok(port) = process.receive(ports, wait_ms)
        as "a listener did not open"
      receive_ports(ports:, remaining: remaining - 1, opened: [port, ..opened])
    }
  }
}
