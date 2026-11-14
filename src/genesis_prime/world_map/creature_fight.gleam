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
//// A player's death, and what the creature does with it (the player's side is
//// genesis_prime/game/player_life; the map's is genesis_prime/world_map/map `LifeChanged`):
////
//// ```
//// C strikes P; the hit leaves P at 0
//// P's connection                map                          creature C                      C's viewers
//// Answer(Landed, killed) ───────────────────────────────────▶ P out of near; the entry is
////                                                            released (below)
//// TellLifeChanged(False) ─LifeChanged(P, False)─▶ P Dead; `inside` emptied
////                          ─PlayerDied(P)─▶ C, and each Live spawn P sees
////                                                         P not near, not on the list: nothing
//// C2 fighting P too, takes PlayerDied(P):
////                                                         P out of near; P's entry erased:
////                                                         ─0x90a(C2, P, 0)─────────────────────▶
////                                                         another entry: 0x908 names it, Released
////                                                         to P; the next attack tick strikes it
////                                                         P the only entry: the leash, as
////                                                         for a release; at home no one is aggroed
//// C Resting or Returning, P near, takes PlayerDied(P):
////                                                         P out of near: the home timer and the
////                                                         corpse timer aggro no one for P
//// P wakes in C's ring: LifeChanged(P, True) ─Approached(P, ..)─▶ C Resting: aggro, as a walk-in
//// ```
////
//// A charge, the attack of a creature whose spell has a cast time (`creature_life.Charged`):
////
//// ```
//// the attack tick, the target in reach of C's place, no round open:
////                                                         round = Charging(CastEnds generation);
////                                                            the attack tick's generation moves on and no
////                                                            next attack tick starts: the round's close starts it
////                                                         ─0x7ff(cast id, spell, target, C's place)────────▶ the client draws the
////                                                         StartTimer(CastEnds, cast time)                    telegraph from the spell
//// CastEnds of the round's generation, C alive and Fighting:
////                                                         the fighters on the threat list inside the
////                                                         attack's area (from C's place along its aim) by
////                                                         their newest sightings
////                                                         none inside: ─0x7f4 (no unit) 0x7fe───▶ round closed; the
////                                                            next attack tick (interval) is started
////                                                         some inside: round = Striking, one awaiting entry
////                                                            per fighter
//// ◀─── Attacks(Strike(key, C, CreatureStriker, offence)) to each fighter ─ StartTimer(strike deadline, 1 s)
//// each fighter's answer, the strike round's way (above) ───▶ the last answer or the deadline closes the round
////                                                         (0x7f4 listing each fighter that landed, 0x7fe); the
////                                                         next attack tick (interval) is started
//// a viewer that arrives while the charge is open:
////                                                         ─0x7ff(the open charge's cast id, spell, target, place)─▶
//// a crowd-control state takes hold of C while the round is Charging (`Controlled`):
////                                                         CancelTimer(CastEnds); round closed, the next attack
////                                                            tick (interval) started
////                                                         ─0x7f9(cast id, result 11) 0x7fe─────────────────▶
////                                                         ChargeInterrupted(cast id) ─▶ creature_guard `Interrupted`
//// ```
////
//// - **Aggro** comes only from a viewer, by `Approached` while Resting: the map
////   sends it for a hostile creature (faction level 0 to 2) only. A Neutral creature
////   (3 to 7) enters a fight only by a player's strike (`0x1403ad540`). Any threat
////   above 0 shows the creature hostile (`0x14045a950`). The map leaves a stealthed
////   player out of every ring (genesis_prime/world_map/map `StealthChanged`, Jim's
////   decision, a server choice): it sends `Withdrew` when the player enters stealth and
////   `Approached` when it leaves stealth inside the ring. So the home timer and the
////   respawn, which aggro the players in `near`, do not aggro a stealthed one, and a
////   creature already fighting it keeps it on its threat list, since `Withdrew`
////   touches only `near`.
//// - **A dead player is not aggroed** (server choice: the client holds no creature rule,
////   and a dead unit is struck by nothing, `Spell4ValidTargets.targetBitmask`). The map
////   leaves a dead player out of every ring and sends `PlayerDied` to each creature the
////   player sees (genesis_prime/world_map/map `LifeChanged`); the creature drops the
////   player from `near` and from its threat list. A player that wakes inside the ring is
////   sent `Approached` as a walk-in or a stealth exit is, so it is aggroed.
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
//// - **A path that ends in standing is replaced.** A new path that is no distance
////   to run (the leash in the instant a chase began, a target that doubled back
////   onto the creature, a death) is sent as 0x638 of kind 2 at the creature's place with its
////   blend bit clear, which places the unit at once (`0x1407138f0`, `0x140714120`), but
////   only while the path last sent is still being run; a creature that has stood
////   since its path ended sends nothing. A death mid-path places the viewers where
////   the creature fell the same way.
//// - **Reach** is the attack spell's `targetMaxRange` plus the creature's hit radius,
////   centre to centre (a server choice; genesis_prime/world_map/creature_life `Attack`).
//// - **One round at a time.** The attack interval is never below the strike
////   deadline (genesis_prime/world_map/creature_kind), so a tick of an attack with no cast
////   time never finds a round open. A charge is the open round before its strike (`Charging`,
////   then `Striking`): it starts no attack tick, the close of its round starts the next, and
////   a tick that finds a charge open does nothing, so there is never a second round.
//// - **The charge's area** is the attack spell's damage telegraph, drawn on the caster, in the
////   selection of its area row (genesis_prime/game/spell_area `area_of_spell`,
////   genesis_prime/game/area `select`). The 0x7ff carries no telegraph position: the client
////   draws the shape on the caster itself (`0x140546e60`) and turns it with the caster's
////   yaw on every update (`0x14054b1b0.follows_caster`).
//// - **The charge's aim.** An aiming turret turns its aim toward its 0x908 target, not the
////   0x7ff's, all through a cast whose spell has the follow flag, and its telegraph turns with
////   it (`0x14046cdc0.turret_cast_aim`). So at `CastEnds` the area points along the bearing
////   from the turret to the fight's target, the unit its 0x908 names, by that player's
////   newest sighting, not along where the player stood at the go: a fighter that left that
////   line is not struck, and one that walked round the turret with its target is. With no
////   sighting of the target the strike goes along the turret's body yaw, the facing of its
////   place. The server never turns the body: the 0x7ff's yaw turns nothing
////   (`creature.facing`).
//// - **A creature that cannot move** (a unit type that never moves: a turret,
////   `creature_unit_type.can_move`) sends no 0x638 to chase or walk home. An attack tick that
////   finds its target beyond the leash range from home releases it as the leash does, but goes
////   straight to Resting where it stands: no walk and no home timer. A player that entered
////   its ring before is aggroed again only when it enters it again (`Approached`).
//// - **Reach of a charge** is the area row's max range, not the spell's `targetMaxRange`
////   (genesis_prime/world_map/spawn `attack_of`): the charge starts when the target is inside
////   the range the area covers.
//// - **The leash** is taken on an attack tick that finds the creature at the circle,
////   `leash_range` from its spawn, with its target out of reach, or when no threat is
////   left (274 section 3). Walking home it takes no strike and turns to no one; at home,
////   at full health, it aggroes the players still in its ring.
//// - **Death** sends 0x89a (C, 0) and `Released` to everyone on the threat list
////   (`death.combat_flag`); the respawn aggroes the players in its ring. Whether the
////   creature stands or lies dead is creature_life's alone: the fight leaves at the
////   kill, and the creature's place, kept apart from the fight's status, stays where
////   it fell.
//// - **A leash restores the health**: the fight asks the creature's rule
////   (`RestoreHealth`), which sets creature_life's health to full and sends the 0x937.
//// - **Every timer carries a generation**: a tick of a fight that ended, a deadline
////   of a round that closed or a home timer of an earlier walk does nothing when it
////   fires, though it waited in the mailbox when it was cancelled.
//// - **A player at 0** answers `Landed` with the killed bit, or `Refused(Dead)` to a strike
////   that finds it dead; the creature releases it and also drops it from `near`, so its home
////   timer, which can fire 0 ms after a kill at its spawn, does not aggro the body before the
////   map's `PlayerDied` arrives. `PlayerDied` does the same for a creature whose strike did not
////   kill it, and for one that holds the player only in `near` or on its list.
//// - **What a held state stops** (genesis_prime/world_map/creature_control), by the state:
////   - A state whose CCStates flags hold the value 2 (Stun, Sleep, Root, Hold, Knockdown, Disable,
////     Knockback, Pushback, Pull, PositionSwitch, DisableCinematic) starts no chase or walk
////     home, and a path the creature runs stops where it stands, as at a death
////     (`Fighter.still`). When the last such state ends it acts again from where it stands
////     (`Controlled`, `ControlEnded`).
////   - A state the attack spell's caster conditions mask (Spell4CCConditions) starts no strike
////     of an instant attack, and a Stun, Knockdown or Knockback starts none whatever the mask
////     (`Fighter.attack_refused`).
////   - A charge starts only while no state is held (`Fighter.holds_a_state`); that is a gap,
////     since the client's conditions for the charge spells mask nothing (issue 801).
////   - The attack tick goes on and does nothing else; threat, targets and the viewers' news are
////     kept as usual, and a creature that stands still (`Fighter.still`) does not leash from its
////     tick: out of reach at its leash circle it stays in the fight, with its threat and its health,
////     and leashes at the first tick after the state ends. It leashes in place only when its
////     last threat entry goes while it is held (`Released`), when the walk home waits for `ControlEnded`.
//// - **A state breaks a charge.** Any crowd-control state that takes hold while the round is
////   `Charging` ends the cast. The authority is Jim's decision of 2026-11-11 ("any crowd control
////   that lands during the charge is the interrupt"); the client holds no rule for it. Spell4 85474's
////   tooltip, text 748852 ("unless it is interrupted while charging"), and Spell4 85469's hint, text
////   748860, are evidence for the Sim-Turrets only. Interrupt Armor already decides whether a state
////   lands (genesis_prime/world_map/creature_control), so the fight breaks the charge only when a
////   state took hold. The fight cancels the `CastEnds` timer, writes 0x7f9 with result
////   11 (SpellInterrupted) and the 0x7fe, closes the round, starts the next attack tick and asks the
////   creature's rule to tell the guard (`ChargeInterrupted`, with the charge's cast id), which opens the creature
////   (genesis_prime/world_map/creature_guard). A creature holding a state starts no charge, so a state
////   that lands in a charge is the first; once the go is out (`Striking`) the strikes are out and
////   nothing breaks. The break is the fight's
////   for any creature with a charge, guarded or not: a bare turret's charge breaks the same way
////   and the guard, finding itself `Bare`, opens nothing.
//// - **An opened creature is held** (`Fighter.still`, `attack_refused` and `holds_a_state`): it
////   starts no charge, strike, chase or walk until its opening ends, when `ControlEnded` lets it
////   act again.
////
//// What happens at each deadline and process death:
////
//// | Point | What happens | Test |
//// |---|---|---|
//// | P's answer comes after the strike deadline | the go leaves P out; the hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | P's connection ends, camps or P goes out of sight | the map's `Unwatched` drops P from threat; with no threat left the creature leashes | `a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test` |
//// | a strike or `TargetMoved` from a connection that is not a viewer (a race with `Unwatched`) | the damage applies, no threat is added | `a_strike_from_a_non_viewer_adds_no_threat_test` |
//// | P and C strike each other at one instant | both are tells; each side answers in its own step, before the other's deadline | `a_medic_and_a_beast_striking_each_other_at_one_instant_both_get_their_answers_before_either_deadline_test` |
//// | C crashes mid-fight | the map sends every player `Gone`; P drops C, and sends 0x89a (P, 0) when no fighter is left (genesis_prime/game/player_life) | `a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test` |
//// | C is told `Retire` while Returning | it stops; the map's sweep sends it only with no viewer, so no one is on its threat list | `over_random_sights_rings_strikes_and_ticks_the_threat_list_stays_within_the_viewers_test` |
//// | a timer of a round that closed, or of a fight that ended, fires | it is of an old generation and does nothing | `a_deadline_timer_already_fired_for_a_closed_round_does_nothing_test` |
//// | C dies while it runs | it rests where it fell, and a viewer that arrives before its respawn is shown it there | `a_viewer_arriving_between_a_running_creatures_death_and_its_respawn_sees_it_where_it_fell_test` |
//// | P dies and C's killing answer and the map's `PlayerDied` both reach C | two senders, either order: the first drops P from `near` and the threat list, the second finds nothing | `a_creature_told_player_died_for_its_target_erases_its_entry_names_the_next_and_never_strikes_the_body_test`, `player_died_for_a_player_neither_near_nor_on_the_list_changes_nothing_test` |
//// | P died and C's home timer or corpse timer fires before `PlayerDied` reaches C | C aggroes the body; P drops `Threatened`, C's first strike is refused `Dead`, and C releases P and drops it from `near`: at most one swing, in the window of one map hop | `a_creature_that_kills_its_only_target_in_its_ring_does_not_aggro_the_body_at_its_home_timer_test`, `a_creature_whose_strike_is_refused_dead_does_not_aggro_the_body_at_its_home_timer_nor_when_its_corpse_timer_stands_it_test` |
//// | a strike P sent before it died reaches C after `PlayerDied` | `StruckBy` adds P to the threat list; C's first strike is refused `Dead` and releases it |  |
//// | `PlayerDied` for a player on neither `near` nor the threat list (its `Unwatched` came first, or the killing answer dropped it) | nothing | `player_died_for_a_player_neither_near_nor_on_the_list_changes_nothing_test` |
//// | C is Returning, or dead, when `PlayerDied` reaches it | Returning: P out of `near`, nothing sent; dead: the send is dropped, and the map's `inside` holds no dead player for C's next start | `a_near_player_told_player_died_is_not_aggroed_at_the_home_timer_nor_by_the_corpse_timer_and_one_approached_again_is_test` |
//// | P dies, wakes inside C's ring, and C's killing answer reaches C after the wake's `Approached` | the answer drops P from `near` after the wake put it there: P stands in the ring and is not aggroed until it enters again; the answer is taken only before the strike deadline (`strike_tell.deadline_ms`, 1000 ms), so the gap is a Wake Here chosen within that second of the death |  |
//// | the home timer fires | C stands at its spawn, Resting, at full health, and aggroes the near players it sees | `at_home_the_creature_aggroes_the_near_players_test` |
//// | Charge start: the attack tick finds the target in reach, no round open, the attack is `Charged` | round Charging, 0x7ff of the spell, `StartTimer(CastEnds, cast time)`, no strike and no next attack tick; the tick's generation moves on | `a_charge_starts_with_its_cast_time_and_telegraph_test` |
//// | Charge start: a second attack tick finds the charge open | nothing: the tick it came from is of an old generation | `a_second_attack_tick_during_a_charge_starts_nothing_test` |
//// | Charge start: the guard holds the number `next_cast` offers | the round takes the next free id and `next_cast` moves past that id, so two charges in a row take different ids and a late answer to the first closes nothing of the second | `two_charges_under_a_held_guard_take_different_cast_ids_test` |
//// | CastEnds timer: it fires for the open charge | each fighter on the threat list inside the rectangle along the bearing to the target now gets a strike, and the strike deadline starts; none inside, the go (0x7f4) names no unit and 0x7fe follows | `at_its_end_the_charge_strikes_each_fighter_inside_its_rectangle_test`, `a_charge_faces_its_target_test`, `a_charge_with_nobody_inside_goes_with_no_target_test` |
//// | CastEnds timer: it fires for a charge that ended (a death or a leash) or of an old generation | it does nothing | `a_stale_cast_end_does_nothing_test` |
//// | a state takes hold during the charge | `CancelTimer(CastEnds)`, 0x7f9 (cast id, 11) and 0x7fe, the round closed, the next attack tick started, `ChargeInterrupted` | `a_state_that_takes_hold_during_the_charge_breaks_it_so_the_cast_end_strikes_no_one_test`, `a_stun_on_the_target_during_the_charge_breaks_it_and_the_next_attack_tick_starts_test`, `a_stun_during_the_charge_interrupts_it_and_opens_the_turret_test` |
//// | CastEnds timer: it fires after an interrupt | the round was closed and the generation moved on, so it does nothing | `a_cast_end_after_an_interrupt_is_stale_test` |
//// | a state takes hold after the go (the round is `Striking`) | nothing breaks: the strikes are out | `an_interrupt_after_the_go_opens_nothing_test` |
//// | a second state takes hold in the same round | the first state closed the round, so the second finds no charge: nothing more | `a_second_state_in_the_same_round_opens_nothing_more_test` |
//// | CastEnds timer: a fighter was released during the charge | it is off the threat list, so it is not struck | `a_fighter_released_mid_charge_is_not_struck_test` |
//// | Strike to a fighter: its answer, the last one or the deadline | each answer joins the go as a round's does; the last answer or the deadline closes the round (0x7f4, 0x7fe), and the next attack tick starts | `the_struck_go_and_finish_follow_the_answers_test` |
//// | Death or leash during the charge: C is killed, or its last threat entry is released | `CancelTimer(CastEnds)` and 0x7fe for the charge, no 0x7f4, then the death or the release as without a charge; the later CastEnds does nothing | `death_during_a_charge_ends_it_test`, `leash_during_a_charge_ends_it_test` |
//// | a viewer arrives while the charge is open | its news holds the charge's 0x7ff, with its cast id, so its client takes the later 0x7f4 | `a_viewer_arriving_mid_charge_gets_the_open_cast_test` |
//// | a viewer arrives while the charge is open and the threat list's top entry changed since it began | its 0x7ff names the top entry, the target its 0x908 names | `a_viewer_arriving_mid_charge_is_told_the_current_target_in_the_open_cast_test` |
//// | a creature that cannot move: its target is out of reach, or beyond the leash range from home | out of reach: no 0x638, it keeps its place; beyond the leash range: the release as the leash does, with no walk, to Resting | `a_turret_never_chases_or_walks_home_test`, `a_turret_leashes_in_place_when_its_target_is_beyond_its_leash_range_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/area.{type Inside, type Row}
import genesis_prime/game/cast
import genesis_prime/game/hit.{type Offence}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight as Told, type Key, Attacks, CreatureStriker,
  Released, Threatened,
}
import genesis_prime/step.{type Address, type ConnectionId}
import genesis_prime/world_map/creature_life.{type Attack, Charged, Instant}
import genesis_prime/world_map/creature_path.{
  type Path, Circle, Running, Standing,
}
import genesis_prime/world_map/creature_unit_type.{type CreatureUnitType}
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// What the creature fights with: its unit and address, the place of its spawn,
/// which is home and the leash circle's centre, its attack, the time between its
/// attack ticks and the run's game numbers, which are fixed for its life; what its held
/// crowd-control states stop it doing now, which the creature's rule gives each step
/// (genesis_prime/world_map/creature_control); and the ids of the guard's live casts
/// (`creature_guard.live_casts`), which its casts take no id of (`cast.mint`). An opened
/// creature (genesis_prime/world_map/creature_guard `opened`) is stopped in all three.
/// - `still`: it holds a state that stops its run (genesis_prime/game/crowd_control
///   `stopping_mask`), so `chase` starts no path, `leash` starts no walk and a state that
///   takes hold stands it where it is.
/// - `attack_refused`: it holds a state its attack spell's caster conditions mask, or a
///   Stun, Knockdown or Knockback, so `ticked` starts no strike of an instant attack.
/// - `holds_a_state`: it holds any state, so `ticked` starts no charge (a gap that issue 801
///   closes) and a state that takes hold during a charge breaks it.
/// An attack that is `Charged` is a charge, and a creature whose unit type cannot move never
/// chases or walks home.
pub type Fighter {
  Fighter(
    unit_id: Int,
    address: Address,
    unit_type: CreatureUnitType,
    home: Place,
    attack: Attack,
    interval_ms: Int,
    numbers: GameNumbers,
    still: Bool,
    attack_refused: Bool,
    holds_a_state: Bool,
    guard_casts: List(Int),
  )
}

