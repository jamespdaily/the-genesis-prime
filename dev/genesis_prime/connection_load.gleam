//// What a socket owner costs under load, and how big it gets: the measures that
//// choose its flow control, its heap ceiling and the connection cap.
////
//// Run it with `gleam run -m genesis_prime/connection_load` on a machine with
//// nothing else heavy running, from a shell that allows 4,096 open files, with
//// `ERL_FLAGS="+sbwt none +sbwtdcpu none +sbwtdio none"` so idle schedulers do
//// not spin and count as CPU time. It lives in `dev/` because Gleam compiles
//// that directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it.
////
//// The server is this node: one listener under the real top supervisor's
//// settings, with a handler that only counts frames. The clients are in a peer
//// node (OTP's `peer` module), so their cost is not in the server's CPU time:
//// `connections` clients, each sending `frames_per_second` frames of
//// `frame_bytes` bytes a second, from a random moment in its first period.
//// The client's dash rate is one movement frame (message 0x637) per game
//// update, and the client's `video.framerateMax` is 120 by default (15 to 180);
//// the size of a movement frame is not read from the client, so the frame is
//// `frame_bytes` bytes, and its cost per frame is read, not copied, so it
//// barely depends on that size.
////
//// A run warms up for `warm_up_seconds`, then measures for
//// `window_seconds`: CPU time of this node's runtime (`statistics(runtime)`,
//// all threads, system time included) divided by the frames the handlers
//// counted, the sum of the owners' reductions divided by the same, and a
//// sampler that reads every owner each `sample_interval_ms` for its longest
//// mailbox and its largest heap, `total_heap_size` plus the shared binaries it
//// holds, in words. Each variant runs `rounds` times, rotated so no variant
//// always runs first, and the median of each measure is printed.
////
//// Variants: `once` is `{active, once}`, `active 8` and `active 32` are
//// `{active, N}`, and `once, planted` is `once` with a handler that burns a
//// fixed extra time per frame (under a microsecond), to show the harness
//// sees a change of the size the choosing rule cares about.
////
//// Both Erlang helpers are in `dev/connection_load_ffi.erl`.

