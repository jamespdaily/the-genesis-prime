//// The auth login's rule (`genesis_prime/login/auth_connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's login request built by `scripted_client`. Expected values come
//// from these places.
//// - The hello: build 16042 and message table checksum 0x097998A0, which the
////   client checks (CheckAuthServerVersion 0x140037b70), the realm's id, and
////   0 in every field the client never reads (opcode.0x3).
//// - 0x592 and its UserId, game token and build (opcode.0x592); 0x591, whose
////   one value is not disconnected-for-lag when 0 (opcode.0x591); 0x3db, whose
////   fields are the game server's address, the session key, the account id,
////   the realm's name, flags, PvP type (0 is PvE) and note text id (0 is no
////   note) (opcode.0x3db).
//// - 0x63d reasons: 16 "Invalid Login Token", 19 "Client version does not
////   match the game server version", 12 "NCSoft login service finish
////   timeout" (opcode.0x63d).
//// - The ping and its pong, bare, with the same number (opcode.0x0 and
////   opcode.0x1: 07 00 00 00 00 00 n and 07 00 00 00 01 00 n).
//// - The random bytes: block n = HMAC-SHA256(key: seed, data: n as 64 bits
////   big-endian); the session key is the first 16 bytes of block 0.
//// - The rule's doc comment, as approved on the login card.

import genesis_prime/client_connection.{
  type Answer, type Request, AskHandOff, FromHandOff,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/hand_off.{
  AlreadyHeld, GameToken, Holder, Kept, NoHolder, Put, SessionKey, Take, Taken,
}
import genesis_prime/login/auth_connection.{Settings}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_refused
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/step.{
  type Event, type Outcome, type Step, ConnectionId, EndedBeforeAnswer,
  LogWarning, NoAnswerInTime, NotRunning, StoppedWaiting,
}
import genesis_prime/store.{AccountId}
import gleam/list
import gleam/option.{type Option, None, Some}
import login_client
import login_rule_support as support
import login_support
import owned_test
import scripted_client.{StsLogin}

fn settings(planted planted: Option(Frame)) -> auth_connection.Settings {
  Settings(..login_support.auth_settings(), planted:)
}

fn holder() -> hand_off.Holder {
  Holder(
    account_id: AccountId(7),
    login_name: "jim",
    game_account_id: support.guid_of(1),
  )
}

fn token() -> guid.Guid {
  support.guid_of(17)
}

fn feed(
  state: auth_connection.State,
  event: Event(Nil, Answer),
) -> #(auth_connection.State, Step(Nil, Request)) {
  auth_connection.step(state, support.input(event))
}

/// A connection the server has accepted with this seed; the step is the
/// hello.
fn accepted(
  seed seed: BitArray,
  planted planted: Option(Frame),
) -> #(auth_connection.State, Step(Nil, Request)) {
  feed(
    auth_connection.new(settings(planted:)),
    step.Socket(step.Accepted(ConnectionId(1), support.peer, seed)),
  )
}

fn connected(seed seed: BitArray) -> auth_connection.State {
  accepted(seed:, planted: None).0
}

/// The bytes of the client's login request for a UserId and a build, in its
/// 0x244 wrapper under the base key.
fn login_request(user_id user_id: guid.Guid, build build: Int) -> BitArray {
  let outer =
    scripted_client.login_request_frame(
      login: StsLogin(
        user_id: guid.to_text(user_id),
        token: guid.to_text(token()),
        name: "jim",
      ),
      build:,
    )
  let assert Ok(bytes) = frame.encode(outer.message_id, outer.body)
    as "the request frame encodes"
  bytes
}

fn read(
  state: auth_connection.State,
  bytes: BitArray,
) -> #(auth_connection.State, Step(Nil, Request)) {
  feed(state, step.Socket(step.Read(bytes)))
}

fn answer(
  state state: auth_connection.State,
  taken taken: Step(Nil, Request),
  outcome outcome: Outcome(Answer),
) -> #(auth_connection.State, Step(Nil, Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  feed(state, step.Answered(ask: ask.ask, outcome:))
}

/// Every frame the step writes, as the client reads it: each must be in a
/// 0x76 wrapper, which is opened under the base key.
fn heard(taken: Step(Nil, Request)) -> List(Frame) {
  list.map(support.written_frames(taken), login_client.in_the_auth_wrapper)
}

