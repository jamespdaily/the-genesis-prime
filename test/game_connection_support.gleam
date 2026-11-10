//// What the game connection's rule tests share (`genesis_prime/game/connection`):
//// the settings, the client's messages built by `game_client`, and the inputs
//// that bring a connection to each stage, from the hello to a player in the
//// world, its camp, its fight and its death.

import cast_support
import character_support
import character_tables
import class_resource_support
import client_tables
import connection_rule_support as support
import fixture_tables
import game_client
import genesis_prime/account_session.{Claim, Claimed, TakenOver}
import genesis_prime/client_connection.{
  type Answer, type Message, type News, type PeerNews, type Request, Appeared,
  AskHandOff, AskMap, AskMapRun, AskSessions, AskStore, CreatureAppeared,
  ForStay, FromHandOff, FromMap, FromSessions, FromStore, Moving, PeerNews,
  Removed, SentByMap, SentByPeer, SentBySessions, TellChat, TellMoved, TellPeer,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{type Settings, Settings}
import genesis_prime/game/hit.{Blow, Offence}
import genesis_prime/game/loadout
import genesis_prime/game/server_proxy
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/vendor.{type Vendors}
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{Holder, NoHolder, Taken}
import genesis_prime/login/guid
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/item_move
import genesis_prime/message/item_place
import genesis_prime/message/movement_command
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_position
import genesis_prime/message/spell_started
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_stealth
import genesis_prime/message/vendor_purchase.{VendorPurchase}
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, type Outcome,
  type TimerId, CallerId, CancelTimer, ConnectionId, EndedBeforeAnswer, Map,
  NoAnswerInTime, NotRunning, OwnEffect, OwnEvent, StartTimer, TimerFired,
  TimerId, Unwatch, Watch, WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{
  AccountId, Character, CharacterId, CharacterLoaded, ForMove, ForSelect,
  ForWorld, HeldCurrency, Listed, Move, NameStands, NotTheAccounts, PlaceSaved,
  SavePlace, Unavailable,
}
import genesis_prime/table/id.{
  ClassId, Creature2Id, RaceId, Spell4BaseId, Spell4Id,
}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/creature_kind.{Kind, Kinds}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map.{Join, Leave, Left, SeenBy, Summon}
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import map_support
import message_support
import place_support
import planted_table
import server_proxy_support
import spawn_support
import world_entry_support
import zone_welcome_support

/// What the tests' game connections are made with: a realm id and a
/// character limit the hello and the list must carry, the number of character
/// slots a create is told, the client's tables and a deadline.
pub fn settings() -> game_connection.Settings {
  Settings(
    realm_id: 5,
    max_characters: 9,
    game: GameSettings(
      camp_countdown_ms: 12_345,
      character_slots: 3,
      dev_commands: False,
    ),
    realm_name: "Test Realm",
    tables: character_tables.shared(),
    ask_deadline_ms: 4000,
    rate: support.roomy(),
    class_resources: class_resource_support.classes(),
    server_proxies: server_proxy_support.none(),
    zone_welcomes: zone_welcome_support.none(),
    vendors: vendor.none(),
    numbers: spawn_support.numbers,
  )
}

/// The same settings with the development chat commands on
/// (`genesis_prime/game/dev_command`).
pub fn settings_with_dev_commands() -> game_connection.Settings {
  let settings = settings()
  Settings(..settings, game: GameSettings(..settings.game, dev_commands: True))
}

/// The 16 bytes the client shows as its session key: 01 .. 10, as in the
/// client's vector (vector.opcode.0x58f.body), the wire bytes of the GUID
/// `support.guid_of(1)` the hand-off is asked for.
pub fn session_key() -> BitArray {
  guid.to_wire(support.guid_of(1))
}

pub fn holder() -> hand_off.Holder {
  Holder(
    account_id: AccountId(7),
    login_name: "jim",
    game_account_id: support.guid_of(0x11),
  )
}

pub fn base() -> Cipher {
  cipher.base()
}

pub fn keyed() -> Cipher {
  game_client.session_cipher(session_key: session_key())
}

/// The system time every answer of the tests carries, as a FILETIME.
pub const filetime = world_entry_support.filetime

pub fn feed(
  state state: game_connection.State,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(game_connection.State, ConnectionStep(Request)) {
  feed_at(state:, filetime:, event:)
}

/// An event that reaches the connection at this system time, as a FILETIME.
pub fn feed_at(
  state state: game_connection.State,
  filetime filetime: Int,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, support.input_at(filetime:, event:))
}

pub fn read(
  state state: game_connection.State,
  bytes bytes: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  feed(state:, event: step.OwnEvent(step.Read(bytes)))
}

pub fn answer(
  state state: game_connection.State,
  taken taken: ConnectionStep(Request),
  outcome outcome: Outcome(Answer),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  feed(state:, event: step.OwnEvent(step.Answered(ask: ask.ask, outcome:)))
}

/// A connection the server has accepted, made with these settings; the step
/// is the hello.
pub fn accepted(
  settings: game_connection.Settings,
) -> #(game_connection.State, ConnectionStep(Request)) {
  feed(
    state: game_connection.new(settings),
    event: step.OwnEvent(step.Accepted(
      ConnectionId(1),
      support.peer,
      support.seed(1),
    )),
  )
}

pub fn connected() -> game_connection.State {
  accepted(settings()).0
}

/// What the client sends first: 0x058F, under the base key.
pub fn hello_reply() -> BitArray {
  game_client.hello_reply(session_key: session_key(), account_name: "jim")
}

/// A message of the client's under the session key.
pub fn keyed_message(
  message_id message_id: Int,
  body body: BitArray,
) -> BitArray {
  game_client.client_bytes(message_id:, body:, cipher: keyed())
}

pub fn select_start() -> BitArray {
  keyed_message(message_id: 0x07E0, body: <<>>)
}

/// 0x038C carrying the store-catalog request, as the client sends it after
/// 0x07E0 (opcode.0x82d: the value 0x13, then a 14-bit value in two bytes).
pub fn store_request() -> BitArray {
  keyed_message(
    message_id: 0x038C,
    body: game_client.world_body(kind: 0x13, message_id: 0x082D, body: <<
      0x34,
      0x12,
    >>),
  )
}

/// 0x038C carrying 0x07CC, the reward rotation request no feature takes: the
/// wrapper value 0x0B, then the 32-bit content type (opcode.0x7cc, fact
/// 0x1403f4740).
pub fn unhandled_request() -> BitArray {
  keyed_message(
    message_id: 0x038C,
    body: game_client.world_body(kind: 0x0B, message_id: 0x07CC, body: <<
      0,
      0,
      0,
      0,
    >>),
  )
}

/// The connection after the hand-off held the key: Sessions asked to claim
/// the account.
pub fn claiming() -> #(game_connection.State, ConnectionStep(Request)) {
  claiming_from(connected())
}

/// `fresh`, a connection the server has accepted, after the hand-off held the
/// key: Sessions asked to claim the account.
pub fn claiming_from(
  fresh: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = read(state: fresh, bytes: hello_reply())
  answer(
    state:,
    taken:,
    outcome: step.Answer(FromHandOff(Taken(holder: holder()))),
  )
}

/// The claim the connection asks Sessions: its account and its id.
pub fn claim_ask() -> Request {
  AskSessions(Claim(account: AccountId(7), connection: ConnectionId(1)))
}

/// Sessions' answer to the claim in `taken`.
pub fn claimed(
  state state: game_connection.State,
  taken taken: ConnectionStep(Request),
) -> #(game_connection.State, ConnectionStep(Request)) {
  answer(state:, taken:, outcome: step.Answer(FromSessions(Claimed)))
}

/// The connection after Sessions answered the claim: in character select,
/// nothing asked.
pub fn in_select() -> game_connection.State {
  in_select_from(connected())
}

