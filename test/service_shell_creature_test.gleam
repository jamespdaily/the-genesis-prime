//// What the service shell does for a rule that starts creatures and timers,
//// proven on the gate. Expected values come from these places.
//// - The doc comments of `genesis_prime/step` (`StartCreature`,
////   `CreatureNotStarted`, `StartServiceTimer`, `CancelServiceTimer`,
////   `ServiceTimerFired`) and of `genesis_prime/service/shell`: a creature that
////   runs is watched at the address its unit gives, so its end comes back once
////   as `WatchEnded` with the watch's id; one that does not start comes back as
////   `CreatureNotStarted` with the watch's id, and no watch is opened for it; a
////   timer's firing comes back once, and a cancelled timer gives none.
//// - The failure table of the creature step (`genesis_prime/world_map/map`):
////   a creature start that fails leaves its spawn empty, so the rule must
////   be told, and told once.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import gate_rule
import genesis_prime/service
import genesis_prime/step.{type Address, Creature, CreatureStart}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/supervision.{type ChildSpecification}
import open_wait
import owned_test

/// The creature the gate is asked to start: unit 7 of the first run of World
/// 3460, standing at spawn 1.
pub fn a_creature() -> step.CreatureStart {
  CreatureStart(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    life: 3,
    spawn: spawn_source.Stored(id: SpawnId(1)),
    clock_origin_ms: 0,
    viewers: [],
  )
}

/// The address `a_creature` is found at.
pub fn a_creatures_address() -> Address {
  Creature(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    life: 3,
  )
}

/// A gate whose reach starts creatures as `starting` says, tells `started` of
/// each creature it was asked to start and `located` of each address it was
/// asked to find, and finds the creature's address at `target`.
fn starting_creatures(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  starting starting: Result(Nil, service.StartChildError),
  started started: Subject(step.CreatureStart),
  located located: Subject(Address),
  at target: process.Pid,
) -> ChildSpecification(Nil) {
  ask_support.reaching(
    name: gate,
    shutdown_ms: 1000,
    reach: service.Reach(
      locate: fn(address) {
        process.send(located, address)
        case address == a_creatures_address() {
          True -> Ok(target)
          False -> Error(Nil)
        }
      },
      send: fn(_to, _message) { Error(Nil) },
      start_creature: fn(creature) {
        process.send(started, creature)
        starting
      },
    ),
  )
}

/// The gate's answer to an ask for `key`, which comes when the key opens.
fn awaiting(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  key key: Int,
) -> Subject(gate_rule.Answer) {
  let replies = process.new_subject()
  let assert Ok(service.ToService(_)) =
    service.call(gate, gate_rule.Await(key:), fn(answer) {
      process.send(replies, answer)
    })
    as "the gate took the wait"
  replies
}

