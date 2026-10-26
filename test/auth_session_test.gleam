//// The rule of one auth-server connection. The hello is message 3 with the
//// build and checksum the client checks (fact file opcode.0x3, vector
//// `vector.opcode.0x3.body`, CheckAuthServerVersion 0x140037b70); the client's
//// login request is message 0x592 whose body is `vector.opcode.0x592.body`'s
//// layout with its planted values (build 16042, name Jim, GUIDs 10..1f and
//// 20..2f), inside 0x244 under the base key; the answer is 0x591 and the
//// hand-off 0x3DB (vector `vector.opcode.0x3db.body`: address 127.0.0.1, port
//// 24000, key 01 .. 10, realm Nexus), each inside 0x76 under the base key
//// (opcode.0x76, `vector.opcode.0x7e0.frame` for the wrapper's bytes).

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper, ClientWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/login/account.{Identity}
import genesis_prime/login/auth_session.{
  BadWrapper, End, IdentityMismatch, IssueSessionKey, LogDigestMismatch,
  MalformedLoginRequest, RedeemGameToken, Send, TokenRefused, UnexpectedMessage,
  WrongBuild,
}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted
import genesis_prime/message/login_request.{type LoginRequest, LoginRequest}
import genesis_prime/message/server_hello
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import message_support
import owned_test

fn base_cipher() -> cipher.Cipher {
  let assert Ok(built) = cipher.new(cipher.base_key)
    as "the base key builds a cipher"
  built
}

fn settings() -> auth_session.Settings {
  auth_session.Settings(
    game_server: Endpoint(address: 0x7F000001, port: 24_000),
    realm_name: "Nexus",
    expected_files_digest: None,
  )
}

/// The two GUIDs of the vector: 10 11 .. 1f and 20 21 .. 2f.
fn user_id_bytes() -> BitArray {
  message_support.hex("101112131415161718191a1b1c1d1e1f")
}

fn token_bytes() -> BitArray {
  message_support.hex("202122232425262728292a2b2c2d2e2f")
}

fn identity() -> account.Identity {
  let assert Ok(user_id) = guid.from_wire(user_id_bytes()) as "16 bytes"
  Identity(name: "jim", user_id:)
}

/// The login request of vector.opcode.0x592.body, with the fields the rule
/// reads open to change.
fn request(
  build build: Int,
  name name: String,
  user_id user_id: BitArray,
  token token: BitArray,
  digest digest: Int,
) -> LoginRequest {
  LoginRequest(
    build:,
    files_digest: digest,
    account_name: name,
    field_4: user_id,
    field_5: token,
    field_6: 0x41,
    field_7: 0x42,
    field_8: 0x43,
    field_9: 0x44,
    processor_manufacturer: "a",
    processor_name: "bc",
    processor_description: "",
    processor_family: 0x51,
    processor_level: 0x52,
    processor_revision: 0x53,
    processor_clock_speed: 0x54,
    processor_core_count: 0x55,
    memory_mebibytes: 0x60,
    video_adapter_description: "d",
    video_adapter_vendor_id: 0x71,
    video_adapter_device_id: 0x72,
    video_adapter_subsystem_id: 0x73,
    video_adapter_revision: 0x74,
    video_adapter_memory_mebibytes: 0x75,
    processor_architecture: 0x81,
    windows_version: 0x82,
    service_pack: 0x83,
    os_flags: 0x84,
    realm_data_center_id: 0x99,
  )
}

fn good_request() -> LoginRequest {
  request(
    build: 16_042,
    name: "Jim",
    user_id: user_id_bytes(),
    token: token_bytes(),
    digest: 0x0807060504030201,
  )
}

/// The frame the client sends for a login request: the request's message in a
/// 0x244 wrapper under the base key.
fn sent(request: LoginRequest) -> Frame {
  let assert Ok(body) = login_request.encode(request) as "the request encodes"
  wrapped(Frame(0x0592, body))
}

