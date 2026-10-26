//// The login's subtree of the supervision tree. Expected values come from the
//// supervision issue's settings (a service subtree is one for one with 3
//// restarts in 5 seconds, as `server.supervisor()` states for the top level;
//// see `supervision_test`) and from the designing-processes skill: one
//// process owns each piece of state, so the game tokens and the session keys
//// are two processes, and a fault in one does not touch the other's keys.

import genesis_prime/login/account.{type Identity, Identity}
import genesis_prime/login/guid
import genesis_prime/login/handoff.{Unknown}
import genesis_prime/login/service
import gleam/erlang/process
import gleam/list
import gleam/otp/static_supervisor
import login_clock
import owned_test
import supervisor_children
import supervisor_flags.{Flags}

const expiry_milliseconds = 1000

fn identity() -> Identity {
  let assert Ok(user_id) = guid.from_wire(<<0:size(128)>>) as "16 bytes"
  Identity(name: "jim", user_id:)
}

fn settings(clock: login_clock.Clock) -> service.Settings {
  service.Settings(
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
  )
}

pub fn the_login_subtree_is_one_for_one_with_three_restarts_in_five_seconds_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(service.supervised(settings(login_clock.new())))
    |> static_supervisor.start
    as "the planted top supervisor did not start"
  let assert [subtree] = supervisor_children.in_start_order(started.pid)
    as "the top holds the login subtree"
  assert supervisor_flags.read(subtree)
    == Flags(strategy: static_supervisor.OneForOne, intensity: 3, period: 5)
    as "the supervision issue: a service subtree is one for one with 3 restarts in 5 seconds"
}

pub fn the_subtree_runs_the_game_tokens_and_the_session_keys_as_two_processes_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = settings(login_clock.new())
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(service.supervised(settings))
    |> static_supervisor.start
    as "the planted top supervisor did not start"
  let assert [subtree] = supervisor_children.in_start_order(started.pid)
    as "the top holds the login subtree"
  assert list.length(supervisor_children.in_start_order(subtree)) == 2
    as "designing-processes: one process owns each piece of state, and the game tokens and the session keys are two"
  let token = handoff.issue(settings.game_tokens.name, identity())
  let key = handoff.issue(settings.session_keys.name, identity())
  assert handoff.redeem(settings.session_keys.name, token) == Error(Unknown)
    as "a game token is not a session key: each hand-off holds its own"
  assert handoff.redeem(settings.game_tokens.name, token) == Ok(identity())
    as "opcode.0x592: the game token is redeemed by the auth login"
  assert handoff.redeem(settings.session_keys.name, key) == Ok(identity())
    as "opcode.0x58f: the session key is redeemed by the game server"
}
