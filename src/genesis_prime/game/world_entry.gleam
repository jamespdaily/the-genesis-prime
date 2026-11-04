//// Entering the world: the client's request to play a character, from the
//// store's read of it, through its map's join, to the messages that put the
//// player in the world. Like character select it is a feature of the game
//// connection's rule (genesis_prime/game/connection): it makes its own asks
//// and takes their answers, and the rule turns its effects into writes, asks
//// and its watch on the map.
////
//// ```
//// 0x07DD play, character id  ─▶ play_requested ─▶ Ask store LoadCharacter(account, id)
//// Loaded(character)          ─▶ loaded         ─▶ Ask map MapId(world, 0): Join(connection, character, place)
////                                                 (or Refused: the rule hands back to select)
//// Joined(unit record, loadout, health, run)
////                            ─▶ joined         ─▶ Send 0xAD, 0x262, 0x19B, 0x111 x 10, 0x1A0, 0x19D,
////                                                 0x6BC, 0x636, 0xF1, 0x61, WatchMap(map, run)
//// NotJoined(reason)          ─▶ joined         ─▶ NotInTheWorld: the rule hands back to select
//// ```
////
//// - **The unit** is the map's: it builds the player's unit when it takes the
////   player (genesis_prime/world_map/map), with the loadout and the maximum
////   health, and answers 0x262's record, which `joined` sends as it is, and the
////   typed loadout and maximum health, which `Entered` keeps. The place the map
////   is given, and 0xAD and 0x262 carry, is bounded (below).
//// - **The order** is the client's: 0xAD first; 0x262 before 0x19B; 0x19B
////   before the loadout, 0x6BC, 0x636 and 0x61 (0x1403b5ad0, 0x14057a630, 0x1403c74d0,
////   and 0x6BC's case 0x1403ecc9b, which does nothing until 0x19B has set the
////   player). 0xF1 sets the flag loading's last stage waits on (0x1403b67e0).
//// - **The loadout** (genesis_prime/game/loadout) is sent after 0x19B, which sets
////   the player, and before 0x61: the Novice armor pieces and shield, each held
////   at the bag index of its slot, then the weapon in slot 16 (0x111 at location
////   0, in bag order), then one ability item per level-1 spell (0x111 at
////   location 4, bag index from 0), then the tier 1 of each ability in action
////   sets 0 to 3 (0x1A0) and action set 0 with the abilities in bar slots 0 to 2
////   (0x19D) (`opcode.0x111.ability_bag`, `opcode.0x1a0`, `opcode.0x19d`). Without
////   the weapon the client hides the bar and refuses the abilities that need
////   one (`lua.ActionBarFrame.InitializeBars`, `0x1403afb10`). Holding an item
////   draws nothing: the worn set is drawn by the item visuals the map's unit
////   carries in its 0x262 (genesis_prime/world_map/player_unit,
////   `opcode.0x262.worn_visuals`). The unit's 0x262 also carries the gear's
////   health, shield and properties (`player_unit.create`).
//// - **0xAD** carries the saved world and position, and 0.0 in its last two
////   floats, which neither entry path reads (opcode.0xad.last_floats). The
////   position, here and in 0x262, is bounded to the box the client bounds a
////   unit's position to (`start_place.within_the_worlds_box`), because the
////   client's world load keeps 0xAD's as sent (opcode.0xad.position); the
////   place the character is saved at is not bounded.
//// - **0x6BC** carries the character's stored path, experience 0 on each of the
////   four paths (path level 1), only the character's own path unlocked and
////   -1.0 days since the last path change, which leaves no change cooldown
////   (opcode.0x6bc). The client's path tracker reads the path and the levels.
//// - **0x636** carries the player's unit id, the value 0 and the reset bit
////   1 (vector.opcode.0x636.body); the client echoes the value in 0x635.
//// - **0xF1:** Normal difficulty 0, prime level 0, flags 0, for an open world
////   (opcode.0xf1.fields), and the send interval 125 ms, the client's own
////   until 0xF1 arrives (opcode.0xf1); a value below 25 is raised to 25.
//// - **0x19B:** the player's unit id; its second value is never read, 0
////   (opcode.0x19b.second_value).
//// - **Refused.** A character the account does not have, or one with no
////   saved place (world 0, made before create wrote the start place), is not
////   entered: a warning, and the rule hands back to character select, which
////   sends 0x0162 Failed and the list again, as before world entry
////   (opcode.0x162.after_create).
//// - **A join the map refuses** (`map.NotJoined`: the character's class and
////   faction have no Novice set, or its level has no Base Health row) is not
////   entered: a warning, and the rule hands back to character select as for a
////   character with no saved place.
//// - **An answer that is none of the ask out** (the map's while the store is
////   asked, or the reverse, or the map's `Left`, which answers a leave)
////   is `Error(Nil)`, as character select gives, and the
////   rule treats it as a bug.
//// - **Instance 0** for every world: open worlds share one instance
////   (genesis_prime/world_map/map_id), so an instanced world has no instance
////   to ask for.

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/chat
import genesis_prime/game/chat_tell
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/message/action_set.{ActionSet}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/float32
import genesis_prime/message/item_added.{ItemAdded}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/player_path.{PlayerPath}
import genesis_prime/message/shared_item.{SharedItem}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/store.{
  type AccountId, type Character, type CharacterId, type SessionEpoch,
  CharacterId,
}
import genesis_prime/table/id.{type Spell4BaseId}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/unit_fields
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}

