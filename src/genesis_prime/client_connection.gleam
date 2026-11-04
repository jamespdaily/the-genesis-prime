//// What every client connection's rule asks other processes, what comes back,
//// what other processes send it, and what every such rule does alike: the STS rule
//// (genesis_prime/login/sts_connection), the auth rule
//// (genesis_prime/login/auth_connection) and the game rule
//// (genesis_prime/game/connection). The server's directory sends each request
//// to its process and wraps each answer (genesis_prime/server).
////
//// Each rule keeps a `Link`: who the connection is for their log lines, the
//// seed's random source and the number of their last ask. Each sorts an input
//// with `hear`, which decides what the client closing, a failed socket and an
//// input it never asked for do, and ends the connection when the
//// server stops after the effects the rule gives it.
//// Each takes a request or frame at a time, through a `Flow` that `drive`
//// runs, and says what it decided with `Handled`, which `settle` carries out.
//// Each holds at most `held_limit` bytes it has not taken (`hold`) and counts
//// each whole request or frame the client sends against a rate (`charge`),
//// and ends the connection past either, in its rule, so a recording replays
//// to the same end.
//// The rules that take the client's wrapper (the auth rule and the game rule)
//// open each whole frame with `open`, and write each message with `wrapped`.

import genesis_prime/account_session
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{type Wrapper, ClientWrapper}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/network_message
import genesis_prime/game/chat_tell.{type Tell as ChatTell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{type Answered, type Tell as StrikeTell}
import genesis_prime/hand_off
import genesis_prime/message/bit_stream
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/random.{type Random}
import genesis_prime/step.{
  type About, type ConnectionEffect, type ConnectionEvent, type ConnectionId,
  type ConnectionStep, type Effect, type Event, type Now, type Outcome,
  type Peer, About, Accepted, Answered, AskId, Effects, EffectsThenAsk, Log,
  LogError, LogLine, LogWarning, OwnEffect, OwnEvent, PeerClosed, ReadFailed,
  Stop, Stopping, TimerFired, Woken, Write, WriteFailed,
}
import genesis_prime/store
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// What a connection rule asks.
pub type Request {
  AskStore(request: store.Request)
  AskHandOff(message: hand_off.Message)
  AskSessions(message: account_session.Message)
  /// Ask the map, which Maps starts when it is not running
  /// (genesis_prime/world_map/registry).
  AskMap(map: MapId, message: map.Message)
  /// Ask the run of the map with this incarnation, which Maps never starts: a
  /// map that is not running, or runs as another incarnation, is not running
  /// for this ask (genesis_prime/world_map/registry).
  AskMapRun(map: MapId, incarnation: Int, message: map.Message)
  /// What a `Tell` effect sends the run of a map (genesis_prime/step): that the
  /// player of `connection` moved to `place` (genesis_prime/world_map/map
  /// `Moved`), for the map to decide who sees whom. A tell of a join or a leave
  /// cannot be built. It is never asked: the directory answers an ask of it as
  /// no process running.
  TellMoved(connection: ConnectionId, place: Place)
  /// What a `Tell` effect sends the connection of a player who sees this one
  /// (genesis_prime/step `Connection`): news of this player's unit, which that
  /// connection writes as 0x262, 0x638 or 0x355 when its client can take it.
  /// Never asked, and never told to a map.
  TellPeer(news: PeerNews)
  /// What a `Tell` effect sends the connection of another player, or every
  /// connection of a zone channel, or the connection that holds a character's
  /// name (genesis_prime/step `Connection`, `ZoneChannel`, `CharacterNamed`): a
  /// chat line or a whisper's reply (genesis_prime/game/chat_tell). Never asked,
  /// and never told to a map.
  TellChat(tell: ChatTell)
  /// What a `Tell` effect sends a creature (genesis_prime/step `Creature`): the
  /// strike of a cast's go, which the creature's owner process decides
  /// (genesis_prime/world_map/creature_life). Told through the creature registry
  /// with no watch, and never asked.
  TellStrike(tell: StrikeTell)
}

/// News of one unit from its owner, a player's connection or a creature's
/// process, to the connection of a player who sees it: the run of the map the
/// owner is in (`map` and `incarnation`, as its connection watches it), the
/// owner's unit in that run, and what happened to it. A viewer that is in another run of the map, or another map, drops it:
/// the unit id there may name another unit.
pub type PeerNews {
  PeerNews(map: MapId, incarnation: Int, unit_id: Int, news: News)
}

/// What a unit's owner tells the connections that see its unit, which they write
/// as the message the client creates, moves and removes a unit with.
pub type News {
  /// The unit as the client creates it, at the owner's current place and stamped
  /// from the map's clock: 0x262 (opcode.0x262).
  Appeared(unit: UnitCreatePlayer)
  /// A creature as the client creates it, at its spawn and stamped from the
  /// map's clock: 0x262 of type 0 (opcode.0x262.creature). Sent by the
  /// creature's own process (genesis_prime/world_map/creature), which owns the
  /// unit.
  CreatureAppeared(unit: UnitCreateCreature)
  /// The unit moved: the map's server time at the move (the map's clock,
  /// `world_map/map.server_time`) and at most 31 of its relayed commands in the
  /// order sent, since 0x638's count is 5 bits (opcode.0x638).
  Moving(server_time_ms: Int, commands: List(RelayedMovement))
  /// The unit is gone from the viewer's sight, or its owner camped: 0x355
  /// (opcode.0x355).
  Removed
  /// The unit started a cast: 0x7ff (opcode.0x7ff), written when the viewer's
  /// client shows the unit, and the cast is then one the viewer knows.
  CastStarted(start: SpellStarted)
  /// A cast of the unit goes off: 0x7f4 (opcode.0x7f4), written for a cast the
  /// viewer wrote the start of.
  CastWent(go: SpellGo)
  /// A cast of the unit ends: 0x7fe (opcode.0x7fe), written for a cast the viewer
  /// wrote the start of, which the viewer then forgets.
  CastFinished(cast_id: Int)
  /// The unit's health after a landed hit, from the creature that owns it: 0x937
  /// (opcode.0x937), written when the viewer's client shows the unit, whatever
  /// the viewer's own casts.
  Health(health: Int, dead: Bool)
  /// The unit died: 0x88c with the dead bit (opcode.0x88c), written when the
  /// viewer's client shows the unit.
  Died
}

/// The most commands one 0x638 holds: its count is 5 bits (opcode.0x638).
const most_commands_in_a_message = 31

/// The news a move is sent as: its `commands` in order, at most 31 to a message,
/// and none for no command.
pub fn peer_moves(
  map map: MapId,
  incarnation incarnation: Int,
  unit_id unit_id: Int,
  server_time_ms server_time_ms: Int,
  commands commands: List(RelayedMovement),
) -> List(PeerNews) {
  list.sized_chunk(commands, most_commands_in_a_message)
  |> list.map(fn(chunk) {
    PeerNews(
      map:,
      incarnation:,
      unit_id:,
      news: Moving(server_time_ms:, commands: chunk),
    )
  })
}

/// What comes back from an ask, by the process asked.
pub type Answer {
  FromStore(answer: store.Answer)
  FromHandOff(answer: hand_off.Answer)
  FromSessions(answer: account_session.Outgoing)
  FromMap(answer: map.Outgoing)
}

/// What another process sends a connection rule, by the process that sent
/// it. Only the game rule is sent anything; the login's rules take `Nil`.
pub type Message {
  SentBySessions(message: account_session.Outgoing)
  /// What a map sends the connection of a player in it without waiting: who
  /// sees this connection's player (`Watched`, `Unwatched`), and a unit whose
  /// owner's connection ended (`Gone`). A map's answers (`Joined`, `Left`) come
  /// as an ask's outcome, never as this.
  SentByMap(message: map.Outgoing)
  /// What the connection of another player sends it without waiting: news of
  /// that player's unit, written while this player is in the world
  /// (genesis_prime/game/connection).
  SentByPeer(news: PeerNews)
  /// What the connection of another player sent it without waiting: a chat line
  /// or a whisper's reply, written while this player is in the world
  /// (genesis_prime/game/chat).
  SentByChat(tell: ChatTell)
  /// What a creature this connection struck answers, without waiting: the
  /// answer to a strike its caster told, which the strike rule takes into the round
  /// it belongs to (genesis_prime/game/strike).
  SentByTarget(answered: Answered)
}

/// What an accepted connection keeps beside its rule's own state: who
/// it is for log lines, the seed's random source, the number of the last
/// ask it made, so each ask has an id of its own, and what the client may
/// still send before the rate refuses it. Only this module builds or changes
/// one (`link`, `charge`, `draw`, `ask`), so an ask's id is never reused and
/// the rate's bucket is never swapped for a larger one.
pub opaque type Link {
  Link(
    connection: ConnectionId,
    peer: Peer,
    random: Random,
    asks: Int,
    allowance: Allowance,
  )
}

/// How fast a client may send, as a bucket of whole requests or frames. A
/// client that has sent nothing for a while may send `burst` at once, and the
/// bucket fills by `per_second` each second, so a client that sends at exactly
/// `per_second` is never refused. Both are the server's choice, in each rule's
/// settings, and `bucket` is the only way
/// to make one, so none is a value that refuses every client or one that
/// refuses a client for the server's own wait.
pub opaque type Bucket {
  Bucket(burst: Int, per_second: Int)
}

/// Why a bucket was refused.
pub type BucketRefused {
  /// A bucket must hold at least one request or frame.
  BurstBelowOne(burst: Int)
  /// A bucket must fill by at least one a second.
  PerSecondBelowOne(per_second: Int)
  /// Frames that wait for an ask are counted only when the ask is answered, so
  /// a client that sends at `per_second` through the longest wait the rule
  /// has sends `needed`, and a `burst` below that closes a client that kept
  /// to its rate.
  BurstBelowWait(burst: Int, needed: Int)
}

/// A bucket of `burst` and `per_second` for a rule whose longest wait with the
/// client's frames untaken is `longest_wait_ms`, or why it is refused. The wait
/// is the rule's own (its asks' deadlines and timers, which its module states).
pub fn bucket(
  burst burst: Int,
  per_second per_second: Int,
  longest_wait_ms longest_wait_ms: Int,
) -> Result(Bucket, BucketRefused) {
  let needed = { per_second * longest_wait_ms + 999 } / 1000
  use <- bool.guard(when: burst < 1, return: Error(BurstBelowOne(burst:)))
  use <- bool.guard(
    when: per_second < 1,
    return: Error(PerSecondBelowOne(per_second:)),
  )
  use <- bool.guard(
    when: burst < needed,
    return: Error(BurstBelowWait(burst:, needed:)),
  )
  Ok(Bucket(burst:, per_second:))
}

/// A sentence that says why a bucket was refused, for the log.
pub fn describe_refusal(refused refused: BucketRefused) -> String {
  case refused {
    BurstBelowOne(burst:) ->
      "a rate bucket of " <> int.to_string(burst) <> " holds less than one"
    PerSecondBelowOne(per_second:) ->
      "a rate bucket that fills by "
      <> int.to_string(per_second)
      <> " a second never fills"
    BurstBelowWait(burst:, needed:) ->
      "a rate bucket of "
      <> int.to_string(burst)
      <> " holds less than the "
      <> int.to_string(needed)
      <> " frames a client sends at the rate while its frames wait for an ask"
  }
}

/// The most the bucket holds.
pub fn burst(bucket bucket: Bucket) -> Int {
  bucket.burst
}

/// How many the bucket fills by each second.
pub fn per_second(bucket bucket: Bucket) -> Int {
  bucket.per_second
}

/// What the client may still send: its bucket, and what the bucket held at the
/// monotonic time of the last whole request or frame, in thousandths of one,
/// so a refill of `per_second` a second is whole thousandths each millisecond
/// and no time is lost to rounding.
pub opaque type Allowance {
  Allowance(bucket: Bucket, thousandths: Int, as_of_ms: Int)
}

/// The link of a connection just accepted at `now`, with the seed's random
/// source and a full bucket.
pub fn link(
  connection connection: ConnectionId,
  peer peer: Peer,
  seed seed: BitArray,
  bucket bucket: Bucket,
  now now: Now,
) -> Link {
  Link(
    connection:,
    peer:,
    random: random.new(seed:),
    asks: 0,
    allowance: Allowance(
      bucket:,
      thousandths: bucket.burst * 1000,
      as_of_ms: now.monotonic_ms,
    ),
  )
}

/// Counts one whole request or frame the client sent, at the time of the
/// input that takes it, against the connection's rate: the session with the
/// link that has paid for it (`relinked`), or the end of the connection when
/// the bucket holds less than one, with a warning and nothing written to a
/// client that sends faster than any client does.
pub fn charge(
  session session: session,
  link link: Link,
  now now: Now,
  about about: About,
  relinked relinked: fn(Link) -> session,
) -> Result(session, Handled(session)) {
  let allowance = link.allowance
  let capacity = allowance.bucket.burst * 1000
  let refilled =
    int.min(
      capacity,
      allowance.thousandths
        + int.max(0, now.monotonic_ms - allowance.as_of_ms)
        * allowance.bucket.per_second,
    )
  case refilled >= 1000 {
    True ->
      Ok(relinked(
        Link(
          ..link,
          allowance: Allowance(
            ..allowance,
            thousandths: refilled - 1000,
            as_of_ms: int.max(allowance.as_of_ms, now.monotonic_ms),
          ),
        ),
      ))
    False ->
      Error(
        Done(session, [
          log(
            about:,
            level: LogWarning,
            text: "the client sent faster than the rate allows",
          ),
          Stop,
        ]),
      )
  }
}

/// The most bytes a connection holds that its rule has not taken as requests
/// or frames: one whole frame at the client's size limit, 131,070
/// (MessageSizeLimit 0x140335ec0), and one read of the socket
/// (`genesis_prime/connection/frame.read_limit`). A server choice. Bytes wait
/// while an ask is out, and a client may send as many as the network carries
/// in that time.
fn held_limit() -> Int {
  frame.size_limit + frame.read_limit
}

/// The bytes a rule holds after a read of `bytes` is added to the `held` it
/// had, or the end of the connection when that is more than `held_limit`,
/// with an error and nothing written to a client that is no client.
pub fn hold(
  session session: session,
  held held: BitArray,
  bytes bytes: BitArray,
  about about: About,
) -> Result(BitArray, Handled(session)) {
  use <- bool.guard(
    when: bit_array.byte_size(held) + bit_array.byte_size(bytes) > held_limit(),
    return: Error(end_for(
      session:,
      about:,
      text: "the client sent more bytes than the server holds for it",
    )),
  )
  Ok(<<held:bits, bytes:bits>>)
}

/// The id of the connection the link is for.
pub fn connection(link link: Link) -> ConnectionId {
  link.connection
}

/// The next `count` random bytes of the connection's seed.
pub fn draw(link link: Link, count count: Int) -> #(Link, BitArray) {
  let #(random, bytes) = random.bytes(link.random, count)
  #(Link(..link, random:), bytes)
}

