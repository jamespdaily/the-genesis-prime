//// The rule of one game connection: the client's connection to the game
//// server, from the hello to the character list its select screen shows. It
//// decides everything; its connection shell carries it out
//// (genesis_prime/connection/shell). The client reaches it with the session
//// key the auth server's hand-off gave it (genesis_prime/login/auth_connection).
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
//// 0x244{0x07DD}                ◀─ 0x3DC{0x0162 refused}           ─▶ store: ListCharacters(account)
////     Characters(rows)         ◀─ 0x0036, 0x0117, as above
//// 0x244{0x038C{0x082D}}        ─▶ logged as unhandled
//// 0x244{0x0241}                ─▶ logged as unhandled
//// ping 0x0, bare               ◀─ pong 0x1, bare
//// Sessions: TakenOver          ◀─ 0x3DC{0x036A reason 19}, session key; the connection ends
//// ```
////
//// - **The hello** is the first thing written: any game server message before
////   it ends the client's login with 0x801B2 (0x1400370d0). It is the
////   connection's first input, `Socket(Accepted)`, that writes it, in the game
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
//// - **The claim** makes this connection the account's one session
////   (genesis_prime/sessions). It follows the hand-off's answer, since the
////   account is known only then, and comes before the list, so a client that
////   reaches character select holds the slot. The rule opens a watch on
////   Sessions with each claim, numbered from 1 by a counter that does not go
////   back. Sessions answers `Claimed` to every claim, sending the previous
////   holder `TakenOver` first.
//// - **Taken over.** `Woken(TakenOver)`, when the connection holds the slot or
////   is claiming it again, writes 0x036A reason 19 (AccountDisconnected) under
////   the cipher the connection holds, logs the takeover at info and ends the
////   connection. The client drops to its error screen and shows "This account
////   has been disconnected" (0x1400168a0, which only picks the text by the
////   reason). The message is taken between steps, never while an ask is out:
////   a takeover that arrives while the connection waits on an ask that then
////   fails is never taken, because the failure ends the connection, so that
////   client gets the failure's text (reason 8) and not the account's. Both
////   texts end the connection; taking a delivery during an ask would make the
////   shell decide by a message's content.
//// - **Sessions ending.** When the watch on Sessions ends (`WatchEnded`) the
////   connection waits `claim_wait_ms` on a timer, since a restarted Sessions
////   is not yet there, then claims again (`TimerFired`), with its character
////   select state kept and the frames it holds waiting for the answer; the
////   client sees nothing. A claim that finds Sessions not running (the
////   outcome `NotRunning`) drops its watch and waits again, up to
////   `claim_retries` times, before the client is told the server failed. A
////   claim Sessions does not answer, or that ends before its answer, is that
////   failure at once.
//// - **The character list and creating a character** are character select's
////   own feature (genesis_prime/game/character_select): it makes its own store
////   asks and takes the store's answers, and the rule turns its effects into
////   writes in the game wrapper, log lines and the ask. The rule decodes what
////   the client sent into typed values first: 0x025C carries the whole frame
////   of 0x025B (opcode.0x25c), and 0x07DD is the client's play request. The
////   failures every ask shares (no answer, or the store unavailable) are the
////   rule's, so a request added to character select adds no status here.
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
////   of its watch; a late answer (`AnsweredLate`) is dropped, also a late
////   `Claimed`, which leaves the slot claimed by a connection that has ended
////   and is freed by Sessions' watch on it. A crash of the connection's own process
////   drops the client, which connects again from the login.
//// - **Network messages** are answered before any wrapper is read: a ping 0
////   gets a pong 1 (opcode.0x0), a pong or close notice nothing
////   (genesis_prime/client_connection, genesis_prime/connection/network_message).
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection, as does a 0x025C that holds no 0x025B or a 0x025B or 0x07DD
////   whose body is cut; a whole frame of a message the rule does not take,
////   0x038C with 0x082D inside it, 0x0241 and any other, is logged as
////   unhandled and the connection goes on (opcode.0x241).

