//// A creature's fight (`genesis_prime/world_map/creature_fight`), run through the
//// creature's own rule (`genesis_prime/world_map/creature`) as the pure rule it is:
//// its messages and timers in, its sends out. Expected values come from these
//// places.
//// - The design of step F (the Design artifact of issue 367, section 1, and its
////   shape review): aggro from a viewer's `Approached` while resting; threat from a
////   strike, damage times the effect's threatMultiplier; the top entry is the
////   target; the chase stops `chase_stop_fraction` x reach short of the target and
////   is clipped at the leash circle; the attack tick; the leash and the walk home;
////   the newest move sequence number per connection; timers of an old generation do
////   nothing; death frees the threat list and freezes where the creature stands.
//// - The messages: 0x908 names the target and its threat (`opcode.0x908`), 0x90a
////   another entry's threat, 0 erasing it (`opcode.0x90a`), 0x89a the combat flag
////   (`opcode.0x89a`), 0x638's kind 4 the path (`movement_command.kind_4`), and the
////   cast's 0x7ff, 0x7f4 and 0x7fe (`opcode.0x7ff`, `opcode.0x7f4`, `opcode.0x7fe`).
//// - The game numbers of migration 0010: aggro range 10, leash range 55, aggro
////   threat 1, chase stop fraction 0.5.
//// - The Virtual Battle Beast: 52 health (`Creature2.73464`), runLand 10.0
////   (`0x1405b45e0`), reach 5.0 + 3.0 (`Spell4.5649` and its hit radius), its attack
////   Spell4 5649 every 1500 ms (migration 0010), effect 184741 for 12
////   (`Spell4Effects.184741`).
//// - The threatMultiplier of Spell4Effects 125182 is 2.0 (the client's row).

import connection_rule_support as support
import genesis_prime/client_connection.{
  type News, CastFinished, CastStarted, CastWent, CombatState, CreatureAppeared,
  CreatureMoved, Health, PeerNews, Targeting, Threat,
}
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell.{
  Answered, Attacks, CreatureStriker, Key, Landed, PlayerStriker, Refused,
  Released, Strike, Threatened,
}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{SpellDamageDescription}
import genesis_prime/step.{
  type ConnectionId, type ServiceStep, Connection, ConnectionId, CreatureStart,
  OwnEffect, OwnEvent, ServiceTimerFired, StartServiceTimer, Started, Told,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature.{type State, Settings}
import genesis_prime/world_map/creature_fight
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_path.{Running}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import map_support
import owned_test
import place_support
import qcheck
import spawn_support

const ship = MapId(world_id: 3460, instance: 0)

/// The creature's unit and life: its address is Creature(ship, 1, 7, 3).
const unit = 7

const life = 3

/// The time every test starts at, on the monotonic clock.
const start_ms = 10_000

/// A Beast at x = 0 started for these viewers, its `Started` taken.
fn beast(viewers viewers: List(Int)) -> State {
  let state =
    creature.new(Settings(
      creature: CreatureStart(
        map: ship,
        incarnation: 1,
        unit_id: unit,
        life:,
        spawn_id: SpawnId(1),
        clock_origin_ms: 5000,
        viewers: list.map(viewers, fn(viewer) {
          #(ConnectionId(viewer), stay_of(viewer))
        }),
      ),
      spawn: spawn_support.battle_beast(number: 1, x: 0.0),
      kind: Kind(
        respawn_ms: 60_000,
        attack_spell4_id: Spell4Id(5649),
        attack_interval_ms: 1500,
      ),
      numbers: spawn_support.numbers,
    ))
  let #(state, _) =
    creature.step(
      state,
      support.input_at_ms(ms: start_ms, event: OwnEvent(Started)),
    )
  state
}

/// The creature's address, which its strikes come from.
fn address() -> step.Address {
  step.Creature(map: ship, incarnation: 1, unit_id: unit, life:)
}

fn at(x: Float) -> start_place.Place {
  place_support.at(world_id: 3460, world_zone_id: 5967, x:, y: 0.0, z: 0.0)
}

/// The unit of the player of connection `number`: ten times it.
fn unit_of(number: Int) -> Int {
  number * 10
}

/// The stay of the player of connection `number`, as the map names it: its
/// `number`th, so each player's is its own.
fn stay_of(number: Int) -> Stay {
  map_support.stay(count: number)
}

fn tell(
  state state: State,
  at_ms at_ms: Int,
  message message: creature.Message,
) -> #(State, ServiceStep(creature.Outgoing)) {
  creature.step(
    state,
    support.input_at_ms(ms: start_ms + at_ms, event: OwnEvent(Told(message))),
  )
}