/// Where a standing creature is in a fight. Whether it is alive is creature_life's
/// (genesis_prime/world_map/creature_life): a creature that dies leaves its fight
/// and rests where it fell until its respawn.
pub type Status {
  /// Fighting no one: a viewer's `Approached` or a strike starts a fight.
  Resting
  /// On a fight: its threat list, never empty, the target it last named, the
  /// strike round it waits on, and the generation of its attack tick.
  Fighting(
    threat: Dict(ConnectionId, Threat),
    target: ConnectionId,
    round: Option(Round),
    tick: Int,
  )
  /// Walking home after a leash, taking no strike, until its home timer of this
  /// generation fires.
  Returning(home: Int)
}

/// One entry of the threat list: the player's unit, the stay of the message that
/// put it on the list, which every tell to it names, and its threat.
pub type Threat {
  Threat(unit_id: Int, stay: Stay, amount: Float)
}

/// The round the creature waits on: the number of its cast (`cast.cast_id`, the 0x7ff,
/// 0x7f4 and 0x7fe of the round name it) and where it stands.
pub type Round {
  Round(cast_id: Int, stage: Stage)
}

/// Where a round stands. An attack with no cast time starts at `Striking` with one
/// awaiting entry; a charge is `Charging` first, then `Striking` with an entry for each
/// fighter inside its rectangle.
pub type Stage {
  /// The cast is under way: the generation of its `CastEnds` timer, and the area row and rule
  /// the attack's `Charged` gave, which its end selects by. A state that takes hold while it
  /// lasts breaks it (`held`).
  Charging(ends: Int, area: Row, inside: Inside)
  /// The strikes are out: the generation of the deadline timer, the key of each strike
  /// not answered yet with the connection it went to, and what the answers struck so far
  /// (the go lists them). The round closes when none is awaited or at the deadline.
  Striking(
    deadline: Int,
    awaiting: Dict(Key, ConnectionId),
    struck: List(cast.Struck),
  )
}

