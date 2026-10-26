//// A program started in an operating system process of its own, read line by
//// line, stopped by SIGTERM as a host stops it. It is the way a test sees what
//// a started server writes, when it is ready and the status it ends with.
//// `released_node` starts the entry point and reads one report; this module
//// starts any program and reads everything it writes.
////
//// The test that started a child owns it: the child is killed when `run`
//// ends, however it ends, so no child outlives its test.

import gleam/int
import gleam/list
import gleam/option.{type Option}
import template_database

/// A running child: its operating system process, as the VM holds it.
pub type Child

/// What the child's output holds, line by line, as the test reads it.
pub type Event {
  Line(String)
  ExitStatus(Int)
  Silent
}

/// Why a read of the child's output did not end as asked.
pub type Failure {
  /// The child's VM ended before the line, with its exit status and what it
  /// wrote.
  Exited(status: Int, output: List(String))
  /// The child wrote nothing for the whole wait.
  NotReady(output: List(String))
}

/// How long the child may write nothing, in milliseconds. A deadline for a
/// child that hangs, never a wait: the line or the end ends it.
const silence_limit_ms = 30_000

/// What the server writes once its tree is up and SIGTERM is handled; a test
/// that sends SIGTERM first reads up to this.
pub const server_running = "the server is running"

/// A test's own database in the names the server reads the pool's settings by:
/// PGHOST, PGPORT, PGUSER, PGDATABASE and, when there is one, PGPASSWORD.
pub fn database_environment(
  database: template_database.Database,
) -> List(#(String, String)) {
  let settings = database.settings
  let password = case settings.password {
    option.Some(password) -> [#("PGPASSWORD", password)]
    option.None -> []
  }
  list.append(
    [
      #("PGHOST", settings.tcp_host),
      #("PGPORT", int.to_string(settings.port)),
      #("PGUSER", settings.user),
      #("PGDATABASE", database.name),
    ],
    password,
  )
}

/// Starts the program at the absolute path `program` with `arguments` and
/// `environment` added to this VM's own, runs `body` with the child and kills
/// the child afterwards if it still runs.
pub fn run_program(
  program program: String,
  arguments arguments: List(String),
  environment environment: List(#(String, String)),
  body body: fn(Child) -> a,
) -> a {
  run_child(open_program(program, arguments, environment), body)
}

/// Starts an Erlang VM of the same installation as this one, with this VM's
/// code paths outside OTP, running `arguments`, with `environment` added to this
/// VM's own, runs `body` with the child and kills the child afterwards if it
/// still runs.
pub fn run_erlang(
  arguments arguments: List(String),
  environment environment: List(#(String, String)),
  body body: fn(Child) -> a,
) -> a {
  run_child(open_erlang(arguments, environment), body)
}

fn run_child(child: Child, body: fn(Child) -> a) -> a {
  with_cleanup(fn() { body(child) }, fn() { kill_if_running(child) })
}

/// The lines the child writes, up to and including the first for which `until`
/// holds, or why it gave none.
pub fn lines_until(
  child: Child,
  until until: fn(String) -> Bool,
) -> Result(List(String), Failure) {
  read_until(child, until, [])
}

fn read_until(
  child: Child,
  until: fn(String) -> Bool,
  seen: List(String),
) -> Result(List(String), Failure) {
  case next_event(child, silence_limit_ms) {
    Line(line) ->
      case until(line) {
        True -> Ok(list.reverse([line, ..seen]))
        False -> read_until(child, until, [line, ..seen])
      }
    ExitStatus(status) -> Error(Exited(status:, output: list.reverse(seen)))
    Silent -> Error(NotReady(output: list.reverse(seen)))
  }
}

/// What the child writes from now until it ends, and the status it ends with,
/// or why it gave no end.
pub fn lines_until_exit(child: Child) -> Result(#(List(String), Int), Failure) {
  case lines_until(child, fn(_line) { False }) {
    Error(Exited(status:, output:)) -> Ok(#(output, status))
    Error(NotReady(output:)) -> Error(NotReady(output:))
    Ok(_) -> panic as "a read with no end ended on a line"
  }
}

/// Sends SIGTERM to the child's operating system process.
@external(erlang, "released_child_ffi", "signal_term")
pub fn terminate(child: Child) -> Nil

/// The child's operating system process id, none once it has ended.
@external(erlang, "released_child_ffi", "os_pid")
pub fn os_pid(child: Child) -> Option(Int)

@external(erlang, "released_child_ffi", "open_program")
fn open_program(
  program: String,
  arguments: List(String),
  environment: List(#(String, String)),
) -> Child

@external(erlang, "released_node_ffi", "open")
fn open_erlang(
  arguments: List(String),
  environment: List(#(String, String)),
) -> Child

@external(erlang, "released_node_ffi", "next_event")
fn next_event(child: Child, within: Int) -> Event

@external(erlang, "released_child_ffi", "kill_if_running")
fn kill_if_running(child: Child) -> Nil

@external(erlang, "released_node_ffi", "with_cleanup")
fn with_cleanup(body: fn() -> a, cleanup: fn() -> Nil) -> a
