//// A wait that can no longer end warns by name and goes on (`open_wait`,
//// `owned_test`). Expected values are the rule of the detector: a read that
//// looked at its socket and found nothing is judged by the driven clock of its
//// test, which counts the clock reads of the server's participants; a read in
//// a test whose server took no input since the previous empty look, after one
//// has taken at least one, cannot end, and the test's owner prints one
//// `check WARNING` line naming the test and the wait. The line never fails
//// the test: the wait goes on until what it waits for comes.

import driven_time
import frame_peer
import genesis_prime/service/shell.{type ServiceTime}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import login_client
import mailbox_support
import mug
import open_wait
import owned_test
import socket_read

/// A server process of the driven clock: each message makes it read the clock,
/// as a connection does for an input, and answer on the subject it came with.
fn start_participant(service_time: ServiceTime) -> Subject(Subject(Nil)) {
  let assert Ok(started) =
    actor.new(Nil)
    |> actor.on_message(fn(state, reply: Subject(Nil)) {
      let _read = service_time.clock()
      process.send(reply, Nil)
      actor.continue(state)
    })
    |> actor.start
    as "the participant started"
  started.data
}

fn read_by(participant: Subject(Subject(Nil))) -> Nil {
  let reply = process.new_subject()
  process.send(participant, reply)
  open_wait.received(from: reply, what: "the participant's read of the clock")
}

type Step {
  /// The server takes an input: a participant reads the clock.
  Input
  /// The read looks at its socket and finds nothing.
  EmptyLook
}

const waiting_for = "a frame the server never writes"

/// The warnings a test body printed while it did the steps in a wait named
/// `waiting_for`, on a driven clock with one participant.
fn warnings_after(steps: List(Step)) -> List(String) {
  let warnings = process.new_subject()
  owned_test.run_warning_to(
    warn: fn(text) { process.send(warnings, text) },
    progress_file: None,
    timeout_ms: 30_000,
    body: fn() {
      let time = driven_time.new()
      let participant = start_participant(driven_time.service_time(time))
      open_wait.named(waiting_for, fn() {
        list.each(steps, fn(step) {
          case step {
            Input -> read_by(participant)
            EmptyLook -> open_wait.looked_and_found_nothing()
          }
        })
      })
    },
  )
  hopeless_lines(mailbox_support.drain(warnings))
}

/// The lines of the warnings that name a wait that can no longer end: the
/// deadline warning names the same wait, and a slow machine may give it too.
fn hopeless_lines(warnings: List(String)) -> List(String) {
  list.filter(warnings, string.contains(
    _,
    "is in a wait that can no longer end",
  ))
}

pub fn a_wait_cannot_end_when_no_input_was_taken_since_the_last_empty_look_after_one_was_test() -> Nil {
  use <- owned_test.run(30_000)
  // Each row: the steps, how many warnings the test's owner heard, and why.
  let cases = [
    #([Input, EmptyLook], 0, "the first empty look has no look to compare"),
    #(
      [Input, EmptyLook, EmptyLook],
      1,
      "no input between two empty looks: nothing can write",
    ),
    #(
      [Input, EmptyLook, EmptyLook, EmptyLook, EmptyLook],
      1,
      "one warning for each wait, however many looks follow",
    ),
    #(
      [Input, EmptyLook, Input, EmptyLook],
      0,
      "an input between the looks: the server is still at work",
    ),
    #(
      [Input, EmptyLook, Input, EmptyLook, EmptyLook],
      1,
      "the second look after the last input finds the server quiet",
    ),
    #(
      [EmptyLook, EmptyLook, EmptyLook],
      0,
      "no participant has taken an input yet: the server may not have begun",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(steps, count, reason) = case_
    let warnings = warnings_after(steps)
    assert list.length(warnings) == count as reason
    assert list.all(warnings, string.contains(_, waiting_for))
      as "each warning names the wait"
  })
}

pub fn the_hopeless_warning_names_the_test_and_the_wait_test() -> Nil {
  use <- owned_test.run(30_000)
  assert owned_test.hopeless_warning(
      test_name: "module:function",
      what: "a frame",
    )
    == "check WARNING: test module:function is in a wait that can no longer end, since the server took no input since the last look and the clock does not move: a frame"
}

pub fn a_wait_in_a_test_with_no_driven_clock_is_never_judged_test() -> Nil {
  use <- owned_test.run(30_000)
  let warnings = process.new_subject()
  owned_test.run_warning_to(
    warn: fn(text) { process.send(warnings, text) },
    progress_file: None,
    timeout_ms: 30_000,
    body: fn() {
      open_wait.named(waiting_for, fn() {
        list.repeat(Nil, 4)
        |> list.each(fn(_) { open_wait.looked_and_found_nothing() })
      })
    },
  )
  assert hopeless_lines(mailbox_support.drain(warnings)) == []
}

pub fn a_read_that_can_no_longer_end_warns_naming_the_test_and_the_wait_and_the_run_passes_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(listener, port) = frame_peer.listen()
  let client = login_client.connect(port)
  let peer = frame_peer.accept(listener)
  let warnings = process.new_subject()
  // The peer writes only once the owner has warned, so the read can end only
  // after the warning: the run passes with the warning given.
  let read =
    owned_test.run_warning_to(
      warn: fn(text) {
        process.send(warnings, text)
        frame_peer.write(peer, <<7>>)
      },
      progress_file: None,
      timeout_ms: 30_000,
      body: fn() {
        let time = driven_time.new()
        let participant = start_participant(driven_time.service_time(time))
        read_by(participant)
        socket_read.receive(
          socket: client,
          limit: socket_read.Open,
          what: waiting_for,
        )
      },
    )
  assert read == Ok(<<7>>) as "the read ended with what the peer wrote"
  assert hopeless_lines(mailbox_support.drain(warnings))
    == [
      "check WARNING: test hopeless_wait_test:a_read_that_can_no_longer_end_warns_naming_the_test_and_the_wait_and_the_run_passes_test is in a wait that can no longer end, since the server took no input since the last look and the clock does not move: "
      <> waiting_for,
    ]
}

/// More bytes than the loopback socket's buffers hold, so the peer's send
/// blocks until the test reads.
const burst_bytes = 4_000_000

fn read_all(client: mug.Socket, left: Int) -> Nil {
  case left {
    0 -> Nil
    _ -> {
      let assert Ok(bytes) = socket_read.looking(client)
        as "the burst's bytes came"
      read_all(client, left - bit_array.byte_size(bytes))
    }
  }
}

pub fn a_wait_whose_server_sends_a_large_burst_after_an_empty_look_still_passes_with_no_warning_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(listener, port) = frame_peer.listen()
  let client = login_client.connect(port)
  let peer = frame_peer.accept(listener)
  let warnings = process.new_subject()
  owned_test.run_warning_to(
    warn: fn(text) { process.send(warnings, text) },
    progress_file: None,
    timeout_ms: 30_000,
    body: fn() {
      let time = driven_time.new()
      let participant = start_participant(driven_time.service_time(time))
      read_by(participant)
      open_wait.named(waiting_for, fn() {
        // The look found nothing; the server then starts a burst whose send
        // cannot finish until the test reads. The judge only reads a count, so
        // it holds back neither the test's read nor the server's send.
        open_wait.looked_and_found_nothing()
        let _writer =
          process.spawn(fn() {
            frame_peer.write(peer, <<0:size(burst_bytes)-unit(8)>>)
          })
        read_all(client, burst_bytes)
      })
    },
  )
  assert hopeless_lines(mailbox_support.drain(warnings)) == []
    as "the read took the whole burst and said nothing"
}