/// The next ask of the connection: its id, the request and a deadline
/// `deadline_ms` after the time of the input.
pub fn ask(
  link link: Link,
  now now: Now,
  deadline_ms deadline_ms: Int,
  request request: Request,
) -> #(Link, step.Ask(Request)) {
  let asks = link.asks + 1
  #(
    Link(..link, asks:),
    step.Ask(
      ask: AskId(asks),
      request:,
      deadline_ms: now.monotonic_ms + deadline_ms,
    ),
  )
}

/// What a log line of the connection is about, with the account once the
/// rule knows it.
pub fn about(link link: Link, account_id account_id: Option(Int)) -> About {
  About(
    ..step.no_one,
    connection: Some(link.connection),
    peer: Some(link.peer),
    account_id:,
  )
}

/// A log line of the connection, about `about`.
pub fn log(
  about about: About,
  level level: step.LogLevel,
  text text: String,
) -> Effect(ConnectionEffect(Request)) {
  Log(LogLine(level:, text:, about:))
}

/// A whole frame of a message the rule does not take: logged as unhandled at
/// `level`, and the connection goes on. `server` names whose rule it is, as
/// the line says ("auth", "game").
pub fn unhandled(
  session session: session,
  about about: About,
  server server: String,
  message_id message_id: Int,
  level level: step.LogLevel,
) -> Handled(session) {
  Continue(session, [
    Log(LogLine(
      level:,
      text: "unhandled " <> server <> " message " <> message_text(message_id:),
      about: About(..about, message: Some(#("unhandled", message_id))),
    )),
  ])
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
pub fn end_for(
  session session: session,
  about about: About,
  text text: String,
) -> Handled(session) {
  Done(session, [log(about:, level: LogError, text:), Stop])
}

/// The step of a rule that took bytes or an answer before the connection was
/// accepted: an error log line and the end of the connection. `rule` names
/// whose rule it is, as the line says ("auth", "game", "STS").
pub fn before_accepted(rule rule: String) -> ConnectionStep(Request) {
  Effects([
    Log(LogLine(
      level: LogError,
      text: "the "
        <> rule
        <> " rule took an input before the connection was accepted",
      about: step.no_one,
    )),
    Stop,
  ])
}

/// The step of a rule that was accepted a second time: an error log line and
/// the end of the connection. `rule` names whose rule it is, as the line says.
pub fn accepted_again(
  about about: About,
  rule rule: String,
) -> ConnectionStep(Request) {
  Effects([
    log(
      about:,
      level: LogError,
      text: "the " <> rule <> " rule was accepted a second time",
    ),
    Stop,
  ])
}

/// A message id as the log writes it: four hex digits, as in `0x0244`.
pub fn message_text(message_id message_id: Int) -> String {
  "0x" <> string.pad_start(string.uppercase(int.to_base16(message_id)), 4, "0")
}

/// A body the client's own reader would refuse, as the message it was read for
/// and why it was refused: the refusal every feature that decodes a client
/// message has.
pub type Undecoded {
  Undecoded(message_id: Int, error: bit_stream.DecodeError)
}

/// A decode that failed, as the refusal for the message it was read for.
pub fn decoded(
  result result: Result(message, bit_stream.DecodeError),
  message_id message_id: Int,
) -> Result(message, Undecoded) {
  result.map_error(result, fn(error) { Undecoded(message_id:, error:) })
}

/// The sentence a body the client's own reader would refuse is logged with.
pub fn describe_undecoded(undecoded undecoded: Undecoded) -> String {
  message_text(message_id: undecoded.message_id)
  <> " does not decode: "
  <> bit_stream.describe_decode(error: undecoded.error)
}

/// What an input is to a connection rule.
pub type Heard {
  /// The connection was accepted.
  Connect(connection: ConnectionId, peer: Peer, seed: BitArray)
  /// Bytes arrived.
  Bytes(bytes: BitArray)
  /// The outcome of the ask the rule made.
  Outcome(outcome: Outcome(Answer))
  /// An input every rule takes the same way, or none a connection is given:
  /// the step to take, with the state unchanged.
  Otherwise(step: ConnectionStep(Request))
}

/// Sorts an input: what the client closing and a failed socket do is the same
/// in every rule, so it is decided here (a socket that fails as closed is the
/// client's close and ends the connection with no log line; any other failure
/// is a warning); `about` says who a log
/// line is about. The server stopping ends the connection after the effects
/// `stopping` gives, which the rule writes first: none for a connection with
/// no one to tell, a notice for one whose client waits for the server's next
/// message. `stopping` is called only when the server stops. `Woken`,
/// `WatchEnded` and `TimerFired` come only for a watch or timer the rule
/// started, and only the game rule starts either; it takes them before it calls
/// `hear`. To every other rule they are inputs it never asked for.
pub fn hear(
  event event: Event(ConnectionEvent(message, Answer)),
  about about: About,
  stopping stopping: fn() -> List(Effect(ConnectionEffect(Request))),
) -> Heard {
  let ends = fn(level, text) {
    Otherwise(Effects([Log(LogLine(level:, text:, about:)), Stop]))
  }
  case event {
    OwnEvent(Accepted(connection:, peer:, seed:)) ->
      Connect(connection:, peer:, seed:)
    OwnEvent(step.Read(bytes:)) -> Bytes(bytes:)
    OwnEvent(Answered(outcome:, ..)) -> Outcome(outcome:)
    OwnEvent(PeerClosed)
    | OwnEvent(ReadFailed(failure: step.Closed))
    | OwnEvent(WriteFailed(failure: step.Closed)) -> Otherwise(Effects([Stop]))
    Stopping(..) -> Otherwise(Effects(list.append(stopping(), [Stop])))
    OwnEvent(ReadFailed(failure:)) | OwnEvent(WriteFailed(failure:)) ->
      ends(LogWarning, socket_failed_text(failure:))
    OwnEvent(Woken(..)) | step.WatchEnded(..) | OwnEvent(TimerFired(..)) ->
      ends(LogError, "a connection rule took an input it never asked for")
  }
}

/// The sentence a failed socket is logged with.
pub fn socket_failed_text(failure failure: step.SocketFailure) -> String {
  "the socket failed (" <> step.describe_socket_failure(failure) <> ")"
}

/// What taking one request or frame, or one answer, decided.
pub type Handled(session) {
  /// Go on to the next request or frame in the bytes.
  Continue(session: session, effects: List(Effect(ConnectionEffect(Request))))
  /// Carry out the effects, then ask; what follows in the bytes waits.
  Asking(
    session: session,
    effects: List(Effect(ConnectionEffect(Request))),
    ask: step.Ask(Request),
  )
  /// Carry out the effects, then take no frame until another input. The
  /// effects of a rule that ends the connection hold `Stop`; one that waits for
  /// a timer or a process holds none.
  Done(session: session, effects: List(Effect(ConnectionEffect(Request))))
}

/// How a rule takes what the client sent: the callbacks `drive` and `settle`
/// run it with, which a rule makes for each input from the time of the
/// input. `item` is one request or frame the bytes hold and `error` what the
/// bytes are when they are none.
pub type Flow(session, item, error, state) {
  Flow(
    /// The bytes read and not yet taken.
    pending: fn(session) -> BitArray,
    /// The first whole item in the bytes and the bytes after it, `None` when
    /// its end has not arrived.
    take: fn(BitArray) -> Result(Option(#(item, BitArray)), error),
    /// What one item does, given the bytes after it as `rest`, which it keeps
    /// as the session's pending bytes.
    taking: fn(session, item, BitArray) -> Handled(session),
    /// What bytes that are no item do: the rule ends the connection.
    refused: fn(session, error) -> Handled(session),
    /// Counts one whole item against the session's rate: the session once it
    /// has paid, or what the rule does when the rate is past (`charge`).
    charged: fn(session) -> Result(session, Handled(session)),
    /// The rule's state for a session.
    connected: fn(session) -> state,
  )
}

/// Takes the whole items in a session's pending bytes in order, until one
/// asks, the connection ends or the bytes hold no more; `refused` ends the
/// connection for bytes that are no item, after the whole items before them.
/// `carried` are the effects already decided, the last first.
pub fn drive(
  session session: session,
  flow flow: Flow(session, item, error, state),
  carried carried: List(Effect(ConnectionEffect(Request))),
) -> #(state, ConnectionStep(Request)) {
  case flow.take(flow.pending(session)) {
    Error(error) ->
      settle(handled: flow.refused(session, error), flow:, carried:)
    Ok(None) -> #(flow.connected(session), Effects(list.reverse(carried)))
    Ok(Some(#(first, rest))) ->
      case flow.charged(session) {
        Ok(session) ->
          settle(handled: flow.taking(session, first, rest), flow:, carried:)
        Error(handled) -> settle(handled:, flow:, carried:)
      }
  }
}

/// Carries out what was decided after the effects already `carried`, the last
/// first: on `Continue` `drive` takes the next item, on `Asking` the step ends
/// in the ask, on `Done` no frame is taken after the effects. The effects leave in order, reversed once
/// here.
pub fn settle(
  handled handled: Handled(session),
  flow flow: Flow(session, item, error, state),
  carried carried: List(Effect(ConnectionEffect(Request))),
) -> #(state, ConnectionStep(Request)) {
  case handled {
    Continue(session:, effects:) ->
      drive(session:, flow:, carried: list.fold(effects, carried, list.prepend))
    Asking(session:, effects:, ask:) -> #(
      flow.connected(session),
      EffectsThenAsk(in_order(carried:, then: effects), ask),
    )
    Done(session:, effects:) -> #(
      flow.connected(session),
      Effects(in_order(carried:, then: effects)),
    )
  }
}

fn in_order(
  carried carried: List(Effect(ConnectionEffect(Request))),
  then effects: List(Effect(ConnectionEffect(Request))),
) -> List(Effect(ConnectionEffect(Request))) {
  list.append(list.reverse(carried), effects)
}

/// Why an ask had no answer, for the log: `who` is the process asked.
pub fn without_answer(
  who who: String,
  outcome outcome: Outcome(Answer),
) -> String {
  case outcome {
    step.NotRunning -> who <> " was not running"
    step.NoAnswerInTime -> who <> " gave no answer in time"
    step.EndedBeforeAnswer -> who <> " ended before it answered"
    step.StoppedWaiting -> "the server began stopping"
    step.Answer(..) -> who <> " gave an answer"
  }
}

/// A message as the bytes to write: its frame in `wrapper`, under `cipher`.
pub fn wrapped(
  wrapper wrapper: Wrapper,
  inner inner: Frame,
  cipher cipher: Cipher,
) -> BitArray {
  let assert Ok(bytes) = encrypted_frame.wrap(wrapper, inner, cipher)
    as "a message the rule writes is far below the size limit"
  bytes
}

/// The ids of the messages every connection that takes the client's wrapper
/// handles in `open`: the network layer's ping, pong and close notice
/// (genesis_prime/connection/network_message) and the client's wrapper 0x0244
/// that holds every other message. The coverage measure counts them as handled.
pub fn shared_message_ids() -> List(Int) {
  [
    encrypted_frame.message_id(ClientWrapper),
    ..network_message.taken_message_ids()
  ]
}

/// What a whole frame from the client is to a rule that takes the client's
/// wrapper.
pub type Opened(session) {
  /// The network layer's message, or a frame of a message the rule does not
  /// take: decided.
  Settled(handled: Handled(session))
  /// The frame inside the client's wrapper, for the rule to take.
  Inside(inner: Frame)
  /// A frame the client's reader would refuse: the rule ends the connection,
  /// with `text` as the reason it logs. The rule ends it, since only the rule
  /// knows what an end must do first (the game rule saves the player's place).
  Broken(text: String)
}

/// Sorts a whole frame from the client: the network layer's messages first
/// (genesis_prime/connection/network_message), answered before any wrapper is
/// looked at (a ping is answered, a pong or close notice accepted, a network
/// message that does not decode ends the connection); then the client's
/// wrapper, opened with `cipher` (genesis_prime/connection/encrypted_frame),
/// whose inner frame is given to the rule; and a frame of a message the rule
/// does not take, logged as unhandled by `server`. A wrapper or inner frame
/// that is none the client's reader accepts is `Broken`.
pub fn open(
  session session: session,
  about about: About,
  server server: String,
  frame whole: Frame,
  cipher cipher: Cipher,
) -> Opened(session) {
  let unknown = fn(message_id) {
    Settled(unhandled(session:, about:, server:, message_id:, level: LogWarning))
  }
  case network_message.handle(frame: whole) {
    network_message.Answer(bytes:) ->
      Settled(Continue(session, [OwnEffect(Write(bytes))]))
    network_message.Accepted -> Settled(Continue(session, []))
    network_message.Malformed(message_id:, ..) ->
      Broken(
        text: "a network message "
        <> message_text(message_id:)
        <> " does not decode",
      )
    network_message.NotNetwork ->
      case whole.message_id == encrypted_frame.message_id(ClientWrapper) {
        False -> unknown(whole.message_id)
        True ->
          case encrypted_frame.unwrap(whole, cipher) {
            Ok(inner) -> Inside(inner:)
            Error(encrypted_frame.NotAWrapper(message_id:)) ->
              unknown(message_id)
            Error(encrypted_frame.BadFrame(error)) ->
              Broken(
                text: "the wrapped frame is no frame: " <> frame.describe(error),
              )
          }
      }
  }
}
