//// The settings of the login and game rules as the tests give them to a rule or
//// to a listener: the realm the auth rule hands clients to, and each rule's
//// settings, whose ask deadline is the server's own (5 s). A rule's tests read
//// the deadline as data (an ask's deadline in the rule's effects). A listener
//// that runs on a clock of its own replaces it with a deadline beyond the test
//// (`login_support`).

import character_tables
import class_resource_support
import connection_rule_support as support
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/objective
import genesis_prime/game/vendor
import genesis_prime/game_settings
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/world_map/spawn_id
import gleam/dict
import gleam/option.{None}
import gleam/set
import projector_support
import server_proxy_support
import spawn_support
import tutorial_support
import zone_welcome_support

/// The realm the auth rule hands clients to.
pub fn realm() -> auth_connection.Realm {
  auth_connection.Realm(
    id: 1,
    name: "Nexus",
    game_server: Endpoint(address: 0x7F000001, port: 24_000),
  )
}

/// The settings of the STS rule.
pub fn sts_settings() -> sts_connection.Settings {
  sts_connection.Settings(
    ask_deadline_ms: 5000,
    game_token_lifetime_ms: 60_000,
    rate: support.roomy(),
  )
}

/// The settings of the auth rule: nothing planted.
pub fn auth_settings() -> auth_connection.Settings {
  auth_connection.Settings(
    realm: realm(),
    ask_deadline_ms: 5000,
    session_key_lifetime_ms: auth_connection.session_key_lifetime_ms,
    planted: None,
    rate: support.roomy(),
  )
}

/// The settings of the game rule.
pub fn game_settings() -> connection_state.Settings {
  connection_state.Settings(
    realm_id: 1,
    max_characters: 12,
    game: game_settings.defaults(),
    realm_name: realm().name,
    tables: character_tables.shared(),
    ask_deadline_ms: 5000,
    rate: support.roomy(),
    class_resources: class_resource_support.classes(),
    server_proxies: server_proxy_support.none(),
    zone_welcomes: zone_welcome_support.none(),
    vendors: vendor.none(),
    numbers: spawn_support.numbers,
    visibility: dict.new(),
    tutorial_chain: tutorial_support.none(),
    projector_landings: projector_support.none(),
    reused_unit_objectives: set.new(),
    stored_spawns: spawn_id.stored(ids: set.new()),
    arrival_objectives: set.new(),
    held_objectives: set.new(),
    script_rows: objective.no_rows(),
  )
}
