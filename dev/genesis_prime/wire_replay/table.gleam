//// The replay's table (genesis_prime/wire_replay): the one process that holds
//// what a replay's shells and its client share. For each recorded connection
//// it holds the recorded inputs its script has still to give a `Now` to, how
//// many it has given, whether its script has been handed out and the process
//// of its shell; it also holds the timers the shells have started. A shell asks
//// it for the `Now` of each input it takes, the client asks it how far a shell
//// is, waits for a shell to take an input or to start a timer, and fires the
//// timer: they share nothing else, and the table answers each in the order it
//// is asked.
////
//// - **A connection's states.** A connection's entry is one of four: not handed
////   out (its script is still to be asked for), handed out (its shell has not
////   asked for a `Now`), running (its shell has, and it holds the shell's
////   process), and failed (its shell took an input that matches no recorded
////   one; it holds the mismatch and the count taken before it).
//// - **A `Now`.** `take` matches an input the shell took with the next
////   recorded input by kind: another kind than the recording's next is an
////   ordering mismatch, an input after the last recorded one is an unrecorded
////   input, and either is kept against the connection, so the client sees it
////   however late it asks. A read of `n` bytes takes the `Now` of the recorded
////   read line its last byte falls in, and the line counts as taken once its
////   last byte has been; reads that are parts of one line leave the line's bytes
////   taken so far (`PartlyRead`).
//// - **A wait.** The client's wait for a count of taken inputs or a started
////   timer is a message the table answers when it can: at once, or when the
////   shell takes the input or starts the timer. The client bounds the wait
////   itself; a waiter whose client has given up is answered into a mailbox
////   nobody reads. A timer's start goes to the oldest wait for it, and is kept
////   only when no wait is there, so the one start is delivered once.
//// - **A table that ends.** The client's calls watch the table's process: a
////   table that ends (its supervisor starts another that knows no connection)
////   answers no call, and the client's call says so (`TableEnded`) instead of
////   exiting. The shells' calls, `take`, `next_read` and `handout`, exit with
////   the table's end, which ends their connection.

import genesis_prime/connection/script.{type Elapsed}
import genesis_prime/seed.{type Seed}
import genesis_prime/step.{type Now}
import genesis_prime/wire_recording.{type Input}
import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// One recorded input of a connection: the line it is on (the header is line 0)
/// and the `Now` it carried.
pub type Recorded {
  Recorded(line: Int, input: Input, at: Now)
}

/// A connection as the table is loaded with it: its file's name, its accept
/// ordinal, its seed, its recorded inputs in order, and the line its closing
/// line is on.
pub type Prepared {
  Prepared(
    name: String,
    ordinal: Int,
    seed: Seed,
    inputs: List(Recorded),
    closing_line: Int,
  )
}

/// What the table gave a script that asked for its connection.
pub type HandedOut {
  HandedOut(name: String, ordinal: Int, seed: Seed)
}

/// Why an input the shell took matches no recorded input.
pub type Mismatch {
  /// The shell took an input after the last recorded one; `line` is the
  /// recording's closing line.
  Unrecorded(line: Int)
  /// The shell took an input of another kind than the next recorded one,
  /// which is on `line`.
  OutOfOrder(line: Int, expected: Input, taken: Input)
}

/// A sentence that says why an input matches no recorded one, for the log of the
/// shell that ends because of it.
pub fn describe(mismatch mismatch: Mismatch) -> String {
  case mismatch {
    Unrecorded(line:) ->
      "no input is recorded after the last one, before line "
      <> int.to_string(line)
    OutOfOrder(line:, ..) ->
      "the next recorded input is another kind: it is on line "
      <> int.to_string(line)
  }
}

/// A timer a shell started: where its firing is sent, and the reference of the
/// start, which tells it from a stale firing.
pub type Started {
  Started(subject: Subject(Elapsed), reference: Reference)
}

/// Why a call of the client got no answer.
pub type Unanswered {
  /// The table did not answer in time.
  NotInTime
  /// The table's process ended before it answered.
  TableEnded
}

