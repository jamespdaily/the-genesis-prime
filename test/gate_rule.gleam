//// A small service rule for the tests of asks and of the service shell: a
//// latch that answers an ask when its key is opened, before or after the
//// ask, so a test's answer never depends on which message reached the service
//// first. It also holds the messages that make a service send and
//// watch, whose watches end as the opening of the key of the same number, and
//// the messages that make it misbehave: a crash, and each effect a service
//// shell refuses.

import genesis_prime/step.{
  type Address, type CallerId, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceStep, Ask, AskId, Asked, Effects,
  EffectsThenAsk, Input, OwnEffect, OwnEvent, Reply, Send, StartTimer, Started,
  Stop, Stopping, TimerId, Watch, WatchEnded, WatchId,
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
  /// Send `Echoed(n)` to the process at the address, then answer with
  /// `Echoed(n)`.
  SendTo(to: Address, n: Int)
  /// Watch the process at the address as watch `watch`, then answer with
  /// `Echoed(watch)`. The watch's end opens the key `watch`.
  WatchAddress(watch: Int, target: Address)
  /// Watch the process at the address as each of the watches, in this order,
  /// in one step, then answer with `Echoed` and the count of watches.
  WatchEach(watches: List(Int), target: Address)
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
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Answer)) {
  let Input(event:, ..) = input
  case event {
    Started -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(caller:, message:)) -> asked(state:, caller:, message:)
    WatchEnded(watch: WatchId(key)) -> opened(state:, key:)
    step.Woken(..) | step.TimerFired(..) | step.Answered(..) ->
      panic as "a service takes Started, Asked, WatchEnded and Stopping only"
  }
}

fn asked(
  state state: State,
  caller caller: CallerId,
  message message: Message,
) -> #(State, ServiceStep(Answer)) {
  case message {
    Echo(n) -> #(state, Effects([OwnEffect(Reply(caller, Echoed(n)))]))
    Await(key:) ->
      case set.contains(state.opened, key) {
        True -> #(state, Effects([OwnEffect(Reply(caller, Opened(key)))]))
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
      let #(state, replies) = open(state:, key:)
      #(
        state,
        Effects(
          list.append(replies, [
            OwnEffect(Reply(caller, Echoed(list.length(replies)))),
          ]),
        ),
      )
    }
    Ignore -> #(state, Effects([]))
    StopThenReply -> #(
      state,
      Effects([Stop, OwnEffect(Reply(caller, Echoed(9)))]),
    )
    Crash -> panic as "the planted crash"
    SendTo(to:, n:) -> #(
      state,
      Effects([Send(to, Echoed(n)), OwnEffect(Reply(caller, Echoed(n)))]),
    )
    WatchAddress(watch:, target:) -> #(
      state,
      Effects([
        Watch(WatchId(watch), target),
        OwnEffect(Reply(caller, Echoed(watch))),
      ]),
    )
    WatchEach(watches:, target:) -> #(
      state,
      Effects(
        list.append(
          list.map(watches, fn(watch) { Watch(WatchId(watch), target) }),
          [OwnEffect(Reply(caller, Echoed(list.length(watches))))],
        ),
      ),
    )
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

/// A watch's end: the key of its number is opened, with no caller to answer.
fn opened(state state: State, key key: Int) -> #(State, ServiceStep(Answer)) {
  let #(state, replies) = open(state:, key:)
  #(state, Effects(replies))
}

/// Opens `key`: the replies to the callers waiting for it, in the order they
/// asked.
fn open(
  state state: State,
  key key: Int,
) -> #(State, List(Effect(Answer, ServiceEffect(Answer)))) {
  let waiters = list.reverse(waiting_for(state, key))
  #(
    State(
      waiting: dict.delete(state.waiting, key),
      opened: set.insert(state.opened, key),
    ),
    list.map(waiters, fn(waiter) { OwnEffect(Reply(waiter, Opened(key))) }),
  )
}

fn waiting_for(state: State, key: Int) -> List(CallerId) {
  case dict.get(state.waiting, key) {
    Ok(callers) -> callers
    Error(Nil) -> []
  }
}
