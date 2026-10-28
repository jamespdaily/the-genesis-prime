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
//// - World entry: the client's path from 0x07DD to control (the fact file's
////   opcode.0xad, opcode.0x262, opcode.0x19b, opcode.0x6bc, opcode.0x636,
////   opcode.0xf1 and opcode.0x61, and the order the client's handlers need), the player's
////   0x262 against the client's own vector (vector.opcode.0x262.roxo_alive,
////   tested with `player_unit_test`), the saved place a WorldLocation2 row
////   gives (character_tables), the map's join in the rule's doc comment, the
////   failures every ask shares (reason 8), and 0x038C carrying one whole inner
////   frame (opcode.0x38c).
//// - The create path: 0x025C carries the whole frame of 0x025B (opcode.0x25c),
////   the result is 0x00DC (opcode.0xdc, lua.Character.OnCreateCharacterFailed),
////   and after CreateOk the client's 0x07DD (opcode.0x7dd) gets 0x0162 Failed
////   and then the list again, 0x0036 before 0x0117 (opcode.0x162.after_create,
////   opcode.0x36), the new character selected by the client's own rule
////   (lua.CharacterSelection.OnLoadFromCharacter.preselect).

import character_support
import character_tables
import connection_rule_support as support
import game_client
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, AskHandOff, AskMap, AskSessions,
  AskStore, FromHandOff, FromMap, FromSessions, FromStore, SentBySessions,
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
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/create_result
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/delete_result
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/message/player_entered_world
import genesis_prime/message/player_path.{PlayerPath}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/sessions.{Claim, Claimed, TakenOver}
import genesis_prime/step.{
  type Event, type Outcome, type Step, ConnectionId, EndedBeforeAnswer, LogError,
  LogInfo, LogWarning, Map, NoAnswerInTime, NotRunning, OtherSocketFailure,
  Sessions, StartTimer, StoppedWaiting, TimerFired, TimerId, Unwatch, Watch,
  WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{
  AccountId, Character, CharacterCreated, CharacterDeleted, CharacterId,
  CharacterLoaded, CharacterRenamed, Created, Deleted, ForSelect, ForWorld,
  ListCharacters, Listed, LoadCharacter, LookEntry, NameStands, NameTaken,
  NewCharacter, NewNameTaken, NoFreeSlot, NoSuchCharacter, NotRenamable,
  NotTheAccounts, Renamed, Select, Unavailable, World,
}
import genesis_prime/table/character_customization
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import genesis_prime/world_map/map.{Join, Joined}
import genesis_prime/world_map/map_id.{MapId}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

/// What the tests' game connections are made with: a realm id and a
/// character limit the hello and the list must carry, the number of character
/// slots a create is told, the client's tables and a deadline.
fn settings() -> game_connection.Settings {
  Settings(
    realm_id: 5,
    max_characters: 9,
    character_slots: 3,
    tables: character_tables.shared(),
    ask_deadline_ms: 4000,
  )
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
  event: Event(Message, Answer),
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

/// The connection after the hand-off held the key: Sessions asked to claim
/// the account.
fn claiming() -> #(game_connection.State, Step(Nil, Request)) {
  let #(state, taken) = replied()
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
  )
}

/// The claim the connection asks Sessions: its account and its id.
fn claim_ask() -> Request {
  AskSessions(Claim(account: AccountId(7), connection: ConnectionId(1)))
}

/// Sessions' answer to the claim in `taken`.
fn claimed(
  state state: game_connection.State,
  taken taken: Step(Nil, Request),
) -> #(game_connection.State, Step(Nil, Request)) {
  answer(state:, taken:, outcome: step.Answer(FromSessions(Claimed)))
}

/// The connection after Sessions answered the claim: in character select,
/// nothing asked.
fn in_select() -> game_connection.State {
  let #(state, taken) = claiming()
  claimed(state:, taken:).0
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
    outcome: step.Answer(FromStore(ForSelect(Listed(characters:)))),
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
fn disconnect(
  taken: Step(Nil, Request),
  cipher: Cipher,
) -> disconnect_reason.DisconnectReason {
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

/// A stored character whose gender is 2 or 3, which no CharacterCustomization
/// row has, so its entry holds no body visuals whatever its race
/// (`character_customization.all` below shows it).
fn character(id id: Int, name name: String, seed seed: Int) -> store.Character {
  Character(
    character_id: CharacterId(id),
    name:,
    gender: 2 + seed % 2,
    race_id: RaceId(1 + seed % 30),
    class_id: ClassId(1 + seed % 20),
    faction_id: 166 - seed % 2,
    level: 10 + seed,
    path: seed % 4,
    world_id: 1000 + seed,
    world_zone_id: 2000 + seed,
    position_x: 1.5,
    position_y: 2.5,
    position_z: 3.5,
    look: [],
    bones: [],
    naming: NameStands,
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
  assert ask_request(taken) == claim_ask()
    as "the account the hand-off named, claimed for this connection"
  assert support.writes(taken) == []
  let #(state, _) = claimed(state:, taken:)
  // The next read is under the session key: the store is asked because 0x07E0
  // opened under it.
  let #(_, taken) = read(state, select_start())
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
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
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  assert ask_request(taken) == claim_ask()
    as "Sessions is asked first: 0x07E0 still waits in the bytes read"
  let #(_, taken) = claimed(state:, taken:)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "the holder's account, once Sessions answers"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
  assert support.writes(taken) == []
}

pub fn the_stores_rows_become_0x0117_under_the_session_key_with_no_characters_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = listed(characters: [])
  let assert [Frame(message_id: 0x0036, ..), Frame(message_id: 0x0117, body:)] =
    heard(taken, keyed())
    as "opcode.0x36 and opcode.0x117 inside 0x3DC under the session key"
  assert character_list.decode(body)
    == Ok(CharacterList(
      server_time: filetime,
      characters: [],
      enabled_creation_ids: [],
      disabled_creation_ids: [],
      realm_id: 5,
      in_world_realm_id: 0,
      in_world_character_id: 0,
      in_world_logoff_ms: 0,
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
  assert list.all(
    character_customization.all(character_tables.shared()),
    fn(row) { row.gender < 2 },
  )
    as "no CharacterCustomization row is for gender 2 or 3 (character_tables_test: the client's table has rows for genders 0 and 1 only), so a character of gender 2 or 3 has no body visual"
  let assert [Frame(message_id: 0x0036, ..), Frame(message_id: 0x0117, body:)] =
    heard(taken, keyed())
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
        gender: 2,
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
    as "0x14007f720 and the rows: each field of the entry is the row's; the three unread fields 0 (opcode.0x117.character_unread); not disabled, no rename; costume mask 0 and no costume items or dyes, since the characters have no look, and no CharacterCustomization row has their gender (0x140027380); no bones; 0 days since logout; floats 1.5, 2.5 and 3.5 as the bits 0x3FC00000, 0x40200000 and 0x40600000"
  assert sent.server_time == filetime && sent.realm_id == 5
}

pub fn a_session_key_the_hand_off_does_not_hold_gets_0x036a_reason_19_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = replied()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(NoHolder)))
  assert disconnect(taken, keyed()) == AccountDisconnected
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
    assert disconnect(taken, keyed()) == LostUserServer
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
  assert disconnect(taken, keyed()) == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(state, taken) = replied()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromHandOff(AlreadyHeld)))
  assert disconnect(taken, keyed()) == LostUserServer
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
      assert disconnect(taken, keyed()) == LostUserServer
        as "0x1400168a0: the client waits for 0x0117 with no timeout (lua.Character.OnCharacterList), so every failure ends with 0x036A, reason 8 for the server's own"
      let assert [line] = support.logs_of(step: taken, level: LogWarning)
      assert line.about.peer == Some(support.peer)
      assert line.about.account_id == Some(7) as "the account is known by then"
    },
  )
}

