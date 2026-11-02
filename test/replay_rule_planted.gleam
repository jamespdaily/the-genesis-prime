//// The replay rule with a change planted in its internal types: its state has
//// a new variant that wraps the old state, and it counts the steps it takes.
//// The bytes it writes for any input are the replay rule's, so a recording of
//// the replay rule is a recording of this one, and a replay shows whether a
//// change of internal types makes a recording refuse to replay.

import genesis_prime/step.{
  type ConnectionInput, type ConnectionRule, type ConnectionStep, Rule,
}
import replay_rule

/// What the planted rule keeps between inputs: the replay rule's state, and,
/// after its first step, how many steps it has taken.
pub type State {
  Fresh(inner: replay_rule.State)
  Counting(inner: replay_rule.State, steps: Int)
}

/// The rule as its shell runs it, under the replay rule's name.
pub fn rule() -> ConnectionRule(Nil, State, Nil, Nil, Nil) {
  Rule(name: "replay_rule", settings: Nil, new:, step:)
}

fn new(settings: Nil) -> State {
  Fresh(replay_rule.new(settings))
}

fn step(
  state state: State,
  input input: ConnectionInput(Nil, Nil),
) -> #(State, ConnectionStep(Nil)) {
  let #(inner, steps) = case state {
    Fresh(inner:) -> #(inner, 1)
    Counting(inner:, steps:) -> #(inner, steps + 1)
  }
  let #(inner, taken) = replay_rule.step(inner, input)
  #(Counting(inner:, steps:), taken)
}
