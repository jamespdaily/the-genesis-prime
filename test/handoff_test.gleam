//// The hand-offs that carry a login from one connection to the next: the
//// game token the STS login issues and the auth login redeems in 0x592, and
//// the session key the auth login issues and the game server redeems in 0x58F
//// (opcode.0x592, opcode.0x58f). Expected values come from the login issue's
//// test list (test 5): a key is 16 bytes from `crypto:strong_rand_bytes`,
//// held until redeemed once, and refused when expired or unknown, the expiry
//// being a start argument; and from the opcode records: a game token is the
//// second GUID of 0x592 and a session key is the GUID of 0x3db and 0x58f, 16
//// bytes each. The clock is the test's own (`login_clock`), moved by hand.

import genesis_prime/login/account.{type Identity, Identity}
import genesis_prime/login/guid
import genesis_prime/login/handoff.{Expired, Unknown}
import gleam/bit_array
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import login_clock
import owned_test

const expiry_milliseconds = 1000

const event_wait_ms = 1000

fn identity(name: String) -> Identity {
  let assert Ok(user_id) = guid.from_wire(<<0:size(128)>>) as "16 bytes"
  Identity(id: 7, name:, user_id:)
}

/// A hand-off under a supervisor of the test, on the test's clock, and the
/// name its users find it by.
fn started(clock: login_clock.Clock) -> Name(handoff.Message(Identity)) {
  let name = process.new_name("handoff_test")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(
      handoff.supervised(
        handoff.Settings(name:, expiry_milliseconds:, clock: fn() {
          login_clock.read(clock)
        }),
      ),
    )
    |> static_supervisor.start
    as "the supervisor of the hand-off did not start"
  name
}

pub fn a_key_is_sixteen_bytes_and_no_two_are_alike_test() -> Nil {
  use <- owned_test.run(5000)
  let name = started(login_clock.new())
  let first = handoff.issue(name, identity("jim"))
  let second = handoff.issue(name, identity("jim"))
  assert bit_array.byte_size(first) == 16
    as "opcode.0x3db and opcode.0x58f: the session key is 16 bytes (a GUID)"
  assert bit_array.byte_size(second) == 16
    as "opcode.0x592: the game token is a GUID, 16 bytes"
  assert first != second
    as "16 bytes from crypto:strong_rand_bytes do not repeat (2^-128 for a pair)"
}

pub fn a_key_is_redeemed_for_what_it_was_issued_for_test() -> Nil {
  use <- owned_test.run(5000)
  let name = started(login_clock.new())
  let key = handoff.issue(name, identity("jim"))
  assert handoff.redeem(name, key) == Ok(identity("jim"))
    as "the login issue's test 5: the key is held for the next connection to check"
}

pub fn a_key_is_redeemed_once_test() -> Nil {
  use <- owned_test.run(5000)
  let name = started(login_clock.new())
  let key = handoff.issue(name, identity("jim"))
  let assert Ok(_) = handoff.redeem(name, key) as "the first redemption"
  assert handoff.redeem(name, key) == Error(Unknown)
    as "the login issue: the game token is used once; a second use is a key that is not held"
}

pub fn a_key_that_was_never_issued_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let name = started(login_clock.new())
  let _key = handoff.issue(name, identity("jim"))
  assert handoff.redeem(name, <<9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9>>)
    == Error(Unknown)
    as "the login issue's test 5: an unknown key is refused"
}

pub fn a_key_is_valid_until_its_expiry_and_expired_at_it_test() -> Nil {
  use <- owned_test.run(5000)
  let clock = login_clock.new()
  let name = started(clock)
  let before = handoff.issue(name, identity("before"))
  let at = handoff.issue(name, identity("at"))
  login_clock.set(clock, expiry_milliseconds - 1)
  assert handoff.redeem(name, before) == Ok(identity("before"))
    as "the login issue's test 5: a key expires after the set time, the start argument, so one a millisecond short of it is valid"
  login_clock.set(clock, expiry_milliseconds)
  assert handoff.redeem(name, at) == Error(Expired)
    as "the login issue's test 5: a key whose time has passed is refused"
}

pub fn an_expiry_counts_from_the_time_the_key_was_issued_test() -> Nil {
  use <- owned_test.run(5000)
  let clock = login_clock.new()
  let name = started(clock)
  login_clock.set(clock, 5000)
  let key = handoff.issue(name, identity("jim"))
  login_clock.set(clock, 5000 + expiry_milliseconds - 1)
  assert handoff.redeem(name, key) == Ok(identity("jim"))
    as "the login issue's test 5: the expiry is a time after the issue, and the monotonic clock's zero is arbitrary"
}

pub fn an_expired_key_is_dropped_when_the_next_key_is_issued_test() -> Nil {
  use <- owned_test.run(5000)
  let clock = login_clock.new()
  let name = started(clock)
  let stale = handoff.issue(name, identity("stale"))
  login_clock.set(clock, expiry_milliseconds * 5)
  let _key = handoff.issue(name, identity("fresh"))
  assert handoff.redeem(name, stale) == Error(Unknown)
    as "designing-processes: a producer never outruns its consumer, so keys that nobody redeemed do not pile up: issuing drops the expired"
}

pub fn a_hand_off_that_restarts_holds_no_keys_test() -> Nil {
  use <- owned_test.run(5000)
  let clock = login_clock.new()
  let name = process.new_name("handoff_restart_test")
  let starts = process.new_subject()
  let spec =
    handoff.supervised(
      handoff.Settings(name:, expiry_milliseconds:, clock: fn() {
        login_clock.read(clock)
      }),
    )
  let reporting =
    supervision.worker(fn() { report_start(spec, starts) })
    |> supervision.timeout(1000)
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(reporting)
    |> static_supervisor.start
    as "the supervisor of the hand-off did not start"
  let assert Ok(first) = process.receive(starts, event_wait_ms)
    as "the hand-off did not report its start"
  let key = handoff.issue(name, identity("jim"))
  process.kill(first)
  let assert Ok(second) = process.receive(starts, event_wait_ms)
    as "the supervisor did not restart the hand-off"
  assert second != first as "a restart is a new process"
  assert handoff.redeem(name, key) == Error(Unknown)
    as "designing-processes: a restart rebuilds the state from nothing, so a login in flight fails and the client logs in again"
}

fn report_start(
  spec: supervision.ChildSpecification(Subject(handoff.Message(Identity))),
  starts: Subject(Pid),
) -> Result(actor.Started(Subject(handoff.Message(Identity))), actor.StartError) {
  use started <- result.map(spec.start())
  process.send(starts, started.pid)
  started
}
