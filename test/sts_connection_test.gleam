//// The STS login's rule (`genesis_prime/login/sts_connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's side played by `scripted_client` and the library's RC4. Expected
//// values come from these places.
//// - The library's vector `vector.StsConnLib64.MT.dll!0x18002d4e0.srp`
////   (`login_vectors`): account `jim`, password `secret`, its salt and
////   verifier, and the SRP formulas B = (k v + g^b) mod N, which the test
////   writes out itself and checks against the vector's own B.
//// - The random bytes: block n = HMAC-SHA256(key: seed, data: n as 64 bits
////   big-endian); the SRP secret b is the first draw (block 0, read
////   little-endian) and the game token the second (the first 16 bytes of
////   block 1).
//// - The errors: unknown name and wrong M1 are code 3002, the client's
////   "Invalid account name or password" (0x1400b2f20,
////   StsConnLib64.MT.dll!0x180003d30); code 42 at LoginStart is "NCSoft login
////   service start timeout" (0x1400b2f20) and at LoginFinish "NCSoft login
////   service finish timeout" (0x1400b3070). An error reply is a status of
////   400 or more and `<Error code="N" .../>` (0x18002de60).
//// - RC4: plain up to the end of the M2 reply; from the next byte each way,
////   one state per direction under the 64-byte K, none dropped; the server
////   sends nothing between M2 and LoginFinish (StsConnLib64.MT.dll!0x18000a350).
//// - ListMyAccounts: exactly one GameAccount whose Alias the client sends
////   back (0x180004950, 0x1400b36c0); Ping is one-way and has no answer
////   (0x18002f370).
//// - The rule's doc comment, as approved on the login card: the asks, the
////   token kept at LoginFinish, the refusals and the out-of-order cases.

import connection_rule_support as support
import genesis_prime/client_connection.{
  type Answer, type Request, AskHandOff, AskStore, FromHandOff, FromStore,
}
import genesis_prime/hand_off.{AlreadyHeld, GameToken, Holder, Kept, Put}
import genesis_prime/login/guid
import genesis_prime/login/rc4
import genesis_prime/login/srp
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_xml
import genesis_prime/step.{
  type Event, type Outcome, type Step, ConnectionId, Effects, EndedBeforeAnswer,
  LogError, LogWarning, NoAnswerInTime, NotRunning, StoppedWaiting,
}
import genesis_prime/store.{
  AccountFound, AccountId, FindAccount, ForLogin, Login, NoSuchAccount,
  Unavailable,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import login_client
import login_support
import login_vectors as vector
import owned_test
import scripted_client.{type Exchange, type Reply}
import seeded

/// The client's side of one connection beside the rule's state: its RC4
/// streams once the proof has passed, and the next sequence number.
type Session {
  Session(
    state: sts_connection.State,
    sending: Option(rc4.Stream),
    receiving: Option(rc4.Stream),
    sequence: Int,
  )
}

fn feed(
  session: Session,
  event: Event(Nil, Answer),
) -> #(Session, Step(Nil, Request)) {
  let #(state, taken) = sts_connection.step(session.state, support.input(event))
  #(Session(..session, state:), taken)
}

/// A connection the server has accepted with this seed; the server writes
/// nothing first.
fn accepted(seed seed: BitArray) -> Session {
  let #(session, taken) =
    feed(
      Session(
        state: sts_connection.new(login_support.sts_settings()),
        sending: None,
        receiving: None,
        sequence: 1,
      ),
      step.Socket(step.Accepted(ConnectionId(1), support.peer, seed)),
    )
  assert support.writes(taken) == [] as "the STS server waits for the client"
  session
}

/// The bytes the client sends, through its RC4 once the proof has passed.
fn send_bytes(
  session: Session,
  plain: BitArray,
) -> #(Session, Step(Nil, Request)) {
  let #(sending, wire) =
    login_client.crypt_when_on(stream: session.sending, bytes: plain)
  feed(Session(..session, sending:), step.Socket(step.Read(wire)))
}

/// A request with the next sequence number.
fn request(
  session session: Session,
  protocol protocol: String,
  command command: String,
  body body: sts_xml.Node,
) -> #(Session, Step(Nil, Request)) {
  send_bytes(
    Session(..session, sequence: session.sequence + 1),
    scripted_client.request(
      sequence: Some(session.sequence),
      protocol:,
      command:,
      body: sts_xml.render(body),
    ),
  )
}