fn fire(
  state state: State,
  at_ms at_ms: Int,
  timer timer: step.TimerId,
) -> #(State, ServiceStep(creature.Outgoing)) {
  creature.step(
    state,
    support.input_at_ms(
      ms: start_ms + at_ms,
      event: OwnEvent(ServiceTimerFired(timer:)),
    ),
  )
}

fn approached(
  number number: Int,
  x x: Float,
  seq seq: Int,
) -> creature.Message {
  creature.Approached(
    by: ConnectionId(number),
    unit_id: unit_of(number),
    place: at(x),
    seq:,
    stay: stay_of(number),
  )
}

fn moved(number number: Int, x x: Float, seq seq: Int) -> creature.Message {
  creature.TargetMoved(
    by: ConnectionId(number),
    place: at(x),
    seq:,
    stay: stay_of(number),
  )
}

/// A strike of the player of connection `number` at x = 2 with these blows (effect,
/// damage, threatMultiplier), with rolls that neither deflect nor crit.
fn strike_of(
  number number: Int,
  cast_id cast_id: Int,
  blows blows: List(#(Int, Int, Float)),
) -> creature.Message {
  creature.Strike(tell: Strike(
    key: Key(cast_id:, phase: 0, unit_id: unit),
    from: Connection(ConnectionId(number)),
    striker: PlayerStriker(
      unit_id: unit_of(number),
      place: at(2.0),
      seq: 1,
      stay: stay_of(number),
      rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
    ),
    offence: Offence(
      blows: list.map(blows, fn(blow) {
        Blow(
          spell4_effects_id: blow.0,
          damage_type: 3,
          damage: blow.1,
          delay_ms: 0,
          threat_multiplier: blow.2,
        )
      }),
      crit_chance: 0.0,
      crit_severity: 1.5,
      strikethrough: 0.0,
    ),
  ))
}

/// The tells of the step to players in the fight, by connection.
fn fights_told(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, strike_tell.Fight)) {
  list.map(fights_told_for(taken), fn(told) { #(told.0, told.2) })
}

/// The same, each with the stay it goes for.
fn fights_told_for(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, Stay, strike_tell.Fight)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.FightTold(stay:, told:) -> Ok(#(sent.0, stay, told))
      creature.News(..) | creature.Struck(..) -> Error(Nil)
    }
  })
}

/// Each send of the step in order, as one line: the news to a viewer, a fight's
/// tell or a strike's answer to a connection.
fn said(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.map(support.sends(taken), fn(sent) {
    let to = " to " <> int.to_string(sent.0)
    case sent.1 {
      creature.News(news: PeerNews(news:, ..), ..) -> name_of(news) <> to
      creature.FightTold(told: Threatened(unit_id:, life:), ..) ->
        "Threatened("
        <> int.to_string(unit_id)
        <> ", "
        <> int.to_string(life)
        <> ")"
        <> to
      creature.FightTold(told: Released(unit_id:), ..) ->
        "Released(" <> int.to_string(unit_id) <> ")" <> to
      creature.FightTold(told: Attacks(..), ..) -> "Attacks" <> to
      creature.Struck(answered: Answered(outcome: Landed(..), ..), ..) ->
        "Landed" <> to
      creature.Struck(answered: Answered(outcome: Refused(why:), ..), ..) ->
        case why {
          strike_tell.Dead -> "Refused(Dead)" <> to
          strike_tell.Returning -> "Refused(Returning)" <> to
        }
      creature.Struck(..) -> "Deflected" <> to
    }
  })
}

fn name_of(news: News) -> String {
  case news {
    Targeting(target_unit_id:, threat:) ->
      "0x908("
      <> int.to_string(target_unit_id)
      <> ", "
      <> int.to_string(threat)
      <> ")"
    Threat(other_unit_id:, threat:) ->
      "0x90a("
      <> int.to_string(other_unit_id)
      <> ", "
      <> int.to_string(threat)
      <> ")"
    CombatState(in_combat: True) -> "0x89a(1)"
    CombatState(in_combat: False) -> "0x89a(0)"
    CreatureMoved(..) -> "0x638"
    CastStarted(..) -> "0x7ff"
    CastWent(..) -> "0x7f4"
    client_connection.CastMissed(..) -> "0x7fb"
    CastFinished(..) -> "0x7fe"
    Health(health:, ..) -> "0x937(" <> int.to_string(health) <> ")"
    client_connection.Died -> "0x88c"
    CreatureAppeared(..) -> "0x262"
    client_connection.Removed -> "0x355"
    client_connection.Appeared(..)
    | client_connection.Moving(..)
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.Shield(..) -> "other"
  }
}

