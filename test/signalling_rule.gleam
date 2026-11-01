//// A connection rule for the tests of what reaches a connection shell from
//// other processes and of the effects that name them: a delivered message, a
//// watch and its end, and a timer. The client's bytes are commands, and the
//// rule answers with a record of every input it takes, so a test reads what
//// the shell fed the rule and in which order.
////
//// A command is four bytes: a letter, one byte `n` and a 16-bit number of
//// milliseconds, used by a timer.
////
//// ```
//// 'W' n    watch n on Sessions            'T' n ms start timer n, which fires after ms
//// 'X' n    cancel timer n                 'P' n    write the record 'p' n
//// 'Z' n ms start timer n, which would fire after ms, and cancel it in the
////          same step, so no machine's speed decides whether it fired first
//// ```
////
//// Each record the rule writes is nine bytes: a letter and a 64-bit signed
//// number.
////
//// ```
//// 'c' id   the connection was accepted as connection id
//// 'w' n    the message n was delivered    'e' n    watch n ended
////          (a message -n also watches 1 to n on Sessions)
//// 't' n    timer n fired                  'p' n    the answer to 'P' n
//// ```
////
//// The rule stops when the client closes or its socket fails.

import genesis_prime/step.{
  type ConnectionEffect, type ConnectionInput, type ConnectionRule,
  type ConnectionStep, type Effect, Accepted, CancelTimer, Effects, Input, Log,
  LogLine, LogWarning, OwnEffect, OwnEvent, PeerClosed, Read, ReadFailed, Rule,
  Sessions, StartTimer, Stop, TimerFired, TimerId, Watch, WatchEnded, WatchId,
  Woken, Write, WriteFailed,
}
import gleam/int
import gleam/list

/// The commands not yet run.
pub type State {
  State(pending: BitArray)
}

/// The letters of the commands.
pub const watch_command = 0x57

pub const timer_command = 0x54

pub const cancel_command = 0x58

pub const pong_command = 0x50

pub const start_then_cancel_command = 0x5A

/// The letters that start a record.
pub const accepted = 0x63

pub const woken = 0x77

pub const watch_ended = 0x65

pub const timer_fired = 0x74

pub const pong = 0x70

/// The rule as its shell runs it; a delivered message is an `Int`.
pub fn rule() -> ConnectionRule(Nil, State, Nil, Int, Nil) {
  Rule(name: "signalling_rule", settings: Nil, new:, step:)
}

/// The rule's first state.
pub fn new(_settings: Nil) -> State {
  State(pending: <<>>)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: ConnectionInput(Int, Nil),
) -> #(State, ConnectionStep(Nil)) {
  let Input(event:, ..) = input
  case event {
    OwnEvent(Accepted(connection: step.ConnectionId(id), ..)) -> #(
      state,
      Effects([record(accepted, id)]),
    )
    OwnEvent(Read(bytes:)) ->
      run(State(pending: <<state.pending:bits, bytes:bits>>), [])
    OwnEvent(Woken(message:)) -> #(state, Effects(woken_effects(message)))
    WatchEnded(watch: WatchId(n)) -> #(state, Effects([record(watch_ended, n)]))
    OwnEvent(TimerFired(timer: TimerId(n))) -> #(
      state,
      Effects([record(timer_fired, n)]),
    )
    OwnEvent(PeerClosed) | step.Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(ReadFailed(..)) | OwnEvent(WriteFailed(..)) -> #(
      state,
      Effects([warn("the socket failed"), Stop]),
    )
    OwnEvent(step.Answered(..)) -> #(
      state,
      Effects([warn("an input a connection does not take"), Stop]),
    )
  }
}

/// What a delivered message does: the record of it, and, for a negative
/// message `-n`, the watches 1 to `n` on Sessions in that order after the
/// record, so a test can start watches from a message that waits in the
/// mailbox.
fn woken_effects(message: Int) -> List(Effect(ConnectionEffect)) {
  let watches = case message < 0 {
    True ->
      list.repeat(Nil, int.negate(message))
      |> list.index_map(fn(_, index) {
        command(letter: watch_command, n: index + 1, milliseconds: 0)
      })
    False -> []
  }
  [record(woken, message), ..watches]
}

/// Runs the commands the client has sent, in order; `effects` are the effects
/// so far, the last first.
fn run(
  state: State,
  effects: List(Effect(ConnectionEffect)),
) -> #(State, ConnectionStep(Nil)) {
  case state.pending {
    <<letter, n, milliseconds:16, rest:bytes>> ->
      run(
        State(pending: rest),
        list.append(list.reverse(commands(letter:, n:, milliseconds:)), effects),
      )
    _ -> #(state, Effects(list.reverse(effects)))
  }
}

/// The effects of one command, in the order they are carried out.
fn commands(
  letter letter: Int,
  n n: Int,
  milliseconds milliseconds: Int,
) -> List(Effect(ConnectionEffect)) {
  case letter {
    _ if letter == start_then_cancel_command -> [
      command(letter: timer_command, n:, milliseconds:),
      command(letter: cancel_command, n:, milliseconds: 0),
    ]
    _ -> [command(letter:, n:, milliseconds:)]
  }
}

fn command(
  letter letter: Int,
  n n: Int,
  milliseconds milliseconds: Int,
) -> Effect(ConnectionEffect) {
  case letter {
    _ if letter == watch_command -> Watch(WatchId(n), Sessions)
    _ if letter == timer_command ->
      OwnEffect(StartTimer(TimerId(n), milliseconds))
    _ if letter == cancel_command -> OwnEffect(CancelTimer(TimerId(n)))
    _ if letter == pong_command -> record(pong, n)
    _ -> panic as "the test sent a letter the signalling rule has no command for"
  }
}

fn record(letter: Int, number: Int) -> Effect(ConnectionEffect) {
  OwnEffect(Write(<<letter, number:64>>))
}

fn warn(text: String) -> Effect(ConnectionEffect) {
  Log(LogLine(level: LogWarning, text:, about: step.no_one))
}
