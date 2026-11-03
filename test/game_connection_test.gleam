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
////   opcode.0xf1 and opcode.0x61, and the order the client's handlers
////   need), the player's 0x262 against the client's own vector (vector.opcode.0x262.roxo_alive,
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
import genesis_prime/account_session.{Claim, Claimed, TakenOver}
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, AskHandOff, AskMap, AskMapRun,
  AskSessions, AskStore, FromHandOff, FromMap, FromSessions, FromStore,
  SentByMap, SentBySessions, TellMoved,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/coverage/sent_message
import genesis_prime/game/connection.{Settings} as game_connection
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{
  AlreadyHeld, Holder, Kept, NoHolder, SessionKey, Take, Taken,
}
import genesis_prime/login/guid
import genesis_prime/message/camp_countdown
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
import genesis_prime/message/fall_value.{FallValue}
import genesis_prime/message/fell_below_floor.{FellBelowFloor}
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/move_speed_setting.{MoveSpeedSetting}
import genesis_prime/message/movement_command
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/movement_send_interval_answer.{
  MovementSendIntervalAnswer,
}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/message/player_entered_world
import genesis_prime/message/player_path.{PlayerPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/start_movement
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/message/zone_value_changed.{ZoneValueChanged}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, type Outcome, CallerId,
  CancelTimer, ConnectionId, EndedBeforeAnswer, LogError, LogInfo, LogWarning,
  Map, NoAnswerInTime, NotRunning, OtherSocketFailure, OwnEffect, OwnEvent,
  Sessions, StartTimer, StoppedWaiting, TimerFired, TimerId, Unwatch, Watch,
  WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{
  AccountId, Character, CharacterCreated, CharacterDeleted, CharacterId,
  CharacterLoaded, CharacterRenamed, Created, Deleted, ForMove, ForSelect,
  ForWorld, ListCharacters, Listed, LoadCharacter, LookEntry, Move, NameStands,
  NameTaken, NewCharacter, NewNameTaken, NoFreeSlot, NoSuchCharacter,
  NotRenamable, NotTheAccounts, NothingSaved, PlaceRefused, PlaceSaved, Renamed,
  SavePlace, Select, Unavailable, World,
}
import genesis_prime/table/character_customization
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import genesis_prime/world_map/map.{Join, Leave, Left, MovedUnit, Seen, Unseen}
import genesis_prime/world_map/map_id.{type MapId, MapId}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import place_support

/// What the tests' game connections are made with: a realm id and a
/// character limit the hello and the list must carry, the number of character
/// slots a create is told, the client's tables and a deadline.
fn settings() -> game_connection.Settings {
  Settings(
    realm_id: 5,
    max_characters: 9,
    game: GameSettings(camp_countdown_ms: 12_345, character_slots: 3),
    tables: character_tables.shared(),
    ask_deadline_ms: 4000,
    rate: support.roomy(),
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
  event: Event(ConnectionEvent(Message, Answer)),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, support.input_at(filetime:, event:))
}

fn read(
  state: game_connection.State,
  bytes: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  feed(state, step.OwnEvent(step.Read(bytes)))
}

fn answer(
  state state: game_connection.State,
  taken taken: ConnectionStep(Request),
  outcome outcome: Outcome(Answer),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  feed(state, step.OwnEvent(step.Answered(ask: ask.ask, outcome:)))
}

/// A connection the server has accepted, made with these settings; the step
/// is the hello.
fn accepted(
  settings: game_connection.Settings,
) -> #(game_connection.State, ConnectionStep(Request)) {
  feed(
    game_connection.new(settings),
    step.OwnEvent(step.Accepted(ConnectionId(1), support.peer, support.seed(1))),
  )
}

fn connected() -> game_connection.State {
  accepted(settings()).0
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
fn replied() -> #(game_connection.State, ConnectionStep(Request)) {
  read(connected(), hello_reply())
}

/// The connection after the hand-off held the key: Sessions asked to claim
/// the account.
fn claiming() -> #(game_connection.State, ConnectionStep(Request)) {
  claiming_from(connected())
}

/// `fresh`, a connection the server has accepted, after the hand-off held the
/// key: Sessions asked to claim the account.
fn claiming_from(
  fresh: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = read(fresh, hello_reply())
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
  taken taken: ConnectionStep(Request),
) -> #(game_connection.State, ConnectionStep(Request)) {
  answer(state:, taken:, outcome: step.Answer(FromSessions(Claimed)))
}

/// The connection after Sessions answered the claim: in character select,
/// nothing asked.
fn in_select() -> game_connection.State {
  in_select_from(connected())
}

/// `fresh`, a connection the server has accepted, after Sessions answered the
/// claim: in character select, nothing asked.
fn in_select_from(fresh: game_connection.State) -> game_connection.State {
  let #(state, taken) = claiming_from(fresh)
  claimed(state:, taken:).0
}

/// The connection after 0x07E0, with its ask to the store.
fn listing() -> #(game_connection.State, ConnectionStep(Request)) {
  read(in_select(), select_start())
}

/// The connection after the store's rows, the list written.
fn listed(
  characters characters: List(store.Character),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = listing()
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromStore(ForSelect(Listed(characters:)))),
  )
}

/// Every message the step writes, as the client reads it: each in a 0x3DC
/// wrapper, opened under `cipher`.
fn heard(taken: ConnectionStep(Request), cipher: Cipher) -> List(Frame) {
  list.map(support.written_frames(taken), game_client.in_the_game_wrapper(
    _,
    cipher,
  ))
}

/// The one 0x036A the step writes, under `cipher`, with the connection ended.
fn disconnect(
  taken: ConnectionStep(Request),
  cipher: Cipher,
) -> disconnect_reason.DisconnectReason {
  let assert [Frame(message_id: 0x036A, body:)] = heard(taken, cipher)
    as "one 0x036A in its wrapper, under the cipher the connection holds"
  let assert Ok(DisconnectNotice(reason:)) = disconnect_notice.decode(body)
    as "0x036A decodes"
  assert support.stops(taken) as "the connection ends after 0x036A"
  reason
}

fn ask_request(taken: ConnectionStep(Request)) -> Request {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  ask.request
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
    place: Some(place_support.at(
      world_id: 1000 + seed,
      world_zone_id: 2000 + seed,
      x: 1.5,
      y: 2.5,
      z: 3.5,
    )),
    look: [],
    bones: [],
    naming: NameStands,
  )
}

// ---- the tests, in the order of the card's list ----

pub fn on_connect_the_hello_is_the_first_thing_written_in_0x3dc_under_the_base_key_with_the_realm_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = accepted(settings())
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
  assert support.unhandled_ids(taken)
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
  assert support.unhandled_ids(taken) == []
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
    )
  let #(state, taken) = claimed(state:, taken:)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
  assert support.unhandled_ids(taken) == []
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
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x082D))]
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

/// What each effect of a step is, in order: the bytes of a write are not
/// compared here, only what kind of effect leaves and when.
fn kinds(taken: ConnectionStep(Request)) -> List(String) {
  list.map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Write(..)) -> "write"
      step.Log(..) -> "log"
      step.Stop -> "stop"
      OwnEffect(..) | step.Watch(..) | step.Unwatch(..) -> "other"
    }
  })
}

pub fn the_effects_of_frames_before_a_frame_that_asks_leave_in_the_order_the_frames_came_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    read(in_select(), <<
      support.ping(1):bits,
      store_request():bits,
      support.ping(2):bits,
      create_message(a_create_request("Ab Cd")):bits,
    >>)
  assert support.writes(taken) == [support.pong(1), support.pong(2)]
    as "opcode.0x0 and opcode.0x1: each ping is answered, the first ping's pong first"
  assert kinds(taken) == ["write", "log", "write"]
    as "a read's frames are taken in order: the pong, the unhandled 0x082D's log line, the pong; the create's ask ends the step after them"
  assert support.asked(taken) != None
    as "the create asks the store, after the earlier frames' effects"
}

pub fn the_effects_of_frames_before_a_frame_that_ends_the_connection_leave_in_the_order_the_frames_came_test() -> Nil {
  use <- owned_test.run(10_000)
  let below_header = <<3, 0, 0, 0, 0, 0>>
  let #(_, taken) =
    read(in_select(), <<
      support.ping(1):bits,
      store_request():bits,
      support.ping(2):bits,
      below_header:bits,
    >>)
  assert support.writes(taken) == [support.pong(1), support.pong(2)]
    as "opcode.0x0 and opcode.0x1: each ping before the bad frame is answered, the first ping's pong first"
  assert kinds(taken) == ["write", "log", "write", "log", "stop"]
    as "the whole frames before a frame the client's reader would refuse (ParseWrappedMessage 0x140331620) leave in order, then the refusal's log line and the end"
}

pub fn the_client_closing_a_socket_failure_and_a_late_answer_are_handled_as_in_the_login_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(connected(), step.OwnEvent(step.PeerClosed))
  assert support.effects_of(taken) == [step.Stop]
    as "the client closed: nothing to tell it, nothing to log"
  list.each([step.ReadFailed, step.WriteFailed], fn(failed) {
    let #(_, taken) =
      feed(
        connected(),
        step.OwnEvent(failed(OtherSocketFailure(reason: "broken"))),
      )
    assert support.stops(taken)
    assert support.writes(taken) == []
      as "the socket failed: nothing more can be written"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.peer == Some(support.peer)
  })
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
/// look of labels 2 and 22 (the Exile face of CharacterCustomization row 604).
fn a_create_request(name: String) -> create_character.CreateCharacter {
  CreateCharacter(
    ..character_support.create_request(name),
    path: 2,
    customisation_labels: [2, 22],
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
) -> #(game_connection.State, ConnectionStep(Request)) {
  read(in_select(), create_message(request))
}

/// The one 0x00DC the step writes, decoded.
fn create_result_of(
  taken: ConnectionStep(Request),
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
          level: 1,
          path: 2,
          place: character_tables.novice_start_place(),
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(22), value: 2),
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
  let no_place = Character(..world_character(), place: None)
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(CharacterLoaded(no_place, character_support.epoch(1))),
        ),
      ),
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
          level: 1,
          path: 2,
          place: character_tables.novice_start_place(),
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(22), value: 2),
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
fn playing(
  character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  playing_from(in_select(), character_id)
}

/// `in_character_select` after 0x07DD for the character, with its ask to the
/// store.
fn playing_from(
  in_character_select: game_connection.State,
  character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  read(in_character_select, play_message(character_id))
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
    place: Some(place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -560.18798828125,
    )),
    look: character_tables.row_10_look(),
    bones: character_support.bones(48),
    naming: NameStands,
  )
}

/// The connection after the store gave `character`: the map is asked.
fn joining_as(
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  joining_from(in_select(), character)
}

/// `in_character_select` after the store gave `character`: the map is asked.
fn joining_from(
  in_character_select: game_connection.State,
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = playing_from(in_character_select, 42)
  answer(
    state:,
    taken:,
    outcome: step.Answer(
      FromStore(
        ForWorld(CharacterLoaded(character, character_support.epoch(1))),
      ),
    ),
  )
}

/// The connection after the store gave the character: the map is asked.
fn joining() -> #(game_connection.State, ConnectionStep(Request)) {
  joining_as(world_character())
}

/// The tests' map: the world the tests' character is saved in, and its one
/// open instance.
fn camp_map() -> MapId {
  MapId(world_id: 3460, instance: 0)
}

/// The run of the tests' map.
const incarnation = 77

/// A map of the tests' realm and tables, as the server starts one for the tests'
/// connections, with four other connections joined, so the next join is unit 5.
fn map_with_four_players() -> map.State {
  let state =
    map.new(map.Settings(
      map: camp_map(),
      incarnation:,
      realm_id: settings().realm_id,
      tables: settings().tables,
    ))
  list.fold([2, 3, 4, 5], state, fn(state, other) {
    let assert Some(place) = world_character().place
      as "the tests' character has a saved place"
    let #(state, _) =
      map.step(
        state,
        support.input(
          OwnEvent(step.Asked(
            caller: CallerId(other),
            message: Join(
              connection: ConnectionId(other),
              character: world_character(),
              place:,
            ),
          )),
        ),
      )
    state
  })
}

