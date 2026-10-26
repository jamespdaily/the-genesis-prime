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
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{None, Some}
import gleam/otp/actor

/// The process that holds the registered draws.
pub type Draws {
  Draws(subject: Subject(Message))
}

/// The process's messages.
pub type Message {
  Register(connection: String, draws: List(BitArray), reply: Subject(Nil))
  Next(draw: Draw, reply: Subject(Result(BitArray, String)))
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
      case draw.connection {
        None -> {
          process.send(reply, Error("a draw with no connection"))
          actor.continue(registered)
        }
        Some(connection) ->
          case dict.get(registered, connection) {
            Error(Nil) -> {
              process.send(
                reply,
                Error(
                  "no draws are registered for the connection " <> connection,
                ),
              )
              actor.continue(registered)
            }
            Ok([]) -> {
              process.send(
                reply,
                Error(
                  "the connection "
                  <> connection
                  <> " drew more than the recording holds",
                ),
              )
              actor.continue(registered)
            }
            Ok([bytes, ..later]) ->
              case bit_array.byte_size(bytes) == draw.count {
                True -> {
                  process.send(reply, Ok(bytes))
                  actor.continue(dict.insert(registered, connection, later))
                }
                False -> {
                  process.send(
                    reply,
                    Error(
                      "the connection "
                      <> connection
                      <> " drew "
                      <> int.to_string(draw.count)
                      <> " bytes where the recording drew "
                      <> int.to_string(bit_array.byte_size(bytes)),
                    ),
                  )
                  actor.continue(registered)
                }
              }
          }
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
      Error(reason) -> panic as reason
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
