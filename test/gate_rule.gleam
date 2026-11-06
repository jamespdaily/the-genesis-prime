//// A small service rule for the tests of asks and of the service shell: a
//// latch that answers an ask when its key is opened, before or after the
//// ask, so a test's answer never depends on which message reached the service
//// first. It also holds the messages that make a service send and
//// watch, whose watches end as the opening of the key of the same number, and
//// the message that makes it misbehave: a crash. It starts creatures and timers
//// too: a creature that does not start opens the key of its watch's number below
//// zero, and a timer opens the key `timer_key_base` more than its number when
//// it fires.

import genesis_prime/step.{
  type Address, type CallerId, type CreatureStart, type Effect,
  type ServiceEffect, type ServiceInput, type ServiceStep, Asked,
  CancelServiceTimer, CreatureNotStarted, Effects, Input, OwnEffect, OwnEvent,
  Reply, Send, ServiceTimerFired, StartCreature, StartServiceTimer, Started,
  Stop, Stopping, TimerId, Told, Watch, WatchEnded, WatchId,
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
  /// Start the creature, watched as watch `watch`, then answer with
  /// `Echoed(watch)`. The creature's end opens the key `watch`; one that does
  /// not start opens the key `-watch`.
  StartCreatureAs(watch: Int, creature: CreatureStart)
  /// Start the creature as `StartCreatureAs` does, then timer `timer` for
  /// `after_ms` in the same step, then answer with `Echoed(watch)`.
  StartCreatureThenTimer(
    watch: Int,
    creature: CreatureStart,
    timer: Int,
    after_ms: Int,
  )
  /// Start timer `timer` for `after_ms`, then answer with `Echoed(timer)`. Its
  /// firing opens the key `timer_key_base + timer`.
  StartTimerAs(timer: Int, after_ms: Int)
  /// Cancel timer `timer`, then answer with `Echoed(timer)`.
  CancelTimerAs(timer: Int)
}

/// The key a timer's firing opens is its number plus this.
pub const timer_key_base = 1000

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
    OwnEvent(Started) -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(caller:, message:)) -> asked(state:, caller:, message:)
    OwnEvent(Told(..)) ->
      panic as "the gate takes Started, Asked and Stopping only; nothing tells it"
    OwnEvent(ServiceTimerFired(timer: TimerId(timer))) ->
      opened(state:, key: timer_key_base + timer)
    OwnEvent(CreatureNotStarted(watch: WatchId(watch), ..)) ->
      opened(state:, key: -watch)
    WatchEnded(watch: WatchId(key)) -> opened(state:, key:)
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
      Effects([
        OwnEffect(Send(to, Echoed(n))),
        OwnEffect(Reply(caller, Echoed(n))),
      ]),
    )
    WatchAddress(watch:, target:) -> #(
      state,
      Effects([
        Watch(WatchId(watch), target),
        OwnEffect(Reply(caller, Echoed(watch))),
      ]),
    )
    StartCreatureAs(watch:, creature:) -> #(
      state,
      Effects([
        OwnEffect(StartCreature(WatchId(watch), creature)),
        OwnEffect(Reply(caller, Echoed(watch))),
      ]),
    )
    StartCreatureThenTimer(watch:, creature:, timer:, after_ms:) -> #(
      state,
      Effects([
        OwnEffect(StartCreature(WatchId(watch), creature)),
        OwnEffect(StartServiceTimer(TimerId(timer), after_ms)),
        OwnEffect(Reply(caller, Echoed(watch))),
      ]),
    )
    StartTimerAs(timer:, after_ms:) -> #(
      state,
      Effects([
        OwnEffect(StartServiceTimer(TimerId(timer), after_ms)),
        OwnEffect(Reply(caller, Echoed(timer))),
      ]),
    )
    CancelTimerAs(timer:) -> #(
      state,
      Effects([
        OwnEffect(CancelServiceTimer(TimerId(timer))),
        OwnEffect(Reply(caller, Echoed(timer))),
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
) -> #(State, List(Effect(ServiceEffect(Answer)))) {
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