/// The news sent to viewer `number`, in order.
fn news_to(taken: ServiceStep(creature.Outgoing), number: Int) -> List(News) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent {
      #(to, creature.News(news: PeerNews(news:, ..), ..)) if to == number ->
        Ok(news)
      _ -> Error(Nil)
    }
  })
}

/// The timers the step starts, with their times.
fn timers(taken: ServiceStep(creature.Outgoing)) -> List(#(step.TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartServiceTimer(timer:, after_ms:)) -> Ok(#(timer, after_ms))
      OwnEffect(step.Send(..))
      | OwnEffect(step.Reply(..))
      | OwnEffect(step.StartCreature(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The one timer the step starts for `after_ms`.
fn timer_for(
  taken: ServiceStep(creature.Outgoing),
  after_ms: Int,
) -> step.TimerId {
  let assert [timer] =
    list.filter_map(timers(taken), fn(started) {
      case started.1 == after_ms {
        True -> Ok(started.0)
        False -> Error(Nil)
      }
    })
    as "the step starts one timer of that time"
  timer
}

/// The path of the step's 0x638 to a viewer.
fn path_sent(taken: ServiceStep(creature.Outgoing)) -> creature_path.Path {
  let assert [CreatureMoved(path:), ..] =
    list.filter(news_to(taken, 2), fn(news) { name_of(news) == "0x638" })
    as "the step sends a 0x638"
  path
}

fn x_of(place: start_place.Place) -> Float {
  start_place.x(place)
}

// Test 7: the newest move sequence number per connection.

pub fn a_move_with_a_lower_sequence_number_than_the_creature_holds_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 5),
    )
  let tick = timer_for(aggro, 1500)
  let #(state, older) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 40.0, seq: 4))
  assert said(older) == []
    as "move 4 is older than the move 5 the creature holds: dropped, no chase"
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: tick)
  assert list.contains(said(ticked), "0x7ff to 2")
    as "the tick finds the player where move 5 put it, 5 units off, within reach 8: it strikes"
}

pub fn a_target_moved_of_seq_n_plus_1_then_an_approached_of_seq_n_leaves_the_creature_at_n_plus_1s_place_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, early) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: moved(number: 2, x: 30.0, seq: 6),
    )
  assert said(early) == []
    as "a move from a player not on the list starts nothing"
  let #(_, aggro) =
    tell(state:, at_ms: 10, message: approached(number: 2, x: 5.0, seq: 5))
  let path = path_sent(aggro)
  assert x_of(creature_path.end(path:)) == 26.0
    as "the map's Approached of move 5 comes after the connection's move 6: the creature keeps move 6's place, 30, and runs to 30 - 0.5 x 8 = 26"
}

pub fn two_moves_of_one_client_frame_both_reach_the_creature_in_order_and_the_later_place_wins_test() -> Nil {
  use <- owned_test.run(5000)
  // The connection stamps two 0x637s of one frame, which share one client clock
  // (`opcode.0x637.client_clock`), with its own moves 6 and 7.
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 5),
    )
  let #(state, first) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 20.0, seq: 6))
  assert x_of(creature_path.end(path: path_sent(first))) == 16.0
  let #(_, second) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 40.0, seq: 7))
  assert x_of(creature_path.end(path: path_sent(second))) == 36.0
    as "move 7 is newer than move 6 though both carry one client clock: the creature runs on to 40 - 4"
}

// Test 8: aggro from a viewer.

pub fn a_viewer_entering_the_ring_is_targeted_the_creature_enters_combat_and_the_player_is_threatened_before_any_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  assert said(aggro)
    == [
      "0x908(20, 1) to 2", "0x908(20, 1) to 5", "0x89a(1) to 2", "0x89a(1) to 5",
      "Threatened(7, 3) to 2",
    ]
    as "0x908 (C, P, aggro threat 1) and 0x89a (C, 1) to every viewer, then Threatened to P, and no 0x7ff before the first tick"
  assert fights_told_for(aggro)
    == [#(2, stay_of(2), Threatened(unit_id: unit, life:))]
    as "the threat goes for the player's stay as the creature holds it, so the connection drops one of an earlier stay"
  assert list.map(timers(aggro), fn(timer) { timer.1 }) == [1500]
    as "the attack tick starts at the kind's interval"
}

