//// What running the services in one node or in several costs: how long a
//// failed part takes to come back, and what a message costs when it crosses
//// from one node to another.
////
//// Run it with `gleam run -m genesis_prime/node_cost` on a machine with
//// nothing else heavy running. It lives in `dev/` because Gleam compiles that
//// directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it. The planted services are its own, because a
//// `dev/` module cannot import a `test/` one.
////
//// Two measures, each in microseconds:
////
//// - Restart cost: `restart_runs` times, the planted world subtree inside a
////   running node is killed and the clock stops when its replacement answers
////   a ping; against `fresh_node_runs` times, a fresh peer node of this
////   project (OTP's `peer` module, started with this project's code path) is
////   started and the clock stops when `genesis_prime/server.start` has
////   returned on it and the node answers a call. The median, the smallest and
////   the largest are printed for each.
//// - Message round trip: one small message and its reply, `round_trips` times
////   between two processes in this node, against `round_trips` times between
////   a process in this node and one in a peer node on this machine; the
////   median, the smallest and the largest of each.
////
//// The peer measures need this node to be distributed. The benchmark starts
//// distribution under a name made for the run and stops it at the end; the
//// peer nodes are stopped as soon as each measure is taken. Both are done
//// through the one Erlang file `dev/node_cost_ffi.erl`.

import genesis_prime/database/pool
import genesis_prime/game/service as game_service
import genesis_prime/login/service
import genesis_prime/message/bit_stream
import genesis_prime/server
import genesis_prime/shutdown
import genesis_prime/telemetry/snapshot
import genesis_prime/topology/trial
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import gleam/result
import gleam/string

/// How many times the restart of the planted world subtree is timed.
const restart_runs = 10

/// How many times a fresh peer node is started and timed.
const fresh_node_runs = 10

/// How many round trips each of the two message measures times.
const round_trips = 10_000

/// How long a wait for a start, a reply or a peer node may take, in
/// milliseconds, before the benchmark stops with a message instead of hanging.
const deadline_ms = 30_000

/// A node of the Erlang distribution, this one or a peer.
type Node

/// A peer node started from this one, and the handle that stops it.
type Peer

/// The planted worker's request: answer on `reply`.
type Ping {
  Ping(reply: Subject(Pong))
}

/// The planted worker's answer.
type Pong {
  Pong
}

/// The planted world subtree's wiring: the name its worker registers, where
/// each start of its supervisor and of its worker is reported, so a run waits
/// for the replacement by receiving instead of sleeping. The subjects belong
/// to the process that made them: the benchmark's.
type World {
  World(worker: Name(Ping), supervisors: Subject(Pid), workers: Subject(Pid))
}

/// The times of a measure's runs, in microseconds.
type Summary {
  Summary(
    median_microseconds: Float,
    minimum_microseconds: Float,
    maximum_microseconds: Float,
  )
}

/// Runs the benchmark and prints the restart cost of the world subtree in
/// this node against the start of a fresh node, and the round trip within this
/// node against the round trip to a peer node.
pub fn main() -> Nil {
  io.println(
    "node cost, in microseconds: median (smallest to largest) of the runs",
  )
  print_summary(
    "restart of the world subtree in this node, "
      <> int.to_string(restart_runs)
      <> " runs",
    summarise(restart_in_node_runs()),
  )
  let assert Ok(_node) = start_distribution()
    as "this node could not become distributed; the reason is printed above"
  print_summary(
    "start of a fresh node to its first answer, "
      <> int.to_string(fresh_node_runs)
      <> " runs",
    summarise(fresh_node_runs_times()),
  )
  print_summary(
    "round trip between two processes in this node, "
      <> int.to_string(round_trips)
      <> " runs",
    summarise(round_trips_in_node(round_trips)),
  )
  let assert Ok(peer) = start_peer() as "the peer node did not start"
  let to_peer = round_trips_to_peer(peer, round_trips)
  stop_peer(peer)
  print_summary(
    "round trip to a process in a peer node, "
      <> int.to_string(round_trips)
      <> " runs",
    summarise(to_peer),
  )
  stop_distribution()
}

/// A world with a fresh worker name and fresh start subjects.
fn new_world() -> World {
  World(
    worker: process.new_name("node_cost_world_worker"),
    supervisors: process.new_subject(),
    workers: process.new_subject(),
  )
}

/// Starts a top supervisor with the real top supervisor's settings
/// (`server.supervisor()`) and the planted world subtree as its one child: a
/// supervisor, with a worker that answers pings.
fn start_node_with_world(
  world: World,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  server.supervisor()
  |> static_supervisor.add(
    supervision.supervisor(fn() { start_world_subtree(world) }),
  )
  |> static_supervisor.start
}