/// What world entry asks or sends; the game connection's rule turns each into
/// its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to `loaded`.
  AskStore(request: store.WorldRequest)
  /// Ask the map; its answer comes back to `joined`.
  AskMap(map: MapId, message: map.Message)
  /// Send this message to the client, in the game wrapper under the
  /// connection's cipher.
  Send(frame: Frame)
  /// Watch the run of the map that took the player: its end comes back to the
  /// connection's rule.
  WatchMap(map: MapId, incarnation: Int)
}

/// Why the client's request to play is refused: its body is one the client's
/// own reader would refuse. The connection ends.
pub type Refusal {
  NotDecoded(undecoded: client_connection.Undecoded)
}

/// Where world entry is.
pub opaque type State {
  /// The store is asked for the character.
  Loading(character_id: CharacterId)
  /// The map is asked to take the character at its saved place, which this
  /// login holds as the epoch `session_epoch`.
  Joining(
    character: Character,
    place: Place,
    session_epoch: SessionEpoch,
    map: MapId,
  )
}

/// What the store's read of the character leads to.
pub type Loaded {
  /// The map is asked to take the player.
  Join(state: State, effects: List(Effect))
  /// The character is not entered; character select refuses the play.
  Refused(character_id: Int, warning: String)
}

/// What the map's answer to the join leads to.
pub type Joined {
  /// The player is in the world: what it keeps, and the messages that put it
  /// there.
  InTheWorld(entered: Entered, effects: List(Effect))
  /// The map refused the character (`map.NotJoined`); character select refuses
  /// the play, as it does for a character with no saved place.
  NotInTheWorld(character_id: Int, warning: String)
}

/// A player in the world: its character, its map, the run of the map that took
/// it, which the rule watches as `Map(map, incarnation)`, its unit id, the
/// origin of the map's clock (`Joined` carries it), its loadout and maximum
/// health (typed, from the tables: the weapon, the abilities and the gear's
/// properties, which the 0x262 carries as bits), its own 0x262 record
/// (`Joined`'s unit, which the connection sends the players who see it), who
/// sees it, the units its own client shows, the casts of other units its client
/// has been sent the start of, where it stands
/// (genesis_prime/game/movement), whether its client has sent the stay's first 0xF2, its
/// health, shield and the creatures it fights (genesis_prime/game/player_life),
/// and whether it is camping
/// (genesis_prime/game/camp), its casts (genesis_prime/game/cast), the rounds of
/// its strikes (genesis_prime/game/strike) and its chat
/// (genesis_prime/game/chat), which the rule keeps up to date. A player that has
/// just entered is not camping, has no viewers and shows no unit: the map's
/// `Watched` and `Unwatched` keep `viewers`, the connections whose players see
/// this one, the connection sends everything about the player's own unit to them,
/// and `shown` and `gone` are the units its client holds and the ones the map
/// reported gone (genesis_prime/game/connection).
pub type Entered {
  Entered(
    character_id: CharacterId,
    map: MapId,
    incarnation: Int,
    unit_id: Int,
    unit: UnitCreatePlayer,
    loadout: Loadout,
    max_health: Int,
    clock_origin_ms: Int,
    viewers: Set(ConnectionId),
    shown: shown.Picture,
    casts_written: Dict(Int, Int),
    gone: Set(Int),
    movement: movement.State,
    readiness: Readiness,
    life: player_life.Life,
    camp: camp.Camp,
    cast: cast.State,
    strike: strike.State,
    chat: chat.Chat,
  )
}