/// The map's answer to the join the connection asked, which the real map gives:
/// the ask is stepped through a map of the tests' realm and tables with four
/// other players (`mapped`).
fn map_answer(taken: ConnectionStep(Request)) -> map.Outgoing {
  mapped(map_state: map_with_four_players(), taken:).1
}

/// The map's answer to a join of the tests' player, for the tests that need an
/// answer and read nothing in it.
fn a_join_answer() -> map.Outgoing {
  map_answer(joining().1)
}

/// The connection after the map took `character`: the burst is written.
fn entered_as(
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  entered_from(in_select(), character)
}

/// `in_character_select` after the map took `character`: the burst is written.
fn entered_from(
  in_character_select: game_connection.State,
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = joining_from(in_character_select, character)
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken))))
}

/// The connection after the map took the player: the burst is written.
fn entered() -> #(game_connection.State, ConnectionStep(Request)) {
  entered_as(world_character())
}

/// The connection in the world, with its burst taken.
fn in_world() -> game_connection.State {
  entered().0
}

/// The 0x262 among the burst, decoded.
fn player_in(taken: ConnectionStep(Request)) -> UnitCreatePlayer {
  game_client.unit_create_player_in(frames: heard(taken, keyed()))
}

/// A world message as the client sends it: inside 0x038C, whose first byte is
/// the 5-bit value 3 of SendWorldMessage (opcode.0x38c), under the session key.
fn world_message(message_id: Int, body: BitArray) -> BitArray {
  keyed_message(0x038C, game_client.world_body(kind: 3, message_id:, body:))
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
        FromStore(
          ForWorld(CharacterLoaded(
            world_character(),
            character_support.epoch(1),
          )),
        ),
      ),
    )
  assert ask_request(taken)
    == AskMap(
      camp_map(),
      Join(ConnectionId(1), world_character(), entry_place()),
    )
    as "the saved world of the character, its one open instance, the connection's id, the character and the place the client is told"
  assert support.writes(taken) == []
    as "nothing is written before the map answers"
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken))))
  assert written_ids(taken) == game_client.world_entry_ids
    as "the order the client needs: 0xAD first; 0x262 before 0x19B; 0x19B before 0x6BC, 0x636 and 0x61 (the client drops 0x6BC until 0x19B has set the player, opcode.0x6bc); 0xF1 after 0xAD (opcode.0xad, opcode.0x19b, opcode.0x6bc, opcode.0x636, opcode.0x61, opcode.0xf1)"
  let after_the_burst = list.drop(support.effects_of(taken), 7)
  assert after_the_burst
    == [
      Watch(WatchId(2), Map(camp_map(), incarnation)),
      OwnEffect(StartTimer(TimerId(2), 60_000)),
    ]
    as "the connection watches the run of the map that holds its player, after the burst, and the save timer starts"
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
        start_movement.Position(UnitPositionCommand(
          x: 0x41E9075F,
          y: 0xC45577C8,
          z: 0xC40C0C08,
          blends: 0,
        )),
        start_movement.Rotation(MovementRotation(
          yaw: 0,
          pitch: 0,
          roll: 0,
          blends: 0,
        )),
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
      #(playing(42), step.Answer(FromMap(a_join_answer()))),
      // The store's answer while the map is asked.
      #(
        joining(),
        step.Answer(
          FromStore(
            ForWorld(CharacterLoaded(
              world_character(),
              character_support.epoch(1),
            )),
          ),
        ),
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
    answer(state:, taken:, outcome: step.Answer(FromMap(a_join_answer())))
  assert disconnect(taken, keyed()) == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn an_unhandled_message_id_is_a_warning_the_first_time_on_a_connection_and_a_debug_line_after_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = read(in_world(), move_message(0x0635))
  let assert [first] = support.logs(taken)
  assert first.level == LogWarning
    as "the first 0x635 of the connection is logged as unhandled, as a warning"
  assert first.about.message == Some(#("unhandled", 0x0635))
  let #(state, taken) = read(state, move_message(0x0635))
  let assert [again] = support.logs(taken)
  assert again.level == step.LogDebug
    as "a repeat of an id already logged is a debug line, since the client sends some messages again and again"
  assert again.about.message == Some(#("unhandled", 0x0635))
  let #(_, taken) = read(state, activity())
  let assert [other] = support.logs(taken)
  assert other.level == LogWarning as "another id is its first: a warning"
}

pub fn a_world_message_carries_one_whole_frame_whose_message_is_logged_under_its_own_id_in_character_select_and_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([in_select(), in_world()], fn(state) {
    let #(_, taken) = read(state, store_request())
    assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x082D))]
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
      let #(state, taken) = read(state, keyed_message(0x038C, body))
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      let taken = case support.asked(taken) {
        None -> taken
        Some(_) -> {
          assert ask_request(taken) == save_asked(1, entry_place())
            as "the player in the world is saved before the connection ends"
          answer(state:, taken:, outcome: place_saved()).1
        }
      }
      assert support.stops(taken)
        as { "opcode.0x38c: " <> what <> " ends the connection" }
    })
  })
}

pub fn a_log_line_in_the_world_is_about_the_players_map_and_character_and_one_in_character_select_is_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), WatchEnded(WatchId(2)))
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.map == Some(camp_map())
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
    line.about.map == Some(camp_map()) && line.about.character_id == Some(42)
  })
    as "the lines of the shared connection code, which log a refused frame, carry them too"
}

pub fn a_watch_the_rule_did_not_open_ending_in_the_world_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), WatchEnded(WatchId(9)))
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.stops(taken)
    as "the player is in the world, so the place is saved before the connection ends"
  let #(_, taken) = feed(in_select_with_a_list(), WatchEnded(WatchId(2)))
  assert support.stops(taken)
    as "the map's watch is open only while the player is in the world"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn the_end_of_sessions_in_the_world_claims_again_and_the_claim_puts_the_player_back_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), WatchEnded(WatchId(1)))
  assert support.effects_of(taken)
    == [
      OwnEffect(CancelTimer(TimerId(2))),
      OwnEffect(StartTimer(TimerId(1), 100)),
    ]
    as "Sessions is likely still restarting, so the claim waits a moment, as in character select; the save timer is cancelled meanwhile"
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
  assert ask_request(taken) == claim_ask()
  let #(state, taken) = claimed(state:, taken:)
  assert support.writes(taken) == []
  // Back in the world: the movement the client sends is read as in the world,
  // and the map's end ends the connection.
  let #(state, taken) = read(state, move_message(0x0635))
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x0635))]
    as "the claim kept where the client is, the player in the world"
  let #(state, taken) = feed(state, WatchEnded(WatchId(2)))
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
    as "the map's watch is still open after the claim"
}

pub fn the_end_of_the_map_while_the_claim_waits_ends_the_connection_with_reason_8_and_a_takeover_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(map_ended, taken) = feed(state, WatchEnded(WatchId(2)))
  let #(_, taken) = answer(state: map_ended, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
    as "the player's map ended while the connection waits to claim again: its place is saved, then the client is told"
  let #(taken_over, taken) = feed(state, taken_over())
  let #(_, taken) = answer(state: taken_over, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == AccountDisconnected
}

pub fn a_map_end_while_character_select_waits_to_claim_is_a_bug_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(_, taken) = feed(state, WatchEnded(WatchId(2)))
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
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
  let #(state, taken) = read(in_world(), second)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.stops(taken)
    as "0x058F is sent once (opcode.0x58f), in the world as in character select; in the world the place is saved first"
  let #(_, taken) = read(in_world(), play_message(42))
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x07DD))]
    as "a play of the client that is in the world already is logged as unhandled, and no store is asked"
  assert support.asked(taken) == None
  assert !support.stops(taken)
}

// ---- the player moves, and the place is saved ----
//
// Expected values come from the Client trace of the move step and the facts it
// names: opcode.0x637 (the message, its kinds, no echo), opcode.0x639 and
// opcode.0x638 (the server writes neither while the player moves),
// movement_command.position_bound, movement_command.kind_24 and kind_27,
// 0x140c45dd0 (the move speed setting), 0x140715350 (kind 14 is yaw, pitch and
// roll), 0x1404586e0 (0x262's kind 2 places the unit and a bit clear places it
// at once), opcode.0xad (the world and position it loads at), and 0x1400168a0
// (0x036A's reasons). The 60 s period, the order of the saves and what a drop
// writes are the step's own design: the Design artifact of the move step and
// its failure table.

/// 0x637 holding `commands`, as the client writes it, under the session key.
fn moves_message(commands: List(movement_command.MovementCommand)) -> BitArray {
  world_message(0x0637, game_client.moves_body(client_clock: 0x1234, commands:))
}

fn platform_command(unit_id: Int) -> movement_command.MovementCommand {
  movement_command.Platform(MovementPlatform(unit_id:))
}

/// A place in World 3460, zone 6009, as `world_character()` has.
fn standing_at(x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
}

/// Where `world_character()` is saved: the place of WorldLocation2 row 51596.
fn entry_place() -> Place {
  standing_at(x: 29.128599166870117, y: -853.87158203125, z: -560.18798828125)
}

/// The ask of a save of the tests' player: the account and character of the
/// tests' connection, the epoch its load gave, the save's number and the place.
fn save_asked(sequence: Int, place: Place) -> Request {
  AskStore(
    Move(SavePlace(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      save_sequence: sequence,
      place:,
    )),
  )
}

/// The store's answer that a place was saved.
fn place_saved() -> Outcome(Answer) {
  step.Answer(FromStore(ForMove(PlaceSaved)))
}

/// The connection after the client moved the player to x, y, z.
fn moved_to(
  state state: game_connection.State,
  x x: Float,
  y y: Float,
  z z: Float,
) -> game_connection.State {
  read(state, moves_message([game_client.position_command(x:, y:, z:)])).0
}

/// The outcomes in which a store ask gets no answer, for a save.
fn no_answers() -> List(Outcome(Answer)) {
  [
    step.Answer(FromStore(Unavailable)),
    NotRunning,
    NoAnswerInTime,
    EndedBeforeAnswer,
  ]
}

pub fn the_client_moving_gets_no_answer_and_every_later_move_is_read_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    read(
      in_world(),
      moves_message([game_client.position_command(x: 1.5, y: 2.5, z: 3.5)]),
    )
  assert support.writes(taken) == []
    as "opcode.0x637: the server sends nothing in answer: no echo, no acknowledgement, no 0x638 for a unit under the client's control and no 0x639, which would end the client's control"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "the rule takes 0x637, so it is no unhandled message"
  let #(state, taken) =
    read(
      state,
      bit_array.concat([
        moves_message([game_client.position_command(x: 2.5, y: 2.5, z: 3.5)]),
        moves_message([game_client.position_command(x: 3.5, y: 2.5, z: 3.5)]),
        support.ping(1),
      ]),
    )
  assert support.writes(taken) == [support.pong(1)]
    as "each move is read, and only the ping is answered"
  assert support.logs(taken) == []
  let #(_, taken) = feed(state, step.OwnEvent(step.PeerClosed))
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 3.5, y: 2.5, z: 3.5))
    as "the moves were all read: the last one is where the player stands"
}