/// The one-way messages: no sequence.
fn one_way(
  session session: Session,
  command command: String,
  body body: String,
  protocol protocol: String,
) -> #(Session, Step(Nil, Request)) {
  send_bytes(
    session,
    scripted_client.request(sequence: None, protocol:, command:, body:),
  )
}

/// The connection after the client's Connect.
fn connected(seed seed: BitArray) -> Session {
  let #(session, taken) =
    one_way(
      session: accepted(seed:),
      protocol: "Sts",
      command: "Connect",
      body: sts_xml.render(
        sts_xml.Parent("Connect", [sts_xml.Text("ConnType", "1281")]),
      ),
    )
  assert support.effects_of(taken) == []
    as "Connect is one-way and gets no answer"
  session
}

fn login_start(session: Session) -> #(Session, Step(Nil, Request)) {
  request(
    session:,
    protocol: "Auth",
    command: "LoginStart",
    body: sts_xml.Parent("Request", [
      sts_xml.Text("LoginName", vector.name),
      sts_xml.Text("NetAddress", "192.168.1.5"),
    ]),
  )
}

fn answer(
  session session: Session,
  taken taken: Step(Nil, Request),
  outcome outcome: Outcome(Answer),
) -> #(Session, Step(Nil, Request)) {
  let assert Some(ask) = support.asked(taken) as "the taken ends in an ask"
  feed(session, step.Answered(ask: ask.ask, outcome:))
}

/// The bytes the taken writes, which must be one write, deciphered with the
/// client's receiving stream when it is on.
fn hear(session: Session, taken: Step(Nil, Request)) -> #(Session, BitArray) {
  let assert [written] = support.writes(taken)
    as "the taken writes exactly one reply"
  let #(receiving, plain) =
    login_client.crypt_when_on(stream: session.receiving, bytes: written)
  #(Session(..session, receiving:), plain)
}

fn reply_of(bytes: BitArray) -> Reply {
  let assert Ok(reply) = scripted_client.read_reply(bytes)
    as "the bytes are one whole STS reply"
  reply
}

fn assert_error_reply(
  bytes bytes: BitArray,
  sequence sequence: Int,
  code code: Int,
) -> Nil {
  let reply = reply_of(bytes)
  assert reply.status >= 400
    as "0x18002de60: an error reply has a status of 400 or more"
  assert reply.sequence == sequence
    as "the error answers the request's sequence"
  assert reply.root.name == "Error" as "the body is an Error element"
  let assert Ok(text) = bit_array.to_string(bytes)
  assert string.contains(text, "<Error code=\"" <> int.to_string(code) <> "\"")
    as "the Error element names the code"
  Nil
}

fn client_secret() -> BitArray {
  seeded.bytes(state: 99, count: 32).0
}

/// The client's side of the exchange after LoginStart is answered with the
/// account of the vector, for a password the client chooses.
fn key_data_exchange(
  session: Session,
  password password: String,
) -> #(Session, Exchange) {
  let #(session, taken) = login_start(session)
  let #(session, taken) =
    answer(
      session:,
      taken:,
      outcome: step.Answer(FromStore(ForLogin(AccountFound(support.jim())))),
    )
  let #(session, bytes) = hear(session, taken)
  let assert Ok(server_key_data) =
    bit_array.base64_decode(login_client.child(
      reply: reply_of(bytes),
      name: "KeyData",
    ))
    as "KeyData is base64"
  let assert Ok(exchange) =
    scripted_client.exchange(
      name: vector.name,
      password:,
      secret: client_secret(),
      server_key_data:,
    )
    as "the server's key data is the salt and B"
  #(session, exchange)
}

fn key_data_request(
  session: Session,
  exchange: Exchange,
) -> #(Session, Step(Nil, Request)) {
  request(
    session:,
    protocol: "Auth",
    command: "KeyData",
    body: sts_xml.Parent("Request", [
      sts_xml.Text("KeyData", bit_array.base64_encode(exchange.key_data, True)),
    ]),
  )
}

/// The connection after the right proof and M2: RC4 under K on in both
/// directions of the client's side too.
fn proven(seed seed: BitArray) -> #(Session, Exchange) {
  let #(session, exchange, _taken, _m2) = proven_with_m2(seed:)
  #(session, exchange)
}