import genesis_prime/client_connection.{
  type Answer, type Link, type Message, type Request, AskHandOff, AskSessions,
  AskStore, Asking, Bytes, Connect, Continue, End, FromHandOff, FromSessions,
  FromStore, Inside, Otherwise, SentBySessions, Settled, Waiting,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError, Frame}
import genesis_prime/connection/hello
import genesis_prime/game/character_select
import genesis_prime/hand_off.{type Holder, SessionKey, Take}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream
import genesis_prime/message/character_select_start
import genesis_prime/message/create_character
import genesis_prime/message/create_character_carrier
import genesis_prime/message/delete_character
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, AccountDisconnected, LostUserServer,
}
import genesis_prime/message/game_hello_reply
import genesis_prime/message/play_character
import genesis_prime/message/rename_character
import genesis_prime/sessions
import genesis_prime/step.{
  type Effect, type Input, type Now, type Outcome, type Rule, type Step,
  type TimerId, type WatchId, Answered, AnsweredLate, Asked, Effects, LogInfo,
  LogWarning, Sessions, Socket, StartTimer, Started, Stop, Stopping, TimerFired,
  TimerId, Unwatch, Watch, WatchEnded, WatchId, Woken, Write,
}
import genesis_prime/store
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/game/connection"

/// What every game connection is made with, at start.
pub type Settings {
  Settings(
    /// The realm's id: the hello's, and the character list's, which becomes
    /// the client's current realm when it plays a character (opcode.0x117).
    realm_id: Int,
    /// The number of characters the client's list is told the account may
    /// have; the Lua keeps it and nothing reads it (lua.Character.OnCharacterList).
    max_characters: Int,
    /// The characters an account may have: the client's own count of slots
    /// for an account with no entitlement, which no message carries
    /// (lua.CharacterSelection.OnLoadFromCharacter).
    character_slots: Int,
    /// The client's game tables, which a create request and the list's body
    /// visuals are read from.
    tables: table_store.Tables,
    /// How long an ask to the hand-off, Sessions or the store may take.
    ask_deadline_ms: Int,
  )
}

/// Where the connection is. Once accepted, the state keeps the connection and
/// the peer for every log line it writes.
pub opaque type State {
  NotAccepted(settings: Settings)
  Connected(session: Session)
}

/// What an accepted connection keeps.
type Session {
  Session(
    settings: Settings,
    link: Link,
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
    /// The cipher the connection's frames are read and written under: the
    /// base key's until 0x058F re-keys it.
    cipher: Cipher,
    /// How many watches on Sessions the rule has opened; the open one, while
    /// the connection holds the slot, is the last.
    watches: Int,
    status: Status,
  )
}

/// The connection's one status.
type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key.
  TakingSessionKey
  /// Sessions is asked to make the connection the account's session, or the
  /// connection waits on the claim timer before it asks. `select` is the
  /// character select the client is in after the answer: new for the first
  /// claim, the one it was in when Sessions ended for a later one. `retries` is
  /// how many times Sessions was not running for this claim.
  ClaimingSession(holder: Holder, select: character_select.State, retries: Int)
  /// The session key was held for `holder` and Sessions holds the account's
  /// slot for this connection; the client is in character select, which holds
  /// its own state, asks the store itself and says when its answer is awaited.
  InCharacterSelect(holder: Holder, select: character_select.State)
}

/// How long a connection waits before it claims again after Sessions ended or
/// was not running. A restarted Sessions is started by its supervisor at once,
/// so a short wait finds it; the client's screen shows nothing meanwhile.
const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
/// With the wait, it bounds how long a client waits on its prompt for a
/// Sessions that does not come back: half a second, then it is told the
/// server failed, as for the store.
const claim_retries = 5

