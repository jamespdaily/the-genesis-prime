//// The address a connection reached the server from. The expected value is
//// the issue's test 1, "keyed so that a replay can find a connection's own
//// draws": the recording server names a draw's connection by the peer address
//// of its socket (`socket.peer`, as text), which for a connection through the
//// relay is the address the relay connected to the server from. The relay
//// writes that address beside each recording, so a replay finds the draws of
//// the connection a recording was made by.
////
//// The planted server's own side of the connection gives the address the server
//// sees, written by the same function the server uses for its log and its
//// draws.

import genesis_prime/recording/session
import gleam/option.{type Option, Some}
import mug
import owned_test
import recording_support

/// How long one wait for an event may take, in milliseconds.
const event_wait_ms = 5000

/// The peer address of a socket as text, as the server writes it.
@external(erlang, "genesis_prime_socket_ffi", "peer")
fn peer(socket: mug.Socket) -> Option(String)

pub fn the_relay_writes_the_address_it_connected_from_beside_each_recording_test() -> Nil {
  use <- owned_test.run(30_000)
  use relay_session <- recording_support.run
  let first =
    recording_support.connect(session: relay_session, wait_ms: event_wait_ms)
  let second =
    recording_support.connect(session: relay_session, wait_ms: event_wait_ms)
  let assert Some(first_peer) = peer(first.server)
    as "the first connection has a peer"
  let assert Some(second_peer) = peer(second.server)
    as "the second connection has a peer"
  // The relay passes a chunk only after it has written the recording and the
  // address beside it, so once a round has gone through both are in the folder.
  recording_support.exchange(
    ends: first,
    seed: 1,
    rounds: 1,
    wait_ms: event_wait_ms,
  )
  recording_support.exchange(
    ends: second,
    seed: 2,
    rounds: 1,
    wait_ms: event_wait_ms,
  )
  assert first_peer != second_peer
    as "two open connections have two addresses, so a draw's connection is told apart"

  assert session.read_connection(
      recording_path: relay_session.folder <> "/game-001.recording",
    )
    == Ok(first_peer)
    as "the file beside the first recording holds the address the server sees for that connection"
  assert session.read_connection(
      recording_path: relay_session.folder <> "/game-002.recording",
    )
    == Ok(second_peer)
    as "the file beside the second recording holds the address the server sees for that connection"
}