/// Why a wait for the shell to take inputs ended.
pub type Waited {
  /// The shell took an input that matches no recorded one.
  Mismatched(mismatch: Mismatch)
  /// The shell had not taken that many inputs in time; `taken` is how many it
  /// had.
  TimedOut(taken: Int)
  /// The table's process ended.
  WaitedTableEnded
}

/// What the table is told. Only this module makes one, through its functions.
pub opaque type Command {
  Load(connections: List(Prepared), reply: Subject(Nil))
  Handout(reply: Subject(Result(HandedOut, Nil)))
  Take(
    connection: String,
    taking: Input,
    shell: Pid,
    reply: Subject(Result(Now, Mismatch)),
  )
  NextRead(connection: String, reply: Subject(Option(Int)))
  Taken(connection: String, reply: Subject(Int))
  AwaitTaken(
    connection: String,
    inputs: Int,
    reply: Subject(Result(Nil, Mismatch)),
  )
  AwaitHandedOut(connection: String, reply: Subject(Nil))
  TimerStarted(connection: String, timer: Int, started: Started)
  TimerCancelled(connection: String, timer: Int, reference: Reference)
  AwaitTimer(connection: String, timer: Int, reply: Subject(Started))
  ShellOf(connection: String, reply: Subject(Option(Pid)))
  FailureOf(connection: String, reply: Subject(Option(Mismatch)))
}

/// What a recording says of a connection, which no state of its entry changes.
type Plan {
  Plan(name: String, ordinal: Int, seed: Seed, closing_line: Int)
}

/// The recorded inputs the shell has still to take.
type Pending {
  /// None of the first of these has been taken.
  Untouched(inputs: List(Recorded))
  /// `first` is a read of which `have` bytes, fewer than it holds, have been
  /// taken.
  PartlyRead(have: Int, first: Recorded, later: List(Recorded))
}

/// A wait of the client for the shell to take `inputs` inputs.
type TakenWaiter {
  TakenWaiter(inputs: Int, reply: Subject(Result(Nil, Mismatch)))
}

/// How far a connection's shell is through its recorded inputs: what it has
/// still to take, how many it has taken, and who waits for it to take more.
type Progress {
  Progress(pending: Pending, taken: Int, waiting: List(TakenWaiter))
}

/// One connection of the loaded session, in the state its shell has brought it
/// to.
type Entry {
  /// Loaded; its script is still to be handed out, and clients wait for that.
  NotHanded(
    plan: Plan,
    progress: Progress,
    waiting_for_hand_out: List(Subject(Nil)),
  )
  /// Its script is handed out; its shell has not asked for a `Now`.
  HandedOutNotRunning(plan: Plan, progress: Progress)
  /// Its shell has asked for a `Now`.
  Running(plan: Plan, shell: Pid, progress: Progress)
  /// Its shell took an input that matches no recorded one: `taken` inputs
  /// matched before it.
  Failed(plan: Plan, shell: Pid, mismatch: Mismatch, taken: Int)
}

/// A timer wait of the client.
type TimerWaiter {
  TimerWaiter(connection: String, timer: Int, reply: Subject(Started))
}

type State {
  State(
    connections: Dict(String, Entry),
    to_hand_out: List(String),
    timers: Dict(#(String, Int), Started),
    timer_waiters: List(TimerWaiter),
  )
}

/// How long a call of a shell to the table may take, in milliseconds. The table
/// answers at once, so only a table that has ended or is stuck is waited for this
/// long.
const call_ms = 5000

/// The table, named, as a child of the replay's supervisor.
pub fn supervised(name name: Name(Command)) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    actor.new(
      State(
        connections: dict.new(),
        to_hand_out: [],
        timers: dict.new(),
        timer_waiters: [],
      ),
    )
    |> actor.on_message(handle)
    |> actor.named(name)
    |> actor.start
  })
  |> supervision.map_data(fn(_subject) { Nil })
}

/// Loads the recorded connections, which the table then hands out in the order
/// of their ordinals.
pub fn load(
  table table: Subject(Command),
  connections connections: List(Prepared),
) -> Nil {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    Load(connections:, reply:)
  })
}

/// The next connection's script to hand out, or `Error(Nil)` when each has been.
/// A shell calls it, and exits with the table.
pub fn handout(table: Subject(Command)) -> Result(HandedOut, Nil) {
  actor.call(table, waiting: call_ms, sending: Handout)
}