pub fn a_store_answer_to_another_ask_than_the_one_out_gets_0x036a_reason_8_an_error_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(store.ForLogin(store.NoSuchAccount))),
      step.Answer(FromStore(ForSelect(Created(NameTaken)))),
    ],
    fn(outcome) {
      let #(state, taken) = listing()
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == LostUserServer
        as "a list is asked for, so the client would wait on its prompt for good unless it is told"
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
        as "an answer of another ask is a bug of the server's: an error"
    },
  )
}

pub fn the_server_stopping_after_the_hello_gets_0x036a_reason_8_under_the_cipher_held_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  // Waiting for 0x058F: the base key.
  let #(_, taken) = feed(connected(), step.Stopping(deadline_ms: 9000))
  assert disconnect(taken, base()) == LostUserServer
    as "opcode.0x36a: the client is told, or it would wait on its prompt for good"
  // Part-way through an ask: the shell gives StoppedWaiting, then the step
  // that ends without an ask is the end.
  let #(state, taken) = replied()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
  let #(state, taken) = claiming()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
  let #(state, taken) = listing()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
  // In character select with the list sent: the session key.
  let #(state, _) = listed(characters: [])
  let #(_, taken) = feed(state, step.Stopping(deadline_ms: 9000))
  assert disconnect(taken, keyed()) == LostUserServer
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
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  let #(_, taken) = claimed(state:, taken:)
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
    == [Some(#("unhandled", 0x082D)), Some(#("unhandled", 0x0241))]
    as "opcode.0x38c and opcode.0x82d: 0x038C carries the whole frame of 0x082D, which is logged under its own id; opcode.0x241: the client sends it and waits for no answer, and no feature takes it; each is logged in order"
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
  let #(state, taken) = claimed(state:, taken:)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
  assert unhandled_ids(taken) == []
    as "0x038C follows 0x07E0 in the bytes and waits for the store's answer"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed(characters: [])))),
    )
  let assert [Frame(message_id: 0x0036, ..), Frame(message_id: 0x0117, ..)] =
    heard(taken, keyed())
    as "the list first"
  assert unhandled_ids(taken) == [Some(#("unhandled", 0x082D))]
    as "then the frame that waited, whose inner message 0x082D is logged under its own id (opcode.0x38c)"
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
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "the client asked for its list again, so the store is asked again"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Listed([character(id: 5, name: "Eve", seed: 1)]))),
      ),
    )
  let assert [Frame(message_id: 0x0036, ..), Frame(message_id: 0x0117, body:)] =
    heard(taken, keyed())
  let assert Ok(sent) = character_list.decode(body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve"]
    as "the new list holds what the store gave this time"
}

// ---- create and the play that follows ----

/// A create request for CharacterCreation row 466 with a path of 2 and the
/// look of labels 2 and 21.
fn a_create_request(name: String) -> create_character.CreateCharacter {
  CreateCharacter(
    ..character_support.create_request(name),
    path: 2,
    customisation_labels: [2, 21],
    customisation_values: [1, 2],
  )
}

/// The bytes of a create request as the client sends it: the whole frame of
/// 0x025B as the body of 0x025C (opcode.0x25c), under the session key.
fn create_message(request: create_character.CreateCharacter) -> BitArray {
  let assert Ok(body) = create_character.encode(request)
    as "the request encodes"
  let assert Ok(plain) = frame.encode(0x025B, body) as "0x025B frames"
  keyed_message(0x025C, plain)
}

fn play_message(character_id: Int) -> BitArray {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id:))
    as "0x07DD encodes"
  keyed_message(0x07DD, body)
}

/// The connection after a create request, with its ask to the store.
fn creating(
  request: create_character.CreateCharacter,
) -> #(game_connection.State, Step(Nil, Request)) {
  read(in_select(), create_message(request))
}

/// The one 0x00DC the step writes, decoded.
fn create_result_of(
  taken: Step(Nil, Request),
) -> create_character_result.CreateCharacterResult {
  character_support.create_result_in(heard(taken, keyed()))
}

pub fn message_0x025c_with_a_valid_0x025b_asks_the_store_to_make_the_character_and_its_answer_is_0x00dc_create_ok_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = creating(a_create_request("Ab Cd"))
  assert ask_request(taken)
    == AskStore(
      store.Select(store.CreateCharacter(
        account_id: AccountId(7),
        character: NewCharacter(
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          path: 2,
          world_id: 3460,
          world_zone_id: 6009,
          position_x: 29.128599166870117,
          position_y: -853.87158203125,
          position_z: -560.18798828125,
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
          ],
          bones: character_support.bones(46),
        ),
        character_slots: 3,
      )),
    )
    as "opcode.0x25b, CharacterCreation row 466; its PreTutorial start is WorldLocation2 row 51596 (World 3460, zone 6009 and its position); the slot count is the settings'"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Created(CharacterCreated(CharacterId(11))))),
      ),
    )
  assert create_result_of(taken)
    == CreateCharacterResult(
      character_id: 11,
      field_2: 0,
      result: create_result.CreateOk,
    )
    as "opcode.0xdc: the new character's id and CreateOk"
  assert !support.stops(taken) as "the connection goes on to the play request"
  assert support.asked(taken) == None
}

