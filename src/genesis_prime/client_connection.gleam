//// What every client connection's rule asks other processes, what comes back,
//// what other processes send it, and what every such rule does alike: the STS rule
//// (genesis_prime/login/sts_connection), the auth rule
//// (genesis_prime/login/auth_connection) and the game rule
//// (genesis_prime/game/connection). The server's directory sends each request
//// to its process and wraps each answer (genesis_prime/server).
////
//// Each rule keeps a `Link`: who the connection is for their log lines, the
//// seed's random source and the number of their last ask. Each sorts an input
//// with `hear`, which decides what the client closing, a failed socket, a late
//// answer and an input a connection is never given do, and ends the
//// connection when the server stops after the effects the rule gives it.
//// Each takes a request or frame at a time, through a `Flow` that `drive`
//// runs, and says what it decided with `Handled`, which `settle` carries out.
//// The rules that take the client's wrapper (the auth rule and the game rule)
//// open each whole frame with `open`, and write each message with `wrapped`.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{type Wrapper, ClientWrapper}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/network_message
import genesis_prime/hand_off
import genesis_prime/random.{type Random}
import genesis_prime/sessions
import genesis_prime/step.{
  type About, type ConnectionId, type Effect, type Event, type Now, type Outcome,
  type Peer, type Step, About, Accepted, Answered, AnsweredLate, AskId, Asked,
  Effects, EffectsThenAsk, Log, LogError, LogLine, LogWarning, PeerClosed,
  ReadFailed, Socket, Started, Stop, Stopping, TimerFired, Woken, Write,
  WriteFailed,
}
import genesis_prime/store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// What a connection rule asks.
pub type Request {
  AskStore(request: store.Request)
  AskHandOff(message: hand_off.Message)
  AskSessions(message: sessions.Message)
}

/// What comes back from an ask, by the process asked.
pub type Answer {
  FromStore(answer: store.Answer)
  FromHandOff(answer: hand_off.Answer)
  FromSessions(answer: sessions.Outgoing)
}

/// What another process sends a connection rule, by the process that sent
/// it. Only the game rule is sent anything; the login's rules take `Nil`.
pub type Message {
  SentBySessions(message: sessions.Outgoing)
}

/// What an accepted connection keeps beside its rule's own state: who
/// it is for log lines, the seed's random source, and the number of the last
/// ask it made, so each ask has an id of its own.
pub type Link {
  Link(connection: ConnectionId, peer: Peer, random: Random, asks: Int)
}

