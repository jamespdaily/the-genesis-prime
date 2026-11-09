//// The rule of one game connection: the client's connection to the game
//// server, from the hello through character select to the player in the
//// world. It decides everything; its connection shell carries it out
//// (genesis_prime/connection/shell). The client reaches it with the session
//// key the auth server's hand-off gave it (genesis_prime/login/auth_connection).
//// This module takes each input and gives it to the flow that holds it, one
//// module each under genesis_prime/game/connection/: login, select, world,
//// movement, chat, casting, life and viewers, over the effects, frames and
//// state they share.
////
//// ```
//// client                          rule                              asks
//// connects                     ◀─ 0x3DC{0x0003 hello, realm id}, base key
//// 0x244{0x058F} (base key)     ─▶ session key from the 16 bytes
////                                 and the base key; the connection is
////                                 re-keyed: every frame after this one,
////                                 each way, is under the session key
////                                                                ─▶ hand-off: Take(SessionKey)
//// 0x244{0x07E0}                   waits in the bytes read until the
////   (same read, session key)      hand-off, then Sessions, answer
////   Taken(holder)                 watches Sessions                ─▶ sessions: Claim(account, connection)
////   Claimed                       the bytes are taken again       ─▶ store: ListCharacters(account)
////     Characters(rows)         ◀─ 0x3DC{0x0036 level}, 0x3DC{0x0117 character_list}, session key
//// 0x244{0x025C{0x025B}}        ─▶ checked                         ─▶ store: CreateCharacter(..)
////     CharacterCreated(id)     ◀─ 0x3DC{0x00DC create result}, session key
//// 0x244{0x07DD}                ─▶ world entry                     ─▶ store: LoadCharacter(account, id)
////     CharacterLoaded(row, epoch, health)                         ─▶ map MapId(world, 0): Join(connection, row, place)
////       Joined(unit record)    ◀─ 0xAD, 0x262, 0x19B, 0x25E, 0x6BC, 0x636, 0xF1, 0x61; watches the map (watch 2)
////     NotTheAccounts, or no place ◀─ 0x3DC{0x0162 refused}       ─▶ store: ListCharacters(account)
////       Characters(rows)       ◀─ 0x0036, 0x0117, as above
//// in the world, inside 0x038C: 0x637, 0x63A, 0xD5, 0x63B, 0xF2, 0xFB, 0xFC
////                              ─▶ the movement keeps the place or refuses a command
////                                 (genesis_prime/game/movement); 0x635 is logged as unhandled
//// 0x244{0x038C{0xBF 1}}        ─▶ in the world, the camp runs  ◀─ 0x3DC{0x0092 countdown, cancel 0, bonuses 0}
//// 0x244{0x038C{0xBF 0}}        ─▶ the camp is cleared; nothing is written
//// 0x244{0x038C{0xC0}}          ─▶ camp finished; the save timer is cancelled  ─▶ store: SavePlace(account, character, epoch, sequence, place, health)
////     answered, whatever it is   ─▶ map run (map, incarnation): Leave(connection)
////       Left, NotRunning or EndedBeforeAnswer ◀─ 0x3DC{0x0594 bit 1, reason 0}; the map watch is dropped;
////                                the connection is in character select again
//// 0x244{0x07E0}                ─▶ the list, as at login: 0x0036, 0x0117 (no new claim)
//// every 60 s (save timer)      ─▶ store: SavePlace(account, character, epoch, sequence, place, health)
//// the map ends (watch 2)       ─▶ store: SavePlace   ◀─ 0x3DC{0x036A reason 8}; the connection ends
//// 0x244{0x038C{kind, inner}}  ─▶ the inner message logged as unhandled under its own id,
////                                 but the messages the routing table takes in the world
//// 0x244{0x0241}                ─▶ taken and dropped (genesis_prime/game/dropped): nothing logged, nothing sent
//// 0x244{0x038C{0x023C and the other reports and requests}} ─▶ taken and dropped, the same way
//// ping 0x0, bare               ◀─ pong 0x1, bare
//// Sessions: TakenOver          ─▶ in the world, store: SavePlace  ◀─ 0x3DC{0x036A reason 19}, session key; the connection ends
//// ```
////
//// - **The hello** is the first thing written: any game server message before
////   it ends the client's login with 0x801B2 (0x1400370d0). It is the
////   connection's first input, `OwnEvent(Accepted)`, that writes it, in the game
////   wrapper under the base key, with the realm's id from the settings
////   (genesis_prime/connection/hello, opcode.0x3).
//// - **The re-key.** The client re-keys at once on sending 0x058F, so the
////   rule does too, before it asks; bytes that arrive after it in the same
////   read are read under the session key
////   (vector.0x14003827c.session_fold). The first client message must be
////   0x058F, and only one is taken: another first message, or a second 0x058F,
////   is logged as an error and ends the connection.
//// - **Reads during an ask.** Frames after the one that asked stay in the
////   bytes read and are taken once the answer comes, so 0x07E0 is taken after
////   the hand-off's and Sessions' answers, and 0x038C and 0x0241 after the
////   store's.
//// - **The server never ends a connection after the hello without telling
////   the client**, which waits for the list with no timeout and would stay on
////   its prompt otherwise (lua.Character.OnCharacterList): 0x036A in the game
////   wrapper under the cipher the connection holds at that moment, then the
////   close. Every reason drops the client to its error screen and only picks
////   the text (0x1400168a0):
////   - reason 19, "This account has been disconnected", when the hand-off
////     does not hold the session key (never put, taken, or expired), with a
////     warning naming the peer;
////   - reason 19 again, with an info line, for a connection taken over by a
////     newer login of its account;
////   - reason 8, "Lost connection with user server.", for the server's own
////     failure, with a warning: the hand-off, Sessions or the store is not
////     running, ended before it answered, gave no answer by the settings' ask
////     deadline, or the store answers `Unavailable`; and with no log for the
////     server stopping, whether it is waiting on an ask (`StoppedWaiting`) or
////     not (`Stopping`).
////   A client that breaks the protocol, closes, or whose socket fails is not
////   told: the rule logs the break and ends the connection.
//// - **A process dying or a deadline passing.** The rule holds no process:
////   a restart of the hand-off, Sessions or the store is seen only as an ask's
////   outcome (`NotRunning`, `EndedBeforeAnswer`), or, for Sessions, as the end
////   of its watch; a late answer gives the rule no input, a late `Claimed` too,
////   which leaves the slot claimed by a connection that has ended and is freed
////   by Sessions' watch on it. A crash of the connection's own process
////   drops the client, which connects again from the login.
//// - **Which feature takes a message** is the routing table's row
////   (genesis_prime/game/routing): the id, how it arrives, the stage it is taken
////   in and the feature's own kind of message. The connection keeps the shared
////   part (the hello, the re-key, the claim, the asks, the saves and every
////   ending); each feature decodes its messages and returns its decisions as
////   effects the connection carries out: a write, a warning, an ask of the
////   store or the map, the watch on the map, the save timer, and the leave of
////   the world (`Decided`), or the refusal that ends the connection; an accepted
////   0x0637 also tells the map that the player moved (`Tell`, which the shell
////   sends with no answer). The player
////   camps (genesis_prime/game/camp), moves (genesis_prime/game/movement), picks
////   a character (genesis_prime/game/character_select) and plays one
////   (genesis_prime/game/world_entry) by those rows.
//// - **0x038C** carries a 5-bit kind in its first byte, then exactly one whole
////   frame (0x14007e180, opcode.0x38c): every message the client sends in the
////   world is inside one (0x1403f4900 nests 0x637 in it). The inner message is
////   routed by the table, and logged as unhandled under its own id when it has
////   no row at the stage. A body that holds no whole frame, or
////   bytes after it, is one the client never writes, and ends the connection.
//// - **Network messages** are answered before any wrapper is read: a ping 0
////   gets a pong 1 (opcode.0x0), a pong or close notice nothing
////   (genesis_prime/client_connection, genesis_prime/connection/network_message).
//// - **Unhandled messages** are logged as a warning the first time an id comes
////   on the connection, and at debug for each repeat of it, since the client
////   sends some of them again and again. A message with no row at the stage is
////   unhandled: the movement and camp messages are taken only with the player in
////   the world, and in any other state they are.
//// - **Log lines** carry the connection, the peer and the account once the
////   hand-off has named it, and in the world the map and the character.
//// - **Limits.** Each ends the connection with nothing written, since a
////   client past one is no client: a frame longer than 131,070 bytes
////   (MessageSizeLimit 0x140335ec0), refused at its length field; more than
////   `client_connection.held_limit` bytes not yet taken, which an ask or the
////   claim's wait lets pile up, with an error log; and more frames than the
////   rate allows (`Settings.rate`, a bucket counted in whole frames when they
////   are taken), with a warning.
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection, as does a 0x025C that holds no 0x025B or a 0x025B or 0x07DD
////   whose body is cut; a whole frame of a message the rule does not take,
////   0x038C with 0x082D inside it and any other with no row, is logged as
////   unhandled and the connection goes on; 0x0241 and the reports and requests
////   of genesis_prime/game/dropped have rows, and are taken with nothing logged
////   (opcode.0x241).