/// The newest place the creature knows a connection's player at, with the move
/// sequence number and the stay it came with, and the hit radius of the player's race
/// (genesis_prime/game/hit_radius), which a charge's rectangle counts the player by.
pub type Sighting {
  Sighting(unit_id: Int, place: Place, seq: Int, stay: Stay, hit_radius: Float)
}

/// A creature's fight: its status, where it stands or runs (kept apart from the
/// status, and still where it fell while it lies dead), the players inside its
/// ring (from `Approached` and `Withdrew`), the newest place of each player it
/// heard of, the number of its next cast and the next timer generation.
pub opaque type State {
  State(
    status: Status,
    path: Path,
    near: Set(ConnectionId),
    sightings: Dict(ConnectionId, Sighting),
    next_cast: Int,
    next_generation: Int,
  )
}

/// What the creature's rule turns its messages and timers into for the fight.
pub type Input {
  /// The map: the player of `by`, in its stay `stay`, entered the creature's ring,
  /// at `place` of move `seq`, with the hit radius of its race.
  Approached(
    by: ConnectionId,
    unit_id: Int,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
  )
  /// The map: the player of `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The map: the player of `by` died. It leaves `near` and the threat list.
  PlayerDied(by: ConnectionId)
  /// The player of `by`, on the threat list, in its stay `stay`, moved to `place`
  /// of move `seq`; its race's hit radius is `hit_radius`.
  TargetMoved(
    by: ConnectionId,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
  )
  /// A player's strike landed on the creature for `threat`
  /// (`threat_of`), from `place` of move `seq`; its race's hit radius is `hit_radius`.
  StruckBy(
    by: ConnectionId,
    unit_id: Int,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
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
  /// creature_control: a state took hold of the creature while it lives. An open charge
  /// breaks; a path it runs stops where it stands (0x638 of kind 2 for its viewers, as at a
  /// death) when its states stop its run (`Fighter.still`).
  Controlled
  /// creature_control: the last state that stopped the creature's run ended. It acts again
  /// from where it stands: a fight chases its target and goes on; a creature that was to walk home
  /// when a state held it starts the walk.
  ControlEnded
  /// creature: a property modifier changed the creature's run speed
  /// (`fighter.attack.run_speed`). A path it runs at another speed is run on from where
  /// the creature stands at the new speed, to the same end.
  SpeedChanged
}

/// The fight's timers, each of the generation it was started with: a timer of a
/// generation the fight no longer waits on (a round that closed, a tick of a fight
/// that ended) does nothing when it fires.
pub type Timer {
  /// Every `interval_ms` while Fighting: strike when the target is in reach, else
  /// chase or leash.
  AttackTick(generation: Int)
  /// The strike round's deadline (genesis_prime/game/strike_tell `deadline_ms`).
  StrikeDeadline(generation: Int)
  /// The walk home is run.
  HomeArrival(generation: Int)
  /// The charge's cast time is up (`Attack.cast_ms` after its 0x7ff): the charge strikes.
  CastEnds(generation: Int)
}

/// What the fight asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer.
  ToViewers(news: News)
  /// A tell to the connection of a player in the fight, for the stay the fight
  /// holds it in.
  ToPlayer(to: ConnectionId, stay: Stay, told: Told)
  /// The creature stands at full health again: creature_life's health is restored
  /// and each viewer is sent its 0x937.
  RestoreHealth
  /// A crowd-control state broke the open charge: its `CancelTimer(CastEnds)`, the 0x7f9 of
  /// result 11 and the 0x7fe are in the effects before it, and the creature's rule tells the
  /// guard (`creature_guard.Interrupted`), which opens the creature.
  ChargeInterrupted(cast_id: Int)
  StartTimer(timer: Timer, after_ms: Int)
  CancelTimer(timer: Timer)
}

/// A creature resting at its spawn, with no one near.
pub fn new(home home: Place) -> State {
  State(
    status: Resting,
    path: Standing(at: home),
    near: set.new(),
    sightings: dict.new(),
    next_cast: 1,
    next_generation: 1,
  )
}

