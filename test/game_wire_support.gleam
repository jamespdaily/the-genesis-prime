//// The setup the whole-server wire tests (`game_wire_*_test`) share: the tree on a driven
//// clock with the account of the library's vector, the session key its hand-off holds, a
//// player created and played into the world, two players on one map, a world with planted
//// spawns, and the readers of the frames a client hears. A helper only one test file uses sits
//// in that file.

import ask_support
import character_support
import character_tables
import connection_rule_support as support
import content_support
import driven_time
import fight_bot
import fixture_tables
import game_client
import genesis_prime
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/content
import genesis_prime/content/projector_landing as content_projector_landing
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/terrain as content_terrain
import genesis_prime/content/tutorial_quest as content_tutorial_quest
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/hand_off.{Holder, Put, SessionKey}
import genesis_prime/import_world_data
import genesis_prime/login/guid
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_destroyed
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/service
import genesis_prime/store.{type AccountId, AccountId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn
import genesis_prime/world_map/unit_fields
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
import late_sends_support
import login_support
import open_wait
import owned_key
import place_support
import planted_table
import pog
import socket_read
import spawn_support
import terrain_support

/// The 16 bytes the client shows as its session key: the wire bytes of the
/// GUID the hand-off holds.
pub fn session_key() -> BitArray {
  guid.to_wire(support.guid_of(1))
}

/// The number of an account, as the client sends it in 0x058F.
pub fn account_number(account: AccountId) -> Int {
  let AccountId(number) = account
  number
}

/// The tree on the driven clock `time` with the account of the library's vector
/// inserted, the game listener's port and the account.
pub fn start(
  time time: driven_time.Time,
) -> #(login_support.Started, Int, AccountId) {
  let #(started, ports, account_id) = login_support.start_with_jim(time:)
  #(started, ports.game_port, AccountId(account_id))
}

/// How long the hand-off holds a session key the auth server gives on this tree:
/// the `session_key_lifetime_ms` of its auth settings, which the auth connection
/// puts in each Put it sends the hand-off.
pub fn session_key_lifetime_ms(started: login_support.Started) -> Int {
  started.settings.login.auth.settings.session_key_lifetime_ms
}