pub fn a_player_that_is_not_a_viewer_is_not_aggroed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, nothing) =
    tell(
      state: beast(viewers: [5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  assert said(nothing) == [] && timers(nothing) == []
    as "threat only for viewers: the map's ring and its sight can cross with Unwatched"
}

// Test 9: threat from damage.

pub fn damage_adds_damage_times_each_effects_threat_multiplier_and_the_top_entry_is_the_target_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  // Effect 125182 (threatMultiplier 2.0) hits for 10 and effect 1 (1.0) for 5.
  let #(state, first) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [
        #(125_182, 10, 2.0),
        #(1, 5, 1.0),
      ]),
    )
  assert list.filter(said(first), fn(line) {
      line != "0x937(37) to 2" && line != "0x937(37) to 5"
    })
    == [
      "Landed to 5",
      "0x908(50, 25) to 2",
      "0x908(50, 25) to 5",
      "Threatened(7, 3) to 5",
    ]
    as "10 x 2.0 + 5 x 1.0 = 25 above the aggro threat 1: player 5 is the new target"
  let #(state, second) =
    tell(
      state:,
      at_ms: 200,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 30, 1.0)]),
    )
  assert list.contains(said(second), "0x908(20, 31) to 2")
    as "1 + 30 = 31 tops 25: the target is player 2 again"
  let #(_, third) =
    tell(
      state:,
      at_ms: 300,
      message: strike_of(number: 5, cast_id: 3, blows: [#(1, 2, 1.0)]),
    )
  assert list.contains(said(third), "0x90a(50, 27) to 2")
    && !list.any(said(third), fn(line) { line == "0x908(50, 27) to 2" })
    as "25 + 2 = 27 stays below 31: another entry's threat, 0x90a"
}

// Test 10: the chase.

pub fn a_target_out_of_reach_is_chased_at_run_speed_10_and_no_new_path_is_planned_while_it_stays_in_reach_of_the_paths_end_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let assert Running(from:, to:, started_ms:, speed:) = path_sent(aggro)
  assert x_of(from) == 0.0
    && x_of(to) == 26.0
    && speed == 10.0
    && started_ms == start_ms
    as "from the spawn to 30 - 0.5 x 8, at runLand 10.0 x MoveSpeedMultiplier 1.0"
  let #(state, near) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 31.0, seq: 2))
  assert said(near) == []
    as "31 is 5 from the path's end 26, within reach 8: no new path"
  let #(_, watched) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  let assert [CreatureAppeared(place:, ..), ..] = news_to(watched, 9)
  assert x_of(place) == 10.0
    as "a viewer arriving 1 s into the chase is sent the 0x262 where the creature runs: 10 units along"
}

// Test 11: the attack.

pub fn a_target_in_reach_is_struck_with_5649_every_1500_ms_and_the_answer_is_written_as_the_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == ["0x7ff to 2", "Attacks to 2"]
  let assert [CastStarted(start:)] = news_to(ticked, 2)
  assert start.spell4_id == 5649
    && start.caster_unit_id == 7
    && start.primary_target_unit_id == 20
    as "the kind's spell, cast by the creature on its target"
  let assert [#(2, Attacks(tell: Strike(key:, from:, striker:, offence:)))] =
    fights_told(ticked)
  assert from == address()
    && striker == CreatureStriker
    && key.cast_id == start.cast_id
    && key.unit_id == 20
    as "the strike answers to the creature and names the cast and the struck unit; the struck player rolls"
  assert list.map(offence.blows, fn(blow) {
      #(blow.spell4_effects_id, blow.damage)
    })
    == [#(184_741, 12)]
    as "effect 184741 for 12 (Spell4Effects.184741)"
  assert list.sort(list.map(timers(ticked), fn(timer) { timer.1 }), int.compare)
    == [1000, 1500]
    as "the strike's 1 s deadline and the next tick at 1500 ms"
  let description =
    SpellDamageDescription(
      raw_damage: 12,
      scaled_raw_damage: 12,
      absorbed: 7,
      shield_absorbed: 3,
      health_damage_with_overkill: 2,
      overkill: 0,
      glance: 0,
      killed: 0,
      combat_result: combat_result.Hit,
      damage_type: damage_type.Physical,
      hits: [],
    )
  let #(_, answered) =
    tell(
      state:,
      at_ms: 1600,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Landed(descriptions: [
          hit.Description(
            spell4_effects_id: 184_741,
            delay_ms: 0,
            damage: description,
          ),
        ]),
      )),
    )
  assert said(answered) == ["0x7f4 to 2", "0x7fe to 2"]
  let assert [CastWent(go:), CastFinished(..)] = news_to(answered, 2)
  let assert [target] = go.targets
  let assert [effect] = target.effects
  assert target.unit_id == 20 && effect.spell4_effects_id == 184_741
    as "the go names the player and effect 184741, with the description the player's hit made (raw 12)"
}

pub fn an_answer_after_the_deadline_is_left_out_of_the_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let deadline = timer_for(ticked, 1000)
  let assert [#(_, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
  let #(state, late) = fire(state:, at_ms: 2500, timer: deadline)
  assert said(late) == ["0x7f4 to 2", "0x7fe to 2"]
  let assert [CastWent(go:), CastFinished(..)] = news_to(late, 2)
  assert go.targets == [] as "no answer by the deadline: the go leaves P out"
  let #(_, answer) =
    tell(
      state:,
      at_ms: 2600,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Landed(descriptions: []),
      )),
    )
  assert said(answer) == [] as "the round is closed: the late answer is dropped"
}

