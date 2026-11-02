//// A connection rule for the test of which side a connection's closing line
//// names when the rule asks before it stops, as the game rule does when it
//// saves a player's place: the client closing, or the server stopping, is
//// answered with an ask, and the connection stops when the ask is answered.
//// It writes one byte when the connection is accepted, so a test knows the
//// shell has taken the connection. Every other input is taken and nothing is
//// done.

import genesis_prime/step.{
  type ConnectionInput, type ConnectionRule, type ConnectionStep, Accepted,
  Answered, Ask, AskId, Effects, EffectsThenAsk, OwnEffect, OwnEvent, PeerClosed,
  Rule, Stop, Stopping, Write,
}

/// The rule as its shell runs it. It asks with the one request `Nil`, and the
/// directory that answers it is the test's.
pub fn rule() -> ConnectionRule(Nil, Nil, Nil, Nil, Nil) {
  Rule(name: "leaving_rule", settings: Nil, new: fn(_settings) { Nil }, step:)
}

/// One input in, the same state and what the shell must do out.
pub fn step(
  state state: Nil,
  input input: ConnectionInput(Nil, Nil),
) -> #(Nil, ConnectionStep(Nil)) {
  #(state, case input.event {
    OwnEvent(PeerClosed) | Stopping(..) ->
      EffectsThenAsk(
        [],
        Ask(
          ask: AskId(1),
          request: Nil,
          deadline_ms: input.now.monotonic_ms + 1000,
        ),
      )
    OwnEvent(Accepted(..)) -> Effects([OwnEffect(Write(<<1>>))])
    OwnEvent(Answered(..)) -> Effects([Stop])
    OwnEvent(_) | step.WatchEnded(..) -> Effects([])
  })
}
