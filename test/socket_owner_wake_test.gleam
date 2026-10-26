//// A conversation the socket's owner wakes with messages from other
//// processes, as a game connection is woken by a map's deliveries. Expected
//// values come from the designing-processes skill: one process owns each piece
//// of state, so what a message from another process does to a connection is
//// done in the connection's own process, in order with what the socket reads,
//// and a connection's state is its own alone.
//// Every test waits for the events it needs: bytes the client receives, the
//// end of the connection.

import genesis_prime/connection/socket_owner.{
  type Conversation, Frames, Protocol, Reaction, Waking,
}
import gleam/erlang/process.{type Subject}
import listening
import owned_test
import serving
import tcp_client

/// How long a test waits for a read of the client that must come at once, in
/// milliseconds.
const read_wait_ms = 2000

/// A conversation that counts what it handles, the socket's frames and the
/// numbers sent to `inbox`, and answers each with a byte holding the count.
/// A message that closes the connection is the number 0.
fn counting(count: Int, inbox: Subject(Int)) -> Conversation {
  Waking(
    handle: fn(_input) {
      let counted = count + 1
      Reaction(
        send: [<<counted>>],
        close: False,
        next: counting(counted, inbox),
      )
    },
    wake: process.new_selector()
      |> process.select_map(inbox, fn(number) {
        case number {
          0 -> Reaction(send: [], close: True, next: counting(count, inbox))
          _ -> {
            let counted = count + 1
            Reaction(
              send: [<<number, counted>>],
              close: False,
              next: counting(counted, inbox),
            )
          }
        }
      }),
  )
}

/// A protocol whose connection makes its inbox in the owner's process, as a
/// game connection makes its subject for a map's deliveries, and tells the test
/// where it is.
fn serve(inboxes: Subject(Subject(Int))) -> serving.Running {
  serving.start(
    Protocol(mode: Frames, connect: fn(_peer) {
      let inbox = process.new_subject()
      process.send(inboxes, inbox)
      Reaction(send: [], close: False, next: counting(0, inbox))
    }),
    fn(settings) { settings },
  )
}

fn client_receives(client: tcp_client.Client, count: Int) -> BitArray {
  let assert Ok(bytes) = tcp_client.receive(client, count, read_wait_ms)
    as "the server did not write the bytes"
  bytes
}

pub fn a_message_to_the_owner_wakes_the_conversation_and_its_reaction_is_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let inboxes = process.new_subject()
  let running = serve(inboxes)
  let client = serving.connect(running)
  let assert Ok(inbox) = process.receive(inboxes, serving.event_wait_ms)
    as "the connection made its inbox"
  process.send(inbox, 7)
  assert client_receives(client, 2) == <<7, 1>>
    as "what another process sent is handled in the owner, and its reaction written"
}

pub fn a_wakes_reaction_brings_the_next_conversation_with_its_own_state_test() -> Nil {
  use <- owned_test.run(10_000)
  let inboxes = process.new_subject()
  let running = serve(inboxes)
  let client = serving.connect(running)
  let assert Ok(inbox) = process.receive(inboxes, serving.event_wait_ms)
    as "the connection made its inbox"
  process.send(inbox, 5)
  assert client_receives(client, 2) == <<5, 1>>
  let frame = listening.frame_of(message_id: 0x0637, size: 0)
  let assert Ok(Nil) = tcp_client.send(client, frame)
    as "the client sends a frame"
  assert client_receives(client, 1) == <<2>>
    as "a frame read after a wake counts from the state the wake left"
  process.send(inbox, 6)
  assert client_receives(client, 2) == <<6, 3>>
    as "a wake after a frame counts from the state the frame left"
}

pub fn a_wake_that_closes_closes_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let inboxes = process.new_subject()
  let running = serve(inboxes)
  let client = serving.connect(running)
  let assert Ok(inbox) = process.receive(inboxes, serving.event_wait_ms)
    as "the connection made its inbox"
  process.send(inbox, 0)
  assert tcp_client.await_close(client, read_wait_ms)
    as "a reaction that closes ends the connection however it was made"
}