fn wrapped(inner: Frame) -> Frame {
  let assert Ok(bytes) =
    encrypted_frame.wrap(ClientWrapper, inner, base_cipher())
    as "the frame wraps"
  let assert Ok(#([outer], <<>>)) = frame.decode(bytes)
    as "a wrapper is one frame"
  outer
}

fn started() -> auth_session.Session {
  auth_session.start(settings()).0
}

/// The session after a good login request, waiting for the token.
fn waiting_for_the_token() -> auth_session.Session {
  auth_session.receive(started(), sent(good_request())).0
}

/// The bytes of each frame the effects send, in order.
fn sends(effects: List(auth_session.Effect)) -> List(BitArray) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(bytes) -> Ok(bytes)
      RedeemGameToken(_)
      | IssueSessionKey(_)
      | LogDigestMismatch(..)
      | End(_) -> Error(Nil)
    }
  })
}

/// What the server sent, read back as the client reads it: each `Send`'s
/// frame, unwrapped when it is a 0x76 wrapper.
fn frames_sent(effects: List(auth_session.Effect)) -> List(Frame) {
  list.map(sends(effects), fn(bytes) {
    let assert Ok(#([outer], <<>>)) = frame.decode(bytes)
      as "a send is one frame"
    case outer.message_id {
      0x0076 -> {
        let assert Ok(inner) = encrypted_frame.unwrap(outer, base_cipher())
          as "the client reads a 0x76 wrapper under the base key"
        inner
      }
      _ -> outer
    }
  })
}

fn issues_a_key(effects: List(auth_session.Effect)) -> Bool {
  list.any(effects, fn(effect) {
    case effect {
      IssueSessionKey(_) -> True
      Send(_) | RedeemGameToken(_) | LogDigestMismatch(..) | End(_) -> False
    }
  })
}

pub fn the_build_and_the_checksum_are_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert auth_session.build == 16_042
    as "CheckAuthServerVersion 0x140037b70: the client's version is 16042"
  assert auth_session.message_table_checksum == 0x097998A0
    as "CheckAuthServerVersion 0x140037b70: the checksum is 0x097998A0"
}

pub fn a_new_connection_gets_the_hello_with_the_build_and_the_checksum_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = auth_session.start(settings())
  let assert [Send(bytes)] = effects
    as "the server starts with one send, the hello"
  let assert Ok(#([hello], <<>>)) = frame.decode(bytes)
    as "the hello is one frame, bare: the only message the client accepts unwrapped from the auth server"
  assert hello.message_id == 0x0003 as "opcode.0x3: the hello is message 3"
  assert bit_array.byte_size(hello.body) == 47
    as "opcode.0x3: 373 bits, padded to 47 bytes"
  let assert Ok(<<build:bytes-size(4), _:bytes>>) = Ok(hello.body)
    as "the body has a build"
  assert build == <<0xAA, 0x3E, 0x00, 0x00>>
    as "vector.opcode.0x3.body: the build 16042 is the first bytes aa 3e 00 00"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the client's reader takes the body back"
  assert decoded.build == 16_042
    as "CheckAuthServerVersion 0x140037b70: word 0 is the build"
  assert decoded.message_table_checksum == 0x097998A0
    as "CheckAuthServerVersion 0x140037b70: the checksum is 0x97998a0"
}

pub fn a_good_login_request_asks_for_its_token_to_be_redeemed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = auth_session.receive(started(), sent(good_request()))
  assert effects == [RedeemGameToken(token_bytes())]
    as "opcode.0x592: the second GUID is the STS login's game token (HandleRequestGameTokenResult 0x1400b3a50 keeps the text it is parsed from)"
}

pub fn a_file_digest_that_is_not_the_expected_one_is_logged_and_the_login_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    auth_session.start(
      auth_session.Settings(
        ..settings(),
        expected_files_digest: Some(0xD061ADE9D704A68F),
      ),
    )
  let #(_, effects) = auth_session.receive(session, sent(good_request()))
  assert effects
    == [
      LogDigestMismatch(
        received: 0x0807060504030201,
        expected: 0xD061ADE9D704A68F,
      ),
      RedeemGameToken(token_bytes()),
    ]
    as "the decision on the login issue: a file-digest fold that does not match is logged, not refused (FoldClientFileDigests 0x140012780 gives 0xD061ADE9D704A68F for this install)"
}

