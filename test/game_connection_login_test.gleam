//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover the hello, the
//// re-key, the list at login, the claim and one login per account.
////
//// Expected values come from these places.
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

import character_tables
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/account_session.{Claimed, TakenOver}
import genesis_prime/client_connection.{
  type Request, AskHandOff, AskStore, FromHandOff, FromSessions, FromStore,
  SentBySessions,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/coverage/sent_message
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/hand_off.{
  AlreadyHeld, Kept, NoHolder, SessionKey, Take, Taken,
}
import genesis_prime/message/account_entitlements.{AccountEntitlements}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{CharacterListEntry}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/held_entitlement.{HeldEntitlement}
import genesis_prime/message/premium_tier.{PremiumTier}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, EndedBeforeAnswer, LogError, LogInfo,
  LogWarning, NoAnswerInTime, NotRunning, OtherSocketFailure, OwnEffect,
  OwnEvent, Sessions, StartTimer, StoppedWaiting, TimerFired, TimerId, Unwatch,
  Watch, WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{
  AccountId, Created, ForSelect, ListCharacters, Listed, NameTaken, Select,
  Unavailable,
}
import genesis_prime/table/character_customization
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test

/// The connection after 0x058F, with its ask to take the session key.
fn replied() -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.connected(),
    game_connection_support.hello_reply(),
  )
}

// ---- the tests, in the order of the card's list ----

pub fn on_connect_the_hello_is_the_first_thing_written_in_0x3dc_under_the_base_key_with_the_realm_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.accepted(game_connection_support.settings())
  assert support.asked(taken) == None
  assert !support.stops(taken)
  let assert [Frame(message_id: 0x0003, body:)] =
    game_connection_support.heard(taken, game_connection_support.base())
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
  assert game_connection_support.ask_request(taken)
    == AskHandOff(Take(SessionKey(key: support.guid_of(1))))
    as "opcode.0x58f: the 16 bytes the client showed, as the GUID they are"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the hand-off answers"
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: game_connection_support.holder())),
      ),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
    as "the account the hand-off named, claimed for this connection"
  assert support.writes(taken) == []
  let #(state, _) = game_connection_support.claimed(state:, taken:)
  // The next read is under the session key: the store is asked because 0x07E0
  // opened under it.
  let #(_, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "0x07E0 under the session key is read"
}

pub fn a_message_under_the_base_key_after_0x058f_is_not_read_as_the_client_sent_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let under_the_base_key =
    game_client.client_bytes(
      message_id: 0x07E0,
      body: <<>>,
      cipher: game_connection_support.base(),
    )
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      under_the_base_key,
    )
  assert support.asked(taken) == None
    as "vector.0x14003827c.session_fold: after 0x058F the client sends nothing under the base key, so these bytes opened under the session key are not 0x07E0"
}

pub fn message_0x07e0_in_the_same_read_as_0x058f_waits_until_the_hand_off_answers_then_the_store_is_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      game_connection_support.hello_reply():bits,
      game_connection_support.select_start():bits,
    >>)
  assert game_connection_support.ask_request(taken)
    == AskHandOff(Take(SessionKey(key: support.guid_of(1))))
    as "only the hand-off is asked while the key is out: 0x07E0 waits in the bytes read"
  assert support.writes(taken) == []
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: game_connection_support.holder())),
      ),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
    as "Sessions is asked first: 0x07E0 still waits in the bytes read"
  let #(_, taken) = game_connection_support.claimed(state:, taken:)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the holder's account, once Sessions answers"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
  assert support.writes(taken) == []
}

