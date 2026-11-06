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
import crowd_control_support
import genesis_prime/client_connection.{
  type News, CastFinished, CastStarted, CastWent, CombatState, CreatureAppeared,
  CreatureMoved, CreaturePlaced, Health, PeerNews, Targeting, Threat,
}
import genesis_prime/game/crowd_control
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell.{
  Answered, Attacks, CreatureStriker, Key, Landed, PlayerStriker, Refused,
  Released, Strike, Threatened,
}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state
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
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_path.{Running}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import gleam/option.{None}
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
  beast_with(viewers:, armor: creature_life.NoArmor)
}

/// A Beast with this Interrupt Armor.
fn beast_with(
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> State {
  beast_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: spawn_support.battle_beast(number: 1, x: 0.0),
    viewers:,
    armor:,
  )
}

/// A Beast started at this source's spawn, `Started` taken.
fn beast_from(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> State {
  let state =
    creature.new(Settings(
      creature: CreatureStart(
        map: ship,
        incarnation: 1,
        unit_id: unit,
        life:,
        spawn: source,
        clock_origin_ms: 5000,
        viewers: list.map(viewers, fn(viewer) {
          #(ConnectionId(viewer), stay_of(viewer))
        }),
      ),
      spawn: Spawn(
        ..spawn,
        combat: creature_life.Combat(..spawn.combat, interrupt_armor: armor),
      ),
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
  creature.Strike(
    tell: Strike(
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
      controls: [],
    ),
  )
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
    CreaturePlaced(..) -> "0x638(placed)"
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
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.Shield(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..) -> "other"
    client_connection.CrowdControlApplied(..) -> "0x87f"
    client_connection.CrowdControlEnded(..) -> "0x880"
    client_connection.InterruptArmor(armor:) ->
      "0x938(21, " <> int.to_string(armor) <> ")"
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

pub fn a_summoned_creature_aggroes_the_first_player_that_approaches_it_and_strikes_with_5649_test() -> Nil {
  use <- owned_test.run(5000)
  // The summoned creature is a run-only spawn: only its respawn differs from a
  // stored one's, so the first `Approached` the map tells it (from the ring held
  // at its start) leads to the same aggro and the same attack tick.
  let spawn = spawn_support.battle_beast(number: -1, x: 0.0)
  let state =
    beast_from(
      source: spawn_source.RunOnly(spawn_source.Summoned(
        id: SpawnId(-1),
        creature_id: spawn.creature_id,
        level: None,
        place: spawn.place,
      )),
      spawn:,
      viewers: [2],
      armor: creature_life.NoArmor,
    )
  let #(state, aggro) =
    tell(state:, at_ms: 0, message: approached(number: 2, x: 5.0, seq: 1))
  assert said(aggro)
    == ["0x908(20, 1) to 2", "0x89a(1) to 2", "Threatened(7, 3) to 2"]
    as "the player is targeted and threatened as for a stored spawn's creature"
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == ["0x7ff to 2", "Attacks to 2"]
  let assert [CastStarted(start:)] = news_to(ticked, 2)
  assert start.spell4_id == 5649
    && start.caster_unit_id == 7
    && start.primary_target_unit_id == 20
    as "the kind's attack spell, cast by the creature on the approaching player"
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
  let assert [
    #(2, Attacks(tell: Strike(key:, from:, striker:, offence:, controls: []))),
  ] = fights_told(ticked)
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
        outcome: Landed(
          descriptions: [
            hit.Description(
              spell4_effects_id: 184_741,
              delay_ms: 0,
              damage: description,
            ),
          ],
          controls: [],
        ),
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
        outcome: Landed(descriptions: [], controls: []),
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
        outcome: Landed(descriptions: [], controls: []),
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

/// The leash's path home is the client's only way to stop a creature it was told
/// to run: a 0x638 replaces the unit's position movement (`movement_command.kind_4`).
/// A leash in the millisecond the chase began finds the creature still at home, with
/// no distance to walk, yet its viewers hold a path that runs away from it.
pub fn a_leash_in_the_millisecond_a_chase_began_still_tells_the_viewers_to_stop_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, chased) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  assert list.contains(said(chased), "0x638 to 5")
    as "the chase is sent to the viewers: they now run the creature toward x = 26"
  let #(_, leashed) =
    tell(state:, at_ms: 0, message: creature.Unwatched(by: ConnectionId(2)))
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the only player on the threat list is gone: the creature leashes"
  assert list.contains(said(leashed), "0x638(placed) to 5")
    as "the viewers' running path is replaced by the creature's place, home, though it is where its path began"
  let assert [CreaturePlaced(place:, at_ms:)] =
    list.filter(news_to(leashed, 5), fn(news) {
      name_of(news) == "0x638(placed)"
    })
    as "one placement to the viewer"
  assert x_of(place) == 0.0 && at_ms == start_ms
    as "the place is the spawn, home, at the time of the leash"
}

pub fn a_creature_whose_path_has_ended_at_the_leash_circle_sends_no_placement_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, chased) =
    tell(state:, at_ms: 0, message: moved(number: 2, x: 100.0, seq: 2))
  assert x_of(creature_path.end(path: path_sent(chased))) == 55.0
    as "the path to 96 is clipped at the leash circle, 55 from the spawn"
  let #(_, again) =
    tell(state:, at_ms: 5800, message: moved(number: 2, x: 100.0, seq: 3))
  assert said(again) == []
    as "the path ended at 5500 ms, at the circle: a replan finds nothing to run and the viewers hold no path that still runs, so nothing is sent"
}

pub fn a_leash_of_a_creature_that_stands_at_home_sends_no_path_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  assert !list.contains(said(aggro), "0x638 to 5")
    as "5 is within reach 8 of the spawn: the creature stays at home"
  let #(_, leashed) =
    tell(state:, at_ms: 700, message: creature.Unwatched(by: ConnectionId(2)))
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the only player on the threat list is gone: the creature leashes"
  assert !list.contains(said(leashed), "0x638 to 5")
    && !list.contains(said(leashed), "0x638(placed) to 5")
    as "no path was sent, so none runs and nothing is sent to replace one"
}

