//// The six lines on which a load step stops keeping up, and the mark of a step
//// the load clients themselves limited (`genesis_prime/load_step`), each run on
//// a planted observation. Expected values come from the card's definition of
//// "stops keeping up".
//// - A player failure: any one.
//// - Login to world: 1 in 100 over 1,000 ms.
//// - Ping round trip: 1 in 100 over 500 ms, the client's own ping interval
////   (SendNetworkPings, at most once every 500 ms).
//// - A process's mailbox non-empty in every sample of the last 10 s.
//// - The store's workers waiting in every sample of the last 10 s.
//// - Any server error or warning line during the step.
//// - A step in which the load clients used over half their cores, or began a
////   player more than 500 ms late, is the clients' limit and not the server's.
//// Each line is shown failing, and passing at the value just below it.

import genesis_prime/load_sample.{type Sample, Sample, Waiting}
import genesis_prime/load_step.{
  type Observation, ClientsLimited, Failed, Kept, LoginToWorldSlow,
  MailboxBacklog, Observation, PingSlow, PlayerFailed, ServerLogLine,
  StoreBacklog,
}
import gleam/erlang/process
import gleam/int
import gleam/list
import owned_test

/// The whole numbers from `first` to `last`.
fn through(first: Int, last: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, last - first + 1), fn(_, offset) {
    first + offset
  })
}

/// A sample of a server that keeps up, taken `at_ms` into the step: nothing
/// waiting, no log lines, and 1 s of 4 s of scheduler time busy.
fn calm(at_ms: Int) -> Sample {
  Sample(
    at_ms:,
    connections: [10, 10, 10],
    waiting: [],
    largest_heap_words: 1000,
    memory_bytes: 1_000_000,
    busy_us: at_ms * 1000,
    total_us: at_ms * 4000,
    run_queue: 0,
    store_waiting: 0,
    worker_start_us: 50,
    log_lines: 0,
  )
}

/// Eleven samples one second apart, the first and the last 10 s apart.
fn seconds() -> List(Sample) {
  list.map(through(0, 10), fn(second) { calm(second * 1000) })
}

/// A step the server kept up with: no failure, a hundred logins and pings all
/// well under their limits, calm samples on both nodes.
fn kept() -> Observation {
  Observation(
    failures: 0,
    login_to_world_ms: list.repeat(200, 100),
    ping_round_trip_us: list.repeat(300, 100),
    server: seconds(),
    clients: seconds(),
    unconnected: 0,
    start_lag_ms: 0,
  )
}

pub fn a_calm_step_is_kept_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_step.judge(kept()) == Kept
}

pub fn one_player_failure_fails_the_step_and_none_passes_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_step.judge(Observation(..kept(), failures: 1))
    == Failed([PlayerFailed])
  assert load_step.judge(Observation(..kept(), failures: 0)) == Kept
}

pub fn two_logins_in_a_hundred_over_1000_ms_fail_and_one_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let slow = fn(over: Int) {
    Observation(
      ..kept(),
      login_to_world_ms: list.append(
        list.repeat(1001, over),
        list.repeat(1000, 100 - over),
      ),
    )
  }
  assert load_step.judge(slow(2)) == Failed([LoginToWorldSlow])
  assert load_step.judge(slow(1)) == Kept as "1 in 100 over is the limit"
}

pub fn two_pings_in_a_hundred_over_500_ms_fail_and_one_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let slow = fn(over: Int) {
    Observation(
      ..kept(),
      ping_round_trip_us: list.append(
        list.repeat(500_001, over),
        list.repeat(500_000, 100 - over),
      ),
    )
  }
  assert load_step.judge(slow(2)) == Failed([PingSlow])
  assert load_step.judge(slow(1)) == Kept as "1 in 100 over is the limit"
}

