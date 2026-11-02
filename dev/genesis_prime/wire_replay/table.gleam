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
//// - **A `Now`.** `take` matches an input the shell took with the next
////   recorded input: another kind than the recording's next is an ordering
////   mismatch, an input after the last recorded one is an unrecorded input, and
////   either is kept against the connection, so the client sees it however late
////   it asks. A read of `n` bytes takes the `Now` of the recorded read line its
////   last byte falls in, and the line counts as taken once its last byte has
////   been; reads that are parts of one line leave the line's bytes taken so far
////   (`partial`).
//// - **A wait.** The client's wait for a count of taken inputs or a started
////   timer is a message the table answers when it can: at once, or when the
////   shell takes the input or starts the timer. The client bounds the wait
////   itself; a waiter whose client has given up is answered into a mailbox
////   nobody reads.

import genesis_prime/connection/script.{type Elapsed, type Taking}
import genesis_prime/step.{type Now}
import genesis_prime/wire_recording.{type Input}
import gleam/bit_array
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
    seed: BitArray,
    inputs: List(Recorded),
    closing_line: Int,
  )
}

/// What the table gave a script that asked for its connection.
pub type Handed {
  Handed(name: String, ordinal: Int, seed: BitArray)
}

/// Why an input the shell took matches no recorded input.
pub type Mismatch {
  /// The shell took an input after the last recorded one; `line` is the
  /// recording's closing line.
  Unrecorded(line: Int)
  /// The shell took an input of another kind than the next recorded one,
  /// which is on `line`.
  OutOfOrder(line: Int, expected: Taking, taken: Taking)
}

/// A timer a shell started: where its firing is sent, and the reference of the
/// start, which tells it from a stale firing.
pub type Started {
  Started(subject: Subject(Elapsed), reference: Reference)
}

/// What the table is told. Only this module makes one, through its functions.
pub opaque type Command {
  Load(connections: List(Prepared), reply: Subject(Nil))
  Handout(reply: Subject(Result(Handed, Nil)))
  Take(
    connection: String,
    taking: Taking,
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
  AwaitHanded(connection: String, reply: Subject(Nil))
  TimerStarted(connection: String, timer: Int, started: Started)
  TimerCancelled(connection: String, timer: Int, reference: Reference)
  AwaitTimer(connection: String, timer: Int, reply: Subject(Started))
  ShellOf(connection: String, reply: Subject(Option(Pid)))
  FailureOf(connection: String, reply: Subject(Option(Mismatch)))
}

type Entry {
  Entry(
    name: String,
    ordinal: Int,
    seed: BitArray,
    closing_line: Int,
    pending: List(Recorded),
    partial: Int,
    taken: Int,
    handed: Bool,
    shell: Option(Pid),
    failure: Option(Mismatch),
    handed_waiters: List(Subject(Nil)),
    taken_waiters: List(#(Int, Subject(Result(Nil, Mismatch)))),
  )
}

type State {
  State(
    connections: Dict(String, Entry),
    to_hand_out: List(String),
    timers: Dict(#(String, Int), Started),
    timer_waiters: List(#(String, Int, Subject(Started))),
  )
}

/// How long a call to the table may take, in milliseconds. The table answers
/// at once, so only a table that has ended or is stuck is waited for this long.
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
pub fn load(table: Subject(Command), connections: List(Prepared)) -> Nil {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    Load(connections:, reply:)
  })
}

/// The next connection's script to hand out, or `Error(Nil)` when each has been.
pub fn handout(table: Subject(Command)) -> Result(Handed, Nil) {
  actor.call(table, waiting: call_ms, sending: Handout)
}

/// The `Now` of an input the calling shell took, which counts the input as
/// taken; or why it matches no recorded input.
pub fn take(
  table table: Subject(Command),
  connection connection: String,
  taking taking: Taking,
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

/// How many recorded inputs the connection's shell has taken.
pub fn taken(
  table table: Subject(Command),
  connection connection: String,
) -> Int {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    Taken(connection:, reply:)
  })
}

/// Why a wait for the shell to take inputs ended.
pub type Waited {
  /// The shell took an input that matches no recorded one.
  Mismatched(mismatch: Mismatch)
  /// The shell had not taken that many inputs in time; `taken` is how many it
  /// had.
  TimedOut(taken: Int)
}

/// Waits up to `within_ms` until the connection's shell has taken `inputs`
/// recorded inputs.
pub fn await_taken(
  table table: Subject(Command),
  connection connection: String,
  inputs inputs: Int,
  within_ms within_ms: Int,
) -> Result(Nil, Waited) {
  let reply = process.new_subject()
  process.send(table, AwaitTaken(connection:, inputs:, reply:))
  case process.receive(reply, within: within_ms) {
    Ok(Ok(Nil)) -> Ok(Nil)
    Ok(Error(mismatch)) -> Error(Mismatched(mismatch:))
    Error(Nil) -> Error(TimedOut(taken: taken(table:, connection:)))
  }
}

/// Waits up to `within_ms` until the connection's script has been handed out.
pub fn await_handed(
  table table: Subject(Command),
  connection connection: String,
  within_ms within_ms: Int,
) -> Result(Nil, Nil) {
  let reply = process.new_subject()
  process.send(table, AwaitHanded(connection:, reply:))
  process.receive(reply, within: within_ms)
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
) -> Result(Started, Nil) {
  let reply = process.new_subject()
  process.send(table, AwaitTimer(connection:, timer:, reply:))
  process.receive(reply, within: within_ms)
}

/// The process of the connection's shell, once it has asked for a `Now`.
pub fn shell_of(
  table table: Subject(Command),
  connection connection: String,
) -> Option(Pid) {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    ShellOf(connection:, reply:)
  })
}

