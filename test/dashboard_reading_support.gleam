//// What the dashboard's reading tests share: the text the state script prints
//// when everything is healthy (`dev/play_service/state.sh`'s contract, one
//// `key=value` line for each fact), changes to it, and the reading that text
//// gives, written out value by value.

import genesis_prime/dashboard/host_reading.{
  type Reading, type Section, Database, Fresh, LiveLockFree, MachineUp, Never,
  Reading, Server, Stale, UpdateLockFree, Updater,
}
import gleam/bit_array
import gleam/list
import gleam/option.{Some}
import gleam/string

/// The last line of the updater's log in a planted report.
pub const last_line = "2026-11-20 02:41:58 play-service: replacing genesis-play"

/// What the script prints with everything healthy and nobody connected.
pub fn healthy_lines() -> List(#(String, String)) {
  [
    #("machine", "up"),
    #("server", "running"),
    #("server_revision", "9d2015a0"),
    #("server_address", "192.168.1.5"),
    #("database", "running"),
    #("database_ready", "yes"),
    #("game_connections", "0"),
    #("held", "no"),
    #("update_lock", "free"),
    #("live_lock", "free"),
    #("updater_last_line", last_line),
  ]
}

/// A change to the healthy lines: a key set to a value (added when the
/// healthy lines have none), or a key left out.
pub type Change {
  Set(key: String, value: String)
  Drop(key: String)
}

/// The healthy lines with the changes made.
pub fn changed(changes: List(Change)) -> List(#(String, String)) {
  let touched = list.map(changes, fn(change) { change.key })
  let kept =
    list.filter(healthy_lines(), fn(line) { !list.contains(touched, line.0) })
  let set =
    list.filter_map(changes, fn(change) {
      case change {
        Set(key:, value:) -> Ok(#(key, value))
        Drop(..) -> Error(Nil)
      }
    })
  list.append(kept, set)
}

/// The lines as the script prints them.
pub fn text(lines: List(#(String, String))) -> BitArray {
  list.map(lines, fn(line) { line.0 <> "=" <> line.1 <> "\n" })
  |> string.concat
  |> bit_array.from_string
}

/// The server a healthy report holds.
pub fn running_server() -> host_reading.Server {
  Server(
    state: host_reading.ContainerRunning,
    revision: Some("9d2015a0"),
    address: Some("192.168.1.5"),
  )
}

/// The database a healthy report holds.
pub fn ready_database() -> host_reading.Database {
  Database(state: host_reading.ContainerRunning, ready: True)
}

/// The updater a healthy report holds.
pub fn idle_updater() -> host_reading.Updater {
  Updater(held: False, lock: UpdateLockFree, last_line:)
}

/// How the facts of a reading stand: all fresh as of a read, all stale since a
/// read for a cause, or none ever read for a reason.
pub type Freshness {
  AllFresh(read_ms: Int)
  AllStale(cause: host_reading.Cause, read_ms: Int)
  AllNever(reason: String)
}

fn section(value: a, freshness: Freshness) -> Section(a) {
  case freshness {
    AllFresh(read_ms:) -> Fresh(value, read_ms)
    AllStale(cause:, read_ms:) -> Stale(value, cause, read_ms)
    AllNever(reason:) -> Never(reason)
  }
}

/// The reading composed at `composed_ms` that holds the facts of the healthy
/// lines, every fact in the same freshness. The one place the six facts are
/// listed.
pub fn every_fact(
  composed_ms composed_ms: Int,
  freshness freshness: Freshness,
) -> Reading {
  Reading(
    composed_ms:,
    machine: section(MachineUp, freshness),
    server: section(running_server(), freshness),
    connections: section(0, freshness),
    database: section(ready_database(), freshness),
    updater: section(idle_updater(), freshness),
    live_lock: section(LiveLockFree, freshness),
  )
}

/// The reading the healthy lines give when read at `at`, every fact fresh.
pub fn fresh(at: Int) -> Reading {
  every_fact(composed_ms: at, freshness: AllFresh(at))
}