/// The same, with the step of the KeyData request and the bytes of M2, which
/// the server writes in plain text, before RC4 is on.
fn proven_with_m2(
  seed seed: BitArray,
) -> #(Session, Exchange, Step(Nil, Request), BitArray) {
  let #(session, exchange) =
    key_data_exchange(connected(seed:), password: vector.password)
  let #(session, taken) = key_data_request(session, exchange)
  let #(session, m2) = hear(session, taken)
  let assert Ok(stream) = rc4.start(exchange.session_key)
  #(
    Session(..session, sending: Some(stream), receiving: Some(stream)),
    exchange,
    taken,
    m2,
  )
}

fn login_finish(session: Session) -> #(Session, Step(Nil, Request)) {
  request(
    session:,
    protocol: "Auth",
    command: "LoginFinish",
    body: sts_xml.Empty("Request"),
  )
}

/// The game token the rule asks the hand-off to keep at LoginFinish.
fn token_asked(taken: Step(Nil, Request)) -> guid.Guid {
  let assert Some(ask) = support.asked(taken) as "LoginFinish asks the hand-off"
  let assert AskHandOff(Put(key: GameToken(token:), ..)) = ask.request
    as "the ask keeps a game token"
  token
}

/// The connection after LoginFinish is answered: the game token asked for and
/// the reply to LoginFinish.
fn finished(seed seed: BitArray) -> #(Session, guid.Guid, Reply) {
  let #(session, _exchange) = proven(seed:)
  let #(session, taken) = login_finish(session)
  let token = token_asked(taken)
  let #(session, taken) =
    answer(session:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  let #(session, bytes) = hear(session, taken)
  #(session, token, reply_of(bytes))
}

fn list_my_accounts(session: Session) -> #(Session, Step(Nil, Request)) {
  request(
    session:,
    protocol: "GameAccount",
    command: "ListMyAccounts",
    body: sts_xml.Parent("Request", [
      sts_xml.Text("UserId", guid.to_text(support.jim().game_account_id)),
      sts_xml.Text("GameCode", "wildstar"),
    ]),
  )
}

fn request_game_token(session: Session) -> #(Session, Step(Nil, Request)) {
  request(
    session:,
    protocol: "Auth",
    command: "RequestGameToken",
    body: sts_xml.Parent("Request", [
      sts_xml.Text("UserId", guid.to_text(support.jim().game_account_id)),
      sts_xml.Text("GameCode", "wildstar"),
      sts_xml.Text("AccountAlias", vector.name),
    ]),
  )
}

// ---- SRP, written out here from the formula ----

@external(erlang, "genesis_prime_login_ffi", "mod_pow")
fn mod_pow(base: Int, exponent: Int, modulus: Int) -> Int

fn little(bytes: BitArray) -> Int {
  let bits = bit_array.bit_size(bytes)
  let assert <<number:size(bits)-little>> = bytes as "whole bytes"
  number
}

/// The server's first KeyData for the vector's account and a secret b: the
/// salt and B = (k v + 2^b) mod N, each with its 32-bit length, the numbers as
/// the library writes them.
fn expected_key_data(secret: BitArray) -> BitArray {
  let prime = srp.group_prime()
  let server_value =
    {
      srp.multiplier()
      * little(vector.verifier())
      + mod_pow(2, little(secret), prime)
    }
    % prime
  let salt = vector.salt()
  let bytes = srp.number_bytes(server_value)
  <<
    { bit_array.byte_size(salt) }:size(32)-little,
    salt:bits,
    { bit_array.byte_size(bytes) }:size(32)-little,
    bytes:bits,
  >>
}

// ---- the tests, in the order of the card's list ----

pub fn login_start_for_a_stored_account_answers_key_data_with_the_accounts_salt_and_b_test() -> Nil {
  use <- owned_test.run(10_000)
  assert expected_key_data(vector.server_secret()) == vector.server_key_data()
    as "the formula the test writes out gives the library's own B for the vector's b"
  let seed = support.seed(first: 1)
  let #(session, taken) = login_start(connected(seed:))
  let assert Some(ask) = support.asked(taken) as "LoginStart asks the store"
  assert ask.request == AskStore(Login(FindAccount(vector.name)))
    as "the store is asked for the login name the client sent"
  assert ask.deadline_ms == support.now_ms + 5000
    as "the ask's deadline is the settings' ask deadline from this input's time"
  assert support.writes(taken) == [] as "nothing is written before the answer"
  let #(_, taken) =
    answer(
      session:,
      taken:,
      outcome: step.Answer(FromStore(ForLogin(AccountFound(support.jim())))),
    )
  let assert [written] = support.writes(taken) as "one KeyData reply"
  let reply = reply_of(written)
  assert reply.status == 200 && reply.sequence == 1
    as "a success that answers LoginStart's sequence"
  let assert Ok(key_data) =
    bit_array.base64_decode(login_client.child(reply:, name: "KeyData"))
  assert key_data == expected_key_data(support.block(seed:, counter: 0))
    as "the account's salt and B from the first block of the seed"
}

