//// The clock and the timers of a whole-server test whose timers must not depend on
//// real time: the connections of the listener it gives its scripts to, and the
//// service shells (maps, creatures) of the world it gives its service time to, take
//// their time from this clock and start their timers on this scheduler, and a
//// timer fires only when the test advances the clock past its time.
////
//// ```
//// test ──advance(1000)──▶ the earliest timer due within 1000 ms
////                           ├─ the clock reads that timer's due time
////                           ├─ Elapsed is sent to the process that started it
////                           └─ barrier: passes of sys:suspend and sys:resume over every participant
////                              until two passes in a row saw no change; only then
////                              the clock is asked for the next due timer
//// ```
////
//// - **Contract:** a script's clock gives each connection input its `Now` and its
////   scheduler starts each timer (genesis_prime/connection/script); a service time's
////   clock and scheduler do the same for a service shell's inputs and timers
////   (genesis_prime/service/shell).
//// - **Time** starts an hour after the node's own reading when the clock is made, then
////   moves only by `advance`. The hour keeps it ahead of a map the server starts
////   later, which counts its clock from the node's own time: a connection's time
////   before the map's start would make the unit's server time negative, which the
////   0x262 cannot hold. The node's time for an input, which the shell counts an
////   ask's wait from, stays the node's own, as a replay's does.
//// - **Order:** timers fire in the order of their due times, equal times in the order
////   they were started.
//// - **Participants** are the processes that read this clock or start a timer on it:
////   the connections of the listeners given these scripts and the shells of a world
////   given this service time. The hand-off and Sessions take the real time and are
////   not participants. A participant that has ended is dropped at the next pass.
//// - **The change counter** counts the clock reads of participants and the
////   participants found ended. Each input of a driven shell reads the clock at
////   least once (a connection input that asks reads it again when the answer comes
////   back), so a pass in which the counter does not move is a pass in which no
////   participant took an input and none ended.
//// - **The barrier** (`wait_until_quiet`) makes `advance` return only when every frame
////   a timer caused is in the client's socket. A chain through a process that is not a
////   participant (a registry, the store) is invisible to the counter; the creatures
////   send straight to the connections, so no frame path of a map or a creature goes
////   through one.
//// - **No wait here has a time limit.** A call to the clock and the barrier wait until
////   they are answered, and the test's deadline warns of one that never is, naming
////   it, and the wait goes on (`open_wait`, `owned_test.run`).

import genesis_prime/connection/script.{
  type Elapsed, type Scripts, Elapsed, Issued, Script,
}
import genesis_prime/service/shell.{type ServiceTime, ServiceTime}
import genesis_prime/step.{type Now, type TimerId, Now}
import genesis_prime/step/runtime
import genesis_prime/step/timer
import gleam/bool
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import open_wait

/// How far ahead of the node's own time the clock starts.
const ahead_ms = 3_600_000

/// A driven clock and its timers.
pub opaque type Time {
  Time(driver: Subject(Message))
}

type Pending {
  Pending(
    due_ms: Int,
    number: Int,
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
    changes: Int,
    participants: List(Pid),
  )
}

/// What the clock has seen of the participants at one moment: how many changes
/// (clock reads, participants found ended) there have been and which participants
/// are still running.
type Participation {
  Participation(changes: Int, running: List(Pid))
}

