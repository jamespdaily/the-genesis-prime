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
////   (`death.combat_flag`); the respawn aggroes the players in its ring. Whether the
////   creature stands or lies dead is creature_life's alone: the fight leaves at the
////   kill, and the creature's place, kept apart from the fight's status, stays where
////   it fell.
//// - **A leash restores the health**: the fight asks the creature's rule
////   (`RestoreHealth`), which sets creature_life's health to full and sends the 0x937.
//// - **Every timer carries a generation**: a tick of a fight that ended, a deadline
////   of a round that closed or a home timer of an earlier walk does nothing when it
////   fires, though it waited in the mailbox when it was cancelled.
//// - **A player at 0** answers `Landed` with the killed bit; the creature releases it.
////
//// What happens at each deadline and process death:
////
//// | Point | What happens | Test |
//// |---|---|---|
//// | P's answer comes after the strike deadline | the go leaves P out; the hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | P's connection ends, camps or P goes out of sight | the map's `Unwatched` drops P from threat; with no threat left the creature leashes | `a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test` |
//// | a strike or `TargetMoved` from a connection that is not a viewer (a race with `Unwatched`) | the damage applies, no threat is added | `a_strike_from_a_non_viewer_adds_no_threat_test` |
//// | P and C strike each other at one instant | both are tells; each side answers in its own step, before the other's deadline | `a_bot_pressing_as_the_dagun_strikes_it_gets_both_strikes_answered_test` |
//// | C crashes mid-fight | the map sends every player `Gone`; P drops C, and sends 0x89a (P, 0) when no fighter is left (genesis_prime/game/player_life) | `a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test` |
//// | C is told `Retire` while Returning | it stops; the map's sweep sends it only with no viewer, so no one is on its threat list | `over_random_sights_rings_strikes_and_ticks_the_threat_list_stays_within_the_viewers_test` |
//// | a timer of a round that closed, or of a fight that ended, fires | it is of an old generation and does nothing | `a_deadline_timer_already_fired_for_a_closed_round_does_nothing_test` |
//// | C dies while it runs | it rests where it fell, and a viewer that arrives before its respawn is shown it there | `a_viewer_arriving_between_a_running_creatures_death_and_its_respawn_sees_it_where_it_fell_test` |
//// | the home timer fires | C stands at its spawn, Resting, at full health, and aggroes the near players it sees | `at_home_the_creature_aggroes_the_near_players_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/cast
import genesis_prime/game/hit.{type Offence}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight as Told, type Key, Attacks, CreatureStriker,
  Released, Threatened,
}
import genesis_prime/step.{type Address, type ConnectionId}
import genesis_prime/world_map/creature_life.{type Attack}
import genesis_prime/world_map/creature_path.{
  type Path, Circle, Running, Standing,
}
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
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

/// One entry of the threat list: the player's unit and its threat.
pub type Threat {
  Threat(unit_id: Int, amount: Float)
}

/// The strike round the creature waits on: its key, the player struck, and the
/// generation of its deadline timer.
pub type Round {
  Round(key: Key, target: ConnectionId, deadline: Int)
}

/// The newest place the creature knows a connection's player at, with the move
/// sequence number it came with.
pub type Sighting {
  Sighting(unit_id: Int, place: Place, seq: Int)
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
  /// The map: the player of `by` entered the creature's ring, at `place` of move
  /// `seq`.
  Approached(by: ConnectionId, unit_id: Int, place: Place, seq: Int)
  /// The map: the player of `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The player of `by`, on the threat list, moved to `place` of move `seq`.
  TargetMoved(by: ConnectionId, place: Place, seq: Int)
  /// A player's strike landed on the creature for `threat`
  /// (`threat_of`), from `place` of move `seq`.
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
}