pub fn a_deadline_timer_already_fired_for_a_closed_round_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let deadline = timer_for(ticked, 1000)
  let assert [#(_, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
  let #(state, _) =
    tell(
      state:,
      at_ms: 1600,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Landed(descriptions: []),
      )),
    )
  // The deadline's timer was cancelled with the answer, but had already fired and
  // waits in the mailbox.
  let #(_, stale) = fire(state:, at_ms: 2500, timer: deadline)
  assert said(stale) == [] && timers(stale) == []
    as "a timer of a round that closed is of an old generation: it does nothing"
}

// Test 12: the leash.

pub fn at_the_leash_circle_with_the_target_out_of_reach_the_creature_leashes_and_walks_home_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, chased) =
    tell(state:, at_ms: 0, message: moved(number: 2, x: 100.0, seq: 2))
  assert x_of(creature_path.end(path: path_sent(chased))) == 55.0
    as "the path to 96 is clipped at the leash circle, 55 from the spawn"
  // Ticks at 1.5, 3, 4.5 s chase on; the one at 6 s finds the creature at 55.
  let tick = timer_for(aggro, 1500)
  let #(state, t1) = fire(state:, at_ms: 1500, timer: tick)
  let #(state, t2) = fire(state:, at_ms: 3000, timer: timer_for(t1, 1500))
  let #(state, t3) = fire(state:, at_ms: 4500, timer: timer_for(t2, 1500))
  let #(state, leashed) = fire(state:, at_ms: 6000, timer: timer_for(t3, 1500))
  assert said(leashed)
    == [
      "0x90a(20, 0) to 2",
      "0x89a(0) to 2",
      "0x937(52) to 2",
      "0x638 to 2",
      "Released(7) to 2",
    ]
    as "0x90a 0 for each entry, 0x89a (C, 0), a full 0x937, the path home, and Released"
  assert fights_told_for(leashed) == [#(2, stay_of(2), Released(unit_id: unit))]
    as "the release goes for the player's stay"
  let assert Running(to:, ..) = path_sent(leashed)
  assert x_of(to) == 0.0 as "the path runs home"
  let #(_, refused) =
    tell(
      state:,
      at_ms: 6100,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 5, 1.0)]),
    )
  assert said(refused) == ["Refused(Returning) to 2"]
    as "walking home the creature takes no strike"
}

pub fn the_next_strike_after_a_leash_finds_the_creature_at_full_health_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, hurt) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 20, 1.0)]),
    )
  assert list.contains(said(hurt), "0x937(32) to 2") as "52 - 20"
  let #(state, _) =
    tell(state:, at_ms: 200, message: moved(number: 2, x: 100.0, seq: 2))
  let #(state, t1) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let #(state, t2) = fire(state:, at_ms: 3000, timer: timer_for(t1, 1500))
  let #(state, t3) = fire(state:, at_ms: 4500, timer: timer_for(t2, 1500))
  let #(state, leashed) = fire(state:, at_ms: 6000, timer: timer_for(t3, 1500))
  let home = timer_for(leashed, 5500)
  let #(state, _) = fire(state:, at_ms: 11_500, timer: home)
  let #(_, after) =
    tell(
      state:,
      at_ms: 12_000,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 10, 1.0)]),
    )
  assert list.contains(said(after), "0x937(42) to 2")
    as "the leash restored the health: 52 - 10 = 42, not 32 - 10"
}

pub fn at_home_the_creature_aggroes_the_near_players_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, _) =
    tell(state:, at_ms: 0, message: moved(number: 2, x: 100.0, seq: 2))
  // Player 2 runs out of the ring: the map says so.
  let #(state, _) =
    tell(state:, at_ms: 0, message: creature.Withdrew(by: ConnectionId(2)))
  let #(state, t1) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let #(state, t2) = fire(state:, at_ms: 3000, timer: timer_for(t1, 1500))
  let #(state, t3) = fire(state:, at_ms: 4500, timer: timer_for(t2, 1500))
  let #(state, leashed) = fire(state:, at_ms: 6000, timer: timer_for(t3, 1500))
  let #(state, returning) =
    tell(state:, at_ms: 7000, message: approached(number: 5, x: 3.0, seq: 1))
  assert said(returning) == []
    as "a player entering the ring while the creature walks home is only noted"
  let #(_, home) = fire(state:, at_ms: 11_500, timer: timer_for(leashed, 5500))
  assert list.contains(said(home), "0x908(50, 1) to 5")
    && list.contains(said(home), "Threatened(7, 3) to 5")
    as "home, at full health, it aggroes the player still in its ring (Jim's answer of 2026-11-04)"
}

