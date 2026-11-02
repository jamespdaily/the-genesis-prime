//// What the closer says when it cannot close a listener
//// (`genesis_prime/connection/closer`). The expected sentence is the closer's
//// own contract in its doc comment: a listener that cannot be closed is logged
//// as a warning with the reason Ranch gave, and the "every listener" line is
//// not logged; Ranch has no listener under a name no listener holds
//// (`ranch_server`'s table has no entry for it).

import ask_support
import asking_rule
import genesis_prime/connection/closer
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import log_capture
import mailbox_support
import mug
import owned_test
import supervisor_children
import unitest

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
    log_capture.drain(lines)
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

pub fn a_listener_whose_supervisor_ends_while_the_close_waits_does_not_stop_the_closer_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let first = started_listener()
  let second = started_listener()
  let assert [embedded] = supervisor_children.in_start_order(first.supervisor)
    as "the first listener's tree holds Ranch's embedded supervisor"
  let assert [_proxy, first_supervisor] =
    supervisor_children.in_start_order(embedded)
    as "which holds Ranch's server proxy and the listener's own supervisor"
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let closing =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) {
        supervisor.add(builder, closer.supervised([first.name, second.name]))
      },
    )
  // The first listener's supervisor takes no call, so the closer's call to it
  // waits, and the supervisor then ends while the call waits (an exit with the
  // reason `killed`, which the caller of a call sees as `{killed, {gen_server,
  // call, ...}}`).
  let assert True = ask_support.suspend_process(first_supervisor)
    as "the listener's supervisor was suspended"
  let stopping = ask_support.begin_stop_tree(closing.supervisor)
  mailbox_support.await_queued(first_supervisor)
  process.kill(first_supervisor)
  assert ask_support.ended(stopping) == ask_support.shutdown()
    as "the closing tree stopped as a stop ends it"
  log_capture.stop(capture)
  let refused =
    mug.new("127.0.0.1", port: second.port)
    |> mug.ip_version_preference(mug.Ipv4Only)
    |> mug.timeout(ask_support.event_wait_ms)
    |> mug.connect
  assert refused == Error(mug.ConnectFailedIpv4(mug.Econnrefused))
    as "the listener after the one that ended was closed to new connections"
  let closed =
    log_capture.drain(lines)
    |> list.filter(fn(line) { string.contains(line.1, "listener") })
    |> list.map(fn(line) { #(line.0, line.1) })
  assert list.contains(closed, #(
    "warning",
    "a listener could not be closed to new connections: no listener runs under the name",
  ))
    as "the listener that ended is one that is not running"
  ask_support.stop(second)
}

/// A server whose one listener runs the asking rule, with no closer.
fn started_listener() -> ask_support.Server {
  ask_support.start(
    rule: asking_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    recorder: None,
    with: fn(builder) { builder },
  )
}
