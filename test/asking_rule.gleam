//// A connection rule for the tests of asks: the client's bytes are commands,
//// and the rule answers with a record of everything it takes, so a test reads
//// what the shell fed the rule and in which order.
////
//// A command is four bytes: a letter, one byte `n` and a 16-bit wait in
//// milliseconds, which is how long an ask has before its deadline.
////
//// ```
//// 'E' n   ask the gate to echo n        'W' n   ask the gate for key n
//// 'O' n   ask the gate to open key n    'I'     ask the gate to ignore the ask
//// 'C'     ask the gate to crash         'S' n   ask the store for "login-n"
//// 'P' n   no ask: write the pong 'p' n at once
//// 'Q' n   no ask: the step is `Stop` and then a write of 'q' n
//// ```
////
//// Each record the rule writes is twelve bytes: a letter, the ask's number
//// (from 1), a code, one byte and a 64-bit signed millisecond reading.
////
//// ```
//// 'a' ask 0 0 deadline    an ask is made, written with the step's effects
//// 'r' ask code n now      the ask's outcome came back
//// 'l' ask 0 0 now         the ask's answer came late
//// 's' 0 0 0 deadline      the server is stopping
//// ```
////
//// The rule stops when the client closes, and when the server stops once no
//// answer is still due.

import gate_rule
import genesis_prime/step.{
  type Effect, type Input, type Outcome, type Rule, type Step, Accepted,
  Answered, AnsweredLate, Ask, AskId, Effects, EffectsThenAsk, EndedBeforeAnswer,
  Input, Log, LogLine, LogWarning, NoAnswerInTime, NotRunning, PeerClosed, Read,
  ReadFailed, Rule, Socket, Stop, StoppedWaiting, Stopping, Write, WriteFailed,
}
import genesis_prime/store
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// What the rule asks, each naming the process it asks.
pub type Request {
  OfGate(gate_rule.Message)
  OfStore(store.Request)
}

/// What comes back, each the answer of the process asked.
pub type Answer {
  FromGate(gate_rule.Answer)
  FromStore(store.Answer)
}

/// The commands not yet run, the next ask's number, the asks whose answer may
/// still come late, and whether the server is stopping.
pub type State {
  State(pending: BitArray, next_ask: Int, late: Set(Int), stopping: Bool)
}

/// The letters of the commands.
pub const echo_command = 0x45

pub const await_command = 0x57

pub const open_command = 0x4F

pub const ignore_command = 0x49

pub const crash_command = 0x43

pub const store_command = 0x53

pub const ping_command = 0x50

pub const stop_then_write_command = 0x51

/// The letters that start a record.
pub const asked = 0x61

pub const outcome = 0x72

pub const late = 0x6C

pub const stopping = 0x73

/// The code of a record whose outcome is each of these.
pub const code_echoed = 0

pub const code_not_running = 1

pub const code_no_answer_in_time = 2

pub const code_ended_before_answer = 3

pub const code_stopped_waiting = 4

pub const code_opened = 6

pub const code_account_found = 7

pub const code_no_such_account = 8

pub const code_unavailable = 9

/// The rule as its shell runs it.
pub fn rule() -> Rule(Nil, State, Nil, Answer, Nil, Request) {
  Rule(name: "asking_rule", settings: Nil, new:, step:)
}

/// The rule's first state.
pub fn new(_settings: Nil) -> State {
  State(pending: <<>>, next_ask: 1, late: set.new(), stopping: False)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  let Input(now:, event:) = input
  case event {
    Socket(Accepted(..)) -> #(state, Effects([]))
    Socket(Read(bytes:)) ->
      run(
        state: State(..state, pending: <<state.pending:bits, bytes:bits>>),
        now:,
        written: [],
      )
    Socket(PeerClosed) -> #(state, Effects([Stop]))
    Socket(ReadFailed(..)) | Socket(WriteFailed(..)) -> #(
      state,
      Effects([warn("the socket failed"), Stop]),
    )
    Answered(ask: AskId(number), outcome: result) -> {
      let #(code, extra) = coded(result)
      let state = case result {
        NoAnswerInTime | StoppedWaiting ->
          State(..state, late: set.insert(state.late, number))
        step.Answer(..) | NotRunning | EndedBeforeAnswer -> state
      }
      run(state:, now:, written: [
        Write(record(
          letter: outcome,
          number:,
          code:,
          extra:,
          milliseconds: now.monotonic_ms,
        )),
      ])
    }
    AnsweredLate(ask: AskId(number)) -> {
      let state = State(..state, late: set.delete(state.late, number))
      let written =
        Write(record(
          letter: late,
          number:,
          code: 0,
          extra: 0,
          milliseconds: now.monotonic_ms,
        ))
      case state.stopping && set.is_empty(state.late) {
        True -> #(state, Effects([written, Stop]))
        False -> #(state, Effects([written]))
      }
    }
    Stopping(deadline_ms:) -> {
      let state = State(..state, stopping: True)
      let written =
        Write(record(
          letter: stopping,
          number: 0,
          code: 0,
          extra: 0,
          milliseconds: deadline_ms,
        ))
      case set.is_empty(state.late) {
        True -> #(state, Effects([written, Stop]))
        False -> #(state, Effects([written]))
      }
    }
    step.Started
    | step.Woken(..)
    | step.Asked(..)
    | step.WatchEnded(..)
    | step.TimerFired(..) -> #(
      state,
      Effects([warn("an input a connection does not take"), Stop]),
    )
  }
}

