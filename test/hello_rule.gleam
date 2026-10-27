//// A tiny connection rule for the shell's and the replay's tests: it greets
//// a client with the server hello and answers each ping with its pong, and
//// nothing else. The login card's rules replace it in the server.

import genesis_prime/step.{type Input, type Step}

/// What the rule keeps between inputs: the bytes of a frame not yet whole.
pub type State {
  State(pending: BitArray)
}

/// The rule's settings: the build the hello names.
pub type Settings {
  Settings(build: Int)
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  todo as "the build follows the shape commit"
}

/// One input in, the new state and what the shell must do out.
pub fn step(state: State, input: Input(Nil, Nil)) -> #(State, Step(Nil, Nil)) {
  todo as "the build follows the shape commit"
}
