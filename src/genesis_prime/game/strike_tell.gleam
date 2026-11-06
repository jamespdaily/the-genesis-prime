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
////   SentByTarget(Answered(key, outcome))   ◀─ Send(Connection(c), Answered(key, outcome)),
////                                             for the stay the strike was told for
////
////   SentByFoe(Threatened(unit, life))      ◀─ the creature put the player on its threat list
////   SentByFoe(Attacks(Strike(key, Creature(..), CreatureStriker, offence)))
////                                          ◀─ the creature's own strike
////   hit rule on the player's health and shield, rolls from the player's seed
////   Tell(Creature(..), TellStrikeAnswered(Answered(key, outcome))) ─▶ the creature's round
////   SentByFoe(Released(unit))              ◀─ the creature took the player off its threat list
////   (each SentByFoe travels for the player's stay: ForStay(stay, SentByFoe(..)))
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
//// - **A strike carries the crowd-control states** of its phase (`ControlTell`) beside
////   its damage, or alone: a phase with a stun and no damage still tells the unit
////   (Stagger's 38780). The creature answers `Landed` with the states it took, and
////   only those are listed in the caster's go (genesis_prime/world_map/creature_control).
//// - **A player's strike carries its place and move sequence number**, so a
////   creature it puts on a fight finds it, ordered with the moves its connection
////   tells (genesis_prime/world_map/creature_fight).

import genesis_prime/game/hit.{type Description, type Offence, type Rolls}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/step.{type Address}
import genesis_prime/world_map/stay.{type Stay}

/// How long a round waits for its answers, in milliseconds. A creature's respawn time
/// is never below it (genesis_prime/world_map/creature_kind), so a unit does not stand
/// again while a round it was struck in is open.
pub const deadline_ms = 1000

/// One strike: the cast, the go's phase and the struck unit.
pub type Key {
  Key(cast_id: Int, phase: Int, unit_id: Int)
}

/// What a striker tells the unit it strikes: the strike's key, the striker's
/// address, which the answer goes to, who the striker is, its offence, and the
/// crowd-control states its phase puts on the unit.
pub type Tell {
  Strike(
    key: Key,
    from: Address,
    striker: Striker,
    offence: Offence,
    controls: List(ControlTell),
  )
}

/// A state the unit took: the effect as it was told, and the monotonic time in
/// milliseconds the creature holds it until (its arrival plus delay plus duration,
/// on the clock the creature and the caster's connection share), so the caster's
/// node for the state lives exactly as long as the state does.
pub type ControlLanded {
  ControlLanded(tell: ControlTell, ends_at_ms: Int)
}

/// One CCStateSet effect a strike puts on the unit (genesis_prime/game/crowd_control
/// `Row`), with the instance id the caster gave it for the go: the state, the
/// delay before and the duration of the effect in milliseconds, and the Interrupt
/// Armor it removes (dataBits03). The cast id is the strike's key's. The creature
/// holds the state from the tell until the delay and duration have passed and
/// sends the state's 0x87f and 0x880 with this instance id (`cc_state.instance_id`).
pub type ControlTell {
  ControlTell(
    effect_id: Int,
    state: CrowdControlState,
    instance_id: Int,
    delay_ms: Int,
    duration_ms: Int,
    armor_removed: Int,
  )
}

/// Who strikes, with what the struck unit's owner needs of it.
pub type Striker {
  /// A player: its unit, the place it struck from and the move sequence number of
  /// that place (genesis_prime/game/connection), and its rolls, from its
  /// connection's seed.
  PlayerStriker(unit_id: Int, place: Place, seq: Int, stay: Stay, rolls: Rolls)
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
  /// The blows landed: a description for each (genesis_prime/game/hit), and the
  /// states the unit took of the strike's `controls` (a unit that takes none
  /// answers `[]`).
  Landed(descriptions: List(Description), controls: List(ControlLanded))
  /// The creature deflected the whole strike.
  Deflected
  /// The creature took no strike.
  Refused(why: Refusal)
}

/// The struck unit's answer to the strike of `key`.
pub type Answered {
  Answered(key: Key, outcome: Outcome)
}

/// What a creature that fights a player tells the player's connection, for the
/// player's stay (genesis_prime/world_map/stay).
pub type Fight {
  /// The creature `unit_id` of life `life` put the player on its threat list.
  Threatened(unit_id: Int, life: Int)
  /// The creature `unit_id` took the player off its threat list: it leashed or
  /// died, or the player died.
  Released(unit_id: Int)
  /// The creature strikes the player.
  Attacks(tell: Tell)
}
