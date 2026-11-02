//// A connection rule for the tests of how a replay ends a connection: it takes
//// every input and writes nothing, and when the client closes it asks a
//// process for something instead of stopping, so its shell waits for an answer
//// that a test's directory never gives. A recording of it that ends with the
//// client's close shows whether the replay waits for the shell to end.

import genesis_prime/step.{
  type ConnectionInput, type ConnectionRule, type ConnectionStep, Accepted, Ask,
  AskId, Effects, EffectsThenAsk, Input, OwnEvent, PeerClosed, Read, ReadFailed,
  Rule, WriteFailed,
}

/// How long the ask the rule makes when the client closes may wait, in
/// milliseconds: longer than any test runs.
const ask_ms = 60_000

/// The rule as its shell runs it.
pub fn rule() -> ConnectionRule(Nil, Nil, Nil, Nil, Nil) {
  Rule(name: "lingering_rule", settings: Nil, new:, step:)
}

/// The rule keeps nothing between inputs.
pub fn new(_settings: Nil) -> Nil {
  Nil
}

/// The client's close is an ask; every other input has no effect.
pub fn step(
  state state: Nil,
  input input: ConnectionInput(Nil, Nil),
) -> #(Nil, ConnectionStep(Nil)) {
  let Input(now:, event:) = input
  case event {
    OwnEvent(PeerClosed) -> #(
      state,
      EffectsThenAsk(
        effects: [],
        ask: Ask(
          ask: AskId(1),
          request: Nil,
          deadline_ms: now.monotonic_ms + ask_ms,
        ),
      ),
    )
    OwnEvent(Accepted(..))
    | OwnEvent(Read(..))
    | OwnEvent(ReadFailed(..))
    | OwnEvent(WriteFailed(..))
    | OwnEvent(step.Woken(..))
    | OwnEvent(step.TimerFired(..))
    | OwnEvent(step.Answered(..))
    | step.WatchEnded(..)
    | step.Stopping(..) -> #(state, Effects([]))
  }
}
