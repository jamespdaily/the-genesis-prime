//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. Expected values come from these
//// places.
//// - The hello: message 3 inside 0x3DC under the base key, which is the first
////   thing written, since any game server message before it ends the client's
////   login (0x1400370d0); its build, checksum and realm id (opcode.0x3).
//// - 0x058F, with the session key the client shows (opcode.0x58f); the client
////   keys its cipher from the key at once, and every message after it, each
////   way, is under it (vector.0x14003827c.session_fold). 0x07E0 follows it
////   (opcode.0x7e0).
//// - 0x0117: the server's time, one entry per character as the client's list
////   shows it, the realm's id, `max_characters`, and 0 in the fields the
////   client never reads or no feature gives yet (opcode.0x117, 0x14007f720,
////   opcode.0x117.character_unread, 0x140027380).
//// - 0x036A and its reasons: 19 "This account has been disconnected" and 8
////   "Lost connection with user server." (0x1400168a0, opcode.0x36a).
//// - The ping and its pong, bare (opcode.0x0, opcode.0x1); 0x038C carrying
////   0x082D, and 0x0241 (opcode.0x82d, opcode.0x241).
//// - The rule's doc comment, as approved on the card, and the shape's change
////   that the game connection never stops without telling the client after
////   the hello.

import connection_rule_support as support
import game_client
import genesis_prime/client_connection.{
  type Answer, type Request, AskHandOff, AskStore, FromHandOff, FromStore,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection.{Settings} as game_connection
import genesis_prime/hand_off.{
  AlreadyHeld, Holder, Kept, NoHolder, SessionKey, Take, Taken,
}
import genesis_prime/login/guid
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{CharacterListEntry}
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/step.{
  type Event, type Outcome, type Step, ConnectionId, EndedBeforeAnswer, LogError,
  LogWarning, NoAnswerInTime, NotRunning, OtherSocketFailure, StoppedWaiting,
}
import genesis_prime/store.{
  AccountId, Character, CharacterId, Characters, ListCharacters, Unavailable,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

/// What the tests' game connections are made with: a realm id and a
/// character limit the hello and the list must carry, and a deadline.
fn settings() -> game_connection.Settings {
  Settings(realm_id: 5, max_characters: 9, ask_deadline_ms: 4000)
}

/// The 16 bytes the client shows as its session key: 01 .. 10, as in the
/// client's vector (vector.opcode.0x58f.body), the wire bytes of the GUID
/// `support.guid_of(1)` the hand-off is asked for.
fn session_key() -> BitArray {
  guid.to_wire(support.guid_of(1))
}

fn holder() -> hand_off.Holder {
  Holder(
    account_id: AccountId(7),
    login_name: "jim",
    game_account_id: support.guid_of(0x11),
  )
}

fn base() -> Cipher {
  cipher.base()
}

fn keyed() -> Cipher {
  game_client.session_cipher(session_key: session_key())
}

/// The system time every answer of the tests carries, as a FILETIME.
const filetime = 133_900_000_000_000_000

fn feed(
  state: game_connection.State,
  event: Event(Nil, Answer),
) -> #(game_connection.State, Step(Nil, Request)) {
  game_connection.step(state, support.input_at(filetime:, event:))
}

fn read(
  state: game_connection.State,
  bytes: BitArray,
) -> #(game_connection.State, Step(Nil, Request)) {
  feed(state, step.Socket(step.Read(bytes)))
}

fn answer(
  state state: game_connection.State,
  taken taken: Step(Nil, Request),
  outcome outcome: Outcome(Answer),
) -> #(game_connection.State, Step(Nil, Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  feed(state, step.Answered(ask: ask.ask, outcome:))
}

/// A connection the server has accepted; the step is the hello.
fn accepted() -> #(game_connection.State, Step(Nil, Request)) {
  feed(
    game_connection.new(settings()),
    step.Socket(step.Accepted(ConnectionId(1), support.peer, support.seed(1))),
  )
}

fn connected() -> game_connection.State {
  accepted().0
}

/// What the client sends first: 0x058F, under the base key.
fn hello_reply() -> BitArray {
  game_client.hello_reply(session_key: session_key(), account_name: "jim")
}