import genesis_prime/client_connection.{
  type Answer, type Message, type Request, AskHandOff, Broken, Bytes, Connect,
  Continue, ForStay, Inside, Otherwise, SentByChat, SentBySessions, Settled,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/connection/hello
import genesis_prime/game/cast
import genesis_prime/game/character_select
import genesis_prime/game/chat
import genesis_prime/game/class_resource
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/dropped as connection_dropped
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/life as connection_life
import genesis_prime/game/connection/login as connection_login
import genesis_prime/game/connection/movement as connection_movement
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/select as connection_select
import genesis_prime/game/connection/state.{
  type Ending, type Session, type Status, AwaitingHelloReply, Busy,
  ClaimingSession, Ending, EnteringWorld, Greeting, InCharacterSelect, InWorld,
  LeavingMap, Present, SavingPlace, Selecting, Session, Summoning,
  TakingSessionKey, WaitingToClaim,
} as connection_state
import genesis_prime/game/connection/viewers as connection_viewers
import genesis_prime/game/connection/world as connection_world
import genesis_prime/game/player_life
import genesis_prime/game/routing
import genesis_prime/game/strike
import genesis_prime/hand_off.{SessionKey, Take}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream
import genesis_prime/message/create_character
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/game_hello_reply
import genesis_prime/message/world_message
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionEvent, type ConnectionInput,
  type ConnectionRule, type ConnectionStep, type Effect, type Event, type Now,
  type Outcome, type TimerId, type WatchId, Effects, LogDebug, LogWarning,
  OwnEffect, OwnEvent, Stopping, TimerFired, WatchEnded, Woken, Write,
}
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/game/connection"

