//// The creature supervisor: a factory supervisor that starts a creature when a map's
//// shell carries out its `StartCreature` effect. It is a plain supervisor, not a
//// rule: it makes no game decision.
////
//// ```
//// world supervisor (rest_for_one, 3 restarts in 10 s)       permanent
////  ├─ creature registry: the `pg` scope, named               permanent
////  ├─ Maps: the registry actor, named                        permanent
////  ├─ creature supervisor: factory supervisor, named         permanent   this module
////  │    └─ one creature per spawn: service shell + creature rule, unnamed  temporary
////  └─ map supervisor: factory supervisor, named              permanent
////       └─ one map per MapId, unnamed                        temporary
////
//// a map's shell                      creature supervisor                 creature registry
////   StartCreature(watch, creature)
////   start_creature(creature) ──call──▶ start(CreatureProcessStart(creature, run: the map's pid))
////                                       starts the shell with the creature's rule
////                                       joins the creature's address ──────▶ member
////   ◀── Ok / Error(reason) ◀────────────
////   Ok: the shell watches Creature(map, run, unit)
////   Error: CreatureNotStarted(watch, reason) is the rule's next input
//// ```
////
//// - **It sits after Maps and before the map supervisor** under `rest_for_one`:
////   its restart restarts the map supervisor, so every map ends, and its
////   children, every creature, end with it; Maps' restart ends it and the maps
////   too.
//// - **Each creature is temporary.** A creature that ends is never restarted by
////   its supervisor: its map watches it and starts the spawn again as another
////   unit, after a delay (genesis_prime/world_map/map), so a creature that crashes
////   in a loop cannot restart itself without bound. Its restart limit is stated
////   and never reached.
//// - **The run's pid** is the process that asks for the creature, the map's. The
////   creature watches the run by it and not through Maps: Maps waits on the
////   run's start while the run starts its creatures (genesis_prime/world_map/creature).
//// - **A start that fails** gives the map's shell the reason, as the supervisor
////   reported it, and the map logs it and leaves the spawn empty for the run. A
////   supervisor that is not running (restarting, or stopping) is a failed
////   start.

import genesis_prime/service.{type Call}
import genesis_prime/step.{type CreatureStart}
import genesis_prime/world_map/creature
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// What the creature supervisor starts a creature with: the creature, and the
/// pid of the run of the map that asked, which the creature watches.
pub type CreatureProcessStart {
  CreatureProcessStart(creature: CreatureStart, run: Pid)
}

/// The creature supervisor's messages.
pub type CreatureSupervisor =
  factory_supervisor.Message(
    CreatureProcessStart,
    Subject(Call(creature.Message, creature.Outgoing)),
  )

/// The creature supervisor, named, whose children are creatures started by
/// `start`, each temporary. A creature has `shutdown_ms` to stop.
pub fn supervisor(
  name name: Name(CreatureSupervisor),
  shutdown_ms shutdown_ms: Int,
  start start: fn(CreatureProcessStart) ->
    actor.StartResult(Subject(Call(creature.Message, creature.Outgoing))),
) -> ChildSpecification(
  factory_supervisor.Supervisor(
    CreatureProcessStart,
    Subject(Call(creature.Message, creature.Outgoing)),
  ),
) {
  service.temporary_factory(name:, shutdown_ms:, start:)
}

/// Starts the creature under the named supervisor, as the process that calls it
/// is the run it belongs to: `Ok` once it is running and joined to its address,
/// or the reason it did not start.
pub fn start_creature(
  supervisor supervisor: Name(CreatureSupervisor),
  creature creature: CreatureStart,
) -> Result(Nil, service.StartChildError) {
  service.start_child(
    supervisor:,
    argument: CreatureProcessStart(creature:, run: process.self()),
  )
  |> result.replace(Nil)
}