type Message {
  /// A participant's read of the clock: counted, and the reader is a participant.
  ReadNow(reader: Pid, reply: Subject(Now))
  /// The test's own read of the clock: neither counted nor a participant.
  Peek(reply: Subject(Now))
  /// The change counter and the participants still running; an ended one is dropped
  /// and counts as a change.
  Observe(reply: Subject(Participation))
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
  let monotonic_ms = monotonic_ms + ahead_ms
  let filetime = filetime + ahead_ms * 10_000
  let assert Ok(started) =
    actor.new(
      State(
        now_ms: monotonic_ms,
        start_ms: monotonic_ms,
        start_filetime: filetime,
        next_number: 0,
        pending: [],
        changes: 0,
        participants: [],
      ),
    )
    |> actor.on_message(handle)
    |> actor.start
    as "the driven clock started"
  Time(driver: started.data)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    ReadNow(reader:, reply:) -> {
      process.send(reply, now_of(state))
      actor.continue(
        State(
          ..state,
          changes: state.changes + 1,
          participants: joined(state.participants, reader),
        ),
      )
    }
    Peek(reply:) -> {
      process.send(reply, now_of(state))
      actor.continue(state)
    }
    Observe(reply:) -> {
      let running = list.filter(state.participants, process.is_alive)
      let changes =
        state.changes + list.length(state.participants) - list.length(running)
      process.send(reply, Participation(changes:, running:))
      actor.continue(State(..state, changes:, participants: running))
    }
    Start(owner:, subject:, timer:, reference:, after_ms:, reply:) -> {
      process.send(reply, state.next_number)
      let pending =
        Pending(
          due_ms: state.now_ms + after_ms,
          number: state.next_number,
          subject:,
          timer:,
          reference:,
        )
      actor.continue(
        State(
          ..state,
          next_number: state.next_number + 1,
          pending: list.append(state.pending, [pending]),
          participants: joined(state.participants, owner),
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
    TakeDue(limit_ms:, reply:) -> take_due(state:, limit_ms:, reply:)
  }
}

/// Gives the earliest timer due by `limit_ms` and moves the clock to its due time;
/// with none due, moves the clock to `limit_ms`.
fn take_due(
  state state: State,
  limit_ms limit_ms: Int,
  reply reply: Subject(Option(Pending)),
) -> actor.Next(State, Message) {
  let due =
    list.filter(state.pending, fn(pending) { pending.due_ms <= limit_ms })
    |> list.sort(fn(a, b) {
      int.compare(a.due_ms, b.due_ms)
      |> order_then(int.compare(a.number, b.number))
    })
  case due {
    [] -> {
      process.send(reply, None)
      actor.continue(State(..state, now_ms: int.max(state.now_ms, limit_ms)))
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

fn joined(participants: List(Pid), pid: Pid) -> List(Pid) {
  use <- bool.guard(
    when: list.contains(participants, pid),
    return: participants,
  )
  [pid, ..participants]
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
          clock: fn(_taking) { read(time) },
          node_monotonic_ms: fn(_now) { runtime.monotonic_ms() },
          schedule: fn(subject, timer, reference, after_ms) {
            started(time:, subject:, timer:, reference:, after_ms:)
          },
        ),
      ),
    )
  }
}

/// The clock and scheduler a world is started with (`server.World.service_time`):
/// every map and creature of it reads this clock for each input and starts its
/// timers here, so one `Time` drives a listener's connections and its world.
pub fn service_time(time: Time) -> ServiceTime {
  ServiceTime(
    clock: fn() { read(time) },
    schedule: fn(subject, timer, reference, after_ms) {
      started(time:, subject:, timer:, reference:, after_ms:)
    },
  )
}

/// A participant's reading of the clock, which the clock counts.
fn read(time: Time) -> Now {
  let reader = process.self()
  asked(time:, make: ReadNow(reader, _))
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
    asked(time:, make: fn(reply) {
      Start(owner:, subject:, timer:, reference:, after_ms:, reply:)
    })
  fn() { asked(time:, make: Cancel(number, _)) }
}

/// Asks the clock and waits for its answer, with no limit of its own.
fn asked(time time: Time, make make: fn(Subject(reply)) -> Message) -> reply {
  open_wait.named("the driven clock to answer", fn() {
    process.call_forever(time.driver, make)
  })
}

/// Moves the clock on by `ms`, firing each timer due within it, one at a time in
/// the order of their due times. Each fires at its own due time; then the barrier
/// (`wait_until_quiet`) runs, and only after it is the next due timer chosen, so a
/// timer started anywhere in the chain the fired one caused is in the queue when the
/// choice is made. The test first reads all its connection has written
/// (`game_client.read_until_pong`), so the test's own input has been taken and no
/// timer it cancels is still in the queue.
pub fn advance(time time: Time, ms ms: Int) -> Nil {
  let Now(monotonic_ms: from_ms, ..) = asked(time:, make: Peek)
  fire_until(time:, limit_ms: from_ms + ms)
}

fn fire_until(time time: Time, limit_ms limit_ms: Int) -> Nil {
  case asked(time:, make: TakeDue(limit_ms, _)) {
    None -> Nil
    Some(Pending(subject:, timer:, reference:, ..)) -> {
      process.send(subject, Elapsed(timer:, reference:))
      wait_until_quiet(time)
      fire_until(time:, limit_ms:)
    }
  }
}

/// Returns after two passes in a row that saw no change. A pass reads the counter,
/// waits until each participant that is still running has taken everything in its
/// mailbox (`settled`), and reads the counter again; a changed counter means some
/// participant took an input or ended during the pass, and the pass is made again
/// over the participants as they are then.
///
/// One quiet pass is not enough. A participant A can read the clock for an input
/// before the pass's opening read, and during the pass send a message M to a
/// participant B the pass has already settled. B takes M after its `settled`, and
/// its read for M comes after the pass's closing read when B is slow: the counter
/// then did not move, and the pass is quiet while B holds M. The second pass opens
/// at the first one's closing read. A's send returned before A answered the first
/// pass's `settled`, and a local send has put M in B's queue, or in one of B's
/// signal buffers (a receiver with its messages off the heap, as a connection shell
/// is), before the send returns. B's next fetch moves every buffered signal into
/// its queue, at the latest when B takes the first pass's `sys:suspend`, which may
/// be after that request. So by the time B answers the first pass, M is in B's
/// queue, and the second pass's request is queued behind it: B's read for M is
/// counted in the second pass, which is then not quiet. Any input whose read is not
/// before the first pass's opening read is after its closing read, so the second
/// pass counts it.
///
/// A participant that ends during a pass is dropped by the next look, which counts
/// it as a change, so the last signals of an ended participant get one more pass.
fn wait_until_quiet(time: Time) -> Nil {
  let opening = asked(time:, make: Observe)
  pass(time:, opening:, after_a_quiet_pass: False)
}

/// One pass over the participants `opening` names, which ends the barrier when it
/// is quiet after a quiet pass, and is made again from its closing look otherwise.
fn pass(
  time time: Time,
  opening opening: Participation,
  after_a_quiet_pass after_a_quiet_pass: Bool,
) -> Nil {
  list.each(opening.running, settled)
  let closing = asked(time:, make: Observe)
  case closing.changes == opening.changes, after_a_quiet_pass {
    True, True -> Nil
    True, False -> pass(time:, opening: closing, after_a_quiet_pass: True)
    False, _ -> pass(time:, opening: closing, after_a_quiet_pass: False)
  }
}

/// Returns when the participant has taken what was in its mailbox when this was
/// called (`sys:suspend` is answered in the order of its mailbox), or has ended.
/// The wait has no limit of its own (`open_wait`).
pub fn settled(participant: Pid) -> Nil {
  open_wait.named("a driven process to take its mailbox", fn() {
    taken_or_ended(participant)
  })
}

/// `sys:suspend` and `sys:resume` of the process, which wait until the process
/// answers or ends; the call monitors the process, so one that ends gives its exit
/// at once and leaves no crash report. The ones in `gleam/otp/system` have no way
/// to lift their five seconds, and `get_state` copies the process's whole state.
@external(erlang, "driven_time_ffi", "taken_or_ended")
fn taken_or_ended(participant: Pid) -> Nil