pub fn a_name_that_fails_rule_0_is_0x00dc_name_length_and_nothing_is_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = creating(a_create_request("Abcd"))
  assert support.asked(taken) == None as "nothing is stored"
  assert create_result_of(taken).result == create_result.NameLength
    as "lua.Character.OnCreateCharacterFailed: 10"
  assert !support.stops(taken)
}

pub fn a_name_taken_in_any_case_and_an_account_at_its_slots_are_0x00dc_6_and_9_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = creating(a_create_request("Ab Cd"))
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Created(NameTaken)))),
    )
  assert create_result_of(taken).result == create_result.NameUnavailable
    as "lua.Character.OnCreateCharacterFailed: 6"
  let #(state, taken) = creating(a_create_request("Ab Cd"))
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Created(NoFreeSlot)))),
    )
  assert create_result_of(taken).result == create_result.AccountFull
    as "lua.Character.OnCreateCharacterFailed: 9"
  assert !support.stops(taken)
}

pub fn a_request_the_client_would_not_send_is_0x00dc_create_failed_with_a_warning_naming_the_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    creating(CreateCharacter(..a_create_request("Ab Cd"), creation_id: 539))
  assert support.asked(taken) == None as "nothing is stored"
  assert create_result_of(taken).result == create_result.CreateFailed
    as "lua.Character.OnCreateCharacterFailed: 4 is 'due to an error'; CharacterCreation row 539 is a Level50 row that costs currency the account lacks"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "the refusal is logged once"
  assert support.says(line, "539") as "the warning names the creation row"
  assert line.about.account_id == Some(7)
  assert !support.stops(taken)
}

pub fn a_store_that_gives_no_answer_to_a_create_gets_0x036a_reason_8_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      NoAnswerInTime,
      NotRunning,
      EndedBeforeAnswer,
      StoppedWaiting,
    ],
    fn(outcome) {
      let #(state, taken) = creating(a_create_request("Ab Cd"))
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == LostUserServer
        as "0x1400168a0 and lua.Character.OnCharacterList: the client waits with no timeout, so a create the store cannot answer ends with 0x036A, reason 8, as a list does"
    },
  )
}

pub fn a_play_of_a_character_the_account_does_not_have_gets_0x0162_failed_then_0x0036_and_0x0117_with_the_character_selected_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = playing(11)
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForWorld(NotTheAccounts))),
    )
  let assert [Frame(message_id: 0x0162, body:)] = heard(taken, keyed())
    as "opcode.0x162.after_create: the refusal is written first"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
    as "opcode.0x162: 2 Failed is the generic refusal"
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "the list is built again"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "a play the real client would not send is logged once"
  assert support.says(line, "11") as "the warning names the character's id"
  assert line.about.account_id == Some(7)
  let new = Character(..character(id: 11, name: "Ab Cd", seed: 1), level: 1)
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForSelect(Listed([character(id: 5, name: "Eve", seed: 2), new])),
        ),
      ),
    )
  let assert [
    Frame(message_id: 0x0036, body: level),
    Frame(message_id: 0x0117, body: list_body),
  ] = heard(taken, keyed())
    as "opcode.0x36 then opcode.0x117"
  assert max_character_level.decode(level) == Ok(MaxCharacterLevel(12))
    as "opcode.0x36: the highest level of the account's characters (Eve's 12; the new character's is 1)"
  let assert Ok(sent) = character_list.decode(list_body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve", "Ab Cd"]
  let assert [0, chosen] =
    list.map(sent.characters, fn(entry) { entry.last_logged_out_days })
    as "lua.CharacterSelection.OnLoadFromCharacter.preselect: only the character named has a last logout, so the client selects it"
  assert chosen != 0
}

pub fn a_play_of_a_character_with_no_saved_place_is_refused_the_same_way_and_the_map_is_not_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = playing(42)
  let no_place = Character(..world_character(), world_id: 0)
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForWorld(CharacterLoaded(no_place)))),
    )
  let assert [Frame(message_id: 0x0162, body:)] = heard(taken, keyed())
    as "the world 0 a character made before create wrote its start place has no World row, which 0xAD needs (opcode.0xad)"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "the list again, and no map is asked"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line, "no saved place")
}

pub fn a_second_request_waits_for_the_create_answer_and_is_then_taken_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    read(in_select(), <<
      create_message(a_create_request("Ab Cd")):bits,
      play_message(11):bits,
    >>)
  assert ask_request(taken)
    == AskStore(
      store.Select(store.CreateCharacter(
        account_id: AccountId(7),
        character: NewCharacter(
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          path: 2,
          world_id: 3460,
          world_zone_id: 6009,
          position_x: 29.128599166870117,
          position_y: -853.87158203125,
          position_z: -560.18798828125,
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
          ],
          bones: character_support.bones(46),
        ),
        character_slots: 3,
      )),
    )
    as "only the create is asked while its answer is out"
  assert support.writes(taken) == []
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Created(CharacterCreated(CharacterId(11))))),
      ),
    )
  let assert [Frame(message_id: 0x00DC, ..)] = heard(taken, keyed())
    as "the result first"
  assert ask_request(taken)
    == AskStore(World(LoadCharacter(AccountId(7), CharacterId(11))))
    as "then the play that waited: the character the create made is read for the world"
}

// ---- entering the world ----

/// The connection after 0x07DD for the character, with its ask to the store.
fn playing(character_id: Int) -> #(game_connection.State, Step(Nil, Request)) {
  read(in_select(), play_message(character_id))
}

/// A Dominion human male, class 2, who stands in World 3460 at the place of
/// WorldLocation2 row 51596 (the Novice start): its body is the look of
/// CharacterCustomization row 10 (labels 21 = 2 and 2 = 1, display 137 on slot
/// 25), and it has the 48 bone values race 1, sex 0 carries
/// (opcode.0x25b.counts).
fn world_character() -> store.Character {
  Character(
    character_id: CharacterId(42),
    name: "Ab Cd",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(2),
    faction_id: 166,
    level: 1,
    path: 3,
    world_id: 3460,
    world_zone_id: 6009,
    position_x: 29.128599166870117,
    position_y: -853.87158203125,
    position_z: -560.18798828125,
    look: [
      LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
      LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
    ],
    bones: character_support.bones(48),
    naming: NameStands,
  )
}

/// The connection after the store gave the character: the map is asked.
fn joining() -> #(game_connection.State, Step(Nil, Request)) {
  let #(state, taken) = playing(42)
  answer(
    state:,
    taken:,
    outcome: step.Answer(
      FromStore(ForWorld(CharacterLoaded(world_character()))),
    ),
  )
}

/// The unit id and the run of the map the tests' map gives.
const unit_id = 5

