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
//// - **The barrier** (`wait_until_quiet`) runs before `advance` moves the clock and after
////   each timer it fires, so `advance` starts from every timer the inputs already
////   received start and returns only when every frame a timer caused is in the client's
////   socket. A chain through a process that is not a
////   participant (a registry, the store) is invisible to the counter; the creatures
////   send straight to the connections, so no frame path of a map or a creature goes
////   through one.
//// - **A wait** (`wait_for`) runs the barrier and looks at its condition once: with the
////   participants quiet and the clock still, a condition that fails cannot come true
////   through the participants' own work, so the wait ends at once with a panic naming it.
////   A condition that depends on a process that is not a participant is sound only
////   when the participants' step reaches it synchronously (a call it makes).
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
import gleam/result
import mailbox_support
import open_wait

/// How far ahead of the node's own time the clock starts.
const ahead_ms = 3_600_000

/// How long the clock's start may take, which is the start that `actor.new` allows.
const initialisation_ms = 1000

/// Makes the calling process keep its mailbox outside its heap. The clock holds one
/// read for each creature of a crowd at once, and a collection of a process whose
/// mailbox is on its heap copies every message waiting and, after a full sweep, moves
/// them again: the VM has aborted in that move (`Overrun stack and heap`).
@external(erlang, "driven_time_ffi", "keep_mailbox_off_heap")
fn keep_mailbox_off_heap() -> Nil

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
  /// The timers the process has started that have neither fired nor been cancelled.
  PendingOf(owner: Pid, reply: Subject(List(TimerId)))
  TakeDue(limit_ms: Int, reply: Subject(Option(Pending)))
}

/// A clock at the node's own time with no timer running, linked to the calling
/// test, which ends it.
pub fn new() -> Time {
  let Now(monotonic_ms:, filetime:) = runtime.now()
  let monotonic_ms = monotonic_ms + ahead_ms
  let filetime = filetime + ahead_ms * 10_000
  let state =
    State(
      now_ms: monotonic_ms,
      start_ms: monotonic_ms,
      start_filetime: filetime,
      next_number: 0,
      pending: [],
      changes: 0,
      participants: [],
    )
  let assert Ok(started) =
    actor.new_with_initialiser(initialisation_ms, fn(driver) {
      keep_mailbox_off_heap()
      actor.initialised(state) |> actor.returning(driver) |> Ok
    })
    |> actor.on_message(handle)
    |> actor.start
    as "the driven clock started"
  let time = Time(driver: started.data)
  open_wait.judging(fn() { taken_inputs(time) })
  time
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
    PendingOf(owner:, reply:) -> {
      process.send(
        reply,
        list.filter_map(state.pending, fn(pending) {
          case pending.owner == owner {
            True -> Ok(pending.timer)
            False -> Error(Nil)
          }
        }),
      )
      actor.continue(state)
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

/// The scripts of the connections of a server: the scripts `over` hands out, with
/// this clock and these timers in place of theirs (the seed stays). An
/// `Error` of `over` (no connection left) is passed on.
pub fn scripts(time time: Time, over over: Scripts) -> Scripts {
  fn() {
    use issued <- result.map(over())
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

/// The process that is the clock.
pub fn driver(time: Time) -> Pid {
  let assert Ok(pid) = process.subject_owner(time.driver)
    as "the clock's subject belongs to its process"
  pid
}

/// The timers the process `owner` started on this clock that have neither fired nor
/// been cancelled, in the order they were started.
pub fn pending_of(time time: Time, owner owner: Pid) -> List(TimerId) {
  asked(time:, make: PendingOf(owner, _))
}

/// The clock's time now, which the participants read for each input.
pub fn now(time time: Time) -> Now {
  asked(time:, make: Peek)
}

/// Moves the clock on by `ms`, firing each timer due within it, one at a time in
/// the order of their due times. The barrier (`wait_until_quiet`) runs first, so each
/// timer that an input a participant has already received starts is in the queue,
/// started on the clock as it was, before the clock moves: a connection writes the
/// frames of an input before it starts that input's timers, so a test that has read
/// the frames and advances at once would otherwise move the clock first and the timer
/// would fall due that much later. Each timer fires at its own due time; then the
/// barrier runs again, and only after it is the next due timer chosen, so a timer
/// started anywhere in the chain the fired one caused is in the queue when the choice
/// is made. The test first reads all its connection has written
/// (`game_client.read_until_pong`), so the test's own input has been taken and no
/// timer it cancels is still in the queue.
pub fn advance(time time: Time, ms ms: Int) -> Nil {
  wait_until_quiet(time)
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
///
/// `advance` runs it before the clock moves and after each timer it fires. A test
/// runs it itself, with no advance, after an input of its own whose chain goes
/// through another participant with no timer on the way (a press whose go strikes
/// a creature at once), once the connection has taken that input
/// (`game_client.read_until_pong`).
pub fn wait_until_quiet(time: Time) -> Nil {
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

/// Waits for `condition` on the driven clock: the barrier (`wait_until_quiet`) runs,
/// and the condition is looked at once. A participant that was to take an input
/// has taken it by then, so a condition such an input makes true holds, and the
/// clock has not moved. A condition that still fails is one no participant can
/// make true without the clock moving, so the wait ends at once with a panic that
/// names `what`: it never polls and has no limit of time.
///
/// Its limit is the barrier's: a chain through a process that is not a participant
/// (a registry, a supervisor) is invisible to it, so a condition on such a process's
/// state is not a condition to wait on here; wait on the monitor of the process
/// whose end is meant.
pub fn wait_for(
  time time: Time,
  what what: String,
  condition condition: fn() -> Bool,
) -> Nil {
  wait_until_quiet(time)
  use <- bool.guard(when: condition(), return: Nil)
  let message =
    "the driven clock's participants are quiet and no input waits for them, so nothing more can happen before the clock moves: "
    <> what
    <> " never held"
  panic as message
}

/// How many inputs the participants have taken so far, which the test's open
/// reads look at after each empty look (`open_wait.looked_and_found_nothing`):
/// the counter of reads of the clock, which each input moves when it starts. It
/// is a look at the counter, so it neither waits for a participant nor holds one
/// back.
fn taken_inputs(time: Time) -> Int {
  asked(time:, make: Observe).changes
}

/// Returns when the participant has taken what was in its mailbox when this was
/// called, or has ended (`mailbox_support.settled`).
pub fn settled(participant: Pid) -> Nil {
  let _settled = mailbox_support.settled(participant)
  Nil
}
