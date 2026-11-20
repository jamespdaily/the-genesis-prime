//// What the Mac's play service is doing, as the dashboard knows it: the
//// state script's report read into typed facts, and the rule that keeps each
//// fact's last good value when a read fails.
////
//// ```text
//// script output ──parse──► Report (each fact: Ok value | Error reason)
////                              │
//// previous Reading ──after_read(outcome, now)──► Reading (each fact: Fresh | Stale | Never)
//// ```
////
//// - A fact the report gives is fresh as of the read's time; one it does not
////   give, or gives in a form the dashboard does not know, keeps its last
////   value, stale with the reason (`dev/play_service/state.sh`'s header lists
////   each key and its values).
//// - A read that did not succeed (the script's status, its deadline, a script
////   that is missing) stales every fact the same way, with the reason.
//// - A read still running 6 s after a fact was read stales that fact: the poller
////   reads every 2 s, so 6 s of silence is three misses.
//// - A fact never read stays unread, with the reason of the last attempt.

import genesis_prime/dashboard/script
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Whether the Podman machine answers.
pub type Machine {
  MachineUp
  MachineDown
}

/// What Podman says a container is, or that there is none.
pub type ContainerState {
  ContainerRunning
  ContainerStopping
  ContainerExited
  ContainerCreated
  ContainerMissing
}

/// The play server's container: its state and the labels it was made with.
pub type Server {
  Server(
    state: ContainerState,
    revision: Option(String),
    address: Option(String),
  )
}

/// The play database's container and whether it accepts a connection now.
pub type Database {
  Database(state: ContainerState, ready: Bool)
}

/// The updater's lock.
pub type UpdateLock {
  UpdateLockFree
  UpdateLockRun(pid: Int)
  UpdateLockOwnerless
  UpdateLockGone(pid: Option(Int))
}

/// The updater: whether the service is held, its lock and its log's last line.
pub type Updater {
  Updater(held: Bool, lock: UpdateLock, last_line: String)
}

/// The live lock: free, held by a live owner of a kind, or one whose taker is
/// still writing it or is gone.
pub type LiveLock {
  LiveLockFree
  LiveLockClient(pid: Int, folder: Option(String))
  LiveLockRun(pid: Int, folder: Option(String))
  LiveLockOwnerless(kind: Option(String), folder: Option(String))
  LiveLockGone(kind: Option(String), pid: Option(Int), folder: Option(String))
}

/// Why a fact could not be read, in words.
pub type Unreadable {
  Unreadable(reason: String)
}

/// One fact as the report gave it, or why it could not be read.
pub type Report {
  Report(
    machine: Result(Machine, Unreadable),
    server: Result(Server, Unreadable),
    connections: Result(Int, Unreadable),
    database: Result(Database, Unreadable),
    updater: Result(Updater, Unreadable),
    live_lock: Result(LiveLock, Unreadable),
  )
}

/// Why a fact is stale: its read failed, or no read has ended for too long.
pub type Cause {
  ReadFailed(reason: String)
  NoNewReading
}

/// A fact in a reading: never read, read at `read_ms` and fresh as of the
/// reading, or last read at `read_ms` and stale since.
pub type Section(a) {
  Never(reason: String)
  Fresh(value: a, read_ms: Int)
  Stale(value: a, cause: Cause, read_ms: Int)
}

/// Every fact the Overview shows, each with its own freshness, as of
/// `composed_ms`.
pub type Reading {
  Reading(
    composed_ms: Int,
    machine: Section(Machine),
    server: Section(Server),
    connections: Section(Int),
    database: Section(Database),
    updater: Section(Updater),
    live_lock: Section(LiveLock),
  )
}

/// What happened to the read the poller wanted: it ended, or it is still
/// running.
pub type Outcome {
  Ran(result: Result(script.Finished, script.Failure))
  Waiting
}

/// How long a read may run before the facts last read are shown stale: three
/// of the poller's default 2 s intervals. A guess: a read takes 0.6 to 1.6 s.
const stale_after_ms = 6000

// PARSING ---------------------------------------------------------------------

/// Reads the state script's output. A line that is not `key=value`, or has a
/// key the script does not print, is ignored: the runner merges the script's
/// standard error into its output. Output that is empty or not text gives no
/// fact, only the reason.
pub fn parse(output output: BitArray) -> Result(Report, Unreadable) {
  case bit_array.to_string(output) {
    Error(Nil) -> Error(Unreadable("the report is not text"))
    Ok(text) ->
      case string.trim(text) {
        "" -> Error(Unreadable("the report is empty"))
        _ -> {
          let lines = key_lines(text)
          Ok(Report(
            machine: machine(lines),
            server: server(lines),
            connections: connections(lines),
            database: database(lines),
            updater: updater(lines),
            live_lock: live_lock(lines),
          ))
        }
      }
  }
}