// Test 13: Unwatched and death.

pub fn unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  let #(_, unwatched) =
    tell(state:, at_ms: 200, message: creature.Unwatched(by: ConnectionId(5)))
  assert said(unwatched)
    == [
      "0x355 to 5",
      "0x90a(50, 0) to 2",
      "0x908(20, 1) to 2",
      "Released(7) to 5",
    ]
    as "player 5 (threat 3, the target) leaves the list, its entry erased (0x90a 0); player 2 is the target again"
}

pub fn death_takes_the_creature_out_of_combat_and_releases_everyone_on_its_list_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  let #(_, killed) =
    tell(
      state:,
      at_ms: 200,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 60, 1.0)]),
    )
  assert said(killed)
    == [
      "Landed to 2", "0x937(0) to 2", "0x937(0) to 5", "0x88c to 2",
      "0x88c to 5", "0x89a(0) to 2", "0x89a(0) to 5", "Released(7) to 2",
      "Released(7) to 5",
    ]
    as "death.combat_flag: 0x89a (C, 0) and Released to everyone on the threat list"
}

pub fn a_viewer_arriving_between_a_running_creatures_death_and_its_respawn_sees_it_where_it_fell_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  let corpse = timer_for(killed, 60_000)
  let #(state, watched) =
    tell(
      state:,
      at_ms: 2000,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  let assert [CreatureAppeared(place:, ..)] = news_to(watched, 9)
  assert x_of(place) == 10.0
    as "it fell 1 s into its run, 10 units along: the corpse lies there, not where the run would end"
  let #(_, stood) = fire(state:, at_ms: 61_000, timer: corpse)
  let appeared =
    list.filter(news_to(stood, 9), fn(news) { name_of(news) == "0x262" })
    |> list.map(fn(news) {
      let assert CreatureAppeared(place:, ..) = news
        as "a 0x262 of the creature"
      x_of(place)
    })
  assert appeared == [0.0]
    as "it stands again at its spawn (death.creature_respawn)"
}

// Test 14: threat only for viewers.

type Op {
  See(Int)
  Unsee(Int)
  Near(Int)
  Hit(Int)
  Tick
  Wait
}

fn op_of(numbers: #(Int, Int)) -> Op {
  let player = numbers.1 % 3 + 2
  case numbers.0 % 6 {
    0 -> See(player)
    1 -> Unsee(player)
    2 -> Near(player)
    3 -> Hit(player)
    4 -> Tick
    _ -> Wait
  }
}

/// The breaches of `threat ⊆ viewers` over the operations, each tick firing every
/// timer the creature started, with `viewers` the rule's own view or one the test
/// plants.
fn breaches(
  ops ops: List(Op),
  viewers_of viewers_of: fn(State) -> set.Set(ConnectionId),
) -> List(String) {
  let #(_, _, _, found) =
    list.fold(ops, #(beast(viewers: []), [], 0, []), fn(held, op) {
      let #(state, pending, at_ms, found) = held
      let at_ms = at_ms + 100
      let #(state, taken_timers) = case op {
        See(n) -> {
          let #(state, taken) =
            tell(
              state:,
              at_ms:,
              message: creature.Watched(by: ConnectionId(n), stay: stay_of(n)),
            )
          #(state, timers(taken))
        }
        Unsee(n) -> {
          let #(state, taken) =
            tell(
              state:,
              at_ms:,
              message: creature.Unwatched(by: ConnectionId(n)),
            )
          #(state, timers(taken))
        }
        Near(n) -> {
          let #(state, taken) =
            tell(
              state:,
              at_ms:,
              message: approached(number: n, x: 4.0, seq: at_ms),
            )
          #(state, timers(taken))
        }
        Hit(n) -> {
          let #(state, taken) =
            tell(
              state:,
              at_ms:,
              message: strike_of(number: n, cast_id: at_ms, blows: [
                #(1, 1, 1.0),
              ]),
            )
          #(state, timers(taken))
        }
        Tick ->
          list.fold(
            pending,
            #(state, []),
            fn(so_far, timer: #(step.TimerId, Int)) {
              let #(state, started) = so_far
              let #(state, taken) = fire(state:, at_ms:, timer: timer.0)
              #(state, list.append(started, timers(taken)))
            },
          )
        Wait -> #(state, [])
      }
      let pending = case op {
        Tick -> taken_timers
        See(..) | Unsee(..) | Near(..) | Hit(..) | Wait ->
          list.append(pending, taken_timers)
      }
      let threat = creature_fight.threatened(state: creature.fight(state:))
      let found = case set.is_subset(threat, viewers_of(state)) {
        True -> found
        False -> [
          "at "
            <> int.to_string(at_ms)
            <> " ms the threat list holds a connection that is not a viewer",
          ..found
        ]
      }
      #(state, pending, at_ms, found)
    })
  found
}

