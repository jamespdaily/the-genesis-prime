//// A connection rule for the tests of what a connection takes from its script:
//// it writes the seed and the time it was given, so a test reads which script
//// each input came from.
////
//// Each record the rule writes is a letter and the numbers it was given:
////
//// ```
//// 'a' seed(32 bytes) monotonic_ms(64, signed) filetime(64)   the connection was accepted
//// 'r' monotonic_ms(64, signed) filetime(64)                  bytes were read, whatever they hold
//// ```
////
//// The rule stops when the client closes or its socket fails.

import genesis_prime/step.{
  type ConnectionEffect, type ConnectionInput, type ConnectionRule,
  type ConnectionStep, type Effect, Accepted, Effects, Input, Log, LogLine,
  LogWarning, OwnEffect, OwnEvent, PeerClosed, Read, ReadFailed, Rule, Stop,
  Write, WriteFailed,
}

/// The letters that start a record.
pub const accepted = 0x61

pub const read = 0x72

/// The rule as its shell runs it.
pub fn rule() -> ConnectionRule(Nil, Nil, Nil, Nil, Nil) {
  Rule(name: "script_rule", settings: Nil, new:, step:)
}

/// The rule keeps nothing between inputs.
pub fn new(_settings: Nil) -> Nil {
  Nil
}

/// One input in, the record of the seed or the time it carried out.
pub fn step(
  state state: Nil,
  input input: ConnectionInput(Nil, Nil),
) -> #(Nil, ConnectionStep(Nil)) {
  let Input(event:, now:) = input
  case event {
    OwnEvent(Accepted(seed:, ..)) -> #(
      state,
      Effects([
        OwnEffect(
          Write(<<
            accepted,
            seed:bits,
            now.monotonic_ms:64,
            now.filetime:64,
          >>),
        ),
      ]),
    )
    OwnEvent(Read(..)) -> #(
      state,
      Effects([
        OwnEffect(Write(<<read, now.monotonic_ms:64, now.filetime:64>>)),
      ]),
    )
    OwnEvent(PeerClosed) | step.Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(ReadFailed(..)) | OwnEvent(WriteFailed(..)) -> #(
      state,
      Effects([warn("the socket failed"), Stop]),
    )
    OwnEvent(step.Woken(..))
    | step.WatchEnded(..)
    | OwnEvent(step.TimerFired(..))
    | OwnEvent(step.Answered(..)) -> #(
      state,
      Effects([warn("an input the script rule does not take"), Stop]),
    )
  }
}

fn warn(text: String) -> Effect(ConnectionEffect) {
  Log(LogLine(level: LogWarning, text:, about: step.no_one))
}
