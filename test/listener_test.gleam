//// The listener's connection cap. The expected values come from the rule the
//// cap states: a listener serves at most `connection_cap` connections at
//// once and refuses the next one by closing it. Every test waits for the
//// events it needs: a frame the handler reports, a closed socket.

import gleam/erlang/process
import listening.{Config}
import owned_test
import tcp_client

/// How long a test waits for a refused connection to be closed, in
/// milliseconds.
const close_wait_ms = 2000

pub fn a_connection_under_the_cap_is_accepted_and_the_one_past_it_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(Config(..listening.config(), connection_cap: 2))
  let first = listening.connect(running)
  let assert Ok(Nil) =
    tcp_client.send(first, listening.frame_of(message_id: 1, size: 0))
  let assert Ok(_) = listening.next(running)
    as "the first connection, under the cap of 2, was not accepted"
  let second = listening.connect(running)
  let assert Ok(Nil) =
    tcp_client.send(second, listening.frame_of(message_id: 2, size: 0))
  let assert Ok(_) = listening.next(running)
    as "the second connection, the last under the cap of 2, was not accepted"
  let third = listening.connect(running)
  assert tcp_client.await_close(third, close_wait_ms)
    as "a cap of 2 serves 2 connections, so the third is refused by closing it"
  tcp_client.send_if_open(third, listening.frame_of(message_id: 3, size: 0))
  assert process.receive(running.frames, 0) == Error(Nil)
    as "a refused connection never reaches the handler"
  tcp_client.close(first)
  tcp_client.close(second)
}
