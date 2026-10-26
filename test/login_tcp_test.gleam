//// The login served end to end over TCP, against the real listeners the
//// server's tree starts: a scripted client (`scripted_client`, written from the
//// fact file's records) connects to the STS listener, logs in, connects to the
//// auth listener, sends 0x592, and receives 0x591 and a 0x3DB naming the game
//// listener's address and a fresh session key. The accounts are in a database
//// of the test's own. The expected values are the login issue's test 3 and
//// the records it rests on: the STS requests and replies
//// (`StsConnLib64.MT.dll!0x180006fb0`, `0x18000a350`, `0x1800043d0`,
//// `0x180004950`, `0x180004ac0`), RC4 under the session key after the exchange
//// (`0x18003a7d0`), the hello, 0x592, 0x591 and 0x3DB (opcode.0x3,
//// opcode.0x592, opcode.0x591, opcode.0x3db) with the wrappers 0x244 and 0x76
//// under the base key.
////
//// Every wait is for bytes the server writes or for the socket to close; the
//// deadlines are for a server that does not answer, never a pause.

import genesis_prime/login/account
import genesis_prime/login/account_store
import genesis_prime/login/auth_session
import genesis_prime/login/guid
import genesis_prime/login/handoff
import genesis_prime/login/service
import genesis_prime/login/sts_xml
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted
import genesis_prime/server
import genesis_prime/shutdown.{Stopped}
import gleam/bit_array
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/option.{None}
import gleam/string
import login_client.{type Ports, Ports}
import owned_test
import tcp_client
import template_database

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// The game listener the hand-off names: the loopback address and a port. No
/// game listener runs on it, as the hand-off only names it.
const game_address = 0x7F000001

const game_port = 24_000

/// The running server: the ports its two listeners opened and the name of the
/// hand-off that holds the session keys for the game server's check.
type Running {
  Running(
    ports: Ports,
    session_keys: Name(handoff.Message(account.Identity)),
    shutdown: shutdown.Settings,
  )
}

fn start(database: template_database.Database) -> Running {
  let pool_settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("login_tcp_pool"),
      pool_size: 2,
    )
  let defaults = template_database.tree_settings(pool_settings)
  let ports = process.new_subject()
  let login =
    service.Settings(
      ..defaults.login,
      sts: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("sts", port))
      }),
      auth: service.Port(number: 0, opened: fn(port) {
        process.send(ports, #("auth", port))
      }),
      auth_login: auth_session.Settings(
        game_server: Endpoint(address: game_address, port: game_port),
        realm_name: "Nexus",
        expected_files_digest: None,
      ),
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
  Running(
    ports: Ports(sts_port:, auth_port:),
    session_keys: login.session_keys.name,
    shutdown: defaults.shutdown,
  )
}

pub fn a_player_logs_in_over_tcp_and_is_handed_to_the_game_listener_with_a_fresh_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(account) =
    account_store.create(database.connection, "Jim", "secret")
    as "the account is created"
  let login =
    login_client.sts_login(
      ports: running.ports,
      name: "Jim",
      password: "secret",
      seed: 0x39,
    )
  assert login.user_id == guid.to_text(account.user_id)
    as "the STS login's UserId is the account's GUID"
  let socket =
    login_client.auth_login(ports: running.ports, login:, build: 16_042)
  let frames =
    login_client.read_frames(client: socket, have: <<>>, count: 2)
    |> list.map(login_client.as_the_client_reads)
  assert list.map(frames, fn(sent) { sent.message_id }) == [0x0591, 0x03DB]
    as "opcode.0x591 then opcode.0x3db"
  let assert [accepted, handed] = frames as "two frames"
  assert login_accepted.decode(accepted.body)
    == Ok(login_accepted.LoginAccepted(0))
    as "opcode.0x591: login accepted"
  let assert Ok(handoff_message) = game_server_handoff.decode(handed.body)
    as "the hand-off decodes"
  assert handoff_message.game_server
    == Endpoint(address: game_address, port: game_port)
    as "opcode.0x3db: the address of the game listener as a number (127.0.0.1 is 0x7F000001) and its port"
  assert bit_array.byte_size(handoff_message.session_key) == 16
    as "opcode.0x3db: the session key is 16 bytes"
  assert handoff.redeem(running.session_keys, handoff_message.session_key)
    == Ok(account.identity(account))
    as "the key is held for the game server's 0x58F check, for the account that logged in"
}

