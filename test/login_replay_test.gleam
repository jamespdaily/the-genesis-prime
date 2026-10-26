//// A recorded login session replayed over TCP against the real listeners the
//// server's tree starts. The expected values are the issue's tests 4 and 5.
//// - A login whose random values come from a seed can be played again: the
////   scripted client logs in through the recording relay against a server
////   started with a seed, and the two recordings of the session (the STS
////   connection and the auth connection, `sts-001` and `auth-001`) replay
////   against a new server started with the seed the recordings name, every
////   server chunk matching. A server answer that differs by one byte fails
////   the replay at that byte, named by its offset in the stream of what the
////   server sent.
//// - A login whose random values were drawn fresh cannot: the live recording of
////   2026-10-26 (`test/recording/2026-10-26-login/`, made with the real client
////   against an unseeded server) replays up to the reply that carries the
////   server's SRP value B, whose bytes (the salt, and B, which depends on the
////   server's secret b) differ on a new server, and there the replay stops with
////   the offset of the first byte that differs. The reply is the XML of the
////   STS library (`Reply`, `KeyData`) as the recording holds it; the live
////   account is `jimtest`, and the replay supplies no password.
////
//// Every wait is for bytes the server writes or for the socket to close; the
//// deadlines are for a server that does not answer, never a pause. The new
//// server shares the recording server's database, so the account's salt and
//// verifier, which the account store draws from the operating system when it
//// creates an account, are the same.

import genesis_prime/login/account_store
import genesis_prime/login/random_source.{type RandomSource, Strong}
import genesis_prime/login/service
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/recording.{
  type Chunk, type Recording, Auth, Chunk, Header, Recording, ServerToClient,
  Sts,
}
import genesis_prime/recording/listener
import genesis_prime/recording/pipe.{Server}
import genesis_prime/recording/relay
import genesis_prime/seeded_random
import genesis_prime/server
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor
import gleam/string
import login_client.{type Ports, Ports}
import owned_test
import recording_support
import replay.{Differs, Target}
import template_database

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// The game listener the hand-off names: the loopback address and a port. No
/// game listener runs on it, as the hand-off only names it.
const game_address = 0x7F000001

const game_port = 24_000

/// The seed of the server a session is recorded on.
const recorded_seed = 72

/// The live recording of the first session with the real client.
const live_folder = "test/recording/2026-10-26-login/"

/// A source that draws the sequence of `seed`, in a process the test's
/// supervisor owns.
fn seeded(seed: Int) -> RandomSource {
  let name = process.new_name("replay_seeded_source")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(seeded_random.supervised(name:, seed:))
    |> static_supervisor.start
    as "the seeded source did not start"
  seeded_random.source(name)
}

/// Starts a server's tree on the test's database, its login drawing from the
/// sequence of `seed`, or from the operating system when there is none, and
/// returns the ports of its two login listeners.
fn start(database: template_database.Database, seed: Option(Int)) -> Ports {
  let pool_settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("login_replay_pool"),
      pool_size: 2,
    )
  let defaults = template_database.tree_settings(pool_settings)
  let random = case seed {
    Some(seed) -> seeded(seed)
    None -> Strong
  }
  let ports = process.new_subject()
  let login =
    service.Settings(
      ..service.settings(
        sts_port: 0,
        auth_port: 0,
        game_server: Endpoint(address: game_address, port: game_port),
        realm_name: "Nexus",
        expected_files_digest: None,
        random:,
      ),
      sts: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("sts", port))
      }),
      auth: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("auth", port))
      }),
    )
  let assert Ok(_) = server.start(server.Settings(..defaults, login:))
    as "the server's tree did not start"
  let assert Ok(first) = process.receive(ports, wait_ms)
    as "a login listener did not open"
  let assert Ok(second) = process.receive(ports, wait_ms)
    as "the other login listener did not open"
  let reported =
    list.sort([first, second], fn(left, right) {
      string.compare(left.0, right.0)
    })
  let assert [#("auth", auth_port), #("sts", sts_port)] = reported
    as "one listener serves the auth login and one the STS login"
  Ports(sts_port:, auth_port:)
}