pub fn the_stores_rows_become_0x0117_under_the_session_key_with_no_characters_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = game_connection_support.listed(characters: [])
  let assert [
    Frame(message_id: 0x097F, body: tier),
    Frame(message_id: 0x0968, body: entitlements),
    Frame(message_id: 0x0036, ..),
    Frame(message_id: 0x0117, body:),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x97f, opcode.0x968, opcode.0x36 and opcode.0x117 inside 0x3DC under the session key"
  assert premium_tier.decode(tier) == Ok(PremiumTier(tier: 1))
    as "the premium tier first, so 0x968's refresh keeps the player Signature (lua.AccountItemLib.GetPremiumTier.users)"
  assert account_entitlements.decode(entitlements)
    == Ok(
      AccountEntitlements(entitlements: [
        HeldEntitlement(entitlement_id: 12, count: 1),
      ]),
    )
    as "the settings' 3 slots are the client's 2 and an entitlement 12 of 1 (lua.CharacterSelection.OnLoadFromCharacter)"
  assert character_list.decode(body)
    == Ok(CharacterList(
      server_time: game_connection_support.filetime,
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
  let first = game_connection_support.character(id: 42, name: "Ab", seed: 3)
  let second = game_connection_support.character(id: 9, name: "Zéd Qu", seed: 8)
  let #(_, taken) = game_connection_support.listed(characters: [first, second])
  assert list.all(
    character_customization.all(character_tables.shared()),
    fn(row) { row.gender < 2 },
  )
    as "no CharacterCustomization row is for gender 2 or 3 (character_tables_test: the client's table has rows for genders 0 and 1 only), so a character of gender 2 or 3 has no body visual"
  let assert [
    Frame(message_id: 0x097F, ..),
    Frame(message_id: 0x0968, ..),
    Frame(message_id: 0x0036, ..),
    Frame(message_id: 0x0117, body:),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
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
  assert sent.server_time == game_connection_support.filetime
    && sent.realm_id == 5
}

pub fn a_session_key_the_hand_off_does_not_hold_gets_0x036a_reason_19_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = replied()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(NoHolder)),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
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
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
      as "0x1400168a0: 8 is 'Lost connection with user server.', for the server's own failure"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "the failure is the server's: a warning"
    assert line.about.peer == Some(support.peer)
  })
  // A hand-off answer no Take gets is a bug of the server's, and ends the
  // connection the same way, with an error.
  let #(state, taken) = replied()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(Kept)),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(state, taken) = replied()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromHandOff(AlreadyHeld)),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
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
      let #(state, taken) = game_connection_support.listing()
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
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
      let #(state, taken) = game_connection_support.listing()
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "a list is asked for, so the client would wait on its prompt for good unless it is told"
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
        as "an answer of another ask is a bug of the server's: an error"
    },
  )
}

pub fn the_server_stopping_after_the_hello_gets_0x036a_reason_8_under_the_cipher_held_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  // Waiting for 0x058F: the base key.
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.connected(),
      step.Stopping(deadline_ms: 9000),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.base(),
    )
    == LostUserServer
    as "opcode.0x36a: the client is told, or it would wait on its prompt for good"
  // Part-way through an ask: the shell gives StoppedWaiting, then the step
  // that ends without an ask is the end.
  let #(state, taken) = replied()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  let #(state, taken) = game_connection_support.claiming()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  let #(state, taken) = game_connection_support.listing()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  // In character select with the list sent: the session key.
  let #(state, _) = game_connection_support.listed(characters: [])
  let #(_, taken) =
    game_connection_support.feed(state, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  // Before the connection is accepted there is no client to tell.
  let #(_, taken) =
    game_connection_support.feed(
      game_connection.new(game_connection_support.settings()),
      step.Stopping(deadline_ms: 9000),
    )
  assert support.writes(taken) == []
  assert support.stops(taken)
}

pub fn a_first_message_other_than_0x058f_or_a_second_0x058f_is_logged_as_an_error_and_the_connection_closes_test() -> Nil {
  use <- owned_test.run(10_000)
  let first =
    game_client.client_bytes(
      message_id: 0x07E0,
      body: <<>>,
      cipher: game_connection_support.base(),
    )
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), first)
  assert support.stops(taken)
    as "the client's first message is 0x058F (opcode.0x58f); another one is no client's"
  let assert [line] = support.logs_of(step: taken, level: LogError)
  assert line.about.peer == Some(support.peer)
  assert support.asked(taken) == None
  // A second 0x058F in the same read, as the client would send it under the
  // session key, is read once the key is taken.
  let second =
    game_connection_support.keyed_message(
      0x058F,
      game_client.hello_reply_body(
        session_key: game_connection_support.session_key(),
        account_name: "jim",
      ),
    )
  let #(state, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      game_connection_support.hello_reply():bits,
      second:bits,
    >>)
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: game_connection_support.holder())),
      ),
    )
  let #(_, taken) = game_connection_support.claimed(state:, taken:)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // And one in character select.
  let #(_, taken) =
    game_connection_support.read(game_connection_support.in_select(), second)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.asked(taken) == None
}