/// What every game connection is made with, at start
/// (genesis_prime/game/connection/state).
pub type Settings =
  connection_state.Settings

/// Where the connection is. Once accepted, the state keeps the connection and
/// the peer for every log line it writes.
pub opaque type State {
  NotAccepted(settings: Settings)
  Connected(session: Session)
}

/// The longest the rule can hold the client's frames untaken, given how long
/// an ask may take: frames that arrive while an ask is out or the claim waits
/// are counted against the rate only when the answer comes. The longest run
/// without a frame taken is two asks in a row (the hand-off's then the claim,
/// or the store's then the map's) and the waits between the claims a Sessions
/// that is not running gets, `claim_retries` of `claim_wait_ms`. A rate's burst
/// must hold what a client sends at its rate through that
/// (`genesis_prime/client_connection.bucket`).
pub fn longest_wait_ms(ask_deadline_ms ask_deadline_ms: Int) -> Int {
  2
  * ask_deadline_ms
  + connection_login.claim_wait_ms
  * connection_login.claim_retries
}

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> ConnectionRule(Settings, State, Request, Message, Answer) {
  step.Rule(name: rule_name, settings:, new:, step:)
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  NotAccepted(settings:)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: ConnectionInput(Message, Answer),
) -> #(State, ConnectionStep(Request)) {
  case state {
    NotAccepted(settings:) ->
      case
        client_connection.hear(input.event, about: step.no_one, stopping: fn() {
          []
        })
      {
        Connect(connection:, peer:, seed:) -> #(
          Connected(Session(
            settings:,
            link: client_connection.link(
              connection:,
              peer:,
              seed:,
              bucket: settings.rate,
              now: input.now,
            ),
            pending: <<>>,
            cipher: cipher.base(),
            unhandled_logged: set.new(),
            unrelayed_logged: set.new(),
            unhandled_channels_logged: set.new(),
            unknown_zones_logged: set.new(),
            next_whisper: 1,
            move_seq: 0,
            last_stay: stay.none_yet(),
            status: AwaitingHelloReply,
          )),
          Effects([OwnEffect(Write(hello_bytes(settings)))]),
        )
        Bytes(..) | client_connection.Outcome(..) -> #(
          state,
          client_connection.before_accepted(rule: "game"),
        )
        Otherwise(step:) -> #(state, step)
      }
    Connected(session:) ->
      connected(session:, now: input.now, event: input.event)
  }
}

