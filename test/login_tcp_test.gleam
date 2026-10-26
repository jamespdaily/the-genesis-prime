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

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/account
import genesis_prime/login/account_store
import genesis_prime/login/auth_session
import genesis_prime/login/guid
import genesis_prime/login/handoff
import genesis_prime/login/rc4
import genesis_prime/login/service
import genesis_prime/login/sts_xml
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted
import genesis_prime/message/server_hello
import genesis_prime/server
import genesis_prime/shutdown.{Stopped}
import gleam/bit_array
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import scripted_client.{type Reply}
import seeded
import tcp_client.{type Client}
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
    sts_port: Int,
    auth_port: Int,
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
    sts_port:,
    auth_port:,
    session_keys: login.session_keys.name,
    shutdown: defaults.shutdown,
  )
}

fn connect(port: Int) -> Client {
  let assert Ok(client) = tcp_client.connect(port)
    as "the client could not connect to the listener"
  client
}

fn send(client: Client, bytes: BitArray) -> Nil {
  let assert Ok(Nil) = tcp_client.send(client, bytes)
    as "the server closed the connection before the client finished sending"
  Nil
}

/// The client's side of an STS connection: its socket, its RC4 streams once
/// the exchange is done, and the next sequence number.
type StsClient {
  StsClient(
    socket: Client,
    sending: Option(rc4.Stream),
    receiving: Option(rc4.Stream),
    next_sequence: Int,
  )
}

/// What the server answered, or that it closed the connection first.
type Heard {
  Heard(client: StsClient, reply: Reply)
}

/// Writes a request the way the library does, through RC4 once it is on, and
/// reads the reply: bytes are deciphered as they arrive, in order, until they
/// make one whole reply.
fn ask(
  client client: StsClient,
  protocol protocol: String,
  command command: String,
  body body: sts_xml.Node,
) -> Heard {
  let plain =
    scripted_client.request(
      sequence: Some(client.next_sequence),
      protocol:,
      command:,
      body: sts_xml.render(body),
    )
  send(client.socket, case client.sending {
    Some(stream) -> rc4.crypt(stream, plain)
    None -> plain
  })
  let reply = read_reply(client, <<>>)
  Heard(
    client: StsClient(..client, next_sequence: client.next_sequence + 1),
    reply:,
  )
}

fn read_reply(client: StsClient, have: BitArray) -> Reply {
  let assert Ok(bytes) = tcp_client.receive_some(client.socket, wait_ms)
    as "the server did not answer the request"
  let plain = case client.receiving {
    Some(stream) -> rc4.crypt(stream, bytes)
    None -> bytes
  }
  let all = <<have:bits, plain:bits>>
  case scripted_client.read_reply(all) {
    Ok(reply) -> reply
    Error(Nil) -> read_reply(client, all)
  }
}

fn child(reply: Reply, name: String) -> String {
  let assert Ok(text) = scripted_client.child_text(reply, name)
    as { "the reply has no " <> name }
  text
}

/// Starts an STS connection with the one-way Connect the library sends first.
fn sts_connect(running: Running) -> StsClient {
  let socket = connect(running.sts_port)
  send(
    socket,
    scripted_client.request(
      sequence: None,
      protocol: "Sts",
      command: "Connect",
      body: sts_xml.render(
        sts_xml.Parent("Connect", [sts_xml.Text("ConnType", "1281")]),
      ),
    ),
  )
  StsClient(socket:, sending: None, receiving: None, next_sequence: 1)
}

/// LoginStart and the SRP answer: the reply to the answer, and what the client
/// computed, for a password the client chooses.
fn srp_exchange(
  client client: StsClient,
  name name: String,
  password password: String,
  seed seed: Int,
) -> #(Heard, scripted_client.Exchange) {
  let started =
    ask(
      client: client,
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", name),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  let assert Ok(server_key_data) =
    bit_array.base64_decode(child(started.reply, "KeyData"))
    as "KeyData is base64"
  let #(secret, _) = seeded.bytes(state: seed, count: 32)
  let assert Ok(exchange) =
    scripted_client.exchange(name:, password:, secret:, server_key_data:)
    as "the server's key data is the salt and B"
  let answered =
    ask(
      client: started.client,
      protocol: "Auth",
      command: "KeyData",
      body: sts_xml.Parent("Request", [
        sts_xml.Text(
          "KeyData",
          bit_array.base64_encode(exchange.key_data, True),
        ),
      ]),
    )
  #(answered, exchange)
}

/// The client's whole STS login to the game token, as the library goes.
fn sts_login(
  running running: Running,
  name name: String,
  password password: String,
  seed seed: Int,
) -> scripted_client.StsLogin {
  let #(answered, exchange) =
    srp_exchange(
      client: sts_connect(running),
      name: string.lowercase(name),
      password:,
      seed:,
    )
  assert answered.reply.status == 200
    as "StsConnLib64.MT.dll!0x18002d3b0: the client accepts the server's M2"
  assert child(answered.reply, "KeyData")
    == bit_array.base64_encode(
      <<32:size(32)-little, exchange.expected_m2:bits>>,
      True,
    )
    as "StsConnLib64.MT.dll!0x18002d3b0: M2 = SHA-256(A | M1 | K)"
  let assert Ok(receiving) = rc4.start(exchange.session_key)
    as "this OTP has RC4"
  let assert Ok(sending) = rc4.start(exchange.session_key) as "this OTP has RC4"
  let client =
    StsClient(
      ..answered.client,
      sending: Some(sending),
      receiving: Some(receiving),
    )
  let finished =
    ask(
      client: client,
      protocol: "Auth",
      command: "LoginFinish",
      body: sts_xml.Empty("Request"),
    )
  let user_id = child(finished.reply, "UserId")
  assert child(finished.reply, "AuthType") == "0"
    as "StsConnLib64.MT.dll!0x1800043d0: AuthType 0 is a finished login"
  let listed =
    ask(
      client: finished.client,
      protocol: "GameAccount",
      command: "ListMyAccounts",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
      ]),
    )
  let assert Ok(game_account) = sts_xml.child(listed.reply.root, "GameAccount")
    as "exactly one GameAccount (HandleListMyAccountsResult 0x1400b36c0)"
  let assert Ok(alias) = sts_xml.child(game_account, "Alias")
    as "GameAccount has an Alias"
  let token =
    ask(
      client: listed.client,
      protocol: "Auth",
      command: "RequestGameToken",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
        sts_xml.Text("AccountAlias", alias.text),
      ]),
    )
  scripted_client.StsLogin(user_id:, token: child(token.reply, "Token"), name:)
}

