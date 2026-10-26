//// One STS connection as a process carries it out, against the library's own
//// bytes: the account is the SRP vector's (fact file
//// `vector.StsConnLib64.MT.dll!0x18002d4e0.srp`: jim, secret, salt 01 .. 10,
//// the server's b = 51 .. 70) and the services are planted, so the replies are
//// the vector's bytes. After the exchange RC4 under the vector's K covers both
//// directions (StsConnLib64.MT.dll!0x18000a350, 0x18003a7d0; vector
//// `vector.StsConnLib64.MT.dll!0x1800f7420.rc4`).

import genesis_prime/login/account.{type Identity, Account}
import genesis_prime/login/guid
import genesis_prime/login/rc4
import genesis_prime/login/sts_connection.{type Output}
import genesis_prime/login/sts_message
import gleam/bit_array
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import log_capture.{Text, Whole}
import login_vectors as vector
import message_support
import owned_test
import scripted_client

const user_id_text = "00112233-4455-6677-8899-aabbccddeeff"

fn user_id() -> guid.Guid {
  let assert Ok(parsed) = guid.from_text(user_id_text) as "a GUID text"
  parsed
}

fn services() -> sts_connection.Services {
  sts_connection.Services(
    find_account: fn(name) {
      case name == vector.name {
        True ->
          Ok(Account(
            id: 7,
            name:,
            user_id: user_id(),
            salt: vector.salt(),
            verifier: vector.verifier(),
            created: "2026-01-02T03:04:05Z",
          ))
        False -> Error(Nil)
      }
    },
    issue_game_token: fn(_identity: Identity) {
      message_support.hex("33221100 5544 7766 8899 aabbccddeeff")
    },
    draw_secret: vector.server_secret,
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

fn key_data() -> BitArray {
  scripted_client.request(
    sequence: Some(2),
    protocol: "Auth",
    command: "KeyData",
    body: "<Request>\n<KeyData>"
      <> vector.client_key_data_base64
      <> "</KeyData>\n</Request>\n",
  )
}

fn after_the_exchange() -> Output {
  let started =
    sts_connection.receive(sts_connection.new(services(), None), login_start())
  sts_connection.receive(started.connection, key_data())
}

pub fn the_first_reply_is_the_vectors_key_data_test() -> Nil {
  use <- owned_test.run(5000)
  let output =
    sts_connection.receive(sts_connection.new(services(), None), login_start())
  assert output.send
    == [
      sts_message.encode(sts_message.KeyDataAnswer(
        sequence: 1,
        key_data: vector.server_key_data(),
      )),
    ]
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: the server's KeyData for jim with b = 51 .. 70"
  assert !output.close as "the connection stays open for the client's answer"
}

pub fn a_request_that_arrives_in_two_reads_is_answered_once_it_is_whole_test() -> Nil {
  use <- owned_test.run(5000)
  let whole = login_start()
  let assert Ok(first) = bit_array.slice(whole, 0, 30) as "a prefix"
  let assert Ok(second) =
    bit_array.slice(whole, 30, bit_array.byte_size(whole) - 30)
    as "the rest"
  let waiting =
    sts_connection.receive(sts_connection.new(services(), None), first)
  assert waiting.send == [] as "a half request is not answered"
  let answered = sts_connection.receive(waiting.connection, second)
  assert list.length(answered.send) == 1
    as "the request is answered when its last byte arrives"
}

pub fn m2_goes_out_in_the_clear_and_the_cipher_covers_what_follows_test() -> Nil {
  use <- owned_test.run(5000)
  let proved = after_the_exchange()
  assert proved.send
    == [
      sts_message.encode(sts_message.KeyDataAnswer(
        sequence: 2,
        key_data: vector.second_server_key_data(),
      )),
    ]
    as "StsConnLib64.MT.dll!0x18000a350: the library puts RC4 under K on the connection from the next byte, so the reply that carries M2 is in the clear"
  let assert Ok(client_sending) = rc4.start(vector.session_key())
    as "this OTP has RC4"
  let assert Ok(client_receiving) = rc4.start(vector.session_key())
    as "this OTP has RC4"
  let request =
    scripted_client.request(
      sequence: Some(3),
      protocol: "Auth",
      command: "LoginFinish",
      body: "<Request/>\n",
    )
  let finished =
    sts_connection.receive(
      proved.connection,
      rc4.crypt(client_sending, request),
    )
  let assert [written] = finished.send as "one reply"
  assert rc4.crypt(client_receiving, written)
    == sts_message.encode(sts_message.LoginFinished(
      sequence: 3,
      user_id: user_id_text,
      user_name: "jim",
    ))
    as "StsConnLib64.MT.dll!0x18003a7d0: the connection's bytes in both directions are RC4 under K, one state each, running on across messages"
}

pub fn a_request_in_the_clear_after_the_exchange_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let proved = after_the_exchange()
  let finished =
    sts_connection.receive(
      proved.connection,
      scripted_client.request(
        sequence: Some(3),
        protocol: "Auth",
        command: "LoginFinish",
        body: "<Request/>\n",
      ),
    )
  assert finished.close
    as "StsConnLib64.MT.dll!0x18003a7d0: after the exchange the client ciphers every byte, so bytes in the clear are not the client's"
  assert finished.send == []
    as "nothing is answered to bytes that do not decipher to a request"
}

pub fn bytes_that_are_not_a_request_end_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let output =
    sts_connection.receive(sts_connection.new(services(), None), <<
      "GET / HTTP/1.1\r\n\r\n":utf8,
    >>)
  assert output.close && output.send == []
    as "CLAUDE.md: a decode failure ends the connection; StsConnLib64.MT.dll!0x180022cb0: a request starts POST /<protocol>/<command> STS/1.0"
}

