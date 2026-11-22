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
////   0x25E, 0x6BC, 0x636, 0xF1 and 0x61 (opcode.0xad and the others), the refusal of
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

import ability_points_support
import ask_support
import bot_frames
import cast_support
import character_support
import character_tables
import connection_rule_support as support
import content_support
import driven_time
import event_wait
import fight_bot
import fixture_tables
import game_client
import game_connection_support
import genesis_prime
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/connection/registry
import genesis_prime/content
import genesis_prime/content/projector_landing as content_projector_landing
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/tutorial_quest as content_tutorial_quest
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/movement
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{Holder, Put, SessionKey}
import genesis_prime/import_world_data
import genesis_prime/login/guid
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/bit_stream
import genesis_prime/message/camp_countdown
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result.{TargetIsNotUseable}
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry
import genesis_prime/message/chat_line_accepted
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/combat_result
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
import genesis_prime/message/experience_gained
import genesis_prime/message/float32
import genesis_prime/message/game_server_handoff
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/interaction_result
import genesis_prime/message/item_added
import genesis_prime/message/item_move
import genesis_prime/message/item_place
import genesis_prime/message/item_removed
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/movement_command
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags
import genesis_prime/message/movement_velocity
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/player_character_state
import genesis_prime/message/player_health
import genesis_prime/message/quest_log as quest_message
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/message/relayed_movement
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_damage
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_position
import genesis_prime/message/spell_started
import genesis_prime/message/start_movement
import genesis_prime/message/static_unit_type
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_cast
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_float_stat_changed
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_level.{UnitStatLevel}
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/message/unit_stealth
import genesis_prime/message/whisper_failed
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/service
import genesis_prime/sitting_bot
import genesis_prime/step
import genesis_prime/store.{type AccountId, AccountId}
import genesis_prime/table/id.{XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_life.{Attack, Combat}
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/game_number.{type GameNumbers, GameNumbers}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/float
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/system
import gleam/result
import gleam_community/maths
import item_bot
import level_up_support
import limited_action_set_support as limited
import log_capture
import login_client
import login_support
import login_vectors as vector
import mailbox_support
import message_support
import novice_tables
import open_wait
import owned_key
import owned_test
import place_support
import planted_table
import pog
import quest_bot
import quest_support
import rating_support
import socket_read
import spawn_support
import terrain_support
import tutorial_bot
import unitest
import vendor_support

/// The 16 bytes the client shows as its session key: the wire bytes of the
/// GUID the hand-off holds.
fn session_key() -> BitArray {
  guid.to_wire(support.guid_of(1))
}

/// The number of an account, as the client sends it in 0x058F.
fn account_number(account: AccountId) -> Int {
  let AccountId(number) = account
  number
}

/// The tree on the driven clock `time` with the account of the library's vector
/// inserted, the game listener's port and the account.
fn start(
  time time: driven_time.Time,
) -> #(login_support.Started, Int, AccountId) {
  let #(started, ports, account_id) = login_support.start_with_jim(time:)
  #(started, ports.game_port, AccountId(account_id))
}

/// How long the hand-off holds a session key the auth server gives on this tree:
/// the `session_key_lifetime_ms` of its auth settings, which the auth connection
/// puts in each Put it sends the hand-off.
fn session_key_lifetime_ms(started: login_support.Started) -> Int {
  started.settings.login.auth.settings.session_key_lifetime_ms
}

/// The session key the auth server gives one login of the library's vector on
/// the tree at `ports`, taken from its 0x3db.
fn session_key_of_a_login(ports: login_client.Ports) -> guid.Guid {
  let login =
    login_client.sts_login(
      ports:,
      name: vector.name,
      password: vector.password,
      seed: 7,
      limit: socket_read.Open,
    )
  let socket =
    login_client.auth_login(
      ports:,
      login:,
      build: 16_042,
      limit: socket_read.Open,
    )
  let assert [_accepted, handoff] =
    login_client.read_frames(
      client: socket,
      have: <<>>,
      count: 2,
      limit: socket_read.Open,
    )
    as "0x591 then 0x3db"
  let assert Ok(handed) =
    game_server_handoff.decode(login_client.in_the_auth_wrapper(handoff).body)
    as "0x3db decodes"
  let assert Ok(key) = guid.from_wire(handed.session_key)
    as "the session key is a GUID"
  key
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
  assert offer_session_key(
      started:,
      account:,
      login_name:,
      game_account_id:,
      key:,
    )
    == hand_off.Kept
    as "the hand-off kept the session key"
  Nil
}

/// What the hand-off answers a put of `key` for the account: `Kept` when it holds
/// no such key, `AlreadyHeld` when it does.
fn offer_session_key(
  started started: login_support.Started,
  account account: AccountId,
  login_name login_name: String,
  game_account_id game_account_id: guid.Guid,
  key key: guid.Guid,
) -> hand_off.Answer {
  let #(_sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call(
        started.settings.hand_off,
        Put(
          key: SessionKey(key),
          holder: Holder(account_id: account, login_name:, game_account_id:),
          lifetime_ms: session_key_lifetime_ms(started),
        ),
        reply,
      )
    })
  answer
}

pub fn a_client_with_a_held_session_key_gets_the_hello_and_then_the_list_of_its_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  // The list's path is the character's own: an entry built with path 0 fails the last assert.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let id =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  put_session_key(started, account)
  let game =
    game_client.connect(
      port:,
      account_id: account_number(account),
      session_key: session_key(),
      account_name: "jim",
      limit: socket_read.Open,
    )
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
  assert entry.character_id == id && entry.name == "Zed Qu"
  assert entry.class_id == 4 && entry.path == 2 && entry.faction_id == 166
    as "the row's values, as character_support inserted them"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_second_login_to_the_account_disconnects_the_first_with_0x036a_reason_19_and_gets_its_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let _id =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let first = in_select(started:, port:, account:)
  let second = in_select(started:, port:, account:)
  // The second login's list came after its claim, which sent the first
  // connection its takeover.
  let assert [notice] = game_client.read(game: first, count: 1)
  game_client.nothing_more(game: first)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: AccountDisconnected))
    as "0x1400168a0: 19 is 'This account has been disconnected', which the connection a newer login took over gets"
  open_wait.named(
    "the first connection to close after a newer login took over",
    fn() { game_client.await_closed(game: first) },
  )
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let game =
    game_client.connect(
      port:,
      account_id: account_number(account),
      session_key: session_key(),
      account_name: "jim",
      limit: socket_read.Open,
    )
  let assert [notice] = game_client.read(game:, count: 1)
  game_client.nothing_more(game:)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: AccountDisconnected))
    as "0x1400168a0: 19 is 'This account has been disconnected', for a key the hand-off never held"
  open_wait.named(
    "the connection to close after a key the hand-off never held",
    fn() { game_client.await_closed(game:) },
  )
  login_support.stop(started)
}

pub fn a_session_key_the_auth_server_gave_expires_only_when_the_driven_clock_passes_its_lifetime_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, ports, account_id) = login_support.start_with_jim(time:)
  let account = AccountId(account_id)
  let lifetime_ms = session_key_lifetime_ms(started)
  let early = session_key_of_a_login(ports)
  let late = session_key_of_a_login(ports)
  let probe = session_key_of_a_login(ports)
  let offered = fn(key) {
    offer_session_key(
      started:,
      account:,
      login_name: "jim",
      game_account_id: support.jim().game_account_id,
      key:,
    )
  }
  driven_time.advance(time:, ms: lifetime_ms - 1)
  assert offered(probe) == hand_off.AlreadyHeld
    as "1 ms before its lifetime has passed on the driven clock a key is still held"
  let held =
    game_client.connect(
      port: ports.game_port,
      account_id: account_number(account),
      session_key: guid.to_wire(early),
      account_name: "jim",
      limit: socket_read.Open,
    )
  game_client.send(game: held, message_id: 0x07E0, body: <<>>)
  let assert [_tier, _entitlements, _level, listed] =
    game_client.read(game: held, count: 4)
  assert listed.message_id == 0x0117
    as "a claim of a key still held is answered with the character list"
  driven_time.advance(time:, ms: 1)
  assert offered(probe) == hand_off.Kept
    as "a key is gone at its expiry time (hand_off.drop_expired): the put finds none held"
  let expired =
    game_client.connect(
      port: ports.game_port,
      account_id: account_number(account),
      session_key: guid.to_wire(late),
      account_name: "jim",
      limit: socket_read.Open,
    )
  let assert [notice] = game_client.read(game: expired, count: 1)
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: AccountDisconnected))
    as "a claim of an expired key gets 0x1400168a0's reason 19, as for a key never held"
  game_client.close(game: held)
  login_support.stop(started)
}

pub fn an_open_game_connection_gets_0x036a_reason_8_when_the_server_stops_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, ports, account_id) = login_support.start_with_jim(time:)
  let game =
    in_select(started:, port: ports.game_port, account: AccountId(account_id))
  let stopping = ask_support.begin_stop_tree(started.tree)
  let assert [notice] = game_client.read(game:, count: 1)
  game_client.nothing_more(game:)
  assert notice.message_id == 0x036A as "opcode.0x36a"
  assert disconnect_notice.decode(notice.body)
    == Ok(DisconnectNotice(reason: LostUserServer))
    as "0x1400168a0: 8 is the server's own end, which the open connection is told when the stop reaches it"
  open_wait.named("the connection to close after the server's stop", fn() {
    game_client.await_closed(game:)
  })
  let _reason =
    ask_support.ended(
      watched: stopping,
      what: "the server's tree to end after its stop",
    )
  Nil
}

/// The stop closes the STS, auth and game listeners to new sockets before it
/// stops any connection (`genesis_prime/connection/closer`). The game
/// connection is held, so it takes no exit until the test lets it. The held
/// connection's own listener stops it only after that listener's socket is
/// closed and after the closer has ended, so the exit reaching it means the
/// stop has begun draining. Each port is then waited on until it refuses: the
/// operating system can take a moment past the owner's exit to close a socket
/// it had just accepted on, and the connection is still held, so every refusal
/// is seen before any connection drained.
pub fn the_stop_closes_every_listener_before_any_connection_drains_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let account = AccountId(login_support.insert_jim(started))
  let ports = login_support.ports(started)
  let _game = in_select(started:, port: ports.game_port, account:)
  let assert [connection] =
    ask_support.connections_of(started.settings.game.listener)
    as "the game listener holds the one connection"
  let stopping =
    ask_support.while_suspended(process: connection, body: fn() {
      let stopping = ask_support.begin_stop_tree(started.tree)
      event_wait.until("the stop's exit reaches the held game connection", fn() {
        mailbox_support.tagged(connection, atom.create("EXIT")) > 0
      })
      event_wait.until(
        "the STS listener takes no socket once the stop is draining connections",
        fn() { login_client.refused(ports.sts_port) },
      )
      event_wait.until("the auth listener takes no socket either", fn() {
        login_client.refused(ports.auth_port)
      })
      event_wait.until("the game listener takes no socket either", fn() {
        login_client.refused(ports.game_port)
      })
      stopping
    })
  let _reason =
    ask_support.ended(
      watched: stopping,
      what: "the server's tree to end once the held connection takes its exit",
    )
  Nil
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
  let burst = game_client.read_entry(game:)
  assert cast_support.ids(frames: burst) == game_client.world_entry_ids
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
  assert game_client.unit_create_player_in(frames: burst).tail.movement_commands
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

pub fn a_created_warriors_entry_gives_the_bot_its_novice_weapon_three_abilities_on_the_bar_and_the_sheets_gear_figures_test() -> Nil {
  use <- owned_test.run(60_000)
  // A created entry whose items are stored at another equipped location fails the loadout asserts.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  let created = created_result(game)
  let _list = listed_entries(game)
  send_play(game:, character_id: created.character_id)
  let burst = game_client.read_entry(game:)
  assert cast_support.ids(frames: burst) == game_client.world_entry_ids
    as "the loadout comes after 0x19b and before 0x61 (opcode.0x19b, opcode.0x61)"
  let loadout = game_client.loadout_in(frames: burst)
  assert loadout.weapon == Some(81_346)
    as "CharacterCreation row 466's weapon, itemId04, is equipped in slot 16 (lua.ActionBarFrame.InitializeBars)"
  assert loadout.abilities == [#(0, 18_309), #(1, 37_968), #(2, 38_017)]
    as "the Warrior's three level-1 spells (SpellLevel rows 919, 920 and 925) as their Spell4Base ids, in bag slots 0 to 2 (opcode.0x111.ability_bag)"
  assert loadout.bar == [#(0, 18_309), #(1, 37_968), #(2, 38_017)]
    as "the bar's large buttons 0 to 2 show the three abilities (opcode.0x19d)"
  assert game_client.sheet(
      unit: game_client.unit_create_player_in(frames: burst),
      tables: character_tables.shared(),
    )
    == game_client.Sheet(
      assault_power: 51,
      support_power: 14,
      max_health: 736,
      max_shield: 450,
    )
    as "player.level1_gear_properties: the sheet shows Assault Power 51 (203.0625 x 0.25), Support Power 14 (55.6875 x 0.25), Max Health 736 and Max Shields 450"
  game_client.close(game:)
  login_support.stop(started)
}

/// The slot and display of each worn visual a 0x262 carries: the item visuals
/// of the armor slots, which are below the body's (slots 24 to 39).
fn worn_in(
  player player: unit_create_player.UnitCreatePlayer,
) -> List(#(Int, Int)) {
  list.filter(player.tail.item_visuals, fn(visual) { visual.slot < 24 })
  |> list.map(fn(visual) {
    assert visual.item_color_set_id == 0 && visual.dye == 0
      as "opcode.0x262.worn_visuals: colour set 0 and dye 0"
    #(visual.slot, visual.display_id)
  })
}

pub fn a_created_warriors_entry_holds_its_six_armor_pieces_draws_its_set_and_leaves_the_sheet_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  // A created entry whose items are stored at another equipped location fails the loadout asserts.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  let created = created_result(game)
  let _list = listed_entries(game)
  send_play(game:, character_id: created.character_id)
  let burst = game_client.read_entry(game:)
  let loadout = game_client.loadout_in(frames: burst)
  assert loadout.armor
    == [
      #(0, 81_359),
      #(1, 81_344),
      #(3, 81_381),
      #(4, 81_345),
      #(5, 81_380),
      #(15, 8534),
    ]
    as "CharacterCreation row 466's chest 81359, legs 81344, shoulder 81381, feet 81345, hands 81380 and shield 8534, each held at the bag index of its slot (opcode.0x111.equipped_set)"
  assert loadout.weapon == Some(81_346) as "the weapon stays in slot 16"
  let player = game_client.unit_create_player_in(frames: burst)
  assert worn_in(player:)
    == novice_tables.worn_visuals(class_id: 1, faction_id: 167)
    as "opcode.0x262.worn_visuals: the Warrior of faction 167 is drawn in its chest 3838, legs 3840, shoulder 530, feet 3841, hands 3839 and weapon 119 (Item2.novice_visuals), and the shield is not drawn"
  assert game_client.sheet(unit: player, tables: character_tables.shared())
    == game_client.Sheet(
      assault_power: 51,
      support_power: 14,
      max_health: 736,
      max_shield: 450,
    )
    as "0x1403b77d0: holding the armor changes no figure the sheet shows: Assault Power 51, Support Power 14, Max Health 736 and Max Shields 450, as before"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_created_dominion_cassian_veteran_is_played_into_the_world_at_row_42148_facing_the_clients_yaw_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
  let burst = game_client.read_entry(game:)
  let assert [Frame(body: world, ..), ..] = burst
  let assert Ok(entered) = enter_world.decode(world)
  assert entered.world_id == 1387
    && entered.position_x == 0xC56FBBEC
    && entered.position_y == 0xC4750DE8
    && entered.position_z == 0xC5BD2A1C
    as "row 359 is a Nexus start of Dominion (166) Cassian (race 1): WorldLocation2 row 42148 (Quest2.10530.links, the retail race split), World 1387 and its position as 32-bit floats"
  assert game_client.unit_create_player_in(frames: burst).tail.movement_commands
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
      name: "Abe Qu",
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert_at_level(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
      level: 1,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  assert list.length(game_client.read_entry(game:)) == burst_length()
    as "the player entered the world"
  // The player's map is the run the real Maps holds for the character's world.
  let assert Ok(found) =
    open_wait.named("Maps to answer the find", fn() {
      world_map_registry.find_or_start(
        started.settings.world.maps,
        MapId(world_id: 1387, instance: 0),
        deadline_ms: ask_support.deadline_far_beyond_the_tests_deadline(),
      )
    })
    as "the map is running, started by the play"
  process.kill(found.pid)
  let assert [Frame(message_id: 0x036A, body:)] =
    game_client.read(game:, count: 1)
    as "opcode.0x36a: the connection watches the map it is in, so its end tells the client"
  game_client.nothing_more(game:)
  assert disconnect_notice.decode(body)
    == Ok(DisconnectNotice(reason: LostUserServer))
    as "0x1400168a0: 8, 'Lost connection with user server.'"
  open_wait.named("the connection to close at the end of its map", fn() {
    game_client.await_closed(game:)
  })
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let _character =
    character_support.insert(
      pool:,
      account:,
      name: "Abe Qu",
      class_id: 4,
      path: 2,
    )
  let _character =
    character_support.insert(
      pool:,
      account:,
      name: "Cal Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  game_client.send_create(game:, body: create_request("Ab Cd"))
  assert created_result(game).result == create_result.AccountFull
    as "lua.CharacterSelection.OnLoadFromCharacter: 2 slots without an entitlement; lua.Character.OnCreateCharacterFailed: 9"
  assert names_of(pool) == ["Abe Qu", "Cal Qu"] as "nothing more is stored"
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let _abe =
    character_support.insert(
      pool:,
      account:,
      name: "Abe Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_delete(game, zed)
  assert character_support.delete_result_in(game_client.read(game:, count: 1))
    == DeleteCharacterResult(result: delete_result.DeleteOk, data: 0)
    as "opcode.0xe6: result 0, and the value nothing reads (opcode.0xe6.value)"
  assert names_of(pool) == ["Abe Qu"] as "the row is deleted"
  assert list.map(listed_entries(game), fn(entry) { entry.name }) == ["Abe Qu"]
    as "the next 0x0117 omits the deleted character"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_delete_of_a_character_another_account_has_is_0x00e6_result_1_and_deletes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // A delete not scoped to the requesting account deletes the other account's row and fails the row assert.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
      name: "Cal Qu",
      class_id: 1,
      path: 1,
    )
  let game = in_select(started:, port:, account:)
  send_delete(game, theirs)
  assert character_support.delete_result_in(game_client.read(game:, count: 1))
    == DeleteCharacterResult(result: delete_result.DeleteFailed, data: 0)
    as "lua.CharacterSelection.OnCharacterDeleteResult: 1; a modified client could send any id"
  assert names_of(pool) == ["Cal Qu"] as "nothing is deleted"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_rename_of_a_marked_character_is_0x014b_result_18_and_the_next_list_shows_the_name_with_the_bit_clear_test() -> Nil {
  use <- owned_test.run(60_000)
  // A rename that leaves the character marked fails the next list's bit.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool:, name: "Zed Qu")
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
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let _abe =
    character_support.insert(
      pool:,
      account:,
      name: "Abe Cd",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool:, name: "Zed Qu")
  let game = in_select(started:, port:, account:)
  send_rename(game:, character_id: zed, name: "aBE cD")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.NameUnavailable
    as "lua.CharacterSelection.OnCharacterRenameResult: 16; the unique index on the lower-cased name refuses it"
  assert names_of(pool) == ["Zed Qu", "Abe Cd"] as "nothing changes"
  let assert [still_marked, _] = listed_entries(game)
  assert still_marked.requires_rename == 1
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_rename_with_a_name_failing_rule_0_is_0x014b_15_and_an_unmarked_character_is_13_test() -> Nil {
  use <- owned_test.run(60_000)
  // A rename that does not require the mark renames the unmarked character and fails the result 13 assert.
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let zed =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let game = in_select(started:, port:, account:)
  send_rename(game:, character_id: zed, name: "Ab Cd")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.RenameFailed
    as "lua.CharacterSelection.OnCharacterRenameResult: 13; the character is not marked, so the client would not offer a rename"
  character_support.mark_for_rename(pool:, name: "Zed Qu")
  send_rename(game:, character_id: zed, name: "Abcd")
  assert character_support.rename_result_in(game_client.read(game:, count: 1)).result
    == rename_result.NameLength
    as "lua.CharacterSelection.OnCharacterRenameResult: 15; rule 0 wants a first and a last name, and the character is marked, so the update reaches the table's check"
  assert names_of(pool) == ["Zed Qu"] as "nothing changes"
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

/// The health the client is created with: stat 0 of the 0x262 among `frames`
/// (`opcode.0x262`).
fn health_in(frames frames: List(Frame)) -> Int {
  let assert Ok(health) =
    unit_fields.stat(
      tail: game_client.unit_create_player_in(frames:).tail,
      stat_id: unit_fields.health_stat,
    )
    as "the player's 0x262 holds stat 0 as an integer"
  health
}

pub fn a_player_who_moves_and_drops_is_saved_and_stands_where_it_left_at_the_next_login_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
  let first = game_client.read_entry(game:)
  let entered_health = Some(health_in(frames: first))
  assert game_client.unit_create_player_in(frames: first).tail.movement_commands
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
      health: entered_health,
    )
    as "the drop saved the place the client last sent, at the epoch its login raised and as its first save, with the health the client was created with (stat 0 of its 0x262)"
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let second = game_client.read_entry(game:)
  let assert [Frame(body: world, ..), ..] = second
  let assert Ok(entered) = enter_world.decode(world)
  assert entered.position_x == float32.to_bits(100.5)
    && entered.position_y == float32.to_bits(-20.25)
    && entered.position_z == float32.to_bits(300.125)
    as "0xAD loads the world where the player left"
  assert game_client.unit_create_player_in(frames: second).tail.movement_commands
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
  assert Some(health_in(frames: second)) == entered_health
    as "and with the health the drop saved, the one the first login was created with"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_character_saved_with_less_health_enters_with_it_in_its_own_0x262_and_a_drop_saves_it_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let character =
    character_support.insert(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let assert Ok(_) =
    pog.query("update character set health = 100 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the row holds the health a login saved"
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let burst = game_client.read_entry(game:)
  assert health_in(frames: burst) == 100
    as "opcode.0x262: stat 0 of the player's own 0x262 is the saved health, below the level's maximum"
  game_client.close(game:)
  login_support.await_no_game_connection(started)
  assert character_support.place_row(pool:, character_id: character).health
    == Some(100)
    as "the drop saved the health the player had: the one it entered with"
  login_support.stop(started)
}

pub fn a_stop_with_a_player_in_the_world_saves_the_place_it_last_stood_at_before_the_tree_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
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
  let burst = game_client.read_entry(game:)
  let entered_health = Some(health_in(frames: burst))
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
      health: entered_health,
    )
    as "the stop saved the place the client last sent, as the login's first save, before the tree ended, with the health the client was created with"
  process.kill(after.pid)
  game_client.close(game:)
}

pub fn a_connection_that_crashes_saves_nothing_is_not_restarted_and_the_place_saved_before_stands_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
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
  let _burst = game_client.read_entry(game:)
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
  open_wait.named("the connection to close after its process was killed", fn() {
    game_client.await_closed(game:)
  })
  assert character_support.place_row(pool:, character_id: character)
    == character_support.PlaceRow(
      world_id: 1387,
      world_zone_id: 1100,
      position: #(1.5, 2.5, 3.5),
      rotation: #(0.0, 0.0, 0.0),
      session_epoch: 1,
      save_sequence: 0,
      health: None,
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
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
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
    character_support.insert_at_level(
      pool:,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
      level: 1,
    )
  let game = in_select(started:, port:, account:)
  send_play(game:, character_id: character)
  let first_burst = game_client.read_entry(game:)
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
  let second_burst = game_client.read_entry(game:)
  assert list.map(second_burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
    as "the play enters the world again as at the first entry"
  let second = game_client.unit_create_player_in(frames: second_burst)
  assert second.unit_id == 2
    as "opcode.0x262: the camp took the first unit out of the map, and the map never gives a unit id twice"
  let assert Ok(start_movement.Position(position)) =
    list.first(second.tail.movement_commands)
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

// ---- a purchase is saved ----

/// The credits the character is given before it buys (the table's value is a server
/// choice, `starting_credits`; the test gives its own so it does not depend on it).
const credits_before_the_buy = 1000

/// The credits slot of the entry's 0x25E: the first of 15 u64 little-endian, the types 1
/// to 15 in order, credits first (opcode.0x25e).
fn credits_in_entry(frames frames: List(Frame)) -> Int {
  let assert [Frame(body:, ..)] =
    list.filter(frames, fn(frame) { frame.message_id == 0x025E })
    as "the entry sends one 0x25E"
  let assert Ok(state) = player_character_state.decode(body)
    as "the client's reader reads the 0x25E"
  let assert <<credits:unsigned-little-size(64), _:bytes>> = state.currencies
  credits
}

pub fn credits_survive_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  // Supplier Ingavak (Creature2 28739) stands 3.0 from the player's edge, within the
  // 9.0 a vendor request is answered up to (opcode.0x7ea). The player is an Exile
  // (faction 167), to whom his faction 171 is friendly (Faction2Relationship 771). A
  // buy of one Item2 14838 costs the 67 the window shows (`vendor.start_zone_prices`),
  // and 0x919 kind 0 then carries the credits left (opcode.0x919). After a camp and a
  // new play, the 0x25E carries them in its first currency slot (opcode.0x25e).
  let vendors =
    vendor_support.stocking_items(
      creature_ids: [28_739],
      items: vendor_support.ingavaks_items,
    )
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_706),
          creature_id: 28_739,
          display_info_id: 29_772,
          outfit_info_id: 9029,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors:,
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_706))
  let ingavak =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 -. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            vendors:,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [ingavak],
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is of the faction Ingavak is friendly to"
  let assert Ok(_) =
    pog.query(
      "insert into character_currency (character_id, currency_type_id, amount) values ($1, 1, $2)",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(credits_before_the_buy))
    |> pog.execute(pool)
    as "the character holds credits"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && game_client.creatures_created_in(frames:) != []
    })
  assert credits_in_entry(frames: entry) == credits_before_the_buy
    as "the entry carries the credits the character holds"
  let assert [shown] = game_client.creatures_created_in(frames: entry)
  assert shown.creature_id == 28_739
    as "the creature in sight is Supplier Ingavak"
  // The right-click opens the window; the item's unique id is the one the window shows.
  let #(window, have) =
    item_bot.open_vendor(game:, have:, unit_id: shown.unit_id)
  let assert Ok(stimpack) =
    list.find(window.items, fn(item) { item.entry_id == 14_838 })
    as "the window shows Item2 14838"
  let #(bought, have) =
    item_bot.buy(game:, have:, unique_id: stimpack.unique_id, quantity: 1)
  assert list.map(bought.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 67)]
    as "opcode.0x919: kind 0 sets the total, the credits less the 67 the client shows (vendor.start_zone_prices)"
  assert list.map(bought.added, fn(held) { held.item.item_id }) == [14_838]
    as "the bought item is added to the inventory"
  // The player camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert credits_in_entry(frames: second_entry) == credits_before_the_buy - 67
    as "opcode.0x25e: the first currency slot carries the credits the buy saved"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- an objective's progress is saved ----

pub fn objective_progress_survives_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  // Scientist Lusk (Creature2 12484) stands 3.0 from the player's edge. Quest 3668's
  // objective 0 (4744) is a type 3 objective for him with count 1, and its objectives 1
  // and 2 are not talks, so the quest stays Accepted (QuestObjective rows). The talk is
  // the client's 0x7ea kind 37 (opcode.0x7ea) and is counted with a 0x361 (opcode.0x361);
  // after a camp and a new play, the 0x35f entry of the quest carries state 1, the flags
  // word 6 (tracked bit 1 and the done bit of objective 0, bit 2) and the progress 1, 0, 0
  // (opcode.0x35f).
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_707),
          creature_id: 12_484,
          display_info_id: 27_273,
          outfit_info_id: 0,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor_support.stocking(creature_ids: []),
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_707))
  let lusk =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 -. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [lusk],
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is of the faction Lusk's faction 171 is friendly to"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 3668, 1, 0, true, 0, '{0,0,0}', 0, '{0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 3668 with nothing done"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && game_client.creatures_created_in(frames:) != []
    })
  let assert [shown] = game_client.creatures_created_in(frames: entry)
  assert shown.creature_id == 12_484
    as "the creature in sight is Scientist Lusk"
  let assert Ok(request) =
    interaction_request.encode(InteractionRequest(
      unit_id: shown.unit_id,
      kind: 37,
    ))
  game_client.send_world(
    game:,
    message_id: interaction_request.message_id,
    body: request,
  )
  let #(talked, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(talked, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 3668), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the talk counts objective 0 of quest 3668"
  // The player camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(active: [entry], ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f, which holds the one quest"
  assert entry.quest_id == 3668 && entry.state == 1
    as "the quest is still Accepted: objectives 1 and 2 are open"
  assert entry.flags == 6
    as "opcode.0x35f: tracked (bit 1) and the done bit of objective 0 (bit 2)"
  assert entry.progress == [1, 0, 0]
    as "opcode.0x35f: the progress of each objective, the talk's saved"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_move_into_a_marker_sends_its_objective_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10513's objective 21271 (index 0, type 22, count 1) names WorldLocation2 51735
  // as its marker: World 3460, centre (32.5895, -854.5823, -544.8400), radius 1.0 and no
  // vertical limit. The client sends nothing for a place; its movement update (0x637) is
  // all the server sees of the arrival (opcode.0x637), and the server tells the client the
  // objective's progress (opcode.0x361: the quest, the objective, the value).
  let time = driven_time.new()
  let started = start_with_creatures(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10513, 1, 0, true, 0, '{0,0,0,0,0}', 0, '{0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10513 with nothing done"
  // Five units west of the marker's centre, outside its radius.
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 6009,
    position: #(27.5895, -854.5823, -544.84),
  )
  send_play(game:, character_id: character)
  let #(_burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  send_move(game:, position: #(33.0, -854.5823, -544.84), rotation: #(
    0.0,
    0.0,
    0.0,
  ))
  let #(arrived, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(arrived, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_513), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: 0.41 from the centre of 51735 completes objective 21271 of quest 10513"
  // A later move inside the same marker: the server has written all it held for this
  // connection when its pong comes, so a 0x361 that the move would send is among the
  // frames.
  send_move(game:, position: #(32.8, -854.5823, -544.9), rotation: #(
    0.0,
    0.0,
    0.0,
  ))
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.filter(later, fn(frame) { frame.message_id == 0x0361 }) == []
    as "opcode.0x361: the objective is done, so a second move inside the marker counts nothing"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_checklist_target_shows_its_index_and_counts_once_when_activated_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 5855 holds objective 8782 at its index 1 (QuestObjective: type 14, count 5, data
  // TargetGroup 2766, whose member is Creature2 26016), and objective 8781 at index 0
  // (type 8). Creature2 26016 has activate spell 1817 behind Prerequisite 0, an
  // activateSpellCastTime of 1500 ms and an activateSpellMaxRange of 3.0; the spell is of
  // castMethod 0, so its go waits for no answer. Spawns 70878 and 70880 of World 1387 are
  // two of its objects, both with the world data's checklist index 0, so the server must
  // give them two distinct bits of the 32-bit mask (opcode.0x361, `checklist_index`): in
  // spawn order, the lowest index no earlier target holds, 0 and 1. The 0x262 carries the
  // index (opcode.0x262), the activate counts the bit of the object activated in the one
  // 0x361 (opcode.0x361: the quest, the objective, the whole mask), and the 0x35f of a
  // later entry carries the mask as the objective's progress (opcode.0x35f).
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_checklist",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 5855, 1, 0, true, 0, '{0,0}', 0, '{0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 5855 with nothing done"
  // One unit east of spawn 70880, the second of the two: within the 3.0 of the creature's
  // activateSpellMaxRange, and 17.4 from spawn 70878, which is still in sight.
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 1387,
    world_zone_id: 1100,
    position: #(-3513.5, -979.1523, -6123.66),
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(static_objects_created_in(frames:)) == 2
    })
  let assert [_, second] as objects = static_objects_created_in(frames: entry)
  assert list.map(objects, fn(object) {
      #(object.creature_id, object.checklist_index)
    })
    == [#(26_016, 0), #(26_016, 1)]
    as "the two objects of Creature2 26016 are shown in spawn order with the two distinct indexes of objective 8782's bits"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: second.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes: the
  // confirmation is sent before the timer starts, so the clock moves only after the pong.
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the first press is confirmed"
  driven_time.advance(time:, ms: 1500)
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 5855), #(32, 1), #(32, 2)]),
      ),
    ]
    as "opcode.0x361: the go of the activate counts the bit of index 1, the second object's, in objective 8782 of quest 5855"
  // The same object activated a second time: its bit is set in objective 8782. Creature2
  // 26016 links through prerequisiteIdAnimState 11686, whose two type 11 conditions nest
  // Prerequisite 11687 (type 43 on quest 5855's objective at index 1, and type 94
  // comparison 2, which fails once the unit's bit is set) and 11688 (the same for quest
  // 6780) (Prerequisite.prerequisiteTypeId.11, .94). A prerequisite that fails sets the
  // unit's anim state 1 (0x14046c4d0), and the client offers a unit in it nothing
  // (0x140479560.anim_state_exit), so the press is refused as not useable (100) with no
  // cast; the server has written all it held for this connection when its pong comes. The
  // used object goes out of sight at its go and comes back under its unit id after the
  // release time (migration 0033, 30 s), when the press meets the closed link.
  driven_time.advance(time:, ms: 31_000)
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(static_objects_created_in(frames:), fn(object) {
        object.unit_id == second.unit_id
      })
    })
  let assert Ok(again) =
    cast_activate.encode(CastActivate(
      client_cast_id: 2,
      target_unit_id: second.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: again,
  )
  let #(pressed_again, have) =
    game_client.read_until_pong(game:, have:, number: 2)
  assert refusals(frames: pressed_again)
    == [cast_result.to_value(TargetIsNotUseable)]
    as "opcode.0x7fc: the second press of the marked object is refused as not useable"
  assert list.filter(pressed_again, fn(frame) {
      frame.message_id == 0x07FD || frame.message_id == 0x0361
    })
    == []
    as "opcode.0x7fd and opcode.0x361: no cast starts and nothing is counted, the bit of index 1 is set in objective 8782"
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(active: [quest], ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f, which holds the one quest"
  assert quest.quest_id == 5855 && quest.progress == [0, 2]
    as "opcode.0x35f: the progress of objective 8782 is the mask with the bit of index 1, kept over the relog"
  game_client.close(game:)
  login_support.stop(started)
}

/// A character of this number one unit west of crate 18256's place in World 426, holding
/// quest 3741 ("Scattered Supplies", objective 4813) with nothing done when it is asked to:
/// its game, the bytes its client has read beyond its entry, and the frames of its entry,
/// read until the crate of the world data is shown.
fn near_the_crates(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  holds_the_quest holds_the_quest: Bool,
) -> #(game_client.Game, BitArray, List(Frame)) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number:,
      character_name:,
      class_id: 4,
      level: 1,
    )
  case holds_the_quest {
    True -> {
      let assert Ok(_) =
        pog.query(
          "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 3741, 1, 0, true, 0, '{0}', 0, '{0}', '{0,0,0,0,0,0}')",
        )
        |> pog.parameter(pog.int(character))
        |> pog.execute(pool)
        as "the character holds quest 3741 with nothing done"
      Nil
    }
    False -> Nil
  }
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 426,
    world_zone_id: 648,
    position: #(4453.227, -741.5363, -5457.145),
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && static_objects_created_in(frames:) != []
    })
  #(game, have, entry)
}

pub fn a_crate_of_scattered_supplies_counts_once_and_vanishes_for_everyone_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12919 (Exile Supply Crate, quest 3741) casts activate spell 1817 after its
  // activateSpellCastTime of 2000 ms, from at most 5.0 away, and links to quest 3741's
  // objective index 0 (objective 4813, type 32, count 6) through its questAnim columns.
  // The fixture imports six of its crates (rows 18256 to 18261), as many as the
  // objective's count, so the load does not take the objective as short of units and
  // the connection releases a crate it counts (`objective_units.reused`).
  // The client keeps no record of a crate it has used and offers it again until the
  // objective is done (`QuestObjective.type.32.repeat_use`); the server counts a crate
  // once and takes it out of sight of everyone, so the client is sent 0x361 once and
  // 0x355 to each viewer (opcode.0x361, opcode.0x355; a used quest object vanishing for
  // everyone is Jim's decision of 2026-11-16).
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_crates",
      time:,
      adjusted: fn(settings) { settings },
    )
  let #(game, have, entry) =
    near_the_crates(
      started:,
      number: 1,
      character_name: "Zed Qu",
      holds_the_quest: True,
    )
  let #(viewer, viewer_have, _) =
    near_the_crates(
      started:,
      number: 2,
      character_name: "Ann Qu",
      holds_the_quest: False,
    )
  let assert Ok(crate) =
    nearest_object_of(
      objects: static_objects_created_in(frames: entry),
      creature_id: 12_919,
      to: #(4454.227, -5457.145),
    )
    as "crate 18256 is shown to the player who holds the quest"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: crate.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes.
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  // The map takes the crate out of sight after the connection has told it the use: a
  // message from another process, so the 0x355 is waited for with the 0x361.
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
      && destroyed_units(frames:) != []
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 3741), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go counts one of the six"
  assert destroyed_units(frames: went) == [crate.unit_id]
    as "opcode.0x355: the crate goes out of the sight of the player who used it"
  let #(seen_by_viewer, _viewer_have) =
    game_client.read_until(game: viewer, have: viewer_have, found: fn(frames) {
      destroyed_units(frames:) != []
    })
  assert destroyed_units(frames: seen_by_viewer) == [crate.unit_id]
    as "opcode.0x355: and out of the sight of a second player, who holds no quest"
  // The same unit pressed again is a unit the player's client no longer holds: the
  // press is refused and counts nothing.
  let assert Ok(again) =
    cast_activate.encode(CastActivate(
      client_cast_id: 2,
      target_unit_id: crate.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: again,
  )
  let #(pressed_again, _) = game_client.read_until_pong(game:, have:, number: 2)
  assert list.filter(pressed_again, fn(frame) {
      frame.message_id == 0x0361 || frame.message_id == 0x07FD
    })
    == []
    as "opcode.0x361 and opcode.0x7fd: a second press of the same crate counts nothing and starts no cast"
  game_client.close(game:)
  game_client.close(game: viewer)
  login_support.stop(started)
}

