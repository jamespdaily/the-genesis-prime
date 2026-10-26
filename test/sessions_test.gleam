//// The registry of the game sessions: one live connection for each account. A
//// new connection takes its account's slot, tells the connection that held it
//// to end and waits for it to end; a connection that ends frees its slot by
//// itself; two accounts do not affect each other. The expected values are the
//// design the world issue records (one process knows the account's live game
//// connection and monitors it; the wait is in the new connection, within a
//// deadline) and designing-processes (cleanup that must happen runs in a
//// process that monitors the dying one; peers never call each other
//// synchronously). Each test starts a registry of its own under a name of its
//// own.

import genesis_prime/game/sessions.{PreviousNotEnding, RegistryNotAnswering}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor
import owned_test

/// How long a test waits for what must happen at once, in milliseconds.
const event_wait_ms = 5000

fn start_registry() -> Name(sessions.Message) {
  let name = process.new_name("sessions")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(sessions.supervised(name))
    |> static_supervisor.start
    as "the registry did not start"
  name
}

/// What a connection does when it is told to end.
type OnNotice {
  Ends
  Ignores
}

/// A process that plays a game connection: it takes its account's slot, says
/// how that went and what it did when it was told to end.
type Connection {
  Connection(
    pid: Pid,
    claimed: Subject(Result(Nil, sessions.NotFreed)),
    told: Subject(Nil),
  )
}

fn connect(
  registry registry: Name(sessions.Message),
  account_id account_id: Int,
  on_notice on_notice: OnNotice,
  within_ms within_ms: Int,
) -> Connection {
  let claimed = process.new_subject()
  let told = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let notice = process.new_subject()
      process.send(
        claimed,
        sessions.take_over(registry:, account_id:, notice:, within_ms:),
      )
      case process.receive_forever(notice) {
        sessions.TakeOver -> {
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

pub fn the_first_connection_of_an_account_takes_the_slot_and_is_told_of_no_one_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry()
  let first =
    connect(registry:, account_id: 7, on_notice: Ends, within_ms: event_wait_ms)
  assert heard(first.claimed) == Some(Ok(Nil))
    as "an account with no connection has its slot free"
}

pub fn a_second_connection_of_the_account_ends_the_first_and_then_has_the_slot_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry()
  let first =
    connect(registry:, account_id: 7, on_notice: Ends, within_ms: event_wait_ms)
  assert heard(first.claimed) == Some(Ok(Nil)) as "the first took the slot"
  let second =
    connect(registry:, account_id: 7, on_notice: Ends, within_ms: event_wait_ms)
  assert heard(first.told) == Some(Nil)
    as "the world issue: a second login first tells the old connection to end"
  assert heard(second.claimed) == Some(Ok(Nil))
    as "the second has the slot once the first has ended"
  assert ended(first.pid)
    as "the first connection is gone when the second is answered"
}

pub fn a_connection_that_does_not_end_in_time_leaves_the_slot_untaken_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry()
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
    )
  assert heard(first.claimed) == Some(Ok(Nil))
  let second =
    connect(registry:, account_id: 7, on_notice: Ends, within_ms: 300)
  assert heard(second.claimed) == Some(Error(PreviousNotEnding))
    as "designing-processes: the wait carries a deadline, so a connection that does not end is an answer and not a hang"
}

pub fn the_slot_is_freed_when_a_connection_dies_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry()
  let first =
    connect(
      registry:,
      account_id: 7,
      on_notice: Ignores,
      within_ms: event_wait_ms,
    )
  assert heard(first.claimed) == Some(Ok(Nil))
  process.kill(first.pid)
  assert ended(first.pid)
  let second =
    connect(registry:, account_id: 7, on_notice: Ends, within_ms: event_wait_ms)
  assert heard(second.claimed) == Some(Ok(Nil))
    as "the slot of a connection that died is free"
  assert process.receive(first.told, 0) == Error(Nil)
    as "a connection that is gone is told nothing"
}

pub fn connections_of_different_accounts_do_not_affect_each_other_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = start_registry()
  let one =
    connect(
      registry:,
      account_id: 1,
      on_notice: Ignores,
      within_ms: event_wait_ms,
    )
  assert heard(one.claimed) == Some(Ok(Nil))
  let two =
    connect(
      registry:,
      account_id: 2,
      on_notice: Ignores,
      within_ms: event_wait_ms,
    )
  assert heard(two.claimed) == Some(Ok(Nil))
    as "another account's slot is free whatever the first account holds"
  assert process.receive(one.told, 100) == Error(Nil)
    && process.receive(two.told, 0) == Error(Nil)
    as "no connection of another account is told to end"
}

pub fn a_registry_that_is_not_running_is_an_answer_and_not_a_crash_test() -> Nil {
  use <- owned_test.run(30_000)
  let registry = process.new_name("no_sessions")
  let notice = process.new_subject()
  assert sessions.take_over(registry:, account_id: 7, notice:, within_ms: 100)
    == Error(RegistryNotAnswering)
    as "designing-processes: a request to a process that is away is an outside failure the asker handles"
}
