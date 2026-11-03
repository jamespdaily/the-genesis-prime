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
////   the account's slots 2 without an entitlement
////   (lua.CharacterSelection.OnLoadFromCharacter); the place a create saves is
////   the WorldLocation2 row of its start (`character_tables`).
//// - World entry: the client's 0x07DD is answered with 0xAD, 0x262, 0x19B,
////   0x6BC, 0x636, 0xF1 and 0x61 (opcode.0xad and the others), the refusal of
////   a play of a character the account does not have with 0x0162, 0x0036 and 0x0117
////   (opcode.0x162.after_create, opcode.0x36), and the end of the player's map
////   with 0x036A reason 8 (0x1400168a0).
//// - The delete path: 0x0352 is answered with 0x00E6 (opcode.0x352,
////   opcode.0xe6, lua.CharacterSelection.OnCharacterDeleteResult), and the
////   rename path: 0x0786 is answered with 0x014B for a character the entry's
////   rename bit marks (opcode.0x786, opcode.0x14b,
////   lua.CharacterSelection.OnCharacterRenameResult).
//// - The camp: 0xBF 1 is answered with 0x92, 0xC0 with 0x594 once the place is
////   saved and the player is out of its map, and the client's 0x07E0 on the
////   same connection with the list as at login (opcode.0xbf, opcode.0xc0,
////   opcode.0x92, opcode.0x594, opcode.0x594.character_select).
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import character_support
import connection_rule_support as support
import game_client
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{Holder, Put, SessionKey}
import genesis_prime/login/guid
import genesis_prime/message/camp_countdown
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/create_result
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/delete_result
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/enter_world
import genesis_prime/message/float32
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/store.{type AccountId, AccountId}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import gleam/bool
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import login_client
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

pub fn a_second_login_to_the_account_disconnects_the_first_with_0x036a_reason_19_and_gets_its_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let _id =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  let first = in_select(started:, port:, account:)
  let second = in_select(started:, port:, account:)
  // The second login's list came after its claim, which sent the first
  // connection its takeover.
  let assert [notice] = game_client.read(game: first, count: 1)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: AccountDisconnected))
    as "0x1400168a0: 19 is 'This account has been disconnected', which the connection a newer login took over gets"
  assert game_client.closed(game: first) as "and the server closes it"
  // The newest login stays connected: its ping is answered.
  game_client.send(game: second, message_id: 0x07E0, body: <<>>)
  let assert [_level, listed] = game_client.read(game: second, count: 2)
  assert listed.message_id == 0x0117
    as "the second connection still plays: its list is asked and answered"
  game_client.close(game: second)
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

pub fn a_stop_closes_every_listener_to_new_connects_before_an_open_game_connection_drains_and_it_still_gets_0x036a_reason_8_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, ports, account_id) = login_support.start_with_jim()
  let account = AccountId(account_id)
  let game = in_select(started:, port: ports.game_port, account:)
  let assert [connection] =
    ask_support.connections_of(started.settings.game.listener)
    as "the game listener holds the one connection"
  // The connection is held back, so the game listener's stop waits for it
  // while the connects below are tried.
  let stopping =
    ask_support.while_suspended(process: connection, body: fn() {
      let stopping = ask_support.begin_stop_tree(started.tree)
      await_refused(ports.game_port)
      assert login_client.refused(ports.sts_port)
        as "the STS listener no longer takes a socket by the time the game listener's is closed: the stop closes the listeners before it drains any connection"
      assert login_client.refused(ports.auth_port)
        as "nor does the auth listener"
      stopping
    })
  let assert [notice] = game_client.read(game:, count: 1)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: LostUserServer))
    as "0x1400168a0: 8 is the server's own end, which the open connection is told when the stop reaches it"
  assert game_client.closed(game:) as "and the server closes it"
  let _reason = ask_support.ended(stopping)
  Nil
}