/// `fresh`, a connection the server has accepted, after Sessions answered the
/// claim: in character select, nothing asked.
pub fn in_select_from(fresh: game_connection.State) -> game_connection.State {
  let #(state, taken) = claiming_from(fresh)
  claimed(state:, taken:).0
}

/// The connection after 0x07E0, with its ask to the store.
pub fn listing() -> #(game_connection.State, ConnectionStep(Request)) {
  read(state: in_select(), bytes: select_start())
}

/// The connection after the store's rows, the list written.
pub fn listed(
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
pub fn heard(
  taken taken: ConnectionStep(Request),
  cipher cipher: Cipher,
) -> List(Frame) {
  list.map(support.written_frames(taken), game_client.in_the_game_wrapper(
    _,
    cipher,
  ))
}

/// The one 0x036A the step writes, under `cipher`, with the connection ended.
pub fn disconnect(
  taken taken: ConnectionStep(Request),
  cipher cipher: Cipher,
) -> disconnect_reason.DisconnectReason {
  let assert [Frame(message_id: 0x036A, body:)] = heard(taken:, cipher:)
    as "one 0x036A in its wrapper, under the cipher the connection holds"
  let assert Ok(DisconnectNotice(reason:)) = disconnect_notice.decode(body)
    as "0x036A decodes"
  assert support.stops(taken) as "the connection ends after 0x036A"
  reason
}

pub fn ask_request(taken: ConnectionStep(Request)) -> Request {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  ask.request
}

/// A stored character whose gender is 2 or 3, which no CharacterCustomization
/// row has, so its entry holds no body visuals whatever its race
/// (`character_customization.all` below shows it).
pub fn character(
  id id: Int,
  name name: String,
  seed seed: Int,
) -> store.Character {
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

/// What each effect of a step is, in order: the bytes of a write are not
/// compared here, only what kind of effect leaves and when.
pub fn kinds(taken: ConnectionStep(Request)) -> List(String) {
  list.map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Write(..)) -> "write"
      step.Log(..) -> "log"
      step.Stop -> "stop"
      OwnEffect(..) | step.Watch(..) | step.Unwatch(..) -> "other"
    }
  })
}

/// A create request for CharacterCreation row 466 with a path of 2 and the
/// look of labels 2 and 22 (the Exile face of CharacterCustomization row 604).
pub fn a_create_request(name: String) -> create_character.CreateCharacter {
  CreateCharacter(
    ..character_support.create_request(name),
    path: 2,
    customisation_labels: [2, 22],
    customisation_values: [1, 2],
  )
}

/// The bytes of a create request as the client sends it: the whole frame of
/// 0x025B as the body of 0x025C (opcode.0x25c), under the session key.
pub fn create_message(request: create_character.CreateCharacter) -> BitArray {
  let assert Ok(body) = create_character.encode(request)
    as "the request encodes"
  let assert Ok(plain) = frame.encode(0x025B, body) as "0x025B frames"
  keyed_message(message_id: 0x025C, body: plain)
}

pub fn play_message(character_id: Int) -> BitArray {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id:))
    as "0x07DD encodes"
  keyed_message(message_id: 0x07DD, body:)
}

/// The connection after 0x07DD for the character, with its ask to the store.
pub fn playing(
  character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  playing_from(in_character_select: in_select(), character_id:)
}

/// `in_character_select` after 0x07DD for the character, with its ask to the
/// store.
pub fn playing_from(
  in_character_select in_character_select: game_connection.State,
  character_id character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  read(state: in_character_select, bytes: play_message(character_id))
}

/// A Dominion human male, class 2, who stands in World 3460 at the place of
/// WorldLocation2 row 51596 (the Novice start): its body is the look of
/// CharacterCustomization row 10 (labels 21 = 2 and 2 = 1, display 137 on slot
/// 25), and it has the 48 bone values race 1, sex 0 carries
/// (opcode.0x25b.counts).
pub fn world_character() -> store.Character {
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
pub fn joining_as(
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  joining_from(in_character_select: in_select(), character:)
}

/// `in_character_select` after the store gave `character`, which has no saved
/// health: the map is asked.
pub fn joining_from(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  joining_saved(in_character_select:, character:, saved_health: None)
}

/// `in_character_select` after the store gave `character` with the health its
/// last save kept: the map is asked.
pub fn joining_saved(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
  saved_health saved_health: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  joining_holding(
    in_character_select:,
    character:,
    saved_health:,
    saved_experience: None,
    quests: [],
  )
}

/// `in_character_select` after the store gave `character` with the health, the
/// experience (`None` for none) and the quest rows its last save kept: the map
/// is asked.
pub fn joining_holding(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
  saved_health saved_health: Option(Int),
  saved_experience saved_experience: Option(Int),
  quests quests: List(store.QuestRow),
) -> #(game_connection.State, ConnectionStep(Request)) {
  joining_holding_items(
    in_character_select:,
    character:,
    saved_health:,
    saved_experience:,
    quests:,
    items: world_entry_support.novice_items(character:),
  )
}

/// `joining_holding` for a character whose store holds these items.
pub fn joining_holding_items(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
  saved_health saved_health: Option(Int),
  saved_experience saved_experience: Option(Int),
  quests quests: List(store.QuestRow),
  items items: List(store.HeldItem),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = playing_from(in_character_select:, character_id: 42)
  answer(
    state:,
    taken:,
    outcome: step.Answer(
      FromStore(
        ForWorld(
          CharacterLoaded(
            character,
            character_support.epoch(1),
            saved_health,
            saved_experience,
            items,
            quests,
            [],
          ),
        ),
      ),
    ),
  )
}

/// The connection after the store gave the character: the map is asked.
pub fn joining() -> #(game_connection.State, ConnectionStep(Request)) {
  joining_as(world_character())
}

/// The tests' map: the world the tests' character is saved in, and its one
/// open instance.
pub fn camp_map() -> MapId {
  MapId(world_id: 3460, instance: 0)
}

/// The run of the tests' map.
pub const incarnation = 77

/// A map of the tests' realm and tables, as the server starts one for the tests'
/// connections, with four other connections joined, so the next join is unit 5.
pub fn map_with_four_players() -> map.State {
  map_run_with_four_players(incarnation)
}

/// The same as the run `run` of the tests' map.
pub fn map_run_with_four_players(run: Int) -> map.State {
  let state =
    map.new(map.Settings(
      map: camp_map(),
      incarnation: run,
      realm_id: settings().realm_id,
      tables: settings().tables,
      spawns: spawn.no_spawns(),
      summons: spawn_support.summon_checks(),
      kinds: Kinds(
        default: Kind(
          respawn_ms: 60_000,
          attack_spell4_id: Spell4Id(5649),
          attack_interval_ms: 1500,
        ),
        by_creature: dict.new(),
      ),
      numbers: spawn_support.numbers,
      idle_stop_ms: 60_000,
      sweep_ms: 10_000,
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
              stay: viewer_stay(other),
              alive: True,
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
pub fn map_answer(taken: ConnectionStep(Request)) -> map.Outgoing {
  mapped(map_state: map_with_four_players(), taken:).1
}

/// The map's answer to a join of the tests' player, for the tests that need an
/// answer and read nothing in it.
pub fn a_join_answer() -> map.Outgoing {
  map_answer(joining().1)
}

/// The connection after the map took `character`: the burst is written.
pub fn entered_as(
  character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  entered_from(in_character_select: in_select(), character:)
}

/// `in_character_select` after the map took `character`: the burst is written.
pub fn entered_from(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
) -> #(game_connection.State, ConnectionStep(Request)) {
  entered_saved(in_character_select:, character:, saved_health: None)
}

/// `in_character_select` after the store gave `character` with the health its
/// last save kept and the map took it: the burst is written.
pub fn entered_saved(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
  saved_health saved_health: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) =
    joining_saved(in_character_select:, character:, saved_health:)
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken))))
}

