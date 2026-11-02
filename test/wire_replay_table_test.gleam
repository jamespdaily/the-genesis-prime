//// The replay's table (dev/genesis_prime/wire_replay/table): what the shells and
//// the client share, answered one command at a time. Expected values come from
//// these places.
//// - The table's contract in the doc comments of
////   `genesis_prime/wire_replay/table` and `genesis_prime/wire_replay`: a timer
////   start is delivered once, to the client wait that asks for it, whichever
////   of the two reaches the table first; a replay whose table ends fails as a
////   replay failure and never as the crash of a call.
//// - Erlang orders signals per sender, so a test that sends the table two
////   commands from one process knows the table takes them in that order.

import genesis_prime/step.{type Now, Now}
import genesis_prime/wire_recording.{Accepted, Client, PeerClosed}
import genesis_prime/wire_replay
import genesis_prime/wire_replay/table as replay_table
import gleam/erlang/process
import gleam/erlang/reference
import owned_test
import recording_support
import replay_rule
import wire_replay_support as support

/// How long a wait that must end with nothing lasts, in milliseconds: the table
/// answers at once, so a start that was kept would have come long before.
const quiet_ms = 500

fn file() -> String {
  "replay_rule-0.jsonl"
}

fn at(n: Int) -> Now {
  Now(monotonic_ms: n, filetime: n * 10)
}

/// A session of one connection that is accepted and closes.
fn write_session(folder: String) -> Nil {
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "replay_rule", seed: support.seed(1), ordinal: 1),
    ],
    steps: [
      support.In(0, at(1), Accepted),
      support.In(0, at(2), PeerClosed),
      support.Closed(0, Client),
    ],
  )
}

pub fn a_timer_start_a_waiting_client_took_is_not_kept_for_the_next_wait_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  write_session(folder)
  let replay = support.start_replay(support.load(folder))
  let table = process.named_subject(replay.table.name)
  // A wait with no time left still holds its place in the table, so the next
  // start of timer 1 is delivered to it, as a start is to a wait that is there
  // when it comes.
  assert replay_table.await_timer(
      table:,
      connection: file(),
      timer: 1,
      within_ms: 0,
    )
    == Error(replay_table.NotInTime)
    as "nothing has started timer 1"
  replay_table.timer_started(
    table:,
    connection: file(),
    timer: 1,
    started: replay_table.Started(
      subject: process.new_subject(),
      reference: reference.new(),
    ),
  )
  assert replay_table.await_timer(
      table:,
      connection: file(),
      timer: 1,
      within_ms: quiet_ms,
    )
    == Error(replay_table.NotInTime)
    as "the start went to the wait that was there, so the rule's next start of the timer is the next one a wait gets"
  let _lines = wire_replay.finish(replay)
  Nil
}

pub fn a_replay_whose_table_process_ends_fails_as_a_replay_failure_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  write_session(folder)
  let #(result, _logged) =
    support.run_scripted(
      folder:,
      rule: replay_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      with: fn(builder) { builder },
      actions: wire_replay.plan,
      scripts: fn(replay) { replay.scripts },
      after_start: fn(_server, replay) {
        // The table's supervisor starts another, which knows no connection.
        let assert Ok(pid) = process.named(replay.table.name)
          as "the table is running"
        process.kill(pid)
      },
    )
  assert result == Error(wire_replay.TableLost)
    as "the client's next call to the table found it gone, and the replay says so"
}