/// Whether the player's client has finished loading the world: the connection
/// tells its map `Ready` once, at the stay's first 0xF2 (`opcode.0xf2`), so no
/// creature fights a loading player.
pub type Readiness {
  ClientLoading
  ClientReady
}

/// The shield a player enters the world with: the stat 20 its client was told in
/// its 0x262 (`player_unit.create`), or 0 when the unit holds none.
fn full_shield(unit unit: UnitCreatePlayer) -> Int {
  unit_fields.stat(tail: unit.tail, stat_id: unit_fields.shield_stat)
  |> result.unwrap(0)
}

/// The process whose answer world entry waits for, for the log line of an ask
/// that gets none.
pub type Awaiting {
  AwaitingStore
  AwaitingMap
}

/// The movement send interval 0xF1 carries, in milliseconds: 125, the
/// client's own until 0xF1 arrives (opcode.0xf1, 0x140c3a004). The client
/// raises a value below 25 to 25.
const movement_send_interval_ms = 125

/// The experience each path starts with: 0, which the client turns into path
/// level 1 (opcode.0x6bc, PathLevel.pathXP). No path experience is stored.
const starting_path_experience = 0

/// The days since the last path change 0x6BC carries: -1.0, so the client's
/// change cooldown (GameFormula 2366: 1800 seconds from the last change) has
/// run out. No path change is stored (opcode.0x6bc).
const path_change_days = -1.0

/// The instance every world is entered at: open worlds share one.
const open_world_instance = 0

/// The client's 0x07DD, whose body is decoded for this account: the store is
/// asked for the character, or the body is refused.
pub fn take(
  account_id account_id: AccountId,
  body body: BitArray,
) -> Result(#(State, List(Effect)), Refusal) {
  play_character.decode(body)
  |> client_connection.decoded(message_id: play_character.message_id)
  |> result.map_error(NotDecoded)
  |> result.map(fn(request) { play_requested(account_id:, request:) })
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}

/// The client's 0x07DD, read for this account: the store is asked for the
/// character.
fn play_requested(
  account_id account_id: AccountId,
  request request: PlayCharacter,
) -> #(State, List(Effect)) {
  #(Loading(character_id: CharacterId(request.character_id)), [
    AskStore(request: store.LoadCharacter(
      account_id:,
      character_id: CharacterId(request.character_id),
    )),
  ])
}

/// Whose answer is awaited.
pub fn awaiting(state state: State) -> Awaiting {
  case state {
    Loading(..) -> AwaitingStore
    Joining(..) -> AwaitingMap
  }
}

/// The store's answer to `play_requested`'s ask: the map is asked to take the
/// character at its saved world, or the play is refused, for a character the
/// account does not have or one with no saved place. With no read asked for,
/// it is none this module asked for and gives an `Error`.
pub fn loaded(
  state state: State,
  answer answer: store.WorldAnswer,
  connection connection: ConnectionId,
) -> Result(Loaded, Nil) {
  case state {
    Loading(character_id: CharacterId(character_id)) ->
      Ok(case answer {
        store.NotTheAccounts ->
          Refused(
            character_id:,
            warning: "a play of character "
              <> int.to_string(character_id)
              <> ", which the account does not have",
          )
        store.CharacterLoaded(character:, session_epoch:) ->
          case character.place {
            None ->
              Refused(
                character_id:,
                warning: "a play of character "
                  <> int.to_string(character_id)
                  <> ", which has no saved place",
              )
            Some(place) -> {
              let sent = start_place.within_the_worlds_box(place)
              let map =
                MapId(
                  world_id: start_place.world_id(place),
                  instance: open_world_instance,
                )
              Join(
                state: Joining(character:, place:, session_epoch:, map:),
                effects: [
                  AskMap(
                    map:,
                    message: map.Join(connection:, character:, place: sent),
                  ),
                ],
              )
            }
          }
      })
    Joining(..) -> Error(Nil)
  }
}