/// The chase is replanned when the target is beyond reach of the path's end. A
/// target that doubles back to the place the creature has run to leaves nothing to
/// run, but the viewers still run the earlier path on to its end.
pub fn a_target_that_doubles_back_onto_the_runner_stops_the_viewers_runs_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, chased) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let assert Running(to:, ..) = path_sent(chased)
  assert x_of(to) == 26.0
    as "the path runs from the spawn to 30 - 0.5 x 8, at 10 units a second"
  let #(_, doubled) =
    tell(state:, at_ms: 1000, message: moved(number: 2, x: 10.0, seq: 2))
  assert said(doubled) == ["0x638(placed) to 2", "0x638(placed) to 5"]
    as "1 s into the run the creature is at 10, where the target now is: the viewers are told to stand it there"
  let assert [CreaturePlaced(place:, at_ms:), ..] = news_to(doubled, 5)
  assert x_of(place) == 10.0 && at_ms == start_ms + 1000
    as "at the place and the time of the move"
}

pub fn a_creature_killed_while_it_runs_places_its_viewers_where_it_fell_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(_, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  let assert [CreaturePlaced(place:, at_ms:)] =
    list.filter(news_to(killed, 5), fn(news) {
      name_of(news) == "0x638(placed)"
    })
    as "the viewers hold a path that runs on past the corpse, so each is sent one placement"
  assert x_of(place) == 10.0 && at_ms == start_ms + 1000
    as "where it fell, 1 s into its run, at the time of its death"
}

pub fn a_creature_killed_standing_places_nobody_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(_, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  assert !list.contains(said(killed), "0x638(placed) to 5")
    as "no path was sent, so none runs on"
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

// Stealth (issue 483): the map tells a creature `Withdrew` for a player that enters
// stealth. The creature's rule is not changed; these tests hold what the step relies
// on. Evidence: Jim's decision on issue 483 (Discord, 2026-11-06, option A): a
// creature keeps fighting a stealthed player already on its threat list, and does not
// aggro one that is not.

pub fn a_creature_fighting_a_player_told_withdrew_for_it_keeps_it_on_its_threat_list_chases_its_next_move_and_strikes_it_in_reach_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let tick = timer_for(aggro, 1500)
  let #(state, withdrawn) =
    tell(state:, at_ms: 100, message: creature.Withdrew(by: ConnectionId(2)))
  assert said(withdrawn) == []
    as "Withdrew touches only the creature's near set: no news, no change of target"
  let #(_, chased) =
    tell(state:, at_ms: 200, message: moved(number: 2, x: 30.0, seq: 2))
  assert x_of(creature_path.end(path: path_sent(chased))) == 26.0
    as "the next TargetMoved of the target is chased as before: 30 - 0.5 x 8 = 26"
  let #(_, struck) = fire(state:, at_ms: 1500, timer: tick)
  assert list.contains(said(struck), "0x7ff to 2")
    as "the tick finds the player 5 units off, within reach 8: it strikes, with no new aggro"
  let #(_, unwatched) =
    tell(state:, at_ms: 300, message: creature.Unwatched(by: ConnectionId(2)))
  assert list.contains(said(unwatched), "Released(7) to 2")
    as "the player was still on the threat list, so the end of its watch releases it"
}

pub fn a_near_player_told_withdrew_is_not_aggroed_at_the_home_timer_nor_when_the_corpse_stands_the_creature_again_and_one_approached_again_is_test() -> Nil {
  use <- owned_test.run(5000)
  near_player_is_not_aggroed_and_one_approached_again_is(
    gone: creature.Withdrew(by: ConnectionId(5)),
  )
}

