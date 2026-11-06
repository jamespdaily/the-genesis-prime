//// What the game connection's rule keeps and the parts every flow of it shares
//// (genesis_prime/game/connection): the session and its status, the log lines,
//// the asks, the notice and every ending, the save of the player's place, and
//// the tells of news to the players who see the player.

import genesis_prime/client_connection.{
  type Bucket, type Link, type Request, AskStore, Asking, Done, TellPeer,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/character_select
import genesis_prime/game/class_resource
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/world_entry
import genesis_prime/game_settings.{type GameSettings}
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, LostUserServer,
}
import genesis_prime/step.{
  type About, type ConnectionEffect, type ConnectionId, type Effect, type Now,
  About, LogWarning, OwnEffect, Stop, TimerId, WatchId, Write,
}
import genesis_prime/store
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
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
    /// The numbers the server chose, from the content load
    /// (genesis_prime/content/game_number), of which a player entering the world
    /// reads its health regeneration (genesis_prime/game/player_life).
    numbers: GameNumbers,
  )
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
    status: Status,
  )
}

/// The connection's one status.
pub type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key.
  TakingSessionKey
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
  /// The store is asked to save where the player stands, and its answer is
  /// awaited; `then` says what follows it. A connection in this status ends
  /// without a second save: the save out is the one its end waits for.
  SavingPlace(holder: Holder, entered: world_entry.Entered, then: AfterSave)
  /// The camp's place is saved and the map's run is asked to take the player
  /// out (`world_map/map.Leave`), and its answer is awaited. A connection in this
  /// status ends without a save: the place is already saved, and the map drops
  /// a player whose connection ends. `then` says what follows `Left`.
  LeavingMap(holder: Holder, entered: world_entry.Entered, then: AfterLeave)
}

/// What follows the map's answer to a leave.
pub type AfterLeave {
  /// The camp: 0x0594 and a new character select.
  ToCharacterSelect
  /// The Holocrypt: the map of `place`'s world is asked to take the player there
  /// (`world_entry.rejoining`), and its entry burst follows.
  JoinAt(place: Place)
}

/// Where an entry into the world started, for what its refusal does.
pub type EntryFrom {
  /// A play in character select: the refusal is 0x0162 and the list again.
  FromCharacterSelect
  /// The Holocrypt, with the client still in the world: the refusal is 0x0594,
  /// as the camp's leave writes, then a new character select.
  FromHolocrypt
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

/// A message in the game wrapper under the cipher the connection holds.
pub fn to_client(
  session session: Session,
  inner inner: Frame,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(
    Write(client_connection.wrapped(GameWrapper, inner, session.cipher)),
  )
}

/// 0x036A with the reason, in the game wrapper under the cipher the
/// connection holds, so the client leaves its prompt.
pub fn notice(
  session session: Session,
  reason reason: DisconnectReason,
) -> Effect(ConnectionEffect(Request)) {
  let assert Ok(body) = disconnect_notice.encode(DisconnectNotice(reason:))
    as "a reason is within 5 bits"
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
    TakingSessionKey
    | ClaimingSession(..)
    | EnteringWorld(..)
    | Summoning(..)
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
      <> client_connection.message_text(inner.message_id)
      <> " to a feature that does not take it here",
  )
}

/// The connections that see the player, each with its player's stay, in the
/// order of their numbers.
pub fn sorted_viewers(
  entered entered: world_entry.Entered,
) -> List(#(ConnectionId, Stay)) {
  map.sorted_by_connection(entered.viewers)
}

/// The player's level: its unit's stat 10, 1 when it has none.
pub fn level_of(entered entered: world_entry.Entered) -> Int {
  unit_fields.stat(tail: entered.unit.tail, stat_id: unit_fields.level_stat)
  |> result.unwrap(1)
}

/// The connections whose players see the player.
pub fn viewer_connections(
  entered entered: world_entry.Entered,
) -> Set(ConnectionId) {
  set.from_list(dict.keys(entered.viewers))
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
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey -> None
  }
}

/// The tell of news about the player's own unit to the connection of a player
/// who sees it, for that player's stay.
pub fn news_to(
  entered entered: world_entry.Entered,
  viewer viewer: #(ConnectionId, Stay),
  news news: client_connection.News,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Connection(viewer.0),
    request: TellPeer(
      stay: viewer.1,
      news: client_connection.PeerNews(unit_id: entered.unit_id, news:),
    ),
  ))
}

/// The tell of news to the connection, when its player sees this one; none when
/// it no longer does: its client was sent the unit's 0x355 and forgot the unit.
pub fn news_to_connection(
  entered entered: world_entry.Entered,
  connection connection: ConnectionId,
  news news: client_connection.News,
) -> List(Effect(ConnectionEffect(Request))) {
  case dict.get(entered.viewers, connection) {
    Ok(stay) -> [news_to(entered:, viewer: #(connection, stay), news:)]
    Error(Nil) -> []
  }
}

/// The tells that remove the player's own unit from the client of each player who
/// sees it, for its camp and the Holocrypt, which send them before its leave is
/// asked: the map's `Unwatched` after the leave would be a second sender of news
/// of the unit.
pub fn removes_its_unit_from_the_viewers(
  entered entered: world_entry.Entered,
) -> List(Effect(ConnectionEffect(Request))) {
  list.map(sorted_viewers(entered:), fn(viewer) {
    news_to(entered:, viewer:, news: client_connection.Removed)
  })
}

/// The session with the player it holds in the world changed by `change`: the
/// player in the world, or in the world and waiting to claim again, where a send
/// is taken. A status that takes no send, since the shell takes none while an ask
/// is out, or that holds no player in the world, is as it was.
pub fn with_entered(
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
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | Summoning(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey -> session.status
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
/// `SavingPlace` holds the player too, but its save is out, so its end saves
/// nothing more; in `LeavingMap` the place is already saved.
pub fn holds_a_player(
  status: Status,
) -> Option(#(Holder, world_entry.Entered)) {
  case status {
    InWorld(holder:, entered:)
    | Summoning(holder:, entered:)
    | ClaimingSession(holder:, resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(holder:, resume: ResumeWorld(entered:), ..) ->
      Some(#(holder, entered))
    SavingPlace(..)
    | LeavingMap(..)
    | ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey -> None
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
    | SavingPlace(entered:, ..)
    | LeavingMap(entered:, ..)
    | ClaimingSession(resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(resume: ResumeWorld(entered:), ..) -> Some(entered)
    ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey -> None
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
    AwaitingHelloReply | TakingSessionKey -> None
  }
}