/// The unit ids the 0x355 among the frames remove, in the order sent.
fn destroyed_units(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_destroyed.message_id {
      True ->
        unit_destroyed.decode(frame.body)
        |> result.map(fn(destroyed) { destroyed.unit_id })
        |> result.replace_error(Nil)
      False -> Error(Nil)
    }
  })
}

// ---- two players see each other ----

/// What a character who has pressed a mine's activate leaves: the game, the mine's
/// unit, what the client has read after the cast's finish and its pong, the frames of
/// its entry and the frames it has read since the press.
type MineCast {
  MineCast(
    started: login_support.Started,
    game: game_client.Game,
    mine: unit_create_static.UnitCreateStatic,
    have: BitArray,
    entry: List(Frame),
    pressed: List(Frame),
    time: driven_time.Time,
  )
}

/// A character in World 3460 at the position, of the faction, holding the quest with its
/// objective 0 done, who has pressed the activate of the mine (the nearest object of
/// Creature2 `mine` to the character) after the entry showed every object of `shown`
/// (a Creature2 and its place), and whose cast has gone. The mine's activate is a cast
/// of Spell4 85452's castTime, 2000 ms (`Creature2.activateSpellCastTime` is 0, so
/// `0x14054e340` takes the spell's). The server runs on a driven clock, which the
/// helper moves by the cast's 2000 ms once the server has taken the press.
fn player_whose_mine_cast_went(
  character_name character_name: String,
  faction faction: Int,
  quest quest: Int,
  zone zone: Int,
  position position: #(Float, Float, Float),
  shown shown: List(#(Int, #(Float, Float, Float))),
  mine mine: Int,
) -> MineCast {
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_mine",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name:,
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = $2 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(faction))
    |> pog.execute(pool)
    as "the character has the faction"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, $2, 1, 0, true, 1, '{1,0,0,0,0,0}', 0, '{0,0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(quest))
    |> pog.execute(pool)
    as "the character holds the quest with objective 0 done"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: zone,
    position:,
  )
  send_play(game:, character_id: character)
  // Every object of `shown` is in the frames read, so the choice of the mine among the
  // objects of its Creature2 does not rest on the order they came in. The Sim-Turrets
  // of objectives 21288 and 21316 stand within sight of the mine, and each writes its
  // own 0x262 from its own process, so they may come before or after the mine's.
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.all(shown, fn(pair) {
        objects_standing_at(
          objects: static_objects_created_in(frames:),
          creature_id: pair.0,
          place: pair.1,
        )
        != []
      })
    })
  let assert Ok(mine) =
    nearest_object_of(
      objects: static_objects_created_in(frames: entry),
      creature_id: mine,
      to: #(position.0, position.2),
    )
    as "a static object of the mine's Creature2 is shown"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: mine.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes: the
  // confirmation is sent before the timer starts, so the clock moves only after the pong.
  // The cast goes and finishes after its time, so the client waits for the server's 0x7fe,
  // and the server has written all it held for this connection when its second pong comes.
  let #(confirmed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(confirmed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(cast, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x07FE })
    })
  let #(rest, have) = game_client.read_until_pong(game:, have:, number: 2)
  MineCast(
    started:,
    game:,
    mine:,
    have:,
    entry:,
    pressed: list.flatten([confirmed, cast, rest]),
    time:,
  )
}

/// An Exile in World 3460 one unit east of the tutorial's mine (Creature2 73463, world
/// database row 29098), holding quest 10518 with its objective 0 done, who has pressed
/// the mine's activate: the game, the mine's unit, what the client has read after the
/// cast's finish and its pong and the frames the client has read so far. The Dominion's
/// marker 52899 holds a mine of the same Creature2, 143 units away (a click target with
/// no spawn stands at its objective's marker), so the entry is read until both are in
/// and the Exile's mine is the one nearest the Exile.
fn exile_whose_mine_cast_went() -> #(
  login_support.Started,
  game_client.Game,
  Int,
  BitArray,
  List(Frame),
  driven_time.Time,
) {
  let cast =
    player_whose_mine_cast_went(
      character_name: "Zed Qu",
      faction: 167,
      quest: 10_518,
      zone: 6009,
      // One unit east of the mine (spawn 29098 stands at x -70.4453).
      position: #(-69.4453, -868.5904, 383.553),
      shown: [
        #(73_463, #(-70.4453, -868.5904, 383.553)),
        #(73_463, #(72.98709869384766, -872.089111328125, 357.6340026855469)),
      ],
      mine: 73_463,
    )
  #(
    cast.started,
    cast.game,
    cast.mine.unit_id,
    cast.have,
    cast.pressed,
    cast.time,
  )
}

pub fn a_mine_cast_counts_the_exile_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 73463 casts activate spell 85452 (activateSpellCastTime 0, so the cast goes
  // after the spell's castTime, 2000 ms) and links to quest 10518 through Prerequisite 41818 (type 43 on quest 10518
  // value 1 or on quest 10524 value 1). Objective 21287 is index 1 of quest 10518
  // (type 5, count 1, flags 3). The client sends nothing at the go, and the server
  // tells it the progress (opcode.0x361: the quest, the objective, the value 1). The
  // used mine goes out of sight, as any used quest object does (Jim, 2026-11-16): a
  // 0x355 for its unit follows (opcode.0x355).
  let #(started, game, mine, have, went, _) = exile_whose_mine_cast_went()
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the mine's cast counts objective 21287 of quest 10518"
  let #(destroyed, _) = destroyed_after(game:, have:, seen: went)
  assert destroyed == [mine]
    as "opcode.0x355: the mine that was used goes out of the player's sight, and no other unit does"
  game_client.close(game:)
  login_support.stop(started)
}

/// The unit ids the 0x355 among the frames remove, or, when none is among them, those of
/// the first 0x355 the map sends the game next: the map takes a used object out of sight
/// after the connection has told it the use, so the news may come before or after the
/// frames the caller has read.
fn destroyed_after(
  game game: game_client.Game,
  have have: BitArray,
  seen seen: List(Frame),
) -> #(List(Int), BitArray) {
  case destroyed_units(frames: seen) {
    [] -> {
      let #(more, have) =
        game_client.read_until(game:, have:, found: fn(frames) {
          destroyed_units(frames:) != []
        })
      #(destroyed_units(frames: more), have)
    }
    units -> #(units, have)
  }
}

pub fn a_second_cast_on_the_mine_after_its_objective_is_done_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21287 is done once the first cast has gone. The mine links through
  // prerequisiteIdAnimState 41818, whose type 43 conditions need an open objective
  // (Prerequisite.prerequisiteTypeId.43), so the prerequisite fails and sets the unit's
  // anim state 1 (0x14046c4d0): the client offers it nothing
  // (0x140479560.anim_state_exit), and the activate is refused with TargetIsNotUseable
  // (100) at the press, with no cast started. The used mine goes out of sight at its go
  // and comes back after the release time (migration 0033, 30 s), when the player's
  // press of it meets the closed link.
  let #(started, game, mine, have, _, time) = exile_whose_mine_cast_went()
  driven_time.advance(time:, ms: 31_000)
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(static_objects_created_in(frames:), fn(object) {
        object.unit_id == mine
      })
    })
  let assert Ok(again) =
    cast_activate.encode(CastActivate(client_cast_id: 2, target_unit_id: mine))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: again,
  )
  let #(pressed, _) = game_client.read_until_pong(game:, have:, number: 3)
  assert refusals(frames: pressed) == [cast_result.to_value(TargetIsNotUseable)]
    as "opcode.0x7fc: the second press is refused as not useable"
  // The Sim-Turrets in sight write their own casts from their own processes, at any time
  // relative to the pong, so the frames may hold them: a cast of this press would show as
  // a 0x7fd (sent only to the one who pressed) and a 0x7ff of the mine's spell 85452.
  assert list.all(game_client.casts_in(frames: pressed), fn(event) {
    case event {
      game_client.CastConfirmed(..) -> False
      game_client.CastStarted(spell4_id:, ..) -> spell4_id != 85_452
      game_client.CastRefused(..)
      | game_client.CastWent(..)
      | game_client.CastFinished(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..) -> True
    }
  })
    as "no cast of the second press is confirmed or started"
  game_client.close(game:)
  login_support.stop(started)
}

/// A Dominion character in World 3460 one unit east of marker 52899 (WorldLocation2
/// 52899, x 72.98709869384766, y -872.089111328125, z 357.6340026855469), holding quest
/// 10524 with its objective 0 done, who sees the mines the markers hold: the markers
/// 52899, 52900 and 52901 (the click objectives 21313, 21314 and 21315, indexes 1, 2
/// and 3 of quest 10524) have no stored spawn, the world database holds only the
/// Exile's mines (rows 29098 to 29100) in that world, and each mine of the tutorial
/// is a Creature2 of its own (73463, 73667 and 73668, CreationTypeEnum 20, unit type
/// 32).
pub fn a_dominion_player_sees_and_counts_the_mines_at_their_markers_test() -> Nil {
  use <- owned_test.run(60_000)
  // The marker of each mine: its centre (WorldLocation2 position0, 1 and 2).
  let markers = [
    #(73_463, #(72.98709869384766, -872.089111328125, 357.6340026855469)),
    #(73_667, #(53.51499938964844, -872.089111328125, 374.47900390625)),
    #(73_668, #(43.11709976196289, -872.089111328125, 395.1889953613281)),
  ]
  // The character is one unit east of marker 52899, whose mine is the nearest of its
  // Creature2.
  let MineCast(started:, game:, mine:, have:, entry:, pressed:, ..) =
    player_whose_mine_cast_went(
      character_name: "Dax Qu",
      faction: 166,
      quest: 10_524,
      zone: 5967,
      position: #(73.98709869384766, -872.089111328125, 357.6340026855469),
      shown: markers,
      mine: 73_463,
    )
  let at_markers =
    list.map(markers, fn(pair) {
      objects_standing_at(
        objects: static_objects_created_in(frames: entry),
        creature_id: pair.0,
        place: pair.1,
      )
    })
  let assert [[at_52899], [_], [_]] = at_markers
    as "opcode.0x262: one mine of each Creature2 stands at its marker"
  assert list.all(list.flatten(at_markers), fn(object) {
    object.unit_type == static_unit_type.SimpleCollidable
  })
    as "opcode.0x262: each mine is sent as unit type 32, the type CreationTypeEnum 20 pairs with"
  assert mine == at_52899 as "the mine pressed is the one at marker 52899"
  assert list.filter(pressed, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_524), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the mine's cast counts objective 21313 of quest 10524"
  let #(destroyed, _) = destroyed_after(game:, have:, seen: pressed)
  assert destroyed == [mine.unit_id]
    as "opcode.0x355: the mine that was used goes out of the player's sight, and no other mine does"
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
      account_id: account_number(account),
      session_key: guid.to_wire(key),
      account_name: login_name,
      limit: socket_read.Open,
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
    /// The frames the first client read while it acted before the second played.
    first_acted: List(Frame),
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

/// The messages of the Holocrypt's join: an entry burst without 0x25E.
fn holocrypt_burst_length() -> Int {
  list.length(game_client.holocrypt_entry_ids())
}

/// A player of an account of its own with a character, connected in character
/// select: the first is the library's account, the others are made for a test.
fn new_player(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int) {
  new_player_of_class(started:, number:, character_name:, class_id: 4)
}

/// A player as `new_player` makes it, of the class given.
fn new_player_of_class(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
) -> #(game_client.Game, Int) {
  new_player_at_level(started:, number:, character_name:, class_id:, level: 9)
}

/// A player as `new_player` makes it, of the class and the level given.
fn new_player_at_level(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
  level level: Int,
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
    character_support.insert_at_level(
      pool:,
      account:,
      name: character_name,
      class_id:,
      path: 2,
      level:,
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

/// Two players enter one map on a server of the driven clock `time`: the first a
/// Medic, the second a Medic, both of level 1.
fn two_players_enter_one_map(time time: driven_time.Time) -> TwoEntered {
  two_players_enter(
    started: login_support.start(time:),
    first_class: 4,
    level: 1,
  )
}

/// As `two_players_enter_one_map`, the first player being of the class given, the
/// server holding the fixture's rows (the starting abilities' own trees) and its game
/// connections and its World taking their time and their timers from `time`, which a
/// test whose casts run on timers moves by hand.
fn two_players_of_class_enter_one_map_with(
  first_class first_class: Int,
  time time: driven_time.Time,
) -> TwoEntered {
  two_players_enter_on(tables: character_tables.shared(), first_class:, time:)
}

/// As `two_players_of_class_enter_one_map_with`, on these tables.
fn two_players_enter_on(
  tables tables: table_store.Tables,
  first_class first_class: Int,
  time time: driven_time.Time,
) -> TwoEntered {
  two_players_enter(started: started_on(tables:, time:), first_class:, level: 9)
}

/// A server holding these tables, its game connections and its World taking their time and
/// their timers from `time`.
fn started_on(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      game: server.Served(
        ..settings.game,
        settings: connection_state.Settings(..settings.game.settings, tables:),
      ),
    )
  })
}

/// Two players of the level given enter one map, the first of the class given and the
/// second a Medic. A test of the entry's burst takes level 1, whose bag is the level-1
/// three and the innate (`game_client.world_entry_ids`); a higher level's bag holds more.
fn two_players_enter(
  started started: login_support.Started,
  first_class first_class: Int,
  level level: Int,
) -> TwoEntered {
  two_players_enter_after(
    started:,
    first_class:,
    level:,
    first_acts: fn(_, have) { #([], have) },
  )
}

/// As `two_players_enter`, the first player acting on its entry with `first_acts` (given
/// its connection and the bytes it has read, giving the frames it read and the bytes it has
/// read then) before the second plays.
fn two_players_enter_after(
  started started: login_support.Started,
  first_class first_class: Int,
  level level: Int,
  first_acts first_acts: fn(game_client.Game, BitArray) ->
    #(List(Frame), BitArray),
) -> TwoEntered {
  let #(first, first_character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: first_class,
      level:,
    )
  let #(second, second_character) =
    new_player_at_level(
      started:,
      number: 2,
      character_name: "Ann Qu",
      class_id: 4,
      level:,
    )
  send_play(game: first, character_id: first_character)
  let #(first_burst, first_have) =
    game_client.read_entry_kept(game: first, have: <<>>)
  let #(first_acted, first_have) = first_acts(first, first_have)
  send_play(game: second, character_id: second_character)
  let #(second_entry, second_have) =
    game_client.read_entry_kept(game: second, have: <<>>)
  let #(seen_first, second_have) =
    game_client.next(game: second, have: second_have)
  let second_burst = list.append(second_entry, [seen_first])
  let #(seen_second, first_have) =
    game_client.next(game: first, have: first_have)
  TwoEntered(
    started:,
    first:,
    second:,
    second_character:,
    first_burst:,
    first_acted:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
  )
}

pub fn a_player_entering_is_written_its_whole_burst_before_the_0x262_of_a_player_in_sight_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_burst:, second_burst:, ..) as entered =
    two_players_enter_one_map(time:)
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

pub fn a_players_press_is_answered_0x7fd_go_and_finish_and_a_player_in_sight_reads_the_same_cast_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_enter_one_map(time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 2,
    target: 0,
  )
  let #(own, _) = game_client.read_kept(game: first, have: first_have, count: 3)
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 3)
  let assert [
    game_client.CastConfirmed(client_cast_id: 1, server_cast_id: cast_id),
    game_client.CastWent(cast_id: went, phase: 0),
    game_client.CastFinished(cast_id: finished),
  ] = game_client.casts_in(frames: own)
    as "opcode.0x7fd, 0x7f4 and 0x7fe: the caster's client is answered, Paralytic Surge being instant (Spell4.42352: no cast time) and starting no child"
  assert went == cast_id && finished == cast_id
  let assert [
    game_client.CastStarted(
      cast_id: seen_id,
      root_spell4_id: root,
      parent_spell4_id: 0,
      caster_unit_id: 1,
      ..,
    ),
    game_client.CastWent(cast_id: seen_went, phase: 0),
    game_client.CastFinished(cast_id: seen_finished),
  ] = game_client.casts_in(frames: seen)
    as "opcode.0x7ff, 0x7f4 and 0x7fe: the watcher's client reads the same cast, started by unit 1 with no parent"
  assert seen_id == cast_id && seen_went == cast_id && seen_finished == cast_id
    as "one cast id, which no other unit's cast shares (0x140561c30)"
  assert root == 42_352
    as "the root is the pressed spell, Spell4 42352, Paralytic Surge, the Medic's third level-1 ability (SpellLevel 1089) at bag index 2 (opcode.0x7ff.root_parent)"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The unit and the Spell4Effects id and delay of each effect info of one decoded go.
fn effect_infos_of(go go: spell_go.SpellGo) -> List(#(Int, List(#(Int, Int)))) {
  list.map(go.targets, fn(target) {
    #(
      target.unit_id,
      list.map(target.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms)
      }),
    )
  })
}

/// The effect infos of the go of the cast `cast_id` among the frames.
fn go_effect_infos(
  frames frames: List(Frame),
  cast_id cast_id: Int,
) -> List(#(Int, List(#(Int, Int)))) {
  list.filter(frames, fn(frame) { frame.message_id == spell_go.message_id })
  |> list.filter_map(fn(frame) { spell_go.decode(frame.body) })
  |> list.filter(fn(go) { go.cast_id == cast_id })
  |> list.flat_map(effect_infos_of)
}

pub fn a_watcher_is_told_the_delays_of_spell4_36201_as_the_table_has_them_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client row sends a player to cast Spell4 36201 (an explorer route's music), which
  // holds the Spell4Effects row 74798 (type 17, flags 2, delay 1) and the type 80 row
  // 135368 (delay 0) on the primary target: the Medic's bag index 2 (SpellLevel 1089,
  // Paralytic Surge) is given it, so a whole server tells the go of a real spell with
  // both rows.
  use tables <- fixture_tables.changed(table: "SpellLevel", id: 1089, with: [
    #("spell4Id", planted_table.Integer(36_201)),
  ])
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_enter_on(tables:, first_class: 4, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 2,
    target: 0,
  )
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: own, client_cast_id: 1)
    as "opcode.0x7fd: the press of Spell4 36201 is answered with its server cast id"
  let #(seen, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      go_effect_infos(frames:, cast_id:) != []
    })
  assert go_effect_infos(frames: seen, cast_id:)
    == [#(1, [#(74_798, 1), #(135_368, 0)])]
    as "opcode.0x7f4.first_start: the type 80 row 135368 starts at delay 0, so the client builds the buff and row 74798 (delay 1, flags 2) is told its own 1"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_medics_discharge_pulses_three_times_and_a_player_in_sight_reads_the_same_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 4, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let pulses = [
    "went k1 p0",
    "started k2 80382 root 58832 parent 58832",
    "went k2 p0",
    "started k3 42569 root 58832 parent 80382",
    "went k3 p0",
    "finished k2",
    "went k1 p1",
    "started k4 80382 root 58832 parent 58832",
    "went k4 p0",
    "started k5 42569 root 58832 parent 80382",
    "went k5 p0",
    "finished k4",
    "went k1 p2",
    "started k6 80382 root 58832 parent 58832",
    "went k6 p0",
    "started k7 80383 root 58832 parent 80382",
    "went k7 p0",
    "started k8 42568 root 58832 parent 80383",
    "went k8 p0",
    "finished k8",
    "finished k7",
    "finished k6",
    "finished k1",
  ]
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The channel ends at its channelMaxTime, 1250 ms after the press, the pulses
  // coming every channelPulseTime, 410 ms.
  driven_time.advance(time:, ms: 1250)
  let #(later, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", ..pulses]
    as "Spell4.58832, Discharge, the Medic's first level-1 ability (SpellLevel 631): the accept, then a go for each of its three pulses (channelPulseTime 410, channelMaxTime 1250: 0x14053d1f0), each starting its Proxy 80382 (Spell4Effects 173926, phaseFlags -1) with the pulse index as its phase (opcode.0x7f4.phase); 80382's Proxies 212835 (42569, gate Prerequisite 33154: fewer than 2 stacks) start Power Charge on pulses 0 and 1 and 212838 (80383, gate 32921: exactly 2 stacks) starts 80383 on pulse 2, whose Proxy 212837 starts 42568; then the finish"
  let #(seen, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert cast_support.cast_lines(frames: seen)
    == ["started k1 58832 root 58832 parent 0", ..pulses]
    as "opcode.0x7ff, 0x7f4 and 0x7fe: a player in sight reads the same casts, started by unit 1 with no parent"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// `opcode.0x262.casts` and `cast.target_node_end`: a player that enters beside a Medic
/// holding the bar of Gamma Rays (Spell4 29874, castTime 1250 ms) is created the Medic's
/// unit with the cast listed, not yet gone, and named as its cast in progress; the
/// cast's go and its 0x7fe are then written to it, since the client ends a cast only by
/// the 0x7fe it is sent.
pub fn a_viewer_joining_beside_a_casting_player_shows_its_cast_bar_and_writes_its_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    first_acted:,
    second_burst:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started: started_on(tables: character_tables.shared(), time:),
      first_class: 4,
      level: 9,
      first_acts: fn(first, have) {
        // Gamma Rays is the Medic's second level-1 ability, so bag index 1.
        game_client.press_ability(
          game: first,
          client_cast_id: 1,
          bag_index: 1,
          target: 0,
        )
        game_client.read_until_pong(game: first, have:, number: 1)
      },
    )
  let assert [game_client.CastConfirmed(server_cast_id: cast_id, ..)] =
    game_client.casts_in(frames: first_acted)
    as "the press is accepted (opcode.0x7fd) and Gamma Rays' cast time holds its first go"
  let assert Ok(seen_first) = list.last(second_burst)
    as "the second player's entry ends with the 0x262 of the first"
  let created = game_client.unit_create_player_in(frames: [seen_first])
  assert created.unit_id == 1
  assert list.map(created.tail.casts, fn(entry) {
      #(entry.caster_unit_id, entry.cast_id, entry.spell4_id, entry.started)
    })
    == [#(1, cast_id, 29_874, 1)]
    as "opcode.0x262.casts: the create lists the cast the Medic holds the bar of, not yet gone (state 2, bit 1)"
  assert created.tail.cast_id == cast_id
    as "and names it as the cast in progress, which the client looks up in that list (SetUnitCast 0x1404697a0)"
  driven_time.advance(time:, ms: 1250)
  // The first player's pong comes after the go and the finish the clock moved, so the
  // viewer's connection has been told them by the time its own pong comes.
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let #(later, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let own_events = [
    game_client.CastWent(cast_id:, phase: 0),
    game_client.CastFinished(cast_id:),
  ]
  assert list.filter(game_client.casts_in(frames: later), list.contains(
      own_events,
      _,
    ))
    == own_events
    as "the viewer is written the cast's go and its end: the cast is one it was given"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// `opcode.0x262.casts`, `opcode.0x811` and `cast.target_node_end`: a player that enters
/// beside a Medic whose Discharge has pulsed once (410 ms after the press, starting a
/// Power Charge, Spell4 42569, whose Fluff row 96819 lasts until removed) is created the
/// Medic's unit with Discharge listed as the cast in progress and the Power Charge listed
/// beside it with a target info on the Medic's unit (index 0, flags 0, count 1, a Hit, the
/// row at delay 0 and lifetime 0); the clock then moves past the pulse that takes the
/// Power Charges off the Medic (Spell4Effects 212836, Spell4 80383), and the viewer is
/// written the 0x811 that ends the Power Charge it was listed, since the client ends a
/// buff only by what it is sent.
pub fn a_viewer_joining_beside_a_medic_holding_power_charges_lists_them_and_writes_their_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    second_burst:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started: started_on(tables: character_tables.shared(), time:),
      first_class: 4,
      level: 9,
      first_acts: fn(first, have) {
        // Discharge is the Medic's first level-1 ability, so bag index 0.
        game_client.press_ability(
          game: first,
          client_cast_id: 1,
          bag_index: 0,
          target: 0,
        )
        let #(pressed, have) =
          game_client.read_until_pong(game: first, have:, number: 1)
        // The first pulse comes 410 ms after the press (channelPulseTime).
        driven_time.advance(time:, ms: 500)
        let #(pulsed, have) =
          game_client.read_until_pong(game: first, have:, number: 2)
        #(list.append(pressed, pulsed), have)
      },
    )
  let assert Ok(seen_first) = list.last(second_burst)
    as "the second player's entry ends with the 0x262 of the first"
  let created = game_client.unit_create_player_in(frames: [seen_first])
  assert created.unit_id == 1
  let assert [discharge, power_charge] =
    list.sort(created.tail.casts, fn(left, right) {
      int.compare(left.cast_id, right.cast_id)
    })
    as "the create lists Discharge and the one Power Charge the first pulse started"
  assert #(
      discharge.caster_unit_id,
      discharge.spell4_id,
      discharge.started,
      discharge.targets,
    )
    == #(1, 58_832, 0, [])
    as "Discharge is listed in state 3 (its first go has gone) and holds no node"
  assert #(
      power_charge.caster_unit_id,
      power_charge.spell4_id,
      power_charge.started,
    )
    == #(1, 42_569, 0)
    as "the Power Charge is listed in state 3, a cast of the Medic that is not the current cast"
  assert list.map(power_charge.targets, fn(target) {
      #(
        target.unit_id,
        target.index,
        target.flags,
        target.instance_count,
        target.combat_result,
        list.map(target.effects, fn(effect) {
          #(
            effect.spell4_effects_id,
            effect.instance_id,
            effect.delay_ms,
            effect.lifetime_ms,
          )
        }),
      )
    })
    == [#(1, 0, 0, 1, combat_result.Hit, [#(96_819, 1, 0, 0)])]
    as "its one target is the Medic's unit with row 96819, delay 0 and lifetime 0 (until removed)"
  assert created.tail.cast_id == discharge.cast_id
    as "the cast in progress is Discharge, which the client looks up in that list"
  driven_time.advance(time:, ms: 800)
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  let #(later, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert list.contains(
    game_client.targets_removed_in(frames: later),
    #(power_charge.cast_id, [1]),
  )
    as "the viewer is written the 0x811 that takes the Power Charge off the Medic: the buff it was listed ends on its screen"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_stalkers_two_taps_of_shred_open_and_close_the_threshold_and_a_player_in_sight_reads_both_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The Proxy's phases come 133, 300 and 333 ms after the cast (SpellPhase 3712
  // to 3714), so it is over 766 ms in and the global cooldown, 1000 ms from the
  // press, is not.
  driven_time.advance(time:, ms: 800)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == [
      "confirmed k1",
      "opened 38765 k1",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
    ]
    as "Spell4.38765, Shred (SpellLevel 780, thresholdTime 4000): the first tap casts it and opens the threshold with 0x816 (opcode.0x816), its Proxy 38767 starts in phase 0 (Spell4Effects 83776) and goes in three phases (SpellPhase 3712 to 3714); the Stalker's passive 45057 starts 60724 beside it 50 ms in (its ungated Proxy 147125)"
  game_client.press_ability(
    game: first,
    client_cast_id: 2,
    bag_index: 0,
    target: 0,
  )
  let #(held, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  assert cast_support.cast_lines(frames: held) == []
    as "the second tap is held for the global cooldown: the server has written nothing for it"
  driven_time.advance(time:, ms: 200)
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: own)
    == [
      "confirmed k1",
      "went k1 p0",
      "started k2 39467 root 38765 parent 38766",
      "finished k1",
      "closed 38765 1",
    ]
    as "Spell4Thresholds 238: the second tap, held until the global cooldown ends (Spell4.38765: kind 0, SpellCoolDown 115, 1000 ms), casts the stage 38766 and 0x814 closes the threshold with the cooldown bit (opcode.0x814)"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 15)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 38765 root 38765 parent 0",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
    ]
    as "opcode.0x7ff.root_parent and cast.stage_root_parent: a player in sight reads the base cast with parent 0 and the stage with root and parent 38765, and no threshold message"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// Presses the ability, moves the clock `advance_ms` on so the stage Proxy's phases fire,
/// and reads until `gos` gos of the player's own casts have arrived and the server has
/// written all it held for this connection (pings numbered `pong` and `pong + 1`),
/// giving the frames of the press. A refusal of the press (0x7fc) fails at once, naming
/// its result, because no go would follow it and the Beast's own attacks would keep the
/// wait for them alive for ever, with the test's deadline only warning. `advance_ms` must be in [500, 1133).
fn press_and_read_gos(
  game game: game_client.Game,
  have have: BitArray,
  time time: driven_time.Time,
  client_cast_id client_cast_id: Int,
  advance_ms advance_ms: Int,
  gos gos: Int,
  pong pong: Int,
  beast beast: Int,
) -> #(List(Frame), BitArray) {
  assert advance_ms >= 500 && advance_ms < 1133
    as "the advance is at least 500 ms, so the global cooldown's 500 ms refusal window has passed (below it a second tap is refused with result 14), and under 1133 ms, because both stage Proxies start with no delay (Spell4Effects 83776 and 83782, delayTime 0) and their first phase is at 133 ms (SpellPhase 3712 and 4032), so the first Beast round's 1000 ms strike deadline (strike_tell.deadline_ms) falls at press + 1133 and an advance past it closes that round in driven time while the Beast's real answer is still coming"
  game_client.press_ability(game:, client_cast_id:, bag_index: 0, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: pong)
  driven_time.advance(time:, ms: advance_ms)
  let #(later, have) =
    game_client.read_until(game:, have:, found: fn(later) {
      let seen = list.append(pressed, later)
      list.length(own_go_targets(frames: seen, beast:)) >= gos
      || refusals(frames: seen) != []
    })
  let #(rest, have) =
    game_client.read_until_pong(game:, have:, number: pong + 1)
  let frames = list.flatten([pressed, later, rest])
  assert refusals(frames:) == []
    as "opcode.0x7fc: the press is accepted, so no refusal is written"
  #(frames, have)
}

/// The results of the refusals (0x7fc) among the frames, in order.
fn refusals(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastRefused(result:, ..) -> Ok(result)
      game_client.CastConfirmed(..)
      | game_client.CastStarted(..)
      | game_client.CastWent(..)
      | game_client.CastFinished(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..) -> Error(Nil)
    }
  })
}

/// The targets of each go of a cast that is not the Beast's, in order: a Beast a
/// player strikes fights back, and its own gos name the player (the design of step
/// F: a strike puts its striker on the creature's threat list).
fn own_go_targets(
  frames frames: List(Frame),
  beast beast: Int,
) -> List(List(Int)) {
  game_client.go_targets_in(frames:)
  |> list.filter(fn(go) { cast_state.caster_of(cast_id: go.0) != beast })
  |> list.map(fn(go) { go.1 })
}

pub fn a_stalkers_second_tap_of_shred_strikes_the_beast_with_the_stages_proxy_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [beast_place(x: 1.5, z: 0.5)],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, frames, have) =
    enters_and_sees_the_beasts(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 5,
      beasts: 1,
    )
  let assert [beast, ..] = game_client.creatures_created_in(frames:)
  let beast_unit = beast.unit_id
  let own = game_client.unit_create_player_in(frames:).unit_id
  let #(first_tap, have) =
    press_and_read_gos(
      game:,
      have:,
      time:,
      client_cast_id: 1,
      advance_ms: 1000,
      gos: 5,
      pong: 1,
      beast: beast_unit,
    )
  assert own_go_targets(frames: first_tap, beast: beast_unit)
    == [[], [], [beast_unit], [beast_unit], [beast_unit]]
    as "Spell4.38765, Shred: its own go names nobody (it has no damage), so does the Stalker's passive 45057 (its ungated Proxy 147125 starts 60724 after 50 ms, with no damage), and Shred's Proxy 38767, aimed at the area (Spell4Effects 83788, targetFlags 4), goes in three phases (SpellPhase 3712 to 3714), each naming the Beast 3 m away inside Spell4AoeTargetConstraints 694 (360 degrees, 6.5 m)"
  assert list.map(game_client.health_in(frames: first_tap), fn(health) {
      health.1
    })
    == [43, 34, 25]
    as "a Stalker of level 1 with the Novice gear (Assault Power 50.77): a hit of Shred's Proxy is 0.0967 x 50.77 = 4.91 plus 4.22 for the level, 9.13, rounded to 9 (Spell4Effects 83788, 0x140565600); the Beast has 52 health and never deflects, so each of the three hits takes 9"
  let #(second_tap, _) =
    press_and_read_gos(
      game:,
      have:,
      time:,
      client_cast_id: 2,
      advance_ms: 1000,
      gos: 5,
      pong: 3,
      beast: beast_unit,
    )
  assert own_go_targets(frames: second_tap, beast: beast_unit)
    == [[], [beast_unit], [beast_unit], [beast_unit], [own]]
    as "Spell4Thresholds 238: the second tap casts the stage 38766, which strikes nobody itself, and the stage's Proxy 39467 (Spell4Effects 83782), aimed at the area by Spell4Effects 86439 on Spell4 39467's area row 694, goes in three phases (SpellPhase 4032 to 4034), each naming the Beast; then the Stalker's passive 45057 starts 63366 (its row 159136, type 14, dataBits00 44), whose Spell4Effects 159134 (type 73) is aimed at the caster"
  assert list.map(game_client.health_in(frames: second_tap), fn(health) {
      health.1
    })
    == [16, 7, 0]
    as "each go of the stage's Proxy hits for 9 as the base's does (Spell4Effects 86439 holds the parameters of 83788): 25 less 9 is 16, 7 and then the Beast's last 7 health"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_stalkers_held_shred_taps_its_stages_again_and_a_player_in_sight_reads_the_same_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 1)
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The global cooldown of the first cast is 1000 ms (Spell4.38765: SpellCoolDown
  // 115); the clock moves that far, so the Proxy's phases and the repeat fire in the
  // order of their times.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let own = cast_support.cast_lines(frames: list.append(pressed, later))
  assert list.take(own, 12)
    == [
      "started k1 38765 root 38765 parent 0",
      "opened 38765 k1",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
    ]
    as "opcode.0x4db and cast.hold_answer: held 1 starts Shred with a cast id of the server's, no 0x7fd, and opens the threshold (opcode.0x816); Spell4.38765 thresholdTime 4000, its Proxy 38767 goes in three phases (SpellPhase 3712 to 3714) and the Stalker's passive 45057 starts 60724 beside it"
  assert list.drop(own, 12)
    == [
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
      "closed 38765 1",
    ]
    as "cast.hold_repeat: with the key still down, one global cooldown later (Spell4.38765: SpellCoolDown 115, 1000 ms) the next tap casts the stage 38766 (Spell4Thresholds 238), the last, and 0x814 closes the threshold (opcode.0x814)"
  // The server has taken the release before the clock moves on, and the clock moves
  // 1500 ms, past the next global cooldown (1000 ms) by half of it, so a repeat the
  // release failed to stop would fire inside it.
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 0)
  let #(_, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  driven_time.advance(time:, ms: 1500)
  let #(after_release, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: after_release)
    == ["went k1 p0", "went k1 p1", "went k1 p2", "finished k1"]
    as "cast.hold_stop: held 0 cuts no cast short, so the stage's Proxy 39467 goes in its three phases (SpellPhase 4032 to 4034), and it ends the repeats, so no cast starts one global cooldown later"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 19)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 38765 root 38765 parent 0",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
      "went k5 p0",
      "went k5 p1",
      "went k5 p2",
      "finished k5",
    ]
    as "opcode.0x7ff.root_parent: a player in sight reads the same casts, the base cast with parent 0 and the repeat's stage with root and parent 38765"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_stalkers_connection_ending_mid_hold_removes_it_for_a_player_in_sight_and_the_server_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 1)
  // The hold is under way with the Proxy's phases and the repeat still to fire: the
  // clock does not move, so the connection ends in the middle of it.
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  game_client.close(game: first)
  let #(seen, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0355 })
    })
  assert list.any(seen, fn(frame) {
    frame.message_id == 0x0355
    && unit_destroyed.decode(frame.body)
    == Ok(unit_destroyed.UnitDestroyed(unit_id: 1, chest_world_object_delay: 0))
  })
    as "opcode.0x355: the map removes the unit that held a key when its connection ended"
  game_client.hold_ability(game: second, bag_index: 0, target: 0, held: 1)
  let #(own, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let assert [
    game_client.CastStarted(
      spell4_id: 58_832,
      root_spell4_id: 58_832,
      parent_spell4_id: 0,
      caster_unit_id: 2,
      ..,
    ),
    ..
  ] = game_client.casts_in(frames: own)
    as "the server goes on: the second player's own hold of Spell4.58832, Discharge, the Medic's first level-1 ability (SpellLevel 631), is answered with its own 0x7ff, unit 2 casting"
  game_client.close(game: second)
  login_support.stop(started)
}

