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
////   started and the clock stops when `genesis_prime/server.start()` has
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

import genesis_prime/server
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}

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
  todo as "body in the build commit"
}

/// A world with a fresh worker name and fresh start subjects.
fn new_world() -> World {
  todo as "body in the build commit"
}

/// Starts a top supervisor with the real top supervisor's settings
/// (`server.supervisor()`) and the planted world subtree as its one child: a
/// supervisor, with a worker that answers pings.
fn start_node_with_world(
  world: World,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  todo as "body in the build commit"
}

/// Starts the planted world subtree's supervisor and reports its pid on
/// `world.supervisors`.
fn start_world_subtree(
  world: World,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  todo as "body in the build commit"
}

/// Starts the planted world subtree's worker under `world.worker`, answering
/// each `Ping` with a `Pong`, and reports its pid on `world.workers`.
fn start_world_worker(
  world: World,
) -> Result(actor.Started(Subject(Ping)), actor.StartError) {
  todo as "body in the build commit"
}

/// Times, in nanoseconds, killing the planted world subtree's supervisor until
/// the replacement worker answers a ping: the clock starts at the kill and
/// stops at the first `Pong` from the new worker.
fn time_restart_in_node(world: World) -> Int {
  todo as "body in the build commit"
}

/// The `restart_runs` times of restarting the planted world subtree in a
/// running node, in nanoseconds.
fn restart_in_node_runs() -> List(Int) {
  todo as "body in the build commit"
}

/// Times, in nanoseconds, starting a fresh peer node with this project's code
/// path, until `genesis_prime/server.start()` has returned on it and the node
/// answers a call. The node is stopped after the clock does.
fn time_fresh_node() -> Int {
  todo as "body in the build commit"
}

/// The `fresh_node_runs` times of starting a fresh peer node, in nanoseconds.
fn fresh_node_runs_times() -> List(Int) {
  todo as "body in the build commit"
}

/// Times each of `count` round trips, in nanoseconds, of a `Ping` and its
/// `Pong` between this process and a worker process in this node.
fn round_trips_in_node(count: Int) -> List(Int) {
  todo as "body in the build commit"
}

/// Times each of `count` round trips, in nanoseconds, of a `Ping` and its
/// `Pong` between this process and a worker process in `peer`'s node.
fn round_trips_to_peer(peer: Peer, count: Int) -> List(Int) {
  todo as "body in the build commit"
}

/// Waits for a `Ping`, answers it, and waits again, in the node it runs in. It
/// first sends its own subject to `ready`, so the process that started it can
/// ping it.
fn serve_pings(ready: Subject(Subject(Ping))) -> Nil {
  todo as "body in the build commit"
}

/// The median, smallest and largest of `nanoseconds`, which are not empty, in
/// microseconds.
fn summarise(nanoseconds: List(Int)) -> Summary {
  todo as "body in the build commit"
}

/// Prints a measure's name and its summary on one line.
fn print_summary(name: String, summary: Summary) -> Nil {
  todo as "body in the build commit"
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

/// Stops a peer node and waits for it to be gone.
@external(erlang, "node_cost_ffi", "stop_peer")
fn stop_peer(peer: Peer) -> Nil

/// Calls `genesis_prime/server.start()` on the peer, in a process that stays
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
