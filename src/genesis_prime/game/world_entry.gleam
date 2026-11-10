//// Entering the world: the client's request to play a character, from the
//// store's read of it, through its map's join, to the messages that put the
//// player in the world. Like character select it is a feature of the game
//// connection's rule (genesis_prime/game/connection): it makes its own asks
//// and takes their answers, and the rule turns its effects into writes, asks
//// and its watch on the map.
////
//// ```
//// 0x07DD play, character id  ─▶ play_requested ─▶ Ask store LoadCharacter(account, id)
//// Loaded(character)          ─▶ loaded         ─▶ Ask map MapId(world, 0): Join(connection, character, place, stay, alive)
////                                                 (or Refused, for a level with no XpPerLevel row too: the rule hands back to select)
//// Joined(unit record, loadout, run)
////                            ─▶ joined         ─▶ Send 0xAD, 0x262, 0x19B, 0x92C, 0x25E (a play only), 0x111 x 10 (x 11 with an
////                                                 innate), 0x1A0, 0x19D, 0x19F (with an innate), 0x6BC, 0x636, 0xF1, 0x61,
////                                                 WatchMap(map, run), StartPassive (with an innate passive)
////                                                 (a player saved dead: the ghost's 0x262 and
////                                                 0x1B3 before 0x636, which names the ghost)
//// NotJoined(reason)          ─▶ joined         ─▶ NotInTheWorld: the rule hands back to select
//// the Holocrypt, map left    ─▶ rejoining      ─▶ Ask map of the place's world: Join(connection, character, place, stay, alive: True)
////                                                 (then Joined and NotJoined as above)
//// ```
////
//// - **The unit** is the map's: it builds the player's unit when it takes the
////   player (genesis_prime/world_map/map), with the body's visuals and the loadout,
////   and answers 0x262's record and the typed loadout. `joined` works out the gear
////   from the items the character holds at location 0 (genesis_prime/game/gear), which
////   `Entered` keeps, writes its item visuals and properties into the record, and sends
////   it with the health the player enters at as stat 0. A level the tables have no Base
////   Health row for is `GearFault`: the connection is ended with an error. A play enters at the health its last save kept,
////   capped at the maximum, and at full health when none was kept; the
////   Holocrypt's join enters at full health (`player_life.entering`; the
////   server's choice). A play that enters below its maximum health starts the
////   health tick (genesis_prime/game/player_life), the one timer entry starts. The place the map is given, and 0xAD and 0x262 carry, is
////   bounded (below).
//// - **A player saved dead** (saved health 0, `player_life.entering`) enters
////   dead: its own 0x262 carries stat 0 = 0, which the client creates dead and
////   refuses nothing for (`0x140457bc5`); the ghost's 0x262 at the saved place,
////   0x1B3 with dead 1 (after 0x19B, before which it fails quietly,
////   `opcode.0x1b3.before_player`) and the entry's 0x636, which names the ghost,
////   follow the 0x6BC in that order; no 0x88C and no 0x89A is sent
////   (`death.enter_dead`, `death.player_branch`), and no regeneration starts. Its
////   shield is 0 in its own 0x262 and its viewers' (`player_life.entering`).
//// - **The order** is the client's: 0xAD first; 0x262 before 0x19B; 0x19B
////   before the loadout, 0x6BC, 0x636 and 0x61 (0x1403b5ad0, 0x14057a630, 0x1403c74d0,
////   and 0x6BC's case 0x1403ecc9b, which does nothing until 0x19B has set the
////   player). 0xF1 sets the flag loading's last stage waits on (0x1403b67e0).
//// - **0x92C** is the player's reward properties, BagSlots and BankSlots at the premium
////   tier the client was sent (genesis_prime/game/reward_property), sent right after
////   0x19B at every play and join. Without it the client holds 0 bag slots and
////   refuses every bag in a bag slot (`opcode.0x92c`). Its place in the burst is the
////   server's own choice; the client does not prove it.
//// - **0x25E** is the player character's own state (genesis_prime/game/character_state),
////   sent once per play right after 0x19B, which sets the player its handler needs
////   (`opcode.0x25e.entry_order`). Its handler raises `CharacterCreated`, which the class
////   resource bar waits for. A play from character select, a character switch included,
////   makes the client a new game object, which needs its own copy; the Holocrypt's join is
////   a 0xAD in the world on the same game object (`0x1403b6de0`), where a second copy would
////   add its items and pets again, so it sends none. The frame is built when the store
////   answers, before the map is asked: a character whose level has no XpPerLevel row is
////   refused then, so no unit of it reaches the map. The load requires a Class row for
////   each playable class (`character_state.requirements`).
//// - **0x35F** is the player's quest log (genesis_prime/game/quest_log), sent right
////   after the 0x25E at every play, an empty log included, because the 0x25E empties
////   what the client holds of it (`opcode.0x35f.entry_order`). The log belongs to the
////   client's process, not to a game object, so the Holocrypt's join sends none
////   (`quest_log.process_wide`). The log the connection keeps remembers the reset time
////   the message carried. A saved log the client would refuse fails the load, before
////   the map is asked.
//// - **The held items** are the character's saved rows (`store.HeldItem`): each is
////   sent as a 0x111 with its own guid, item id, location, bag index and stack
////   count, in location then bag index order, after 0x19B, which sets the player,
////   and before 0x61. A Novice character holds its armor pieces and shield, each
////   at the bag index of its slot, and the weapon in slot 16 (location 0), as
////   its creation saved them.
//// - **The loadout** (genesis_prime/game/loadout) is sent after the held items:
////   one ability item per level-1 spell and the class's innate (0x111 at
////   location 4, bag index from 0: the abilities, then the innate's Spell4Base
////   at index 3; abilities are not saved, so their guid is `loadout.item_guid`,
////   `opcode.0x111.ability_guid`), then the tier 1 of each of them in action
////   sets 0 to 3 (0x1A0) and action set 0 with the abilities in bar slots 0 to 2
////   (0x19D; the innate is in no action set), then, with an innate, 0x19F {0}, which
////   points the innate button at slot 0 (`opcode.0x111.ability_bag`, `opcode.0x1a0`,
////   `opcode.0x19d`, `opcode.0x19f`, `lua.ActionBarFrame.ActionBarInnate`). Without
////   the weapon the client hides the bar and refuses the abilities that need
////   one (`lua.ActionBarFrame.InitializeBars`, `0x1403afb10`). Holding an item
////   draws nothing: the worn set is drawn by the item visuals the map's unit
////   carries in its 0x262 (genesis_prime/world_map/player_unit,
////   `opcode.0x262.worn_visuals`). The unit's 0x262 also carries the gear's
////   health, shield and properties (`player_unit.create`), and the player's own
////   carries its class resource's slot at its start and the slot's maximum
////   (`player_unit.with_resource`, genesis_prime/game/class_resource), which the
////   player then holds.
//// - **The innate's passive** is never cast by the client, so the entry's last effect
////   starts it (`StartPassive`, genesis_prime/game/cast `passive_started`), after the
////   entry's writes and the watch on the map, at each join: a play and the Holocrypt's
////   join (`Class.spell4IdInnateAbilityPassive00`).
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
////   faction have no Novice set) is not
////   entered: a warning, and the rule hands back to character select as for a
////   character with no saved place.
//// - **An answer that is none of the ask out** (the map's while the store is
////   asked, or the reverse, or the map's `Left`, which answers a leave)
////   is `Error(Nil)`, as character select gives, and the
////   rule treats it as a bug.
//// - **The stay** (genesis_prime/world_map/stay) is the one the connection gives
////   each join, after every earlier one; `Entered` keeps it, and the connection
////   takes a message another process sent for the player's stay only when it
////   names that one.
//// - **Instance 0** for every world: open worlds share one instance
////   (genesis_prime/world_map/map_id), so an instanced world has no instance
////   to ask for.

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/character_state
import genesis_prime/game/chat
import genesis_prime/game/chat_tell
import genesis_prime/game/class_resource
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/experience
import genesis_prime/game/gear.{type Gear}
import genesis_prime/game/innate
import genesis_prime/game/inventory
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/look
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/reward_property
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike
import genesis_prime/game/unit_properties
import genesis_prime/game/vendor
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/message/action_set.{ActionSet}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/float32
import genesis_prime/message/innate_index_set.{InnateIndexSet}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/player_path.{PlayerPath}
import genesis_prime/message/reward_properties
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/step.{type ConnectionId, type Now}
import genesis_prime/store.{
  type AccountId, type Character, type CharacterId, CharacterId,
}
import genesis_prime/table/id.{
  type Item2Id, type Spell4BaseId, type UnitProperty2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
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
  /// What the player's life decided at entry (`player_life.entering`), which the
  /// connection carries out as it does a fight's (genesis_prime/game/connection/
  /// life_effect): a player that enters below its maximum health starts its
  /// health timer, and one that enters dead is written its ghost, the window and
  /// control of the ghost.
  Life(effects: List(player_life.Effect))
  /// Start the player's innate passive, the spell with this Spell4Base, which the
  /// plans hold.
  StartPassive(base: Spell4BaseId)
  /// A line for the log at the warning level.
  Warn(text: String)
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
  /// The map is asked to take the character at `place`, with the movement it
  /// enters with: at a play, the saved place as the login whose epoch the store
  /// gave; at the Holocrypt, the stay's own movement placed there, so its saves
  /// go on numbered after the earlier ones (`movement.placed`). `saved_health`
  /// is the health the character's last save kept, which a play enters at
  /// (`player_life.entering`) and the Holocrypt's join does not have: it enters
  /// at full health. `experience` is what the character enters with
  /// (`experience.entering`; the Holocrypt's join keeps the stay's own). `items`
  /// are the items the character holds, which the Holocrypt's join keeps from the
  /// stay it leaves. `quests` is the quest log the character holds
  /// (genesis_prime/game/quest_log), which the Holocrypt's join keeps from the
  /// stay it leaves as well. `buyback` is the list the player has to buy back
  /// (genesis_prime/game/vendor_sale): a play starts it empty and the Holocrypt's join
  /// keeps the stay's own, as the client keeps its Buyback tab across the world
  /// change (only a 0xBC replaces it).
  Joining(
    character: Character,
    place: Place,
    movement: movement.State,
    saved_health: Option(Int),
    experience: Int,
    items: List(store.HeldItem),
    currencies: Currencies,
    quests: QuestLog,
    buyback: Buyback,
    map: MapId,
    stay: Stay,
    entry: Entry,
  )
}