/// Waits until a connect to the port is refused: a wait for the listener to
/// close, ended by the test's own deadline.
fn await_refused(port: Int) -> Nil {
  use <- bool.guard(when: login_client.refused(port), return: Nil)
  process.sleep(1)
  await_refused(port)
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

pub fn a_created_character_is_stored_at_its_start_place_answered_with_create_ok_listed_and_played_into_the_world_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  let created = created_result(game)
  assert created.result == create_result.CreateOk
    as "opcode.0xdc: a valid request is created"
  assert names_of(pool) == ["Ab Cd"] as "the character is stored"
  let assert [entry] = listed_entries(game)
    as "the list holds the new character"
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
  assert entry.world_id == 3460
    && entry.world_zone_id == 6009
    && entry.position_x == 0x41E9075F
    && entry.position_y == 0xC45577C8
    && entry.position_z == 0xC40C0C08
    as "row 466 is a PreTutorial start, WorldLocation2 row 51596: World 3460, zone 6009, and its position as 32-bit floats; the database kept them"
  send_play(game:, character_id: created.character_id)
  let burst = game_client.read(game:, count: 7)
  assert list.map(burst, fn(frame) { frame.message_id })
    == [0x00AD, 0x0262, 0x019B, 0x06BC, 0x0636, 0x00F1, 0x0061]
    as "the player enters the world: the messages in the client's order (opcode.0xad, opcode.0x262, opcode.0x19b, opcode.0x6bc, opcode.0x636, opcode.0xf1, opcode.0x61)"
  let assert [Frame(body: world, ..), Frame(body: unit, ..), ..] = burst
  let assert Ok(entered) = enter_world.decode(world)
  assert entered.world_id == 3460
    && entered.position_x == entry.position_x
    && entered.position_z == entry.position_z
    as "0xAD carries the place the database saved"
  assert entered.position_x == 0x41E9075F
    && entered.position_y == 0xC45577C8
    && entered.position_z == 0xC40C0C08
    as "0xAD carries the position of WorldLocation2 row 51596 as 32-bit floats"
  assert game_client.unit_create_player_in(frames: burst).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0x41E9075F,
        y: 0xC45577C8,
        z: 0xC40C0C08,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0xC03017E2,
        pitch: 0x80000000,
        roll: 0,
        blends: 0,
      )),
    ]
    as "0x262 places the player at row 51596 facing the yaw the client's QuaternionToEulerAngles (0x1401b2fe0) gives the row's facing, 0xc03017e2, pitch -0.0 (0x80000000) and roll 0"
  let assert Ok(player) = unit_create_player.decode(unit)
  assert player.character_id == created.character_id
    && player.name == "Ab Cd"
    && player.realm_id == 1
    && player.unit_id == 1
    as "0x262 is the character, in the realm of the settings, as the first unit of its map"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_created_dominion_cassian_veteran_is_played_into_the_world_at_row_42148_facing_the_clients_yaw_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let game = in_select(started:, port:, account:)
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        ..character_support.create_request("Ab Cd"),
        creation_id: 359,
        path: 1,
        customisation_labels: [2, 21],
        customisation_values: [1, 2],
        bone_values: character_support.bones(48),
      ),
    )
    as "the request encodes"
  game_client.send_create(game:, body:)
  let created = created_result(game)
  assert created.result == create_result.CreateOk
    as "opcode.0xdc: a valid request is created"
  send_play(game:, character_id: created.character_id)
  let burst = game_client.read(game:, count: 7)
  let assert [Frame(body: world, ..), ..] = burst
  let assert Ok(entered) = enter_world.decode(world)
  assert entered.world_id == 1387
    && entered.position_x == 0xC56FBBEC
    && entered.position_y == 0xC4750DE8
    && entered.position_z == 0xC5BD2A1C
    as "row 359 is a Nexus start of Dominion (166) Cassian (race 1): WorldLocation2 row 42148 (Quest2.10530.links, the retail race split), World 1387 and its position as 32-bit floats"
  assert game_client.unit_create_player_in(frames: burst).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0xC56FBBEC,
        y: 0xC4750DE8,
        z: 0xC5BD2A1C,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0xC0490FDA,
        pitch: 0x80000000,
        roll: 0,
        blends: 0,
      )),
    ]
    as "0x262 places the player at row 42148 facing the yaw QuaternionToEulerAngles (0x1401b2fe0) gives its facing in the emulator: 0xc0490fda, pitch 0x80000000, roll 0"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_play_of_a_character_the_account_does_not_have_gets_0x0162_failed_and_the_list_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let other =
    login_support.insert_account(
      pool:,
      login_name: "login-2",
      salt: <<1>>,
      verifier: <<1>>,
      game_account_id: support.guid_of(0x22),
    )
  let theirs =
    character_support.insert(
      pool:,
      account: AccountId(other),
      name: "Abe",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: theirs)
  let assert [refused, level, listed] = game_client.read(game:, count: 3)
    as "opcode.0x162.after_create: 0x0162, then 0x0036 and 0x0117"
  assert refused.message_id == 0x0162
  assert level.message_id == 0x0036
  assert listed.message_id == 0x0117
  let assert Ok(listing) = character_list.decode(listed.body)
  assert listing.characters == []
    as "the account has no characters: the read is scoped by its id, so another account's character is not played, nor listed"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn the_end_of_the_players_map_tells_the_client_reason_8_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let assert [_, _, _, _, _, _, _] = game_client.read(game:, count: 7)
    as "the player entered the world"
  // The player's map is the run the real Maps holds for the character's world.
  let assert Ok(found) =
    world_map_registry.find_or_start(
      started.settings.world.maps,
      MapId(world_id: 1387, instance: 0),
      deadline_ms: ask_support.monotonic_ms() + ask_support.event_wait_ms,
    )
    as "the map is running, started by the play"
  process.kill(found.pid)
  let assert [Frame(message_id: 0x036A, body:)] =
    game_client.read(game:, count: 1)
    as "opcode.0x36a: the connection watches the map it is in, so its end tells the client"
  assert disconnect_notice.decode(body)
    == Ok(DisconnectNotice(reason: LostUserServer))
    as "0x1400168a0: 8, 'Lost connection with user server.'"
  assert game_client.closed(game:) as "and the connection ends"
  login_support.stop(started)
}