pub fn a_process_waiting_in_every_sample_of_the_last_10_s_fails_and_one_missing_once_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let stuck = process.spawn_unlinked(process.sleep_forever)
  let other = process.spawn_unlinked(process.sleep_forever)
  let waiting = fn(pid, at_ms) {
    Sample(..calm(at_ms), waiting: [
      Waiting(pid:, mailbox: 3, heap_words: 100, described: ""),
    ])
  }
  let always = list.map(through(0, 10), fn(s) { waiting(stuck, s * 1000) })
  assert load_step.judge(Observation(..kept(), server: always))
    == Failed([MailboxBacklog])
  let missed_once =
    list.map(through(0, 10), fn(second) {
      case second == 4 {
        True -> calm(second * 1000)
        False -> waiting(stuck, second * 1000)
      }
    })
  assert load_step.judge(Observation(..kept(), server: missed_once)) == Kept
    as "a mailbox that emptied once is a process that keeps up"
  let alternating =
    list.map(through(0, 10), fn(second) {
      waiting(
        case int.is_even(second) {
          True -> stuck
          False -> other
        },
        second * 1000,
      )
    })
  assert load_step.judge(Observation(..kept(), server: alternating)) == Kept
    as "two processes, each waiting in half the samples, are not one that never empties"
  process.kill(stuck)
  process.kill(other)
}

pub fn a_backlog_older_than_the_last_10_s_does_not_fail_the_step_test() -> Nil {
  use <- owned_test.run(5000)
  let stuck = process.spawn_unlinked(process.sleep_forever)
  let early =
    list.map(through(0, 20), fn(second) {
      case second < 5 {
        True ->
          Sample(..calm(second * 1000), waiting: [
            Waiting(pid: stuck, mailbox: 9, heap_words: 100, described: ""),
          ])
        False -> calm(second * 1000)
      }
    })
  assert load_step.judge(Observation(..kept(), server: early)) == Kept
  process.kill(stuck)
}

pub fn store_workers_waiting_in_every_sample_of_the_last_10_s_fail_and_one_empty_sample_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let queued = fn(second) { Sample(..calm(second * 1000), store_waiting: 2) }
  let always = list.map(through(0, 10), queued)
  assert load_step.judge(Observation(..kept(), server: always))
    == Failed([StoreBacklog])
  let drained_once =
    list.map(through(0, 10), fn(second) {
      case second == 7 {
        True -> calm(second * 1000)
        False -> queued(second)
      }
    })
  assert load_step.judge(Observation(..kept(), server: drained_once)) == Kept
}

pub fn one_error_or_warning_line_during_the_step_fails_it_and_none_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let lines = fn(count) {
    list.map(through(0, 10), fn(second) {
      case second == 10 {
        True -> Sample(..calm(second * 1000), log_lines: count)
        False -> calm(second * 1000)
      }
    })
  }
  assert load_step.judge(Observation(..kept(), server: lines(1)))
    == Failed([ServerLogLine])
  assert load_step.judge(Observation(..kept(), server: lines(0))) == Kept
}

pub fn a_step_whose_clients_used_over_half_their_cores_is_clients_limited_test() -> Nil {
  use <- owned_test.run(5000)
  let busy = fn(share_of_cores: Int) {
    [
      Sample(..calm(0), busy_us: 0, total_us: 0),
      Sample(
        ..calm(10_000),
        busy_us: 40_000 * share_of_cores,
        total_us: 4_000_000,
      ),
    ]
  }
  // The server also failed a line: the clients' limit comes first, since
  // their load may be what failed it.
  let failing = Observation(..kept(), failures: 1)
  assert load_step.judge(Observation(..failing, clients: busy(51)))
    == ClientsLimited
  assert load_step.judge(Observation(..failing, clients: busy(50)))
    == Failed([PlayerFailed])
    as "exactly half of their cores is not over half"
}

pub fn a_step_that_began_a_player_over_500_ms_late_is_clients_limited_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_step.judge(Observation(..kept(), start_lag_ms: 501))
    == ClientsLimited
  assert load_step.judge(Observation(..kept(), start_lag_ms: 500)) == Kept
}

pub fn a_player_the_machine_had_no_local_port_for_makes_the_step_clients_limited_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_step.judge(Observation(..kept(), unconnected: 1))
    == ClientsLimited
    as "eaddrnotavail: the clients' machine ran out of ports, which says nothing of the server"
}