/// Which way the player comes into a world: a play from character select, which
/// the client starts a new game object for and so needs its 0x25E (the frame,
/// built before the map is asked), or the Holocrypt's join, a 0xAD in the world on
/// the same game object, which sends none.
type Entry {
  PlayEntry(character_state: Frame)
  HolocryptEntry
}

/// What the store's read of the character leads to.
pub type Loaded {
  /// The map is asked to take the player.
  Join(state: State, effects: List(Effect))
  /// The character is not entered; character select refuses the play.
  Refused(character_id: Int, warning: String)
  /// The character's saved quest log holds an entry the client would refuse. Only
  /// the server writes the log, so it is a bug of the server's, and nothing
  /// repairs the row: the connection is ended and the text is logged as an error.
  Fault(text: String)
}

/// What the map's answer to the join leads to.
pub type Joined {
  /// The player is in the world: what it keeps, and the messages that put it
  /// there.
  InTheWorld(entered: Entered, effects: List(Effect))
  /// The map refused the character (`map.NotJoined`); character select refuses
  /// the play, as it does for a character with no saved place.
  NotInTheWorld(character_id: Int, warning: String)
  /// The tables have no Base Health row for the character's level, so its maximum
  /// health is unknown: no unit of it is made, the connection is ended and the text,
  /// which names the level, is logged as an error.
  GearFault(text: String)
}

