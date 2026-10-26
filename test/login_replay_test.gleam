//// A recorded login session replayed over TCP, against the real listeners the
//// server's tree starts, on a database made from nothing. The expected values
//// are the issue's tests 4 and 5.
//// - A session recorded against a recording server can be played again: the
////   scripted client logs in through the recording relays with a wrong password
////   first and then the right one, and goes on to the auth server; the three
////   recordings (the two STS connections and the auth connection, `sts-001`,
////   `sts-002` and `auth-001`) replay against a new server on a fresh database
////   that holds the accounts the session folder names and is given each
////   replayed connection's own recorded draws. Every server chunk matches, the
////   SRP value B, the game token and the session key among them, and after the
////   recording's last chunk the server sends nothing more before it closes the
////   connection. A server answer that differs by one byte fails the replay at
////   that byte, named by its offset in the stream of what the server sent.
//// - A recording whose draws were not recorded cannot: the live recording of
////   the first session with the real client (`live_folder`) replays up to the
////   reply that carries B, which depends on the server's secret b. The account
////   is inserted with the salt the recording's reply carries, so the salt
////   matches and the first byte that differs is inside B.
////
//// Every wait is for bytes the server writes or for the socket to close; the
//// deadlines are for a server that does not answer, never a pause.

import genesis_prime/login/account_store
import genesis_prime/login/random_source.{type RandomSource, Strong}
import genesis_prime/login/service
import genesis_prime/login/srp
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/recording.{
  type Chunk, type Recording, Auth, Chunk, Header, Recording, ServerToClient,
  Sts,
}
import genesis_prime/recording/draw_log
import genesis_prime/recording/listener
import genesis_prime/recording/pipe.{Server}
import genesis_prime/recording/relay
import genesis_prime/recording/session.{type Session, UsedAccount}
import genesis_prime/server
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor
import gleam/string
import login_client.{type Ports, Ports}
import owned_test
import recorded_draws
import recording_support
import replay.{Differs, Target}
import session_accounts
import simplifile
import tcp_client
import template_database

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// The game listener the hand-off names: the loopback address and a port. No
/// game listener runs on it, as the hand-off only names it.
const game_address = 0x7F000001

const game_port = 24_000

/// The live recording of the first session with the real client.
const live_folder = "test/recording/2026-10-26-login/"

/// Starts a server's tree on the test's database, its login drawing from
/// `random`, and returns the ports of its two login listeners.
fn start(database: template_database.Database, random: RandomSource) -> Ports {
  let pool_settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("login_replay_pool"),
      pool_size: 2,
    )
  let defaults = template_database.tree_settings(pool_settings)
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
/// `folder`, its header naming `role`.
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
      header: Header(..recording_support.header(), role:),
      connections: process.new_name("login_replay_relay"),
    ))
    as "the relay did not start"
  started
}

/// A recording server on `database`: the draw log writing into `folder` is its
/// random source.
fn recording_server(
  database: template_database.Database,
  folder: String,
) -> Ports {
  let log_name = process.new_name("login_replay_draw_log")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(draw_log.supervised(name: log_name, folder:))
    |> static_supervisor.start
    as "the draw log did not start"
  start(database, draw_log.source(log_name))
}

/// The scripted client logs in as `jim` through two relays, one for each
/// listener of a recording server: a wrong password first, which the server
/// refuses, then the right one, and on to the hand-off of the auth server. The
/// account `jim` exists on `database`. Returns the session folder.
fn record_session(database: template_database.Database) -> String {
  let folder = recording_support.new_folder()
  let recorded = recording_server(database, folder)
  let sts_relay = relay_to(port: recorded.sts_port, role: Sts, folder:)
  let auth_relay = relay_to(port: recorded.auth_port, role: Auth, folder:)
  let ports = Ports(sts_port: sts_relay.port, auth_port: auth_relay.port)

  let #(refused, _) =
    login_client.srp_exchange(
      client: login_client.sts_connect(ports),
      name: "jim",
      password: "not it",
      seed: 1,
    )
  assert refused.reply.status == 400
    as "StsConnLib64.MT.dll!0x18002de60: a wrong password is refused with status 400"
  assert tcp_client.await_close(refused.client.socket, wait_ms)
    as "the server closes the refused connection"

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
  folder
}

fn read_recording(folder: String, name: String) -> Recording {
  let assert Ok(recording) =
    recording.read(from: folder <> "/" <> name <> ".recording")
    as { name <> " was recorded" }
  recording
}

/// What a replayed server is made of: a fresh database that holds the
/// session's accounts, the process that gives each replayed connection its
/// recorded draws, and the server's ports.
type Replayed {
  Replayed(ports: Ports, draws: recorded_draws.Draws, saved: Session)
}

fn replayed_server(
  database: template_database.Database,
  folder: String,
) -> Replayed {
  let assert Ok(saved) = session.read(folder) as "the session folder reads back"
  list.each(saved.accounts, fn(account) {
    session_accounts.insert(connection: database.connection, account:)
  })
  let draws = recorded_draws.start()
  Replayed(ports: start(database, recorded_draws.source(draws)), draws:, saved:)
}

/// Replays the recording called `name` of the session folder against the
/// replayed server, giving the connection the draws recorded for the one the
/// recording was made by.
fn replay_recording(
  replayed replayed: Replayed,
  folder folder: String,
  name name: String,
  recording recording: Recording,
) -> Result(Nil, replay.Failure) {
  let assert Ok(recorded_as) =
    session.read_connection(
      recording_path: folder <> "/" <> name <> ".recording",
    )
    as { name <> " has the address its connection was recorded from" }
  let port = case recording.header.role {
    Sts -> replayed.ports.sts_port
    Auth -> replayed.ports.auth_port
    recording.Game -> panic as "the session has no game connection"
  }
  replay.run_connected(
    recording:,
    target: Target("127.0.0.1", port),
    deadline_ms: wait_ms,
    connected: fn(address) {
      recorded_draws.register(
        replayed.draws,
        address,
        session.draws_of(replayed.saved, recorded_as),
      )
    },
  )
}