const incarnation = 77

/// The connection after the map took the player: the burst is written.
fn entered() -> #(game_connection.State, Step(Nil, Request)) {
  let #(state, taken) = joining()
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(Joined(unit_id:, incarnation:))),
  )
}

/// The connection in the world, with its burst taken.
fn in_world() -> game_connection.State {
  entered().0
}

/// The 0x262 among the burst, decoded.
fn player_in(taken: Step(Nil, Request)) -> UnitCreatePlayer {
  let assert Ok(Frame(body:, ..)) =
    list.find(heard(taken, keyed()), fn(frame) { frame.message_id == 0x0262 })
    as "the burst holds 0x0262"
  let assert Ok(player) = unit_create_player.decode(body) as "0x0262 decodes"
  player
}

fn move_message(message_id: Int) -> BitArray {
  keyed_message(message_id, <<0, 0, 0, 0>>)
}

pub fn message_0x07dd_asks_the_store_for_the_character_then_the_map_and_the_answer_is_0xad_0x262_0x19b_0x6bc_0x636_0xf1_0x61_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = playing(42)
  assert ask_request(taken)
    == AskStore(World(LoadCharacter(AccountId(7), CharacterId(42))))
    as "opcode.0x7dd: the character's id, and the holder's account, which scopes the read"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForWorld(CharacterLoaded(world_character()))),
      ),
    )
  assert ask_request(taken)
    == AskMap(MapId(world_id: 3460, instance: 0), Join(ConnectionId(1), 42))
    as "the saved world of the character, its one open instance, the connection's id and the character's id"
  assert support.writes(taken) == []
    as "nothing is written before the map answers"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Joined(unit_id:, incarnation:))),
    )
  assert list.map(heard(taken, keyed()), fn(frame) { frame.message_id })
    == [0x00AD, 0x0262, 0x019B, 0x06BC, 0x0636, 0x00F1, 0x0061]
    as "the order the client needs: 0xAD first; 0x262 before 0x19B; 0x19B before 0x6BC, 0x636 and 0x61 (the client drops 0x6BC until 0x19B has set the player, opcode.0x6bc); 0xF1 after 0xAD (opcode.0xad, opcode.0x19b, opcode.0x6bc, opcode.0x636, opcode.0x61, opcode.0xf1)"
  assert list.last(support.effects_of(taken))
    == Ok(Watch(WatchId(2), Map(MapId(3460, 0), incarnation)))
    as "the connection watches the run of the map that holds its player, after the burst"
  assert support.asked(taken) == None
  assert !support.stops(taken)
}

pub fn message_0xad_carries_the_saved_world_and_position_and_0_in_its_last_two_floats_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [Frame(message_id: 0x00AD, body:), ..] =
    heard(entered().1, keyed())
  assert enter_world.decode(body)
    == Ok(EnterWorld(
      world_id: 3460,
      position_x: 0x41E9075F,
      position_y: 0xC45577C8,
      position_z: 0xC40C0C08,
      field_5: 0,
      field_6: 0,
    ))
    as "opcode.0xad: World 3460 and the position of WorldLocation2 row 51596 as 32-bit floats (29.1286, -853.8716 and -560.1880 are 0x41E9075F, 0xC45577C8 and 0xC40C0C08); the fourth and fifth floats are never read, 0.0 (opcode.0xad.last_floats)"
}

pub fn message_0x262_carries_the_characters_values_its_health_its_place_its_body_and_bones_and_nothing_else_test() -> Nil {
  use <- owned_test.run(10_000)
  assert player_in(entered().1)
    == UnitCreatePlayer(
      unit_id: 5,
      character_id: 42,
      realm_id: 5,
      name: "Ab Cd",
      race_id: 1,
      class_id: 2,
      gender: 0,
      group_id: 0,
      owned_unit_ids: [],
      guild_name: "",
      guild_type: 0,
      guild_ids: [],
      bone_values: character_support.bones(48),
      pvp_flags: 0,
      premium_tier: 0,
      title_id: 0,
      create_flags: 0,
      stats: [
        UnitStat(stat_id: 0, value: 136),
        UnitStat(stat_id: 10, value: 1),
      ],
      server_time_estimate_start: 0,
      movement_commands: [
        UnitPositionCommand(
          x: 0x41E9075F,
          y: 0xC45577C8,
          z: 0xC40C0C08,
          blends: 0,
        ),
      ],
      properties: [
        UnitProperty(property_id: 7, field_2: 0x43080000, value: 0x43080000),
      ],
      item_visuals: [
        ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0),
      ],
      cast_id: 0,
      faction_id: 166,
      base_faction_id: 166,
      tagged_by_unit_id: 0,
      tagged_by_group_id: 0,
      field_31: 0,
      field_33: 0,
      world_socket_id: 0,
      cluster_id: 0,
      field_37: 0,
      minimap_marker_id: 0,
      display_info_id: 0,
      outfit_info_id: 0,
    )
    as "opcode.0x262: the unit id the map gave, the row's character id, the settings' realm id, name, race, class, gender, both factions 166 (vector.opcode.0x262.roxo: a base faction with a row, or 0x19B fails); stat 0 and property 7 are 136 as the client's creation check needs (vector.opcode.0x262.health, 0x140457bc5), and stat 10 is the character's level 1 (0x140458140); one kind 2 movement command at the saved position, which the client never moves to the ground after 0xAD (0x1403e828a); the body of the character list (CharacterCustomization row 10: display 137 on slot 25) and the stored bones; PvP flags 0, not the path 3 (0x1403b48b0); every other value is the client's no-value case (opcode.0x262.player_fields, opcode.0x262.unit_fields)"
}

