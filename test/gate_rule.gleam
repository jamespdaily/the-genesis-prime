//// A small service rule for the tests of asks and of the service shell: a
//// latch that answers an ask when its key is opened, before or after the
//// ask, so a test's answer never depends on which message reached the service
//// first. It also holds the messages that make a service misbehave: a crash,
//// and each effect a service shell refuses.

import genesis_prime/step.{
  type CallerId, type Input, type Step, Ask, AskId, Asked, Effects,
  EffectsThenAsk, Input, Reply, Send, Sessions, StartTimer, Started, Stop,
  Stopping, TimerId, Watch, WatchId,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}

/// What the gate is asked.
pub type Message {
  /// Answer at once with `Echoed(n)`.
  Echo(Int)
  /// Answer with `Opened(key)` once `key` is opened, which may already be so.
  Await(key: Int)
  /// Open `key`: answer each caller waiting for it with `Opened(key)`, then
  /// answer this ask with `Echoed` and the count of those callers.
  Open(key: Int)
  /// Take the ask and never answer it.
  Ignore
  /// The step is `Stop` and then a reply: the caller is still answered.
  StopThenReply
  /// The rule crashes.
  Crash
  /// The rule returns `Send`, which a service shell refuses.
  TrySend
  /// The rule returns `Watch`, which a service shell refuses.
  TryWatch
  /// The rule returns `StartTimer`, which a service shell refuses.
  TryTimer
  /// The rule ends its step in an ask, which a service shell refuses.
  TryAsk
}

/// What the gate answers with.
pub type Answer {
  Echoed(Int)
  Opened(key: Int)
}

/// The callers waiting for each key, and the keys opened so far.
pub type State {
  State(waiting: Dict(Int, List(CallerId)), opened: Set(Int))
}

/// The gate's first state: nothing waits and nothing is open.
pub fn new(_settings: Nil) -> State {
  State(waiting: dict.new(), opened: set.new())
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Message, Nil),
) -> #(State, Step(Answer, Nil)) {
  let Input(event:, ..) = input
  case event {
    Started -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    Asked(caller:, message:) -> asked(state:, caller:, message:)
    step.Socket(..)
    | step.Woken(..)
    | step.WatchEnded(..)
    | step.TimerFired(..)
    | step.Answered(..)
    | step.AnsweredLate(..) ->
      panic as "a service takes Started, Asked and Stopping only"
  }
}

fn asked(
  state state: State,
  caller caller: CallerId,
  message message: Message,
) -> #(State, Step(Answer, Nil)) {
  case message {
    Echo(n) -> #(state, Effects([Reply(caller, Echoed(n))]))
    Await(key:) ->
      case set.contains(state.opened, key) {
        True -> #(state, Effects([Reply(caller, Opened(key))]))
        False -> #(
          State(
            ..state,
            waiting: dict.insert(state.waiting, key, [
              caller,
              ..waiting_for(state, key)
            ]),
          ),
          Effects([]),
        )
      }
    Open(key:) -> {
      let waiters = list.reverse(waiting_for(state, key))
      #(
        State(
          waiting: dict.delete(state.waiting, key),
          opened: set.insert(state.opened, key),
        ),
        Effects(
          list.append(
            list.map(waiters, fn(waiter) { Reply(waiter, Opened(key)) }),
            [Reply(caller, Echoed(list.length(waiters)))],
          ),
        ),
      )
    }
    Ignore -> #(state, Effects([]))
    StopThenReply -> #(state, Effects([Stop, Reply(caller, Echoed(9))]))
    Crash -> panic as "the planted crash"
    TrySend -> #(state, Effects([Send(Echoed(0))]))
    TryWatch -> #(state, Effects([Watch(WatchId(1), Sessions)]))
    TryTimer -> #(state, Effects([StartTimer(TimerId(1), 10)]))
    TryAsk -> #(
      state,
      EffectsThenAsk(
        effects: [],
        ask: Ask(ask: AskId(1), request: Nil, deadline_ms: 0),
      ),
    )
  }
}

fn waiting_for(state: State, key: Int) -> List(CallerId) {
  case dict.get(state.waiting, key) {
    Ok(callers) -> callers
    Error(Nil) -> []
  }
}