/// Sends 0x07DD for the character.
fn send_play(
  game game: game_client.Game,
  character_id character_id: Int,
) -> Nil {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id:))
    as "0x07DD encodes"
  game_client.send(game:, message_id: 0x07DD, body:)
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
    as "lua.Character.OnCreateCharacterFailed: 6; the unique index on the lower-cased name refuses the second"
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

// ---- delete and rename ----

fn send_delete(game: game_client.Game, character_id: Int) -> Nil {
  let assert Ok(body) = delete_character.encode(DeleteCharacter(character_id:))
    as "0x0352 encodes"
  game_client.send(game:, message_id: 0x0352, body:)
}

fn send_rename(
  game game: game_client.Game,
  character_id character_id: Int,
  name name: String,
) -> Nil {
  let assert Ok(body) =
    rename_character.encode(RenameCharacter(character_id:, name:))
    as "0x0786 encodes"
  game_client.send(game:, message_id: 0x0786, body:)
}

/// Asks for the list again, as the client does when it opens character select,
/// and gives its entries.
fn listed_entries(
  game: game_client.Game,
) -> List(character_list_entry.CharacterListEntry) {
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_level, listed] = game_client.read(game:, count: 2)
  let assert Ok(list) = character_list.decode(listed.body)
  list.characters
}

