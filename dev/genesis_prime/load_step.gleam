//// Whether the server kept up with one step of the load run, judged on what
//// the step measured, before the run (the numbers are the card's definition of
//// "stops keeping up"). A step runs from its first sample, through the players'
//// arrival, a hold and the players' leaving, to the sample that finds the
//// server's connections closed. It fails on any of seven lines:
//// - a player failure: a close, an unexpected message or a wait over 5 s,
////   any one;
//// - login to world: more than 1 login in 100 over 1,000 ms (a fifth of the 5 s
////   wait at which the server gives up on a slow answer);
//// - ping round trip: more than 1 in 100 over 500 ms, the client's ping
////   interval (SendNetworkPings sends at most once every 500 ms and waits for
////   each answer);
//// - a process with messages waiting in every sample of the last 10 s of the
////   hold (one that keeps up empties its mailbox between arrivals);
//// - store workers waiting in every sample of the arrival, when every player
////   logs in and asks the store (the hold only pings);
//// - any server warning or error line during the step, the leaving included;
//// - connections still held by the server when the wait for them to close ends.
////
//// A step in which the load clients used over half their cores, began a player
//// more than 500 ms after its time, or had a player that this machine had no
//// local port to connect from (`eaddrnotavail`), is the clients' limit and not
//// the server's, whatever else it showed: those server choices keep the clients'
//// own load from being taken for the server's.

import genesis_prime/load_sample.{type Sample}
import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// The line a step failed on.
pub type Line {
  PlayerFailed
  LoginToWorldSlow
  PingSlow
  MailboxBacklog
  StoreBacklog
  ServerLogLine
  NotDrained
}

/// What one step measured. The servers' and the clients' samples are in
/// time order, the first at the step's start and the last after the players
/// left; `arrived_ms` is when the last player was to begin and `held_ms` when
/// the hold ends and the players leave, on the clock the samples use.
pub type Observation {
  Observation(
    failures: Int,
    login_to_world_ms: List(Int),
    ping_round_trip_us: List(Int),
    server: List(Sample),
    clients: List(Sample),
    unconnected: Int,
    start_lag_ms: Int,
    arrived_ms: Int,
    held_ms: Int,
  )
}

/// How the step went.
pub type Verdict {
  /// The server kept up.
  Kept
  /// The server did not keep up, on these lines.
  Failed(lines: List(Line))
  /// The clients were the limit, so the step says nothing of the server.
  ClientsLimited
}

const login_to_world_limit_ms = 1000

const ping_limit_us = 500_000

/// The window the mailbox line looks at, in milliseconds.
const backlog_window_ms = 10_000

/// The share of their cores the clients may use before they are the limit.
const clients_busy_limit = 0.5

/// How late a player may begin before the clients are the limit, in
/// milliseconds.
const start_lag_limit_ms = 500

/// The verdict on a step.
pub fn judge(observation: Observation) -> Verdict {
  use <- bool.guard(when: clients_limited(observation), return: ClientsLimited)
  case failed_lines(observation) {
    [] -> Kept
    lines -> Failed(lines)
  }
}

/// The verdict in words, for the run's report.
pub fn describe(verdict: Verdict) -> String {
  case verdict {
    Kept -> "kept"
    ClientsLimited -> "clients-limited"
    Failed(lines:) ->
      "failed on "
      <> string.join(
        list.map(lines, fn(line) {
          case line {
            PlayerFailed -> "a player failure"
            LoginToWorldSlow -> "login to world over 1,000 ms"
            PingSlow -> "ping over 500 ms"
            MailboxBacklog -> "a mailbox that never emptied"
            StoreBacklog -> "store workers always waiting"
            ServerLogLine -> "a server warning or error line"
            NotDrained -> "connections still held after the players left"
          }
        }),
        ", ",
      )
  }
}

fn clients_limited(observation: Observation) -> Bool {
  observation.unconnected > 0
  || observation.start_lag_ms > start_lag_limit_ms
  || load_sample.use_between(held(observation:, samples: observation.clients))
  >. clients_busy_limit
}

/// The samples of a node taken up to the end of the hold, which is when the
/// clients work.
pub fn held(
  observation observation: Observation,
  samples samples: List(Sample),
) -> List(Sample) {
  until(samples:, to: observation.held_ms)
}

fn failed_lines(observation: Observation) -> List(Line) {
  let arrival = until(samples: observation.server, to: observation.arrived_ms)
  [
    #(PlayerFailed, observation.failures > 0),
    #(
      LoginToWorldSlow,
      percentile(values: observation.login_to_world_ms, percent: 99)
        > login_to_world_limit_ms,
    ),
    #(
      PingSlow,
      percentile(values: observation.ping_round_trip_us, percent: 99)
        > ping_limit_us,
    ),
    #(MailboxBacklog, never_empty(observation) != []),
    #(
      StoreBacklog,
      arrival != []
        && list.all(arrival, fn(sample) {
        load_sample.store_waiting(sample) > 0
      }),
    ),
    #(ServerLogLine, load_sample.log_lines_between(observation.server) > 0),
    #(
      NotDrained,
      list.last(observation.server)
        |> result.map(fn(last) { int.sum(load_sample.connections(last)) > 0 })
        |> result.unwrap(False),
    ),
  ]
  |> list.filter(fn(line) { line.1 })
  |> list.map(fn(line) { line.0 })
}

/// The value that `percent` in a hundred of the values are at or under
/// (the nearest rank), or 0 for no values.
pub fn percentile(values values: List(Int), percent percent: Int) -> Int {
  let sorted = list.sort(values, int.compare)
  let rank = { list.length(sorted) * percent + 99 } / 100
  case list.drop(sorted, int.max(rank, 1) - 1) {
    [value, ..] -> value
    [] -> 0
  }
}

/// The samples taken up to `to` milliseconds on the monotonic clock, which can
/// be negative, so no sample's time is taken to be 0 or more.
fn until(samples samples: List(Sample), to to: Int) -> List(Sample) {
  list.filter(samples, fn(sample) { sample.at_ms <= to })
}

/// The samples taken from `from` to `to` milliseconds, both included.
fn within(
  samples samples: List(Sample),
  from from: Int,
  to to: Int,
) -> List(Sample) {
  list.filter(until(samples:, to:), fn(sample) { sample.at_ms >= from })
}

/// The processes with messages waiting in every sample of the last 10 s of the
/// hold.
pub fn never_empty(observation: Observation) -> List(load_sample.Waiting) {
  let window =
    within(
      samples: observation.server,
      from: observation.held_ms - backlog_window_ms,
      to: observation.held_ms,
    )
  case window {
    [] -> []
    [first, ..rest] ->
      list.filter(first.waiting, fn(found) {
        list.all(rest, fn(sample) {
          list.any(sample.waiting, fn(other) { other.pid == found.pid })
        })
      })
  }
}