fn connected(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(State, ConnectionStep(Request)) {
  case event {
    OwnEvent(Woken(message: SentBySessions(message:))) ->
      settled(
        handled: connection_login.sessions_sent(session:, now:, message:),
        now:,
      )
    OwnEvent(Woken(message: ForStay(stay:, sent:))) ->
      settled(handled: stay_sent(session:, now:, stay:, sent:), now:)
    OwnEvent(Woken(message: SentByChat(tell:))) ->
      settled(handled: connection_chat.chat_sent(session:, tell:), now:)
    WatchEnded(watch:) ->
      settled(handled: watch_ended(session:, now:, watch:), now:)
    OwnEvent(TimerFired(timer:)) if timer == connection_state.save_timer ->
      settled(handled: connection_world.save_due(session:, now:), now:)
    OwnEvent(TimerFired(timer:)) ->
      settled(handled: other_timer_fired(session:, now:, timer:), now:)
    OwnEvent(step.PeerClosed)
    | OwnEvent(step.ReadFailed(failure: step.Closed))
    | OwnEvent(step.WriteFailed(failure: step.Closed)) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(log: None, notice: None),
        within_ms: session.settings.ask_deadline_ms,
      )
    OwnEvent(step.ReadFailed(failure:))
    | OwnEvent(step.WriteFailed(failure:)) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(
          log: Some(#(LogWarning, client_connection.socket_failed_text(failure))),
          notice: None,
        ),
        within_ms: session.settings.ask_deadline_ms,
      )
    Stopping(deadline_ms:) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(log: None, notice: Some(LostUserServer)),
        within_ms: int.min(
          session.settings.ask_deadline_ms,
          deadline_ms - now.monotonic_ms,
        ),
      )
    OwnEvent(step.Accepted(..))
    | OwnEvent(step.Read(..))
    | OwnEvent(step.Answered(..)) -> heard(session:, now:, event:)
  }
}

/// An input that ends the connection when it is taken by one that holds a
/// player in the world: the end is `ending`, after the save of the player's
/// place within `within_ms`. In any other state it is the same input every
/// client connection rule takes (`heard`). The game rule takes these inputs
/// itself, before `client_connection.hear`, which ends the connection at once
/// for every rule.
fn leaves_or_hears(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
  ending ending: Ending,
  within_ms within_ms: Int,
) -> #(State, ConnectionStep(Request)) {
  case connection_state.holds_a_player(session.status) {
    Some(_) ->
      settled(
        handled: connection_state.end_with(session:, now:, ending:, within_ms:),
        now:,
      )
    None -> heard(session:, now:, event:)
  }
}