/// A player in the world: its character as the store loaded it (which a join at
/// the Holocrypt asks the map with again), the place it entered this stay at, the
/// stay its join named, its map, the run of the map that took it, which the rule watches as
/// `Map(map, incarnation)`, its unit id, the
/// origin of the map's clock (`Joined` carries it), its loadout (typed, from the
/// tables: the abilities and the innate), its gear (what the items it holds at
/// location 0 give: the weapon, the visuals and the properties the 0x262 carries as bits,
/// genesis_prime/game/gear), its own 0x262 record
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
/// `SeenBy` and `UnseenBy` keep `viewers`, the connections whose players see
/// this one, each with its player's stay as the map named it, the
/// connection sends everything about the player's own unit to them, and `shown`
/// and `gone` are the units its client holds and the ones the map reported gone
/// (genesis_prime/game/connection).
pub type Entered {
  Entered(
    character: Character,
    entered_at: Place,
    stay: Stay,
    character_id: CharacterId,
    map: MapId,
    incarnation: Int,
    unit_id: Int,
    unit: UnitCreatePlayer,
    loadout: Loadout,
    /// The items the character holds, as the store saved them: each with its
    /// own guid, its item2 id, where it is held and how many it stacks.
    items: List(store.HeldItem),
    /// What the character holds of each currency: the saved amounts, which a
    /// purchase lowers (genesis_prime/game/vendor_purchase) and the store saves with it.
    currencies: Currencies,
    /// The vendor window the player has open, which a purchase is made from
    /// (genesis_prime/game/vendor_purchase): the result of each interaction message
    /// sets it, clears it or keeps it (genesis_prime/game/interaction.Window), and a
    /// join of a world has none.
    vendor: Option(vendor.Opened),
    /// What the character has sold to vendors since it entered, which the vendor
    /// window lists to buy back (genesis_prime/game/vendor_sale): a play starts with
    /// none and the Holocrypt's join keeps it (`Joining`); the list is lost with the
    /// connection, as the character's next play starts it empty.
    buyback: Buyback,
    /// The character's experience: the saved one, or the least of its level when
    /// none was saved (`experience.entering`). The connection adds each kill's
    /// credit to it (genesis_prime/game/connection/experience) and saves it with
    /// the place.
    experience: Int,
    /// The quest log the character holds (genesis_prime/game/quest_log): the
    /// connection saves it with the place and, at a play, sends it after 0x25E.
    quests: QuestLog,
    /// What the worn items give (genesis_prime/game/gear): the connection works it out
    /// again after each change of a worn item and keeps it with the unit, the look and
    /// the properties it gave them.
    gear: Gear,
    clock_origin_ms: Int,
    viewers: Dict(ConnectionId, Stay),
    shown: shown.Picture,
    casts_written: Dict(Int, Int),
    gone: Set(Int),
    movement: movement.State,
    readiness: Readiness,
    life: player_life.Life,
    /// The player's properties, each with its base and value
    /// (genesis_prime/game/unit_properties): the connection owns them beside the life
    /// and the cast, applies a modifier of its own spell to them, and hands the
    /// strike, the damage, the defence and the regeneration the values they read.
    properties: unit_properties.Properties,
    /// The player's look, its item visuals and the disguises of its own spells held over
    /// them (genesis_prime/game/look): the connection owns it beside the properties.
    look: look.Look,
    resources: class_resource.Resources,
    camp: camp.Camp,
    cast: cast.State,
    strike: strike.State,
    chat: chat.Chat,
  )
}

