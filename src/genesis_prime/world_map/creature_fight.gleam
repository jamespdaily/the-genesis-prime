//// A creature's fight: the feature of the creature's rule
//// (genesis_prime/world_map/creature) that decides whom it fights, where it runs,
//// when it strikes and when it gives up and walks home. Its health stays
//// creature_life's (genesis_prime/world_map/creature_life); the player's side of a
//// fight is the player's connection's (genesis_prime/game/player_life). It runs in
//// the creature's process, so every 0x908, 0x90a, 0x89a, 0x638, 0x7ff, 0x7f4 and
//// 0x7fe of the unit comes from its one owner.
////
//// From aggro to home, and what each side sends:
////
//// ```
//// P's connection           map                          creature C (this rule)                   C's viewers
//// 0x637 ─Moved(place, seq)─▶ P is ready, hostile, and
////                            crossed C's ring (aggro_range of the spawn)
////                          ─Approached(P, unit, place, seq)─▶ Resting, P a viewer:
////                                                         threat {P: aggro_threat}; near + P
////                                                         ─0x908(C, P, threat) 0x89a(C, 1)──────▶
//// ◀──────────────────────────────── Threatened(C, life) ──
//// 0x89a(P, 1) to P and P's viewers; P's place now, then each accepted 0x637:
//// ─TargetMoved(place, seq)────────────────────────────────▶ the newest seq per connection wins
////                                                         StartTimer(attack tick, interval)
////                                                         the target out of reach of the path's end:
////                                                         ─0x638[kind 0, kind 4 to the target less
////                                                            chase_stop_fraction x reach, at the run
////                                                            speed, clipped at the leash circle]──▶
//// the attack tick, the target in reach of place_at(path, now):
////                                                         ─0x7ff───────────────────────────────▶
//// ◀──────────── Attacks(Strike(key, C, CreatureStriker, offence)) ─ StartTimer(strike deadline, 1 s)
//// the hit rule on P's health and shield, rolls from P's seed
//// 0x938(20), 0x92f to P; 0x938, 0x937 to P's viewers
//// ─TellStrikeAnswered(Answered(key, Landed))──────────────▶ ─0x7f4(effect, P's descriptions) 0x7fe─▶
////                                                         the deadline first: the go leaves P out
//// the attack tick finds C at the leash circle with the target out of reach, or no threat is left:
////                                                         ─0x90a(C, X, 0) for each X, 0x89a(C, 0),
////                                                            0x937 full, 0x638 home────────────▶
//// ◀──────────────────────────────── Released(C) ─ to each threatened connection
//// 0x89a(P, 0) when no fighter is left; the stream stops   Returning: strikes Refused(Returning),
////                                                         Approached only adds to near
//// the home timer ─────────────────────────────────────▶   Resting; each near player it still sees
////                                                         is aggroed as by Approached
//// ```
////
//// - **Aggro** comes only from a viewer, by `Approached` while Resting: the map
////   sends it for a hostile creature (faction level 0 to 2) only. A Neutral creature
////   (3 to 7) enters a fight only by a player's strike (`0x1403ad540`). Any threat
////   above 0 shows the creature hostile (`0x14045a950`).
//// - **Threat** added by a strike is the damage taken times the effect's
////   `Spell4Effects.threatMultiplier`. The top entry is the target: a change of target
////   sends 0x908, and every other entry 0x90a (`opcode.0x908`, `opcode.0x90a`).
//// - **Threat only for viewers.** A strike or a `TargetMoved` from a connection that
////   is not a viewer adds no threat, and `Unwatched` drops the viewer's entry, so the
////   threat list is always within the viewers and the map's sweep, which retires only a
////   creature with no viewer, never retires a fighting one.
//// - **Ordering.** Each accepted 0x637 gets its connection's next move sequence
////   number (genesis_prime/game/connection). The creature keeps the newest per
////   connection and drops a lower one; an equal one is the same move. So `Approached`,
////   from the map, and `TargetMoved`, from the connection, two senders, may arrive in
////   either order. 0x637's client clock is not used: two moves of one frame share it
////   (`opcode.0x637.client_clock`).
//// - **The chase** is a straight path of kind 4 at the creature's run speed
////   (`movement_command.kind_4`, `0x1405b45e0`), planned again only when the target is
////   beyond reach of the current path's end, and clipped at the leash circle
////   (genesis_prime/world_map/creature_path).
//// - **Reach** is the attack spell's `targetMaxRange` plus the creature's hit radius,
////   centre to centre (a server choice; genesis_prime/world_map/creature_life `Attack`).
//// - **One strike round at a time.** The attack interval is never below the strike
////   deadline (genesis_prime/world_map/creature_kind), so a tick never finds a round
////   open.
//// - **The leash** is taken on an attack tick that finds the creature at the circle,
////   `leash_range` from its spawn, with its target out of reach, or when no threat is
////   left (274 section 3). Walking home it takes no strike and turns to no one; at home,
////   at full health, it aggroes the players still in its ring.
//// - **Death** sends 0x89a (C, 0) and `Released` to everyone on the threat list
////   (`death.combat_flag`); the respawn aggroes the players in its ring.
//// - **A player at 0** answers `Landed` with the killed bit; the creature releases it.
////
//// What happens at each deadline and process death:
////
//// | Point | What happens | Test |
//// |---|---|---|
//// | P's answer comes after the strike deadline | the go leaves P out; the hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | P's connection ends, camps or P goes out of sight | the map's `Unwatched` drops P from threat; with no threat left the creature leashes | `a_player_whose_connection_ends_mid_chase_makes_the_creature_leash_test` |
//// | a strike or `TargetMoved` from a connection that is not a viewer (a race with `Unwatched`) | the damage applies, no threat is added | `a_strike_from_a_non_viewer_adds_no_threat_test` |
//// | P and C strike each other at one instant | both are tells; each side answers in its own step, before the other's deadline | `mutual_strikes_are_both_answered_before_the_deadline_test` |
//// | C crashes mid-fight | the map sends every player `Gone`; P drops C, and sends 0x89a (P, 0) when no fighter is left (genesis_prime/game/player_life) | `a_creature_crash_mid_fight_clears_the_players_combat_flag_test` |
//// | C is told `Retire` while Returning | it stops; the map's sweep sends it only with no viewer, so no one is on its threat list | `a_creature_never_retires_with_a_player_on_its_threat_list_test` |
//// | the home timer fires | C stands at its spawn, Resting, at full health, and aggroes the near players it sees | `at_home_the_creature_aggroes_the_near_players_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{type Answered, type Fight as Told}
import genesis_prime/step.{type Address, type ConnectionId}
import genesis_prime/world_map/creature_life.{type Attack}
import genesis_prime/world_map/creature_path.{type Path}
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/set.{type Set}