/// Player 5 comes near a creature and `gone` tells the creature it is not near any more:
/// neither the home timer nor the corpse timer aggroes it, and an `Approached` after
/// `gone` does.
fn near_player_is_not_aggroed_and_one_approached_again_is(
  gone gone: creature.Message,
) -> Nil {
  // Home timer: player 2 fights the creature and runs out of the ring until it
  // leashes; player 5 comes near while it walks home.
  let leashed = fn() {
    let #(state, aggro) =
      tell(
        state: beast(viewers: [2, 5]),
        at_ms: 0,
        message: approached(number: 2, x: 5.0, seq: 1),
      )
    let #(state, _) =
      tell(state:, at_ms: 0, message: moved(number: 2, x: 100.0, seq: 2))
    let #(state, _) =
      tell(state:, at_ms: 0, message: creature.Withdrew(by: ConnectionId(2)))
    let #(state, t1) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
    let #(state, t2) = fire(state:, at_ms: 3000, timer: timer_for(t1, 1500))
    let #(state, t3) = fire(state:, at_ms: 4500, timer: timer_for(t2, 1500))
    let #(state, leashed) =
      fire(state:, at_ms: 6000, timer: timer_for(t3, 1500))
    #(state, timer_for(leashed, 5500))
  }
  let #(state, home) = leashed()
  let #(state, _) =
    tell(state:, at_ms: 7000, message: approached(number: 5, x: 3.0, seq: 1))
  let #(withdrawn, _) = tell(state:, at_ms: 7100, message: gone)
  let #(_, at_home) = fire(state: withdrawn, at_ms: 11_500, timer: home)
  assert !aggroes(at_home)
    as "home: player 5 was told it is gone, so it is in no ring and is not aggroed"
  let #(again, _) =
    tell(
      state: withdrawn,
      at_ms: 7200,
      message: approached(number: 5, x: 3.0, seq: 2),
    )
  let #(_, at_home) = fire(state: again, at_ms: 11_500, timer: home)
  assert list.contains(said(at_home), "0x908(50, 1) to 5")
    as "approached again before the home timer, it is aggroed"

  // The corpse timer: the creature is killed and stands again at its spawn.
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  let corpse = timer_for(killed, 60_000)
  let #(state, _) =
    tell(state:, at_ms: 2000, message: creature.Withdrew(by: ConnectionId(2)))
  let #(state, _) =
    tell(state:, at_ms: 3000, message: approached(number: 5, x: 3.0, seq: 1))
  let #(withdrawn, _) = tell(state:, at_ms: 3100, message: gone)
  let #(_, stood) = fire(state: withdrawn, at_ms: 61_000, timer: corpse)
  assert !aggroes(stood)
    as "corpse timer: players 2 and 5 were told they are gone, so the creature stands again and aggroes no one"
  let #(again, _) =
    tell(
      state: withdrawn,
      at_ms: 3200,
      message: approached(number: 5, x: 3.0, seq: 2),
    )
  let #(_, stood) = fire(state: again, at_ms: 61_000, timer: corpse)
  assert list.contains(said(stood), "0x908(50, 1) to 5")
    as "approached again before the corpse timer, it is aggroed"
}

// A player's death (issue 496): the killing answer, the refusal and the map's
// `PlayerDied` each take the player out of the creature's `near` and its threat
// list, so no timer aggroes the body. Evidence: `Spell4ValidTargets.targetBitmask`
// (a dead unit is struck by nothing); the rest is the server's choice (the Design of
// issue 496, section 2); a threat of 0 erases an entry (`opcode.0x90a`).

pub fn a_creature_that_kills_its_only_target_in_its_ring_does_not_aggro_the_body_at_its_home_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once()
  let #(state, answered) =
    tell(state:, at_ms: 1600, message: killing_answer(key:))
  let #(_, at_home) = fire(state:, at_ms: 1600, timer: timer_for(answered, 0))
  assert !aggroes(at_home)
    as "the creature stands at its spawn: its home timer fires at once, and the body is in no one's ring"
}

pub fn a_creature_whose_strike_is_refused_dead_does_not_aggro_the_body_at_its_home_timer_nor_when_its_corpse_timer_stands_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once_among(viewers: [2, 5])
  let refused =
    creature.StrikeAnswered(answered: Answered(
      key:,
      outcome: Refused(why: strike_tell.Dead),
    ))
  let #(state, answered) = tell(state:, at_ms: 1600, message: refused)
  let #(state, at_home) =
    fire(state:, at_ms: 1600, timer: timer_for(answered, 0))
  assert !aggroes(at_home) as "home timer: the refusing player is not aggroed"
  // Player 5 kills the creature; its corpse timer stands it again.
  let #(state, killed) =
    tell(
      state:,
      at_ms: 2000,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  let #(_, stood) =
    fire(state:, at_ms: 62_000, timer: timer_for(killed, 60_000))
  assert !aggroes(stood)
    as "corpse timer: the creature stands again and aggroes no one for player 2"
}

pub fn a_creature_told_player_died_for_its_target_erases_its_entry_names_the_next_and_never_strikes_the_body_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
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
  // Player 5 (threat 3) is the target, player 2 (threat 1) the other entry.
  let #(state, died) =
    tell(state:, at_ms: 200, message: creature.PlayerDied(by: ConnectionId(5)))
  assert said(died)
    == [
      "0x90a(50, 0) to 2",
      "0x90a(50, 0) to 5",
      "0x908(20, 1) to 2",
      "0x908(20, 1) to 5",
      "Released(7) to 5",
    ]
    as "opcode.0x90a: a threat of 0 erases the body's entry; opcode.0x908 names player 2; the body is told Released"
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [#(struck, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
    as "the tick strikes one player"
  assert struck == 2 && key.unit_id == unit_of(2)
    as "the strike goes to player 2's connection and names its unit, never the body's"
}

pub fn a_creature_told_player_died_for_its_only_entry_leashes_and_at_home_aggroes_no_one_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, died) =
    tell(state:, at_ms: 100, message: creature.PlayerDied(by: ConnectionId(2)))
  assert said(died)
    == [
      "0x90a(20, 0) to 2",
      "0x89a(0) to 2",
      "0x937(52) to 2",
      "Released(7) to 2",
    ]
    as "the leash of a creature standing at its spawn: the entry erased, out of combat, full health (52), no path, the body told Released"
  let #(_, at_home) = fire(state:, at_ms: 100, timer: timer_for(died, 0))
  assert said(at_home) == []
    as "at home nothing is aggroed: the body is not near"
}

