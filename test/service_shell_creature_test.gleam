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
import gleam/erlang/process.{type Subject}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import owned_test
import spawn_support

/// The creature the gate is asked to start: unit 7 of the first run of World
/// 3460, standing at spawn 1.
fn a_creature() -> step.CreatureStart {
  CreatureStart(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    spawn: spawn_support.battle_beast(number: 1, x: 0.0),
    clock_origin_ms: 0,
  )
}

/// The address `a_creature` is found at.
fn a_creatures_address() -> Address {
  Creature(map: MapId(world_id: 3460, instance: 0), incarnation: 1, unit_id: 7)
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

fn start_tree(child: ChildSpecification(Nil)) -> process.Pid {
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.restart_tolerance(intensity: 10, period: 5)
    |> supervisor.add(child)
    |> supervisor.start
    as "the tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  started.pid
}

pub fn a_creature_that_does_not_start_comes_back_as_not_started_and_no_watch_is_opened_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = process.spawn_unlinked(process.sleep_forever)
  let gate = process.new_name("gate")
  let started = process.new_subject()
  let located = process.new_subject()
  let tree =
    start_tree(starting_creatures(
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
  assert process.receive(started, within: ask_support.event_wait_ms)
    == Ok(a_creature())
    as "the shell asked reach to start the creature the rule named"
  assert process.receive(not_started, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(-1))
    as "the failed start reached the rule as CreatureNotStarted with the watch's id"
  assert process.receive(located, within: 0) == Error(Nil)
    as "no watch was opened for a creature that did not start: its address was never looked up"
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
    start_tree(starting_creatures(
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
  assert process.receive(started, within: ask_support.event_wait_ms)
    == Ok(a_creature())
  assert process.receive(located, within: ask_support.event_wait_ms)
    == Ok(a_creatures_address())
    as "the creature that started is watched at the address its unit gives"
  assert process.receive(ended, within: 0) == Error(Nil)
    as "the creature runs, so the watch has not ended"
  let down = process.monitor(target)
  process.kill(target)
  let _reason = ask_support.ended(down)
  assert process.receive(ended, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(2))
    as "the creature's end reached the rule as WatchEnded with the watch's id"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_timer_fires_once_and_a_cancelled_timer_never_fires_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    start_tree(ask_support.reaching(
      name: gate,
      shutdown_ms: 1000,
      reach: service.watch_only(locate: fn(_address) { Error(Nil) }),
    ))
  let cancelled = awaiting(gate:, key: gate_rule.timer_key_base + 2)
  let fires = awaiting(gate:, key: gate_rule.timer_key_base + 1)
  let last = awaiting(gate:, key: gate_rule.timer_key_base + 3)
  assert ask_support.call_gate(gate, gate_rule.StartTimerAs(2, 20))
    == gate_rule.Echoed(2)
  assert ask_support.call_gate(gate, gate_rule.CancelTimerAs(2))
    == gate_rule.Echoed(2)
  assert ask_support.call_gate(gate, gate_rule.StartTimerAs(1, 20))
    == gate_rule.Echoed(1)
  assert ask_support.call_gate(gate, gate_rule.StartTimerAs(3, 200))
    == gate_rule.Echoed(3)
  assert process.receive(fires, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(gate_rule.timer_key_base + 1))
    as "the timer's firing reached the rule as ServiceTimerFired with its id"
  assert process.receive(last, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(gate_rule.timer_key_base + 3))
  assert process.receive(cancelled, within: 0) == Error(Nil)
    as "the cancelled timer, due long before the last one, never fired"
  let _reason = ask_support.stop_tree(tree)
  Nil
}