/// One input of the fight in, the new state and the effects out. `viewers` are the
/// creature's viewers now, each in the stay its `Watched` named, `alive` whether
/// creature_life holds it standing, and `now_ms` the monotonic time of the input.
/// A player's strike or move of another stay than its viewer's is of an earlier
/// stay, delayed past the player's leave and new join: it starts and moves nothing.
pub fn step(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Dict(ConnectionId, Stay),
  alive alive: Bool,
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case input {
    Approached(by:, unit_id:, place:, seq:, stay:, hit_radius:) -> {
      let state =
        State(
          ..sighted(state:, by:, unit_id:, place:, seq:, stay:, hit_radius:),
          near: set.insert(state.near, by),
        )
      case state.status, alive && in_stay(viewers:, by:, stay:) {
        Resting, True ->
          aggro(state:, fighter:, viewers:, players: [by], now_ms:)
        Resting, False | Fighting(..), _ | Returning(..), _ -> #(state, [])
      }
    }
    Withdrew(by:) -> #(State(..state, near: set.delete(state.near, by)), [])
    PlayerDied(by:) -> fell(state:, fighter:, by:, now_ms:)
    TargetMoved(by:, place:, seq:, stay:, hit_radius:) -> {
      use <- bool.guard(
        when: !in_stay(viewers:, by:, stay:),
        return: #(state, []),
      )
      let state =
        sighted(
          state:,
          by:,
          unit_id: unit_of(state:, by:),
          place:,
          seq:,
          stay:,
          hit_radius:,
        )
      case state.status, alive {
        Fighting(target:, ..), True if target == by ->
          chase(state:, fighter:, now_ms:)
        Fighting(..), _ | Resting, _ | Returning(..), _ -> #(state, [])
      }
    }
    StruckBy(by:, unit_id:, place:, seq:, stay:, hit_radius:, threat:) -> {
      use <- bool.guard(
        when: !in_stay(viewers:, by:, stay:),
        return: #(state, []),
      )
      let state =
        sighted(state:, by:, unit_id:, place:, seq:, stay:, hit_radius:)
      case alive {
        False -> #(state, [])
        True -> threatened_by(state:, fighter:, by:, stay:, threat:, now_ms:)
      }
    }
    Unwatched(by:) -> fell(state:, fighter:, by:, now_ms:)
    StrikeAnswered(answered:) ->
      answered_strike(state:, fighter:, answered:, now_ms:)
    TimerFired(timer: AttackTick(generation:)) ->
      case state.status, alive {
        Fighting(tick:, ..), True if tick == generation ->
          ticked(state:, fighter:, now_ms:)
        Fighting(..), _ | Resting, _ | Returning(..), _ -> #(state, [])
      }
    TimerFired(timer: StrikeDeadline(generation:)) ->
      case state.status {
        Fighting(
          round: Some(
            Round(stage: Striking(deadline:, struck:, ..), ..) as round,
          ),
          ..,
        )
          if deadline == generation
        -> {
          let #(state, closed) = round_closed(state:, round:, struck:, now_ms:)
          let #(state, ticking) = ticking_again(state:, fighter:)
          #(state, list.append(closed, ticking))
        }
        Fighting(..) | Resting | Returning(..) -> #(state, [])
      }
    TimerFired(timer: CastEnds(generation:)) ->
      case state.status {
        Fighting(
          round: Some(
            Round(stage: Charging(ends:, area:, inside:), ..) as round,
          ),
          ..,
        )
          if ends == generation
        -> charge_ended(state:, fighter:, round:, area:, inside:, now_ms:)
        Fighting(..) | Resting | Returning(..) -> #(state, [])
      }
    TimerFired(timer: HomeArrival(generation:)) ->
      case state.status {
        Returning(home:) if home == generation -> {
          let state =
            State(..state, status: Resting, path: Standing(at: fighter.home))
          aggro(
            state:,
            fighter:,
            viewers:,
            players: near_viewers(state:, viewers:),
            now_ms:,
          )
        }
        Returning(..) | Resting | Fighting(..) -> #(state, [])
      }
    Killed -> killed(state:, fighter:, now_ms:)
    Controlled -> held(state:, fighter:, now_ms:)
    ControlEnded -> resumed(state:, fighter:, now_ms:)
    SpeedChanged -> speed_changed(state:, fighter:, now_ms:)
    StoodAgain -> {
      let state =
        State(..state, status: Resting, path: Standing(at: fighter.home))
      aggro(
        state:,
        fighter:,
        viewers:,
        players: near_viewers(state:, viewers:),
        now_ms:,
      )
    }
  }
}

/// Whether the creature takes a strike: a creature walking home refuses it.
pub fn refusal(state state: State) -> Result(Nil, strike_tell.Refusal) {
  case state.status {
    Returning(..) -> Error(strike_tell.Returning)
    Resting | Fighting(..) -> Ok(Nil)
  }
}

/// The id of the cast the fight holds live: the open round's, which the guard's casts take no id
/// of (`cast.mint`); none with no round open.
pub fn live_casts(state state: State) -> List(Int) {
  case state.status {
    Fighting(round: Some(Round(cast_id:, ..)), ..) -> [cast_id]
    Fighting(..) | Resting | Returning(..) -> []
  }
}

/// The connections on the threat list: none unless Fighting.
pub fn threatened(state state: State) -> Set(ConnectionId) {
  case state.status {
    Fighting(threat:, ..) -> set.from_list(dict.keys(threat))
    Resting | Returning(..) -> set.new()
  }
}

/// Where the creature stands at monotonic time `now_ms`, for the 0x262 of a viewer
/// that arrives while it runs.
pub fn place_at(state state: State, now_ms now_ms: Int) -> Place {
  creature_path.place_at(path: state.path, now_ms:)
}

