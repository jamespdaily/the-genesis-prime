//// The recording server's draws. The expected values are the issue's test 1:
//// a recording server writes every draw of each connection in order, keyed so
//// that a replay can find a connection's own draws, and two logins that draw at
//// the same time keep their draws apart. A connection is named by the peer
//// address of its socket (`socket.peer`), and a draw is as long as the login
//// takes: the SRP secret of the STS login is 32 bytes
//// (`sts_connection.services`), and a game token or a session key is 16
//// (`handoff.issue`).
////
//// The draws go through the services the connections use and the hand-offs
//// they share, started as the login's tree starts them, with the log process
//// as their random source.

import genesis_prime/login/account.{Identity}
import genesis_prime/login/guid
import genesis_prime/login/handoff
import genesis_prime/login/random_source.{type RandomSource}
import genesis_prime/login/sts_connection
import genesis_prime/recording/draw_log
import genesis_prime/recording/session
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor
import owned_test
import pog
import recording_support
import simplifile

/// How many logins' draws each connection makes.
const logins = 4

/// How long a test waits for a connection to finish its draws, in
/// milliseconds.
const wait_ms = 10_000

/// The services a login's connections draw through, and the hand-off that
/// holds the session keys, over a log process that writes into `folder`.
type Server {
  Server(
    services: sts_connection.Services,
    session_keys: process.Name(handoff.Message(account.Identity)),
  )
}

fn start(folder: String) -> Server {
  let log_name = process.new_name("draw_log")
  let game_tokens = process.new_name("draw_log_game_tokens")
  let session_keys = process.new_name("draw_log_session_keys")
  let random = draw_log.source(log_name)
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(draw_log.supervised(name: log_name, folder:))
    |> static_supervisor.add(handoff.supervised(hand_off(game_tokens, random)))
    |> static_supervisor.add(handoff.supervised(hand_off(session_keys, random)))
    |> static_supervisor.start
    as "the recording server's processes did not start"
  Server(
    services: sts_connection.services(
      // The services hold a connection to the database for the lookups of
      // accounts; no draw uses it.
      connection: pog.named_connection(process.new_name("draw_log_unused_pool")),
      game_tokens:,
      random:,
    ),
    session_keys:,
  )
}

fn hand_off(
  name: process.Name(handoff.Message(account.Identity)),
  random: RandomSource,
) -> handoff.Settings(account.Identity) {
  handoff.Settings(
    name:,
    expiry_milliseconds: 60_000,
    clock: fn() { 0 },
    random:,
  )
}

/// What one connection drew, in the order it drew it: the secret, the game
/// token and the session key of each login.
fn connection_draws(server: Server, peer: String) -> List(BitArray) {
  let assert Ok(user_id) = guid.from_wire(<<0:size(128)>>) as "16 bytes"
  let identity = Identity(id: 7, name: "jim", user_id:)
  list.flat_map(list.repeat(Nil, logins), fn(_login) {
    let secret = server.services.draw_secret(Some(peer), None)
    let token = server.services.issue_game_token(identity, Some(peer))
    let key = handoff.issue(server.session_keys, identity, Some(peer))
    [secret, token, key]
  })
}

/// Starts a process that makes a connection's draws and reports them.
fn start_connection(server: Server, peer: String) -> Subject(List(BitArray)) {
  let reported = process.new_subject()
  process.spawn(fn() { process.send(reported, connection_draws(server, peer)) })
  reported
}

pub fn the_draws_of_two_concurrent_connections_are_recorded_apart_and_in_order_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  let server = start(folder)
  let first_peer = "127.0.0.1:40001"
  let second_peer = "127.0.0.1:40002"

  // Both connections draw at once, so their writes interleave in the log.
  let first = start_connection(server, first_peer)
  let second = start_connection(server, second_peer)
  let assert Ok(first_drew) = process.receive(first, wait_ms)
    as "the first connection finished its draws"
  let assert Ok(second_drew) = process.receive(second, wait_ms)
    as "the second connection finished its draws"

  assert list.map(first_drew, bit_array.byte_size)
    == list.flatten(list.repeat([32, 16, 16], logins))
    as "a secret is 32 bytes and a game token or a session key is 16, a login's draws in the order it makes them"
  let assert Ok(saved) = session.read(folder) as "the session folder reads back"
  assert session.draws_of(saved, first_peer) == first_drew
    as "a replay finds the first connection's own draws, as it drew them and in its order"
  assert session.draws_of(saved, second_peer) == second_drew
    as "a replay finds the second connection's own draws, as it drew them and in its order"
  assert list.length(saved.draws) == 2 * logins * 3
    as "every draw of both connections was written, and none twice"
  assert list.unique(list.append(first_drew, second_drew))
    == list.append(first_drew, second_drew)
    as "the strong source gives no draw that another repeats"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}

pub fn a_draw_with_no_peer_is_written_without_a_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  let server = start(folder)
  let secret = server.services.draw_secret(None, None)
  let assert Ok(saved) = session.read(folder) as "the session folder reads back"
  assert saved.draws == [session.Draw(connection: None, bytes: secret)]
    as "a draw of a socket with no peer is kept as drawn, under no connection, so no replay takes it for another connection's"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}
