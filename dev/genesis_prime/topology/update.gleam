//// What a simulated player's connection receives: an update about a unit that
//// is in the player's visibility range, and the outcome of the player's own
//// attacks. Both prototypes send exactly these.

import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Effect, type HitOutcome}

/// Something that happened to a unit. `sent_at` is the monotonic time in
/// microseconds of the move or think that caused it, so a player can measure
/// how long the news took to arrive.
pub type Update {
  Moved(unit_id: Int, position: Position, sent_at: Int)
  HealthChanged(unit_id: Int, health: Int, sent_at: Int)
  Died(unit_id: Int, sent_at: Int)
  Returned(unit_id: Int, sent_at: Int)
}

/// The answer to one attack, sent to the attacker's connection.
pub type HitReply {
  HitReply(target_id: Int, outcome: HitOutcome)
}

/// Everything a player's connection can receive.
pub type Delivery {
  Updated(Update)
  Hit(HitReply)
  /// The owner has joined this connection to the unit with this id; updates
  /// in range are sent to it from now on.
  Joined(unit_id: Int)
}

/// The update that tells observers of an effect, stamped with the time of the
/// move or think that caused the effect.
pub fn from_effect(effect: Effect, sent_at: Int) -> Update {
  todo as "body in the build commit"
}
