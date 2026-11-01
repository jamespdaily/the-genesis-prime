//// How the server takes the end of its tree. Expected values come from these
//// places.
//// - OTP: a supervisor that exceeds its restart intensity ends with the reason
////   `shutdown`, the reason the application's root gives a tree it stops, so
////   the reason cannot tell a failure from a stop. `init:stop` sets the node's
////   status to `stopping` before it stops any application, so only a node that
////   is stopping ends its tree in order.
//// - The card: a tree that ends while the node runs ends the node with status
////   1, and a tree that ends because the node stops does not.
//// The test VM is not stopping, so what a node that is stopping does is read
//// through `ending`'s argument; the nodes of `sigterm_test` show the real stop.

import ask_support
import genesis_prime/application.{Fatal, Orderly, Tree}
import gleam/dynamic
import gleam/erlang/atom
import gleam/erlang/process
import owned_test

fn shutdown() -> process.ExitReason {
  process.Abnormal(atom.to_dynamic(atom.create("shutdown")))
}

pub fn a_tree_that_ends_while_the_node_stops_ends_in_order_whatever_the_reason_test() -> Nil {
  use <- owned_test.run(5000)
  assert application.ending(reason: shutdown(), node_stopping: True) == Orderly
  assert application.ending(reason: process.Normal, node_stopping: True)
    == Orderly
  assert application.ending(reason: process.Killed, node_stopping: True)
    == Orderly
}

pub fn a_tree_that_ends_while_the_node_runs_is_fatal_whatever_the_reason_test() -> Nil {
  use <- owned_test.run(5000)
  assert application.ending(reason: shutdown(), node_stopping: False)
    == Fatal(reason: shutdown())
    as "a tree past its restart intensity ends with shutdown, which is no stop"
  assert application.ending(reason: process.Normal, node_stopping: False)
    == Fatal(reason: process.Normal)
  assert application.ending(
      reason: process.Abnormal(dynamic.string("boom")),
      node_stopping: False,
    )
    == Fatal(reason: process.Abnormal(dynamic.string("boom")))
}

pub fn the_end_of_the_tree_while_the_node_runs_crashes_the_process_that_takes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let taker = process.spawn_unlinked(fn() { application.end_of(shutdown()) })
  let assert process.Abnormal(_) = ask_support.ended(process.monitor(taker))
    as "taking the end of a tree while the node is not stopping crashes, so the node ends with status 1"
  Nil
}

pub fn a_tree_serves_while_it_runs_and_the_node_is_not_stopping_test() -> Nil {
  use <- owned_test.run(10_000)
  let pid = process.spawn_unlinked(process.sleep_forever)
  let tree = Tree(pid:, monitor: process.monitor(pid))
  assert application.serving(tree) as "a tree that runs on a node that runs"
  process.kill(pid)
  let _reason = ask_support.ended(tree.monitor)
  assert !application.serving(tree) as "a tree that has ended does not serve"
}