/// What the creature fights with, fixed for its life: its unit and address, the
/// place of its spawn, which is home and the leash circle's centre, its attack, the
/// time between its attack ticks, and the run's game numbers.
pub type Fighter {
  Fighter(
    unit_id: Int,
    address: Address,
    home: Place,
    attack: Attack,
    interval_ms: Int,
    numbers: GameNumbers,
  )
}

/// Where the creature is in a fight.
pub type Status {
  /// At its spawn, fighting no one: a viewer's `Approached` aggroes it.
  Resting
  /// On a fight: its threat list, its path and its open strike round.
  Fighting(fight: Fight)
  /// Walking home after a leash, along `home`, taking no strike.
  Returning(home: Path)
  /// Lying dead, until creature_life's corpse timer stands it again.
  Dead
}

/// A fight the creature is on: the threat of each connection whose player is on its
/// list, never empty, the path it runs, and the strike round it waits on.
pub type Fight {
  Fight(threat: Dict(ConnectionId, Threat), path: Path, round: Option(Round))
}

/// One entry of the threat list: the player's unit and its threat.
pub type Threat {
  Threat(unit_id: Int, amount: Float)
}

/// The strike round the creature waits on: its key and the player struck.
pub type Round {
  Round(key: strike_tell.Key, target: ConnectionId)
}

/// The newest place the creature knows a connection's player at, with the move
/// sequence number it came with.
pub type Sighting {
  Sighting(unit_id: Int, place: Place, seq: Int)
}

/// A creature's fight: its status, the players inside its ring (from `Approached`
/// and `Withdrew`), the newest place of each player it heard of, and the number of
/// its next cast.
pub opaque type State {
  State(
    status: Status,
    near: Set(ConnectionId),
    sightings: Dict(ConnectionId, Sighting),
    next_cast: Int,
  )
}

/// What the creature's rule turns its messages and timers into for the fight.
pub type Input {
  /// The map: the player of `by` entered the creature's ring, at `place` of move
  /// `seq`.
  Approached(by: ConnectionId, unit_id: Int, place: Place, seq: Int)
  /// The map: the player of `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The player of `by`, on the threat list, moved to `place` of move `seq`.
  TargetMoved(by: ConnectionId, place: Place, seq: Int)
  /// A player's strike landed on the creature for `threat` (the damage taken times
  /// each effect's threatMultiplier), from `place` of move `seq`.
  StruckBy(
    by: ConnectionId,
    unit_id: Int,
    place: Place,
    seq: Int,
    threat: Float,
  )
  /// The map: the player of `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
  /// The player's answer to the creature's strike.
  StrikeAnswered(answered: Answered)
  /// One of the fight's timers fired.
  TimerFired(timer: Timer)
  /// creature_life: a strike killed the creature.
  Killed
  /// creature_life: the corpse timer stood the creature again at its spawn.
  StoodAgain
}

/// The fight's timers: the creature's rule gives each a timer id of its own.
pub type Timer {
  /// Every `interval_ms` while Fighting: strike when the target is in reach, else
  /// chase or leash.
  AttackTick
  /// The strike round's deadline (genesis_prime/game/strike_tell `deadline_ms`).
  StrikeDeadline
  /// The walk home is run.
  HomeArrival
}

/// What the fight asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer.
  ToViewers(news: News)
  /// A tell to the connection of a player in the fight.
  ToPlayer(to: ConnectionId, told: Told)
  StartTimer(timer: Timer, after_ms: Int)
  CancelTimer(timer: Timer)
}

/// A creature resting at its spawn, with no one near.
pub fn new() -> State {
  todo as "new: the build fills it in"
}

/// One input of the fight in, the new state and the effects out. `viewers` are the
/// creature's viewers now; `now_ms` the monotonic time of the input.
pub fn step(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Set(ConnectionId),
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  todo as "step: the build fills it in"
}

/// The fight's status.
pub fn status(state state: State) -> Status {
  state.status
}

/// Whether the creature takes a strike: a creature walking home refuses it.
pub fn refusal(state state: State) -> Result(Nil, strike_tell.Refusal) {
  todo as "refusal: the build fills it in"
}

/// The connections on the threat list: none unless Fighting.
pub fn threatened(state state: State) -> Set(ConnectionId) {
  todo as "threatened: the build fills it in"
}

/// Where the creature stands at monotonic time `now_ms`, for the 0x262 of a viewer
/// that arrives while it runs.
pub fn place_at(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> Place {
  todo as "place_at: the build fills it in"
}