/// `in_character_select` after the store gave `character` with the experience its
/// last save kept and the map took it: the burst is written.
pub fn entered_holding(
  in_character_select in_character_select: game_connection.State,
  character character: store.Character,
  saved_experience saved_experience: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) =
    joining_holding(
      in_character_select:,
      character:,
      saved_health: None,
      saved_experience:,
      quests: [],
    )
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken))))
}

/// The connection after the store gave the tests' character these quest rows and
/// the map took it: the burst is written.
pub fn entered_with_quests(
  quests quests: List(store.QuestRow),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) =
    joining_holding(
      in_character_select: in_select(),
      character: world_character(),
      saved_health: None,
      saved_experience: None,
      quests:,
    )
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken))))
}

/// The connection in the world, with its burst taken, for a character whose
/// store holds these items.
pub fn in_world_holding(
  items items: List(store.HeldItem),
) -> game_connection.State {
  let #(state, taken) =
    joining_holding_items(
      in_character_select: in_select(),
      character: world_character(),
      saved_health: None,
      saved_experience: None,
      quests: [],
      items:,
    )
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken)))).0
}

/// The tests' player's health at full: 736, the Engineer's level 1 maximum
/// (`player.level1_base_health`: CreatureLevel row 1's 135.97 and the Novice
/// armor's 600).
pub const full_health = 736

/// The connection after the map took the player: the burst is written.
pub fn entered() -> #(game_connection.State, ConnectionStep(Request)) {
  entered_as(world_character())
}

/// The connection in the world, with its burst taken.
pub fn in_world() -> game_connection.State {
  entered().0
}

/// The connection in the world of an Exile, with its burst taken: the character
/// of `in_world` (a Dominion one) with the Exile faction.
pub fn in_world_as_exile() -> game_connection.State {
  entered_as(Character(..world_character(), faction_id: spawn.exile_faction)).0
}

/// The connection in the world, with its burst taken, made with the
/// development chat commands on.
pub fn in_world_with_dev_commands() -> game_connection.State {
  entered_from(
    in_character_select: in_select_from(
      accepted(settings_with_dev_commands()).0,
    ),
    character: world_character(),
  ).0
}

/// The connection in the world of an Exile, with its burst taken, made with these
/// vendors.
pub fn in_world_stocking(vendors vendors: Vendors) -> game_connection.State {
  entered_from(
    in_character_select: in_select_from(
      accepted(Settings(..settings(), vendors:)).0,
    ),
    character: Character(..world_character(), faction_id: spawn.exile_faction),
  ).0
}

/// `in_world_stocking`'s Exile, whose store holds `credits` credits for it.
pub fn in_world_stocking_holding_credits(
  vendors vendors: Vendors,
  credits credits: Int,
) -> game_connection.State {
  let character =
    Character(..world_character(), faction_id: spawn.exile_faction)
  let #(state, taken) =
    playing_from(
      in_character_select: in_select_from(
        accepted(Settings(..settings(), vendors:)).0,
      ),
      character_id: 42,
    )
  let #(state, taken) =
    answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(
            CharacterLoaded(
              character,
              character_support.epoch(1),
              None,
              None,
              world_entry_support.novice_items(character:),
              [],
              [HeldCurrency(currency_type_id: 1, amount: credits)],
            ),
          ),
        ),
      ),
    )
  answer(state:, taken:, outcome: step.Answer(FromMap(map_answer(taken)))).0
}

/// The client's 0x00BE for the stock position and the quantity of lots (`vendor_purchase`),
/// read by the connection in the world.
pub fn purchase_requested(
  state state: game_connection.State,
  unique_id unique_id: Int,
  quantity quantity: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) =
    vendor_purchase.encode(VendorPurchase(unique_id:, quantity:))
    as "a unique id and a quantity of 32 bits fit the message"
  read(state:, bytes: world_message(message_id: 0x00BE, body:))
}

/// The ask of a `!summon` line of the tests' player: the run of the map that
/// took the player, 77 (`incarnation`), with the connection's id, the
/// Creature2 id and the level the line named, if any.
pub fn summon_asked(
  creature2_id creature2_id: Int,
  level level: Option(Int),
) -> Request {
  AskMapRun(
    map: camp_map(),
    incarnation:,
    message: Summon(
      connection: ConnectionId(1),
      creature_id: Creature2Id(creature2_id),
      level:,
    ),
  )
}

/// The 0x262 among the burst, decoded.
pub fn player_in(taken: ConnectionStep(Request)) -> UnitCreatePlayer {
  game_client.unit_create_player_in(frames: heard(taken:, cipher: keyed()))
}

/// A world message as the client sends it: inside 0x038C, whose first byte is
/// the 5-bit value 3 of SendWorldMessage (opcode.0x38c), under the session key.
pub fn world_message(
  message_id message_id: Int,
  body body: BitArray,
) -> BitArray {
  keyed_message(
    message_id: 0x038C,
    body: game_client.world_body(kind: 3, message_id:, body:),
  )
}

/// The client's 0x07EA of the unit and kind (`interaction_request`), read by the
/// connection in the world.
pub fn interaction_requested(
  state state: game_connection.State,
  unit_id unit_id: Int,
  kind kind: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(unit_id:, kind:))
    as "a unit id and a 7-bit kind fit the message"
  read(state:, bytes: world_message(message_id: 0x07EA, body:))
}

pub fn move_message(message_id: Int) -> BitArray {
  keyed_message(message_id:, body: <<0, 0, 0, 0>>)
}

/// 0x637 holding `commands`, as the client writes it, under the session key.
pub fn moves_message(
  commands: List(movement_command.MovementCommand),
) -> BitArray {
  world_message(
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1234, commands:),
  )
}

/// A place in World 3460, zone 6009, as `world_character()` has.
pub fn standing_at(x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
}

/// Where `world_character()` is saved: the place of WorldLocation2 row 51596.
pub fn entry_place() -> Place {
  standing_at(x: 29.128599166870117, y: -853.87158203125, z: -560.18798828125)
}

/// The ask of a save of the tests' player at full health: the account and
/// character of the tests' connection, the epoch its load gave, the save's
/// number and the place, the full health (`full_health`) and the level 1 the
/// character has with the 0 experience that is the least of level 1 (XpPerLevel
/// ID 1's minXpForLevel, `opcode.0x25e.safe_body`).
pub fn save_asked(sequence sequence: Int, place place: Place) -> Request {
  save_asked_keeping(sequence:, place:, health: Some(full_health))
}

/// The same with the health the save keeps: `None` for none.
pub fn save_asked_keeping(
  sequence sequence: Int,
  place place: Place,
  health health: Option(Int),
) -> Request {
  AskStore(
    Move(
      SavePlace(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        save_sequence: sequence,
        place:,
        health:,
        experience: 0,
        level: 1,
        quests: [],
      ),
    ),
  )
}

/// The store's answer that a place was saved.
pub fn place_saved() -> Outcome(Answer) {
  step.Answer(FromStore(ForMove(PlaceSaved)))
}

/// The connection after the client moved the player to x, y, z.
pub fn moved_to(
  state state: game_connection.State,
  x x: Float,
  y y: Float,
  z z: Float,
) -> game_connection.State {
  read(state:, bytes: moves_message([game_client.position_command(x:, y:, z:)])).0
}

/// The outcomes in which a store ask gets no answer, for a save.
pub fn no_answers() -> List(Outcome(Answer)) {
  [
    step.Answer(FromStore(Unavailable)),
    NotRunning,
    NoAnswerInTime,
    EndedBeforeAnswer,
  ]
}

/// A message the client's code never sends, with what makes it so.
pub fn refused_messages() -> List(#(BitArray, String)) {
  [
    #(
      world_message(message_id: 0x063B, body: <<3, 0, 0, 0>>),
      "a move speed setting above 2",
    ),
    ..refused_moves()
  ]
}

