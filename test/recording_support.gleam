//// A relay in front of a planted server, for the tests of the recording relay:
//// a folder of its own, a listening server the test accepts on, and the relay
//// started with the loopback as its address. The test is the client and, by
//// accepting, the server's side too, so it sees both ends of a connection.

import genesis_prime/recording.{
  type Chunk, type Direction, type Header, type Recording, Header,
}
import genesis_prime/recording/listener.{type Listener}
import genesis_prime/recording/pipe.{Server}
import genesis_prime/recording/relay.{Settings}
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleam/time/calendar.{Date}
import mug
import seeded
import simplifile

/// The longest chunk an exchange sends. A single process plays both ends, so a
/// chunk must fit in the operating system's socket buffers along the way.
const longest_chunk = 20_000

/// A running relay in front of a planted server.
pub type Session {
  Session(relay_port: Int, folder: String, header: Header, server: Listener)
}

/// Both ends of one connection through the relay: the client's socket, and the
/// socket the planted server accepted from the relay.
pub type Ends {
  Ends(client: mug.Socket, server: mug.Socket)
}

/// The header every planted session records: the client's build, a date, the
/// game role and a commit of 40 hexadecimal digits.
pub fn header() -> Header {
  Header(
    build: 16_042,
    date: Date(2026, calendar.October, 26),
    role: recording.Game,
    commit: "0123456789abcdef0123456789abcdef01234567",
    seed: None,
  )
}

/// A new folder under `build/` that no other test uses, made empty.
pub fn new_folder() -> String {
  let folder =
    "build/recording_test/"
    <> string.lowercase(bit_array.base16_encode(crypto.strong_random_bytes(8)))
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
    as "the test's folder was not made"
  folder
}

/// Runs `body` with a relay in a new folder under `build/`, and removes the
/// folder after.
pub fn run(body: fn(Session) -> a) -> a {
  let folder = new_folder()
  let assert Ok(server) = listener.listen(bind: listener.Loopback, port: 0)
    as "the planted server did not listen"
  let assert Ok(server_port) = listener.port(server)
    as "the planted server has no port"
  let assert Ok(started) =
    relay.start(Settings(
      bind: listener.Loopback,
      listen_port: 0,
      server: Server(host: "127.0.0.1", port: server_port),
      folder:,
      header: header(),
      connections: process.new_name("recording_connections"),
    ))
    as "the relay did not start"
  let result =
    body(Session(relay_port: started.port, folder:, header: header(), server:))
  let assert Ok(Nil) = simplifile.delete(folder)
    as "the test's folder was not removed"
  result
}

/// Opens a client connection through the relay and accepts it on the planted
/// server, waiting for each at most `wait_ms` milliseconds.
pub fn connect(session session: Session, wait_ms wait_ms: Int) -> Ends {
  let assert Ok(client) =
    mug.new("127.0.0.1", port: session.relay_port)
    |> mug.ip_version_preference(mug.Ipv4Only)
    |> mug.timeout(wait_ms)
    |> mug.connect
    as "the client did not connect to the relay"
  let assert Ok(server) =
    listener.accept_within(session.server, within: wait_ms)
    as "the relay did not connect to the planted server"
  Ends(client:, server:)
}

/// Plays `rounds` rounds over a connection. In each, the client sends random
/// bytes and the server must receive exactly those bytes, and then the server
/// sends random bytes and the client must receive exactly those. The bytes and
/// their lengths (1 to 20,000) come from `seed`, so a failing run repeats.
/// Returns each round's client bytes and server bytes, in order.
pub fn exchange(
  ends ends: Ends,
  seed seed: Int,
  rounds rounds: Int,
  wait_ms wait_ms: Int,
) -> List(#(BitArray, BitArray)) {
  let #(played, _) =
    int.range(from: 0, to: rounds, with: #([], seed), run: fn(state, round) {
      let #(played, random) = state
      let label = "round " <> int.to_string(round)
      let #(client_bytes, random) = random_bytes(random)
      let #(server_bytes, random) = random_bytes(random)
      assert mug.send(ends.client, client_bytes) == Ok(Nil)
        as { label <> ": the client's bytes were not sent" }
      assert mug.receive_exact(
          ends.server,
          byte_size: bit_array.byte_size(client_bytes),
          timeout_milliseconds: wait_ms,
        )
        == Ok(client_bytes)
        as { label <> ": the server did not receive the client's bytes" }
      assert mug.send(ends.server, server_bytes) == Ok(Nil)
        as { label <> ": the server's bytes were not sent" }
      assert mug.receive_exact(
          ends.client,
          byte_size: bit_array.byte_size(server_bytes),
          timeout_milliseconds: wait_ms,
        )
        == Ok(server_bytes)
        as { label <> ": the client did not receive the server's bytes" }
      #([#(client_bytes, server_bytes), ..played], random)
    })
  list.reverse(played)
}

fn random_bytes(state: Int) -> #(BitArray, Int) {
  let #(length, state) = seeded.up_to(state:, most: longest_chunk - 1)
  seeded.bytes(state:, count: length + 1)
}

/// The recordings in the session's folder, in the order of their file names.
pub fn recordings(session: Session) -> List(Recording) {
  let assert Ok(names) = simplifile.read_directory(session.folder)
    as "the session's folder could not be listed"
  list.sort(names, string.compare)
  |> list.map(fn(name) {
    let assert Ok(recording) = recording.read(session.folder <> "/" <> name)
      as { "the recording " <> name <> " did not read" }
    recording
  })
}

/// The chunks joined into runs of one direction: each run is its direction and
/// the bytes of its chunks one after another. A relay records a packet as the
/// socket delivers it, so the number of chunks in a run is not the number of
/// sends.
pub fn runs(chunks: List(Chunk)) -> List(#(Direction, BitArray)) {
  list.fold(chunks, [], fn(runs, chunk) {
    case runs {
      [#(direction, bytes), ..earlier] if direction == chunk.direction -> [
        #(direction, <<bytes:bits, chunk.bytes:bits>>),
        ..earlier
      ]
      _ -> [#(chunk.direction, chunk.bytes), ..runs]
    }
  })
  |> list.reverse
}
