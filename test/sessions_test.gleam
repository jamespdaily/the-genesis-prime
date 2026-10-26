//// The registry of the game sessions: every holder of an account stays
//// tracked until it goes down, a claim tells every live holder to end and is
//// answered only when none of them is alive, a holder that has not gone down
//// within the eviction deadline is killed, and a claimant that times out or
//// dies leaves its claim for the registry to remove. The expected values are
//// the design the world issue records (one process knows the account's live
//// game connection and monitors it; the wait is in the new connection, within
//// a deadline; the registry kills what does not end) and designing-processes
//// (cleanup that must happen runs in a process that monitors the dying one;
//// peers never call each other synchronously). Each test starts a registry of
//// its own under a name of its own, and each answer to a claim is checked for
//// the old connections' death by the claimant itself, the moment it is
//// answered.

import genesis_prime/connection/clock
import genesis_prime/game/service as game_service
import genesis_prime/game/sessions.{PreviousNotEnding, RegistryNotAnswering}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor
import map_support
import owned_test

/// How long a test waits for what must happen at once, in milliseconds.
const event_wait_ms = 5000

/// The eviction deadline of the registries the tests start, in milliseconds.
/// Short, so a test of the kill does not wait; the tests that must not reach it
/// give a longer one.
const short_eviction_ms = 300

fn start_registry(eviction_ms eviction_ms: Int) -> Name(sessions.Message) {
  let name = process.new_name("sessions")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(sessions.supervised(name:, eviction_ms:))
    |> static_supervisor.start
    as "the registry did not start"
  name
}

/// What a connection does when it is told to end.
type OnNotice {
  Ends
  Ignores
}

/// What a claimant knew the moment its claim was answered: how it went, which
/// of the connections it was asked to watch were alive, and how long the claim
/// took.
type Claimed {
  Claimed(
    result: Result(Nil, sessions.NotFreed),
    alive: List(Pid),
    elapsed_ms: Int,
  )
}

/// A process that plays a game connection: it takes its account's slot, says
/// how that went and which of the connections in `watching` were alive at that
/// moment, and, as a connection that did not get the slot does, ends when it
/// did not. Once it has the slot it ends or ignores the notice that it is told
/// to end.
type Connection {
  Connection(pid: Pid, claimed: Subject(Claimed), told: Subject(Nil))
}

fn connect(
  registry registry: Name(sessions.Message),
  account_id account_id: Int,
  on_notice on_notice: OnNotice,
  within_ms within_ms: Int,
  watching watching: List(Pid),
) -> Connection {
  let claimed = process.new_subject()
  let told = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let notice = process.new_subject()
      let started = clock.monotonic_milliseconds()
      let result =
        sessions.take_over(registry:, account_id:, notice:, within_ms:)
      process.send(
        claimed,
        Claimed(
          result:,
          alive: list.filter(watching, process.is_alive),
          elapsed_ms: clock.monotonic_milliseconds() - started,
        ),
      )
      case result {
        Error(sessions.RegistryNotAnswering)
        | Error(sessions.PreviousNotEnding) -> Nil
        Ok(Nil) -> {
          let sessions.TakeOver = process.receive_forever(notice)
          process.send(told, Nil)
          case on_notice {
            Ends -> Nil
            Ignores -> process.sleep_forever()
          }
        }
      }
    })
  Connection(pid:, claimed:, told:)
}

fn ended(pid: Pid) -> Bool {
  let monitor = process.monitor(pid)
  let outcome =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { True })
    |> process.selector_receive(within: event_wait_ms)
  outcome == Ok(True)
}

fn heard(subject: Subject(a)) -> Option(a) {
  case process.receive(subject, event_wait_ms) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

/// How the claim of a connection went, waiting for the answer.
fn result_of(connection: Connection) -> Option(Result(Nil, sessions.NotFreed)) {
  option.map(heard(connection.claimed), fn(claimed) { claimed.result })
}

/// The connections of those watched that were alive when the claim was
/// answered, waiting for the answer.
fn alive_at_the_answer(connection: Connection) -> Option(List(Pid)) {
  option.map(heard(connection.claimed), fn(claimed) { claimed.alive })
}

pub fn the_first_connection_of_an_account_takes_the_slot_and_is_told_of_no_one_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: short_eviction_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil))
    as "an account with no connection has its slot free"
}

pub fn a_second_connection_of_the_account_ends_the_first_and_then_has_the_slot_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: event_wait_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid],
    )
  assert heard(first.told) == Some(Nil)
    as "the world issue: a second login first tells the old connection to end"
  assert result_of(second) == Some(Ok(Nil))
    as "the second has the slot once the first has ended"
}

pub fn the_old_connection_is_dead_at_the_moment_the_new_one_is_answered_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: event_wait_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid],
    )
  assert alive_at_the_answer(second) == Some([])
    as "the world issue: a claimant is answered only when no other holder of the account is alive, checked by the claimant as it is answered"
}

pub fn a_holder_that_does_not_end_by_the_eviction_deadline_is_killed_and_the_claimant_has_the_slot_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: short_eviction_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid],
    )
  let assert Some(claimed) = heard(second.claimed)
    as "the second was answered: the registry kills what does not end, so the claimant always gets the slot"
  assert claimed.result == Ok(Nil)
  assert claimed.alive == []
    as "the old connection is dead when the new one is answered"
  assert heard(first.told) == Some(Nil)
    as "the old connection was told to end first, and ignored it"
  assert claimed.elapsed_ms >= short_eviction_ms
    as "the registry gives the connection the whole eviction deadline before it kills it"
}

