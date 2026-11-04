//// Where the creatures are found: a scope of `genesis_prime/group_registry`, with one group for each
//// creature, named by its `Creature(map, incarnation, unit_id)` address
//// (genesis_prime/step). It is the world supervisor's first child, so every
//// process that finds a creature (a map's shell for a `Watch` or a `Send`, a
//// player's connection for a tell) asks it, and no process keeps a list of
//// creatures and no atom is made for one.
////
//// ```
//// world supervisor (rest_for_one, 3 restarts in 10 s)
////  ├─ creature registry: the `pg` scope, a gen_server   permanent, 1 s to stop
////  ├─ Maps ...
////  ├─ creature supervisor ...
////  └─ map supervisor ...
////
//// creature supervisor      scope                         a shell
////   starts the creature ─▶ join(map, run, unit, pid)
////                          find(map, run, unit)  ◀───── the group's one member
////                          tell(map, run, unit, message) ─▶ {woken, TellCall(message)} to it
//// ```
////
//// - **Join.** The creature supervisor's start function joins the new
////   process under its address as the process returns, so the creature is found
////   from the moment `StartCreature` has been carried out.
//// - **An address is one creature in one run.** A creature that ends and is
////   replaced is another unit and so another address: a find never lands on a
////   replacement.
//// - **A creature ending.** The scope monitors each member and drops it from
////   its group; a `find` just after the end may still give the pid, and a tell to
////   it is then dropped like any message to a process that ended.
//// - **The scope restarting.** The restarted scope has no members. The registry
////   is the first child under `rest_for_one`, so the maps and creatures end with
////   it: a map that ends is started again, empty, by the next ask.
//// - **The name.** The scope is named by an atom made once at start with
////   `process.new_name`, so each tree has its own scope and none is shared.

import genesis_prime/client_connection.{type PeerNews}
import genesis_prime/group_registry.{type Scope}
import genesis_prime/service.{type Call, TellCall}
import genesis_prime/step.{Creature}
import genesis_prime/world_map/creature
import genesis_prime/world_map/map_id.{type MapId}
import gleam/erlang/process.{type Pid}
import gleam/otp/supervision.{type ChildSpecification}

/// What a creature's shell takes through the scope: the calls a service takes.
pub type Delivered =
  Call(creature.Message, PeerNews)

/// The scope creatures are found in: made once, with `new`, and given to the
/// tree and to the shells that look in it.
pub opaque type CreatureRegistry {
  CreatureRegistry(scope: Scope(Delivered))
}

/// A new registry, with a scope name no other registry has.
pub fn new() -> CreatureRegistry {
  CreatureRegistry(scope: group_registry.new("creatures"))
}

/// The scope as a permanent child of a supervisor.
pub fn supervised(
  registry registry: CreatureRegistry,
) -> ChildSpecification(Nil) {
  group_registry.supervised(registry.scope)
}

/// The scope, for the shell that takes what is told to a creature
/// (`group_registry.select_delivered`).
pub fn scope(registry registry: CreatureRegistry) -> Scope(Delivered) {
  registry.scope
}

/// Makes the process the member of the group of the creature that is unit
/// `unit_id` in this run of the map; the creature supervisor's start function
/// calls it once for each creature.
pub fn join(
  registry registry: CreatureRegistry,
  map map: MapId,
  incarnation incarnation: Int,
  unit_id unit_id: Int,
  pid pid: Pid,
) -> Nil {
  group_registry.join(
    registry.scope,
    Creature(map:, incarnation:, unit_id:),
    pid,
  )
}

/// The process of the creature that is unit `unit_id` in this run of the map, or
/// `Error(Nil)` when none is a member.
pub fn find(
  registry registry: CreatureRegistry,
  map map: MapId,
  incarnation incarnation: Int,
  unit_id unit_id: Int,
) -> Result(Pid, Nil) {
  group_registry.find(registry.scope, Creature(map:, incarnation:, unit_id:))
}

/// Tells the creature the message, which its shell takes as a `Told` input;
/// `Error(Nil)` when no process is a member, and nothing is sent.
pub fn tell(
  registry registry: CreatureRegistry,
  map map: MapId,
  incarnation incarnation: Int,
  unit_id unit_id: Int,
  message message: creature.Message,
) -> Result(Nil, Nil) {
  group_registry.deliver_one(
    registry.scope,
    Creature(map:, incarnation:, unit_id:),
    TellCall(message:),
  )
}