pub fn a_near_player_told_player_died_is_not_aggroed_at_the_home_timer_nor_by_the_corpse_timer_and_one_approached_again_is_test() -> Nil {
  use <- owned_test.run(5000)
  near_player_is_not_aggroed_and_one_approached_again_is(
    gone: creature.PlayerDied(by: ConnectionId(5)),
  )
}

pub fn player_died_for_a_player_neither_near_nor_on_the_list_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = beast(viewers: [2])
  let #(unchanged, told) =
    tell(state:, at_ms: 100, message: creature.PlayerDied(by: ConnectionId(2)))
  assert support.effects_of(told) == [] && unchanged == state
    as "player 2 was never near: no effects, state unchanged"
  let #(state, key) = struck_once()
  let #(state, _) = tell(state:, at_ms: 1600, message: killing_answer(key:))
  let #(after, told) =
    tell(state:, at_ms: 1700, message: creature.PlayerDied(by: ConnectionId(2)))
  assert support.effects_of(told) == [] && after == state
    as "the killing answer already released player 2 and dropped it from near: the map's PlayerDied finds nothing"
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
  struck_once_among(viewers: [2])
}

/// The same for a creature these viewers see; player 2 is the one it aggroes.
fn struck_once_among(viewers viewers: List(Int)) -> #(State, strike_tell.Key) {
  let #(state, aggro) =
    tell(
      state: beast(viewers:),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [#(_, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
  #(state, key)
}

/// The player's answer to the strike of `key`: `Landed` with the killed bit set.
fn killing_answer(key key: strike_tell.Key) -> creature.Message {
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
  creature.StrikeAnswered(answered: Answered(
    key:,
    outcome: Landed(
      descriptions: [
        hit.Description(
          spell4_effects_id: 184_741,
          delay_ms: 0,
          damage: killing,
        ),
      ],
      controls: [],
    ),
  ))
}

/// Whether the step aggroes a player: it names a target (0x908) or tells a player
/// `Threatened`.
fn aggroes(taken: ServiceStep(creature.Outgoing)) -> Bool {
  list.any(said(taken), fn(line) {
    string.starts_with(line, "0x908") || string.starts_with(line, "Threatened")
  })
}

pub fn a_target_the_strike_killed_is_released_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once()
  let #(_, answered) = tell(state:, at_ms: 1600, message: killing_answer(key:))
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

// A crowd-control state: the creature does not act until it ends
// (`genesis_prime/world_map/creature_control`, `cc_state.end`).

/// A strike of the player of connection `number` that carries these states and no
/// damage.
fn controlling(
  number number: Int,
  cast_id cast_id: Int,
  controls controls: List(strike_tell.ControlTell),
) -> creature.Message {
  let assert creature.Strike(tell:) = strike_of(number:, cast_id:, blows: [])
    as "strike_of gives a strike"
  creature.Strike(tell: Strike(..tell, controls:))
}

pub fn a_stunned_creature_starts_no_attack_until_the_state_ends_and_then_attacks_from_where_it_stands_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 stands 5 units off, within reach 8: the first tick would strike.
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let first_tick = timer_for(aggro, 1500)
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 100,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert list.contains(said(stunned), "0x87f to 2")
    as "its viewers are told the state took hold"
  let state_ends = timer_for(stunned, 2500)
  let #(state, ticked) = fire(state:, at_ms: 1500, timer: first_tick)
  assert !list.contains(said(ticked), "0x7ff to 2") && fights_told(ticked) == []
    as "the tick finds the player in reach and strikes nothing: the creature is stunned"
  let second_tick = timer_for(ticked, 1500)
  let #(state, ended) = fire(state:, at_ms: 2600, timer: state_ends)
  assert list.contains(said(ended), "0x880 to 2")
    as "the state ends with its 0x880"
  let #(_, acted) = fire(state:, at_ms: 3000, timer: second_tick)
  assert list.contains(said(acted), "0x7ff to 2")
    as "the next tick strikes again from where the creature stands"
}

pub fn a_stunned_creature_starts_no_chase_and_a_running_one_stops_where_it_stands_then_chases_from_there_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 is 30 units off: the creature runs at 10 units a second toward 26.
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  assert list.contains(said(aggro), "0x638 to 2")
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 500,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let assert [CreaturePlaced(place:, ..)] =
    list.filter(news_to(stunned, 2), fn(news) {
      name_of(news) == "0x638(placed)"
    })
    as "a running path stops with 0x638 of kind 2 where the creature stands"
  assert x_of(place) == 5.0 as "10 units a second for 500 ms from x = 0"
  let #(state, moved_away) =
    tell(state:, at_ms: 700, message: moved(number: 2, x: 35.0, seq: 2))
  assert said(moved_away) == []
    as "the player moves and the stunned creature starts no chase"
  let #(_, ended) = fire(state:, at_ms: 3000, timer: timer_for(stunned, 2500))
  let path = path_sent(ended)
  let assert Running(from:, ..) = path as "when the state ends it chases again"
  assert x_of(from) == 5.0 as "from where it stood"
  assert x_of(creature_path.end(path:)) == 31.0
    as "toward 35, 0.5 x reach 8 short"
}

