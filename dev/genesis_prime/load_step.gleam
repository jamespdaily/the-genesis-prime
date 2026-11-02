//// Whether the server kept up with one step of the load run, judged on what
//// the step measured, before the run (the numbers are the card's definition of
//// "stops keeping up"). A step fails on any of six lines:
//// - a player failure: a close, an unexpected message or a wait over 5 s,
////   any one;
//// - login to world: more than 1 login in 100 over 1,000 ms (a fifth of the 5 s
////   wait at which the server gives up on a slow answer);
//// - ping round trip: more than 1 in 100 over 500 ms, the client's ping
////   interval (SendNetworkPings sends at most once every 500 ms and waits for
////   each answer);
//// - a process with messages waiting in every sample of the last 10 s (one
////   that keeps up empties its mailbox between arrivals);
//// - store workers waiting in every sample of the last 10 s;
//// - any server warning or error line during the step.
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
import gleam/string

/// The line a step failed on.
pub type Line {
  PlayerFailed
  LoginToWorldSlow
  PingSlow
  MailboxBacklog
  StoreBacklog
  ServerLogLine
}

/// What one step measured. The servers' and the clients' samples are in
/// time order, the first at the step's start and the last at its end.
pub type Observation {
  Observation(
    failures: Int,
    login_to_world_ms: List(Int),
    ping_round_trip_us: List(Int),
    server: List(Sample),
    clients: List(Sample),
    unconnected: Int,
    start_lag_ms: Int,
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

/// The window the two backlog lines look at, in milliseconds.
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
          }
        }),
        ", ",
      )
  }
}

fn clients_limited(observation: Observation) -> Bool {
  observation.unconnected > 0
  || observation.start_lag_ms > start_lag_limit_ms
  || case observation.clients {
    [first, ..] as samples ->
      case list.last(samples) {
        Ok(last) -> load_sample.use_between(first:, last:) >. clients_busy_limit
        Error(Nil) -> False
      }
    [] -> False
  }
}

fn failed_lines(observation: Observation) -> List(Line) {
  let window = last_seconds(observation.server)
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
    #(MailboxBacklog, never_empty(observation.server) != []),
    #(
      StoreBacklog,
      window != [] && list.all(window, fn(sample) { sample.store_waiting > 0 }),
    ),
    #(ServerLogLine, logged_during(observation.server)),
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

/// The samples taken within the last 10 s of the step.
fn last_seconds(samples: List(Sample)) -> List(Sample) {
  case list.last(samples) {
    Ok(last) ->
      list.filter(samples, fn(sample) {
        sample.at_ms >= last.at_ms - backlog_window_ms
      })
    Error(Nil) -> []
  }
}

/// The processes with messages waiting in every sample of the last 10 s.
pub fn never_empty(samples: List(Sample)) -> List(load_sample.Waiting) {
  case last_seconds(samples) {
    [] -> []
    [first, ..rest] ->
      list.filter(first.waiting, fn(found) {
        list.all(rest, fn(sample) {
          list.any(sample.waiting, fn(other) { other.pid == found.pid })
        })
      })
  }
}

/// Whether the log count grew between the step's first sample and its last.
fn logged_during(samples: List(Sample)) -> Bool {
  case samples, list.last(samples) {
    [first, ..], Ok(last) -> last.log_lines > first.log_lines
    _, _ -> False
  }
}
