//// Which side a connection's closing line names (genesis_prime/connection/shell,
//// genesis_prime/wire_recording): the side that began the end, not the input
//// the step that stops takes. Expected values come from these places.
//// - The shell's contract in its doc comment: the closing line names the client
////   when the step that stopped took the socket's close, the server otherwise;
////   and a rule that asks before it stops, as the game rule does to save a
////   player's place, stops in the step of the ask's answer, so the input that
////   began the end is the one that says who ended it.
//// - The listener a client connects to, the recording its connection writes and
////   the wire recording's own reader.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import genesis_prime/connection/script
import genesis_prime/wire_recording.{Client, Recording, Server}
import gleam/erlang/process
import gleam/option.{None, Some}
import leaving_rule
import mug
import owned_test
import recording_support

/// A listener whose connections run the leaving rule, recorded in `folder`,
/// with a directory that answers every ask as a process not running.
fn started(folder: String) -> ask_support.Server {
  ask_support.start_scripted(
    rule: leaving_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 2000,
    wire_recorder: Some(recording_support.wire_recorder(folder)),
    scripts: script.operating_system,
    registry: None,
    locate: fn(_address) { Error(Nil) },
    with: fn(builder) { builder },
  )
}

pub fn a_close_by_the_client_that_asks_before_it_stops_is_recorded_as_the_clients_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let server = started(folder)
  let client = ask_support.connect(server)
  assert ask_support.read_bytes(client:, bytes: 1) == <<1>>
    as "the shell took the connection: the rule wrote its byte"
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(watched)
  let assert Ok(Recording(closing: Some(closing), ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole"
  assert closing.by == Client
    as "the client closed it: the step that stopped took the ask's answer, but the end began with the socket's close"
  ask_support.stop(server)
}

pub fn a_stop_of_the_server_that_asks_before_it_stops_is_recorded_as_the_servers_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let server = started(folder)
  let client = ask_support.connect(server)
  assert ask_support.read_bytes(client:, bytes: 1) == <<1>>
    as "the shell took the connection: the rule wrote its byte"
  ask_support.stop(server)
  let assert Ok(Recording(closing: Some(closing), ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole: the rule stopped in time"
  assert closing.by == Server as "the server's stop began the end"
}
