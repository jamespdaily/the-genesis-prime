//// The log capture the tests share. A capture sees each line once, however
//// many tests start a capture at the same moment: the logger accepts two
//// overlapping adds of one handler id and lists the handler twice, so a
//// capture started that way would see every line twice.

import fresh_node
import genesis_prime/step
import genesis_prime/step/runtime
import gleam/erlang/process.{type Subject}
import gleam/list
import log_capture
import owned_test

/// How many captures start at the same moment.
const captures = 20

pub fn captures_that_start_at_once_in_a_fresh_node_each_see_a_line_once_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(captures_started_at_once)
}

/// Starts `captures` captures of this process's lines from as many processes
/// released together, logs one line and then a last one, and checks that each
/// capture holds the first line once and then the last. Run in a fresh node,
/// where nothing has installed the capture's logger handler yet.
pub fn captures_started_at_once() -> Nil {
  let logger = process.self()
  let ready = process.new_subject()
  let started = process.new_subject()
  let each =
    list.map(list.repeat(Nil, captures), fn(_) {
      let lines = process.new_subject()
      let _worker =
        process.spawn(fn() {
          let go = process.new_subject()
          process.send(ready, go)
          process.receive_forever(go)
          let _capture = log_capture.start(from: logger, into: lines)
          process.send(started, Nil)
        })
      lines
    })
  let released = list.map(each, fn(_) { process.receive_forever(ready) })
  list.each(released, fn(go) { process.send(go, Nil) })
  list.each(each, fn(_) { process.receive_forever(started) })
  runtime.log(step.LogWarning, "first", step.no_one)
  runtime.log(step.LogWarning, "last", step.no_one)
  list.each(each, fn(lines) {
    assert lines_to_last(lines) == ["first", "last"]
      as "a capture holds each line once: the first, then the last"
  })
}

/// The text of each line a capture sent, up to and including the one that says
/// `last`.
fn lines_to_last(lines: Subject(#(String, String))) -> List(String) {
  let assert Ok(#(_, text)) = process.receive(lines, 5000)
    as "the capture sent the last line"
  case text {
    "last" -> [text]
    _ -> [text, ..lines_to_last(lines)]
  }
}