/// The `Now` of an input the calling shell took, which counts the input as
/// taken; or why it matches no recorded input.
pub fn take(
  table table: Subject(Command),
  connection connection: String,
  taking taking: Input,
) -> Result(Now, Mismatch) {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    Take(connection:, taking:, shell: process.self(), reply:)
  })
}

/// The byte count of the next recorded read line not yet taken, or `None`.
pub fn next_read(
  table table: Subject(Command),
  connection connection: String,
) -> Option(Int) {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    NextRead(connection:, reply:)
  })
}

/// Sends the table a command and waits up to `within_ms` for the answer,
/// ending the wait at once when the table's process ends: a client's call.
fn ask(
  table: Subject(Command),
  within_ms: Int,
  make: fn(Subject(answer)) -> Command,
) -> Result(answer, Unanswered) {
  case process.subject_owner(table) {
    Error(Nil) -> Error(TableEnded)
    Ok(pid) -> {
      let reply = process.new_subject()
      let monitor = process.monitor(pid)
      process.send(table, make(reply))
      let heard =
        process.new_selector()
        |> process.select_map(reply, Replied)
        |> process.select_specific_monitor(monitor, fn(_down) { Gone })
        |> process.selector_receive(within: within_ms)
      process.demonitor_process(monitor)
      case heard {
        Ok(Replied(answer)) -> Ok(answer)
        Ok(Gone) -> Error(TableEnded)
        Error(Nil) -> Error(NotInTime)
      }
    }
  }
}

/// What a client's wait hears: the table's answer, or the table's end.
type Heard(answer) {
  Replied(answer: answer)
  Gone
}

/// How many recorded inputs the connection's shell has taken.
pub fn taken(
  table table: Subject(Command),
  connection connection: String,
) -> Result(Int, Unanswered) {
  ask(table, call_ms, fn(reply) { Taken(connection:, reply:) })
}

/// Waits up to `within_ms` until the connection's shell has taken `inputs`
/// recorded inputs.
pub fn await_taken(
  table table: Subject(Command),
  connection connection: String,
  inputs inputs: Int,
  within_ms within_ms: Int,
) -> Result(Nil, Waited) {
  case
    ask(table, within_ms, fn(reply) { AwaitTaken(connection:, inputs:, reply:) })
  {
    Ok(Ok(Nil)) -> Ok(Nil)
    Ok(Error(mismatch)) -> Error(Mismatched(mismatch:))
    Error(TableEnded) -> Error(WaitedTableEnded)
    Error(NotInTime) ->
      case taken(table:, connection:) {
        Ok(taken) -> Error(TimedOut(taken:))
        Error(NotInTime) | Error(TableEnded) -> Error(WaitedTableEnded)
      }
  }
}

/// Waits up to `within_ms` until the connection's script has been handed out.
pub fn await_handed_out(
  table table: Subject(Command),
  connection connection: String,
  within_ms within_ms: Int,
) -> Result(Nil, Unanswered) {
  ask(table, within_ms, fn(reply) { AwaitHandedOut(connection:, reply:) })
}

/// Tells the table a shell started a timer, which a firing is sent to.
pub fn timer_started(
  table table: Subject(Command),
  connection connection: String,
  timer timer: Int,
  started started: Started,
) -> Nil {
  process.send(table, TimerStarted(connection:, timer:, started:))
}

/// Tells the table a shell cancelled the timer it started with `reference`.
pub fn timer_cancelled(
  table table: Subject(Command),
  connection connection: String,
  timer timer: Int,
  reference reference: Reference,
) -> Nil {
  process.send(table, TimerCancelled(connection:, timer:, reference:))
}

/// Waits up to `within_ms` until the connection's shell has started the timer.
pub fn await_timer(
  table table: Subject(Command),
  connection connection: String,
  timer timer: Int,
  within_ms within_ms: Int,
) -> Result(Started, Unanswered) {
  ask(table, within_ms, fn(reply) { AwaitTimer(connection:, timer:, reply:) })
}