pub fn message_0x19b_names_the_unit_0x6bc_gives_the_path_0x636_gives_control_of_it_0xf1_keeps_the_clients_interval_and_0x61_is_empty_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [
    _,
    _,
    Frame(message_id: 0x019B, body: is_player),
    Frame(message_id: 0x06BC, body: path_body),
    Frame(message_id: 0x0636, body: control),
    Frame(message_id: 0x00F1, body: interval),
    Frame(message_id: 0x0061, body: entered_world),
  ] = heard(entered().1, keyed())
  assert unit_is_player.decode(is_player)
    == Ok(UnitIsPlayer(unit_id: 5, field_2: 0))
    as "opcode.0x19b: the first value is the unit id the map gave, which must be the unit 0x262 created; the second is never read (opcode.0x19b.second_value)"
  assert player_path.decode(path_body)
    == Ok(PlayerPath(
      path: 3,
      soldier_experience: 0,
      settler_experience: 0,
      scientist_experience: 0,
      explorer_experience: 0,
      unlocked_paths: 8,
      last_path_change_days: 0xBF800000,
    ))
    as "opcode.0x6bc: the stored path 3 (Explorer); experience 0 on each path, which is path level 1 (PathLevel); only the character's own path unlocked, bit 3 is 8; -1.0 days (0xBF800000), so no path change cooldown is left (GameFormula 2366: 1800 seconds)"
  assert client_control_granted.decode(control)
    == Ok(ClientControlGranted(echo_value: 0, reset_movement: 1, unit_id: 5))
    as "vector.opcode.0x636.body: the value 0, the reset bit 1 and the unit id"
  assert movement_send_interval.decode(interval)
    == Ok(MovementSendInterval(
      world_difficulty: 0,
      world_prime_level: 0,
      world_flags: 0,
      interval_milliseconds: 125,
    ))
    as "opcode.0xf1.fields: Normal difficulty, prime level 0 and no flags for an open world; the interval 125 ms, the client's own until 0xF1 arrives (opcode.0xf1, 0x140c3a004; below 25 the client raises it to 25)"
  assert player_entered_world.decode(entered_world)
    == Ok(player_entered_world.PlayerEnteredWorld)
    as "opcode.0x61: the body is empty"
}

pub fn a_store_a_maps_or_a_map_that_gives_no_answer_ends_the_play_with_0x036a_reason_8_and_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, NotRunning, EndedBeforeAnswer], fn(outcome) {
    list.each([#(playing(42), "the store"), #(joining(), "the map")], fn(asked) {
      let #(#(state, taken), who) = asked
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == LostUserServer
        as "0x1400168a0 and opcode.0xad: the client waits for 0xAD or 0x162 with no timeout, so every failure ends with 0x036A, reason 8 for the server's own"
      let assert [line] = support.logs_of(step: taken, level: LogWarning)
        as "the failure is the server's: a warning"
      assert support.says(line, who) as "the line names the process"
      assert line.about.account_id == Some(7)
    })
  })
  let #(state, taken) = playing(42)
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromStore(Unavailable)))
  assert disconnect(taken, keyed()) == LostUserServer
    as "a store that is unavailable"
  let assert [_] = support.logs_of(step: taken, level: LogWarning)
  list.each([playing(42), joining()], fn(asked) {
    let #(state, taken) = asked
    let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
    assert disconnect(taken, keyed()) == LostUserServer
      as "the server stopping while the connection waits: the client is told"
    assert support.logs(taken) == [] as "a stop is no failure"
  })
}

pub fn an_answer_that_is_none_world_entry_asked_for_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      // The map's answer while the store is asked.
      #(playing(42), step.Answer(FromMap(Joined(unit_id:, incarnation:)))),
      // The store's answer while the map is asked.
      #(
        joining(),
        step.Answer(FromStore(ForWorld(CharacterLoaded(world_character())))),
      ),
      // Another process's answers.
      #(playing(42), step.Answer(FromStore(ForSelect(Listed([]))))),
      #(playing(42), step.Answer(FromSessions(Claimed))),
      #(playing(42), step.Answer(FromHandOff(Kept))),
    ],
    fn(asked) {
      let #(#(state, taken), outcome) = asked
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == LostUserServer
        as "the client waits for 0xAD or 0x162, so it is told"
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
        as "an answer of another ask is a bug of the server's: an error"
    },
  )
}

pub fn a_world_answer_when_character_select_asked_the_store_is_a_bug_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = listing()
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForWorld(NotTheAccounts))),
    )
  assert disconnect(taken, keyed()) == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(state, taken) = listing()
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Joined(unit_id:, incarnation:))),
    )
  assert disconnect(taken, keyed()) == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn the_clients_movement_messages_after_entry_are_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let ids = [0x0635, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x0637]
  let #(state, taken) =
    read(in_world(), bit_array.concat(list.map(ids, move_message)))
  assert unhandled_ids(taken)
    == list.map(ids, fn(id) { Some(#("unhandled", id)) })
    as "opcode.0x635, opcode.0x636 (0x63A and 0x637 follow control), opcode.0xf2 and the movement the client sends: it waits for no answer, and no feature takes them; each is logged under its own id, in order"
  assert support.writes(taken) == []
  assert !support.stops(taken)
  let #(_, taken) = read(state, support.ping(1))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 1>>]
    as "the connection goes on"
}

pub fn an_unhandled_message_id_is_a_warning_the_first_time_on_a_connection_and_a_debug_line_after_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = read(in_world(), move_message(0x0637))
  let assert [first] = support.logs(taken)
  assert first.level == LogWarning
    as "the first 0x637 of the connection is logged as unhandled, as a warning"
  assert first.about.message == Some(#("unhandled", 0x0637))
  let #(state, taken) = read(state, move_message(0x0637))
  let assert [again] = support.logs(taken)
  assert again.level == step.LogDebug
    as "opcode.0x637: the client sends it on every move, up to 8 a second, so a repeat of an id already logged is a debug line"
  assert again.about.message == Some(#("unhandled", 0x0637))
  let #(_, taken) = read(state, move_message(0x0635))
  let assert [other] = support.logs(taken)
  assert other.level == LogWarning as "another id is its first: a warning"
}

pub fn a_world_message_carries_one_whole_frame_whose_message_is_logged_under_its_own_id_in_character_select_and_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([in_select(), in_world()], fn(state) {
    let #(_, taken) = read(state, store_request())
    assert unhandled_ids(taken) == [Some(#("unhandled", 0x082D))]
      as "opcode.0x38c: a 5-bit value, then the world message's whole frame (0x14007e180); the inner message is logged as unhandled under its own id"
    assert !support.stops(taken)
    assert support.writes(taken) == []
  })
}

pub fn a_world_message_with_no_whole_frame_or_bytes_after_it_is_one_the_client_never_writes_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let whole = game_client.world_body(kind: 3, message_id: 0x082D, body: <<1>>)
  let bad = [
    #(<<>>, "no kind byte"),
    #(<<3>>, "a kind and no frame"),
    #(<<3, 8, 0, 0>>, "a length cut short"),
    #(<<3, 20, 0, 0, 0, 0x2D, 0x08, 1>>, "a length of 20 and 3 bytes"),
    #(<<whole:bits, 0>>, "a byte after the frame"),
  ]
  list.each([in_select(), in_world()], fn(state) {
    list.each(bad, fn(case_) {
      let #(body, what) = case_
      let #(_, taken) = read(state, keyed_message(0x038C, body))
      assert support.stops(taken)
        as { "opcode.0x38c: " <> what <> " ends the connection" }
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      assert support.asked(taken) == None
    })
  })
}

pub fn a_takeover_in_the_world_writes_0x036a_reason_19_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), taken_over())
  assert disconnect(taken, keyed()) == AccountDisconnected
    as "0x1400168a0: 19 is 'This account has been disconnected', for the connection a newer login took over, in the world as in character select"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
  assert line.about.account_id == Some(7)
}

