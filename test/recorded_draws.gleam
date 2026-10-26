//// The draws of a recorded session, given back to a server that replays it: a
//// random source that answers each connection's draws with the ones the
//// recording server wrote for the connection it replays, in order. A replay
//// registers its connection's draws under the connection's own address once
//// the connection is open (`replay.run_connected`), before the first byte
//// reaches the server, so the server draws only after they are there.
////
//// A draw the source cannot answer from the recording, because the connection
//// has no draws registered, has none left or is asked for another number of
//// bytes than it recorded, ends the drawing process with the reason, which
//// closes the connection and fails the replay.

import genesis_prime/login/random_source.{type Draw, type RandomSource}
import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option
import gleam/otp/actor
import gleam/result

/// The process that holds the registered draws.
pub type Draws {
  Draws(subject: Subject(Message))
}

/// The process's messages.
pub type Message {
  Register(connection: String, draws: List(BitArray), reply: Subject(Nil))
  Next(draw: Draw, reply: Subject(Result(BitArray, Refusal)))
}

/// Why a draw cannot be answered from the registered draws.
pub type Refusal {
  /// The draw names no connection.
  NoConnection
  /// No draws are registered for the connection.
  NothingRegistered(connection: String)
  /// The connection drew more than the recording holds.
  Exhausted(connection: String)
  /// The connection asked for `asked` bytes where the recording drew
  /// `recorded`.
  WrongSize(connection: String, asked: Int, recorded: Int)
}

fn describe(refusal: Refusal) -> String {
  case refusal {
    NoConnection -> "a draw with no connection"
    NothingRegistered(connection:) ->
      "no draws are registered for the connection " <> connection
    Exhausted(connection:) ->
      "the connection " <> connection <> " drew more than the recording holds"
    WrongSize(connection:, asked:, recorded:) ->
      "the connection "
      <> connection
      <> " drew "
      <> int.to_string(asked)
      <> " bytes where the recording drew "
      <> int.to_string(recorded)
  }
}

/// How long a caller waits for the process, in milliseconds. It answers from
/// memory.
const call_ms = 5000

/// Starts the process, linked to the caller, with no draws registered.
pub fn start() -> Draws {
  let assert Ok(started) =
    actor.new(dict.new())
    |> actor.on_message(handle)
    |> actor.start
    as "the recorded draws' process did not start"
  Draws(subject: started.data)
}

fn handle(
  registered: Dict(String, List(BitArray)),
  message: Message,
) -> actor.Next(Dict(String, List(BitArray)), Message) {
  case message {
    Register(connection:, draws:, reply:) -> {
      process.send(reply, Nil)
      actor.continue(dict.insert(registered, connection, draws))
    }
    Next(draw:, reply:) ->
      case answer(registered, draw) {
        Ok(#(bytes, registered)) -> {
          process.send(reply, Ok(bytes))
          actor.continue(registered)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(registered)
        }
      }
  }
}

/// The next draw registered for the draw's connection, and the registered draws
/// without it, or why there is none to give.
fn answer(
  registered: Dict(String, List(BitArray)),
  draw: Draw,
) -> Result(#(BitArray, Dict(String, List(BitArray))), Refusal) {
  use connection <- result.try(option.to_result(draw.connection, NoConnection))
  use recorded <- result.try(
    dict.get(registered, connection)
    |> result.replace_error(NothingRegistered(connection:)),
  )
  case recorded {
    [] -> Error(Exhausted(connection:))
    [bytes, ..later] -> {
      let recorded_size = bit_array.byte_size(bytes)
      use <- bool.guard(
        recorded_size != draw.count,
        Error(WrongSize(connection:, asked: draw.count, recorded: recorded_size)),
      )
      Ok(#(bytes, dict.insert(registered, connection, later)))
    }
  }
}

/// The source to give the server's settings: each draw of a connection is
/// answered from the draws registered for its address.
pub fn source(draws draws: Draws) -> RandomSource {
  random_source.Supplied(draw: fn(draw) {
    let answer =
      actor.call(draws.subject, waiting: call_ms, sending: fn(reply) {
        Next(draw:, reply:)
      })
    case answer {
      Ok(bytes) -> bytes
      Error(refusal) -> panic as describe(refusal)
    }
  })
}

/// Registers the draws a connection will make, under the address the server
/// sees for it, replacing any registered before.
pub fn register(
  draws draws: Draws,
  connection connection: String,
  bytes bytes: List(BitArray),
) -> Nil {
  actor.call(draws.subject, waiting: call_ms, sending: fn(reply) {
    Register(connection:, draws: bytes, reply:)
  })
}
