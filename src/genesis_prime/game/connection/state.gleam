//// What the game connection's rule keeps and the parts every flow of it shares
//// (genesis_prime/game/connection): the session and its status, the log lines,
//// the asks, the notice and every ending, the save of the player's place, and
//// the tells of news to the players who see the player.

import genesis_prime/client_connection.{
  type Bucket, type Link, type Request, AskStore, Asking, Done,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/activate
import genesis_prime/game/character_select
import genesis_prime/game/class_resource
import genesis_prime/game/deadline_timer
import genesis_prime/game/dev_command
import genesis_prime/game/held_tier
import genesis_prime/game/inventory
import genesis_prime/game/item_charge
import genesis_prime/game/level_up
import genesis_prime/game/limited_action_set
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/player_address
import genesis_prime/game/player_life
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/projector
import genesis_prime/game/quest_log
import genesis_prime/game/quest_turn_in
import genesis_prime/game/server_proxy.{type ServerProxies}
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_plan
import genesis_prime/game/spell_tier
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/tutorial.{type Chain}
import genesis_prime/game/unit_news
import genesis_prime/game/vendor.{type Vendors}
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/game/zone_welcome.{type ZoneWelcomes}
import genesis_prime/game_settings.{type GameSettings}
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/bit_stream
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, LostUserServer,
}
import genesis_prime/shared/quest_view.{type QuestView}
import genesis_prime/step.{
  type About, type ConnectionEffect, type ConnectionId, type Effect, type Now,
  type TimerId, About, CancelTimer, LogWarning, OwnEffect, StartTimer, Stop,
  TimerId, WatchId, Write,
}
import genesis_prime/store
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/relay.{type Inbound}
import genesis_prime/world_map/spawn_id.{type LoadedSpawns}
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// What every game connection is made with, at start.
pub type Settings {
  Settings(
    /// The realm's id: the hello's, and the character list's, which becomes
    /// the client's current realm when it plays a character (opcode.0x117).
    realm_id: Int,
    /// The number of characters the client's list is told the account may
    /// have; the Lua keeps it and nothing reads it (lua.Character.OnCharacterList).
    max_characters: Int,
    /// The game's own settings: the characters an account may have and the
    /// camp's countdown (genesis_prime/game_settings).
    game: GameSettings,
    /// The realm's name, the one a whisper's realm name must equal, compared
    /// without case, for the whisper to be for this realm (opcode.0x1d4).
    realm_name: String,
    /// The client's game tables, which a create request and the list's body
    /// visuals are read from.
    tables: table_store.Tables,
    /// How long an ask to the hand-off, Sessions or the store may take.
    ask_deadline_ms: Int,
    /// How fast the client may send its frames
    /// (`genesis_prime/client_connection.Bucket`).
    rate: Bucket,
    /// Each playable class's resource, from the content load
    /// (genesis_prime/content/class_resource), which a player entering the world
    /// starts with.
    class_resources: class_resource.Classes,
    /// The spells the server casts with a go of an ability where the client's
    /// tables link none, from the content load (genesis_prime/content/server_proxy),
    /// which the ability trees the cast rule reads hold (`plans_of`).
    server_proxies: ServerProxies,
    /// The Tutorial row each WorldZone shows when a player lands in it or walks into
    /// it, from the content load (genesis_prime/content/zone_welcome), which the
    /// client's zone reports send as 0x179 (genesis_prime/game/zone_welcome).
    zone_welcomes: ZoneWelcomes,
    /// The creatures that sell and what each sells, from the content load
    /// (genesis_prime/content/vendor), which a request to open a vendor's window is
    /// answered from (genesis_prime/game/interaction).
    vendors: Vendors,
    /// The numbers the server chose, from the content load
    /// (genesis_prime/content/game_number), of which a player entering the world
    /// reads its health regeneration (genesis_prime/game/player_life).
    numbers: GameNumbers,
    /// The loaded visibility prerequisites of each world, from the content load
    /// (genesis_prime/content/spawn `visibility`): the prerequisites the started
    /// spawns and sent objects of the world hide behind, which the connection checks
    /// for its player to tell the map what to hide (genesis_prime/game/visibility).
    visibility: dict.Dict(Int, List(Prerequisite)),
    /// The quests no creature gives, in the order each faction is given them, from the
    /// content load (genesis_prime/content/tutorial_quest): a character entering World
    /// 3460 and one whose server-completed chain quest is done is given the next
    /// (genesis_prime/game/tutorial).
    tutorial_chain: Chain,
    /// Where each of the training simulation's projectors puts a player, from the
    /// content load (genesis_prime/content/projector_landing): the cast's go reads it
    /// (genesis_prime/game/projector).
    projector_landings: projector.Landings,
    /// The objectives whose unit counts again when it is used again, from the content
    /// load (genesis_prime/content/spawn `reused_unit_objectives`): the other objectives that
    /// count a use of a unit or a cast at one count each unit once
    /// (genesis_prime/game/quest_log `used`).
    reused_unit_objectives: Set(Int),
    /// The stored spawn rows and the rows the server places, from the content load
    /// (genesis_prime/content/spawn `loaded_spawns`): what a saved quest's used objects are
    /// kept against at the load (genesis_prime/game/quest_log `without_lost_spawns`).
    loaded_spawns: LoadedSpawns,
    /// The scripted objectives that only an instance run or a PvP match can complete, from
    /// the content load (genesis_prime/content/objective_set, table `held_objective`): the
    /// settle leaves them open (genesis_prime/game/objective `stand_in_scripts`).
    held_objectives: Set(Int),
    /// The scripted objectives whose text asks only to reach a place, from the content load
    /// (genesis_prime/content/objective_set, table `arrival_objective`): the settle completes
    /// one when the player stands at a marker (genesis_prime/game/objective `script_of`).
    arrival_objectives: Set(Int),
    /// The scripted objectives whose real rule is a kill or a click, from the content load
    /// (genesis_prime/content/objective_set, tables `kill_objective` and `click_objective`): a
    /// kill or an activation of a creature of the objective's reward pane counts for one
    /// (genesis_prime/game/objective `counts`).
    script_rows: objective.ScriptRows,
  )
}