/// The link of a connection just accepted, with the seed's random source.
pub fn link(
  connection connection: ConnectionId,
  peer peer: Peer,
  seed seed: BitArray,
) -> Link {
  Link(connection:, peer:, random: random.new(seed:), asks: 0)
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

/// A log line of the connection.
pub fn log(
  link link: Link,
  account_id account_id: Option(Int),
  level level: step.LogLevel,
  text text: String,
) -> Effect(Nil) {
  Log(LogLine(level:, text:, about: about(link:, account_id:)))
}

/// A whole frame of a message the rule does not take: logged as unhandled,
/// and the connection goes on. `server` names whose rule it is, as the line
/// says ("auth", "game").
pub fn unhandled(
  session session: session,
  link link: Link,
  account_id account_id: Option(Int),
  server server: String,
  message_id message_id: Int,
) -> Handled(session) {
  Continue(session, [
    Log(LogLine(
      level: LogWarning,
      text: "unhandled " <> server <> " message " <> message_text(message_id:),
      about: About(
        ..about(link:, account_id:),
        message: Some(#("unhandled", message_id)),
      ),
    )),
  ])
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
pub fn end_for(
  session session: session,
  link link: Link,
  account_id account_id: Option(Int),
  text text: String,
) -> Handled(session) {
  Done(session, [log(link:, account_id:, level: LogError, text:), Stop])
}

/// The step of a rule that took bytes or an answer before the connection was
/// accepted: an error log line and the end of the connection. `rule` names
/// whose rule it is, as the line says ("auth", "game", "STS").
pub fn before_accepted(rule rule: String) -> Step(Nil, Request) {
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
  link link: Link,
  account_id account_id: Option(Int),
  rule rule: String,
) -> Step(Nil, Request) {
  Effects([
    log(
      link:,
      account_id:,
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
  Otherwise(step: Step(Nil, Request))
}

/// Sorts an input: what the client closing, a failed socket and a late answer
/// do is the same in every rule, so it is decided here; `about` says who a log
/// line is about. The server stopping ends the connection after the effects
/// `stopping` gives, which the rule writes first: none for a connection with
/// no one to tell, a notice for one whose client waits for the server's next
/// message. `stopping` is called only when the server stops. `Woken`,
/// `WatchEnded` and `TimerFired` reach only the game rule, which takes them
/// before it calls `hear`; to every rule before it watches or starts a timer,
/// and to the login's rules, they are inputs a connection is never given.
pub fn hear(
  event event: Event(message, Answer),
  about about: About,
  stopping stopping: fn() -> List(Effect(Nil)),
) -> Heard {
  let ends = fn(level, text) {
    Otherwise(Effects([Log(LogLine(level:, text:, about:)), Stop]))
  }
  case event {
    Socket(Accepted(connection:, peer:, seed:)) ->
      Connect(connection:, peer:, seed:)
    Socket(step.Read(bytes:)) -> Bytes(bytes:)
    Answered(outcome:, ..) -> Outcome(outcome:)
    Socket(PeerClosed) -> Otherwise(Effects([Stop]))
    Stopping(..) -> Otherwise(Effects(list.append(stopping(), [Stop])))
    Socket(ReadFailed(failure:)) | Socket(WriteFailed(failure:)) ->
      ends(
        LogWarning,
        "the socket failed (" <> step.describe_socket_failure(failure) <> ")",
      )
    AnsweredLate(..) -> Otherwise(Effects([]))
    Started | Woken(..) | Asked(..) | step.WatchEnded(..) | TimerFired(..) ->
      ends(
        LogError,
        "a connection rule took an input a connection is never given",
      )
  }
}

/// What taking one request or frame, or one answer, decided.
pub type Handled(session) {
  /// Go on to the next request or frame in the bytes.
  Continue(session: session, effects: List(Effect(Nil)))
  /// Carry out the effects, then ask; what follows in the bytes waits.
  Asking(session: session, effects: List(Effect(Nil)), ask: step.Ask(Request))
  /// Carry out the effects, then take no frame until another input. The
  /// effects of a rule that ends the connection hold `Stop`; one that waits for
  /// a timer or a process holds none.
  Done(session: session, effects: List(Effect(Nil)))
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
  carried carried: List(Effect(Nil)),
) -> #(state, Step(Nil, Request)) {
  case flow.take(flow.pending(session)) {
    Error(error) ->
      settle(handled: flow.refused(session, error), flow:, carried:)
    Ok(None) -> #(flow.connected(session), Effects(list.reverse(carried)))
    Ok(Some(#(first, rest))) ->
      settle(handled: flow.taking(session, first, rest), flow:, carried:)
  }
}

/// Carries out what was decided after the effects already `carried`, the last
/// first: on `Continue` `drive` takes the next item, on `Asking` the step ends
/// in the ask, on `Done` no frame is taken after the effects. The effects leave in order, reversed once
/// here.
pub fn settle(
  handled handled: Handled(session),
  flow flow: Flow(session, item, error, state),
  carried carried: List(Effect(Nil)),
) -> #(state, Step(Nil, Request)) {
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
  carried carried: List(Effect(Nil)),
  then effects: List(Effect(Nil)),
) -> List(Effect(Nil)) {
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

/// What a whole frame from the client is to a rule that takes the client's
/// wrapper.
pub type Opened(session) {
  /// The network layer's message, a frame the rule does not take, or a frame
  /// that is none the client's reader accepts: decided.
  Settled(handled: Handled(session))
  /// The frame inside the client's wrapper, for the rule to take.
  Inside(inner: Frame)
}

/// Sorts a whole frame from the client: the network layer's messages first
/// (genesis_prime/connection/network_message), answered before any wrapper is
/// looked at (a ping is answered, a pong or close notice accepted, a network
/// message that does not decode ends the connection); then the client's
/// wrapper, opened with `cipher` (genesis_prime/connection/encrypted_frame),
/// whose inner frame is given to the rule; and a frame of a message the rule
/// does not take, logged as unhandled by `server`. A wrapper or inner frame
/// that is none the client's reader accepts ends the connection.
pub fn open(
  session session: session,
  link link: Link,
  account_id account_id: Option(Int),
  server server: String,
  frame whole: Frame,
  cipher cipher: Cipher,
) -> Opened(session) {
  let ends = fn(text) { Settled(end_for(session:, link:, account_id:, text:)) }
  let unknown = fn(message_id) {
    Settled(unhandled(session:, link:, account_id:, server:, message_id:))
  }
  case network_message.handle(frame: whole) {
    network_message.Answer(bytes:) -> Settled(Continue(session, [Write(bytes)]))
    network_message.Accepted -> Settled(Continue(session, []))
    network_message.Malformed(message_id:, ..) ->
      ends(
        "a network message " <> message_text(message_id:) <> " does not decode",
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
              ends("the wrapped frame is no frame: " <> frame.describe(error))
          }
      }
  }
}