/// What a character has sold to vendors since it entered, newest last: the id the
/// next sale gets, which the client names an entry by, and each entry.
pub type Buyback {
  Buyback(next_id: Int, entries: List(BuybackEntry))
}

/// One sale on the buyback list: the id the client names it by, the Item2 sold,
/// how many were sold and the credits the vendor paid for them all.
pub type BuybackEntry {
  BuybackEntry(buyback_id: Int, item2_id: Item2Id, quantity: Int, credits: Int)
}

/// Whether the player's client has finished loading the world: the connection
/// tells its map `Ready` once, at the stay's first 0xF2 (`opcode.0xf2`), so no
/// creature fights a loading player.
pub type Readiness {
  ClientLoading
  /// Loading after the Holocrypt's join. The client moved its ghost until the
  /// join's 0xAD reached it, which removes every unit and its control
  /// (`opcode.0x637`, 0x1403b6de0): a ghost's 0x637 sent before it arrives is
  /// taken in this stay, and is dropped as the ghost's until the stay's first
  /// 0xF2. A body's 0x637 before that 0xF2 is dropped too; the body stands at
  /// the Holocrypt place the join gave, and its next move is taken.
  GhostLoading
  ClientReady
}

/// 0x636 for the body of a player that enters alive. A player that enters dead
/// is given control of its ghost by its life's effects.
fn control_at_entry(
  life life: player_life.Life,
  unit_id unit_id: Int,
) -> List(Effect) {
  case player_life.state(life:) {
    player_life.Alive -> [control_granted(unit_id:)]
    player_life.Dead -> []
  }
}