/// The map's answer to `loaded`'s ask: the messages that put the player in
/// the world, in the client's order, then the watch on the run of the map that
/// took it. With no join asked for, it is none this
/// module asked for and gives an `Error`.
pub fn joined(
  state state: State,
  answer answer: map.Outgoing,
  realm_id realm_id: Int,
  next_whisper next_whisper: Int,
) -> Result(Joined, Nil) {
  case state {
    Joining(character:, place:, session_epoch:, map:) -> {
      case answer {
        map.Joined(unit:, loadout:, max_health:, incarnation:, clock_origin_ms:) -> {
          let sent = start_place.within_the_worlds_box(place)
          let unit_id = unit.unit_id
          let CharacterId(character_id_number) = character.character_id
          Ok(InTheWorld(
            entered: Entered(
              character_id: character.character_id,
              map:,
              incarnation:,
              unit_id:,
              unit:,
              loadout:,
              max_health:,
              clock_origin_ms:,
              viewers: set.new(),
              shown: dict.new(),
              casts_written: dict.new(),
              gone: set.new(),
              movement: movement.entered(place:, session_epoch:),
              readiness: ClientLoading,
              life: player_life.new(
                health: max_health,
                shield: full_shield(unit:),
              ),
              camp: camp.none(),
              cast: cast.new(),
              strike: strike.new(),
              chat: chat.new(
                speaker: chat_tell.Speaker(
                  realm_id:,
                  character_id: character_id_number,
                  name: character.name,
                  faction_id: character.faction_id,
                  unit_id:,
                  map:,
                  incarnation:,
                ),
                next_whisper:,
              ),
            ),
            effects: list.flatten([
              [
                enter_world(place: sent),
                player_created(unit:),
                unit_is_player(unit_id:),
              ],
              loadout_sent(character_number: character_id_number, loadout:),
              [
                player_path(character:),
                control_granted(unit_id:),
                movement_interval(),
                entered_world(),
                WatchMap(map:, incarnation:),
              ],
            ]),
          ))
        }
        map.NotJoined(reason:) -> {
          let CharacterId(character_id) = character.character_id
          Ok(NotInTheWorld(
            character_id:,
            warning: "the map refused the join of character "
              <> int.to_string(character_id)
              <> ": "
              <> map.describe_not_joined(reason:),
          ))
        }
        map.Left
        | map.Watched(..)
        | map.Unwatched(..)
        | map.Gone(..)
        | map.Retire
        | map.Approached(..)
        | map.Withdrew(..) -> Error(Nil)
      }
    }
    Loading(..) -> Error(Nil)
  }
}

/// 0xAD with the saved world and position, and 0.0 in the last two floats.
fn enter_world(place place: Place) -> Effect {
  let assert Ok(body) =
    enter_world.encode(EnterWorld(
      world_id: start_place.world_id(place),
      position_x: float32.to_bits(start_place.x(place)),
      position_y: float32.to_bits(start_place.y(place)),
      position_z: float32.to_bits(start_place.z(place)),
      field_5: float32.to_bits(0.0),
      field_6: float32.to_bits(0.0),
    ))
    as "a saved world of the table's 15 bits and a position's floats fit the message"
  Send(Frame(message_id: enter_world.message_id, body:))
}

/// 0x262 for a unit, as the map built it: the entry burst's own player and
/// another player's unit that comes into sight are written the same way.
pub fn unit_created_frame(unit unit: UnitCreatePlayer) -> Frame {
  let assert Ok(body) = unit_create_player.encode(unit)
    as "a stored character's values fit the message's fields: the table's checks hold each"
  Frame(message_id: unit_create_player.message_id, body:)
}

