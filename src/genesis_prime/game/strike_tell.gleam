//// What a caster's connection and a struck creature tell each other, and
//// nothing else: the strike one sends and the answer the other gives. They sit
//// apart from both processes' rules so the connection's request type
//// (genesis_prime/client_connection) and the creature's rule
//// (genesis_prime/world_map/creature) share them with no import between the two.
////
//// ```
//// caster's connection                                      creature
////   Tell(Creature(map, run, unit, life), TellStrike(Strike(key, from, offence, rolls)))
////                                                           ─▶ hit rule ─▶ health, 0x937, 0x88c to its viewers
////   SentByTarget(Answered(key, outcome))  ◀─ Send(Connection(from), Answered(key, outcome))
//// ```
////
//// - **The key** names one strike: the cast, the go's phase and the struck unit, so
////   an answer finds its round and a late one finds none.
//// - **No process waits.** The strike and the answer are tells; the caster keeps a
////   deadline for each round (genesis_prime/game/strike).
//// - **The answer goes to `from`**, the connection that sent the strike, which a
////   creature cannot find from the key.

import genesis_prime/game/hit.{type Description, type Offence, type Rolls}
import genesis_prime/step.{type ConnectionId}

/// How long a round waits for its answers, in milliseconds. A creature's respawn time
/// is never below it (genesis_prime/world_map/creature_kind), so a unit does not stand
/// again while a round it was struck in is open.
pub const deadline_ms = 1000

/// One strike: the cast, the go's phase and the struck unit.
pub type Key {
  Key(cast_id: Int, phase: Int, unit_id: Int)
}

/// What the caster's connection tells a creature.
pub type Tell {
  Strike(key: Key, from: ConnectionId, offence: Offence, rolls: Rolls)
}

/// Why a creature does not take a strike.
pub type Refusal {
  /// The creature is dead: it was killed after the caster's picture showed it
  /// alive (`Spell4ValidTargets.targetBitmask`: no area strikes a dead unit).
  Dead
}

/// What a creature answers a strike with.
pub type Outcome {
  /// The blows landed: a description for each (genesis_prime/game/hit).
  Landed(descriptions: List(Description))
  /// The creature deflected the whole strike.
  Deflected
  /// The creature took no strike.
  Refused(why: Refusal)
}

/// The creature's answer to the strike of `key`.
pub type Answered {
  Answered(key: Key, outcome: Outcome)
}
