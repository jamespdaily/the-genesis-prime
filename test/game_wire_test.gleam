//// The game server's listener of the real tree, on a migrated database of the
//// test's own, played by the scripted client (`game_client`): the hello, 0x058F
//// with a session key the hand-off holds, 0x07E0 and the list the store's rows
//// make. Expected values come from these places.
//// - The messages as the fact file records them (opcode.0x3, opcode.0x58f,
////   opcode.0x7e0, opcode.0x117, opcode.0x36a) and the rows the tests insert.
//// - The reasons of 0x036A: 19 "This account has been disconnected"
////   (0x1400168a0).
//// - The create path: 0x025C carries 0x025B (opcode.0x25c), the result is
////   0x00DC (opcode.0xdc, lua.Character.OnCreateCharacterFailed), and the
////   client's 0x07DD after CreateOk gets 0x0162 Failed, 0x0036 and 0x0117
////   (opcode.0x162.after_create, opcode.0x36), with the account's slots 2
////   without an entitlement (lua.CharacterSelection.OnLoadFromCharacter).
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import character_support
import connection_rule_support as support
import game_client
import genesis_prime/hand_off.{Holder, Put, SessionKey}
import genesis_prime/login/guid
import genesis_prime/message/character_list
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/create_result
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{AccountDisconnected}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/service
import genesis_prime/store.{type AccountId, AccountId}
import gleam/dynamic/decode
import gleam/list
import login_support
import owned_test
import pog

/// The 16 bytes the client shows as its session key: the wire bytes of the
/// GUID the hand-off holds.
fn session_key() -> BitArray {
  guid.to_wire(support.guid_of(1))
}

/// The tree with the account of the library's vector inserted, the game
/// listener's port and the account.
fn start() -> #(login_support.Started, Int, AccountId) {
  let #(started, ports, account_id) = login_support.start_with_jim()
  #(started, ports.game_port, AccountId(account_id))
}

/// Puts the session key in the tree's hand-off, held for the account.
fn put_session_key(started: login_support.Started, account: AccountId) -> Nil {
  let #(_sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call(
        started.settings.hand_off,
        Put(
          key: SessionKey(support.guid_of(1)),
          holder: Holder(
            account_id: account,
            login_name: "jim",
            game_account_id: support.jim().game_account_id,
          ),
          lifetime_ms: 60_000,
        ),
        reply,
      )
    })
  assert answer == hand_off.Kept as "the hand-off kept the session key"
  Nil
}

pub fn a_client_with_a_held_session_key_gets_the_hello_and_then_the_list_of_its_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let id =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  put_session_key(started, account)
  let game =
    game_client.connect(port:, session_key: session_key(), account_name: "jim")
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_level, listed] = game_client.read(game:, count: 2)
  assert listed.message_id == 0x0117
    as "opcode.0x36 and opcode.0x117 follow 0x058F and 0x07E0"
  let assert Ok(list) = character_list.decode(listed.body)
  assert list.realm_id == 1 && list.max_characters == 12
    as "the realm's id and the character limit of the tree's game settings"
  let assert [entry] = list.characters
    as "the account's one character, from the store"
  assert entry.character_id == id && entry.name == "Zed"
  assert entry.class_id == 4 && entry.path == 2 && entry.faction_id == 166
    as "the row's values, as character_support inserted them"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_client_whose_session_key_the_hand_off_does_not_hold_gets_0x036a_reason_19_and_is_disconnected_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, _account) = start()
  let game =
    game_client.connect(port:, session_key: session_key(), account_name: "jim")
  let assert [notice] = game_client.read(game:, count: 1)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: AccountDisconnected))
    as "0x1400168a0: 19 is 'This account has been disconnected', for a key the hand-off never held"
  assert game_client.closed(game:) as "the server closes the connection"
  login_support.stop(started)
}

/// A create request for CharacterCreation row 466 with a path of 1 and the
/// look of labels 2 and 22, as the client's bytes.
fn create_request(name: String) -> BitArray {
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        ..character_support.create_request(name),
        path: 1,
        customisation_labels: [2, 22],
        customisation_values: [1, 1],
      ),
    )
    as "the request encodes"
  body
}

fn created_result(
  game: game_client.Game,
) -> create_character_result.CreateCharacterResult {
  character_support.create_result_in(game_client.read(game:, count: 1))
}

/// Connects a client with the account's held session key and sends 0x07E0,
/// reading the list it gets.
fn in_select(
  started started: login_support.Started,
  port port: Int,
  account account: AccountId,
) -> game_client.Game {
  put_session_key(started, account)
  let game =
    game_client.connect(port:, session_key: session_key(), account_name: "jim")
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_level, _list] = game_client.read(game:, count: 2)
  game
}

fn names_of(pool: pog.Connection) -> List(String) {
  let assert Ok(returned) =
    pog.query("select name from character order by character_id")
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(pool)
    as "the names read"
  returned.rows
}

pub fn a_created_character_is_stored_answered_with_create_ok_and_listed_after_the_refused_play_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  let created = created_result(game)
  assert created.result == create_result.CreateOk
    as "opcode.0xdc: a valid request is created"
  assert names_of(pool) == ["Ab Cd"] as "the character is stored"
  game_client.send(game:, message_id: 0x07DD, body: {
    let assert Ok(body) =
      play_character.encode(PlayCharacter(character_id: created.character_id))
      as "0x07DD encodes"
    body
  })
  let assert [refused, level, listed] = game_client.read(game:, count: 3)
    as "opcode.0x162.after_create: 0x0162, then 0x0036 and 0x0117"
  assert refused.message_id == 0x0162
  assert level.message_id == 0x0036
  assert listed.message_id == 0x0117
  let assert Ok(listing) = character_list.decode(listed.body)
  let assert [entry] = listing.characters as "the list holds the new character"
  assert entry.character_id == created.character_id
    && entry.name == "Ab Cd"
    && entry.level == 1
    && entry.race_id == 1
    && entry.gender == 1
    && entry.class_id == 1
    && entry.faction_id == 167
    && entry.path == 1
    as "CharacterCreation row 466 and the request: class 1, race 1, sex 1, faction 167, path 1, level 1"
  assert entry.bone_values == character_support.bones(46)
    as "the bones come back as sent"
  assert entry.last_logged_out_days != 0
    as "lua.CharacterSelection.OnLoadFromCharacter.preselect: the new character carries the last logout the client's rule selects by"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_name_taken_in_another_case_is_name_unavailable_and_nothing_more_is_stored_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let _character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("zED qU"))
  assert created_result(game).result == create_result.NameUnavailable
    as "lua.Character.OnCreateCharacterFailed: 6; the unique index on lower(name) refuses the second"
  assert names_of(pool) == ["Zed Qu"] as "nothing more is stored"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn an_account_at_its_two_slots_is_account_full_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let _character =
    character_support.insert(pool:, account:, name: "Abe", class_id: 4, path: 2)
  let _character =
    character_support.insert(pool:, account:, name: "Cal", class_id: 4, path: 2)
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  assert created_result(game).result == create_result.AccountFull
    as "lua.CharacterSelection.OnLoadFromCharacter: 2 slots without an entitlement; lua.Character.OnCreateCharacterFailed: 9"
  assert names_of(pool) == ["Abe", "Cal"] as "nothing more is stored"
  game_client.close(game:)
  login_support.stop(started)
}
