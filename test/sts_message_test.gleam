//// The messages of the STS login in typed values. The requests are decoded
//// from the bytes `vector.StsConnLib64.MT.dll!0x180022cb0.messages` records
//// (the library's own writers run on Ghidra's p-code emulator) or, where that
//// vector has none, from bodies written as the records name their children:
//// `StsConnLib64.MT.dll!0x18002f410` (Connect), `0x180004950` (ListMyAccounts)
//// and `0x180004ac0` (RequestGameToken). The answers are the bodies the
//// records say the client reads: `0x18000a350` (KeyData), `0x1800043d0`
//// (LoginFinish), `0x180004950` (the game accounts), `0x180004ac0` (the token),
//// `0x18002de60` (an error), and the vector's own reply to sequence 5.

import genesis_prime/login/sts_message.{
  Connect, ConnectionOpened, GameAccount, KeyData, ListMyAccounts, LoginFinish,
  LoginStart, Ping, RequestGameToken, Transaction,
}
import genesis_prime/login/sts_wire.{Request}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import login_vectors as vector
import owned_test

fn request(
  sequence sequence: option.Option(Int),
  command command: String,
  body body: String,
) -> sts_wire.Request {
  Request(sequence:, protocol: "Auth", command:, body: <<body:utf8>>)
}

/// The bytes of a final reply: the status line, the sequence with R, the
/// length of the body in bytes and the body.
fn reply(
  status status: String,
  sequence sequence: Int,
  body body: String,
) -> BitArray {
  let length = bit_array.byte_size(<<body:utf8>>)
  <<
    "STS/1.0 ":utf8,
    status:utf8,
    "\r\ns:":utf8,
    int.to_string(sequence):utf8,
    "R\r\nl:":utf8,
    int.to_string(length):utf8,
    "\r\n\r\n":utf8,
    body:utf8,
  >>
}

pub fn the_login_start_the_library_writes_decodes_to_the_name_and_address_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(1),
      command: "LoginStart",
      body: "<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n",
    ))
    == Ok(Transaction(
      1,
      LoginStart(login_name: "jim", net_address: "192.168.1.5"),
    ))
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginStart for name jim, address 192.168.1.5, sequence 1"
}

pub fn the_key_data_the_library_writes_decodes_to_its_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(2),
      command: "KeyData",
      body: "<Request>\n<KeyData>AAECAwQFBgcICQ==</KeyData>\n</Request>\n",
    ))
    == Ok(Transaction(2, KeyData(<<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>)))
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: KeyData of the bytes 00..09 is AAECAwQFBgcICQ== with sequence 2"
}

pub fn the_clients_srp_answer_decodes_to_the_vectors_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(2),
      command: "KeyData",
      body: "<Request>\n<KeyData>"
        <> vector.client_key_data_base64
        <> "</KeyData>\n</Request>\n",
    ))
    == Ok(Transaction(2, KeyData(vector.client_key_data())))
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: the client answers KeyData with the base64 of A and M1"
}

pub fn the_login_finish_the_library_writes_decodes_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(3),
      command: "LoginFinish",
      body: "<Request/>\n",
    ))
    == Ok(Transaction(3, LoginFinish))
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginFinish with sequence 3 and <Request/>"
}

pub fn the_list_my_accounts_request_holds_the_user_id_and_the_game_code_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(
      Request(
        sequence: Some(4),
        protocol: "GameAccount",
        command: "ListMyAccounts",
        body: <<
          "<Request>\n<UserId>00112233-4455-6677-8899-aabbccddeeff</UserId>\n<GameCode>wildstar</GameCode>\n</Request>\n":utf8,
        >>,
      ),
    )
    == Ok(Transaction(
      4,
      ListMyAccounts(
        user_id: "00112233-4455-6677-8899-aabbccddeeff",
        game_code: "wildstar",
      ),
    ))
    as "StsConnLib64.MT.dll!0x180004950: POST /GameAccount/ListMyAccounts with <Request><UserId>..</UserId><GameCode>..</GameCode></Request>"
}