/// The shield a player enters the world with: the stat 20 its client was told in
/// its 0x262 (`player_unit.with_gear`), or 0 when no shield is worn and the unit holds
/// none.
fn full_shield(unit unit: UnitCreatePlayer) -> Int {
  unit_fields.stat(tail: unit.tail, stat_id: unit_fields.shield_stat)
  |> result.unwrap(0)
}

/// The unit with the shield it enters with as stat 20, when a shield is worn: a unit
/// with none holds no stat 20, as `player_unit.with_gear` leaves it.
fn with_shield_stat(
  unit unit: UnitCreatePlayer,
  worn worn: Gear,
  shield shield: Int,
) -> UnitCreatePlayer {
  case gear.shield_capacity(gear: worn) {
    Some(_) ->
      player_unit.with_integer_stat(
        unit,
        stat_id: unit_fields.shield_stat,
        value: shield,
      )
    None -> unit
  }
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
/// character at its saved world for the stay `stay`, or the play is refused, for
/// a character the account does not have, one with no saved place or one whose
/// level has no XpPerLevel row (`character_state.frame`). With no read asked for,
/// it is none this module asked for and gives an `Error`.
pub fn loaded(
  state state: State,
  answer answer: store.WorldAnswer,
  connection connection: ConnectionId,
  stay stay: Stay,
  tables tables: table_store.Tables,
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
        store.CharacterLoaded(
          character:,
          session_epoch:,
          saved_health:,
          saved_experience:,
          items:,
          currencies:,
          quests:,
        ) ->
          case character.place {
            None ->
              Refused(
                character_id:,
                warning: "a play of character "
                  <> int.to_string(character_id)
                  <> ", which has no saved place",
              )
            Some(place) ->
              case quest_log.from_rows(rows: quests, tables:) {
                Error(refused) ->
                  Fault(
                    text: "a play of character "
                    <> int.to_string(character_id)
                    <> ", whose saved quest log the client would refuse: "
                    <> quest_log.describe(refused:),
                  )
                Ok(log) ->
                  joining_a_play(
                    character:,
                    place:,
                    movement: movement.entered(place:, session_epoch:),
                    saved_health:,
                    saved_experience:,
                    items:,
                    currencies: currency.from_held(held: currencies),
                    quests: log,
                    connection:,
                    stay:,
                    tables:,
                  )
              }
          }
      })
    Joining(..) -> Error(Nil)
  }
}