pub fn a_delete_of_the_accounts_character_is_0x00e6_result_0_and_the_next_list_omits_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  let _abe =
    character_support.insert(pool:, account:, name: "Abe", class_id: 4, path: 2)
  let game = in_select(started:, port:, account:)
  send_delete(game, zed)
  assert character_support.delete_result_in(game_client.read(game:, count: 1))
    == DeleteCharacterResult(result: delete_result.DeleteOk, value: 0)
    as "opcode.0xe6: result 0, and the value nothing reads (opcode.0xe6.value)"
  assert names_of(pool) == ["Abe"] as "the row is deleted"
  assert list.map(listed_entries(game), fn(entry) { entry.name }) == ["Abe"]
    as "the next 0x0117 omits the deleted character"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_delete_of_a_character_another_account_has_is_0x00e6_result_1_and_deletes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let other =
    AccountId(login_support.insert_account(
      pool:,
      login_name: "other",
      salt: <<1>>,
      verifier: <<2>>,
      game_account_id: support.guid_of(0x22),
    ))
  let theirs =
    character_support.insert(
      pool:,
      account: other,
      name: "Cal",
      class_id: 1,
      path: 1,
    )
  let game = in_select(started:, port:, account:)
  send_delete(game, theirs)
  assert character_support.delete_result_in(game_client.read(game:, count: 1))
    == DeleteCharacterResult(result: delete_result.DeleteFailed, value: 0)
    as "lua.CharacterSelection.OnCharacterDeleteResult: 1; a modified client could send any id"
  assert names_of(pool) == ["Cal"] as "nothing is deleted"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_rename_of_a_marked_character_is_0x014b_result_18_and_the_next_list_shows_the_name_with_the_bit_clear_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  character_support.mark_for_rename(pool:, name: "Zed")
  let game = in_select(started:, port:, account:)
  let assert [marked] = listed_entries(game)
  assert marked.requires_rename == 1
    as "opcode.0x117: the bit the client offers a rename by (lua.CharacterSelection.OnSelectCharacter)"
  send_rename(game:, character_id: zed, name: "Ab Cd")
  assert character_support.rename_result_in(game_client.read(game:, count: 1))
    == RenameCharacterResult(
      result: rename_result.RenameOk,
      character_id: zed,
      name: "Ab Cd",
    )
    as "opcode.0x14b: result 18 with the id and the stored name"
  let assert [renamed] = listed_entries(game)
  assert renamed.name == "Ab Cd" && renamed.requires_rename == 0
    as "the row is renamed and unmarked"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_rename_to_a_name_taken_in_any_case_is_0x014b_16_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  let _abe =
    character_support.insert(
      pool:,
      account:,
      name: "Abe Cd",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool:, name: "Zed")
  let game = in_select(started:, port:, account:)
  send_rename(game:, character_id: zed, name: "aBE cD")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.NameUnavailable
    as "lua.CharacterSelection.OnCharacterRenameResult: 16; the unique index on the lower-cased name refuses it"
  assert names_of(pool) == ["Zed", "Abe Cd"] as "nothing changes"
  let assert [still_marked, _] = listed_entries(game)
  assert still_marked.requires_rename == 1
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_rename_with_a_name_failing_rule_0_is_0x014b_15_and_an_unmarked_character_is_13_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(pool:, account:, name: "Zed", class_id: 4, path: 2)
  let game = in_select(started:, port:, account:)
  send_rename(game:, character_id: zed, name: "Abcd")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.NameLength
    as "lua.CharacterSelection.OnCharacterRenameResult: 15; rule 0 wants a first and a last name"
  send_rename(game:, character_id: zed, name: "Ab Cd")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.RenameFailed
    as "lua.CharacterSelection.OnCharacterRenameResult: 13; the character is not marked, so the client would not offer a rename"
  assert names_of(pool) == ["Zed"] as "nothing changes"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- the player moves and the place is kept ----

/// Sends 0x0637 holding a position and a rotation, as the client's movement
/// update does (opcode.0x637).
fn send_move(
  game game: game_client.Game,
  position position: #(Float, Float, Float),
  rotation rotation: #(Float, Float, Float),
) -> Nil {
  let body =
    game_client.moves_body(client_clock: 0x1234, commands: [
      game_client.position_command(x: position.0, y: position.1, z: position.2),
      game_client.rotation_command(
        yaw: rotation.0,
        pitch: rotation.1,
        roll: rotation.2,
      ),
    ])
  game_client.send_world(game:, message_id: 0x0637, body:)
}

