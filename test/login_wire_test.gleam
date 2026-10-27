//// The login's bytes on the wire: the STS and the auth listener of the
//// server's real tree, on a migrated database of the test's own, played by
//// the scripted client (`login_client`, `scripted_client`). Expected values
//// come from these places.
//// - The library's vector `vector.StsConnLib64.MT.dll!0x18002d4e0.srp`
////   (`login_vectors`): account `jim`, password `secret`, its salt and
////   verifier, inserted as the account's row.
//// - The client's own side of the exchange, written from the records in
////   `scripted_client`: M2 = SHA-256(A | M1 | K) (0x18002d3b0).
//// - RC4: plain up to the end of the M2 reply; from the next byte each way,
////   one state per direction under K; the server sends nothing between M2
////   and LoginFinish (StsConnLib64.MT.dll!0x18000a350).
//// - The hello: build 16042 and checksum 0x097998A0 (0x140037b70), the
////   realm's id, 0 in every other field (opcode.0x3). 0x591 and 0x3db as the
////   auth rule's doc comment draws them (opcode.0x591, opcode.0x3db).
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import genesis_prime/hand_off
import genesis_prime/login/guid
import genesis_prime/login/rc4
import genesis_prime/login/sts_xml
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/service/shell as service_shell
import genesis_prime/store.{AccountId}
import gleam/bit_array
import gleam/erlang/process
import gleam/option.{Some}
import login_client.{StsClient}
import login_rule_support as support
import login_support
import login_vectors as vector
import owned_test

/// The tree, with the account of the library's vector inserted, its ports
/// and the account's id.
fn start() -> #(login_support.Started, login_client.Ports, Int) {
  let started = login_support.start()
  let account_id = login_support.insert_jim(started)
  #(started, login_support.ports(started), account_id)
}

fn stop(started: login_support.Started) -> Nil {
  let _reason = ask_support.stop_tree(started.tree)
  Nil
}

pub fn the_sts_login_runs_plain_to_m2_and_then_both_ways_on_rc4_under_k_one_state_per_direction_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, ports, _account_id) = start()
  let client = login_client.sts_connect(ports)
  let #(answered, exchange) =
    login_client.srp_exchange(
      client:,
      name: vector.name,
      password: vector.password,
      seed: 7,
    )
  assert answered.reply.status == 200 as "the proof is accepted, in plain text"
  assert login_client.child(reply: answered.reply, name: "KeyData")
    == bit_array.base64_encode(
      <<32:size(32)-little, exchange.expected_m2:bits>>,
      True,
    )
    as "StsConnLib64.MT.dll!0x18002d3b0: M2 = SHA-256(A | M1 | K), read with no cipher on"
  let assert Ok(sending) = rc4.start(exchange.session_key)
  let assert Ok(receiving) = rc4.start(exchange.session_key)
  let client =
    StsClient(
      ..answered.client,
      sending: Some(sending),
      receiving: Some(receiving),
    )
  // Nothing the server sent between M2 and LoginFinish: its reply to
  // LoginFinish deciphers from the first byte of the receiving stream.
  let finished =
    login_client.ask(
      client:,
      protocol: "Auth",
      command: "LoginFinish",
      body: sts_xml.Empty("Request"),
    )
  assert login_client.child(reply: finished.reply, name: "AuthType") == "0"
    as "the first bytes after M2 decipher under K with none dropped"
  assert login_client.child(reply: finished.reply, name: "UserId")
    == guid.to_text(support.jim().game_account_id)
  // The next reply runs on the same receiving state; the next request on the
  // same sending state.
  let listed =
    login_client.ask(
      client: finished.client,
      protocol: "GameAccount",
      command: "ListMyAccounts",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", guid.to_text(support.jim().game_account_id)),
        sts_xml.Text("GameCode", "wildstar"),
      ]),
    )
  assert listed.reply.status == 200
    as "each direction's state runs on across messages"
  stop(started)
}

pub fn a_client_that_connects_to_the_auth_listener_gets_the_hello_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, ports, _account_id) = start()
  let socket = login_client.connect(ports.auth_port)
  let assert [hello] =
    login_client.read_frames(client: socket, have: <<>>, count: 1)
    as "the auth server greets the client first"
  assert hello.message_id == 0x0003 as "the hello travels bare"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the hello decodes"
  assert decoded
    == ServerHello(
      build: 16_042,
      realm_id: 1,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0,
      message_table_checksum: 0x097998A0,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    )
    as "CheckAuthServerVersion 0x140037b70: build 16042, checksum 0x097998A0; the realm's id; 0 in every field the client never reads"
  stop(started)
}

pub fn a_login_request_with_the_stss_game_token_gets_0x591_then_0x3db_and_the_hand_off_keeps_the_session_key_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, ports, account_id) = start()
  let login =
    login_client.sts_login(
      ports: ports,
      name: vector.name,
      password: vector.password,
      seed: 7,
    )
  let socket = login_client.auth_login(ports: ports, login:, build: 16_042)
  let assert [accepted, handoff] =
    login_client.read_frames(client: socket, have: <<>>, count: 2)
    as "0x591 then 0x3db"
  let accepted = login_client.in_the_auth_wrapper(accepted)
  let handoff = login_client.in_the_auth_wrapper(handoff)
  assert accepted.message_id == 0x0591 && handoff.message_id == 0x03DB
  assert login_accepted.decode(accepted.body)
    == Ok(LoginAccepted(disconnected_for_lag: 0))
  let assert Ok(handed) = game_server_handoff.decode(handoff.body)
    as "0x3db decodes"
  assert handed.game_server == login_support.realm().game_server
  assert handed.account_id == account_id as "opcode.0x3db: the account's id"
  assert handed.realm_name == "Nexus"
  assert handed.realm_flags == 0
    && handed.realm_pvp_type == 0
    && handed.realm_note_text_id == 0
    as "flags 0, PvE and no note"
  // The hand-off keeps the session key for the account.
  let assert Ok(session_key) = guid.from_wire(handed.session_key)
  let answers = process.new_subject()
  let assert Ok(_) =
    service_shell.call(
      name: started.settings.hand_off,
      message: hand_off.Take(hand_off.SessionKey(session_key)),
      reply: fn(answer) { process.send(answers, answer) },
    )
    as "the hand-off is running"
  let assert Ok(hand_off.Taken(holder:)) =
    process.receive(answers, within: 5000)
    as "the hand-off answered"
  assert holder.account_id == AccountId(account_id)
  assert holder.login_name == vector.name
  stop(started)
}