pub fn a_request_of_no_known_command_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let output =
    sts_connection.receive(
      sts_connection.new(services(), None),
      scripted_client.request(
        sequence: Some(1),
        protocol: "Auth",
        command: "Surprise",
        body: "<Request/>\n",
      ),
    )
  assert output.close && output.send == []
    as "the login uses six commands (StsConnLib64.MT.dll!0x180022cb0), and another is not the client's"
}

pub fn an_account_that_does_not_exist_gets_the_refusal_and_the_connection_closes_test() -> Nil {
  use <- owned_test.run(5000)
  let output =
    sts_connection.receive(
      sts_connection.new(services(), None),
      scripted_client.request(
        sequence: Some(1),
        protocol: "Auth",
        command: "LoginStart",
        body: "<Request>\n<LoginName>nobody</LoginName>\n<NetAddress>1.2.3.4</NetAddress>\n</Request>\n",
      ),
    )
  assert output.send
    == [
      sts_message.encode(sts_message.Refused(sequence: 1, code: 3002)),
    ]
    as "HandleLoginStartResult 0x1400b2f20: 10, 11 and 3002 raise the invalid login event"
  assert output.close as "the refusal is the last write"
}

pub fn a_connection_that_ended_answers_nothing_more_test() -> Nil {
  use <- owned_test.run(5000)
  let ended =
    sts_connection.receive(sts_connection.new(services(), None), <<
      "GET / HTTP/1.1\r\n\r\n":utf8,
    >>)
  let again = sts_connection.receive(ended.connection, login_start())
  assert again.send == [] && again.close
    as "after a connection ends it takes no more"
}

pub fn the_line_of_an_account_that_is_not_found_carries_the_peer_and_no_account_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  let _ended =
    sts_connection.receive(
      sts_connection.new(services(), Some("192.0.2.1:50000")),
      scripted_client.request(
        sequence: Some(1),
        protocol: "Auth",
        command: "LoginStart",
        body: "<Request>\n<LoginName>nobody</LoginName>\n<NetAddress>1.2.3.4</NetAddress>\n</Request>\n",
      ),
    )
  let assert Ok(line) =
    log_capture.next_from(capture:, from: process.self(), within: 2000)
    as "the connection did not log why it ended"
  assert line.level == "warning"
    as "designing-processes: an outside failure the server recovered from is a warning"
  assert dict.get(line.metadata, "peer") == Ok(Text("192.0.2.1:50000"))
    as "designing-processes: every line carries who and where; a connection with no login is known by its peer"
  assert dict.get(line.metadata, "account") == Error(Nil)
    as "no account is known before the login finds one"
}

pub fn the_line_of_a_login_that_failed_after_the_account_was_found_carries_its_id_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  let started =
    sts_connection.receive(
      sts_connection.new(services(), Some("192.0.2.1:50000")),
      login_start(),
    )
  let _ended =
    sts_connection.receive(
      started.connection,
      scripted_client.request(
        sequence: Some(2),
        protocol: "Auth",
        command: "KeyData",
        body: "<Request>\n<KeyData>AAEC</KeyData>\n</Request>\n",
      ),
    )
  let assert Ok(line) =
    log_capture.next_from(capture:, from: process.self(), within: 2000)
    as "the connection did not log why it ended"
  assert dict.get(line.metadata, "account") == Ok(Whole(7))
    as "designing-processes: the line carries the account once the login has found it"
  assert dict.get(line.metadata, "peer") == Ok(Text("192.0.2.1:50000"))
    as "and the peer, which names the connection"
  assert !string.contains(line.formatted, "secret")
    as "designing-processes: never a password or a key in a log line"
}