pub fn a_bare_ping_is_answered_with_a_bare_pong_with_the_same_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.connected(),
      support.ping(9),
    )
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 9>>]
    as "opcode.0x1: the pong carries the ping's number, bare, before the client has answered the hello"
  assert !support.stops(taken)
  let #(state, _) = game_connection_support.listed(characters: [])
  let #(_, taken) = game_connection_support.read(state, support.ping(3))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 3>>]
    as "opcode.0x0: in character select too, the ping travels bare and is never ciphered"
}

pub fn message_0x038c_carrying_0x082d_and_0x0241_are_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.listed(characters: [])
  let #(state, taken) =
    game_connection_support.read(state, <<
      game_connection_support.store_request():bits,
      game_connection_support.activity():bits,
    >>)
  assert support.unhandled_ids(taken)
    == [Some(#("unhandled", 0x082D)), Some(#("unhandled", 0x0241))]
    as "opcode.0x38c and opcode.0x82d: 0x038C carries the whole frame of 0x082D, which is logged under its own id; opcode.0x241: the client sends it and waits for no answer, and no feature takes it; each is logged in order"
  assert support.writes(taken) == []
  assert !support.stops(taken)
  let #(_, taken) = game_connection_support.read(state, support.ping(1))
  assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 1>>]
    as "the connection goes on"
}

pub fn frames_after_the_one_that_asked_wait_for_its_answer_and_are_then_taken_in_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      game_connection_support.hello_reply():bits,
      game_connection_support.select_start():bits,
      game_connection_support.store_request():bits,
    >>)
  assert support.unhandled_ids(taken) == []
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: game_connection_support.holder())),
      ),
    )
  let #(state, taken) = game_connection_support.claimed(state:, taken:)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
  assert support.unhandled_ids(taken) == []
    as "0x038C follows 0x07E0 in the bytes and waits for the store's answer"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed(characters: [])))),
    )
  let assert [
    Frame(message_id: 0x097F, ..),
    Frame(message_id: 0x0968, ..),
    Frame(message_id: 0x0036, ..),
    Frame(message_id: 0x0117, ..),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
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
    let #(_, taken) =
      game_connection_support.read(game_connection_support.connected(), <<
        support.ping(4):bits,
        bad:bits,
      >>)
    assert support.writes(taken) == [<<7, 0, 0, 0, 1, 0, 4>>]
      as "the ping before the bad frame is answered"
    assert support.stops(taken)
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
  })
}

pub fn the_effects_of_frames_before_a_frame_that_asks_leave_in_the_order_the_frames_came_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(game_connection_support.in_select(), <<
      support.ping(1):bits,
      game_connection_support.store_request():bits,
      support.ping(2):bits,
      game_connection_support.create_message(
        game_connection_support.a_create_request("Ab Cd"),
      ):bits,
    >>)
  assert support.writes(taken) == [support.pong(1), support.pong(2)]
    as "opcode.0x0 and opcode.0x1: each ping is answered, the first ping's pong first"
  assert game_connection_support.kinds(taken) == ["write", "log", "write"]
    as "a read's frames are taken in order: the pong, the unhandled 0x082D's log line, the pong; the create's ask ends the step after them"
  assert support.asked(taken) != None
    as "the create asks the store, after the earlier frames' effects"
}

pub fn the_effects_of_frames_before_a_frame_that_ends_the_connection_leave_in_the_order_the_frames_came_test() -> Nil {
  use <- owned_test.run(10_000)
  let below_header = <<3, 0, 0, 0, 0, 0>>
  let #(_, taken) =
    game_connection_support.read(game_connection_support.in_select(), <<
      support.ping(1):bits,
      game_connection_support.store_request():bits,
      support.ping(2):bits,
      below_header:bits,
    >>)
  assert support.writes(taken) == [support.pong(1), support.pong(2)]
    as "opcode.0x0 and opcode.0x1: each ping before the bad frame is answered, the first ping's pong first"
  assert game_connection_support.kinds(taken)
    == ["write", "log", "write", "log", "stop"]
    as "the whole frames before a frame the client's reader would refuse (ParseWrappedMessage 0x140331620) leave in order, then the refusal's log line and the end"
}