/// A message of the client's under the session key.
fn keyed_message(message_id: Int, body: BitArray) -> BitArray {
  game_client.client_bytes(message_id:, body:, cipher: keyed())
}

fn select_start() -> BitArray {
  keyed_message(0x07E0, <<>>)
}

/// 0x038C carrying the store-catalog request, as the client sends it after
/// 0x07E0 (opcode.0x82d: the value 0x13, then a 14-bit value in two bytes).
fn store_request() -> BitArray {
  keyed_message(
    0x038C,
    game_client.world_body(kind: 0x13, message_id: 0x082D, body: <<0x34, 0x12>>),
  )
}

fn activity() -> BitArray {
  keyed_message(0x0241, <<>>)
}

/// The connection after 0x058F, with its ask to take the session key.
fn replied() -> #(game_connection.State, Step(Nil, Request)) {
  read(connected(), hello_reply())
}

/// The connection after the hand-off held the key: in character select,
/// nothing asked.
fn in_select() -> game_connection.State {
  let #(state, taken) = replied()
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
  ).0
}

/// The connection after 0x07E0, with its ask to the store.
fn listing() -> #(game_connection.State, Step(Nil, Request)) {
  read(in_select(), select_start())
}

/// The connection after the store's rows, the list written.
fn listed(
  characters characters: List(store.Character),
) -> #(game_connection.State, Step(Nil, Request)) {
  let #(state, taken) = listing()
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromStore(Characters(characters:))),
  )
}

/// Every message the step writes, as the client reads it: each in a 0x3DC
/// wrapper, opened under `cipher`.
fn heard(taken: Step(Nil, Request), cipher: Cipher) -> List(Frame) {
  list.map(support.written_frames(taken), game_client.in_the_game_wrapper(
    _,
    cipher,
  ))
}

/// The one 0x036A the step writes, under `cipher`, with the connection ended.
fn disconnect(taken: Step(Nil, Request), cipher: Cipher) -> Int {
  let assert [Frame(message_id: 0x036A, body:)] = heard(taken, cipher)
    as "one 0x036A in its wrapper, under the cipher the connection holds"
  let assert Ok(DisconnectNotice(reason:)) = disconnect_notice.decode(body)
    as "0x036A decodes"
  assert support.stops(taken) as "the connection ends after 0x036A"
  reason
}

fn ask_request(taken: Step(Nil, Request)) -> Request {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  ask.request
}

fn unhandled_ids(taken: Step(Nil, Request)) -> List(Option(#(String, Int))) {
  list.map(support.logs_of(step: taken, level: LogWarning), fn(line) {
    line.about.message
  })
}

fn character(id id: Int, name name: String, seed seed: Int) -> store.Character {
  Character(
    character_id: CharacterId(id),
    name:,
    gender: seed % 4,
    race_id: 1 + seed % 30,
    class_id: 1 + seed % 20,
    faction_id: 166 - seed % 2,
    level: 10 + seed,
    path: seed % 4,
    world_id: 1000 + seed,
    world_zone_id: 2000 + seed,
    position_x: 1.5,
    position_y: 2.5,
    position_z: 3.5,
  )
}

// ---- the tests, in the order of the card's list ----

pub fn on_connect_the_hello_is_the_first_thing_written_in_0x3dc_under_the_base_key_with_the_realm_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = accepted()
  assert support.asked(taken) == None
  assert !support.stops(taken)
  let assert [Frame(message_id: 0x0003, body:)] = heard(taken, base())
    as "opcode.0x3 and 0x1400370d0: the hello, opened under the base key, is the only thing written, so nothing travels before it"
  let assert Ok(hello) = server_hello.decode(body) as "opcode.0x3: the hello"
  assert hello
    == ServerHello(
      build: 16_042,
      realm_id: 5,
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
    as "CheckAuthServerVersion 0x140037b70: build 16042 and checksum 0x097998A0; the realm's id from the settings; every field the client never reads is 0 (opcode.0x3)"
}

pub fn message_0x058f_asks_the_hand_off_to_take_the_session_key_and_every_later_frame_is_read_under_the_session_key_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = replied()
  assert ask_request(taken)
    == AskHandOff(Take(SessionKey(key: support.guid_of(1))))
    as "opcode.0x58f: the 16 bytes the client showed, as the GUID they are"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the hand-off answers"
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert support.asked(taken) == None
  assert support.writes(taken) == []
  // The next read is under the session key: the store is asked because 0x07E0
  // opened under it.
  let #(_, taken) = read(state, select_start())
  assert ask_request(taken) == AskStore(ListCharacters(AccountId(7)))
    as "0x07E0 under the session key is read"
}