pub fn the_place_kept_is_the_last_world_position_and_a_platforms_frame_is_not_kept_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    read(
      in_world(),
      bit_array.concat([
        moves_message([game_client.position_command(x: 5.5, y: 6.5, z: 7.5)]),
        moves_message([
          platform_command(9),
          game_client.position_command(x: 100.0, y: 100.0, z: 100.0),
        ]),
        moves_message([
          game_client.position_command(x: 200.0, y: 200.0, z: 200.0),
        ]),
      ]),
    ).0
  let #(_, taken) = feed(state, step.OwnEvent(step.PeerClosed))
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 5.5, y: 6.5, z: 7.5))
    as "opcode.0x637: a kind 2 under a platform is in that unit's frame, and the client sends only what changed, so the next message's kind 2 is under the platform still"
  let state =
    read(
      state,
      moves_message([
        platform_command(0),
        game_client.position_command(x: 8.5, y: 9.5, z: 10.5),
        game_client.rotation_command(yaw: 1.5, pitch: -0.25, roll: 0.5),
      ]),
    ).0
  let #(_, taken) = feed(state, step.OwnEvent(step.PeerClosed))
  assert ask_request(taken)
    == save_asked(
      1,
      start_place.turned(
        standing_at(x: 8.5, y: 9.5, z: 10.5),
        Facing(yaw: 1.5, pitch: -0.25, roll: 0.5),
      ),
    )
    as "kind 1 at 0 is the world's frame again: the position and the rotation are kept"
}

pub fn a_position_beyond_the_worlds_box_is_kept_as_the_client_sent_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = moved_to(state: in_world(), x: 40_000.0, y: 3000.0, z: -40_000.0)
  let #(_, taken) = feed(state, step.OwnEvent(step.PeerClosed))
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 40_000.0, y: 3000.0, z: -40_000.0))
    as "movement_command.position_bound: x and z beyond 32768 and y above 2048 come from the client's own frames at the edge, so they are kept as sent"
}

/// A message the client's code never sends, with what makes it so.
fn refused_messages() -> List(#(BitArray, String)) {
  let not_a_number = 0x7FC00000
  let infinity = 0x7F800000
  let position_of = fn(x, y, z) {
    movement_command.Position(UnitPositionCommand(x:, y:, z:, blends: 0))
  }
  let zero = 0
  let one = 0x3F800000
  [
    #(
      moves_message([position_of(not_a_number, one, one)]),
      "a position that is not a number",
    ),
    #(moves_message([position_of(one, infinity, one)]), "a height of infinity"),
    #(moves_message([position_of(zero, 0xFF800000, zero)]), "minus infinity"),
    #(
      moves_message([game_client.position_command(x: 0.0, y: -2048.5, z: 0.0)]),
      "a height below -2048",
    ),
    #(
      moves_message([
        movement_command.Rotation(MovementRotation(
          yaw: one,
          pitch: not_a_number,
          roll: one,
          blends: 0,
        )),
      ]),
      "a rotation that is not a number",
    ),
    #(
      moves_message([
        movement_command.StateFlags(MovementStateFlags(flags: 0x40000)),
      ]),
      "state flags above 0x3ffff",
    ),
    #(
      moves_message([movement_command.Mode(MovementMode(mode: 2))]),
      "a mode other than 0, 1 and 3",
    ),
    #(world_message(0x063B, <<3, 0, 0, 0>>), "a move speed setting above 2"),
    #(
      moves_message([
        game_client.position_command(x: 99.0, y: 99.0, z: 99.0),
        position_of(one, not_a_number, one),
      ]),
      "a refused command after a good one, of which nothing is kept",
    ),
  ]
}

pub fn a_command_the_clients_code_never_sends_ends_the_connection_after_saving_the_last_good_place_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = moved_to(state: in_world(), x: 7.5, y: 8.5, z: 9.5)
  list.each(refused_messages(), fn(refused) {
    let #(bytes, what) = refused
    let #(refusing, taken) = read(state, bytes)
    let assert [line] = support.logs_of(step: taken, level: LogError)
      as { what <> ": one error line says what the client sent" }
    assert line.about.account_id == Some(7)
      && line.about.character_id == Some(42)
      as "and whose it is"
    assert ask_request(taken)
      == save_asked(1, standing_at(x: 7.5, y: 8.5, z: 9.5))
      as {
        what
        <> ": the last good place is saved, and nothing of the message is kept"
      }
    assert support.writes(taken) == []
      as "nothing is written to a client that sent what its own code never does"
    assert !support.stops(taken)
      as "the connection ends once the save is answered"
    let #(_, taken) = answer(state: refusing, taken:, outcome: place_saved())
    assert support.effects_of(taken) == [step.Stop]
      as {
        what <> ": the save answered, the connection ends with nothing written"
      }
  })
}

/// The bodies of the messages the rule decodes and keeps nothing of.
fn decoded_and_dropped() -> List(#(Int, BitArray)) {
  let assert Ok(zone) =
    zone_value_changed.encode(ZoneValueChanged(old_value: 6009, new_value: 6010))
  let assert Ok(interval) =
    movement_send_interval_answer.encode(MovementSendIntervalAnswer(
      field_1: 4,
      field_2: 1,
      field_3: 14,
    ))
  let assert Ok(speed) =
    move_speed_setting.encode(MoveSpeedSetting(move_speed: 2))
  let assert Ok(terrain) = terrain_loaded.encode(TerrainLoaded(field_1: 6009))
  let assert Ok(fall) = fall_value.encode(FallValue(field_1: 0x40490FDB))
  let assert Ok(floor) =
    fell_below_floor.encode(FellBelowFloor(
      no_ground: 1,
      camera_x: 0x3F800000,
      camera_y: 0x40000000,
      camera_z: 0xC0400000,
    ))
  [
    #(0x063A, zone),
    #(0x00D5, interval),
    #(0x063B, speed),
    #(0x00F2, terrain),
    #(0x00FB, fall),
    #(0x00FC, floor),
  ]
}

pub fn the_clients_0x063a_0x00d5_0x063b_0x00f2_0x00fb_and_0x00fc_are_decoded_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(decoded_and_dropped(), fn(message) {
    let #(message_id, body) = message
    let #(state, taken) = read(in_world(), world_message(message_id, body))
    assert support.logs(taken) == []
      as "opcode.0x63a, opcode.0xd5, opcode.0x63b, opcode.0xf2, opcode.0xfb and opcode.0xfc: the rule takes each, so none is logged as unhandled"
    assert support.writes(taken) == [] && support.asked(taken) == None
    assert !support.stops(taken) as "none ends the connection"
    let #(_, taken) = read(state, support.ping(1))
    assert support.writes(taken) == [support.pong(1)]
      as "the connection goes on"
  })
}

pub fn a_body_of_one_of_the_movement_messages_that_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(state, taken) = read(in_world(), world_message(id, <<>>))
    let assert [line] = support.logs_of(step: taken, level: LogError)
      as "an empty body is shorter than any of the messages' fields"
    assert support.says(line:, words: "does not decode")
    assert ask_request(taken) == save_asked(1, entry_place())
      as "the player is in the world, so its place is saved before the connection ends"
    let #(_, taken) = answer(state:, taken:, outcome: place_saved())
    assert support.effects_of(taken) == [step.Stop]
  })
}

pub fn the_movement_messages_before_the_world_are_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(_, taken) =
      read(in_select_with_a_list(), world_message(id, <<0, 0, 0, 0>>))
    assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
      as "no player is in the world in character select, so there is no place to keep: the message is logged as unhandled as before"
    assert !support.stops(taken)
  })
}

pub fn a_movement_message_sent_on_its_own_and_not_inside_0x038c_is_logged_as_unhandled_even_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(_, taken) = read(in_world(), move_message(id))
    assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
      as "opcode.0x38c, opcode.0x637: the client sends every world message inside 0x038C and no other way, so one on its own is no message the rule takes"
    assert !support.stops(taken) && support.asked(taken) == None
  })
}

pub fn the_clients_0x0635_is_still_logged_as_unhandled_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = read(in_world(), world_message(0x0635, <<0, 0, 0, 0>>))
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x0635))]
    as "opcode.0x635 answers 0x636 and is no part of the move step"
  assert !support.stops(taken)
}

// ---- the login places the player ----

/// A character saved at `entry_place()` facing yaw 1.5, pitch -0.25, roll 0.5.
fn turned_character() -> store.Character {
  store.Character(
    ..world_character(),
    place: Some(start_place.turned(
      entry_place(),
      Facing(yaw: 1.5, pitch: -0.25, roll: 0.5),
    )),
  )
}

pub fn the_login_places_the_player_at_the_saved_place_and_turns_it_the_saved_way_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = entered_as(turned_character())
  let assert [Frame(message_id: 0x00AD, body:), ..] = heard(taken, keyed())
  let assert Ok(entering) = enter_world.decode(body)
  assert entering.position_x == 0x41E9075F
    && entering.position_y == 0xC45577C8
    && entering.position_z == 0xC40C0C08
    as "opcode.0xad: the world loads at the saved position"
  assert player_in(taken).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0x41E9075F,
        y: 0xC45577C8,
        z: 0xC40C0C08,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0x3FC00000,
        pitch: 0xBE800000,
        roll: 0x3F000000,
        blends: 0,
      )),
    ]
    as "0x1404586e0, 0x140715350: kind 2 at the saved position with its bit clear, which places the unit at once, then kind 14 with the saved yaw, pitch and roll (1.5 is 0x3FC00000, -0.25 is 0xBE800000, 0.5 is 0x3F000000)"
}

pub fn a_saved_position_beyond_the_worlds_box_is_written_as_the_boxs_edge_in_0xad_and_0x262_and_saved_as_it_was_test() -> Nil {
  use <- owned_test.run(10_000)
  let far = standing_at(x: 1.0e9, y: 5000.0, z: -1.0e9)
  let #(state, taken) =
    entered_as(Character(..world_character(), place: Some(far)))
  let assert [Frame(message_id: 0x00AD, body:), ..] = heard(taken, keyed())
  let assert Ok(entering) = enter_world.decode(body)
  assert #(entering.position_x, entering.position_y, entering.position_z)
    == #(0x47000000, 0x45000000, 0xC7000000)
    as "opcode.0xad.position: LoadWorld keeps the position as sent, so the server writes the box the client bounds a unit's position to (0x1405b5070, bounds 32768.0 = 0x47000000 and 2048.0 = 0x45000000): x and z within 32768, y within 2048"
  assert list.first(player_in(taken).movement_commands)
    == Ok(
      start_movement.Position(UnitPositionCommand(
        x: 0x47000000,
        y: 0x45000000,
        z: 0xC7000000,
        blends: 0,
      )),
    )
    as "0x1405b5070: the client draws the unit within the box, so the position written into 0x262 is the box's edge"
  let #(_, taken) = feed(state, step.OwnEvent(step.PeerClosed))
  assert ask_request(taken) == save_asked(1, far)
    as "the place the character is saved at stays as the database held it; only what the client is sent is bounded"
}

pub fn a_character_never_saved_still_gets_a_position_at_its_start_place_and_faces_0_0_0_test() -> Nil {
  use <- owned_test.run(10_000)
  assert player_in(entered().1).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0x41E9075F,
        y: 0xC45577C8,
        z: 0xC40C0C08,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ]
    as "0x1404586e0: without a kind 2 the unit stands at 0, 0, 0, so even a character with no save gets its start place; its facing is 0, 0, 0"
}

// ---- every 60 s ----

pub fn the_save_timer_starts_when_the_player_enters_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.contains(
    support.effects_of(entered().1),
    OwnEffect(StartTimer(TimerId(2), 60_000)),
  )
    as "a save every 60 s from the moment the player is in the world"
}

pub fn every_60_seconds_the_last_known_position_is_saved_also_when_no_move_came_since_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
    as "the timer starts again at its firing"
  assert ask_request(taken) == save_asked(1, entry_place())
    as "opcode.0x637: a player standing still sends no 0x637, so the save writes the last place known, the one it entered at"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
  let #(state, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.effects_of(taken) == [] && support.asked(taken) == None
    as "a saved place needs nothing more: the player goes on playing"
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert ask_request(taken) == save_asked(2, entry_place())
    as "the second save of the login is numbered 2"
  let #(state, _) = answer(state:, taken:, outcome: place_saved())
  let state = moved_to(state: state, x: 1.5, y: 2.5, z: 3.5)
  let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert ask_request(taken)
    == save_asked(3, standing_at(x: 1.5, y: 2.5, z: 3.5))
    as "a move since the last save is in the next"
}