pub fn the_client_closing_a_socket_failure_and_a_late_answer_are_handled_as_in_the_login_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.connected(),
      step.OwnEvent(step.PeerClosed),
    )
  assert support.effects_of(taken) == [step.Stop]
    as "the client closed: nothing to tell it, nothing to log"
  list.each([step.ReadFailed, step.WriteFailed], fn(failed) {
    let #(_, taken) =
      game_connection_support.feed(
        game_connection_support.connected(),
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
  let #(state, _) = game_connection_support.listed(characters: [])
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the client asked for its list again, so the store is asked again"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForSelect(
            Listed([
              game_connection_support.character(id: 5, name: "Eve", seed: 1),
            ]),
          ),
        ),
      ),
    )
  let assert [
    Frame(message_id: 0x097F, ..),
    Frame(message_id: 0x0968, ..),
    Frame(message_id: 0x0036, ..),
    Frame(message_id: 0x0117, body:),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(sent) = character_list.decode(body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve"]
    as "the new list holds what the store gave this time"
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

pub fn after_the_hand_off_the_account_is_claimed_with_a_watch_on_sessions_before_the_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, claim) = game_connection_support.claiming()
  assert support.effects_of(claim) == [Watch(WatchId(1), Sessions)]
    as "the rule watches Sessions with the claim, under its one watch id"
  assert game_connection_support.ask_request(claim)
    == game_connection_support.claim_ask()
  let assert Some(ask) = support.asked(claim)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  // 0x07E0 arriving while the claim is out waits; the list is asked only after
  // Sessions answers.
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert support.asked(taken) == None
  assert support.effects_of(taken) == []
  let #(_, taken) = game_connection_support.claimed(state:, taken: claim)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the claim comes before the list: the frame that waited is taken once Sessions answers"
}

/// A step that ended the connection as a takeover does: 0x036A reason 19 under
/// the connection's cipher (0x1400168a0: 19 is 'This account has been
/// disconnected', the account-level text), one info line naming the connection
/// and the account, no ask, and no warning or error.
fn assert_taken_over(taken: ConnectionStep(Request)) -> Nil {
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
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
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      game_connection_support.taken_over(),
    )
  assert_taken_over(taken)
}

pub fn a_claim_answered_taken_over_ends_the_connection_as_a_takeover_does_test() -> Nil {
  use <- owned_test.run(10_000)
  // A newer login holds the slot: Sessions answers the claim `TakenOver`, for
  // a first claim and for a claim made again after Sessions ended in
  // character select.
  let #(state, taken) = game_connection_support.claiming()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert_taken_over(taken)
  let #(state, taken) =
    game_connection_support.claiming_again(
      game_connection_support.in_select_with_a_list(),
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert_taken_over(taken)
}

pub fn a_claim_made_again_in_the_world_and_answered_taken_over_saves_the_place_then_tells_the_client_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.claiming_again(game_connection_support.in_world())
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "a player in the world is saved before the client is told"
  assert support.writes(taken) == [] as "the notice follows the save's answer"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once, with the ask"
  assert line.about.account_id == Some(7)
  let #(_, saved) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      saved,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
  assert support.logs(saved) == []
}

pub fn a_claim_made_again_in_the_world_that_sessions_does_not_answer_saves_the_place_then_tells_the_client_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) =
      game_connection_support.claiming_again(game_connection_support.in_world())
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.entry_place(),
      )
      as "a player in the world is saved before the client is told"
    assert support.writes(taken) == [] as "the notice follows the save's answer"
    let #(_, saved) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert game_connection_support.disconnect(
        saved,
        game_connection_support.keyed(),
      )
      == LostUserServer
  })
}

pub fn a_takeover_while_the_connection_waits_to_claim_again_ends_it_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(_, taken) =
    game_connection_support.feed(state, game_connection_support.taken_over())
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
    as "a takeover Sessions sent before it ended still disconnects the old connection"
}