pub fn a_message_under_the_base_key_after_0x058f_is_not_read_as_the_client_sent_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let under_the_base_key =
    game_client.client_bytes(message_id: 0x07E0, body: <<>>, cipher: base())
  let #(_, taken) = read(in_select(), under_the_base_key)
  assert support.asked(taken) == None
    as "vector.0x14003827c.session_fold: after 0x058F the client sends nothing under the base key, so these bytes opened under the session key are not 0x07E0"
}

pub fn message_0x07e0_in_the_same_read_as_0x058f_waits_until_the_hand_off_answers_then_the_store_is_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    read(connected(), <<hello_reply():bits, select_start():bits>>)
  assert ask_request(taken)
    == AskHandOff(Take(SessionKey(key: support.guid_of(1))))
    as "only the hand-off is asked while the key is out: 0x07E0 waits in the bytes read"
  assert support.writes(taken) == []
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert ask_request(taken) == AskStore(ListCharacters(AccountId(7)))
    as "the holder's account, once the hand-off answers"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
  assert support.writes(taken) == []
}

pub fn the_stores_rows_become_0x0117_under_the_session_key_with_no_characters_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = listed(characters: [])
  let assert [Frame(message_id: 0x0117, body:)] = heard(taken, keyed())
    as "opcode.0x117 inside 0x3DC under the session key"
  assert character_list.decode(body)
    == Ok(CharacterList(
      server_time: filetime,
      characters: [],
      enabled_creation_ids: [],
      disabled_creation_ids: [],
      realm_id: 5,
      pending_removal_realm_id: 0,
      pending_removal_character_id: 0,
      pending_removal_time: 0,
      reservations: 0,
      max_characters: 9,
      field_11: 0,
      faction_restriction: 0,
      free_level_50_available: 0,
    ))
    as "opcode.0x117: the input's system time as the server's time, no characters, the settings' realm id and max_characters, the creation id lists empty so the client offers the rows its enabled column sets (0x140021bb0), and 0 in every field no feature gives yet"
  assert !support.stops(taken)
  assert support.asked(taken) == None
}

pub fn the_stores_rows_become_one_entry_each_in_the_order_given_with_every_field_from_the_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let first = character(id: 42, name: "Ab", seed: 3)
  let second = character(id: 9, name: "Zéd Qu", seed: 8)
  let #(_, taken) = listed(characters: [first, second])
  let assert [Frame(message_id: 0x0117, body:)] = heard(taken, keyed())
  let assert Ok(sent) = character_list.decode(body)
  assert sent.characters
    == [
      CharacterListEntry(
        character_id: 42,
        name: "Ab",
        gender: 3,
        race_id: 4,
        class_id: 4,
        faction_id: 165,
        level: 13,
        body_visuals: [],
        worn_visuals: [],
        world_id: 1003,
        world_zone_id: 2003,
        field_12: 0,
        position_x: 0x3FC00000,
        position_y: 0x40200000,
        position_z: 0x40600000,
        field_16: 0,
        field_17: 0,
        path: 3,
        disabled: 0,
        requires_rename: 0,
        costume_slot_mask: 0,
        costume_item_ids: [],
        costume_dyes: [],
        bone_values: [],
        last_logged_out_days: 0,
      ),
      CharacterListEntry(
        character_id: 9,
        name: "Zéd Qu",
        gender: 0,
        race_id: 9,
        class_id: 9,
        faction_id: 166,
        level: 18,
        body_visuals: [],
        worn_visuals: [],
        world_id: 1008,
        world_zone_id: 2008,
        field_12: 0,
        position_x: 0x3FC00000,
        position_y: 0x40200000,
        position_z: 0x40600000,
        field_16: 0,
        field_17: 0,
        path: 0,
        disabled: 0,
        requires_rename: 0,
        costume_slot_mask: 0,
        costume_item_ids: [],
        costume_dyes: [],
        bone_values: [],
        last_logged_out_days: 0,
      ),
    ]
    as "0x14007f720 and the rows: each field of the entry is the row's; the three unread fields 0 (opcode.0x117.character_unread); not disabled, no rename; costume mask 0 and no costume items or dyes, since no appearance is written yet (0x140027380); no bones; 0 days since logout; floats 1.5, 2.5 and 3.5 as the bits 0x3FC00000, 0x40200000 and 0x40600000"
  assert sent.server_time == filetime && sent.realm_id == 5
}

