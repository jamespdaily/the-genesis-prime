//// What a socket owner needs to hold the largest frame the client sends: a
//// frame of exactly `frame.size_limit` (131,070) bytes, which the size cap lets
//// through and the heap ceiling must not kill.
////
//// Run it with `gleam run -m genesis_prime/connection_frame_peak`. It lives in
//// `dev/` because Gleam compiles that directory with the project, so
//// `gleam build` keeps it compiling, while `gleam test` never runs it.
////
//// The frame arrives in about a millisecond, which a sampler cannot catch, so
//// the need is found by the runtime's own check instead: for each ceiling that
//// from `first_words` to `last_words` in steps of `step_words`, `runs` times a fresh
//// connection receives the largest frame and then a small frame under that
//// ceiling, and the ceiling is printed with how many runs the owner survived.
//// The smallest ceiling that every run survived is the memory the runtime
//// itself needs for the frame, collections and shared binaries counted.
////
//// The helpers are in `dev/connection_load_ffi.erl`.

import genesis_prime/connection/frame
import genesis_prime/connection/listener
import genesis_prime/connection/socket_owner.{Settings}
import genesis_prime/server
import gleam/bit_array
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/static_supervisor
import gleam/string

/// How many times each ceiling is tried.
const runs = 5

/// The ceilings tried, in words: from `first_words` to `last_words` in steps
/// of `step_words`. Every 4,096 words from 4,096 up to 53,248 were all killed
/// in an earlier run of 20 each, so the range starts there.
const first_words = 53_248

const step_words = 2048

const last_words = 65_536

/// How long a run waits for a frame to reach the handler, in milliseconds.
const deadline_ms = 1000

/// A client socket.
type Client

/// Prints the survival at each ceiling.
pub fn main() -> Nil {
  io.println(
    "largest frame of "
    <> int.to_string(frame.size_limit)
    <> " bytes, then a small frame: owners that survived, of "
    <> int.to_string(runs)
    <> " runs",
  )
  int.range(from: first_words, to: last_words + 1, with: Nil, run: fn(_, words) {
    case words % step_words {
      0 -> {
        let survived =
          list.repeat(Nil, runs)
          |> list.count(fn(_) { survives(words) })
        io.println(
          "ceiling "
          <> int.to_string(words)
          <> " words: "
          <> int.to_string(survived),
        )
      }
      _ -> Nil
    }
  })
}

/// Whether a fresh connection's owner, under the ceiling, handled the largest
/// frame and a small one after it.
fn survives(ceiling_words: Int) -> Bool {
  let frames = process.new_subject()
  let ports = process.new_subject()
  let handler = fn(_frame) { process.send(frames, Nil) }
  let defaults = listener.settings(port: 0, handler:)
  let settings =
    listener.Settings(
      ..defaults,
      connection_cap: 10,
      owner: Settings(..defaults.owner, heap_ceiling_words: ceiling_words),
      listening: fn(port) { process.send(ports, port) },
    )
  let assert Ok(started) =
    server.supervisor()
    |> static_supervisor.add(listener.supervised(settings))
    |> static_supervisor.start
    as "the server did not start"
  let assert Ok(port) = process.receive(ports, deadline_ms)
    as "the listener did not report its port"
  let assert Ok(client) = connect(port) as "the client did not connect"
  send_if_open(client, frame_of(frame.size_limit - frame.header_size))
  let largest_handled = process.receive(frames, deadline_ms) == Ok(Nil)
  send_if_open(client, frame_of(0))
  let small_handled = process.receive(frames, deadline_ms) == Ok(Nil)
  close(client)
  stop_tree(started.pid)
  largest_handled && small_handled
}

fn frame_of(body_bytes: Int) -> BitArray {
  let assert Ok(bytes) =
    frame.encode(
      message_id: 0x0244,
      body: bit_array.from_string(string.repeat("a", body_bytes)),
    )
    as "the frame is within the size limit"
  bytes
}

@external(erlang, "connection_load_ffi", "connect")
fn connect(port: Int) -> Result(Client, Nil)

@external(erlang, "connection_load_ffi", "send_if_open")
fn send_if_open(client: Client, bytes: BitArray) -> Nil

@external(erlang, "connection_load_ffi", "close")
fn close(client: Client) -> Nil

@external(erlang, "connection_load_ffi", "stop_tree")
fn stop_tree(supervisor: Pid) -> Nil