/// An input the client's side or an ask's outcome gives, sorted by what every
/// client connection rule does alike.
fn heard(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(State, ConnectionStep(Request)) {
  case
    client_connection.hear(
      event,
      about: connection_state.about_of(session),
      stopping: fn() { server_stopping(session) },
    )
  {
    Bytes(bytes:) ->
      case
        client_connection.hold(
          session:,
          held: session.pending,
          bytes:,
          about: connection_state.about_of(session),
        )
      {
        Error(handled) -> settled(handled:, now:)
        Ok(pending) -> {
          let session = Session(..session, pending:)
          case asking(session.status) {
            // A frame is taken only once the answer to the ask in flight comes.
            True -> #(Connected(session), Effects([]))
            False ->
              client_connection.drive(session:, flow: flow(now), carried: [])
          }
        }
      }
    client_connection.Outcome(outcome:) ->
      settled(handled: answered(session:, now:, outcome:), now:)
    Connect(..) -> #(
      Connected(session),
      client_connection.accepted_again(
        about: connection_state.about_of(session),
        rule: "game",
      ),
    )
    Otherwise(step:) -> #(Connected(session), step)
  }
}

/// What an input decided, carried out as the rule takes the client's frames at
/// the time of the input.
fn settled(
  handled handled: client_connection.Handled(Session),
  now now: Now,
) -> #(State, ConnectionStep(Request)) {
  client_connection.settle(
    handled: connection_casting.persisted(handled:, now:),
    flow: flow(now),
    carried: [],
  )
}

/// Whether an ask is in flight, so the frames after the one that asked wait.
fn asking(status: Status) -> Bool {
  case status {
    TakingSessionKey
    | ClaimingSession(..)
    | WaitingToClaim(..)
    | EnteringWorld(..)
    | Summoning(..)
    | SavingPlace(..)
    | LeavingMap(..) -> True
    InCharacterSelect(select:, ..) -> character_select.waiting(select)
    AwaitingHelloReply | InWorld(..) -> False
  }
}

/// How the rule takes the client's frames, at the time of an input.
fn flow(now: Now) -> client_connection.Flow(Session, Frame, FrameError, State) {
  client_connection.Flow(
    pending: fn(session: Session) { session.pending },
    take: frame.take,
    taking: fn(session, whole, rest) {
      connection_casting.persisted(
        handled: handle(
          session: Session(..session, pending: rest),
          now:,
          frame: whole,
        ),
        now:,
      )
    },
    refused: fn(session, error) {
      connection_state.end_for(
        session:,
        now:,
        text: "the bytes are no frame: " <> frame.describe(error),
      )
    },
    charged: fn(session) {
      client_connection.charge(
        session:,
        link: session.link,
        now:,
        about: connection_state.about_of(session),
        relinked: fn(link) { Session(..session, link:) },
      )
    },
    connected: Connected,
  )
}

/// The hello, in the game wrapper under the base key (genesis_prime/connection/hello).
fn hello_bytes(settings: Settings) -> BitArray {
  client_connection.wrapped(
    GameWrapper,
    hello.frame(realm_id: settings.realm_id),
    cipher.base(),
  )
}

/// What a connection writes before it ends when the server stops: the notice
/// that the server failed, so the client leaves its prompt. A stop is no
/// failure, so no log line comes with it.
fn server_stopping(
  session: Session,
) -> List(Effect(ConnectionEffect(Request))) {
  [connection_state.notice(session:, reason: LostUserServer)]
}

/// What one whole frame does: the network layer's messages first, then the
/// message in the client's wrapper.
fn handle(
  session session: Session,
  now now: Now,
  frame whole: Frame,
) -> client_connection.Handled(Session) {
  case
    client_connection.open(
      session:,
      about: connection_state.about_of(session),
      server: "game",
      frame: whole,
      cipher: session.cipher,
    )
  {
    Settled(handled:) -> handled
    Inside(inner:) -> inner_message(session:, now:, inner:)
    Broken(text:) -> connection_state.end_for(session:, now:, text: text)
  }
}

/// What the message in the client's wrapper does: the routing table says
/// which feature takes it at the connection's stage (genesis_prime/game/routing),
/// and the feature decides. Before the hello reply any other message ends the
/// connection; at any later stage a message with no row is logged as unhandled.
fn inner_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case connection_state.standing(session.status) {
    Busy(text:) -> connection_state.end_for(session:, now:, text:)
    Greeting -> routed(session:, now:, inner:, stage: routing.BeforeHelloReply)
    Selecting(..) ->
      routed(session:, now:, inner:, stage: routing.AtCharacterSelect)
    Present(..) -> routed(session:, now:, inner:, stage: routing.AtWorld)
  }
}