pub fn a_stunned_creature_whose_threat_is_gone_leashes_but_starts_the_walk_home_when_the_state_ends_test() -> Nil {
  use <- owned_test.run(5000)
  // Viewer 5 watches player 2's fight. The creature runs, is stunned at x = 5 and
  // loses its last threat while held.
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 500,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, leashed) =
    tell(state:, at_ms: 600, message: creature.Unwatched(by: ConnectionId(2)))
  assert list.contains(said(leashed), "0x89a(0) to 5")
    && fights_told(leashed) == [#(2, Released(unit_id: unit))]
    as "the leash changes the status and tells as usual"
  assert !list.contains(said(leashed), "0x638 to 5")
    && !list.contains(said(leashed), "0x638(placed) to 5")
    && timers(leashed) == []
    as "but the stunned creature starts no walk and no home timer"
  let #(_, ended) = fire(state:, at_ms: 3000, timer: timer_for(stunned, 2500))
  assert list.contains(said(ended), "0x638 to 5")
    as "the walk home starts when the state ends"
  assert list.map(timers(ended), fn(started) { started.1 }) == [500]
    as "5 units home at 10 a second: the home timer"
}

pub fn two_players_stuns_hold_the_creature_until_the_later_one_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let first_tick = timer_for(aggro, 1500)
  let #(state, first) =
    tell(
      state:,
      at_ms: 100,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, second) =
    tell(
      state:,
      at_ms: 700,
      message: controlling(number: 5, cast_id: 2, controls: [
        crowd_control_support.stagger_stun(instance_id: 49_153),
      ]),
    )
  assert list.count(said(first), fn(line) { line == "0x87f to 2" }) == 1
    && list.count(said(second), fn(line) { line == "0x87f to 2" }) == 1
    as "two 0x87f, one for each player's state"
  let #(state, ticked) = fire(state:, at_ms: 1500, timer: first_tick)
  let #(state, first_ended) =
    fire(state:, at_ms: 2600, timer: timer_for(first, 2500))
  assert list.contains(said(first_ended), "0x880 to 2")
  let #(state, ticked_again) =
    fire(state:, at_ms: 3000, timer: timer_for(ticked, 1500))
  assert !list.contains(said(ticked_again), "0x7ff to 2")
    as "the first state ended and the second still holds: no attack"
  let #(state, second_ended) =
    fire(state:, at_ms: 3200, timer: timer_for(second, 2500))
  assert list.contains(said(second_ended), "0x880 to 2")
  let #(_, acted) =
    fire(state:, at_ms: 4500, timer: timer_for(ticked_again, 1500))
  assert list.contains(said(acted), "0x7ff to 2")
    as "after the later state the creature acts"
}

// ---- crowd-control states (`genesis_prime/world_map/creature_control`) ----
//
// Expected values come from these places: Kick's Knockdown, Spell4Effects 140382
// (delayTime 166, durationTime 3000, state 8), and Stagger's Stun, Spell4Effects 83827
// (delayTime 0, durationTime 2500, state 0), read with `table_rows`; the creature holds
// a state from the tell's arrival to delay plus duration (the module's doc) and ends it
// only with the server's 0x880 (`cc_state.end`); a creature with Interrupt Armor takes
// none and logs one line (Design 445 section 3); the client clears every state at a
// death, so none is ended then (`cc_state.end`).

/// A strike of the player of connection `number` that carries these states and
/// kills with its damage.
fn killing(
  number number: Int,
  cast_id cast_id: Int,
  controls controls: List(strike_tell.ControlTell),
) -> creature.Message {
  let assert creature.Strike(tell:) =
    strike_of(number:, cast_id:, blows: [#(1, 1000, 1.0)])
    as "strike_of gives a strike"
  creature.Strike(tell: Strike(..tell, controls:))
}

/// The Beast started for viewers 2 and 5 with this Interrupt Armor.
fn armored(armor armor: creature_life.InterruptArmor) -> State {
  beast_with(viewers: [2, 5], armor:)
}

/// The states' news the step sends to viewer `number`: `0x87f` and `0x880`, in order.
fn state_news(
  taken: ServiceStep(creature.Outgoing),
  number: Int,
) -> List(client_connection.News) {
  list.filter(news_to(taken, number), fn(news) {
    list.contains(["0x87f", "0x880"], name_of(news))
  })
}

/// The states the step's answer to the caster says landed.
fn landed_in(
  taken: ServiceStep(creature.Outgoing),
) -> List(strike_tell.ControlLanded) {
  list.flat_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.Struck(
        answered: Answered(outcome: Landed(controls:, ..), ..),
        ..,
      ) -> controls
      creature.Struck(..) | creature.News(..) | creature.FightTold(..) -> []
    }
  })
}

/// The timers of the creature's states the step starts, with their times.
fn control_timers(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(step.TimerId, Int)) {
  list.filter(timers(taken), fn(started) {
    creature.control_of(timer: started.0) != Error(Nil)
  })
}

fn timers_cancelled(
  taken: ServiceStep(creature.Outgoing),
) -> List(step.TimerId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.CancelServiceTimer(timer:)) -> Ok(timer)
      OwnEffect(step.Send(..))
      | OwnEffect(step.Reply(..))
      | OwnEffect(step.StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

pub fn a_struck_creature_with_no_armor_holds_the_state_its_viewers_get_the_0x87f_and_the_answer_names_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.kick_knockdown(instance_id: 28_673),
      ]),
    )
  let applied =
    client_connection.CrowdControlApplied(
      state: crowd_control_state.Knockdown,
      instance_id: 28_673,
    )
  assert state_news(taken, 2) == [applied] && state_news(taken, 5) == [applied]
    as "0x87f with the go's instance id for each viewer"
  assert landed_in(taken)
    == [
      strike_tell.ControlLanded(
        tell: crowd_control_support.kick_knockdown(instance_id: 28_673),
        ends_at_ms: 14_166,
      ),
    ]
    as "the answer names it, with the time the creature holds it until: its arrival, 10000 + 1000, plus 166 plus 3000"
  assert creature.controlled(state:)
  assert control_timers(taken) == [#(step.TimerId(5), 3166)]
    as "one timer for the state, 166 + 3000 from the tell; ids 4n + 1 from 5"
}

