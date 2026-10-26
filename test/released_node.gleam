//// The server's entry point started in an operating system process of its
//// own, the way a release starts it, so a test can ask what that node is and
//// what it opens. The child is an Erlang VM with the build's code paths and
//// no `-name` or `-sname`, running `genesis_prime:main`, with the database
//// settings of one test's own database in its environment.
////
//// The child tells the test what it is in one report, written after the top
//// supervisor has finished starting every child, and then waits for its input
//// to close before it ends. The test that started a child owns it: the child
//// ends when the test's process does, however that happens.
////
//// Every child gets an epmd port of its own (`ERL_EPMD_PORT`), so a test can
//// see whether the child started or contacted an epmd, and no child touches
//// the epmd of the machine it runs on.

import template_database

/// How the child is started. `Unnamed` is how a release starts the server:
/// no `-name` and no `-sname`. `ShortName` plants a start that turns Erlang
/// distribution on, to show a test can tell the two apart.
pub type Naming {
  Unnamed
  ShortName(name: String)
}

/// What to start: the test's own database for the server's pool, how the
/// node is named, and how many extra listening sockets the child opens after
/// the tree is up, to show a test catches a listener the server did not
/// start.
pub type Start {
  Start(
    database: template_database.Database,
    naming: Naming,
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
  /// A report line that is not one the child writes.
  Unreadable(line: String)
}

/// A running child: its operating system process, the epmd port made for it
/// and its report.
pub type Node {
  Node(process: Process, epmd_port: Int, report: Report)
}

/// The operating system process of a child, as the VM holds it.
pub type Process

/// How the listening ports a node holds differ from the ports it should.
pub type Difference {
  Difference(unexpected: List(Int), missing: List(Int))
}

/// Starts the child, waits for its report and runs `body` with it. The child
/// is stopped, and the epmd the child may have started is killed, however
/// `body` ends.
pub fn run(_start: Start, _body: fn(Node) -> a) -> a {
  panic as "shape only: not built"
}

/// The ports in `observed` that are not in `expected`, and the ports in
/// `expected` that are not in `observed`, each sorted.
pub fn compare_ports(
  observed _observed: List(Int),
  expected _expected: List(Int),
) -> Difference {
  panic as "shape only: not built"
}

/// Whether something accepts a connection on the epmd port made for a child.
pub fn epmd_answers(_node: Node) -> Bool {
  panic as "shape only: not built"
}

/// The node names the epmd on the child's epmd port lists, none when there is
/// no epmd on it.
pub fn epmd_names(_node: Node) -> List(String) {
  panic as "shape only: not built"
}
