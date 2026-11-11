//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover the hello, the
//// re-key, the list at login and the connection after it.
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
////   0x082D, and 0x07CC (opcode.0x82d, opcode.0x7cc).
//// - The rule's doc comment, as approved on the card, and the shape's change
////   that the game connection never stops without telling the client after
////   the hello.

import character_tables
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/client_connection.{
  AskHandOff, AskStore, FromHandOff, FromStore,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
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
  ConnectionId, EndedBeforeAnswer, LogError, LogWarning, NoAnswerInTime,
  NotRunning, OtherSocketFailure, StoppedWaiting,
}
import genesis_prime/store.{
  AccountId, Created, ForSelect, ListCharacters, Listed, NameTaken, Select,
  Unavailable,
}
import genesis_prime/table/character_customization
import gleam/list
import gleam/option.{None, Some}
import login_support
import owned_test

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
  let #(state, taken) = login_support.replied()
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
  let #(state, taken) = login_support.replied()
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
    let #(state, taken) = login_support.replied()
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
  let #(state, taken) = login_support.replied()
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
  let #(state, taken) = login_support.replied()
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
  let #(state, taken) = login_support.replied()
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

pub fn message_0x038c_carrying_0x082d_and_0x07cc_are_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.listed(characters: [])
  let #(state, taken) =
    game_connection_support.read(state, <<
      game_connection_support.store_request():bits,
      game_connection_support.unhandled_request():bits,
    >>)
  assert support.unhandled_ids(taken)
    == [Some(#("unhandled", 0x082D)), Some(#("unhandled", 0x07CC))]
    as "opcode.0x38c, opcode.0x82d and opcode.0x7cc: 0x038C carries the whole frame of 0x082D and of 0x07CC, no feature takes either, and each is logged under its own id in order"
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