/// Starts the planted world subtree's supervisor and reports its pid on
/// `world.supervisors`.
fn start_world_subtree(
  world: World,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  use subtree <- result.map(
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(
      supervision.worker(fn() { start_world_worker(world) }),
    )
    |> static_supervisor.start,
  )
  process.send(world.supervisors, subtree.pid)
  subtree
}

/// Starts the planted world subtree's worker under `world.worker`, answering
/// each `Ping` with a `Pong`, and reports its pid on `world.workers`.
fn start_world_worker(
  world: World,
) -> Result(actor.Started(Subject(Ping)), actor.StartError) {
  actor.new_with_initialiser(deadline_ms, fn(subject) {
    process.send(world.workers, process.self())
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, message) {
    let Ping(reply:) = message
    process.send(reply, Pong)
    actor.continue(state)
  })
  |> actor.named(world.worker)
  |> actor.start
}

/// Times, in nanoseconds, killing the planted world subtree's supervisor until
/// the replacement worker answers a ping: the clock starts at the kill and
/// stops at the first `Pong` from the new worker.
fn time_restart_in_node(world: World) -> Int {
  let assert Ok(node) = start_node_with_world(world)
    as "the planted node did not start"
  let assert Ok(subtree) = process.receive(world.supervisors, deadline_ms)
    as "the world subtree did not report its start"
  let assert Ok(first_worker) = process.receive(world.workers, deadline_ms)
    as "the world worker did not report its start"
  let started = monotonic_nanoseconds()
  process.kill(subtree)
  let assert Ok(replacement) = process.receive(world.workers, deadline_ms)
    as "the world worker was not replaced"
  let Pong =
    process.call(process.named_subject(world.worker), deadline_ms, Ping)
  let elapsed = monotonic_nanoseconds() - started
  assert replacement != first_worker as "the world worker was not replaced"
  stop_node(node.pid)
  elapsed
}

/// Stops a supervisor started by this process and waits until it is gone.
fn stop_node(node: Pid) -> Nil {
  let monitor = process.monitor(node)
  process.unlink(node)
  process.send_exit(node)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { Nil })
    |> process.selector_receive(within: deadline_ms)
    as "the planted node did not stop"
  Nil
}

/// The `restart_runs` times of restarting the planted world subtree in a
/// running node, in nanoseconds.
fn restart_in_node_runs() -> List(Int) {
  repeat(restart_runs, fn() { time_restart_in_node(new_world()) })
}

/// Times, in nanoseconds, starting a fresh peer node with this project's code
/// path, until `genesis_prime/server.start` has returned on it and the node
/// answers a call. The node is stopped after the clock does.
fn time_fresh_node() -> Int {
  let started = monotonic_nanoseconds()
  let assert Ok(peer) = start_peer() as "the peer node did not start"
  let assert Ok(Nil) = start_server_on_peer(peer)
    as "the server did not start on the peer"
  let _answering_node = ask_node_name(peer)
  let elapsed = monotonic_nanoseconds() - started
  stop_peer(peer)
  elapsed
}

/// The `fresh_node_runs` times of starting a fresh peer node, in nanoseconds.
fn fresh_node_runs_times() -> List(Int) {
  repeat(fresh_node_runs, time_fresh_node)
}

/// Times each of `count` round trips, in nanoseconds, of a `Ping` and its
/// `Pong` between this process and a worker process in this node.
fn round_trips_in_node(count: Int) -> List(Int) {
  let ready = process.new_subject()
  let worker = process.spawn_unlinked(fn() { serve_pings(ready) })
  let assert Ok(target) = process.receive(ready, deadline_ms)
    as "the ping worker did not start"
  let times = time_round_trips(target, count)
  process.kill(worker)
  times
}

/// Times each of `count` round trips, in nanoseconds, of a `Ping` and its
/// `Pong` between this process and a worker process in `peer`'s node.
fn round_trips_to_peer(peer: Peer, count: Int) -> List(Int) {
  let ready = process.new_subject()
  let _worker = spawn_on(peer_node(peer), fn() { serve_pings(ready) })
  let assert Ok(target) = process.receive(ready, deadline_ms)
    as "the ping worker did not start on the peer"
  time_round_trips(target, count)
}

/// Times `count` round trips to `target`, one after the other, with one reply
/// subject, so both measures cost the same on this side.
fn time_round_trips(target: Subject(Ping), count: Int) -> List(Int) {
  let reply = process.new_subject()
  repeat(count, fn() {
    let started = monotonic_nanoseconds()
    process.send(target, Ping(reply:))
    let assert Ok(Pong) = process.receive(reply, deadline_ms)
      as "a ping was not answered"
    monotonic_nanoseconds() - started
  })
}

/// Runs `work` `times` times, one after the other, and keeps each result.
fn repeat(times: Int, work: fn() -> a) -> List(a) {
  int.range(0, times, [], fn(taken, _run) { [work(), ..taken] })
}