pub fn a_frame_that_arrives_while_the_save_is_out_waits_and_is_taken_after_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  let #(state, held) = read(state, support.ping(4))
  assert support.writes(held) == [] as "the ask is out: the frame waits"
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.writes(taken) == [support.pong(4)]
    as "taken once the answer comes, in the order it arrived"
}

pub fn a_60_s_save_the_store_cannot_make_is_a_warning_the_player_goes_on_and_the_next_timer_asks_again_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(no_answers(), fn(outcome) {
    let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
    let #(state, taken) = answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "an outside failure the server recovered from"
    assert line.about.account_id == Some(7)
      && line.about.character_id == Some(42)
      && line.about.map == Some(camp_map())
      as "the line says who and where"
    assert !support.stops(taken) && support.writes(taken) == []
      as "the player stays in the world"
    let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(2))))
    assert ask_request(taken) == save_asked(2, entry_place())
      as "the next timer tries again, with the next number"
  })
}

pub fn a_60_s_save_that_changed_nothing_is_an_info_line_and_one_the_database_refused_is_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  let #(_, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForMove(NothingSaved))),
    )
  let assert [line] = support.logs(taken)
  assert line.level == LogInfo
    as "a later login holds the character, or a newer save of this one was stored first: nothing is wrong"
  assert !support.stops(taken)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForMove(PlaceRefused))),
    )
  let assert [line] = support.logs(taken)
  assert line.level == LogError
    as "no place the rule keeps breaks a check, so a refusal is a bug"
  assert !support.stops(taken)
  let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert support.asked(taken) != None
    as "the player goes on, and the timer tries again"
}

pub fn a_stop_during_the_60_s_save_leaves_the_player_in_the_world_and_the_stop_that_follows_saves_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  let #(state, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert support.effects_of(taken) == [] && !support.stops(taken)
    as "the shell's next input is Stopping, which says what the stop does"
  let #(_, taken) = feed(state, step.Stopping(deadline_ms: 9000))
  assert ask_request(taken) == save_asked(2, entry_place())
    as "the save the stop cut short may have committed or not: the stop saves once more, with the next number"
}

pub fn a_drop_taken_after_a_60_s_save_saves_again_with_the_next_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
  let #(state, _) = answer(state:, taken:, outcome: place_saved())
  let #(_, taken) = feed(state, OwnEvent(step.PeerClosed))
  assert ask_request(taken) == save_asked(2, entry_place())
    as "the shell took the client's close after the save's answer: the drop saves, numbered after the timer's save"
}

/// The answers a save never gets: those of another group of asks.
fn answers_to_other_asks() -> List(Outcome(Answer)) {
  [
    step.Answer(FromStore(ForSelect(Listed([])))),
    step.Answer(FromStore(ForWorld(NotTheAccounts))),
    step.Answer(FromHandOff(NoHolder)),
    step.Answer(FromSessions(Claimed)),
    step.Answer(FromMap(a_join_answer())),
  ]
}

pub fn an_answer_that_is_none_a_save_asked_for_is_a_bug_with_reason_8_and_an_error_and_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(answers_to_other_asks(), fn(outcome) {
    let #(state, taken) = feed(in_world(), OwnEvent(TimerFired(TimerId(2))))
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the save is over: a bug ends the connection without saving again"
    let #(state, taken) = feed(in_world(), step.Stopping(deadline_ms: 9000))
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
    assert support.asked(taken) == None
  })
}

// ---- every drop saves ----

/// The socket's ends the shell gives the rule, with the log lines each makes
/// before the save.
fn socket_ends() -> List(#(Event(ConnectionEvent(Message, Answer)), Int)) {
  [
    #(OwnEvent(step.PeerClosed), 0),
    #(OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "broken"))), 1),
    #(OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "broken"))), 1),
  ]
}

pub fn a_client_close_or_a_failed_read_or_write_saves_the_last_place_then_ends_with_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(socket_ends(), fn(socket_end) {
    let #(event, warnings) = socket_end
    let state = moved_to(state: in_world(), x: 7.5, y: 8.5, z: 9.5)
    let #(state, taken) = feed(state, event)
    assert ask_request(taken)
      == save_asked(1, standing_at(x: 7.5, y: 8.5, z: 9.5))
      as "the place the player last stood at is saved when the connection drops"
    assert !support.stops(taken) && support.writes(taken) == []
    assert list.length(support.logs_of(step: taken, level: LogWarning))
      == warnings
      as "a failed socket is a warning, a client's own close is not"
    let #(_, taken) = answer(state:, taken:, outcome: place_saved())
    assert support.effects_of(taken) == [step.Stop]
      as "nothing is written to a client that is gone, and no more is logged"
  })
}

pub fn a_drop_the_store_cannot_save_is_a_warning_and_the_connection_ends_anyway_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(no_answers(), fn(outcome) {
    let #(state, taken) = feed(in_world(), OwnEvent(step.PeerClosed))
    let #(_, taken) = answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.character_id == Some(42)
    assert support.stops(taken) && support.writes(taken) == []
      as "the last 60 s save stands: the connection ends, a store that is away does not keep it open"
  })
  let #(state, taken) = feed(in_world(), OwnEvent(step.PeerClosed))
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert support.stops(taken) && support.logs(taken) == []
    as "the server stopping is no failure: no warning"
}

pub fn a_takeover_in_the_world_saves_the_place_then_writes_0x036a_reason_19_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = moved_to(state: in_world(), x: 7.5, y: 8.5, z: 9.5)
  let #(state, taken) = feed(state, taken_over())
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 7.5, y: 8.5, z: 9.5))
    as "a newer login took the account: the older connection saves at its own epoch, which changes nothing once the newer login has loaded the character"
  assert support.writes(taken) == [] && !support.stops(taken)
    as "the notice is written after the save"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
  assert line.about.account_id == Some(7)
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == AccountDisconnected
    as "0x1400168a0: 19 is 'This account has been disconnected'"
  assert support.logs(taken) == []
}

pub fn the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), WatchEnded(WatchId(2)))
  assert ask_request(taken) == save_asked(1, entry_place())
  assert support.writes(taken) == [] && !support.stops(taken)
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.map == Some(camp_map())
  let #(_, taken) = answer(state:, taken:, outcome: NoAnswerInTime)
  assert disconnect(taken, keyed()) == LostUserServer
    as "the player is gone from the world with its map: the client is told whether or not the save was answered"
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
    as "a save with no answer is a warning of its own"
}

pub fn a_notice_that_fails_to_write_after_the_leaving_save_does_not_save_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), taken_over())
  let #(state, _) = answer(state:, taken:, outcome: place_saved())
  let #(_, taken) =
    feed(state, OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))))
  assert support.asked(taken) == None
    as "the leaving save was answered: the failed write of the notice ends the connection and saves nothing again"
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
}

pub fn an_end_reached_while_a_save_is_out_never_saves_a_second_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), OwnEvent(step.PeerClosed))
  list.each(
    [
      OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "gone"))),
      OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))),
      OwnEvent(step.PeerClosed),
      step.Stopping(deadline_ms: 9000),
      taken_over(),
      WatchEnded(WatchId(2)),
    ],
    fn(event) {
      let #(_, taken) = feed(state, event)
      assert support.asked(taken) == None
        as "the connection is already leaving, with its save out: no second save is asked"
      assert support.stops(taken)
    },
  )
}

pub fn the_rate_and_the_held_bytes_limits_end_the_connection_in_the_world_without_a_save_test() -> Nil {
  use <- owned_test.run(10_000)
  // The last 60 s save stands: a client past a limit is no client, and the
  // limits end the connection inside the shared client connection code.
  let state =
    entered_from(
      in_select_from(
        accepted(
          Settings(..settings(), rate: support.bucket(burst: 10, per_second: 1)),
        ).0,
      ),
      world_character(),
    ).0
  let #(state, taken) = read(state, support.pings(count: 8))
  assert !support.stops(taken)
  let #(_, taken) = read(state, support.ping(8))
  assert support.stops(taken) && support.asked(taken) == None
    as "a frame past the rate ends the connection and asks nothing"
  let #(_, taken) = read(in_world(), <<0:size({ support.held_limit + 1 } * 8)>>)
  assert support.stops(taken) && support.asked(taken) == None
    as "bytes past the held limit end it the same way"
}

/// A 0x0244 whose body is no frame under the session key.
fn bad_wrapper() -> BitArray {
  let assert Ok(bytes) = frame.encode(0x0244, <<1, 2, 3>>)
    as "a wrapper's frame encodes"
  bytes
}

pub fn every_other_end_with_the_player_in_the_world_saves_first_test() -> Nil {
  use <- owned_test.run(10_000)
  let breaks = [
    #(
      read(in_world(), keyed_message(0x058F, <<>>)),
      "0x058F sent a second time",
    ),
    #(
      read(in_world(), keyed_message(0x038C, <<>>)),
      "a world message with no kind byte",
    ),
    #(read(in_world(), bad_wrapper()), "a wrapped frame that is no frame"),
    #(
      read(in_world(), <<0xFF, 0xFF, 0x01, 0x00>>),
      "a frame of a length no frame has",
    ),
    #(feed(in_world(), WatchEnded(WatchId(9))), "a watch the rule did not open"),
    #(
      feed(in_world(), OwnEvent(TimerFired(TimerId(3)))),
      "a timer the rule did not start",
    ),
    #(
      feed(
        in_world(),
        OwnEvent(step.Answered(ask: step.AskId(99), outcome: NoAnswerInTime)),
      ),
      "an answer when no ask was out",
    ),
  ]
  list.each(breaks, fn(broken) {
    let #(#(state, taken), what) = broken
    assert ask_request(taken) == save_asked(1, entry_place())
      as {
        what <> ": the connection holds a player, so its place is saved first"
      }
    assert support.writes(taken) == [] && !support.stops(taken)
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      as "and one error line says what the client did"
    let #(_, taken) = answer(state:, taken:, outcome: place_saved())
    assert support.effects_of(taken) == [step.Stop]
      as { what <> ": nothing is written to a client that is no client" }
  })
}

// ---- the stop ----

pub fn the_server_stopping_in_the_world_saves_within_the_stops_deadline_then_tells_the_client_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), step.Stopping(deadline_ms: 9000))
  assert ask_request(taken) == save_asked(1, entry_place())
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the ask's own deadline is the shorter: 4000 ms against the 8000 ms the stop leaves"
  assert support.writes(taken) == [] && !support.stops(taken)
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
    as "the save answered, the client is told 0x036A reason 8, as before"
  assert support.logs(taken) == [] as "a stop is no failure"
  let #(_, taken) = feed(in_world(), step.Stopping(deadline_ms: 3000))
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == 3000
    as "a stop that leaves less than the ask's deadline bounds the save: it must be done by the stop's own deadline"
}

pub fn a_stop_whose_deadline_has_passed_skips_the_save_tells_the_client_and_ends_with_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([support.now_ms, support.now_ms - 500], fn(deadline_ms) {
    let #(_, taken) = feed(in_world(), step.Stopping(deadline_ms:))
    assert support.asked(taken) == None
      as "no time is left to ask: an ask with a deadline that has passed would only be waited for"
    assert disconnect(taken, keyed()) == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
      as "the place is not saved by this stop, and the warning says so"
  })
}

pub fn a_save_at_shutdown_the_store_cannot_make_is_a_warning_and_the_client_is_still_told_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(no_answers(), fn(outcome) {
    let #(state, taken) = feed(in_world(), step.Stopping(deadline_ms: 9000))
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
  })
  let #(state, taken) = feed(in_world(), step.Stopping(deadline_ms: 9000))
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
  assert support.logs(taken) == []
}

pub fn a_stop_while_the_connection_waits_to_claim_again_saves_then_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, step.Stopping(deadline_ms: 9000))
  assert ask_request(taken) == save_asked(1, entry_place())
    as "the player is in the world still, whatever the claim is doing"
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
}