/// A message in the client's wrapper at a stage, given to the feature the
/// table names, or logged as unhandled when it has no row there.
fn routed(
  session session: Session,
  now now: Now,
  inner inner: Frame,
  stage stage: routing.Stage,
) -> client_connection.Handled(Session) {
  case
    routing.route(
      stage:,
      arrival: routing.OnItsOwn,
      message_id: inner.message_id,
    )
  {
    Ok(routing.Hello) -> hello_message(session:, now:, inner:)
    Ok(routing.CharacterSelect(message:)) ->
      connection_select.select_message(session:, now:, inner:, message:)
    Ok(routing.WorldEntry) ->
      connection_select.play_requested(session:, now:, inner:)
    Ok(routing.WorldMessage) -> world_carried(session:, now:, inner:)
    Ok(routing.Dropped(message:)) ->
      connection_dropped.dropped_message(session:, now:, inner:, message:)
    Ok(routing.Movement(..))
    | Ok(routing.Camp(..))
    | Ok(routing.Chat(..))
    | Ok(routing.Cast(..))
    | Ok(routing.Life(..))
    | Ok(routing.Innate(..)) ->
      connection_state.misrouted(session:, now:, inner:)
    Error(Nil) ->
      case stage {
        routing.BeforeHelloReply ->
          connection_state.end_for(
            session:,
            now:,
            text: "the first message of a game connection is 0x058F, not "
              <> client_connection.message_text(inner.message_id),
          )
        routing.AtCharacterSelect | routing.AtWorld ->
          unhandled(session:, message_id: inner.message_id)
      }
  }
}

/// The client's 0x058F: the first one is the hello's reply, and a second ends
/// the connection.
fn hello_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case connection_state.standing(session.status) {
    Greeting -> hello_replied(session:, now:, inner:)
    Selecting(..) | Present(..) | Busy(..) ->
      connection_state.end_for(
        session:,
        now:,
        text: "0x058F was sent a second time",
      )
  }
}

/// A whole frame of a message the rule does not take, logged as unhandled:
/// a warning the first time its id comes on the connection, and a debug line
/// for each repeat, since the client sends some of them on every move.
fn unhandled(
  session session: Session,
  message_id message_id: Int,
) -> client_connection.Handled(Session) {
  let level = case set.contains(session.unhandled_logged, message_id) {
    True -> LogDebug
    False -> LogWarning
  }
  let session =
    Session(
      ..session,
      unhandled_logged: set.insert(session.unhandled_logged, message_id),
    )
  client_connection.unhandled(
    session:,
    about: connection_state.about_of(session),
    server: "game",
    message_id:,
    level:,
  )
}