pub fn a_creature_that_does_not_start_comes_back_as_not_started_and_no_watch_is_opened_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = process.spawn_unlinked(process.sleep_forever)
  let gate = process.new_name("gate")
  let started = process.new_subject()
  let located = process.new_subject()
  let tree =
    ask_support.start_tree(starting_creatures(
      gate:,
      starting: Error(service.SupervisorNotRunning),
      started:,
      located:,
      at: target,
    ))
  let not_started = awaiting(gate:, key: -1)
  assert ask_support.call_gate(
      gate,
      gate_rule.StartCreatureAs(watch: 1, creature: a_creature()),
    )
    == gate_rule.Echoed(1)
    as "the step went on to its reply"
  assert open_wait.received(
      from: started,
      what: "the shell's ask to reach to start the creature",
    )
    == a_creature()
    as "the shell asked reach to start the creature the rule named"
  assert open_wait.received(
      from: not_started,
      what: "the rule's input for the failed creature start",
    )
    == gate_rule.Opened(-1)
    as "the failed start reached the rule as CreatureNotStarted with the watch's id"
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(located, within: 0) == Error(Nil)
    as "no watch was opened for a creature that did not start: its address was never looked up"
  process.kill(target)
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_timer_of_the_step_that_started_a_creature_fires_after_the_creatures_failed_start_test() -> Nil {
  use <- owned_test.run(30_000)
  // The map answers a development summon by the timer it starts with the
  // creature: the failure of the start is the rule's next input after the step
  // (`genesis_prime/service/shell` `take`), so the timer, even one of 0 ms, is
  // the first input that says the start did not fail.
  let target = process.spawn_unlinked(process.sleep_forever)
  let gate = process.new_name("gate")
  let started = process.new_subject()
  let located = process.new_subject()
  let tree =
    ask_support.start_tree(starting_creatures(
      gate:,
      starting: Error(service.SupervisorNotRunning),
      started:,
      located:,
      at: target,
    ))
  let arrivals = process.new_subject()
  list.each([-4, gate_rule.timer_key_base + 9], fn(key) {
    let assert Ok(service.ToService(_)) =
      service.call(gate, gate_rule.Await(key:), fn(answer) {
        process.send(arrivals, answer)
      })
      as "the gate took the wait"
  })
  assert ask_support.call_gate(
      gate,
      gate_rule.StartCreatureThenTimer(
        watch: 4,
        creature: a_creature(),
        timer: 9,
        after_ms: 0,
      ),
    )
    == gate_rule.Echoed(4)
  assert open_wait.received(
      from: arrivals,
      what: "the rule's input for the failed creature start",
    )
    == gate_rule.Opened(-4)
    as "the failed start comes first"
  assert open_wait.received(
      from: arrivals,
      what: "the rule's input for the timer of the same step",
    )
    == gate_rule.Opened(gate_rule.timer_key_base + 9)
    as "the timer of the same step comes after it"
  process.kill(target)
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_creature_that_starts_is_watched_at_its_address_and_its_end_comes_back_as_watch_ended_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = process.spawn_unlinked(process.sleep_forever)
  let gate = process.new_name("gate")
  let started = process.new_subject()
  let located = process.new_subject()
  let tree =
    ask_support.start_tree(starting_creatures(
      gate:,
      starting: Ok(Nil),
      started:,
      located:,
      at: target,
    ))
  let ended = awaiting(gate:, key: 2)
  assert ask_support.call_gate(
      gate,
      gate_rule.StartCreatureAs(watch: 2, creature: a_creature()),
    )
    == gate_rule.Echoed(2)
  assert open_wait.received(
      from: started,
      what: "the shell's ask to reach to start the creature",
    )
    == a_creature()
  assert open_wait.received(
      from: located,
      what: "the address the shell watches for the started creature",
    )
    == a_creatures_address()
    as "the creature that started is watched at the address its unit gives"
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(ended, within: 0) == Error(Nil)
    as "the creature runs, so the watch has not ended"
  let down = process.monitor(target)
  process.kill(target)
  let _reason =
    ask_support.ended(watched: down, what: "the killed target to end")
  assert open_wait.received(
      from: ended,
      what: "the rule's input for the creature's end",
    )
    == gate_rule.Opened(2)
    as "the creature's end reached the rule as WatchEnded with the watch's id"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_timer_fires_once_and_a_cancelled_timer_never_fires_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    ask_support.start_tree(ask_support.reaching(
      name: gate,
      shutdown_ms: 1000,
      reach: service.watch_only(locate: fn(_address) { Error(Nil) }),
    ))
  let cancelled = awaiting(gate:, key: gate_rule.timer_key_base + 2)
  let fires = awaiting(gate:, key: gate_rule.timer_key_base + 1)
  let last = awaiting(gate:, key: gate_rule.timer_key_base + 3)
  // The timer is due at once and cancelled in the step that starts it, so
  // whether its firing is sent before or after the cancel, it must be dropped;
  // no time has to pass for that, and the timers after it are only waited for,
  // with an upper bound.
  assert ask_support.call_gate(gate, gate_rule.StartThenCancelTimerAs(2, 0))
    == gate_rule.Echoed(2)
  assert ask_support.call_gate(gate, gate_rule.StartTimerAs(1, 20))
    == gate_rule.Echoed(1)
  assert ask_support.call_gate(gate, gate_rule.StartTimerAs(3, 400))
    == gate_rule.Echoed(3)
  assert open_wait.received(
      from: fires,
      what: "the rule's input for the first timer's firing",
    )
    == gate_rule.Opened(gate_rule.timer_key_base + 1)
    as "the timer's firing reached the rule as ServiceTimerFired with its id"
  assert open_wait.received(
      from: last,
      what: "the rule's input for the last timer's firing",
    )
    == gate_rule.Opened(gate_rule.timer_key_base + 3)
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(cancelled, within: 0) == Error(Nil)
    as "the cancelled timer, due long before the last one, never fired"
  let _reason = ask_support.stop_tree(tree)
  Nil
}