/// What a viewer that arrives at monotonic time `now_ms` is sent after the
/// creature's 0x262, so its client shows what the others' do: in a fight, the
/// combat flag (0x89a), the target (0x908) and each other entry (0x90a); a charge that is
/// open, its 0x7ff again with its cast id, which the later go names; and on a path not yet
/// run, the rest of it from where the creature is now (0x638).
pub fn arrival_news(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> List(News) {
  let fight = case state.status {
    Fighting(threat:, target:, ..) -> {
      let others =
        map.sorted_by_connection(threat)
        |> list.filter(fn(entry) { entry.0 != target })
        |> list.map(fn(entry) { threat_news(entry.1) })
      let assert Ok(top) = dict.get(threat, target)
        as "the target is on the threat list"
      [
        client_connection.CombatState(in_combat: True),
        targeting_news(top),
        ..others
      ]
    }
    Resting | Returning(..) -> []
  }
  let charge = case state.status {
    Fighting(
      threat:,
      target:,
      round: Some(Round(cast_id:, stage: Charging(..))),
      ..,
    ) -> {
      let assert Ok(top) = dict.get(threat, target)
        as "the target is on the threat list"
      [
        client_connection.CastStarted(start: cast.creature_started(
          cast_id:,
          spell4_id: fighter.attack.spell4_id.value,
          caster_unit_id: fighter.unit_id,
          target_unit_id: top.unit_id,
          place: creature_path.place_at(path: state.path, now_ms:),
        )),
      ]
    }
    Fighting(..) | Resting | Returning(..) -> []
  }
  let path = case state.path {
    Running(to:, speed:, ..) -> {
      let here = creature_path.place_at(path: state.path, now_ms:)
      case here == to {
        True -> []
        False -> [
          client_connection.CreatureMoved(path: Running(
            from: here,
            to:,
            started_ms: now_ms,
            speed:,
          )),
        ]
      }
    }
    Standing(..) -> []
  }
  list.flatten([fight, charge, path])
}

/// The threat a landed strike adds: each blow's damage taken (to health) times its
/// effect's threatMultiplier (`Spell4Effects.threatMultiplier`), matched by effect.
pub fn threat_of(
  offence offence: Offence,
  descriptions descriptions: List(hit.Description),
) -> Float {
  list.fold(descriptions, 0.0, fn(sum, description) {
    let multiplier =
      list.find(offence.blows, fn(blow) {
        blow.spell4_effects_id == description.spell4_effects_id
      })
      |> result.map(fn(blow) { blow.threat_multiplier })
      |> result.unwrap(1.0)
    sum
    +. int.to_float(description.damage.health_damage_with_overkill)
    *. multiplier
  })
}

/// Whether the player of `by` is a viewer in the stay `stay`.
fn in_stay(
  viewers viewers: Dict(ConnectionId, Stay),
  by by: ConnectionId,
  stay stay: Stay,
) -> Bool {
  dict.get(viewers, by) == Ok(stay)
}

/// The state with the player's newest place: in the same stay, a move of a lower
/// sequence number than the one held is older and dropped, and an equal one is the
/// same move; a sighting of another stay gives way to the newer stay's.
fn sighted(
  state state: State,
  by by: ConnectionId,
  unit_id unit_id: Int,
  place place: Place,
  seq seq: Int,
  stay stay: Stay,
  hit_radius hit_radius: Float,
) -> State {
  case dict.get(state.sightings, by) {
    Ok(held) if held.stay == stay && held.seq > seq -> state
    Ok(..) | Error(Nil) ->
      State(
        ..state,
        sightings: dict.insert(
          state.sightings,
          by,
          Sighting(unit_id:, place:, seq:, stay:, hit_radius:),
        ),
      )
  }
}

/// The unit the creature last knew the connection's player as, 0 for none.
fn unit_of(state state: State, by by: ConnectionId) -> Int {
  case dict.get(state.sightings, by) {
    Ok(sighting) -> sighting.unit_id
    Error(Nil) -> 0
  }
}

/// The near players the creature sees now, in the order of their connections.
fn near_viewers(
  state state: State,
  viewers viewers: Dict(ConnectionId, Stay),
) -> List(ConnectionId) {
  map.sorted_connections(set.intersection(
    state.near,
    set.from_list(dict.keys(viewers)),
  ))
}

/// A resting creature aggroes these players, each with the aggro threat, in the
/// stay its sighting came with (`start_fight`). No player it has a place for in
/// the stay it is a viewer in, no fight.
fn aggro(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Dict(ConnectionId, Stay),
  players players: List(ConnectionId),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let entries =
    list.filter_map(players, fn(player) {
      case dict.get(state.sightings, player) {
        Ok(sighting) ->
          case in_stay(viewers:, by: player, stay: sighting.stay) {
            True ->
              Ok(#(
                player,
                Threat(
                  unit_id: sighting.unit_id,
                  stay: sighting.stay,
                  amount: fighter.numbers.aggro_threat,
                ),
              ))
            False -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    })
  start_fight(state:, fighter:, entries:, now_ms:)
}

/// A resting creature starts a fight with these entries: the first is the target
/// (0x908), each other is named in 0x90a, the creature is in combat (0x89a), each
/// player is told `Threatened`, the creature chases its target when it is out of
/// reach, and the attack tick starts.
fn start_fight(
  state state: State,
  fighter fighter: Fighter,
  entries entries: List(#(ConnectionId, Threat)),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case entries {
    [] -> #(state, [])
    [first, ..others] -> {
      let #(state, tick) = generation(state)
      let state =
        State(
          ..state,
          status: Fighting(
            threat: dict.from_list(entries),
            target: first.0,
            round: None,
            tick:,
          ),
        )
      let named = [
        targeting(first.1),
        ..list.map(others, fn(other) { ToViewers(threat_news(other.1)) })
      ]
      let told =
        list.map(entries, fn(entry) {
          ToPlayer(
            to: entry.0,
            stay: { entry.1 }.stay,
            told: threatened_told(fighter:),
          )
        })
      let #(state, chased) = chase(state:, fighter:, now_ms:)
      #(
        state,
        list.flatten([
          named,
          [ToViewers(client_connection.CombatState(in_combat: True))],
          told,
          chased,
          [StartTimer(timer: AttackTick(tick), after_ms: fighter.interval_ms)],
        ]),
      )
    }
  }
}

fn threatened_told(fighter fighter: Fighter) -> Told {
  case fighter.address {
    step.Creature(life:, ..) -> Threatened(unit_id: fighter.unit_id, life:)
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.Connection(..)
    | step.CharacterNamed(..)
    | step.ZoneChannel(..) ->
      panic as "a creature's address is a Creature address"
  }
}

/// A viewer's strike, in its stay `stay`, adds its threat: a resting creature
/// starts a fight with it; a fighting one adds to its entry, naming a new top entry
/// as its target (0x908), and any other entry's new threat in 0x90a.
fn threatened_by(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  stay stay: Stay,
  threat threat: Float,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Returning(..) -> #(state, [])
    Resting ->
      start_fight(
        state:,
        fighter:,
        entries: [
          #(by, Threat(unit_id: unit_of(state:, by:), stay:, amount: threat)),
        ],
        now_ms:,
      )
    Fighting(threat: entries, target:, ..) as fighting -> {
      let unit_id = unit_of(state:, by:)
      let is_new = !dict.has_key(entries, by)
      let entries =
        dict.upsert(entries, by, fn(found) {
          case found {
            Some(entry) -> Threat(..entry, amount: entry.amount +. threat)
            None -> Threat(unit_id:, stay:, amount: threat)
          }
        })
      let #(top, top_entry) = top_of(entries)
      let state =
        State(
          ..state,
          status: Fighting(..fighting, threat: entries, target: top),
        )
      let told = case is_new {
        True -> [ToPlayer(to: by, stay:, told: threatened_told(fighter:))]
        False -> []
      }
      let named = case top != target || top == by {
        True -> [targeting(top_entry)]
        False -> {
          let assert Ok(entry) = dict.get(entries, by)
            as "the striker is on the list"
          [ToViewers(threat_news(entry))]
        }
      }
      #(state, list.append(named, told))
    }
  }
}

/// 0x908 naming the entry as the target, with its threat, to the viewers.
fn targeting(entry: Threat) -> Effect {
  ToViewers(targeting_news(entry))
}

/// The news of 0x908 naming the entry as the target, with its threat.
fn targeting_news(entry: Threat) -> News {
  client_connection.Targeting(
    target_unit_id: entry.unit_id,
    threat: whole(entry.amount),
  )
}

/// The news of 0x90a giving another entry's threat.
fn threat_news(entry: Threat) -> News {
  client_connection.Threat(
    other_unit_id: entry.unit_id,
    threat: whole(entry.amount),
  )
}

/// The top entry of a threat list: the most threat, the lowest connection on a tie.
fn top_of(entries: Dict(ConnectionId, Threat)) -> #(ConnectionId, Threat) {
  let assert [top, ..] =
    dict.to_list(entries)
    |> list.sort(fn(first, second) {
      float.compare({ second.1 }.amount, { first.1 }.amount)
      |> order.break_tie(map.compare_connections(
        first: first.0,
        second: second.0,
      ))
    })
    as "a fight's threat list is never empty"
  top
}

/// A player that is no longer a foe of the creature leaves the near players and the
/// threat list, and is told `Released`: a viewer that no longer sees the creature
/// (`Unwatched`), or a player that died (`PlayerDied`). The last one leashes the
/// creature, and a new top entry is named its target.
fn fell(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  released(
    state: State(..state, near: set.delete(state.near, by)),
    fighter:,
    by:,
    now_ms:,
  )
}

