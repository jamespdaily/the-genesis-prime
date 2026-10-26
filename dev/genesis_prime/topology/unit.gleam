//// A creature or a player's character on the map, and the rules that change
//// one. Both prototypes run these rules and differ only in which process
//// owns the unit. A rule takes the current time from the monotonic clock, in
//// microseconds, and returns the new unit with the effects a process must
//// carry out. Pure.
////
//// A unit id is a plain `Int`, a named hot path under the typed-id rule of the
//// writing-gleam skill, for the reason given in `genesis_prime/topology/grid`.

import genesis_prime/topology/position.{type Position}
import gleam/option.{type Option}

/// How long a dead unit stays dead before it returns, in microseconds.
pub const return_delay_microseconds = 1_000_000

/// What a unit is. A creature thinks on its own; a player's unit moves only
/// when its player says so.
pub type Kind {
  Player
  Creature
}

/// Whether a unit is alive. A dead unit holds the time on the monotonic clock
/// at which it returns, so no flag and no separate timer value can disagree.
pub type Status {
  Alive
  Dead(returns_at: Int)
}

/// A unit: its id, what it is, where it stands, its health and the most it can
/// have, and whether it is alive. Health is never below 0 and a dead unit has
/// 0 health.
pub type Unit {
  Unit(
    id: Int,
    kind: Kind,
    position: Position,
    health: Int,
    maximum_health: Int,
    status: Status,
  )
}

/// What the observers of a unit are told after a rule changed it. The process
/// that ran the rule tells every player in visibility range.
pub type Effect {
  Moved(unit_id: Int, position: Position)
  HealthChanged(unit_id: Int, health: Int)
  Died(unit_id: Int)
  Returned(unit_id: Int)
}

/// What a hit did to the one who was hit: it landed and left this much health,
/// or it was refused because the unit was already dead.
pub type HitOutcome {
  Landed(remaining_health: Int)
  RefusedDead
}

/// What a hit returns: the unit after the hit, the outcome for the attacker
/// and the effects for the observers.
pub type HitResult {
  HitResult(unit: Unit, outcome: HitOutcome, effects: List(Effect))
}

/// A unit seen from outside: the only facts another unit's rule may read.
pub type Neighbour {
  Neighbour(unit_id: Int, kind: Kind, position: Position)
}

/// A living unit at full health.
pub fn new(
  id: Int,
  kind: Kind,
  position: Position,
  maximum_health: Int,
) -> Unit {
  todo as "body in the build commit"
}

/// Takes `damage` from a unit. A hit on a dead unit is refused. Health stops
/// at 0; the hit that brings it there kills the unit once, and it returns
/// `return_delay_microseconds` after `now`.
pub fn hit(unit: Unit, damage: Int, now: Int) -> HitResult {
  todo as "body in the build commit"
}

/// One think of a creature: it steps `step_metres` toward `target`, the
/// nearest player in its aggro range, or stays where it is when there is none.
/// A dead creature does not think.
pub fn think(
  creature: Unit,
  target: Option(Position),
  step_metres: Float,
  now: Int,
) -> #(Unit, List(Effect)) {
  todo as "body in the build commit"
}

/// Puts a unit at a position. A dead unit does not move.
pub fn move(unit: Unit, position: Position) -> #(Unit, List(Effect)) {
  todo as "body in the build commit"
}

/// Brings a dead unit back at full health once `now` has reached its return
/// time. Before that time, and for a living unit, nothing changes.
pub fn return_if_due(unit: Unit, now: Int) -> #(Unit, List(Effect)) {
  todo as "body in the build commit"
}

/// The neighbour of one kind that is nearest to `from`, or none when no
/// neighbour of that kind is listed. Two at the same distance resolve to the
/// lower id, so the answer does not depend on the list's order.
pub fn nearest(
  from: Position,
  neighbours: List(Neighbour),
  kind: Kind,
) -> Option(Neighbour) {
  todo as "body in the build commit"
}