/// The process of the connection's shell, once it has asked for a `Now`.
pub fn shell_of(
  table table: Subject(Command),
  connection connection: String,
) -> Result(Option(Pid), Unanswered) {
  ask(table, call_ms, fn(reply) { ShellOf(connection:, reply:) })
}

/// The mismatch the connection's shell met, if it met one.
pub fn failure_of(
  table table: Subject(Command),
  connection connection: String,
) -> Result(Option(Mismatch), Unanswered) {
  ask(table, call_ms, fn(reply) { FailureOf(connection:, reply:) })
}

fn handle(state: State, command: Command) -> actor.Next(State, Command) {
  case command {
    Load(connections:, reply:) -> {
      process.send(reply, Nil)
      let sorted =
        list.sort(connections, fn(a, b) { int.compare(a.ordinal, b.ordinal) })
      actor.continue(
        State(
          ..state,
          connections: dict.from_list(
            list.map(sorted, fn(prepared) {
              #(prepared.name, entry_of(prepared))
            }),
          ),
          to_hand_out: list.map(sorted, fn(prepared) { prepared.name }),
        ),
      )
    }
    Handout(reply:) ->
      case state.to_hand_out {
        [] -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
        [name, ..rest] -> {
          let entry = entry_named(state, name)
          let assert NotHanded(plan:, progress:, waiting_for_hand_out:) = entry
            as "a connection to hand out has not been handed out"
          process.send(
            reply,
            Ok(HandedOut(name:, ordinal: plan.ordinal, seed: plan.seed)),
          )
          list.each(waiting_for_hand_out, process.send(_, Nil))
          actor.continue(
            State(
              ..state,
              to_hand_out: rest,
              connections: dict.insert(
                state.connections,
                name,
                HandedOutNotRunning(plan:, progress:),
              ),
            ),
          )
        }
      }
    Take(connection:, taking:, shell:, reply:) ->
      with_entry(state, connection, answer_take(_, taking:, shell:, reply:))
    NextRead(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, next_read_of(entry))
        entry
      })
    Taken(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, taken_by(entry))
        entry
      })
    AwaitTaken(connection:, inputs:, reply:) ->
      with_entry(state, connection, await_taken_by(_, inputs:, reply:))
    AwaitHandedOut(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        case entry {
          NotHanded(waiting_for_hand_out:, ..) ->
            NotHanded(..entry, waiting_for_hand_out: [
              reply,
              ..waiting_for_hand_out
            ])
          HandedOutNotRunning(..) | Running(..) | Failed(..) -> {
            process.send(reply, Nil)
            entry
          }
        }
      })
    TimerStarted(connection:, timer:, started:) -> {
      let #(waiting, others) =
        list.partition(state.timer_waiters, fn(waiter) {
          waiter.connection == connection && waiter.timer == timer
        })
      // The oldest wait is the last of those kept newest first.
      case list.reverse(waiting) {
        [oldest, ..newer] -> {
          process.send(oldest.reply, started)
          actor.continue(
            State(
              ..state,
              timer_waiters: list.append(list.reverse(newer), others),
            ),
          )
        }
        [] ->
          actor.continue(
            State(
              ..state,
              timers: dict.insert(state.timers, #(connection, timer), started),
            ),
          )
      }
    }
    TimerCancelled(connection:, timer:, reference:) ->
      case dict.get(state.timers, #(connection, timer)) {
        Ok(Started(reference: current, ..)) if current == reference ->
          actor.continue(
            State(
              ..state,
              timers: dict.delete(state.timers, #(connection, timer)),
            ),
          )
        Ok(Started(..)) | Error(Nil) -> actor.continue(state)
      }
    AwaitTimer(connection:, timer:, reply:) ->
      case dict.get(state.timers, #(connection, timer)) {
        Ok(started) -> {
          process.send(reply, started)
          actor.continue(
            State(
              ..state,
              timers: dict.delete(state.timers, #(connection, timer)),
            ),
          )
        }
        Error(Nil) ->
          actor.continue(
            State(..state, timer_waiters: [
              TimerWaiter(connection:, timer:, reply:),
              ..state.timer_waiters
            ]),
          )
      }
    ShellOf(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, shell_in(entry))
        entry
      })
    FailureOf(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, mismatch_in(entry))
        entry
      })
  }
}