/// A suited player's connection ends before the suit's 10,250 ms are up, on a clock the
/// test moves by hand: the watcher is written the suit once, then 0x355 for the unit and
/// no 0x933 after, and the server goes on. The first player's class presses the ability
/// at `bag_index` that puts the suit of `display` on it.
fn a_suited_players_connection_ends(
  tables tables: table_store.Tables,
  first_class first_class: Int,
  bag_index bag_index: Int,
  display display: Int,
) -> Nil {
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, second_have:, ..) =
    two_players_enter_on(tables:, first_class:, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  let is_suit = fn(frame: Frame) { frame.message_id == 0x0933 }
  let #(suited, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, is_suit)
    })
  let assert [suit] = list.filter(suited, is_suit)
    as "the watcher's client is written one 0x933 when the suit goes on"
  assert unit_item_visuals_changed.decode(suit.body)
    == Ok(
      UnitItemVisualsChanged(unit_id: 1, item_visuals: [
        ItemVisual(slot: 64, display_id: display, item_color_set_id: 0, dye: 0),
      ]),
    )
    as "opcode.0x933: unit 1 in slot 64 with the suit of a faction 166 player, ItemDisplay 7221 (178142 of Spell4 47860)"
  // The clock is the test's and has not moved, so the suit's 10,250 ms are not up: the
  // connection ends in the middle of the suit.
  game_client.close(game: first)
  let #(after, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0355 })
    })
  assert list.any(after, fn(frame) {
    frame.message_id == 0x0355
    && unit_destroyed.decode(frame.body)
    == Ok(unit_destroyed.UnitDestroyed(unit_id: 1, chest_world_object_delay: 0))
  })
    as "opcode.0x355: the map removes the suited unit when its connection ended"
  let #(rest, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert list.filter(list.append(after, rest), is_suit) == []
    as "no 0x933 follows the end of the suited player's connection, the restore included: its unit is gone"
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn an_engineers_connection_ending_mid_suit_removes_it_for_a_player_in_sight_with_no_0x933_after_and_the_server_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mode: Eradicate is the Engineer's innate, after its three abilities in the bag
  // (`Class` 2 spell4IdInnateAbilityActive00 47866).
  a_suited_players_connection_ends(
    tables: character_tables.shared(),
    first_class: 2,
    bag_index: 3,
    display: 7221,
  )
}

pub fn a_spellslingers_quick_draw_goes_in_five_phases_and_its_charged_shot_is_held_until_the_release_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 7, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let child = fn(number, spell4_id) {
    [
      "started k"
        <> int.to_string(number)
        <> " "
        <> int.to_string(spell4_id)
        <> " root 43468 parent 43468",
      "went k" <> int.to_string(number) <> " p0",
      "finished k" <> int.to_string(number),
    ]
  }
  let quick_draw =
    list.flatten([
      ["went k1 p0", "went k1 p1"],
      child(2, 43_498),
      ["went k1 p2"],
      child(3, 43_499),
      ["went k1 p3"],
      child(4, 43_498),
      // 43500 holds one lasting row, a type 17 of 990 ms (Spell4Effects 99472), so
      // it is still going when the cast ends 1000 ms in: it has no finish yet.
      [
        "started k5 43500 root 43468 parent 43468",
        "went k5 p0",
      ],
      ["went k1 p4", "finished k1"],
    ])
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The phases of Quick Draw come 0, 366, 200, 200 and 234 ms after one another
  // (SpellPhase 5882 to 5886), 1000 ms in all.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", ..quick_draw]
    as "Spell4.43468, Quick Draw (SpellLevel 1011): five gos, the phase indexes 0 to 4 (SpellPhase 5882 to 5886), and the children whose caster apply gate passes: no cast of 43500 is live, so 17301 (type 15, comparison 2 on 43500) passes and 17302 (comparison 1) fails: 43498 by Spell4Effects 196513 in phase 1, 43499 by 196514 in phase 2, 43498 by 196515 and 43500 by 196516 in phase 3, each with its own go and finish, then Quick Draw's finish"
  let #(seen, second_have) =
    game_client.read_kept(game: second, have: second_have, count: 18)
  assert cast_support.cast_lines(frames: seen)
    == ["started k1 43468 root 43468 parent 0", ..quick_draw]
  game_client.press_ability(
    game: first,
    client_cast_id: 2,
    bag_index: 1,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  // Spell4Thresholds 123 raises the charge to level 1 after its thresholdDuration,
  // 1000 ms; the level after it (Spell4Thresholds 124) comes 1400 ms later.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", "opened 34718 k1", "finished k2", "index 34718 1"]
    as "Spell4.34718, Charged Shot (SpellLevel 1036): the press opens the threshold with the cast's id and holds the cast; Spell4Thresholds 123 raises the level to 1 after thresholdDuration 1000 (opcode.0x817); the Quick Draw's 43500, a lasting row of 990 ms (Spell4Effects 99472), finishes in the same window"
  game_client.press_ability(
    game: first,
    client_cast_id: 3,
    bag_index: 1,
    target: 0,
  )
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 5)
  assert cast_support.cast_lines(frames: own)
    == [
      "confirmed k1",
      "went k1 p0",
      "finished k1",
      "closed 34718 0",
      "finished k2",
    ]
    as "the release casts the row at level 1, 34722 (Spell4Thresholds 123), then 0x814 closes the threshold and the base cast ends with its 0x7fe (cast.charge_release_base)"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 6)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 34718 root 34718 parent 0",
      "finished k2",
      "started k3 34722 root 34718 parent 34718",
      "went k3 p0",
      "finished k3",
      "finished k1",
    ]
    as "cast.stage_root_parent: a player in sight reads the charge, then the stage with root and parent 34718, and no go for the base cast"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_player_in_sight_is_sent_the_worn_visuals_the_player_wears_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    first_burst:,
    second_burst:,
    seen_second:,
    ..,
  ) = two_players_enter_one_map(time:)
  let worn = novice_tables.worn_visuals(class_id: 4, faction_id: 166)
  let decoded = fn(frame: Frame) {
    let assert Ok(player) = unit_create_player.decode(frame.body)
      as "0x262 decodes"
    player
  }
  assert worn_in(player: game_client.unit_create_player_in(frames: first_burst))
    == worn
    as "opcode.0x262.worn_visuals: the Exile Medic is drawn in its own set: chest 4106, legs 4107, shoulder 4158, feet 4105, hands 4104 and weapon 3280 (Item2.novice_visuals)"
  let assert [seen_first] = list.drop(second_burst, burst_length())
  assert worn_in(player: decoded(seen_first)) == worn
    as "opcode.0x262.other_player: the second player's client is sent the first's 0x262 with the same worn visuals"
  assert worn_in(player: decoded(seen_second)) == worn
    as "opcode.0x262.other_player: the first player's client is sent the second's 0x262 with its worn visuals"
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
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    second_character:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter_one_map(time:)
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
    game_client.read_message(
      game: second,
      have: second_have,
      message_id: 0x0092,
    )
  game_client.send_world(game: second, message_id: 0x00C0, body: <<>>)
  let #(left, second_have) = game_client.next(game: second, have: second_have)
  assert left.message_id == 0x0594
    as "the camp returns the client to character select"
  let #(gone, first_have) = game_client.next(game: first, have: first_have)
  assert gone.message_id == 0x0355 as "opcode.0x355: the unit is removed"
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == 2
  // It plays again as a new unit, which the first sees appear.
  game_client.send(game: second, message_id: 0x07E0, body: <<>>)
  let #(_list, second_have) =
    game_client.read_message(
      game: second,
      have: second_have,
      message_id: 0x0117,
    )
  send_play(game: second, character_id: second_character)
  let #(_again, _second_have) =
    game_client.read_entry_kept(game: second, have: second_have)
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

/// A created Warrior of CharacterCreation row 466 for the account, played into
/// the map: its client, in the world, with the bytes read beyond its entry.
fn created_warrior_enters(
  game game: game_client.Game,
  name name: String,
) -> #(game_client.Game, BitArray) {
  game_client.send_create(game:, body: create_request(name))
  let created = created_result(game)
  let _list = listed_entries(game)
  send_play(game:, character_id: created.character_id)
  let #(_burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  #(game, have)
}

pub fn a_second_player_sees_the_first_take_off_its_chest_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let first = in_select(started:, port:, account:)
  let second_guid = support.guid_of(0x22)
  let second_account =
    AccountId(login_support.insert_other(
      started:,
      login_name: "player2",
      game_account_id: second_guid,
    ))
  let second =
    connected_as(
      started:,
      port:,
      account: second_account,
      login_name: "player2",
      game_account_id: second_guid,
      key: support.guid_of(2),
    )
  let #(first, first_have) = created_warrior_enters(game: first, name: "Zed Qu")
  let #(second, second_have) =
    created_warrior_enters(game: second, name: "Ann Qu")
  // The second's entry is followed by the 0x262 of the first, which names its unit.
  let #(seen_first, second_have) =
    game_client.next(game: second, have: second_have)
  let first_unit = unit_of(seen_first)
  let #(_seen_second, _first_have) =
    game_client.next(game: first, have: first_have)
  // The first takes its chest, held at worn slot 0, into its first bag slot.
  let assert Ok(move) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: 0, bag_index: 0),
      to: item_place.ItemPlace(location: 1, bag_index: 0),
    ))
    as "0x182 encodes"
  game_client.send_world(game: first, message_id: 0x0182, body: move)
  let is_properties = fn(frame: Frame) { frame.message_id == 0x093A }
  let #(seen, _second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, is_properties)
    })
  let assert [look] =
    list.filter(seen, fn(frame) { frame.message_id == 0x0933 })
    as "the second client is written one 0x933 when the first's chest comes off"
  assert unit_item_visuals_changed.decode(look.body)
    == Ok(
      UnitItemVisualsChanged(unit_id: first_unit, item_visuals: [
        ItemVisual(slot: 1, display_id: 0, item_color_set_id: 0, dye: 0),
      ]),
    )
    as "opcode.0x933.empty_display: the first's chest slot 1 is emptied on the second's screen"
  let assert [properties] = list.filter(seen, is_properties) as "and one 0x93a"
  let assert Ok(changed) = unit_properties_changed.decode(properties.body)
  assert changed.unit_id == first_unit
  assert list.filter(changed.properties, fn(entry) {
      entry.property_id == 7 || entry.property_id == 42
    })
    == [
      UnitProperty(
        property_id: 7,
        base: float32.to_bits(586.0),
        value: float32.to_bits(586.0),
      ),
      UnitProperty(
        property_id: 42,
        base: float32.to_bits(187.5),
        value: float32.to_bits(187.5),
      ),
    ]
    as "player.level1_gear_properties: without the chest's quarter of the 600 Base Health and its 62.5 Armor, 736 falls to 586 and 250 to 187.5"
  assert list.map(seen, fn(frame) { frame.message_id })
    |> list.filter(fn(id) { id == 0x0933 || id == 0x093A })
    == [0x0933, 0x093A]
    as "the look comes before the properties"
  game_client.close(game: first)
  game_client.close(game: second)
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
/// zones are the planted WorldZone rows, whose top zones are 4961 and 35. Every
/// seat has read the other three players' units, so no player's entry is still
/// on its way to another seat. The server runs on the driven clock `time`.
fn four_players(
  time time: driven_time.Time,
) -> #(login_support.Started, List(Seat)) {
  let started = login_support.start(time:)
  let seats =
    list.map(
      [#(1, "Zed Qu"), #(2, "Ann Qu"), #(3, "Bob Qu"), #(4, "Cat Qu")],
      fn(player) {
        let #(number, character_name) = player
        let #(game, character) = new_player(started:, number:, character_name:)
        send_play(game:, character_id: character)
        let #(burst, have) = game_client.read_entry_kept(game:, have: <<>>)
        let zone_channel = game_client.zone_channel_in(frames: burst)
        assert zone_channel == 1
          as "chat.zone_channel_id: the burst gives Zone the fixed id 1 in every seat"
        Seat(game:, have:, zone_channel:)
      },
    )
  #(started, list.map(seats, told_of_the_others))
}

/// Reads until the seat has been told of the three other players' units (0x262).
/// Each of their connections writes its own unit to this one after its own
/// burst, so no ping to this connection settles them: a pong comes after only
/// what this connection took before the ping.
fn told_of_the_others(seat: Seat) -> Seat {
  let seat = wait_for_frame(seat:, message_id: 0x0262).1
  let seat = wait_for_frame(seat:, message_id: 0x0262).1
  wait_for_frame(seat:, message_id: 0x0262).1
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  game_client.send_world(game: target.game, message_id: 0x00BF, body: <<1>>)
  let target = wait_for_frame(seat: target, message_id: 0x0092).1
  game_client.send_world(game: target.game, message_id: 0x00C0, body: <<>>)
  let #(frame, have) = game_client.next(game: target.game, have: target.have)
  assert frame.message_id == 0x0594
    as "the camp returns the client to character select"
  let target = Seat(..target, have:)
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
  let #(listed, target) = wait_for_frame(seat: target, message_id: 0x0117)
  let assert Ok(listing) = character_list.decode(listed.body)
  let assert [entry] = listing.characters
  send_play(game: target.game, character_id: entry.character_id)
  let #(_, have) =
    game_client.read_entry_kept(game: target.game, have: target.have)
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
  // The speaker's accept is written before the line is told to the target, so
  // the target's line is waited for, not a pong after the accept.
  let #(line, have) =
    game_client.read_chat(game: target.game, have: target.have)
  assert line.text == "again"
  // One sender writes to this seat, so a second "again" would arrive before the
  // next line: the line after it is the next one sent.
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "once",
    chat_message_id: 3,
  )
  let #(next_line, _) = game_client.read_chat(game: target.game, have:)
  assert next_line.text == "once" as "the first whisper was told to it once"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_speaker_that_ends_before_the_reply_leaves_the_target_with_its_line_and_no_error_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("serial")
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  let lines = process.new_subject()
  // Only the two connections of this test are read: another test's connection
  // or listener logging at the same time is no line of this one.
  let assert Ok(speaker_pid) =
    registry.find_named(started.settings.registry, "zed qu")
  let assert Ok(target_pid) =
    registry.find_named(started.settings.registry, "ann qu")
  let speaker_capture =
    log_capture.start_with_metadata(from: speaker_pid, into: lines)
  let capture = log_capture.start_with_metadata(from: target_pid, into: lines)
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
  log_capture.stop(speaker_capture)
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
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
  let _reason =
    ask_support.ended(watched: gone, what: "the killed member to end")
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
  // The speaker's accept is written before the line is told to the group, so
  // the survivor's line is waited for, not a pong after the accept.
  let #(heard, _) = wait_for_frame(seat: survivor, message_id: 0x01C8)
  let assert Ok(line) = game_client.heard_line(frame: heard)
  assert line.text == "still here"
    as "the design's failure table: a later line goes to the others, and the dead member is no longer in the group"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

/// Reads until the server writes a message with this id, and gives it.
fn wait_for_frame(
  seat seat: Seat,
  message_id message_id: Int,
) -> #(Frame, Seat) {
  let #(frame, have) =
    game_client.read_message(game: seat.game, have: seat.have, message_id:)
  #(frame, Seat(..seat, have:))
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
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
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

// ---- the sitting bot on the whole server ----

/// Every event the bot reports, in order, up to and including the first for
/// which `done` holds of what has been seen so far; the test fails when the bot
/// reports no more within the event deadline.
fn events_until(
  events events: process.Subject(sitting_bot.Event),
  seen seen: List(sitting_bot.Event),
  done done: fn(List(sitting_bot.Event)) -> Bool,
) -> List(sitting_bot.Event) {
  case done(seen) {
    True -> list.reverse(seen)
    False -> {
      let event =
        open_wait.received(
          from: events,
          what: "the bot's report of what the test waits for",
        )
      events_until(events:, seen: [event, ..seen], done:)
    }
  }
}

pub fn a_sitting_bot_and_a_player_see_each_other_appear_hear_each_others_say_lines_and_the_player_sees_the_bot_leave_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
    as "the bot is seated near the player"
  let events = process.new_subject()
  let finished = process.new_subject()
  let bot =
    process.spawn_unlinked(fn() {
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.Schedule(
            walk: sitting_bot.client_circle,
            chat_every_ms: 300,
            whisper_every_ms: 600,
          ),
          // Past the test's deadline: only the stop can end the bot inside it.
          for_ms: 300_000,
          report: fn(event) { process.send(events, event) },
        ),
      )
    })
  // The player sees the bot appear, then says a line the bot can hear.
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  let assert Ok(bot_unit) = unit_create_player.decode(appeared.body)
  assert bot_unit.name == "Sitting Bot"
    as "the player sees the bot's unit appear"
  game_client.say(game: zed, text: "hello bot", chat_message_id: 1)
  // The bot's own say reaches the player on Say, from the bot's name.
  let #(heard_by_player, have) =
    game_client.read_chat(game: zed, have: zed_seat.have)
  let zed_seat = Seat(..zed_seat, have:)
  assert heard_by_player
    == game_client.HeardLine(
      channel_type: 4,
      channel_id: 0,
      sender: "Sitting Bot",
      text: "bot say 1",
    )
    as "the sitting bot's first line is a say with the counter 1, and the player reads it"
  // The bot saw the player appear and heard the player's say.
  let heard_by_bot =
    sitting_bot.LineHeard(line: game_client.HeardLine(
      channel_type: 4,
      channel_id: 0,
      sender: "Zed Qu",
      text: "hello bot",
    ))
  let accepted_for_bot =
    sitting_bot.LineAccepted(chat_message_id: 1, name: "Sitting Bot")
  let seen_by_bot =
    events_until(events:, seen: [], done: fn(seen) {
      list.contains(seen, heard_by_bot) && list.contains(seen, accepted_for_bot)
    })
  assert list.contains(
    seen_by_bot,
    sitting_bot.UnitShown(unit_id: 1, name: "Zed Qu"),
  )
    as "the bot is shown the player's unit, the map's first, with its name"
  assert list.contains(seen_by_bot, heard_by_bot)
    as "the bot hears the player's say"
  assert list.contains(seen_by_bot, accepted_for_bot)
    as "the bot's first line, numbered 1 as the client numbers, is answered with its accept"
  // The bot stops and leaves: the player sees its unit go.
  sitting_bot.request_stop(bot)
  let tally =
    open_wait.received(
      from: finished,
      what: "the bot to end when asked to stop",
    )
  assert tally.lines_heard >= 1
    && tally.units_seen >= 1
    && tally.lines_sent >= 1
    as "the summary counts what the bot sent, was shown and heard"
  let #(gone, _zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0355)
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == bot_unit.unit_id
    as "the bot's unit is removed for the player when the bot closes its connection"
  game_client.close(game: zed)
  login_support.stop(started)
}

pub fn a_sitting_bot_that_follows_replays_the_named_players_moves_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
  let finished = process.new_subject()
  let bot =
    process.spawn_unlinked(fn() {
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.Schedule(
            walk: sitting_bot.Follow(delay_ms: 200),
            chat_every_ms: 600_000,
            whisper_every_ms: 600_000,
          ),
          for_ms: 60_000,
          report: fn(_event) { Nil },
        ),
      )
    })
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  let bot_unit = unit_of(appeared)
  // The player walks: a position, a velocity, a rotation and a state, as the
  // client's own batch holds them (opcode.0x637).
  let velocity =
    movement_velocity.MovementVelocity(
      x: 0x3C00,
      y: 0x0000,
      z: 0x4000,
      blends: 1,
    )
  let rotation = MovementRotation(yaw: 0x3F000000, pitch: 0, roll: 0, blends: 0)
  let flags = movement_state_flags.MovementStateFlags(flags: 0x1)
  game_client.send_world(
    game: zed,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1234, commands: [
      game_client.position_command(x: 100.5, y: 50.25, z: -200.75),
      movement_command.Velocity(velocity),
      movement_command.Rotation(rotation),
      movement_command.StateFlags(flags),
    ]),
  )
  // The bot's own 0x0637 follows after its delay: the player sees the bot's unit
  // move with the same commands, its position the player's own.
  let #(replayed, _zed_seat) =
    wait_for_move_of(seat: zed_seat, unit_id: bot_unit)
  assert replayed
    == [
      relayed_movement.Position(UnitPositionCommand(
        x: float32.to_bits(100.5),
        y: float32.to_bits(50.25),
        z: float32.to_bits(-200.75),
        blends: 0,
      )),
      relayed_movement.Velocity(velocity),
      relayed_movement.Rotation(rotation),
      relayed_movement.StateFlags(flags),
    ]
    as "the bot walks as the player did, every command as the client sent it"
  sitting_bot.request_stop(bot)
  let _tally =
    open_wait.received(
      from: finished,
      what: "the bot to end when asked to stop",
    )
  game_client.close(game: zed)
  login_support.stop(started)
}

/// Reads until a 0x638 of the unit and gives its commands.
fn wait_for_move_of(
  seat seat: Seat,
  unit_id unit_id: Int,
) -> #(List(relayed_movement.RelayedMovement), Seat) {
  let #(frame, seat) = wait_for_frame(seat:, message_id: 0x0638)
  let assert Ok(moved) = unit_movement.decode(frame.body) as "0x638 decodes"
  case moved.unit_id == unit_id {
    True -> #(moved.commands, seat)
    False -> wait_for_move_of(seat:, unit_id:)
  }
}

@external(erlang, "sitting_bot_signal_ffi", "send_sigterm")
fn send_sigterm() -> Nil

@external(erlang, "sitting_bot_signal_ffi", "restore_signal_handler")
fn restore_signal_handler() -> Nil

pub fn a_sigterm_to_the_node_ends_the_sitting_bot_which_leaves_and_gives_its_tally_test() -> Nil {
  use <- owned_test.run(120_000)
  // The VM's signal handling is the node's: the bot's handler replaces OTP's
  // while it sits, so no other test may be running.
  use <- unitest.tag("serial")
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
  let finished = process.new_subject()
  let _bot =
    process.spawn_unlinked(fn() {
      sitting_bot.stop_on_sigterm(process.self())
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.client_schedule(walk: sitting_bot.client_circle),
          // Past the test's deadline: only the stop can end the bot inside it.
          for_ms: 300_000,
          report: fn(_event) { Nil },
        ),
      )
    })
  // The bot is in the map once the player is shown its unit; then the node
  // receives SIGTERM.
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  send_sigterm()
  let _tally =
    open_wait.received(
      from: finished,
      what: "the bot to end on SIGTERM and give its tally",
    )
  let #(gone, _zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0355)
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == unit_of(appeared)
    as "the bot closed its connection, so the player sees its unit go"
  restore_signal_handler()
  game_client.close(game: zed)
  login_support.stop(started)
}

/// The server's tree with the world standing the creatures of the spawn table
/// the test's database holds: the 27 Virtual Defense Daguns the migrations seed
/// and the 27 Virtual Battle Beasts of the planted world-database file, loaded
/// through the content load into a key of the test's own, on the driven clock
/// `time`.
fn start_with_creatures(time time: driven_time.Time) -> login_support.Started {
  start_with_world_data(folder: content_support.fixture_folder, time:)
}

/// The server's tree with the world standing the spawns of the planted world-database
/// file in the folder and the migrations' seeded ones, loaded through the content load
/// into a key of the test's own, and the game connections holding the visibility
/// prerequisites and the reused unit objectives the load found (as the server's own
/// start passes them), on the driven clock `time`.
fn start_with_world_data(
  folder folder: String,
  time time: driven_time.Time,
) -> login_support.Started {
  start_with_world_data_on(folder:, time:, adjusted: fn(settings) { settings })
}

/// As `start_with_world_data`, the server's settings then passed through
/// `adjusted`: a test whose casts run on timers moves `time` by hand.
fn start_with_world_data_on(
  folder folder: String,
  time time: driven_time.Time,
  adjusted adjusted: fn(server.Settings) -> server.Settings,
) -> login_support.Started {
  login_support.start_with(time:, change: with_world_data(folder:, adjusted:))
}

/// The change of the server's settings that imports the planted world-database file
/// in `folder`, loads the content into a key of the test's own and passes the settings
/// through `adjusted`.
fn with_world_data(
  folder folder: String,
  adjusted adjusted: fn(server.Settings) -> server.Settings,
) -> fn(server.Settings) -> server.Settings {
  fn(settings: server.Settings) {
    let pool =
      pog.Config(
        ..settings.pool,
        pool_name: process.new_name("content_pool"),
        pool_size: 1,
      )
    let assert Ok(_) =
      import_world_data.import_spawns(
        db: content_support.connect_with(config: pool),
        folder:,
      )
      as "the planted world-database file imports"
    let key = owned_key.new_fixture_key()
    let assert Ok(Nil) =
      content.load(
        tables: character_tables.content_tables(),
        migrations: genesis_prime.load_migrations(),
        pool: pog.Config(..pool, pool_name: process.new_name("load_pool")),
        ask: readiness.Settings(
          within_ms: ask_support.beyond_the_test_ms,
          attempt_ms: ask_support.beyond_the_test_ms,
          pause_ms: 50,
        ),
        probe: content.pool_probe,
        terrain: terrain_support.flat_reader(),
        key:,
      )
      as "the content load puts the seeded spawns in the world's term"
    server.Settings(
      ..settings,
      game: server.Served(
        ..settings.game,
        settings: connection_state.Settings(
          ..settings.game.settings,
          visibility: content_spawn.visibility(key:),
          reused_unit_objectives: content_spawn.reused_unit_objectives(key:),
        ),
      ),
      world: server.World(..settings.world, spawns: key),
    )
    |> adjusted
  }
}

pub fn a_bot_entering_warfare_woods_is_written_one_0x262_for_each_planted_spawn_and_a_second_bot_sees_the_same_unit_ids_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = start_with_creatures(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(first, first_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  character_support.move_to(
    pool:,
    character_id: first_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: character_tables.exile_circle_centre(),
  )
  send_play(game: first, character_id: first_character)
  let #(_burst, have) = game_client.read_entry_kept(game: first, have: <<>>)
  let #(frames, _) =
    game_client.read_until(game: first, have:, found: fn(frames) {
      list.length(planted_creatures_in(frames:)) >= 54
    })
  let seen = planted_creatures_in(frames:)
  assert list.length(seen) == 54
    as "one 0x262 for each of the 54 spawns: the 27 Virtual Battle Beasts and the 27 Virtual Defense Daguns, all within 1024 units of the characters in Warfare Woods"
  let units = list.map(seen, fn(creature) { creature.unit_id })
  assert list.length(list.unique(units)) == 54
    && list.all(units, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "each unit id is its own, never 0 and below 2^20"
  assert list.count(seen, fn(creature) { creature.creature_id == 73_464 }) == 27
    && list.count(seen, fn(creature) { creature.creature_id == 73_465 }) == 27
    as "opcode.0x262.creature: the Creature2 id of each spawn's creature"
  assert list.all(seen, fn(creature) {
    let values = #(
      creature.tail.display_info_id,
      creature.tail.outfit_info_id,
      creature.tail.faction_id,
      creature.tail.base_faction_id,
    )
    case creature.creature_id {
      73_464 -> values == #(26_565, 0, 1441, 1441)
      _ -> values == #(26_578, 0, 1442, 1442)
    }
  })
    as "each spawn's own values: the Battle Beast's display 26565, faction 1441 and base faction 1441, the Dagun's 26578, 1442 and 1442, and no outfit (the world database's rows and migration 0008's)"
  let #(second, second_character) =
    new_player(started:, number: 2, character_name: "Ann Qu")
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: character_tables.exile_circle_centre(),
  )
  send_play(game: second, character_id: second_character)
  let #(_burst, have) = game_client.read_entry_kept(game: second, have: <<>>)
  let #(frames, _) =
    game_client.read_until(game: second, have:, found: fn(frames) {
      list.length(planted_creatures_in(frames:)) >= 54
    })
  assert list.sort(
      list.map(planted_creatures_in(frames:), fn(creature) { creature.unit_id }),
      int.compare,
    )
    == list.sort(units, int.compare)
    as "two players see one unit id for each creature"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The creatures the frames create that are the planted Virtual Battle Beasts and
/// Virtual Defense Daguns; the creatures a kill objective's marker places in the same
/// world arrive in the same range and are not among them.
fn planted_creatures_in(
  frames frames: List(Frame),
) -> List(unit_create_creature.UnitCreateCreature) {
  list.filter(game_client.creatures_created_in(frames:), fn(creature) {
    creature.creature_id == 73_464 || creature.creature_id == 73_465
  })
}

// ---- the creatures a kill objective's marker places, on the whole server ----
//
// Objective 21290 (QuestObjective: type 8, TargetGroup 14356 of Creature2 73492 then
// 73567, count 3, marker 51740) is the sixth objective of quest 10518 (Quest2
// objective05: `table_rows -- Quest2 10518`), so its progress is the 0x361 of index 5
// (opcode.0x361). The client's marker 51740 is at (-142.06599, -860.46375, 556.80902)
// with radius 38 in World 3460, zone 5967 (`table_rows -- WorldLocation2 51740`);
// the ring of the design (issue 602) is the circle of half that radius, the slot i of
// 3 at the angle 2 pi i / 3 from the +x axis towards +z, the group's creatures in
// order: 73492, 73567, 73492. Creature2 73492 has factionId 170 and no
// prerequisite, hostile to the Exile (Faction2Relationship 686: 167 and 170, level
// 0; Faction2 167 is the Exile, 166 the Dominion), so an Exile character (faction
// 167) may attack it. Paralytic Surge reaches 15
// (Spell4 42352 targetMaxRange), and a creature's aggro range is 10 (migration 0010),
// so the character stands 12 beyond the slot, away from the ring's centre.

/// The marker's centre and the ring's radius, half the marker's 38.
const marker_51740 = #(-142.06599, -860.46375, 556.80902)

const ring_radius = 19.0

/// Where slot `index` of the 3 on marker 51740's ring is: the point on the circle at
/// 2 pi index / 3 from the +x axis towards +z, at the marker's height.
fn ring_slot(index index: Int) -> #(Float, Float, Float) {
  let angle = 2.0 *. maths.pi() *. int.to_float(index) /. 3.0
  #(
    marker_51740.0 +. ring_radius *. maths.cos(angle),
    marker_51740.1,
    marker_51740.2 +. ring_radius *. maths.sin(angle),
  )
}

fn is_near(
  left left: #(Float, Float, Float),
  right right: #(Float, Float, Float),
) -> Bool {
  float.absolute_value(left.0 -. right.0) <. 0.01
  && float.absolute_value(left.1 -. right.1) <. 0.01
  && float.absolute_value(left.2 -. right.2) <. 0.01
}

/// A world on the planted world data and the content load, whose game connections take
/// the tables given and, with the maps, their time from `time`.
fn world_with_the_markers_creatures(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_on(
    folder: content_support.fixture_folder,
    tables:,
    time:,
    tutorial: False,
  )
}

/// A world on the planted world data of `folder` and the content load, whose game connections
/// take the tables given and, with the maps, their time from `time`. A world that `tutorial`
/// is on runs the tutorial as the content load read it: the first quest a new character of
/// World 3460 is given and the landing of each projector; the others give none.
fn world_on(
  folder folder: String,
  tables tables: table_store.Tables,
  time time: driven_time.Time,
  tutorial tutorial: Bool,
) -> login_support.Started {
  world_with_numbers(
    folder:,
    tables:,
    time:,
    tutorial:,
    numbers: function.identity,
  )
}

/// The world of `world_on` whose game connections take the game numbers `numbers` makes
/// of the tests' own.
fn world_with_numbers(
  folder folder: String,
  tables tables: table_store.Tables,
  time time: driven_time.Time,
  tutorial tutorial: Bool,
  numbers numbers: fn(GameNumbers) -> GameNumbers,
) -> login_support.Started {
  start_with_world_data_on(folder:, time:, adjusted: fn(settings) {
    let held =
      connection_state.Settings(
        ..settings.game.settings,
        numbers: numbers(settings.game.settings.numbers),
      )
    let key = settings.world.spawns
    server.Settings(
      ..settings,
      game: server.Served(..settings.game, settings: case tutorial {
        True ->
          connection_state.Settings(
            ..held,
            tables:,
            tutorial_chain: content_tutorial_quest.chain(key:),
            projector_landings: content_projector_landing.landings(key:),
          )
        False -> connection_state.Settings(..held, tables:)
      }),
    )
  })
}

/// A level 1 Medic of the Exile holding quest 10518 with objectives 0 to 4 done and `sixth`
/// of the 3 kills the sixth asks, played into World 3460 12 beyond ring slot 0 and facing
/// it, and read until both of Creature2 73492's 0x262 have arrived: the game, the burst's
/// frames and the bytes beyond.
fn a_medic_at_the_marker_ring(
  started started: login_support.Started,
  sixth sixth: Int,
) -> #(game_client.Game, List(Frame), BitArray, Int) {
  a_medic_of_a_level_at_the_marker_ring(
    started:,
    sixth:,
    level: 1,
    saved_experience: None,
  )
}

/// The same Medic of the level given, holding the experience its last save kept (`None`
/// for the least of its level).
fn a_medic_of_a_level_at_the_marker_ring(
  started started: login_support.Started,
  sixth sixth: Int,
  level level: Int,
  saved_experience saved_experience: Option(Int),
) -> #(game_client.Game, List(Frame), BitArray, Int) {
  a_player_of_a_level_at_the_marker_ring(
    started:,
    class_id: 4,
    sixth:,
    level:,
    saved_experience:,
  )
}

/// The same player of the class given.
fn a_player_of_a_level_at_the_marker_ring(
  started started: login_support.Started,
  class_id class_id: Int,
  sixth sixth: Int,
  level level: Int,
  saved_experience saved_experience: Option(Int),
) -> #(game_client.Game, List(Frame), BitArray, Int) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id:,
      level:,
    )
  case saved_experience {
    Some(experience) -> {
      let assert Ok(_) =
        pog.query(
          "update character set experience = $2 where character_id = $1",
        )
        |> pog.parameter(pog.int(character))
        |> pog.parameter(pog.int(experience))
        |> pog.execute(pool)
        as "the character's last save kept this experience"
      Nil
    }
    None -> Nil
  }
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile one (faction 167), which Creature2 73492 is hostile to"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10518, 1, 0, true, 31, '{5,1,1,1,2,"
      <> int.to_string(sixth)
      <> "}', 0, '{0,0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10518 with its first five objectives done: the client opens an objective of flag 2 (21290's 0x603) only when every earlier one is done (0x140553790)"
  let slot = ring_slot(index: 0)
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 5967,
    position: #(slot.0 +. 12.0, slot.1, slot.2),
  )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(targets_in(frames:)) >= 2
    })
  #(game, frames, have, character)
}

/// The creatures the frames create that are Creature2 73492.
fn targets_in(
  frames frames: List(Frame),
) -> List(unit_create_creature.UnitCreateCreature) {
  list.filter(game_client.creatures_created_in(frames:), fn(creature) {
    creature.creature_id == 73_492
  })
}

/// The 73492 of the frames that stands at ring slot 0.
fn the_target_at_slot_0(
  frames frames: List(Frame),
) -> unit_create_creature.UnitCreateCreature {
  let assert Ok(target) =
    list.find(targets_in(frames:), fn(creature) {
      is_near(
        left: game_client.placed_by_tail(tail: creature.tail),
        right: ring_slot(index: 0),
      )
    })
    as "a Creature2 73492 stands at ring slot 0"
  target
}

pub fn a_placed_target_is_shown_killed_and_counted_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 0)
  let shown = targets_in(frames:)
  assert list.map(shown, fn(creature) {
      game_client.placed_by_tail(tail: creature.tail)
    })
    |> list.all(fn(place) {
      is_near(left: place, right: ring_slot(index: 0))
      || is_near(left: place, right: ring_slot(index: 2))
    })
    as "opcode.0x262: the two 73492 of the ring stand at its slots 0 and 2, the group's creatures taking the slots in order, 73492, 73567, 73492"
  let target = the_target_at_slot_0(frames:)
  assert target.tail.faction_id == 170 && target.tail.base_faction_id == 170
    as "opcode.0x262: both factions are the Creature2 row's, 170"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // The kill's credit comes from the creature after its death is written.
  let #(counted, _) = game_client.read_until_pong(game:, have:, number: 7)
  assert list.filter(list.append(killed, counted), fn(frame) {
      frame.message_id == 0x0361
    })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 5), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the kill counts objective 21290, the sixth of quest 10518, once"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Medic of the marker ring that levels from 3 to 4 on the kill at slot 0: its abilities