pub fn a_session_key_the_hand_off_does_not_hold_gets_0x036a_reason_19_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = replied()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(NoHolder)))
  assert disconnect(taken, keyed()) == 19
    as "0x1400168a0: 19 is 'This account has been disconnected', for a key never put, taken or expired"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "the refusal is logged once"
  assert line.about.connection == Some(ConnectionId(1))
    && line.about.peer == Some(support.peer)
    as "the warning names the connection and its peer"
  assert support.asked(taken) == None
}

pub fn a_hand_off_that_gives_no_answer_gets_0x036a_reason_8_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, NotRunning, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = replied()
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == 8
      as "0x1400168a0: 8 is 'Lost connection with user server.', for the server's own failure"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "the failure is the server's: a warning"
    assert line.about.peer == Some(support.peer)
  })
  // A hand-off answer no Take gets is a bug of the server's, and ends the
  // connection the same way, with an error.
  let #(state, taken) = replied()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(Kept)))
  assert disconnect(taken, keyed()) == 8
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(state, taken) = replied()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(AlreadyHeld)))
  assert disconnect(taken, keyed()) == 8
}

pub fn a_store_that_gives_no_answer_or_is_unavailable_gets_0x036a_reason_8_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      NoAnswerInTime,
      NotRunning,
      EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, taken) = listing()
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == 8
        as "0x1400168a0: the client waits for 0x0117 with no timeout (lua.Character.OnCharacterList), so every failure ends with 0x036A, reason 8 for the server's own"
      let assert [line] = support.logs_of(step: taken, level: LogWarning)
      assert line.about.peer == Some(support.peer)
      assert line.about.account_id == Some(7) as "the account is known by then"
    },
  )
}

pub fn the_server_stopping_after_the_hello_gets_0x036a_reason_8_under_the_cipher_held_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  // Waiting for 0x058F: the base key.
  let #(_, taken) = feed(connected(), step.Stopping(deadline_ms: 9000))
  assert disconnect(taken, base()) == 8
    as "opcode.0x36a: the client is told, or it would wait on its prompt for good"
  // Part-way through an ask: the shell gives StoppedWaiting, then the step
  // that ends without an ask is the end.
  let #(state, taken) = replied()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == 8
  let #(state, taken) = listing()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == 8
  // In character select with the list sent: the session key.
  let #(state, _) = listed(characters: [])
  let #(_, taken) = feed(state, step.Stopping(deadline_ms: 9000))
  assert disconnect(taken, keyed()) == 8
  // Before the connection is accepted there is no client to tell.
  let #(_, taken) =
    feed(game_connection.new(settings()), step.Stopping(deadline_ms: 9000))
  assert support.writes(taken) == []
  assert support.stops(taken)
}

pub fn a_first_message_other_than_0x058f_or_a_second_0x058f_is_logged_as_an_error_and_the_connection_closes_test() -> Nil {
  use <- owned_test.run(10_000)
  let first =
    game_client.client_bytes(message_id: 0x07E0, body: <<>>, cipher: base())
  let #(_, taken) = read(connected(), first)
  assert support.stops(taken)
    as "the client's first message is 0x058F (opcode.0x58f); another one is no client's"
  let assert [line] = support.logs_of(step: taken, level: LogError)
  assert line.about.peer == Some(support.peer)
  assert support.asked(taken) == None
  // A second 0x058F in the same read, as the client would send it under the
  // session key, is read once the key is taken.
  let second =
    keyed_message(
      0x058F,
      game_client.hello_reply_body(
        session_key: session_key(),
        account_name: "jim",
      ),
    )
  let #(state, taken) = read(connected(), <<hello_reply():bits, second:bits>>)
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // And one in character select.
  let #(_, taken) = read(in_select(), second)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.asked(taken) == None
}