/// The ability trees the cast rule reads for the standing spells, every ability at tier 1: the
/// client's, with the server's Proxies planted into them (genesis_prime/game/server_proxy). A
/// press reads `held_plans_of`.
pub fn plans_of(session session: Session) -> spell_plan.Plans {
  server_proxy.planted_into(
    plans: spell_plan.plans_with_later(session.settings.tables),
    proxies: session.settings.server_proxies,
  )
}

/// The ability trees a press reads for a player in the world: `plans_of`'s, with the plan of the
/// tier the player holds in the active set put under each ability they hold above tier 1
/// (genesis_prime/game/held_tier), then the server's Proxies planted into those plans.
pub fn held_plans_of(
  session session: Session,
  entered entered: world_entry.Entered,
) -> spell_plan.Plans {
  let tables = session.settings.tables
  server_proxy.planted_into(
    plans: held_tier.plans_of(
      plans: spell_plan.plans_with_later(tables),
      tier_plans: spell_plan.tier_plans(tables),
      tiers: spell_tier.tiers(tables),
      held: limited_action_set.held_tiers(
        saved: entered.action_sets,
        set: limited_action_set.set_number(set: limited_action_set.first_set()),
      ),
    ),
    proxies: session.settings.server_proxies,
  )
}

/// The quest log of a player in the world as the read-only view the cast and unit rules
/// read quests through (genesis_prime/shared/quest_view).
pub fn quests_of(entered entered: world_entry.Entered) -> QuestView {
  quest_log.view(log: entered.quests)
}

/// The activate spells' plans and prerequisites the cast rule reads
/// (genesis_prime/game/activate).
pub fn activations_of(session session: Session) -> activate.Activations {
  activate.activations(tables: session.settings.tables)
}

/// The plans of the spells the cast-a-spell objectives name
/// (genesis_prime/game/shortcut_spell).
pub fn shortcut_spells_of(
  session session: Session,
) -> shortcut_spell.Shortcuts {
  shortcut_spell.shortcuts(tables: session.settings.tables)
}

/// The plans of the level-up fanfares (genesis_prime/game/level_up).
pub fn level_ups_of(session session: Session) -> level_up.Fanfares {
  level_up.fanfares(tables: session.settings.tables)
}

/// What an accepted connection keeps.
pub type Session {
  Session(
    settings: Settings,
    link: Link,
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
    /// The cipher the connection's frames are read and written under: the
    /// base key's until 0x058F re-keys it.
    cipher: Cipher,
    /// The ids of the messages already logged as unhandled on this
    /// connection: the first of an id is a warning, a repeat a debug line.
    unhandled_logged: Set(Int),
    /// The kinds of movement command already named in a log line as not
    /// relayed to other players on this connection.
    unrelayed_logged: Set(Int),
    /// The ids of the chat channel types already logged as unhandled on this
    /// connection (`chat.Unhandled`): once for each.
    unhandled_channels_logged: Set(Int),
    /// The WorldZone ids already logged as having no row on this connection.
    unknown_zones_logged: Set(Int),
    /// The reasons a request to talk to a unit or to accept or retry a quest was
    /// declined that are already logged on this connection (genesis_prime/game/
    /// interaction and genesis_prime/game/quest `Declined`): the first of a reason is
    /// a warning, a repeat a debug line.
    interaction_logged: Set(String),
    /// The number of the next whisper the connection's players make: it counts
    /// for the connection's life, so a reply to a whisper of an earlier stay in
    /// the world never meets a new whisper (genesis_prime/game/chat).
    next_whisper: Int,
    /// The sequence number of the last 0x637 the connection accepted and told: it
    /// counts for the connection's life, through a camp and the next entry, so a
    /// creature never takes a move of an earlier stay for a newer one
    /// (genesis_prime/world_map/creature_fight).
    move_seq: Int,
    /// The stay the connection's last join named (genesis_prime/world_map/stay):
    /// each join asks with the one after it, so the stays count for the
    /// connection's life and a message of an earlier stay never names the
    /// current one.
    last_stay: Stay,
    /// What reached the connection while an ask was out whose answer returns it
    /// to the world (`holds_map_messages`), oldest first: what other processes
    /// sent for a stay and the connection's own timers that fired. Each is taken,
    /// in this order, once the answer returns the connection there
    /// (genesis_prime/game/connection `stay_sent`, `timer_fired`).
    held: List(Held),
    status: Status,
  )
}