/// are the level-1 three and the innate, then SpellLevel 614's base 26038 (Fissure) at bag
/// index 4, written after the level and before the properties, on the whole server and again
/// at the entry of the relog. Fissure is planned (its second spell's hit telegraphs 2996 to 2998
/// are placed by flag 8, the position the cast holds), so the press of slot 4 is accepted: it is
/// confirmed, not refused, and the child's start carries the press pose. The Medic stands 8 m
/// from the ring's other creature and faces it. Which creatures each go strikes is the job of
/// the strike tests and of the whole-server test of Fissure among still Beasts. The clock is
/// driven and nothing waits on real time.
pub fn a_medic_that_levels_from_3_to_4_holds_fissure_castable_and_a_relog_at_4_holds_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  // The saved experience is one short of level 4 (XpPerLevel row 4, minXpForLevel 2860), so
  // the one kill, which gives at least 1, reaches it.
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(game, frames, have, character) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  let other =
    list.find(targets_in(frames:), fn(creature) {
      creature.unit_id != the_target_at_slot_0(frames:).unit_id
    })
  let assert Ok(other) = other as "the ring's second 73492 stands at slot 2"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  let risen =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x01AC, 0x0938, 0x0111, 0x01A0], frame.message_id)
      && !is_other_stat(frame:)
    })
  assert list.map(risen, fn(frame) { frame.message_id })
    == [0x01AC, 0x0938, 0x0111, 0x01A0]
    as "the experience, then the level, then the ability the level grants and its book entry (opcode.0x111.ability_level_up)"
  let assert [_, level, ability, book] = risen
  assert unit_stat_changed.decode(level.body)
    |> result.map(fn(changed) { changed.change })
    == Ok(unit_stat_change.Level(UnitStatLevel(value: 4)))
    as "opcode.0x938: stat 10 is 4, written before the ability the client checks it for (0x1403bb040)"
  let assert Ok(added) = item_added.decode(ability.body)
  assert #(
      added.held_item.item.location,
      added.held_item.item.bag_index,
      added.held_item.item.item_id,
      added.held_item.reason,
    )
    == #(4, 4, 26_038, 49)
    as "opcode.0x111.ability_level_up: SpellLevel 614's base at the slot after the bag of 4, reason 49"
  let assert Ok(tiers) = ability_tiers.decode(book.body)
  assert tiers.tiers
    == list.map([0, 1, 2, 3], fn(action_set_index) {
      AbilityTier(spell4_base_id: 26_038, tier: 1, action_set_index:)
    })
    as "opcode.0x1a0: tier 1 of the base in each of the four action sets"
  // The Medic walks to 8 m from the ring's other creature, which stands alive and untouched,
  // and faces it: it is 8 m ahead of the press pose, inside the first rectangle of Fissure's
  // rows (TelegraphDamage 2998: 10 wide, from 1 to 15 m ahead).
  let creature_at = game_client.placed_by_tail(tail: other.tail)
  let press_at = #(creature_at.0 +. 8.0, creature_at.1, creature_at.2)
  game_client.move_to(
    game:,
    clock: 200,
    x: press_at.0,
    y: press_at.1,
    z: press_at.2,
  )
  let facing_the_creature =
    game_client.yaw_toward(from: #(press_at.0, press_at.2), target: #(
      creature_at.0,
      creature_at.2,
    ))
  game_client.face(game:, yaw: facing_the_creature, clock: 210)
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 8)
  // The last Paralytic Surge lingers 2700 ms (`fight_bot.paralytic_surge_lingers_ms`) and holds
  // the press of any other ability inside the 500 ms queue window (`cast_press.verdict`), so the
  // clock moves past that lingering first.
  driven_time.advance(time:, ms: 3000)
  game_client.press_ability(
    game:,
    client_cast_id: 50,
    bag_index: 4,
    target: other.unit_id,
  )
  // The connection writes the confirm and the child's start before its pong, so a press that is
  // held or refused ends this wait at the assertions below; the first go comes from the cast's
  // timer, which a confirmed press has armed.
  let #(first_go, have) = game_client.read_until_pong(game:, have:, number: 10)
  assert refusals(frames: first_go) == []
    as "opcode.0x7fc: Fissure is planned, so the press is not refused"
  let assert Ok(confirmed_frame) =
    list.find(first_go, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed; none came, so the press was held behind a lingering cast or not made"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed_frame.body)
  let starts =
    list.filter(first_go, fn(frame) { frame.message_id == 0x07FF })
    |> list.map(fn(frame) {
      let assert Ok(started) = spell_started.decode(frame.body)
        as "0x7ff decodes"
      started
    })
  let assert Ok(child_started) =
    list.find(starts, fn(started) { started.spell4_id == 41_844 })
    as "opcode.0x7ff: the child 41844 starts"
  assert #(child_started.root_spell4_id, child_started.parent_spell4_id)
    == #(41_843, 41_843)
    as "Spell4Effects 94215 starts child 41844 of the pressed 41843"
  let held =
    spell_position.SpellPosition(
      x: float32.to_bits(press_at.0),
      y: float32.to_bits(press_at.1),
      z: float32.to_bits(press_at.2),
    )
  assert confirmed.position == held && child_started.position == held
    as "opcode.0x7fd, opcode.0x7ff: the position the cast holds is the Medic's place at the press"
  assert confirmed.yaw == float32.to_bits(facing_the_creature)
    && child_started.yaw == float32.to_bits(facing_the_creature)
    as "opcode.0x7fd, opcode.0x7ff: the yaw the client turns the picture by is the facing the Medic had at the press (the client's own yaw is the caster's facing, a marked guess)"
  // The relog at level 4 holds the same five abilities, the new one in slot 4.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert location_4_items(frames: second_entry)
    == [
      #(0, 38_201),
      #(1, 16_322),
      #(2, 26_543),
      #(3, 46_615),
      #(4, 26_038),
    ]
    as "the entry's location-4 items are the level-1 three, the innate and Fissure's base in slot 4: a relog holds the book a rise made"
  game_client.close(game:)
  login_support.stop(started)
}

/// The targets of each go, in order, of the child 41844 of Fissure whose 0x7ff is among
/// `frames`, read in `in`.
fn fissure_goes(
  frames frames: List(Frame),
  in read: List(Frame),
) -> List(List(Int)) {
  let events = game_client.casts_in(frames:)
  case game_client.starts_of(events:, spell4_id: 41_844) {
    [#(cast_id, _), ..] ->
      list.filter_map(game_client.go_targets_in(frames: read), fn(go) {
        case go.0 == cast_id {
          True -> Ok(go.1)
          False -> Error(Nil)
        }
      })
    [] -> []
  }
}

/// A Beast of 5000 health that never deflects and stands where it is once struck: a client-default
/// Beast has 52 health, which Fissure's first go alone kills, and a struck creature chases its
/// attacker at its run speed, which 0 makes none. The speed is worked out again from the
/// creature's display's run speed (`CombatContext.run_land`) whenever its properties change, as
/// Fissure's debuff changes them, so both are 0.
fn still_beast_at(number number: Int, place place: Place) -> spawn.Spawn {
  let beast = spawn_support.beast_without_deflect_at(number:, place:)
  spawn.Spawn(
    ..beast,
    health: 5000,
    health_source: unit_fields.Recorded,
    combat: Combat(
      ..beast.combat,
      attack: Attack(..beast.combat.attack, run_speed: 0.0),
    ),
    context: spawn.CombatContext(..beast.context, run_land: 0.0),
  )
}

/// A level-4 Medic stands 8 m behind a Beast and presses Fissure at it with three Beasts in
/// view: A 8 m ahead, B 2 m past the hit radius aside of it and C 4 m past it. Fissure's child
/// strikes the 10 wide rectangle of TelegraphDamage 2998 at its first go, the 6 wide one of
/// 2997 at the second and the 2 wide one of 2996 at the third, so the units each go lists are
/// those whose edge is inside the rectangle of that go: A at every go, B at the first two and C
/// at the first alone. No Beast fights the Dominion Medic on sight, none dies and none moves,
/// and nobody moves after the press. The clock is driven and nothing waits on real time.
pub fn a_medic_presses_fissure_among_still_beasts_and_each_go_strikes_only_the_beasts_its_own_rectangle_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let radius = spawn_support.beast_combat().hit_radius
  // The half widths of rows 2998, 2997 and 2996 are 5, 3 and 1. A Beast is struck when its
  // centre is within the half width plus its hit radius of the middle line: B at `radius + 2`
  // is inside the first two (5 + radius, 3 + radius) and outside the third (1 + radius), C at
  // `radius + 4` is inside the first alone, each 1 m from the edge it is judged by.
  let aside_b = radius +. 2.0
  let aside_c = radius +. 4.0
  let started =
    world_with_spawns(
      spawns: [
        still_beast_at(number: 1, place: beast_place(x: 1.5, z: -4.5)),
        still_beast_at(
          number: 2,
          place: beast_place(x: 1.5 +. aside_b, z: -4.5),
        ),
        still_beast_at(
          number: 3,
          place: beast_place(x: 1.5 +. aside_c, z: -4.5),
        ),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 4,
    )
  send_play(game:, character_id: character)
  let #(seen, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= 3
    })
  let beast_at_x = fn(x: Float) {
    let assert Ok(beast) =
      list.find(game_client.creatures_created_in(frames: seen), fn(creature) {
        float.loosely_equals(
          game_client.placed_by_tail(tail: creature.tail).0,
          x,
          0.01,
        )
      })
      as "a Beast stands at this x"
    beast.unit_id
  }
  let beast_ahead = beast_at_x(1.5)
  let beast_near = beast_at_x(1.5 +. aside_b)
  let beast_far = beast_at_x(1.5 +. aside_c)
  // The Medic is stored at (1.5, 2.5, 3.5): A is 8 m ahead of it when it faces -z.
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(1.5, 3.5), target: #(1.5, -4.5)),
    clock: 100,
  )
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 4, target: 0)
  let #(first, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames:, in: frames) != []
    })
  let #(first_flushed, have) =
    game_client.read_until_pong(game:, have:, number: 14)
  let pressed = list.append(first, first_flushed)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Fissure is planned and a level-4 Medic holds it, so the press is not refused"
  let assert Ok(child_started) =
    list.find(
      list.filter(pressed, fn(frame) { frame.message_id == 0x07FF })
        |> list.map(fn(frame) {
          let assert Ok(started) = spell_started.decode(frame.body)
            as "0x7ff decodes"
          started
        }),
      fn(started) { started.spell4_id == 41_844 },
    )
    as "opcode.0x7ff: the child 41844 starts"
  assert #(child_started.root_spell4_id, child_started.parent_spell4_id)
    == #(41_843, 41_843)
    as "Spell4Effects 94215 starts child 41844 of the pressed 41843"
  driven_time.advance(time:, ms: 250)
  let #(second, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames: pressed, in: frames) != []
    })
  let #(second_flushed, have) =
    game_client.read_until_pong(game:, have:, number: 15)
  driven_time.advance(time:, ms: 250)
  let #(third, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames: pressed, in: frames) != []
    })
  let #(third_flushed, _) =
    game_client.read_until_pong(game:, have:, number: 16)
  let struck = fn(read: List(Frame)) {
    case fissure_goes(frames: pressed, in: read) {
      [targets] -> list.sort(targets, int.compare)
      _ -> panic as "the go lists one set of targets"
    }
  }
  assert struck(pressed)
    == list.sort([beast_ahead, beast_near, beast_far], int.compare)
    as "opcode.0x7f4: the first go strikes the 10 wide rectangle (TelegraphDamage 2998, phaseFlags 1), which holds all three Beasts"
  assert struck(list.append(second, second_flushed))
    == list.sort([beast_ahead, beast_near], int.compare)
    as "opcode.0x7f4: the second go strikes the 6 wide rectangle (TelegraphDamage 2997, phaseFlags 2), which holds A and B and not C, which the first go struck"
  assert struck(list.append(third, third_flushed)) == [beast_ahead]
    as "opcode.0x7f4: the third go strikes the 2 wide rectangle (TelegraphDamage 2996, phaseFlags 4), which holds A alone"
  game_client.close(game:)
  login_support.stop(started)
}

/// A level-6 Medic saved at 100 health holds Crisis Wave (Spell4Base 25579, Spell4 41382, bag
/// index 7: the Medic's 5 to 6 rise gives it) and presses it on itself. Its area row 661 is
/// ordered by health (MissingMostHealth), which the server reads as no area: the press is
/// confirmed, its go lists the Medic alone with the heal of row 93037 (type 10, flags 5: the caster and the
/// area) and the Medic's health rises by the amount that heal's description gives. The allies
/// the order would pick are not found. The clock is driven and nothing waits on real time.
pub fn a_hurt_medic_presses_crisis_wave_and_the_cast_starts_goes_and_heals_the_caster_where_the_order_refused_it_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_spawns(spawns: [], tables: character_tables.shared(), time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 6,
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(_) =
    pog.query("update character set health = 100 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the row holds a health below the level's maximum, so a heal is a real change"
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  assert health_in(frames: entry) == 100
    as "opcode.0x262: the Medic enters with the 100 it was saved with"
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 25_579 })
    as "the level-6 Medic holds Crisis Wave's base 25579 (SpellLevel 1194)"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 14)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Crisis Wave is planned, so the press is not refused"
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: pressed, client_cast_id: 1)
    as "opcode.0x7fd: the press is confirmed with the server's cast id"
  // Spell4.41382 castTime 1250: the go waits for the clock. A pressed cast is told its player
  // by the 0x7fd and the go; the 0x7ff is for a child and for the viewers.
  driven_time.advance(time:, ms: 1250)
  let #(went, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      finishes(frames:, cast_id:)
    })
  assert game_client.go_targets_in(frames: went)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [own])]
    as "opcode.0x7f4: the go lists the Medic alone, the allies the order would pick are not found"
  assert game_client.missed_in(frames: went) == []
    as "opcode.0x7fb: nothing is missed"
  let assert [go] =
    list.filter_map(went, fn(frame) {
      case frame.message_id == 0x07F4 {
        True -> spell_go.decode(frame.body) |> result.replace_error(Nil)
        False -> Error(Nil)
      }
    })
    |> list.filter(fn(go) { go.cast_id == cast_id })
    as "the cast has one go"
  let assert [info] = go.targets as "the go has the Medic's target info"
  let assert [
    spell_effect_info.SpellEffectInfo(
      spell4_effects_id: 93_037,
      result: spell_effect_result.Damage(spell_effect_damage.SpellEffectDamage(
        description:,
      )),
      ..,
    ),
  ] = info.effects
    as "the Medic's info holds the heal row 93037 (Spell4Effects 93037: type 10, flags 5)"
  let healed = description.health_damage_with_overkill - description.overkill
  assert healed > 0 as "the heal changes the Medic's health"
  // The 1250 ms the clock ran also fire the Medic's health regeneration (`player_life`), each
  // tick its own 0x92f, before the go; the heal's 0x92f is the first after it, and the read
  // ends at the cast's 0x7fe, which follows it.
  let go_index =
    index_where(frames: went, found: fn(frame) { frame.message_id == 0x07F4 })
  let health_in_frames = fn(frames) {
    game_client.own_health_of(events: game_client.fight_in(frames:), unit: own)
  }
  let before =
    health_in_frames(list.take(went, go_index))
    |> list.last
    |> result.unwrap(100)
  let assert [after, ..] = health_in_frames(list.drop(went, go_index + 1))
    as "the heal's 0x92f follows the go before the cast ends"
  assert after - before == healed
    as "opcode.0x92f: the heal raises the Medic's health by the amount the heal's description gives"
  game_client.close(game:)
  login_support.stop(started)
}

/// The player at the marker ring faces the target at ring slot 0 and presses Paralytic Surge on
/// the driven clock until it dies: the frames up to its death and the bytes beyond them.
fn kills_the_target_at_slot_0(
  game game: game_client.Game,
  have have: BitArray,
  frames frames: List(Frame),
  time time: driven_time.Time,
) -> #(List(Frame), BitArray) {
  let target = the_target_at_slot_0(frames:)
  let slot = ring_slot(index: 0)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(slot.0 +. 12.0, slot.2), target: #(
      slot.0,
      slot.2,
    )),
    clock: 100,
  )
  let assert Ok(killed) =
    fight_bot.presses_until_the_target_dies(
      ability: fight_bot.paralytic_surge,
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: target.unit_id,
      cast_id: 1,
      seen: [],
    )
  killed
}

/// A Medic of level 9 whose saved experience is one short of level 10 (XpPerLevel row 10,
/// minXpForLevel 23860) kills the target at ring slot 0: the 0x0169 of its entry holds 0 and 0
/// before 0x025E, the rise to 10 sends 1 and 1 after the level (`XpPerLevel.abilityPointsPerLevel`
/// is 1 from ID 10; `opcode.0x169`), and the relog at 10 sends 1 and 1 again in the same place.
/// The clock is driven and nothing waits on real time.
pub fn a_medic_that_levels_from_9_to_10_receives_one_point_and_a_relog_at_10_sends_it_again_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started =
    world_with_kill_experience_below_the_fourth_level_gap(tables:, time:)
  let assert Ok(level_ten) = xp_per_level.get(tables:, id: XpPerLevelId(10))
    as "XpPerLevel has a row 10"
  let #(game, frames, have, character) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 9,
      saved_experience: Some(level_ten.min_xp_for_level - 1),
    )
  assert ability_points_support.points_in(frames:) == [#(0, 0)]
    as "XpPerLevel.abilityPointsPerLevel: IDs 1 to 9 give none, so the entry's 0x0169 holds 0 and 0"
  assert entry_places_the_points_between_the_reward_properties_and_the_state(
    frames:,
  )
    as "lua.Abilities.UpdateInterfaceMenuAlerts: before 0x025E, after 0x092C"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x0169
      })
    })
  let from_the_kill = list.append(killed, rest)
  assert ability_points_support.points_in(frames: from_the_kill) == [#(1, 1)]
    as "the rise to 10 sends a 0x0169 of 1 and 1"
  let rise =
    list.filter(from_the_kill, fn(frame) {
      list.contains([0x01AC, 0x0938, 0x0169], frame.message_id)
      && !is_other_stat(frame:)
    })
  assert list.map(rise, fn(frame) { frame.message_id })
    == [0x01AC, 0x0938, 0x0169]
    as "the experience, the level, then the points: the client re-reads the points when it raises PlayerLevelChange, after the level's stat"
  let assert [_, level, _] = rise
  assert unit_stat_changed.decode(level.body)
    |> result.map(fn(changed) { changed.change })
    == Ok(unit_stat_change.Level(UnitStatLevel(value: 10)))
    as "opcode.0x938: stat 10 is 10"
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert ability_points_support.points_in(frames: second_entry) == [#(1, 1)]
    as "the relog at 10 sends one 0x0169 of 1 and 1"
  assert entry_places_the_points_between_the_reward_properties_and_the_state(
    frames: second_entry,
  )
    as "the relog's entry sends it in the same place"
  game_client.close(game:)
  login_support.stop(started)
}

/// The marker world whose kills give experience to a player four or more levels above the
/// creature. The ring's creatures are level 2 and the level 9 Medic's gap clamps to -4, whose
/// multiplier (`kill_experience_multiplier_below_4`, a `game_number` server choice: the client
/// has no kill formula) is 0 in the content; only that one is set to 1, so the test changes
/// the server's content and no client rule.
fn world_with_kill_experience_below_the_fourth_level_gap(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_numbers(
    folder: content_support.fixture_folder,
    tables:,
    time:,
    tutorial: False,
    numbers: fn(numbers) {
      GameNumbers(..numbers, kill_experience_multipliers: [
        1.0,
        ..list.drop(numbers.kill_experience_multipliers, up_to: 1)
      ])
    },
  )
}

/// Whether 0x0169 follows 0x092C and comes before 0x025E in the frames.
fn entry_places_the_points_between_the_reward_properties_and_the_state(
  frames frames: List(Frame),
) -> Bool {
  list.window(cast_support.ids(frames:), 3)
  |> list.contains([0x092C, 0x0169, 0x025E])
}

/// The Spellslinger of the marker ring that levels from 3 to 4 on the kill at slot 0 with
/// its slot 0 ability (SpellLevel 1011's Spell4 43468, base 27638, castTime 1000), then casts
/// SpellLevel 1012's base 20718 (Spell4 34756: castTime 1000, no cost, a living target; the
/// plan holds it) at the ring's other creature, and again after a relog at level 4: the
/// press of slot 4 is confirmed (0x07FD) and not refused (`opcode.0x7fd`, `opcode.0x7fc`).
/// The clock is driven and nothing waits on real time.
pub fn a_spellslinger_that_levels_from_3_to_4_casts_its_new_ability_and_a_relog_at_4_casts_it_too_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let tables = fixture_tables.shared()
  let started = world_with_the_markers_creatures(tables:, time:)
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(game, frames, have, character) =
    a_player_of_a_level_at_the_marker_ring(
      started:,
      class_id: 7,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  assert location_4_items(frames:)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 31_213)]
    as "SpellLevel 1011, 1036 and 1236 (level 1, in id order) then Class 7's innate Spell4 47273 (base 31213)"
  let target = the_target_at_slot_0(frames:)
  let assert Ok(other) =
    list.find(targets_in(frames:), fn(creature) {
      creature.unit_id != target.unit_id
    })
    as "the ring's second 73492 stands at slot 2"
  let slot = ring_slot(index: 0)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(slot.0 +. 12.0, slot.2), target: #(
      slot.0,
      slot.2,
    )),
    clock: 100,
  )
  let assert Ok(#(killed, have)) =
    fight_bot.presses_until_the_target_dies(
      // `lingers_ms` holds the 1000 ms global cooldown, not an effect duration: the
      // press that leaves the creature alive waits that long before the next press.
      ability: fight_bot.Ability(
        bag_index: 0,
        cast_ms: spellslinger_cast_ms,
        lingers_ms: spellslinger_cast_ms,
      ),
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: target.unit_id,
      cast_id: 1,
      seen: [],
    )
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  let risen =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x0111, 0x01A0], frame.message_id)
    })
  let assert [ability, book] = list.drop(risen, list.length(risen) - 2)
  let assert Ok(added) = item_added.decode(ability.body)
  assert #(
      added.held_item.item.location,
      added.held_item.item.bag_index,
      added.held_item.item.item_id,
      added.held_item.reason,
    )
    == #(4, 4, 20_718, 49)
    as "opcode.0x111.ability_level_up: SpellLevel 1012's base at the slot after the bag of 4, reason 49"
  let assert Ok(tiers) = ability_tiers.decode(book.body)
  assert tiers.tiers
    == list.flat_map([20_718, 54_909], fn(base) {
      list.map([0, 1, 2, 3], fn(action_set_index) {
        AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
      })
    })
    as "opcode.0x1a0: tier 1 of the base and of its alternate (Spell4Base 54909) in each of the four action sets"
  // The press of slot 4 at the ring's other creature, which stands alive and untouched,
  // once the global cooldown of the last press of the fight has run.
  driven_time.advance(time:, ms: spellslinger_cast_ms)
  game_client.press_ability(
    game:,
    client_cast_id: 50,
    bag_index: 4,
    target: other.unit_id,
  )
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 8)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: the press of the new ability is not refused"
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: pressed,
    client_cast_id: 50,
  ))
    as "opcode.0x7fd: the press of the new ability is confirmed"
  // The relog at level 4 holds the new ability in slot 4 and casts it.
  let #(second_entry, have) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert location_4_items(frames: second_entry)
    == [
      #(0, 27_638),
      #(1, 20_684),
      #(2, 20_325),
      #(3, 31_213),
      #(4, 20_718),
    ]
    as "a relog holds the book a rise made, in its order"
  // The ring's other creature is shown to the player again, alive, before the press. The map
  // tells the connection of it and the connection itself writes the 0x01BC the entry read ends
  // on: two senders, so the creature may already be in the entry's frames, and the wait looks
  // in them too.
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(shown) {
      list.any(
        targets_in(frames: list.append(second_entry, shown)),
        fn(creature) { creature.unit_id == other.unit_id },
      )
    })
  game_client.press_ability(
    game:,
    client_cast_id: 60,
    bag_index: 4,
    target: other.unit_id,
  )
  let #(pressed, _) = game_client.read_until_pong(game:, have:, number: 9)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: the press after the relog is not refused"
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: pressed,
    client_cast_id: 60,
  ))
    as "opcode.0x7fd: the press after the relog is confirmed"
  game_client.close(game:)
  login_support.stop(started)
}

/// The cast time of the Spellslinger's slot 0 ability (Spell4 43468) and of the level 4
/// one (Spell4 34756): 1000 ms each, with a global cooldown of 1000 ms.
const spellslinger_cast_ms = 1000

/// The location-4 items of the entry frames as (bag index, base).
fn location_4_items(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(item_bot.answer_in(frames:).added, fn(held) {
    case held.item.location {
      4 -> Ok(#(held.item.bag_index, held.item.item_id))
      _ -> Error(Nil)
    }
  })
}

/// Whether the frame is a 0x938 of a stat other than the level.
fn is_other_stat(frame frame: Frame) -> Bool {
  use <- bool.guard(when: frame.message_id != 0x0938, return: False)
  let assert Ok(changed) = unit_stat_changed.decode(frame.body)
    as "the server's 0x938 decodes"
  case changed.change {
    unit_stat_change.Level(..) -> False
    unit_stat_change.Shield(..)
    | unit_stat_change.InterruptArmor(..)
    | unit_stat_change.Absorption(..) -> True
  }
}

/// Whether the frames hold the 0x35c that completes quest 10518 (state 3, objective 0).
fn quest_10518_completed_in(frames frames: List(Frame)) -> Bool {
  list.any(frames, fn(frame) {
    frame.message_id == 0x035C
    && quest_state.decode(frame.body)
    == Ok(QuestState(quest_id: 10_518, state: 3, objective_id: 0))
  })
}

pub fn the_last_kill_of_quest_10518_is_followed_by_0x35c_state_2_its_rewards_and_0x35c_state_3_test() -> Nil {
  use <- owned_test.run(120_000)
  // Quest 10518 has no creature that receives it (`table_rows -- Creature2
  // questIdReceive00=10518` names none), so the client shows it Achieved itself and only
  // the server's 0x35c state 3 completes it (Quest2.10513.completion). The sixth objective
  // has 2 of its 3 kills done, so the kill of the target at ring slot 0 is the last.
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 2)
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // No wait on time: the read goes on until the frame that completes the quest arrives.
  let #(rest, _) =
    game_client.read_until(game:, have:, found: fn(rest) {
      quest_10518_completed_in(frames: list.append(killed, rest))
    })
  let quest_frames =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x0361, 0x035C, 0x01AC], frame.message_id)
    })
  assert list.map(quest_frames, fn(frame) { frame.message_id })
    == [0x01AC, 0x0361, 0x035C, 0x01AC, 0x035C]
    as "the kill's experience, then the progress and the state 2 the kill makes, then the completion's experience and its state 3"
  let assert [kill_experience, progress, achieved, reward, completed] =
    quest_frames
  assert experience_gained.decode(kill_experience.body)
    |> result.map(fn(gained) { gained.source_kind })
    == Ok(2)
    as "opcode.0x1ac: the first experience is the kill's, kind 2"
  assert progress.body
    == message_support.packed([#(15, 10_518), #(32, 5), #(32, 3)])
    as "opcode.0x361: objective 5 of quest 10518 is at 3 of 3"
  assert quest_state.decode(achieved.body)
    == Ok(QuestState(quest_id: 10_518, state: 2, objective_id: 0))
    as "opcode.0x35c: the quest is Achieved"
  assert experience_gained.decode(reward.body)
    |> result.map(fn(gained) { #(gained.experience, gained.source_kind) })
    == Ok(#(655, 3))
    as "opcode.0x1ac: the quest's experience override 655, kind 3 (a quest), from the completion"
  assert quest_state.decode(completed.body)
    == Ok(QuestState(quest_id: 10_518, state: 3, objective_id: 0))
    as "opcode.0x35c: the server completes the quest, state 3 with objective 0, last"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_placed_target_respawns_at_its_slot_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 0)
  let target = the_target_at_slot_0(frames:)
  let #(_, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // The respawn time is the row every creature without one of its own takes
  // (death.creature_respawn): the creature kind row 0 of the content.
  let assert Ok(kind) =
    pog.query("select respawn_ms from creature_kind where creature_id = 0")
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pog.named_connection(started.settings.pool.pool_name))
    as "the default creature kind is read"
  let assert [respawn_ms] = kind.rows
  // The creature sends its news before it starts the corpse's timer, which the
  // advance's barrier waits for.
  driven_time.advance(time:, ms: respawn_ms)
  let #(after, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), target.unit_id)
      && list.any(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id == target.unit_id
      })
    })
  let assert Ok(again) =
    list.find(game_client.creatures_created_in(frames: after), fn(unit) {
      unit.unit_id == target.unit_id
    })
  assert game_client.placed_by_tail(tail: again.tail)
    == game_client.placed_by_tail(tail: target.tail)
    && again.creature_id == 73_492
    as "death.creature_respawn: 0x355, then a new 0x262 with the same unit id at the same place, ring slot 0"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Creature2 ids of the static objects the frames create, sorted: the 0x262 of a
/// type 8, 10, 11, 13 or 32 object (`unit_create_static`), as the client reads them.
fn static_objects_in(frames frames: List(Frame)) -> List(Int) {
  list.map(static_objects_created_in(frames:), fn(object) { object.creature_id })
  |> list.sort(int.compare)
}

/// The static objects the 0x262 among the frames create, as the client reads them, in
/// the order sent.
fn static_objects_created_in(
  frames frames: List(Frame),
) -> List(unit_create_static.UnitCreateStatic) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0262 ->
        case game_client.created_unit(body: frame.body) {
          Ok(game_client.ObjectCreated(..)) ->
            unit_create_static.decode(frame.body) |> result.replace_error(Nil)
          Ok(game_client.PlayerCreated(..))
          | Ok(game_client.CreatureCreated(..))
          | Error(Nil) -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

/// The static objects of the Creature2 that stand at the place, within 0.01 on each
/// axis.
fn objects_standing_at(
  objects objects: List(unit_create_static.UnitCreateStatic),
  creature_id creature_id: Int,
  place place: #(Float, Float, Float),
) -> List(unit_create_static.UnitCreateStatic) {
  list.filter(objects, fn(object) {
    let #(x, y, z) = game_client.placed_by_tail(tail: object.tail)
    object.creature_id == creature_id
    && float.absolute_value(x -. place.0) <. 0.01
    && float.absolute_value(y -. place.1) <. 0.01
    && float.absolute_value(z -. place.2) <. 0.01
  })
}

/// The static object of the Creature2 that stands nearest the position (x, z) of
/// the world, or Error(Nil) when none of it is among the objects.
fn nearest_object_of(
  objects objects: List(unit_create_static.UnitCreateStatic),
  creature_id creature_id: Int,
  to to: #(Float, Float),
) -> Result(unit_create_static.UnitCreateStatic, Nil) {
  let apart = fn(object: unit_create_static.UnitCreateStatic) {
    let #(x, _, z) = game_client.placed_by_tail(tail: object.tail)
    let far = x -. to.0
    let deep = z -. to.1
    far *. far +. deep *. deep
  }
  objects
  |> list.filter(fn(object) { object.creature_id == creature_id })
  |> list.sort(fn(a, b) { float.compare(apart(a), apart(b)) })
  |> list.first
}

/// A new character of the faction at the position in World 3460, entered as the
/// player of the account number `number`, and every message the server wrote up to
/// the pong of a ping sent after the 0x262 of each of `anchors`, units that no
/// prerequisite hides from the character. The map writes its objects in one tell,
/// after its reply to the join and from another process than the connection's
/// pong, so the pong alone does not follow them; a creature of the map writes its
/// own 0x262 from its own process, so it too is named among the anchors to be
/// followed. The anchors' 0x262 show the tell has been taken, and the connection
/// writes all of it before it takes the ping.
fn entering_3460_as(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  faction_id faction_id: Int,
  at position: #(Float, Float, Float),
  anchors anchors: List(Int),
) -> List(Frame) {
  let #(game, character_id) = new_player(started:, number:, character_name:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(_) =
    pog.query("update character set faction_id = $2 where character_id = $1")
    |> pog.parameter(pog.int(character_id))
    |> pog.parameter(pog.int(faction_id))
    |> pog.execute(pool)
    as "the character took its faction"
  character_support.move_to(
    pool:,
    character_id:,
    world_id: 3460,
    world_zone_id: 6009,
    position:,
  )
  send_play(game:, character_id:)
  let #(burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  let #(until_anchor, have) =
    read_until_objects(game:, have:, creature_ids: anchors, read: burst)
  let #(after, _) = game_client.read_until_pong(game:, have:, number: 1)
  game_client.close(game:)
  list.append(until_anchor, after)
}

/// Reads messages until the 0x262 of a static object with each of these Creature2 ids
/// has been read (an id listed twice, twice), which `read` may already hold.
fn read_until_objects(
  game game: game_client.Game,
  have have: BitArray,
  creature_ids creature_ids: List(Int),
  read read: List(Frame),
) -> #(List(Frame), BitArray) {
  use <- bool.guard(
    when: includes_each(
      read: static_objects_in(frames: read),
      wanted: creature_ids,
    ),
    return: #(read, have),
  )
  let #(frame, rest) = game_client.next(game:, have:)
  read_until_objects(
    game:,
    have: rest,
    creature_ids:,
    read: list.append(read, [frame]),
  )
}

/// Whether `read` holds each of `wanted`, an id listed twice twice.
fn includes_each(read read: List(Int), wanted wanted: List(Int)) -> Bool {
  list.all(wanted, fn(id) {
    list.count(read, fn(seen) { seen == id })
    >= list.count(wanted, fn(listed) { listed == id })
  })
}

/// The tutorial's two Sim-Turrets, each twice: objectives 21288 and 21316 count 2 of
/// Creature2 73494 and 74862, which the world data of this test holds no row of, so the
/// load places both at their markers (WorldLocation2 51671, 52753, 52902 and 52903, all
/// within the sight range of 1024 units of the Start Arrow's row 29054 and past it from
/// the mounts). They start as creatures of unit type 13, and the 0x262 of each is
/// written to a character in sight of them, whatever its faction.
const sim_turrets = [73_494, 73_494, 74_862, 74_862]

/// The tutorial's three mines, each twice: Creature2 73463, 73667 and 73668 each link to
/// an Exile objective (21287, 21340, 21318: markers 51662, 51663, 51664) and a Dominion
/// objective (21313, 21314, 21315: markers 52899, 52900, 52901), and the world data of
/// this test holds no row of them, so the load places each at both of its markers (a
/// click target with no spawn stands at its objective's marker). Every marker is within
/// the sight range of 1024 units of the Start Arrow's row 29054 (the farthest, 51664 at
/// x -119.41, z 424.96, is 924 units off it), and a mine's visibility prerequisite hides
/// none of them from an Exile with no tutorial quest.
const tutorial_mines = [73_463, 73_463, 73_667, 73_667, 73_668, 73_668]

/// The ids with the Sim-Turrets and the mines, sorted as `static_objects_in` sorts them.
fn with_the_sim_turrets_and_mines(ids ids: List(Int)) -> List(Int) {
  list.flatten([ids, sim_turrets, tutorial_mines]) |> list.sort(int.compare)
}

pub fn entering_world_3460_writes_no_start_arrow_and_mount_displays_only_to_an_exile_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started =
    start_with_world_data(folder: "test/fixture/world_data_tutorial", time:)
  let at_the_arrows = #(71.4148, -855.3006, -479.419)
  let at_the_mounts = #(1381.03, -495.32764, 213.793)
  let at_the_arrows_ids = with_the_sim_turrets_and_mines(ids: [73_619])
  let exile =
    static_objects_in(frames: entering_3460_as(
      started:,
      number: 1,
      character_name: "Zed Qu",
      faction_id: 167,
      at: at_the_arrows,
      anchors: at_the_arrows_ids,
    ))
  assert exile == at_the_arrows_ids
    as "an Exile with no tutorial quest at the Start Arrow's row 29054: the hologram 73619 (Creature2 prerequisite 41795, which passes for a player under no cast) is written and the Start Arrow 73707 (prerequisite 41803: neither quest 10527 nor 10532 is open) is not"
  let exile_at_the_mounts =
    static_objects_in(
      frames: entering_3460_as(
        started:,
        number: 2,
        character_name: "Ann Qu",
        faction_id: 167,
        at: at_the_mounts,
        anchors: [74_787],
      ),
    )
  assert exile_at_the_mounts == [74_781, 74_782, 74_783, 74_784, 74_787]
    as "an Exile at the mounts: the four EXILE mount displays are written (Creature2 prerequisite 19, base faction 167), and 74787, which has none"
  let dominion_at_the_mounts =
    static_objects_in(
      frames: entering_3460_as(
        started:,
        number: 3,
        character_name: "Cal Qu",
        faction_id: 166,
        at: at_the_mounts,
        anchors: [74_787],
      ),
    )
  assert dominion_at_the_mounts == [74_787]
    as "a Dominion character at the same place is written 74787, which has no visibility prerequisite, and none of the mount displays (Faction2 166 fails prerequisite 19)"
  login_support.stop(started)
}

/// Where a Beast stands in World 1387, zone 1100, at `x` and `z`: the world and
/// zone a new test character stands in, at 1.5, 2.5, 3.5, facing -z.
fn beast_place(x x: Float, z z: Float) -> Place {
  place_support.at(world_id: 1387, world_zone_id: 1100, x:, y: 2.5, z:)
}

/// A world with a Virtual Battle Beast at each of these places, none of which
/// deflects, and which respawn after 1000 ms (the least a creature kind may hold, the
/// strike deadline), on the tables given. The game connections and the World take
/// their time and timers from `time`: a Beast's swing, strike deadline,
/// respawn and leash fire only when the test advances it.
fn world_with_beasts(
  places places: List(Place),
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_spawns(
    spawns: list.index_map(places, fn(place, index) {
      spawn_support.beast_without_deflect_at(number: index + 1, place:)
    }),
    tables:,
    time:,
  )
}