pub fn a_bare_ping_is_answered_with_a_bare_pong_with_the_same_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = read(connected(), support.ping(9))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 9>>]
    as "opcode.0x1: the pong carries the ping's number, bare, before the client has answered the hello"
  assert !support.stops(taken)
  let #(state, _) = listed(characters: [])
  let #(_, taken) = read(state, support.ping(3))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 3>>]
    as "opcode.0x0: in character select too, the ping travels bare and is never ciphered"
}

pub fn message_0x038c_carrying_0x082d_and_0x0241_are_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = listed(characters: [])
  let #(state, taken) = read(state, <<store_request():bits, activity():bits>>)
  assert unhandled_ids(taken)
    == [Some(#("unhandled", 0x038C)), Some(#("unhandled", 0x0241))]
    as "opcode.0x82d and opcode.0x241: the client sends them and waits for no answer, and no feature takes them yet; each frame is logged in order"
  assert support.writes(taken) == []
  assert !support.stops(taken)
  let #(_, taken) = read(state, support.ping(1))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 1>>]
    as "the connection goes on"
}

pub fn frames_after_the_one_that_asked_wait_for_its_answer_and_are_then_taken_in_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    read(connected(), <<
      hello_reply():bits,
      select_start():bits,
      store_request():bits,
    >>)
  assert unhandled_ids(taken) == []
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert ask_request(taken) == AskStore(ListCharacters(AccountId(7)))
  assert unhandled_ids(taken) == []
    as "0x038C follows 0x07E0 in the bytes and waits for the store's answer"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(Characters(characters: []))),
    )
  let assert [Frame(message_id: 0x0117, ..)] = heard(taken, keyed())
    as "the list first"
  assert unhandled_ids(taken) == [Some(#("unhandled", 0x038C))]
    as "then the frame that waited"
}

pub fn a_frame_the_clients_reader_would_refuse_ends_the_connection_after_the_whole_frames_before_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // A length under the 6 bytes of a header (ParseWrappedMessage 0x140331620).
  let below_header = <<3, 0, 0, 0, 0, 0>>
  // A ping number of 20 or more: opcode.0x0 says 0 to 19.
  let assert Ok(ping_20) = frame.encode(0x0000, <<20>>)
  // A wrapper whose inner length does not account for its body.
  let assert Ok(disagrees) = frame.encode(0x0244, <<100, 0, 0, 0, 1, 2, 3>>)
  list.each([below_header, ping_20, disagrees], fn(bad) {
    let #(_, taken) = read(connected(), <<support.ping(4):bits, bad:bits>>)
    assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 4>>]
      as "the ping before the bad frame is answered"
    assert support.stops(taken)
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
  })
}

pub fn the_client_closing_a_socket_failure_and_a_late_answer_are_handled_as_in_the_login_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(connected(), step.Socket(step.PeerClosed))
  assert support.effects_of(taken) == [step.Stop]
    as "the client closed: nothing to tell it, nothing to log"
  list.each([step.ReadFailed, step.WriteFailed], fn(failed) {
    let #(_, taken) =
      feed(
        connected(),
        step.Socket(failed(OtherSocketFailure(reason: "broken"))),
      )
    assert support.stops(taken)
    assert support.writes(taken) == []
      as "the socket failed: nothing more can be written"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.peer == Some(support.peer)
  })
  // A late answer is dropped and the connection goes on.
  let state = in_select()
  let #(state, taken) = feed(state, step.AnsweredLate(ask: step.AskId(1)))
  assert support.effects_of(taken) == []
  let #(_, taken) = read(state, support.ping(2))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 2>>]
}

pub fn a_second_0x07e0_asks_the_store_again_and_sends_a_new_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = listed(characters: [])
  let #(state, taken) = read(state, select_start())
  assert ask_request(taken) == AskStore(ListCharacters(AccountId(7)))
    as "the client asked for its list again, so the store is asked again"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(Characters([character(id: 5, name: "Eve", seed: 1)])),
      ),
    )
  let assert [Frame(message_id: 0x0117, body:)] = heard(taken, keyed())
  let assert Ok(sent) = character_list.decode(body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve"]
    as "the new list holds what the store gave this time"
}