pub fn a_player_who_moves_and_drops_is_saved_and_stands_where_it_left_at_the_next_login_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let first = game_client.read(game:, count: 7)
  assert game_client.unit_create_player_in(frames: first).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: float32.to_bits(1.5),
        y: float32.to_bits(2.5),
        z: float32.to_bits(3.5),
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ]
    as "a character never saved starts where the test inserted it, facing 0, 0, 0"
  send_move(game:, position: #(100.5, -20.25, 300.125), rotation: #(
    1.5,
    -0.25,
    0.5,
  ))
  game_client.close(game:)
  login_support.await_no_game_connection(started)
  assert character_support.place_row(pool:, character_id: character)
    == character_support.PlaceRow(
      world_id: 1387,
      world_zone_id: 1100,
      position: #(100.5, -20.25, 300.125),
      rotation: #(1.5, -0.25, 0.5),
      session_epoch: 1,
      save_sequence: 1,
    )
    as "the drop saved the place the client last sent, at the epoch its login raised and as its first save"
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let second = game_client.read(game:, count: 7)
  let assert [Frame(body: world, ..), ..] = second
  let assert Ok(entered) = enter_world.decode(world)
  assert entered.position_x == float32.to_bits(100.5)
    && entered.position_y == float32.to_bits(-20.25)
    && entered.position_z == float32.to_bits(300.125)
    as "0xAD loads the world where the player left"
  assert game_client.unit_create_player_in(frames: second).movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: float32.to_bits(100.5),
        y: float32.to_bits(-20.25),
        z: float32.to_bits(300.125),
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: float32.to_bits(1.5),
        pitch: float32.to_bits(-0.25),
        roll: float32.to_bits(0.5),
        blends: 0,
      )),
    ]
    as "0x262 places the player there at once, facing the way it faced"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_stop_with_a_player_in_the_world_saves_the_place_it_last_stood_at_before_the_tree_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let _burst = game_client.read(game:, count: 7)
  send_move(game:, position: #(100.5, -20.25, 300.125), rotation: #(
    1.5,
    -0.25,
    0.5,
  ))
  game_client.send_ping(game:, number: 1)
  assert game_client.read_pong(game:) == 1
    as "the connection answers after it took the move, which came first on its one socket"
  login_support.stop(started)
  let assert [notice] = game_client.read(game:, count: 1)
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: LostUserServer))
    as "0x1400168a0: 8 is the server's own end, which the player in the world is told once its place is saved"
  let assert Ok(after) =
    pog.start(
      pog.Config(
        ..started.settings.pool,
        pool_name: process.new_name("after_the_stop"),
      ),
    )
    as "a pool of its own reads the database the stopped tree had"
  process.unlink(after.pid)
  assert character_support.place_row(pool: after.data, character_id: character)
    == character_support.PlaceRow(
      world_id: 1387,
      world_zone_id: 1100,
      position: #(100.5, -20.25, 300.125),
      rotation: #(1.5, -0.25, 0.5),
      session_epoch: 1,
      save_sequence: 1,
    )
    as "the stop saved the place the client last sent, as the login's first save, before the tree ended"
  process.kill(after.pid)
  game_client.close(game:)
}

pub fn a_connection_that_crashes_saves_nothing_is_not_restarted_and_the_place_saved_before_stands_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(started, port, account) = start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let _burst = game_client.read(game:, count: 7)
  send_move(game:, position: #(100.5, -20.25, 300.125), rotation: #(
    1.5,
    -0.25,
    0.5,
  ))
  // A read of the connection's state after the move, so the move is taken
  // before the connection is killed: the ping's answer comes after it.
  game_client.send_ping(game:, number: 1)
  assert game_client.read_pong(game:) == 1
  let assert [connection] =
    ask_support.connections_of(started.settings.game.listener)
    as "the game listener holds the one connection"
  process.kill(connection)
  login_support.await_no_game_connection(started)
  assert game_client.closed(game:) as "the client's socket is closed with it"
  assert character_support.place_row(pool:, character_id: character)
    == character_support.PlaceRow(
      world_id: 1387,
      world_zone_id: 1100,
      position: #(1.5, 2.5, 3.5),
      rotation: #(0.0, 0.0, 0.0),
      session_epoch: 1,
      save_sequence: 0,
    )
    as "a crash runs no save: the row holds the place it had, and no save was made at this login's epoch (the 60 s save would have been the last)"
  assert ask_support.connections_of(started.settings.game.listener) == []
    as "Ranch starts connections as temporary children, so nothing restarts it"
  login_support.stop(started)
}

