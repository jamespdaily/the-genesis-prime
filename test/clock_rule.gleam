//// A small service rule for the tests of the service shell's clock: it tells the
//// test each input it takes, as the shell gave it (the `Now` it carries and what
//// happened), and carries out the commands it is asked: the timers, a creature
//// start and a watch, which start the inputs the shell reads the clock for.

import genesis_prime/step.{
  type Address, type CreatureStart, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceStep, Asked, CancelServiceTimer,
  CreatureNotStarted, Effects, Input, OwnEffect, OwnEvent, Reply, Send,
  ServiceTimerFired, Sessions, StartCreature, StartServiceTimer, Started, Stop,
  Stopping, TimerId, Told, Watch, WatchEnded, WatchId,
}
import gleam/list

/// What the rule is asked or told.
pub type Command {
  /// Take the input and report it, nothing more.
  Report
  /// Start timer `timer` for `after_ms`.
  StartTimer(timer: Int, after_ms: Int)
  /// Cancel timer `timer`.
  CancelTimer(timer: Int)
  /// Start the creature, watched as watch `watch`.
  StartCreatureAs(watch: Int, creature: CreatureStart)
  /// Watch the process at the address as watch `watch`.
  WatchAddress(watch: Int, target: Address)
}

/// The rule keeps nothing.
pub fn new(_settings: Nil) -> Nil {
  Nil
}

/// One input in: an ask is answered with the input as it came, once its command
/// is carried out; any other input is sent to the `Sessions` address as it came,
/// and a `Stopping` ends the service.
pub fn step(
  state state: Nil,
  input input: ServiceInput(Command),
) -> #(Nil, ServiceStep(ServiceInput(Command))) {
  let Input(event:, ..) = input
  let reported = OwnEffect(Send(Sessions, input))
  let effects = case event {
    OwnEvent(Asked(caller:, message:)) ->
      list.append(commanded(message), [OwnEffect(Reply(caller, input))])
    Stopping(..) -> [reported, Stop]
    OwnEvent(Told(..))
    | OwnEvent(Started)
    | OwnEvent(ServiceTimerFired(..))
    | OwnEvent(CreatureNotStarted(..))
    | WatchEnded(..) -> [reported]
  }
  #(state, Effects(effects))
}

fn commanded(
  command: Command,
) -> List(Effect(ServiceEffect(ServiceInput(Command)))) {
  case command {
    Report -> []
    StartTimer(timer:, after_ms:) -> [
      OwnEffect(StartServiceTimer(TimerId(timer), after_ms)),
    ]
    CancelTimer(timer:) -> [OwnEffect(CancelServiceTimer(TimerId(timer)))]
    StartCreatureAs(watch:, creature:) -> [
      OwnEffect(StartCreature(WatchId(watch), creature)),
    ]
    WatchAddress(watch:, target:) -> [Watch(WatchId(watch), target)]
  }
}