pub fn the_end_of_the_players_map_ends_the_connection_with_0x036a_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), WatchEnded(WatchId(2)))
  assert disconnect(taken, keyed()) == LostUserServer
    as "the player is gone from the world with its map, so the client is told the server failed, or it would stay in a world no server holds"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.account_id == Some(7)
}

pub fn a_log_line_in_the_world_is_about_the_players_map_and_character_and_one_in_character_select_is_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), WatchEnded(WatchId(2)))
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.map == Some(MapId(world_id: 3460, instance: 0))
    as "every line of a connection in the world says where: the map the player is in"
  assert line.about.character_id == Some(42)
    as "and who: the character the player plays"
  assert line.about.connection == Some(ConnectionId(1))
  let #(_, taken) = feed(in_select_with_a_list(), taken_over())
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
  assert line.about.map == None && line.about.character_id == None
    as "in character select the connection is in no map and plays no character"
  let #(_, taken) = read(in_world(), keyed_message(0x0244, <<>>))
  assert list.all(support.logs(taken), fn(line) {
    line.about.map == Some(MapId(world_id: 3460, instance: 0))
    && line.about.character_id == Some(42)
  })
    as "the lines of the shared connection code, which log a refused frame, carry them too"
}

pub fn a_watch_the_rule_did_not_open_ending_in_the_world_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), WatchEnded(WatchId(9)))
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) = feed(in_select_with_a_list(), WatchEnded(WatchId(2)))
  assert support.stops(taken)
    as "the map's watch is open only while the player is in the world"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn the_end_of_sessions_in_the_world_claims_again_and_the_claim_puts_the_player_back_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), WatchEnded(WatchId(1)))
  assert support.effects_of(taken) == [StartTimer(TimerId(1), 100)]
    as "Sessions is likely still restarting, so the claim waits a moment, as in character select"
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(state, taken) = feed(state, TimerFired(TimerId(1)))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
  assert ask_request(taken) == claim_ask()
  let #(state, taken) = claimed(state:, taken:)
  assert support.writes(taken) == []
  // Back in the world: the movement the client sends is read as in the world,
  // and the map's end ends the connection.
  let #(state, taken) = read(state, move_message(0x0637))
  assert unhandled_ids(taken) == [Some(#("unhandled", 0x0637))]
    as "the claim kept where the client is, the player in the world"
  let #(_, taken) = feed(state, WatchEnded(WatchId(2)))
  assert disconnect(taken, keyed()) == LostUserServer
    as "the map's watch is still open after the claim"
}

pub fn the_end_of_the_map_while_the_claim_waits_ends_the_connection_with_reason_8_and_a_takeover_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(_, taken) = feed(state, WatchEnded(WatchId(2)))
  assert disconnect(taken, keyed()) == LostUserServer
    as "the player's map ended while the connection waits to claim again"
  let #(_, taken) = feed(state, taken_over())
  assert disconnect(taken, keyed()) == AccountDisconnected
}

pub fn a_map_end_while_character_select_waits_to_claim_is_a_bug_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(_, taken) = feed(state, WatchEnded(WatchId(2)))
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn the_server_stopping_in_the_world_tells_the_client_with_reason_8_under_the_session_key_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), step.Stopping(deadline_ms: 9000))
  assert disconnect(taken, keyed()) == LostUserServer
}

pub fn a_second_0x058f_or_a_play_in_the_world_is_not_taken_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let second =
    keyed_message(
      0x058F,
      game_client.hello_reply_body(
        session_key: session_key(),
        account_name: "jim",
      ),
    )
  let #(_, taken) = read(in_world(), second)
  assert support.stops(taken)
    as "0x058F is sent once (opcode.0x58f), in the world as in character select"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) = read(in_world(), play_message(42))
  assert unhandled_ids(taken) == [Some(#("unhandled", 0x07DD))]
    as "a play of the client that is in the world already is logged as unhandled, and no store is asked"
  assert support.asked(taken) == None
  assert !support.stops(taken)
}

// ---- delete and rename ----

fn delete_message(character_id: Int) -> BitArray {
  let assert Ok(body) = delete_character.encode(DeleteCharacter(character_id:))
    as "0x0352 encodes"
  keyed_message(0x0352, body)
}

fn rename_message(character_id: Int, name: String) -> BitArray {
  let assert Ok(body) =
    rename_character.encode(RenameCharacter(character_id:, name:))
    as "0x0786 encodes"
  keyed_message(0x0786, body)
}

/// The connection after a delete request, with its ask to the store.
fn deleting(character_id: Int) -> #(game_connection.State, Step(Nil, Request)) {
  read(in_select(), delete_message(character_id))
}

/// The connection after a rename request, with its ask to the store.
fn renaming(
  character_id: Int,
  name: String,
) -> #(game_connection.State, Step(Nil, Request)) {
  read(in_select(), rename_message(character_id, name))
}

pub fn message_0x0352_asks_the_store_to_delete_the_character_and_its_answer_is_0x00e6_result_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = deleting(11)
  assert ask_request(taken)
    == AskStore(
      store.Select(store.DeleteCharacter(
        account_id: AccountId(7),
        character_id: CharacterId(11),
      )),
    )
    as "opcode.0x352: the character's id, and the holder's account, which scopes the delete"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Deleted(CharacterDeleted)))),
    )
  assert character_support.delete_result_in(heard(taken, keyed()))
    == DeleteCharacterResult(result: delete_result.DeleteOk, value: 0)
    as "opcode.0xe6: result 0 and the value nothing reads (opcode.0xe6.value)"
  assert !support.stops(taken) as "the connection goes on"
  assert support.asked(taken) == None
    as "lua.CharacterSelection.OnCharacterDeleteResult: the client rebuilds its list, so the store is not asked for it again"
}

pub fn a_delete_of_a_character_the_account_does_not_have_is_0x00e6_result_1_and_a_warning_with_the_account_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = deleting(11)
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Deleted(NoSuchCharacter)))),
    )
  assert character_support.delete_result_in(heard(taken, keyed()))
    == DeleteCharacterResult(result: delete_result.DeleteFailed, value: 0)
    as "lua.CharacterSelection.OnCharacterDeleteResult: 1 shows 'Something went wrong...'"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "a request the real client would not send is logged once"
  assert support.says(line, "11") as "the warning names the character's id"
  assert line.about.account_id == Some(7)
  assert !support.stops(taken)
}