/// A 0x637 the client's code never sends, with what makes it so
/// (`movement_command.position_bound` and the commands' records).
pub fn refused_moves() -> List(#(BitArray, String)) {
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
    #(
      moves_message([
        game_client.position_command(x: 99.0, y: 99.0, z: 99.0),
        position_of(one, not_a_number, one),
      ]),
      "a refused command after a good one, of which nothing is kept",
    ),
  ]
}

/// The answers a save never gets: those of another group of asks.
pub fn answers_to_other_asks() -> List(Outcome(Answer)) {
  [
    step.Answer(FromStore(ForSelect(Listed([])))),
    step.Answer(FromStore(ForWorld(NotTheAccounts))),
    step.Answer(FromHandOff(NoHolder)),
    step.Answer(FromSessions(Claimed)),
    step.Answer(FromMap(a_join_answer())),
  ]
}

pub fn taken_over() -> Event(ConnectionEvent(Message, Answer)) {
  OwnEvent(Woken(message: SentBySessions(message: TakenOver)))
}

/// A connection in character select with its list shown, which Sessions' end
/// finds with state to keep.
pub fn in_select_with_a_list() -> game_connection.State {
  listed(characters: []).0
}

/// The connection `held` after Sessions ended and the wait ran out: the claim
/// is out again.
pub fn claiming_again(
  held: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, _) = feed(state: held, event: WatchEnded(WatchId(1)))
  let #(state, taken) = feed(state:, event: OwnEvent(TimerFired(TimerId(1))))
  assert ask_request(taken) == claim_ask()
  #(state, taken)
}

/// 0xBF inside 0x038C: one bit, 1 to start a camp and 0 to cancel it
/// (opcode.0xbf).
pub fn camp_request_message(start: Bool) -> BitArray {
  world_message(message_id: 0x00BF, body: case start {
    True -> <<1>>
    False -> <<0>>
  })
}

/// 0xC0 inside 0x038C: its body is empty (opcode.0xc0).
pub fn camp_finished_message() -> BitArray {
  world_message(message_id: 0x00C0, body: <<>>)
}

/// The connection with the player's camp running, its 0x92 written.
pub fn camping() -> game_connection.State {
  read(state: in_world(), bytes: camp_request_message(True)).0
}

/// The connection after 0xC0 of a running camp: the save is asked.
pub fn saving_the_camp() -> #(game_connection.State, ConnectionStep(Request)) {
  read(state: camping(), bytes: camp_finished_message())
}

/// The connection after the camp's save was answered: the map's run is asked
/// to let the player leave.
pub fn leaving_the_map() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = saving_the_camp()
  answer(state:, taken:, outcome: place_saved())
}

/// The ask of the player's leave: the run of the map that took the player, 77
/// (`incarnation`), with the connection's id.
pub fn leave_asked() -> Request {
  AskMapRun(
    map: camp_map(),
    incarnation:,
    message: Leave(connection: ConnectionId(1)),
  )
}

/// The connection after the map answered `Left`: 0x594 is written and the
/// client is in character select.
pub fn camped_out() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = leaving_the_map()
  answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
}

/// The frames the step writes, as the client reads them, opened under the keyed
/// cipher.
pub fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  heard(taken:, cipher: keyed())
}

/// The Spell4 id of each `spell_started` (0x07FF) among the frames, in order.
pub fn started_spells(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a spell_started decodes"
        Ok(start.spell4_id)
      }
      False -> Error(Nil)
    }
  })
}

/// The stealth bits of each `unit_stealth` (0x08F5) among the frames, in order.
pub fn stealth_bits(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_stealth.message_id {
      True -> {
        let assert Ok(change) = unit_stealth.decode(frame.body)
          as "a unit_stealth decodes"
        Ok(change.stealthed)
      }
      False -> Error(Nil)
    }
  })
}

/// The message ids from the first frame with this id on, that frame included.
pub fn from_id(frames frames: List(Frame), id id: Int) -> List(Int) {
  list.drop_while(cast_support.ids(frames:), fn(found) { found != id })
}

/// News of the unit `unit_id` as its owner's connection sends it, for the tests'
/// player's first stay.
pub fn news_sent_by_a_peer(
  unit_id unit_id: Int,
  news news: News,
) -> Event(ConnectionEvent(Message, Answer)) {
  sent_by_a_peer(news_of(unit_id:, news:))
}