/// What the connection holds until an ask returns it to the world.
pub type Held {
  /// What another process sent for `stay`.
  HeldSend(stay: Stay, sent: client_connection.StaySent)
  /// A timer of the connection that fired during the wait.
  HeldTimer(timer: TimerId)
}

/// The connection's one status.
pub type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key; `account_id` is the one
  /// the client's reply named, checked against the holder the hand-off gives.
  TakingSessionKey(account_id: store.AccountId)
  /// Sessions is asked to make the connection the account's session, and its
  /// answer is awaited. `resume` is where the client is after the answer: a
  /// new character select for the first claim; a new one again, or its player
  /// in the world, for a later one. `retries` is how many times Sessions was
  /// not running for this claim.
  ClaimingSession(holder: Holder, resume: Resume, retries: Int)
  /// The connection waits on the claim timer before it asks Sessions again,
  /// with `resume` and `retries` as `ClaimingSession` holds them. No ask is
  /// out, so no answer is taken here.
  WaitingToClaim(holder: Holder, resume: Resume, retries: Int)
  /// The session key was held for `holder` and Sessions holds the account's
  /// slot for this connection; the client is in character select, which holds
  /// its own state, asks the store itself and says when its answer is awaited.
  InCharacterSelect(holder: Holder, select: character_select.State)
  /// The client asked to play a character, or its dead player chose the
  /// Holocrypt (`from`); world entry asks the store, then the map, or the map
  /// alone for the Holocrypt. A refusal hands the client back to a new character
  /// select, after 0x0594 when it came from the world.
  EnteringWorld(holder: Holder, entry: world_entry.State, from: EntryFrom)
  /// The player is in the world, in `entered`'s map, which the connection
  /// watches (`map_watch`).
  InWorld(holder: Holder, entered: world_entry.Entered)
  /// The player is in the world and its map's run is asked to start a creature
  /// for a development command (`world_map/map.Summon`, genesis_prime/game/dev_command),
  /// whose answer is awaited with the client's frames held. The player's place is
  /// not saved yet, so a connection that ends in this status saves it as one in
  /// `InWorld` does; the shell takes no other input during the ask, so the
  /// creature's news of its unit waits until the status is `InWorld` again.
  Summoning(holder: Holder, entered: world_entry.Entered)
  /// The player is in the world and the store is asked to move the items of the
  /// player's 0x182 (`moving`, genesis_prime/game/inventory), whose answer is
  /// awaited with the client's frames held. The player's place is not saved yet,
  /// so a connection that ends in this status saves it as one in `InWorld` does;
  /// the held items in `entered` are the ones before the move, which the answer
  /// replaces.
  MovingItem(
    holder: Holder,
    entered: world_entry.Entered,
    moving: inventory.Moving,
  )
  /// The player is in the world and the store is asked to save the spend of the charge the
  /// player's 0x943 uses (`spending`, genesis_prime/game/item_charge), whose answer is
  /// awaited with the client's frames and the started cast's state and effects held. The
  /// player's place is not saved yet, so a connection that ends in this status saves it as
  /// one in `InWorld` does; the held items and the cast in `entered` are the ones before the
  /// use, which the answer replaces or keeps.
  SpendingCharge(
    holder: Holder,
    entered: world_entry.Entered,
    spending: item_charge.Spending,
  )
  /// The player is in the world and the store is asked to take the price of the buy the
  /// player's 0xBE made and to add its items (`purchase`, genesis_prime/game/vendor_purchase),
  /// whose answer is awaited with the client's frames held. The player's place is not saved
  /// yet, so a connection that ends in this status saves it as one in `InWorld` does; the
  /// held items and credits in `entered` are the ones before the buy, which the answer
  /// replaces.
  Buying(
    holder: Holder,
    entered: world_entry.Entered,
    purchase: vendor_purchase.Purchase,
  )
  /// The player is in the world and the store is asked to take the items the sale the
  /// player's 0x166 or 0x167 made sells and to pay for them (`sale`,
  /// genesis_prime/game/vendor_sale), whose answer is awaited with the client's frames
  /// held. The player's place is not saved yet, so a connection that ends in this status
  /// saves it as one in `InWorld` does; the held items, credits and buyback list in
  /// `entered` are the ones before the sale, which the answer replaces.
  Selling(holder: Holder, entered: world_entry.Entered, sale: vendor_sale.Sale)
  /// The player is in the world and the store is asked to set a currency's total for the
  /// development command `!currency` (`grant`, genesis_prime/game/dev_command), whose
  /// answer is awaited with the client's frames held. The player's place is not saved yet,
  /// so a connection that ends in this status saves it as one in `InWorld` does; the
  /// currencies in `entered` are the ones before the command, which the answer replaces.
  Granting(
    holder: Holder,
    entered: world_entry.Entered,
    grant: dev_command.Grant,
  )
  /// The player is in the world and the store is asked to complete the quest the player's
  /// 0x35D turned in and to give its rewards (`turn_in`, genesis_prime/game/quest_turn_in),
  /// whose answer is awaited with the client's frames held. The store's request saves the
  /// place with the turn-in, so a connection that ends in this status saves nothing more (a
  /// later save would carry the quest log and experience from before the turn-in); the quest
  /// log, items, credits and experience in `entered` are the ones before the turn-in, which
  /// the answer replaces.
  TurningIn(
    holder: Holder,
    entered: world_entry.Entered,
    turn_in: quest_turn_in.TurnIn,
  )
  /// The store is asked to save where the player stands, and its answer is
  /// awaited; `then` says what follows it. A connection in this status ends
  /// without a second save: the save out is the one its end waits for.
  SavingPlace(holder: Holder, entered: world_entry.Entered, then: AfterSave)
  /// The map's run is asked to take the player out (`world_map/map.Leave`), and its
  /// answer is awaited. A connection in this status ends without a save, and the map
  /// drops a player whose connection ends. The camp's place is saved before the ask;
  /// a move to another place (`JoinAt`) saves nothing, so the next login finds the
  /// last save. `then` says what follows `Left`.
  LeavingMap(holder: Holder, entered: world_entry.Entered, then: AfterLeave)
}

