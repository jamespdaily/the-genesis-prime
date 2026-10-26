//// The whole login served end to end, in one process and without a socket: a
//// scripted client (`scripted_client`, written from the fact file's records)
//// talks to an STS connection and then an auth connection, each carried out as
//// a server's process carries them out (`sts_connection`, `auth_connection`),
//// over real accounts in Postgres and the real hand-offs. The expected values
//// are the login issue's: the STS login reaches a game token, the auth login
//// with that token and the STS login's UserId gets 0x591 and a hand-off with a
//// fresh session key, and a wrong secret, an unknown account, a token used
//// twice or a build other than 16042 never gets a session key.

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper, ClientWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/account_store
import genesis_prime/login/auth_connection
import genesis_prime/login/auth_session
import genesis_prime/login/guid
import genesis_prime/login/handoff
import genesis_prime/login/rc4
import genesis_prime/login/service
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_xml
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted
import genesis_prime/message/login_request.{LoginRequest}
import gleam/bit_array
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor
import gleam/string
import owned_test
import scripted_client.{type Reply}
import seeded
import template_database

/// The test's server: the account store's database, the two hand-offs and the
/// connections' services.
type Server {
  Server(
    sts: sts_connection.Services,
    auth: auth_connection.Services,
    session_keys: Name(handoff.Message(Identity)),
    game_tokens: Name(handoff.Message(Identity)),
  )
}

fn start_server(database: template_database.Database) -> Server {
  let game_tokens = process.new_name("flow_game_tokens")
  let session_keys = process.new_name("flow_session_keys")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(
      service.supervised(service.Settings(
        game_tokens: handoff.Settings(
          name: game_tokens,
          expiry_milliseconds: 60_000,
          clock: fn() { 0 },
        ),
        session_keys: handoff.Settings(
          name: session_keys,
          expiry_milliseconds: 60_000,
          clock: fn() { 0 },
        ),
      )),
    )
    |> static_supervisor.start
    as "the login subtree did not start"
  Server(
    sts: sts_connection.services(database.connection, game_tokens),
    auth: auth_connection.services(game_tokens, session_keys),
    session_keys:,
    game_tokens:,
  )
}

/// The client's side of one STS connection: the connection, the RC4 streams
/// once the exchange is done, and the next sequence number.
type StsClient {
  StsClient(
    connection: sts_connection.Connection,
    receiving: option.Option(rc4.Stream),
    sending: option.Option(rc4.Stream),
    next_sequence: Int,
  )
}

/// What the client hears back: its state and the reply, or that the server
/// closed the connection.
type Heard {
  Heard(client: StsClient, replies: List(Reply), closed: Bool)
}

fn connect(server: Server) -> StsClient {
  StsClient(
    connection: sts_connection.new(server.sts),
    receiving: None,
    sending: None,
    next_sequence: 1,
  )
}

/// Sends bytes the way the library does (through RC4 once it is on) and reads
/// what the server writes back.
fn talk(client: StsClient, plain: BitArray) -> Heard {
  let wire = case client.sending {
    Some(stream) -> rc4.crypt(stream, plain)
    None -> plain
  }
  let output = sts_connection.receive(client.connection, wire)
  let #(replies, receiving) =
    read_replies(receiving: client.receiving, writes: output.send, read: [])
  Heard(
    client: StsClient(..client, connection: output.connection, receiving:),
    replies:,
    closed: output.close,
  )
}

/// Reads each write the server made, deciphering with the client's receiving
/// stream, which starts after the reply that carries M2.
fn read_replies(
  receiving receiving: option.Option(rc4.Stream),
  writes writes: List(BitArray),
  read read: List(Reply),
) -> #(List(Reply), option.Option(rc4.Stream)) {
  case writes {
    [] -> #(list.reverse(read), receiving)
    [written, ..rest] -> {
      let plain = case receiving {
        Some(stream) -> rc4.crypt(stream, written)
        None -> written
      }
      let assert Ok(reply) = scripted_client.read_reply(plain)
        as "the server wrote a reply the library reads"
      read_replies(receiving:, writes: rest, read: [reply, ..read])
    }
  }
}

fn transaction(
  client client: StsClient,
  protocol protocol: String,
  command command: String,
  body body: sts_xml.Node,
) -> Heard {
  let heard =
    talk(
      client,
      scripted_client.request(
        sequence: Some(client.next_sequence),
        protocol:,
        command:,
        body: sts_xml.render(body),
      ),
    )
  Heard(
    ..heard,
    client: StsClient(..heard.client, next_sequence: client.next_sequence + 1),
  )
}

