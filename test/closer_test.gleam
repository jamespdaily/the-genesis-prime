//// What the closer says when it cannot close a listener
//// (`genesis_prime/connection/closer`). The expected sentence is the closer's
//// own contract in its doc comment: a listener that cannot be closed is logged
//// as a warning with the reason Ranch gave, and the "every listener" line is
//// not logged; Ranch has no listener under a name no listener holds
//// (`ranch_server`'s table has no entry for it).

import ask_support
import asking_rule
import genesis_prime/connection/closer
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import log_capture
import owned_test
import unitest

type Line =
  #(String, String, List(#(String, String)))

pub fn a_listener_the_closer_cannot_close_is_logged_as_a_warning_with_the_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let nobody = process.new_name("no_listener")
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) { supervisor.add(builder, closer.supervised([nobody])) },
    )
  ask_support.stop(server)
  log_capture.stop(capture)
  let closed =
    drain(lines)
    |> list.filter(fn(line) { string.contains(line.1, "listener") })
    |> list.map(fn(line) { #(line.0, line.1) })
  assert list.contains(closed, #(
    "warning",
    "a listener could not be closed to new connections: no listener runs under the name",
  ))
    as "the closer names why: Ranch has no listener under the name"
  assert !list.contains(closed, #(
    "info",
    "every listener stopped accepting new connections",
  ))
    as "and does not say every listener closed"
}

fn drain(lines: Subject(Line)) -> List(Line) {
  case process.receive(lines, 0) {
    Ok(line) -> [line, ..drain(lines)]
    Error(Nil) -> []
  }
}