/// The mismatch the connection's shell met, if it met one.
pub fn failure_of(
  table table: Subject(Command),
  connection connection: String,
) -> Option(Mismatch) {
  actor.call(table, waiting: call_ms, sending: fn(reply) {
    FailureOf(connection:, reply:)
  })
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
          let assert Ok(entry) = dict.get(state.connections, name)
            as "a connection to hand out is loaded"
          process.send(
            reply,
            Ok(Handed(name:, ordinal: entry.ordinal, seed: entry.seed)),
          )
          list.each(entry.handed_waiters, process.send(_, Nil))
          actor.continue(
            State(
              ..state,
              to_hand_out: rest,
              connections: dict.insert(
                state.connections,
                name,
                Entry(..entry, handed: True, handed_waiters: []),
              ),
            ),
          )
        }
      }
    Take(connection:, taking:, shell:, reply:) ->
      with_entry(state, connection, fn(entry) {
        let entry = Entry(..entry, shell: Some(shell))
        case entry.failure {
          Some(mismatch) -> {
            process.send(reply, Error(mismatch))
            entry
          }
          None ->
            case take_input(entry, taking) {
              Ok(#(entry, now)) -> {
                process.send(reply, Ok(now))
                notify_taken(entry)
              }
              Error(mismatch) -> {
                process.send(reply, Error(mismatch))
                notify_failed(Entry(..entry, failure: Some(mismatch)), mismatch)
              }
            }
        }
      })
    NextRead(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, next_read_of(entry.pending))
        entry
      })
    Taken(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, entry.taken)
        entry
      })
    AwaitTaken(connection:, inputs:, reply:) ->
      with_entry(state, connection, fn(entry) {
        case entry.taken >= inputs, entry.failure {
          True, _ -> {
            process.send(reply, Ok(Nil))
            entry
          }
          False, Some(mismatch) -> {
            process.send(reply, Error(mismatch))
            entry
          }
          False, None ->
            Entry(..entry, taken_waiters: [
              #(inputs, reply),
              ..entry.taken_waiters
            ])
        }
      })
    AwaitHanded(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        case entry.handed {
          True -> {
            process.send(reply, Nil)
            entry
          }
          False ->
            Entry(..entry, handed_waiters: [reply, ..entry.handed_waiters])
        }
      })
    TimerStarted(connection:, timer:, started:) -> {
      let #(waiting, others) =
        list.partition(state.timer_waiters, fn(waiter) {
          waiter.0 == connection && waiter.1 == timer
        })
      list.each(waiting, fn(waiter) { process.send(waiter.2, started) })
      actor.continue(
        State(
          ..state,
          timers: dict.insert(state.timers, #(connection, timer), started),
          timer_waiters: others,
        ),
      )
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
              #(connection, timer, reply),
              ..state.timer_waiters
            ]),
          )
      }
    ShellOf(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, entry.shell)
        entry
      })
    FailureOf(connection:, reply:) ->
      with_entry(state, connection, fn(entry) {
        process.send(reply, entry.failure)
        entry
      })
  }
}

fn with_entry(
  state: State,
  connection: String,
  change: fn(Entry) -> Entry,
) -> actor.Next(State, Command) {
  let assert Ok(entry) = dict.get(state.connections, connection)
    as "a call names a connection of the loaded session"
  actor.continue(
    State(
      ..state,
      connections: dict.insert(state.connections, connection, change(entry)),
    ),
  )
}