pub fn a_recorded_session_replays_over_tcp_on_a_fresh_database_to_its_end_test() -> Nil {
  use <- owned_test.run(120_000)
  use recorded_database <- template_database.run
  use fresh_database <- template_database.run
  let assert Ok(_) =
    account_store.create(recorded_database.connection, "jim", "secret")
    as "the account is created"
  let folder = record_session(recorded_database)
  let replayed = replayed_server(fresh_database, folder)

  // The connections replay in the order the client opened them; the auth
  // connection redeems the game token the second STS connection issued.
  list.each(["sts-001", "sts-002", "auth-001"], fn(name) {
    assert replay_recording(
        replayed:,
        folder:,
        name:,
        recording: read_recording(folder, name),
      )
      == Ok(Nil)
      as {
        name
        <> ": every server chunk matches, and the server sends nothing past the end before the connection closes"
      }
  })
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}

pub fn a_server_answer_that_differs_by_one_byte_fails_the_replay_at_that_byte_test() -> Nil {
  use <- owned_test.run(120_000)
  use recorded_database <- template_database.run
  use fresh_database <- template_database.run
  let assert Ok(_) =
    account_store.create(recorded_database.connection, "jim", "secret")
    as "the account is created"
  let folder = record_session(recorded_database)
  let sts = read_recording(folder, "sts-002")

  // The last server chunk of the STS connection, which is under the session
  // cipher, has one byte in its middle changed: the server's answer then
  // differs from the recording's at the byte's offset in the stream of
  // everything the server sent.
  let assert Ok(#(position, Chunk(direction, time, original))) =
    last_server_chunk(sts)
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
      ..sts,
      chunks: list.index_map(sts.chunks, fn(chunk, at) {
        case at == position {
          True -> changed
          False -> chunk
        }
      }),
    )
  let offset = server_bytes_before(sts, position) + index

  let replayed = replayed_server(fresh_database, folder)
  assert replay_recording(
      replayed:,
      folder:,
      name: "sts-002",
      recording: edited,
    )
    == Error(Differs(
      chunk: position,
      offset:,
      expected: altered,
      received: recorded,
    ))
    as "the replay matched every byte before the changed one and stopped at it"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
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

pub fn the_live_recording_replays_up_to_the_servers_first_random_value_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let assert Ok(live) = recording.read(from: live_folder <> "sts-001.recording")
    as "the live STS recording reads"
  let assert Ok(#(position, reply)) = first_server_chunk(live)
    as "the live recording holds the server's reply"

  // The first server chunk is the reply to LoginStart: the XML
  // `<Reply>...<KeyData>` and then the base64 of the key data, which is the
  // salt and B, each as its length (32 bits, little-endian) and its bytes
  // (StsConnLib64.MT.dll!0x18002d4e0, as `scripted_client.exchange` reads it).
  let assert Ok(text) = bit_array.to_string(reply.bytes) as "the reply is text"
  let assert Ok(#(head, rest)) = string.split_once(text, "<KeyData>")
    as "the reply carries KeyData"
  let assert Ok(#(value, _)) = string.split_once(rest, "</KeyData>")
    as "the KeyData element closes"
  let assert Ok(<<
    salt_length:size(32)-little,
    salt:bytes-size(salt_length),
    _:bits,
  >>) = bit_array.base64_decode(value)
    as "the key data starts with the salt"
  let value_start = bit_array.byte_size(<<head:utf8, "<KeyData>":utf8>>)
  let value_end = value_start + bit_array.byte_size(<<value:utf8>>)
  // B starts after the salt and the two 32-bit lengths, 8 + salt_length bytes
  // in; base64 writes 6 bits a character, so the first character with a bit
  // of B in it is the one that holds that bit.
  let first_b_character = value_start + { 8 * { 8 + salt_length } } / 6

  // The live account is `jimtest`; no password was recorded, so the account
  // has the recorded salt and a verifier of a password of the test's own, and
  // the new server finds the salt the recording holds.
  session_accounts.insert(
    connection: database.connection,
    account: UsedAccount(
      name: "jimtest",
      user_id: "00000000-0000-4000-8000-000000000072",
      salt:,
      verifier: srp.verifier(
        name: "jimtest",
        password: "not the live one",
        salt:,
      ),
    ),
  )
  let running = start(database, Strong)
  let outcome =
    replay.run(
      recording: live,
      target: Target("127.0.0.1", running.sts_port),
      deadline_ms: wait_ms,
    )
  let assert Error(Differs(chunk:, offset:, expected:, received:)) = outcome
    as "the replay of a recording with no draws stops at a difference"
  assert chunk == position
    as "it stops in the reply that carries the SRP value B, the first server chunk"
  assert offset >= first_b_character
    as "every byte before B matched, the salt among them"
  assert offset < value_end
    as "the first byte that differs is in B's characters"
  assert expected != received as "the two bytes differ"
}

/// The position in the recording of its first server chunk, and the chunk.
fn first_server_chunk(recording: Recording) -> Result(#(Int, Chunk), Nil) {
  list.index_map(recording.chunks, fn(chunk, position) { #(position, chunk) })
  |> list.find(fn(entry) { { entry.1 }.direction == ServerToClient })
}