pub fn login_start_for_an_unknown_name_answers_error_3002_and_nothing_is_ciphered_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(session, taken) = login_start(connected(seed: support.seed(first: 1)))
  let #(session, taken) =
    answer(
      session:,
      taken:,
      outcome: step.Answer(FromStore(ForLogin(NoSuchAccount))),
    )
  let #(session, bytes) = hear(session, taken)
  assert_error_reply(bytes:, sequence: 1, code: 3002)
  assert session.receiving == None && session.sending == None
    as "no RC4 starts after a refusal"
  assert !support.stops(taken) as "the client decides when to close"
  let #(_, taken) = login_start(session)
  assert option.is_some(support.asked(taken))
    as "plain bytes still read after the refusal, so nothing was ciphered"
}

pub fn key_data_with_a_wrong_m1_answers_error_3002_in_plain_text_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(session, exchange) =
    key_data_exchange(
      connected(seed: support.seed(first: 1)),
      password: "not the password",
    )
  let #(session, taken) = key_data_request(session, exchange)
  let #(_, bytes) = hear(session, taken)
  assert_error_reply(bytes:, sequence: 2, code: 3002)
  assert support.logs_of(step: taken, level: LogError) == []
    as "a wrong password is the player's, not an error of the server"
}

pub fn key_data_with_the_right_m1_answers_m2_in_plain_text_and_then_both_ways_run_on_rc4_under_k_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(session, exchange, taken, m2) =
    proven_with_m2(seed: support.seed(first: 1))
  assert support.asked(taken) == None && !support.stops(taken)
    as "the proof is checked at once"
  let reply = reply_of(m2)
  assert reply.status == 200 && reply.sequence == 2
    as "M2 answers the KeyData request, in plain text"
  assert login_client.child(reply:, name: "KeyData")
    == bit_array.base64_encode(
      <<32:size(32)-little, exchange.expected_m2:bits>>,
      True,
    )
    as "StsConnLib64.MT.dll!0x18002d3b0: M2 = SHA-256(A | M1 | K), with its 32-bit length"
  let #(session, taken) = login_finish(session)
  assert support.writes(taken) == []
    as "StsConnLib64.MT.dll!0x18000a350: the server sends nothing between M2 and the client's LoginFinish"
  let #(session, taken) =
    answer(session:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  let #(session, bytes) = hear(session, taken)
  assert login_client.child(reply: reply_of(bytes), name: "AuthType") == "0"
    as "the first bytes after M2 decipher under K from byte 0: none were dropped and none were sent in between"
  let #(session, taken) = list_my_accounts(session)
  let #(_, bytes) = hear(session, taken)
  assert reply_of(bytes).status == 200 && reply_of(bytes).sequence == 4
    as "the next reply deciphers on the same receiving state, which runs on across messages"
}

pub fn login_finish_asks_the_hand_off_to_keep_a_new_game_token_and_once_kept_answers_auth_type_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let seed = support.seed(first: 1)
  let #(session, _exchange) = proven(seed:)
  let #(session, taken) = login_finish(session)
  let assert Some(ask) = support.asked(taken) as "LoginFinish asks the hand-off"
  let assert Ok(token) = guid.from_wire(support.sixteen(seed:, counter: 1))
  assert ask.request
    == AskHandOff(Put(
      key: GameToken(token:),
      holder: Holder(
        account_id: AccountId(7),
        login_name: vector.name,
        game_account_id: support.jim().game_account_id,
      ),
      lifetime_ms: 60_000,
    ))
    as "the token is the seed's second draw and is kept for the account for the settings' lifetime"
  assert ask.deadline_ms == support.now_ms + 5000
  assert support.writes(taken) == []
    as "the client is answered only once the token is kept"
  let #(_, taken) =
    answer(session:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  let #(_, bytes) = hear(session, taken)
  let reply = reply_of(bytes)
  assert reply.status == 200 && reply.sequence == 3
  assert login_client.child(reply:, name: "AuthType") == "0"
    as "StsConnLib64.MT.dll!0x1800043d0: AuthType 0 is a finished login"
  assert login_client.child(reply:, name: "UserId")
    == guid.to_text(support.jim().game_account_id)
    as "the UserId is the account's game account id as GUID text"
  assert login_client.child(reply:, name: "UserName") == vector.name
}