/// The player of `by` leaves the threat list and is told `Released`: with no one
/// left the creature leashes, which tells it with the rest of the leash, else its
/// entry is erased (0x90a 0) and a new top entry is named its target (0x908). A
/// player no longer on the list (its `Unwatched` came during the round) was
/// released then.
fn released(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let entry = case state.status {
    Fighting(threat: entries, ..) ->
      dict.get(entries, by) |> result.map(fn(entry) { #(entries, entry) })
    Resting | Returning(..) -> Error(Nil)
  }
  case entry {
    Error(Nil) -> #(state, [])
    Ok(#(entries, entry)) -> {
      let erased = ToViewers(threat_news(Threat(..entry, amount: 0.0)))
      let entries = dict.delete(entries, by)
      case dict.is_empty(entries) {
        True -> leash(state:, fighter:, now_ms:)
        False -> {
          let told =
            ToPlayer(
              to: by,
              stay: entry.stay,
              told: Released(unit_id: fighter.unit_id),
            )
          let #(state, named, chased) =
            retargeted(state:, fighter:, entries:, now_ms:)
          #(state, list.flatten([[erased], named, [told], chased]))
        }
      }
    }
  }
}

/// A fight left with these entries: its top entry is the target, named in 0x908
/// when it changed, and the creature chases it; the naming and the chase are given
/// apart, so the release goes between them.
fn retargeted(
  state state: State,
  fighter fighter: Fighter,
  entries entries: Dict(ConnectionId, Threat),
  now_ms now_ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  let assert Fighting(target:, ..) as fighting = state.status
    as "a fight is retargeted only while Fighting"
  let #(top, top_entry) = top_of(entries)
  let state =
    State(..state, status: Fighting(..fighting, threat: entries, target: top))
  let named = case top == target {
    True -> []
    False -> [targeting(top_entry)]
  }
  let #(state, chased) = chase(state:, fighter:, now_ms:)
  #(state, named, chased)
}

/// The attack tick: with the target in reach and no round open the creature
/// strikes, or opens its charge when its attack has a cast time; out of reach at the
/// leash circle it leashes; else it chases. The next tick starts unless it leashed or
/// opened a charge, whose round's close starts it. A creature whose states refuse its
/// attack starts none (`attacks`), and one whose states stop its run starts no path
/// (`chase`) and does not leash while they hold: out of reach at its circle it only
/// starts the next tick, and the first tick after they end leashes or chases. A creature
/// that cannot move is at its leash when its target is beyond the leash range from home,
/// since it never walks to the circle.
fn ticked(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Fighting(target:, round:, ..) = state.status
    as "a tick is taken only while Fighting"
  let here = creature_path.place_at(path: state.path, now_ms:)
  case dict.get(state.sightings, target) {
    Error(Nil) -> next_tick(state:, fighter:, effects: [])
    Ok(sighting) -> {
      let in_reach =
        creature_path.distance(from: here, to: sighting.place)
        <=. fighter.attack.reach
      let at_circle = case cannot_move(fighter:) {
        True ->
          creature_path.distance(from: fighter.home, to: sighting.place)
          >. fighter.numbers.leash_range
        False ->
          creature_path.distance(from: here, to: fighter.home)
          >=. fighter.numbers.leash_range -. circle_tolerance
      }
      case in_reach, round, at_circle {
        True, None, _ -> attacks(state:, fighter:, target:, sighting:, here:)
        True, Some(..), _ -> next_tick(state:, fighter:, effects: [])
        False, _, True if fighter.still ->
          next_tick(state:, fighter:, effects: [])
        False, _, True -> leash(state:, fighter:, now_ms:)
        False, _, False -> {
          let #(state, chased) = chase(state:, fighter:, now_ms:)
          next_tick(state:, fighter:, effects: chased)
        }
      }
    }
  }
}

/// The attack on a target in reach with no round open: the charge when the attack has
/// a cast time, else the strike, and the next tick for a strike. A charge starts only
/// while the creature holds no state, and a strike while none refuses the attack
/// (`Fighter`); otherwise the tick only starts the next.
fn attacks(
  state state: State,
  fighter fighter: Fighter,
  target target: ConnectionId,
  sighting sighting: Sighting,
  here here: Place,
) -> #(State, List(Effect)) {
  case fighter.attack.cast {
    Charged(..) if fighter.holds_a_state ->
      next_tick(state:, fighter:, effects: [])
    Instant if fighter.attack_refused -> next_tick(state:, fighter:, effects: [])
    Charged(cast_ms:, area:, inside:) ->
      charges(state:, fighter:, sighting:, here:, cast_ms:, area:, inside:)
    Instant -> {
      let #(state, struck) =
        strikes(state:, fighter:, target:, sighting:, here:)
      next_tick(state:, fighter:, effects: struck)
    }
  }
}

/// Whether the creature never moves: its unit type cannot.
fn cannot_move(fighter fighter: Fighter) -> Bool {
  !creature_unit_type.can_move(unit_type: fighter.unit_type)
}

/// How near the leash circle a creature counts as at it: a path clipped at the
/// circle ends on it, give or take a float's rounding.
const circle_tolerance = 0.01

fn next_tick(
  state state: State,
  fighter fighter: Fighter,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  let assert Fighting(..) as fighting = state.status
    as "a tick is started only while Fighting"
  let #(state, tick) = generation(state)
  #(
    State(..state, status: Fighting(..fighting, tick:)),
    list.append(effects, [
      StartTimer(timer: AttackTick(tick), after_ms: fighter.interval_ms),
    ]),
  )
}

/// The creature casts its attack on its target: 0x7ff to its viewers, the strike to
/// the target's connection, and the round's deadline.
fn strikes(
  state state: State,
  fighter fighter: Fighter,
  target target: ConnectionId,
  sighting sighting: Sighting,
  here here: Place,
) -> #(State, List(Effect)) {
  let cast_id =
    cast.mint(
      unit_id: fighter.unit_id,
      number: state.next_cast,
      live: fighter.guard_casts,
    )
  let key = strike_tell.Key(cast_id:, phase: 0, unit_id: sighting.unit_id)
  let #(state, deadline) = generation(state)
  let assert Fighting(..) as fighting = state.status
    as "a creature strikes only while Fighting"
  let stage =
    Striking(deadline:, awaiting: dict.from_list([#(key, target)]), struck: [])
  #(
    State(
      ..state,
      next_cast: cast.number_of(cast_id:) + 1,
      status: Fighting(..fighting, round: Some(Round(cast_id:, stage:))),
    ),
    [
      ToViewers(
        client_connection.CastStarted(start: cast.creature_started(
          cast_id:,
          spell4_id: fighter.attack.spell4_id.value,
          caster_unit_id: fighter.unit_id,
          target_unit_id: sighting.unit_id,
          place: here,
        )),
      ),
      ToPlayer(
        to: target,
        stay: sighting.stay,
        told: Attacks(
          tell: strike_tell.Strike(
            key:,
            from: fighter.address,
            striker: CreatureStriker,
            offence: fighter.attack.offence,
            controls: [],
          ),
        ),
      ),
      StartTimer(
        timer: StrikeDeadline(deadline),
        after_ms: strike_tell.deadline_ms,
      ),
    ],
  )
}

/// A fighter's answer to a strike of the open round: its go names what landed, and a
/// fighter the strike killed, or found dead, is released and leaves the near players, so
/// the creature's home timer or corpse timer does not aggro the body. The round closes
/// with the last answer; a charging creature then starts its next attack tick.
fn answered_strike(
  state state: State,
  fighter fighter: Fighter,
  answered answered: Answered,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(
      round: Some(Round(stage: Striking(awaiting:, ..), ..) as round),
      ..,
    ) ->
      case dict.get(awaiting, answered.key) {
        Ok(target) ->
          answer_taken(state:, fighter:, round:, target:, answered:, now_ms:)
        Error(Nil) -> #(state, [])
      }
    Fighting(..) | Resting | Returning(..) -> #(state, [])
  }
}

/// The answer of the fighter of `target`, to the strike round `round`: it joins the go, the
/// round closes when no answer is awaited, and a fighter the answer ends is released.
fn answer_taken(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  target target: ConnectionId,
  answered answered: Answered,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Striking(deadline:, awaiting:, struck: so_far) = round.stage
    as "an answer is taken only in a Striking round"
  let #(struck, ends_target, target_dead) = answer_of(answered:)
  let struck = list.append(so_far, struck)
  let awaiting = dict.delete(awaiting, answered.key)
  let last = dict.is_empty(awaiting)
  let #(state, closed) = case last {
    True -> {
      let #(state, closed) = round_closed(state:, round:, struck:, now_ms:)
      #(state, [CancelTimer(timer: StrikeDeadline(deadline)), ..closed])
    }
    False -> {
      let stage = Striking(deadline:, awaiting:, struck:)
      #(with_round(state:, round: Round(..round, stage:)), [])
    }
  }
  let #(state, ended) = case ends_target, target_dead {
    False, _ -> #(state, [])
    True, True -> fell(state:, fighter:, by: target, now_ms:)
    True, False -> released(state:, fighter:, by: target, now_ms:)
  }
  let #(state, ticking) = case last {
    True -> ticking_again(state:, fighter:)
    False -> #(state, [])
  }
  #(state, list.flatten([closed, ended, ticking]))
}

/// The state with `round` as its open round.
fn with_round(state state: State, round round: Round) -> State {
  let assert Fighting(..) as fighting = state.status
    as "a round is held only while Fighting"
  State(..state, status: Fighting(..fighting, round: Some(round)))
}

/// What the target's answer was: what struck for the round's go, whether the entry
/// ends (a kill or a refusal), and whether the target is dead (a kill or a `Dead`
/// refusal).
fn answer_of(answered answered: Answered) -> #(List(cast.Struck), Bool, Bool) {
  let unit_id = answered.key.unit_id
  case answered.outcome {
    strike_tell.Landed(descriptions:, ..) -> {
      let killed =
        list.any(descriptions, fn(description) {
          description.damage.killed == 1
        })
      #(
        [
          cast.Hit(
            unit_id:,
            unit: cast.HitPlayer,
            descriptions:,
            controls: [],
            armor_removed: 0,
          ),
        ],
        killed,
        killed,
      )
    }
    strike_tell.Immune(..) ->
      panic as "a player is never guarded: only a creature answers Immune"
    strike_tell.Deflected -> #([cast.Deflected(unit_id:)], False, False)
    strike_tell.Refused(why: strike_tell.Dead) -> #([], True, True)
    strike_tell.Refused(why: strike_tell.Returning) -> #([], True, False)
  }
}

