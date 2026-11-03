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
////   a play of a character the account does not have with 0x0162, 0x097F, 0x0968, 0x0036 and 0x0117
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
import event_wait
import game_client
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/connection/registry
import genesis_prime/game/connection as game_connection
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{Holder, Put, SessionKey}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream
import genesis_prime/message/camp_countdown
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry
import genesis_prime/message/chat_channel_joined
import genesis_prime/message/chat_line_accepted
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
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/whisper_failed
import genesis_prime/server
import genesis_prime/service
import genesis_prime/store.{type AccountId, AccountId}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import log_capture
import login_client
import login_support
import mailbox_support
import owned_test
import pog
import unitest

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
  hold_session_key(
    started:,
    account:,
    login_name: "jim",
    game_account_id: support.jim().game_account_id,
    key: support.guid_of(1),
  )
}

/// Puts `key` in the tree's hand-off, held for the account.
fn hold_session_key(
  started started: login_support.Started,
  account account: AccountId,
  login_name login_name: String,
  game_account_id game_account_id: guid.Guid,
  key key: guid.Guid,
) -> Nil {
  let #(_sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call(
        started.settings.hand_off,
        Put(
          key: SessionKey(key),
          holder: Holder(account_id: account, login_name:, game_account_id:),
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
  let assert [_tier, _entitlements, _level, listed] =
    game_client.read(game:, count: 4)
  assert listed.message_id == 0x0117
    as "opcode.0x97f, opcode.0x968, opcode.0x36 and opcode.0x117 follow 0x058F and 0x07E0"
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
  let assert [_tier, _entitlements, _level, listed] =
    game_client.read(game: second, count: 4)
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
  connected_as(
    started:,
    port:,
    account:,
    login_name: "jim",
    game_account_id: support.jim().game_account_id,
    key: support.guid_of(1),
  )
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
  let burst = game_client.read(game:, count: burst_length())
  assert list.map(burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
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
  let burst = game_client.read(game:, count: burst_length())
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
  let assert [refused, _tier, _entitlements, level, listed] =
    game_client.read(game:, count: 5)
    as "opcode.0x162.after_create: 0x0162, then 0x097F, 0x0968, 0x0036 and 0x0117"
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
  let assert [_, _, _, _, _, _, _, _, _] =
    game_client.read(game:, count: burst_length())
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
  let assert [_tier, _entitlements, _level, listed] =
    game_client.read(game:, count: 4)
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
  let first = game_client.read(game:, count: burst_length())
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
  let second = game_client.read(game:, count: burst_length())
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
  let _burst = game_client.read(game:, count: burst_length())
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
  let _burst = game_client.read(game:, count: burst_length())
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
  let first_burst = game_client.read(game:, count: burst_length())
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
  let assert [_tier, _entitlements, level, listed] =
    game_client.read(game:, count: 4)
  assert level.message_id == 0x0036 && listed.message_id == 0x0117
    as "opcode.0x594.character_select: 0x36 then 0x117, as at login, on the same connection"
  let assert Ok(listing) = character_list.decode(listed.body)
  assert list.map(listing.characters, fn(entry) { entry.character_id })
    == [character]
    as "the account's character is listed, and no longer held in the world"
  send_play(game:, character_id: character)
  let second_burst = game_client.read(game:, count: burst_length())
  assert list.map(second_burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
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

// ---- two players see each other ----

/// Puts a session key in the hand-off for an account and connects a client with
/// it, reading its character list: the client is in character select.
fn connected_as(
  started started: login_support.Started,
  port port: Int,
  account account: AccountId,
  login_name login_name: String,
  game_account_id game_account_id: guid.Guid,
  key key: guid.Guid,
) -> game_client.Game {
  hold_session_key(started:, account:, login_name:, game_account_id:, key:)
  let game =
    game_client.connect(
      port:,
      session_key: guid.to_wire(key),
      account_name: login_name,
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_, _, _, _] = game_client.read(game:, count: 4)
  game
}

/// The unit id of a 0x262.
fn unit_of(frame: Frame) -> Int {
  assert frame.message_id == 0x0262 as "the frame is a 0x262"
  let assert Ok(unit) = unit_create_player.decode(frame.body) as "0x262 decodes"
  unit.unit_id
}

/// Two clients of two accounts, each with a character, connected in character
/// select; the first plays its character into an empty map, then the second
/// plays its own into the same map. What each read of the entry is.
type TwoEntered {
  TwoEntered(
    started: login_support.Started,
    first: game_client.Game,
    second: game_client.Game,
    second_character: Int,
    /// The first client's whole entry burst.
    first_burst: List(Frame),
    /// The second client's whole entry burst and, after it, the 0x262 of the
    /// first player.
    second_burst: List(Frame),
    /// The 0x262 of the second player the first client was sent.
    seen_second: Frame,
    first_have: BitArray,
    second_have: BitArray,
  )
}

/// The messages of an entry burst the client reads before the zone channel's.
fn burst_length() -> Int {
  list.length(game_client.world_entry_ids)
}

/// A player of an account of its own with a character, connected in character
/// select: the first is the library's account, the others are made for a test.
fn new_player(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int) {
  let port = login_support.ports(started).game_port
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let login_name = case number {
    1 -> "jim"
    _ -> "player" <> int.to_string(number)
  }
  let #(account, game_account_id) = case number {
    1 -> #(
      AccountId(login_support.insert_jim(started)),
      support.jim().game_account_id,
    )
    _ -> {
      let id = support.guid_of(0x20 + number)
      #(
        AccountId(login_support.insert_other(
          started:,
          login_name:,
          game_account_id: id,
        )),
        id,
      )
    }
  }
  let character =
    character_support.insert(
      pool:,
      account:,
      name: character_name,
      class_id: 4,
      path: 2,
    )
  let game =
    connected_as(
      started:,
      port:,
      account:,
      login_name:,
      game_account_id:,
      key: support.guid_of(number),
    )
  #(game, character)
}

fn two_players_enter_one_map() -> TwoEntered {
  let started = login_support.start()
  let #(first, first_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  let #(second, second_character) =
    new_player(started:, number: 2, character_name: "Ann Qu")
  send_play(game: first, character_id: first_character)
  let #(first_burst, first_have) =
    game_client.read_kept(game: first, have: <<>>, count: burst_length())
  send_play(game: second, character_id: second_character)
  let #(second_burst, second_have) =
    game_client.read_kept(game: second, have: <<>>, count: burst_length() + 1)
  let #(seen_second, first_have) =
    game_client.next(game: first, have: first_have)
  TwoEntered(
    started:,
    first:,
    second:,
    second_character:,
    first_burst:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
  )
}

pub fn a_player_entering_is_written_its_whole_burst_before_the_0x262_of_a_player_in_sight_test() -> Nil {
  use <- owned_test.run(60_000)
  let TwoEntered(started:, first:, second:, first_burst:, second_burst:, ..) as entered =
    two_players_enter_one_map()
  assert list.map(first_burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
    as "the first player enters an empty map: its burst only"
  assert list.map(list.take(second_burst, burst_length()), fn(frame) {
      frame.message_id
    })
    == game_client.world_entry_ids
    as "the second player's whole entry burst comes before the 0x262 of the first: a 0x262 of another unit that landed while the client waits on 0x636 could take control (0x1403d9760)"
  let assert [_, own, ..] = second_burst
  assert unit_of(own) == 2 as "the second player's own unit is the map's second"
  let assert [seen_first] = list.drop(second_burst, burst_length())
  assert unit_of(seen_first) == 1
    as "the first player's unit is created for the second player"
  assert unit_of(entered.seen_second) == 2
    as "the second player's unit is created for the first player"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The position a 0x638 of the unit `unit_id` ends at, which is the position of
/// its last kind 2 command.
fn moved_to(frame: Frame, unit_id: Int) -> #(Float, Float, Float) {
  assert frame.message_id == 0x0638 as "the frame is a 0x638"
  let assert Ok(relayed) = unit_movement.decode(frame.body) as "0x638 decodes"
  assert relayed.unit_id == unit_id
    && relayed.reset_movement == 0
    && relayed.kept == 0
  game_client.observe(
    others: dict.from_list([#(unit_id, #(0.0, 0.0, 0.0))]),
    frame:,
  )
  |> dict.get(unit_id)
  |> result.unwrap(#(0.0, 0.0, 0.0))
}

// Every frame the first client reads about the second player's unit comes from
// the second player's own connection, one sender, so its order is the BEAM's
// promise; the second's connection sends a move only to a player it has been
// told sees it, which the first's 0x262 of it shows it has. The only frame
// from another sender is the map's `Gone` when the second's connection ends, and
// the first's connection writes a move that lands after it as nothing.
pub fn two_players_on_one_map_see_each_other_appear_move_and_leave_test() -> Nil {
  use <- owned_test.run(60_000)
  let TwoEntered(
    started:,
    first:,
    second:,
    second_character:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter_one_map()
  assert unit_of(seen_second) == 2
    as "the second player's unit is created for the first, by the second's own connection"
  // The second player moves five times at once; only the first sees it, each
  // move as the second's own connection sent it, in the order sent.
  list.each([0.0, 1.0, 2.0, 3.0, 4.0], fn(step) {
    game_client.send_world(
      game: second,
      message_id: 0x0637,
      body: game_client.moves_body(client_clock: 0x1234, commands: [
        game_client.position_command(x: 100.5 +. step, y: 50.25, z: -200.75),
      ]),
    )
  })
  let #(moves, first_have) =
    game_client.read_kept(game: first, have: first_have, count: 5)
  assert list.map(moves, fn(frame) { moved_to(frame, 2) })
    == [
      #(100.5, 50.25, -200.75),
      #(101.5, 50.25, -200.75),
      #(102.5, 50.25, -200.75),
      #(103.5, 50.25, -200.75),
      #(104.5, 50.25, -200.75),
    ]
    as "opcode.0x638: each move is sent to the viewer, in the order sent"
  // The second player camps out: the first sees its unit go, after its moves.
  game_client.send_world(game: second, message_id: 0x00BF, body: <<1>>)
  let #(_countdown, second_have) =
    game_client.next(game: second, have: second_have)
  game_client.send_world(game: second, message_id: 0x00C0, body: <<>>)
  let #(left, second_have) = game_client.next(game: second, have: second_have)
  assert left.message_id == 0x0594
  let #(gone, first_have) = game_client.next(game: first, have: first_have)
  assert gone.message_id == 0x0355 as "opcode.0x355: the unit is removed"
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == 2
  // It plays again as a new unit, which the first sees appear.
  game_client.send(game: second, message_id: 0x07E0, body: <<>>)
  let #(_list, second_have) =
    game_client.read_kept(game: second, have: second_have, count: 4)
  send_play(game: second, character_id: second_character)
  let #(_again, _second_have) =
    game_client.read_kept(game: second, have: second_have, count: 8)
  let #(back, first_have) = game_client.next(game: first, have: first_have)
  assert unit_of(back) == 3 as "a new unit, never an id given before"
  // The first's 0x262 of it shows the second's connection knows the first sees
  // it, so this move is sent to the first.
  game_client.send_world(
    game: second,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1235, commands: [
      game_client.position_command(x: 7.5, y: 8.5, z: 9.5),
    ]),
  )
  let #(moved_again, first_have) =
    game_client.next(game: first, have: first_have)
  assert moved_to(moved_again, 3) == #(7.5, 8.5, 9.5)
    as "the rejoined player's moves are sent to the run it joined"
  // The second player's client drops: its connection ends, sends nothing, and
  // the map tells the first's connection the unit is gone.
  game_client.close(game: second)
  let #(dropped, _first_have) = game_client.next(game: first, have: first_have)
  assert dropped.message_id == 0x0355
  let assert Ok(destroyed) = unit_destroyed.decode(dropped.body)
  assert destroyed.unit_id == 3
    as "the connection that drops is removed for the first player by the map's Gone"
  game_client.close(game: first)
  login_support.stop(started)
}

// ---- chat on the whole server ----

/// One scripted client at the table: its connection, the bytes read beyond what
/// it has used, and the id of its zone channel as its own 0x1bc gave it.
type Seat {
  Seat(game: game_client.Game, have: BitArray, zone_channel: Int)
}

/// Four players of four accounts enter one map, each reports the zone the
/// client's own terrain gives (0xF2 once, as the client does while the world
/// loads): the first three stand in zone 6009, the fourth in zone 648. The
/// zones are the planted WorldZone rows, whose top zones are 4961 and 35.
fn four_players() -> #(login_support.Started, List(Seat)) {
  let started = login_support.start()
  let seats =
    list.map(
      [#(1, "Zed Qu"), #(2, "Ann Qu"), #(3, "Bob Qu"), #(4, "Cat Qu")],
      fn(player) {
        let #(number, character_name) = player
        let #(game, character) = new_player(started:, number:, character_name:)
        send_play(game:, character_id: character)
        let #(burst, have) =
          game_client.read_kept(game:, have: <<>>, count: burst_length())
        let assert [Frame(body: joined, ..)] =
          list.filter(burst, fn(frame) { frame.message_id == 0x01BC })
          as "the burst gives the zone channel"
        let assert Ok(channel) = chat_channel_joined.decode(joined)
        assert channel.channel_type == 9
        Seat(game:, have:, zone_channel: channel.channel_id)
      },
    )
  #(started, seats)
}

/// Sends the zone the client's terrain gives (0xF2) and settles the seat: every
/// message the server wrote so far is read, so the next read starts after it.
fn reported(seat seat: Seat, zone zone: Int, number number: Int) -> Seat {
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: zone))
  game_client.send_world(game: seat.game, message_id: 0x00F2, body:)
  written_to(seat:, number:).1
}

/// The frames the server wrote to the seat up to its answer to a ping.
fn written_to(seat seat: Seat, number number: Int) -> #(List(Frame), Seat) {
  let #(frames, have) =
    game_client.read_until_pong(game: seat.game, have: seat.have, number:)
  #(frames, Seat(..seat, have:))
}

fn seat_at(seats: List(Seat), index: Int) -> Seat {
  let assert Ok(seat) = list.first(list.drop(seats, index))
    as "the seat is at the table"
  seat
}

fn chat_lines(frames: List(Frame)) -> List(game_client.HeardLine) {
  list.filter_map(frames, fn(frame) { game_client.heard_line(frame:) })
}

pub fn say_yell_emote_whisper_and_zone_reach_the_right_players_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let speaker = seat_at(seats, 0)
  let neighbour = seat_at(seats, 1)
  let far = seat_at(seats, 2)
  let other_zone = seat_at(seats, 3)
  // Each client reports its zone, the third walks out of sight, which the
  // speaker learns by the unit's removal.
  let speaker = reported(seat: speaker, zone: 6009, number: 1)
  let neighbour = reported(seat: neighbour, zone: 6009, number: 1)
  let far = reported(seat: far, zone: 6009, number: 1)
  let other_zone = reported(seat: other_zone, zone: 648, number: 1)
  let away =
    game_client.moves_body(client_clock: 0, commands: [
      game_client.position_command(x: 5000.0, y: 0.0, z: 0.0),
    ])
  game_client.send_world(game: far.game, message_id: 0x0637, body: away)
  let #(_, speaker) = wait_for_frame(seat: speaker, message_id: 0x0355)
  let speaker = written_to(seat: speaker, number: 2).1
  let neighbour = written_to(seat: neighbour, number: 2).1
  let far = written_to(seat: far, number: 2).1
  let other_zone = written_to(seat: other_zone, number: 2).1

  // Say, yell and emote reach the player in sight and no one else.
  let speaker =
    list.fold(
      [#(4, "says"), #(5, "yells"), #(8, "emotes")],
      speaker,
      fn(speaker, line) {
        let #(channel_type, text) = line
        game_client.send_line(
          game: speaker.game,
          channel_type:,
          channel_id: 0,
          text:,
          chat_message_id: channel_type,
        )
        let #(accept, have) =
          game_client.read_accepted(
            game: speaker.game,
            have: speaker.have,
            chat_message_id: channel_type,
          )
        assert accept.name == "Zed Qu"
          as "the speaker sees its own line by the accept"
        Seat(..speaker, have:)
      },
    )
  let speaker = written_to(seat: speaker, number: 3).1
  let #(heard, neighbour) = written_to(seat: neighbour, number: 3)
  assert chat_lines(heard)
    == [
      game_client.HeardLine(
        channel_type: 4,
        channel_id: 0,
        sender: "Zed Qu",
        text: "says",
      ),
      game_client.HeardLine(
        channel_type: 5,
        channel_id: 0,
        sender: "Zed Qu",
        text: "yells",
      ),
      game_client.HeardLine(
        channel_type: 8,
        channel_id: 0,
        sender: "Zed Qu",
        text: "emotes",
      ),
    ]
    as "the player in sight reads the say, the yell and the emote, each on its own channel (Jim, 2026-11-03)"
  let #(far_heard, far) = written_to(seat: far, number: 3)
  assert chat_lines(far_heard) == []
    as "a player out of sight, under the same top zone, hears no say"
  let #(other_heard, other_zone) = written_to(seat: other_zone, number: 3)
  assert chat_lines(other_heard) == chat_lines(heard)
    as "a player in sight hears the say, the yell and the emote whatever top zone it stands under: say reaches the players who see the speaker"

  // A whisper reaches the character named, wherever it stands.
  game_client.whisper(
    game: speaker.game,
    target: "bOb qU",
    text: "psst",
    chat_message_id: 6,
  )
  let #(accept, speaker_have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 6,
    )
  let speaker = Seat(..speaker, have: speaker_have)
  assert accept.name == "Bob Qu"
    as "the speaker sees 'To Bob Qu', the target's own name, though it typed another case"
  let #(far_heard, far) = written_to(seat: far, number: 4)
  assert chat_lines(far_heard)
    == [
      game_client.HeardLine(
        channel_type: 6,
        channel_id: 0,
        sender: "Zed Qu",
        text: "psst",
      ),
    ]
    as "the target reads one whisper on (6, 0), though it is out of sight"
  game_client.whisper(
    game: speaker.game,
    target: "No One",
    text: "hello?",
    chat_message_id: 7,
  )
  let #(failed, speaker) = wait_for_frame(seat: speaker, message_id: 0x01D9)
  let assert Ok(failure) = whisper_failed.decode(failed.body)
  assert failure.target_name == bit_stream.utf16_units("No One")
    && failure.chat_message_id == 7

  // A zone line reaches every player under the speaker's top zone in its run,
  // in sight or not, and no one under another top zone.
  game_client.send_line(
    game: speaker.game,
    channel_type: 9,
    channel_id: speaker.zone_channel,
    text: "zone",
    chat_message_id: 8,
  )
  let #(_, speaker_have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 8,
    )
  let speaker = Seat(..speaker, have: speaker_have)
  let speaker = written_to(seat: speaker, number: 5).1
  let #(neighbour_heard, _) = written_to(seat: neighbour, number: 5)
  let #(far_heard, _) = written_to(seat: far, number: 5)
  let zone_line = fn(frames) {
    list.filter(chat_lines(frames), fn(line) { line.channel_type == 9 })
  }
  let expected = [
    game_client.HeardLine(
      channel_type: 9,
      channel_id: speaker.zone_channel,
      sender: "Zed Qu",
      text: "zone",
    ),
  ]
  assert zone_line(neighbour_heard) == expected
    as "Jim 2026-11-03: the player in sight under the same top zone hears the zone line"
  assert zone_line(far_heard) == expected
    as "and so does the one out of sight: zone reach is the top zone, not sight"
  let #(other_heard, _) = written_to(seat: other_zone, number: 5)
  assert zone_line(other_heard) == []
    as "a player under another top zone, though in sight, hears no zone line"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

fn all_ids(frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

pub fn no_chat_flow_writes_player_info_and_0x597_stays_unhandled_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let speaker = reported(seat: seat_at(seats, 0), zone: 6009, number: 1)
  let neighbour = reported(seat: seat_at(seats, 1), zone: 6009, number: 1)
  let speaker = written_to(seat: speaker, number: 2).1
  let neighbour = written_to(seat: neighbour, number: 2).1
  game_client.say(game: speaker.game, text: "hi", chat_message_id: 1)
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "psst",
    chat_message_id: 2,
  )
  game_client.send_line(
    game: speaker.game,
    channel_type: 9,
    channel_id: speaker.zone_channel,
    text: "zone",
    chat_message_id: 3,
  )
  let #(spoken, _) = written_to(seat: speaker, number: 3)
  let #(heard, _) = written_to(seat: neighbour, number: 3)
  assert list.length(chat_lines(heard)) == 3
    as "the neighbour read the say, the whisper and the zone line"
  list.each(list.append(spoken, heard), fn(frame) {
    assert frame.message_id != 0x0598 && frame.message_id != 0x0599
      as "chat.name_lookup: every 0x1c8 carries its speaker's name, so no chat flow writes player info (0x598 or 0x599)"
  })
  assert list.contains(all_ids(heard), 0x01C8)
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn two_players_whispering_each_other_at_once_both_get_their_answer_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let first = written_to(seat: seat_at(seats, 0), number: 1).1
  let second = written_to(seat: seat_at(seats, 1), number: 1).1
  game_client.whisper(
    game: first.game,
    target: "Ann Qu",
    text: "one",
    chat_message_id: 1,
  )
  game_client.whisper(
    game: second.game,
    target: "Zed Qu",
    text: "two",
    chat_message_id: 1,
  )
  let #(first_frames, _) =
    frames_with(seat: first, message_ids: [0x01C2, 0x01C8])
  let #(second_frames, _) =
    frames_with(seat: second, message_ids: [0x01C2, 0x01C8])
  let accepted_name = fn(frames: List(Frame)) {
    let assert [frame] =
      list.filter(frames, fn(frame) { frame.message_id == 0x01C2 })
    let assert Ok(accept) = chat_line_accepted.decode(frame.body)
    accept.name
  }
  assert accepted_name(first_frames) == "Ann Qu"
    && accepted_name(second_frames) == "Zed Qu"
    as "the design: every send is a tell and none asks, so two whispers at once never wait on each other"
  assert list.map(chat_lines(first_frames), fn(line) { line.text }) == ["two"]
  assert list.map(chat_lines(second_frames), fn(line) { line.text }) == ["one"]
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_target_that_camped_is_not_found_and_is_found_again_after_it_enters_again_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  game_client.send_world(game: target.game, message_id: 0x00BF, body: <<1>>)
  let #(_, have) =
    game_client.read_kept(game: target.game, have: target.have, count: 1)
  game_client.send_world(game: target.game, message_id: 0x00C0, body: <<>>)
  let #(frame, have) = game_client.next(game: target.game, have:)
  assert frame.message_id == 0x0594
    as "the camp returns the client to character select"
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "hi",
    chat_message_id: 1,
  )
  let #(failed, speaker) = wait_for_frame(seat: speaker, message_id: 0x01D9)
  assert failed.message_id == 0x01D9
    as "the design's failure table: after the camp's leave the name group is left, so the whisper gets 0x1d9"
  game_client.send(game: target.game, message_id: 0x07E0, body: <<>>)
  let #(listed, have) =
    game_client.read_kept(game: target.game, have:, count: 4)
  let assert [_, _, _, Frame(body: list_body, ..)] = listed
  let assert Ok(listing) = character_list.decode(list_body)
  let assert [entry] = listing.characters
  send_play(game: target.game, character_id: entry.character_id)
  let #(_, have) =
    game_client.read_kept(game: target.game, have:, count: burst_length())
  let target = Seat(..target, have:)
  let target = written_to(seat: target, number: 3).1
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "again",
    chat_message_id: 2,
  )
  let #(accept, _) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 2,
    )
  assert accept.name == "Ann Qu" as "a new entry joins the name group again"
  let #(target_frames, _) = written_to(seat: target, number: 4)
  assert list.map(chat_lines(target_frames), fn(line) { line.text })
    == ["again"]
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_speaker_that_ends_before_the_reply_leaves_the_target_with_its_line_and_no_error_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("serial")
  let #(started, seats) = four_players()
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "bye",
    chat_message_id: 1,
  )
  game_client.close(game: speaker.game)
  let #(heard, rest) =
    game_client.read_chat(game: target.game, have: target.have)
  assert heard.text == "bye" as "the target's line stands"
  let #(more, _) = written_to(seat: Seat(..target, have: rest), number: 2)
  assert chat_lines(more) == [] as "the target was written the line once"
  log_capture.stop(capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "error"
    })
    == []
    as "the design's failure table: the reply to a dead process is dropped, nothing logged as an error"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_member_whose_connection_crashes_leaves_its_groups_and_later_lines_reach_the_others_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let speaker = reported(seat: seat_at(seats, 0), zone: 6009, number: 1)
  let doomed = reported(seat: seat_at(seats, 1), zone: 6009, number: 1)
  assert doomed.zone_channel == speaker.zone_channel
    as "the member that will crash shares the speaker's zone channel"
  let survivor = reported(seat: seat_at(seats, 2), zone: 6009, number: 1)
  let speaker = written_to(seat: speaker, number: 2).1
  let survivor = written_to(seat: survivor, number: 2).1
  let assert Ok(pid) = registry.find_named(started.settings.registry, "ann qu")
    as "the member is in its name group"
  let gone = process.monitor(pid)
  process.kill(pid)
  let _reason = ask_support.ended(gone)
  event_wait.until("the scope noticed the crash by itself", fn() {
    registry.find_named(started.settings.registry, "ann qu") == Error(Nil)
  })
  game_client.send_line(
    game: speaker.game,
    channel_type: 9,
    channel_id: speaker.zone_channel,
    text: "still here",
    chat_message_id: 1,
  )
  let #(_, _) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 1,
    )
  let #(heard, _) = written_to(seat: survivor, number: 3)
  assert list.map(chat_lines(heard), fn(line) { line.text }) == ["still here"]
    as "the design's failure table: a later line goes to the others, and the dead member is no longer in the group"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

