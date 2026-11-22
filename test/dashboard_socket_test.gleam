//// What the dashboard's websocket says of a runtime that did not start: the
//// 503 the page's client asks again after is written to the log with its
//// reason, so a start that fails on a loaded machine names itself. The ways are
//// `gleam/otp/actor.StartError` (the factory's child did not start) and the
//// exceptions of the ask (the factory was gone or ended while the ask waited).

import exception
import genesis_prime/dashboard/socket
import gleam/dynamic
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import owned_test

pub fn each_way_a_runtime_does_not_start_is_described_with_its_reason_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "the runtime missed its init time",
      socket.StartFailed(actor.InitTimeout),
      "the page's runtime did not start in time",
    ),
    #(
      "the runtime's init returned an error",
      socket.StartFailed(actor.InitFailed("x")),
      "the page's runtime failed to start: x",
    ),
    #(
      "the runtime ended in its init, killed",
      socket.StartFailed(actor.InitExited(process.Killed)),
      "the page's runtime exited while it started: killed",
    ),
    #(
      "the runtime ended in its init, abnormally",
      socket.StartFailed(actor.InitExited(process.Abnormal(dynamic.int(7)))),
      "the page's runtime exited while it started: 7",
    ),
    #(
      "the factory ended while the ask waited",
      socket.AskEnded(exception.Exited(dynamic.int(7))),
      "the runtimes' factory ended while the start was asked: 7",
    ),
    #(
      "the ask raised an error",
      socket.AskEnded(exception.Errored(dynamic.int(7))),
      "the ask of the runtimes' factory raised an error: 7",
    ),
    #(
      "the ask threw a value",
      socket.AskEnded(exception.Thrown(dynamic.int(7))),
      "the ask of the runtimes' factory threw a value: 7",
    ),
  ]
  list.each(rows, fn(row) {
    assert socket.describe_not_started(not_started: row.1) == row.2 as row.0
  })
}