/// The round closes: its go (0x7f4) names the units struck, the 0x7fb any deflect,
/// and the cast finishes (0x7fe).
fn round_closed(
  state state: State,
  round round: Round,
  struck struck: List(cast.Struck),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Fighting(..) as fighting = state.status
    as "a round closes only while Fighting"
  let here = creature_path.place_at(path: state.path, now_ms:)
  let cast_id = round.cast_id
  let missed = case cast.creature_missed(cast_id:, struck:) {
    Some(missed) -> [ToViewers(client_connection.CastMissed(missed:))]
    None -> []
  }
  #(
    State(..state, status: Fighting(..fighting, round: None)),
    list.flatten([
      [
        ToViewers(
          client_connection.CastWent(go: cast.creature_went(
            cast_id:,
            place: here,
            struck:,
          )),
        ),
      ],
      missed,
      [ToViewers(client_connection.CastFinished(cast_id:))],
    ]),
  )
}

/// The creature opens its charge on its target: round `Charging` with a `CastEnds`
/// generation, the 0x7ff of the attack spell to the viewers, and `StartTimer(CastEnds,
/// cast_ms)`. The attack tick's generation moves to one no timer carries, so the tick that
/// opened the charge, or a later copy of it, does nothing, and no attack tick starts: the
/// round's close starts it.
fn charges(
  state state: State,
  fighter fighter: Fighter,
  sighting sighting: Sighting,
  here here: Place,
  cast_ms cast_ms: Int,
  area area: Row,
  inside inside: Inside,
) -> #(State, List(Effect)) {
  let cast_id =
    cast.mint(
      unit_id: fighter.unit_id,
      number: state.next_cast,
      live: fighter.guard_casts,
    )
  let #(state, ends) = generation(state)
  let #(state, tick) = generation(state)
  let assert Fighting(..) as fighting = state.status
    as "a creature charges only while Fighting"
  let round = Round(cast_id:, stage: Charging(ends:, area:, inside:))
  #(
    State(
      ..state,
      next_cast: cast.number_of(cast_id:) + 1,
      status: Fighting(..fighting, round: Some(round), tick:),
    ),
    [
      ToViewers(
        client_connection.CastStarted(start: cast.creature_started(
          cast_id:,
          spell4_id: fighter.attack.spell4_id.value,
          caster_unit_id: fighter.unit_id,
          target_unit_id: sighting.unit_id,
          place: here,
        )),
      ),
      StartTimer(timer: CastEnds(ends), after_ms: cast_ms),
    ],
  )
}

/// The charge's cast time is up: each fighter on the threat list inside the rectangle
/// (`game/spell_area`, `game/area` select) gets a strike and the round becomes `Striking`
/// with the deadline; with none inside, the go names no unit, the cast finishes and the next
/// attack tick starts. The rectangle points along the bearing from the creature to its target
/// now, as the client's turret aims at the unit its 0x908 names, or along the creature's own
/// facing when the target has no sighting. No state is held then: one that took hold during the
/// charge broke it (`held`), and its `CastEnds` is stale.
fn charge_ended(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  area row: Row,
  inside inside: Inside,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Fighting(threat:, target:, ..) = state.status
    as "a charge ends only while Fighting"
  let here = creature_path.place_at(path: state.path, now_ms:)
  let aim = aim_of(state:, target:, here:)
  let struck =
    inside_rectangle(
      state:,
      row:,
      inside:,
      aim:,
      fighters: map.sorted_by_connection(threat),
    )
  case struck {
    [] -> {
      let #(state, closed) = round_closed(state:, round:, struck: [], now_ms:)
      let #(state, ticking) = ticking_again(state:, fighter:)
      #(state, list.append(closed, ticking))
    }
    [_, ..] -> {
      let #(state, deadline) = generation(state)
      let keyed =
        list.map(struck, fn(found) {
          let #(connection, threat, sighting) = found
          #(
            connection,
            threat,
            strike_tell.Key(
              cast_id: round.cast_id,
              phase: 0,
              unit_id: sighting.unit_id,
            ),
          )
        })
      let stage =
        Striking(
          deadline:,
          awaiting: dict.from_list(
            list.map(keyed, fn(found) { #(found.2, found.0) }),
          ),
          struck: [],
        )
      #(
        with_round(state:, round: Round(..round, stage:)),
        list.append(
          list.map(keyed, fn(found) {
            ToPlayer(
              to: found.0,
              stay: { found.1 }.stay,
              told: Attacks(
                tell: strike_tell.Strike(
                  key: found.2,
                  from: fighter.address,
                  striker: CreatureStriker,
                  offence: fighter.attack.offence,
                  controls: [],
                ),
              ),
            )
          }),
          [
            StartTimer(
              timer: StrikeDeadline(deadline),
              after_ms: strike_tell.deadline_ms,
            ),
          ],
        ),
      )
    }
  }
}

/// Where the charge's rectangle points at its end: from the creature's place along the
/// bearing to the player of `target`, by its newest sighting (`area.bearing` with yaw 0 is
/// the yaw that faces the target, `movement_command.kind_14.facing`); the creature's own
/// facing when it has no sighting of it.
fn aim_of(
  state state: State,
  target target: ConnectionId,
  here here: Place,
) -> area.Pose {
  let body = area.pose_of(place: here)
  case dict.get(state.sightings, target) {
    Ok(sighting) ->
      area.Pose(
        ..body,
        yaw: area.bearing(
          from: body.at,
          target: area.point_of(place: sighting.place),
          yaw: 0.0,
        ),
      )
    Error(Nil) -> body
  }
}

/// The fighters of the threat list, by their newest sightings, that the attack's area
/// selects around the creature's place facing `aim`: nearest first, at most the area row's
/// target count.
fn inside_rectangle(
  state state: State,
  row row: Row,
  inside inside: Inside,
  aim aim: area.Pose,
  fighters fighters: List(#(ConnectionId, Threat)),
) -> List(#(ConnectionId, Threat, Sighting)) {
  let seen =
    list.filter_map(fighters, fn(entry) {
      dict.get(state.sightings, entry.0)
      |> result.map(fn(sighting) { #(entry.0, entry.1, sighting) })
    })
  area.select(
    candidates: list.map(seen, fn(found) {
      area.Candidate(
        unit_id: { found.2 }.unit_id,
        at: area.point_of(place: { found.2 }.place),
        hit_radius: { found.2 }.hit_radius,
      )
    }),
    centre: aim,
    row:,
    inside:,
  )
  |> list.filter_map(fn(unit_id) {
    list.find(seen, fn(found) { { found.2 }.unit_id == unit_id })
  })
}

/// A charging creature starts its next attack tick when its round closes and it still
/// fights; the attack tick of an attack with no cast time runs through its round, and a
/// creature that left the fight has none.
fn ticking_again(
  state state: State,
  fighter fighter: Fighter,
) -> #(State, List(Effect)) {
  case state.status, fighter.attack.cast {
    Fighting(..), Charged(..) -> next_tick(state:, fighter:, effects: [])
    Fighting(..), Instant | Resting, _ | Returning(..), _ -> #(state, [])
  }
}

/// The round ends before its go: a strike round closes as its deadline closes it, with
/// what was struck so far; a charge only cancels its `CastEnds` and finishes the cast
/// (0x7fe), with no go, since nothing went.
fn round_ended(
  state state: State,
  round round: Round,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case round.stage {
    Striking(struck:, ..) -> {
      let #(state, closed) = round_closed(state:, round:, struck:, now_ms:)
      #(state, [cancel_of(round:), ..closed])
    }
    Charging(..) -> {
      let assert Fighting(..) as fighting = state.status
        as "a round ends only while Fighting"
      #(State(..state, status: Fighting(..fighting, round: None)), [
        cancel_of(round:),
        ToViewers(client_connection.CastFinished(cast_id: round.cast_id)),
      ])
    }
  }
}

/// The timer that ends the round, to cancel when the round ends first.
fn cancel_of(round round: Round) -> Effect {
  case round.stage {
    Striking(deadline:, ..) -> CancelTimer(timer: StrikeDeadline(deadline))
    Charging(ends:, ..) -> CancelTimer(timer: CastEnds(ends))
  }
}

/// The creature runs toward its target when the target is beyond reach of where its
/// path ends: a new path from where it is, stopping short of the target and clipped
/// at the leash circle, sent as 0x638. A creature whose states stop its run starts no path,
/// and one that cannot move never does.
fn chase(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: fighter.still || cannot_move(fighter:),
    return: #(state, []),
  )
  let target_place = case state.status {
    Fighting(target:, ..) ->
      dict.get(state.sightings, target)
      |> result.map(fn(sighting) { sighting.place })
    Resting | Returning(..) -> Error(Nil)
  }
  case target_place {
    Error(Nil) -> #(state, [])
    Ok(target_place) -> chase_to(state:, fighter:, target_place:, now_ms:)
  }
}