pub fn over_random_sights_rings_strikes_and_ticks_the_threat_list_stays_within_the_viewers_test() -> Nil {
  use <- owned_test.run(60_000)
  use numbers <- qcheck.given(qcheck.generic_list(
    qcheck.tuple2(qcheck.bounded_int(0, 1000), qcheck.bounded_int(0, 1000)),
    qcheck.bounded_int(from: 1, to: 40),
  ))
  assert breaches(ops: list.map(numbers, op_of), viewers_of: fn(state) {
      creature.viewers(state:)
    })
    == []
    as "threat only for viewers, so the map's sweep, which retires a creature with no viewer, never retires a fighting one"
}

pub fn the_harness_names_a_threat_entry_that_is_not_a_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  // The planted bug: a view of the viewers that holds none.
  assert breaches(ops: [See(2), Near(2)], viewers_of: fn(_) { set.new() }) != []
}

pub fn a_strike_from_a_non_viewer_adds_no_threat_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 5's strike was on its way when the map's Unwatched of it arrived.
  let #(state, taken) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 1.0)]),
    )
  assert said(taken) == ["Landed to 5", "0x937(42) to 2"]
    as "the damage applies: 52 - 10, shown to the viewer"
  assert creature_fight.threatened(state: creature.fight(state:)) == set.new()
    as "no threat for a connection that does not see the creature, so no fight starts"
}

// The review of 0929cb9: what a viewer arriving mid-fight is sent, the erasure of
// one entry among several, the release of a target that died, stale timers and a
// sighting's new unit.

pub fn a_viewer_arriving_mid_chase_gets_the_fight_and_the_rest_of_the_path_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, watched) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  assert list.map(news_to(watched, 9), name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x638"]
    as "the viewer's client shows what the others' do: the creature in combat, its target, and its run"
  let assert [
    _,
    _,
    _,
    CreatureMoved(path: Running(from:, to:, started_ms:, ..)),
  ] = news_to(watched, 9)
  assert x_of(from) == 10.0 && x_of(to) == 26.0 && started_ms == start_ms + 1000
    as "the rest of the path: from where it is 1 s into its run to where the run ends, from now"
  assert said(watched)
    |> list.filter(fn(line) { line != "0x262 to 9" })
    |> list.all(fn(line) { string.ends_with(line, " to 9") })
    as "only the arriving viewer is sent anything: no new path is planned"
  let #(_, after) =
    tell(state:, at_ms: 1100, message: moved(number: 2, x: 31.0, seq: 2))
  assert said(after) == []
    as "the creature's own path is the one it had: 31 is within reach of its end"
}

pub fn a_viewer_arriving_mid_return_gets_the_path_home_and_no_fight_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  // The fighter leaves sight 1 s into the chase: the creature leashes and walks home.
  let #(state, _) =
    tell(state:, at_ms: 1000, message: creature.Unwatched(by: ConnectionId(2)))
  let #(_, watched) =
    tell(
      state:,
      at_ms: 1500,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  assert list.map(news_to(watched, 9), name_of) == ["0x262", "0x638"]
    as "out of combat: no 0x89a or 0x908, only the rest of the walk home"
  let assert [_, CreatureMoved(path: Running(from:, to:, ..))] =
    news_to(watched, 9)
  assert x_of(from) == 5.0 && x_of(to) == 0.0
    as "it fell back from 10 at 10 a second for half a second: 5 left to the spawn"
}

pub fn dropping_a_secondary_entry_erases_it_and_dropping_the_top_one_erases_it_and_names_the_next_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5, 6]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  // Player 5 (threat 3) is the target, player 2 (threat 1) the other entry.
  let #(_, secondary) =
    tell(state:, at_ms: 200, message: creature.Unwatched(by: ConnectionId(2)))
  assert said(secondary)
    == [
      "0x355 to 2",
      "0x90a(20, 0) to 5",
      "0x90a(20, 0) to 6",
      "Released(7) to 2",
    ]
    as "opcode.0x90a: a threat of 0 erases player 2's entry for the viewers; the target stays"
  let #(_, top) =
    tell(state:, at_ms: 200, message: creature.Unwatched(by: ConnectionId(5)))
  assert said(top)
    == [
      "0x355 to 5", "0x90a(50, 0) to 2", "0x90a(50, 0) to 6",
      "0x908(20, 1) to 2", "0x908(20, 1) to 6", "Released(7) to 5",
    ]
    as "the top entry is erased too, and the next is named the target"
}