/// 0x262 for the player, as the map built its unit.
fn player_created(unit unit: UnitCreatePlayer) -> Effect {
  Send(unit_created_frame(unit:))
}

/// 0x19B with the player's unit id and 0, which the client never reads
/// (opcode.0x19b.second_value).
fn unit_is_player(unit_id unit_id: Int) -> Effect {
  let assert Ok(body) =
    unit_is_player.encode(UnitIsPlayer(unit_id:, field_2: 0))
    as "a unit id of 32 bits fits the message"
  Send(Frame(message_id: unit_is_player.message_id, body:))
}

/// 0x6BC with the character's stored path as its only unlocked path, and the
/// starting experience and change days (opcode.0x6bc).
fn player_path(character character: Character) -> Effect {
  let assert Ok(body) =
    player_path.encode(PlayerPath(
      path: character.path,
      soldier_experience: starting_path_experience,
      settler_experience: starting_path_experience,
      scientist_experience: starting_path_experience,
      explorer_experience: starting_path_experience,
      unlocked_paths: int.bitwise_shift_left(1, character.path),
      last_path_change_days: float32.to_bits(path_change_days),
    ))
    as "a stored path of 0 to 3 fits the message's 3 bits, and its bit fits the 4 unlocked-path bits"
  Send(Frame(message_id: player_path.message_id, body:))
}

/// 0x636 with the value 0, the reset bit 1 and the player's unit id
/// (vector.opcode.0x636.body).
fn control_granted(unit_id unit_id: Int) -> Effect {
  let assert Ok(body) =
    client_control_granted.encode(ClientControlGranted(
      echo_value: 0,
      reset_movement: 1,
      unit_id:,
    ))
    as "a unit id of 32 bits fits the message"
  Send(Frame(message_id: client_control_granted.message_id, body:))
}

/// 0xF1 with difficulty 0, prime level 0, flags 0 and the client's own
/// movement send interval (opcode.0xf1.fields).
fn movement_interval() -> Effect {
  let assert Ok(body) =
    movement_send_interval.encode(MovementSendInterval(
      world_difficulty: 0,
      world_prime_level: 0,
      world_flags: 0,
      interval_milliseconds: movement_send_interval_ms,
    ))
    as "the message's fields fit their values"
  Send(Frame(message_id: movement_send_interval.message_id, body:))
}

/// 0x61, whose body is empty.
fn entered_world() -> Effect {
  let assert Ok(body) = player_entered_world.encode(PlayerEnteredWorld)
    as "an empty body encodes"
  Send(Frame(message_id: player_entered_world.message_id, body:))
}

/// The location of the held items that are equipped: the armor pieces and the
/// shield, each at the bag index of its slot, and the weapon, in the slot the
/// loadout names (`0x1403afb10`, `ItemSlot.equippedSlotFlags`).
const equipped_location = 0

/// The location of the held items that are abilities (`opcode.0x111.ability_bag`).
const ability_location = 4

/// The reason an item is added for when it is held from the start: 49, which
/// adds an ability without raising the ability book's change
/// (`opcode.0x111.ability_bag`) and, as every reason but 27, shows the ability
/// in its bar slot (`0x1403c1bf0`).
const held_from_the_start = 49

/// The action sets an ability book entry holds, 0 to 3 (`opcode.0x1a0`).
const action_sets = [0, 1, 2, 3]

/// The tier every ability starts at (`opcode.0x1a0`: tier 0 counts as 1).
const first_tier = 1

/// The result of an action set the client takes as ok (`opcode.0x19d`).
const action_set_ok = 1

/// The action set shown until a message changes it (`opcode.0x19d`).
const first_action_set = 0

/// The shortcut type of an ability, by its Spell4Base id (`opcode.0x19d`).
const ability_shortcut = 4

