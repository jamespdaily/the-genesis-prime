//// A page's websocket: the connection a tab makes to its runtime.
////
//// ```text
//// tab ──text frame──► decoded runtime message ──► runtime (one per tab)
//// tab ◄─text frame─── client message ◄────────── runtime
//// ```
////
//// - The upgrade reaches this module only after the gate allowed it
////   (`web.handle`), so a refused handshake starts no runtime.
//// - A tab's runtime is started under the factory supervisor when the socket
////   opens and stopped when it closes, so tabs share nothing.
//// - The socket monitors its runtime: a runtime that ends (the supervisor
////   rebuilds the page runtimes together with the poller) closes the socket
////   with an abnormal end, so the tab's client reconnects and gets a new one.
//// - A text frame that is not a runtime message ends the connection, as a
////   reader that refuses a frame does.

import genesis_prime/dashboard/host
import genesis_prime/dashboard/overview
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/factory_supervisor
import lustre
import lustre/server_component
import mist.{type Connection, type ResponseData}

/// The factory supervisor that holds a page's runtimes; each is started with
/// the poller it subscribes to.
pub type Runtimes =
  factory_supervisor.Supervisor(
    Subject(host.Message),
    Subject(lustre.RuntimeMessage(overview.Message)),
  )

/// What a websocket is told: the runtime sent the page a change, or the
/// runtime ended.
type Event {
  FromRuntime(server_component.ClientMessage(overview.Message))
  RuntimeEnded
}

/// What a websocket holds: its page's runtime and the subject the runtime
/// sends the page's changes to.
type Socket {
  Socket(
    runtime: Subject(lustre.RuntimeMessage(overview.Message)),
    client: Subject(server_component.ClientMessage(overview.Message)),
  )
}

/// Upgrades the request to a websocket whose runtime is started in
/// `runtimes`, subscribed to `poller`.
pub fn upgrade(
  request request: Request(Connection),
  runtimes runtimes: Runtimes,
  poller poller: Subject(host.Message),
) -> Response(ResponseData) {
  mist.websocket(
    request:,
    on_init: fn(_connection) {
      let assert Ok(started) = factory_supervisor.start_child(runtimes, poller)
        as "the page's runtime did not start"
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
    on_close: fn(socket: Socket) {
      process.send(
        socket.runtime,
        server_component.deregister_subject(socket.client),
      )
      process.send(socket.runtime, lustre.shutdown())
    },
  )
}

fn handle(
  socket socket: Socket,
  message message: mist.WebsocketMessage(Event),
  connection connection: mist.WebsocketConnection,
) -> mist.Next(Socket, Event) {
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