/// The creature's strike on player 2, standing in reach, at the first tick: the
/// state and the strike's key.
fn struck_once() -> #(State, strike_tell.Key) {
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [#(_, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
  #(state, key)
}

pub fn a_target_the_strike_killed_is_released_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once()
  let killing =
    SpellDamageDescription(
      raw_damage: 12,
      scaled_raw_damage: 12,
      absorbed: 9,
      shield_absorbed: 0,
      health_damage_with_overkill: 3,
      overkill: 2,
      glance: 0,
      killed: 1,
      combat_result: combat_result.Hit,
      damage_type: damage_type.Physical,
      hits: [],
    )
  let #(_, answered) =
    tell(
      state:,
      at_ms: 1600,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Landed(descriptions: [
          hit.Description(
            spell4_effects_id: 184_741,
            delay_ms: 0,
            damage: killing,
          ),
        ]),
      )),
    )
  assert list.contains(said(answered), "Released(7) to 2")
    as "the player's answer is Landed with the killed bit: the creature releases it"
}

pub fn a_target_found_dead_is_released_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once()
  let #(_, answered) =
    tell(
      state:,
      at_ms: 1600,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Refused(why: strike_tell.Dead),
      )),
    )
  assert list.contains(said(answered), "Released(7) to 2")
    as "a player at 0 refuses the strike Dead: the creature releases it"
}

pub fn an_attack_tick_of_a_fight_that_ended_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  // The fight ends by its last viewer's Unwatched before the tick fires.
  let #(state, _) =
    tell(state:, at_ms: 500, message: creature.Unwatched(by: ConnectionId(2)))
  let #(_, stale) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(stale) == [] && timers(stale) == []
    as "the tick is of the fight that leashed: an old generation"
}

pub fn a_home_timer_that_fires_again_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, leashed) =
    tell(state:, at_ms: 1000, message: creature.Unwatched(by: ConnectionId(2)))
  let home = timer_for(leashed, 1000)
  let #(state, _) = fire(state:, at_ms: 2000, timer: home)
  let #(_, again) = fire(state:, at_ms: 2100, timer: home)
  assert said(again) == [] && timers(again) == []
    as "the creature is home: a firing of that walk's timer is of an old generation"
}

pub fn a_player_back_in_the_ring_under_a_new_unit_with_the_same_sequence_number_is_aggroed_as_the_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  // The player camped and entered again with no move since: its connection's
  // sequence number is the same, its unit is new (the map gives no id twice).
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 7),
    )
  let #(state, leashed) =
    tell(state:, at_ms: 100, message: creature.Unwatched(by: ConnectionId(2)))
  let #(state, _) = fire(state:, at_ms: 200, timer: timer_for(leashed, 100))
  let #(state, _) =
    tell(
      state:,
      at_ms: 5000,
      message: creature.Watched(
        by: ConnectionId(2),
        stay: stay.next(stay_of(2)),
      ),
    )
  let #(_, again) =
    tell(
      state:,
      at_ms: 5000,
      message: creature.Approached(
        by: ConnectionId(2),
        unit_id: 21,
        place: at(5.0),
        seq: 7,
        stay: stay.next(stay_of(2)),
      ),
    )
  assert list.contains(said(again), "0x908(21, 1) to 2")
    as "the equal sequence number is taken, with the new unit 21"
  assert fights_told_for(again)
    == [#(2, stay.next(stay_of(2)), Threatened(unit_id: unit, life:))]
    as "the threat goes for the stay the newest Watched named"
}

pub fn a_strike_of_a_players_earlier_stay_that_reaches_the_creature_after_its_rejoin_threatens_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // The player struck the Beast, then left the map and joined it again: the map
  // sent the Beast Unwatched and the new stay's Watched. The strike, delayed, lands
  // after both.
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: creature.Unwatched(by: ConnectionId(2)),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: creature.Watched(
        by: ConnectionId(2),
        stay: stay.next(stay_of(2)),
      ),
    )
  let #(_, struck) =
    tell(
      state:,
      at_ms: 200,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 10, 1.0)]),
    )
  assert fights_told_for(struck) == []
    as "a strike of the earlier stay starts no fight with the player's new stay"
}

pub fn a_player_that_stops_seeing_the_creature_is_told_its_release_for_the_stay_it_had_test() -> Nil {
  use <- owned_test.run(5000)
  // The Unwatched takes the player out of the viewers and off the threat list in
  // one step: its release still goes for the stay the Watched named.
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(_, unwatched) =
    tell(state:, at_ms: 1000, message: creature.Unwatched(by: ConnectionId(2)))
  assert fights_told_for(unwatched)
    == [#(2, stay_of(2), Released(unit_id: unit))]
}