/// A relay that passes each connection to `port` and writes its recording into
/// `folder`, its header naming `role` and the seed of the server behind it.
fn relay_to(
  port port: Int,
  role role: recording.Role,
  folder folder: String,
) -> relay.Relay {
  let assert Ok(started) =
    relay.start(relay.Settings(
      bind: listener.Loopback,
      listen_port: 0,
      server: Server(host: "127.0.0.1", port:),
      folder:,
      header: Header(
        ..recording_support.header(),
        role:,
        seed: Some(recorded_seed),
      ),
      connections: process.new_name("login_replay_relay"),
    ))
    as "the relay did not start"
  started
}

/// The two connections of one login session, as the relay recorded them.
type Session {
  Session(sts: Recording, auth: Recording)
}

/// The scripted client logs in as `jim` through two relays, one for each
/// listener of a server seeded with `seed`, to the hand-off of the auth
/// server, and returns what the relays recorded. The account `jim` exists on
/// `database`.
fn record_session(database: template_database.Database) -> Session {
  let recorded = start(database, Some(recorded_seed))
  let folder = recording_support.new_folder()
  let sts_relay = relay_to(port: recorded.sts_port, role: Sts, folder:)
  let auth_relay = relay_to(port: recorded.auth_port, role: Auth, folder:)
  let ports = Ports(sts_port: sts_relay.port, auth_port: auth_relay.port)
  let login =
    login_client.sts_login(ports:, name: "jim", password: "secret", seed: 0x39)
  let socket = login_client.auth_login(ports:, login:, build: 16_042)
  assert list.length(login_client.read_frames(
      client: socket,
      have: <<>>,
      count: 2,
    ))
    == 2
    as "the recorded session ran to the auth server's 0x591 and 0x3DB"
  // The relay writes a chunk before it passes it on, so what the client has
  // read is in the files.
  let assert Ok(sts) = recording.read(from: folder <> "/sts-001.recording")
    as "the STS connection was recorded"
  let assert Ok(auth) = recording.read(from: folder <> "/auth-001.recording")
    as "the auth connection was recorded"
  Session(sts:, auth:)
}

pub fn a_seeded_session_replays_over_tcp_to_its_end_against_a_new_server_with_the_same_seed_test() -> Nil {
  use <- owned_test.run(120_000)
  use database <- template_database.run
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let session = record_session(database)
  assert session.sts.header.seed == Some(recorded_seed)
    as "the STS recording names the seed it was recorded on"
  assert session.auth.header.seed == Some(recorded_seed)
    as "the auth recording names the seed it was recorded on"

  // The new server starts with the seed the recording names, as a replay of a
  // session does.
  let replayed = start(database, session.sts.header.seed)
  assert replay.run(
      recording: session.sts,
      target: Target("127.0.0.1", replayed.sts_port),
      deadline_ms: wait_ms,
    )
    == Ok(Nil)
    as "every server chunk of the STS connection matches, the SRP value and the game token among them"
  assert replay.run(
      recording: session.auth,
      target: Target("127.0.0.1", replayed.auth_port),
      deadline_ms: wait_ms,
    )
    == Ok(Nil)
    as "every server chunk of the auth connection matches, the session key among them"
}