pub fn two_players_are_handed_different_session_keys_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the first account is created"
  let assert Ok(_) = account_store.create(database.connection, "sam", "hunter2")
    as "the second account is created"
  let keys =
    list.map([#("jim", "secret", 1), #("sam", "hunter2", 2)], fn(player) {
      let login =
        login_client.sts_login(
          ports: running.ports,
          name: player.0,
          password: player.1,
          seed: player.2,
        )
      let socket =
        login_client.auth_login(ports: running.ports, login:, build: 16_042)
      let assert [_, handed] =
        login_client.read_frames(client: socket, have: <<>>, count: 2)
        |> list.map(login_client.as_the_client_reads)
        as "0x591 and 0x3DB"
      let assert Ok(message) = game_server_handoff.decode(handed.body)
        as "the hand-off decodes"
      message.session_key
    })
  let assert [first, second] = keys as "two keys"
  assert first != second as "each hand-off carries a fresh session key"
}

pub fn a_wrong_password_is_refused_over_tcp_and_the_connection_closes_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let #(answered, _) =
    login_client.srp_exchange(
      client: login_client.sts_connect(running.ports),
      name: "jim",
      password: "not it",
      seed: 7,
    )
  assert answered.reply.status == 400
    as "StsConnLib64.MT.dll!0x18002de60: a refusal is an error reply, status 400"
  assert answered.reply.root.name == "Error"
    as "StsConnLib64.MT.dll!0x18002de60: its root is an Error element"
  assert tcp_client.await_close(answered.client.socket, wait_ms)
    as "the login ends: the server closes the connection after the refusal"
}

pub fn an_unknown_account_is_refused_over_tcp_and_the_connection_closes_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let started =
    login_client.ask(
      client: login_client.sts_connect(running.ports),
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", "nobody"),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  assert started.reply.status == 400 as "an unknown account is refused"
  assert tcp_client.await_close(started.client.socket, wait_ms)
    as "the server closes the connection after the refusal"
}

pub fn a_game_token_works_once_over_tcp_and_the_second_use_gets_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let login =
    login_client.sts_login(
      ports: running.ports,
      name: "jim",
      password: "secret",
      seed: 3,
    )
  let first =
    login_client.auth_login(ports: running.ports, login:, build: 16_042)
  assert list.length(login_client.read_frames(
      client: first,
      have: <<>>,
      count: 2,
    ))
    == 2
    as "the first use is handed on"
  let second =
    login_client.auth_login(ports: running.ports, login:, build: 16_042)
  assert tcp_client.await_close(second, wait_ms)
    as "the login issue: the game token is used once, so the second use gets no 0x591 and the connection closes"
}

pub fn a_build_other_than_16042_is_closed_without_an_answer_over_tcp_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let login =
    login_client.sts_login(
      ports: running.ports,
      name: "jim",
      password: "secret",
      seed: 4,
    )
  let wrong =
    login_client.auth_login(ports: running.ports, login:, build: 16_043)
  assert tcp_client.await_close(wrong, wait_ms)
    as "CheckAuthServerVersion 0x140037b70: the client's build is 16042, and another ends the connection with no answer"
  let right =
    login_client.auth_login(ports: running.ports, login:, build: 16_042)
  assert list.length(login_client.read_frames(
      client: right,
      have: <<>>,
      count: 2,
    ))
    == 2
    as "the token the wrong build did not spend is still good for the right one"
}

pub fn the_ordered_stop_closes_both_login_listeners_and_their_connections_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  // An STS connection exists once its owner has answered, and an auth
  // connection once the hello has arrived; each owner registers as it starts.
  let started =
    login_client.ask(
      client: login_client.sts_connect(running.ports),
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", "jim"),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  assert started.reply.status == 200 as "the STS connection was served"
  let auth = login_client.connect(running.ports.auth_port)
  let assert [_hello] =
    login_client.read_frames(client: auth, have: <<>>, count: 1)
    as "the auth connection was greeted"
  shutdown.stop(running.shutdown)
  assert process.receive(running.shutdown.finished, wait_ms)
    == Ok(Stopped(failures: []))
    as "the order ran with the login's listeners and connections registered, and must not fail"
  assert tcp_client.await_close(auth, wait_ms)
    as "the shutdown closes an open auth connection"
  assert tcp_client.await_close(started.client.socket, wait_ms)
    as "the shutdown closes an open STS connection"
  assert tcp_client.connect(running.ports.sts_port) == Error(Nil)
    as "the STS listener refuses new connections once the order has run"
  assert tcp_client.connect(running.ports.auth_port) == Error(Nil)
    as "the auth listener refuses new connections once the order has run"
}