fn only(heard: Heard) -> Reply {
  let assert [reply] = heard.replies as "one reply"
  reply
}

/// What a completed STS login gives the client: the UserId and the game token
/// as their texts.
type StsLogin {
  StsLogin(user_id: String, token: String, name: String)
}

/// Runs the client's STS login to the game token: Connect, LoginStart, KeyData,
/// LoginFinish, ListMyAccounts and RequestGameToken (the library's order).
fn sts_login(
  server server: Server,
  name name: String,
  password password: String,
  seed seed: Int,
) -> StsLogin {
  let client = connect(server)
  let heard =
    talk(
      client,
      scripted_client.request(
        sequence: None,
        protocol: "Sts",
        command: "Connect",
        body: sts_xml.render(
          sts_xml.Parent("Connect", [sts_xml.Text("ConnType", "1281")]),
        ),
      ),
    )
  assert heard.replies == [] as "Connect is one-way"
  let lowered = string.lowercase(name)
  let heard =
    transaction(
      client: heard.client,
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", lowered),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  let first = only(heard)
  assert first.status == 200
    as "StsConnLib64.MT.dll!0x180034a30: a success is 200"
  let assert Ok(encoded) = scripted_client.child_text(first, "KeyData")
    as "the reply holds KeyData (StsConnLib64.MT.dll!0x18000a350)"
  let assert Ok(server_key_data) = bit_array.base64_decode(encoded)
    as "KeyData is base64"
  let #(secret, _) = seeded.bytes(state: seed, count: 32)
  let assert Ok(exchange) =
    scripted_client.exchange(
      name: lowered,
      password:,
      secret:,
      server_key_data:,
    )
    as "the server's key data is the salt and B"
  let heard =
    transaction(
      client: heard.client,
      protocol: "Auth",
      command: "KeyData",
      body: sts_xml.Parent("Request", [
        sts_xml.Text(
          "KeyData",
          bit_array.base64_encode(exchange.key_data, True),
        ),
      ]),
    )
  let second = only(heard)
  let assert Ok(second_encoded) = scripted_client.child_text(second, "KeyData")
    as "the reply holds the second KeyData"
  let assert Ok(second_data) = bit_array.base64_decode(second_encoded)
    as "base64"
  assert second_data == <<32:size(32)-little, exchange.expected_m2:bits>>
    as "StsConnLib64.MT.dll!0x18002d3b0: the client accepts M2 = SHA-256(A | M1 | K) and nothing else"
  // From the next byte, RC4 under K covers both directions.
  let assert Ok(receiving) = rc4.start(exchange.session_key)
    as "this OTP has RC4"
  let assert Ok(sending) = rc4.start(exchange.session_key) as "this OTP has RC4"
  let client =
    StsClient(
      ..heard.client,
      receiving: Some(receiving),
      sending: Some(sending),
    )
  let heard =
    transaction(
      client: client,
      protocol: "Auth",
      command: "LoginFinish",
      body: sts_xml.Empty("Request"),
    )
  let finished = only(heard)
  let assert Ok(user_id) = scripted_client.child_text(finished, "UserId")
    as "LoginFinish's reply holds the UserId"
  assert scripted_client.child_text(finished, "AuthType") == Ok("0")
    as "StsConnLib64.MT.dll!0x1800043d0: AuthType 0 is a finished login"
  let heard =
    transaction(
      client: heard.client,
      protocol: "GameAccount",
      command: "ListMyAccounts",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
      ]),
    )
  let listed = only(heard)
  let assert Ok(game_account) = sts_xml.child(listed.root, "GameAccount")
    as "exactly one GameAccount (HandleListMyAccountsResult 0x1400b36c0)"
  let assert Ok(alias) = sts_xml.child(game_account, "Alias")
    as "GameAccount has an Alias"
  let heard =
    transaction(
      client: heard.client,
      protocol: "Auth",
      command: "RequestGameToken",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
        sts_xml.Text("AccountAlias", alias.text),
      ]),
    )
  let assert Ok(token) = scripted_client.child_text(only(heard), "Token")
    as "the reply holds the Token"
  StsLogin(user_id:, token:, name:)
}