/// The client's 0x038C: a 5-bit kind and one whole inner frame
/// (opcode.0x38c), which is every message the client sends in the world. The
/// routing table says which feature takes the inner message with the player in
/// the world (genesis_prime/game/routing), and any other is logged as unhandled
/// under its own id. A body that holds no whole frame, or bytes after it, is
/// one the client never writes, and ends the connection.
fn world_carried(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case world_message.decode(inner.body) {
    Error(error) ->
      connection_state.end_for(
        session:,
        now:,
        text: client_connection.describe_undecoded(client_connection.Undecoded(
          message_id: world_message.message_id,
          error:,
        )),
      )
    Ok(carried) ->
      case frame.parse(carried.inner_frame) {
        Error(error) ->
          connection_state.end_for(
            session:,
            now:,
            text: "0x038C holds no whole frame: " <> frame.describe(error),
          )
        Ok(whole) ->
          case connection_state.standing(session.status) {
            Present(holder:, entered:) ->
              case
                routing.route(
                  stage: routing.AtWorld,
                  arrival: routing.InsideWorldMessage,
                  message_id: whole.message_id,
                )
              {
                Ok(routing.Movement(message:)) ->
                  connection_movement.movement_message(
                    session:,
                    now:,
                    holder:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Camp(message:)) ->
                  connection_world.camp_message(
                    session:,
                    now:,
                    holder:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Chat(message:)) ->
                  connection_chat.chat_message(
                    session:,
                    now:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Cast(message:)) ->
                  connection_casting.cast_message(
                    session:,
                    now:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Life(message:)) ->
                  connection_life.life_message(
                    session:,
                    now:,
                    holder:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Innate(message:)) ->
                  connection_world.innate_message(
                    session:,
                    now:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Dropped(message:)) ->
                  connection_dropped.dropped_message(
                    session:,
                    now:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Hello)
                | Ok(routing.CharacterSelect(..))
                | Ok(routing.WorldEntry)
                | Ok(routing.WorldMessage) ->
                  connection_state.misrouted(session:, now:, inner: whole)
                Error(Nil) -> unhandled(session:, message_id: whole.message_id)
              }
            Greeting | Selecting(..) | Busy(..) ->
              unhandled(session:, message_id: whole.message_id)
          }
      }
  }
}

/// The client's 0x058F: the connection is keyed from the session key at once,
/// as the client keys its own (vector.0x14003827c.session_fold), and the
/// hand-off is asked to take the key.
fn hello_replied(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case game_hello_reply.decode(inner.body) {
    Error(error) ->
      connection_state.end_for(
        session:,
        now:,
        text: "the game hello reply 0x058F does not decode: "
          <> bit_stream.describe_decode(error:),
      )
    Ok(reply) -> {
      let assert Ok(key) = guid.from_wire(reply.session_key)
        as "the reply's session key is 16 bytes"
      case rekeyed(session_key: reply.session_key) {
        Error(error) ->
          connection_state.end_for(
            session:,
            now:,
            text: "the session key makes no cipher: "
              <> describe_key_error(error),
          )
        Ok(keyed) ->
          connection_state.ask(
            session: Session(..session, cipher: keyed, status: TakingSessionKey),
            now:,
            request: AskHandOff(Take(SessionKey(key:))),
            before: [],
          )
      }
    }
  }
}

/// The cipher a game connection is keyed to from the moment the client sends
/// 0x058F: the base key folded with the 16 bytes of the session key the
/// message carries (vector.0x14003827c.session_fold). Every frame after that
/// one, each way, is under it.
pub fn rekeyed(
  session_key session_key: BitArray,
) -> Result(Cipher, cipher.KeyError) {
  cipher.session_key(bytes: session_key, base_key: cipher.base_key)
  |> result.try(cipher.new)
}

fn describe_key_error(error: cipher.KeyError) -> String {
  case error {
    cipher.ZeroKey -> "the key is 0, which the client refuses"
    cipher.SessionKeyNotSixteenBytes(bytes:) ->
      "the session key is " <> int.to_string(bytes) <> " bytes, not 16"
  }
}

/// The ids of the client's messages the rule takes: each row of the routing
/// table (genesis_prime/game/routing), and 0x025B, the create request that
/// 0x025C carries. A stage takes some of them: before the hello reply only
/// 0x058F, in the world 0x038C and, from inside it, the movement and camp
/// messages. The coverage measure counts all of them as handled.
pub fn taken_message_ids() -> List(Int) {
  list.flatten([
    [create_character.message_id],
    routing.message_ids(arrival: routing.OnItsOwn),
    carried_message_ids(),
  ])
}