pub fn a_server_answer_that_differs_by_one_byte_fails_the_replay_at_that_byte_test() -> Nil {
  use <- owned_test.run(120_000)
  use database <- template_database.run
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let session = record_session(database)

  // The last server chunk of the STS connection, which is under the session
  // cipher, has one byte in its middle changed: the server's answer then
  // differs from the recording's at the byte's offset in the stream of
  // everything the server sent.
  let assert Ok(#(position, Chunk(direction, time, original))) =
    last_server_chunk(session.sts)
    as "the STS connection has server chunks"
  let index = bit_array.byte_size(original) / 2
  let assert Ok(before) = bit_array.slice(original, 0, index)
    as "the index is inside the chunk"
  let assert Ok(<<recorded>>) = bit_array.slice(original, index, 1)
    as "the index is inside the chunk"
  let assert Ok(after) =
    bit_array.slice(
      original,
      index + 1,
      bit_array.byte_size(original) - index - 1,
    )
    as "the rest is inside the chunk"
  let altered = 255 - recorded
  let changed = Chunk(direction, time, <<before:bits, altered, after:bits>>)
  let edited =
    Recording(
      ..session.sts,
      chunks: list.index_map(session.sts.chunks, fn(chunk, at) {
        case at == position {
          True -> changed
          False -> chunk
        }
      }),
    )
  let offset = server_bytes_before(session.sts, position) + index

  let replayed = start(database, session.sts.header.seed)
  assert replay.run(
      recording: edited,
      target: Target("127.0.0.1", replayed.sts_port),
      deadline_ms: wait_ms,
    )
    == Error(Differs(
      chunk: position,
      offset:,
      expected: altered,
      received: recorded,
    ))
    as "the replay matched every byte before the changed one and stopped at it"
}

/// The position in the recording of its last server chunk, and the chunk.
fn last_server_chunk(recording: Recording) -> Result(#(Int, Chunk), Nil) {
  list.index_map(recording.chunks, fn(chunk, position) { #(position, chunk) })
  |> list.filter(fn(entry) { { entry.1 }.direction == ServerToClient })
  |> list.last
}

/// How many bytes the server sent in the chunks before the one at `position`.
fn server_bytes_before(recording: Recording, position: Int) -> Int {
  list.take(recording.chunks, position)
  |> list.filter(fn(chunk) { chunk.direction == ServerToClient })
  |> list.fold(0, fn(total, chunk) { total + bit_array.byte_size(chunk.bytes) })
}

pub fn the_unseeded_live_recording_replays_up_to_the_servers_first_random_value_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  // The live account is `jimtest`; no password was recorded, so the new
  // server's account has another, and the salt and verifier are its own.
  let assert Ok(_) =
    account_store.create(database.connection, "jimtest", "not the live one")
    as "the account is created"
  let assert Ok(live) = recording.read(from: live_folder <> "sts-001.recording")
    as "the live STS recording reads"
  assert live.header.seed == None
    as "the live recording was made unseeded, so no seed can start its server"
  let assert Ok(#(position, reply)) = first_server_chunk(live)
    as "the live recording holds the server's reply"

  // The first server chunk is the reply to LoginStart:
  // `<Reply><KeyData>` and then the base64 of the salt and B.
  let assert Ok(text) = bit_array.to_string(reply.bytes) as "the reply is text"
  let assert Ok(#(head, rest)) = string.split_once(text, "<KeyData>")
    as "the reply carries KeyData"
  let assert Ok(#(value, _)) = string.split_once(rest, "</KeyData>")
    as "the KeyData element closes"
  let value_start = bit_array.byte_size(<<head:utf8, "<KeyData>":utf8>>)
  let value_end = value_start + bit_array.byte_size(<<value:utf8>>)

  let running = start(database, None)
  let outcome =
    replay.run(
      recording: live,
      target: Target("127.0.0.1", running.sts_port),
      deadline_ms: wait_ms,
    )
  let assert Error(Differs(chunk:, offset:, expected:, received:)) = outcome
    as "the replay of an unseeded recording stops at a difference"
  assert chunk == position
    as "it stops in the reply that carries the SRP value B, the first server chunk"
  assert offset >= value_start
    as "every byte of the reply before the KeyData value matched: the status line, the sequence, the length and the elements"
  assert offset < value_end
    as "the first byte that differs is in the KeyData value, the salt or B"
  assert expected != received as "the two bytes differ"
}

/// The position in the recording of its first server chunk, and the chunk.
fn first_server_chunk(recording: Recording) -> Result(#(Int, Chunk), Nil) {
  list.index_map(recording.chunks, fn(chunk, position) { #(position, chunk) })
  |> list.find(fn(entry) { { entry.1 }.direction == ServerToClient })
}