/// Puts `key` in the tree's hand-off, held for the account.
pub fn hold_session_key(
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
pub fn offer_session_key(
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

/// A create request for CharacterCreation row 466 with a path of 1 and the
/// look of labels 2 and 22, as the client's bytes.
pub fn create_request(name: String) -> BitArray {
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

pub fn created_result(
  game: game_client.Game,
) -> create_character_result.CreateCharacterResult {
  character_support.create_result_in(game_client.read(game:, count: 1))
}

/// Connects a client with the account's held session key and sends 0x07E0,
/// reading the list it gets.
pub fn in_select(
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

/// The slot and display of each worn visual a 0x262 carries: the item visuals
/// of the armor slots, which are below the body's (slots 24 to 39).
pub fn worn_in(
  player player: unit_create_player.UnitCreatePlayer,
) -> List(#(Int, Int)) {
  list.filter(player.tail.item_visuals, fn(visual) { visual.slot < 24 })
  |> list.map(fn(visual) {
    assert visual.item_color_set_id == 0 && visual.dye == 0
      as "opcode.0x262.worn_visuals: colour set 0 and dye 0"
    #(visual.slot, visual.display_id)
  })
}

/// Sends 0x07DD for the character.
pub fn send_play(
  game game: game_client.Game,
  character_id character_id: Int,
) -> Nil {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id:))
    as "0x07DD encodes"
  game_client.send(game:, message_id: 0x07DD, body:)
}

/// Asks for the list again, as the client does when it opens character select,
/// and gives its entries.
pub fn listed_entries(
  game: game_client.Game,
) -> List(character_list_entry.CharacterListEntry) {
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_tier, _entitlements, _level, listed] =
    game_client.read(game:, count: 4)
  let assert Ok(list) = character_list.decode(listed.body)
  list.characters
}

// ---- the player moves and the place is kept ----

/// Sends 0x0637 holding a position and a rotation, as the client's movement
/// update does (opcode.0x637).
pub fn send_move(
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
pub fn health_in(frames frames: List(Frame)) -> Int {
  let assert Ok(health) =
    unit_fields.stat(
      tail: game_client.unit_create_player_in(frames:).tail,
      stat_id: unit_fields.health_stat,
    )
    as "the player's 0x262 holds stat 0 as an integer"
  health
}

// ---- the camp ----

/// The camp countdown the bot's server is started with, in milliseconds: small,
/// since the bot sends 0xC0 as soon as it has read the 0x92 and never waits it
/// out (opcode.0xc0: a Quit does the same).
pub const bot_countdown_ms = 1500

/// The unit ids the 0x355 among the frames remove, in the order sent.
pub fn destroyed_units(frames frames: List(Frame)) -> List(Int) {
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

/// Puts a session key in the hand-off for an account and connects a client with
/// it, reading its character list: the client is in character select.
pub fn connected_as(
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
pub fn unit_of(frame: Frame) -> Int {
  assert frame.message_id == 0x0262 as "the frame is a 0x262"
  let assert Ok(unit) = unit_create_player.decode(frame.body) as "0x262 decodes"
  unit.unit_id
}

/// Two clients of two accounts, each with a character, connected in character
/// select; the first plays its character into an empty map, then the second
/// plays its own into the same map. What each read of the entry is.
pub type TwoEntered {
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
pub fn burst_length() -> Int {
  list.length(game_client.world_entry_ids)
}

/// A player of an account of its own with a character, connected in character
/// select: the first is the library's account, the others are made for a test.
pub fn new_player(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int) {
  new_player_of_class(started:, number:, character_name:, class_id: 4)
}

/// A player as `new_player` makes it, of the class given.
pub fn new_player_of_class(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
) -> #(game_client.Game, Int) {
  new_player_at_level(started:, number:, character_name:, class_id:, level: 9)
}

/// A player as `new_player` makes it, of the class and the level given.
pub fn new_player_at_level(
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
pub fn two_players_enter_one_map(time time: driven_time.Time) -> TwoEntered {
  two_players_enter(
    started: login_support.start(time:),
    first_class: 4,
    level: 1,
  )
}

/// Two players of the level given enter one map, the first of the class given and the
/// second a Medic. A test of the entry's burst takes level 1, whose bag is the level-1
/// three and the innate (`game_client.world_entry_ids`); a higher level's bag holds more.
pub fn two_players_enter(
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
pub fn two_players_enter_after(
  started started: login_support.Started,
  first_class first_class: Int,
  level level: Int,
  first_acts first_acts: fn(game_client.Game, BitArray) ->
    #(List(Frame), BitArray),
) -> TwoEntered {
  two_players_enter_saved(
    started:,
    first_class:,
    level:,
    saved_health: None,
    first_acts:,
  )
}

/// As `two_players_enter_after`, both characters saved with `saved_health` when it is given
/// (below the level's maximum, so a heal is a real change) before either plays.
pub fn two_players_enter_saved(
  started started: login_support.Started,
  first_class first_class: Int,
  level level: Int,
  saved_health saved_health: Option(Int),
  first_acts first_acts: fn(game_client.Game, BitArray) ->
    #(List(Frame), BitArray),
) -> TwoEntered {
  two_players_enter_saved_each(
    started:,
    first_class:,
    level:,
    first_health: saved_health,
    second_health: saved_health,
    first_acts:,
  )
}

/// As `two_players_enter_saved`, each character saved with the health of its own when it is
/// given.
pub fn two_players_enter_saved_each(
  started started: login_support.Started,
  first_class first_class: Int,
  level level: Int,
  first_health first_health: Option(Int),
  second_health second_health: Option(Int),
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
  list.each(
    [#(first_character, first_health), #(second_character, second_health)],
    fn(saved) {
      case saved.1 {
        Some(health) -> {
          let pool = pog.named_connection(started.settings.pool.pool_name)
          let assert Ok(_) =
            pog.query(
              "update character set health = $1 where character_id = $2",
            )
            |> pog.parameter(pog.int(health))
            |> pog.parameter(pog.int(saved.0))
            |> pog.execute(pool)
            as "each character's row holds the health it saved"
          Nil
        }
        None -> Nil
      }
    },
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

/// The results of the refusals (0x7fc) among the frames, in order.
pub fn refusals(frames frames: List(Frame)) -> List(Int) {
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

// ---- chat on the whole server ----

/// One scripted client at the table: its connection, the bytes read beyond what
/// it has used, and the id of its zone channel as its own 0x1bc gave it.
pub type Seat {
  Seat(game: game_client.Game, have: BitArray, zone_channel: Int)
}

/// Reads until the server writes a message with this id, and gives it.
pub fn wait_for_frame(
  seat seat: Seat,
  message_id message_id: Int,
) -> #(Frame, Seat) {
  let #(frame, have) =
    game_client.read_message(game: seat.game, have: seat.have, message_id:)
  #(frame, Seat(..seat, have:))
}

/// The server's tree with the world standing the creatures of the spawn table
/// the test's database holds: the 27 Virtual Defense Daguns the migrations seed
/// and the 27 Virtual Battle Beasts of the planted world-database file, loaded
/// through the content load into a key of the test's own, on the driven clock
/// `time`.
pub fn start_with_creatures(
  time time: driven_time.Time,
) -> login_support.Started {
  start_with_world_data(folder: content_support.fixture_folder, time:)
}

/// The server's tree with the world standing the spawns of the planted world-database
/// file in the folder and the migrations' seeded ones, loaded through the content load
/// into a key of the test's own, and the game connections holding the visibility
/// prerequisites and the reused unit objectives the load found (as the server's own
/// start passes them), on the driven clock `time`.
pub fn start_with_world_data(
  folder folder: String,
  time time: driven_time.Time,
) -> login_support.Started {
  start_with_world_data_on(folder:, time:, adjusted: fn(settings) { settings })
}

/// As `start_with_world_data`, the server's settings then passed through
/// `adjusted`: a test whose casts run on timers moves `time` by hand.
pub fn start_with_world_data_on(
  folder folder: String,
  time time: driven_time.Time,
  adjusted adjusted: fn(server.Settings) -> server.Settings,
) -> login_support.Started {
  login_support.start_with(time:, change: with_world_data(folder:, adjusted:))
}

/// The change of the server's settings that imports the planted world-database file
/// in `folder`, loads the content into a key of the test's own and passes the settings
/// through `adjusted`.
pub fn with_world_data(
  folder folder: String,
  adjusted adjusted: fn(server.Settings) -> server.Settings,
) -> fn(server.Settings) -> server.Settings {
  with_world_data_on_ground(
    folder:,
    terrain: terrain_support.flat_reader(),
    adjusted:,
  )
}

/// As `with_world_data`, the content load reading the ground through `terrain`.
pub fn with_world_data_on_ground(
  folder folder: String,
  terrain terrain: content_terrain.Reader,
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
        terrain:,
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
          loaded_spawns: content_spawn.loaded_spawns(key:),
        ),
      ),
      world: server.World(..settings.world, spawns: key),
    )
    |> adjusted
  }
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
pub const marker_51740 = #(-142.06599, -860.46375, 556.80902)

pub const ring_radius = 19.0

/// Where slot `index` of the 3 on marker 51740's ring is: the point on the circle at
/// 2 pi index / 3 from the +x axis towards +z, at the marker's height.
pub fn ring_slot(index index: Int) -> #(Float, Float, Float) {
  let angle = 2.0 *. maths.pi() *. int.to_float(index) /. 3.0
  #(
    marker_51740.0 +. ring_radius *. maths.cos(angle),
    marker_51740.1,
    marker_51740.2 +. ring_radius *. maths.sin(angle),
  )
}

pub fn is_near(
  left left: #(Float, Float, Float),
  right right: #(Float, Float, Float),
) -> Bool {
  float.absolute_value(left.0 -. right.0) <. 0.01
  && float.absolute_value(left.1 -. right.1) <. 0.01
  && float.absolute_value(left.2 -. right.2) <. 0.01
}

/// A world on the planted world data and the content load, whose game connections take
/// the tables given and, with the maps, their time from `time`.
pub fn world_with_the_markers_creatures(
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
pub fn world_on(
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
pub fn world_with_numbers(
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

/// The same Medic of the level given, holding the experience its last save kept (`None`
/// for the least of its level).
pub fn a_medic_of_a_level_at_the_marker_ring(
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
pub fn a_player_of_a_level_at_the_marker_ring(
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
pub fn targets_in(
  frames frames: List(Frame),
) -> List(unit_create_creature.UnitCreateCreature) {
  list.filter(game_client.creatures_created_in(frames:), fn(creature) {
    creature.creature_id == 73_492
  })
}

/// The 73492 of the frames that stands at ring slot 0.
pub fn the_target_at_slot_0(
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

/// The player at the marker ring faces the target at ring slot 0 and presses Paralytic Surge on
/// the driven clock until it dies: the frames up to its death and the bytes beyond them.
pub fn kills_the_target_at_slot_0(
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

/// The location-4 items of the entry frames as (bag index, base).
pub fn location_4_items(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(item_bot.answer_in(frames:).added, fn(held) {
    case held.item.location {
      4 -> Ok(#(held.item.bag_index, held.item.item_id))
      _ -> Error(Nil)
    }
  })
}

/// The static objects the 0x262 among the frames create, as the client reads them, in
/// the order sent.
pub fn static_objects_created_in(
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

/// Where a Beast stands in World 1387, zone 1100, at `x` and `z`: the world and
/// zone a new test character stands in, at 1.5, 2.5, 3.5, facing -z.
pub fn beast_place(x x: Float, z z: Float) -> Place {
  place_support.at(world_id: 1387, world_zone_id: 1100, x:, y: 2.5, z:)
}

/// A world with a Virtual Battle Beast at each of these places, none of which
/// deflects, and which respawn after 1000 ms (the least a creature kind may hold, the
/// strike deadline), on the tables given. The game connections and the World take
/// their time and timers from `time`: a Beast's swing, strike deadline,
/// respawn and leash fire only when the test advances it.
pub fn world_with_beasts(
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

/// A server holding these tables, its game connections and its World taking their time and
/// their timers from `time`.
pub fn started_on(
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

/// A server as `started_on` makes it, with the sends of its maps to the connection that
/// entered second held back by `delay_ms` of real time each, in the order the maps sent them
/// (`late_sends_support`): the map's notices and the snapshots it relays to that connection
/// arrive late, and nothing a connection sends another directly.
pub fn started_with_the_maps_sends_delayed(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
  delay_ms delay_ms: Int,
) -> login_support.Started {
  let late = late_sends_support.delaying(owner: process.self(), delay_ms:)
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      world: server.World(..settings.world, maps_reach: late),
      game: server.Served(
        ..settings.game,
        settings: connection_state.Settings(..settings.game.settings, tables:),
      ),
    )
  })
}

/// Where the Dagun stands: 23.5 units along -z from where a new test character
/// stands in World 1387, zone 1100, at 1.5, 2.5, 3.5.
pub const dagun_z = -20.0

/// The Dagun's attack tick: the attack interval of the creature kinds the tests'
/// worlds are planted with. The interval is a server choice (the client's effect
/// 184741 has no tickTime), so it is read from those kinds.
pub fn dagun_attack_interval_ms() -> Int {
  spawn_support.kinds().default.attack_interval_ms
}

/// A world with one Dagun at x 1.5, z `dagun_z` on the tables given, its blow the `blow` given
/// when it is `Some` (planted test data) and its own otherwise. Its map's and creature's timers
/// and the connections' are on the clock `time`, so the Dagun's attack tick and home timer
/// fire only when the test advances it.
pub fn world_with_a_dagun_on(
  tables tables: table_store.Tables,
  blow blow: Option(Int),
  time time: driven_time.Time,
) -> login_support.Started {
  let dagun = spawn_support.dagun(number: 1, x: 0.0)
  let dagun = case blow {
    Some(damage) -> spawn_support.spawn_dealing(spawn: dagun, damage:)
    None -> dagun
  }
  world_with_spawns_respawning(
    spawns: [spawn.Spawn(..dagun, place: beast_place(x: 1.5, z: dagun_z))],
    respawn_ms: 60_000,
    tables:,
    time:,
  )
}

/// A world 1387 with these spawns, which respawn after 1000 ms, on the tables given, its
/// game connections and World taking their time and timers from `time`.
pub fn world_with_spawns(
  spawns spawns: List(spawn.Spawn),
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_spawns_respawning(spawns:, respawn_ms: 1000, tables:, time:)
}

/// As `world_with_spawns`, the spawns respawning after `respawn_ms`.
pub fn world_with_spawns_respawning(
  spawns spawns: List(spawn.Spawn),
  respawn_ms respawn_ms: Int,
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
        spawns: spawn_support.key_in(world_id: 1387, spawns:, respawn_ms:),
      ),
    )
  })
}

/// The run of the world 1387 map and the process of the Dagun's creature, unit
/// `dagun`. The first player's connection takes the map's watch 1, so the first
/// creature has life 2 (genesis_prime/world_map/map `joined_new`).
pub fn the_dagun_and_its_map(
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
pub fn read_after_the_map_and_the_creature_took_it(
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

/// Runs the body on the client's rows with Paralytic Surge's recharge taken
/// off: the fight presses it four times in a row, and Spell4 42352's spellCoolDown of
/// 25000 ms would refuse each press after the first unless the clock moved on by
/// that much between presses, which would move every timer the Beast holds with it.
pub fn on_rows_without_paralytic_surges_recharge(
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
pub fn world_with_a_beast_ahead(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_beasts(places: [beast_place(x: 1.5, z: 0.5)], tables:, time:)
}

/// Plays a new player of the class, at level 1, into the world and reads until the
/// 0x262 of each of the Beasts has arrived.
pub fn enters_and_sees_the_beasts(
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

/// The health of each 0x937 among the frames for the unit, in order.
pub fn beast_health_in(
  frames frames: List(Frame),
  beast beast: Int,
) -> List(Int) {
  list.filter_map(game_client.health_in(frames:), fn(health) {
    case health.0 == beast {
      True -> Ok(health.1)
      False -> Error(Nil)
    }
  })
}

/// Whether the frames hold the 0x7fe of the cast.
pub fn finishes(frames frames: List(Frame), cast_id cast_id: Int) -> Bool {
  list.contains(
    game_client.casts_in(frames:),
    game_client.CastFinished(cast_id:),
  )
}

/// The place among the frames of the first one `found` holds for, or -1.
pub fn index_where(
  frames frames: List(Frame),
  found found: fn(Frame) -> Bool,
) -> Int {
  list.index_map(frames, fn(frame, index) { #(frame, index) })
  |> list.find(fn(entry) { found(entry.0) })
  |> result.map(fn(entry) { entry.1 })
  |> result.unwrap(-1)
}

/// Whether the frames hold the finish of a cast (0x7fe).
pub fn holds_a_finish(frames frames: List(Frame)) -> Bool {
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

/// Presses the ability of the bag index and moves the clock on by its cast time, so
/// the timer of its go fires: the first pong shows the connection took the press and
/// started the go's timer on the clock. The Beast answers the strike on its own
/// process, so the read after the advance goes on until the go is written with its
/// outcome (a health, a miss, or no target at all), and the second pong follows it.
/// The frames of the reads and the bytes beyond.
pub fn press_and_fire(
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

/// The place of the first frame of the message in the frames, or -1.
pub fn position_of(
  frames frames: List(Frame),
  message_id message_id: Int,
) -> Int {
  case
    list.index_map(frames, fn(frame, index) { #(frame.message_id, index) })
    |> list.find(fn(entry) { entry.0 == message_id })
  {
    Ok(#(_, index)) -> index
    Error(Nil) -> -1
  }
}

/// As `press_until_dead`, with every frame the presses were answered with, in order.
pub fn press_until_dead_reading(
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

pub fn press_loop(
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

pub fn walk_to(
  game game: game_client.Game,
  z z: Float,
  clock clock: Int,
) -> Nil {
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: clock, commands: [
      game_client.position_command(x: 1.5, y: 2.5, z:),
    ]),
  )
}

/// The stat of the player's own 0x262.
pub fn entry_stat(entry entry: List(Frame), stat_id stat_id: Int) -> Int {
  let player = game_client.unit_create_player_in(frames: entry)
  let assert Ok(value) = unit_fields.stat(tail: player.tail, stat_id:)
    as "the player's 0x262 holds the stat as an integer"
  value
}

/// Runs the body on the client's rows with Paralytic Surge's recharge taken off (as
/// `on_rows_without_paralytic_surges_recharge`) and the Sim-Turrets' deflect taken off: their
/// base deflect chance is 0.016 (CreatureLevel row 101 0.05 times Creature2Difficulty 1's
/// multiplier 101 of 0.32, as `Creature2.73464.crit_deflect_glance` has it), and the
/// presses the opening holds are only enough to destroy a turret when none of them deflects.
pub fn on_rows_with_turrets_that_never_deflect(
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