pub fn a_claim_that_gets_no_answer_in_time_leaves_the_old_holder_tracked_and_the_next_claim_ends_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: 1500)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: 300,
      watching: [],
    )
  assert result_of(second) == Some(Error(PreviousNotEnding))
    as "designing-processes: the wait carries a deadline, so a connection that does not end is an answer and not a hang"
  let third =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid],
    )
  assert alive_at_the_answer(third) == Some([])
    as "the first holder is still tracked after the second gave up, so the third claim ends it: it is never left alive and untracked"
}

pub fn a_claim_answered_after_its_claimant_gave_up_does_not_leave_the_old_holder_untracked_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: short_eviction_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let assert Ok(registry_pid) = process.named(registry)
    as "the registry is registered"
  // The registry does not run while the second connection waits for its
  // answer, so the second gives up; the registry then takes the claim late.
  map_support.suspend(registry_pid)
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: 200,
      watching: [],
    )
  let assert Some(Error(_)) = result_of(second)
    as "the second connection gave up, as one whose registry does not answer does"
  map_support.resume(registry_pid)
  let third =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid, second.pid],
    )
  assert alive_at_the_answer(third) == Some([])
    as "the old connection and the one that gave up are dead when the third is answered"
  assert heard(first.told) == Some(Nil)
    as "a claim the registry took late still told the old connection to end"
}

pub fn two_logins_in_a_chain_leave_no_connection_alive_when_the_last_is_answered_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: 500)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid],
    )
  assert heard(first.told) == Some(Nil) as "the second claim told the first"
  let third =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid, second.pid],
    )
  assert alive_at_the_answer(third) == Some([])
    as "the third is answered when both the first and the second are dead: a third login is never let in while an older connection of the account lives"
  // The second was told to end by the third's claim too, with an eviction
  // deadline of its own, a little after the first's. So either the first's end
  // answered it before that deadline and it ended by itself, or its deadline
  // killed it while it waited. The third is answered only when the second is
  // down, and the second's report was sent before it went down, so it is
  // already here.
  case process.receive(second.claimed, 0) {
    Ok(claimed) -> {
      assert claimed.result == Ok(Nil)
        as "the second was answered: it took the slot once the first was down"
      assert claimed.alive == []
        as "the second is answered only when the first is dead"
      Nil
    }
    Error(Nil) -> {
      assert ended(second.pid)
        as "the second was never answered, so it was killed at its eviction deadline while it waited"
      Nil
    }
  }
}

pub fn a_claimant_that_dies_while_it_waits_leaves_no_claim_for_the_next_one_to_wait_for_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: 600)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert heard(first.told) == Some(Nil)
    as "the second claim is in the registry: the first was told to end"
  process.kill(second.pid)
  assert ended(second.pid)
  let third =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: event_wait_ms,
      watching: [first.pid, second.pid],
    )
  let assert Some(claimed) = heard(third.claimed) as "the third was answered"
  assert claimed.result == Ok(Nil)
    as "the registry removed the dead claimant on its end, so the third does not wait for it for ever"
  assert claimed.alive == []
    as "the old connection was killed at the eviction deadline and the claimant that died is gone"
}

pub fn the_slot_is_freed_when_a_connection_dies_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: event_wait_ms)
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(first) == Some(Ok(Nil))
  process.kill(first.pid)
  assert ended(first.pid)
  let second =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ends,
      within_ms: 2000,
      watching: [],
    )
  assert result_of(second) == Some(Ok(Nil))
    as "the registry removes a holder that is down, so the slot of a connection that died is free"
  assert process.receive(first.told, 0) == Error(Nil)
    as "a connection that is gone is told nothing"
}

pub fn connections_of_different_accounts_do_not_affect_each_other_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry(eviction_ms: short_eviction_ms)
  let one =
    connect(
      registry:,
      account_id: 1,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(one) == Some(Ok(Nil))
  let two =
    connect(
      registry:,
      account_id: 2,
      on_notice: Ignores,
      within_ms: event_wait_ms,
      watching: [],
    )
  assert result_of(two) == Some(Ok(Nil))
    as "another account's slot is free whatever the first account holds"
  assert process.receive(one.told, 100) == Error(Nil)
    && process.receive(two.told, 0) == Error(Nil)
    as "no connection of another account is told to end"
  assert process.is_alive(one.pid) && process.is_alive(two.pid)
    as "no connection of another account is killed"
}

pub fn a_registry_that_is_not_running_is_an_answer_and_not_a_crash_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = process.new_name("no_sessions")
  let notice = process.new_subject()
  assert sessions.take_over(registry:, account_id: 7, notice:, within_ms: 100)
    == Error(RegistryNotAnswering)
    as "designing-processes: a request to a process that is away is an outside failure the asker handles"
}

pub fn the_deadlines_of_a_second_login_are_ordered_so_each_comes_before_the_next_gives_up_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_service.leave_deadline_ms < game_service.eviction_deadline_ms
    as "the old connection leaves the map politely within a deadline shorter than the eviction deadline, so the registry kills only a connection that did not"
  assert game_service.claim_deadline_ms
    >= game_service.eviction_deadline_ms + 1000
    as "the new connection waits longer than the eviction deadline and a margin of a second, so the registry's kill comes before the claimant gives up"
}