fn entry_named(state: State, connection: String) -> Entry {
  let assert Ok(entry) = dict.get(state.connections, connection)
    as "a call names a connection of the loaded session"
  entry
}

fn with_entry(
  state: State,
  connection: String,
  change: fn(Entry) -> Entry,
) -> actor.Next(State, Command) {
  let entry = entry_named(state, connection)
  actor.continue(
    State(
      ..state,
      connections: dict.insert(state.connections, connection, change(entry)),
    ),
  )
}

fn entry_of(prepared: Prepared) -> Entry {
  NotHanded(
    plan: Plan(
      name: prepared.name,
      ordinal: prepared.ordinal,
      seed: prepared.seed,
      closing_line: prepared.closing_line,
    ),
    progress: Progress(
      pending: Untouched(inputs: prepared.inputs),
      taken: 0,
      waiting: [],
    ),
    waiting_for_hand_out: [],
  )
}

fn taken_by(entry: Entry) -> Int {
  case entry {
    NotHanded(progress:, ..)
    | HandedOutNotRunning(progress:, ..)
    | Running(progress:, ..) -> progress.taken
    Failed(taken:, ..) -> taken
  }
}

fn shell_in(entry: Entry) -> Option(Pid) {
  case entry {
    NotHanded(..) | HandedOutNotRunning(..) -> None
    Running(shell:, ..) | Failed(shell:, ..) -> Some(shell)
  }
}

fn mismatch_in(entry: Entry) -> Option(Mismatch) {
  case entry {
    NotHanded(..) | HandedOutNotRunning(..) | Running(..) -> None
    Failed(mismatch:, ..) -> Some(mismatch)
  }
}

fn next_read_of(entry: Entry) -> Option(Int) {
  case entry {
    NotHanded(progress:, ..)
    | HandedOutNotRunning(progress:, ..)
    | Running(progress:, ..) ->
      case progress.pending {
        Untouched(inputs:) -> next_read_in(inputs)
        PartlyRead(first:, later:, ..) -> next_read_in([first, ..later])
      }
    Failed(..) -> None
  }
}

fn next_read_in(pending: List(Recorded)) -> Option(Int) {
  case pending {
    [] -> None
    [Recorded(input: wire_recording.Read(bytes:), ..), ..] ->
      Some(bit_array.byte_size(bytes))
    [_, ..rest] -> next_read_in(rest)
  }
}

/// Answers a client's wait for `inputs` taken: at once when the shell has taken
/// them or has met a mismatch, else when it does.
fn await_taken_by(
  entry entry: Entry,
  inputs inputs: Int,
  reply reply: Subject(Result(Nil, Mismatch)),
) -> Entry {
  case entry {
    Failed(taken:, mismatch:, ..) -> {
      case taken >= inputs {
        True -> process.send(reply, Ok(Nil))
        False -> process.send(reply, Error(mismatch))
      }
      entry
    }
    NotHanded(progress:, ..) ->
      NotHanded(..entry, progress: waiting_for(progress:, inputs:, reply:))
    HandedOutNotRunning(progress:, ..) ->
      HandedOutNotRunning(
        ..entry,
        progress: waiting_for(progress:, inputs:, reply:),
      )
    Running(progress:, ..) ->
      Running(..entry, progress: waiting_for(progress:, inputs:, reply:))
  }
}

fn waiting_for(
  progress progress: Progress,
  inputs inputs: Int,
  reply reply: Subject(Result(Nil, Mismatch)),
) -> Progress {
  case progress.taken >= inputs {
    True -> {
      process.send(reply, Ok(Nil))
      progress
    }
    False ->
      Progress(..progress, waiting: [
        TakenWaiter(inputs:, reply:),
        ..progress.waiting
      ])
  }
}