/// A world 1387 with these spawns, which respawn after 1000 ms, on the tables given, its
/// game connections and World taking their time and timers from `time`.
fn world_with_spawns(
  spawns spawns: List(spawn.Spawn),
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      game: server.Served(
        ..settings.game,
        settings: connection_state.Settings(..settings.game.settings, tables:),
      ),
      world: server.World(
        ..settings.world,
        spawns: spawn_support.key_in(world_id: 1387, spawns:, respawn_ms: 1000),
      ),
    )
  })
}

/// Runs the body on the client's rows with Paralytic Surge's recharge taken
/// off: the fight presses it four times in a row, and Spell4 42352's spellCoolDown of
/// 25000 ms would refuse each press after the first unless the clock moved on by
/// that much between presses, which would move every timer the Beast holds with it.
fn on_rows_without_paralytic_surges_recharge(
  body body: fn(table_store.Tables) -> a,
) -> a {
  fixture_tables.changed(
    table: "Spell4",
    id: 42_352,
    with: [#("spellCoolDown", planted_table.Integer(0))],
    body:,
  )
}

/// A world with one Beast 3 m ahead of the place a new test character stands at.
fn world_with_a_beast_ahead(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_beasts(places: [beast_place(x: 1.5, z: 0.5)], tables:, time:)
}

/// Plays a new player's character into the world and reads until the Beast's 0x262
/// arrives: the burst and the creature, and the bytes beyond them.
fn enters_and_sees_the_beast(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, List(Frame), BitArray) {
  enters_and_sees_the_beasts(
    started:,
    number:,
    character_name:,
    class_id: 4,
    beasts: 1,
  )
}

/// Plays a new player of the class, at level 1, into the world and reads until the
/// 0x262 of each of the Beasts has arrived.
fn enters_and_sees_the_beasts(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
  beasts beasts: Int,
) -> #(game_client.Game, List(Frame), BitArray) {
  let #(game, character) =
    new_player_at_level(started:, number:, character_name:, class_id:, level: 1)
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= beasts
    })
  #(game, frames, have)
}

pub fn a_medic_kills_a_planted_beast_with_paralytic_surge_and_a_watcher_reads_the_same_fight_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_a_beast_ahead(tables:, time:)
  let #(first, first_frames, first_have) =
    enters_and_sees_the_beast(started:, number: 1, character_name: "Zed Qu")
  let #(second, second_frames, second_have) =
    enters_and_sees_the_beast(started:, number: 2, character_name: "Ann Qu")
  let assert [beast, ..] =
    game_client.creatures_created_in(frames: first_frames)
  let beast_unit = beast.unit_id
  assert list.map(
      game_client.creatures_created_in(frames: second_frames),
      fn(unit) { unit.unit_id },
    )
    == [beast_unit]
    as "both players are shown the same creature"
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(
      frames: first_frames,
    ))
  let toward =
    game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    ))
  // The caster turns its back on the Beast: the press strikes nothing.
  game_client.face(game: first, yaw: toward +. 3.1415927, clock: 100)
  let #(away, first_have) =
    press_and_fire(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      cast_id: 1,
    )
  assert holds_a_finish(frames: away)
    as "the press's cast finished once the clock has fired its timer"
  assert list.map(game_client.go_targets_in(frames: away), fn(go) { go.1 })
    == [[]]
    && game_client.health_in(frames: away) == []
    as "a press with its back to the Beast strikes nobody: the go names no target and no 0x937 follows (the facing is the last kind 14 yaw)"
  // Facing the Beast, it presses until the Beast dies.
  game_client.face(game: first, yaw: toward, clock: 200)
  let #(first_have, healths) =
    press_until_dead(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      lingers_ms: fight_bot.paralytic_surge_lingers_ms,
      beast: beast_unit,
      cast_id: 2,
    )
  assert healths == [38, 24, 10, 0]
    as "a Medic of level 1 with the Novice gear (Assault Rating 203.0625, Support Rating 55.6875: Assault Power 50.77, Support Power 13.92): a hit of Paralytic Surge is 0.0935 x 50.77 + 0.0935 x 13.92 = 6.05, rounded to 6, plus 8.14 for the level, 14.14, rounded to 14 (Spell4Effects 96125, 0x140565600); the Beast has 52 health, never deflects and the player has no critical hit rating, so the health is 38, 24, 10 and 0, each 0x937 held until its go"
  let #(watched, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(game_client.deaths_in(frames:), fn(death) {
        death == #(beast_unit, True)
      })
      && list.contains(
        game_client.go_targets_in(frames:),
        #(last_cast_of(frames), [beast_unit]),
      )
    })
  let seen_health =
    list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == beast_unit {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
  assert seen_health == healths
    as "the watcher reads the same 0x937 the caster did, then 0x88c"
  assert list.contains(
    game_client.go_targets_in(frames: watched),
    #(last_cast_of(watched), [beast_unit]),
  )
    as "the watcher reads the same 0x7f4, naming the Beast, for the cast it was sent the start of (opcode.0x7ff, opcode.0x7f4)"
  let assert Ok(last) = list.last(game_client.health_in(frames: watched))
  assert last == #(beast_unit, 0, True)
    as "opcode.0x937: health 0 with the dead bit, from the creature itself"
  // The creature stands again after its respawn time, 1000 ms from the kill, which
  // the clock moves on by: 0x355, then a full 0x262. The creature sends its news
  // before it starts the corpse's timer, which the advance's barrier waits for.
  driven_time.advance(time:, ms: 1000)
  let #(after_first, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  let #(after_second, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  list.each([after_first, after_second], fn(frames) {
    assert list.contains(game_client.removals_in(frames:), beast_unit)
      && list.map(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id
      })
      == [beast_unit]
      as "death.creature_respawn: 0x355, then a 0x262 with the same unit id, to each viewer"
  })
  // The picture of the respawned Beast is alive again: a press strikes it.
  let #(_, after_respawn) =
    press_until_a_hit(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      beast: beast_unit,
      cast_id: 100,
    )
  assert after_respawn == 38
    as "the respawned Beast has its 52 health again and was struck for 14, so the caster's picture holds it alive again: the 0x355 cleared it and the respawn's 0x262 restored it"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn three_ticks_reach_the_client_and_health_falls_three_times_test() -> Nil {
  use <- owned_test.run(120_000)
  // No level-1 ability holds a periodic damage row (the client's level-1 tree spells),
  // so Paralytic Surge's damage row 96125 (targetFlags 4, the Medic's bag index 2) is
  // given a tickTime of 2000 and a durationTime of 6000: three ticks, 2000, 4000 and
  // 6000 ms after the go (`Spell4Effects.effectType.8.periodic`).
  use tables <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 96_125,
    with: [
      #("tickTime", planted_table.Integer(2000)),
      #("durationTime", planted_table.Integer(6000)),
    ],
  )
  let time = driven_time.new()
  let started = world_with_a_beast_ahead(tables:, time:)
  let #(game, frames, have) =
    enters_and_sees_the_beast(started:, number: 1, character_name: "Zed Qu")
  let assert Ok(connection) =
    registry.find_named(started.settings.registry, "zed qu")
  let assert [beast] = game_client.creatures_created_in(frames:)
  let beast_unit = beast.unit_id
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(frames:))
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    )),
    clock: 100,
  )
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 2, target: 0)
  let #(taken, have) = game_client.read_until_pong(game:, have:, number: 1)
  driven_time.advance(time:, ms: fight_bot.paralytic_surge_cast_ms)
  // The go strikes the Beast as the press is taken, with no timer on the way: the
  // advance's barrier waits for the Beast's answer, the 0x7f4 it lets out and the
  // Beast's 0x937, written before the pong.
  let #(went, have) = game_client.read_until_pong(game:, have:, number: 2)
  let at_go = list.append(taken, went)
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: at_go, client_cast_id: 1)
    as "opcode.0x7fd: the press is answered with its server cast id"
  assert list.contains(
      game_client.casts_in(frames: at_go),
      game_client.CastWent(cast_id:, phase: 0),
    )
    && !finishes(frames: at_go, cast_id:)
    as "opcode.0x7f4: the press goes off at once (Spell4.42352: no cast time), and its cast does not end with the go"
  assert game_client.ticks_in(frames: at_go) == []
    && list.all(beast_health_in(frames: at_go, beast: beast_unit), fn(health) {
      health == 52
    })
    as "the go strikes no description of the ticking row (the issue's first acceptance check): no 0x7f8, and the Beast keeps its 52 health"
  // The clock fires each tick's timer; the Beast answers the tick's strike on its own
  // process, and the barrier holds the advance until each frame it caused is written.
  let #(rounds, have) =
    list.fold([3, 4, 5], #([], have), fn(so_far, number) {
      let #(rounds, have) = so_far
      driven_time.advance(time:, ms: 2000)
      let #(round, have) = game_client.read_until_pong(game:, have:, number:)
      #(list.append(rounds, [round]), have)
    })
  list.each(rounds, fn(round) {
    assert game_client.ticks_in(frames: round)
      == [#(cast_id, 96_125, beast_unit, [14])]
      as "opcode.0x7f8: one tick each 2000 ms, naming the go's cast, the row 96125 and the Beast, with one damage description; a hit of Paralytic Surge by a Medic of level 1 with the Novice gear is 14 (Spell4Effects 96125, 0x140565600), worked out from the caster at the tick, and the Beast never deflects"
  })
  assert list.map(rounds, beast_health_in(frames: _, beast: beast_unit))
    == [[38], [24], [10]]
    as "opcode.0x937 after each 0x7f8, from the creature itself: the Beast's 52 health falls by its tick's 14, three times"
  let assert [first_round, second_round, last_round] = rounds
  assert !finishes(frames: first_round, cast_id:)
    && !finishes(frames: second_round, cast_id:)
    as "the cast is held past Paralytic Surge's own end, 2700 ms after the go, while its row still ticks"
  let tick_at =
    index_where(frames: last_round, found: fn(frame) {
      game_client.ticks_in(frames: [frame]) != []
    })
  let finish_at =
    index_where(frames: last_round, found: fn(frame) {
      finishes(frames: [frame], cast_id:)
    })
  assert tick_at >= 0 && finish_at > tick_at
    as "opcode.0x7fe: the cast ends after its last tick's 0x7f8 (cast.miss_after_finish)"
  assert list.filter(
      driven_time.pending_of(time:, owner: connection),
      cast_state.owns,
    )
    == []
    as "no tick timer and no timer of a cast is left on the connection once the cast has ended"
  driven_time.advance(time:, ms: 2000)
  let #(after, _) = game_client.read_until_pong(game:, have:, number: 6)
  assert game_client.ticks_in(frames: after) == []
    && beast_health_in(frames: after, beast: beast_unit) == []
    as "the ticks stop with the row's three: no 0x7f8 and no fall of the Beast's health 2000 ms later"
  game_client.close(game:)
  login_support.stop(started)
}

/// The health of each 0x937 among the frames for the unit, in order.
fn beast_health_in(frames frames: List(Frame), beast beast: Int) -> List(Int) {
  list.filter_map(game_client.health_in(frames:), fn(health) {
    case health.0 == beast {
      True -> Ok(health.1)
      False -> Error(Nil)
    }
  })
}

/// Whether the frames hold the 0x7fe of the cast.
fn finishes(frames frames: List(Frame), cast_id cast_id: Int) -> Bool {
  list.contains(
    game_client.casts_in(frames:),
    game_client.CastFinished(cast_id:),
  )
}

/// The place among the frames of the first one `found` holds for, or -1.
fn index_where(
  frames frames: List(Frame),
  found found: fn(Frame) -> Bool,
) -> Int {
  list.index_map(frames, fn(frame, index) { #(frame, index) })
  |> list.find(fn(entry) { found(entry.0) })
  |> result.map(fn(entry) { entry.1 })
  |> result.unwrap(-1)
}

/// Whether the frames hold the finish of a cast (0x7fe).
fn holds_a_finish(frames frames: List(Frame)) -> Bool {
  list.any(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastFinished(..) -> True
      game_client.CastRefused(..)
      | game_client.CastConfirmed(..)
      | game_client.CastStarted(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..)
      | game_client.CastWent(..) -> False
    }
  })
}

/// How many times the frames start Telekinetic Strike's Psi Point child, 30900, under
/// the spell (0x7ff).
fn psi_children(frames frames: List(Frame)) -> Int {
  list.count(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastStarted(spell4_id: 30_900, parent_spell4_id: 32_893, ..) ->
        True
      game_client.CastStarted(..)
      | game_client.CastRefused(..)
      | game_client.CastConfirmed(..)
      | game_client.CastWent(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..)
      | game_client.CastFinished(..) -> False
    }
  })
}

/// The cast time of Telekinetic Strike (Spell4 32893, castTime 1250): its go is that long
/// after the press.
const telekinetic_strike_cast_ms = 1250

/// How long after its go a hit of Telekinetic Strike lasts: none, the cast ends with
/// its go (its effects 62159 and 62204 have no durationTime).
const telekinetic_strike_lingers_ms = 0

pub fn an_espers_telekinetic_strike_hits_only_the_beast_inside_its_never_drawn_telegraph_and_a_watcher_reads_the_same_fight_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [beast_place(x: 1.5, z: 0.5), beast_place(x: 11.5, z: 3.5)],
      tables: character_tables.shared(),
      time:,
    )
  let #(first, first_frames, first_have) =
    enters_and_sees_the_beasts(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 3,
      beasts: 2,
    )
  let #(second, second_frames, second_have) =
    enters_and_sees_the_beasts(
      started:,
      number: 2,
      character_name: "Ann Qu",
      class_id: 4,
      beasts: 2,
    )
  let beast_at_x = fn(frames, x) {
    let assert [beast] =
      list.filter(game_client.creatures_created_in(frames:), fn(unit) {
        game_client.placed_by_tail(tail: unit.tail).0 == x
      })
      as "one Beast stands at this x"
    beast.unit_id
  }
  let ahead = beast_at_x(first_frames, 1.5)
  let beside = beast_at_x(first_frames, 11.5)
  assert beast_at_x(second_frames, 1.5) == ahead
    && beast_at_x(second_frames, 11.5) == beside
    as "both players are shown the same two creatures"
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(
      frames: first_frames,
    ))
  let toward =
    game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    ))
  // The caster turns its back on the Beasts: the press strikes nothing.
  game_client.face(game: first, yaw: toward +. 3.1415927, clock: 100)
  let #(away, first_have) =
    press_and_fire(
      time:,
      game: first,
      have: first_have,
      bag_index: 0,
      cast_ms: telekinetic_strike_cast_ms,
      cast_id: 1,
    )
  assert holds_a_finish(frames: away)
    as "the press's cast finished once the clock has moved on by its cast time"
  assert list.map(game_client.go_targets_in(frames: away), fn(go) { go.1 })
    == [[]]
    && game_client.health_in(frames: away) == []
    && list.all(game_client.casts_in(frames: away), fn(event) {
      case event {
        game_client.CastStarted(spell4_id:, ..) -> spell4_id == 32_893
        game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> True
      }
    })
    as "a press with its back to the Beasts strikes nobody: the go names no target, no 0x937 follows and Telekinetic Strike's Proxy 62204, aimed at the area (targetFlags 4), starts no child"
  // Facing the Beast ahead, it presses until that Beast dies.
  game_client.face(game: first, yaw: toward, clock: 200)
  let #(first_have, healths) =
    press_until_dead(
      time:,
      game: first,
      have: first_have,
      bag_index: 0,
      cast_ms: telekinetic_strike_cast_ms,
      lingers_ms: telekinetic_strike_lingers_ms,
      beast: ahead,
      cast_id: 2,
    )
  assert healths == [17, 0]
    as "an Esper of level 1 with the Novice gear (Assault Rating 203.0625, Assault Power 50.77): a hit of Telekinetic Strike is 0.336 x 50.77 = 17.06, rounded to 17, plus 18.0 for the level, 35 (Spell4Effects 62159, 0x140565600); the Beast has 52 health and never deflects, so the health is 17 and then 0"
  let #(watched, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(game_client.deaths_in(frames:), fn(death) {
        death == #(ahead, True)
      })
      && list.count(game_client.go_targets_in(frames:), fn(go) {
        go.1 == [ahead]
      })
      == 2
      && psi_children(frames:) == 2
    })
  // The Beast ahead fights back every 1500 ms with its own attack, Spell4 5649,
  // whose go names the caster; the kill lands 1250 ms after the first hit, before
  // its first 1500 ms tick, so it has not swung yet, and only the casts of
  // Telekinetic Strike are read here.
  let strike_cast_ids =
    list.filter_map(game_client.casts_in(frames: watched), fn(event) {
      case event {
        game_client.CastStarted(cast_id:, spell4_id: 32_893, ..) -> Ok(cast_id)
        game_client.CastStarted(..)
        | game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> Error(Nil)
      }
    })
  let strike_goes =
    list.filter(game_client.go_targets_in(frames: watched), fn(go) {
      list.contains(strike_cast_ids, go.0)
    })
  assert strike_goes != []
    && list.all(strike_goes, fn(go) { go.1 == [] || go.1 == [ahead] })
    as "the Beast 10 m to the side is within the area row's 30 m all round but outside the never-drawn telegraph 2169, a rectangle 3 m wide ahead of the caster grown by the Beast's hit radius 3 (Spell4.32893.area): no go of a Telekinetic Strike names it"
  assert list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == beside {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
    == []
    && !list.contains(game_client.removals_in(frames: watched), beside)
    as "the Beast to the side is struck by none, shown no health and never removed"
  assert list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == ahead {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
    == healths
    as "the watcher reads the same 0x937 the caster did, then 0x88c"
  assert psi_children(frames: watched) == 2
    as "Proxy 62204 starts the Psi Point child 30900 on each struck unit (Spell4Effects.targetFlags 4): two hits, two children"
  // The Beast stands again after its respawn time, 1000 ms from the kill, which the
  // clock moves on by: 0x355, then a full 0x262.
  driven_time.advance(time:, ms: 1000)
  let #(after_first, _) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  let #(after_second, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  list.each([after_first, after_second], fn(frames) {
    assert game_client.removals_in(frames:) == [ahead]
      && list.map(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id
      })
      == [ahead]
      as "death.creature_respawn: 0x355, then a 0x262 with the same unit id, to each viewer, for the Beast that died only"
  })
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The id of the last cast the frames start (0x7ff).
fn last_cast_of(frames: List(Frame)) -> Int {
  let assert Ok(game_client.CastStarted(cast_id:, ..)) =
    list.filter(game_client.casts_in(frames:), fn(event) {
      case event {
        game_client.CastStarted(..) -> True
        game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> False
      }
    })
    |> list.last
    as "the watcher was sent a cast's start"
  cast_id
}

/// Presses the ability of the bag index and moves the clock on by its cast time, so
/// the timer of its go fires: the first pong shows the connection took the press and
/// started the go's timer on the clock. The Beast answers the strike on its own
/// process, so the read after the advance goes on until the go is written with its
/// outcome (a health, a miss, or no target at all), and the second pong follows it.
/// The frames of the reads and the bytes beyond.
fn press_and_fire(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  cast_id cast_id: Int,
) -> #(List(Frame), BitArray) {
  game_client.press_ability(
    game:,
    client_cast_id: cast_id,
    bag_index:,
    target: 0,
  )
  let #(taken, have) = game_client.read_until_pong(game:, have:, number: 1)
  driven_time.advance(time:, ms: cast_ms)
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(went) {
      let seen = list.append(taken, went)
      let gos = game_client.go_targets_in(frames: seen)
      gos != []
      && {
        list.all(gos, fn(go) { go.1 == [] })
        || game_client.health_in(frames: seen) != []
        || game_client.missed_in(frames: seen) != []
      }
    })
  let #(settled, have) = game_client.read_until_pong(game:, have:, number: 2)
  #(list.flatten([taken, went, settled]), have)
}

/// Presses the ability of the bag index until a press hits the Beast (a deflected one
/// is shown by a 0x7fb and strikes again), and gives the Beast's health after the hit.
fn press_until_a_hit(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  beast beast: Int,
  cast_id cast_id: Int,
) -> #(BitArray, Int) {
  let #(frames, have) =
    press_and_fire(time:, game:, have:, bag_index:, cast_ms:, cast_id:)
  assert game_client.health_in(frames:) != []
    || game_client.missed_in(frames:) != []
    as "the press's hit or miss is written once the clock has fired its timer"
  case
    list.find(game_client.health_in(frames:), fn(health) { health.0 == beast })
  {
    Ok(health) -> #(have, health.1)
    Error(Nil) ->
      press_until_a_hit(
        time:,
        game:,
        have:,
        bag_index:,
        cast_ms:,
        beast:,
        cast_id: cast_id + 1,
      )
  }
}

/// The place of the first frame of the message in the frames, or -1.
fn position_of(frames frames: List(Frame), message_id message_id: Int) -> Int {
  case
    list.index_map(frames, fn(frame, index) { #(frame.message_id, index) })
    |> list.find(fn(entry) { entry.0 == message_id })
  {
    Ok(#(_, index)) -> index
    Error(Nil) -> -1
  }
}

/// Presses the ability of the bag index, one cast after another, until the 0x88c of
/// the Beast arrives: each press moves the clock on by the ability's cast time, and a
/// press that leaves the Beast alive moves it on by `lingers_ms` more, to the end of
/// the cast. The Beast's health after each hit, in order, and the bytes beyond.
fn press_until_dead(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  lingers_ms lingers_ms: Int,
  beast beast: Int,
  cast_id cast_id: Int,
) -> #(BitArray, List(Int)) {
  let #(have, healths, _) =
    press_until_dead_reading(
      time:,
      game:,
      have:,
      bag_index:,
      cast_ms:,
      lingers_ms:,
      beast:,
      cast_id:,
    )
  #(have, healths)
}

/// As `press_until_dead`, with every frame the presses were answered with, in order.
fn press_until_dead_reading(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  lingers_ms lingers_ms: Int,
  beast beast: Int,
  cast_id cast_id: Int,
) -> #(BitArray, List(Int), List(Frame)) {
  press_loop(
    time:,
    game:,
    have:,
    bag_index:,
    cast_ms:,
    lingers_ms:,
    beast:,
    cast_id:,
    healths: [],
    seen: [],
  )
}

fn press_loop(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  lingers_ms lingers_ms: Int,
  beast beast: Int,
  cast_id cast_id: Int,
  healths healths: List(Int),
  seen seen: List(Frame),
) -> #(BitArray, List(Int), List(Frame)) {
  let #(frames, have) =
    press_and_fire(time:, game:, have:, bag_index:, cast_ms:, cast_id:)
  let seen = list.append(seen, frames)
  assert game_client.health_in(frames:) != []
    || game_client.missed_in(frames:) != []
    as "the press's hit or miss is written once the clock has fired its timer"
  assert list.is_empty(game_client.health_in(frames:))
    || position_of(frames:, message_id: 0x07F4)
    < position_of(frames:, message_id: 0x0937)
    as "the caster's client is written the go, with the number, before the health it caused: a creature's news for a unit of the caster's open round is held until the go is written"
  let hits =
    list.filter_map(game_client.health_in(frames:), fn(health) {
      case health.0 == beast {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
  let healths = list.append(healths, hits)
  case list.last(healths) {
    Ok(0) -> {
      // The Beast sends its health and then its death on its own process, so the
      // pong does not show the death is written.
      let #(more, have) = case
        list.contains(game_client.deaths_in(frames:), #(beast, True))
      {
        True -> #([], have)
        False ->
          game_client.read_until(game:, have:, found: fn(more) {
            list.contains(game_client.deaths_in(frames: more), #(beast, True))
          })
      }
      assert list.contains(
        game_client.deaths_in(frames: list.append(frames, more)),
        #(beast, True),
      )
        as "the killing hit is followed by the Beast's 0x88c"
      #(have, healths, list.append(seen, more))
    }
    Ok(_) | Error(Nil) -> {
      driven_time.advance(time:, ms: lingers_ms)
      let #(later, have) = game_client.read_until_pong(game:, have:, number: 3)
      let seen = list.append(seen, later)
      assert holds_a_finish(frames: list.append(frames, later))
        as "the cast of the press has finished when the next press comes"
      press_loop(
        time:,
        game:,
        have:,
        bag_index:,
        cast_ms:,
        lingers_ms:,
        beast:,
        cast_id: cast_id + 1,
        healths:,
        seen:,
      )
    }
  }
}

// ------------------------------------------- a creature fights back, on the whole server
//
// Expected values come from the design of step F (the Design artifact of issue
// 367: its CI bot and its process tests 20, 21 and 22) and these places. The
// tests' characters are of the Dominion (faction 166), so the planted creature is
// a Virtual Defense Dagun, hostile to the Dominion (Faction2Relationship 1442-166
// level 0, `Creature2.73465`), with the Battle Beast's 52 health and attack: spell
// 5649's effect 184741 for 12 (`Spell4Effects.184741`) every attack interval of the
// creature kinds (a server choice: migration 0010; `spawn_support.kinds`), its own
// reach 5.0 + 2.0, run speed 10.0 (`0x1405b45e0`). The aggro range
// is 10 and the leash range 55 (migration 0010). A Medic of level 1 has 736 health
// and a shield of 450 (`player.level1_gear_properties`). The 0x908, 0x90a, 0x89a,
// 0x938, 0x92f and 0x638 are read as the client reads them (`opcode.0x908`,
// `opcode.0x90a`, `opcode.0x89a`, `opcode.0x938`, `opcode.0x92f`,
// `movement_command.kind_4`).

/// Where the Dagun stands: 23.5 units along -z from where a new test character
/// stands in World 1387, zone 1100, at 1.5, 2.5, 3.5.
const dagun_z = -20.0

/// The Dagun's attack tick: the attack interval of the creature kinds the tests'
/// worlds are planted with. The interval is a server choice (the client's effect
/// 184741 has no tickTime), so it is read from those kinds.
fn dagun_attack_interval_ms() -> Int {
  spawn_support.kinds().default.attack_interval_ms
}

/// A world with one Dagun at x 1.5, z -20, its map's and creature's timers and the
/// connections' on the clock `time`, so the Dagun's attack tick and home timer fire
/// only when the test advances it.
fn world_with_a_dagun(time time: driven_time.Time) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      world: server.World(
        ..settings.world,
        spawns: spawn_support.key_in(
          world_id: 1387,
          spawns: [
            spawn.Spawn(
              ..spawn_support.dagun(number: 1, x: 0.0),
              place: beast_place(x: 1.5, z: dagun_z),
            ),
          ],
          respawn_ms: 60_000,
        ),
      ),
    )
  })
}

/// Returns when the first creature of the map, unit `unit_id`, has taken all it was
/// sent, for a test whose next step is an input, not an advance (an advance waits
/// for the participants itself): a creature's frames are sent before its step's
/// timer is started.
fn the_creature_has_taken_what_it_was_sent(
  started started: login_support.Started,
  unit_id unit_id: Int,
) -> Nil {
  let #(_, creature) = the_dagun_and_its_map(started:, dagun: unit_id)
  driven_time.settled(creature)
}

/// A Medic of level 1 played in, its 0x262 and the Dagun's read, and ready: its
/// client's first 0xF2 sent.
fn a_ready_medic(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int, Int, BitArray) {
  let #(game, frames, have) =
    a_ready_player(started:, number:, character_name:, class_id: 4)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames:)
  #(game, own, dagun.unit_id, have)
}

/// As `a_ready_medic`, a Stalker.
fn a_ready_stalker(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int, Int, BitArray) {
  let #(game, frames, have) =
    a_ready_player(started:, number:, character_name:, class_id: 5)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames:)
  #(game, own, dagun.unit_id, have)
}

/// A player of the class, of level 1, played in, its entry and the Dagun's 0x262
/// read, and ready: its client's first 0xF2 sent. The frames read and the bytes
/// kept.
fn a_ready_player(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
) -> #(game_client.Game, List(Frame), BitArray) {
  let #(game, frames, have) =
    enters_and_sees_the_beasts(
      started:,
      number:,
      character_name:,
      class_id:,
      beasts: 1,
    )
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: 1100))
  game_client.send_world(game:, message_id: terrain_loaded.message_id, body:)
  #(game, frames, have)
}

fn walk_to(game game: game_client.Game, z z: Float, clock clock: Int) -> Nil {
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: clock, commands: [
      game_client.position_command(x: 1.5, y: 2.5, z:),
    ]),
  )
}

/// Reads until the fight's frames hold what `found` looks for.
fn read_fight(
  game game: game_client.Game,
  have have: BitArray,
  found found: fn(List(game_client.FightEvent)) -> Bool,
) -> #(List(game_client.FightEvent), BitArray) {
  let #(frames, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      found(game_client.fight_in(frames:))
    })
  #(game_client.fight_in(frames:), have)
}

/// Whether the Dagun has been sent a path among the events: a 0x638 with a kind 4 command.
fn dagun_runs(
  events events: List(game_client.FightEvent),
  dagun dagun: Int,
) -> Bool {
  list.any(game_client.moves_of(events:, unit: dagun), fn(move) {
    list.contains(move.0, 4)
  })
}

/// Whether a 0x638 of `unit` among the events leaves it at z: a path's end, or the
/// place a leash in the instant of the chase puts it at.
fn leaves_unit_at(
  events events: List(game_client.FightEvent),
  unit unit: Int,
  z z: Float,
) -> Bool {
  list.any(game_client.moves_of(events:, unit:), fn(move) {
    move.1 == Some(#(1.5, 2.5, z))
  })
}

pub fn a_bot_entering_a_daguns_ring_is_targeted_and_chased_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // The smoke test of the whole server: the aggro and the chase come at the
  // move, with no tick to wait for. The strike, the shield and the leash are driven
  // with the creature's timers in the test of both rules together
  // (game_connection_fight_test, `a_beasts_aggro_strike_and_leash_...`).
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  // Into the ring: 9 units from the Dagun, beyond its reach of 7.
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(fight, _) =
    read_fight(game:, have:, found: fn(events) {
      dagun_runs(events:, dagun:)
      && list.contains(
        events,
        game_client.InCombat(unit_id: own, in_combat: True),
      )
    })
  assert list.contains(
    fight,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "0x908: the Dagun targets the bot with the aggro threat 1"
  assert list.contains(
      fight,
      game_client.InCombat(unit_id: dagun, in_combat: True),
    )
    && list.contains(fight, game_client.InCombat(unit_id: own, in_combat: True))
    as "both 0x89a: the Dagun's and the bot's own"
  let assert [#(turn_kinds, _), #(kinds, ends_at), ..] =
    game_client.moves_of(events: fight, unit: dagun)
    as "the Dagun turns, then runs"
  assert turn_kinds == [0, 18]
    as "the turn goes before the path: kind 0, then kind 18 naming the bot (a kind 4 path leaves the rotation)"
  assert kinds == [0, 4, 10, 13, 18, 26]
    as "the chase: kind 0, the kind 4 path, then the defaults for the velocity, move and state with kind 18 for the bot in place of kind 21, so the Dagun goes on facing the bot after it stops, and no kind 11 or kind 24"
  let assert [#(1, []), #(1, []), ..] =
    game_client.ground_lift_of(events: fight, unit: dagun)
    as "unit.ground_lift.server_commands: the turn and the run both keep the second bit 1, and neither holds a kind 24, the run's state coming from the state default"
  assert ends_at == Some(#(1.5, 2.5, dagun_z +. 9.0 -. 3.5))
    as "to the bot less half the Dagun's reach of 7 (chase_stop_fraction 0.5)"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Stalker's ability bag index of Stealth, Spell4 46073: its press starts Stealth
/// 38784 and, when the caster is stealthed, its Cancel 38783 (Spell4Effects 107792 and
/// 107793, behind Prerequisites 7050 and 8127).
const stealth_index = 3

/// The recharge of the Stealth toggle out of combat, which a second press waits for
/// (Spell4Effects 159128: dataBits03 is the float 1000.0).
const stealth_recharge_ms = 1000

/// Whether a go of a cast of the unit `caster` names the unit `target` (opcode.0x7f4).
fn struck_by(
  frames frames: List(Frame),
  caster caster: Int,
  target target: Int,
) -> Bool {
  list.any(game_client.go_targets_in(frames:), fn(go) {
    cast_state.caster_of(cast_id: go.0) == caster && list.contains(go.1, target)
  })
}

/// Whether the event is a 0x908 of the unit, whoever it targets and whatever the threat.
fn is_targeted_by(event event: game_client.FightEvent, unit unit: Int) -> Bool {
  case event {
    game_client.Targeted(unit_id:, ..) -> unit_id == unit
    game_client.Threatens(..)
    | game_client.InCombat(..)
    | game_client.LevelIs(..)
    | game_client.ShieldIs(..)
    | game_client.InterruptArmorIs(..)
    | game_client.AbsorptionIs(..)
    | game_client.OwnHealthIs(..)
    | game_client.Moves(..)
    | game_client.Went(..)
    | game_client.Started(..)
    | game_client.HealthIs(..) -> False
  }
}

/// The stealth changes among the frames, each the unit and its stealthed bit, in
/// order (opcode.0x8f5).
fn stealth_changes_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_stealth.message_id {
      True -> {
        let assert Ok(change) = unit_stealth.decode(frame.body)
          as "0x8f5 decodes"
        Ok(#(change.unit_id, change.stealthed))
      }
      False -> Error(Nil)
    }
  })
}

/// The run of the world 1387 map and the process of the Dagun's creature, unit
/// `dagun`. The first player's connection takes the map's watch 1, so the first
/// creature has life 2 (genesis_prime/world_map/map `joined_new`).
fn the_dagun_and_its_map(
  started started: login_support.Started,
  dagun dagun: Int,
) -> #(world_map_registry.MapProcess, process.Pid) {
  let assert Ok(run) =
    open_wait.named("Maps to answer the find", fn() {
      world_map_registry.find_or_start(
        started.settings.world.maps,
        MapId(world_id: 1387, instance: 0),
        deadline_ms: ask_support.deadline_far_beyond_the_tests_deadline(),
      )
    })
    as "the map is running, started by the play"
  let assert Ok(creature) =
    creature_registry.find(
      started.settings.world.creatures,
      map: MapId(world_id: 1387, instance: 0),
      incarnation: run.incarnation,
      unit_id: dagun,
      life: 2,
    )
    as "the Dagun runs under its address"
  #(run, creature)
}

/// Pings and reads all the server wrote for the connection after what the test sent
/// has crossed the map and the creature. It rests on one ordering assumption, which
/// nothing but the first pong links: the connection takes what the test sent (the
/// first pong is written after its tells to the map), so the map holds the
/// connection's `Moved` before the test's `get_state` of the map; the map then
/// holds nothing for the creature that is not already in the creature's mailbox
/// (a local send lands at once), so the `get_state` of the creature follows its
/// `Approached`; and the creature has queued what it tells the connection before
/// the second ping, which the connection takes after it. The frames of both reads.
fn read_after_the_map_and_the_creature_took_it(
  game game: game_client.Game,
  have have: BitArray,
  started started: login_support.Started,
  dagun dagun: Int,
  pongs pongs: #(Int, Int),
) -> #(List(Frame), BitArray) {
  let #(first, have) =
    game_client.read_until_pong(game:, have:, number: pongs.0)
  let #(run, creature) = the_dagun_and_its_map(started:, dagun:)
  let _map_took_it = system.get_state(run.pid)
  let _creature_took_it = system.get_state(creature)
  let #(second, have) =
    game_client.read_until_pong(game:, have:, number: pongs.1)
  #(list.append(first, second), have)
}

pub fn a_stealthed_bot_walking_into_a_daguns_ring_gets_no_aggro_and_pressing_stealth_again_inside_it_is_targeted_and_chased_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // A Stalker pressing its Stealth toggle, Spell4.46073: a first press enters stealth
  // and a second ends it. The toggle recharges in 1000 ms out of combat, so the
  // connections' clock is driven and moved by hand between the presses.
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_stalker(started:, number: 1, character_name: "Zed Qu")
  game_client.press_ability(
    game:,
    client_cast_id: 1,
    bag_index: stealth_index,
    target: 0,
  )
  let #(entered, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      stealth_changes_in(frames:) != []
    })
  assert stealth_changes_in(frames: entered) == [#(own, 1)]
    as "opcode.0x8f5: the press enters stealth"
  // Into the ring: 9 units from the Dagun, beyond its reach of 7.
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(walked, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  let walked = game_client.fight_in(frames: walked)
  assert list.all(walked, fn(event) { !is_targeted_by(event:, unit: dagun) })
    && !list.contains(
      walked,
      game_client.InCombat(unit_id: dagun, in_combat: True),
    )
    && !list.contains(
      walked,
      game_client.InCombat(unit_id: own, in_combat: True),
    )
    && game_client.moves_of(events: walked, unit: dagun) == []
    as "Jim's decision, a server choice: the stealthed bot stands in no ring, so the Dagun sends no 0x908 at all or 0x89a and does not run"
  driven_time.advance(time:, ms: stealth_recharge_ms)
  game_client.press_ability(
    game:,
    client_cast_id: 2,
    bag_index: stealth_index,
    target: 0,
  )
  let #(fight, _) =
    read_fight(game:, have:, found: fn(events) {
      dagun_runs(events:, dagun:)
      && list.contains(
        events,
        game_client.InCombat(unit_id: own, in_combat: True),
      )
    })
  assert list.contains(
    fight,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "leaving stealth inside the ring aggroes as a walk-in does: 0x908 with the aggro threat 1"
  let assert [#(turn_kinds, _), #(kinds, ends_at), ..] =
    game_client.moves_of(events: fight, unit: dagun)
    as "the Dagun turns, then runs"
  assert turn_kinds == [0, 18]
    as "the turn goes before the path: kind 0, then kind 18 naming the bot (a kind 4 path leaves the rotation)"
  assert kinds == [0, 4, 10, 13, 18, 26]
    as "the chase: kind 0, the kind 4 path, then the defaults for the velocity, move and state with kind 18 for the bot in place of kind 21, so the Dagun goes on facing the bot after it stops, and no kind 11 or kind 24"
  assert ends_at == Some(#(1.5, 2.5, dagun_z +. 9.0 -. 3.5))
    as "to the bot less half the Dagun's reach of 7 (chase_stop_fraction 0.5)"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_dagun_fighting_a_bot_that_then_stealths_keeps_striking_it_and_its_landed_blow_ends_the_stealth_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // The same Stalker as above: Stealth 38784's row 83834 (dataBits02 0: damage taken
  // ends it) is the one a press out of combat reaches.
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_stalker(started:, number: 1, character_name: "Zed Qu")
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
    })
  the_creature_has_taken_what_it_was_sent(started:, unit_id: dagun)
  game_client.press_ability(
    game:,
    client_cast_id: 1,
    bag_index: stealth_index,
    target: 0,
  )
  let #(entered, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      stealth_changes_in(frames:) != []
    })
  // The map has told the Dagun of the bot's stealth, and the Dagun has taken it,
  // before the clock reaches its attack tick, so the tick meets the Dagun with the
  // stealth on its threat list.
  let #(taken, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  // The Dagun's attack tick, its interval after the aggro: the bot is in its reach
  // by then, and the strike's chain ends in the bot's 0x8f5 of the stealth ending.
  driven_time.advance(time:, ms: dagun_attack_interval_ms())
  let #(struck, _) = game_client.read_until_pong(game:, have:, number: 3)
  let frames = list.flatten([entered, taken, struck])
  assert stealth_changes_in(frames:) == [#(own, 1), #(own, 0)]
    as "opcode.0x8f5: the press enters stealth, and the Dagun, which keeps fighting the bot it already had on its threat list, strikes it: Spell4Effects.effectType.83 (83834, dataBits02 0) ends the stealth on the damage taken"
  assert struck_by(frames:, caster: dagun, target: own)
    as "the Dagun's strike names the bot: it keeps fighting a player it already had on its threat list (opcode.0x7f4)"
  assert !struck_by(frames:, caster: own, target: dagun)
    as "the bot's own press struck nothing, so the Dagun's threat list held the bot from the walk-in, not from the press"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
    })
  let #(_, pid) = the_dagun_and_its_map(started:, dagun:)
  process.kill(pid)
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.InCombat(unit_id: own, in_combat: False),
      )
    })
  assert list.contains(game_client.removals_in(frames:), dagun)
    as "the map's Gone: the bot's client removes the Dagun"
  game_client.close(game:)
  login_support.stop(started)
}

