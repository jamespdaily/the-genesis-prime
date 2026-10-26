//// The key a login connection puts on its draws. The expected values are the
//// issue's test 1: a connection is named by the listener it reached, its peer
//// address and the order it started in, so a recording of draws can tell apart
//// two connections of one client address (one on each listener, or one after
//// the other on a port that was used again). The STS connection draws its SRP
//// secret and asks for a game token, and the auth connection asks for a session
//// key, each naming its connection; a connection with no peer names none.

import genesis_prime/login/account.{type Identity, Account, Identity}
import genesis_prime/login/auth_connection
import genesis_prime/login/auth_session
import genesis_prime/login/guid
import genesis_prime/login/random_source.{type Connection, Auth, Connection, Sts}
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import owned_test
import scripted_client

/// How long a test waits for a connection to name itself, in milliseconds.
const wait_ms = 5000

fn user_id() -> guid.Guid {
  let assert Ok(parsed) = guid.from_text("00112233-4455-6677-8899-aabbccddeeff")
    as "a GUID text"
  parsed
}

/// STS services that report the connection each draw and each game token is
/// for, and answer with fixed bytes.
fn sts_services(
  reports: Subject(Option(Connection)),
) -> sts_connection.Services {
  sts_connection.Services(
    find_account: fn(_name) {
      Ok(Account(
        id: 7,
        name: "jim",
        user_id: user_id(),
        salt: <<1:size(128)>>,
        verifier: <<2:size(1024)>>,
        created: "2026-01-02T03:04:05Z",
      ))
    },
    issue_game_token: fn(_identity: Identity, origin) {
      process.send(reports, origin)
      <<0:size(128)>>
    },
    draw_secret: fn(origin, _account) {
      process.send(reports, origin)
      <<3:size(256)>>
    },
  )
}

fn login_start() -> BitArray {
  scripted_client.request(
    sequence: Some(1),
    protocol: "Auth",
    command: "LoginStart",
    body: "<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n",
  )
}

/// The connection an STS connection that has served a LoginStart named in its
/// draw.
fn sts_origin(peer: Option(String)) -> Option(Connection) {
  let reports = process.new_subject()
  let connection = sts_connection.new(sts_services(reports), peer)
  let _ = sts_connection.receive(connection, login_start())
  let assert Ok(origin) = process.receive(reports, wait_ms)
    as "the connection drew its secret"
  origin
}

pub fn an_sts_connection_names_its_listener_its_peer_and_its_start_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let peer = "127.0.0.1:40001"
  let assert Some(first) = sts_origin(Some(peer))
    as "a connection with a peer names itself"
  let assert Some(second) = sts_origin(Some(peer))
    as "a second connection of the same address names itself"
  assert first.role == Sts as "an STS connection names the STS listener"
  assert first.peer == peer as "it names the client's address"
  assert second.peer == peer && second.role == Sts
    as "the second connection is of the same listener and address"
  assert first.started < second.started
    as "the connection that started later has the later start order, so the two are told apart and ranked"
}

pub fn an_sts_connection_with_no_peer_names_no_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  assert sts_origin(None) == None
}

pub fn an_auth_connection_names_the_auth_listener_in_the_draw_of_its_session_key_test() -> Nil {
  use <- owned_test.run(10_000)
  let reports = process.new_subject()
  let identity = Identity(id: 7, name: "jim", user_id: user_id())
  let services =
    auth_connection.Services(
      redeem_game_token: fn(_key) { Ok(identity) },
      issue_session_key: fn(_identity, origin) {
        process.send(reports, origin)
        <<0:size(128)>>
      },
    )
  let settings =
    auth_session.Settings(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      realm_name: "Nexus",
      expected_files_digest: None,
    )
  let peer = "127.0.0.1:40001"
  let hello = auth_connection.new(services, settings, Some(peer))
  let login =
    scripted_client.StsLogin(
      user_id: "00112233-4455-6677-8899-aabbccddeeff",
      token: "33221100-5544-7766-8899-aabbccddeeff",
      name: "jim",
    )
  let _ =
    auth_connection.receive(
      hello.connection,
      scripted_client.login_request_frame(login:, build: 16_042),
    )
  let assert Ok(Some(origin)) = process.receive(reports, wait_ms)
    as "the connection asked for a session key, naming itself"
  assert origin.role == Auth && origin.peer == peer
    as "an auth connection names the auth listener and the client's address"
}
