//// What every client connection's rule asks other processes, what comes back,
//// and what every such rule does alike: the STS rule
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
//// Each takes a request or frame at a time and says what it decided with
//// `Handled`, which `settle` carries out. The rules that take the client's
//// wrapper (the auth rule and the game rule) read each whole frame with
//// `drive` and `open`, and write each message with `wrapped`.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/client_frame
import genesis_prime/connection/encrypted_frame.{type Wrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/hand_off
import genesis_prime/random.{type Random}
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
}

/// What comes back from an ask, by the process asked.
pub type Answer {
  FromStore(answer: store.Answer)
  FromHandOff(answer: hand_off.Answer)
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

/// The log line of a whole frame of a message the rule does not take: it is
/// logged and the connection goes on. `server` names whose rule it is, as the
/// line says ("auth", "game").
pub fn unhandled(
  link link: Link,
  account_id account_id: Option(Int),
  server server: String,
  message_id message_id: Int,
) -> Effect(Nil) {
  Log(LogLine(
    level: LogWarning,
    text: "unhandled " <> server <> " message " <> message_text(message_id:),
    about: About(
      ..about(link:, account_id:),
      message: Some(#("unhandled", message_id)),
    ),
  ))
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
/// line is about. The server stopping ends the connection after `stopping`,
/// the effects the rule writes first: none for a connection with no one to
/// tell, a notice for one whose client waits for the server's next message.
pub fn hear(
  event event: Event(Nil, Answer),
  about about: About,
  stopping stopping: List(Effect(Nil)),
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
    Stopping(..) -> Otherwise(Effects(list.append(stopping, [Stop])))
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
  /// Carry out the effects, which end with `Stop`.
  End(session: session, effects: List(Effect(Nil)))
}

/// Carries out what was decided after the effects already `carried`: on
/// `Continue` the rule's `drive` takes the next request or frame, on `Asking`
/// the step ends in the ask, on `End` it ends.
pub fn settle(
  handled handled: Handled(session),
  carried carried: List(Effect(Nil)),
  connected connected: fn(session) -> state,
  drive drive: fn(session, List(Effect(Nil))) -> #(state, Step(Nil, Request)),
) -> #(state, Step(Nil, Request)) {
  case handled {
    Continue(session:, effects:) ->
      drive(session, list.append(carried, effects))
    Asking(session:, effects:, ask:) -> #(
      connected(session),
      EffectsThenAsk(list.append(carried, effects), ask),
    )
    End(session:, effects:) -> #(
      connected(session),
      Effects(list.append(carried, effects)),
    )
  }
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

/// Sorts a whole frame from the client: a ping is answered, a pong or close
/// notice accepted, a network message that does not decode ends the
/// connection, a frame of a message the rule does not take is logged as
/// unhandled by `server`, and the frame inside the client's wrapper, opened
/// with `cipher`, is given to the rule.
pub fn open(
  session session: session,
  link link: Link,
  account_id account_id: Option(Int),
  server server: String,
  frame whole: Frame,
  cipher cipher: Cipher,
) -> Opened(session) {
  case client_frame.receive(frame: whole, cipher:) {
    client_frame.Pong(bytes:) -> Settled(Continue(session, [Write(bytes)]))
    client_frame.Noted -> Settled(Continue(session, []))
    client_frame.Malformed(message_id:, ..) ->
      Settled(
        End(session, [
          log(
            link:,
            account_id:,
            level: LogError,
            text: "a network message "
              <> message_text(message_id:)
              <> " does not decode",
          ),
          Stop,
        ]),
      )
    client_frame.Unknown(message_id:) ->
      Settled(
        Continue(session, [unhandled(link:, account_id:, server:, message_id:)]),
      )
    client_frame.Broken(error:) ->
      Settled(
        End(session, [
          log(
            link:,
            account_id:,
            level: LogError,
            text: "the wrapped frame is no frame: " <> frame.describe(error),
          ),
          Stop,
        ]),
      )
    client_frame.Wrapped(inner:) -> Inside(inner:)
  }
}

/// Takes the whole frames in a session's pending bytes in order, until one
/// asks, the connection ends or the bytes hold no more. `taking` takes one
/// frame, given the bytes after it as `rest`, which it keeps as the
/// session's pending bytes; `refused` ends the connection for bytes that are
/// no frame, after the whole frames before them; `carried` are the effects
/// already decided.
pub fn drive(
  session session: session,
  carried carried: List(Effect(Nil)),
  pending pending: fn(session) -> BitArray,
  taking taking: fn(session, Frame, BitArray) -> Handled(session),
  refused refused: fn(session, FrameError) -> Handled(session),
  connected connected: fn(session) -> state,
) -> #(state, Step(Nil, Request)) {
  let next = fn(session, carried) {
    drive(session:, carried:, pending:, taking:, refused:, connected:)
  }
  case frame.take(pending(session)) {
    Error(error) ->
      settle(
        handled: refused(session, error),
        carried:,
        connected:,
        drive: next,
      )
    Ok(None) -> #(connected(session), Effects(carried))
    Ok(Some(#(first, rest))) ->
      settle(
        handled: taking(session, first, rest),
        carried:,
        connected:,
        drive: next,
      )
  }
}
