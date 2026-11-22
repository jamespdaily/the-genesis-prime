//// A page's websocket: the connection a tab makes to its runtime.
////
//// ```text
//// tab ──text frame──► decoded runtime message ──► runtime (one per tab)
//// tab ◄─text frame─── client message ◄────────── runtime
//// ```
////
//// - The upgrade reaches this module only after the gate allowed it
////   (`web.handle`), so a refused handshake starts no runtime.
//// - A tab's runtime is started under the page's factory supervisor before the
////   handshake is answered and stopped when the socket closes, so tabs share
////   nothing. A start that fails, or whose factory ends during the ask, is a
////   503 for the caller to answer, and a handshake mist refuses stops the
////   runtime. The socket is the same for every page: the page's message type
////   and the argument its runtime starts with are the caller's.
//// - Mist ends a socket whose init takes over 500 ms with an HTTP answer after
////   the 101. The init is only constant work in the socket's own process: it
////   makes a subject, sends the runtime one message, monitors the runtime and
////   builds a selector, beside mist's own set-up of the compression state of a
////   permessage-deflate handshake. None of it receives, calls or waits for
////   another process, so only a stall of the whole machine can make it late.
//// - The socket monitors its runtime: a runtime that ends (the supervisor
////   rebuilds the page runtimes together with what they follow) closes the socket
////   with an abnormal end, so the tab's client reconnects and gets a new one.
//// - A text frame that is not a runtime message ends the connection, as a
////   reader that refuses a frame does.

import exception.{type Exception}
import genesis_prime/step/runtime
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result
import lustre
import lustre/server_component
import mist.{type Connection, type ResponseData}

/// The factory supervisor that holds a page's runtimes; each is started with
/// the argument the page subscribes by (the poller, or the followers it
/// follows).
pub type Runtimes(argument, message) =
  factory_supervisor.Supervisor(
    argument,
    Subject(lustre.RuntimeMessage(message)),
  )

/// What a websocket is told: the runtime sent the page a change, or the
/// runtime ended.
type Event(message) {
  FromRuntime(server_component.ClientMessage(message))
  RuntimeEnded
}

/// What a websocket holds: its page's runtime and the subject the runtime
/// sends the page's changes to.
type Socket(message) {
  Socket(
    runtime: Subject(lustre.RuntimeMessage(message)),
    client: Subject(server_component.ClientMessage(message)),
  )
}

/// Why a page's runtime did not start: the factory returned an error, or the
/// ask of it ended with an exception because the factory was gone or ended
/// while the ask waited.
pub type NotStarted {
  StartFailed(actor.StartError)
  AskEnded(Exception)
}

/// The way a runtime did not start and its reason, as a line of the log says it.
pub fn describe_not_started(not_started not_started: NotStarted) -> String {
  case not_started {
    StartFailed(error) ->
      "the page's runtime " <> runtime.describe_start_error(error)
    AskEnded(exception.Exited(reason)) ->
      "the runtimes' factory ended while the start was asked: "
      <> runtime.term_text(reason)
    AskEnded(exception.Errored(reason)) ->
      "the ask of the runtimes' factory raised an error: "
      <> runtime.term_text(reason)
    AskEnded(exception.Thrown(reason)) ->
      "the ask of the runtimes' factory threw a value: "
      <> runtime.term_text(reason)
  }
}

/// Starts the page's runtime in `runtimes` with the `argument` the page
/// subscribes by, then upgrades the request to a websocket on it. The runtime
/// starts before the handshake is answered, so a start that is slow or fails is
/// the handshake's answer and never a failure after the upgrade. The error is
/// that the runtime did not start: the factory returned an error, or it was
/// gone or ended while the ask waited, which makes the asking process exit. The
/// error says which, for the log.
pub fn upgrade(
  request request: Request(Connection),
  runtimes runtimes: Runtimes(argument, message),
  argument argument: argument,
) -> Result(Response(ResponseData), NotStarted) {
  use started <- result.try(
    case
      exception.rescue(fn() {
        factory_supervisor.start_child(runtimes, argument)
      })
    {
      Ok(Ok(started)) -> Ok(started)
      Ok(Error(error)) -> Error(StartFailed(error))
      Error(exception) -> Error(AskEnded(exception))
    },
  )
  let response =
    mist.websocket(
      request:,
      on_init: fn(_connection) {
        // Runs under mist's 500 ms limit: only the constant work the module
        // lists. A send to a runtime that has ended is dropped and the monitor
        // of one answers at once, which closes the socket.
        let client = process.new_subject()
        process.send(started.data, server_component.register_subject(client))
        let _monitor = process.monitor(started.pid)
        let selector =
          process.new_selector()
          |> process.select_map(client, FromRuntime)
          |> process.select_monitors(fn(_down) { RuntimeEnded })
        #(Socket(runtime: started.data, client:), Some(selector))
      },
      handler: handle,
      on_close: fn(socket: Socket(message)) {
        process.send(
          socket.runtime,
          server_component.deregister_subject(socket.client),
        )
        process.send(socket.runtime, lustre.shutdown())
      },
    )
  // A body that is not the websocket is mist's refusal of the handshake: no
  // socket is left to serve, so the runtime is stopped.
  case response.body {
    mist.Websocket -> Nil
    _refused -> process.send(started.data, lustre.shutdown())
  }
  Ok(response)
}

fn handle(
  socket socket: Socket(message),
  message message: mist.WebsocketMessage(Event(message)),
  connection connection: mist.WebsocketConnection,
) -> mist.Next(Socket(message), Event(message)) {
  case message {
    mist.Text(text) ->
      case json.parse(text, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> {
          process.send(socket.runtime, runtime_message)
          mist.continue(socket)
        }
        Error(error) -> mist.stop_abnormal(describe(error))
      }
    mist.Binary(_) -> mist.continue(socket)
    mist.Custom(RuntimeEnded) -> mist.stop_abnormal("the page's runtime ended")
    mist.Custom(FromRuntime(client_message)) -> {
      // A write to a socket that has gone ends this process; the close
      // callback then stops the runtime.
      let assert Ok(Nil) =
        mist.send_text_frame(
          connection,
          json.to_string(server_component.client_message_to_json(client_message)),
        )
        as "the page's socket could not be written"
      mist.continue(socket)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn describe(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "the page sent a frame that ends early"
    json.UnexpectedByte(byte) -> "the page sent a frame with the byte " <> byte
    json.UnexpectedSequence(text) ->
      "the page sent a frame with the sequence " <> text
    json.UnableToDecode(errors) ->
      "the page sent a frame that is not a runtime message ("
      <> int.to_string(list.length(errors))
      <> " fields wrong)"
  }
}