// ------------------------------------------- death and coming back, on the whole server
//
// Expected values come from the design of step G (issue 368: test 12, the
// coming back's frames of tests 8 and 9) and these places: the client's Death
// addon sends 0x15a {its unit, 1 or 2, 0} for Wake Here and the Holocrypt
// (`lua.GameLib.RezType`); Wake Here writes 0x92f, 0x938, 0x88c, 0x1b3, 0x355,
// 0x636 and 0x247 in that order (`opcode.0x88c`, `opcode.0x1b3`,
// `opcode.0x247.death`), at full health and shield (`death.server_choices`), the
// values the player entered with in its 0x262 (stats 0 and 20); the Holocrypt
// writes the same, then the entry burst at the start of the race and faction in
// the world, else at the place the stay entered at (`death.server_choices`):
// World 1387 holds no Novice start, so the place a new test character stands at.

/// A world with one Dagun at x 1.5, z -20 whose blow is 100000: planted test
/// data, since the Dagun's own 12 every 1500 ms takes some 400 ticks to kill a
/// player of level 1, and the test is of the death and the coming back, not of the
/// number. The fight's sequence is the client's as on the Dagun of
/// `world_with_a_dagun`.
fn world_with_a_lethal_dagun(
  time time: driven_time.Time,
) -> login_support.Started {
  let dagun =
    spawn_support.spawn_dealing(
      spawn: spawn_support.dagun(number: 1, x: 0.0),
      damage: 100_000,
    )
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      world: server.World(
        ..settings.world,
        spawns: spawn_support.key_in(
          world_id: 1387,
          spawns: [
            spawn.Spawn(..dagun, place: beast_place(x: 1.5, z: dagun_z)),
          ],
          respawn_ms: 60_000,
        ),
      ),
    )
  })
}

/// The player of the frames' 0x262 walks into the Dagun's ring, the Dagun's aggro
/// is read with its tick on the clock, the clock moves on to the tick (the Dagun runs
/// to within its reach of the bot in less than that), and the player is read until
/// its own 0x88c marks it dead and the death's last frame, the ghost's 0x636, has
/// come: the bytes kept.
fn killed_by_the_dagun(
  time time: driven_time.Time,
  started started: login_support.Started,
  game game: game_client.Game,
  own own: Int,
  dagun dagun: Int,
  have have: BitArray,
) -> BitArray {
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  driven_time.advance(time:, ms: dagun_attack_interval_ms())
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.deaths_in(frames:), #(own, True))
      && list.any(frames, fn(frame) { frame.message_id == 0x0636 })
    })
  have
}

/// 0x15a for the unit and the choice, with the value 0, sent inside 0x038C.
fn choose(
  game game: game_client.Game,
  own own: Int,
  choice choice: Int,
) -> Nil {
  game_client.send_world(
    game:,
    message_id: 0x015A,
    body: message_support.choice_body(unit_id: own, choice:, value: 0),
  )
}

/// The frames of the coming back among `frames`, in order.
fn coming_back_in(frames frames: List(Frame)) -> List(Frame) {
  list.filter(frames, fn(frame) {
    list.contains(
      [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247],
      frame.message_id,
    )
  })
}

/// The stat of the player's own 0x262.
fn entry_stat(entry entry: List(Frame), stat_id stat_id: Int) -> Int {
  let player = game_client.unit_create_player_in(frames: entry)
  let assert Ok(value) = unit_fields.stat(tail: player.tail, stat_id:)
    as "the player's 0x262 holds the stat as an integer"
  value
}

pub fn a_bot_of_each_class_killed_by_a_planted_dagun_comes_back_by_wake_here_over_the_wire_and_the_spellslinger_by_the_holocrypt_test() -> Nil {
  use <- owned_test.run(120_000)
  // The Medic's half of the fight, a creature it kills standing again at its
  // respawn, is `a_medic_kills_a_planted_beast_with_paralytic_surge_and_a_watcher_reads_the_same_fight_test`.
  // Each bot has a world and a clock of its own: the Dagun that has killed one is
  // walking home on a timer, and the next bot's death should not wait on it.
  list.each(
    [
      #(1, "Ann Qu", 1),
      #(2, "Bea Qu", 2),
      #(3, "Cal Qu", 3),
      #(4, "Dee Qu", 4),
      #(5, "Eve Qu", 5),
    ],
    fn(bot) {
      let #(number, character_name, class_id) = bot
      let class = "class " <> int.to_string(class_id)
      let time = driven_time.new()
      let started = world_with_a_lethal_dagun(time:)
      let #(game, entry, have) =
        a_ready_player(started:, number:, character_name:, class_id:)
      let own = game_client.unit_create_player_in(frames: entry).unit_id
      let assert [dagun] = game_client.creatures_created_in(frames: entry)
      let have =
        killed_by_the_dagun(
          time:,
          started:,
          game:,
          own:,
          dagun: dagun.unit_id,
          have:,
        )
      choose(game:, own:, choice: 1)
      let #(frames, _) =
        game_client.read_until(game:, have:, found: fn(frames) {
          list.contains(
            list.map(coming_back_in(frames:), fn(frame) { frame.message_id }),
            0x0247,
          )
        })
      let back = coming_back_in(frames:)
      assert cast_support.ids(frames: back)
        == [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247]
        as { class <> " comes back by Wake Here in the client's order" }
      assert list.contains(game_client.deaths_in(frames: back), #(own, False))
        as { class <> ": 0x88c marks its unit alive" }
      let assert [Frame(body: health, ..)] =
        list.filter(back, fn(frame) { frame.message_id == 0x092F })
      let assert Ok(health) = player_health.decode(health)
      let assert [Frame(body: shield, ..)] =
        list.filter(back, fn(frame) { frame.message_id == 0x0938 })
      let assert Ok(unit_stat_changed.UnitStatChanged(
        change: unit_stat_change.Shield(UnitStatShield(value: shield)),
        ..,
      )) = unit_stat_changed.decode(shield)
        as "the 0x938 is the shield's"
      assert health.health == entry_stat(entry:, stat_id: 0)
        && shield == entry_stat(entry:, stat_id: 20)
        as { class <> ": at the full health and shield it entered with" }
      game_client.close(game:)
      login_support.stop(started)
    },
  )
  // The Spellslinger comes back by the Holocrypt.
  let time = driven_time.new()
  let started = world_with_a_lethal_dagun(time:)
  let #(game, entry, have) =
    a_ready_player(started:, number: 6, character_name: "Fay Qu", class_id: 7)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames: entry)
  let have =
    killed_by_the_dagun(
      time:,
      started:,
      game:,
      own:,
      dagun: dagun.unit_id,
      have:,
    )
  choose(game:, own:, choice: 2)
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.count(
        list.drop_while(frames, fn(frame) { frame.message_id != 0x00AD }),
        fn(_) { True },
      )
      >= holocrypt_burst_length()
    })
  let burst =
    list.take(
      list.drop_while(frames, fn(frame) { frame.message_id != 0x00AD }),
      holocrypt_burst_length(),
    )
  assert cast_support.ids(frames: burst) == game_client.holocrypt_entry_ids()
    as "the Spellslinger comes back by the Holocrypt: the entry burst, 0xAD first, with no second 0x25E (opcode.0x25e.entry_order)"
  let assert [Frame(body:, ..), ..] = burst
  let assert Ok(entered) = enter_world.decode(body)
  assert entered.world_id == 1387
    && entered.position_x == float32.to_bits(1.5)
    && entered.position_y == float32.to_bits(2.5)
    && entered.position_z == float32.to_bits(3.5)
    as "at the place the stay entered at: World 1387 holds no Novice start"
  game_client.close(game:)
  login_support.stop(started)
}

/// Whether the creature's fight is Returning, read from its process's state: the
/// service shell's `Running` holds the creature's state as its fourth field, whose fifth
/// is its fight, whose second is the fight's status: an atom for Resting, else a tuple
/// tagged by the status.
fn creature_walks_home(creature creature: process.Pid) -> Bool {
  let tag = decode.map(atom.decoder(), atom.to_string)
  let status = decode.one_of(tag, [decode.at([0], tag)])
  let assert Ok(status) =
    decode.run(system.get_state(creature), decode.at([3, 4, 1], status))
    as "the creature's state holds its fight's status"
  status == "returning"
}

pub fn a_bot_killed_by_a_dagun_in_its_ring_is_struck_no_more_the_dagun_rests_at_home_and_waking_in_the_ring_is_aggroed_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // Jim's live report: a creature that killed a player kept attacking the body. A
  // creature leashes at the death (0x90a 0, 0x89a (C, 0)) and, standing at its spawn, its
  // home timer fires at once, so a body left in the creature's near set was aggroed
  // again in the same instant. A server choice (the Design of issue 496): a dead unit is
  // struck by nothing (`Spell4ValidTargets.targetBitmask`), so the Dagun rests, and a
  // player that wakes inside its ring is aggroed as a walk-in is.
  let time = driven_time.new()
  let started = world_with_a_lethal_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  // Into the ring and within the Dagun's reach: it strikes from home and never runs, so
  // its home timer after the kill has no walk to wait for, and is due when the leash
  // starts it.
  walk_to(game:, z: dagun_z +. 5.0, clock: 100)
  let #(aggro, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  // The attack tick strikes and kills, and the clock fires the home timer the leash
  // started at the same instant, each after the barrier of the one before it.
  driven_time.advance(time:, ms: dagun_attack_interval_ms())
  let #(died, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.deaths_in(frames:), #(own, True))
      && list.any(frames, fn(frame) { frame.message_id == 0x0636 })
      && list.contains(
        game_client.fight_in(frames:),
        game_client.InCombat(unit_id: dagun, in_combat: False),
      )
    })
  assert list.contains(
    game_client.fight_in(frames: died),
    game_client.Threatens(unit_id: dagun, other_unit_id: own, threat: 0),
  )
    as "opcode.0x90a: the Dagun erases the body's threat when it leashes"
  let #(_, creature) = the_dagun_and_its_map(started:, dagun:)
  assert !creature_walks_home(creature:)
    as "the Dagun took its home timer: the clock fired it after the leash"
  let #(settled, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(3, 4),
    )
  let after_the_leash =
    list.drop(
      list.drop_while(
        game_client.fight_in(frames: list.flatten([aggro, died, settled])),
        fn(event) {
          event != game_client.InCombat(unit_id: dagun, in_combat: False)
        },
      ),
      1,
    )
  assert list.all(after_the_leash, fn(event) {
    case event {
      game_client.Targeted(unit_id:, ..)
      | game_client.Started(caster_unit_id: unit_id, ..) -> unit_id != dagun
      game_client.Went(cast_id:, ..) -> cast_state.caster_of(cast_id:) != dagun
      game_client.Moves(unit_id:, kinds:, ..) ->
        // After the leash the Dagun only turns to its spawn facing, with the blended kind 19
        // turn a creature arriving home makes; it never runs.
        unit_id != dagun || kinds == [0, 19]
      game_client.Threatens(..)
      | game_client.InCombat(..)
      | game_client.LevelIs(..)
      | game_client.ShieldIs(..)
      | game_client.InterruptArmorIs(..)
      | game_client.AbsorptionIs(..)
      | game_client.OwnHealthIs(..)
      | game_client.HealthIs(..) -> True
    }
  })
    as "after the Dagun's leash and its home timer the Dagun names no target, starts no cast, strikes and runs nowhere (the one 0x638 it is sent is kind 0 then kind 14, the leash's turn to its spawn's facing as it stands at home already): the body is in no ring"
  choose(game:, own:, choice: 1)
  let #(woke, _) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(
        events,
        game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
      )
    })
  assert list.contains(
    woke,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "0x908: the bot that woke inside the ring is aggroed with the aggro threat 1, as a walk-in"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(watcher, _, dagun, watcher_have) =
    a_ready_medic(started:, number: 2, character_name: "Ann Qu")
  let #(fighter, own, _, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  walk_to(game: fighter, z: dagun_z +. 9.5, clock: 100)
  // The fighter ends once the Dagun runs toward it: mid-chase.
  let #(_, _) =
    read_fight(game: fighter, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
      && game_client.moves_of(events:, unit: dagun) != []
    })
  game_client.close(game: fighter)
  let #(seen, _) =
    read_fight(game: watcher, have: watcher_have, found: fn(events) {
      leaves_unit_at(events:, unit: dagun, z: dagun_z)
    })
  assert list.contains(
      seen,
      game_client.Threatens(unit_id: dagun, other_unit_id: own, threat: 0),
    )
    && list.contains(
      seen,
      game_client.InCombat(unit_id: dagun, in_combat: False),
    )
    && list.contains(game_client.health_of(events: seen, unit: dagun), 52)
    as "the fighter's end is its Unwatched: no threat is left, so the Dagun leashes (0x90a 0, 0x89a (C, 0), a full 0x937) and runs home, which the watcher sees"
  game_client.close(game: watcher)
  login_support.stop(started)
}

// ---- a timed quest is botched ----

pub fn a_timed_quest_is_botched_over_the_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 1872 (Quest2 flags 0x404) is given a limit of 60,000 ms, as the fixture
  // holds none of the client's timed quests. The character holds it with 60,000 ms
  // left; the entry starts its timer on the driven clock, and 0x35C of quest 1872 in
  // state 4 (Botched; its 10 bytes are 0x50, 0x07, 0x02 and zeros) is written when
  // the clock reaches the deadline, never before (opcode.0x35c).
  use tables <- quest_support.with_time_limits(limits: [#(1872, 60_000)])
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      server.Settings(
        ..settings,
        game: server.Served(
          ..settings.game,
          settings: connection_state.Settings(..settings.game.settings, tables:),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 1872, 1, 0, true, 0, '{}', 60000, '{}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 1872 with 60,000 ms left"
  send_play(game:, character_id: character)
  let #(_, have) = game_client.read_entry_kept(game:, have: <<>>)
  // The pong shows the entry's step is done, so its timer is on the clock.
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 1)
  driven_time.advance(time:, ms: 59_999)
  let #(before, have) = game_client.read_until_pong(game:, have:, number: 2)
  assert !list.any(before, fn(frame) { frame.message_id == 0x035C })
    as "1 ms before its deadline the quest is not botched"
  driven_time.advance(time:, ms: 1)
  let #(after, _) = game_client.read_until_pong(game:, have:, number: 3)
  assert list.filter(after, fn(frame) { frame.message_id == 0x035C })
    == [
      Frame(message_id: 0x035C, body: <<0x50, 0x07, 0x02, 0, 0, 0, 0, 0, 0, 0>>),
    ]
    as "opcode.0x35c: quest 1872 is Botched at its deadline"
  // The pong follows the save the botch asked for, which the connection answers
  // before it takes the ping.
  let assert Ok(saved) =
    pog.query(
      "select state, quest_ms_left from character_quest where character_id = $1 and quest_id = 1872",
    )
    |> pog.parameter(pog.int(character))
    |> pog.returning({
      use state <- decode.field(0, decode.int)
      use ms_left <- decode.field(1, decode.optional(decode.int))
      decode.success(#(state, ms_left))
    })
    |> pog.execute(pool)
    as "the quest row is read"
  assert saved.rows == [#(4, None)]
    as "the botch is saved: state 4, which holds no time left"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- a bot plays the items, the vendor and the levels ----

/// The Item2 the bot buys, splits, moves, sells and buys back: it stacks to 50 and a
/// lot is 1 item (`vendor_purchase_test`'s rows), and the client shows 67 credits for it
/// at the multiplier 1.0 (`vendor.start_zone_prices`).
const stimpack = 14_838

const stimpack_cost = 67

/// What Supplier Ingavak pays for one: the sell base 10 at his multiplier 1.0
/// (`item_price_test`).
const stimpack_sells_for = 10

/// The Item2 the bot buys a lot of and deletes: a lot is 5 items at 13 credits each
/// (`vendor_purchase_test`: 20791 stacks to 99, buyFromVendorStackCount 5).
const bandage = 20_791

const bandage_lot_cost = 65

/// A slot of the inventory (location 1).
fn in_bags(bag_index bag_index: Int) -> item_place.ItemPlace {
  item_place.ItemPlace(location: 1, bag_index:)
}

/// The chest's slot among the worn items: bag index 0, the lowest bit of its slot flags
/// (`inventory_test`).
const chest_slot = item_place.ItemPlace(location: 0, bag_index: 0)

pub fn a_bot_moves_splits_equips_deletes_buys_sells_buys_back_and_levels_up_and_finds_it_all_after_a_relog_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  // Supplier Ingavak (Creature2 28739) stands 3.0 from the player's edge, behind the
  // player, within the 9.0 a vendor request is answered up to (opcode.0x7ea); the Beast
  // stands 3 m ahead, where the fight of the medic's test strikes it. The player is an
  // Exile (faction 167), to whom his faction 171 is friendly (Faction2Relationship 771),
  // with 1000 credits and one experience point less than level 2 asks for
  // (XpPerLevel row 2's minXpForLevel).
  let time = driven_time.new()
  let vendors =
    vendor_support.stocking_items(
      creature_ids: [28_739],
      items: vendor_support.ingavaks_items,
    )
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_706),
          creature_id: 28_739,
          display_info_id: 29_772,
          outfit_info_id: 9029,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors:,
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_706))
  let ingavak =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 +. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let started =
    login_support.start_with(time:, change: fn(settings) {
      server.Settings(
        ..settings,
        game: server.Served(
          ..settings.game,
          settings: connection_state.Settings(
            ..settings.game.settings,
            tables:,
            vendors:,
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [
              ingavak,
              spawn_support.beast_without_deflect_at(
                number: 1,
                place: beast_place(x: 1.5, z: 0.5),
              ),
            ],
            respawn_ms: 1000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(level_two) = xp_per_level.get(tables:, id: XpPerLevelId(2))
    as "XpPerLevel has a row 2"
  let experience_before = level_two.min_xp_for_level - 1
  let assert Ok(_) =
    pog.query(
      "update character set faction_id = 167, experience = $2 where character_id = $1",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(experience_before))
    |> pog.execute(pool)
    as "the character is of the faction Ingavak is friendly to, one point short of level 2"
  let assert Ok(_) =
    pog.query(
      "insert into character_currency (character_id, currency_type_id, amount) values ($1, 1, $2)",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(credits_before_the_buy))
    |> pog.execute(pool)
    as "the character holds credits"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(game_client.creatures_created_in(frames:)) >= 2
    })
  assert credits_in_entry(frames: entry) == credits_before_the_buy
    as "the entry carries the credits the character holds"
  assert entry_stat(entry:, stat_id: 10) == 1
    as "the entry's 0x262 shows level 1"
  let shown = game_client.creatures_created_in(frames: entry)
  let assert Ok(vendor) =
    list.find(shown, fn(unit) { unit.creature_id == 28_739 })
    as "Supplier Ingavak is in sight"
  let assert Ok(beast) =
    list.find(shown, fn(unit) { unit.creature_id != 28_739 })
    as "the Beast is in sight"
  let assert Ok(chest) =
    list.find(item_bot.answer_in(frames: entry).added, fn(held) {
      held.item.location == chest_slot.location
      && held.item.bag_index == chest_slot.bag_index
    })
    as "the creation loadout wears a chest piece"
  let chest = chest.item
  // 1: buys 3 of the stimpack. A lot is 1 item, so 3 lots; a new stack goes to the
  // lowest empty slot (`vendor_purchase_test`), for the credits the window shows.
  let #(window, have) =
    item_bot.open_vendor(game:, have:, unit_id: vendor.unit_id)
  let assert Ok(row) =
    list.find(window.items, fn(row) { row.entry_id == stimpack })
    as "the window shows the stimpack"
  assert window.buy_multiplier == float32.to_bits(1.0)
    as "the window's multiplier is the 1.0 at which the client shows 67 for the stimpack (vendor.start_zone_prices)"
  let #(bought, have) =
    item_bot.buy(game:, have:, unique_id: row.unique_id, quantity: 3)
  assert bought.refused == [] as "the buy is allowed"
  assert list.map(bought.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 3 * stimpack_cost)]
    as "opcode.0x919: kind 0 sets the total, the credits less 3 stimpacks"
  let assert [added] = bought.added as "3 lots of 1 item fill one new stack"
  let stack = added.item
  assert #(stack.item_id, stack.location, stack.bag_index, stack.stack_count)
    == #(stimpack, 1, 0, 3)
    as "vendor_purchase_test: a stack of 3 at the lowest empty slot of the inventory"
  // 2: splits 1 off into an empty slot.
  let #(split, have) =
    item_bot.split(
      game:,
      have:,
      item_guid: stack.item_guid,
      to: in_bags(bag_index: 5),
      count: 1,
    )
  assert split.refused == [] as "the split is allowed"
  assert list.map(split.count_changed, fn(changed) {
      #(changed.item_guid, changed.count)
    })
    == [#(stack.item_guid, 2)]
    as "opcode.0x17f: the stack keeps 2"
  let assert [split_off] = split.added as "the one split off is a new item"
  let single = split_off.item
  assert #(
      single.item_id,
      single.location,
      single.bag_index,
      single.stack_count,
    )
    == #(stimpack, 1, 5, 1)
    as "opcode.0x17d: the split goes to the slot the bot named, with the count it named"
  // 3: moves the one to another empty slot.
  let #(moved, have) =
    item_bot.move(
      game:,
      have:,
      from: in_bags(bag_index: 5),
      to: in_bags(bag_index: 7),
    )
  assert moved.refused == [] as "the move is allowed"
  assert list.map(moved.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(single.item_guid, in_bags(bag_index: 7))]
    as "opcode.0x569: the item is at the new slot"
  // 4: sells the stack of 2: the vendor pays 10 for each, and the sale is the Buyback
  // list's first.
  let #(sold, have) =
    item_bot.sell(
      game:,
      have:,
      place: item_place.ItemPlace(
        location: stack.location,
        bag_index: stack.bag_index,
      ),
      quantity: 2,
    )
  let credits_after_the_sale =
    credits_before_the_buy - 3 * stimpack_cost + 2 * stimpack_sells_for
  assert sold.refused == [] as "the sale is allowed"
  assert list.map(sold.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_after_the_sale)]
    as "opcode.0x919: the credits plus the 10 the vendor pays for each of 2"
  assert list.map(sold.removed, fn(removed) {
      #(removed.item_guid, removed.reason)
    })
    == [#(stack.item_guid, 7)]
    as "opcode.0x148 with the reason 7, Vendor"
  let assert [listed] = sold.buyback_added
    as "the sale is added to the Buyback list"
  assert #(
      listed.item_id,
      listed.quantity,
      listed.amount_1,
      listed.currency_type_1,
    )
    == #(stimpack, 2, 2 * stimpack_sells_for, 1)
    as "opcode.0xba.price: the entry holds the item, its count, the credits paid and the currency type 1"
  // 5: buys it back for what the entry holds: the vendor_purchase rule fills a stack
  // below the stack limit first, so the held stack of 1 grows to 3.
  let #(back, have) =
    item_bot.buy_back(game:, have:, buyback_id: listed.buyback_id)
  assert back.refused == [] as "the buy back is allowed"
  assert list.map(back.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 3 * stimpack_cost)]
    as "opcode.0xba.price: a buy back costs what its entry holds, so the credits are as before the sale"
  assert back.buyback_removed == [listed.buyback_id]
    as "opcode.0xbd: the entry leaves the Buyback list"
  assert back.added == [] as "the bought-back items make no new stack"
  assert list.map(back.count_changed, fn(changed) {
      #(changed.item_guid, changed.count, changed.reason)
    })
    == [#(single.item_guid, 3, 16)]
    as "opcode.0x17f with the reason 16, Buyback: the moved stack of 1 grows to 3"
  // 6: buys a lot of bandages and deletes it.
  let assert Ok(bandage_row) =
    list.find(window.items, fn(row) { row.entry_id == bandage })
    as "the window shows the bandage"
  let #(lot, have) =
    item_bot.buy(game:, have:, unique_id: bandage_row.unique_id, quantity: 1)
  assert lot.refused == [] as "the buy is allowed"
  assert list.map(lot.currencies, fn(told) { #(told.kind, told.total) })
    == [
      #(0, credits_before_the_buy - 3 * stimpack_cost - bandage_lot_cost),
    ]
    as "opcode.0x919: the credits less the 65 of a lot"
  let assert [lot_added] = lot.added as "a lot is one new stack"
  let bandages = lot_added.item
  assert #(bandages.item_id, bandages.stack_count) == #(bandage, 5)
    as "a lot of 20791 is 5 items"
  let #(deleted, have) =
    item_bot.delete(
      game:,
      have:,
      place: item_place.ItemPlace(
        location: bandages.location,
        bag_index: bandages.bag_index,
      ),
    )
  assert deleted.refused == [] as "the delete is allowed"
  assert list.map(deleted.removed, fn(removed) {
      #(removed.item_guid, removed.reason)
    })
    == [#(bandages.item_guid, 21)]
    as "opcode.0x149: the item goes with the reason 21, Delete"
  // 7 and 8: takes the chest off into an empty slot and puts it back on.
  let #(off, have) =
    item_bot.move(game:, have:, from: chest_slot, to: in_bags(bag_index: 10))
  assert off.refused == [] as "the chest comes off"
  assert list.map(off.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(chest.item_guid, in_bags(bag_index: 10))]
    as "opcode.0x182: the chest is in the bag slot it was moved to"
  let #(on, have) =
    item_bot.move(game:, have:, from: in_bags(bag_index: 10), to: chest_slot)
  assert on.refused == [] as "the chest goes on"
  assert list.map(on.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(chest.item_guid, chest_slot)]
    as "opcode.0x182: the chest is in the chest slot again"
  // 9: kills the Beast with the Medic's first ability, as the medic's test does.
  let own = game_client.unit_create_player_in(frames: entry)
  let own_place = game_client.placed_at(unit: own)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    )),
    clock: 100,
  )
  let #(have, _, fight) =
    press_until_dead_reading(
      time:,
      game:,
      have:,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      lingers_ms: fight_bot.paralytic_surge_lingers_ms,
      beast: beast.unit_id,
      cast_id: 1,
    )
  let #(fight, have) = case
    list.any(fight, fn(frame) { frame.message_id == 0x01AC })
  {
    True -> #(fight, have)
    False -> {
      let #(more, have) =
        game_client.read_until(game:, have:, found: fn(more) {
          list.any(more, fn(frame) { frame.message_id == 0x01AC })
        })
      #(list.append(fight, more), have)
    }
  }
  // The shell writes each effect with its own send, so the level's 0x938 can come in a
  // later read than the 0x1AC; the pong follows all the connection wrote before it
  // took the ping (pongs 1 and 3 are the actions' and the press loop's).
  let #(after_the_gain, have) =
    game_client.read_until_pong(game:, have:, number: 4)
  let fight = list.append(fight, after_the_gain)
  let assert [Frame(body: gain, ..)] =
    list.filter(fight, fn(frame) { frame.message_id == 0x01AC })
    as "the kill sends one 0x1AC"
  let assert Ok(gained) = experience_gained.decode(gain)
    as "the client's reader reads the 0x1AC"
  assert gained.source_kind == 2 && gained.source_unit_id == beast.unit_id
    as "opcode.0x1ac: kind 2, KillCreature, naming the Beast"
  assert gained.experience > 0 as "the kill gives experience"
  assert list.contains(
    game_client.fight_in(frames: fight),
    game_client.LevelIs(unit_id: own.unit_id, level: 2),
  )
    as "opcode.0x938: stat 10 of the player is 2, as the experience crosses level 2's minXpForLevel"
  // 10: camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert entry_stat(entry: second_entry, stat_id: 10) == 2
    as "opcode.0x262: the entry shows level 2"
  let assert [Frame(body: state_body, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x025E })
    as "the entry sends one 0x25E"
  let assert Ok(state) = player_character_state.decode(state_body)
    as "the client's reader reads the 0x25E"
  assert state.experience == experience_before + gained.experience
    as "opcode.0x25e: the experience the character had and the kill's 0x1AC gave"
  assert credits_in_entry(frames: second_entry)
    == credits_before_the_buy - 3 * stimpack_cost - bandage_lot_cost
    as "opcode.0x25e: the credits after the buy, the sale, the buy back and the lot"
  let held =
    list.map(item_bot.answer_in(frames: second_entry).added, fn(held) {
      held.item
    })
  let in_the_bags =
    list.filter_map(held, fn(item) {
      case item.location == 1 {
        True -> Ok(#(item.bag_index, item.item_id, item.stack_count))
        False -> Error(Nil)
      }
    })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  assert in_the_bags == [#(in_bags(bag_index: 7).bag_index, stimpack, 3)]
    as "one stack of 3 at the moved slot: the sold stack's slot is empty and the lot is deleted"
  assert list.any(held, fn(item) {
    item.location == chest_slot.location
    && item.bag_index == chest_slot.bag_index
    && item.item_id == chest.item_id
  })
    as "the chest is worn"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- a quest bot ----

/// Where the Exile Human starts: WorldLocation2 42074, World 426, WorldZone 648
/// (Northern Wilds), where the quest bot stands and never moves.
const exile_start = #(4098.16, -665.98, -5165.1)

/// A row of the spawn table for World 426 at an offset east (`dx`) and south (`dz`)
/// of the Exile start: the row of an object (entity type 10) or a creature (entity
/// type 0) the quest bot meets, as the planted rows of the other whole-server tests are
/// the test's own, not recorded.
fn northern_wilds_row(
  number number: Int,
  entity_type entity_type: Int,
  creature_id creature_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  faction_id faction_id: Int,
  dx dx: Float,
  dz dz: Float,
) -> spawn.Row {
  spawn.Row(
    ..spawn_support.beast_row(number:),
    entity_type:,
    creature_id:,
    world_id: 426,
    area_id: 648,
    x: exile_start.0 +. dx,
    y: exile_start.1,
    z: exile_start.2 +. dz,
    display_info_id:,
    outfit_info_id:,
    faction_id:,
    base_faction_id: faction_id,
  )
}

pub fn a_bot_accepts_uses_and_turns_in_a_northern_wilds_quest_takes_up_another_and_finds_both_after_a_relog_test() -> Nil {
  use <- owned_test.run(120_000)
  // Northern Wilds is the Exile start zone (World 426, WorldZone 35 of Quest2 3886 and
  // 3480). Creature2 11066 gives and receives quest 3886 (questIdGiven01, questIdReceive04),
  // which asks for one use of Creature2 13630 (QuestObjective 5053: type 12, count 1) and
  // three uses of the members of TargetGroup 1460, which is Creature2 13623 (5052: type 14,
  // count 3). Creature2 11061 gives quest 3480 (questIdGiven00), whose first objective asks
  // for three uses of Creature2 11070 (4470: type 12, count 3). Every Creature2 has the activate
  // spell 1817 with an activateSpellCastTime of 2000 ms; the activateSpellMaxRange is 5.0 for
  // 13630 and 11070 and 7.0 for 13623, and the reach to a giver is 6.0 between edges. Each is
  // planted within 4.5 of the Exile start. The giver's faction 171 is friendly to the
  // Exile's 167 (Faction2Relationship 771).
  let time = driven_time.new()
  let giver = 11_066
  let other_giver = 11_061
  let rows = [
    northern_wilds_row(
      number: 1,
      entity_type: 0,
      creature_id: giver,
      display_info_id: 22_825,
      outfit_info_id: 9065,
      faction_id: 171,
      dx: 0.0,
      dz: 4.0,
    ),
    northern_wilds_row(
      number: 2,
      entity_type: 0,
      creature_id: other_giver,
      display_info_id: 22_825,
      outfit_info_id: 9065,
      faction_id: 171,
      dx: 0.0,
      dz: -4.0,
    ),
    northern_wilds_row(
      number: 3,
      entity_type: 0,
      creature_id: 11_070,
      display_info_id: 24_086,
      outfit_info_id: 0,
      faction_id: 219,
      dx: 3.0,
      dz: 0.0,
    ),
    northern_wilds_row(
      number: 4,
      entity_type: 10,
      creature_id: 13_630,
      display_info_id: 23_147,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -3.0,
      dz: 0.0,
    ),
    northern_wilds_row(
      number: 5,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -2.0,
      dz: 3.0,
    ),
    northern_wilds_row(
      number: 6,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -3.0,
      dz: 3.0,
    ),
    northern_wilds_row(
      number: 7,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -4.0,
      dz: 3.0,
    ),
  ]
  let selection =
    spawn.select(
      rows:,
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor_support.stocking(creature_ids: []),
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the rows pass the spawn checks"
  let assert Ok(northern_wilds) = dict.get(selection.worlds, 426)
    as "World 426 has spawns"
  assert dict.size(northern_wilds.by_id) == 3
    && dict.size(northern_wilds.objects) == 4
    as "the three creatures (11066, 11061 and 11070) start and the four objects (13630 and the three 13623) are sent"
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in_with_objects(
            world_id: 426,
            spawns: dict.values(northern_wilds.by_id),
            objects: dict.values(northern_wilds.objects),
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 426,
    world_zone_id: 648,
    position: exile_start,
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(static_objects_created_in(frames:)) == 4
      && list.length(game_client.creatures_created_in(frames:)) == 3
    })
  let shown = game_client.creatures_created_in(frames: entry)
  let assert Ok(giving) =
    list.find(shown, fn(unit) { unit.creature_id == giver })
    as "the giver of 3886 is in sight"
  let assert Ok(other_giving) =
    list.find(shown, fn(unit) { unit.creature_id == other_giver })
    as "the giver of 3480 is in sight"
  let assert Ok(attacker) =
    list.find(shown, fn(unit) { unit.creature_id == 11_070 })
    as "Creature2 11070 is in sight"
  let objects = static_objects_created_in(frames: entry)
  let assert Ok(single) =
    list.find(objects, fn(object) { object.creature_id == 13_630 })
    as "the object of objective 5053 is in sight"
  let group =
    list.filter(objects, fn(object) { object.creature_id == 13_623 })
    |> list.sort(fn(a, b) { int.compare(a.checklist_index, b.checklist_index) })
  assert list.map(group, fn(object) { object.checklist_index }) == [0, 1, 2]
    as "opcode.0x262: the three objects of TargetGroup 1460 take the checklist indexes 0, 1 and 2, in spawn order"
  // 1: talks to the giver, which opens its dialog.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [giving.unit_id]
    as "opcode.0x357: the giver's dialog opens for its unit"
  // 2: mentions quest 3886, which carries Quest2 flag 0x400 (needs a mention: the client's
  // CanAcceptQuest refuses it with code 11 until the log holds a state of 4 to 7), then
  // accepts it.
  let #(_, have) = quest_bot.mention(game:, have:, quest_id: 3886)
  let #(accepted, have) = quest_bot.accept(game:, have:, quest_id: 3886)
  assert accepted.states
    == [QuestState(quest_id: 3886, state: 1, objective_id: 0)]
    as "opcode.0x35c: quest 3886 is Accepted"
  // 3: uses the object of objective 5053: the cast is confirmed, and its go after the
  // 2000 ms of activateSpellCastTime counts the objective.
  let #(pressed, have) =
    quest_bot.activate(game:, have:, client_cast_id: 1, unit_id: single.unit_id)
  assert list.length(pressed.confirmed) == 1
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(used, have) = quest_bot.went(game:, have:)
  assert used.progress
    == [QuestObjectiveProgress(quest_id: 3886, objective_index: 0, progress: 1)]
    as "opcode.0x361: objective 5053 of quest 3886, index 0, counts 1"
  assert used.states == [] as "the quest has an open objective left"
  // 4: uses the three objects of the group, in the order of their indexes: each go
  // counts its bit of the whole mask (opcode.0x361), and the third achieves the quest.
  let #(have, masks, last) =
    list.index_fold(group, #(have, [], used), fn(done, object, index) {
      let #(have, masks, _) = done
      let #(_, have) =
        quest_bot.activate(
          game:,
          have:,
          client_cast_id: 2 + index,
          unit_id: object.unit_id,
        )
      driven_time.advance(time:, ms: 2000)
      let #(went, have) = quest_bot.went(game:, have:)
      #(have, list.append(masks, went.progress), went)
    })
  assert masks
    == [
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 1),
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 3),
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 7),
    ]
    as "opcode.0x361: objective 5052 of quest 3886, index 1, carries the whole mask: bits 0, 1 and 2 set one by one"
  assert last.states == [QuestState(quest_id: 3886, state: 2, objective_id: 0)]
    as "opcode.0x35c: the third use achieves the quest"
  // 5: turns it in at its receiver with the choice the bot is offered. Of the three
  // choices of Quest2 3886 (Quest2Reward 2192, 2430 and 4767), `equip_requirement.offered`
  // allows a class 4 character with Class 4's startingItemProficiencies 260 only 2430,
  // which gives Item2 13332. The experience is the quest's conLevel 4 XpPerLevel
  // baseQuestXpPerLevel 152 times Quest2Difficulty 4's xpMultiplier 1.5 times the
  // LevelDifferentialAttribute of a difference of 3, 1.0: 228, short of the 655 level 2 asks for.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [giving.unit_id]
    as "opcode.0x357: the receiver's dialog opens"
  let #(turned, have) =
    quest_bot.turn_in(game:, have:, quest_id: 3886, reward_id: 2430)
  assert turned.experience
    == [
      experience_gained.ExperienceGained(
        experience: 228,
        rest_experience_used: 0,
        bonus_experience: 0,
        source_kind: 3,
        source_unit_id: 0,
      ),
    ]
    as "opcode.0x1ac: kind 3, a quest, for 228"
  assert list.any(turned.added, fn(held) { held.item.item_id == 13_332 })
    as "the chosen reward, Item2 13332, is added"
  assert list.last(turned.states)
    == Ok(QuestState(quest_id: 3886, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest is Completed"
  assert list.contains(
    list.take_while(
      list.map(turned.frames, fn(frame) { frame.message_id }),
      fn(id) { id != quest_state.message_id },
    ),
    experience_gained.message_id,
  )
    as "the experience comes before the quest's state"
  // 6: takes up quest 3480 at its giver.
  let #(talked, have) =
    quest_bot.talk(game:, have:, unit_id: other_giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [other_giving.unit_id]
    as "opcode.0x357: the second giver's dialog opens"
  let #(accepted, have) = quest_bot.accept(game:, have:, quest_id: 3480)
  assert accepted.states
    == [QuestState(quest_id: 3480, state: 1, objective_id: 0)]
    as "opcode.0x35c: quest 3480 is Accepted, its exclusion 3479 not held"
  // 7: uses Creature2 11070 once, of the three objective 4470 asks for.
  let #(pressed_once, have) =
    quest_bot.activate(
      game:,
      have:,
      client_cast_id: 5,
      unit_id: attacker.unit_id,
    )
  assert list.length(pressed_once.confirmed) == 1
    as "opcode.0x7fd: the press at 11070 is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(once, have) = quest_bot.went(game:, have:)
  assert once.progress
    == [QuestObjectiveProgress(quest_id: 3480, objective_index: 0, progress: 1)]
    as "opcode.0x361: objective 4470 of quest 3480 counts 1 of 3"
  assert once.states == [] as "opcode.0x35c: the quest stays Accepted"
  // 8: camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(completed:, active:, ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f"
  assert list.map(completed, fn(done) { done.quest_id }) == [3886]
    as "opcode.0x35f: quest 3886 is among the completed"
  assert list.map(active, fn(entry) {
      #(entry.quest_id, entry.state, entry.progress)
    })
    == [#(3480, 1, [1, 0])]
    as "opcode.0x35f: only quest 3480 is active, Accepted with objective 0 at 1 and objective 1 at 0"
  game_client.close(game:)
  login_support.stop(started)
}

// The tutorial boss, Creature2 73499 (QuestObjective 21296 and 21310, type 2, count 1,
// marker 51744). Marker 51744 is at (429.29544, -388.88251, 253.77565) in World 3460,
// zone 5968 (`table_rows -- WorldLocation2 51744`), and a lone target stands at the
// marker's centre. The Creature2 row gives factionId 219, Friendly to both player
// factions, so the server stands it with faction 233, Hostile to the parent 165 of the
// Dominion 166 and the Exile 167 (Faction2Relationship 746, migration 0027). Quest 10520
// (Quest2 10520, questPlayerFactionEnum 0, the Exile's) holds the kill as its fourth
// objective, index 3 (Quest2 objective03 21296), and opens it once the objectives of
// index 0 and 2 are done (0x140553790: the objectives of index 1 and 4 hold flag 0x21
// and the visit's 0x3; the objective_test header gives the shape).

/// The boss's marker centre.
const marker_51744 = #(429.29544, -388.88251, 253.77565)

/// An Exile Medic of level 30 holding quest 10520 with the objectives of index 0 and 2 done,
/// played into World 3460 12 beyond the boss and facing it, and read until the
/// boss's 0x262 has arrived: the game, the burst's frames and the bytes beyond.
fn an_exile_medic_beside_the_boss(
  started started: login_support.Started,
) -> #(game_client.Game, List(Frame), BitArray) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 30,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile one (faction 167)"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10520, 1, 0, true, 5, '{3,0,1,0,0}', 0, '{0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10520 with the objectives of index 0 (21294) and 2 (21295) done, so the kill of index 3 is open"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 5968,
    position: #(marker_51744.0 +. 12.0, marker_51744.1, marker_51744.2),
  )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(game_client.creatures_created_in(frames:), fn(creature) {
        creature.creature_id == 73_499
      })
    })
  #(game, frames, have)
}

pub fn an_exile_kills_the_boss_and_objective_21296_counts_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have) = an_exile_medic_beside_the_boss(started:)
  let assert Ok(boss) =
    list.find(game_client.creatures_created_in(frames:), fn(creature) {
      creature.creature_id == 73_499
    })
    as "the boss is created for the Exile"
  assert is_near(
    left: game_client.placed_by_tail(tail: boss.tail),
    right: marker_51744,
  )
    as "opcode.0x262: a lone target stands at its marker's centre"
  assert boss.tail.faction_id == 233 && boss.tail.base_faction_id == 233
    as "opcode.0x262: the unit stands with faction 233, Hostile to the Exile's parent (Faction2Relationship 746)"
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(
      from: #(marker_51744.0 +. 12.0, marker_51744.2),
      target: #(marker_51744.0, marker_51744.2),
    ),
    clock: 100,
  )
  let assert Ok(#(killed, have)) =
    fight_bot.presses_until_the_target_dies(
      ability: fight_bot.paralytic_surge,
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: boss.unit_id,
      cast_id: 1,
      seen: [],
    )
  // The kill's credit comes from the creature after its death is written.
  let #(counted, _) = game_client.read_until_pong(game:, have:, number: 7)
  assert list.filter(list.append(killed, counted), fn(frame) {
      frame.message_id == 0x0361
    })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_520), #(32, 3), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the kill counts objective 21296, the fourth of quest 10520, once: 1 of 1"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- the Sim-Turrets of the Novice training simulation, on the whole server ----