/// The one refusal the step writes, whole, with the connection ended.
fn refusal(taken: Step(Nil, Request)) -> login_refused.LoginRefused {
  let assert [Frame(message_id: 0x063D, body:)] = heard(taken)
    as "one 0x63d in its wrapper"
  let assert Ok(refused) = login_refused.decode(body) as "0x63d decodes"
  assert support.stops(taken) as "a refusal ends the connection"
  refused
}

/// The connection after a login request for a UserId and a build, with its
/// Take ask.
fn asking_as(
  seed seed: BitArray,
  user_id user_id: guid.Guid,
  build build: Int,
) -> #(auth_connection.State, Step(Nil, Request)) {
  read(connected(seed:), login_request(user_id:, build:))
}

/// The connection after a login request for the holder's UserId and the
/// build the client is, with its Take ask.
fn asking(seed seed: BitArray) -> #(auth_connection.State, Step(Nil, Request)) {
  asking_as(seed:, user_id: holder().game_account_id, build: 16_042)
}

/// The connection after the hand-off gave the holder for the token, with the
/// ask to keep the session key.
fn token_taken(
  seed seed: BitArray,
) -> #(auth_connection.State, Step(Nil, Request)) {
  let #(state, taken) = asking(seed:)
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
  )
}

// ---- the tests, in the order of the card's list ----

pub fn on_connect_the_server_sends_the_hello_with_build_16042_the_checksum_and_the_realm_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = accepted(seed: support.seed(first: 1), planted: None)
  let assert [Frame(message_id: 0x0003, body:)] = support.written_frames(taken)
    as "one bare frame, message 3, and nothing else"
  let assert [written] = support.writes(taken)
  let assert Ok(#([bare], <<>>)) = frame.decode(written)
  assert bare.message_id == 0x0003 as "the hello travels bare, not in 0x76"
  let assert Ok(hello) = server_hello.decode(body) as "opcode.0x3: the hello"
  assert hello
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
    as "CheckAuthServerVersion 0x140037b70: build 16042 and checksum 0x097998A0; the realm's id; every field the client never reads is 0 (opcode.0x3)"
  // A planted frame follows the hello in the wrapper, and only when set.
  let planted = Frame(message_id: 0x0914, body: <<>>)
  let #(_, taken) =
    accepted(seed: support.seed(first: 1), planted: Some(planted))
  let assert [first, second] = support.written_frames(taken)
    as "the hello, then the planted frame"
  assert first.message_id == 0x0003
  assert login_client.in_the_auth_wrapper(second) == planted
    as "the planted frame arrives in the 0x76 wrapper, as the client reads it"
  let assert [_, wrapped] = support.writes(taken)
  let assert Ok(#([outer], <<>>)) = frame.decode(wrapped)
  assert outer.message_id == 0x0076 as "it travels in 0x76"
}

pub fn a_login_request_with_a_live_game_token_gets_0x591_then_0x3db_with_a_session_key_the_hand_off_keeps_test() -> Nil {
  use <- owned_test.run(10_000)
  let seed = support.seed(first: 1)
  let #(state, taken) = asking(seed:)
  let assert Some(ask) = support.asked(taken) as "the token is taken"
  assert ask.request == AskHandOff(Take(GameToken(token: token())))
    as "the game token the client showed"
  assert ask.deadline_ms == support.now_ms + 5000
  assert support.writes(taken) == [] as "nothing is written before the answer"
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  let assert Ok(session_key) =
    guid.from_wire(support.sixteen(seed:, counter: 0))
  let assert Some(ask) = support.asked(taken) as "the session key is kept"
  assert ask.request
    == AskHandOff(Put(
      key: SessionKey(key: session_key),
      holder: holder(),
      lifetime_ms: 60_000,
    ))
    as "the seed's first draw, kept for the account for the settings' lifetime"
  assert support.writes(taken) == []
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  let assert [accepted, handoff] = heard(taken) as "0x591, then 0x3db"
  assert accepted.message_id == 0x0591 && handoff.message_id == 0x03DB
  assert login_accepted.decode(accepted.body)
    == Ok(LoginAccepted(disconnected_for_lag: 0))
    as "opcode.0x591: not disconnected for lag"
  assert game_server_handoff.decode(handoff.body)
    == Ok(GameServerHandoff(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      session_key: guid.to_wire(session_key),
      account_id: 7,
      realm_name: "Nexus",
      realm_flags: 0,
      realm_pvp_type: 0,
      realm_note_text_id: 0,
    ))
    as "opcode.0x3db: the game server's address, the session key, the account's id, the realm's name, flags 0, PvE and no note"
  assert !support.stops(taken) as "the client goes on to the game server"
}

pub fn a_token_never_kept_already_taken_or_expired_gets_0x63d_reason_16_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = asking(seed: support.seed(first: 1))
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(NoHolder)))
  let refused = refusal(taken)
  assert refused.reason == 16 && refused.value == 0
    as "opcode.0x63d: 16 is 'Invalid Login Token'"
  assert support.asked(taken) == None
    as "no session key is made for a refused login"
}