/// The `key=value` lines of the text, the first line of a key standing.
fn key_lines(text: String) -> Dict(String, String) {
  string.split(text, "\n")
  |> list.fold(dict.new(), fn(lines, line) {
    let line = case string.ends_with(line, "\r") {
      True -> string.drop_end(line, 1)
      False -> line
    }
    case string.split_once(line, "=") {
      Ok(#(key, value)) ->
        case dict.has_key(lines, key) {
          True -> lines
          False -> dict.insert(lines, key, value)
        }
      Error(Nil) -> lines
    }
  })
}

/// The reason the script gave for a fact it printed as `unreadable`.
fn reason_of(lines: Dict(String, String), key: String) -> String {
  case dict.get(lines, key <> "_reason") {
    Ok(reason) if reason != "" -> reason
    Ok(_) | Error(Nil) -> key <> " could not be read"
  }
}

/// Why a fact of the containers has no line: the machine hides it, or the
/// report left it out.
fn missing_line(lines: Dict(String, String), key: String) -> String {
  case dict.get(lines, "machine") {
    Ok("down") -> "the Podman machine is down"
    Ok("unreadable") -> "the Podman machine could not be read"
    Ok(_) | Error(Nil) -> "the report has no " <> key <> " line"
  }
}

fn present(text: String) -> Option(String) {
  case text {
    "" -> None
    text -> Some(text)
  }
}

fn machine(lines: Dict(String, String)) -> Result(Machine, Unreadable) {
  case dict.get(lines, "machine") {
    Ok("up") -> Ok(MachineUp)
    Ok("down") -> Ok(MachineDown)
    Ok("unreadable") -> Error(Unreadable(reason_of(lines, "machine")))
    Ok(other) -> Error(Unreadable("the machine's state is \"" <> other <> "\""))
    Error(Nil) -> Error(Unreadable("the report has no machine line"))
  }
}

fn container_state(word: String) -> Result(ContainerState, Nil) {
  case word {
    "running" -> Ok(ContainerRunning)
    "stopping" -> Ok(ContainerStopping)
    "exited" -> Ok(ContainerExited)
    "created" -> Ok(ContainerCreated)
    "missing" -> Ok(ContainerMissing)
    _ -> Error(Nil)
  }
}

/// The container line `key` of the report, read as a state; the reason when it
/// is missing, unreadable or a word the dashboard does not know.
fn container(
  lines: Dict(String, String),
  key: String,
) -> Result(ContainerState, Unreadable) {
  case dict.get(lines, key) {
    Error(Nil) -> Error(Unreadable(missing_line(lines, key)))
    Ok("unreadable") -> Error(Unreadable(reason_of(lines, key)))
    Ok(word) ->
      container_state(word)
      |> result.replace_error(Unreadable(
        "the " <> key <> "'s state is \"" <> word <> "\"",
      ))
  }
}

fn server(lines: Dict(String, String)) -> Result(Server, Unreadable) {
  use state <- result.try(container(lines, "server"))
  case state {
    ContainerMissing -> Ok(Server(state:, revision: None, address: None))
    ContainerRunning | ContainerStopping | ContainerExited | ContainerCreated ->
      case dict.get(lines, "server_labels") {
        Ok("unreadable") -> Error(Unreadable(reason_of(lines, "server_labels")))
        Ok(_) | Error(Nil) -> {
          use revision <- result.try(label(lines, "server_revision"))
          use address <- result.map(label(lines, "server_address"))
          Server(state:, revision:, address:)
        }
      }
  }
}

/// A label line of a server that exists: empty means the container has no such
/// label; a missing line means the report left it out.
fn label(
  lines: Dict(String, String),
  key: String,
) -> Result(Option(String), Unreadable) {
  dict.get(lines, key)
  |> result.map(present)
  |> result.replace_error(Unreadable("the report has no " <> key <> " line"))
}

fn connections(lines: Dict(String, String)) -> Result(Int, Unreadable) {
  case dict.get(lines, "game_connections") {
    Error(Nil) -> Error(Unreadable(missing_line(lines, "game_connections")))
    Ok("unreadable") -> Error(Unreadable(reason_of(lines, "game_connections")))
    Ok(text) ->
      case int.parse(text) {
        Ok(count) if count >= 0 -> Ok(count)
        Ok(_) | Error(Nil) ->
          Error(Unreadable(
            "the game connections are \"" <> text <> "\", not a number",
          ))
      }
  }
}

fn state_word(state: ContainerState) -> String {
  case state {
    ContainerRunning -> "running"
    ContainerStopping -> "stopping"
    ContainerExited -> "exited"
    ContainerCreated -> "created"
    ContainerMissing -> "missing"
  }
}

fn database(lines: Dict(String, String)) -> Result(Database, Unreadable) {
  use state <- result.try(container(lines, "database"))
  case dict.get(lines, "database_ready"), state {
    Error(Nil), _ -> Error(Unreadable("the report has no database_ready line"))
    Ok("unreadable"), _ -> Error(Unreadable(reason_of(lines, "database_ready")))
    Ok("yes"), ContainerRunning -> Ok(Database(state:, ready: True))
    Ok("no"), _ -> Ok(Database(state:, ready: False))
    Ok("yes"), _ ->
      Error(Unreadable(
        "the database is " <> state_word(state) <> " and ready at once",
      ))
    Ok(other), _ ->
      Error(Unreadable(
        "the database is ready \"" <> other <> "\", not yes or no",
      ))
  }
}

fn yes_or_no(
  lines: Dict(String, String),
  key: String,
) -> Result(Bool, Unreadable) {
  case dict.get(lines, key) {
    Ok("yes") -> Ok(True)
    Ok("no") -> Ok(False)
    Ok(other) ->
      Error(Unreadable(key <> " is \"" <> other <> "\", not yes or no"))
    Error(Nil) -> Error(Unreadable("the report has no " <> key <> " line"))
  }
}

/// A process id line: none when the line is absent or empty, an error when it
/// is not a number.
fn pid_line(
  lines lines: Dict(String, String),
  key key: String,
  noun noun: String,
) -> Result(Option(Int), Unreadable) {
  case dict.get(lines, key) {
    Error(Nil) | Ok("") -> Ok(None)
    Ok(text) ->
      case int.parse(text) {
        Ok(pid) -> Ok(Some(pid))
        Error(Nil) ->
          Error(Unreadable(
            "the " <> noun <> "'s process is \"" <> text <> "\", not a number",
          ))
      }
  }
}

fn updater(lines: Dict(String, String)) -> Result(Updater, Unreadable) {
  use held <- result.try(yes_or_no(lines, "held"))
  use pid <- result.try(pid_line(
    lines:,
    key: "update_lock_pid",
    noun: "update lock",
  ))
  use lock <- result.try(case dict.get(lines, "update_lock"), pid {
    Ok("free"), _ -> Ok(UpdateLockFree)
    Ok("run"), Some(pid) -> Ok(UpdateLockRun(pid:))
    Ok("run"), None ->
      Error(Unreadable("the update lock has an owner but no process"))
    Ok("ownerless"), _ -> Ok(UpdateLockOwnerless)
    Ok("gone"), pid -> Ok(UpdateLockGone(pid:))
    Ok(other), _ -> Error(Unreadable("the update lock is \"" <> other <> "\""))
    Error(Nil), _ -> Error(Unreadable("the report has no update_lock line"))
  })
  use last_line <- result.map(
    dict.get(lines, "updater_last_line")
    |> result.replace_error(Unreadable(
      "the report has no updater_last_line line",
    )),
  )
  Updater(held:, lock:, last_line:)
}

fn live_lock(lines: Dict(String, String)) -> Result(LiveLock, Unreadable) {
  use pid <- result.try(pid_line(
    lines:,
    key: "live_lock_pid",
    noun: "live lock",
  ))
  let kind = dict.get(lines, "live_lock_kind") |> result.unwrap("") |> present
  let folder =
    dict.get(lines, "live_lock_folder") |> result.unwrap("") |> present
  case dict.get(lines, "live_lock"), pid {
    Ok("free"), _ -> Ok(LiveLockFree)
    Ok("client"), Some(pid) -> Ok(LiveLockClient(pid:, folder:))
    Ok("run"), Some(pid) -> Ok(LiveLockRun(pid:, folder:))
    Ok("client"), None | Ok("run"), None ->
      Error(Unreadable("the live lock has an owner but no process"))
    Ok("ownerless"), _ -> Ok(LiveLockOwnerless(kind:, folder:))
    Ok("gone"), pid -> Ok(LiveLockGone(kind:, pid:, folder:))
    Ok(other), _ -> Error(Unreadable("the live lock is \"" <> other <> "\""))
    Error(Nil), _ -> Error(Unreadable("the report has no live_lock line"))
  }
}

// MERGING ---------------------------------------------------------------------

/// What a reading is made from: a report, the reason no report was made, or
/// that the read has not ended.
type Input {
  Parsed(report: Report)
  Failed(reason: String)
  StillRunning
}

/// The reading after `outcome`, from the `previous` one, at `now_ms`. A read
/// still running (`Waiting`) with no earlier reading gives none.
pub fn after_read(
  previous previous: Option(Reading),
  outcome outcome: Outcome,
  now_ms now_ms: Int,
) -> Option(Reading) {
  case outcome {
    Waiting -> {
      use _reading <- option.map(previous)
      merge(previous:, input: StillRunning, now_ms:)
    }
    Ran(Ok(script.Finished(output:, status: 0))) ->
      case parse(output:) {
        Ok(report) -> Some(merge(previous:, input: Parsed(report:), now_ms:))
        Error(Unreadable(reason:)) ->
          Some(merge(previous:, input: Failed(reason:), now_ms:))
      }
    Ran(Ok(script.Finished(output:, status:))) ->
      Some(merge(
        previous:,
        input: Failed(reason: exit_reason(output, status)),
        now_ms:,
      ))
    Ran(Error(failure)) ->
      Some(merge(
        previous:,
        input: Failed(reason: failure_reason(failure)),
        now_ms:,
      ))
  }
}

fn exit_reason(output: BitArray, status: Int) -> String {
  let first_line = case bit_array.to_string(output) {
    Ok(text) ->
      string.split(text, "\n")
      |> list.first
      |> result.unwrap("")
      |> string.trim
    Error(Nil) -> ""
  }
  let base = "the state script exited with status " <> int.to_string(status)
  case first_line {
    "" -> base
    line -> base <> ": " <> line
  }
}

fn failure_reason(failure: script.Failure) -> String {
  case failure {
    script.DeadlineReached(deadline_ms:) ->
      "the state script did not finish in "
      <> int.to_string(deadline_ms / 1000)
      <> " s"
    script.NotFound(path:) -> "the state script is not found: " <> path
    script.NotExecutable(path:) ->
      "the state script is not executable: " <> path
    script.NotStarted(path:, reason:) ->
      "the state script did not start (" <> path <> "): " <> reason
  }
}

/// The six facts, each merged on its own: the one place a reading is listed
/// fact by fact.
fn merge(
  previous previous: Option(Reading),
  input input: Input,
  now_ms now_ms: Int,
) -> Reading {
  Reading(
    composed_ms: now_ms,
    machine: merged(
      before: option.map(previous, fn(reading) { reading.machine }),
      input:,
      pick: fn(report: Report) { report.machine },
      now_ms:,
    ),
    server: merged(
      before: option.map(previous, fn(reading) { reading.server }),
      input:,
      pick: fn(report: Report) { report.server },
      now_ms:,
    ),
    connections: merged(
      before: option.map(previous, fn(reading) { reading.connections }),
      input:,
      pick: fn(report: Report) { report.connections },
      now_ms:,
    ),
    database: merged(
      before: option.map(previous, fn(reading) { reading.database }),
      input:,
      pick: fn(report: Report) { report.database },
      now_ms:,
    ),
    updater: merged(
      before: option.map(previous, fn(reading) { reading.updater }),
      input:,
      pick: fn(report: Report) { report.updater },
      now_ms:,
    ),
    live_lock: merged(
      before: option.map(previous, fn(reading) { reading.live_lock }),
      input:,
      pick: fn(report: Report) { report.live_lock },
      now_ms:,
    ),
  )
}

/// One fact after a read: fresh when the report gives it; else its last value
/// stale with the reason the report or the read gave; else unread. While the
/// read is still running, a fresh fact older than `stale_after_ms` is stale for
/// want of a new reading, and any other fact stays as it is.
fn merged(
  before before: Option(Section(a)),
  input input: Input,
  pick pick: fn(Report) -> Result(a, Unreadable),
  now_ms now_ms: Int,
) -> Section(a) {
  case input, before {
    Parsed(report:), _ -> after_fact(before:, read: pick(report), now_ms:)
    Failed(reason:), _ ->
      after_fact(before:, read: Error(Unreadable(reason)), now_ms:)
    StillRunning, Some(Fresh(value:, read_ms:))
      if now_ms - read_ms >= stale_after_ms
    -> Stale(value:, cause: NoNewReading, read_ms:)
    StillRunning, Some(section) -> section
    StillRunning, None -> Never("no read has ended")
  }
}

fn after_fact(
  before before: Option(Section(a)),
  read read: Result(a, Unreadable),
  now_ms now_ms: Int,
) -> Section(a) {
  case read {
    Ok(value) -> Fresh(value:, read_ms: now_ms)
    Error(Unreadable(reason:)) ->
      case before {
        Some(Fresh(value:, read_ms:)) | Some(Stale(value:, read_ms:, ..)) ->
          Stale(value:, cause: ReadFailed(reason:), read_ms:)
        Some(Never(_)) | None -> Never(reason:)
      }
  }
}
