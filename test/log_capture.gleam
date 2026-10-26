//// Captures the lines the server logs during a test, through a logger handler
//// that sends each line to the test as an event, so a test waits for the
//// line it needs and never for a fixed time. The handler sees every line of
//// the node, including those of tests running beside this one, so a test asks
//// for the lines of the process it started.
////
//// Logger's level belongs to the whole node. `start` brings it to info, once
//// per run, so no test depends on OTP's default level; the one test that
//// turns debug on and off is `log_test`'s.

import database_support
import genesis_prime/telemetry/log
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}

/// A line that was logged: its level as logger names it (`error`, `warning`,
/// `info` or `debug`), its text, the process that wrote it and its metadata
/// by key. Only the metadata a test can read is kept: whole numbers, floats,
/// texts and maps of them. `formatted` is the line the node's default handler
/// writes for it, made with the handler's own formatter.
pub type Event {
  Event(
    level: String,
    text: String,
    from: Pid,
    metadata: Dict(String, Field),
    formatted: String,
  )
}

/// One metadata value.
pub type Field {
  Whole(Int)
  Fraction(Float)
  Text(String)
  Fields(Dict(String, Field))
}

type Handle

/// A running capture, ended by `stop`.
pub opaque type Capture {
  Capture(handle: Handle, events: Subject(Event))
}

/// Starts capturing every line logged after the call, delivered to the process
/// that calls it.
pub fn start() -> Capture {
  database_support.once("log_level_info", fn() { log.configure(debug: False) })
  let events = process.new_subject()
  Capture(handle: add(events), events:)
}

/// Stops capturing.
pub fn stop(capture: Capture) -> Nil {
  remove(capture.handle)
}

/// The next line the process `from` wrote, waiting up to `within`
/// milliseconds for it, in the order it wrote them. A line another process
/// wrote is skipped.
pub fn next_from(
  capture capture: Capture,
  from from: Pid,
  within within: Int,
) -> Result(Event, Nil) {
  case process.receive(capture.events, within) {
    Ok(event) if event.from == from -> Ok(event)
    Ok(_) -> next_from(capture:, from:, within:)
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "log_capture_ffi", "add")
fn add(events: Subject(Event)) -> Handle

@external(erlang, "log_capture_ffi", "remove")
fn remove(handle: Handle) -> Nil