/// What follows the map's answer to a leave.
pub type AfterLeave {
  /// The camp: 0x0594 and a new character select.
  ToCharacterSelect
  /// The Holocrypt, a departures terminal or a `!go` into another world: the map of
  /// `place`'s world is asked to take the player there (`world_entry.rejoining`),
  /// with `health` as its saved health (`None` is a full one), and its entry burst
  /// follows, then the system line `told` when there is one.
  JoinAt(place: Place, health: Option(Int), told: Option(String))
}

/// Where an entry into the world started, for what its refusal does.
pub type EntryFrom {
  /// A play in character select: the refusal is 0x0162 and the list again.
  FromCharacterSelect
  /// The Holocrypt, with the client still in the world: the refusal is 0x0594,
  /// as the camp's leave writes, then a new character select.
  FromInWorld
}

/// What a save of the player's place is for, so its answer knows what comes
/// next.
pub type AfterSave {
  /// The save the timer asked for: the player goes on playing.
  Playing
  /// The connection ends once the save is answered, whatever the answer:
  /// `notice` is written first when there is one, then the connection stops.
  Leaving(notice: Option(DisconnectReason))
  /// The player camps: once the save is answered, whatever the answer, the map's
  /// run is asked to take the player out (`LeavingMap`).
  Camped
}

/// Where a claim made again after Sessions ended puts the client back. The
/// shell takes the end of a watch only between steps, so no ask of character
/// select is out then, and a character select resumes as a new one.
pub type Resume {
  ResumeSelect
  ResumeWorld(entered: world_entry.Entered)
}

/// The watch on the player's map, open while the player is in the world.
pub const map_watch = WatchId(2)

/// The timer that saves the player's place every `movement.save_period_ms`
/// while the player is in the world.
pub const save_timer = TimerId(2)

/// The timer that fires at the next daily quest reset while the player is in the
/// world (genesis_prime/game/quest_log `reset_due`).
pub const quest_reset_timer = TimerId(10)

/// The timer that fires when the earliest running quest's time limit runs out while
/// the player is in the world (genesis_prime/game/quest_log `next_deadline`).
pub const quest_deadline_timer = TimerId(11)

/// The timer that fires when the earliest moment a held timed item runs out comes, while the
/// player is in the world (genesis_prime/game/item_expiry `next_deadline`).
pub const item_expiry_timer = TimerId(13)

/// The timers the player's stay in the world runs, which the claim made again and the leaving
/// of the world cancel and the claim starts again.
const stay_timers = [
  save_timer,
  quest_reset_timer,
  quest_deadline_timer,
  item_expiry_timer,
]