/// The chase toward the target's place, unless it is in reach of where the path
/// ends.
fn chase_to(
  state state: State,
  fighter fighter: Fighter,
  target_place target_place: Place,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: creature_path.distance(
      from: creature_path.end(path: state.path),
      to: target_place,
    )
      <=. fighter.attack.reach,
    return: #(state, []),
  )
  let path =
    creature_path.toward(
      from: creature_path.place_at(path: state.path, now_ms:),
      target: target_place,
      stop_short: fighter.numbers.chase_stop_fraction *. fighter.attack.reach,
      circle: Circle(centre: fighter.home, radius: fighter.numbers.leash_range),
      speed: fighter.attack.run_speed,
      now_ms:,
    )
  #(State(..state, path:), path_news(was: state.path, now: path, now_ms:))
}

/// What the viewers are told of the creature's new path: a running path as 0x638 of
/// kind 4, and a standing one as 0x638 of kind 2 only when the path they were last
/// sent is still being run, since a client left running it would run on from a
/// creature that stands. A creature that has stood since its path ended says nothing.
fn path_news(was was: Path, now now: Path, now_ms now_ms: Int) -> List(Effect) {
  case now, was {
    Running(..), _ -> [ToViewers(client_connection.CreatureMoved(path: now))]
    Standing(at:), Running(..) ->
      case creature_path.arrives_ms(path: was, now_ms:) > now_ms {
        True -> [
          ToViewers(client_connection.CreaturePlaced(place: at, at_ms: now_ms)),
        ]
        False -> []
      }
    Standing(..), Standing(..) -> []
  }
}

/// The leash: every threat entry erased (0x90a 0), out of combat (0x89a 0), full
/// health (0x937), the path home (0x638), each threatened player told `Released`,
/// an open round closed, and the home timer started. The creature takes no strike
/// until it is home. A creature whose states stop its run leashes in everything but the walk
/// and its timer, which `ControlEnded` starts. A creature that cannot move has no walk:
/// it rests where it stands.
fn leash(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(entries, round) = case state.status {
    Fighting(threat:, round:, ..) -> #(map.sorted_by_connection(threat), round)
    Resting | Returning(..) -> #([], None)
  }
  let #(state, closed) = case round {
    Some(round) -> round_ended(state:, round:, now_ms:)
    None -> #(state, [])
  }
  let #(state, walked) = case cannot_move(fighter:) {
    True -> #(State(..state, status: Resting), [])
    False -> {
      let #(state, home) = generation(state)
      let state = State(..state, status: Returning(home:))
      case fighter.still {
        True -> #(state, [])
        False -> walk_home(state:, fighter:, home:, now_ms:)
      }
    }
  }
  #(
    state,
    list.flatten([
      closed,
      list.map(entries, fn(entry) {
        ToViewers(client_connection.Threat(
          other_unit_id: { entry.1 }.unit_id,
          threat: 0,
        ))
      }),
      [
        ToViewers(client_connection.CombatState(in_combat: False)),
        RestoreHealth,
      ],
      walked,
      list.map(entries, fn(entry) {
        ToPlayer(
          to: entry.0,
          stay: { entry.1 }.stay,
          told: Released(unit_id: fighter.unit_id),
        )
      }),
    ]),
  )
}

/// The path home from where the creature stands, sent as 0x638 (or placed, when the path
/// it ran ends in standing), with the home timer of generation `home` for its arrival.
/// The leash starts it, or `ControlEnded` does when a state held the creature at the
/// leash.
fn walk_home(
  state state: State,
  fighter fighter: Fighter,
  home home: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let here = creature_path.place_at(path: state.path, now_ms:)
  let path =
    creature_path.straight(
      from: here,
      to: fighter.home,
      speed: fighter.attack.run_speed,
      now_ms:,
    )
  #(
    State(..state, path:),
    list.append(path_news(was: state.path, now: path, now_ms:), [
      StartTimer(
        timer: HomeArrival(home),
        after_ms: creature_path.arrives_ms(path:, now_ms:) - now_ms,
      ),
    ]),
  )
}

/// The creature stands where it is: the path it runs stops, and its viewers are placed
/// there when they still run it (0x638 of kind 2). A death does it, and so does a state
/// that takes hold.
fn stand_still(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let here = creature_path.place_at(path: state.path, now_ms:)
  let placed = path_news(was: state.path, now: Standing(at: here), now_ms:)
  #(State(..state, path: Standing(at: here)), placed)
}

/// A crowd-control state takes hold: the creature stands where it is when its states stop
/// its run (`Fighter.still`), and runs on under the others. An open charge is
/// broken whatever the state: `CancelTimer(CastEnds)`, 0x7f9 of result 11 and 0x7fe of its cast, the round closed
/// and the next attack tick started, then `ChargeInterrupted` with the charge's cast id for the guard. A charge already
/// gone (the go is out, round `Striking`) is not broken, and a second state of the same round finds
/// none.
fn held(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, placed) = case fighter.still {
    True -> stand_still(state:, now_ms:)
    False -> #(state, [])
  }
  case state.status {
    Fighting(round: Some(Round(cast_id:, stage: Charging(ends:, ..))), ..) as fighting -> {
      let #(state, ticked) =
        next_tick(
          state: State(..state, status: Fighting(..fighting, round: None)),
          fighter:,
          effects: [],
        )
      #(
        state,
        list.flatten([
          placed,
          [
            CancelTimer(timer: CastEnds(ends)),
            ToViewers(client_connection.CastInterrupted(cast_id:)),
          ],
          ticked,
          [ChargeInterrupted(cast_id:)],
        ]),
      )
    }
    Fighting(..) | Resting | Returning(..) -> #(state, placed)
  }
}

/// The creature died: its path frozen where it fell and its viewers placed there
/// when they still run it, out of combat (0x89a 0), each threatened player told
/// `Released`, and an open round's cast finished.
fn killed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, placed) = stand_still(state:, now_ms:)
  case state.status {
    Fighting(threat:, round:, ..) -> {
      let finished = case round {
        Some(round) -> [
          cancel_of(round:),
          ToViewers(client_connection.CastFinished(cast_id: round.cast_id)),
        ]
        None -> []
      }
      #(
        State(..state, status: Resting),
        list.flatten([
          placed,
          finished,
          [ToViewers(client_connection.CombatState(in_combat: False))],
          list.map(map.sorted_by_connection(threat), fn(entry) {
            ToPlayer(
              to: entry.0,
              stay: { entry.1 }.stay,
              told: Released(unit_id: fighter.unit_id),
            )
          }),
        ]),
      )
    }
    Resting | Returning(..) -> #(State(..state, status: Resting), placed)
  }
}

/// The last state that stopped its run ended: a Fighting creature chases its target again from where it
/// stands (its attack tick went on), and a Returning one that stands away from home
/// starts the walk its leash could not, with its home timer.
fn resumed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(..) -> chase(state:, fighter:, now_ms:)
    Returning(home:) -> walk_home(state:, fighter:, home:, now_ms:)
    Resting -> #(state, [])
  }
}

/// The creature's run speed changed: a path still being run at another speed is
/// run on from where the creature stands, to the same end, at the new speed, and sent
/// as 0x638. A walk home gets a new home timer for the new arrival, and its old one is
/// cancelled. A creature that stands, or whose path is run, has nothing to replan.
fn speed_changed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let still_run = creature_path.arrives_ms(path: state.path, now_ms:) > now_ms
  case state.path {
    Running(speed:, ..) as was
      if still_run && speed != fighter.attack.run_speed
    -> {
      let path =
        creature_path.straight(
          from: creature_path.place_at(path: was, now_ms:),
          to: creature_path.end(path: was),
          speed: fighter.attack.run_speed,
          now_ms:,
        )
      let state = State(..state, path:)
      let moved = path_news(was:, now: path, now_ms:)
      case state.status {
        Returning(home: old) -> {
          let #(state, home) = generation(state)
          #(
            State(..state, status: Returning(home:)),
            list.flatten([
              [CancelTimer(timer: HomeArrival(old))],
              moved,
              [
                StartTimer(
                  timer: HomeArrival(home),
                  after_ms: creature_path.arrives_ms(path:, now_ms:) - now_ms,
                ),
              ],
            ]),
          )
        }
        Fighting(..) | Resting -> #(state, moved)
      }
    }
    Running(..) | Standing(..) -> #(state, [])
  }
}

fn generation(state: State) -> #(State, Int) {
  #(
    State(..state, next_generation: state.next_generation + 1),
    state.next_generation,
  )
}

/// A threat as the client's 32-bit field holds it: rounded half away from zero.
fn whole(threat: Float) -> Int {
  float.round(threat)
}