/// The news a step tells the viewer connection `viewer`, in order.
pub fn news_told(
  taken taken: ConnectionStep(Request),
  viewer viewer: Int,
) -> List(News) {
  list.filter_map(peer_tells(taken), fn(tell) {
    case tell.0 == viewer {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

/// The `unit_create_player` (0x0262) the tests' player's connection sends the arriving viewer connection
/// `viewer`, taken from the state.
pub fn created_for(
  state state: game_connection.State,
  viewer viewer: Int,
) -> UnitCreatePlayer {
  let assert [#(_, PeerNews(news: Appeared(unit:), ..))] =
    peer_tells(
      feed(
        state:,
        event: sent_by_the_map(SeenBy(
          by: ConnectionId(viewer),
          stay: viewer_stay(viewer),
        )),
      ).1,
    )
    as "the player's connection sends the arriving viewer its unit_create_player"
  unit
}

/// A viewer connection that shows the unit 9.
pub fn viewer_showing_unit_9() -> game_connection.State {
  feed(state: in_world(), event: event_of(Appears)).0
}

/// The messages the step writes, as the client reads them.
pub fn written_ids(taken: ConnectionStep(Request)) -> List(Int) {
  list.map(heard(taken:, cipher: keyed()), fn(frame) { frame.message_id })
}

/// The map's answer to the ask in the step, from the map's rule: `map_state`
/// takes the ask's message as the map's caller 1 and answers it.
pub fn mapped(
  map_state map_state: map.State,
  taken taken: ConnectionStep(Request),
) -> #(map.State, map.Outgoing) {
  let message = case ask_request(taken) {
    AskMap(message:, ..) | AskMapRun(message:, ..) -> message
    AskStore(..)
    | AskHandOff(..)
    | AskSessions(..)
    | TellMoved(..)
    | client_connection.TellReady(..)
    | client_connection.TellStealthChanged(..)
    | client_connection.TellLifeChanged(..)
    | TellPeer(..)
    | client_connection.TellStrike(..)
    | client_connection.TellTargetMoved(..)
    | client_connection.TellStrikeAnswered(..)
    | client_connection.TellTargetChange(..)
    | TellChat(..) ->
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

/// A message for the stay `stay` of the tests' player.
pub fn for_stay(
  stay stay: Stay,
  sent sent: client_connection.StaySent,
) -> Event(ConnectionEvent(Message, Answer)) {
  OwnEvent(Woken(ForStay(stay:, sent:)))
}

/// The same message as `event`, a message for the tests' player's first stay, for
/// its second: the stay of its next join, after a camp or the Holocrypt.
pub fn in_second_stay(
  event: Event(ConnectionEvent(Message, Answer)),
) -> Event(ConnectionEvent(Message, Answer)) {
  let assert OwnEvent(Woken(ForStay(sent:, ..))) = event
    as "a message for a stay"
  for_stay(stay: map_support.stay(count: 2), sent:)
}

/// A notice of the map to the connection, for the tests' player's first stay.
pub fn sent_by_the_map(
  notice: map.Notice,
) -> Event(ConnectionEvent(Message, Answer)) {
  for_stay(stay: own_stay(), sent: SentByMap(notice))
}

/// The stay of the tests' player's first join: the connection's first.
pub fn own_stay() -> Stay {
  map_support.stay(count: 1)
}

/// The stay of the player of connection `viewer`, as the map's `SeenBy` names it:
/// its `viewer`th, so each viewer's is its own.
pub fn viewer_stay(viewer: Int) -> Stay {
  map_support.stay(count: viewer)
}

/// News of the unit `unit_id` as its owner sends it to the tests' player.
pub fn news_of(unit_id unit_id: Int, news news: News) -> PeerNews {
  PeerNews(unit_id:, news:)
}

/// News of the tests' player's unit as its connection sends it to a viewer.
pub fn told(news news: News) -> PeerNews {
  PeerNews(unit_id: own_unit_id, news:)
}

/// A move of the unit `unit_id`, stamped `server_time_ms`.
pub fn moving(
  unit_id unit_id: Int,
  server_time_ms server_time_ms: Int,
  commands commands: List(relayed_movement.RelayedMovement),
) -> PeerNews {
  news_of(unit_id:, news: Moving(server_time_ms:, commands:))
}

/// A send of another player's connection to the connection, for the tests'
/// player's first stay.
pub fn sent_by_a_peer(
  news: PeerNews,
) -> Event(ConnectionEvent(Message, Answer)) {
  for_stay(stay: own_stay(), sent: SentByPeer(news))
}

/// Another player's unit: the tests' player's own record, as unit 9.
pub fn another_unit() -> UnitCreatePlayer {
  UnitCreatePlayer(..player_in(entered().1), unit_id: 9, name: "Zed Other")
}

pub fn moved_unit_commands() -> List(relayed_movement.RelayedMovement) {
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

/// What can reach a viewer about the unit 9, from the unit's owner or the map.
pub type Step {
  Appears
  Moves
  Removes
  MapSaysGone
}

pub fn event_of(step: Step) -> Event(ConnectionEvent(Message, Answer)) {
  case step {
    Appears ->
      sent_by_a_peer(news_of(unit_id: 9, news: Appeared(unit: another_unit())))
    Moves ->
      sent_by_a_peer(moving(
        unit_id: 9,
        server_time_ms: 7,
        commands: moved_unit_commands(),
      ))
    Removes -> sent_by_a_peer(news_of(unit_id: 9, news: Removed))
    MapSaysGone -> sent_by_the_map(map.Gone(unit_id: 9))
  }
}

/// The tells of a step to the connections of other players: the viewer's
/// number and the news, in the order of the viewers' numbers.
pub fn peer_tells(taken: ConnectionStep(Request)) -> List(#(Int, PeerNews)) {
  list.map(peer_tells_for(taken), fn(tell) { #(tell.0, tell.2) })
}

/// The same, each with the stay it is told for.
pub fn peer_tells_for(
  taken: ConnectionStep(Request),
) -> List(#(Int, Stay, PeerNews)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(
        to: step.Connection(ConnectionId(viewer)),
        request: TellPeer(stay:, news:),
      )) -> Ok(#(viewer, stay, news))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// The tell of `request` to the run of the map that took the tests' player, as the
/// connection's rule asks for it.
pub fn map_tell(
  request request: Request,
) -> step.Effect(step.ConnectionEffect(Request)) {
  OwnEffect(step.Tell(to: Map(map: camp_map(), incarnation:), request:))
}

/// The tells of a step to the map: where each goes and what it says.
pub fn told_the_map(
  taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: Map(..), ..)) -> True
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop -> False
    }
  })
}

/// The state after the map told the connection that these connections see its
/// player.
pub fn watched_by(
  state state: game_connection.State,
  viewers viewers: List(Int),
) -> game_connection.State {
  list.fold(viewers, state, fn(state, viewer) {
    feed(
      state:,
      event: sent_by_the_map(SeenBy(
        by: ConnectionId(viewer),
        stay: viewer_stay(viewer),
      )),
    ).0
  })
}

/// The tests' player's unit id: the map's fifth.
pub const own_unit_id = 5

pub fn zone_group(top_zone_id: Int) -> step.Address {
  step.ZoneChannel(map: camp_map(), incarnation:, top_zone_id:)
}

pub fn terrain_loaded_message(world_zone_id: Int) -> BitArray {
  let assert Ok(body) = terrain_loaded.encode(TerrainLoaded(world_zone_id:))
  world_message(message_id: terrain_loaded.message_id, body:)
}

/// The client's 0x63a: the zone the player left and the zone it entered.
pub fn zone_changed_message(old old: Int, new new: Int) -> BitArray {
  let assert Ok(body) =
    world_zone_changed.encode(WorldZoneChanged(
      old_world_zone_id: old,
      new_world_zone_id: new,
    ))
  world_message(message_id: world_zone_changed.message_id, body:)
}

/// The Medic of level 1 in the world, who presses Paralytic Surge at bag index 2.
pub fn medic_in_world() -> game_connection.State {
  entered_as(Character(..world_character(), class_id: ClassId(4))).0
}

/// The Medic of these tables in the world.
pub fn medic_in(tables tables: store_tables.Tables) -> game_connection.State {
  let fresh = accepted(Settings(..settings(), tables:)).0
  entered_from(
    in_character_select: in_select_from(fresh),
    character: Character(..world_character(), class_id: ClassId(4)),
  ).0
}

/// The place of the Stalker's Stealth in its ability bag: Spell4 46073, whose press
/// starts Stealth 38784 and, when the caster is stealthed, its Cancel 38783
/// (`Spell4Effects` 107792 and 107793, behind Prerequisites 7050 and 8127).
pub const stealth_bag_index = 3

/// A press of the Stalker's Stealth at 1000 ms by a Stalker of the fixture's rows
/// (`settings()`), seen by the connections 2 and 3, and the first press's step. The
/// state is taken to 3000 ms with the cast's timers fired, so a second press at 3000 ms
/// or later is no longer refused as a cast in progress or a recharge (Spell4Effects
/// 159128: 1000 ms out of combat).
pub fn stealthed_stalker() -> #(game_connection.State, ConnectionStep(Request)) {
  stealthed_stalker_in(settings: settings())
}

/// The same on the settings given.
pub fn stealthed_stalker_in(
  settings settings: Settings,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, _) = entered_with(settings:, class_id: 5, saved_health: None)
  let #(state, steps) =
    pressed_until(
      state: watched_by(state:, viewers: [2, 3]),
      bag_index: stealth_bag_index,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
    )
  let assert [pressed, ..] = steps as "the press is the first step"
  #(state, pressed)
}

/// A press of the Stalker's Stealth on tables that keep it on damage
/// (`with_stealth_kept_on_damage`).
pub fn stealthed_stalker_kept_on_damage() -> #(
  game_connection.State,
  ConnectionStep(Request),
) {
  use tables <- with_stealth_kept_on_damage
  stealthed_stalker_in(settings: Settings(..settings(), tables:))
}

/// A second press of the Stalker's Stealth at `ms`, which cancels the stealth held.
pub fn press_stealth_again(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(
    state:,
    ms:,
    event: step.OwnEvent(
      step.Read(world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id:,
          bag_index: stealth_bag_index,
          target: 0,
          press: 1,
        ),
      )),
    ),
  )
}

/// Runs the body on tables where the Stalker's Stealth is kept on damage. The client's
/// Stealth 38784 holds two Stealth rows: 83834, broken by damage, for a caster that holds
/// no Spell4 59389 (Prerequisite 16152), and 95774, kept on damage, for one that does
/// (16153). 59389 is the Stalker's level 70 series cap, which no level 1 character holds,
/// so the two comparisons are swapped to give the caster 95774.
pub fn with_stealth_kept_on_damage(
  body body: fn(store_tables.Tables) -> a,
) -> a {
  let swapped = fn(rows, id, comparison) {
    let assert Ok(rows) =
      fixture_tables.change(rows:, table: "Prerequisite", id:, with: [
        #("prerequisiteComparisonId0", planted_table.Integer(comparison)),
      ])
    rows
  }
  fixture_tables.on_rows(
    rows: swapped(swapped(fixture_tables.rows(), 16_152, 1), 16_153, 2),
    reaching: [],
    body:,
  )
}