pub fn the_state_ends_with_a_0x880_at_arrival_plus_delay_plus_duration_and_not_before_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 77, controls: [
        crowd_control_support.kick_knockdown(instance_id: 28_673),
      ]),
    )
  assert list.map(state_news(taken, 2), name_of) == ["0x87f"]
    as "no 0x880 comes with the strike: the state ends only at its timer, 3166 ms on (Kick: 166 + 3000)"
  let #(state, ended) = fire(state:, at_ms: 4166, timer: timer_for(taken, 3166))
  let over =
    client_connection.CrowdControlEnded(
      state: crowd_control_state.Knockdown,
      cast_id: 77,
      instance_id: 28_673,
    )
  assert state_news(ended, 2) == [over] && state_news(ended, 5) == [over]
    as "0x880 names the unit's state, the strike's cast and the go's instance id"
  assert !creature.controlled(state:)
  let #(_, again) = fire(state:, at_ms: 4200, timer: step.TimerId(5))
  assert support.effects_of(again) == []
    as "a timer that fires for a state already ended writes nothing"
}

pub fn two_states_of_one_kind_from_one_caster_are_held_separately_and_two_ending_together_are_two_0x880_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
        crowd_control_support.stagger_stun(instance_id: 28_674),
      ]),
    )
  assert list.length(state_news(taken, 2)) == 2
    && control_timers(taken)
    == [#(step.TimerId(5), 2500), #(step.TimerId(9), 2500)]
    as "two 0x87f and a timer for each state"
  let #(state, first) = fire(state:, at_ms: 3500, timer: step.TimerId(5))
  assert list.map(state_news(first, 2), name_of) == ["0x880"]
    && creature.controlled(state:)
    as "one 0x880 for the first, and the second still holds"
  let #(state, second) = fire(state:, at_ms: 3500, timer: step.TimerId(9))
  assert list.map(state_news(second, 2), name_of) == ["0x880"]
    && !creature.controlled(state:)
    as "each ends with its own 0x880, though both end in one millisecond"
}

pub fn two_players_states_have_two_0x87f_and_two_0x880_each_with_its_own_instance_id_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, second) =
    tell(
      state:,
      at_ms: 1500,
      message: controlling(number: 3, cast_id: 2, controls: [
        crowd_control_support.stagger_stun(instance_id: 40_961),
      ]),
    )
  assert list.map(state_news(first, 5), name_of) == ["0x87f"]
    && list.map(state_news(second, 5), name_of) == ["0x87f"]
  let #(state, one) = fire(state:, at_ms: 3500, timer: step.TimerId(5))
  assert list.map(state_news(one, 5), name_of) == ["0x880"]
    && creature.controlled(state:)
  let #(state, two) = fire(state:, at_ms: 4000, timer: step.TimerId(9))
  assert list.map(state_news(two, 5), name_of) == ["0x880"]
    && !creature.controlled(state:)
    as "each state ends with its own 0x880; the creature is held until the later one"
}

pub fn a_creature_that_dies_stunned_sends_no_0x880_and_a_timer_after_death_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1100,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 1000, 1.0)]),
    )
  assert state_news(killed, 5) == []
    as "the client clears every state at a death: no 0x880"
  assert list.contains(timers_cancelled(killed), step.TimerId(5))
    as "the state's timer is cancelled"
  assert !creature.controlled(state:)
  let #(_, late) = fire(state:, at_ms: 3500, timer: step.TimerId(5))
  assert support.effects_of(late) == []
    as "a timer already waiting in the mailbox writes nothing"
}

pub fn a_strike_that_kills_the_creature_lands_no_state_and_one_on_a_corpse_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, killed) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: killing(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert landed_in(killed) == [] && state_news(killed, 5) == []
    as "a creature the strike kills takes no state"
  let #(state, corpse) =
    tell(
      state:,
      at_ms: 1100,
      message: controlling(number: 2, cast_id: 2, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_674),
      ]),
    )
  assert said(corpse) == ["Refused(Dead) to 2"] && !creature.controlled(state:)
    as "a strike after the death is refused as always: no state"
}

pub fn a_viewer_arriving_while_a_state_is_held_is_not_told_it_and_a_new_creature_holds_none_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: armored(armor: creature_life.NoArmor),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(_, arrived) =
    tell(
      state:,
      at_ms: 1500,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  let names = list.map(news_to(arrived, 9), name_of)
  assert list.first(names) == Ok("0x262") && !list.contains(names, "0x87f")
    as "the creature's 0x262 does not carry a state: a viewer that arrives mid-state is not told (a gap)"
  assert !creature.controlled(state: beast(viewers: []))
    as "a creature that crashed is started again from its spawn with no state"
}