/// The timer a connection waits on before it claims again; one runs at a
/// time.
const claim_timer = TimerId(1)

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> Rule(Settings, State, Message, Answer, Nil, Request) {
  step.Rule(name: rule_name, settings:, new:, step:)
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  NotAccepted(settings:)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Message, Answer),
) -> #(State, Step(Nil, Request)) {
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
            link: client_connection.link(connection:, peer:, seed:),
            pending: <<>>,
            cipher: cipher.base(),
            watches: 0,
            status: AwaitingHelloReply,
          )),
          Effects([Write(hello_bytes(settings))]),
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
  event event: step.Event(Message, Answer),
) -> #(State, Step(Nil, Request)) {
  case event {
    Woken(message: SentBySessions(message:)) ->
      client_connection.settle(
        handled: sessions_sent(session:, message:),
        flow: flow(now),
        carried: [],
      )
    WatchEnded(watch:) ->
      client_connection.settle(
        handled: sessions_ended(session:, watch:),
        flow: flow(now),
        carried: [],
      )
    TimerFired(timer:) ->
      client_connection.settle(
        handled: claim_wait_over(session:, now:, timer:),
        flow: flow(now),
        carried: [],
      )
    Started
    | Socket(..)
    | Asked(..)
    | Answered(..)
    | AnsweredLate(..)
    | Stopping(..) -> heard(session:, now:, event:)
  }
}

/// An input the client's side or an ask's outcome gives, sorted by what every
/// client connection rule does alike.
fn heard(
  session session: Session,
  now now: Now,
  event event: step.Event(Message, Answer),
) -> #(State, Step(Nil, Request)) {
  case
    client_connection.hear(
      event,
      about: client_connection.about(
        session.link,
        account_id: account_id_of(session.status),
      ),
      stopping: fn() { server_stopping(session) },
    )
  {
    Bytes(bytes:) -> {
      let session =
        Session(..session, pending: <<session.pending:bits, bytes:bits>>)
      case asking(session.status) {
        // A frame is taken only once the answer to the ask in flight comes.
        True -> #(Connected(session), Effects([]))
        False -> client_connection.drive(session:, flow: flow(now), carried: [])
      }
    }
    client_connection.Outcome(outcome:) ->
      client_connection.settle(
        handled: answered(session:, now:, outcome:),
        flow: flow(now),
        carried: [],
      )
    Connect(..) -> #(
      Connected(session),
      client_connection.accepted_again(
        link: session.link,
        account_id: account_id_of(session.status),
        rule: "game",
      ),
    )
    Otherwise(step:) -> #(Connected(session), step)
  }
}

/// Whether an ask is in flight, so the frames after the one that asked wait.
fn asking(status: Status) -> Bool {
  case status {
    TakingSessionKey | ClaimingSession(..) -> True
    InCharacterSelect(select:, ..) -> character_select.waiting(select)
    AwaitingHelloReply -> False
  }
}