import genesis_prime/connection/listener
import genesis_prime/connection/socket
import genesis_prime/connection/socket_owner.{Settings}
import genesis_prime/server
import genesis_prime/shutdown
import gleam/erlang/process.{type Pid, type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/static_supervisor
import gleam/result
import gleam/string

/// How many clients connect to the listener.
const connections = 800

/// How many frames each client sends a second: the client's default
/// `video.framerateMax`, one movement frame per game update while dashing.
const frames_per_second = 120

/// The size of each frame, header included.
const frame_bytes = 100

/// How long a run runs before it measures, in seconds.
const warm_up_seconds = 3

/// How long a run measures, in seconds.
const window_seconds = 10

/// How many times each variant runs.
const rounds = 5

/// The time between two readings of the owners, in milliseconds.
const sample_interval_ms = 100

/// The heap ceiling the server's owners run with in the benchmark, in words:
/// high enough never to kill, so the run reports the peak the owners reach.
const unlimited_heap_words = 67_108_864

/// A node of the Erlang distribution, a peer node started from this one, and
/// the clients it runs.
type Peer

type Clients

type Node

type Counter

/// One variant of the benchmark.
type Variant {
  Variant(name: String, flow_control: socket.FlowControl, planted_work: Bool)
}

/// What one run measured.
type Measure {
  Measure(
    connected: Int,
    frames_per_second: Float,
    cores: Float,
    microseconds_per_frame: Float,
    reductions_per_frame: Float,
    peak_mailbox: Int,
    peak_heap_words: Int,
  )
}

/// The longest mailbox, the largest heap in words and the sum of reductions
/// read from the owners at one moment.
type Reading =
  #(Int, Int, Int)

/// Runs every variant `rounds` times and prints the medians.
pub fn main() -> Nil {
  let assert Ok(_node) = start_distribution()
    as "this node could not become distributed; the reason is printed above"
  let assert Ok(peer) = start_peer() as "the peer node did not start"
  let variants = [
    Variant("once", socket.ActiveOnce, False),
    Variant("active 8", socket.ActiveCount(reads: 8), False),
    Variant("active 32", socket.ActiveCount(reads: 32), False),
    Variant("once, planted", socket.ActiveOnce, True),
  ]
  io.println(
    "connection load: "
    <> int.to_string(connections)
    <> " connections, "
    <> int.to_string(frames_per_second)
    <> " frames a second each, "
    <> int.to_string(frame_bytes)
    <> " bytes a frame, "
    <> int.to_string(window_seconds)
    <> " s measured, median of "
    <> int.to_string(rounds)
    <> " rounds",
  )
  let results =
    int.range(from: 0, to: rounds, with: [], run: list.prepend)
    |> list.reverse
    |> list.flat_map(fn(round) {
      rotate(variants, round)
      |> list.map(fn(variant) {
        io.println("round " <> int.to_string(round + 1) <> ": " <> variant.name)
        let measure = run(peer, variant)
        io.println("  " <> describe(measure))
        #(variant.name, measure)
      })
    })
  stop_peer(peer)
  stop_distribution()
  io.println("")
  io.println(
    "variant: frames/s, cores (server CPU), microseconds CPU per frame, reductions per frame, longest mailbox, largest heap in words (median; for the two peaks the largest of the rounds)",
  )
  list.each(variants, fn(variant) {
    let measures =
      list.filter_map(results, fn(result) {
        case result.0 == variant.name {
          True -> Ok(result.1)
          False -> Error(Nil)
        }
      })
    io.println(variant.name <> ": " <> summarise(measures))
  })
}

fn rotate(variants: List(Variant), round: Int) -> List(Variant) {
  let #(front, back) = list.split(variants, round % list.length(variants))
  list.append(back, front)
}

/// One run of one variant: the server, the clients, the warm-up and the
/// window. The server and the clients stop at the end.
fn run(peer: Peer, variant: Variant) -> Measure {
  let counter = new_counter()
  let coordinator =
    shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000)
  let handler = fn(_frame) {
    increment(counter)
    case variant.planted_work {
      True -> burn()
      False -> Nil
    }
  }
  let defaults = listener.settings(port: 0, handler:, shutdown: coordinator)
  let ports = process.new_subject()
  let settings =
    listener.Settings(
      ..defaults,
      connection_cap: connections + 200,
      owner: Settings(
        ..defaults.owner,
        flow_control: variant.flow_control,
        heap_ceiling_words: unlimited_heap_words,
      ),
      listening: fn(port) { process.send(ports, port) },
    )
  let assert Ok(started) =
    server.supervisor()
    |> static_supervisor.add(shutdown.supervised(coordinator))
    |> static_supervisor.add(listener.supervised(settings))
    |> static_supervisor.start
    as "the server did not start"
  let assert Ok(port) = process.receive(ports, 5000)
    as "the listener did not report its port"
  let assert Ok(clients) =
    start_clients(peer, port, connections, frames_per_second, frame_bytes)
    as "the clients did not start"
  process.sleep(warm_up_seconds * 1000)
  let owners = owners(started.pid)
  let sampler = start_sampler(owners)
  let #(_, _, reductions_before) = read_owners(owners)
  let frames_before = counter_value(counter)
  let cpu_before = cpu_milliseconds()
  let wall_before = wall_milliseconds()
  process.sleep(window_seconds * 1000)
  let cpu = cpu_milliseconds() - cpu_before
  let wall = wall_milliseconds() - wall_before
  let frames = counter_value(counter) - frames_before
  let #(_, _, reductions_after) = read_owners(owners)
  let #(peak_mailbox, peak_heap_words) = stop_sampler(sampler)
  stop_clients(clients)
  stop_tree(started.pid)
  let frames_float = int.to_float(frames)
  Measure(
    connected: connected(clients),
    frames_per_second: frames_float /. { int.to_float(wall) /. 1000.0 },
    cores: int.to_float(cpu) /. int.to_float(wall),
    microseconds_per_frame: int.to_float(cpu) *. 1000.0 /. frames_float,
    reductions_per_frame: int.to_float(reductions_after - reductions_before)
      /. frames_float,
    peak_mailbox:,
    peak_heap_words:,
  )
}

/// A sampler: a process that reads every owner each `sample_interval_ms` and
/// keeps the longest mailbox and the largest heap it saw.
type Sampler =
  Subject(Stop)

