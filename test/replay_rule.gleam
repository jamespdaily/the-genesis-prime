//// A connection rule for the tests of the wire replay: it answers commands
//// with records that depend on nothing but the bytes it was sent and the
//// inputs it takes, so a recording of it written by hand holds the bytes the
//// rule writes again. A command is four bytes: a letter, one byte `n` and a
//// 16-bit number of milliseconds.
////
//// ```
//// 'E' n     write the record 'e' n       'T' n ms  start timer n, which fires after ms
//// 'X' n     cancel timer n               'W' n     watch n on Sessions
//// 'R' n     refuse: log a warning that names n, and stop
//// ```
////
//// Each record the rule writes is nine bytes: a letter and a 64-bit number.
////
//// ```
//// 'e' n   the answer to 'E' n          't' n   timer n fired
//// 'w' n   watch n ended
//// ```
////
//// The rule stops when the client closes, when the server stops and when it
//// takes an input it has no use for (a delivered message, an answer).

import connection_rule_support
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionInput, type ConnectionRule,
  type ConnectionStep, type Effect, Accepted, CancelTimer, Effects, Input,
  OwnEffect, OwnEvent, PeerClosed, Read, ReadFailed, Rule, Sessions, StartTimer,
  Stop, TimerFired, TimerId, Watch, WatchEnded, WatchId, WriteFailed,
}
import gleam/int
import gleam/list

/// The commands not yet run.
pub type State {
  State(pending: BitArray)
}

/// The letters of the commands.
pub const echo_command = 0x45

pub const timer_command = 0x54

pub const cancel_command = 0x58

pub const watch_command = 0x57

pub const refuse_command = 0x52

/// The letters that start a record.
pub const echoed = 0x65

pub const timer_fired = 0x74

pub const watch_ended = 0x77

/// The text the rule logs when it refuses command `n`.
pub fn refusal(n: Int) -> String {
  "replay_rule refused command " <> int.to_string(n)
}

/// The rule as its shell runs it.
pub fn rule() -> ConnectionRule(Nil, State, Nil, Nil, Nil) {
  Rule(name: "replay_rule", settings: Nil, new:, step:)
}

/// The rule's first state.
pub fn new(_settings: Nil) -> State {
  State(pending: <<>>)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: ConnectionInput(Nil, Nil),
) -> #(State, ConnectionStep(Nil)) {
  let Input(event:, ..) = input
  case event {
    OwnEvent(Accepted(..)) -> #(state, Effects([]))
    OwnEvent(Read(bytes:)) ->
      run(State(pending: <<state.pending:bits, bytes:bits>>), [])
    OwnEvent(TimerFired(timer: TimerId(n))) -> #(
      state,
      Effects([connection_rule_support.record(letter: timer_fired, number: n)]),
    )
    WatchEnded(watch: WatchId(n)) -> #(
      state,
      Effects([connection_rule_support.record(letter: watch_ended, number: n)]),
    )
    OwnEvent(PeerClosed) | step.Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(ReadFailed(..)) | OwnEvent(WriteFailed(..)) -> #(
      state,
      Effects([connection_rule_support.warn("the socket failed"), Stop]),
    )
    OwnEvent(step.Woken(..)) | OwnEvent(step.Answered(..)) -> #(
      state,
      Effects([
        connection_rule_support.warn("an input the replay rule does not take"),
        Stop,
      ]),
    )
  }
}

/// Runs the commands the client has sent, in order; `effects` are the effects
/// so far, the last first. A refusal ends the run: the commands after it are
/// not run.
fn run(
  state: State,
  effects: List(Effect(ConnectionEffect(Nil))),
) -> #(State, ConnectionStep(Nil)) {
  case state.pending {
    <<letter, n, _:16, rest:bytes>> if letter == refuse_command -> #(
      State(pending: rest),
      Effects(
        list.reverse([Stop, connection_rule_support.warn(refusal(n)), ..effects]),
      ),
    )
    <<letter, n, milliseconds:16, rest:bytes>> ->
      run(State(pending: rest), [command(letter:, n:, milliseconds:), ..effects])
    _ -> #(state, Effects(list.reverse(effects)))
  }
}

fn command(
  letter letter: Int,
  n n: Int,
  milliseconds milliseconds: Int,
) -> Effect(ConnectionEffect(Nil)) {
  case letter {
    _ if letter == echo_command ->
      connection_rule_support.record(letter: echoed, number: n)
    _ if letter == timer_command ->
      OwnEffect(StartTimer(TimerId(n), milliseconds))
    _ if letter == cancel_command -> OwnEffect(CancelTimer(TimerId(n)))
    _ if letter == watch_command -> Watch(WatchId(n), Sessions)
    _ -> panic as "the test sent a letter the replay rule has no command for"
  }
}
