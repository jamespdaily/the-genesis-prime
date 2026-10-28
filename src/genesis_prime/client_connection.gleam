//// What every client connection's rule asks other processes, what comes back,
//// and what every such rule does alike: the STS rule
//// (genesis_prime/login/sts_connection), the auth rule
//// (genesis_prime/login/auth_connection) and the game rule
//// (genesis_prime/game/connection). The server's directory sends each request
//// to its process and wraps each answer (genesis_prime/server).
////
//// Each rule keeps a `Link`: who the connection is for their log lines, the
//// seed's random source and the number of their last ask. Each sorts an input
//// with `hear`, which decides what the client closing, the server stopping, a
//// failed socket, a late answer and an input a connection is never given do.
//// Each takes a request or frame at a time and says what it decided with
//// `Handled`, which `settle` carries out.

import genesis_prime/hand_off
import genesis_prime/random.{type Random}
import genesis_prime/step.{
  type About, type ConnectionId, type Effect, type Event, type Now, type Outcome,
  type Peer, type Step, About, Accepted, Answered, AnsweredLate, AskId, Asked,
  Effects, EffectsThenAsk, Log, LogError, LogLine, LogWarning, PeerClosed,
  ReadFailed, Socket, Started, Stop, Stopping, TimerFired, Woken, WriteFailed,
}
import genesis_prime/store
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
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

/// Sorts an input: what the client closing, the server stopping, a failed
/// socket, a late answer and an input a connection is never given do is the
/// same in every rule, so it is decided here; `about` says who a log line is
/// about.
pub fn hear(event event: Event(Nil, Answer), about about: About) -> Heard {
  let ends = fn(level, text) {
    Otherwise(Effects([Log(LogLine(level:, text:, about:)), Stop]))
  }
  case event {
    Socket(Accepted(connection:, peer:, seed:)) ->
      Connect(connection:, peer:, seed:)
    Socket(step.Read(bytes:)) -> Bytes(bytes:)
    Answered(outcome:, ..) -> Outcome(outcome:)
    Socket(PeerClosed) | Stopping(..) -> Otherwise(Effects([Stop]))
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