pub fn a_file_digest_that_is_the_expected_one_is_not_logged_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    auth_session.start(
      auth_session.Settings(
        ..settings(),
        expected_files_digest: Some(0x0807060504030201),
      ),
    )
  let #(_, effects) = auth_session.receive(session, sent(good_request()))
  assert effects == [RedeemGameToken(token_bytes())]
    as "FoldClientFileDigests 0x140012780: a match needs no log"
}

pub fn a_token_that_belongs_to_the_identity_asks_for_a_session_key_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.token_redeemed(waiting_for_the_token(), Ok(identity()))
  assert effects == [IssueSessionKey(identity())]
    as "opcode.0x3db: the hand-off carries a fresh 16-byte session key, which the game server checks in 0x58F"
}

pub fn the_session_key_is_answered_with_0x591_and_then_the_hand_off_each_in_0x76_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    auth_session.token_redeemed(waiting_for_the_token(), Ok(identity()))
  let key = message_support.session_key()
  let #(_, effects) = auth_session.session_key_issued(session, key)
  let frames = frames_sent(effects)
  assert list.map(frames, fn(sent_frame) { sent_frame.message_id })
    == [0x0591, 0x03DB]
    as "opcode.0x591: login accepted, then the hand-off (opcode.0x3db: accepted only after 0x591), each inside 0x76 (opcode.0x76)"
  let assert [accepted, handoff] = frames as "two frames"
  assert list.all(sends(effects), fn(bytes) {
    let assert Ok(#([outer], <<>>)) = frame.decode(bytes) as "one frame"
    outer.message_id == encrypted_frame.message_id(AuthWrapper)
  })
    as "opcode.0x76: the client accepts only the hello bare, so every other message is inside 0x76"
  assert login_accepted.decode(accepted.body)
    == Ok(login_accepted.LoginAccepted(0))
    as "opcode.0x591: one 32-bit value, of which the client keeps bit 0; its meaning is unread, so the server sends 0"
  assert game_server_handoff.decode(handoff.body)
    == Ok(game_server_handoff.GameServerHandoff(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      session_key: key,
      field_3: 0,
      realm_name: "Nexus",
      field_5: 0,
      field_6: 0,
      field_7: 0,
    ))
    as "vector.opcode.0x3db.body: the address as a number (127.0.0.1 is 0x7F000001), the port, the 16 key bytes in order and the realm's name; the fields whose meaning is unread are 0"
}

pub fn a_build_other_than_16042_ends_the_connection_and_spends_no_token_test() -> Nil {
  use <- owned_test.run(5000)
  let wrong = LoginRequest(..good_request(), build: 16_043)
  let #(_, effects) = auth_session.receive(started(), sent(wrong))
  assert effects == [End(WrongBuild(16_043))]
    as "CheckAuthServerVersion 0x140037b70: the client's build is 16042; a request of another build is not this client's and never reaches the token"
  assert !issues_a_key(effects) as "no session key is issued"
}

pub fn a_login_request_that_ends_inside_a_field_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) = login_request.encode(good_request())
    as "the request encodes"
  let assert Ok(short) = bit_array.slice(body, 0, 100) as "a prefix of the body"
  let #(_, effects) =
    auth_session.receive(started(), wrapped(Frame(0x0592, short)))
  assert effects == [End(MalformedLoginRequest(bit_stream.EndOfData))]
    as "vector.opcode.0x3db.body and CLAUDE.md: bytes that end inside a field fail to decode, and a decode failure ends the connection"
  assert !issues_a_key(effects) as "no session key is issued"
}

pub fn a_login_request_with_bytes_after_its_last_field_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) = login_request.encode(good_request())
    as "the request encodes"
  let #(_, effects) =
    auth_session.receive(started(), wrapped(Frame(0x0592, <<body:bits, 1, 2>>)))
  assert effects == [End(MalformedLoginRequest(bit_stream.TrailingBytes(2)))]
    as "CLAUDE.md: bad input is rejected at the connection; the body of 0x592 is 1168 bits for the vector's values and nothing follows"
}

