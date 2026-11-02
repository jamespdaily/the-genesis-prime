//// The lines on which a load step stops keeping up, and the mark of a step the
//// load clients themselves limited (`genesis_prime/load_step`), each run on a
//// planted observation. Expected values come from the card's definition of
//// "stops keeping up".
//// - A player failure: any one.
//// - Login to world: 1 in 100 over 1,000 ms.
//// - Ping round trip: 1 in 100 over 500 ms, the client's own ping interval
////   (SendNetworkPings, at most once every 500 ms).
//// - A process's mailbox non-empty in every sample of the last 10 s of the hold.
//// - The store's workers waiting in every sample of the arrival.
//// - Any server error or warning line during the step, the players' leaving
////   included.
//// - Connections still held when the wait for them to close ends.
//// - A step in which the load clients used over half their cores, began a
////   player more than 500 ms late, or had a player the machine had no local
////   port for is the clients' limit and not the server's.
//// Each line is shown failing, and passing at the value just below it.

import genesis_prime/load_sample.{type Sample, Sample, ServerReading, Waiting}
import genesis_prime/load_step.{
  type Observation, ClientsLimited, Failed, Kept, LoginToWorldSlow,
  MailboxBacklog, NotDrained, Observation, PingSlow, PlayerFailed, ServerLogLine,
  StoreBacklog,
}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test

/// The whole numbers from `first` to `last`.
fn through(first: Int, last: Int) -> List(Int) {
  int.range(from: last, to: first - 1, with: [], run: list.prepend)
}

/// A sample of a server that keeps up, taken `at_ms` into the step: nothing
/// waiting, no log lines, no connection and 1 s of 4 s of scheduler time busy.
fn calm(at_ms: Int) -> Sample {
  Sample(
    at_ms:,
    waiting: [],
    largest_heap_words: 1000,
    memory_bytes: 1_000_000,
    busy_us: at_ms * 1000,
    total_us: at_ms * 4000,
    run_queue: 0,
    server: Some(ServerReading(
      connections: [],
      store_waiting: 0,
      worker_start_us: 50,
    )),
    log_lines: 0,
  )
}

/// The sample as if `waiting` store workers waited for the pool.
fn with_store_waiting(sample: Sample, waiting: Int) -> Sample {
  let assert Some(reading) = sample.server
    as "a sample of the server carries its reading"
  Sample(
    ..sample,
    server: Some(ServerReading(..reading, store_waiting: waiting)),
  )
}

/// The sample as if the listeners held `held` connections.
fn with_connections(sample: Sample, held: List(Int)) -> Sample {
  let assert Some(reading) = sample.server
    as "a sample of the server carries its reading"
  Sample(..sample, server: Some(ServerReading(..reading, connections: held)))
}

/// Calm samples one second apart from 0 to `last` seconds.
fn seconds(last: Int) -> List(Sample) {
  list.map(through(0, last), fn(second) { calm(second * 1000) })
}

/// A step the server kept up with: no failure, a hundred logins and pings all
/// well under their limits, calm samples on both nodes, the last player
/// arriving at 5 s and the hold ending at 10 s.
fn kept() -> Observation {
  Observation(
    failures: 0,
    login_to_world_ms: list.repeat(200, 100),
    ping_round_trip_us: list.repeat(300, 100),
    server: seconds(10),
    clients: seconds(10),
    unconnected: 0,
    start_lag_ms: 0,
    arrived_ms: 5000,
    held_ms: 10_000,
  )
}

/// The samples `seconds` gives, each second in `changed` made by `change`.
fn changing(
  last last: Int,
  changed changed: fn(Int) -> Bool,
  change change: fn(Sample) -> Sample,
) -> List(Sample) {
  list.map(through(0, last), fn(second) {
    case changed(second) {
      True -> change(calm(second * 1000))
      False -> calm(second * 1000)
    }
  })
}

fn waiting(pid: process.Pid, mailbox: Int) -> fn(Sample) -> Sample {
  fn(sample) {
    Sample(..sample, waiting: [
      Waiting(pid:, mailbox:, heap_words: 1, described: ""),
    ])
  }
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

pub fn a_process_waiting_in_every_sample_of_the_last_10_s_of_the_hold_fails_and_one_missing_once_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let stuck = process.spawn_unlinked(process.sleep_forever)
  let other = process.spawn_unlinked(process.sleep_forever)
  let always =
    changing(last: 10, changed: fn(_) { True }, change: waiting(stuck, 3))
  assert load_step.judge(Observation(..kept(), server: always))
    == Failed([MailboxBacklog])
  let missed_once =
    changing(
      last: 10,
      changed: fn(second) { second != 4 },
      change: waiting(stuck, 3),
    )
  assert load_step.judge(Observation(..kept(), server: missed_once)) == Kept
    as "a mailbox that emptied once is a process that keeps up"
  let alternating = fn(sample: Sample) {
    waiting(
      case int.is_even(sample.at_ms / 1000) {
        True -> stuck
        False -> other
      },
      3,
    )(sample)
  }
  assert load_step.judge(
      Observation(
        ..kept(),
        server: changing(last: 10, changed: fn(_) { True }, change: alternating),
      ),
    )
    == Kept
    as "two processes, each waiting in half the samples, are not one that never empties"
  process.kill(stuck)
  process.kill(other)
}

