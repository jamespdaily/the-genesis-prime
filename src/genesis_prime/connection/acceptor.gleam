//// The process that waits for clients on a listening socket. For each client
//// it checks the connection cap, starts a socket owner under the connection
//// supervisor and makes the owner the socket's owner. A client over the cap,
//// or whose owner did not start, is closed at once and logged.
////
//// The acceptor waits for a client inside its message handler, so it answers
//// no other message while it waits; it has no other message, and a stop
//// signal from its supervisor ends it at once, because it does not trap
//// exits. It restarts with a new listening socket.

import genesis_prime/connection/capacity
import genesis_prime/connection/socket.{type ListenSocket, type Socket}
import genesis_prime/connection/socket_owner
import genesis_prime/shutdown
import genesis_prime/telemetry/log
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision

/// How long the supervisor waits for the acceptor to stop before it kills it,
/// in milliseconds: the process holds nothing to flush.
const shutdown_ms = 1000

/// How long the acceptor has to open its socket and start, in milliseconds.
const start_deadline_ms = 5000

/// Who the acceptor's lines are from: the process, by its name, and the peer
/// address of the client the line is about, when there is one. A client that
/// has not logged in has no account.
fn acceptor_who(peer: Option(String)) -> log.Who {
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Process("acceptor")),
    message: None,
    peer:,
  )
}

/// What the acceptor needs to start.
pub type Settings {
  Settings(
    port: Int,
    connection_cap: Int,
    heap_ceiling_words: Int,
    connections: process.Name(
      factory_supervisor.Message(Socket, Subject(socket_owner.Message)),
    ),
    listening: fn(Int) -> Nil,
    shutdown: shutdown.Settings,
  )
}

/// The acceptor's own message: accept the next client.
pub opaque type Message {
  Accept
}

type State {
  State(listen: ListenSocket, settings: Settings, self: Subject(Message))
}

/// The acceptor as a child of the listener's supervisor, restarted when it
/// ends and given `shutdown_ms` to stop. It opens the listening socket when it
/// starts and calls `listening` with the port it got.
pub fn supervised(
  settings settings: Settings,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(settings) })
  |> supervision.timeout(ms: shutdown_ms)
}

fn start(settings: Settings) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_ms, fn(subject) {
    case socket.listen(settings.port) {
      Ok(listen) -> {
        let assert Ok(port) = socket.listening_port(listen)
          as "a listening socket has a port"
        log.info(
          acceptor_who(None),
          "listening on port "
            <> int.to_string(port)
            <> ", "
            <> capacity.describe(
            cap: settings.connection_cap,
            ceiling_words: settings.heap_ceiling_words,
          ),
        )
        settings.listening(port)
        process.send(subject, Accept)
        Ok(
          actor.initialised(State(listen:, settings:, self: subject))
          |> actor.returning(subject),
        )
      }
      Error(reason) ->
        Error(
          "could not listen on port "
          <> int.to_string(settings.port)
          <> ": "
          <> socket.describe(reason),
        )
    }
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  let Accept = message
  case socket.accept(state.listen) {
    Ok(client) -> {
      admit(state.settings, client)
      // The next accept waits behind any message already queued.
      process.send(state.self, Accept)
      actor.continue(state)
    }
    Error(reason) ->
      actor.stop_abnormal(
        "the listening socket failed: " <> socket.describe(reason),
      )
  }
}

/// Gives a client its socket owner, or closes the client when the server is at
/// its cap or the owner did not start.
fn admit(settings: Settings, client: Socket) -> Nil {
  let connections = factory_supervisor.get_by_name(settings.connections)
  let who = acceptor_who(socket.peer(client))
  case
    factory_supervisor.count_children(connections) >= settings.connection_cap
  {
    True -> {
      log.warning(
        who,
        "connection refused: the listener is at its cap of "
          <> int.to_string(settings.connection_cap)
          <> " connections",
      )
      socket.close(client)
    }
    False ->
      case factory_supervisor.start_child(connections, client) {
        Ok(started) -> {
          case socket.give_to(client, started.pid) {
            Ok(Nil) -> Nil
            Error(reason) ->
              log.warning(
                who,
                "connection could not be given to its owner: "
                  <> socket.describe(reason),
              )
          }
          socket_owner.socket_given(started.data)
        }
        Error(error) -> {
          log.warning(
            who,
            "connection refused: its owner did not start: "
              <> describe_start_error(error),
          )
          socket.close(client)
        }
      }
  }
}

fn describe_start_error(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "it did not start in time"
    actor.InitFailed(why) -> why
    actor.InitExited(_) -> "it ended while starting"
  }
}