/// What the fight asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer.
  ToViewers(news: News)
  /// A tell to the connection of a player in the fight.
  ToPlayer(to: ConnectionId, told: Told)
  /// The creature stands at full health again: creature_life's health is restored
  /// and each viewer is sent its 0x937.
  RestoreHealth
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
/// creature's viewers now, `alive` whether creature_life holds it standing, and
/// `now_ms` the monotonic time of the input.
pub fn step(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Set(ConnectionId),
  alive alive: Bool,
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case input {
    Approached(by:, unit_id:, place:, seq:) -> {
      let state =
        State(
          ..sighted(state:, by:, unit_id:, place:, seq:),
          near: set.insert(state.near, by),
        )
      case state.status, alive && set.contains(viewers, by) {
        Resting, True -> aggro(state:, fighter:, players: [by], now_ms:)
        Resting, False | Fighting(..), _ | Returning(..), _ -> #(state, [])
      }
    }
    Withdrew(by:) -> #(State(..state, near: set.delete(state.near, by)), [])
    TargetMoved(by:, place:, seq:) -> {
      let state =
        sighted(state:, by:, unit_id: unit_of(state:, by:), place:, seq:)
      case state.status, alive {
        Fighting(target:, ..), True if target == by ->
          chase(state:, fighter:, now_ms:)
        Fighting(..), _ | Resting, _ | Returning(..), _ -> #(state, [])
      }
    }
    StruckBy(by:, unit_id:, place:, seq:, threat:) -> {
      let state = sighted(state:, by:, unit_id:, place:, seq:)
      case alive && set.contains(viewers, by) {
        False -> #(state, [])
        True -> threatened_by(state:, fighter:, by:, threat:, now_ms:)
      }
    }
    Unwatched(by:) -> unwatched(state:, fighter:, by:, now_ms:)
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
        Fighting(round: Some(round), ..) if round.deadline == generation ->
          round_closed(state:, round:, struck: [], now_ms:)
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
            players: near_viewers(state:, viewers:),
            now_ms:,
          )
        }
        Returning(..) | Resting | Fighting(..) -> #(state, [])
      }
    Killed -> killed(state:, fighter:, now_ms:)
    StoodAgain -> {
      let state =
        State(..state, status: Resting, path: Standing(at: fighter.home))
      aggro(state:, fighter:, players: near_viewers(state:, viewers:), now_ms:)
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
/// combat flag (0x89a), the target (0x908) and each other entry (0x90a); and on a
/// path not yet run, the rest of it from where the creature is now (0x638).
pub fn arrival_news(state state: State, now_ms now_ms: Int) -> List(News) {
  let fight = case state.status {
    Fighting(threat:, target:, ..) -> {
      let others =
        sorted_entries(threat)
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
  list.append(fight, path)
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

/// The state with the player's newest place: a move of a lower sequence number
/// than the one held is older and dropped; an equal one is the same move.
fn sighted(
  state state: State,
  by by: ConnectionId,
  unit_id unit_id: Int,
  place place: Place,
  seq seq: Int,
) -> State {
  case dict.get(state.sightings, by) {
    Ok(held) if held.seq > seq -> state
    Ok(..) | Error(Nil) ->
      State(
        ..state,
        sightings: dict.insert(
          state.sightings,
          by,
          Sighting(unit_id:, place:, seq:),
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
  viewers viewers: Set(ConnectionId),
) -> List(ConnectionId) {
  map.sorted_connections(set.intersection(state.near, viewers))
}

/// A resting creature aggroes these players, each with the aggro threat
/// (`start_fight`). No player it has a place for, no fight.
fn aggro(
  state state: State,
  fighter fighter: Fighter,
  players players: List(ConnectionId),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let entries =
    list.filter_map(players, fn(player) {
      dict.get(state.sightings, player)
      |> result.map(fn(sighting) {
        #(
          player,
          Threat(
            unit_id: sighting.unit_id,
            amount: fighter.numbers.aggro_threat,
          ),
        )
      })
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
          ToPlayer(to: entry.0, told: threatened_told(fighter:))
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

/// A viewer's strike adds its threat: a resting creature starts a fight with it; a
/// fighting one adds to its entry, naming a new top entry as its target (0x908), and
/// any other entry's new threat in 0x90a.
fn threatened_by(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  threat threat: Float,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Returning(..) -> #(state, [])
    Resting ->
      start_fight(
        state:,
        fighter:,
        entries: [#(by, Threat(unit_id: unit_of(state:, by:), amount: threat))],
        now_ms:,
      )
    Fighting(threat: entries, target:, ..) as fighting -> {
      let unit_id = unit_of(state:, by:)
      let is_new = !dict.has_key(entries, by)
      let entries =
        dict.upsert(entries, by, fn(found) {
          case found {
            Some(entry) -> Threat(..entry, amount: entry.amount +. threat)
            None -> Threat(unit_id:, amount: threat)
          }
        })
      let #(top, top_entry) = top_of(entries)
      let state =
        State(
          ..state,
          status: Fighting(..fighting, threat: entries, target: top),
        )
      let told = case is_new {
        True -> [ToPlayer(to: by, told: threatened_told(fighter:))]
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

/// A viewer that no longer sees the creature leaves the near players and the threat
/// list, and is told `Released`; the last one leashes the creature, and a new top
/// entry is named its target.
fn unwatched(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let state = State(..state, near: set.delete(state.near, by))
  case state.status {
    Fighting(threat: entries, ..) ->
      case dict.has_key(entries, by) {
        False -> #(state, [])
        True -> released(state:, fighter:, by:, now_ms:)
      }
    Resting | Returning(..) -> #(state, [])
  }
}

/// The player of `by` leaves the threat list and is told `Released`; with no one
/// left the creature leashes, else its entry is erased (0x90a 0) and a new top
/// entry is named its target (0x908).
fn released(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(threat: entries, ..) -> {
      let erased = case dict.get(entries, by) {
        Ok(entry) -> [ToViewers(threat_news(Threat(..entry, amount: 0.0)))]
        Error(Nil) -> []
      }
      let entries = dict.delete(entries, by)
      let told = ToPlayer(to: by, told: Released(unit_id: fighter.unit_id))
      case dict.is_empty(entries) {
        True -> {
          let #(state, effects) = leash(state:, fighter:, now_ms:)
          #(state, list.append(effects, [told]))
        }
        False -> {
          let #(state, named, chased) =
            retargeted(state:, fighter:, entries:, now_ms:)
          #(state, list.flatten([erased, named, [told], chased]))
        }
      }
    }
    Resting | Returning(..) -> #(state, [])
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
/// strikes; out of reach at the leash circle it leashes; else it chases. The next
/// tick starts unless it leashed.
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
      let at_circle =
        creature_path.distance(from: here, to: fighter.home)
        >=. fighter.numbers.leash_range -. circle_tolerance
      case in_reach, round, at_circle {
        True, None, _ -> {
          let #(state, struck) =
            strikes(state:, fighter:, target:, sighting:, here:)
          next_tick(state:, fighter:, effects: struck)
        }
        True, Some(..), _ -> next_tick(state:, fighter:, effects: [])
        False, _, True -> leash(state:, fighter:, now_ms:)
        False, _, False -> {
          let #(state, chased) = chase(state:, fighter:, now_ms:)
          next_tick(state:, fighter:, effects: chased)
        }
      }
    }
  }
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
  let cast_id = cast.cast_id(unit_id: fighter.unit_id, number: state.next_cast)
  let key = strike_tell.Key(cast_id:, phase: 0, unit_id: sighting.unit_id)
  let #(state, deadline) = generation(state)
  let assert Fighting(..) as fighting = state.status
    as "a creature strikes only while Fighting"
  #(
    State(
      ..state,
      next_cast: state.next_cast + 1,
      status: Fighting(..fighting, round: Some(Round(key:, target:, deadline:))),
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
        told: Attacks(tell: strike_tell.Strike(
          key:,
          from: fighter.address,
          striker: CreatureStriker,
          offence: fighter.attack.offence,
        )),
      ),
      StartTimer(
        timer: StrikeDeadline(deadline),
        after_ms: strike_tell.deadline_ms,
      ),
    ],
  )
}

/// The target's answer to the open round: its go names what landed, and a target
/// the strike killed, or found dead, is released.
fn answered_strike(
  state state: State,
  fighter fighter: Fighter,
  answered answered: Answered,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(round: Some(round), ..) if round.key == answered.key -> {
      let unit_id = answered.key.unit_id
      let #(struck, ends_target) = case answered.outcome {
        strike_tell.Landed(descriptions:) -> #(
          [cast.Hit(unit_id:, descriptions:)],
          list.any(descriptions, fn(description) {
            description.damage.killed == 1
          }),
        )
        strike_tell.Deflected -> #([cast.Deflected(unit_id:)], False)
        strike_tell.Refused(..) -> #([], True)
      }
      let #(state, closed) = round_closed(state:, round:, struck:, now_ms:)
      let cancel = CancelTimer(timer: StrikeDeadline(round.deadline))
      case ends_target {
        False -> #(state, [cancel, ..closed])
        True -> {
          let #(state, released) =
            released(state:, fighter:, by: round.target, now_ms:)
          #(state, list.flatten([[cancel], closed, released]))
        }
      }
    }
    Fighting(..) | Resting | Returning(..) -> #(state, [])
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
  let cast_id = round.key.cast_id
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

/// The creature runs toward its target when the target is beyond reach of where its
/// path ends: a new path from where it is, stopping short of the target and clipped
/// at the leash circle, sent as 0x638.
fn chase(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
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
  case path {
    Running(..) -> #(State(..state, path:), [
      ToViewers(client_connection.CreatureMoved(path:)),
    ])
    Standing(..) -> #(State(..state, path:), [])
  }
}

/// The leash: every threat entry erased (0x90a 0), out of combat (0x89a 0), full
/// health (0x937), the path home (0x638), each threatened player told `Released`,
/// an open round closed, and the home timer started. The creature takes no strike
/// until it is home.
fn leash(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(entries, round) = case state.status {
    Fighting(threat:, round:, ..) -> #(sorted_entries(threat), round)
    Resting | Returning(..) -> #([], None)
  }
  let #(state, closed) = case round {
    Some(round) -> {
      let #(state, closed) = round_closed(state:, round:, struck: [], now_ms:)
      #(state, [CancelTimer(timer: StrikeDeadline(round.deadline)), ..closed])
    }
    None -> #(state, [])
  }
  let here = creature_path.place_at(path: state.path, now_ms:)
  let path =
    creature_path.straight(
      from: here,
      to: fighter.home,
      speed: fighter.attack.run_speed,
      now_ms:,
    )
  let #(state, home) = generation(state)
  let moved = case path {
    Running(..) -> [ToViewers(client_connection.CreatureMoved(path:))]
    Standing(..) -> []
  }
  #(
    State(..state, status: Returning(home:), path:),
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
      moved,
      list.map(entries, fn(entry) {
        ToPlayer(to: entry.0, told: Released(unit_id: fighter.unit_id))
      }),
      [
        StartTimer(
          timer: HomeArrival(home),
          after_ms: creature_path.arrives_ms(path:, now_ms:) - now_ms,
        ),
      ],
    ]),
  )
}

/// The creature died: out of combat (0x89a 0), each threatened player told
/// `Released`, an open round's cast finished, and its path frozen where it fell.
fn killed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let here = creature_path.place_at(path: state.path, now_ms:)
  let state = State(..state, path: Standing(at: here))
  case state.status {
    Fighting(threat:, round:, ..) -> {
      let finished = case round {
        Some(round) -> [
          CancelTimer(timer: StrikeDeadline(round.deadline)),
          ToViewers(client_connection.CastFinished(cast_id: round.key.cast_id)),
        ]
        None -> []
      }
      #(
        State(..state, status: Resting),
        list.flatten([
          finished,
          [ToViewers(client_connection.CombatState(in_combat: False))],
          list.map(sorted_entries(threat), fn(entry) {
            ToPlayer(to: entry.0, told: Released(unit_id: fighter.unit_id))
          }),
        ]),
      )
    }
    Resting | Returning(..) -> #(State(..state, status: Resting), [])
  }
}

fn sorted_entries(
  threat: Dict(ConnectionId, Threat),
) -> List(#(ConnectionId, Threat)) {
  dict.to_list(threat)
  |> list.sort(fn(first, second) {
    map.compare_connections(first: first.0, second: second.0)
  })
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
