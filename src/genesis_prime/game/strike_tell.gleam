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
////   SentByFoe(Attacks(Strike(key, Creature(..), CreatureStriker(unit, spell4_id), offence)))
////                                          ◀─ the creature's own strike
////   hit rule on the player's health and shield, rolls from the player's seed
////   Tell(Creature(..), TellStrikeAnswered(Answered(key, outcome))) ─▶ the creature's round
////   SentByFoe(Released(unit))              ◀─ the creature took the player off its threat list
////   (each SentByFoe travels for the player's stay: ForStay(stay, SentByFoe(..)))
////
//// caster's connection C                                     healed player's connection T
////   Tell(Connection(T), TellPlayerStrike(stay_T, PlayerStrike(key, C, stay_C, outgoing, heals)))
////                                                            ─▶ each heal row on T's life, in order
////   SentByHealed(PlayerAnswered(key, outcome)) ◀─ Tell(Connection(C), TellPlayerAnswer(stay_C, ..)),
////                                                 then T's own news
//// ```
////
//// - **The key** names one strike: the cast, the occasion (a go's phase, or a tick of
////   one of its periodic rows) and the struck unit, so an answer finds its round and a
////   late one finds none.
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
//// - **The answer marks the state that broke a cast**: the creature sets
////   `ControlLanded.interrupted` on the first landed state of the strike that broke its
////   open cast, so the striker's connection writes the combat log's interrupt line with the
////   go (genesis_prime/game/cast/frame `states_logged`) and no message is added. A state
////   that breaks nothing, a death and a leash carry no mark
////   (genesis_prime/world_map/creature_control `gaps` lists what no mark covers).
//// - **A strike carries the gates of its rows** (`Gate`): each row of the strike, damage,
////   crowd control or go, whose target apply prerequisite reads the struck creature's own
////   state, with the prerequisite as parsed. The creature checks them against its own state
////   when the strike arrives (genesis_prime/game/prerequisite `of_creature`), before the hit
////   rule, and answers the effect ids it passed (`gates_passed`) with `Landed`, `Immune` and
////   `Deflected`, so a deflect still checks its gates: a blow or state of a row that did
////   not pass is not dealt or taken, so it is in neither `descriptions` nor `controls`. A
////   gated go row applies on a unit only when that unit's answer lists its id
////   (genesis_prime/game/cast `went`): `Refused`, an answer after the round closed and no
////   answer at all pass no gate. A row with no gate is unaffected. A phase whose struck
////   units get a gated go row and nothing else still tells them a strike, with no blows and
////   no states: a go row that needs no gate sends none. No call, process or timer is added:
////   the check is the creature's own step of the strike it was told, and the round's one
////   deadline covers it.
//// - **A strike told to another player carries heals only** (`PlayerStrike`): the rows that
////   passed the caster's gates and the caster's outgoing heal multiplier, and the healed
////   player's connection applies them to its own life and answers each row's split
////   (genesis_prime/game/connection/landing). It carries no deadline, so a late one is applied.
//// - **A player's strike carries its place and move sequence number**, so a
////   creature it puts on a fight finds it, ordered with the moves its connection
////   tells (genesis_prime/world_map/creature_fight).

import genesis_prime/game/crowd_control
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/heal_split
import genesis_prime/game/hit.{type Description, type Offence, type Rolls}
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{type Address, type ConnectionId}
import genesis_prime/table/id.{type Spell4EffectsId, type Spell4Id}
import genesis_prime/world_map/stay.{type Stay}
import gleam/option.{type Option}

/// How long a round waits for its answers, in milliseconds. A creature's respawn time
/// is never below it (genesis_prime/world_map/creature_kind), so a unit does not stand
/// again while a round it was struck in is open.
pub const deadline_ms = 1000

/// One strike: the cast, the occasion and the struck unit.
pub type Key {
  Key(cast_id: Int, occasion: Occasion, unit_id: Int)
}

/// What a strike of a cast is for: a go of the phase `phase`, or the tick `tick` of the
/// periodic damage row `effect_id` in the schedule its `go`th go on the unit started
/// (genesis_prime/game/ticking): a later go starts the schedule again, and a round of
/// the earlier schedule may still be open with the same tick number.
pub type Occasion {
  AtGo(phase: Int)
  AtTick(effect_id: Spell4EffectsId, go: Int, tick: Int)
}

/// What a striker tells the unit it strikes: the strike's key, the striker's
/// address, which the answer goes to, who the striker is, its offence, the
/// crowd-control states its phase puts on the unit, and the gates of its rows
/// that the unit checks against its own state.
pub type Tell {
  Strike(
    key: Key,
    from: Address,
    striker: Striker,
    offence: Offence,
    controls: List(ControlTell),
    gates: List(Gate),
  )
}

/// The target apply prerequisite of one row of a strike, which the struck creature
/// checks against its own state (`Spell4Effects.prerequisiteIdTargetApply`): the row's
/// Spell4Effects id, which a blow (`hit.Blow.spell4_effects_id`) or a state
/// (`ControlTell.effect_id`) of the row carries too, and the prerequisite as the load
/// parsed it, so the creature needs no table.
pub type Gate {
  Gate(effect_id: Int, prerequisite: Prerequisite)
}

/// A state the unit took: the effect as it was told, and the monotonic time in
/// milliseconds the creature holds it until (its arrival plus delay plus duration,
/// on the clock the creature and the caster's connection share), so the caster's
/// node for the state lives exactly as long as the state does. `interrupted` names the
/// cast this state broke: the creature marks the first state that landed of the strike
/// that broke an open charge or special, and no other, so the caster's combat log shows
/// the interrupt once (`opcode.0x247.interrupted`).
pub type ControlLanded {
  ControlLanded(
    tell: ControlTell,
    ends_at_ms: Int,
    interrupted: Option(Interrupted),
  )
}

