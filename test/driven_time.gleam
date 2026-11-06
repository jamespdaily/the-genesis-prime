//// The clock and the timers of a whole-server test that must not depend on real
//// time: the game connections of the server it starts take their time from this
//// clock and start their timers on this scheduler, and a timer fires only when the
//// test advances the clock past its time.
////
//// ```
//// test ──advance(1000)──▶ the earliest timer due within 1000 ms
////                           ├─ the clock reads that timer's due time
////                           ├─ Elapsed is sent to the connection that started it
////                           └─ the test waits until that connection has taken it and
////                              finished its step (`sys:get_state`), then asks again
//// ```
////
//// - **Contract:** a script's clock gives each input its `Now`, and its scheduler
////   starts each timer (genesis_prime/connection/script).
//// - **Time** starts at the node's own reading when the clock is made, then moves only
////   by `advance`. The node's time for an input, which the shell counts an ask's
////   wait from, stays the node's own, as a replay's does.
//// - **Order:** timers fire in the order of their due times, equal times in the order
////   they were started, and a timer a step starts inside the advance fires in it when
////   it is due within it, so a connection takes the timers of a stretch of time as a
////   machine that is never late would.

import genesis_prime/connection/script.{
  type Elapsed, type Scripts, Elapsed, Issued, Script,
}
import genesis_prime/step.{type Now, type TimerId, Now}
import genesis_prime/step/runtime
import genesis_prime/step/timer
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/otp/system

/// A driven clock and its timers.
pub opaque type Time {
  Time(driver: Subject(Message))
}

type Pending {
  Pending(
    due_ms: Int,
    number: Int,
    owner: Pid,
    subject: Subject(Elapsed),
    timer: TimerId,
    reference: Reference,
  )
}

type State {
  State(
    now_ms: Int,
    start_ms: Int,
    start_filetime: Int,
    next_number: Int,
    pending: List(Pending),
  )
}

type Message {
  ReadNow(reply: Subject(Now))
  Start(
    owner: Pid,
    subject: Subject(Elapsed),
    timer: TimerId,
    reference: Reference,
    after_ms: Int,
    reply: Subject(Int),
  )
  Cancel(number: Int, reply: Subject(Nil))
  TakeDue(limit_ms: Int, reply: Subject(Option(Pending)))
}

/// A clock at the node's own time with no timer running, linked to the calling
/// test, which ends it.
pub fn new() -> Time {
  let Now(monotonic_ms:, filetime:) = runtime.now()
  let assert Ok(started) =
    actor.new(
      State(
        now_ms: monotonic_ms,
        start_ms: monotonic_ms,
        start_filetime: filetime,
        next_number: 0,
        pending: [],
      ),
    )
    |> actor.on_message(handle)
    |> actor.start
    as "the driven clock started"
  Time(driver: started.data)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    ReadNow(reply:) -> {
      process.send(reply, now_of(state))
      actor.continue(state)
    }
    Start(owner:, subject:, timer:, reference:, after_ms:, reply:) -> {
      process.send(reply, state.next_number)
      let pending =
        Pending(
          due_ms: state.now_ms + after_ms,
          number: state.next_number,
          owner:,
          subject:,
          timer:,
          reference:,
        )
      actor.continue(
        State(
          ..state,
          next_number: state.next_number + 1,
          pending: list.append(state.pending, [pending]),
        ),
      )
    }
    Cancel(number:, reply:) -> {
      process.send(reply, Nil)
      actor.continue(
        State(
          ..state,
          pending: list.filter(state.pending, fn(pending) {
            pending.number != number
          }),
        ),
      )
    }
    TakeDue(limit_ms:, reply:) -> {
      let due =
        list.filter(state.pending, fn(pending) { pending.due_ms <= limit_ms })
        |> list.sort(fn(a, b) {
          int.compare(a.due_ms, b.due_ms)
          |> order_then(int.compare(a.number, b.number))
        })
      case due {
        [] -> {
          process.send(reply, None)
          actor.continue(
            State(..state, now_ms: int.max(state.now_ms, limit_ms)),
          )
        }
        [first, ..] -> {
          process.send(reply, Some(first))
          actor.continue(
            State(
              ..state,
              now_ms: int.max(state.now_ms, first.due_ms),
              pending: list.filter(state.pending, fn(pending) {
                pending.number != first.number
              }),
            ),
          )
        }
      }
    }
  }
}

fn order_then(first: order.Order, second: order.Order) -> order.Order {
  case first {
    order.Eq -> second
    order.Lt | order.Gt -> first
  }
}

fn now_of(state: State) -> Now {
  Now(
    monotonic_ms: state.now_ms,
    filetime: state.start_filetime + { state.now_ms - state.start_ms } * 10_000,
  )
}

/// The scripts of the connections of a server: the server's own script with this
/// clock and these timers.
pub fn scripts(time: Time) -> Scripts {
  fn() {
    let assert Ok(issued) = script.operating_system()
    Ok(
      Issued(
        ..issued,
        script: Script(
          ..issued.script,
          clock: fn(_taking) { process.call(time.driver, 5000, ReadNow) },
          node_monotonic_ms: fn(_now) { runtime.monotonic_ms() },
          schedule: fn(subject, timer, reference, after_ms) {
            started(time:, subject:, timer:, reference:, after_ms:)
          },
        ),
      ),
    )
  }
}

fn started(
  time time: Time,
  subject subject: Subject(Elapsed),
  timer timer: TimerId,
  reference reference: Reference,
  after_ms after_ms: Int,
) -> timer.Cancel {
  let owner = process.self()
  let number =
    process.call(time.driver, 5000, fn(reply) {
      Start(owner:, subject:, timer:, reference:, after_ms:, reply:)
    })
  fn() { process.call(time.driver, 5000, Cancel(number, _)) }
}

/// Moves the clock on by `ms`, firing each timer due within it, one at a time in
/// the order of their due times. Each fires at its own due time and the next waits
/// until the connection it fired on has taken it and finished its step, so a timer
/// that step starts or cancels is in the queue when the next is chosen. The test
/// first reads all the connection has written (`game_client.read_until_pong`), so
/// no step is under way and no timer it cancels is still in the queue.
pub fn advance(time time: Time, ms ms: Int) -> Nil {
  let Now(monotonic_ms: from_ms, ..) = process.call(time.driver, 5000, ReadNow)
  fire_until(time:, limit_ms: from_ms + ms)
}

fn fire_until(time time: Time, limit_ms limit_ms: Int) -> Nil {
  case process.call(time.driver, 5000, TakeDue(limit_ms, _)) {
    None -> Nil
    Some(Pending(owner:, subject:, timer:, reference:, ..)) -> {
      process.send(subject, Elapsed(timer:, reference:))
      case process.is_alive(owner) {
        True -> {
          let _step_done = system.get_state(owner)
          Nil
        }
        False -> Nil
      }
      fire_until(time:, limit_ms:)
    }
  }
}
