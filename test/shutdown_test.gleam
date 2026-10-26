//// The server stops in order: stop accepting, drain connections, flush saves,
//// then stop the tree and end the node. Each test that sends SIGTERM starts a
//// child VM (`released_child`) running the real tree with planted processes
//// registered with its shutdown (`planted_shutdown`), and reads the lines the
//// planted processes and the server write, in the order they were written.
//// Expected values come from three places.
//// - The issue: "Stop accepting, drain connections, flush saves, then stop",
////   with the connection drain bounded by a deadline that is a start argument
////   and the flush's failure logged as an error (the designing-processes skill:
////   "Error: a bug, always looked into").
//// - OTP: a SIGTERM stops a node with `init:stop()` unless a handler of
////   `erl_signal_server` replaces the default one (`erl_signal_handler`,
////   Kernel's "Signals" section of `os:set_signal/2`), and `init:stop(Status)`
////   ends the node with that status, which is 0 for a clean stop and the
////   operating system's exit status for the process.
//// - The network: a connection to a port that nothing listens on is refused
////   (`econnrefused`), and a peer that closes a connection is seen by the
////   other end as `closed` (`gen_tcp:recv/3`).
////
//// What a planted process writes before it answers comes before what the step
//// after it writes, so the order of the lines is the order of the steps and no
//// test depends on timing.

import genesis_prime/server
import genesis_prime/shutdown.{FlushFailed, Stopped}
import gleam/dynamic/decode
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/string
import owned_test
import planted_shutdown
import pog
import released_child.{type Child}
import template_database

/// How long a test waits for a child to start, ask to stop and end: the
/// child's own limit on its silence, plus its database and its end.
const child_deadline_ms = 90_000

/// How long a test waits for a closed connection to be seen. The child ends the
/// connection before it writes the line that the test has read, so the close is
/// already there.
const close_wait_ms = 5000

/// The drain deadline of a child that is not testing it, long enough that a
/// connection that closes when told is never close to it.
const long_drain_ms = 30_000

/// How long a node has to end by itself once its coordinator is killed: the
/// supervisor ends it as the coordinator dies, so a node still running after
/// this is not ending. The snapshot lines it writes every few seconds keep a
/// silence limit from ending the wait.
const coordinator_loss_deadline_ms = 20_000

/// The drain deadline of the child whose connection never closes: short, so the
/// test does not wait out a long one.
const short_drain_ms = 500

fn start(
  database: template_database.Database,
  drain_ms drain_ms: Int,
  connection connection: String,
  flush flush: String,
  coordinator coordinator: String,
  body body: fn(Child) -> a,
) -> a {
  released_child.run_erlang(
    arguments: [
      "-noshell",
      "-eval",
      "genesis_prime@@main:run(planted_shutdown).",
    ],
    environment: [
      #(planted_shutdown.drain_variable, int.to_string(drain_ms)),
      #(planted_shutdown.connection_variable, connection),
      #(planted_shutdown.flush_variable, flush),
      #(planted_shutdown.coordinator_variable, coordinator),
      ..released_child.database_environment(database)
    ],
    body:,
  )
}

/// Reads the child up to the line that says it runs, and gives the port its
/// planted listener holds.
fn until_running(child: Child) -> Int {
  let assert Ok(lines) =
    released_child.lines_until(child, string.contains(
      _,
      released_child.server_running,
    ))
    as "the child did not say it was running"
  let assert Ok(port_line) =
    list.find(lines, string.starts_with(_, "planted listening "))
    as "the child did not say which port its listener holds"
  let assert Ok(port) =
    int.parse(string.remove_prefix(port_line, "planted listening "))
    as "the listener's port is not a number"
  port
}

/// Connects to the listener and reads up to the line that says the connection
/// `number` is registered with the shutdown.
fn connect_and_wait_for_registration(
  child child: Child,
  port port: Int,
  number number: Int,
) -> planted_shutdown.Socket {
  let socket = planted_shutdown.connect(port)
  let assert Ok(_) =
    released_child.lines_until(child, fn(line) {
      line == planted_shutdown.connection_registered(number)
    })
    as "the planted connection did not register"
  socket
}