pub fn a_stop_that_interrupts_the_claim_with_the_player_in_the_world_goes_back_to_the_world_and_the_stop_that_follows_saves_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert ask_request(taken) == claim_ask()
  let #(state, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert !support.stops(taken) && support.writes(taken) == []
    as "the claim is cut short by the stop, with nothing told: the shell's next input is Stopping"
  let #(state, taken) = feed(state, step.Stopping(deadline_ms: 9000))
  assert ask_request(taken) == save_asked(1, entry_place())
    as "a player in the world is saved by the stop whatever the claim was doing"
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
}

// ---- the save timer and the claim ----

pub fn the_save_timer_is_cancelled_while_the_connection_claims_again_and_started_on_the_claim_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(in_world(), WatchEnded(WatchId(1)))
  assert support.effects_of(taken)
    == [
      OwnEffect(CancelTimer(TimerId(2))),
      OwnEffect(StartTimer(TimerId(1), 100)),
    ]
    as "the save timer is cancelled with the claim's wait, so no save fires while the claim is out; a firing already queued is dropped by the shell"
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) = claimed(state:, taken:)
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
    as "the claim answered, the player is in the world and the save timer runs again"
  let state = moved_to(state: state, x: 4.5, y: 5.5, z: 6.5)
  let #(_, taken) = feed(state, OwnEvent(step.PeerClosed))
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 4.5, y: 5.5, z: 6.5))
    as "the claim kept where the player stands"
}

pub fn a_claim_that_finds_sessions_not_running_keeps_the_save_timer_cancelled_until_it_is_claimed_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) = answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), 100))]
    as "the claim is made again after a wait, and the save timer is not started in between"
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(_, taken) = claimed(state:, taken:)
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
}

pub fn a_save_timer_that_fires_while_the_connection_claims_again_is_a_bug_that_saves_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) = feed(in_world(), WatchEnded(WatchId(1)))
  let #(claiming, _) = feed(waiting, OwnEvent(TimerFired(TimerId(1))))
  list.each([waiting, claiming], fn(state) {
    let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(2))))
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert ask_request(taken) == save_asked(1, entry_place())
      as "the player is in the world, so even this end saves"
    let #(_, taken) = answer(state:, taken:, outcome: place_saved())
    assert support.effects_of(taken) == [step.Stop]
  })
}

pub fn the_save_timer_firing_in_character_select_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    feed(in_select_with_a_list(), OwnEvent(TimerFired(TimerId(2))))
  assert support.stops(taken) && support.asked(taken) == None
    as "no player is in the world, so no save timer runs, and there is nothing to save"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
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
fn deleting(
  character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  read(in_select(), delete_message(character_id))
}

/// The connection after a rename request, with its ask to the store.
fn renaming(
  character_id: Int,
  name: String,
) -> #(game_connection.State, ConnectionStep(Request)) {
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
// `genesis_prime/account_session`. The wait is 100 ms and the retries of a claim that
// finds Sessions not running are 5, as the rule's constants state.

/// The wait, in milliseconds, before a claim is made again.
const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
const claim_retries = 5

fn taken_over() -> Event(ConnectionEvent(Message, Answer)) {
  OwnEvent(Woken(message: SentBySessions(message: TakenOver)))
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

/// A step that ended the connection as a takeover does: 0x036A reason 19 under
/// the connection's cipher (0x1400168a0: 19 is 'This account has been
/// disconnected', the account-level text), one info line naming the connection
/// and the account, no ask, and no warning or error.
fn assert_taken_over(taken: ConnectionStep(Request)) -> Nil {
  assert disconnect(taken, keyed()) == AccountDisconnected
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once"
  assert line.about.connection == Some(ConnectionId(1))
    && line.about.account_id == Some(7)
    as "the line names the connection and the account"
  assert support.asked(taken) == None
  assert support.logs_of(step: taken, level: LogWarning) == []
  assert support.logs_of(step: taken, level: LogError) == []
}

pub fn a_connection_given_taken_over_writes_0x036a_reason_19_under_its_cipher_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_select_with_a_list(), taken_over())
  assert_taken_over(taken)
}

pub fn a_claim_answered_taken_over_ends_the_connection_as_a_takeover_does_test() -> Nil {
  use <- owned_test.run(10_000)
  // A newer login holds the slot: Sessions answers the claim `TakenOver`, for
  // a first claim and for a claim made again after Sessions ended in
  // character select.
  let #(state, taken) = claiming()
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromSessions(TakenOver)))
  assert_taken_over(taken)
  let #(state, taken) = claiming_again(in_select_with_a_list())
  let #(_, taken) =
    answer(state:, taken:, outcome: step.Answer(FromSessions(TakenOver)))
  assert_taken_over(taken)
}

/// The connection `held` after Sessions ended and the wait ran out: the claim
/// is out again.
fn claiming_again(
  held: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, _) = feed(held, WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert ask_request(taken) == claim_ask()
  #(state, taken)
}

pub fn a_claim_made_again_in_the_world_and_answered_taken_over_saves_the_place_then_tells_the_client_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = claiming_again(in_world())
  let #(state, taken) =
    answer(state:, taken:, outcome: step.Answer(FromSessions(TakenOver)))
  assert ask_request(taken) == save_asked(1, entry_place())
    as "a player in the world is saved before the client is told"
  assert support.writes(taken) == [] as "the notice follows the save's answer"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once, with the ask"
  assert line.about.account_id == Some(7)
  let #(_, saved) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(saved, keyed()) == AccountDisconnected
  assert support.logs(saved) == []
}

pub fn a_claim_made_again_in_the_world_that_sessions_does_not_answer_saves_the_place_then_tells_the_client_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = claiming_again(in_world())
    let #(state, taken) = answer(state:, taken:, outcome:)
    assert ask_request(taken) == save_asked(1, entry_place())
      as "a player in the world is saved before the client is told"
    assert support.writes(taken) == [] as "the notice follows the save's answer"
    let #(_, saved) = answer(state:, taken:, outcome: place_saved())
    assert disconnect(saved, keyed()) == LostUserServer
  })
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
  let answer_as_a_message =
    OwnEvent(Woken(message: SentBySessions(message: Claimed)))
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
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
    as "Sessions is likely still restarting, so the claim waits a moment"
  assert support.asked(taken) == None
  // Bytes that arrive during the wait are kept for after the claim.
  let #(state, taken) = read(state, select_start())
  assert support.asked(taken) == None && support.effects_of(taken) == []
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    as "the ended watch is forgotten, so the one watch is opened again under its id"
  assert ask_request(taken) == claim_ask()
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(_, taken) = claimed(state:, taken:)
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "Claimed puts the connection back in character select with its state, and the 0x07E0 that waited is taken"
}

pub fn bytes_past_the_hold_limit_while_the_claim_waits_end_the_connection_with_an_error_and_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let waiting_on_the_timer =
    feed(in_select_with_a_list(), WatchEnded(WatchId(1))).0
  let claim_out = claiming().0
  list.each([waiting_on_the_timer, claim_out], fn(state) {
    let #(state, taken) = read(state, <<0:size(support.held_limit * 8)>>)
    assert !support.stops(taken)
      as "bytes up to the limit are kept for after the claim"
    let #(_, taken) = read(state, <<0>>)
    assert support.stops(taken)
      as "one byte past the limit is more than a whole frame and a read can hold"
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.writes(taken) == []
      as "a connection that sends no frame is no client, so it is told nothing"
    assert support.asked(taken) == None
  })
}

pub fn a_frame_one_byte_over_131070_ends_the_connection_with_an_error_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // The length field counts the whole frame, little-endian: 131,070 is fe ff
  // 01 00 and 131,071 ff ff 01 00 (MessageSizeLimit 0x140335ec0).
  let #(_, taken) = read(connected(), <<0xFE, 0xFF, 0x01, 0x00, 0, 0>>)
  assert !support.stops(taken)
    as "a frame of 131,070 bytes is the biggest the client's reader takes, so the connection waits for the rest"
  let #(_, taken) = read(connected(), <<0xFF, 0xFF, 0x01, 0x00, 0, 0>>)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.writes(taken) == []
    as "a client whose frame the client's own reader would refuse is told nothing"
  let #(_, taken) = read(connected(), <<0xFF, 0xFF, 0x01, 0x00>>)
  assert support.stops(taken)
    as "the length is refused as soon as its four bytes are here, before the frame's bytes are waited for"
}

fn read_at(
  state state: game_connection.State,
  ms ms: Int,
  bytes bytes: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(ms:, event: OwnEvent(step.Read(bytes))),
  )
}

pub fn a_full_burst_of_frames_is_taken_and_one_more_in_the_same_millisecond_ends_the_connection_with_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    accepted(
      Settings(..settings(), rate: support.bucket(burst: 5, per_second: 2)),
    ).0
  let #(state, taken) = read(state, support.pings(count: 5))
  assert support.writes(taken)
    == [
      support.pong(0),
      support.pong(1),
      support.pong(2),
      support.pong(3),
      support.pong(4),
    ]
    as "a connection that has sent nothing holds a full bucket of 5 frames, and each is answered"
  assert !support.stops(taken)
  let #(_, taken) = read(state, support.ping(5))
  assert support.stops(taken)
  assert support.writes(taken) == []
    as "the frame past the rate is not answered"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line:, words: "faster")
  assert support.logs_of(step: taken, level: LogError) == []
    as "a client that sends too fast is an outside failure the server recovers from, a warning"
  // A client that waited a long time has the burst again and no more.
  let #(state, taken) =
    read_at(
      state: accepted(
        Settings(..settings(), rate: support.bucket(burst: 5, per_second: 2)),
      ).0,
      ms: support.now_ms + 3_600_000,
      bytes: support.pings(count: 5),
    )
  assert list.length(support.writes(taken)) == 5 && !support.stops(taken)
  let #(_, taken) =
    read_at(state:, ms: support.now_ms + 3_600_000, bytes: support.ping(5))
  assert support.stops(taken)
    as "an hour of waiting does not store more than the burst"
}

pub fn the_bucket_refills_exactly_with_no_drift_over_10000_frames_sent_at_exactly_the_rate_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3 frames a second: a frame is due every 333 1/3 ms, which no whole
  // millisecond holds, so a bucket that rounds each refill drifts. Frame k is
  // sent at the first whole millisecond by which k/3 of a second has passed.
  let state =
    accepted(
      Settings(..settings(), rate: support.bucket(burst: 2, per_second: 3)),
    ).0
  let start = support.now_ms
  let #(state, taken) =
    read_at(state:, ms: start, bytes: support.pings(count: 2))
  assert list.length(support.writes(taken)) == 2 && !support.stops(taken)
    as "the burst of 2 empties the bucket"
  let due = fn(k) { start + { k * 1000 + 2 } / 3 }
  let state =
    int.range(from: 1, to: 10_001, with: state, run: fn(state, k) {
      let #(state, taken) =
        read_at(state:, ms: due(k), bytes: support.ping(k % 20))
      assert support.writes(taken) == [support.pong(k)]
        as "a frame sent at exactly the rate is taken, however many came before"
      assert !support.stops(taken)
      state
    })
  let #(_, taken) = read_at(state:, ms: due(10_001) - 1, bytes: support.ping(0))
  assert support.stops(taken)
    as "a frame one millisecond before it is due is refused: no frame is let through early either"
}