/// The effects that cancel each of the stay's timers.
pub fn stay_timers_cancelled() -> List(Effect(ConnectionEffect(Request))) {
  list.map(stay_timers, fn(timer) { OwnEffect(CancelTimer(timer:)) })
}

/// The effect that carries out a move of the deadline timer `timer`
/// (genesis_prime/game/deadline_timer `moved`).
pub fn deadline_timer_move(
  timer timer: TimerId,
  move move: deadline_timer.DeadlineTimer,
) -> Effect(ConnectionEffect(Request)) {
  case move {
    deadline_timer.StartDeadlineTimer(after_ms:) ->
      OwnEffect(StartTimer(timer:, after_ms:))
    deadline_timer.CancelDeadlineTimer -> OwnEffect(CancelTimer(timer:))
  }
}

/// A message in the game wrapper under the cipher the connection holds.
pub fn to_client(
  session session: Session,
  inner inner: Frame,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(
    Write(client_connection.wrapped(GameWrapper, inner, session.cipher)),
  )
}

/// What one effect of a feature rule that only writes frames and log lines comes to.
pub type Told {
  /// A message to the client.
  Sent(frame: Frame)
  /// A log line of the connection.
  Logged(level: step.LogLevel, text: String)
}

/// The connection's effects for a feature rule's effects, in order: `told` says which
/// of the two each one is.
pub fn told_effects(
  session session: Session,
  effects effects: List(effect),
  told told: fn(effect) -> Told,
) -> List(Effect(ConnectionEffect(Request))) {
  list.map(effects, fn(effect) {
    case told(effect) {
      Sent(frame:) -> to_client(session:, inner: frame)
      Logged(level:, text:) -> log(session:, level:, text:)
    }
  })
}

/// 0x036A with the reason, in the game wrapper under the cipher the
/// connection holds, so the client leaves its prompt.
pub fn notice(
  session session: Session,
  reason reason: DisconnectReason,
) -> Effect(ConnectionEffect(Request)) {
  let body =
    bit_stream.must(DisconnectNotice(reason:), disconnect_notice.encode)
  to_client(session:, inner: Frame(disconnect_notice.message_id, body))
}

/// Where the connection stands when a message of the client's reaches it:
/// what the message's feature needs of the status.
pub type Standing {
  /// The hello is sent; 0x058F is awaited.
  Greeting
  /// The client is in character select, for `holder`'s account.
  Selecting(holder: Holder)
  /// The player is in the world.
  Present(holder: Holder, entered: world_entry.Entered)
  /// An ask is out or the claim waits, so no frame is taken: `text` is why
  /// that frame ends the connection.
  Busy(text: String)
}

pub fn standing(status: Status) -> Standing {
  case status {
    AwaitingHelloReply -> Greeting
    InCharacterSelect(holder:, ..) -> Selecting(holder:)
    InWorld(holder:, entered:) -> Present(holder:, entered:)
    TakingSessionKey(..)
    | ClaimingSession(..)
    | EnteringWorld(..)
    | Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..) -> Busy(text: "a frame was taken while an ask was out")
    WaitingToClaim(..) ->
      Busy(text: "a frame was taken while the claim waited on its timer")
  }
}

/// A message the table routes to a feature at a stage that feature cannot
/// take it in: a bug of the table, so the connection ends.
pub fn misrouted(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  end_for(
    session:,
    now:,
    text: "the routing table sent "
      <> frame.message_text(inner.message_id)
      <> " to a feature that does not take it here",
  )
}

/// The connections that see the player, each with what the player's copy holds of
/// that viewer (its stay and the generation of its sight), in the order of their
/// numbers.
pub fn sorted_viewers(
  entered entered: world_entry.Entered,
) -> List(#(ConnectionId, player_address.Viewer)) {
  map.sorted_by_connection(entered.viewers)
}

/// The player's level: its unit's stat 10, 1 when it has none.
pub fn level_of(entered entered: world_entry.Entered) -> Int {
  unit_fields.stat(tail: entered.unit.tail, stat_id: unit_fields.level_stat)
  |> result.unwrap(1)
}

/// Makes the connection's next ask, after the effects `before`, with the
/// settings' deadline.
pub fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  ask_within(
    session:,
    now:,
    request:,
    before:,
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// Makes the connection's next ask, after the effects `before`, which gets
/// `within_ms` from the time of the input to be answered.
fn ask_within(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(ConnectionEffect(Request))),
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let #(link, made) =
    client_connection.ask(session.link, now:, deadline_ms: within_ms, request:)
  Asking(Session(..session, link:), before, made)
}