pub fn a_message_sessions_never_sends_or_one_before_the_claim_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let answer_as_a_message =
    OwnEvent(Woken(message: SentBySessions(message: Claimed)))
  list.each(
    [
      game_connection_support.feed(
        game_connection_support.in_select(),
        answer_as_a_message,
      ).1,
      game_connection_support.feed(
        game_connection_support.connected(),
        game_connection_support.taken_over(),
      ).1,
      game_connection_support.feed(
        replied().0,
        game_connection_support.taken_over(),
      ).1,
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
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
    as "Sessions is likely still restarting, so the claim waits a moment"
  assert support.asked(taken) == None
  // Bytes that arrive during the wait are kept for after the claim.
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert support.asked(taken) == None && support.effects_of(taken) == []
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    as "the ended watch is forgotten, so the one watch is opened again under its id"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(_, taken) = game_connection_support.claimed(state:, taken:)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "Claimed puts the connection back in character select with its state, and the 0x07E0 that waited is taken"
}

pub fn bytes_past_the_hold_limit_while_the_claim_waits_end_the_connection_with_an_error_and_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let waiting_on_the_timer =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    ).0
  let claim_out = game_connection_support.claiming().0
  list.each([waiting_on_the_timer, claim_out], fn(state) {
    let #(state, taken) =
      game_connection_support.read(state, <<0:size(support.held_limit * 8)>>)
    assert !support.stops(taken)
      as "bytes up to the limit are kept for after the claim"
    let #(_, taken) = game_connection_support.read(state, <<0>>)
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
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFE,
      0xFF,
      0x01,
      0x00,
      0,
      0,
    >>)
  assert !support.stops(taken)
    as "a frame of 131,070 bytes is the biggest the client's reader takes, so the connection waits for the rest"
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFF,
      0xFF,
      0x01,
      0x00,
      0,
      0,
    >>)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.writes(taken) == []
    as "a client whose frame the client's own reader would refuse is told nothing"
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFF,
      0xFF,
      0x01,
      0x00,
    >>)
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
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 5, per_second: 2),
      ),
    ).0
  let #(state, taken) =
    game_connection_support.read(state, support.pings(count: 5))
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
  let #(_, taken) = game_connection_support.read(state, support.ping(5))
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
      state: game_connection_support.accepted(
        Settings(
          ..game_connection_support.settings(),
          rate: support.bucket(burst: 5, per_second: 2),
        ),
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
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 2, per_second: 3),
      ),
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
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 3, per_second: 100),
      ),
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
  let #(_, whole) =
    game_connection_support.read(
      game_connection_support.accepted(
        Settings(..game_connection_support.settings(), rate:),
      ).0,
      bytes,
    )
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
      state: game_connection_support.accepted(
        Settings(..game_connection_support.settings(), rate:),
      ).0,
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
      let #(state, taken) = game_connection_support.read(state, <<byte>>)
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
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let state = game_connection_support.claimed(state:, taken:).0
  let #(state, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(1)))
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
}

pub fn a_watch_or_timer_the_rule_did_not_open_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  list.each(
    [
      game_connection_support.feed(
        game_connection_support.in_select_with_a_list(),
        WatchEnded(WatchId(9)),
      ).1,
      game_connection_support.feed(
        game_connection_support.in_select_with_a_list(),
        OwnEvent(TimerFired(TimerId(1))),
      ).1,
      game_connection_support.feed(waiting, WatchEnded(WatchId(1))).1,
      game_connection_support.feed(waiting, OwnEvent(TimerFired(TimerId(2)))).1,
      game_connection_support.feed(replied().0, WatchEnded(WatchId(1))).1,
      game_connection_support.feed(
        game_connection_support.connected(),
        OwnEvent(TimerFired(TimerId(1))),
      ).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_claim_timer_that_fires_while_the_claims_ask_is_out_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(claim_after_the_hand_off, _) = game_connection_support.claiming()
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(claim_after_the_watch_ended, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
    as "the timer's firing made the claim, so its ask is out"
  list.each([claim_after_the_hand_off, claim_after_the_watch_ended], fn(state) {
    let #(_, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
    assert support.stops(taken)
      as "the timer is waited on only before the claim is asked; a second claim would put two asks out"
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
  })
}

pub fn a_claim_that_finds_sessions_not_running_is_made_again_after_a_wait_up_to_the_retries_then_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.claiming()
  let retry = fn(held: #(game_connection.State, ConnectionStep(Request)), _try) {
    let #(state, taken) = held
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome: NotRunning)
    assert support.effects_of(taken)
      == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
      as "the watch on a Sessions that is not running is dropped, and the claim waits"
    assert support.asked(taken) == None
    assert support.writes(taken) == []
    let #(state, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
    assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    assert game_connection_support.ask_request(taken)
      == game_connection_support.claim_ask()
    #(state, taken)
  }
  let #(state, taken) =
    int.range(from: 1, to: claim_retries + 1, with: #(state, taken), run: retry)
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "after the retries the client is told the server failed, or it would wait on its prompt for good"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line:, words: "sessions was not running")
}