/// The play of a character at its saved place: the map is asked to take it with
/// its 0x25E ready, or the play is refused for a level with no XpPerLevel row.
fn joining_a_play(
  character character: Character,
  place place: Place,
  movement movement: movement.State,
  saved_health saved_health: Option(Int),
  saved_experience saved_experience: Option(Int),
  items items: List(store.HeldItem),
  currencies currencies: Currencies,
  quests quests: QuestLog,
  connection connection: ConnectionId,
  stay stay: Stay,
  tables tables: table_store.Tables,
) -> Loaded {
  case
    experience.entering(
      tables:,
      level: character.level,
      saved: saved_experience,
    )
  {
    Error(Nil) -> {
      let CharacterId(character_id) = character.character_id
      Refused(
        character_id:,
        warning: "a play of character "
          <> int.to_string(character_id)
          <> ", whose level "
          <> int.to_string(character.level)
          <> " has no XpPerLevel row",
      )
    }
    Ok(experience) -> {
      let frame =
        character_state.frame(tables:, character:, experience:, currencies:)
      let #(state, effects) =
        joining(
          character:,
          place:,
          movement:,
          saved_health:,
          experience:,
          items:,
          currencies:,
          quests:,
          buyback: Buyback(next_id: 1, entries: []),
          connection:,
          stay:,
          entry: PlayEntry(character_state: frame),
        )
      Join(state:, effects:)
    }
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
  classes classes: class_resource.Classes,
  numbers numbers: GameNumbers,
  defaults defaults: List(#(UnitProperty2Id, Float)),
  tables tables: table_store.Tables,
  now now: Now,
) -> Result(Joined, Nil) {
  case state {
    Joining(
      character:,
      place:,
      movement:,
      saved_health:,
      experience:,
      items:,
      currencies:,
      quests:,
      buyback:,
      map:,
      stay:,
      entry:,
    ) -> {
      case answer {
        map.Joined(unit:, loadout:, incarnation:, clock_origin_ms:) -> {
          let worn = gear.of_items(tables:, items:)
          use bases <- with_bases(tables:, worn:, level: character.level)
          let assert Ok(max_health) =
            gear.max_health(tables:, gear: worn, level: character.level)
            as "the bases are found only for a level with a Base Health row"
          let sent = start_place.within_the_worlds_box(place)
          let assert Ok(resource) =
            class_resource.of_class(classes:, class_id: character.class_id)
            as "character creation makes only playable classes, and the content load refuses a table with no resource for one"
          let unit =
            unit
            |> player_unit.with_gear(
              replacing: [],
              item_visuals: worn.visuals,
              bases:,
              shield: gear.shield_capacity(gear: worn),
            )
            |> player_unit.with_resource(resource:)
          let properties =
            unit_properties.new(
              defaults:,
              listed: unit.tail.properties,
              level: character.level,
            )
          let #(life, life_effects) =
            player_life.entering(
              saved: saved_health,
              max_health:,
              shield: full_shield(unit:),
              regeneration: player_life.regeneration(
                numbers:,
                properties:,
                shield: worn.properties.shield,
              ),
              place: sent,
            )
          let unit =
            unit
            |> player_unit.with_integer_stat(
              stat_id: unit_fields.health_stat,
              value: player_life.health(life:),
            )
            |> with_shield_stat(worn:, shield: player_life.shield(life:))
          let unit_id = unit.unit_id
          let CharacterId(character_id_number) = character.character_id
          let #(quests, quest_effects) =
            quest_log_sent(entry:, quests:, numbers:, tables:, now:)
          Ok(InTheWorld(
            entered: Entered(
              character:,
              entered_at: place,
              stay:,
              character_id: character.character_id,
              map:,
              incarnation:,
              unit_id:,
              unit:,
              loadout:,
              items:,
              currencies:,
              vendor: None,
              buyback:,
              experience:,
              quests:,
              gear: worn,
              clock_origin_ms:,
              viewers: dict.new(),
              shown: dict.new(),
              casts_written: dict.new(),
              gone: set.new(),
              movement:,
              readiness: readiness_of(entry:),
              life:,
              properties:,
              look: look.new(base: unit.tail.item_visuals),
              resources: class_resource.new(resource:),
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
                // Gap: that 0x92C belongs right after 0x19B is not proven by the
                // client (it reads the properties when a bag is worn and keeps
                // them in a map); the place is the server's, and the frame is sent
                // once per play and join. The open issue "Worn bags open more
                // inventory slots" (#587) settles it on the live client.
                reward_properties_sent(tables:),
              ],
              character_state_sent(entry:),
              quest_effects,
              items_sent(items:),
              loadout_sent(character_number: character_id_number, loadout:),
              [player_path(character:)],
              control_at_entry(life:, unit_id:),
              [
                Life(effects: life_effects),
                movement_interval(),
                entered_world(),
                WatchMap(map:, incarnation:),
              ],
              passive_started(loadout:),
              unread_warned(gear: worn),
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
        | map.Summoned(..)
        | map.NotSummoned(..)
        | map.Noticed(..)
        | map.Watched(..)
        | map.Unwatched(..)
        | map.Retire
        | map.Approached(..)
        | map.Withdrew(..)
        | map.PlayerDied(..) -> Error(Nil)
      }
    }
    Loading(..) -> Error(Nil)
  }
}

/// One warning for each worn item the gear lists as unread or undrawn, at entry, where
/// none is known yet.
fn unread_warned(gear gear: gear.Gear) -> List(Effect) {
  list.map(gear.warnings(gear:, known: None), fn(text) { Warn(text:) })
}

/// The bases of the gear's properties at `level`, handed to `next`, or the fault that
/// ends the connection when the tables have no Base Health row for the level.
fn with_bases(
  tables tables: table_store.Tables,
  worn worn: Gear,
  level level: Int,
  next next: fn(List(#(UnitProperty2Id, Float))) -> Result(Joined, Nil),
) -> Result(Joined, Nil) {
  case gear.bases(tables:, gear: worn, level:) {
    Ok(bases) -> next(bases)
    Error(error) -> Ok(GearFault(text: gear.describe(error:)))
  }
}

/// What the player's client does until its stay's first 0xF2: a play loads the
/// world as it was told to, and the Holocrypt's join leaves the ghost moving
/// until the join's 0xAD reaches it (`GhostLoading`).
fn readiness_of(entry entry: Entry) -> Readiness {
  case entry {
    PlayEntry(..) -> ClientLoading
    HolocryptEntry -> GhostLoading
  }
}

/// 0x35F for a play, with the log that remembers the reset time it carried, and
/// nothing for the Holocrypt's join.
fn quest_log_sent(
  entry entry: Entry,
  quests quests: QuestLog,
  numbers numbers: GameNumbers,
  tables tables: table_store.Tables,
  now now: Now,
) -> #(QuestLog, List(Effect)) {
  case entry {
    PlayEntry(..) -> {
      let #(told, frame) = quest_log.login(log: quests, numbers:, tables:, now:)
      #(told, [Send(frame:)])
    }
    HolocryptEntry -> #(quests, [])
  }
}

/// 0x25E for a play, and nothing for the Holocrypt's join.
fn character_state_sent(entry entry: Entry) -> List(Effect) {
  case entry {
    PlayEntry(character_state:) -> [Send(frame: character_state)]
    HolocryptEntry -> []
  }
}

/// The player chose the Holocrypt and has left its map: the map of `place`'s
/// world is asked to take it there for the stay `stay`, with the earlier stay's
/// movement placed at `place`. The map's answer comes back to `joined`, as at a
/// play.
pub fn rejoining(
  entered entered: Entered,
  place place: Place,
  connection connection: ConnectionId,
  stay stay: Stay,
) -> #(State, List(Effect)) {
  joining(
    character: entered.character,
    place:,
    movement: movement.placed(state: entered.movement, place:),
    saved_health: None,
    experience: entered.experience,
    items: entered.items,
    currencies: entered.currencies,
    quests: entered.quests,
    buyback: entered.buyback,
    connection:,
    stay:,
    entry: HolocryptEntry,
  )
}

/// The ask of the map of `place`'s world to take the character there, with the
/// movement it enters with and the way it comes in (which the readiness its
/// client starts the stay in follows from): the place the map is given is the
/// bounded one the client is told.
fn joining(
  character character: Character,
  place place: Place,
  movement movement: movement.State,
  saved_health saved_health: Option(Int),
  experience experience: Int,
  items items: List(store.HeldItem),
  currencies currencies: Currencies,
  quests quests: QuestLog,
  buyback buyback: Buyback,
  connection connection: ConnectionId,
  stay stay: Stay,
  entry entry: Entry,
) -> #(State, List(Effect)) {
  let map =
    MapId(world_id: start_place.world_id(place), instance: open_world_instance)
  #(
    Joining(
      character:,
      place:,
      movement:,
      saved_health:,
      experience:,
      items:,
      currencies:,
      quests:,
      buyback:,
      map:,
      stay:,
      entry:,
    ),
    [
      AskMap(
        map:,
        message: map.Join(
          connection:,
          character:,
          place: start_place.within_the_worlds_box(place),
          stay:,
          alive: bool.negate(player_life.saved_dead(saved: saved_health)),
        ),
      ),
    ],
  )
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

/// 0x92C with the reward properties the server holds for the player: BagSlots
/// and BankSlots at the premium tier the client was sent (`reward_property`),
/// which unlock the four bag slots and the two bank bag slots of the character
/// window (`opcode.0x92c`).
fn reward_properties_sent(tables tables: table_store.Tables) -> Effect {
  let values =
    reward_property.premium_values(
      tables:,
      system: reward_property.hybrid_system,
      tier: reward_property.signature_tier,
    )
  let assert Ok(body) =
    reward_properties.encode(reward_property.message(values:))
    as "two integer entries fit the message"
  Send(Frame(message_id: reward_properties.message_id, body:))
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
  Send(control_granted_frame(unit_id:))
}

/// 0x636 for the unit `unit_id`, with the value 0 and the reset bit 1
/// (vector.opcode.0x636.body): the entry burst's for the player, and a death's
/// for its ghost and for the player again.
pub fn control_granted_frame(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    client_control_granted.encode(ClientControlGranted(
      echo_value: 0,
      reset_movement: 1,
      unit_id:,
    ))
    as "a unit id of 32 bits fits the message"
  Frame(message_id: client_control_granted.message_id, body:)
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

/// The innate slot the client points its button at: the first of the Class row
/// (`opcode.0x19f`).
const first_innate_slot = 0

/// The 2-bit value of an action set: bit 0 set marks the set unlocked, which the
/// ability book's set arrows and the active set's switch read; nothing in casting
/// or the bar reads it (`opcode.0x19d.set_value`). Set 0, the active set, is
/// unlocked.
const set_unlocked = 1

/// The 0x111 of each saved item, in location then bag index order.
fn items_sent(items items: List(store.HeldItem)) -> List(Effect) {
  items
  |> list.sort(fn(first, second) {
    int.compare(first.location, second.location)
    |> order.break_tie(int.compare(first.bag_index, second.bag_index))
  })
  |> list.map(fn(item) {
    held_item(
      item_guid: item.item_guid,
      item_id: item.item2_id.value,
      location: item.location,
      bag_index: item.bag_index,
      stack_count: item.stack_count,
    )
  })
}

/// The loadout's messages, in order: each ability and the innate, the tiers,
/// action set 0 and the innate's index.
fn loadout_sent(
  character_number character_number: Int,
  loadout loadout: Loadout,
) -> List(Effect) {
  let abilities =
    list.index_map(loadout.bag(loadout:), fn(ability, bag_index) {
      held_item(
        item_guid: loadout.item_guid(
          character_number:,
          location: ability_location,
          bag_index:,
        ),
        item_id: ability.value,
        location: ability_location,
        bag_index:,
        stack_count: 1,
      )
    })
  let innate = case loadout.innate {
    Some(_) -> [innate_index_frame()]
    None -> []
  }
  list.flatten([
    abilities,
    [
      ability_tiers_frame(abilities: loadout.bag(loadout:)),
      action_set_frame(abilities: loadout.abilities),
    ],
    innate,
  ])
}

/// The innate's passive start, when the class's innate has a passive.
fn passive_started(loadout loadout: Loadout) -> List(Effect) {
  case loadout.innate {
    Some(innate.Innate(passive: Some(passive), ..)) -> [
      StartPassive(base: passive.spell4_base_id),
    ]
    Some(innate.Innate(passive: None, ..)) | None -> []
  }
}

/// 0x19F with index 0, the innate slot the loadout holds (`opcode.0x19f`).
fn innate_index_frame() -> Effect {
  let assert Ok(body) =
    innate_index_set.encode(InnateIndexSet(innate_index: first_innate_slot))
    as "the first slot fits the message's 2 bits"
  Send(Frame(message_id: innate_index_set.message_id, body:))
}

/// 0x111 for an item the character holds from the start, with the reason 49.
fn held_item(
  item_guid item_guid: Int,
  item_id item_id: Int,
  location location: Int,
  bag_index bag_index: Int,
  stack_count stack_count: Int,
) -> Effect {
  Send(inventory.item_added_frame(
    item_guid:,
    item_id:,
    location:,
    bag_index:,
    stack_count:,
    reason: held_from_the_start,
  ))
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