pub fn an_input_with_an_earlier_time_credits_no_time_twice_test() -> Nil {
  use <- owned_test.run(10_000)
  // 100 a second is one frame every 10 ms. The bucket holds 3, which it is
  // full of at the hello, at `start`.
  let start = support.now_ms
  let state =
    accepted(
      Settings(..settings(), rate: support.bucket(burst: 3, per_second: 100)),
    ).0
  // Times 10 ms on, then 10 ms back, then 10 ms on again: the clock never goes
  // back, but an input is given its time as the shell read it, and a rule that
  // is given an earlier one must not count the same 10 ms twice.
  let #(state, taken) = read_at(state:, ms: start + 10, bytes: support.ping(0))
  assert support.writes(taken) == [support.pong(0)]
  let #(state, taken) = read_at(state:, ms: start, bytes: support.ping(1))
  assert support.writes(taken) == [support.pong(1)]
  let #(state, taken) = read_at(state:, ms: start + 10, bytes: support.ping(2))
  assert support.writes(taken) == [support.pong(2)]
  let #(_, taken) = read_at(state:, ms: start + 10, bytes: support.ping(3))
  assert support.stops(taken)
    as "3 frames were sent and the bucket held 3; the 10 ms between the first and the last input is credited once, and the bucket was already full then"
}

pub fn frames_sent_byte_by_byte_or_in_one_read_are_refused_at_the_same_frame_test() -> Nil {
  use <- owned_test.run(10_000)
  let rate = support.bucket(burst: 4, per_second: 1)
  let bytes = support.pings(count: 7)
  let #(_, whole) = read(accepted(Settings(..settings(), rate:)).0, bytes)
  let answered = [
    support.pong(0),
    support.pong(1),
    support.pong(2),
    support.pong(3),
  ]
  assert support.writes(whole) == answered
    as "the 4 frames of the burst are answered and the 5th ends the connection"
  assert support.stops(whole)
  let #(fed, written) =
    fed_byte_by_byte(
      state: accepted(Settings(..settings(), rate:)).0,
      bytes:,
      fed: 0,
      written: [],
    )
  assert written == answered
    as "the same frames are answered however the bytes were split"
  assert fed == 5 * 7
    as "a ping is 7 bytes: the 5th frame ends the connection on its last byte, and no earlier"
}

/// Feeds the bytes one at a time until a step stops the connection: how many
/// bytes were fed and the writes of every step, in order.
fn fed_byte_by_byte(
  state state: game_connection.State,
  bytes bytes: BitArray,
  fed fed: Int,
  written written: List(BitArray),
) -> #(Int, List(BitArray)) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let #(state, taken) = read(state, <<byte>>)
      let written = list.append(written, support.writes(taken))
      case support.stops(taken) {
        True -> #(fed + 1, written)
        False -> fed_byte_by_byte(state:, bytes: rest, fed: fed + 1, written:)
      }
    }
    _ -> #(fed, written)
  }
}

pub fn a_second_end_of_sessions_claims_again_under_the_same_watch_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let state = claimed(state:, taken:).0
  let #(state, taken) = feed(state, WatchEnded(WatchId(1)))
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
}

pub fn a_watch_or_timer_the_rule_did_not_open_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  list.each(
    [
      feed(in_select_with_a_list(), WatchEnded(WatchId(9))).1,
      feed(in_select_with_a_list(), OwnEvent(TimerFired(TimerId(1)))).1,
      feed(waiting, WatchEnded(WatchId(1))).1,
      feed(waiting, OwnEvent(TimerFired(TimerId(2)))).1,
      feed(replied().0, WatchEnded(WatchId(1))).1,
      feed(connected(), OwnEvent(TimerFired(TimerId(1)))).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_claim_timer_that_fires_while_the_claims_ask_is_out_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(claim_after_the_hand_off, _) = claiming()
  let #(state, _) = feed(in_select_with_a_list(), WatchEnded(WatchId(1)))
  let #(claim_after_the_watch_ended, taken) =
    feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert ask_request(taken) == claim_ask()
    as "the timer's firing made the claim, so its ask is out"
  list.each([claim_after_the_hand_off, claim_after_the_watch_ended], fn(state) {
    let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
    assert support.stops(taken)
      as "the timer is waited on only before the claim is asked; a second claim would put two asks out"
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
  })
}

pub fn a_claim_that_finds_sessions_not_running_is_made_again_after_a_wait_up_to_the_retries_then_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = claiming()
  let retry = fn(held: #(game_connection.State, ConnectionStep(Request)), _try) {
    let #(state, taken) = held
    let #(state, taken) = answer(state:, taken:, outcome: NotRunning)
    assert support.effects_of(taken)
      == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
      as "the watch on a Sessions that is not running is dropped, and the claim waits"
    assert support.asked(taken) == None
    assert support.writes(taken) == []
    let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
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
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) = answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
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
  let #(state, taken) = feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(_, taken) = answer(state:, taken:, outcome: NoAnswerInTime)
  assert disconnect(taken, keyed()) == LostUserServer
}

pub fn an_answer_to_the_claim_that_is_none_a_claim_gets_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
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
  let #(_, closed) = feed(waiting, step.OwnEvent(step.PeerClosed))
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

pub fn the_game_rule_names_the_client_messages_it_takes_test() -> Nil {
  use <- owned_test.run(10_000)
  let named = list.sort(game_connection.taken_message_ids(), int.compare)
  assert named
    == [
      0x00BF, 0x00C0, 0x00D5, 0x00F2, 0x00FB, 0x00FC, 0x025B, 0x025C, 0x0352,
      0x038C, 0x058F, 0x0637, 0x063A, 0x063B, 0x0786, 0x07DD, 0x07E0,
    ]
    as "the ids the rule's doc comment lists: 0x058F, 0x07E0, 0x07DD, 0x025C with the 0x025B it carries, 0x0352, 0x0786, the world carrier 0x038C (the direct ids of sent_message, fact 0x140332920, and 0x038C, fact 0x1403f4900), and the movement and camp messages of the player in the world, 0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC, 0x00BF and 0x00C0"
  assert list.sort(game_connection.carried_message_ids(), int.compare)
    == [0x00BF, 0x00C0, 0x00D5, 0x00F2, 0x00FB, 0x00FC, 0x0637, 0x063A, 0x063B]
    as "the movement and camp messages are taken only with the player in the world"
}

pub fn character_select_takes_exactly_the_ids_the_rule_names_and_logs_every_other_client_id_as_unhandled_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = listed(characters: [])
  let named = game_connection.taken_message_ids()
  list.each(sent_message.all(), fn(id) {
    let #(_, taken) = read(state, keyed_message(id, <<>>))
    let logged_unhandled =
      support.unhandled_ids(taken) == [Some(#("unhandled", id))]
    // 0x025B travels only inside 0x025C, so on its own it is no message the
    // rule takes (opcode.0x25c), and the movement messages are taken only with
    // the player in the world; every other named id is taken as sent.
    let taken_as_sent =
      list.contains(named, id)
      && id != 0x025B
      && !list.contains(game_connection.carried_message_ids(), id)
    assert logged_unhandled == !taken_as_sent
      as {
        "id "
        <> int.to_string(id)
        <> ": logged as unhandled exactly when the rule's list does not name it"
      }
  })
}

pub fn the_create_carrier_takes_only_the_message_the_rule_names_as_carried_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = listed(characters: [])
  list.each(sent_message.all(), fn(id) {
    let assert Ok(carried) = frame.encode(id, <<>>)
      as "the carried frame encodes"
    let #(_, taken) = read(state, keyed_message(0x025C, carried))
    let refused_as_not_0x025b =
      list.any(support.logs(taken), support.says(_, words: "not 0x025B"))
    assert refused_as_not_0x025b == { id != 0x025B }
      as {
        "id "
        <> int.to_string(id)
        <> " inside 0x025C: opcode.0x25c, 0x025C carries a 0x025B and no other message"
      }
  })
}

// ---- the camp ----
//
// Expected values come from the Client trace of the camp step and the facts it
// names: opcode.0xbf and opcode.0xc0 (the client's two camp messages, each
// inside 0x038C, 0xC0 sent at most once per camp and, for a Quit, at any time
// after the 0x92), opcode.0x92 and vector.opcode.0x92.body (the countdown, the
// cancel bit and the signature bonuses, 285 bytes),
// opcode.0x92.countdown_source and opcode.0x92.countdown_range (the length is
// the server's, under 60 s), lua.ExitWindow.OnPlayerCampCancel (a cancelling
// 0x92 is answered with another 0xBF 0, so the server sends none),
// opcode.0x594 and vector.opcode.0x594.body (the byte 01 is the bit set and
// reason 0), opcode.0x594.character_select (the client sends 0x7E0 only and the
// server answers it as at login), opcode.0x594.world_teardown (0x7EA and 0x549
// may follow) and opcode.0x262 (a unit id the client has seen is refused). The
// order of the save, the leave and 0x594, what each failure does and the
// shell's order for a close are the Design artifact's sequence and failure
// table.

/// 0xBF inside 0x038C: one bit, 1 to start a camp and 0 to cancel it
/// (opcode.0xbf).
fn camp_request_message(start: Bool) -> BitArray {
  world_message(0x00BF, case start {
    True -> <<1>>
    False -> <<0>>
  })
}

/// 0xC0 inside 0x038C: its body is empty (opcode.0xc0).
fn camp_finished_message() -> BitArray {
  world_message(0x00C0, <<>>)
}

/// The body of the 0x92 for a countdown with the cancel bit clear and every
/// bonus 0: the countdown in 32 bits, then 2248 zero bits (the cancel bit, the
/// 32-bit experience and elder points and the 34 amounts of 64 bits), which
/// pad the 2273 bits to the 285 bytes of vector.opcode.0x92.body.
fn countdown_body(countdown_ms: Int) -> BitArray {
  <<countdown_ms:size(32)-little, 0:size(2248)>>
}

/// The connection with the player's camp running, its 0x92 written.
fn camping() -> game_connection.State {
  read(in_world(), camp_request_message(True)).0
}

/// The connection after 0xC0 of a running camp: the save is asked.
fn saving_the_camp() -> #(game_connection.State, ConnectionStep(Request)) {
  read(camping(), camp_finished_message())
}

/// The connection after the camp's save was answered: the map's run is asked
/// to let the player leave.
fn leaving_the_map() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = saving_the_camp()
  answer(state:, taken:, outcome: place_saved())
}

/// The ask of the player's leave: the run of the map that took the player, 77
/// (`incarnation`), with the connection's id.
fn leave_asked() -> Request {
  AskMapRun(
    map: camp_map(),
    incarnation:,
    message: Leave(connection: ConnectionId(1)),
  )
}

/// The connection after the map answered `Left`: 0x594 is written and the
/// client is in character select.
fn camped_out() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = leaving_the_map()
  answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
}

/// The messages the step writes, as the client reads them.
fn written_ids(taken: ConnectionStep(Request)) -> List(Int) {
  list.map(heard(taken, keyed()), fn(frame) { frame.message_id })
}

pub fn message_0xbf_1_in_the_world_is_answered_with_one_0x92_of_the_settings_countdown_and_every_bonus_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = read(in_world(), camp_request_message(True))
  let assert [Frame(message_id: 0x0092, body:)] = heard(taken, keyed())
    as "opcode.0xbf: sending 1 starts nothing on the client, which waits for the server's 0x92 (opcode.0x92)"
  assert body == countdown_body(12_345)
    as "vector.opcode.0x92.body's layout: the countdown in ms, the cancel bit 0 and the bonuses 0, 285 bytes; the countdown is the settings' 12,345 ms, not the default"
  assert bit_array.byte_size(body) == 285
  let assert Ok(decoded) = camp_countdown.decode(body)
  assert decoded
    == camp_countdown.CampCountdown(
      countdown_ms: 12_345,
      cancel: 0,
      experience: 0,
      elder_points: 0,
      currencies: <<0:size(960)>>,
      account_currencies: <<0:size(1216)>>,
    )
    as "opcode.0x92: 15 currencies and 19 account currencies of 64 bits, none given"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "the rule takes 0xBF, so it is no unhandled message"
}