/// The client's side of the auth connection for an STS login: the login
/// request the client writes, with its UserId and its game token parsed from
/// their texts as UuidFromStringA does, in a 0x244 wrapper under the base key.
fn login_request_frame(login login: StsLogin, build build: Int) -> Frame {
  let assert Ok(user_id) = guid.from_text(login.user_id)
    as "the UserId is a GUID text"
  let assert Ok(token) = guid.from_text(login.token)
    as "the token is a GUID text"
  let request =
    LoginRequest(
      build:,
      files_digest: 0x0807060504030201,
      account_name: login.name,
      field_4: guid.to_wire(user_id),
      field_5: guid.to_wire(token),
      field_6: 0,
      field_7: 0,
      field_8: 0,
      field_9: 0,
      processor_manufacturer: "a",
      processor_name: "bc",
      processor_description: "",
      processor_family: 0,
      processor_level: 0,
      processor_revision: 0,
      processor_clock_speed: 0,
      processor_core_count: 0,
      memory_mebibytes: 0,
      video_adapter_description: "d",
      video_adapter_vendor_id: 0,
      video_adapter_device_id: 0,
      video_adapter_subsystem_id: 0,
      video_adapter_revision: 0,
      video_adapter_memory_mebibytes: 0,
      processor_architecture: 0,
      windows_version: 0,
      service_pack: 0,
      os_flags: 0,
      realm_data_center_id: 0,
    )
  let assert Ok(body) = login_request.encode(request) as "the request encodes"
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  let assert Ok(bytes) =
    encrypted_frame.wrap(ClientWrapper, Frame(0x0592, body), base)
    as "the frame wraps"
  let assert Ok(#([outer], <<>>)) = frame.decode(bytes) as "one frame"
  outer
}

fn auth_settings() -> auth_session.Settings {
  auth_session.Settings(
    game_server: Endpoint(address: 0x7F000001, port: 24_000),
    realm_name: "Nexus",
    expected_files_digest: None,
  )
}

/// What the auth connection wrote, as the client reads it: the frames, with
/// each 0x76 wrapper opened under the base key.
fn read_writes(writes: List(BitArray)) -> List(Frame) {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  list.map(writes, fn(bytes) {
    let assert Ok(#([outer], <<>>)) = frame.decode(bytes) as "one frame"
    case outer.message_id == encrypted_frame.message_id(AuthWrapper) {
      True -> {
        let assert Ok(inner) = encrypted_frame.unwrap(outer, base)
          as "the client reads 0x76 under the base key"
        inner
      }
      False -> outer
    }
  })
}

/// The session keys the writes hand over: the key of each 0x3DB.
fn handed_keys(frames: List(Frame)) -> List(BitArray) {
  list.filter_map(frames, fn(sent) {
    case sent.message_id {
      0x03DB -> {
        let assert Ok(handoff) = game_server_handoff.decode(sent.body)
          as "the hand-off decodes"
        Ok(handoff.session_key)
      }
      _ -> Error(Nil)
    }
  })
}

pub fn a_player_logs_in_through_sts_and_auth_and_is_handed_a_session_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(account) =
    account_store.create(database.connection, "Jim", "secret")
    as "the account is created"
  let login = sts_login(server:, name: "Jim", password: "secret", seed: 0x39)
  assert login.user_id == guid.to_text(account.user_id)
    as "the STS login's UserId is the account's GUID"

  let hello = auth_connection.new(server.auth, auth_settings(), "peer")
  let assert [hello_bytes] = hello.send as "the hello is the first write"
  let assert Ok(#([hello_frame], <<>>)) = frame.decode(hello_bytes)
    as "the hello is one frame"
  assert hello_frame.message_id == 0x0003
    as "opcode.0x3: the hello is message 3"

  let answered =
    auth_connection.receive(
      hello.connection,
      login_request_frame(login:, build: 16_042),
    )
  assert !answered.close as "the connection stays open after the hand-off"
  let frames = read_writes(answered.send)
  assert list.map(frames, fn(sent) { sent.message_id }) == [0x0591, 0x03DB]
    as "opcode.0x591 then opcode.0x3db"
  let assert [accepted, handed] = frames as "two frames"
  assert login_accepted.decode(accepted.body)
    == Ok(login_accepted.LoginAccepted(0))
    as "opcode.0x591: login accepted"
  let assert Ok(handoff_message) = game_server_handoff.decode(handed.body)
    as "the hand-off decodes"
  assert handoff_message.game_server
    == Endpoint(address: 0x7F000001, port: 24_000)
    as "opcode.0x3db: the address of the game listener and its port"
  assert bit_array.byte_size(handoff_message.session_key) == 16
    as "opcode.0x3db: the session key is 16 bytes"
  assert handoff.redeem(server.session_keys, handoff_message.session_key)
    == Ok(account.identity(account))
    as "the session key is held for the game server's 0x58F check, for the account that logged in"
}

pub fn two_logins_get_different_tokens_and_session_keys_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let first = sts_login(server:, name: "jim", password: "secret", seed: 1)
  let second = sts_login(server:, name: "jim", password: "secret", seed: 2)
  assert first.token != second.token
    as "each RequestGameToken issues a fresh token"
  let keys =
    list.flat_map([first, second], fn(login) {
      let hello = auth_connection.new(server.auth, auth_settings(), "peer")
      let answered =
        auth_connection.receive(
          hello.connection,
          login_request_frame(login:, build: 16_042),
        )
      handed_keys(read_writes(answered.send))
    })
  let assert [one, other] = keys as "each login is handed a key"
  assert one != other as "each hand-off carries a fresh session key"
}

pub fn a_wrong_password_ends_the_sts_login_with_the_invalid_login_code_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let client = connect(server)
  let heard =
    transaction(
      client: client,
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", "jim"),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  let assert Ok(encoded) = scripted_client.child_text(only(heard), "KeyData")
    as "the reply holds KeyData"
  let assert Ok(server_key_data) = bit_array.base64_decode(encoded) as "base64"
  let #(secret, _) = seeded.bytes(state: 7, count: 32)
  let assert Ok(exchange) =
    scripted_client.exchange(
      name: "jim",
      password: "not the secret",
      secret:,
      server_key_data:,
    )
    as "the exchange runs"
  let heard =
    transaction(
      client: heard.client,
      protocol: "Auth",
      command: "KeyData",
      body: sts_xml.Parent("Request", [
        sts_xml.Text(
          "KeyData",
          bit_array.base64_encode(exchange.key_data, True),
        ),
      ]),
    )
  let refusal = only(heard)
  assert refusal.status == 400
    as "StsConnLib64.MT.dll!0x18002de60: an error reply is status 400"
  assert refusal.root.name == "Error"
    as "StsConnLib64.MT.dll!0x18002de60: the root is an Error element"
  assert heard.closed
    as "the login ends: the connection closes after the refusal"
}

pub fn an_unknown_account_ends_the_sts_login_with_the_same_refusal_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let heard =
    transaction(
      client: connect(server),
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", "nobody"),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  let refusal = only(heard)
  assert refusal.status == 400 as "an error reply is status 400"
  assert heard.closed as "the connection closes after the refusal"
}

pub fn a_game_token_is_used_once_and_the_second_use_gets_no_session_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let login = sts_login(server:, name: "jim", password: "secret", seed: 3)
  let first = auth_connection.new(server.auth, auth_settings(), "peer")
  let answered =
    auth_connection.receive(
      first.connection,
      login_request_frame(login:, build: 16_042),
    )
  assert list.length(handed_keys(read_writes(answered.send))) == 1
    as "the first use is handed a key"
  let second = auth_connection.new(server.auth, auth_settings(), "peer")
  let refused =
    auth_connection.receive(
      second.connection,
      login_request_frame(login:, build: 16_042),
    )
  assert refused.close
    as "the login issue: the game token is used once, and the second use ends the connection"
  assert refused.send == []
    as "no 0x591 and no session key for a token already used"
}