pub fn message_0x0786_asks_the_store_to_rename_the_character_and_its_answer_is_0x014b_result_18_with_the_stored_name_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = renaming(11, "Ab Cd")
  assert ask_request(taken)
    == AskStore(
      store.Select(store.RenameCharacter(
        account_id: AccountId(7),
        character_id: CharacterId(11),
        name: "Ab Cd",
      )),
    )
    as "opcode.0x786: the character's id and the typed name"
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Renamed(CharacterRenamed(name: "Ab Cd")))),
      ),
    )
  assert character_support.rename_result_in(heard(taken, keyed()))
    == RenameCharacterResult(
      result: rename_result.RenameOk,
      character_id: 11,
      name: "Ab Cd",
    )
    as "opcode.0x14b: result 18 with the id and the name"
  assert !support.stops(taken)
}

pub fn a_name_taken_a_name_failing_rule_0_and_a_character_that_is_not_renamable_are_0x014b_16_15_and_13_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = renaming(11, "Ab Cd")
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Renamed(NewNameTaken)))),
    )
  assert character_support.rename_result_in(heard(taken, keyed())).result
    == rename_result.NameUnavailable
    as "lua.CharacterSelection.OnCharacterRenameResult: 16"
  let #(_, taken) = renaming(11, "Abcd")
  assert support.asked(taken) == None as "nothing is stored"
  assert character_support.rename_result_in(heard(taken, keyed())).result
    == rename_result.NameLength
    as "lua.CharacterSelection.OnCharacterRenameResult: 15"
  assert support.logs_of(step: taken, level: LogWarning) == []
    as "a name is a player's to mistype"
  let #(state, taken) = renaming(11, "Ab Cd")
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Renamed(NotRenamable)))),
    )
  assert character_support.rename_result_in(heard(taken, keyed())).result
    == rename_result.RenameFailed
    as "lua.CharacterSelection.OnCharacterRenameResult: 13"
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
  assert !support.stops(taken)
}

pub fn a_store_that_gives_no_answer_to_a_delete_or_a_rename_gets_0x036a_reason_8_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      NoAnswerInTime,
      NotRunning,
      EndedBeforeAnswer,
      StoppedWaiting,
    ],
    fn(outcome) {
      list.each([deleting(11), renaming(11, "Ab Cd")], fn(asked) {
        let #(state, taken) = asked
        let #(_, taken) = answer(state:, taken:, outcome:)
        assert disconnect(taken, keyed()) == LostUserServer
          as "0x1400168a0 and opcode.0xe6, opcode.0x14b: the client waits for the result with no timeout, so a request the store cannot answer ends with 0x036A, reason 8"
        assert support.stops(taken)
      })
    },
  )
}

pub fn a_store_answer_to_another_ask_than_a_delete_or_a_rename_is_a_bug_that_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(deleting(11), ForSelect(Renamed(NewNameTaken))),
      #(renaming(11, "Ab Cd"), ForSelect(Deleted(CharacterDeleted))),
    ],
    fn(asked) {
      let #(#(state, taken), wrong) = asked
      let #(_, taken) =
        answer(state:, taken:, outcome: step.Answer(FromStore(wrong)))
      assert disconnect(taken, keyed()) == LostUserServer
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_0x0352_or_0x0786_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      // opcode.0x352: 64 bits.
      keyed_message(0x0352, <<1, 2>>),
      // opcode.0x786: 64 bits and a wide text.
      keyed_message(0x0786, <<1, 2>>),
    ],
    fn(cut) {
      let #(_, taken) = read(in_select(), cut)
      assert support.stops(taken)
      assert support.asked(taken) == None
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_0x025c_or_0x07dd_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  // The carrier's whole frame is not a frame.
  let #(_, taken) = read(in_select(), keyed_message(0x025C, <<1, 2, 3>>))
  assert support.stops(taken)
    as "opcode.0x25c: the carrier holds a whole frame the client wrote"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // The carrier holds another message than 0x025B.
  let assert Ok(other) = frame.encode(0x07DD, <<0, 0, 0, 0, 0, 0, 0, 0>>)
  let #(_, taken) = read(in_select(), keyed_message(0x025C, other))
  assert support.stops(taken) as "opcode.0x25c carries 0x025B and nothing else"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // A 0x025B body that is cut short.
  let assert Ok(cut) = frame.encode(0x025B, <<1, 2>>)
  let #(_, taken) = read(in_select(), keyed_message(0x025C, cut))
  assert support.stops(taken)
  assert support.asked(taken) == None
  // A 0x07DD body that is cut short (opcode.0x7dd: 64 bits).
  let #(_, taken) = read(in_select(), keyed_message(0x07DD, <<1, 2>>))
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

// ---- one login per account ----
//
// Expected values come from these places: the rule's doc comment (the claim
// follows the hand-off and comes before the list; Sessions ending is claimed
// again after a short wait; a takeover disconnects the old connection), 0x036A
// reason 19 for a takeover and reason 8 for the server's own failure
// (0x1400168a0, opcode.0x36a), and the claim's contract in
// `genesis_prime/sessions`. The wait is 100 ms and the retries of a claim that
// finds Sessions not running are 5, as the rule's constants state.

/// The wait, in milliseconds, before a claim is made again.
const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
const claim_retries = 5

fn taken_over() -> Event(Message, Answer) {
  Woken(message: SentBySessions(message: TakenOver))
}

/// A connection in character select with its list shown, which Sessions' end
/// finds with state to keep.
fn in_select_with_a_list() -> game_connection.State {
  listed(characters: []).0
}

pub fn after_the_hand_off_the_account_is_claimed_with_a_watch_on_sessions_before_the_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, claim) = claiming()
  assert support.effects_of(claim) == [Watch(WatchId(1), Sessions)]
    as "the rule watches Sessions with the claim, under its one watch id"
  assert ask_request(claim) == claim_ask()
  let assert Some(ask) = support.asked(claim)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  // 0x07E0 arriving while the claim is out waits; the list is asked only after
  // Sessions answers.
  let #(state, taken) = read(state, select_start())
  assert support.asked(taken) == None
  assert support.effects_of(taken) == []
  let #(_, taken) = claimed(state:, taken: claim)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "the claim comes before the list: the frame that waited is taken once Sessions answers"
}

