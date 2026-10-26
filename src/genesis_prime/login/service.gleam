//// The login's subtree of the supervision tree: the two hand-offs the
//// connections of the login share, one for the game tokens and one for the
//// session keys, and the two listeners that serve the login, the STS service
//// the client logs in to first and the auth server it connects to after. The
//// hand-offs start first, so a listener's first client finds them. It is one
//// for one with 3 restarts in 5 seconds, like the top level, so a fault that
//// survives three rebuilds stops the subtree and reaches the top. Each
//// listener registers with the shutdown coordinator, which stops it
//// accepting and closes its connections in order.

import genesis_prime/connection/clock
import genesis_prime/connection/listener
import genesis_prime/database/pool
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/auth_connection
import genesis_prime/login/auth_session
import genesis_prime/login/handoff
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{type Endpoint}
import genesis_prime/shutdown
import gleam/erlang/process
import gleam/option.{type Option}
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// A port a listener opens: the number, where 0 takes a free port, and what to
/// call with the port that is open.
pub type Port {
  Port(number: Int, opened: fn(Int) -> Nil)
}

/// What the subtree starts with: the settings of each hand-off, the port of
/// each listener, and what the auth login hands a client to.
pub type Settings {
  Settings(
    game_tokens: handoff.Settings(Identity),
    session_keys: handoff.Settings(Identity),
    sts: Port,
    auth: Port,
    auth_login: auth_session.Settings,
  )
}

/// How long a game token and a session key stay valid after they are issued,
/// in milliseconds. The client opens the auth connection as soon as the STS
/// login gives it the token (HandleNcPlatformEvent 0x140037220, event 14) and
/// opens the game connection as soon as the hand-off arrives (HandleMessage03DB),
/// so a minute is far above any client; no measurement chose it.
const key_expiry_ms = 60_000

/// Settings for a login on the given ports that hands a client to
/// `game_server` under `realm_name`: the hand-offs get names of their own made
/// here, the monotonic clock and `key_expiry_ms`, and each port reports
/// nothing when it opens. `expected_files_digest` is the digest of the
/// client's files the login logs a difference from, none to skip the check.
pub fn settings(
  sts_port sts_port: Int,
  auth_port auth_port: Int,
  game_server game_server: Endpoint,
  realm_name realm_name: String,
  expected_files_digest expected_files_digest: Option(Int),
) -> Settings {
  Settings(
    game_tokens: handoff.Settings(
      name: process.new_name("game_tokens"),
      expiry_milliseconds: key_expiry_ms,
      clock: clock.monotonic_milliseconds,
    ),
    session_keys: handoff.Settings(
      name: process.new_name("session_keys"),
      expiry_milliseconds: key_expiry_ms,
      clock: clock.monotonic_milliseconds,
    ),
    sts: Port(number: sts_port, opened: fn(_port) { Nil }),
    auth: Port(number: auth_port, opened: fn(_port) { Nil }),
    auth_login: auth_session.Settings(
      game_server:,
      realm_name:,
      expected_files_digest:,
    ),
  )
}

/// The login's subtree as a child of the top supervisor. `pool` is the pool
/// the accounts are read through, and `shutdown` the coordinator the
/// listeners and their connections register with.
pub fn supervised(
  settings settings: Settings,
  pool pool: pool.Settings,
  shutdown shutdown: shutdown.Settings,
) -> supervision.ChildSpecification(Supervisor) {
  let sts_services =
    sts_connection.services(
      connection: pool.connection(pool),
      game_tokens: settings.game_tokens.name,
    )
  let auth_services =
    auth_connection.services(
      game_tokens: settings.game_tokens.name,
      session_keys: settings.session_keys.name,
    )
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
  |> static_supervisor.add(handoff.supervised(settings.game_tokens))
  |> static_supervisor.add(handoff.supervised(settings.session_keys))
  |> static_supervisor.add(listener.supervised(
    listener.Settings(
      ..listener.protocol_settings(
        port: settings.sts.number,
        protocol: sts_connection.protocol(sts_services),
        shutdown:,
      ),
      listening: settings.sts.opened,
    ),
  ))
  |> static_supervisor.add(listener.supervised(
    listener.Settings(
      ..listener.protocol_settings(
        port: settings.auth.number,
        protocol: auth_connection.protocol(
          services: auth_services,
          settings: settings.auth_login,
        ),
        shutdown:,
      ),
      listening: settings.auth.opened,
    ),
  ))
  |> static_supervisor.supervised
}