/// Where a line is among the lines, panicking when it is not there.
fn position(lines: List(String), line: String) -> Int {
  let assert Ok(found) =
    list.index_map(lines, fn(candidate, index) { #(candidate, index) })
    |> list.find_map(fn(pair) {
      case pair.0 == line {
        True -> Ok(pair.1)
        False -> Error(Nil)
      }
    })
    as { "the child did not write: " <> line }
  found
}

/// The value the planted saving worker's flush wrote, or none when it wrote
/// nothing.
fn saved_values(database: template_database.Database) -> List(Int) {
  case
    pog.query("select unsaved from " <> planted_shutdown.saved_table)
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(on: database.connection)
  {
    Ok(returned) -> returned.rows
    Error(pog.PostgresqlError(..)) -> []
    Error(error) ->
      panic as { "the saved value could not be read: " <> string.inspect(error) }
  }
}

pub fn sigterm_stops_in_order_and_ends_the_node_with_status_0_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use child <- start(
    database,
    drain_ms: long_drain_ms,
    connection: planted_shutdown.all_close,
    flush: planted_shutdown.flush_saves,
    coordinator: planted_shutdown.coordinator_lives,
  )
  let port = until_running(child)
  let first = connect_and_wait_for_registration(child:, port:, number: 1)
  let second = connect_and_wait_for_registration(child:, port:, number: 2)

  released_child.terminate(child)
  let assert Ok(#(lines, status)) = released_child.lines_until_exit(child)
    as "the child did not end after SIGTERM"

  // The steps, each after the one before it.
  let refuses = position(lines, planted_shutdown.listener_refuses)
  let told_first = position(lines, planted_shutdown.connection_told(1))
  let told_second = position(lines, planted_shutdown.connection_told(2))
  let closed_first = position(lines, planted_shutdown.connection_closed(1))
  let closed_second = position(lines, planted_shutdown.connection_closed(2))
  let flush_started = position(lines, planted_shutdown.flush_started)
  let flush_written = position(lines, planted_shutdown.flush_written)
  let tree_stopped = position(lines, planted_shutdown.tree_stopped)
  assert refuses < told_first && refuses < told_second
    as "a connection was told to close before the listener refused new ones"
  assert told_first < closed_first && told_second < closed_second
    as "a connection closed before it was told to"
  assert int.max(closed_first, closed_second) < flush_started
    as "the flush began before every connection had closed"
  assert flush_started < flush_written
  assert flush_written < tree_stopped
    as "the tree stopped before the flush was written"
  assert !list.contains(lines, planted_shutdown.listener_accepts)
    as "the listener still accepted a connection after it stopped accepting"

  // What the steps did, seen from outside the child.
  assert planted_shutdown.await_closed(first, close_wait_ms)
    as "the first connection was not closed"
  assert planted_shutdown.await_closed(second, close_wait_ms)
    as "the second connection was not closed"
  assert saved_values(database) == [planted_shutdown.saved_value]
    as "the saving worker's value was not written to the database"
  assert status == 0 as "a clean stop ends the node with status 0"
  assert !list.any(lines, string.contains(_, " error "))
    as "a clean stop logged an error"
}

/// How many nodes a test stops. An entry point that waits with
/// `process.sleep_forever` after asking `init` to stop crashes in some stops
/// only: the wait loads the `timer` module through the code server, which
/// `init` has stopped by then, unless `init` kills the process first. `init`
/// reports the crash as an expression that failed. 14 of 30 starts of such an
/// entry point reported it, and none of 40 with `timer` loaded beforehand. 25
/// stops miss such an entry point fewer than once in 500 runs.
const stops_that_catch_a_failed_eval = 25

/// How many of those nodes run at the same time.
const stops_at_once = 5

/// A node stopped by SIGTERM: what it wrote, its stderr among it, and its exit
/// status.
type Stopped =
  #(List(String), Int)

/// Starts a node with the planted `coordinator`, waits until it runs and stops
/// it by SIGTERM. Each node has a database of its own, and is started and read
/// by the process that calls this, which is the one that owns its output.
fn stop_one(coordinator coordinator: String) -> Stopped {
  use database <- template_database.run
  use child <- start(
    database,
    drain_ms: long_drain_ms,
    connection: planted_shutdown.all_close,
    flush: planted_shutdown.flush_saves,
    coordinator:,
  )
  let _port = until_running(child)
  released_child.terminate(child)
  let assert Ok(ended) = released_child.lines_until_exit(child)
    as "the child did not end after SIGTERM"
  ended
}

/// What a worker that stops one node tells the test.
type Worker {
  Ended(Stopped)
  Crashed
}

/// Stops `stops_that_catch_a_failed_eval` nodes, `stops_at_once` at a time,
/// each in a process of its own, and gives what each wrote and its status.
fn stop_many(coordinator coordinator: String) -> List(Stopped) {
  list.repeat(Nil, times: stops_that_catch_a_failed_eval)
  |> list.sized_chunk(into: stops_at_once)
  |> list.flat_map(fn(batch) {
    let reply = process.new_subject()
    let workers =
      list.map(batch, fn(_) {
        let worker =
          process.spawn_unlinked(fn() {
            process.send(reply, Ended(stop_one(coordinator:)))
            process.sleep_forever()
          })
        #(worker, process.monitor(worker))
      })
    let selector =
      list.fold(
        workers,
        process.new_selector() |> process.select(reply),
        fn(selector, worker) {
          process.select_specific_monitor(selector, worker.1, fn(_down) {
            Crashed
          })
        },
      )
    let stopped =
      list.map(batch, fn(_) {
        case process.selector_receive(selector, within: child_deadline_ms) {
          Ok(Ended(stopped)) -> stopped
          Ok(Crashed) -> panic as "a node's stop crashed its worker"
          Error(Nil) -> panic as "a node's stop ran past its deadline"
        }
      })
    list.each(workers, fn(worker) { process.kill(worker.0) })
    stopped
  })
}

pub fn a_clean_stop_writes_no_failed_to_eval_line_and_ends_with_status_0_test() -> Nil {
  use <- owned_test.run(child_deadline_ms * 2)
  // The child's stderr is read with its stdout, line by line. The expression
  // `-eval` runs is the one `release/start` runs; OTP's `init` reports an
  // expression that does not end normally as `Error! Failed to eval: ...`
  // (`init:start_it/1`), here because the entry point crashed after asking
  // `init` to stop.
  list.each(
    stop_many(coordinator: planted_shutdown.coordinator_lives),
    fn(stopped) {
      let #(lines, status) = stopped
      assert !list.any(lines, string.contains(_, "Failed to eval"))
        as "a clean stop wrote a Failed to eval line to stderr"
      assert status == 0 as "a clean stop ends the node with status 0"
    },
  )
}

pub fn a_sigterm_with_no_coordinator_logs_an_error_and_ends_the_node_with_status_1_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  // The contract is the one `shutdown.run` states: a SIGTERM that finds no
  // coordinator ends the node without the ordered stop, with status 1, and
  // says so as an error. The planted entry point runs on after the coordinator
  // has ended, so the SIGTERM finds none.
  let #(lines, status) =
    stop_one(coordinator: planted_shutdown.coordinator_gone)
  assert logged(lines:, level: "error", containing: [
    "shutdown coordinator was not running",
  ])
    as "a SIGTERM that found no coordinator did not log an error"
  assert status == 1
    as "a SIGTERM that found no coordinator did not end the node with status 1"
}

pub fn a_connection_that_will_not_drain_is_closed_at_the_deadline_and_the_flush_still_runs_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use child <- start(
    database,
    drain_ms: short_drain_ms,
    connection: planted_shutdown.second_never_closes,
    flush: planted_shutdown.flush_saves,
    coordinator: planted_shutdown.coordinator_lives,
  )
  let port = until_running(child)
  let first = connect_and_wait_for_registration(child:, port:, number: 1)
  let second = connect_and_wait_for_registration(child:, port:, number: 2)

  released_child.terminate(child)
  let assert Ok(#(lines, status)) = released_child.lines_until_exit(child)
    as "the child did not end after SIGTERM"

  assert list.contains(lines, planted_shutdown.connection_closed(1))
    as "the connection that closes when told did not close"
  assert list.contains(lines, planted_shutdown.connection_told(2))
    as "the connection that will not drain was not told to close"
  assert !list.contains(lines, planted_shutdown.connection_closed(2))
    as "the connection that will not drain closed itself"
  assert planted_shutdown.await_closed(first, close_wait_ms)
  assert planted_shutdown.await_closed(second, close_wait_ms)
    as "the connection that will not drain was not closed at the deadline"
  assert position(lines, planted_shutdown.connection_told(2))
    < position(lines, planted_shutdown.flush_started)
    as "the flush began before the connections were told to close"
  assert list.contains(lines, planted_shutdown.flush_written)
    as "the flush did not run after the connection was closed at the deadline"
  assert saved_values(database) == [planted_shutdown.saved_value]
  assert logged(lines:, level: "warning", containing: ["did not close"])
    as "a connection ended at the deadline was not logged as a warning"
  assert status == 0
    as "a connection that would not drain is an outside failure the server recovered from, so the stop is clean"
}

pub fn a_flush_that_fails_is_logged_as_an_error_and_the_shutdown_still_completes_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use child <- start(
    database,
    drain_ms: long_drain_ms,
    connection: planted_shutdown.all_close,
    flush: planted_shutdown.flush_fails,
    coordinator: planted_shutdown.coordinator_lives,
  )
  let port = until_running(child)
  let first = connect_and_wait_for_registration(child:, port:, number: 1)

  released_child.terminate(child)
  let assert Ok(#(lines, status)) = released_child.lines_until_exit(child)
    as "the child did not end after SIGTERM"

  assert logged(lines:, level: "error", containing: [
    planted_shutdown.saver_name,
    planted_shutdown.flush_failure_reason,
  ])
    as "the failed flush was not logged as an error naming the worker and why"
  assert list.contains(lines, planted_shutdown.connection_closed(1))
    as "the connection was not drained before the flush"
  assert planted_shutdown.await_closed(first, close_wait_ms)
  assert list.contains(lines, planted_shutdown.tree_stopped)
    as "the shutdown did not go on to stop the tree after a failed flush"
  assert saved_values(database) == [] as "a flush that failed wrote something"
  assert status != 0
    as "the stop with a failed flush ended the node with status 0"
}

pub fn the_exit_status_is_0_for_a_clean_stop_and_1_for_any_failed_step_test() -> Nil {
  use <- owned_test.run(5000)
  assert shutdown.exit_status(Stopped(failures: [])) == 0
  assert shutdown.exit_status(
      Stopped(failures: [FlushFailed(worker: "a worker", reason: "a reason")]),
    )
    == 1
  assert shutdown.exit_status(
      Stopped(failures: [
        shutdown.ListenerNotStopped(name: "a listener"),
        shutdown.FlushNotAnswered(worker: "a worker"),
      ]),
    )
    == 1
}

/// Whether the child wrote a line holding every one of `containing` as a log
/// line of `level`: `log.configure` writes each line on one line with its time,
/// its level, its text and its metadata, separated by spaces.
fn logged(
  lines lines: List(String),
  level level: String,
  containing parts: List(String),
) -> Bool {
  list.any(lines, fn(line) {
    string.contains(line, " " <> level <> " ")
    && list.all(parts, string.contains(line, _))
  })
}

pub fn a_coordinator_that_dies_takes_the_node_down_instead_of_being_restarted_empty_test() -> Nil {
  use <- owned_test.run(coordinator_loss_deadline_ms)
  use database <- template_database.run
  use child <- start(
    database,
    drain_ms: long_drain_ms,
    connection: planted_shutdown.all_close,
    flush: planted_shutdown.flush_saves,
    coordinator: planted_shutdown.coordinator_killed,
  )
  // A coordinator restarted by the supervisor holds no registration, so a
  // SIGTERM after it would flush nothing and still end the node with status
  // 0. The issue's one-node choice: a fault the tree cannot recover stops the
  // node, which the host restarts, so the node ends by itself, with a status
  // that is not 0.
  let assert Ok(#(lines, status)) = released_child.lines_until_exit(child)
    as "the node did not end after its coordinator was killed"
  assert list.contains(lines, planted_shutdown.coordinator_killed_line)
    as "the planted program did not kill the coordinator"
  assert status != 0
    as "the node ended with status 0 after its coordinator was killed"
  assert !list.any(lines, string.contains(_, released_child.server_running))
    as "the node went on to run after its coordinator was killed"
}

pub fn a_child_the_supervisor_restarts_does_not_run_the_shutdown_order_test() -> Nil {
  use <- owned_test.run(30_000)
  let settings = shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000)
  let flushes: Subject(Nil) = process.new_subject()
  let starts: Subject(Pid) = process.new_subject()
  let assert Ok(_) =
    server.supervisor()
    |> static_supervisor.add(shutdown.supervised(settings))
    |> static_supervisor.add(
      supervision.worker(fn() {
        planted_shutdown.saver(settings:, name: "a planted saver", flush: fn() {
          process.send(flushes, Nil)
          Ok(Nil)
        })
      })
      |> supervision.timeout(ms: 1000),
    )
    |> static_supervisor.add(
      supervision.worker(fn() { start_sibling(starts) })
      |> supervision.timeout(ms: 1000),
    )
    |> static_supervisor.start
    as "the planted tree did not start"
  let assert Ok(first) = process.receive(starts, 5000)
    as "the sibling did not start"
  process.kill(first)
  let assert Ok(second) = process.receive(starts, 5000)
    as "the supervisor did not restart the sibling"
  assert second != first

  // Only a stop flushes: the one flush there is, is the stop's own, so the
  // restart before it flushed nothing.
  shutdown.stop(settings)
  assert process.receive(settings.finished, 5000) == Ok(Stopped(failures: []))
    as "the stop did not end clean"
  assert process.receive(flushes, 0) == Ok(Nil)
    as "the stop did not flush the saving worker"
  assert process.receive(flushes, 0) == Error(Nil)
    as "the saving worker flushed more than once: the restart ran the shutdown order"
}

/// A child that reports its process as it starts, so the test sees a restart.
fn start_sibling(
  starts: Subject(Pid),
) -> Result(actor.Started(Subject(Nil)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    process.send(starts, process.self())
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, _message: Nil) { actor.continue(state) })
  |> actor.start
}