pub fn the_countdown_in_0x92_is_the_one_in_the_game_settings_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0, 1, 59_999], fn(countdown_ms) {
    let game = GameSettings(..settings().game, camp_countdown_ms: countdown_ms)
    let fresh = accepted(Settings(..settings(), game:)).0
    let #(state, _) = entered_from(in_select_from(fresh), world_character())
    let #(_, taken) = read(state, camp_request_message(True))
    let assert [Frame(message_id: 0x0092, body:)] = heard(taken, keyed())
    assert body == countdown_body(countdown_ms)
      as "opcode.0x92.countdown_range: the settings' time in ms, under 60 s, whatever it is"
  })
}

pub fn message_0xbf_0_during_a_camp_writes_nothing_and_a_following_0xc0_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = read(camping(), camp_request_message(False))
  assert support.writes(taken) == []
    as "lua.ExitWindow.OnPlayerCampCancel: the client cleared its own camp, and a cancelling 0x92 would be answered by another 0xBF 0 without end"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
  let #(state, taken) = read(state, camp_finished_message())
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "opcode.0xc0: the client sends it only for a camp the server started, so it is one the client never sends"
  assert support.says(line, "0x00C0") && support.says(line, "no camp")
  assert ask_request(taken) == save_asked(1, entry_place())
    as "the last good place is saved, as for a refused move"
  assert support.writes(taken) == []
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.effects_of(taken) == [step.Stop]
    as "nothing is written to a client that is no client"
}

pub fn message_0xbf_0_with_no_camp_writes_nothing_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = read(in_world(), camp_request_message(False))
  assert support.writes(taken) == []
    as "lua.ExitWindow.OnPlayerCampCancel: the exit window sends it after any cancelling 0x92, with no camp running"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "it is taken and changes nothing: no unhandled line, no error"
  let #(_, taken) = read(state, camp_request_message(True))
  assert written_ids(taken) == [0x0092] as "a camp can still start"
}

pub fn a_second_0xbf_1_during_a_camp_is_answered_with_a_second_0x92_and_one_0xc0_finishes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = read(camping(), camp_request_message(True))
  let assert [Frame(message_id: 0x0092, body:)] = heard(taken, keyed())
    as "opcode.0xbf: a second 0xBF 1 before the first 0x92 arrives restarts the client's countdown, so each is answered"
  assert body == countdown_body(12_345)
  let #(_, taken) = read(state, camp_finished_message())
  assert ask_request(taken) == save_asked(1, entry_place())
    as "one camp: one 0xC0 finishes it, and a save is asked once"
  assert support.logs(taken) == []
}

pub fn message_0xc0_at_once_after_the_0x92_as_a_quit_sends_it_is_taken_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    read(
      in_world(),
      bit_array.concat([camp_request_message(True), camp_finished_message()]),
    )
  assert written_ids(taken) == [0x0092]
    as "opcode.0xc0: a Quit sends 0xC0 at any time after the 0x92, before the countdown ends, and the server cannot tell it from a camp's"
  assert ask_request(taken) == save_asked(1, entry_place())
    as "the camp finishes at once: the save is asked"
  assert support.logs(taken) == []
}

pub fn message_0xc0_with_no_camp_ends_the_connection_with_an_error_the_last_good_place_saved_and_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = moved_to(state: in_world(), x: 4.5, y: 5.5, z: 6.5)
  let #(state, taken) = read(state, camp_finished_message())
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "opcode.0xc0: the client sends it at most once per camp and only while a camp runs"
  assert support.says(line, "0x00C0")
  assert line.about.character_id == Some(42)
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 4.5, y: 5.5, z: 6.5))
    as "the last place the player stood at is saved"
  assert support.writes(taken) == []
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert support.effects_of(taken) == [step.Stop]
    as "no 0x0594 and no notice: nothing is written"
}

pub fn message_0xc0_cancels_the_save_timer_saves_the_place_asks_the_map_run_to_let_the_player_leave_then_writes_0x594_with_the_byte_01_in_that_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = saving_the_camp()
  assert support.effects_of(taken) == [OwnEffect(CancelTimer(TimerId(2)))]
    as "the 60 s save timer is cancelled before the save, so none fires while the player leaves"
  assert ask_request(taken) == save_asked(1, entry_place())
    as "the place is saved first"
  assert support.writes(taken) == []
  let #(state, taken) = answer(state:, taken:, outcome: place_saved())
  assert ask_request(taken) == leave_asked()
    as "then the map's run that took the player is asked to take it out"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the leave is answered: the client can pick a character only after 0x594, so a play never meets a save still out"
  let #(_, taken) = answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
  assert heard(taken, keyed()) == [Frame(message_id: 0x0594, body: <<1>>)]
    as "vector.opcode.0x594.body: the byte 01 is the bit set and reason 0, which returns to character select"
  assert support.asked(taken) == None && !support.stops(taken)
  assert list.first(support.effects_of(taken)) == Ok(Unwatch(WatchId(2)))
    as "the watch on the map is dropped before 0x0594 is written: the map holds the player no longer"
  assert support.logs(taken) == []
}

pub fn after_0x594_a_0x07e0_is_answered_with_0x0036_and_0x0117_as_at_login_with_no_new_claim_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = camped_out()
  let #(state, taken) = read(state, select_start())
  assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
    as "opcode.0x594.character_select: the client's new character select sends 0x7E0 only, and the list is built as at login, from the store"
  assert support.effects_of(taken) == []
    as "no claim: the connection holds the account's slot still, and no watch is opened"
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
    as "opcode.0x36 then opcode.0x117, as at login"
  let assert Ok(sent) = character_list.decode(body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve"]
}

/// The map's answer to the ask in the step, from the map's rule: `map_state`
/// takes the ask's message as the map's caller 1 and answers it.
fn mapped(
  map_state map_state: map.State,
  taken taken: ConnectionStep(Request),
) -> #(map.State, map.Outgoing) {
  let message = case ask_request(taken) {
    AskMap(message:, ..) | AskMapRun(message:, ..) -> message
    AskStore(..) | AskHandOff(..) | AskSessions(..) | TellMoved(..) ->
      panic as "the step ends in an ask of the map: a store, hand-off or Sessions ask, or a tell, is none"
  }
  let #(map_state, mapped) =
    map.step(
      map_state,
      support.input(OwnEvent(step.Asked(caller: CallerId(1), message:))),
    )
  let assert [#(CallerId(1), outgoing)] = support.replies(mapped)
    as "the map answers the ask once, to its caller"
  #(map_state, outgoing)
}

pub fn after_a_camp_a_play_request_enters_the_world_again_as_a_new_unit_with_the_map_watched_and_the_save_timer_started_again_test() -> Nil {
  use <- owned_test.run(10_000)
  // The real map rule answers every ask: the first join, the leave, the second.
  let #(state, taken) = joining()
  let #(map_state, joined) = mapped(map_state: map_with_four_players(), taken:)
  let #(state, taken) =
    answer(state:, taken:, outcome: step.Answer(FromMap(joined)))
  let first_unit = player_in(taken).unit_id
  let #(state, _) = read(state, camp_request_message(True))
  let #(state, taken) = read(state, camp_finished_message())
  let #(state, taken) = answer(state:, taken:, outcome: place_saved())
  let #(map_state, left) = mapped(map_state:, taken:)
  assert left == Left as "the map took the player out"
  let #(state, taken) =
    answer(state:, taken:, outcome: step.Answer(FromMap(left)))
  assert written_ids(taken) == [0x0594]
  let #(state, taken) = read(state, select_start())
  let #(state, _) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(state, taken) = playing_from(state, 42)
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(CharacterLoaded(
            world_character(),
            character_support.epoch(1),
          )),
        ),
      ),
    )
  let #(_, joined_again) = mapped(map_state:, taken:)
  let #(state, taken) =
    answer(state:, taken:, outcome: step.Answer(FromMap(joined_again)))
  assert written_ids(taken) == game_client.world_entry_ids
    as "the same seven messages as at the first entry"
  assert player_in(taken).unit_id != first_unit && player_in(taken).unit_id == 6
    as "opcode.0x262: the client refuses a unit id it has seen, so the play is a new unit: the map's next id after the five it gave"
  assert support.watches(taken) == [#(WatchId(2), Map(camp_map(), incarnation))]
    as "the map is watched again, under the same watch id the leave dropped"
  assert list.contains(
    support.effects_of(taken),
    OwnEffect(StartTimer(TimerId(2), 60_000)),
  )
    as "the save timer starts again"
  let #(_, taken) = read(state, camp_finished_message())
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "the new life has no camp: a 0xC0 at once is refused"
}

pub fn moving_during_a_camp_keeps_the_camp_and_the_place_saved_at_0xc0_is_the_last_one_moved_to_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = moved_to(state: camping(), x: 1.5, y: 2.5, z: 3.5)
  let state = moved_to(state:, x: 7.5, y: 8.5, z: 9.5)
  let #(state, taken) = read(state, camp_finished_message())
  assert support.logs(taken) == []
    as "lua.ExitWindow.OnCancel: nothing cancels the camp on the client but its exit window, so moving leaves it, and the finish is taken"
  assert ask_request(taken)
    == save_asked(1, standing_at(x: 7.5, y: 8.5, z: 9.5))
    as "the place saved is the last one the client said the player stood at"
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert ask_request(taken) == leave_asked()
}

pub fn a_camp_save_the_store_cannot_make_is_a_warning_and_the_leave_goes_on_to_0x594_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(no_answers(), fn(outcome) {
    let #(state, taken) = saving_the_camp()
    let #(state, taken) = answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "an outside failure the server recovered from"
    assert support.says(line, "not saved")
    assert line.about.character_id == Some(42)
    assert ask_request(taken) == leave_asked()
      as "the last 60 s save stands: the player leaves all the same"
    assert !support.stops(taken)
    let #(_, taken) =
      answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
    assert written_ids(taken) == [0x0594]
      as "and the client is returned to character select"
  })
}

pub fn a_client_that_closes_after_0xc0_gets_its_save_its_leave_and_0x594_in_that_order_and_the_close_is_taken_after_them_without_a_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  // A Quit sends 0xC0 and the client ends itself. The shell takes no other
  // input while an ask is out, so the close waits: it is the rule's input
  // only once the 0x594 step is done, in character select.
  let #(state, taken) = camped_out()
  assert written_ids(taken) == [0x0594]
    as "the save, the leave and 0x594 all ran before the close was taken"
  let #(_, taken) = feed(state, OwnEvent(step.PeerClosed))
  assert support.effects_of(taken) == [step.Stop]
    as "the client's close in character select ends the connection"
  assert support.asked(taken) == None
    as "no second save: the place was saved at 0xC0"
  let #(_, taken) =
    feed(
      state,
      OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "closed"))),
    )
  assert support.stops(taken) && support.asked(taken) == None
    as "the write of 0x0594 may have failed because the client is gone: the connection ends, and saves nothing"
}

pub fn a_leave_answered_not_running_or_ended_before_its_answer_still_writes_0x594_and_returns_to_character_select_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NotRunning, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = leaving_the_map()
    let #(state, taken) = answer(state:, taken:, outcome:)
    assert written_ids(taken) == [0x0594]
      as "the map run that held the player is gone, and its player with it: the leave is done"
    assert list.contains(support.effects_of(taken), Unwatch(WatchId(2)))
      as "the watch on the map is dropped, with an end already queued behind the ask"
    assert !support.stops(taken)
    let #(_, taken) = read(state, select_start())
    assert ask_request(taken) == AskStore(Select(ListCharacters(AccountId(7))))
      as "the client is in character select: its 0x07E0 asks the store"
  })
}

pub fn the_map_ending_while_the_camp_save_is_out_returns_the_client_to_character_select_not_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  // The map's end waits behind the save, which the shell takes no input
  // during. When the save is answered the leave finds no run (`NotRunning`),
  // and its step's `Unwatch` drops the end that waited, so the rule never
  // takes it.
  let #(state, taken) = leaving_the_map()
  assert ask_request(taken) == leave_asked()
  let #(_, taken) = answer(state:, taken:, outcome: NotRunning)
  assert written_ids(taken) == [0x0594]
    as "the client is told to return to character select"
  assert !support.stops(taken) && !list.contains(written_ids(taken), 0x036A)
    as "and not told 'Lost connection with user server.' (reason 8)"
  assert list.contains(support.effects_of(taken), Unwatch(WatchId(2)))
    as "the queued end of watch 2 is dropped with the watch"
}