pub fn the_request_game_token_request_holds_the_user_id_the_game_code_and_the_alias_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(5),
      command: "RequestGameToken",
      body: "<Request>\n<UserId>00112233-4455-6677-8899-aabbccddeeff</UserId>\n<GameCode>wildstar</GameCode>\n<AccountAlias>jim</AccountAlias>\n</Request>\n",
    ))
    == Ok(Transaction(
      5,
      RequestGameToken(
        user_id: "00112233-4455-6677-8899-aabbccddeeff",
        game_code: "wildstar",
        account_alias: "jim",
      ),
    ))
    as "StsConnLib64.MT.dll!0x180004ac0: POST /Auth/RequestGameToken with UserId, GameCode and AccountAlias"
}

pub fn the_ping_decodes_with_no_sequence_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(
      Request(sequence: None, protocol: "Sts", command: "Ping", body: <<>>),
    )
    == Ok(Ping)
    as "StsConnLib64.MT.dll!0x18002f370: Ping has l:0, no body and no sequence"
}

pub fn the_connect_message_decodes_its_children_and_leaves_the_missing_ones_at_zero_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(
      Request(sequence: None, protocol: "Sts", command: "Connect", body: <<
        "<Connect>\n<ConnType>1281</ConnType>\n<Address>192.168.1.5</Address>\n<Program>11</Program>\n<Build>12</Build>\n<Process>13</Process>\n</Connect>\n":utf8,
      >>),
    )
    == Ok(
      ConnectionOpened(Connect(
        connection_type: 1281,
        connection_product_type: 0,
        connection_app_index: 0,
        connection_deployment: 0,
        connection_epoch: 0,
        address: Some("192.168.1.5"),
        product_type: 0,
        app_index: 0,
        deployment: 0,
        epoch: 0,
        program: 11,
        build: 12,
        process: 13,
        notify_flags: 0,
        version_flags: 0,
      )),
    )
    as "StsConnLib64.MT.dll!0x18002f410: ConnType 1281 for the client, each number only when not 0, Address as text"
}

pub fn a_request_of_no_known_command_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(1),
      command: "Surprise",
      body: "<Request/>\n",
    ))
    == Error(sts_message.UnknownCommand(protocol: "Auth", command: "Surprise"))
    as "StsConnLib64.MT.dll!0x180022cb0: the login uses Auth (LoginStart, KeyData, LoginFinish, RequestGameToken), GameAccount (ListMyAccounts) and Sts (Connect, Ping)"
}

pub fn a_transaction_without_a_sequence_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: None,
      command: "LoginFinish",
      body: "<Request/>\n",
    ))
    == Error(sts_message.MissingSequence("LoginFinish"))
    as "StsConnLib64.MT.dll!0x180023550: a request that expects a reply carries s:<n>; only Connect and Ping have none"
}

pub fn a_body_that_is_not_xml_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(1),
      command: "LoginFinish",
      body: "<Request/>",
    ))
    == Error(sts_message.BodyNotXml("LoginFinish"))
    as "StsConnLib64.MT.dll!0x1800248a0: a body not ending in a line feed has no root element"
}

pub fn a_login_start_without_a_name_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(1),
      command: "LoginStart",
      body: "<Request>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n",
    ))
    == Error(sts_message.MissingChild(command: "LoginStart", child: "LoginName"))
    as "StsConnLib64.MT.dll!0x180006fb0: LoginStart carries LoginName and NetAddress"
}

pub fn key_data_that_is_not_base64_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(request(
      sequence: Some(2),
      command: "KeyData",
      body: "<Request>\n<KeyData>not base64!</KeyData>\n</Request>\n",
    ))
    == Error(sts_message.NotBase64("KeyData"))
    as "StsConnLib64.MT.dll!0x18002be60: KeyData is binary data in base64"
}

pub fn a_connect_number_that_is_not_a_number_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.decode(
      Request(sequence: None, protocol: "Sts", command: "Connect", body: <<
        "<Connect>\n<ConnType>many</ConnType>\n</Connect>\n":utf8,
      >>),
    )
    == Error(sts_message.NotANumber(command: "Connect", child: "ConnType"))
    as "StsConnLib64.MT.dll!0x18002f410: every value but Address is a decimal number"
}

