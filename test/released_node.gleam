//// The server's entry point started in an operating system process of its
//// own, the way a release starts it, so a test can ask what that node is and
//// what it opens. The child is an Erlang VM with the build's code paths and
//// no `-name` or `-sname`, running `genesis_prime:main`, with the database
//// settings of one test's own database in its environment.
////
//// The child tells the test what it is in one report, written after the top
//// supervisor has finished starting every child (a call to the supervisor
//// returns only then), and then waits for its input to close before it ends.
//// The test that started a child owns it: the child's input closes when the
//// test's process ends, however that happens, and the child ends with it.
////
//// Every child gets an epmd port of its own (`ERL_EPMD_PORT`), so a test can
//// see whether the child started or contacted an epmd, and no child touches
//// the epmd of the machine it runs on.

import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import planted_table
import template_database

/// How the child is started. `Unnamed` is how a release starts the server:
/// no `-name` and no `-sname`. `ShortName` plants a start that turns Erlang
/// distribution on, to show a test can tell the two apart.
pub type Naming {
  Unnamed
  ShortName(name: String)
}

/// What the child runs. `Server` runs `genesis_prime:main`, the entry point,
/// and reports once its tree is up. `Idle` starts nothing, so a test can ask
/// what a node started in a given way is without the server's own checks
/// of that start.
pub type Program {
  Server
  Idle
}

/// What to start: the test's own database for the server's pool, how the
/// node is named, what it runs, and how many extra listening sockets the child
/// opens after the tree is up, to show a test catches a listener the server did
/// not start.
pub type Start {
  Start(
    database: template_database.Database,
    naming: Naming,
    program: Program,
    planted_listeners: Int,
  )
}

/// Whether a named service of the child's node is running.
pub type Service {
  Running
  Stopped
}

/// What the child reports about itself once the tree is up.
/// - `node` is `node()`, which is `nonode@nohost` when distribution is off.
/// - `net_kernel` and `epmd_client` are whether the processes registered as
///   `net_kernel` and `erl_epmd` are running; both exist only when the node
///   runs distribution.
/// - `listening_ports` are the ports of the node's listening TCP sockets,
///   sorted, each once.
pub type Report {
  Report(
    node: String,
    net_kernel: Service,
    epmd_client: Service,
    listening_ports: List(Int),
  )
}

/// Why a child gave no report.
pub type Failure {
  /// The child's VM ended before its report, with its exit status and what
  /// it wrote.
  Exited(status: Int, output: List(String))
  /// The child wrote nothing for the whole wait, so it is not ready.
  NotReady(output: List(String))
  /// A report that lacks a line the child writes, or has one it cannot read.
  Unreadable(line: String)
}

/// A running child: its operating system process, the epmd port made for it
/// and its report.
pub type Node {
  Node(process: Process, epmd_port: Int, report: Report)
}

/// The operating system process of a child, as the VM holds it.
pub type Process

/// What the child's output holds, line by line, as the test reads it.
type Event {
  Line(String)
  ExitStatus(Int)
  Silent
}

/// How the listening ports a node holds differ from the ports it should.
pub type Difference {
  Difference(unexpected: List(Int), missing: List(Int))
}

/// How long the child may write nothing, in milliseconds, from the start of
/// the VM through the start of the tree to the report. A deadline for a child
/// that hangs, never a wait: the report ends it.
const silence_limit_ms = 30_000

/// The line that ends a report.
const report_end = "report-end"

/// Starts the child, waits for its report and runs `body` with the node, or
/// with why there is no report. The child's input is closed, and the epmd the
/// child may have started is killed, however `body` ends.
pub fn run(start: Start, body: fn(Result(Node, Failure)) -> a) -> a {
  use tables <- planted_table.in_empty_tables_folder
  let epmd_port = free_port()
  let process = open(arguments(start), environment(start:, epmd_port:, tables:))
  with_cleanup(
    fn() {
      read_report(process, [])
      |> result.map(fn(report) { Node(process:, epmd_port:, report:) })
      |> body
    },
    fn() {
      close(process)
      kill_epmd(epmd_port)
    },
  )
}

/// The ports in `observed` that are not in `expected`, and the ports in
/// `expected` that are not in `observed`, each sorted.
pub fn compare_ports(
  observed observed: List(Int),
  expected expected: List(Int),
) -> Difference {
  Difference(
    unexpected: list.filter(observed, fn(port) {
      !list.contains(expected, port)
    })
      |> list.sort(int.compare),
    missing: list.filter(expected, fn(port) { !list.contains(observed, port) })
      |> list.sort(int.compare),
  )
}

/// Whether something accepts a connection on the epmd port made for a child.
pub fn epmd_answers(node: Node) -> Bool {
  accepts_connections(node.epmd_port)
}

/// The node names the epmd on the child's epmd port lists, none when there is
/// no epmd on it.
pub fn epmd_names(node: Node) -> List(String) {
  names_at(node.epmd_port)
}

