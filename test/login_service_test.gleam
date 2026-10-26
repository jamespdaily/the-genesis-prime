//// The login's subtree of the supervision tree. Expected values come from the
//// supervision issue's settings (a service subtree is one for one with 3
//// restarts in 5 seconds, as `server.supervisor()` states for the top level;
//// see `supervision_test`) and from the designing-processes skill: one
//// process owns each piece of state, so the game tokens and the session keys
//// are two processes, and a fault in one does not touch the other's keys.

import genesis_prime/database/pool
import genesis_prime/login/account.{type Identity, Identity}
import genesis_prime/login/guid
import genesis_prime/login/handoff.{Unknown}
import genesis_prime/login/service
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import genesis_prime/shutdown
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/static_supervisor
import gleam/string
import login_clock
import owned_test
import supervisor_children
import supervisor_flags.{Flags}

const expiry_milliseconds = 1000

fn identity() -> Identity {
  let assert Ok(user_id) = guid.from_wire(<<0:size(128)>>) as "16 bytes"
  Identity(id: 7, name: "jim", user_id:)
}

/// The subtree's settings: hand-offs on the test's clock, and both listeners on
/// free ports, which they report once open.
fn settings(
  clock: login_clock.Clock,
  ports: process.Subject(#(String, Int)),
) -> service.Settings {
  let defaults =
    service.settings(
      sts_port: 0,
      auth_port: 0,
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      realm_name: "Nexus",
      expected_files_digest: option.None,
    )
  service.Settings(
    ..defaults,
    game_tokens: handoff.Settings(
      name: process.new_name("login_service_game_tokens"),
      expiry_milliseconds:,
      clock: fn() { login_clock.read(clock) },
    ),
    session_keys: handoff.Settings(
      name: process.new_name("login_service_session_keys"),
      expiry_milliseconds:,
      clock: fn() { login_clock.read(clock) },
    ),
    sts: service.Port(number: 0, opened: fn(port) {
      process.send(ports, #("sts", port))
    }),
    auth: service.Port(number: 0, opened: fn(port) {
      process.send(ports, #("auth", port))
    }),
  )
}

/// The pool the subtree reads accounts through. Nothing here logs in, so the
/// pool is only named and never queried.
fn pool_settings() -> pool.Settings {
  pool.Settings(
    name: process.new_name("login_service_pool"),
    host: "localhost",
    port: 5432,
    database: "none",
    user: "none",
    password: option.None,
    pool_size: 1,
  )
}

/// Starts a planted top supervisor holding the login subtree and the shutdown
/// coordinator its listeners register with.
fn start(settings: service.Settings) -> process.Pid {
  let coordinator =
    shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000)
  let assert Ok(started) =
    server.supervisor()
    |> static_supervisor.add(shutdown.supervised(coordinator))
    |> static_supervisor.add(service.supervised(
      settings:,
      pool: pool_settings(),
      shutdown: coordinator,
    ))
    |> static_supervisor.start
    as "the planted top supervisor did not start"
  started.pid
}

/// The pid of the login subtree, the second child of the planted top.
fn subtree(top: process.Pid) -> process.Pid {
  let assert [_coordinator, subtree] = supervisor_children.in_start_order(top)
    as "the top holds the shutdown coordinator and the login subtree"
  subtree
}

pub fn the_login_subtree_is_one_for_one_with_three_restarts_in_five_seconds_test() -> Nil {
  use <- owned_test.run(5000)
  let top = start(settings(login_clock.new(), process.new_subject()))
  assert supervisor_flags.read(subtree(top))
    == Flags(strategy: static_supervisor.OneForOne, intensity: 3, period: 5)
    as "the supervision issue: a service subtree is one for one with 3 restarts in 5 seconds"
}

pub fn the_subtree_runs_the_hand_offs_and_then_the_two_listeners_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = settings(login_clock.new(), process.new_subject())
  let top = start(settings)
  let children = supervisor_children.in_start_order(subtree(top))
  assert list.length(children) == 4
    as "designing-processes: one process owns each piece of state, so the game tokens and the session keys are two, and the STS and the auth listener are two more"
  let assert [game_tokens, session_keys, ..] = children as "four children"
  assert process.named(settings.game_tokens.name) == Ok(game_tokens)
    as "the game tokens' hand-off starts first, so the first client finds it"
  assert process.named(settings.session_keys.name) == Ok(session_keys)
    as "the session keys' hand-off starts second"
}

pub fn the_hand_offs_hold_their_own_keys_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = settings(login_clock.new(), process.new_subject())
  let _top = start(settings)
  let token = handoff.issue(settings.game_tokens.name, identity())
  let key = handoff.issue(settings.session_keys.name, identity())
  assert handoff.redeem(settings.session_keys.name, token) == Error(Unknown)
    as "a game token is not a session key: each hand-off holds its own"
  assert handoff.redeem(settings.game_tokens.name, token) == Ok(identity())
    as "opcode.0x592: the game token is redeemed by the auth login"
  assert handoff.redeem(settings.session_keys.name, key) == Ok(identity())
    as "opcode.0x58f: the session key is redeemed by the game server"
}

pub fn both_listeners_open_their_own_port_test() -> Nil {
  use <- owned_test.run(5000)
  let ports = process.new_subject()
  let _top = start(settings(login_clock.new(), ports))
  let assert Ok(first) = process.receive(ports, 2000)
    as "a listener did not report its port"
  let assert Ok(second) = process.receive(ports, 2000)
    as "the other listener did not report its port"
  let reported =
    list.sort([first, second], fn(left, right) {
      string.compare(left.0, right.0)
    })
  let assert [#("auth", auth_port), #("sts", sts_port)] = reported
    as "one listener serves the auth login and one the STS login"
  assert auth_port != sts_port as "two listeners on one machine hold two ports"
}