pub fn the_token_reply_is_the_vectors_reply_to_sequence_5_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.encode(sts_message.GameToken(sequence: 5, token: "a&b<c"))
    == <<
      "STS/1.0 200 OK\r\ns:5R\r\nl:45\r\n\r\n<Reply>\n<Token>a&amp;b&lt;c</Token>\n</Reply>\n":utf8,
    >>
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: the final reply to sequence 5 with Token a&b<c"
}

pub fn the_first_key_data_reply_holds_the_vectors_base64_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.encode(sts_message.KeyDataAnswer(
      sequence: 1,
      key_data: vector.server_key_data(),
    ))
    == reply(
      status: "200 OK",
      sequence: 1,
      body: "<Reply>\n<KeyData>"
        <> vector.server_key_data_base64
        <> "</KeyData>\n</Reply>\n",
    )
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: the server's KeyData in base64, in the KeyData child of the reply's root (StsConnLib64.MT.dll!0x18000a350)"
}

pub fn the_login_finish_reply_has_auth_type_0_and_the_user_id_and_name_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.encode(sts_message.LoginFinished(
      sequence: 3,
      user_id: "00112233-4455-6677-8899-aabbccddeeff",
      user_name: "jim",
    ))
    == reply(
      status: "200 OK",
      sequence: 3,
      body: "<Reply>\n<AuthType>0</AuthType>\n<UserId>00112233-4455-6677-8899-aabbccddeeff</UserId>\n<UserName>jim</UserName>\n</Reply>\n",
    )
    as "StsConnLib64.MT.dll!0x1800043d0: the reply's root holds AuthType (0 for a finished login), and the client keeps UserId and UserName"
}

pub fn the_game_accounts_reply_lists_each_account_with_alias_created_and_id_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.encode(
      sts_message.GameAccounts(sequence: 4, accounts: [
        GameAccount(
          alias: "jim",
          created: "2026-01-02T03:04:05Z",
          game_account_id: "7",
        ),
      ]),
    )
    == reply(
      status: "200 OK",
      sequence: 4,
      body: "<Reply>\n<GameAccount>\n<Alias>jim</Alias>\n<Created>2026-01-02T03:04:05Z</Created>\n<GameAccountId>7</GameAccountId>\n</GameAccount>\n</Reply>\n",
    )
    as "StsConnLib64.MT.dll!0x180004950: the root holds one or more GameAccount elements, each with Alias, Created and GameAccountId texts"
}

pub fn a_refusal_is_an_error_element_with_the_code_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_message.encode(sts_message.Refused(sequence: 2, code: 3002))
    == reply(
      status: "400 Error",
      sequence: 2,
      body: "<Error code=\"3002\" server=\"0\" module=\"0\" line=\"0\" text=\"\"/>\n",
    )
    as "StsConnLib64.MT.dll!0x18002de60: an error reply is STS/1.0 400 Error, s:<n>R and an Error element with the attributes code, server, module, line and text"
}

pub fn every_answer_ends_with_a_line_feed_the_client_can_parse_test() -> Nil {
  use <- owned_test.run(5000)
  let answers = [
    sts_message.KeyDataAnswer(sequence: 1, key_data: <<1, 2, 3>>),
    sts_message.LoginFinished(sequence: 1, user_id: "u", user_name: "n"),
    sts_message.GameAccounts(sequence: 1, accounts: []),
    sts_message.GameToken(sequence: 1, token: "t"),
    sts_message.Refused(sequence: 1, code: 1),
  ]
  list.each(answers, fn(answer) {
    let assert Ok(text) = bit_array.to_string(sts_message.encode(answer))
      as "an answer is text"
    assert string.ends_with(text, "\n")
      as "StsConnLib64.MT.dll!0x1800248a0: the client's reader needs the last byte of a body to be a line feed"
    assert string.contains(text, "\r\n\r\n<")
      as "StsConnLib64.MT.dll!0x180023290: the headers end with a blank line and the body follows"
  })
}