/// Gives the shell the `Now` of the input it took, or the mismatch that ended
/// its inputs, and answers the waiters the change reaches.
fn answer_take(
  entry entry: Entry,
  taking taking: Input,
  shell shell: Pid,
  reply reply: Subject(Result(Now, Mismatch)),
) -> Entry {
  case entry {
    Failed(mismatch:, ..) -> {
      process.send(reply, Error(mismatch))
      entry
    }
    NotHanded(..) ->
      panic as "a shell asks for a Now only after its script was handed out"
    HandedOutNotRunning(plan:, progress:) | Running(plan:, progress:, ..) ->
      case take_input(plan:, progress:, taking:) {
        Ok(#(progress, now)) -> {
          process.send(reply, Ok(now))
          Running(plan:, shell:, progress: notify_taken(progress))
        }
        Error(mismatch) -> {
          process.send(reply, Error(mismatch))
          list.each(progress.waiting, fn(waiter) {
            process.send(waiter.reply, Error(mismatch))
          })
          Failed(plan:, shell:, mismatch:, taken: progress.taken)
        }
      }
  }
}

/// Matches an input the shell took with the next recorded one: the progress
/// with that input taken, and its `Now`.
fn take_input(
  plan plan: Plan,
  progress progress: Progress,
  taking taking: Input,
) -> Result(#(Progress, Now), Mismatch) {
  case progress.pending {
    Untouched(inputs: []) -> Error(Unrecorded(line: plan.closing_line))
    Untouched(inputs: [first, ..later]) ->
      match_input(plan:, progress:, first:, later:, have: 0, taking:)
    PartlyRead(have:, first:, later:) ->
      match_input(plan:, progress:, first:, later:, have:, taking:)
  }
}

fn match_input(
  plan plan: Plan,
  progress progress: Progress,
  first first: Recorded,
  later later: List(Recorded),
  have have: Int,
  taking taking: Input,
) -> Result(#(Progress, Now), Mismatch) {
  case first.input, taking {
    wire_recording.Read(bytes: recorded), wire_recording.Read(bytes: arrived) ->
      take_read(
        plan:,
        progress:,
        first:,
        size: bit_array.byte_size(recorded),
        later:,
        have: have + bit_array.byte_size(arrived),
        taking:,
      )
    recorded, _ ->
      case wire_recording.same_kind(recorded, taking) {
        True ->
          Ok(#(
            Progress(
              ..progress,
              pending: Untouched(inputs: later),
              taken: progress.taken + 1,
            ),
            first.at,
          ))
        False ->
          Error(OutOfOrder(line: first.line, expected: recorded, taken: taking))
      }
  }
}

/// Takes bytes of the recorded reads: each recorded read line is taken once its
/// last byte has been, and the `Now` is that of the line the last byte falls in.
/// Bytes beyond the recorded read lines match no input.
fn take_read(
  plan plan: Plan,
  progress progress: Progress,
  first first: Recorded,
  size size: Int,
  later later: List(Recorded),
  have have: Int,
  taking taking: Input,
) -> Result(#(Progress, Now), Mismatch) {
  use <- bool.guard(
    when: have < size,
    return: Ok(#(
      Progress(..progress, pending: PartlyRead(have:, first:, later:)),
      first.at,
    )),
  )
  let progress =
    Progress(
      ..progress,
      pending: Untouched(inputs: later),
      taken: progress.taken + 1,
    )
  case have - size, later {
    0, _ -> Ok(#(progress, first.at))
    _, [] -> Error(Unrecorded(line: plan.closing_line))
    more, [next, ..rest] ->
      case next.input {
        wire_recording.Read(bytes:) ->
          take_read(
            plan:,
            progress:,
            first: next,
            size: bit_array.byte_size(bytes),
            later: rest,
            have: more,
            taking:,
          )
        wire_recording.Accepted
        | wire_recording.Answered(..)
        | wire_recording.TimerFired(..)
        | wire_recording.PeerClosed
        | wire_recording.ReadFailed
        | wire_recording.WriteFailed
        | wire_recording.Woken
        | wire_recording.WatchEnded
        | wire_recording.Stopping ->
          Error(OutOfOrder(line: next.line, expected: next.input, taken: taking))
      }
  }
}

/// Answers the waiters whose count the shell has now reached.
fn notify_taken(progress: Progress) -> Progress {
  let #(reached, waiting) =
    list.partition(progress.waiting, fn(waiter) {
      waiter.inputs <= progress.taken
    })
  list.each(reached, fn(waiter) { process.send(waiter.reply, Ok(Nil)) })
  Progress(..progress, waiting:)
}