/// How the rule takes the client's frames, at the time of an input.
fn flow(now: Now) -> client_connection.Flow(Session, Frame, FrameError, State) {
  client_connection.Flow(
    pending: fn(session: Session) { session.pending },
    take: frame.take,
    taking: fn(session, whole, rest) {
      handle(session: Session(..session, pending: rest), now:, frame: whole)
    },
    refused: fn(session, error) {
      end_for(session, "the bytes are no frame: " <> frame.describe(error))
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

/// A message in the game wrapper under the cipher the connection holds.
fn to_client(session: Session, inner: Frame) -> Effect(Nil) {
  Write(client_connection.wrapped(GameWrapper, inner, session.cipher))
}

/// 0x036A with the reason, in the game wrapper under the cipher the
/// connection holds, so the client leaves its prompt.
fn notice(
  session session: Session,
  reason reason: DisconnectReason,
) -> Effect(Nil) {
  let assert Ok(body) = disconnect_notice.encode(DisconnectNotice(reason:))
    as "a reason is within 5 bits"
  to_client(session, Frame(disconnect_notice.message_id, body))
}

/// What a connection writes before it ends when the server stops: the notice
/// that the server failed, so the client leaves its prompt. A stop is no
/// failure, so no log line comes with it.
fn server_stopping(session: Session) -> List(Effect(Nil)) {
  [notice(session:, reason: LostUserServer)]
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
      link: session.link,
      account_id: account_id_of(session.status),
      server: "game",
      frame: whole,
      cipher: session.cipher,
    )
  {
    Settled(handled:) -> handled
    Inside(inner:) -> taken_message(session:, now:, inner:)
  }
}

/// What the message in the client's wrapper does, by where the connection is:
/// the first must be 0x058F and only one is taken, 0x07E0 starts character
/// select, and any other whole message is logged as unhandled.
fn taken_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let is_hello_reply = inner.message_id == game_hello_reply.message_id
  case session.status {
    AwaitingHelloReply ->
      case is_hello_reply {
        True -> hello_replied(session:, now:, inner:)
        False ->
          end_for(
            session,
            "the first message of a game connection is 0x058F, not "
              <> client_connection.message_text(inner.message_id),
          )
      }
    InCharacterSelect(holder:, ..) ->
      case select_message(inner.message_id) {
        HelloReplyAgain -> end_for(session, "0x058F was sent a second time")
        SelectStart ->
          decoded_step(
            session:,
            now:,
            holder:,
            inner:,
            decode: character_select_start.decode,
            step: fn(_) { character_select.started(holder.account_id) },
          )
        CreateRequest -> create_requested(session:, now:, holder:, inner:)
        PlayRequest ->
          decoded_step(
            session:,
            now:,
            holder:,
            inner:,
            decode: play_character.decode,
            step: fn(request) {
              character_select.play_requested(
                account_id: holder.account_id,
                request:,
              )
            },
          )
        DeleteRequest ->
          decoded_step(
            session:,
            now:,
            holder:,
            inner:,
            decode: delete_character.decode,
            step: fn(request) {
              character_select.delete_requested(
                account_id: holder.account_id,
                request:,
              )
            },
          )
        RenameRequest ->
          decoded_step(
            session:,
            now:,
            holder:,
            inner:,
            decode: rename_character.decode,
            step: fn(request) {
              character_select.rename_requested(
                account_id: holder.account_id,
                request:,
              )
            },
          )
        NotTaken ->
          client_connection.unhandled(
            session:,
            link: session.link,
            account_id: account_id_of(session.status),
            server: "game",
            message_id: inner.message_id,
          )
      }
    TakingSessionKey | ClaimingSession(..) ->
      end_for(session, "a frame was taken while an ask was out")
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
      end_for(
        session,
        "the game hello reply 0x058F does not decode: "
          <> bit_stream.describe_decode(error:),
      )
    Ok(reply) -> {
      let assert Ok(key) = guid.from_wire(reply.session_key)
        as "the reply's session key is 16 bytes"
      case
        cipher.session_key(bytes: reply.session_key, base_key: cipher.base_key)
        |> result.try(cipher.new)
      {
        Error(error) ->
          end_for(
            session,
            "the session key makes no cipher: " <> describe_key_error(error),
          )
        Ok(keyed) ->
          ask(
            session: Session(..session, cipher: keyed, status: TakingSessionKey),
            now:,
            request: AskHandOff(Take(SessionKey(key:))),
            before: [],
          )
      }
    }
  }
}

fn describe_key_error(error: cipher.KeyError) -> String {
  case error {
    cipher.ZeroKey -> "the key is 0, which the client refuses"
    cipher.SessionKeyNotSixteenBytes(bytes:) ->
      "the session key is " <> int.to_string(bytes) <> " bytes, not 16"
  }
}

/// Which of the client's messages character select takes a message is.
type SelectMessage {
  /// A second 0x058F.
  HelloReplyAgain
  /// 0x07E0.
  SelectStart
  /// 0x025C, which carries a create request.
  CreateRequest
  /// 0x07DD, the request to play a character.
  PlayRequest
  /// 0x0352, the request to delete a character.
  DeleteRequest
  /// 0x0786, the request to rename a character.
  RenameRequest
  /// Any other message.
  NotTaken
}

fn select_message(message_id: Int) -> SelectMessage {
  case message_id {
    id if id == game_hello_reply.message_id -> HelloReplyAgain
    id if id == character_select_start.message_id -> SelectStart
    id if id == create_character_carrier.message_id -> CreateRequest
    id if id == play_character.message_id -> PlayRequest
    id if id == delete_character.message_id -> DeleteRequest
    id if id == rename_character.message_id -> RenameRequest
    _ -> NotTaken
  }
}

/// The client's 0x025C: the whole frame of a 0x025B create request, which
/// character select checks and asks the store to make.
fn create_requested(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case create_character_carrier.decode(inner.body) {
    Error(error) ->
      end_for(
        session,
        "0x025C does not decode: " <> bit_stream.describe_decode(error:),
      )
    Ok(carrier) ->
      case frame.parse(carrier.inner_frame) {
        Error(error) ->
          end_for(
            session,
            "0x025C holds no whole frame: " <> frame.describe(error),
          )
        Ok(whole) if whole.message_id != create_character.message_id ->
          end_for(
            session,
            "0x025C holds "
              <> client_connection.message_text(whole.message_id)
              <> ", not 0x025B",
          )
        Ok(whole) ->
          case create_character.decode(whole.body) {
            Error(error) ->
              end_for(
                session,
                "0x025B does not decode: " <> bit_stream.describe_decode(error:),
              )
            Ok(request) ->
              select_step(
                session:,
                now:,
                holder:,
                step: character_select.create_requested(
                  account_id: holder.account_id,
                  request:,
                  tables: session.settings.tables,
                  character_slots: session.settings.character_slots,
                ),
              )
          }
      }
  }
}

/// A message of the client's that character select takes: its body decoded,
/// and `step` gives character select's new state and effects for it. A body
/// the client's reader would refuse ends the connection.
fn decoded_step(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  inner inner: Frame,
  decode decode: fn(BitArray) -> Result(message, bit_stream.DecodeError),
  step step: fn(message) ->
    #(character_select.State, List(character_select.Effect)),
) -> client_connection.Handled(Session) {
  case decode(inner.body) {
    Error(error) ->
      end_for(
        session,
        client_connection.message_text(inner.message_id)
          <> " does not decode: "
          <> bit_stream.describe_decode(error:),
      )
    Ok(message) -> select_step(session:, now:, holder:, step: step(message))
  }
}

/// Character select's new state and what it decided, carried out.
fn select_step(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  step step: #(character_select.State, List(character_select.Effect)),
) -> client_connection.Handled(Session) {
  carry_out(
    session: Session(
      ..session,
      status: InCharacterSelect(holder:, select: step.0),
    ),
    now:,
    effects: step.1,
    written: [],
  )
}

/// Turns what character select decided into writes, and into its ask, which
/// ends the step with what was written before it; `written` are the writes so
/// far, the last first.
fn carry_out(
  session session: Session,
  now now: Now,
  effects effects: List(character_select.Effect),
  written written: List(Effect(Nil)),
) -> client_connection.Handled(Session) {
  case effects {
    [] -> Continue(session, list.reverse(written))
    [character_select.Send(frame:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        to_client(session, frame),
        ..written
      ])
    [character_select.Warn(text:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        log(session:, level: LogWarning, text:),
        ..written
      ])
    [character_select.Ask(request:), ..] ->
      ask(
        session:,
        now:,
        request: AskStore(store.Select(request)),
        before: list.reverse(written),
      )
  }
}

/// Makes the connection's next ask, after the effects `before`.
fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(Nil)),
) -> client_connection.Handled(Session) {
  let #(link, made) =
    client_connection.ask(
      session.link,
      now:,
      deadline_ms: session.settings.ask_deadline_ms,
      request:,
    )
  Asking(Session(..session, link:), before, made)
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case session.status {
    TakingSessionKey -> key_taken(session:, now:, outcome:)
    ClaimingSession(holder:, select:, retries:) ->
      claim_answered(session:, holder:, select:, retries:, outcome:)
    InCharacterSelect(holder:, select:) ->
      select_answered(session:, now:, holder:, select:, outcome:)
    AwaitingHelloReply -> end_for(session, "an answer came when no ask was out")
  }
}

