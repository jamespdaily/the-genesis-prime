//// The draws of a recorded session, given back to a server that replays it: a
//// random source that answers each connection's draws with the ones the
//// recording server wrote for the connection it replays, in order. A replay
//// registers its connection's draws under the listener it reached and the
//// connection's own address once the connection is open
//// (`replay.run_connected`), before the first byte reaches the server, so the
//// server draws only after they are there.
////
//// A draw the source cannot answer from the recording, because the connection
//// has no draws registered, has none left or is asked for another number of
//// bytes than it recorded, ends the drawing process with the reason, which
//// closes the connection and fails the replay. `unused` names the draws a
//// replayed connection left, which a replay that gave a connection exactly its
//// own draws has none of.

import genesis_prime/login/random_source.{type Draw, type RandomSource}
import genesis_prime/recording.{type Role}
import genesis_prime/recording/session
import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result

/// The process that holds the registered draws.
pub type Draws {
  Draws(subject: Subject(Message))
}

/// A replayed connection as the server's draws name it: the listener it
/// reached and its own address.
pub type Address {
  Address(role: Role, peer: String)
}

type Registered =
  Dict(Address, List(BitArray))

/// The process's messages.
pub type Message {
  Register(address: Address, draws: List(BitArray), reply: Subject(Nil))
  Next(draw: Draw, reply: Subject(Result(BitArray, Refusal)))
  Unused(reply: Subject(List(#(Address, Int))))
}

/// Why a draw cannot be answered from the registered draws.
pub type Refusal {
  /// The draw names no connection.
  NoConnection
  /// No draws are registered for the connection.
  NothingRegistered(address: Address)
  /// The connection drew more than the recording holds.
  Exhausted(address: Address)
  /// The connection asked for `asked` bytes where the recording drew
  /// `recorded`.
  WrongSize(address: Address, asked: Int, recorded: Int)
}

fn describe(refusal: Refusal) -> String {
  case refusal {
    NoConnection -> "a draw with no connection"
    NothingRegistered(address:) ->
      "no draws are registered for " <> name(address)
    Exhausted(address:) ->
      name(address) <> " drew more than the recording holds"
    WrongSize(address:, asked:, recorded:) ->
      name(address)
      <> " drew "
      <> int.to_string(asked)
      <> " bytes where the recording drew "
      <> int.to_string(recorded)
  }
}

fn name(address: Address) -> String {
  "the " <> recording.role_name(address.role) <> " connection " <> address.peer
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
  registered: Registered,
  message: Message,
) -> actor.Next(Registered, Message) {
  case message {
    Register(address:, draws:, reply:) -> {
      process.send(reply, Nil)
      actor.continue(dict.insert(registered, address, draws))
    }
    Unused(reply:) -> {
      process.send(
        reply,
        dict.to_list(registered)
          |> list.filter_map(fn(entry) {
            case entry.1 {
              [] -> Error(Nil)
              left -> Ok(#(entry.0, list.length(left)))
            }
          }),
      )
      actor.continue(registered)
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
  registered: Registered,
  draw: Draw,
) -> Result(#(BitArray, Registered), Refusal) {
  use connection <- result.try(option.to_result(draw.connection, NoConnection))
  let address =
    Address(role: session.role_of(connection.role), peer: connection.peer)
  use recorded <- result.try(
    dict.get(registered, address)
    |> result.replace_error(NothingRegistered(address:)),
  )
  case recorded {
    [] -> Error(Exhausted(address:))
    [bytes, ..later] -> {
      let recorded_size = bit_array.byte_size(bytes)
      use <- bool.guard(
        recorded_size != draw.count,
        Error(WrongSize(address:, asked: draw.count, recorded: recorded_size)),
      )
      Ok(#(bytes, dict.insert(registered, address, later)))
    }
  }
}

/// The source to give the server's settings: each draw of a connection is
/// answered from the draws registered for its listener and address.
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

/// Registers the draws a connection will make, under the listener it reached
/// and the address the server sees for it, replacing any registered before.
pub fn register(
  draws draws: Draws,
  address address: Address,
  bytes bytes: List(BitArray),
) -> Nil {
  actor.call(draws.subject, waiting: call_ms, sending: fn(reply) {
    Register(address:, draws: bytes, reply:)
  })
}

/// The registered connections that have draws left, each with how many: what a
/// replayed connection did not use.
pub fn unused(draws draws: Draws) -> List(#(Address, Int)) {
  actor.call(draws.subject, waiting: call_ms, sending: fn(reply) {
    Unused(reply:)
  })
}