/// The step's effects after the first tell to the map, kept to those that write to the
/// client or tell a viewer.
pub fn writes_or_viewer_tells_after_the_map_tell(
  taken taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  support.effects_of(taken)
  |> list.drop_while(fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: Map(..), ..)) -> False
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop -> True
    }
  })
  |> list.drop(1)
  |> list.filter(fn(effect) {
    case effect {
      OwnEffect(step.Write(..))
      | OwnEffect(step.Tell(to: step.Connection(..), ..)) -> True
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop -> False
    }
  })
}

/// The frames the step writes before and after its tell to the map, each in order. The
/// tell stands between the writes that come before it in the step's effects and those
/// that follow.
pub fn written_around_the_map_tell(
  taken taken: ConnectionStep(Request),
) -> #(List(Frame), List(Frame)) {
  let before =
    support.effects_of(taken)
    |> list.take_while(fn(effect) {
      case effect {
        OwnEffect(step.Tell(to: Map(..), ..)) -> False
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          True
      }
    })
    |> list.count(fn(effect) {
      case effect {
        OwnEffect(step.Write(..)) -> True
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          False
      }
    })
  list.split(written(taken:), before)
}

/// The news the step tells the viewer connection `viewer` after its tell to the map.
pub fn news_told_after_the_map_tell(
  taken taken: ConnectionStep(Request),
  viewer viewer: Int,
) -> List(News) {
  let after =
    support.effects_of(taken)
    |> list.drop_while(fn(effect) {
      case effect {
        OwnEffect(step.Tell(to: Map(..), ..)) -> False
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          True
      }
    })
  list.filter_map(after, fn(effect) {
    case effect {
      OwnEffect(step.Tell(
        to: step.Connection(ConnectionId(told)),
        request: TellPeer(news: PeerNews(news:, ..), ..),
      ))
        if told == viewer
      -> Ok(news)
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The cast starts (0x07FF) among these news, in order.
pub fn cast_starts(news: List(News)) -> List(spell_started.SpellStarted) {
  list.filter_map(news, fn(each) {
    case each {
      client_connection.CastStarted(start:) -> Ok(start)
      client_connection.Appeared(..)
      | client_connection.CreatureAppeared(..)
      | client_connection.Moving(..)
      | client_connection.Removed
      | client_connection.CastWent(..)
      | client_connection.CastMissed(..)
      | client_connection.CastTargetsRemoved(..)
      | client_connection.CastStackRemoved(..)
      | client_connection.CastFinished(..)
      | client_connection.Health(..)
      | client_connection.Died
      | client_connection.CameBack
      | client_connection.DeathLogged
      | client_connection.CameBackLogged
      | client_connection.CreatureMoved(..)
      | client_connection.CreaturePlaced(..)
      | client_connection.Targeting(..)
      | client_connection.Threat(..)
      | client_connection.CombatState(..)
      | client_connection.Shield(..)
      | client_connection.InterruptArmor(..)
      | client_connection.Absorption(..)
      | client_connection.Level(..)
      | client_connection.CrowdControlApplied(..)
      | client_connection.CrowdControlEnded(..)
      | client_connection.PropertiesChanged(..)
      | client_connection.Stealth(..)
      | client_connection.LookChanged(..) -> Error(Nil)
    }
  })
}

/// Whether the news takes a cast off some units (0x0811).
pub fn is_cast_removal(news: News) -> Bool {
  case news {
    client_connection.CastTargetsRemoved(..) -> True
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.Level(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> False
  }
}

/// The Medic of these tables in the world, the Beast unit 40 shown before it.
pub fn medic_with_beast_in_world(
  tables tables: store_tables.Tables,
) -> game_connection.State {
  feed(state: medic_in(tables:), event: beast_appears(unit_id: 40)).0
}

/// The 0x262 news of a Beast, as its process sends it, standing 3 m ahead of the
/// Medic, who stands at the place the tests' character is saved at and faces -z.
pub fn beast_appears(
  unit_id unit_id: Int,
) -> Event(ConnectionEvent(Message, Answer)) {
  beast_appears_facing(unit_id:, yaw: 0.0)
}

/// The 0x262 news of a Beast standing where `beast_appears` puts it, its 0x262 giving it
/// the yaw `yaw`.
pub fn beast_appears_facing(
  unit_id unit_id: Int,
  yaw yaw: Float,
) -> Event(ConnectionEvent(Message, Answer)) {
  let place =
    start_place.turned(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 29.128599166870117,
        y: -853.87158203125,
        z: -563.18798828125,
      ),
      facing: start_place.Facing(yaw:, pitch: 0.0, roll: 0.0),
    )
  let beast = spawn_support.beast_at(number: 1, place:)
  sent_by_a_peer(news_of(
    unit_id:,
    news: CreatureAppeared(
      unit: creature_unit.create(
        spawn: beast,
        unit_id:,
        health: 52,
        interrupt_armor: option.None,
        server_time_estimate_start: 0,
      ),
      life: 4,
      place:,
      hit_radius: beast.combat.hit_radius,
      attackable: beast.combat.attackable,
      hostile_to: beast.combat.hostile_to,
    ),
  ))
}

/// A press of Paralytic Surge.
pub fn press_paralytic_surge(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  read(
    state:,
    bytes: world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id:,
        bag_index: 2,
        target: 0,
        press: 1,
      ),
    ),
  )
}

/// A press of Paralytic Surge at the monotonic time `ms`: the spell recharges
/// for a round (Spell4 42352 spellCoolDown), so a press a cast's round later
/// has to be made later.
pub fn press_paralytic_surge_at(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(
    state:,
    ms:,
    event: step.OwnEvent(
      step.Read(world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id:,
          bag_index: 2,
          target: 0,
          press: 1,
        ),
      )),
    ),
  )
}

/// The strikes a step tells the creatures, as the creature's unit and the strike's key.
pub fn strikes_told(
  taken: ConnectionStep(Request),
) -> List(#(Int, strike_tell.Key)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(
        to: step.Creature(unit_id:, ..),
        request: client_connection.TellStrike(tell:),
      )) -> Ok(#(unit_id, tell.key))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The creature's answer that a strike landed, as the connection is sent it.
/// A creature's answer that the strike of `key` landed, for the tests' player's
/// first stay.
pub fn landed(
  key key: strike_tell.Key,
) -> Event(ConnectionEvent(Message, Answer)) {
  for_stay(
    stay: own_stay(),
    sent: client_connection.SentByTarget(answered: strike_tell.Answered(
      key:,
      outcome: strike_tell.Landed(descriptions: [], controls: []),
    )),
  )
}

/// The creature that fights the tests' player: unit 7 of life 3 in the tests' run.
pub fn fighter() -> step.Address {
  step.Creature(map: camp_map(), incarnation:, unit_id: 7, life: 3)
}

/// A creature's tell of its fight, for the tests' player's first stay.
pub fn foe(
  fight: strike_tell.Fight,
) -> Event(ConnectionEvent(Message, Answer)) {
  for_stay(stay: own_stay(), sent: client_connection.SentByFoe(fight:))
}

/// The tells of a step to creatures, as the creature's unit and the request.
pub fn told_creatures(taken: ConnectionStep(Request)) -> List(#(Int, Request)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: step.Creature(unit_id:, ..), request:)) ->
        Ok(#(unit_id, request))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The sequence numbers of the step's tells of a move to the map.
pub fn moves_told(taken: ConnectionStep(Request)) -> List(Int) {
  list.map(told_the_map(taken), fn(effect) {
    let assert OwnEffect(step.Tell(request: TellMoved(seq:, ..), ..)) = effect
      as "the step tells the map a move"
    seq
  })
}

pub fn a_move(x: Float) -> BitArray {
  moves_message([game_client.position_command(x:, y: 2.5, z: 3.5)])
}

/// A creature's strike, of the Beast's offence (12 Physical), on `unit_id`.
pub fn a_beast_strike(unit_id: Int) -> Event(ConnectionEvent(Message, Answer)) {
  foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(cast_id: 2_147_500_000, phase: 0, unit_id:),
        from: fighter(),
        striker: strike_tell.CreatureStriker,
        offence: spawn_support.beast_attack().offence,
        controls: [],
      ),
    ),
  )
}

