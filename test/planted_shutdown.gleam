//// The processes a test plants to take part in the ordered stop, and the
//// program that runs them beside the real tree.
////
//// A listener, connections and a saving worker register with the shutdown the
//// way the game's own will, through `shutdown.register`. Each writes a line to
//// the output when it is asked something, and the line's order is what a test
//// reads: nothing here is timed, and a line is written before the process
//// answers, so the line of a step comes before the line of the step after it.
////
//// `main` is the program a child VM runs (`released_child.run_erlang`): the
//// real tree from `server.start` with planted children registered with its
//// coordinator, started and stopped through `shutdown.run` as `main` of the
//// server does. What it does is set by its environment: `drain_variable`,
//// `connection_variable` and `flush_variable`.

import envoy
import genesis_prime/database/pool
import genesis_prime/login/service
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import genesis_prime/shutdown.{type NotFlushed, type Settings, NotFlushed}
import genesis_prime/telemetry/log
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import pog
import pool_started

/// A TCP socket: a listening one, a connected one, or the test's end of a
/// connection.
pub type Socket

/// The drain deadline of the planted tree, in milliseconds.
pub const drain_variable = "PLANTED_DRAIN_MS"

/// Which connection ignores the request to close: `second` or `none`.
pub const connection_variable = "PLANTED_CONNECTION"

/// What the saving worker's flush does: `saves` writes what it holds to the
/// database, `fails` answers that it cannot.
pub const flush_variable = "PLANTED_FLUSH"

/// Whether the planted program kills the shutdown coordinator once the tree is
/// up: `killed` or `lives`.
pub const coordinator_variable = "PLANTED_COORDINATOR"

pub const coordinator_killed = "killed"

pub const coordinator_lives = "lives"

/// The line written just before the coordinator is killed.
pub const coordinator_killed_line = "planted coordinator killed"

/// The value of `connection_variable` for connections that all close when told.
pub const all_close = "none"

/// The value of `connection_variable` for a second connection that never
/// closes.
pub const second_never_closes = "second"

/// The value of `flush_variable` for a flush that saves.
pub const flush_saves = "saves"

/// The value of `flush_variable` for a flush that fails.
pub const flush_fails = "fails"

/// The table the flush that saves writes, and the one value in it.
pub const saved_table = "planted_saves"

pub const saved_value = 3

/// What the saving worker's flush answers when it fails.
pub const flush_failure_reason = "planted failure"

/// The name the saving worker registers by.
pub const saver_name = "planted saver"

/// The line that tells a test which port the planted listener holds.
pub fn listening(port: Int) -> String {
  "planted listening " <> int.to_string(port)
}

pub const listener_refuses = "planted listener refuses new connections"

pub const listener_accepts = "planted listener still accepts connections"

pub fn connection_registered(number: Int) -> String {
  "planted connection " <> int.to_string(number) <> " registered"
}

pub fn connection_told(number: Int) -> String {
  "planted connection " <> int.to_string(number) <> " told to close"
}

pub fn connection_closed(number: Int) -> String {
  "planted connection " <> int.to_string(number) <> " closed"
}

pub const flush_started = "planted flush started"

pub const flush_written = "planted flush written"

pub const tree_stopped = "planted tree stopped"

/// What the planted listener receives.
pub opaque type ListenerMessage {
  StopAccepting(done: Subject(Nil))
}

/// What a planted connection receives.
pub opaque type ConnectionMessage {
  Close
}

/// What a planted saving worker receives.
pub opaque type SaverMessage {
  Flush(reply: Subject(Result(Nil, NotFlushed)))
}