/// The cast of the creature that a state broke: the Spell4 of the charge or special, which
/// the combat log line names as the spell interrupted.
pub type Interrupted {
  Interrupted(spell4_id: Spell4Id)
}

/// One CCStateSet effect a strike puts on the unit: its Spell4Effects id, the instance
/// id the caster gave it for the go, and its row (genesis_prime/game/crowd_control
/// `Row`: the state, the delay before and the duration of the effect in milliseconds,
/// and the Interrupt Armor it removes). The cast id is the strike's key's. The creature
/// holds the state from the tell until the delay and duration have passed and sends the
/// state's 0x87f and 0x880 with this instance id (`cc_state.instance_id`). A Knockback,
/// Pushback or Pull state carries the `throw` its helper spell names
/// (`spell_plan.CrowdControl.move`), which the creature that takes the state is thrown by;
/// its reference is the striker's place and hit radius when the strike was told.
pub type ControlTell {
  ControlTell(
    effect_id: Int,
    instance_id: Int,
    row: crowd_control.Row,
    throw: Option(forced_move.Throw),
  )
}

/// Who strikes, with what the struck unit's owner needs of it.
pub type Striker {
  /// A player: its unit, the place it struck from and the move sequence number of
  /// that place (genesis_prime/game/connection), its hit radius (its race's Race row,
  /// genesis_prime/game/hit_radius) and its rolls, from its connection's seed.
  PlayerStriker(
    unit_id: Int,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
    rolls: Rolls,
  )
  /// A creature, which keeps no random state: the struck player's connection
  /// draws the rolls. It names its unit and the Spell4 of the attack, the spell a
  /// player's procs of blows taken match their group filter against.
  CreatureStriker(unit_id: Int, spell4_id: Spell4Id)
}

/// Why a unit does not take a strike.
pub type Refusal {
  /// The unit is dead: it was killed after the striker's picture showed it
  /// alive (`Spell4ValidTargets.targetBitmask`: no area strikes a dead unit).
  Dead
  /// The creature gave up its fight and walks home, taking no strike until it
  /// is there.
  Returning
  /// The creature was removed from the field by a DespawnUnit effect and takes no strike
  /// until it stands again; `Dead` would name a death that did not happen.
  Despawned
}

/// What a creature answers a strike with.
pub type Outcome {
  /// The blows landed: a description for each (genesis_prime/game/hit), and the
  /// states the unit took of the strike's `controls` (a unit that takes none
  /// answers `[]`), and the interrupt armor the strike took off it (`armor_removed`, 0
  /// when none), which the striker's connection shows as a ModifyInterruptArmor line.
  /// `gates_passed` is the effect ids of the strike's `gates` the unit passed (`[]` when
  /// it has none): the blows and states of a gated row that is not listed are in none of the
  /// rest.
  Landed(
    descriptions: List(Description),
    controls: List(ControlLanded),
    armor_removed: Int,
    gates_passed: List(Int),
  )
  /// A guarded creature (genesis_prime/world_map/creature_guard) took no damage from a
  /// strike that had blows: it keeps its health, the states it took of the strike's
  /// `controls` still land, and the striker's connection shows the immunity
  /// (`opcode.0x247.immunity`). Its states can still wear down the creature's interrupt armor, so
  /// it carries `armor_removed` and `gates_passed` as `Landed` does.
  Immune(
    controls: List(ControlLanded),
    armor_removed: Int,
    gates_passed: List(Int),
  )
  /// The creature deflected the whole strike. It still checked the strike's gates and
  /// carries the ids it passed as `Landed` does; whether the deflect itself stops a go row
  /// stays as the cast rule has it (genesis_prime/game/cast `went`).
  Deflected(gates_passed: List(Int))
  /// The creature took no strike.
  Refused(why: Refusal)
}

/// The struck unit's answer to the strike of `key`.
pub type Answered {
  Answered(key: Key, outcome: Outcome)
}

/// One heal row a caster tells another player: the row's Spell4Effects id, the vital it
/// heals and the formula's amount from the caster's stats, before any multiplier.
pub type HealTell {
  HealTell(effect_id: Spell4EffectsId, vital: effect_kind.Vital, amount: Int)
}

/// What a caster's connection tells the connection of another player its cast heals:
/// the strike's key, the caster's connection and the caster's stay, which the answer is
/// told for, the caster's HealingMultiplierOutgoing (162) and the heal rows that passed
/// the caster's gates, in the plan's rank order. It carries heals only, so no blow, state
/// or gate can reach a player.
pub type PlayerStrike {
  PlayerStrike(
    key: Key,
    from: ConnectionId,
    stay: Stay,
    outgoing: Float,
    heals: List(HealTell),
  )
}

/// One heal row as the healed player applied it: the row, the vital and the split of the
/// amount the player's own multipliers and room gave.
pub type HealLanded {
  HealLanded(
    effect_id: Spell4EffectsId,
    vital: effect_kind.Vital,
    split: heal_split.Split,
  )
}

/// What a player answers a `PlayerStrike` with.
pub type PlayerOutcome {
  /// Every heal row was applied in the order told, each on the life the one before
  /// left; the list is the rows in that order.
  HealsLanded(heals: List(HealLanded))
  /// The player is dead and took no row.
  PlayerDead
}

/// The healed player's answer to the strike of `key`.
pub type PlayerAnswered {
  PlayerAnswered(key: Key, outcome: PlayerOutcome)
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