/// Reads until the server writes a message with this id, and gives it.
fn wait_for_frame(
  seat seat: Seat,
  message_id message_id: Int,
) -> #(Frame, Seat) {
  let #(frame, have) = game_client.next(game: seat.game, have: seat.have)
  case frame.message_id == message_id {
    True -> #(frame, Seat(..seat, have:))
    False -> wait_for_frame(seat: Seat(..seat, have:), message_id:)
  }
}

/// Reads until the server has written a message of each id, and gives every
/// message read.
fn frames_with(
  seat seat: Seat,
  message_ids message_ids: List(Int),
) -> #(List(Frame), Seat) {
  collect_frames(seat:, wanted: message_ids, found: [])
}

fn collect_frames(
  seat seat: Seat,
  wanted wanted: List(Int),
  found found: List(Frame),
) -> #(List(Frame), Seat) {
  case wanted {
    [] -> #(list.reverse(found), seat)
    [_, ..] -> {
      let #(frame, have) = game_client.next(game: seat.game, have: seat.have)
      collect_frames(
        seat: Seat(..seat, have:),
        wanted: list.filter(wanted, fn(id) { id != frame.message_id }),
        found: [frame, ..found],
      )
    }
  }
}

pub fn the_bot_numbers_its_chat_message_ids_from_1_and_each_is_answered_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(started, seats) = four_players()
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let chatter = game_client.chatter(game: speaker.game)
  let #(chatter, first) = game_client.say_next(chatter:, text: "one")
  let #(chatter, second) = game_client.say_next(chatter:, text: "two")
  let #(_, third) =
    game_client.whisper_next(chatter:, target: "Ann Qu", text: "three")
  assert [first, second, third] == [1, 2, 3]
    as "0x140405cb0: the client's chat message ids start at 1, and each line takes the next"
  let #(_, have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 1,
    )
  let #(_, have) =
    game_client.read_accepted(game: speaker.game, have:, chat_message_id: 2)
  let #(accept, _) =
    game_client.read_accepted(game: speaker.game, have:, chat_message_id: 3)
  assert accept.name == "Ann Qu"
    as "each line is answered under its own id, the whisper with the target's name"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}