/// Starts a listener on a port of the loopback and registers it as a
/// `Listener`. Each connection it accepts is a planted connection, numbered
/// from 1 in the order accepted, registered as a `Connection`; the connection
/// number `ignores_close` never closes when told to. Gives the port.
pub fn start_listener(
  settings settings: Settings,
  ignores_close ignores_close: Int,
) -> Int {
  let port = process.new_subject()
  let assert Ok(_) =
    actor.new_with_initialiser(5000, fn(subject) {
      let #(socket, listening_port) = listen()
      shutdown.register(
        settings:,
        participant: shutdown.Listener(
          name: "planted listener",
          stop_accepting: fn() {
            actor.call(subject, waiting: 5000, sending: StopAccepting)
          },
        ),
      )
      process.spawn_unlinked(fn() {
        accept_each(settings:, listener: socket, ignores_close:, number: 1)
      })
      process.send(port, listening_port)
      Ok(
        actor.initialised(#(socket, listening_port)) |> actor.returning(subject),
      )
    })
    |> actor.on_message(fn(state, message: ListenerMessage) {
      let #(socket, listening_port) = state
      let StopAccepting(done:) = message
      close(socket)
      case refuses(listening_port) {
        True -> io.println(listener_refuses)
        False -> io.println(listener_accepts)
      }
      process.send(done, Nil)
      actor.continue(state)
    })
    |> actor.start
    as "the planted listener did not start"
  let assert Ok(listening_port) = process.receive(port, 5000)
    as "the planted listener did not report its port"
  listening_port
}

fn accept_each(
  settings settings: Settings,
  listener listener: Socket,
  ignores_close ignores_close: Int,
  number number: Int,
) -> Nil {
  case accept(listener) {
    Error(Nil) -> Nil
    Ok(socket) -> {
      let assert Ok(started) =
        start_connection(
          settings:,
          socket:,
          number:,
          ignores_close: number == ignores_close,
        )
        as "a planted connection did not start"
      give(socket, started.pid)
      accept_each(settings:, listener:, ignores_close:, number: number + 1)
    }
  }
}

fn start_connection(
  settings settings: Settings,
  socket socket: Socket,
  number number: Int,
  ignores_close ignores_close: Bool,
) -> Result(actor.Started(Subject(ConnectionMessage)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(subject) {
    shutdown.register(
      settings:,
      participant: shutdown.Connection(close: fn() {
        process.send(subject, Close)
      }),
    )
    io.println(connection_registered(number))
    Ok(actor.initialised(socket) |> actor.returning(subject))
  })
  |> actor.on_message(fn(socket, message: ConnectionMessage) {
    let Close = message
    io.println(connection_told(number))
    case ignores_close {
      True -> actor.continue(socket)
      False -> {
        close(socket)
        io.println(connection_closed(number))
        actor.stop()
      }
    }
  })
  |> actor.start
}

/// A saving worker that registers as a `SavingWorker` named `name`, and
/// answers a flush with what `flush` returns, run in the worker.
pub fn saver(
  settings settings: Settings,
  name name: String,
  flush flush: fn() -> Result(Nil, NotFlushed),
) -> Result(actor.Started(Subject(SaverMessage)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(subject) {
    shutdown.register(
      settings:,
      participant: shutdown.SavingWorker(name:, flush: fn() {
        actor.call(subject, waiting: 5000, sending: Flush)
      }),
    )
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, message: SaverMessage) {
    let Flush(reply:) = message
    process.send(reply, flush())
    actor.continue(state)
  })
  |> actor.start
}

/// How long the child's pool has to start: a handshake for each of its
/// connections, with room for a slow runner.
const pool_start_deadline_ms = 30_000

/// The program a child VM runs. Starts the real tree with the pool settings
/// of the environment and a pool of the test's own database, plants a
/// listener, which a test connects to, and a saving worker holding one value
/// to save, then runs as the server does until SIGTERM ends the node.
pub fn main() -> Nil {
  log.configure(debug: False)
  let drain_deadline_ms = number_from(drain_variable)
  let ignores_close = case envoy.get(connection_variable) {
    Ok(value) if value == second_never_closes -> 2
    Ok(_) | Error(Nil) -> 0
  }
  let flush_fails = envoy.get(flush_variable) == Ok(flush_fails)
  let assert Ok(pool_settings) =
    pool.from_environment(
      name: process.new_name("planted_pool"),
      get: envoy.get,
    )
    as "the planted program's pool settings are not in the environment"
  let settings = shutdown.new(drain_deadline_ms:, flush_deadline_ms: 5000)
  let assert Ok(tree) =
    server.start(server.Settings(
      pool: pool_settings,
      tables: server.TableSettings(
        key: reference.new(),
        folder: "",
        entries: [],
        requirements: [],
      ),
      shutdown: settings,
      snapshot: snapshot.settings(process.new_name("planted_snapshot")),
      login: service.settings(
        sts_port: 0,
        auth_port: 0,
        game_server: Endpoint(address: 0x7F000001, port: 0),
        realm_name: "planted",
        expected_files_digest: None,
      ),
    ))
    as "the planted program's tree did not start"
  // A stop that arrives while pgo opens the pool's connections is reported by
  // pgo's own supervisors as errors, so the program says it runs only once the
  // pool has started.
  assert pool_started.await(
    name: pool_settings.name,
    within_ms: pool_start_deadline_ms,
  )
    as "the planted program's pool did not start"
  watch_for_the_end_of(tree.pid)
  let assert Ok(_) =
    saver(settings:, name: saver_name, flush: fn() {
      case flush_fails {
        True -> {
          io.println(flush_started)
          Error(NotFlushed(reason: flush_failure_reason))
        }
        False -> save(pool.connection(pool_settings))
      }
    })
    as "the planted saving worker did not start"
  let port = start_listener(settings:, ignores_close:)
  io.println(listening(port))
  case envoy.get(coordinator_variable) == Ok(coordinator_killed) {
    True -> {
      io.println(coordinator_killed_line)
      let assert Ok(coordinator) = process.named(settings.name)
        as "the shutdown coordinator is not running"
      process.kill(coordinator)
    }
    False -> Nil
  }
  shutdown.run(tree: tree.pid, settings:)
}

/// Writes `tree_stopped` when the process ends.
fn watch_for_the_end_of(tree: process.Pid) -> Nil {
  let _watcher =
    process.spawn_unlinked(fn() {
      let monitor = process.monitor(tree)
      process.new_selector()
      |> process.select_specific_monitor(monitor, fn(_down) { Nil })
      |> process.selector_receive_forever
      io.println(tree_stopped)
    })
  Nil
}

/// Writes the value the worker holds to the database, in a table the statement
/// makes.
fn save(connection: pog.Connection) -> Result(Nil, NotFlushed) {
  io.println(flush_started)
  let written =
    pog.query(
      "create table "
      <> saved_table
      <> " as select "
      <> int.to_string(saved_value)
      <> " as unsaved",
    )
    |> pog.execute(on: connection)
  case written {
    Ok(_returned) -> {
      io.println(flush_written)
      Ok(Nil)
    }
    Error(pog.ConnectionUnavailable) ->
      Error(NotFlushed(reason: "the database is unreachable"))
    Error(pog.QueryTimeout) -> Error(NotFlushed(reason: "the save timed out"))
    Error(pog.PostgresqlError(message:, ..))
    | Error(pog.ConstraintViolated(message:, ..)) ->
      Error(NotFlushed(reason: message))
    Error(pog.UnexpectedArgumentCount(..))
    | Error(pog.UnexpectedArgumentType(..))
    | Error(pog.UnexpectedResultType(_)) ->
      Error(NotFlushed(reason: "the planted statement is malformed"))
  }
}

fn number_from(variable: String) -> Int {
  let assert Ok(text) = envoy.get(variable)
    as { variable <> " is not set in the planted program's environment" }
  let assert Ok(number) = int.parse(text)
    as { variable <> " is not a whole number" }
  number
}

@external(erlang, "planted_shutdown_ffi", "listen")
fn listen() -> #(Socket, Int)

@external(erlang, "planted_shutdown_ffi", "accept")
fn accept(listener: Socket) -> Result(Socket, Nil)

@external(erlang, "planted_shutdown_ffi", "give")
fn give(socket: Socket, owner: process.Pid) -> Nil

@external(erlang, "planted_shutdown_ffi", "close")
fn close(socket: Socket) -> Nil

@external(erlang, "planted_shutdown_ffi", "refuses")
fn refuses(port: Int) -> Bool

/// A connection from this VM to a planted listener's port, the test's end.
@external(erlang, "planted_shutdown_ffi", "connect")
pub fn connect(port: Int) -> Socket

/// Whether the other end of a connection closes it within `within`
/// milliseconds.
@external(erlang, "planted_shutdown_ffi", "await_closed")
pub fn await_closed(socket: Socket, within: Int) -> Bool