pub fn a_deflected_stun_only_strike_lands_no_state_and_sends_no_0x87f_test() -> Nil {
  use <- owned_test.run(5000)
  // A deflected unit is named in the go's 0x7fb, not in a target info, so the client is
  // given no effect for it: the creature takes no state either (`opcode.0x7fb`). A
  // deflect roll of 0 is under the Beast's chance of 0.016.
  let assert creature.Strike(tell: sent) =
    controlling(number: 2, cast_id: 1, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ])
    as "a strike"
  let assert PlayerStriker(unit_id:, place:, seq:, stay:, ..) = sent.striker
    as "a player's strike"
  let deflected =
    creature.Strike(
      tell: Strike(
        ..sent,
        striker: PlayerStriker(
          unit_id:,
          place:,
          seq:,
          stay:,
          rolls: Rolls(crit: 0.5, deflect: 0.0, glance: 0.5),
        ),
      ),
    )
  let #(state, taken) =
    tell(state: beast(viewers: [2]), at_ms: 0, message: deflected)
  assert said(taken) == ["Deflected to 2"]
    as "the answer is Deflected and nothing is sent to the viewers"
  assert !creature.controlled(state:)
    && control_timers(taken) == []
    && state_news(taken, 2) == []
    && landed_in(taken) == []
}

// ---- Interrupt Armor (`genesis_prime/world_map/creature_control`) ----
//
// Expected values come from these places: Jim's decision for the step (Design 445
// section 3): a state lands only on a creature whose armor is already 0 when the strike
// arrives, a strike on armor above 0 lands none and destroys the row's dataBits03 points
// (Stagger's Stun 83827 removes 1), never below 0, and infinite armor (-1) takes none and
// loses nothing; the viewers are told the current value as 0x938 of stat 21
// (`opcode.0x938.interrupt_armor`), which the client clamps to 0 and the maximum; armor
// returns to its maximum `interrupt_armor_refill_ms` after the strike (10000 ms, migration
// 0016's server choice, `spawn_support.numbers`), and a later strike restarts the wait.

/// The step's 0x938 of stat 21 to viewer `number`, for any armor from 0 to 10, in order.
fn armor_news(
  taken: ServiceStep(creature.Outgoing),
  number: Int,
) -> List(client_connection.News) {
  let armors =
    list.map([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn(armor) {
      client_connection.InterruptArmor(armor:)
    })
  list.filter(news_to(taken, number), fn(news) { list.contains(armors, news) })
}

/// The refill timers the step starts, with their times.
fn refill_timers(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(step.TimerId, Int)) {
  list.filter(timers(taken), fn(started) { started.0 == step.TimerId(2) })
}

fn stunning(
  from from: Int,
  cast_id cast_id: Int,
  instance_id instance_id: Int,
) -> creature.Message {
  controlling(number: from, cast_id:, controls: [
    crowd_control_support.stagger_stun(instance_id:),
  ])
}

pub fn armor_wears_down_by_the_rows_points_and_the_state_lands_once_it_is_0_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    tell(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  assert landed_in(first) == [] && state_news(first, 2) == []
    as "armor 2: the first strike lands no state"
  assert armor_news(first, 2) == [client_connection.InterruptArmor(armor: 1)]
    && armor_news(first, 5) == [client_connection.InterruptArmor(armor: 1)]
    as "it destroys the row's 1 point and every viewer is told the 1 left"
  assert !creature.controlled(state:)
  let #(state, second) =
    tell(
      state:,
      at_ms: 2000,
      message: stunning(from: 2, cast_id: 2, instance_id: 28_674),
    )
  assert landed_in(second) == []
    && armor_news(second, 2) == [client_connection.InterruptArmor(armor: 0)]
    as "the second takes the last point, and still lands nothing: the armor was above 0 when it arrived"
  let #(state, third) =
    tell(
      state:,
      at_ms: 3000,
      message: stunning(from: 2, cast_id: 3, instance_id: 28_675),
    )
  assert landed_in(third)
    == [
      strike_tell.ControlLanded(
        tell: crowd_control_support.stagger_stun(instance_id: 28_675),
        ends_at_ms: 15_500,
      ),
    ]
    as "the third finds the armor at 0 and lands: arrival 10000 + 3000, plus 2500"
  assert armor_news(third, 2) == [] && creature.controlled(state:)
    as "armor 0 changes no more, and the state holds"
}

pub fn armor_is_never_destroyed_below_0_test() -> Nil {
  use <- owned_test.run(5000)
  // One strike with two rows of 1 each on armor 1.
  let #(_, taken) =
    tell(
      state: armored(armor: creature_life.Armor(points: 1)),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
        crowd_control_support.stagger_stun(instance_id: 28_674),
      ]),
    )
  assert armor_news(taken, 2) == [client_connection.InterruptArmor(armor: 0)]
    && landed_in(taken) == []
    as "2 points of rows on 1 point of armor leave 0, and none of the strike's states lands"
}

pub fn infinite_armor_takes_no_state_and_loses_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    tell(
      state: armored(armor: creature_life.InfiniteArmor),
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  assert landed_in(taken) == []
    && armor_news(taken, 2) == []
    && state_news(taken, 2) == []
    && refill_timers(taken) == []
    && !creature.controlled(state:)
    as "infinite armor (-1): no state, no 0x938, nothing to refill"
}