pub fn a_connection_given_taken_over_writes_0x036a_reason_19_under_its_cipher_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_select_with_a_list(), taken_over())
  assert disconnect(taken, keyed()) == AccountDisconnected
    as "0x1400168a0: 19 is 'This account has been disconnected', the account-level text, for the connection a newer login took over"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once"
  assert line.about.connection == Some(ConnectionId(1))
    && line.about.account_id == Some(7)
    as "the line names the connection and the account"
  assert support.asked(taken) == None
  assert support.logs_of(step: taken, level: LogWarning) == []
}

pub fn a_takeover_while_the_connection_waits_to_claim_again_ends_it_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(_, taken) = feed(state, taken_over())
  assert disconnect(taken, keyed()) == AccountDisconnected
    as "a takeover Sessions sent before it ended still disconnects the old connection"
}

pub fn a_message_sessions_never_sends_or_one_before_the_claim_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let answer_as_a_message = Woken(message: SentBySessions(message: Claimed))
  list.each(
    [
      feed(in_select(), answer_as_a_message).1,
      feed(connected(), taken_over()).1,
      feed(replied().0, taken_over()).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      assert support.writes(taken) == []
        as "a connection that was no one's session has nothing to be told"
    },
  )
}

pub fn the_end_of_the_watch_on_sessions_starts_a_timer_and_its_firing_claims_again_from_where_the_connection_is_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  assert support.effects_of(taken) == [StartTimer(TimerId(1), claim_wait_ms)]
    as "Sessions is likely still restarting, so the claim waits a moment"
  assert support.asked(taken) == None
  // Bytes that arrive during the wait are kept for after the claim.
  let #(state, taken) = read(state, select_start())
  assert support.asked(taken) == None && support.effects_of(taken) == []
  let #(state, taken) = feed(state, TimerFired(TimerId(1)))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    as "the ended watch is forgotten, so the one watch is opened again under its id"
  assert ask_request(taken) == claim_ask()
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(_, taken) = claimed(state:, taken:)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "Claimed puts the connection back in character select with its state, and the 0x07E0 that waited is taken"
}

pub fn a_second_end_of_sessions_claims_again_under_the_same_watch_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, TimerFired(TimerId(1)))
  let state = claimed(state:, taken:).0
  let #(state, taken) = feed(state, WatchEnded(WatchId(1)))
  assert support.effects_of(taken) == [StartTimer(TimerId(1), claim_wait_ms)]
  let #(_, taken) = feed(state, TimerFired(TimerId(1)))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
}

pub fn a_watch_or_timer_the_rule_did_not_open_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  list.each(
    [
      feed(in_select_with_a_list(), WatchEnded(WatchId(9))).1,
      feed(in_select_with_a_list(), TimerFired(TimerId(1))).1,
      feed(waiting, WatchEnded(WatchId(1))).1,
      feed(waiting, TimerFired(TimerId(2))).1,
      feed(replied().0, WatchEnded(WatchId(1))).1,
      feed(connected(), TimerFired(TimerId(1))).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_claim_that_finds_sessions_not_running_is_made_again_after_a_wait_up_to_the_retries_then_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = claiming()
  let retry = fn(held: #(game_connection.State, Step(Nil, Request)), _try) {
    let #(state, taken) = held
    let #(state, taken) = answer(state:, taken:, outcome: NotRunning)
    assert support.effects_of(taken)
      == [Unwatch(WatchId(1)), StartTimer(TimerId(1), claim_wait_ms)]
      as "the watch on a Sessions that is not running is dropped, and the claim waits"
    assert support.asked(taken) == None
    assert support.writes(taken) == []
    let #(state, taken) = feed(state, TimerFired(TimerId(1)))
    assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    assert ask_request(taken) == claim_ask()
    #(state, taken)
  }
  let #(state, taken) =
    int.range(from: 1, to: claim_retries + 1, with: #(state, taken), run: retry)
  let #(_, taken) = answer(state:, taken:, outcome: NotRunning)
  assert disconnect(taken, keyed()) == LostUserServer
    as "after the retries the client is told the server failed, or it would wait on its prompt for good"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line:, words: "sessions was not running")
}

pub fn a_claim_that_finds_sessions_not_running_after_its_end_is_made_again_with_the_same_bound_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, TimerFired(TimerId(1)))
  let #(state, taken) = answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), StartTimer(TimerId(1), claim_wait_ms)]
  let #(_, taken) = feed(state, TimerFired(TimerId(1)))
  assert ask_request(taken) == claim_ask()
}

pub fn a_claim_sessions_does_not_answer_gets_0x036a_reason_8_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = claiming()
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
      as "0x1400168a0: 8 is 'Lost connection with user server.', as for the store"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.peer == Some(support.peer)
    assert line.about.account_id == Some(7)
  })
  // A claim that Sessions does not answer on a claim made again after its end.
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, TimerFired(TimerId(1)))
  let #(_, taken) = answer(state:, taken:, outcome: NoAnswerInTime)
  assert disconnect(taken, keyed()) == LostUserServer
}

pub fn an_answer_to_the_claim_that_is_none_a_claim_gets_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromSessions(TakenOver)),
      step.Answer(FromStore(Unavailable)),
      step.Answer(FromHandOff(Kept)),
    ],
    fn(outcome) {
      let #(state, taken) = claiming()
      let #(_, taken) = answer(state:, taken:, outcome:)
      assert disconnect(taken, keyed()) == LostUserServer
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn the_server_stopping_while_a_claim_is_out_or_waited_for_gets_reason_8_with_no_log_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = claiming()
  let #(_, out) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(out, keyed()) == LostUserServer
  assert support.logs(out) == [] as "a stop is no failure"
  let #(waiting, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(_, stopping) = feed(waiting, step.Stopping(deadline_ms: 9000))
  assert disconnect(stopping, keyed()) == LostUserServer
  let #(_, closed) = feed(waiting, step.Socket(step.PeerClosed))
  assert support.effects_of(closed) == [step.Stop]
    as "a client that closes while the connection waits is not told"
}

pub fn a_takeover_queued_behind_a_failing_store_ask_ends_with_reason_8_not_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  // The shell takes no other input while an ask is out, so a takeover that
  // arrives meanwhile is taken after the ask's outcome; the outcome here ends
  // the connection, so the takeover is never taken. This is the gap the rule
  // states: the client gets the server-failure text, not the account's. Both
  // end the connection.
  let #(state, taken) = listing()
  let #(_, taken) = answer(state:, taken:, outcome: NoAnswerInTime)
  assert disconnect(taken, keyed()) == LostUserServer
    as "a failing ask ends with reason 8 though a takeover waits behind it"
}