/// The player the client holds in this connection's world, with its account's
/// holder, while it holds one: the player in the world, or its claim made again
/// with the player in it, where a send is taken. A claim with its ask out, a save
/// and a leave take no send.
pub fn held_in_the_world(
  status: Status,
) -> Option(#(Holder, world_entry.Entered)) {
  case status {
    InWorld(holder:, entered:)
    | WaitingToClaim(holder:, resume: ResumeWorld(entered:), ..) ->
      Some(#(holder, entered))
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> None
  }
}

/// Whether the status is one whose answer returns the connection to the world: a
/// summon, an item move, a purchase, a sale, a currency set, a quest turn-in, the
/// periodic place save, or the claim made again with the player in the world. What other processes
/// send for a stay meanwhile, and the connection's own timers that fire, are held, not
/// dropped. A save before leaving or camping is not one: its stay ends, and the timers
/// of the stay were cancelled with it. Nor is a claim made again from character select.
pub fn holds_map_messages(status: Status) -> Bool {
  case status {
    Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | TurningIn(..)
    | ClaimingSession(resume: ResumeWorld(..), ..)
    | SavingPlace(then: Playing, ..) -> True
    SavingPlace(then: Leaving(..), ..)
    | SavingPlace(then: Camped, ..)
    | InWorld(..)
    | WaitingToClaim(..)
    | ClaimingSession(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> False
  }
}

/// Whether a firing of the connection's own `timer` is held in `status`, as a message
/// for a stay is (`holds_map_messages`). The claim made again cancelled the save, quest
/// reset, quest deadline and item expiry timers (`stay_timers`) and starts them again once
/// answered, so a firing of one of them there is not held: it is a bug.
pub fn holds_timer(status status: Status, timer timer: TimerId) -> Bool {
  case status {
    ClaimingSession(resume: ResumeWorld(..), ..) ->
      !list.contains(stay_timers, timer)
    ClaimingSession(resume: ResumeSelect, ..)
    | Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | InWorld(..)
    | WaitingToClaim(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> holds_map_messages(status)
  }
}

/// Whether the status is one whose ask saves the player's place itself: a quest
/// turn-in, whose request holds the place, and the periodic place save. A save
/// timer that fires during such a wait has nothing to add.
pub fn saves_the_place(status: Status) -> Bool {
  case status {
    TurningIn(..) | SavingPlace(then: Playing, ..) -> True
    SavingPlace(then: Leaving(..), ..)
    | SavingPlace(then: Camped, ..)
    | Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | InWorld(..)
    | WaitingToClaim(..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> False
  }
}

/// The tell of `news` about the player's own unit to the run of its map, which relays it
/// to each player whose relation with this one relays, in the map's order
/// (genesis_prime/world_map/map `PlayerBroadcast`): the owner tells no viewer itself.
pub fn broadcast(
  session session: Session,
  entered entered: world_entry.Entered,
  news news: unit_news.News,
) -> Effect(ConnectionEffect(Request)) {
  tells_the_map(
    entered:,
    request: client_connection.TellBroadcast(
      connection: client_connection.connection(session.link),
      stay: entered.stay,
      news: unit_news.PeerNews(unit_id: entered.unit_id, news:),
    ),
  )
}

/// The tell of `landing` to the run of the player's map, for the player of connection `to`
/// in its stay `to_stay`: what the player's cast lands on that player, or its answer to
/// one. The map admits it by the kind's checks and relays it to `to`
/// (genesis_prime/world_map/map `TellLanding`), in the order this connection told it
/// beside its broadcasts; the player tells no other player itself.
pub fn tells_the_landing(
  session session: Session,
  entered entered: world_entry.Entered,
  to to: ConnectionId,
  to_stay to_stay: Stay,
  landing landing: relay.Landing,
) -> Effect(ConnectionEffect(Request)) {
  tells_the_map(
    entered:,
    request: client_connection.TellLanding(
      connection: client_connection.connection(session.link),
      stay: entered.stay,
      to:,
      to_stay:,
      landing:,
    ),
  )
}

/// The tell of `request` to the run of the player's map, which no answer follows
/// (`step.Tell`): the player's move, its readiness or its stealth, each of which the
/// map takes in the order this connection sent it.
pub fn tells_the_map(
  entered entered: world_entry.Entered,
  request request: Request,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Map(map: entered.map, incarnation: entered.incarnation),
    request:,
  ))
}

/// The tell of `payload` to the creature `unit_id` of life `life`, which no answer
/// follows (`step.Tell`): sent to the run of the player's map with the connection and the
/// stay the player entered in, for the map to admit and pass on to the creature
/// (genesis_prime/world_map/map `TellCreature`). A connection tells a creature only
/// through its map, so a creature hears about a player from one sender in one order.
pub fn tells_the_creature(
  entered entered: world_entry.Entered,
  connection connection: ConnectionId,
  unit_id unit_id: Int,
  life life: Int,
  payload payload: Inbound,
) -> Effect(ConnectionEffect(Request)) {
  tells_the_map(
    entered:,
    request: client_connection.TellCreature(
      connection:,
      stay: entered.stay,
      unit_id:,
      life:,
      payload:,
    ),
  )
}

/// The session with the player it holds in the world changed by `change`: the
/// player in the world, or in the world and waiting to claim again, where a send
/// is taken. A status that takes no send, since the shell takes none while an ask
/// is out, or that holds no player in the world, is as it was.
pub fn with_entered(
  session session: Session,
  change change: fn(world_entry.Entered) -> world_entry.Entered,
) -> Session {
  case session.status {
    InWorld(..) | WaitingToClaim(resume: ResumeWorld(..), ..) ->
      with_entered_in_any_status(session:, change:)
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> session
  }
}

/// The session with the player it holds in any status that holds one, an ask's included,
/// changed by `change`: for a record of what the connection has already done, which an
/// answer's handler reads back from the status (`with_entered` leaves an ask's status as
/// it is, because the rules that decide something wait for the answer). A status that holds
/// no player is as it was.
pub fn with_entered_in_any_status(
  session session: Session,
  change change: fn(world_entry.Entered) -> world_entry.Entered,
) -> Session {
  let status = case session.status {
    InWorld(holder:, entered:) -> InWorld(holder:, entered: change(entered))
    WaitingToClaim(holder:, resume: ResumeWorld(entered:), retries:) ->
      WaitingToClaim(
        holder:,
        resume: ResumeWorld(entered: change(entered)),
        retries:,
      )
    ClaimingSession(holder:, resume: ResumeWorld(entered:), retries:) ->
      ClaimingSession(
        holder:,
        resume: ResumeWorld(entered: change(entered)),
        retries:,
      )
    Summoning(holder:, entered:) -> Summoning(holder:, entered: change(entered))
    MovingItem(holder:, entered:, moving:) ->
      MovingItem(holder:, entered: change(entered), moving:)
    SpendingCharge(holder:, entered:, spending:) ->
      SpendingCharge(holder:, entered: change(entered), spending:)
    Buying(holder:, entered:, purchase:) ->
      Buying(holder:, entered: change(entered), purchase:)
    Granting(holder:, entered:, grant:) ->
      Granting(holder:, entered: change(entered), grant:)
    Selling(holder:, entered:, sale:) ->
      Selling(holder:, entered: change(entered), sale:)
    TurningIn(holder:, entered:, turn_in:) ->
      TurningIn(holder:, entered: change(entered), turn_in:)
    SavingPlace(holder:, entered:, then:) ->
      SavingPlace(holder:, entered: change(entered), then:)
    LeavingMap(holder:, entered:, then:) ->
      LeavingMap(holder:, entered: change(entered), then:)
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> session.status
  }
  Session(..session, status:)
}

/// Asks the store to save where the player stands, after the effects `before`,
/// with `within_ms` to be answered: the movement numbers the save, and the
/// connection waits in `SavingPlace` for the answer.
pub fn saving(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  then then: AfterSave,
  before before: List(Effect(ConnectionEffect(Request))),
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let #(state, request) =
    movement.save(
      state: entered.movement,
      account_id: holder.account_id,
      character_id: entered.character_id,
      health: Some(player_life.saved_health(life: entered.life)),
      experience: entered.experience,
      level: entered.character.level,
      quests: quest_log.rows(log: entered.quests, now_ms: now.monotonic_ms),
      action_sets: limited_action_set.rows(saved: entered.action_sets),
    )
  ask_within(
    session: Session(
      ..session,
      status: SavingPlace(
        holder:,
        entered: world_entry.Entered(..entered, movement: state),
        then:,
      ),
    ),
    now:,
    request: AskStore(store.Move(request)),
    before:,
    within_ms:,
  )
}

/// The connection ends after the save it waited for: the lines the answer made,
/// then the notice when there is one, then the end.
pub fn left(
  session session: Session,
  lines lines: List(Effect(ConnectionEffect(Request))),
  notice told: Option(DisconnectReason),
) -> client_connection.Handled(Session) {
  Done(
    session,
    list.flatten([
      lines,
      case told {
        Some(reason) -> [notice(session:, reason:)]
        None -> []
      },
      [Stop],
    ]),
  )
}

/// What an end writes and logs, besides the save of the player's place: a log
/// line and the notice 0x036A with a reason, each when there is one.
pub type Ending {
  Ending(
    log: Option(#(step.LogLevel, String)),
    notice: Option(DisconnectReason),
  )
}

/// The one end of a connection, for every cause. A connection that holds a
/// player in the world (`holds_a_player`) first asks the store to save where the
/// player stands, with `within_ms` to be answered, and ends when the answer
/// comes, whatever it is (`save_answered`); the log line comes before the ask,
/// the notice after the answer. A connection with no player, or one whose save
/// is already out, ends at once, so no end saves twice. When `within_ms` is
/// 0 or less, as the server's stop can leave it, no ask is made, and a warning
/// says the place was not saved.
pub fn end_with(
  session session: Session,
  now now: Now,
  ending ending: Ending,
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let reason_line = case ending.log {
    Some(#(level, text)) -> [log(session:, level:, text:)]
    None -> []
  }
  case holds_a_player(session.status) {
    None -> left(session:, lines: reason_line, notice: ending.notice)
    Some(_) if within_ms <= 0 ->
      left(
        session:,
        lines: list.append(reason_line, [
          log(
            session:,
            level: LogWarning,
            text: "the place was not saved: no time was left before the stop's deadline",
          ),
        ]),
        notice: ending.notice,
      )
    Some(#(holder, entered)) ->
      saving(
        session:,
        now:,
        holder:,
        entered:,
        then: Leaving(notice: ending.notice),
        before: reason_line,
        within_ms:,
      )
  }
}

/// The player the connection holds in the world and the holder it plays for,
/// when its place is to be saved by an end: in the world, or claiming its
/// account again with the player in the world. A connection already in
/// `SavingPlace` or `TurningIn` holds the player too, but its save is out (the
/// turn-in's transaction saves the place), so its end saves nothing more; in
/// `LeavingMap` and `EnteringWorld` an end saves nothing, and the next login finds
/// the last save.
pub fn holds_a_player(
  status: Status,
) -> Option(#(Holder, world_entry.Entered)) {
  case status {
    InWorld(holder:, entered:)
    | Summoning(holder:, entered:)
    | MovingItem(holder:, entered:, ..)
    | SpendingCharge(holder:, entered:, ..)
    | Buying(holder:, entered:, ..)
    | Granting(holder:, entered:, ..)
    | Selling(holder:, entered:, ..)
    | ClaimingSession(holder:, resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(holder:, resume: ResumeWorld(entered:), ..) ->
      Some(#(holder, entered))
    TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> None
  }
}

/// The connection ends after 0x036A with the reason, and a log line saying
/// why.
pub fn told(
  session session: Session,
  now now: Now,
  reason reason: DisconnectReason,
  level level: step.LogLevel,
  text text: String,
) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: Some(#(level, text)), notice: Some(reason)),
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// The server is stopping while an ask is out: the client is told, with no
/// log line, since a stop is no failure.
pub fn stopped(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: None, notice: Some(LostUserServer)),
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
pub fn end_for(
  session session: Session,
  now now: Now,
  text text: String,
) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: Some(#(step.LogError, text)), notice: None),
    within_ms: session.settings.ask_deadline_ms,
  )
}

// ---- log lines ----

pub fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(ConnectionEffect(Request)) {
  client_connection.log(about: about_of(session), level:, text:)
}

/// What a log line of the connection is about: the connection, the peer and
/// the account once the hand-off has named it; in the world also the map and
/// the character.
pub fn about_of(session: Session) -> About {
  let about =
    client_connection.about(
      session.link,
      account_id: account_id_of(session.status),
    )
  case entered_of(session.status) {
    Some(world_entry.Entered(character_id: store.CharacterId(id), map:, ..)) ->
      About(..about, character_id: Some(id), map: Some(map))
    None -> about
  }
}

/// The player in the world, while the connection holds one.
pub fn entered_of(status: Status) -> Option(world_entry.Entered) {
  case status {
    InWorld(entered:, ..)
    | Summoning(entered:, ..)
    | MovingItem(entered:, ..)
    | SpendingCharge(entered:, ..)
    | Buying(entered:, ..)
    | Granting(entered:, ..)
    | Selling(entered:, ..)
    | TurningIn(entered:, ..)
    | SavingPlace(entered:, ..)
    | LeavingMap(entered:, ..)
    | ClaimingSession(resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(resume: ResumeWorld(entered:), ..) -> Some(entered)
    ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey(..) -> None
  }
}

/// The id of the account the connection is for, once the hand-off has named
/// the holder.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    InCharacterSelect(
      holder: hand_off.Holder(account_id: store.AccountId(id), ..),
      ..,
    )
    | EnteringWorld(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | InWorld(holder: hand_off.Holder(account_id: store.AccountId(id), ..), ..)
    | Summoning(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | MovingItem(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | SpendingCharge(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | Buying(holder: hand_off.Holder(account_id: store.AccountId(id), ..), ..)
    | Granting(holder: hand_off.Holder(account_id: store.AccountId(id), ..), ..)
    | Selling(holder: hand_off.Holder(account_id: store.AccountId(id), ..), ..)
    | TurningIn(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | SavingPlace(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | LeavingMap(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | ClaimingSession(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | WaitingToClaim(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      ) -> Some(id)
    AwaitingHelloReply | TakingSessionKey(..) -> None
  }
}