pub fn the_mailbox_window_includes_the_sample_10_s_before_the_hold_ends_and_no_older_one_test() -> Nil {
  use <- owned_test.run(5000)
  let stuck = process.spawn_unlinked(process.sleep_forever)
  let long = Observation(..kept(), server: seconds(20), held_ms: 20_000)
  let waiting_from = fn(first: Int) {
    Observation(
      ..long,
      server: changing(
        last: 20,
        changed: fn(second) { second >= first },
        change: waiting(stuck, 9),
      ),
    )
  }
  assert load_step.judge(waiting_from(11)) == Kept
    as "the sample at 10 s, the window's edge, is calm, so the window holds one with no backlog"
  assert load_step.judge(waiting_from(10)) == Failed([MailboxBacklog])
    as "waiting from the sample at the edge on is waiting in the whole window"
  assert load_step.judge(waiting_from(5)) == Failed([MailboxBacklog])
  let before =
    changing(
      last: 20,
      changed: fn(second) { second < 10 },
      change: waiting(stuck, 9),
    )
  assert load_step.judge(Observation(..long, server: before)) == Kept
    as "a backlog that ended before the last 10 s of the hold is not judged"
  process.kill(stuck)
}

pub fn store_workers_waiting_in_every_sample_of_the_arrival_fail_and_one_empty_sample_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let queued = fn(sample: Sample) { with_store_waiting(sample, 2) }
  let in_arrival = fn(missing: Int) {
    Observation(
      ..kept(),
      server: changing(
        last: 10,
        changed: fn(second) { second <= 5 && second != missing },
        change: queued,
      ),
    )
  }
  assert load_step.judge(in_arrival(-1)) == Failed([StoreBacklog])
  assert load_step.judge(in_arrival(3)) == Kept
    as "the store emptied once while the players arrived"
  assert load_step.judge(in_arrival(5)) == Kept
    as "the sample at 5 s, when the last player arrives, is in the arrival"
  let after_arrival =
    changing(last: 10, changed: fn(second) { second > 5 }, change: queued)
  assert load_step.judge(Observation(..kept(), server: after_arrival)) == Kept
    as "workers waiting only after the arrival, in the hold, are not judged"
}

pub fn one_error_or_warning_line_during_the_step_fails_it_and_none_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let lines = fn(count) {
    changing(last: 10, changed: fn(second) { second == 10 }, change: fn(sample) {
      Sample(..sample, log_lines: count)
    })
  }
  assert load_step.judge(Observation(..kept(), server: lines(1)))
    == Failed([ServerLogLine])
  assert load_step.judge(Observation(..kept(), server: lines(0))) == Kept
}

pub fn a_warning_line_only_while_the_players_leave_fails_the_step_test() -> Nil {
  use <- owned_test.run(5000)
  let leaving = fn(count) {
    list.append(seconds(10), [
      calm(11_000),
      Sample(..calm(12_000), log_lines: count),
    ])
  }
  assert load_step.judge(Observation(..kept(), server: leaving(1)))
    == Failed([ServerLogLine])
    as "the hold ended at 10 s and the line came at 12 s, in the drain"
  assert load_step.judge(Observation(..kept(), server: leaving(0))) == Kept
}

pub fn connections_still_held_when_the_wait_ends_fail_the_step_test() -> Nil {
  use <- owned_test.run(5000)
  let ending = fn(held: List(Int)) {
    list.append(seconds(10), [with_connections(calm(11_000), held)])
  }
  assert load_step.judge(Observation(..kept(), server: ending([0, 0, 2])))
    == Failed([NotDrained])
  assert load_step.judge(Observation(..kept(), server: ending([0, 0, 0])))
    == Kept
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

pub fn a_step_on_a_negative_monotonic_clock_is_judged_the_same_test() -> Nil {
  use <- owned_test.run(5000)
  // The monotonic clock can be negative, so no time is taken to start at 0.
  let earlier = fn(sample: Sample) {
    Sample(..sample, at_ms: sample.at_ms - 1_000_000)
  }
  let shifted = fn(observation: Observation) {
    Observation(
      ..observation,
      server: list.map(observation.server, earlier),
      clients: list.map(observation.clients, earlier),
      arrived_ms: observation.arrived_ms - 1_000_000,
      held_ms: observation.held_ms - 1_000_000,
    )
  }
  let queued =
    changing(last: 10, changed: fn(_) { True }, change: fn(sample) {
      with_store_waiting(sample, 2)
    })
  assert load_step.judge(shifted(Observation(..kept(), server: queued)))
    == Failed([StoreBacklog])
  let busy = [
    Sample(..calm(0), busy_us: 0, total_us: 0),
    Sample(..calm(10_000), busy_us: 3_000_000, total_us: 4_000_000),
  ]
  assert load_step.judge(shifted(Observation(..kept(), clients: busy)))
    == ClientsLimited
}