pub fn a_build_other_than_16042_gets_no_session_key_and_spends_no_token_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let login = sts_login(server:, name: "jim", password: "secret", seed: 4)
  let wrong = auth_connection.new(server.auth, auth_settings(), "peer")
  let refused =
    auth_connection.receive(
      wrong.connection,
      login_request_frame(login:, build: 16_043),
    )
  assert refused.close && refused.send == []
    as "CheckAuthServerVersion 0x140037b70: the client's build is 16042, and another ends the connection with nothing sent"
  let right = auth_connection.new(server.auth, auth_settings(), "peer")
  let answered =
    auth_connection.receive(
      right.connection,
      login_request_frame(login:, build: 16_042),
    )
  assert list.length(handed_keys(read_writes(answered.send))) == 1
    as "the token the wrong build did not spend is still good for the right one"
}

pub fn a_token_the_server_never_issued_gets_no_session_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let server = start_server(database)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let made_up =
    StsLogin(
      user_id: guid.to_text(account.user_id),
      token: "00112233-4455-6677-8899-aabbccddeeff",
      name: "jim",
    )
  let hello = auth_connection.new(server.auth, auth_settings(), "peer")
  let refused =
    auth_connection.receive(
      hello.connection,
      login_request_frame(login: made_up, build: 16_042),
    )
  assert refused.close && refused.send == []
    as "the login issue: the game token is the real link between STS and auth, and an unknown one is refused"
}