type Stop {
  Stop(reply_with: Subject(#(Int, Int)))
}

fn start_sampler(owners: List(Pid)) -> Sampler {
  let ready = process.new_subject()
  process.spawn(fn() {
    let stops = process.new_subject()
    process.send(ready, stops)
    sample(owners:, stops:, mailbox: 0, heap: 0)
  })
  let assert Ok(stops) = process.receive(ready, 5000)
    as "the sampler did not start"
  stops
}

fn sample(
  owners owners: List(Pid),
  stops stops: Subject(Stop),
  mailbox mailbox: Int,
  heap heap: Int,
) -> Nil {
  case process.receive(stops, sample_interval_ms) {
    Ok(Stop(reply_with:)) -> process.send(reply_with, #(mailbox, heap))
    Error(Nil) -> {
      let #(longest, largest, _) = read_owners(owners)
      sample(
        owners:,
        stops:,
        mailbox: int.max(mailbox, longest),
        heap: int.max(heap, largest),
      )
    }
  }
}

fn stop_sampler(sampler: Sampler) -> #(Int, Int) {
  let reply = process.new_subject()
  process.send(sampler, Stop(reply_with: reply))
  let assert Ok(peaks) = process.receive(reply, 5000)
    as "the sampler did not stop"
  peaks
}

fn describe(measure: Measure) -> String {
  string.join(
    [
      int.to_string(measure.connected) <> " connected",
      round_to(measure.frames_per_second, 0) <> " frames/s",
      round_to(measure.cores, 3) <> " cores",
      round_to(measure.microseconds_per_frame, 3) <> " us/frame",
      round_to(measure.reductions_per_frame, 1) <> " reductions/frame",
      "mailbox " <> int.to_string(measure.peak_mailbox),
      "heap " <> int.to_string(measure.peak_heap_words) <> " words",
    ],
    ", ",
  )
}

/// The median of each measure over the runs; the two peaks are the largest.
fn summarise(measures: List(Measure)) -> String {
  let median_of = fn(value: fn(Measure) -> Float) {
    let sorted = list.map(measures, value) |> list.sort(float.compare)
    let middle = list.length(sorted) / 2
    list.drop(sorted, middle) |> list.first |> result.unwrap(0.0)
  }
  let largest = fn(value: fn(Measure) -> Int) {
    list.map(measures, value) |> list.fold(0, int.max)
  }
  string.join(
    [
      round_to(median_of(fn(m) { m.frames_per_second }), 0) <> " frames/s",
      round_to(median_of(fn(m) { m.cores }), 3) <> " cores",
      round_to(median_of(fn(m) { m.microseconds_per_frame }), 3) <> " us/frame",
      round_to(median_of(fn(m) { m.reductions_per_frame }), 1)
        <> " reductions/frame",
      "mailbox " <> int.to_string(largest(fn(m) { m.peak_mailbox })),
      "heap " <> int.to_string(largest(fn(m) { m.peak_heap_words })) <> " words",
    ],
    ", ",
  )
}

fn round_to(value: Float, places: Int) -> String {
  float.to_string(float.to_precision(value, places))
}

@external(erlang, "connection_load_ffi", "start_distribution")
fn start_distribution() -> Result(Node, Nil)

@external(erlang, "connection_load_ffi", "stop_distribution")
fn stop_distribution() -> Nil

@external(erlang, "connection_load_ffi", "start_peer")
fn start_peer() -> Result(Peer, Nil)

@external(erlang, "connection_load_ffi", "stop_peer")
fn stop_peer(peer: Peer) -> Nil

@external(erlang, "connection_load_ffi", "start_clients")
fn start_clients(
  peer: Peer,
  port: Int,
  count: Int,
  frames_per_second: Int,
  frame_bytes: Int,
) -> Result(Clients, Nil)

@external(erlang, "connection_load_ffi", "stop_clients")
fn stop_clients(clients: Clients) -> Nil

@external(erlang, "connection_load_ffi", "stop_tree")
fn stop_tree(supervisor: Pid) -> Nil

@external(erlang, "connection_load_ffi", "connected")
fn connected(clients: Clients) -> Int

@external(erlang, "connection_load_ffi", "new_counter")
fn new_counter() -> Counter

@external(erlang, "connection_load_ffi", "increment")
fn increment(counter: Counter) -> Nil

@external(erlang, "connection_load_ffi", "counter_value")
fn counter_value(counter: Counter) -> Int

@external(erlang, "connection_load_ffi", "cpu_milliseconds")
fn cpu_milliseconds() -> Int

@external(erlang, "connection_load_ffi", "wall_milliseconds")
fn wall_milliseconds() -> Int

@external(erlang, "connection_load_ffi", "owners")
fn owners(top: Pid) -> List(Pid)

@external(erlang, "connection_load_ffi", "read_owners")
fn read_owners(owners: List(Pid)) -> Reading

@external(erlang, "connection_load_ffi", "burn")
fn burn() -> Nil