// ---- the camp ----

/// The camp countdown the bot's server is started with, in milliseconds: small,
/// since the bot sends 0xC0 as soon as it has read the 0x92 and never waits it
/// out (opcode.0xc0: a Quit does the same).
const bot_countdown_ms = 1500

pub fn a_player_camps_returns_to_character_select_and_plays_the_same_character_again_at_the_place_it_camped_at_test() -> Nil {
  use <- owned_test.run(60_000)
  let started =
    login_support.start_with(change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: game_connection.Settings(
            ..game.settings,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
      )
    })
  let account = AccountId(login_support.insert_jim(started))
  let port = login_support.ports(started).game_port
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let first_burst = game_client.read(game:, count: 7)
  let first = game_client.unit_create_player_in(frames: first_burst)
  assert first.unit_id == 1 as "the first unit of its map"
  // The player walks to a place of its own, then camps there.
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1234, commands: [
      game_client.position_command(x: 100.5, y: 50.25, z: -200.75),
    ]),
  )
  game_client.send_world(game:, message_id: 0x00BF, body: <<1>>)
  let assert [Frame(message_id: 0x0092, body: countdown)] =
    game_client.read(game:, count: 1)
    as "opcode.0xbf: the server answers a start with the camp's countdown, 0x92"
  let assert Ok(counting) = camp_countdown.decode(countdown)
  assert counting.countdown_ms == bot_countdown_ms && counting.cancel == 0
    as "the settings' countdown, with the cancel bit clear"
  game_client.send_world(game:, message_id: 0x00C0, body: <<>>)
  let assert [Frame(message_id: 0x0594, body: leaving)] =
    game_client.read(game:, count: 1)
    as "opcode.0xc0: the server saves, takes the player out of its map and answers 0x594"
  assert leaving == <<1>>
    as "vector.opcode.0x594.body: the bit set and reason 0 return the client to character select"
  // The client's new character select sends 0x7E0 and is answered as at login.
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [level, listed] = game_client.read(game:, count: 2)
  assert level.message_id == 0x0036 && listed.message_id == 0x0117
    as "opcode.0x594.character_select: 0x36 then 0x117, as at login, on the same connection"
  let assert Ok(listing) = character_list.decode(listed.body)
  assert list.map(listing.characters, fn(entry) { entry.character_id })
    == [character]
    as "the account's character is listed, and no longer held in the world"
  send_play(game:, character_id: character)
  let second_burst = game_client.read(game:, count: 7)
  assert list.map(second_burst, fn(frame) { frame.message_id })
    == [0x00AD, 0x0262, 0x019B, 0x06BC, 0x0636, 0x00F1, 0x0061]
    as "the play enters the world again as at the first entry"
  let second = game_client.unit_create_player_in(frames: second_burst)
  assert second.unit_id == 2
    as "opcode.0x262: the camp took the first unit out of the map, and the map never gives a unit id twice"
  let assert Ok(start_movement.Position(position)) =
    list.first(second.movement_commands)
    as "0x262 places the unit first"
  assert position
    == UnitPositionCommand(
      x: float32.to_bits(100.5),
      y: float32.to_bits(50.25),
      z: float32.to_bits(-200.75),
      blends: 0,
    )
    as "the place the player camped at, saved before 0x594: the camp's save is done before the client can pick the character again"
  game_client.close(game:)
  login_support.stop(started)
}