/// The hand-off's answer to taking the session key: the holder, whose account
/// Sessions is asked to claim, or a client that is told it is disconnected.
fn key_taken(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      claim(session:, now:, holder:, select: character_select.new(), retries: 0)
    step.Answer(FromHandOff(hand_off.NoHolder)) ->
      told(
        session:,
        reason: AccountDisconnected,
        level: LogWarning,
        text: "the hand-off does not hold the session key",
      )
    step.Answer(FromHandOff(hand_off.Kept))
    | step.Answer(FromHandOff(hand_off.AlreadyHeld))
    | step.Answer(FromStore(..))
    | step.Answer(FromSessions(..)) ->
      told(
        session:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a Take gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the hand-off", outcome:),
      )
    step.StoppedWaiting -> stopped(session)
  }
}

/// Opens a watch on Sessions and asks it to make this connection the account's
/// session; `select` is the character select the client is in once it
/// answers. The watch is opened with every claim, so a restarted Sessions is
/// watched again.
fn claim(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  select select: character_select.State,
  retries retries: Int,
) -> client_connection.Handled(Session) {
  let watches = session.watches + 1
  ask(
    session: Session(
      ..session,
      watches:,
      status: ClaimingSession(holder:, select:, retries:),
    ),
    now:,
    request: AskSessions(sessions.Claim(
      account: holder.account_id,
      connection: session.link.connection,
    )),
    before: [Watch(watch: WatchId(watches), target: Sessions)],
  )
}

