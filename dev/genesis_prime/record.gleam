//// Records a live session of the real client: a relay that listens where the
//// client connects, passes each connection through to the server and writes
//// one recording file for it. Run it once for each of the server's roles:
////
//// `gleam run -m genesis_prime/record -- <listen port> <server host> <server port> <session folder> <role>`
////
//// - `listen port`: the port the client connects to; the client's address
////   arguments name this machine and this port.
//// - `server host` and `server port`: the server the relay passes each
////   connection to.
//// - `session folder`: the folder the recordings are written into, made when
////   it is missing; by convention `test/recording/<date>-<flow>`.
//// - `role`: `sts`, `auth` or `game`, written into each recording's header.
////
//// The relay runs until the process is stopped. It listens on every IPv4
//// address of the machine, so a client on another machine can reach it.
//// A recording's header holds the client's build, today's date, the role and
//// the commit that is checked out in the directory the relay runs from, with
//// `+uncommitted` after it when a tracked file differs from that commit.

import argv
import genesis_prime/recording.{type Header, type Role, Header}
import genesis_prime/recording/listener
import genesis_prime/recording/pipe.{Server}
import genesis_prime/recording/relay
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import mug
import simplifile

/// The client's build: the build of the archive index and of the auth server's
/// version check (fact `archive_index.header`).
const client_build = 16_042

/// What was wrong with the command line or the machine, before the relay
/// started.
type Failure {
  WrongArguments
  NotAPort(text: String)
  UnknownRole(text: String)
  NoCommit
  FolderNotMade(path: String, error: simplifile.FileError)
  RelayDidNotStart(relay.Failure)
}

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Runs a command in the shell and returns what it wrote.
@external(erlang, "os", "cmd")
fn shell(command: Charlist) -> Charlist

/// Starts the relay from the command line and keeps the node alive.
pub fn main() -> Nil {
  case start(argv.load().arguments) {
    Ok(started) -> {
      io.println(
        "relay listening on port "
        <> int.to_string(started.port)
        <> "; recordings go to the session folder; stop it with Ctrl-C twice",
      )
      process.sleep_forever()
    }
    Error(failure) -> {
      io.println_error(describe(failure))
      halt(case failure {
        WrongArguments | NotAPort(_) | UnknownRole(_) -> 2
        NoCommit | FolderNotMade(_, _) | RelayDidNotStart(_) -> 1
      })
    }
  }
}

fn start(arguments: List(String)) -> Result(relay.Relay, Failure) {
  case arguments {
    [listen_port, server_host, server_port, folder, role] -> {
      use listen_port <- result.try(port(listen_port))
      use server_port <- result.try(port(server_port))
      use role <- result.try(parse_role(role))
      use commit <- result.try(commit())
      use Nil <- result.try(
        simplifile.create_directory_all(folder)
        |> result.map_error(FolderNotMade(folder, _)),
      )
      relay.start(relay.Settings(
        bind: listener.AllInterfaces,
        listen_port:,
        server: Server(host: server_host, port: server_port),
        folder:,
        header: header(role:, commit:),
        connections: process.new_name("recording_connections"),
      ))
      |> result.map_error(RelayDidNotStart)
    }
    _ -> Error(WrongArguments)
  }
}

fn port(text: String) -> Result(Int, Failure) {
  case int.parse(text) {
    Ok(number) if number >= 1 && number <= 65_535 -> Ok(number)
    _ -> Error(NotAPort(text))
  }
}

fn parse_role(text: String) -> Result(Role, Failure) {
  recording.role_from_name(text) |> result.replace_error(UnknownRole(text))
}

fn header(role role: Role, commit commit: String) -> Header {
  let #(date, _) =
    timestamp.system_time() |> timestamp.to_calendar(calendar.local_offset())
  Header(build: client_build, date:, role:, commit:, seed: None)
}

/// The commit checked out in the current directory, `+uncommitted` after it
/// when a tracked file differs from it.
fn commit() -> Result(String, Failure) {
  let head = git("rev-parse HEAD")
  case string.length(head) == 40 && list.all(string.to_graphemes(head), hex) {
    False -> Error(NoCommit)
    True ->
      case git("status --porcelain --untracked-files=no") {
        "" -> Ok(head)
        _ -> Ok(head <> "+uncommitted")
      }
  }
}

fn hex(digit: String) -> Bool {
  string.contains("0123456789abcdef", digit)
}

/// What `git` writes to its standard output for the arguments, trimmed; the
/// empty text when it fails or is not there.
fn git(arguments: String) -> String {
  shell(charlist.from_string("git " <> arguments <> " 2>/dev/null"))
  |> charlist.to_string
  |> string.trim
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/record -- <listen port> <server host> <server port> <session folder> <role>"
    NotAPort(text) -> "not a port (1 to 65535): " <> text
    UnknownRole(text) -> "not a role (sts, auth or game): " <> text
    NoCommit ->
      "the commit could not be read: run the relay from the repository's folder"
    FolderNotMade(path, error) ->
      "the session folder "
      <> path
      <> " was not made: "
      <> simplifile.describe_error(error)
    RelayDidNotStart(relay.CouldNotListen(error)) ->
      "the relay could not listen: " <> mug.describe_error(error)
    RelayDidNotStart(relay.TreeDidNotStart(_)) ->
      "the relay's processes did not start"
  }
}