//
// The world database stores the two Exile Sim-Turrets, Creature2 73494, as unit type 13
// rows 29178 and 29179 (`test/fixture/world_data_turrets`), 31.6 apart in World 3460 at
// (-105.661, -864.7596, 502.462) and (-112.69, -864.691, 470.817). Their stored factions
// are not read: migration 0029 stands them with faction 1441, Hostile to the Exile 167
// (Faction2Relationship 2943, level 0). Each charges Spell4 85469 (castTime 8000) every
// 3000 ms after its attack tick: the 0x7ff when the tick opens it, the 0x7f4 and the
// 0x7fe 8000 ms later. Objective 21288 (QuestObjective: type 2, count 2, data 73494,
// flags 0x203) is the fifth objective of quest 10518 (Quest2 objective04), so its
// progress is the 0x361 of index 4 (opcode.0x361), open once the four objectives
// before it are done (0x140553790, as `a_medic_at_the_marker_ring` holds). Paralytic
// Surge reaches 15 (Spell4 42352 targetMaxRange) and a creature's aggro range is 10
// (migration 0010).

/// The first stored turret, row 29178.
const turret_29178 = #(-105.661, -864.7596, 502.462)

/// The second stored turret, row 29179.
const turret_29179 = #(-112.69, -864.691, 470.817)

/// A world on the planted turret rows and the content load, on the clock `time`.
fn world_with_the_turrets(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_on(
    folder: "test/fixture/world_data_turrets",
    tables:,
    time:,
    tutorial: False,
  )
}

/// An Exile Medic of level 30 holding quest 10518 with its first four objectives done,
/// played into World 3460 at `at`, and read until the 0x262 of both turrets has
/// arrived (a player sees every unit within 1024, `sight.range`), and ready: the game,
/// the burst's frames and the bytes beyond.
fn an_exile_medic_near_the_turrets(
  started started: login_support.Started,
  at at: #(Float, Float, Float),
) -> #(game_client.Game, List(Frame), BitArray) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 30,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile one (faction 167), which faction 1441 is hostile to"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10518, 1, 0, true, 15, '{5,1,1,1,0,0}', 0, '{0,0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10518 with the objectives of index 0 to 3 done, so the turrets' of index 4 is open"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 5967,
    position: at,
  )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(turrets_in(frames:)) >= 2
    })
  // Ready: the client's first 0xF2 (`terrain_loaded`), which puts the player in the rings.
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: 5967))
  game_client.send_world(game:, message_id: terrain_loaded.message_id, body:)
  #(game, frames, have)
}

/// The Sim-Turrets (Creature2 73494) the frames create, as the client reads them.
fn turrets_in(
  frames frames: List(Frame),
) -> List(unit_create_static.UnitCreateStatic) {
  list.filter(static_objects_created_in(frames:), fn(object) {
    object.creature_id == 73_494
  })
}

/// The unit of the turret the frames create at `place`.
fn the_turret_at(
  frames frames: List(Frame),
  place place: #(Float, Float, Float),
) -> Int {
  let assert Ok(turret) =
    list.find(turrets_in(frames:), fn(turret) {
      is_near(left: game_client.placed_by_tail(tail: turret.tail), right: place)
    })
    as "a Creature2 73494 stands at the place of its stored row"
  turret.unit_id
}

/// How many presses fit in the 15000 ms opening after the press that interrupts, each
/// 2700 ms after the last (`fight_bot.paralytic_surge_lingers_ms`): the presses at 2700 to 13500 ms.
const presses_in_the_opening = 5

/// Runs the body on the client's rows with Paralytic Surge's recharge taken off (as
/// `on_rows_without_paralytic_surges_recharge`) and the Sim-Turrets' deflect taken off: their
/// base deflect chance is 0.016 (CreatureLevel row 101 0.05 times Creature2Difficulty 1's
/// multiplier 101 of 0.32, as `Creature2.73464.crit_deflect_glance` has it), and the
/// presses the opening holds are only enough to destroy a turret when none of them deflects.
fn on_rows_with_turrets_that_never_deflect(
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: 42_352,
      with: [#("spellCoolDown", planted_table.Integer(0))],
    )
    as "Spell4 42352 holds the column spellCoolDown"
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Creature2Difficulty", id: 1, with: [
      #("unitPropertyMultiplier101", planted_table.Float(0.0)),
    ])
    as "Creature2Difficulty 1, the Sim-Turret's difficulty, holds the column unitPropertyMultiplier101"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The medic walks to 8 beyond the turret at `place`, inside its aggro range, faces it and waits
/// for its charge to open; presses Paralytic Surge once, whose stun breaks the charge, and
/// presses on within the 15 s of the opening until the turret is destroyed. It checks the
/// wire of the interrupt on the way and gives every frame read and the bytes beyond.
fn interrupts_and_destroys(
  started started: login_support.Started,
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  turret turret: Int,
  own own: Int,
  guard_cast guard_cast: Int,
  place place: #(Float, Float, Float),
  clock clock: Int,
  cast_id cast_id: Int,
) -> #(List(Frame), BitArray) {
  let stands = #(place.0 +. 8.0, place.1, place.2)
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: clock, commands: [
      game_client.position_command(x: stands.0, y: stands.1, z: stands.2),
    ]),
  )
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(stands.0, stands.2), target: #(
      place.0,
      place.2,
    )),
    clock: clock + 100,
  )
  let #(aggroed, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
      )
    })
  // The attack tick, 3000 ms after the aggro, opens the charge.
  driven_time.advance(time:, ms: 3000)
  let #(opened, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_469,
      )
      != []
    })
  let assert [#(charge_cast, charger)] =
    game_client.starts_of(
      events: game_client.casts_in(frames: opened),
      spell4_id: 85_469,
    )
    as "the tick opens the charge with one 0x7ff of Spell4 85469"
  assert charger == turret
  // The press: Paralytic Surge's damage takes nothing from the guarded turret and its stun
  // (Spell4Effects 96126, 2700 ms) breaks the charge.
  character_support.marker_creature_settled(
    settings: started.settings,
    unit_id: turret,
  )
  game_client.press_ability(
    game:,
    client_cast_id: cast_id,
    bag_index: 2,
    target: 0,
  )
  // The connection's pong orders only its own input, not the creature's sends, so the
  // read waits for every message the assertions below name: the broken charge's 0x7fe, the
  // opening's 0x7ff, the guard's 0x811, the states' 0x87f and the press's 0x247 immunity.
  // The turret sends its news to the connection before it answers the strike, and a process's
  // messages to another arrive in the order sent, so a health the press took would be read
  // before the immunity the answer makes.
  let immunity =
    Frame(
      message_id: 0x0247,
      body: message_support.packed([
        #(6, 18),
        #(32, own),
        #(32, turret),
        #(18, 42_352),
        #(4, 2),
      ]),
    )
  // The interrupt line (type 19, `opcode.0x247.interrupted`): Paralytic Surge 42352 as the
  // interrupting spell, result 11 (SpellInterrupted), the medic as the caster, the turret
  // as the unit interrupted, the charge's Spell4 85469 and the combat result Hit (2).
  let interrupt =
    Frame(
      message_id: 0x0247,
      body: message_support.packed([
        #(6, 19),
        #(18, 42_352),
        #(9, 11),
        #(32, own),
        #(32, turret),
        #(18, 85_469),
        #(4, 2),
      ]),
    )
  let #(interrupted, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.casts_in(frames:),
        game_client.CastFinished(cast_id: charge_cast),
      )
      && list.contains(frames, interrupt)
      && game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_472,
      )
      != []
      && list.contains(
        game_client.targets_removed_in(frames:),
        #(guard_cast, [turret]),
      )
      && list.any(frames, fn(frame) { frame.message_id == 0x087F })
      && list.contains(frames, immunity)
    })
  let events = game_client.casts_in(frames: interrupted)
  assert game_client.broken_casts_in(frames: interrupted)
    == [#(charge_cast, 11, turret)]
    as "opcode.0x7f9: the charge is broken with result 11 by the turret"
  assert list.contains(events, game_client.CastFinished(cast_id: charge_cast))
    as "opcode.0x7fe: the broken charge's 0x7fe follows"
  let assert [#(_, opener)] = game_client.starts_of(events:, spell4_id: 85_472)
    as "Spell4 85472, the opening, starts once"
  assert opener == turret as "cast by the turret"
  assert game_client.targets_removed_in(frames: interrupted)
    == [#(guard_cast, [turret])]
    as "opcode.0x811: the guard's cast comes off the turret"
  assert !list.any(game_client.health_in(frames: interrupted), fn(health) {
    health.0 == turret
  })
    as "the guarded turret took no damage from the press"
  assert list.contains(interrupted, immunity)
    as "opcode.0x247.immunity: the press's striker is shown the turret's immunity, type 18 with Spell4 42352"
  assert list.any(interrupted, fn(frame) { frame.message_id == 0x087F })
    as "opcode.0x87f: the states of the stun and the opening are told"
  assert list.filter(interrupted, fn(frame) { frame == interrupt })
    == [interrupt]
    as "opcode.0x247.interrupted: the stun's striker is shown the interrupt line once, type 19 with Spell4 42352 interrupting the charge 85469"
  // The opening lasts 15000 ms on the clock from the interrupting press, and a press's hit
  // lingers 2700 ms before the next (Spell4Effects 96126), so the presses at 2700, 5400,
  // 8100, 10800 and 13500 ms fit in it and a sixth, at 16200, would find the guard back.
  // The turret never deflects (`on_rows_with_turrets_that_never_deflect`), so the five presses
  // all hit, whatever the connection's rolls are, and the kill below tells whether their
  // damage takes the turret's health.
  driven_time.advance(time:, ms: fight_bot.paralytic_surge_lingers_ms)
  let #(lingered, have) = game_client.read_until_pong(game:, have:, number: 2)
  let assert Ok(#(killed, have)) =
    fight_bot.presses_at_most(
      ability: fight_bot.paralytic_surge,
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: turret,
      cast_id: cast_id + 1,
      seen: [],
      presses: presses_in_the_opening,
    )
  let seen = list.flatten([aggroed, opened, interrupted, lingered, killed])
  assert list.contains(game_client.deaths_in(frames: seen), #(turret, True))
    as "the opened turret takes the presses' damage and is destroyed within its 15 s"
  assert list.filter(seen, fn(frame) { frame == interrupt }) == [interrupt]
    as "no later press interrupts anything: the one line is the stun's"
  #(seen, have)
}

pub fn an_exile_interrupts_and_destroys_both_sim_turrets_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started = world_with_the_turrets(tables:, time:)
  // Enters 14 beyond the first turret, outside its aggro range 10.
  let enters = #(turret_29178.0 +. 14.0, turret_29178.1, turret_29178.2)
  let #(game, frames, have) =
    an_exile_medic_near_the_turrets(started:, at: enters)
  let first = the_turret_at(frames:, place: turret_29178)
  let second = the_turret_at(frames:, place: turret_29179)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let #(arrived, have) = game_client.read_until_pong(game:, have:, number: 1)
  let guards =
    game_client.starts_of(
      events: game_client.casts_in(frames: list.append(frames, arrived)),
      spell4_id: 85_474,
    )
  let assert Ok(#(first_guard, _)) =
    list.find(guards, fn(guard) { guard.1 == first })
    as "Spell4 85474, the guard, is cast by each turret on arrival: the first's"
  let assert Ok(#(second_guard, _)) =
    list.find(guards, fn(guard) { guard.1 == second })
    as "and the second's"
  let #(first_seen, have) =
    interrupts_and_destroys(
      started:,
      time:,
      game:,
      have:,
      turret: first,
      own:,
      guard_cast: first_guard,
      place: turret_29178,
      clock: 100,
      cast_id: 1,
    )
  // The kill's credit comes from the creature after its death is written.
  let #(first_counted, have) =
    game_client.read_until_pong(game:, have:, number: 7)
  let #(second_seen, have) =
    interrupts_and_destroys(
      started:,
      time:,
      game:,
      have:,
      turret: second,
      own:,
      guard_cast: second_guard,
      place: turret_29179,
      clock: 400,
      cast_id: 100,
    )
  let #(second_counted, _) =
    game_client.read_until_pong(game:, have:, number: 14)
  assert list.filter(
      list.flatten([first_seen, first_counted, second_seen, second_counted]),
      fn(frame) { frame.message_id == 0x0361 },
    )
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 4), #(32, 1)]),
      ),
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 4), #(32, 2)]),
      ),
    ]
    as "opcode.0x361: each destroyed turret counts objective 21288, the fifth of quest 10518: 1 of 2, then 2 of 2"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_charge_hits_a_player_who_stays_in_its_rectangle_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_turrets(tables:, time:)
  // Enters 14 beyond the first turret, outside its aggro range 10, then walks in to 8
  // beyond it: inside the range and 30 ahead of its charge's start.
  let enters = #(turret_29178.0 +. 14.0, turret_29178.1, turret_29178.2)
  let #(game, frames, have) =
    an_exile_medic_near_the_turrets(started:, at: enters)
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 100, commands: [
      game_client.position_command(
        x: turret_29178.0 +. 8.0,
        y: turret_29178.1,
        z: turret_29178.2,
      ),
    ]),
  )
  let turret = the_turret_at(frames:, place: turret_29178)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let health = entry_stat(entry: frames, stat_id: 0)
  let #(aggroed, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
      )
    })
  assert list.contains(
    game_client.fight_in(frames: aggroed),
    game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
  )
    as "0x908: the turret fights the player who walked into its aggro range"
  // The attack tick, 3000 ms after the aggro, opens the charge.
  driven_time.advance(time:, ms: 3000)
  let #(opened, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_469,
      )
      != []
    })
  let assert [#(cast_id, caster_unit_id)] =
    game_client.starts_of(
      events: game_client.casts_in(frames: opened),
      spell4_id: 85_469,
    )
    as "the tick opens the charge with one 0x7ff of Spell4 85469"
  assert caster_unit_id == turret as "opcode.0x7ff: the turret casts it"
  assert game_client.go_targets_in(frames: opened) == []
    as "the 8 s cast has not gone: no 0x7f4 yet"
  // Its cast time passes with the player in the rectangle, once the charge's own
  // timer is on the clock, which the advance's barrier waits for.
  driven_time.advance(time:, ms: 8000)
  let #(went, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.casts_in(frames:),
        game_client.CastFinished(cast_id:),
      )
      && game_client.own_health_of(
        events: game_client.fight_in(frames:),
        unit: own,
      )
      != []
    })
  assert game_client.go_targets_in(frames: went) == [#(cast_id, [own])]
    as "opcode.0x7f4: the go names the player inside the rectangle"
  let assert [game_client.Went(targets: [#(_, [blow])], ..)] =
    list.filter(game_client.fight_in(frames: went), fn(event) {
      case event {
        game_client.Went(cast_id: went_id, ..) -> went_id == cast_id
        game_client.Targeted(..)
        | game_client.Threatens(..)
        | game_client.InCombat(..)
        | game_client.LevelIs(..)
        | game_client.ShieldIs(..)
        | game_client.InterruptArmorIs(..)
        | game_client.AbsorptionIs(..)
        | game_client.OwnHealthIs(..)
        | game_client.Moves(..)
        | game_client.Started(..)
        | game_client.HealthIs(..) -> False
      }
    })
    as "opcode.0x7f4: one go of the charge, with one damage effect for the player"
  // The strike's crit roll is from the connection's random seed, so the blow is a
  // critical hit or not by chance: 400 when not, and 400 x the turret's critical
  // severity when it is. The severity is property 127 at rating 0: CreatureLevel.101
  // unitPropertyValue27 1.5 x Creature2Tier.1 multiplier 0.85 (Creature2 73494, tier 1;
  // `GetCreatureProperty`, `0x1404585c0`), to which GameFormula 1232 adds nothing at
  // rating 0 (intercept 0, `0x140463e80`): 1.275.
  let expected_raw = case blow.critical {
    True -> 510
    False -> 400
  }
  assert blow.effect_id == 224_644 && blow.raw_damage == expected_raw
    as "Spell4Effects 224644: the charge deals the player 400, or 510 (400 x 1.275) when the 0x7f4's combat result is a critical hit"
  // The blow after the glance and the mitigation and absorbs is `adjusted`; the shield
  // takes 0.625 of it (ShieldMitigationMax, property 175,
  // `player.level1_gear_properties`, rounded as `hit.apply` rounds), which the
  // shield held (`entry_stat` 20) covers, and the health takes the rest.
  let adjusted = blow.raw_damage - blow.glance - blow.absorbed
  assert blow.shield_absorbed == float.round(int.to_float(adjusted) *. 0.625)
    as "opcode.0x7f4: the shield takes 0.625 of the adjusted blow"
  assert blow.shield_absorbed <= entry_stat(entry: frames, stat_id: 20)
    as "the shield held what it took"
  let assert [_, ..] as healths =
    game_client.own_health_of(
      events: game_client.fight_in(frames: went),
      unit: own,
    )
    as "opcode.0x92f: the charge's go gives the player's health"
  let assert Ok(now) = list.last(healths)
    as "the last health is the one that stands"
  assert health - now == adjusted - blow.shield_absorbed
    as "opcode.0x92f: the health loses the adjusted blow less the shield's share"
  assert blow.health_damage == adjusted - blow.shield_absorbed
    as "opcode.0x7f4: the description's health damage is the same"
  assert list.any(
    game_client.shield_of(events: game_client.fight_in(frames: went), unit: own),
    fn(shield) { shield < entry_stat(entry: frames, stat_id: 20) },
  )
    as "opcode.0x938: the shield falls with the blow"
  game_client.close(game:)
  login_support.stop(started)
}

/// The quest rows the store holds for the character: each quest and its state, by quest.
fn quest_rows(
  pool pool: pog.Connection,
  character_id character_id: Int,
) -> List(#(Int, Int)) {
  let assert Ok(returned) =
    pog.query(
      "select quest_id, state::int from character_quest where character_id = $1 order by quest_id",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.returning({
      use quest_id <- decode.field(0, decode.int)
      use state <- decode.field(1, decode.int)
      decode.success(#(quest_id, state))
    })
    |> pog.execute(pool)
    as "the quest rows read"
  returned.rows
}

/// Creates the medic "Zed Qu" on the account of `insert_jim` and plays it into the
/// tutorial world: the connection, the created result, and the entry's frames up to its
/// 0x01BC and its 0x035C, with the bytes beyond them.
fn enter_the_tutorial(
  started: login_support.Started,
) -> #(
  game_client.Game,
  create_character_result.CreateCharacterResult,
  List(Frame),
  BitArray,
) {
  let account = AccountId(login_support.insert_jim(started))
  let game =
    in_select(started:, port: login_support.ports(started).game_port, account:)
  game_client.send_create(
    game:,
    body: character_support.medic_create_request("Zed Qu"),
  )
  let created = created_result(game)
  assert created.result == create_result.CreateOk
    as "opcode.0xdc: a valid request is created"
  send_play(game:, character_id: created.character_id)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.any(frames, fn(frame) { frame.message_id == 0x035C })
    })
  #(game, created, entry, have)
}

pub fn a_bot_creates_an_exile_and_plays_the_tutorial_to_the_northern_wilds_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started =
    world_on(
      folder: "test/fixture/world_data_tutorial_path",
      tables:,
      time:,
      tutorial: True,
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, created, entry, have) = enter_the_tutorial(started)
  let entry_ids = list.map(entry, fn(frame) { frame.message_id })
  assert list.filter(entry_ids, fn(id) { id == 0x035F || id == 0x035C })
    == [0x035F, 0x035C]
    as "opcode.0x35f.entry_order: the log, then the one grant after it"
  assert bot_frames.decoded(entry, quest_state.message_id, quest_state.decode)
    == [QuestState(quest_id: 10_513, state: 1, objective_id: 0)]
    as "opcode.0x35c.add_unaccepted: the entry into World 3460 gives 10513 in state 1"
  let assert Ok(played) =
    tutorial_bot.play(
      game:,
      have:,
      entry:,
      env: tutorial_bot.Env(
        advance: fn(ms) { driven_time.advance(time:, ms:) },
        recharge_ms: 0,
        settled: fn(unit_id) {
          character_support.marker_creature_settled(
            settings: started.settings,
            unit_id:,
          )
        },
      ),
    )
    as "the bot plays every step of the tutorial's path"
  let states =
    bot_frames.decoded(
      played.frames,
      quest_state.message_id,
      quest_state.decode,
    )
  assert list.filter_map(states, fn(told) {
      case told.state {
        3 -> Ok(told.quest_id)
        _ -> Error(Nil)
      }
    })
    == [10_513, 10_527, 10_518, 10_529, 10_525, 10_540, 10_519, 10_520]
    as "Quest2's chain from 10513: each quest is Completed in the order the path gives it, the chain's by the server and the turn-ins at 73421, Dorian 73491 and 74812"
  let progress =
    bot_frames.decoded(
      played.frames,
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    )
  assert list.contains(
      progress,
      QuestObjectiveProgress(quest_id: 10_528, objective_index: 1, progress: 1),
    )
    && list.contains(
      progress,
      QuestObjectiveProgress(quest_id: 10_528, objective_index: 2, progress: 1),
    )
    && list.contains(
      states,
      QuestState(quest_id: 10_528, state: 2, objective_id: 0),
    )
    as "Quest2 10528: the yes at Departures Terminal 73606 counts the travel (index 1) and the Northern Wilds choice (index 2), and the quest is Achieved"
  let assert [entered, ..] =
    list.reverse(bot_frames.decoded(
      played.frames,
      enter_world.message_id,
      enter_world.decode,
    ))
    as "the landing's 0xAD"
  assert entered.world_id == 426
    && entered.position_x == float32.to_bits(4098.16015625)
    && entered.position_y == float32.to_bits(-665.9780883789062)
    && entered.position_z == float32.to_bits(-5165.10009765625)
    as "WorldLocation2 42074, the landing of Departures Terminal 73606: world 426 at (4098.16015625, -665.9780883789062, -5165.10009765625)"
  // The quest log is saved with the player when the save timer fires.
  driven_time.advance(time:, ms: movement.save_period_ms)
  event_wait.until("the store holds the quest log the bot played", fn() {
    quest_rows(pool:, character_id: created.character_id)
    == [
      #(10_513, 3),
      #(10_518, 3),
      #(10_519, 3),
      #(10_520, 3),
      #(10_525, 3),
      #(10_527, 3),
      #(10_528, 2),
      #(10_529, 3),
      #(10_540, 3),
    ]
  })
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_use_of_dorian_leaves_him_in_place_and_10525_is_taken_from_him_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started =
    world_on(
      folder: "test/fixture/world_data_tutorial_path",
      tables:,
      time:,
      tutorial: True,
    )
  let #(game, _, entry, have) = enter_the_tutorial(started)
  let assert Ok(bot) =
    tutorial_bot.play_to_the_dorians(
      game:,
      have:,
      entry:,
      env: tutorial_bot.Env(
        advance: fn(ms) { driven_time.advance(time:, ms:) },
        recharge_ms: 0,
        settled: fn(unit_id) {
          character_support.marker_creature_settled(
            settings: started.settings,
            unit_id:,
          )
        },
      ),
    )
    as "the bot plays the tutorial to the Dorians"
  let dorian_creature = 73_491
  let assert Ok(#(giver_a, at_a)) =
    tutorial_bot.nearest(
      units: tutorial_bot.units(bot:),
      from: tutorial_bot.at(bot:),
      creatures: [dorian_creature],
    )
    as "a Dorian is in sight"
  let bot = tutorial_bot.approach_unit(bot:, at: at_a)
  let #(used, have) =
    quest_bot.use_unit(game:, have: tutorial_bot.have(bot:), unit_id: giver_a)
  assert list.contains(
    used.states,
    QuestState(quest_id: 10_529, state: 3, objective_id: 0),
  )
    as "the use of Dorian completes 10529"
  // The map's removal of a released unit is not ordered against the client's answers, so
  // this test cannot prove that none comes; that Dorian is not released is decided by
  // `objective_release_test`. Here the tutorial goes on with the Dorian the player used.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giver_a)
  assert talked.dialogs != [] as "the Dorian the use counted opens his dialog"
  let #(accepted, _) = quest_bot.accept(game:, have:, quest_id: 10_525)
  assert list.map(accepted.states, fn(told) { #(told.quest_id, told.state) })
    == [#(10_525, 1)]
    as "quest.in_reach: the Dorian the use counted gives 10525 in state 1"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_spellslinger_over_a_socket_casts_surged_quick_draw_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 7,
      level: 1,
    )
  send_play(game:, character_id: character)
  let #(_, have) = game_client.read_entry_kept(game:, have: <<>>)
  // Spell Surge is the Spellslinger's innate, the bag's index 3 after the three level-1
  // abilities, and Quick Draw its first, index 0 (SpellLevel rows of class 7).
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 3, target: 0)
  let #(surge, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: surge,
    client_cast_id: 1,
  ))
    as "opcode.0x7fd: the press of Spell Surge is accepted"
  driven_time.advance(time:, ms: 3000)
  game_client.press_ability(game:, client_cast_id: 2, bag_index: 0, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 2)
  driven_time.advance(time:, ms: 1500)
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 3)
  let frames = list.append(pressed, later)
  assert result.is_ok(game_client.confirmed_cast_of(frames:, client_cast_id: 2))
    as "opcode.0x7fd: the Quick Draw press is accepted"
  let roots =
    list.map(
      bot_frames.decoded(frames, spell_started.message_id, spell_started.decode),
      fn(started) { started.root_spell4_id },
    )
  assert list.contains(roots, 76_002) && !list.contains(roots, 43_468)
    as "CastAbilityBagSpell 0x14039a040 under a node of 47439: the child casts name Quick Draw's alternate 76002 as their root, and none name 43468 (opcode.0x7ff.root_spell4_id)"
  assert list.take(
      list.filter_map(
        bot_frames.decoded(
          frames,
          unit_float_stat_changed.message_id,
          unit_float_stat_changed.decode,
        ),
        fn(changed) {
          case changed.stat_id == 6 {
            True -> Ok(changed.value)
            False -> Error(Nil)
          }
        },
      ),
      1,
    )
    == [float32.to_bits(75.0)]
    as "opcode.0x935: 76002's innate cost (19, 25) takes 25 from the Spellslinger's 100 Spell Power (stat 6, slot 4); the writes after it are the slot refilling over time (class_resource, `Over time`)"
  game_client.close(game:)
  login_support.stop(started)
}

/// The creature of this Creature2 that stands at the x and z of the place, within 0.01.
fn creature_standing_at(
  creatures creatures: List(unit_create_creature.UnitCreateCreature),
  creature_id creature_id: Int,
  place place: #(Float, Float),
) -> Result(unit_create_creature.UnitCreateCreature, Nil) {
  list.find(creatures, fn(creature) {
    let #(x, _, z) = game_client.placed_by_tail(tail: creature.tail)
    creature.creature_id == creature_id
    && float.absolute_value(x -. place.0) <. 0.01
    && float.absolute_value(z -. place.1) <. 0.01
  })
}

