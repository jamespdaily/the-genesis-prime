//// How a node that serves the server ends. Expected values come from these
//// places.
//// - CLAUDE.md and the designing-processes skill: shutdown is ordered, so a
////   stopping server gives every process its `Stopping`, and a recorded
////   process closes its recording with `End` (`genesis_prime/step/runtime`).
//// - OTP: SIGTERM makes the VM run `init:stop`, which stops the applications
////   in order, so the server, started as the application and its tree under
////   the application's root, stops through OTP, and the VM halts with status
////   0. A node whose program crashes while it runs ends with status 1
////   (`genesis_prime@@main`, which `gleam run` starts the server with).
//// - The tree's restart limit, 3 restarts in 10 seconds
////   (`genesis_prime/server`): a fourth restart in that time ends the tree
////   with the reason `shutdown`, the reason of a stop too, so only the node's
////   own state tells the two ends apart.
//// - The ready line is printed only when the server can serve: the database
////   answered and no stop has begun.
//// Each test starts a node of its own (`serving_node`), sends it SIGTERM or
//// lets it fail, and reads what it printed, the recording it left and how it
//// ended.

import database_support
import genesis_prime/rule_recording.{type Record, End}
import genesis_prime/sessions
import genesis_prime/step.{type ServiceEffect, type ServiceEvent}
import gleam/list
import gleam/string
import owned_test
import recording_support
import serving_node.{GivesUp, Serving, SlowStop, UnreachableDatabase}

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

/// Whether Sessions' recording in the folder ends with `End` that counts the
/// records before it.
fn ends_with_end(folder: String) -> Bool {
  let assert Ok(#(_, records)) =
    rule_recording.read(recording_support.recording_in(folder))
    as "the recording reads"
  let records: List(
    Record(
      sessions.Message,
      Nil,
      sessions.Outgoing,
      Nil,
      ServiceEvent(sessions.Message),
      ServiceEffect(sessions.Outgoing),
    ),
  ) = records
  case list.last(records) {
    Ok(End(count:)) -> count == list.length(records) - 1
    Ok(_) | Error(Nil) -> False
  }
}

pub fn sigterm_stops_the_server_through_otp_and_its_recording_ends_with_end_test() -> Nil {
  use <- owned_test.run(120_000)
  use node, folder <- with_node(Serving)
  assert serving_node.await_output(node, ready_line, node_wait_ms)
    as "the node printed its ready line"
  serving_node.terminate(node)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
    as "SIGTERM ends the node with status 0"
  assert_no_crash(node)
  assert ends_with_end(folder)
    as "the recording Sessions kept ends with End: the stop reached its process"
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
  assert ends_with_end(folder) as "no recording is left without End"
  assert !string.contains(serving_node.output(node), ready_line)
    as "no ready line is printed for a server that was stopped"
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