/// Reads frames from the auth connection until there are `count` of them.
fn read_frames(
  client client: Client,
  have have: BitArray,
  count count: Int,
) -> List(Frame) {
  let assert Ok(#(frames, leftover)) = frame.decode(have)
    as "the server wrote bytes that are frames"
  case list.length(frames) >= count {
    True -> frames
    False -> {
      let assert Ok(bytes) = tcp_client.receive_some(client, wait_ms)
        as "the auth server did not write the frames"
      read_frames(client:, have: <<leftover:bits, bytes:bits>>, count:)
    }
  }
}

/// A frame from the auth server as the client reads it: a 0x76 wrapper is
/// opened under the base key.
fn as_the_client_reads(sent: Frame) -> Frame {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  case sent.message_id == encrypted_frame.message_id(AuthWrapper) {
    True -> {
      let assert Ok(inner) = encrypted_frame.unwrap(sent, base)
        as "the client reads 0x76 under the base key"
      inner
    }
    False -> sent
  }
}

/// Connects to the auth listener, reads the hello and sends the login request
/// of an STS login with the given build.
fn auth_login(
  running running: Running,
  login login: scripted_client.StsLogin,
  build build: Int,
) -> Client {
  let socket = connect(running.auth_port)
  let assert [hello] = read_frames(client: socket, have: <<>>, count: 1)
    as "the auth server did not greet the client"
  assert hello.message_id == 0x0003
    as "opcode.0x3: the server's hello is message 3"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the hello decodes"
  assert decoded.build == 16_042 && decoded.message_table_checksum == 0x097998A0
    as "CheckAuthServerVersion 0x140037b70: the client checks build 16042 and checksum 0x097998A0"
  let assert Ok(request_bytes) =
    frame.encode(
      scripted_client.login_request_frame(login:, build:).message_id,
      scripted_client.login_request_frame(login:, build:).body,
    )
    as "the request frame encodes"
  send(socket, request_bytes)
  socket
}

pub fn a_player_logs_in_over_tcp_and_is_handed_to_the_game_listener_with_a_fresh_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(account) =
    account_store.create(database.connection, "Jim", "secret")
    as "the account is created"
  let login = sts_login(running:, name: "Jim", password: "secret", seed: 0x39)
  assert login.user_id == guid.to_text(account.user_id)
    as "the STS login's UserId is the account's GUID"
  let socket = auth_login(running:, login:, build: 16_042)
  let frames =
    read_frames(client: socket, have: <<>>, count: 2)
    |> list.map(as_the_client_reads)
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
        sts_login(running:, name: player.0, password: player.1, seed: player.2)
      let socket = auth_login(running:, login:, build: 16_042)
      let assert [_, handed] =
        read_frames(client: socket, have: <<>>, count: 2)
        |> list.map(as_the_client_reads)
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
    srp_exchange(
      client: sts_connect(running),
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
    ask(
      client: sts_connect(running),
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
  let login = sts_login(running:, name: "jim", password: "secret", seed: 3)
  let first = auth_login(running:, login:, build: 16_042)
  assert list.length(read_frames(client: first, have: <<>>, count: 2)) == 2
    as "the first use is handed on"
  let second = auth_login(running:, login:, build: 16_042)
  assert tcp_client.await_close(second, wait_ms)
    as "the login issue: the game token is used once, so the second use gets no 0x591 and the connection closes"
}

pub fn a_build_other_than_16042_is_closed_without_an_answer_over_tcp_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let running = start(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let login = sts_login(running:, name: "jim", password: "secret", seed: 4)
  let wrong = auth_login(running:, login:, build: 16_043)
  assert tcp_client.await_close(wrong, wait_ms)
    as "CheckAuthServerVersion 0x140037b70: the client's build is 16042, and another ends the connection with no answer"
  let right = auth_login(running:, login:, build: 16_042)
  assert list.length(read_frames(client: right, have: <<>>, count: 2)) == 2
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
    ask(
      client: sts_connect(running),
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", "jim"),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  assert started.reply.status == 200 as "the STS connection was served"
  let auth = connect(running.auth_port)
  let assert [_hello] = read_frames(client: auth, have: <<>>, count: 1)
    as "the auth connection was greeted"
  shutdown.stop(running.shutdown)
  assert process.receive(running.shutdown.finished, wait_ms)
    == Ok(Stopped(failures: []))
    as "the order ran with the login's listeners and connections registered, and must not fail"
  assert tcp_client.await_close(auth, wait_ms)
    as "the shutdown closes an open auth connection"
  assert tcp_client.await_close(started.client.socket, wait_ms)
    as "the shutdown closes an open STS connection"
  assert tcp_client.connect(running.sts_port) == Error(Nil)
    as "the STS listener refuses new connections once the order has run"
  assert tcp_client.connect(running.auth_port) == Error(Nil)
    as "the auth listener refuses new connections once the order has run"
}