/// The 2-bit value of an action set: bit 0 set marks the set unlocked, which the
/// ability book's set arrows and the active set's switch read; nothing in casting
/// or the bar reads it (`opcode.0x19d.set_value`). Set 0, the active set, is
/// unlocked.
const set_unlocked = 1

/// The loadout's messages, in order: each armor piece and the shield, the
/// weapon, each ability, the tiers and action set 0.
fn loadout_sent(
  character_number character_number: Int,
  loadout loadout: Loadout,
) -> List(Effect) {
  let armor =
    list.map(loadout.armor, fn(piece) {
      held_item(
        character_number:,
        item_id: piece.item.value,
        location: equipped_location,
        bag_index: piece.bag_index,
      )
    })
  let weapon =
    held_item(
      character_number:,
      item_id: { loadout.weapon }.value,
      location: equipped_location,
      bag_index: loadout.weapon_slot,
    )
  let abilities =
    list.index_map(loadout.abilities, fn(ability, bag_index) {
      held_item(
        character_number:,
        item_id: ability.value,
        location: ability_location,
        bag_index:,
      )
    })
  list.flatten([
    armor,
    [weapon],
    abilities,
    [
      ability_tiers_frame(abilities: loadout.abilities),
      action_set_frame(abilities: loadout.abilities),
    ],
  ])
}

/// 0x111 for an item the character holds, a stack of 1 with no charges and full
/// durability. The guid is `loadout.item_guid`. Every value the client's code does not name is 0
/// (`opcode.0x111.shared_item_unnamed`), the lists empty.
fn held_item(
  character_number character_number: Int,
  item_id item_id: Int,
  location location: Int,
  bag_index bag_index: Int,
) -> Effect {
  let assert Ok(body) =
    item_added.encode(ItemAdded(
      item: SharedItem(
        item_guid: loadout.item_guid(character_number:, location:, bag_index:),
        field_2: 0,
        item_id:,
        location:,
        bag_index:,
        stack_count: 1,
        charges: 0,
        field_8: 0,
        field_9: 0,
        field_10: 0,
        durability: float32.to_bits(1.0),
        field_12: 0,
        field_13: 0,
        field_14: 0,
        field_15: 0,
        field_16: 0,
        field_17: 0,
        field_18: 0,
        field_19: 0,
        field_20: 0,
        field_21: 0,
        field_22: 0,
        field_23: 0,
        list_a: [],
        list_b: [],
        field_27: 0,
      ),
      reason: held_from_the_start,
    ))
    as "an item of 18 bits, a location of 9 and a guid of 64 bits, a character number below 2^23, fit the message"
  Send(Frame(message_id: item_added.message_id, body:))
}

/// 0x1A0 with tier 1 of each ability in each action set.
fn ability_tiers_frame(abilities abilities: List(Spell4BaseId)) -> Effect {
  let assert Ok(body) =
    ability_tiers.encode(
      AbilityTiers(
        tiers: list.flat_map(abilities, fn(ability) {
          list.map(action_sets, fn(action_set_index) {
            AbilityTier(
              spell4_base_id: ability.value,
              tier: first_tier,
              action_set_index:,
            )
          })
        }),
      ),
    )
    as "a Spell4Base id of 18 bits, a tier of 4 and a set of 3 fit the message"
  Send(Frame(message_id: ability_tiers.message_id, body:))
}

/// 0x19D for action set 0, the abilities in bar slots 0, 1 and 2. A shortcut
/// of type 4 names an ability by its Spell4Base id; the client reads its
/// location for no type 4 shortcut (`0x1403c1bf0`), so it is the ability
/// location.
fn action_set_frame(abilities abilities: List(Spell4BaseId)) -> Effect {
  let assert Ok(body) =
    action_set.encode(ActionSet(
      action_set_index: first_action_set,
      field_2: set_unlocked,
      result: action_set_ok,
      shortcuts: list.index_map(abilities, fn(ability, slot) {
        ActionShortcut(
          shortcut_type: ability_shortcut,
          location: ability_location,
          bag_index: slot,
          object_id: ability.value,
        )
      }),
    ))
    as "a bar slot below 48 and an id of 32 bits fit the message"
  Send(Frame(message_id: action_set.message_id, body:))
}