/// Sessions' answer to the claim: `Claimed` puts the client in character
/// select, where it was, and the frames held are taken. Sessions not running
/// is waited out up to `claim_retries` times, with the watch dropped; any
/// other failure of the ask tells the client the server failed, as the store's
/// do.
fn claim_answered(
  session session: Session,
  holder holder: Holder,
  select select: character_select.State,
  retries retries: Int,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromSessions(sessions.Claimed)) ->
      Continue(
        Session(..session, status: InCharacterSelect(holder:, select:)),
        [],
      )
    step.Answer(FromSessions(sessions.TakenOver))
    | step.Answer(FromStore(..))
    | step.Answer(FromHandOff(..)) ->
      told(
        session:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a claim gets",
      )
    step.NotRunning if retries < claim_retries ->
      Waiting(
        Session(
          ..session,
          status: ClaimingSession(holder:, select:, retries: retries + 1),
        ),
        [
          Unwatch(watch: WatchId(session.watches)),
          StartTimer(timer: claim_timer, after_ms: claim_wait_ms),
        ],
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "Sessions", outcome:),
      )
    step.StoppedWaiting -> stopped(session)
  }
}

/// What Sessions sent the connection: `TakenOver` tells the client its account
/// was disconnected (0x036A reason 19) and ends the connection. `Claimed` is
/// an answer, never sent, and is a bug, as is a takeover before the connection
/// has claimed.
fn sessions_sent(
  session session: Session,
  message message: sessions.Outgoing,
) -> client_connection.Handled(Session) {
  case message, session.status {
    sessions.TakenOver, InCharacterSelect(..)
    | sessions.TakenOver, ClaimingSession(..)
    ->
      told(
        session:,
        reason: AccountDisconnected,
        level: LogInfo,
        text: "a newer login of the account took the session over",
      )
    sessions.TakenOver, AwaitingHelloReply
    | sessions.TakenOver, TakingSessionKey
    -> end_for(session, "Sessions sent a takeover before the claim")
    sessions.Claimed, _ ->
      end_for(session, "Sessions sent an answer as a message")
  }
}

