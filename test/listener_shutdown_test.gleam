//// A listener and its connections in the ordered stop. Expected values come
//// from three places.
//// - The shutdown module's contract: a listener registers `Listener`, whose
////   `stop_accepting` returns once the listener refuses new connections, and
////   each connection registers `Connection`, whose `close` makes the
////   connection end, all before the drain deadline; `shutdown.stop` is what a
////   SIGTERM asks for, and the outcome is sent once every step has run.
//// - The network: a connection to a port that nothing listens on is refused,
////   and a peer that closes a connection is seen by the other end as closed.
//// - OTP: a process that stops itself ends with the reason `normal`, and one
////   that is killed with `killed`.
////
//// Every test waits for events: the outcome the coordinator sends once the
//// order has run, a closed socket, the end of a process. The drain deadline of
//// the test coordinator is long, so a connection that did not close when told
//// would fail the test by its own deadline.

import genesis_prime/shutdown.{Stopped}
import gleam/erlang/process
import listening.{Received}
import owned_test
import tcp_client

/// How long a test waits for the coordinator to report the outcome of the
/// order, in milliseconds.
const outcome_wait_ms = 5000

/// How long a test waits for a client to see its connection closed, in
/// milliseconds.
const close_wait_ms = 2000

pub fn a_listener_refuses_new_connections_once_the_order_has_run_and_does_not_start_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(listening.config())
  let acceptor = process.monitor(running.acceptor)
  shutdown.stop(running.shutdown)
  assert process.receive(running.shutdown.finished, outcome_wait_ms)
    == Ok(Stopped(failures: []))
    as "the order ran with a listener registered, and it must not fail"
  assert tcp_client.connect(running.port) == Error(Nil)
    as "a listener that stopped accepting refuses a new connection"
  assert listening.await_down(acceptor) == Ok(process.Normal)
    as "an acceptor that was told to stop ends normally, so its supervisor does not start it again on a new port"
}

pub fn each_open_connection_is_closed_by_the_order_before_the_drain_deadline_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(listening.config())
  let first = listening.connect(running)
  let second = listening.connect(running)
  // A frame handed to the handler shows its owner exists, and so is
  // registered: an owner registers from its initialiser.
  let assert Ok(Nil) =
    tcp_client.send(first, listening.frame_of(message_id: 1, size: 0))
  let assert Ok(Received(owner: first_owner, ..)) = listening.next(running)
    as "the first connection was not accepted"
  let assert Ok(Nil) =
    tcp_client.send(second, listening.frame_of(message_id: 2, size: 0))
  let assert Ok(Received(owner: second_owner, ..)) = listening.next(running)
    as "the second connection was not accepted"
  let first_monitor = process.monitor(first_owner)
  let second_monitor = process.monitor(second_owner)
  shutdown.stop(running.shutdown)
  assert tcp_client.await_close(first, close_wait_ms)
    as "an open connection is closed when the order runs"
  assert tcp_client.await_close(second, close_wait_ms)
    as "every open connection is closed when the order runs"
  assert listening.await_down(first_monitor) == Ok(process.Normal)
    as "a connection told to close ends itself, not killed at the deadline"
  assert listening.await_down(second_monitor) == Ok(process.Normal)
    as "every connection told to close ends itself, not killed at the deadline"
  assert process.receive(running.shutdown.finished, outcome_wait_ms)
    == Ok(Stopped(failures: []))
    as "the order ends once every connection has closed"
}