pub fn a_claim_that_finds_sessions_not_running_after_its_end_is_made_again_with_the_same_bound_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
}

pub fn a_claim_sessions_does_not_answer_gets_0x036a_reason_8_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = game_connection_support.claiming()
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
      as "0x1400168a0: 8 is 'Lost connection with user server.', as for the store"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.peer == Some(support.peer)
    assert line.about.account_id == Some(7)
  })
  // A claim that Sessions does not answer on a claim made again after its end.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
}

pub fn an_answer_to_the_claim_that_is_none_a_claim_gets_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      step.Answer(FromHandOff(Kept)),
    ],
    fn(outcome) {
      let #(state, taken) = game_connection_support.claiming()
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn the_server_stopping_while_a_claim_is_out_or_waited_for_gets_reason_8_with_no_log_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.claiming()
  let #(_, out) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      out,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert support.logs(out) == [] as "a stop is no failure"
  let #(waiting, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(_, stopping) =
    game_connection_support.feed(waiting, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.disconnect(
      stopping,
      game_connection_support.keyed(),
    )
    == LostUserServer
  let #(_, closed) =
    game_connection_support.feed(waiting, step.OwnEvent(step.PeerClosed))
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
  let #(state, taken) = game_connection_support.listing()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "a failing ask ends with reason 8 though a takeover waits behind it"
}

pub fn the_game_rule_names_the_client_messages_it_takes_test() -> Nil {
  use <- owned_test.run(10_000)
  let named = list.sort(game_connection.taken_message_ids(), int.compare)
  assert named
    == [
      0x009A, 0x00BF, 0x00C0, 0x00D5, 0x00F2, 0x00FB, 0x00FC, 0x015A, 0x01C3,
      0x01D4, 0x025B, 0x025C, 0x0352, 0x038C, 0x04DB, 0x058F, 0x0637, 0x063A,
      0x063B, 0x0786, 0x07DD, 0x07E0, 0x0801,
    ]
    as "the ids the rule's doc comment lists: 0x058F, 0x07E0, 0x07DD, 0x025C with the 0x025B it carries, 0x0352, 0x0786, the world carrier 0x038C (the direct ids of sent_message, fact 0x140332920, and 0x038C, fact 0x1403f4900), and the movement, camp and chat messages of the player in the world, 0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC, 0x00BF, 0x00C0, 0x01C3 and 0x01D4, the cast messages 0x009A, 0x04DB and 0x0801 (opcode.0x9a, opcode.0x4db, opcode.0x801), and the choice of how to come back, 0x015A (opcode.0x15a)"
  assert list.sort(game_connection.carried_message_ids(), int.compare)
    == [
      0x009A, 0x00BF, 0x00C0, 0x00D5, 0x00F2, 0x00FB, 0x00FC, 0x015A, 0x01C3,
      0x01D4, 0x04DB, 0x0637, 0x063A, 0x063B, 0x0801,
    ]
    as "the movement, camp, chat, cast and death messages are taken only with the player in the world"
}

pub fn character_select_takes_exactly_the_ids_the_rule_names_and_logs_every_other_client_id_as_unhandled_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = game_connection_support.listed(characters: [])
  let named = game_connection.taken_message_ids()
  list.each(sent_message.all(), fn(id) {
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.keyed_message(id, <<>>),
      )
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
  let #(state, _) = game_connection_support.listed(characters: [])
  list.each(sent_message.all(), fn(id) {
    let assert Ok(carried) = frame.encode(id, <<>>)
      as "the carried frame encodes"
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.keyed_message(0x025C, carried),
      )
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