/// A creature's strike of one blow of `damage` of the damage type `damage_type` (1 Physical,
/// 2 Tech, 3 Magic) on `unit_id`, with no crit chance.
pub fn a_creatures_blow(
  unit_id unit_id: Int,
  damage_type damage_type: Int,
  damage damage: Int,
) -> Event(ConnectionEvent(Message, Answer)) {
  foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(cast_id: 2_147_500_000, phase: 0, unit_id:),
        from: fighter(),
        striker: strike_tell.CreatureStriker,
        offence: Offence(
          blows: [
            Blow(
              spell4_effects_id: 62_159,
              damage_type:,
              damage:,
              delay_ms: 0,
              threat_multiplier: 1.0,
            ),
          ],
          crit_chance: 0.0,
          crit_severity: 1.5,
          strikethrough: 0.0,
        ),
        controls: [],
      ),
    ),
  )
}

/// The connection camped out of the world from `state`: the camp, its save and the
/// map's `Left`, back in character select.
pub fn camp_from(state: game_connection.State) -> game_connection.State {
  let #(state, _) = read(state:, bytes: camp_request_message(True))
  let #(state, taken) = read(state:, bytes: camp_finished_message())
  let #(state, taken) = answer(state:, taken:, outcome: place_saved())
  answer(state:, taken:, outcome: step.Answer(FromMap(Left))).0
}

/// The frames of these ids, decoded by `decode`.
pub fn decoded(
  frames: List(Frame),
  id: Int,
  decode: fn(BitArray) -> Result(a, b),
) -> List(a) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == id {
      True -> decode(frame.body) |> result.replace_error(Nil)
      False -> Error(Nil)
    }
  })
}

/// A creature's strike on the tests' player that kills it at once: the Beast's
/// strike with its blow raised to 100000, a blow no creature of the client strikes,
/// so a test reaches the death in one step. What the death writes does not read
/// the blow.
pub fn a_killing_strike() -> Event(ConnectionEvent(Message, Answer)) {
  let offence = spawn_support.beast_attack().offence
  foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(
          cast_id: 2_147_500_001,
          phase: 0,
          unit_id: own_unit_id,
        ),
        from: fighter(),
        striker: strike_tell.CreatureStriker,
        offence: spawn_support.dealing(offence:, damage: 100_000),
        controls: [],
      ),
    ),
  )
}

/// `state`, fought by the Beast 7 and struck dead: the state, and the step of the
/// killing strike.
pub fn killed(
  state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, _) =
    feed(state:, event: foe(strike_tell.Threatened(unit_id: 7, life: 3)))
  feed(state:, event: a_killing_strike())
}

/// The tests' player in the world, seen by connection 2, struck dead.
pub fn dead_in_world() -> #(game_connection.State, ConnectionStep(Request)) {
  killed(watched_by(state: in_world(), viewers: [2]))
}

/// 0x15a for the unit, the choice and the value, inside 0x038C.
pub fn choice_message(
  unit_id unit_id: Int,
  choice choice: Int,
  value value: Int,
) -> BitArray {
  world_message(
    message_id: 0x015A,
    body: message_support.choice_body(unit_id:, choice:, value:),
  )
}

/// Wake Here, as the Death addon sends it: the player's own unit, 1 and 0.
pub fn wake_here() -> BitArray {
  choice_message(unit_id: own_unit_id, choice: 1, value: 0)
}

/// The Holocrypt, as the Death addon sends it: the player's own unit, 2 and 0.
pub fn holocrypt() -> BitArray {
  choice_message(unit_id: own_unit_id, choice: 2, value: 0)
}

/// A map of the tests' realm that took the tests' player once and let it leave,
/// so its next join is unit 6, as the real map gives a new id to each join.
pub fn map_after_a_stay() -> map.State {
  let #(map_state, _) =
    mapped(map_state: map_with_four_players(), taken: joining().1)
  let #(map_state, left) = mapped(map_state:, taken: leaving_the_map().1)
  assert left == Left
  map_state
}

/// The tests' player dead, after choosing the Holocrypt: the leave asked.
pub fn holocrypt_chosen() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, _) = dead_in_world()
  read(state:, bytes: holocrypt())
}

/// The Holocrypt's leave answered `Left`: the join at the Holocrypt place asked.
pub fn holocrypt_joining() -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = holocrypt_chosen()
  answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
}

/// The Holocrypt's join answered by a map that gave the player's first unit
/// before: the player is in the world as unit 6.
pub fn at_the_holocrypt() -> #(game_connection.State, ConnectionStep(Request)) {
  at_the_holocrypt_in(map_after_a_stay())
}

/// The Holocrypt chosen by the dead player `dead`, its leave answered `Left`
/// and its join answered by a map that gave the player's first unit before.
pub fn at_the_holocrypt_from(
  dead dead: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at_the_holocrypt_from_at(dead:, filetime:)
}

/// The same, with the choice and both answers reaching the connection at this
/// system time, as a FILETIME.
pub fn at_the_holocrypt_from_at(
  dead dead: game_connection.State,
  filetime filetime: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let answered = fn(state, taken: ConnectionStep(Request), outcome) {
    let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
    feed_at(
      state:,
      filetime:,
      event: step.OwnEvent(step.Answered(ask: ask.ask, outcome:)),
    )
  }
  let #(state, taken) =
    feed_at(
      state: dead,
      filetime:,
      event: step.OwnEvent(step.Read(holocrypt())),
    )
  let #(state, taken) = answered(state, taken, step.Answer(FromMap(Left)))
  let #(_, joined) = mapped(map_state: map_after_a_stay(), taken:)
  answered(state, taken, step.Answer(FromMap(joined)))
}

/// The Holocrypt's join answered by the map `map_state`.
pub fn at_the_holocrypt_in(
  map_state: map.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = holocrypt_joining()
  let #(_, joined) = mapped(map_state:, taken:)
  answer(state:, taken:, outcome: step.Answer(FromMap(joined)))
}

/// 0x7ff for the cast `cast_id` of `caster`, as a caster's rule tells it:
/// `opcode.0x7ff`'s fields with the safe values of the decode (0, 1 and 0).
pub fn spell_started_of(
  cast_id cast_id: Int,
  caster caster: Int,
) -> spell_started.SpellStarted {
  let position = spell_position.SpellPosition(x: 0, y: 0, z: 0)
  spell_started.SpellStarted(
    cast_id:,
    spell4_id: 32_893,
    root_spell4_id: 32_893,
    parent_spell4_id: 0,
    caster_unit_id: caster,
    field_6: 0,
    primary_target_unit_id: caster,
    position:,
    yaw: 0,
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// The map's answer to the join, with the loadout these tables give the
/// character's class and faction in place of the planted one.
pub fn with_the_tables_loadout(
  joined joined: map.Outgoing,
  tables tables: store_tables.Tables,
  class_id class_id: Int,
) -> map.Outgoing {
  let assert map.Joined(unit:, incarnation:, clock_origin_ms:, ..) = joined
    as "the map took the player"
  let assert Ok(held) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
    as "the tables hold a Novice set for the class"
  map.Joined(unit:, loadout: held, incarnation:, clock_origin_ms:)
}

/// The connection after the map took a character of the class, with its entry burst,
/// on the client's tables.
pub fn entered_on_the_clients_tables(
  class_id class_id: Int,
  saved_health saved_health: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  entered_with(
    settings: Settings(..settings(), tables: client_tables.shared()),
    class_id:,
    saved_health:,
  )
}

/// The same with these settings; the map's answer carries the loadout their
/// tables give the class.
pub fn entered_with(
  settings settings: game_connection.Settings,
  class_id class_id: Int,
  saved_health saved_health: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) =
    joining_saved(
      in_character_select: in_select_from(accepted(settings).0),
      character: Character(..world_character(), class_id: ClassId(class_id)),
      saved_health:,
    )
  answer(
    state:,
    taken:,
    outcome: step.Answer(
      FromMap(with_the_tables_loadout(
        joined: map_answer(taken),
        tables: settings.tables,
        class_id:,
      )),
    ),
  )
}

/// The tests' player of this class in the world, its connection reading the
/// starting abilities' own trees (`character_tables.shared`), with
/// its unit id and the bag index of the ability of this Spell4Base.
pub fn entered_with_spell_trees(
  class_id class_id: Int,
  ability ability: Int,
) -> #(game_connection.State, Int, Int) {
  entered_with_server_proxies(
    class_id:,
    ability:,
    proxies: server_proxy_support.none(),
    tables: character_tables.shared(),
  )
}