fn arguments(start: Start) -> List(String) {
  let naming = case start.naming {
    Unnamed -> []
    ShortName(name:) -> ["-sname", name]
  }
  let program = case start.program {
    Server -> "server"
    Idle -> "idle"
  }
  let expression =
    "released_node_ffi:report("
    <> int.to_string(start.planted_listeners)
    <> ", "
    <> program
    <> ")."
  list.flatten([["-noshell"], naming, ["-eval", expression]])
}

/// The database's settings in the names the server reads them by, a folder of
/// the game tables and the child's own epmd port.
fn environment(
  start start: Start,
  epmd_port epmd_port: Int,
  tables tables: String,
) -> List(#(String, String)) {
  let settings = start.database.settings
  let password = case settings.password {
    option.Some(password) -> [#("PGPASSWORD", password)]
    option.None -> []
  }
  list.flatten([
    [
      #("PGHOST", settings.tcp_host),
      #("PGPORT", int.to_string(settings.port)),
      #("PGUSER", settings.user),
      #("PGDATABASE", start.database.name),
      #("GENESIS_TABLE_DIR", tables),
      #("ERL_EPMD_PORT", int.to_string(epmd_port)),
    ],
    password,
  ])
}

/// Reads the child's lines up to the end of its report. `seen` holds the lines
/// read before this call, newest first.
fn read_report(
  process: Process,
  seen: List(String),
) -> Result(Report, Failure) {
  case next_event(process, silence_limit_ms) {
    Line(line) if line == report_end -> parse(list.reverse(seen))
    Line(line) -> read_report(process, [line, ..seen])
    ExitStatus(status) -> Error(Exited(status:, output: list.reverse(seen)))
    Silent -> Error(NotReady(output: list.reverse(seen)))
  }
}

fn parse(lines: List(String)) -> Result(Report, Failure) {
  use node <- result.try(field(lines, "node"))
  use net_kernel <- result.try(field(lines, "net_kernel"))
  use net_kernel <- result.try(service(net_kernel))
  use epmd_client <- result.try(field(lines, "epmd_client"))
  use epmd_client <- result.try(service(epmd_client))
  use listening <- result.try(field(lines, "listening"))
  use listening_ports <- result.map(ports(listening))
  Report(node:, net_kernel:, epmd_client:, listening_ports:)
}

/// What follows `name` and a space on the line that starts with them, empty
/// when the line is only `name`.
fn field(lines: List(String), name: String) -> Result(String, Failure) {
  list.find_map(lines, fn(line) {
    case line == name, string.split_once(line, " ") {
      True, _ -> Ok("")
      False, Ok(#(first, rest)) if first == name -> Ok(rest)
      False, _ -> Error(Nil)
    }
  })
  |> result.replace_error(Unreadable(line: "no line for " <> name))
}

fn service(text: String) -> Result(Service, Failure) {
  case text {
    "running" -> Ok(Running)
    "stopped" -> Ok(Stopped)
    other -> Error(Unreadable(line: other))
  }
}

fn ports(text: String) -> Result(List(Int), Failure) {
  string.split(text, " ")
  |> list.filter(fn(word) { word != "" })
  |> list.try_map(fn(word) {
    int.parse(word) |> result.replace_error(Unreadable(line: word))
  })
}

/// Opens the child, an Erlang VM of the same installation as this one with
/// this VM's code paths outside OTP, running `arguments` with `environment`
/// added to this VM's own. Its output comes back through `next_event`; its
/// input closes when the process that opened it ends.
@external(erlang, "released_node_ffi", "open")
fn open(
  arguments: List(String),
  environment: List(#(String, String)),
) -> Process

/// The next event from the child, waiting at most `within` milliseconds.
@external(erlang, "released_node_ffi", "next_event")
fn next_event(process: Process, within: Int) -> Event

/// Closes the child's input, so it ends; nothing when it has ended already.
@external(erlang, "released_node_ffi", "close")
fn close(process: Process) -> Nil

/// A port on the loopback that nothing listens on.
@external(erlang, "released_node_ffi", "free_port")
fn free_port() -> Int

/// Runs `body`, then `cleanup`, also when `body` crashes.
@external(erlang, "released_node_ffi", "with_cleanup")
fn with_cleanup(body: fn() -> a, cleanup: fn() -> Nil) -> a

@external(erlang, "released_node_ffi", "accepts_connections")
fn accepts_connections(port: Int) -> Bool

@external(erlang, "released_node_ffi", "names_at")
fn names_at(port: Int) -> List(String)

/// Kills the epmd on `port`, if there is one, once no node is registered with
/// it. A child that is still ending is registered until its VM is gone, so
/// the kill is asked again, up to a deadline.
@external(erlang, "released_node_ffi", "kill_epmd")
fn kill_epmd(port: Int) -> Nil