pub fn list_my_accounts_answers_exactly_one_game_account_with_an_alias_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(session, _token, _finished) = finished(seed: support.seed(first: 1))
  let #(session, taken) = list_my_accounts(session)
  assert support.asked(taken) == None as "the account list needs no ask"
  let #(_, bytes) = hear(session, taken)
  let reply = reply_of(bytes)
  assert reply.status == 200 && reply.sequence == 4
  let accounts =
    list.filter(reply.root.children, fn(found) { found.name == "GameAccount" })
  let assert [account] = accounts
    as "HandleListMyAccountsResult 0x1400b36c0: exactly one GameAccount"
  let assert Ok(alias) = sts_xml.child(account, "Alias")
    as "the client reads the Alias"
  assert alias.text == vector.name
    as "the login name is the Alias, which the client sends back in RequestGameToken"
}

pub fn request_game_token_answers_the_token_kept_at_login_finish_with_no_ask_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(session, token, _finished) = finished(seed: support.seed(first: 1))
  let #(session, taken) = list_my_accounts(session)
  let #(session, _list) = hear(session, taken)
  let #(session, taken) = request_game_token(session)
  assert support.asked(taken) == None
    as "0x1400b3a50: a failing RequestGameToken leaves the client with no message, so the rule makes no ask there"
  let #(_, bytes) = hear(session, taken)
  let reply = reply_of(bytes)
  assert reply.status == 200 && reply.sequence == 5
  assert login_client.child(reply:, name: "Token") == guid.to_text(token)
    as "the token the hand-off was asked to keep at LoginFinish"
  // The client sends the three requests back to back; the rule takes the two
  // after LoginFinish once the hand-off answers.
  let #(session, _exchange) = proven(seed: support.seed(first: 1))
  let #(session, first) = login_finish(session)
  let #(session, second) = list_my_accounts(session)
  assert support.asked(second) == None
    as "a read held while the ask is out is taken after it, not now"
  let assert [] = support.writes(second)
  let #(session, third) = request_game_token(session)
  assert support.writes(third) == []
  let token = token_asked(first)
  let #(session, taken) =
    answer(session:, taken: first, outcome: step.Answer(FromHandOff(Kept)))
  let assert [finish_reply, list_reply, token_reply] = support.writes(taken)
    as "after the answer the rule replies to each request in order"
  let assert Some(receiving) = session.receiving
  let #(receiving, plain) = rc4.crypt(receiving, finish_reply)
  assert login_client.child(reply: reply_of(plain), name: "AuthType") == "0"
  let #(receiving, plain) = rc4.crypt(receiving, list_reply)
  assert reply_of(plain).sequence == 4
  let #(_, plain) = rc4.crypt(receiving, token_reply)
  assert login_client.child(reply: reply_of(plain), name: "Token")
    == guid.to_text(token)
}

pub fn a_ping_gets_no_answer_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let ping = fn(session) {
    one_way(session:, protocol: "Sts", command: "Ping", body: "")
  }
  let #(session, taken) = ping(connected(seed: support.seed(first: 1)))
  assert taken == Effects([])
    as "0x18002f370: Ping is one-way and gets no answer"
  let #(_, taken) = login_start(session)
  assert option.is_some(support.asked(taken)) as "the connection goes on"
  let #(session, _token, _finished) = finished(seed: support.seed(first: 1))
  let #(session, taken) = ping(session)
  assert taken == Effects([]) as "a ciphered ping gets no answer either"
  let #(session, taken) = list_my_accounts(session)
  let #(_, bytes) = hear(session, taken)
  assert reply_of(bytes).status == 200
    as "the ping's ciphered bytes were taken in order, so the next request still deciphers"
}

