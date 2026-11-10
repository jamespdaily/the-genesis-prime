//// How a node that serves the server ends. Expected values come from these
//// places.
//// - CLAUDE.md and the designing-processes skill: shutdown is ordered, so a
////   stopping server gives every process its `Stopping`, and a recorded
////   connection closes its recording with its closing line, naming the server
////   as the side that closed it (`genesis_prime/step/runtime`).
//// - OTP: SIGTERM makes the VM run `init:stop`, which stops the applications
////   in order, so the server, started as the application and its tree under
////   the application's root, stops through OTP, and the VM halts with status
////   0. A node whose program crashes while it runs ends with status 1
////   (`genesis_prime@@main`, which `gleam run` starts the server with).
//// - The tree's restart limit (`genesis_prime/server`, the settings'
////   `tree_restarts`; the server's is 3 restarts in 10 seconds, the test's
////   node has an hour as its period): a fourth restart in the period ends the
////   tree with the reason `shutdown`, the reason of a stop too, so only the
////   node's own state tells the two ends apart.
//// - The ready line is printed only when the server can serve: the database
////   answered and no stop has begun.
//// - OTP's `init` (`init:stop`): it stops the applications, then closes the
////   kernel's processes, `user` among them, and kills every process left, so a
////   program still running then dies after the node's output is closed. A node
////   ended by SIGTERM prints no error of that: neither "Failed to eval" nor a
////   `badarg`, which `genesis_prime@@main:run` prints for a program that was
////   killed. The race needs a loaded machine to show, so one test ends several
////   nodes in a row.
//// Each test starts a node of its own (`serving_node`), sends it SIGTERM or
//// lets it fail, and reads what it printed, the recording it left and how it
//// ended.

import database_support
import genesis_prime/wire_recording.{Recording, Server}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import recording_support
import serving_node.{GivesUp, Serving, SlowStop, UnreachableDatabase}
import simplifile

/// What the node prints when the server can serve: the start of its ready
/// line.
const ready_line = "serves the STS login on port"

/// How long a node has to start or to end; a passing test never reaches it.
const node_wait_ms = 60_000

/// A node in `mode` on a database of its own, recording into a folder of its
/// own, handed to `body` with the folder.
fn with_node(
  mode: serving_node.Mode,
  body: fn(serving_node.Node, String) -> a,
) -> a {
  use folder <- recording_support.in_folder
  let database = database_support.new_database(on: database_support.shared())
  body(serving_node.start(mode:, folder:, database:), folder)
}

/// Fails the test when the node printed that its tree ended while it ran or
/// that its program crashed: a stop that went in order prints neither, and the
/// status alone cannot tell, since a node already stopping keeps the status 0
/// its first stop set.
fn assert_no_crash(node: serving_node.Node) -> Nil {
  let printed = serving_node.output(node)
  assert !string.contains(
    printed,
    "the supervision tree ended while the node runs",
  )
    as "the node took the end of its tree as orderly, not as a failure"
  assert !string.contains(printed, "runtime error")
    as "the node's program did not crash"
}

/// The side that closed each recording in the folder, which must be whole: a
/// file whose closing line is missing is no recording of a process that was
/// stopped in order.
fn closed_by(folder: String) -> List(wire_recording.Side) {
  let assert Ok(names) = simplifile.read_directory(folder)
    as "the recording folder reads"
  list.map(names, fn(name) {
    let assert Ok(text) = simplifile.read(folder <> "/" <> name)
      as "a recording reads"
    let assert Ok(Recording(closing: Some(closing), ..)) =
      wire_recording.read(text)
      as { name <> " is whole: the stop reached its process" }
    closing.by
  })
}

pub fn sigterm_stops_the_server_through_otp_and_its_recording_ends_with_its_closing_line_test() -> Nil {
  use <- owned_test.run(120_000)
  use node, folder <- with_node(Serving)
  assert serving_node.await_output(node, ready_line, node_wait_ms)
    as "the node printed its ready line"
  assert serving_node.await_output(
    node,
    "a connection is recorded",
    node_wait_ms,
  )
    as "the node holds a connection to its STS listener, and the shell has opened its recording"
  serving_node.terminate(node)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
    as "SIGTERM ends the node with status 0"
  assert_no_crash(node)
  assert closed_by(folder) == [Server]
    as "the connection's recording ends with its closing line, the server as the side that closed it: the stop reached its process"
  let printed = serving_node.output(node)
  assert string.contains(printed, "every listener stopped accepting")
    as "the closer, the tree's first child to stop, closed the listeners"
  assert string.contains(printed, "the server stopped")
    as "the application's stop callback ran: the stop went through OTP"
}

pub fn sigterm_before_the_ready_line_ends_the_node_with_status_0_and_no_ready_line_test() -> Nil {
  use <- owned_test.run(120_000)
  use node, folder <- with_node(UnreachableDatabase)
  assert serving_node.await_output(node, "the tree started", node_wait_ms)
    as "the tree started under the application"
  serving_node.terminate(node)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
    as "SIGTERM while the readiness ask waits ends the node with status 0"
  assert_no_crash(node)
  assert closed_by(folder) == []
    as "no connection was made, so no recording is left without its closing line"
  assert !string.contains(serving_node.output(node), ready_line)
    as "no ready line is printed for a server that was stopped"
}

/// How many nodes the repeated SIGTERM test ends one after the other.
const repeated_nodes = 6

pub fn repeated_sigterm_before_the_ready_line_leaves_no_error_in_the_nodes_output_test() -> Nil {
  use <- owned_test.run(120_000)
  int.range(from: 1, to: repeated_nodes + 1, with: Nil, run: fn(_, attempt) {
    use node, _folder <- with_node(UnreachableDatabase)
    assert serving_node.await_output(node, "the tree started", node_wait_ms)
      as "the tree started under the application"
    serving_node.terminate(node)
    assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
      as "SIGTERM while the readiness ask waits ends the node with status 0"
    let printed = serving_node.output(node)
    let which = "node " <> int.to_string(attempt) <> " printed: " <> printed
    assert !string.contains(printed, "Failed to eval") as which
    assert !string.contains(printed, "badarg") as which
    assert !string.contains(printed, "runtime error") as which
  })
}

pub fn sigterm_while_the_probe_is_slow_prints_no_ready_line_test() -> Nil {
  use <- owned_test.run(120_000)
  use node, _folder <- with_node(SlowStop)
  assert serving_node.await_output(node, "probing", node_wait_ms)
    as "the readiness ask asked, with Sessions suspended so the stop takes its time"
  serving_node.terminate(node)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
    as "SIGTERM ends the node with status 0"
  assert_no_crash(node)
  assert !string.contains(serving_node.output(node), ready_line)
    as "the probe answered after the stop had begun and the tree was still ending: no ready line"
}

pub fn a_tree_that_gives_up_while_the_node_runs_ends_the_node_with_status_1_test() -> Nil {
  use <- owned_test.run(120_000)
  use node, _folder <- with_node(GivesUp)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(1)
    as "a tree that ends while the node is not stopping is fatal, though it ends with shutdown, so the host restarts the node"
  assert string.contains(
    serving_node.output(node),
    "the supervision tree ended while the node runs",
  )
    as "the node says why it ended"
}