pub fn a_leave_that_gets_no_answer_in_time_tells_the_client_reason_8_and_ends_the_connection_with_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = leaving_the_map()
  let #(_, taken) = answer(state:, taken:, outcome: NoAnswerInTime)
  assert disconnect(taken, keyed()) == LostUserServer
    as "0x1400168a0: 8; the map may still hold the player, and its watch on the connection drops it"
  assert support.asked(taken) == None
    as "the place was saved at 0xC0: no second save"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line, "the map")
}

pub fn the_server_stopping_during_the_camp_save_or_the_leave_stops_the_connection_with_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = saving_the_camp()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
    as "the server never ends a connection after the hello without telling the client"
  assert support.asked(taken) == None && support.logs(taken) == []
    as "the stop is no failure, and the leave is not asked"
  let #(state, taken) = leaving_the_map()
  let #(_, taken) = answer(state:, taken:, outcome: StoppedWaiting)
  assert disconnect(taken, keyed()) == LostUserServer
  assert support.asked(taken) == None && support.logs(taken) == []
    as "no second save, and no 0x594"
}

/// The answers a leave never gets: those of the store, the hand-off and
/// Sessions, and the map's join.
fn answers_to_no_leave() -> List(Outcome(Answer)) {
  [
    place_saved(),
    step.Answer(FromStore(Unavailable)),
    step.Answer(FromHandOff(NoHolder)),
    step.Answer(FromSessions(Claimed)),
    step.Answer(FromMap(a_join_answer())),
  ]
}

pub fn an_answer_in_the_leave_that_is_not_the_maps_is_a_bug_with_reason_8_an_error_and_no_save_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(answers_to_no_leave(), fn(outcome) {
    let #(state, taken) = leaving_the_map()
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the place was saved at 0xC0: a bug ends the connection without saving again"
  })
}

/// The inputs that end a connection, as they reach the rule.
fn ending_inputs() -> List(Event(ConnectionEvent(Message, Answer))) {
  [
    OwnEvent(step.PeerClosed),
    OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "gone"))),
    OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))),
    step.Stopping(deadline_ms: 9000),
    taken_over(),
  ]
}

pub fn an_end_reached_during_the_leave_saves_nothing_more_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = leaving_the_map()
  list.each(ending_inputs(), fn(event) {
    let #(_, taken) = feed(state, event)
    assert support.asked(taken) == None
      as "the place was saved at 0xC0: the end of a connection that is leaving its map saves nothing more"
    assert support.stops(taken)
  })
}

pub fn an_end_reached_during_the_camp_save_never_saves_a_second_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = saving_the_camp()
  list.each(ending_inputs(), fn(event) {
    let #(_, taken) = feed(state, event)
    assert support.asked(taken) == None
    assert support.stops(taken)
  })
}

pub fn a_takeover_during_the_camp_saves_first_and_one_after_it_is_the_one_of_character_select_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(camping(), taken_over())
  assert ask_request(taken) == save_asked(1, entry_place())
    as "as in the world today: the place is saved before the client is told"
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == AccountDisconnected
  let #(state, _) = camped_out()
  let #(_, taken) = feed(state, taken_over())
  assert disconnect(taken, keyed()) == AccountDisconnected
    as "taken after the answers, when the connection is between steps: in character select, with no player to save"
  assert support.asked(taken) == None
}

pub fn the_end_of_sessions_during_a_camp_claims_again_with_the_player_in_the_world_and_the_camp_kept_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = claiming_again(camping())
  let #(state, taken) = claimed(state:, taken:)
  assert support.writes(taken) == []
  let #(_, taken) = read(state, camp_finished_message())
  assert support.logs(taken) == []
    as "the camp is kept in the player's world state, so the claim again leaves it running and the 0xC0 is taken"
  assert ask_request(taken) == save_asked(1, entry_place())
}

pub fn the_end_of_the_map_during_a_camp_saves_the_place_then_tells_the_client_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = feed(camping(), WatchEnded(WatchId(2)))
  assert ask_request(taken) == save_asked(1, entry_place())
  let #(_, taken) = answer(state:, taken:, outcome: place_saved())
  assert disconnect(taken, keyed()) == LostUserServer
    as "a map that ends while the camp counts down takes its player with it: as today, the client is told"
}

/// The ids of the messages the client's old world and its camp may send in
/// character select, which the rule does not take there.
fn world_ids() -> List(Int) {
  [0x07EA, 0x0549, 0x00BF, 0x00C0]
}

pub fn a_0x038c_holding_0x7ea_0x549_0xbf_or_0xc0_in_character_select_is_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(after_camp, _) = camped_out()
  list.each([in_select(), after_camp], fn(state) {
    list.each(world_ids(), fn(id) {
      let #(_, taken) = read(state, world_message(id, <<1>>))
      assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
        as "opcode.0x594.world_teardown: the client's old world may send 0x7EA and 0x549 around 0x7E0, and the camp messages are taken in the world only; each is logged under its own id"
      assert !support.stops(taken) && support.writes(taken) == []
      assert support.asked(taken) == None
    })
  })
}

pub fn an_answer_in_the_camp_save_that_is_not_the_stores_is_a_bug_with_reason_8_an_error_and_no_leave_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(answers_to_other_asks(), fn(outcome) {
    let #(state, taken) = saving_the_camp()
    let #(_, taken) = answer(state:, taken:, outcome:)
    assert disconnect(taken, keyed()) == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the save is over and the camp's leave is not asked: a bug ends the connection without a second save"
  })
}

// ---- other players' units ----
//
// Expected values: 0x262, 0x638 and 0x355 are what the client creates, moves
// and removes a unit with (opcode.0x262, opcode.0x638, opcode.0x355); the
// reset bit and the kept bit are 0, the values of a unit the client does not
// control (opcode.0x638); after the player's own leave the client holds no
// world, so a send for another unit is dropped and nothing is written
// (the Design's failure table); an accepted 0x637 tells the map where the
// movement rule says the player stands, which is `start_place.moved` of the
// last position in the world's frame (genesis_prime/game/movement).

/// A send of the map to the connection.
fn sent_by_the_map(
  message: map.Outgoing,
) -> Event(ConnectionEvent(Message, Answer)) {
  OwnEvent(Woken(SentByMap(message)))
}

/// Another player's unit: the tests' player's own record, as unit 9.
fn another_unit() -> UnitCreatePlayer {
  UnitCreatePlayer(..player_in(entered().1), unit_id: 9, name: "Zed Other")
}

fn moved_unit_commands() -> List(relayed_movement.RelayedMovement) {
  [
    relayed_movement.Position(UnitPositionCommand(
      x: 0x3F800000,
      y: 0x40000000,
      z: 0xC0400000,
      blends: 1,
    )),
    relayed_movement.Mode(MovementMode(mode: 3)),
  ]
}

pub fn a_seen_in_the_world_is_written_at_once_as_the_0x262_of_its_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    feed(in_world(), sent_by_the_map(Seen(unit: another_unit())))
  let assert [Frame(message_id: 0x0262, body:)] = heard(taken, keyed())
    as "opcode.0x262: another player is created with the player's own 0x262"
  assert unit_create_player.decode(body) == Ok(another_unit())
}

pub fn a_moved_unit_is_written_as_a_0x638_with_both_bits_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    feed(
      in_world(),
      sent_by_the_map(MovedUnit(
        unit_id: 9,
        server_time_ms: 4321,
        commands: moved_unit_commands(),
      )),
    )
  let assert [Frame(message_id: 0x0638, body:)] = heard(taken, keyed())
    as "opcode.0x638"
  assert unit_movement.decode(body)
    == Ok(UnitMovement(
      unit_id: 9,
      server_time: 4321,
      reset_movement: 0,
      kept: 0,
      commands: moved_unit_commands(),
    ))
    as "the reset bit is 0 (the unit's movement is not rebuilt) and the kept bit 0, as the Design says, with the commands in order"
}

pub fn an_unseen_is_written_as_a_0x355_of_the_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), sent_by_the_map(Unseen(unit_id: 9)))
  let assert [Frame(message_id: 0x0355, body:)] = heard(taken, keyed())
    as "opcode.0x355"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 9, field_2: 0))
}

pub fn after_the_players_own_leave_nothing_more_is_written_for_other_units_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = camped_out()
  list.each(
    [
      Seen(unit: another_unit()),
      MovedUnit(unit_id: 9, server_time_ms: 1, commands: moved_unit_commands()),
      Unseen(unit_id: 9),
    ],
    fn(message) {
      let #(_, taken) = feed(state, sent_by_the_map(message))
      assert support.writes(taken) == []
        as "the player is in character select: the client holds no world to create, move or remove a unit in"
      assert support.logs_of(step: taken, level: LogError) == []
        as "a send that was on its way when the player left is no bug"
    },
  )
}

pub fn an_answer_of_the_map_sent_as_a_message_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = feed(in_world(), sent_by_the_map(Left))
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.asked(taken) != None
    as "an end with the player in the world saves its place first, as every end does"
}

/// The tells of a step: where each goes and what it says.
fn told_the_map(
  taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(..)) -> True
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop -> False
    }
  })
}

pub fn an_accepted_0x637_tells_the_map_the_place_the_movement_keeps_and_the_relayed_commands_test() -> Nil {
  use <- owned_test.run(10_000)
  let sent = [
    movement_command.Time(MovementTime(time: 99)),
    game_client.position_command(x: 1.5, y: 2.5, z: 3.5),
    movement_command.Mode(MovementMode(mode: 1)),
  ]
  let #(_, taken) = read(in_world(), moves_message(sent))
  assert told_the_map(taken)
    == [
      OwnEffect(step.Tell(
        to: Map(camp_map(), incarnation),
        request: TellMoved(
          connection: ConnectionId(1),
          place: standing_at(x: 1.5, y: 2.5, z: 3.5),
          commands: [
            relayed_movement.Position(UnitPositionCommand(
              x: 0x3FC00000,
              y: 0x40200000,
              z: 0x40600000,
              blends: 0,
            )),
            relayed_movement.Mode(MovementMode(mode: 1)),
          ],
        ),
      )),
    ]
    as "the place is the movement's (the last position of the world's frame), the commands are the sent ones in order without kind 0, the sender's own clock (movement_command.kind_0); the map is the run the connection watches"
}

pub fn a_refused_0x637_tells_the_map_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(refused_messages(), fn(refused) {
    let #(bytes, why) = refused
    let #(_, taken) = read(in_world(), bytes)
    assert told_the_map(taken) == [] as why
  })
}

pub fn a_0x637_with_nothing_to_relay_tells_the_map_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    read(
      in_world(),
      moves_message([movement_command.Time(MovementTime(time: 5))]),
    )
  assert told_the_map(taken) == []
    as "kind 0 alone is the sender's own clock: nothing to relay"
}

pub fn a_command_kind_that_is_not_relayed_is_named_once_a_connection_and_not_relayed_test() -> Nil {
  use <- owned_test.run(10_000)
  let unrelayed = movement_command.Kind26(MovementKind26(field_2: 0))
  let message =
    moves_message([
      unrelayed,
      game_client.position_command(x: 1.0, y: 1.0, z: 1.0),
    ])
  let #(state, first) = read(in_world(), message)
  let assert [line] = support.logs_of(step: first, level: LogInfo)
    as "an info line names the kind"
  assert support.says(line, words: "kind 26")
  let assert [OwnEffect(step.Tell(request: TellMoved(commands:, ..), ..))] =
    told_the_map(first)
  assert list.length(commands) == 1 as "the kind 26 is not relayed"
  let #(_, second) = read(state, message)
  assert support.logs_of(step: second, level: LogInfo) == []
    as "named once on a connection"
}
