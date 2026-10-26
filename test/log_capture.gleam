//// Captures the lines the server logs during a test, through one logger
//// handler for the whole run that sends each line to every test that is
//// capturing, as an event, so a test waits for the line it needs and never
//// for a fixed time. The handler sees every line of the node, including those
//// of tests running beside this one, so a test asks for the lines of the
//// process it started. A test never adds or removes a handler, because
//// logger's handler changes can write back a level another process has just
//// set, which the test that turns debug on would lose.
////
//// Logger's level belongs to the whole node. The first `start` of a run
//// brings it to info and installs the handler, so no test depends on OTP's
//// default level; the one test that turns debug on and off is `log_test`'s.

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

/// A running capture, ended by `stop`.
pub opaque type Capture {
  Capture(events: Subject(Event))
}

/// Starts capturing every line logged after the call, delivered to the process
/// that calls it.
pub fn start() -> Capture {
  database_support.once("log_capture", fn() {
    log.configure(debug: False)
    install()
  })
  let events = process.new_subject()
  receive_from(events)
  Capture(events:)
}

/// Stops capturing. A capture whose process has ended stops by itself.
pub fn stop(capture: Capture) -> Nil {
  stop_receiving(capture.events)
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

/// The next line, from any process, for which `matching` is true, waiting up
/// to `within` milliseconds for it. For a test that does not know the process
/// that writes the line it needs, such as a connection's owner over TCP; a
/// line that does not match is skipped.
pub fn next_matching(
  capture capture: Capture,
  within within: Int,
  matching matching: fn(Event) -> Bool,
) -> Result(Event, Nil) {
  case process.receive(capture.events, within) {
    Ok(event) ->
      case matching(event) {
        True -> Ok(event)
        False -> next_matching(capture:, within:, matching:)
      }
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "log_capture_ffi", "install")
fn install() -> Nil

@external(erlang, "log_capture_ffi", "receive_from")
fn receive_from(events: Subject(Event)) -> Nil

@external(erlang, "log_capture_ffi", "stop_receiving")
fn stop_receiving(events: Subject(Event)) -> Nil