pub fn rescuing_an_exile_removes_the_trap_and_the_exile_for_another_player_too_then_both_return_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's objective 9659 (QuestObjective: type 12, data Creature2 27768, the
  // Bramble Trap, count 4) is credited by the go of a use of a trap, which the creature's
  // activateSpellCastTime of 2000 ms and activateSpellMaxRange of 3.0 allow. The world
  // data's rows 10449, 10451, 10453 and 10454 are four of its traps (so the objective
  // counts each unit once, not the same unit again), and rows 10603 to 10606 are the
  // Trapped Mordesh (Creature2 28112) that stand at the traps' x and z, 0.2 to 0.9 below
  // them. The use releases the trap and the Mordesh together, and 30000 ms later both are
  // back (a server choice, `used_object_release_ms`). Another player in sight is told 0x355
  // for both and 0x262 for both again.
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_nature",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(first, first_character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let #(second, second_character) =
    new_player_at_level(
      started:,
      number: 2,
      character_name: "Ann Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 6296, 1, 0, true, 0, '{0,0,0}', 0, '{0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(first_character))
    |> pog.execute(pool)
    as "the first character holds quest 6296 with nothing done"
  // The trap of row 10451 and the Mordesh of row 10604 stand at this x and z.
  let place = #(-467.3149, -2775.65)
  character_support.move_to(
    pool:,
    character_id: first_character,
    world_id: 990,
    world_zone_id: 1415,
    position: #(-465.8149, -991.1788, -2775.65),
  )
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 990,
    world_zone_id: 1415,
    position: #(-467.3149, -991.1788, -2767.65),
  )
  let both_in = fn(frames) {
    let creatures = game_client.creatures_created_in(frames:)
    result.is_ok(creature_standing_at(creatures:, creature_id: 27_768, place:))
    && result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 28_112,
      place:,
    ))
  }
  send_play(game: first, character_id: first_character)
  let #(first_entry, first_have) =
    game_client.read_until(game: first, have: <<>>, found: both_in)
  send_play(game: second, character_id: second_character)
  let #(second_entry, second_have) =
    game_client.read_until(game: second, have: <<>>, found: both_in)
  let seen = fn(frames) {
    let creatures = game_client.creatures_created_in(frames:)
    let assert Ok(trap) =
      creature_standing_at(creatures:, creature_id: 27_768, place:)
    let assert Ok(mordesh) =
      creature_standing_at(creatures:, creature_id: 28_112, place:)
    #(trap.unit_id, mordesh.unit_id)
  }
  let #(trap, mordesh) = seen(first_entry)
  assert seen(second_entry) == #(trap, mordesh)
    as "both players are shown the same units for the trap and the Mordesh"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(client_cast_id: 1, target_unit_id: trap))
    as "the right-click fits the message"
  game_client.send_world(
    game: first,
    message_id: cast_activate.message_id,
    body: press,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press on the trap is confirmed"
  // The bar runs 2000 ms (Creature2 27768's activateSpellCastTime), and the spell the trap
  // casts for a character at the start of the quest is Spell4 33673 of Spell4Base 19657,
  // castMethod 5: its go waits for the client's answer, which names the base plus one.
  let assert Ok(confirmed) =
    list.find(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "the confirmation of the press"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  driven_time.advance(time:, ms: 2000)
  let assert Ok(answer) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id: confirmed.server_cast_id,
      result: interaction_result.Succeeded,
      spell4_base_id_plus_one: 19_658,
    ))
    as "the answer fits the message"
  game_client.send_world(
    game: first,
    message_id: client_side_interaction_result.message_id,
    body: answer,
  )
  let removed_units = fn(frames) {
    game_connection_support.decoded(frames, 0x0355, unit_destroyed.decode)
    |> list.map(fn(destroyed) { destroyed.unit_id })
  }
  let gone = fn(frames) {
    let removed = removed_units(frames)
    list.contains(removed, trap) && list.contains(removed, mordesh)
  }
  let #(went, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      gone(frames) && list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 6296), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the use counts one of objective 9659's four, in quest 6296"
  let #(seen_gone, second_have) =
    game_client.read_until(game: second, have: second_have, found: gone)
  assert list.sort(removed_units(seen_gone), int.compare)
    == list.sort([trap, mordesh], int.compare)
    as "opcode.0x355: the player who did not use the trap is told the trap and the Mordesh are gone, each once"
  // The restart timer is the release's 30000 ms, started when the units went.
  driven_time.advance(time:, ms: 30_000)
  let #(back, _) =
    game_client.read_until(game: second, have: second_have, found: both_in)
  let creatures = game_client.creatures_created_in(frames: back)
  assert result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 27_768,
      place:,
    ))
    && result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 28_112,
      place:,
    ))
    as "opcode.0x262: the trap and the Mordesh are created again for the other player after the release time"
  let #(first_back, _) =
    game_client.read_until(game: first, have: first_have, found: both_in)
  assert both_in(first_back)
    as "opcode.0x262: the player who used the trap is shown both again as well"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

// ---- a timed item runs out ----

/// The guid and time left of each 0x111 in the frames that adds an item of this Item2.
fn time_left_of(
  frames frames: List(Frame),
  item2_id item2_id: Int,
) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == item_added.message_id {
      True -> {
        let assert Ok(added) = item_added.decode(frame.body)
          as "the 0x111 decodes"
        let item = added.held_item.item
        case item.item_id == item2_id {
          True -> Ok(#(item.item_guid, item.time_left_ms))
          False -> Error(Nil)
        }
      }
      False -> Error(Nil)
    }
  })
}

/// The guid and reason of each 0x148 in the frames.
fn removed_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == item_removed.message_id {
      True -> {
        let assert Ok(removed) = item_removed.decode(frame.body)
          as "the 0x148 decodes"
        Ok(#(removed.item_guid, removed.reason))
      }
      False -> Error(Nil)
    }
  })
}

/// How many rows of the Item2 the character holds, read straight from the table.
fn rows_of_item(
  pool pool: pog.Connection,
  character_id character_id: Int,
  item2_id item2_id: Int,
) -> Int {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query(
      "select count(*)::int from character_item where character_id = $1 and item2_id = $2",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.parameter(pog.int(item2_id))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pool)
    as "the rows were counted"
  count
}

/// A timed item counts down in real time, also while its owner is logged out: on the driven clock, one item runs out a minute
/// after the entry while the player is in the world, and the other while the player is away.
/// The entry sends each its time left (`opcode.0x111.time_left`); the one in the world is
/// removed with 0x148 reason 26 at its moment and not before (`opcode.0x148.expired`), its row
/// goes, and an item whose moment passed while the player was away is gone at the next entry.
pub fn a_timed_item_is_removed_at_its_moment_and_one_that_ran_out_while_away_is_gone_at_entry_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  // Item2 12402 (a single item) and 14838 (a stack) are rows of the client's tables; the
  // moments are 60,000 and 100,000 ms after the clock's time now.
  let now_unix_ms = step.unix_milliseconds(now: driven_time.now(time:))
  let put = fn(item2_id, bag_index, moment) {
    let assert Ok(_) =
      pog.query(
        "insert into character_item (character_id, item2_id, location, bag_index, stack_count, charges, expires_at_unix_ms) values ($1, $2, 1, $3, 1, 0, $4)",
      )
      |> pog.parameter(pog.int(character))
      |> pog.parameter(pog.int(item2_id))
      |> pog.parameter(pog.int(bag_index))
      |> pog.parameter(pog.int(moment))
      |> pog.execute(pool)
      as "the timed item is stored"
    Nil
  }
  put(12_402, 0, now_unix_ms + 60_000)
  put(14_838, 1, now_unix_ms + 100_000)
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert list.map(time_left_of(frames: entry, item2_id: 12_402), fn(sent) {
      sent.1
    })
    == [60_000]
    as "the entry sends the first item's time to its moment"
  assert list.map(time_left_of(frames: entry, item2_id: 14_838), fn(sent) {
      sent.1
    })
    == [100_000]
    as "and the second's"
  let assert [#(guid, _)] = time_left_of(frames: entry, item2_id: 12_402)
  // One millisecond before its moment nothing is removed.
  driven_time.advance(time:, ms: 59_999)
  let #(early, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert removed_in(frames: early) == []
    as "the client is told nothing before the moment"
  // At its moment the item is removed, as a delete is, with the reason Expired.
  driven_time.advance(time:, ms: 1)
  let #(due, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      removed_in(frames:) != []
    })
  assert removed_in(frames: due) == [#(guid, 26)]
    as "opcode.0x148.expired: 0x148 for the item with the reason 26"
  assert rows_of_item(pool:, character_id: character, item2_id: 12_402) == 0
    as "the store deleted its row"
  // The player camps; the second item's moment passes while it is away.
  game_client.send_world(game:, message_id: 0x00BF, body: <<1>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0092)
  game_client.send_world(game:, message_id: 0x00C0, body: <<>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0594)
  driven_time.advance(time:, ms: 600_000)
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0117)
  send_play(game:, character_id: character)
  let #(second_entry, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert time_left_of(frames: second_entry, item2_id: 14_838) == []
    as "the second item ran out while its owner was away, so the entry does not send it"
  assert rows_of_item(pool:, character_id: character, item2_id: 14_838) == 0
    as "and its row is gone"
  game_client.close(game:)
  login_support.stop(started)
}

/// The cast id of the cast of `spell4_id` that the frames both start and send the go of, and
/// the unit its start names as caster.
fn started_and_gone(
  frames frames: List(Frame),
  spell4_id spell4_id: Int,
) -> Result(#(Int, Int), Nil) {
  let events = game_client.casts_in(frames:)
  use #(cast_id, caster) <- result.try(
    list.first(game_client.starts_of(events:, spell4_id:)),
  )
  case
    list.any(events, fn(event) {
      event == game_client.CastWent(cast_id:, phase: 0)
    })
  {
    True -> Ok(#(cast_id, caster))
    False -> Error(Nil)
  }
}

/// The ids of the frames of one cast: the start, the go, the removal of its nodes and the
/// finish, which each begin with the cast id in 32 bits.
fn frames_of_cast(
  frames frames: List(Frame),
  cast_id cast_id: Int,
) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id, frame.body {
      0x07FF, <<id:32-little, _:bits>>
      | 0x07F4, <<id:32-little, _:bits>>
      | 0x0811, <<id:32-little, _:bits>>
      | 0x07FE, <<id:32-little, _:bits>>
      | 0x07FD, <<_:32-little, id:32-little, _:bits>>
        if id == cast_id
      -> Ok(frame.message_id)
      _, _ -> Error(Nil)
    }
  })
}

/// A Medic of level 3 one experience short of level 4 kills the creature at ring slot 0 in
/// sight of a second player and, as the client does 2000 ms after the rise, asks for the
/// fanfare of level 4 with 0x07A5: it is answered with the start and the go of Spell4 77409,
/// Level Up tier 3 (`Spell4.tierIndex.level_up`), which lists its own unit with the tier's one
/// effect row 202345, with no 0x07FD (that answers a press), and both players read the 0x07FE
/// of that cast 5000 ms after the go, the effect's life (`spell.level_up.cast`).
/// A Replay of level 2 is answered with Spell4 77398, and a level above the player's ends the
/// connection, which the second player reads as a leave. The full-screen text, the announcer's
/// voice and the "Level Up!" box are the client's own drawing and are not observable here. The
/// clock is driven and nothing waits on real time.
pub fn a_level_ups_0x07a5_is_answered_with_the_level_up_cast_and_a_player_in_sight_reads_the_same_cast_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(first, frames, first_have, _) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  let first_unit = game_client.unit_create_player_in(frames:).unit_id
  // A second player stands 14 units beyond the first, in sight of it.
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let slot = ring_slot(index: 0)
  let #(second, second_character) =
    new_player_at_level(
      started:,
      number: 2,
      character_name: "Ab Cd",
      class_id: 4,
      level: 9,
    )
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: #(slot.0 +. 14.0, slot.1, slot.2),
  )
  send_play(game: second, character_id: second_character)
  let #(_, second_have) =
    game_client.read_until(game: second, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) {
        frame.message_id == 0x0262
        && case game_client.created_unit(body: frame.body) {
          Ok(game_client.PlayerCreated(unit:)) -> unit.unit_id != first_unit
          _ -> False
        }
      })
    })
  let #(killed, first_have) =
    kills_the_target_at_slot_0(game: first, have: first_have, frames:, time:)
  let #(rest, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  assert list.any(list.append(killed, rest), fn(frame) {
    frame.message_id == 0x0938 && !is_other_stat(frame:)
  })
    as "the kill raised the level to 4 (opcode.0x938), as the 0x07A5 of the fanfare follows it"
  // The client's fanfare asks 2000 ms after the rise; the clock is driven, so the test
  // does not wait.
  game_client.replay_level_up(game: first, level: 4)
  let #(answered, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_409))
    })
  let assert Ok(#(cast_id, caster)) =
    started_and_gone(frames: answered, spell4_id: 77_409)
  assert caster == first_unit
    as "opcode.0x7ff: the cast is the player's own, started on the player's unit"
  assert frames_of_cast(frames: answered, cast_id:) == [0x07FF, 0x07F4]
    as "spell.level_up.cast: the start and the go, and no 0x07FD (it answers a press)"
  assert game_client.go_targets_in(frames: answered)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [first_unit])]
    as "opcode.0x7f4: the go names the player's own unit"
  let assert [go_frame] =
    list.filter(answered, fn(frame) {
      frame.message_id == 0x07F4
      && case frame.body {
        <<id:32-little, _:bits>> -> id == cast_id
        _ -> False
      }
    })
  let assert Ok(go) = spell_go.decode(go_frame.body)
  let assert [info] = go.targets
  assert list.map(info.effects, fn(effect) { effect.spell4_effects_id })
    == [level_up_support.tier(level: 4).effect_id]
    as "Spell4Effects 202345, the one row of tier 3 (Spell4.tierIndex.level_up)"
  let #(seen, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_409))
    })
  let assert Ok(#(seen_id, seen_caster)) =
    started_and_gone(frames: seen, spell4_id: 77_409)
  assert seen_id == cast_id && seen_caster == first_unit
    as "a player in sight reads the same cast, started by the first player's unit"
  assert game_client.go_targets_in(frames: seen)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [first_unit])]
  assert frames_of_cast(frames: seen, cast_id:) == [0x07FF, 0x07F4]
    as "and no 0x07FD"
  // The effect's life is over 5000 ms after the go.
  driven_time.advance(time:, ms: 5000)
  let #(first_end, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.contains(frames_of_cast(frames:, cast_id:), 0x07FE)
    })
  assert frames_of_cast(frames: first_end, cast_id:) == [0x07FE]
    as "spell.level_up.cast: the finish, and nothing else of the cast"
  let #(second_end, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(frames_of_cast(frames:, cast_id:), 0x07FE)
    })
  assert frames_of_cast(frames: second_end, cast_id:) == [0x07FE]
    as "a player in sight reads the same end"
  // A Replay of level 2 is answered with the tier of level 2.
  game_client.replay_level_up(game: first, level: 2)
  let #(replayed, _) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_398))
    })
  assert result.is_ok(started_and_gone(frames: replayed, spell4_id: 77_398))
    as "lua.LevelUpUnlocks.ReplayLevelUp: the Replay button asks for an earlier level and gets that tier"
  // A level above the player's is refused: the connection ends, and the second player
  // reads the first leave.
  game_client.replay_level_up(game: first, level: 5)
  game_client.await_closed(game: first)
  let #(left, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(destroyed_units(frames:), first_unit)
    })
  assert list.contains(destroyed_units(frames: left), first_unit)
    as "opcode.0x355: the player whose connection ended leaves the other's sight"
  game_client.close(game: second)
  login_support.stop(started)
}

// ---- a development command's items ----

/// The tree started with the development commands on, on the driven clock `time`.
fn started_with_dev_commands(
  time time: driven_time.Time,
) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    let game = settings.game
    server.Settings(
      ..settings,
      game: server.Served(
        ..game,
        settings: connection_state.Settings(
          ..game.settings,
          game: GameSettings(..game.settings.game, dev_commands: True),
        ),
      ),
    )
  })
}

pub fn an_item_command_puts_the_item_in_the_bag_the_client_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  // The line `!item 90021` on Say is a purchase of cost 0 on the whole server. Item2 90021
  // has maxCharges 5. The client reads the 0x111 of the stack with the reason 4 (Cheat),
  // which raises its loot-channel notice (`opcode.0x111.reason_cheat`), in the first bag slot.
  let time = driven_time.new()
  let started = started_with_dev_commands(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  send_play(game:, character_id: character)
  let #(_, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  game_client.say(game:, text: "!item 90021", chat_message_id: 1)
  let given = fn(frames: List(Frame)) {
    list.filter_map(frames, fn(frame) {
      case frame.message_id == item_added.message_id {
        True ->
          case item_added.decode(frame.body) {
            Ok(added) if added.held_item.item.item_id == 90_021 ->
              Ok(added.held_item)
            Ok(_) | Error(_) -> Error(Nil)
          }
        False -> Error(Nil)
      }
    })
  }
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      given(frames) != []
    })
  let assert [held] = given(frames)
    as "one 0x111 for the one item the line gave"
  assert held.reason == 4 as "Item.CodeEnumItemUpdateReason: Cheat"
  assert held.item.location == 1 && held.item.bag_index == 0
    as "the first slot of the inventory"
  assert held.item.charges == 5 as "Item2 90021's maxCharges"
  assert held.item.stack_count == 1
  game_client.close(game:)
  login_support.stop(started)
}

/// The (bag index, Spell4Base id) of the type 4 shortcuts of the one 0x019D among frames.
fn bar_shortcuts(frames frames: List(Frame)) -> List(#(Int, Int)) {
  limited.the_action_set(frames:).shortcuts
  |> list.filter(fn(shortcut) { shortcut.shortcut_type == 4 })
  |> list.map(fn(shortcut) { #(shortcut.bag_index, shortcut.object_id) })
}

/// A Spellslinger of level 4 who sets its bar with the client's own 0xB1 (the 2026-11-19
/// sitting's saves A and C, whose bytes the part 1 tests hold) and plays again after a camp.
/// The class loadout is the three level 1 abilities in slots 0 to 2 (SpellLevel 1011, 1036 and
/// 1236); the saved bar is what the next entry's 0x019D carries (`opcode.0x19d`) and the
/// answer is 0x019D then 0x00B2 (`opcode.0xb2`).
pub fn a_bar_saved_with_the_clients_0xb1_is_back_after_a_relog_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: limited.spellslinger,
      level: 4,
    )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert bar_shortcuts(frames: entry)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325)]
    as "a character that saved nothing enters with the class's three abilities"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.hex(limited.save_a),
  )
  let #(answer, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  assert list.filter_map(answer, fn(frame) {
      case frame.message_id {
        0x019D | 0x00B2 -> Ok(frame.message_id)
        _ -> Error(Nil)
      }
    })
    == [0x019D, 0x00B2]
    as "the answer is the set then 0xB2"
  assert limited.the_action_set(frames: answer).result == 1
    as "the sitting's first save is accepted at level 4"
  assert bar_shortcuts(frames: answer)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 20_718)]
    as "slots 0 to 3 are the abilities of the save"
  assert limited.the_answer_bit(frames: answer) == 1
  let #(second_entry, have) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert bar_shortcuts(frames: second_entry)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 20_718)]
    as "the next entry holds the four shortcuts of the save, not the class's three"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.hex(limited.save_c),
  )
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  let #(third_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert bar_shortcuts(frames: third_entry) == [#(0, 27_638), #(1, 20_684)]
    as "after the sitting's third save and a relog the entry holds 27638 and 20684 only"
  game_client.close(game:)
  login_support.stop(started)
}

/// The cast entries of the 0x262 of the unit `unit_id` among the frames, as each cast id with
/// the units it lists and, for each, the effects with the time left they were told with.
fn cast_entries_of(
  frames frames: List(Frame),
  unit_id unit_id: Int,
) -> List(#(Int, List(#(Int, List(#(Int, Int)))))) {
  let casts =
    list.flat_map(frames, fn(frame) {
      case created_unit_of(frame:) {
        Ok(#(created, casts)) if created == unit_id -> casts
        Ok(_) | Error(Nil) -> []
      }
    })
  list.map(casts, fn(cast) {
    #(
      cast.cast_id,
      list.map(cast.targets, fn(target) {
        #(
          target.unit_id,
          list.map(target.effects, fn(effect) {
            #(effect.spell4_effects_id, effect.lifetime_ms)
          }),
        )
      }),
    )
  })
}

/// The unit a 0x262 frame creates, with the casts its tail lists.
fn created_unit_of(
  frame frame: Frame,
) -> Result(#(Int, List(unit_create_cast.UnitCreateCast)), Nil) {
  use <- bool.guard(when: frame.message_id != 0x0262, return: Error(Nil))
  use created <- result.map(game_client.created_unit(body: frame.body))
  case created {
    game_client.PlayerCreated(unit:) -> #(unit.unit_id, unit.tail.casts)
    game_client.CreatureCreated(unit:) -> #(unit.unit_id, unit.tail.casts)
    game_client.ObjectCreated(unit_id:, tail:, ..) -> #(unit_id, tail.casts)
  }
}

/// Fissure's child 41886 started and gone on the Beast: its cast id.
fn fissure_child_gone_on(
  frames frames: List(Frame),
  beast beast: Int,
) -> Result(Int, Nil) {
  use #(cast_id, _) <- result.try(
    game_client.starts_of(
      events: game_client.casts_in(frames:),
      spell4_id: 41_886,
    )
    |> list.first,
  )
  case list.contains(game_client.go_targets_in(frames:), #(cast_id, [beast])) {
    True -> Ok(cast_id)
    False -> Error(Nil)
  }
}

/// The viewer's arrival in the order that shows the Beast's own tell, which the test makes
/// certain: the viewer reads the Medic's 0x262 and the Beast's, walks 1026.5 units along z,
/// where the Medic (1023 away) is in sight and the Beast (1026 away) is not (`sight.range`,
/// 1024), reads the Beast's removal, and walks back into the Beast's sight. The Medic's
/// create is then read before the Beast's by the viewer's own steps, not by which of two
/// senders wrote first. Gives the frames of the first arrival (the Medic's entry among
/// them), the frames of the Beast coming into sight again, and the bytes beyond them.
fn beast_comes_into_sight_after_the_medic(
  game game: game_client.Game,
  burst burst: List(Frame),
  have have: BitArray,
  beast beast: Int,
) -> #(List(Frame), List(Frame), BitArray) {
  let #(arrived, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.count(list.append(burst, frames), fn(frame) {
        frame.message_id == 0x0262
      })
      >= 3
    })
  let entry = list.append(burst, arrived)
  walk_to(game:, z: 1026.5, clock: 1)
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), beast)
    })
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 1)
  walk_to(game:, z: 3.5, clock: 2)
  let #(returned, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(game_client.creatures_created_in(frames:), fn(creature) {
        creature.unit_id == beast
      })
    })
  #(entry, returned, have)
}

/// The entries of property `property_id` that the 0x93a frames among `frames` give the unit
/// `unit_id`, in order.
fn property_entries_of(
  frames frames: List(Frame),
  unit_id unit_id: Int,
  property_id property_id: Int,
) -> List(UnitProperty) {
  list.filter(frames, fn(frame) { frame.message_id == 0x093A })
  |> list.flat_map(fn(frame) {
    let assert Ok(changed) = unit_properties_changed.decode(frame.body)
      as "0x93a decodes"
    use <- bool.guard(when: changed.unit_id != unit_id, return: [])
    list.filter(changed.properties, fn(entry) {
      entry.property_id == property_id
    })
  })
}

/// The cast ids of the 0x7fe frames among `frames`, in order.
fn finished_casts_in(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastFinished(cast_id:) -> Ok(cast_id)
      _ -> Error(Nil)
    }
  })
}

/// `opcode.0x262.casts`: a viewer that comes into sight after a Medic's Fissure (Spell4Base
/// 26038) has left its debuff on a Beast is shown the debuff, with the time it has left, and
/// is told it ends at the end of the last phase's child. The child 41886's row 94370 holds
/// 8000 ms and property 160. The viewer sees the Medic first and the Beast comes into its
/// sight after (`beast_comes_into_sight_after_the_medic`), where the debuff shows once, from
/// both entries. The clock is the test's.
pub fn a_viewer_arriving_after_a_medic_fissures_a_beast_shows_the_debuff_on_the_beast_and_its_end_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  // The Beast holds 5000 health as its spawn's own: a client-default Beast has 52, which
  // Fissure's first go alone kills, and the child's property 160 modifier clamps health to
  // that maximum; a dead Beast stands again at the next 1000 ms of the clock, which
  // clears the views before the debuff's 8000 ms are over.
  let started =
    world_with_spawns(
      spawns: [
        spawn.Spawn(
          ..spawn_support.beast_without_deflect_at(
            number: 1,
            place: beast_place(x: 1.5, z: 0.5),
          ),
          health: 5000,
          health_source: unit_fields.Recorded,
        ),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let facing_the_beast =
    game_client.yaw_toward(from: #(1.5, 3.5), target: #(1.5, 0.5))
  let TwoEntered(first:, second:, first_acted:, second_burst:, second_have:, ..) =
    two_players_enter_after(
      started:,
      first_class: 4,
      level: 4,
      first_acts: fn(game, have) {
        let #(seen, have) =
          game_client.read_until(game:, have:, found: fn(frames) {
            game_client.creatures_created_in(frames:) != []
          })
        let assert [beast, ..] = game_client.creatures_created_in(frames: seen)
        game_client.face(game:, yaw: facing_the_beast, clock: 100)
        game_client.press_ability(
          game:,
          client_cast_id: 1,
          bag_index: 4,
          target: 0,
        )
        let #(pressed, have) =
          game_client.read_until(game:, have:, found: fn(frames) {
            fissure_child_gone_on(
              frames: list.append(seen, frames),
              beast: beast.unit_id,
            )
            != Error(Nil)
          })
        driven_time.advance(time:, ms: 200)
        let #(settled, have) =
          game_client.read_until_pong(game:, have:, number: 5)
        #(list.flatten([seen, pressed, settled]), have)
      },
    )
  let assert [beast, ..] = game_client.creatures_created_in(frames: first_acted)
  let assert Ok(child) =
    fissure_child_gone_on(frames: first_acted, beast: beast.unit_id)
  let #(frames, returned, have) =
    beast_comes_into_sight_after_the_medic(
      game: second,
      burst: second_burst,
      have: second_have,
      beast: beast.unit_id,
    )
  let node = #(child, [#(beast.unit_id, [#(94_370, 7800)])])
  assert cast_entries_of(frames:, unit_id: 1) == [node]
    as "opcode.0x262.casts: the Medic's own entry lists its child cast with the Beast as a target, 8000 ms of row 94370 less the 200 ms since the go"
  assert cast_entries_of(frames: returned, unit_id: beast.unit_id) == [node]
    as "opcode.0x262.casts: the Beast's own entry lists the same node with the time left it was told, once: the viewer holds the Medic's cast by then"
  let assert [shown, ..] =
    list.filter(
      game_client.creatures_created_in(frames: returned),
      fn(creature) { creature.unit_id == beast.unit_id },
    )
  assert list.contains(
    shown.tail.properties,
    UnitProperty(
      property_id: 160,
      base: float32.to_bits(1.0),
      value: 1_066_192_077,
    ),
  )
    as "Spell4Effects 94370: the same go's modifier of property 160, mode 2, dataBits02 the bits of 1.1, is on the Beast the viewer is shown"
  let #(settled, have) =
    game_client.read_until_pong(game: second, have:, number: 6)
  // Fissure's second and third phases, 250 ms and 500 ms after its first, start a child
  // each, whose nodes push the earlier ones off the Beast at the stack cap (Jim's decision
  // on stacking).
  driven_time.advance(time:, ms: 500)
  let #(phased, have) =
    game_client.read_until_pong(game: second, have:, number: 7)
  assert list.contains(
    game_client.targets_removed_in(frames: phased),
    #(child, [beast.unit_id]),
  )
    as "opcode.0x811: the viewer that was shown the node is told it ends when the next phase's node pushes it off, as the Medic's client is"
  let assert Ok(#(last_child, _)) =
    game_client.starts_of(
      events: game_client.casts_in(frames: phased),
      spell4_id: 41_886,
    )
    |> list.last
    as "the viewer is written the start of each later phase's child"
  assert last_child != child
    as "the last phase's child is another cast than the first"
  // The last child's node is the one nothing pushes off: it ends 8000 ms after its go.
  driven_time.advance(time:, ms: 7000)
  let #(holding, have) =
    game_client.read_until_pong(game: second, have:, number: 8)
  assert !list.contains(finished_casts_in(frames: holding), last_child)
    && property_entries_of(
      frames: holding,
      unit_id: beast.unit_id,
      property_id: 160,
    )
    == []
    as "the last phase's child still holds the Beast, and its modifier, before its 8000 ms are over"
  driven_time.advance(time:, ms: 2000)
  let #(ended, _) = game_client.read_until_pong(game: second, have:, number: 9)
  assert list.contains(finished_casts_in(frames: ended), last_child)
    as "opcode.0x7fe: the last phase's child ends 8000 ms after its go, the finish alone ending its last node"
  assert list.last(property_entries_of(
      frames: ended,
      unit_id: beast.unit_id,
      property_id: 160,
    ))
    == Ok(UnitProperty(
      property_id: 160,
      base: float32.to_bits(1.0),
      value: float32.to_bits(1.0),
    ))
    as "opcode.0x93a: the Beast is given property 160 back as the debuff ends"
  let seen = list.flatten([frames, returned, settled, phased, holding, ended])
  assert game_client.dead_in(frames: seen) == []
    as "the Beast stays alive through the phases: its 5000 health"
  assert list.all(game_client.health_in(frames: seen), fn(health) {
    health.0 != beast.unit_id || { health.1 > 0 && !health.2 }
  })
    as "no 0x937 gives the Beast no health"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// A level-14 Warrior presses Flash Bang (Spell4 32320, base 18547) with three Beasts about
/// it: A 3 m ahead, B 3 m from A and C 10 m from A, both behind A as the player sees them. The
/// cast's area row (Spell4AoeTargetConstraints 113: 1 target, 0 to 20 m, 180 degrees, Closest)
/// names A alone, so the Proxy 60807 aimed at the area starts one child, 47202, on A; the
/// child's area row (704: 4 targets, 0 to 4 m, 360 degrees) and its hit row (TelegraphDamage
/// 1766: a circle of radius 4, flags 0x1200, targetTypeFlags 2) centre the strike on A, so the
/// child's go names A and B and not C. The clock is driven and the Beasts never deflect.
pub fn a_warrior_of_level_14_presses_flash_bang_and_the_struck_beasts_child_strikes_around_that_beast_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [
        beast_place(x: 1.5, z: 0.5),
        beast_place(x: 4.5, z: 0.5),
        beast_place(x: 1.5, z: -9.5),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Gor Qu",
      class_id: 1,
      level: 14,
    )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= 3
    })
  let beast_at = fn(x, z) {
    let assert Ok(beast) =
      list.find(game_client.creatures_created_in(frames:), fn(beast) {
        let placed = game_client.placed_by_tail(tail: beast.tail)
        float.absolute_value(placed.0 -. x) <. 0.01
        && float.absolute_value(placed.2 -. z) <. 0.01
      })
      as "the world shows the Beast planted there"
    beast.unit_id
  }
  let closest = beast_at(1.5, 0.5)
  let beside = beast_at(4.5, 0.5)
  let far = beast_at(1.5, -9.5)
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames:), fn(item) { item.1 == 18_547 })
    as "SpellLevel 931 grants Flash Bang's base 18547 to a Warrior of level 14"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Flash Bang is planned, so the press is not refused"
  let starts_in = fn(frames: List(Frame)) {
    list.filter(frames, fn(frame) { frame.message_id == 0x07FF })
    |> list.map(fn(frame) {
      let assert Ok(started) = spell_started.decode(frame.body)
        as "0x7ff decodes"
      started
    })
  }
  let assert [child] =
    list.filter(starts_in(pressed), fn(started) { started.spell4_id == 47_202 })
    as "opcode.0x7ff: one child, because Spell4AoeTargetConstraints 113 selects 1 target"
  assert #(
      child.root_spell4_id,
      child.parent_spell4_id,
      child.primary_target_unit_id,
    )
    == #(32_320, 32_320, closest)
    as "Spell4Effects 60807 starts child 47202 of 32320 on the closest Beast, A, which is its primary target (opcode.0x7ff)"
  let goes_of_child = fn(frames: List(Frame)) {
    list.filter_map(game_client.go_targets_in(frames:), fn(go) {
      case go.0 == child.cast_id {
        True -> Ok(go.1)
        False -> Error(Nil)
      }
    })
  }
  // Phase 0 goes at once and phase 1 10 ms later (SpellPhase 8101 and 8102), so the clock moves
  // past it before the second go is awaited; whether the first go reached the client before the
  // press's pong is the connection's order of writes, which nothing here relies on.
  driven_time.advance(time:, ms: 100)
  let #(later, have) =
    game_client.read_until(game:, have:, found: fn(later) {
      list.any(
        game_client.casts_in(frames: list.append(pressed, later)),
        fn(event) {
          event == game_client.CastWent(cast_id: child.cast_id, phase: 1)
        },
      )
    })
  let #(rest, _) = game_client.read_until_pong(game:, have:, number: 2)
  let goes = goes_of_child(list.flatten([pressed, later, rest]))
  assert !list.any(goes, fn(targets) { list.contains(targets, far) })
    as "no go of the child names C, 10 m from A"
  assert goes == [[closest, beside], [closest]]
    as "opcode.0x7f4: the child's first go names A (its own place, 0 m) and B (3 m, inside the circle of radius 4 and the area row's 4 m) and not C (10 m): TelegraphDamage 1766 is fixed at the unit it is cast on; its second go holds only Spell4Effects 174854, a type 17 row aimed at the target (phaseFlags -1), so it names the primary target alone"
  game_client.close(game:)
  login_support.stop(started)
}

/// The 0x7ff of the spell `spell4_id` the frames hold, in order.
fn starts_of_spell(
  frames frames: List(Frame),
  spell4_id spell4_id: Int,
) -> List(game_client.CastEvent) {
  list.filter(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastStarted(spell4_id: started, ..) -> started == spell4_id
      game_client.CastRefused(..)
      | game_client.CastConfirmed(..)
      | game_client.CastWent(..)
      | game_client.CastFinished(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..) -> False
    }
  })
}

/// A Warrior of level 10 presses Plasma Wall (SpellLevel 938: Spell4 38787, base 23169) on the
/// driven clock. Its Proxy 228473 (tickTime 500, durationTime 5000, `Spell4Effects.effectType.26.
/// periodic`; text 311216 "every 0.5s") casts Spell4 87477 at the caster every half second, ten
/// times, each a cast of its own with the wall as parent and root, and the wall's 0x7fe comes
/// after the tenth. A Warrior enters with no Kinetic Energy (`class_resource`: its slot starts
/// empty and is not saved) and holds no Onslaught, so the wall as the client has it cannot be
/// pressed and held for its ticks. The test edits three columns of the Spell4 row to 0, each for its own reason:
/// - `casterInnateRequirement0` (Kinetic Energy of 250): the press is refused 51.
/// - `prerequisiteIdCasterCast` 19750: the Overdrive waiver of that requirement (propertyFlags
///   bit 2 with a requirement block, `Spell4.prerequisiteIdCasterCast`; Overdrive is the cast
///   of 42908). With the requirement gone the row has no block to waive, so the plan reads
///   19750 as a cast gate (`spell_plan.caster_cast_of`) instead of a waiver.
/// - `prerequisiteIdCasterPersistence` 43680 (text 311216, "Removed when you fall below 250
///   Kinetic Energy"): it needs Kinetic Energy of 250 or a live 42908 (43679), so it would end
///   the cast in the input of its own press.
/// The test is about the Proxy's ticks; the end by a persistence is `cast_proxy_tick_test`'s.
pub fn a_warrior_presses_plasma_wall_and_a_child_cast_starts_every_half_second_ten_times_and_the_wall_finishes_after_the_last_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- fixture_tables.changed(table: "Spell4", id: 38_787, with: [
    #("casterInnateRequirement0", planted_table.Integer(0)),
    #("prerequisiteIdCasterCast", planted_table.Integer(0)),
    #("prerequisiteIdCasterPersistence", planted_table.Integer(0)),
  ])
  let time = driven_time.new()
  let started = world_with_spawns(spawns: [], tables:, time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Gor Qu",
      class_id: 1,
      level: 10,
    )
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 23_169 })
    as "SpellLevel 938 grants Plasma Wall's base 23169 to a Warrior of level 10"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Plasma Wall is planned, so the press is not refused"
  let assert Ok(wall) =
    game_client.confirmed_cast_of(frames: pressed, client_cast_id: 1)
    as "opcode.0x7fd: the press is confirmed with the server's cast id"
  assert starts_of_spell(frames: pressed, spell4_id: 87_477) == []
    as "nothing is cast at the go: the first cast is one tick on"
  let #(ticking, have) =
    list.fold(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      #(pressed, have),
      fn(so_far, number) {
        let #(frames, have) = so_far
        driven_time.advance(time:, ms: 500)
        let #(more, have) =
          game_client.read_until(game:, have:, found: fn(more) {
            let seen = list.append(frames, more)
            // The wall's 0x7fe also ends the wait, so a wall that ends before its tenth
            // tick is a failed assertion below and not a wait with no end.
            list.length(starts_of_spell(frames: seen, spell4_id: 87_477))
            >= number
            || finishes(frames: seen, cast_id: wall)
          })
        #(list.append(frames, more), have)
      },
    )
  let #(finished, have) =
    game_client.read_until(game:, have:, found: fn(more) {
      finishes(frames: list.append(ticking, more), cast_id: wall)
    })
  let frames = list.append(ticking, finished)
  let children = starts_of_spell(frames:, spell4_id: 87_477)
  assert list.length(children) == 10
    as "Spell4Effects 228473: durationTime 5000 over tickTime 500 is ten casts"
  let child_ids =
    list.map(children, fn(event) {
      let assert game_client.CastStarted(
        cast_id:,
        root_spell4_id:,
        parent_spell4_id:,
        caster_unit_id:,
        ..,
      ) = event
      assert #(root_spell4_id, parent_spell4_id, caster_unit_id)
        == #(38_787, 38_787, own)
        as "opcode.0x7ff.root_parent: a cast no press made names the wall as root and parent, and the Warrior casts it"
      cast_id
    })
  assert list.unique(child_ids) == child_ids as "each tick is a cast of its own"
  let events = game_client.casts_in(frames:)
  list.each(child_ids, fn(child) {
    assert list.contains(events, game_client.CastWent(cast_id: child, phase: 0))
      && list.contains(events, game_client.CastFinished(cast_id: child))
      as "each child goes and finishes as any child cast does"
  })
  let assert Ok(last_child) = list.last(child_ids)
  let position = fn(wanted) {
    let assert Ok(found) =
      list.index_map(events, fn(event, index) { #(event, index) })
      |> list.find(fn(entry) { entry.0 == wanted })
    found.1
  }
  assert position(game_client.CastFinished(cast_id: wall))
    > position(game_client.CastFinished(cast_id: last_child))
    as "opcode.0x7fe: the wall finishes after the tenth child, the step that fires the tenth tick"
  driven_time.advance(time:, ms: 1500)
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 2)
  assert starts_of_spell(frames: later, spell4_id: 87_477) == []
    as "no eleventh child follows the wall's end"
  game_client.close(game:)
  login_support.stop(started)
}