/// The same with the server's Proxies planted into the abilities' trees
/// (genesis_prime/game/server_proxy) and these tables.
pub fn entered_with_server_proxies(
  class_id class_id: Int,
  ability ability: Int,
  proxies proxies: server_proxy.ServerProxies,
  tables tables: store_tables.Tables,
) -> #(game_connection.State, Int, Int) {
  let fresh =
    accepted(Settings(..settings(), tables:, server_proxies: proxies)).0
  let #(state, entered) =
    entered_from(
      in_character_select: in_select_from(fresh),
      character: Character(..world_character(), class_id: ClassId(class_id)),
    )
  let unit_id = player_in(entered).unit_id
  let assert Ok(set) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
    as "the tables hold the class's Novice set"
  let assert Ok(bag_index) =
    list.index_map(set.abilities, fn(base, index) { #(base, index) })
    |> list.key_find(Spell4BaseId(ability))
    as "a level-1 player of the class holds the ability"
  #(state, unit_id, bag_index)
}

/// A step of the connection at the monotonic time `ms`.
pub fn at(
  state state: game_connection.State,
  ms ms: Int,
  event event: step.Event(
    step.ConnectionEvent(client_connection.Message, client_connection.Answer),
  ),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, support.input_at_ms(ms:, event:))
}

/// The step, and each strike it and the steps after it tell a creature answered as
/// landed at `ms`, in order.
pub fn landing(
  state state: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  list.fold(strikes_told(taken), #(state, [taken]), fn(so_far, strike) {
    let #(state, steps) = so_far
    let #(state, answered) = at(state:, ms:, event: landed(key: strike.1))
    let #(state, more) = landing(state:, ms:, taken: answered)
    #(state, list.append(steps, more))
  })
}

/// The cast rule's timers the steps start, due from `ms`, less those they cancel.
pub fn cast_timers(
  steps steps: List(ConnectionStep(Request)),
  ms ms: Int,
) -> List(#(Int, TimerId)) {
  let effects = list.flat_map(steps, support.effects_of)
  let cancelled =
    list.filter_map(effects, fn(effect) {
      case effect {
        OwnEffect(CancelTimer(timer:)) -> Ok(timer)
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          Error(Nil)
      }
    })
  list.filter_map(effects, fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) ->
        case cast.owns(timer:) && !list.contains(cancelled, timer) {
          True -> Ok(#(ms + after_ms, timer))
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// How a step is answered: the world beside the connection (nothing, a creature, a
/// flag), the connection and the monotonic time `ms` in, the world and the connection
/// after, and the steps the answers took, the step itself first (`landing`).
pub type Answering(world) =
  fn(world, game_connection.State, Int, ConnectionStep(Request)) ->
    #(world, game_connection.State, List(ConnectionStep(Request)))

/// The answer where every strike told lands at once (`landing`).
fn landed_at_once(
  world world: Nil,
  state state: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(Nil, game_connection.State, List(ConnectionStep(Request))) {
  let #(state, steps) = landing(state:, ms:, taken:)
  #(world, state, steps)
}

/// The cast rule's timers fired in time order up to `until_ms`, each step answered
/// by `answer`: the connection, the world and every step taken.
pub fn casts_run_answered(
  state state: game_connection.State,
  world world: world,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
  answer answer: Answering(world),
) -> #(game_connection.State, world, List(ConnectionStep(Request))) {
  let #(state, world, _, steps) =
    casts_left_answered(state:, world:, pending:, until_ms:, steps:, answer:)
  #(state, world, steps)
}

/// `casts_run_answered`, and the timers still due after `until_ms` as well, to run on
/// from a later point.
pub fn casts_left_answered(
  state state: game_connection.State,
  world world: world,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
  answer answer: Answering(world),
) -> #(
  game_connection.State,
  world,
  List(#(Int, TimerId)),
  List(ConnectionStep(Request)),
) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let #(state, fired) =
        at(state:, ms: due, event: OwnEvent(TimerFired(timer:)))
      let #(world, state, more) = answer(world, state, due, fired)
      casts_left_answered(
        state:,
        world:,
        pending: list.append(rest, cast_timers(steps: more, ms: due)),
        until_ms:,
        steps: list.append(steps, more),
        answer:,
      )
    }
    sorted -> #(state, world, sorted, steps)
  }
}

/// A press of the bag index at `ms`, and the cast timers it leads to up to
/// `until_ms`, each step answered by `answer`: the connection, the world and every
/// step taken.
pub fn pressed_until_answered(
  state state: game_connection.State,
  world world: world,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
  answer answer: Answering(world),
) -> #(game_connection.State, world, List(ConnectionStep(Request))) {
  let #(state, pressed) =
    at(
      state:,
      ms:,
      event: OwnEvent(
        step.Read(world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id:,
            bag_index:,
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  let #(world, state, steps) = answer(world, state, ms, pressed)
  casts_run_answered(
    state:,
    world:,
    pending: cast_timers(steps:, ms:),
    until_ms:,
    steps:,
    answer:,
  )
}

/// The cast rule's timers fired in time order up to `until_ms`, with every strike
/// landing: the connection and every step taken.
pub fn casts_run(
  state state: game_connection.State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  let #(state, _, steps) =
    casts_run_answered(
      state:,
      world: Nil,
      pending:,
      until_ms:,
      steps:,
      answer: landed_at_once,
    )
  #(state, steps)
}

/// `casts_run`, and the timers still due after `until_ms` as well.
pub fn casts_left(
  state state: game_connection.State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
) -> #(
  game_connection.State,
  List(#(Int, TimerId)),
  List(ConnectionStep(Request)),
) {
  let #(state, _, pending, steps) =
    casts_left_answered(
      state:,
      world: Nil,
      pending:,
      until_ms:,
      steps:,
      answer: landed_at_once,
    )
  #(state, pending, steps)
}

/// A press of the bag index at `ms`, and the cast timers it leads to up to
/// `until_ms`, each strike landing.
pub fn pressed_until(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  let #(state, _, steps) =
    pressed_until_answered(
      state:,
      world: Nil,
      bag_index:,
      client_cast_id:,
      ms:,
      until_ms:,
      answer: landed_at_once,
    )
  #(state, steps)
}

/// A 0x182 of the item at `from` to the empty or other place `to`, as the client sends
/// it, inside 0x038C.
pub fn item_moved_message(
  from from: item_place.ItemPlace,
  to to: item_place.ItemPlace,
) -> BitArray {
  let assert Ok(body) = item_move.encode(item_move.ItemMove(from:, to:))
  world_message(message_id: item_move.message_id, body:)
}

/// The connection that took the client's message that changes a held item at `ms`,
/// asked the store, and was given its answer that the change is saved, at the same
/// time: the state and the step of the answer.
pub fn item_change_saved(
  state state: game_connection.State,
  ms ms: Int,
  message message: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = at(state:, ms:, event: OwnEvent(step.Read(message)))
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  at(
    state:,
    ms:,
    event: OwnEvent(step.Answered(
      ask: ask.ask,
      outcome: step.Answer(FromStore(store.ForItems(store.ItemsSaved))),
    )),
  )
}