/// Runs the commands the client has sent, in order, until one asks: the step
/// then ends in that ask, and the commands after it wait in the state.
fn run(
  state state: State,
  now now: step.Now,
  written written: List(Effect(Nil)),
) -> #(State, Step(Nil, Request)) {
  case state.pending {
    <<letter, n, wait:16, rest:bytes>> ->
      case letter {
        _ if letter == ping_command ->
          run(state: State(..state, pending: rest), now:, written: [
            Write(<<0x70, n>>),
            ..written
          ])
        _ if letter == stop_then_write_command -> #(
          State(..state, pending: rest),
          Effects(list.reverse([Write(<<0x71, n>>), Stop, ..written])),
        )
        _ ->
          case request_for(letter, n) {
            Ok(request) -> ask(state:, now:, written:, rest:, request:, wait:)
            Error(Nil) -> #(
              state,
              Effects(
                list.reverse([Stop, warn("an unknown command"), ..written]),
              ),
            )
          }
      }
    _ -> #(state, Effects(list.reverse(written)))
  }
}

/// The request a command's letter asks for, with its byte `n`.
fn request_for(letter: Int, n: Int) -> Result(Request, Nil) {
  case letter {
    _ if letter == echo_command -> Ok(OfGate(gate_rule.Echo(n)))
    _ if letter == await_command -> Ok(OfGate(gate_rule.Await(n)))
    _ if letter == open_command -> Ok(OfGate(gate_rule.Open(n)))
    _ if letter == ignore_command -> Ok(OfGate(gate_rule.Ignore))
    _ if letter == crash_command -> Ok(OfGate(gate_rule.Crash))
    _ if letter == store_command ->
      Ok(OfStore(store.Login(store.FindAccount("login-" <> int.to_string(n)))))
    _ -> Error(Nil)
  }
}

fn ask(
  state state: State,
  now now: step.Now,
  written written: List(Effect(Nil)),
  rest rest: BitArray,
  request request: Request,
  wait wait: Int,
) -> #(State, Step(Nil, Request)) {
  let number = state.next_ask
  let deadline = now.monotonic_ms + wait
  #(
    State(..state, pending: rest, next_ask: number + 1),
    EffectsThenAsk(
      effects: list.reverse([
        Write(record(
          letter: asked,
          number:,
          code: 0,
          extra: 0,
          milliseconds: deadline,
        )),
        ..written
      ]),
      ask: Ask(ask: AskId(number), request:, deadline_ms: deadline),
    ),
  )
}

/// An outcome's code and its byte.
fn coded(result: Outcome(Answer)) -> #(Int, Int) {
  case result {
    step.Answer(FromGate(gate_rule.Echoed(n))) -> #(code_echoed, n)
    step.Answer(FromGate(gate_rule.Opened(key:))) -> #(code_opened, key)
    step.Answer(FromStore(store.ForLogin(store.AccountFound(account:)))) -> {
      let store.AccountId(id) = account.account_id
      #(code_account_found, id % 256)
    }
    step.Answer(FromStore(store.ForLogin(store.NoSuchAccount))) -> #(
      code_no_such_account,
      0,
    )
    step.Answer(FromStore(store.Unavailable)) -> #(code_unavailable, 0)
    step.Answer(FromStore(store.ForSelect(..))) ->
      panic as "the asking rule asks for accounts only"
    NotRunning -> #(code_not_running, 0)
    NoAnswerInTime -> #(code_no_answer_in_time, 0)
    EndedBeforeAnswer -> #(code_ended_before_answer, 0)
    StoppedWaiting -> #(code_stopped_waiting, 0)
  }
}

fn record(
  letter letter: Int,
  number number: Int,
  code code: Int,
  extra extra: Int,
  milliseconds milliseconds: Int,
) -> BitArray {
  <<letter, number, code, extra, milliseconds:64>>
}

fn warn(text: String) -> Effect(Nil) {
  Log(LogLine(level: LogWarning, text:, about: step.no_one))
}