/// The ids of the client's messages the rule takes only from inside 0x038C with
/// the player in the world: the movement and camp messages. Sent on their own,
/// as the client never does, or with no player in the world, they are logged as
/// unhandled.
pub fn carried_message_ids() -> List(Int) {
  routing.message_ids(arrival: routing.InsideWorldMessage)
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case session.status {
    TakingSessionKey -> connection_login.key_taken(session:, now:, outcome:)
    ClaimingSession(holder:, resume:, retries:) ->
      connection_login.claim_answered(
        session:,
        now:,
        holder:,
        resume:,
        retries:,
        outcome:,
      )
    InCharacterSelect(holder:, select:) ->
      connection_select.select_answered(
        session:,
        now:,
        holder:,
        select:,
        outcome:,
      )
    EnteringWorld(holder:, entry:, from:) ->
      connection_world.entry_answered(
        session:,
        now:,
        holder:,
        entry:,
        from:,
        outcome:,
      )
    Summoning(holder:, entered:) ->
      connection_chat.summon_answered(
        session:,
        now:,
        holder:,
        entered:,
        outcome:,
      )
    SavingPlace(holder:, entered:, then:) ->
      connection_world.save_answered(
        session:,
        now:,
        holder:,
        entered:,
        then:,
        outcome:,
      )
    LeavingMap(holder:, entered:, then:) ->
      connection_world.leave_answered(
        session:,
        now:,
        holder:,
        entered:,
        then:,
        outcome:,
      )
    AwaitingHelloReply | WaitingToClaim(..) | InWorld(..) ->
      connection_state.end_for(
        session:,
        now:,
        text: "an answer came when no ask was out",
      )
  }
}

/// What another process sent for a stay of the player (`ForStay`), taken at this
/// one entry point: only while the player is in the world, and only when the stay
/// is the player's own (genesis_prime/world_map/stay). Any other is dropped: it was
/// sent for an earlier stay, before a camp or the Holocrypt, and reaches a later
/// one whose client holds none of the earlier units and whose creatures and
/// viewers are others, or it reaches no stay at all. A dropped strike finds no
/// answer, and the creature's deadline leaves the player out.
fn stay_sent(
  session session: Session,
  now now: Now,
  stay stay: Stay,
  sent sent: client_connection.StaySent,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    Some(#(holder, entered)) if entered.stay == stay ->
      case sent {
        client_connection.SentByMap(notice:) ->
          connection_viewers.map_sent(session:, now:, entered:, notice:)
        client_connection.SentByPeer(news:) ->
          connection_viewers.viewer_takes(session:, now:, entered:, news:)
        client_connection.SentByFoe(fight:) ->
          connection_life.foe_taken(session:, now:, holder:, entered:, fight:)
        client_connection.SentByTarget(answered:) ->
          connection_casting.target_taken(session:, now:, entered:, answered:)
        client_connection.SentByKill(credit:) ->
          connection_experience.credited(session:, now:, entered:, credit:)
      }
    Some(_) | None -> Continue(session, [])
  }
}

/// A timer fired that is not the save timer's: a cast's, a strike's, the class
/// resource's, the player's regeneration's, or the claim's.
fn other_timer_fired(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case
    cast.owns(timer),
    strike.owns(timer),
    class_resource.owns(timer:),
    player_life.owns(timer:)
  {
    True, _, _, _ -> connection_casting.cast_due(session:, now:, timer:)
    False, True, _, _ -> connection_casting.strike_due(session:, now:)
    False, False, True, _ -> connection_resource.resource_due(session:, timer:)
    False, False, False, True ->
      connection_life.regeneration_due(session:, now:, timer:)
    False, False, False, False ->
      connection_login.claim_wait_over(session:, now:, timer:)
  }
}

/// The end of a watch the rule opened. Sessions' (`sessions_watch`): the
/// connection waits on the claim timer, then claims its account again from
/// where it is, in character select or in the world. The player's map
/// (`map_watch`): the player is gone from the world, so the client is told the
/// server failed (0x036A reason 8) and the connection ends. A watch this rule
/// did not open, or one that ends where the connection holds none, is a bug.
fn watch_ended(
  session session: Session,
  now now: Now,
  watch watch: WatchId,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    Some(#(_, entered)) ->
      case chat.watch_ended(chat: entered.chat, watch:) {
        Ok(#(updated, effects)) ->
          connection_chat.carry_chat(
            session: connection_chat.with_chat(session:, chat: updated),
            effects:,
          )
        Error(Nil) -> connection_login.own_watch_ended(session:, now:, watch:)
      }
    None -> connection_login.own_watch_ended(session:, now:, watch:)
  }
}