fn entry_of(prepared: Prepared) -> Entry {
  Entry(
    name: prepared.name,
    ordinal: prepared.ordinal,
    seed: prepared.seed,
    closing_line: prepared.closing_line,
    pending: prepared.inputs,
    partial: 0,
    taken: 0,
    handed: False,
    shell: None,
    failure: None,
    handed_waiters: [],
    taken_waiters: [],
  )
}

/// Matches an input the shell took with the next recorded one: the entry with
/// that input taken, and its `Now`.
fn take_input(entry: Entry, taking: Taking) -> Result(#(Entry, Now), Mismatch) {
  case entry.pending, taking {
    [], _ -> Error(Unrecorded(line: entry.closing_line))
    [Recorded(input: wire_recording.Read(..), ..), ..], script.Read(byte_count:)
    -> take_read(entry, byte_count)
    [Recorded(line:, input:, at:), ..rest], _ ->
      case taking_of(input) == taking {
        True -> Ok(#(Entry(..entry, pending: rest, taken: entry.taken + 1), at))
        False ->
          Error(OutOfOrder(line:, expected: taking_of(input), taken: taking))
      }
  }
}

/// Takes `byte_count` bytes of the recorded reads: each recorded read line is
/// taken once its last byte has been, and the `Now` is that of the line the last
/// byte falls in. Bytes beyond the recorded read lines match no input.
fn take_read(entry: Entry, byte_count: Int) -> Result(#(Entry, Now), Mismatch) {
  place(
    entry:,
    pending: entry.pending,
    have: entry.partial + byte_count,
    taken: entry.taken,
    byte_count:,
  )
}

fn place(
  entry entry: Entry,
  pending pending: List(Recorded),
  have have: Int,
  taken taken: Int,
  byte_count byte_count: Int,
) -> Result(#(Entry, Now), Mismatch) {
  case pending {
    [Recorded(input: wire_recording.Read(bytes:), at:, ..), ..rest] -> {
      let size = bit_array.byte_size(bytes)
      case have >= size, have - size {
        True, 0 ->
          Ok(#(Entry(..entry, pending: rest, partial: 0, taken: taken + 1), at))
        True, more ->
          place(
            entry:,
            pending: rest,
            have: more,
            taken: taken + 1,
            byte_count:,
          )
        False, _ -> Ok(#(Entry(..entry, pending:, partial: have, taken:), at))
      }
    }
    [Recorded(line:, input:, ..), ..] ->
      Error(OutOfOrder(
        line:,
        expected: taking_of(input),
        taken: script.Read(byte_count:),
      ))
    [] -> Error(Unrecorded(line: entry.closing_line))
  }
}

fn next_read_of(pending: List(Recorded)) -> Option(Int) {
  case pending {
    [] -> None
    [Recorded(input: wire_recording.Read(bytes:), ..), ..] ->
      Some(bit_array.byte_size(bytes))
    [_, ..rest] -> next_read_of(rest)
  }
}

/// What the clock is told when the shell takes the recorded `input`.
fn taking_of(input: Input) -> Taking {
  case input {
    wire_recording.Accepted -> script.Accepted
    wire_recording.Read(bytes:) ->
      script.Read(byte_count: bit_array.byte_size(bytes))
    wire_recording.Answered(..) -> script.Answered
    wire_recording.TimerFired(..) -> script.TimerFired
    wire_recording.PeerClosed -> script.PeerClosed
    wire_recording.ReadFailed -> script.ReadFailed
    wire_recording.WriteFailed -> script.WriteFailed
    wire_recording.Woken -> script.Woken
    wire_recording.WatchEnded -> script.WatchEnded
    wire_recording.Stopping -> script.Stopping
  }
}

/// Answers the waiters whose count the shell has now reached.
fn notify_taken(entry: Entry) -> Entry {
  let #(reached, waiting) =
    list.partition(entry.taken_waiters, fn(waiter) { waiter.0 <= entry.taken })
  list.each(reached, fn(waiter) { process.send(waiter.1, Ok(Nil)) })
  Entry(..entry, taken_waiters: waiting)
}

/// Answers every waiter with the mismatch: no later input will be given a
/// `Now`.
fn notify_failed(entry: Entry, mismatch: Mismatch) -> Entry {
  list.each(entry.taken_waiters, fn(waiter) {
    process.send(waiter.1, Error(mismatch))
  })
  Entry(..entry, taken_waiters: [])
}