pub fn armor_refills_at_its_time_and_a_strike_before_it_starts_the_wait_again_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    tell(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  assert refill_timers(first) == [#(step.TimerId(2), 10_000)]
    as "the refill waits interrupt_armor_refill_ms from the strike"
  let #(state, second) =
    tell(
      state:,
      at_ms: 5000,
      message: stunning(from: 2, cast_id: 2, instance_id: 28_674),
    )
  assert list.contains(timers_cancelled(second), step.TimerId(2))
    && refill_timers(second) == [#(step.TimerId(2), 10_000)]
    as "a strike before it cancels the wait and starts it again"
  let #(state, refilled) = fire(state:, at_ms: 15_000, timer: step.TimerId(2))
  assert armor_news(refilled, 2) == [client_connection.InterruptArmor(armor: 2)]
    && armor_news(refilled, 5) == [client_connection.InterruptArmor(armor: 2)]
    as "armor is back at its maximum 2, told to every viewer"
  let #(_, again) =
    tell(
      state:,
      at_ms: 16_000,
      message: stunning(from: 2, cast_id: 3, instance_id: 28_675),
    )
  assert landed_in(again) == []
    && armor_news(again, 2) == [client_connection.InterruptArmor(armor: 1)]
    as "the refilled armor wears down again before a state lands"
  let #(_, full) =
    fire(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 1000,
      timer: step.TimerId(2),
    )
  assert support.effects_of(full) == []
    as "a refill timer that fires with the armor full does nothing"
}

pub fn a_creature_killed_with_worn_armor_cancels_its_refill_and_stands_again_at_full_armor_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1100,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 1000, 1.0)]),
    )
  assert list.contains(timers_cancelled(killed), step.TimerId(2))
    as "the refill timer is cancelled at the death"
  let #(_, late) = fire(state:, at_ms: 11_000, timer: step.TimerId(2))
  assert support.effects_of(late) == []
    as "a refill timer already waiting in the mailbox writes nothing"
  let #(_, arrived) =
    tell(
      state:,
      at_ms: 12_000,
      message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
    )
  let assert [CreatureAppeared(unit:, ..), ..] = news_to(arrived, 9)
    as "the viewer's 0x262"
  assert unit_fields.stat(tail: unit.tail, stat_id: 21) == Ok(2)
    as "armor is back at its maximum"
}

pub fn a_creatures_0x262_carries_its_current_armor_above_0_and_none_otherwise_test() -> Nil {
  use <- owned_test.run(5000)
  let stat_of = fn(state) {
    let #(_, arrived) =
      tell(
        state:,
        at_ms: 2000,
        message: creature.Watched(by: ConnectionId(9), stay: stay_of(9)),
      )
    let assert [CreatureAppeared(unit:, ..), ..] = news_to(arrived, 9)
      as "the viewer's 0x262"
    unit_fields.stat(tail: unit.tail, stat_id: 21)
  }
  let worn = armored(armor: creature_life.Armor(points: 3))
  assert stat_of(worn) == Ok(3)
    as "the create's stat list sets stat 21, which the client reads (opcode.0x938.interrupt_armor)"
  let #(struck, _) =
    tell(
      state: worn,
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  assert stat_of(struck) == Ok(2)
    as "a viewer that arrives after a strike is shown the current value"
  assert stat_of(armored(armor: creature_life.NoArmor)) == Error(Nil)
    && stat_of(armored(armor: creature_life.InfiniteArmor)) == Error(Nil)
    as "none for a creature with no armor or infinite armor: the client's maximum is its own"
}

pub fn a_state_landing_at_armor_0_leaves_the_refill_where_it_is_test() -> Nil {
  use <- owned_test.run(5000)
  // Armor 2 is worn to 0 at 0 and at 1000; the refill, 10000 ms from the last strike
  // that destroyed a point, is due at 11000. A stun at 5000 finds the armor at 0 and
  // lands, and destroys nothing, so it does not move the refill.
  let #(state, _) =
    tell(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 0,
      message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
    )
  let #(state, worn) =
    tell(
      state:,
      at_ms: 1000,
      message: stunning(from: 2, cast_id: 2, instance_id: 28_674),
    )
  assert armor_news(worn, 2) == [client_connection.InterruptArmor(armor: 0)]
  let #(state, landed) =
    tell(
      state:,
      at_ms: 5000,
      message: stunning(from: 2, cast_id: 3, instance_id: 28_675),
    )
  assert list.length(landed_in(landed)) == 1
    as "the stun lands on the armor that is 0"
  assert refill_timers(landed) == []
    && !list.contains(timers_cancelled(landed), step.TimerId(2))
    as "and leaves the running refill alone: two players stunning every few seconds do not keep armor at 0"
  let #(_, refilled) = fire(state:, at_ms: 11_000, timer: step.TimerId(2))
  assert armor_news(refilled, 2) == [client_connection.InterruptArmor(armor: 2)]
    as "the refill fires at 11000, 10000 ms after the strike that destroyed the last point"
}

pub fn a_row_that_destroys_no_armor_changes_nothing_on_armor_above_0_test() -> Nil {
  use <- owned_test.run(5000)
  let told = crowd_control_support.stagger_stun(instance_id: 28_673)
  let harmless =
    strike_tell.ControlTell(
      ..told,
      row: crowd_control.Row(..told.row, armor_removed: 0),
    )
  let #(state, taken) =
    tell(
      state: armored(armor: creature_life.Armor(points: 2)),
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [harmless]),
    )
  assert landed_in(taken) == []
    && armor_news(taken, 2) == []
    && refill_timers(taken) == []
    as "a row of dataBits03 0 lands no state on armor above 0 and sends no 0x938 and starts no refill"
  let #(_, next) =
    tell(
      state:,
      at_ms: 2000,
      message: stunning(from: 2, cast_id: 2, instance_id: 28_674),
    )
  assert armor_news(next, 2) == [client_connection.InterruptArmor(armor: 1)]
    as "the armor was left at 2"
}
