//// What a striker and the unit it strikes tell each other, both ways: a player's
//// connection striking a creature, and a creature striking a player's connection,
//// with one tell type, and what a creature that fights a player tells that
//// player's connection. They sit apart from both processes' rules so the
//// connection's request type (genesis_prime/client_connection) and the creature's
//// rule (genesis_prime/world_map/creature) share them with no import between the
//// two.
////
//// ```
//// player's connection                                       creature
////   Tell(Creature(..), TellStrike(Strike(key, Connection(c), PlayerStriker(unit, place, seq, rolls), offence)))
////                                                            ─▶ hit rule ─▶ health, 0x937, 0x88c to its viewers
////   SentByTarget(Answered(key, outcome))   ◀─ Send(Connection(c), Answered(key, outcome))
////
////   SentByFoe(Threatened(unit, life, player's unit))
////                                          ◀─ the creature put the player on its threat list
////   SentByFoe(Attacks(Strike(key, Creature(..), CreatureStriker, offence)))
////                                          ◀─ the creature's own strike
////   hit rule on the player's health and shield, rolls from the player's seed
////   Tell(Creature(..), TellStrikeAnswered(Answered(key, outcome))) ─▶ the creature's round
////   SentByFoe(Released(unit, player's unit)) ◀─ the creature took the player off its threat list
//// ```
////
//// - **The key** names one strike: the cast, the go's phase and the struck unit, so
////   an answer finds its round and a late one finds none.
//// - **No process waits.** The strike and the answer are tells; the striker keeps a
////   deadline for each round (genesis_prime/game/strike,
////   genesis_prime/world_map/creature_fight).
//// - **The answer goes to `from`**, the address of the striker, which the struck
////   unit cannot find from the key.
//// - **The struck unit's owner rolls when the striker is a creature**: a creature
////   keeps no random state, so the struck player's connection draws the rolls from
////   its own seed, and a recording of that connection replays them.
//// - **A player's strike carries its place and move sequence number**, so a
////   creature it puts on a fight finds it, ordered with the moves its connection
////   tells (genesis_prime/world_map/creature_fight).

import genesis_prime/game/hit.{type Description, type Offence, type Rolls}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{type Address}

/// How long a round waits for its answers, in milliseconds. A creature's respawn time
/// is never below it (genesis_prime/world_map/creature_kind), so a unit does not stand
/// again while a round it was struck in is open.
pub const deadline_ms = 1000

/// One strike: the cast, the go's phase and the struck unit.
pub type Key {
  Key(cast_id: Int, phase: Int, unit_id: Int)
}

/// What a striker tells the unit it strikes: the strike's key, the striker's
/// address, which the answer goes to, who the striker is, and its offence.
pub type Tell {
  Strike(key: Key, from: Address, striker: Striker, offence: Offence)
}

/// Who strikes, with what the struck unit's owner needs of it.
pub type Striker {
  /// A player: its unit, the place it struck from and the move sequence number of
  /// that place (genesis_prime/game/connection), and its rolls, from its
  /// connection's seed.
  PlayerStriker(unit_id: Int, place: Place, seq: Int, rolls: Rolls)
  /// A creature, which keeps no random state: the struck player's connection
  /// draws the rolls.
  CreatureStriker
}

/// Why a unit does not take a strike.
pub type Refusal {
  /// The unit is dead: it was killed after the striker's picture showed it
  /// alive (`Spell4ValidTargets.targetBitmask`: no area strikes a dead unit).
  Dead
  /// The creature gave up its fight and walks home, taking no strike until it
  /// is there.
  Returning
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

/// The struck unit's answer to the strike of `key`.
pub type Answered {
  Answered(key: Key, outcome: Outcome)
}

/// What a creature that fights a player tells the player's connection. A threat
/// and a release name the player's unit `player_unit_id` as the creature holds it
/// on its threat list: the map gives each stay of a player a new unit id, so the
/// connection drops one sent for an earlier stay that reaches a later one.
pub type Fight {
  /// The creature `unit_id` of life `life` put the player on its threat list.
  Threatened(unit_id: Int, life: Int, player_unit_id: Int)
  /// The creature `unit_id` took the player off its threat list: it leashed or
  /// died, or the player died.
  Released(unit_id: Int, player_unit_id: Int)
  /// The creature strikes the player.
  Attacks(tell: Tell)
}