/// The end of the watch on Sessions: the connection waits on the claim timer,
/// then claims its account again from where it is. A watch this rule did not
/// open, or one that ends while the connection is not in character select, is
/// a bug.
fn sessions_ended(
  session session: Session,
  watch watch: WatchId,
) -> client_connection.Handled(Session) {
  let open = WatchId(session.watches)
  case session.status {
    InCharacterSelect(holder:, select:) if watch == open ->
      Waiting(
        Session(
          ..session,
          status: ClaimingSession(holder:, select:, retries: 0),
        ),
        [StartTimer(timer: claim_timer, after_ms: claim_wait_ms)],
      )
    InCharacterSelect(..)
    | ClaimingSession(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      end_for(session, "a watch the rule did not open ended")
  }
}

/// The claim timer fired: the connection claims again. A timer the rule did
/// not start, or one that fires when the connection is not waiting on it, is
/// a bug.
fn claim_wait_over(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case session.status {
    ClaimingSession(holder:, select:, retries:) if timer == claim_timer ->
      claim(session:, now:, holder:, select:, retries:)
    ClaimingSession(..)
    | InCharacterSelect(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      end_for(session, "a timer the rule did not start fired")
  }
}

/// The store's answer to character select's ask: the failures every store ask
/// shares tell the client the server failed; any other answer is character
/// select's to take. A takeover that waits behind a failing ask is never taken
/// (the connection ends with this failure's text).
fn select_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  select select: character_select.State,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(store.Unavailable)) ->
      told(
        session:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the store is unavailable",
      )
    step.Answer(FromStore(store.ForSelect(answer))) ->
      select_taken(session:, now:, holder:, taken: case answer {
        store.Listed(characters:) ->
          character_select.listed(
            select,
            characters:,
            filetime: now.filetime,
            realm_id: session.settings.realm_id,
            max_characters: session.settings.max_characters,
            tables: session.settings.tables,
          )
        store.Created(answer:) -> character_select.created(select, answer)
        store.Deleted(answer:) -> character_select.deleted(select, answer)
        store.Renamed(answer:) -> character_select.renamed(select, answer)
      })
    step.Answer(FromStore(store.ForLogin(..))) ->
      select_taken(session:, now:, holder:, taken: Error(Nil))
    step.Answer(FromHandOff(..)) ->
      told(
        session:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a store ask gets",
      )
    step.Answer(FromSessions(..)) ->
      told(
        session:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a store ask gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the store", outcome:),
      )
    step.StoppedWaiting -> stopped(session)
  }
}

/// What character select made of the store's answer: its new state and
/// effects carried out, or, for an answer it has no ask for, the client told
/// the server failed.
fn select_taken(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  taken taken: Result(
    #(character_select.State, List(character_select.Effect)),
    Nil,
  ),
) -> client_connection.Handled(Session) {
  case taken {
    Ok(step) -> select_step(session:, now:, holder:, step:)
    Error(Nil) ->
      told(
        session:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the store's answer is none character select asked for",
      )
  }
}

/// The connection ends after 0x036A with the reason, and a log line saying
/// why.
fn told(
  session session: Session,
  reason reason: DisconnectReason,
  level level: step.LogLevel,
  text text: String,
) -> client_connection.Handled(Session) {
  End(session, [
    log(session:, level:, text:),
    notice(session:, reason:),
    Stop,
  ])
}

/// The server is stopping while an ask is out: the client is told, with no
/// log line, since a stop is no failure.
fn stopped(session: Session) -> client_connection.Handled(Session) {
  End(session, list.append(server_stopping(session), [Stop]))
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
fn end_for(
  session: Session,
  text: String,
) -> client_connection.Handled(Session) {
  client_connection.end_for(
    session:,
    link: session.link,
    account_id: account_id_of(session.status),
    text:,
  )
}

// ---- log lines ----

fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(Nil) {
  client_connection.log(
    link: session.link,
    account_id: account_id_of(session.status),
    level:,
    text:,
  )
}

/// The id of the account the connection is for, once the hand-off has named
/// the holder.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    InCharacterSelect(
      holder: hand_off.Holder(account_id: store.AccountId(id), ..),
      ..,
    )
    | ClaimingSession(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      ) -> Some(id)
    AwaitingHelloReply | TakingSessionKey -> None
  }
}
