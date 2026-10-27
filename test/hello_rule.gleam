//// A tiny connection rule for the shell's and the replay's tests: it greets
//// a client with the server hello and answers each ping with its pong, and
//// nothing else. The login card's rules replace it in the server.

import genesis_prime/connection/frame
import genesis_prime/connection/network_message.{
  Accepted, Answer, Malformed, NotNetwork,
}
import genesis_prime/message/server_hello.{type ServerHello}
import genesis_prime/step.{
  type Effect, type Input, type Step, About, Effects, Input, Log, LogLine,
  LogWarning, Socket, Stop, Write,
}
import gleam/list
import gleam/option.{None}

/// The rule's settings: the hello it greets each client with.
pub type Settings {
  Settings(hello: ServerHello)
}

/// What the rule keeps between inputs: the hello, and the bytes of a frame
/// not yet whole.
pub type State {
  State(hello: ServerHello, pending: BitArray)
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  State(hello: settings.hello, pending: <<>>)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Nil, Nil),
) -> #(State, Step(Nil, Nil)) {
  let Input(event:, ..) = input
  case event {
    Socket(step.Accepted(..)) -> #(state, Effects([Write(hello_frame(state))]))
    Socket(step.Read(bytes:)) -> read(state, <<state.pending:bits, bytes:bits>>)
    Socket(step.PeerClosed) | step.Stopping(..) -> #(state, Effects([Stop]))
    Socket(step.ReadFailed(..)) | Socket(step.WriteFailed(..)) -> #(
      state,
      Effects([warn("the socket failed"), Stop]),
    )
    step.Started
    | step.Woken(..)
    | step.Asked(..)
    | step.WatchEnded(..)
    | step.TimerFired(..)
    | step.Answered(..)
    | step.AnsweredLate(..) -> #(
      state,
      Effects([warn("an input a connection does not take"), Stop]),
    )
  }
}

fn read(state: State, received: BitArray) -> #(State, Step(Nil, Nil)) {
  let #(frames, rest) = frame.split(received:)
  let answers =
    list.map(frames, fn(found) {
      case network_message.handle(frame: found) {
        Answer(bytes:) -> [Write(bytes)]
        Accepted -> []
        NotNetwork -> [warn("a message the hello rule does not answer")]
        Malformed(..) -> [warn("a malformed network message"), Stop]
      }
    })
    |> list.flatten
  case rest {
    Ok(pending) -> #(State(..state, pending:), Effects(answers))
    Error(error) -> #(
      State(..state, pending: <<>>),
      Effects(list.append(answers, [warn(frame_problem(error)), Stop])),
    )
  }
}

fn frame_problem(error: frame.FrameError) -> String {
  case error {
    frame.LengthOverLimit(..) -> "a frame over the size limit"
    frame.LengthBelowHeader(..) -> "a frame shorter than its header"
    frame.ShorterThanHeader(..)
    | frame.LengthDisagrees(..)
    | frame.MessageIdOutOfRange(..) -> "a frame the client never sends"
  }
}

fn hello_frame(state: State) -> BitArray {
  let assert Ok(body) = server_hello.encode(state.hello)
    as "every field of the settings' hello is within its width"
  let assert Ok(bytes) = frame.encode(server_hello.message_id, body)
    as "the hello is far below the size limit"
  bytes
}

fn warn(text: String) -> Effect(Nil) {
  Log(LogLine(
    level: LogWarning,
    text:,
    about: About(
      connection: None,
      peer: None,
      account_id: None,
      character_id: None,
      map: None,
      message: None,
    ),
  ))
}