pub fn a_user_id_other_than_the_tokens_account_gets_0x63d_reason_16_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    asking_as(
      seed: support.seed(first: 1),
      user_id: support.guid_of(33),
      build: 16_042,
    )
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert refusal(taken).reason == 16
    as "the UserId the client showed is not the token's account: opcode.0x63d 16"
  assert support.asked(taken) == None as "no session key is made"
}

pub fn a_build_other_than_16042_gets_0x63d_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    asking_as(
      seed: support.seed(first: 1),
      user_id: holder().game_account_id,
      build: 16_043,
    )
  assert refusal(taken).reason == 19
    as "opcode.0x63d: 19 is 'Client version does not match the game server version'"
  assert support.asked(taken) == None
    as "the token is not taken for a client of another build"
}

pub fn a_hand_off_that_does_not_answer_gets_0x63d_reason_12_and_a_warning_log_test() -> Nil {
  use <- owned_test.run(10_000)
  let outcomes = [
    NoAnswerInTime,
    NotRunning,
    EndedBeforeAnswer,
    StoppedWaiting,
  ]
  list.each(outcomes, fn(outcome) {
    // At the Take.
    let #(state, taken) = asking(seed: support.seed(first: 1))
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert refusal(taken).reason == 12
      as "opcode.0x63d: 12 is 'NCSoft login service finish timeout'"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "the failure is the server's: a warning"
    assert line.about.connection == Some(ConnectionId(1))
      && line.about.peer == Some(support.peer)
    // At the Put of the session key.
    let #(state, taken) = token_taken(seed: support.seed(first: 1))
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert refusal(taken).reason == 12
    assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
  })
  // A session key that is already held is the server's failure too.
  let #(state, taken) = token_taken(seed: support.seed(first: 1))
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(AlreadyHeld)))
  assert refusal(taken).reason == 12
}

pub fn a_ping_gets_its_pong_test() -> Nil {
  use <- owned_test.run(10_000)
  let ping = fn(number: Int) {
    let assert Ok(bytes) = frame.encode(0x0000, <<number>>)
    bytes
  }
  let state = connected(seed: support.seed(first: 1))
  let #(state, taken) = read(state, ping(9))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 9>>]
    as "opcode.0x1: the pong carries the ping's number, bare"
  assert !support.stops(taken)
  // After the hand-off too.
  let #(state, taken) =
    read(state, login_request(user_id: holder().game_account_id, build: 16_042))
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  let #(state, _taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  let #(_, taken) = read(state, ping(3))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 3>>]
    as "the client's pings go on while it moves to the game server"
}

pub fn the_session_key_comes_from_the_connections_seed_only_test() -> Nil {
  use <- owned_test.run(10_000)
  let session_key_for = fn(seed) {
    let #(_, taken) = token_taken(seed:)
    let assert Some(ask) = support.asked(taken)
    let assert AskHandOff(Put(key: SessionKey(key:), ..)) = ask.request
    key
  }
  let first = session_key_for(support.seed(first: 1))
  assert first == session_key_for(support.seed(first: 1))
    as "the same seed gives the same session key"
  assert first != session_key_for(support.seed(first: 40))
    as "two seeds give different session keys"
}