/// Waits for a `Ping`, answers it, and waits again, in the node it runs in. It
/// first sends its own subject to `ready`, so the process that started it can
/// ping it.
fn serve_pings(ready: Subject(Subject(Ping))) -> Nil {
  let mine = process.new_subject()
  process.send(ready, mine)
  serve_forever(mine)
}

fn serve_forever(mine: Subject(Ping)) -> Nil {
  let Ping(reply:) = process.receive_forever(mine)
  process.send(reply, Pong)
  serve_forever(mine)
}

/// The median, smallest and largest of `nanoseconds`, which are not empty, in
/// microseconds.
fn summarise(nanoseconds: List(Int)) -> Summary {
  let microseconds =
    list.map(nanoseconds, fn(nanosecond) { int.to_float(nanosecond) /. 1000.0 })
  let assert Ok(smallest) = list.reduce(microseconds, float.min)
    as "no runs were timed"
  let assert Ok(largest) = list.reduce(microseconds, float.max)
    as "no runs were timed"
  Summary(
    median_microseconds: trial.median(microseconds),
    minimum_microseconds: smallest,
    maximum_microseconds: largest,
  )
}

/// Prints a measure's name and its summary on one line.
fn print_summary(name: String, summary: Summary) -> Nil {
  io.println(
    string.pad_end(name, 64, " ")
    <> trial.two_places(summary.median_microseconds)
    <> " us ("
    <> trial.two_places(summary.minimum_microseconds)
    <> " to "
    <> trial.two_places(summary.maximum_microseconds)
    <> ")",
  )
}

/// The monotonic clock, in nanoseconds. It can be negative, so 0 never means
/// none.
@external(erlang, "node_cost_ffi", "monotonic_nanoseconds")
fn monotonic_nanoseconds() -> Int

/// Makes this node distributed under a name made for this run. Error when the
/// runtime refuses, for instance because the port mapper (`epmd`) is not
/// running and could not be started.
@external(erlang, "node_cost_ffi", "start_distribution")
fn start_distribution() -> Result(Node, Nil)

/// Stops this node's distribution.
@external(erlang, "node_cost_ffi", "stop_distribution")
fn stop_distribution() -> Nil

/// Starts a peer node on this machine with this project's code path and waits
/// for it to boot. Error when it does not boot.
@external(erlang, "node_cost_ffi", "start_peer")
fn start_peer() -> Result(Peer, Nil)

/// Starts the server's top supervisor on the node that runs this, with a pool
/// of one connection to the Postgres of PGHOST's usual address and no game
/// table to load. The pool opens its connection in the background, so the
/// start does not wait for Postgres and the measure is of the tree. Called on the peer by
/// `dev/node_cost_ffi.erl`.
pub fn start_server() -> Result(Nil, Nil) {
  let settings =
    pool.Settings(
      name: process.new_name("node_cost_pool"),
      host: "127.0.0.1",
      port: 5432,
      database: "postgres",
      user: "postgres",
      password: option.None,
      pool_size: 1,
    )
  let snapshot_settings = snapshot.settings(process.new_name("snapshot"))
  let tree =
    server.Settings(
      pool: settings,
      tables: server.TableSettings(
        key: reference.new(),
        folder: "",
        entries: [],
        requirements: [],
      ),
      shutdown: shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000),
      snapshot: snapshot_settings,
      login: service.settings(
        sts_port: 0,
        auth_port: 0,
        game_server: bit_stream.Endpoint(address: 0x7F000001, port: 0),
        realm_name: "node_cost",
        expected_files_digest: option.None,
      ),
      game: game_service.settings(
        port: 0,
        realm_id: 1,
        start: fn(_row) { Error(Nil) },
        snapshot: snapshot_settings.name,
      ),
    )
  case server.start(tree) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

/// Stops a peer node and waits for it to be gone.
@external(erlang, "node_cost_ffi", "stop_peer")
fn stop_peer(peer: Peer) -> Nil

/// Calls `start_server` on the peer, in a process that stays
/// alive, so the supervisor it starts stays up. Error when the start fails.
@external(erlang, "node_cost_ffi", "start_server_on_peer")
fn start_server_on_peer(peer: Peer) -> Result(Nil, Nil)

/// The name of the node the peer answers a call from: the call is a round trip
/// to the peer's runtime, and its answer is how a run knows the peer is up.
@external(erlang, "node_cost_ffi", "ask_node_name")
fn ask_node_name(peer: Peer) -> Node

/// The node a peer runs as.
@external(erlang, "node_cost_ffi", "peer_node")
fn peer_node(peer: Peer) -> Node

/// Runs `body` in a new process on `node`; the process is not linked to the
/// caller.
@external(erlang, "node_cost_ffi", "spawn_on")
fn spawn_on(node: Node, body: fn() -> Nil) -> Pid