pub fn a_token_that_is_unknown_or_expired_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.token_redeemed(waiting_for_the_token(), Error(Nil))
  assert effects == [End(TokenRefused)]
    as "the decision on the login issue: the second GUID is the game token, the real link between STS and auth, and an unknown or expired one is refused"
  assert !issues_a_key(effects) as "no session key is issued"
}

pub fn a_token_issued_to_another_identity_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(other_id) =
    guid.from_wire(message_support.hex("00112233445566778899aabbccddeeff"))
    as "16 bytes"
  let #(_, effects) =
    auth_session.token_redeemed(
      waiting_for_the_token(),
      Ok(Identity(name: "jim", user_id: other_id)),
    )
  assert effects == [End(IdentityMismatch)]
    as "the decision on the login issue: the first GUID is the UserId from LoginFinish, so it must be the token's account"
  assert !issues_a_key(effects) as "no session key is issued"
}

pub fn a_token_issued_to_another_name_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.token_redeemed(
      waiting_for_the_token(),
      Ok(Identity(..identity(), name: "someone")),
    )
  assert effects == [End(IdentityMismatch)]
    as "the decision on the login issue: the account name is the STS login's, compared in lower case"
  assert !issues_a_key(effects) as "no session key is issued"
}

pub fn the_account_name_is_compared_in_lower_case_test() -> Nil {
  use <- owned_test.run(5000)
  let shouting = LoginRequest(..good_request(), account_name: "JIM")
  let #(session, _) = auth_session.receive(started(), sent(shouting))
  let #(_, effects) = auth_session.token_redeemed(session, Ok(identity()))
  assert effects == [IssueSessionKey(identity())]
    as "the decision on the login issue: the account name is compared case-insensitively; the client lower-cases the name for the STS login (StartStsLogin 0x1400b4500) but sends the typed name in 0x592 (opcode.0x592)"
}

pub fn a_frame_that_is_not_a_0x244_wrapper_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) = login_request.encode(good_request())
    as "the request encodes"
  let #(_, effects) = auth_session.receive(started(), Frame(0x0592, body))
  assert effects == [End(BadWrapper)]
    as "opcode.0x244: every message the client sends travels in 0x244, and the cipher is never skipped"
  let #(_, effects) =
    auth_session.receive(started(), Frame(0x0076, <<1, 2, 3, 4, 5>>))
  assert effects == [End(BadWrapper)]
    as "opcode.0x76 is the server's wrapper, which the client never sends"
}

pub fn a_wrapper_whose_inner_frame_disagrees_with_its_length_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.receive(started(), Frame(0x0244, <<99, 0, 0, 0, 1, 2>>))
  assert effects == [End(BadWrapper)]
    as "opcode.0x244: the inner length is in the clear and counts the whole inner frame"
}

pub fn a_message_other_than_the_login_request_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.receive(started(), wrapped(Frame(0x07E0, <<>>)))
  assert effects == [End(UnexpectedMessage(0x07E0))]
    as "opcode.0x3: from the auth server the client answers the hello with 0x592 and sends nothing else"
}

pub fn a_second_login_request_ends_the_connection_and_spends_no_second_token_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    auth_session.receive(waiting_for_the_token(), sent(good_request()))
  assert effects == [End(UnexpectedMessage(0x0592))]
    as "SendAuthLoginRequest 0x14003a620: the client sends the login request once"
}

pub fn a_client_that_was_handed_on_sends_nothing_more_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    auth_session.token_redeemed(waiting_for_the_token(), Ok(identity()))
  let #(session, _) =
    auth_session.session_key_issued(session, message_support.session_key())
  let #(_, effects) = auth_session.receive(session, sent(good_request()))
  assert effects == [End(UnexpectedMessage(0x0592))]
    as "opcode.0x3db: the client opens the game connection after the hand-off and sends nothing more on this one that the server reads"
}

pub fn the_reasons_say_what_ended_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  assert auth_session.describe(WrongBuild(16_043))
    != auth_session.describe(TokenRefused)
    as "each reason is its own sentence"
}