pub fn a_store_that_gives_no_answer_at_login_start_answers_error_42_and_logs_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  let outcomes = [
    NoAnswerInTime,
    NotRunning,
    EndedBeforeAnswer,
    StoppedWaiting,
    step.Answer(FromStore(Unavailable)),
  ]
  list.each(outcomes, fn(outcome) {
    let #(session, taken) = login_start(connected(seed: support.seed(first: 1)))
    let #(session, taken) = answer(session:, taken:, outcome:)
    let #(_, bytes) = hear(session, taken)
    assert_error_reply(bytes:, sequence: 1, code: 42)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "the failure is the server's: a warning"
    assert line.about.connection == Some(ConnectionId(1))
      && line.about.peer == Some(support.peer)
      as "the line says who and where"
  })
}

pub fn a_hand_off_that_gives_no_answer_at_login_finish_answers_error_42_and_logs_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  let outcomes = [
    NoAnswerInTime,
    NotRunning,
    EndedBeforeAnswer,
    StoppedWaiting,
    step.Answer(FromHandOff(AlreadyHeld)),
  ]
  list.each(outcomes, fn(outcome) {
    let #(session, _exchange) = proven(seed: support.seed(first: 1))
    let #(session, taken) = login_finish(session)
    let #(session, taken) = answer(session:, taken:, outcome:)
    let #(_, bytes) = hear(session, taken)
    assert_error_reply(bytes:, sequence: 3, code: 42)
    let assert [_line] = support.logs_of(step: taken, level: LogWarning)
      as "the failure is the server's: a warning"
  })
}

pub fn a_request_the_client_never_sends_at_that_point_ends_the_connection_and_an_unknown_command_is_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  // KeyData before LoginStart.
  let #(_, taken) =
    request(
      session: connected(seed: support.seed(first: 1)),
      protocol: "Auth",
      command: "KeyData",
      body: sts_xml.Parent("Request", [sts_xml.Text("KeyData", "AAAA")]),
    )
  assert support.stops(taken) && support.writes(taken) == []
    as "KeyData before LoginStart is a request the client never sends"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "the connection ends with an error log"
  // LoginFinish before LoginStart, and before the proof.
  let #(_, taken) = login_finish(connected(seed: support.seed(first: 1)))
  assert support.stops(taken)
    && list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "LoginFinish before the proof ends the connection"
  let #(session, _exchange) =
    key_data_exchange(
      connected(seed: support.seed(first: 1)),
      password: vector.password,
    )
  let #(_, taken) = login_finish(session)
  assert support.stops(taken)
    && list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "LoginFinish while the proof is still to come ends the connection"
  // A whole request of a command the rule does not know.
  let #(session, taken) =
    request(
      session: connected(seed: support.seed(first: 1)),
      protocol: "Auth",
      command: "Frobnicate",
      body: sts_xml.Empty("Request"),
    )
  assert !support.stops(taken) && support.writes(taken) == []
    as "an unknown command does not end the connection"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "it is logged once"
  assert support.says(line:, words: "unhandled")
    && support.says(line:, words: "Frobnicate")
    as "the line says the request is unhandled and which"
  let #(_, taken) = login_start(session)
  assert option.is_some(support.asked(taken))
    as "the connection goes on to the next request"
  // Bytes that are no STS request.
  let #(_, taken) =
    send_bytes(connected(seed: support.seed(first: 1)), <<
      "GET / HTTP/1.1\r\n\r\n":utf8,
    >>)
  assert support.stops(taken)
    && list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "bytes the library never writes end the connection with an error log"
}

pub fn the_srp_secret_and_the_token_come_from_the_connections_seed_only_test() -> Nil {
  use <- owned_test.run(20_000)
  let key_data_and_token = fn(seed) {
    let #(session, taken) = login_start(connected(seed:))
    let #(_, taken) =
      answer(
        session:,
        taken:,
        outcome: step.Answer(FromStore(ForLogin(AccountFound(support.jim())))),
      )
    let assert [written] = support.writes(taken)
    let #(session, _exchange) = proven(seed:)
    let #(_, taken) = login_finish(session)
    #(written, token_asked(taken))
  }
  let first = key_data_and_token(support.seed(first: 1))
  assert first == key_data_and_token(support.seed(first: 1))
    as "the same seed gives the same B and the same token"
  let other = key_data_and_token(support.seed(first: 40))
  assert first.0 != other.0 as "two seeds give different SRP secrets"
  assert first.1 != other.1 as "and different tokens"
}
