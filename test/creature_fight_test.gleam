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

import cast_support
import character_tables
import connection_rule_support as support
import creature_news_support
import crowd_control_support
import fixture_tables
import genesis_prime/game/area
import genesis_prime/game/crowd_control
import genesis_prime/game/forced_move
import genesis_prime/game/hit.{Blow, Offence, Rolls, Worked}
import genesis_prime/game/lasts
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell.{
  type Key, Answered, Attacks, CreatureStriker, Immune, Key, Landed,
  PlayerStriker, Refused, Released, Strike, Threatened,
}
import genesis_prime/game/telegraph_entries
import genesis_prime/game/unit_news.{
  type News, CastFinished, CastStarted, CastWent, CreatureAppeared,
  CreatureFaces, CreatureMoved, CreaturePlaced, PeerNews,
}
import genesis_prime/game/unit_properties.{type Modifier, Change}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/spell_damage_description.{SpellDamageDescription}
import genesis_prime/message/spell_go
import genesis_prime/message/spell_initial_position.{SpellInitialPosition}
import genesis_prime/message/spell_position.{SpellPosition}
import genesis_prime/message/spell_target_info.{SpellTargetInfo}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/message/spell_telegraph_position.{SpellTelegraphPosition}
import genesis_prime/step.{
  type ConnectionId, type ServiceStep, Connection, ConnectionId, CreatureStart,
  OwnEffect, OwnEvent, ServiceTimerFired, StartServiceTimer, Started, Told,
}
import genesis_prime/table/id.{Creature2Id, Spell4Id, UnitProperty2Id}
import genesis_prime/table/loader/store
import genesis_prime/world_map/creature.{type State, Settings}
import genesis_prime/world_map/creature_fight
import genesis_prime/world_map/creature_kind.{type Kind, type Kinds, Kind}
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_path.{Running, Timed}
import genesis_prime/world_map/creature_turn
import genesis_prime/world_map/creature_unit_type
import genesis_prime/world_map/generation
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import gleam_community/maths
import map_spawn_support
import map_support
import owned_test
import place_support
import planted_table
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

/// The Battle Beast's kind: the 60 s respawn time and the 5649 attack at 1500 ms, with no
/// guard and no special.
fn beast_kind() -> Kind {
  Kind(
    respawn_ms: 60_000,
    attack_spell4_id: Spell4Id(5649),
    alternate_spell4_ids: [],
    attack_interval_ms: 1500,
    guard: option.None,
    specials: [],
  )
}

/// A Beast started at this source's spawn, `Started` taken.
fn beast_from(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> State {
  started_from(source:, spawn:, kind: beast_kind(), viewers:, armor:)
}

/// A creature of this kind started at this source's spawn, `Started` taken.
fn started_from(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  kind kind: Kind,
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> State {
  let #(state, _) = started_with(source:, spawn:, kind:, viewers:, armor:)
  state
}

/// The same, with the step of the `Started` it took: the 0x262 of each viewer and what
/// follows it.
fn started_with(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  kind kind: Kind,
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let #(state, taken) =
    started_raw(source:, spawn:, kind:, viewers:, ring: [], armor:)
  #(state, creature_news_support.at_each_player(state:, taken:))
}

/// The same, the step as the creature sends it to its map, for a start whose ring holds
/// these players.
fn started_raw(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  kind kind: Kind,
  viewers viewers: List(Int),
  ring ring: List(step.RingMember),
  armor armor: creature_life.InterruptArmor,
) -> #(State, ServiceStep(creature.Outgoing)) {
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
          #(
            ConnectionId(viewer),
            map_support.stay(count: viewer),
            generation.first(),
          )
        }),
        ring:,
      ),
      spawn: Spawn(
        ..spawn,
        combat: creature_life.Combat(..spawn.combat, interrupt_armor: armor),
      ),
      kind:,
      numbers: spawn_support.numbers,
    ))
  creature.step(
    state,
    support.input_at_ms(ms: start_ms, event: OwnEvent(Started)),
  )
}

/// The player of connection `number`, at x = 5 in its stay, as a ring names it.
fn ring_member(number: Int) -> step.RingMember {
  ring_member_in_stay(number:, stay_count: number)
}

/// The same in the stay of its `stay_count`th join.
fn ring_member_in_stay(
  number number: Int,
  stay_count stay_count: Int,
) -> step.RingMember {
  step.RingMember(
    by: ConnectionId(number),
    unit_id: unit_of(number),
    place: map_spawn_support.at(5.0),
    seq: 1,
    stay: map_support.stay(count: stay_count),
    hit_radius: place_support.player_hit_radius,
  )
}

/// The creature's address, which its strikes come from.
fn address() -> step.Address {
  step.Creature(map: ship, incarnation: 1, unit_id: unit, life:)
}

/// The unit of the player of connection `number`: ten times it.
fn unit_of(number: Int) -> Int {
  number * 10
}

fn tell(
  state state: State,
  at_ms at_ms: Int,
  message message: creature.Message,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let #(state, taken) = tell_raw(state:, at_ms:, message:)
  #(state, creature_news_support.at_each_player(state:, taken:))
}

/// The same, the step as the creature sends it: to its map, news once for all its viewers.
fn tell_raw(
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
  let #(state, taken) =
    creature.step(
      state,
      support.input_at_ms(
        ms: start_ms + at_ms,
        event: OwnEvent(ServiceTimerFired(timer:)),
      ),
    )
  #(state, creature_news_support.at_each_player(state:, taken:))
}

fn approached(
  number number: Int,
  x x: Float,
  seq seq: Int,
) -> creature.Message {
  creature.Approached(member: step.RingMember(
    by: ConnectionId(number),
    unit_id: unit_of(number),
    place: map_spawn_support.at(x),
    seq:,
    stay: map_support.stay(count: number),
    hit_radius: place_support.player_hit_radius,
  ))
}

fn moved(number number: Int, x x: Float, seq seq: Int) -> creature.Message {
  creature.TargetMoved(
    by: ConnectionId(number),
    place: map_spawn_support.at(x),
    seq:,
    stay: map_support.stay(count: number),
    hit_radius: place_support.player_hit_radius,
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
      key: Key(cast_id:, occasion: strike_tell.AtGo(phase: 0), unit_id: unit),
      from: Connection(ConnectionId(number)),
      striker: PlayerStriker(
        unit_id: unit_of(number),
        place: map_spawn_support.at(2.0),
        seq: 1,
        stay: map_support.stay(count: number),
        hit_radius: place_support.player_hit_radius,
        rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
      ),
      offence: Offence(
        blows: list.map(blows, fn(blow) {
          Blow(
            spell4_effects_id: blow.0,
            damage_type: 3,
            damage: Worked(blow.1),
            delay_ms: 0,
            threat_multiplier: blow.2,
          )
        }),
        crit_chance: 0.0,
        crit_severity: 1.5,
        strikethrough: 0.0,
      ),
      controls: [],
      gates: [],
    ),
  )
}

/// The tells of the step to players in the fight, by connection.
fn fights_told(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, strike_tell.Fight)) {
  list.map(fights_told_for(taken), fn(told) { #(told.0, told.2) })
}

/// The numbers of the players the step tells to take a strike, in order.
fn struck_numbers(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.sort(list.map(fights_told(taken), fn(told) { told.0 }), int.compare)
}

/// The same, each with the stay it goes for.
fn fights_told_for(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, Stay, strike_tell.Fight)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.Relay(stay:, payload: relay.Fight(told:), ..) ->
        Ok(#(sent.0, stay, told))
      creature.Relay(payload: relay.Struck(..), ..)
      | creature.Relay(payload: relay.KillCredit(..), ..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> Error(Nil)
    }
  })
}

/// Each send of the step in order, as one line: the news to a viewer, a fight's
/// tell or a strike's answer to a connection.
fn said(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.map(support.sends(taken), fn(sent) {
    let to = " to " <> int.to_string(sent.0)
    case sent.1 {
      creature.Broadcast(news: PeerNews(news:, ..), ..) ->
        creature_news_support.name_of(news) <> to
      creature.Relay(
        payload: relay.Fight(told: Threatened(unit_id:, life:)),
        ..,
      ) ->
        "Threatened("
        <> int.to_string(unit_id)
        <> ", "
        <> int.to_string(life)
        <> ")"
        <> to
      creature.Relay(payload: relay.Fight(told: Released(unit_id:)), ..) ->
        "Released(" <> int.to_string(unit_id) <> ")" <> to
      creature.Relay(payload: relay.Fight(told: Attacks(..)), ..) ->
        "Attacks" <> to
      creature.Relay(
        payload: relay.Struck(answered: Answered(outcome: Landed(..), ..)),
        ..,
      ) -> "Landed" <> to
      creature.Relay(
        payload: relay.Struck(answered: Answered(outcome: Refused(why:), ..)),
        ..,
      ) ->
        case why {
          strike_tell.Dead -> "Refused(Dead)" <> to
          strike_tell.Returning -> "Refused(Returning)" <> to
          strike_tell.Despawned -> "Refused(Despawned)" <> to
        }
      creature.Relay(payload: relay.Struck(..), ..) -> "Deflected" <> to
      creature.Relay(payload: relay.KillCredit(..), ..) -> "KillCredit" <> to
      creature.Snapshot(..) -> "Snapshot" <> to
      creature.Expired(..) -> "Expired" <> to
    }
  })
}

/// The news sent to viewer `number`, in order.
fn news_to(taken: ServiceStep(creature.Outgoing), number: Int) -> List(News) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent {
      #(to, creature.Broadcast(news: PeerNews(news:, ..), ..)) if to == number ->
        Ok(news)
      _ -> Error(Nil)
    }
  })
}

/// Whether the step sends the viewer `to` a 0x908 naming this unit as the creature's target.
fn names_target(
  taken taken: ServiceStep(creature.Outgoing),
  unit_id unit_id: Int,
  to to: Int,
) -> Bool {
  list.any(news_to(taken, to), fn(news) {
    string.starts_with(
      creature_news_support.name_of(news),
      "0x908(" <> int.to_string(unit_id) <> ",",
    )
  })
}

/// The timers the step starts, with their times.
fn timers(taken: ServiceStep(creature.Outgoing)) -> List(#(step.TimerId, Int)) {
  support.service_timers_started(taken)
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
    list.filter(news_to(taken, 2), fn(news) {
      creature_news_support.name_of(news) == "0x638"
    })
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
      "Threatened(7, 3) to 2", "turn(kind 18, unit 20) to 2",
      "turn(kind 18, unit 20) to 5",
    ]
    as "0x908 (C, P, aggro threat 1) and 0x89a (C, 1) to every viewer, then Threatened to P, then the turn to P's unit, and no 0x7ff before the first tick"
  assert fights_told_for(aggro)
    == [#(2, map_support.stay(count: 2), Threatened(unit_id: unit, life:))]
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
    == [
      "0x908(20, 1) to 2", "0x89a(1) to 2", "Threatened(7, 3) to 2",
      "turn(kind 18, unit 20) to 2",
    ]
    as "the player is targeted, threatened and faced as for a stored spawn's creature"
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
      "turn(kind 18, unit 50) to 2",
      "turn(kind 18, unit 50) to 5",
    ]
    as "10 x 2.0 + 5 x 1.0 = 25 above the aggro threat 1: player 5 is the new target, and the creature turns to it"
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

/// The lines of the step that are a fight's start: the target (0x908), the combat flag (0x89a), the
/// threat told to the player and the turn to the target.
fn fight_lines(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.filter(said(taken), fn(line) {
    string.starts_with(line, "0x908")
    || string.starts_with(line, "0x89a")
    || string.starts_with(line, "Threatened")
    || string.starts_with(line, "turn(")
  })
}

pub fn a_creature_that_never_fights_struck_by_a_player_starts_no_fight_test() -> Nil {
  use <- owned_test.run(5000)
  // A creature the client draws lying dead (`Creature2.uiFlags.bit8`) has `Combat.fights` False.
  // The same creature with `fights` True is the control: an `Approached` aggroes it and a strike
  // starts its fight, so the harness can fail. The fight's one start is `aggro` for the first and
  // `threatened_by` for the second.
  let beast = spawn_support.battle_beast(number: 1, x: 0.0)
  let cases = [
    #(
      True,
      "a creature that fights is aggroed by an approach and by a strike, and starts its attack tick",
    ),
    #(
      False,
      "a creature that does not fight sends nothing of a fight and starts no timer",
    ),
  ]
  list.each(cases, fn(row) {
    let #(fights, reason) = row
    let state =
      beast_from(
        source: spawn_source.Stored(id: SpawnId(1)),
        spawn: Spawn(
          ..beast,
          combat: creature_life.Combat(..beast.combat, fights:),
        ),
        viewers: [2],
        armor: creature_life.NoArmor,
      )
    let #(_, approach) =
      tell(state:, at_ms: 0, message: approached(number: 2, x: 5.0, seq: 1))
    assert { fight_lines(approach) == [] } == !fights as reason
    assert { timers(approach) == [] } == !fights as reason
    let #(_, strike) =
      tell(
        state:,
        at_ms: 0,
        message: strike_of(number: 2, cast_id: 1, blows: [#(1, 5, 1.0)]),
      )
    assert { fight_lines(strike) == [] } == !fights as reason
    assert { timers(strike) == [] } == !fights as reason
  })
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
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(aggro)
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
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
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
    #(
      2,
      Attacks(tell: Strike(
        key:,
        from:,
        striker: _,
        offence:,
        controls: [],
        gates: [],
      )),
    ),
  ] = fights_told(ticked)
  assert from == address() && key.cast_id == start.cast_id && key.unit_id == 20
    as "the strike answers to the creature and names the cast and the struck unit; the struck player rolls"
  assert list.map(offence.blows, fn(blow) {
      #(blow.spell4_effects_id, blow.damage)
    })
    == [#(184_741, Worked(12))]
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
          armor_removed: 0,
          gates_passed: [],
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
        outcome: Landed(
          descriptions: [],
          controls: [],
          armor_removed: 0,
          gates_passed: [],
        ),
      )),
    )
  assert said(answer) == [] as "the round is closed: the late answer is dropped"
}

pub fn only_a_creatures_strike_deadline_is_recorded_and_a_maps_restart_timer_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let #(_, stunned) =
    tell(
      state:,
      at_ms: 1600,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let started = list.flatten([timers(aggro), timers(ticked), timers(stunned)])
  assert list.filter(started, fn(timer) {
      creature.is_strike_deadline(timer: timer.0)
    })
    == [#(timer_for(ticked, 1000), 1000)]
    as "of the attack tick, the strike's deadline and the state's timer a creature starts, only the deadline is one"
  assert list.filter([0, 1, 2, 3, 4, 5, 6, 7, 8], fn(number) {
      creature.is_strike_deadline(timer: step.TimerId(number))
    })
    == []
    as "a map's restart timer of a spawn numbered 0 to 8, and the creature's corpse (1), refill (2) and despawn (3) timers, are no deadline: the first is 7 + 2"
  assert creature.is_strike_deadline(timer: step.TimerId(9))
    as "generation 1's deadline is 9: the number alone cannot tell it from the map's restart timer of the spawn numbered 9, which only the process that armed it does"
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
        outcome: Landed(
          descriptions: [],
          controls: [],
          armor_removed: 0,
          gates_passed: [],
        ),
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
      "turn(kind 19, home) to 2",
      "0x638 to 2",
      "Released(7) to 2",
    ]
    as "0x90a 0 for each entry, 0x89a (C, 0), a full 0x937, the turn to home, the path home, and Released"
  assert fights_told_for(leashed)
    == [#(2, map_support.stay(count: 2), Released(unit_id: unit))]
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

/// A creature that a state holds at its leash circle, its target out of reach, stays in the
/// fight: it keeps its threat and its health, starts no walk, and its attack tick goes on.
/// It leashes at the first tick after the state ended.
pub fn a_held_creature_at_the_leash_circle_with_its_target_out_of_reach_does_not_leash_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, _) =
    tell(state:, at_ms: 0, message: moved(number: 2, x: 100.0, seq: 2))
  let #(state, t1) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let #(state, t2) = fire(state:, at_ms: 3000, timer: timer_for(t1, 1500))
  let #(state, t3) = fire(state:, at_ms: 4500, timer: timer_for(t2, 1500))
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 5600,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, held_tick) =
    fire(state:, at_ms: 6000, timer: timer_for(t3, 1500))
  assert said(held_tick) == [] && fights_told_for(held_tick) == []
    as "held at the circle the creature clears no threat, leaves no combat, restores no health and tells no release"
  let #(state, held_again) =
    fire(state:, at_ms: 7500, timer: timer_for(held_tick, 1500))
  assert said(held_again) == [] as "its attack tick goes on and does nothing"
  let #(state, ended) =
    fire(state:, at_ms: 8100, timer: timer_for(stunned, 2500))
  assert list.contains(said(ended), "0x880 to 2")
  let #(_, leashed) =
    fire(state:, at_ms: 9000, timer: timer_for(held_again, 1500))
  assert list.contains(said(leashed), "0x89a(0) to 2")
    && fights_told(leashed) == [#(2, Released(unit_id: unit))]
    as "free again, the tick that finds the target out of reach leashes"
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
    tell(
      state:,
      at_ms: 0,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the only player on the threat list is gone: the creature leashes"
  assert list.contains(said(leashed), "0x638(placed) to 5")
    as "the viewers' running path is replaced by the creature's place, home, though it is where its path began"
  let assert [CreaturePlaced(place:, at_ms:)] =
    list.filter(news_to(leashed, 5), fn(news) {
      creature_news_support.name_of(news) == "0x638(placed)"
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
  let #(state, _) =
    fire(state:, at_ms: 5500, timer: creature.chase_arrival_timer)
  let #(_, again) =
    tell(state:, at_ms: 5800, message: moved(number: 2, x: 100.0, seq: 3))
  assert said(again) == []
    as "the path ended at 5500 ms, at the circle, and the arrival timer stopped the viewers' run: a replan finds nothing to run, so nothing is sent"
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
    tell(
      state:,
      at_ms: 700,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
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
      creature_news_support.name_of(news) == "0x638(placed)"
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

/// A Battle Beast at x = 0 started for these viewers with these players in the ring of its
/// start, the step of its `Started` as the creature sends it to its map. A creature that
/// `fights` False is a spawn that does not fight.
fn started_with_ring(
  viewers viewers: List(Int),
  ring ring: List(step.RingMember),
  fights fights: Bool,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let spawn = spawn_support.battle_beast(number: 1, x: 0.0)
  started_raw(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(..spawn, combat: creature_life.Combat(..spawn.combat, fights:)),
    kind: beast_kind(),
    viewers:,
    ring:,
    armor: creature_life.NoArmor,
  )
}

pub fn a_creature_started_with_a_ring_answers_each_viewer_then_aggroes_the_ring_players_it_has_as_viewers_in_one_step_test() -> Nil {
  use <- owned_test.run(5000)
  // The map starts a respawn with the ring it reads at the start (Design run A, 4.1): the
  // creature answers each viewer's `Seen` first, as every start does, then starts one fight
  // over the players of the ring that see it. The first of them is the target
  // (`opcode.0x908`) and each other is named (`opcode.0x90a`).
  let fight_and_snapshots = fn(taken) {
    list.filter(creature_news_support.said_to_the_map(taken), fn(line) {
      string.starts_with(line, "snapshot")
      || string.starts_with(line, "0x908")
      || string.starts_with(line, "0x90a")
      || string.starts_with(line, "Threatened")
    })
  }
  list.each(
    [
      #(
        "a ring of both viewers",
        [2, 5],
        [2, 5],
        True,
        [
          "snapshot for 2",
          "snapshot for 5",
          "0x908(20, 1) to all",
          "0x90a(50, 1) to all",
          "Threatened(7, 3) to 2",
          "Threatened(7, 3) to 5",
        ],
        1,
      ),
      #(
        "a ring of a viewer and of a player who does not see it",
        [2, 5],
        [5, 9],
        True,
        [
          "snapshot for 2",
          "snapshot for 5",
          "0x908(50, 1) to all",
          "Threatened(7, 3) to 5",
        ],
        1,
      ),
      #(
        "an empty ring: the effects of a start with none",
        [2, 5],
        [],
        True,
        ["snapshot for 2", "snapshot for 5"],
        0,
      ),
      #(
        "a creature that does not fight: nobody is aggroed",
        [2, 5],
        [2, 5],
        False,
        ["snapshot for 2", "snapshot for 5"],
        0,
      ),
    ],
    fn(row) {
      let #(_, taken) =
        started_with_ring(
          viewers: row.1,
          ring: list.map(row.2, ring_member),
          fights: row.3,
        )
      assert fight_and_snapshots(taken) == row.4 as row.0
      assert list.length(support.service_timers_started(taken)) == row.5
        as { row.0 <> ": the attack tick once, and no timer for no fight" }
    },
  )
}

pub fn a_ring_at_a_start_puts_every_ring_player_into_near_and_aggroes_the_viewers_of_the_stay_it_names_in_one_fight_test() -> Nil {
  use <- owned_test.run(5000)
  // The players of the ring are near; the creature fights those of them whose stay is the
  // stay of the viewer they are (`aggro`), the first of them as target.
  let two = ring_member(2)
  let five = ring_member(5)
  list.each(
    [
      #("every ring player a viewer", [2, 5], [two, five], True, [2, 5], [2, 5]),
      #(
        "one ring player in another stay than its viewer's",
        [2, 5],
        [two, ring_member_in_stay(number: 5, stay_count: 6)],
        True,
        [2],
        [2, 5],
      ),
      #(
        "one ring player who is not a viewer",
        [2, 5],
        [two, ring_member(9)],
        True,
        [2],
        [2, 9],
      ),
      #("an empty ring", [2, 5], [], True, [], []),
      #("a creature that does not fight", [2, 5], [two, five], False, [], [2, 5]),
    ],
    fn(row) {
      let #(state, _) =
        started_with_ring(viewers: row.1, ring: row.2, fights: row.3)
      let fight = creature.fight(state:)
      assert creature_fight.threatened(state: fight)
        == set.from_list(list.map(row.4, ConnectionId))
        as { row.0 <> ": the threat list" }
      assert creature_fight.near(state: fight)
        == set.from_list(list.map(row.5, ConnectionId))
        as { row.0 <> ": the players near" }
    },
  )
  // A ring player who dies after the start is the new life's own to handle: it leaves
  // `near` and the list, its entry is erased (`opcode.0x90a`) and it is released.
  let #(state, _) =
    started_with_ring(viewers: [2, 5], ring: [two, five], fights: True)
  let #(state, died) =
    tell(state:, at_ms: 100, message: creature.PlayerDied(by: ConnectionId(2)))
  assert said(died)
    == [
      "0x90a(20, 0) to 2",
      "0x90a(20, 0) to 5",
      "0x908(50, 1) to 2",
      "0x908(50, 1) to 5",
      "turn(kind 18, unit 50) to 2",
      "turn(kind 18, unit 50) to 5",
      "Released(7) to 2",
    ]
    as "the dead player's entry is erased, the other is the target, and the dead player is released"
  assert creature_fight.threatened(state: creature.fight(state:))
    == set.from_list([ConnectionId(5)])
  assert creature_fight.near(state: creature.fight(state:))
    == set.from_list([ConnectionId(5)])
    as "the dead player is no longer near"
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
    tell(
      state:,
      at_ms: 300,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(unwatched), "Released(7) to 2")
    as "the player was still on the threat list, so the end of its watch releases it"
}

pub fn a_near_player_told_withdrew_is_not_aggroed_at_the_home_timer_and_one_approached_again_is_test() -> Nil {
  use <- owned_test.run(5000)
  near_player_is_not_aggroed_and_one_approached_again_is(
    gone: creature.Withdrew(by: ConnectionId(5)),
  )
}

/// Player 5 comes near a creature and `gone` tells the creature it is not near any more:
/// the home timer does not aggro it, and an `Approached` after `gone` does.
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

pub fn a_creature_whose_strike_is_refused_dead_does_not_aggro_the_body_at_its_home_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, key) = struck_once_among(viewers: [2, 5])
  let refused =
    creature.StrikeAnswered(answered: Answered(
      key:,
      outcome: Refused(why: strike_tell.Dead),
    ))
  let #(state, answered) = tell(state:, at_ms: 1600, message: refused)
  let #(_, at_home) = fire(state:, at_ms: 1600, timer: timer_for(answered, 0))
  assert !aggroes(at_home) as "home timer: the refusing player is not aggroed"
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
      "turn(kind 18, unit 20) to 2",
      "turn(kind 18, unit 20) to 5",
      "Released(7) to 5",
    ]
    as "opcode.0x90a: a threat of 0 erases the body's entry; opcode.0x908 names player 2, whom the creature turns to; the body is told Released"
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
      "turn(kind 19, spawn facing) to 2",
      "Released(7) to 2",
    ]
    as "the leash of a creature standing at its spawn: the entry erased, out of combat, full health (52), no path, the turn to the spawn's facing (it is home), the body told Released"
  let #(_, at_home) = fire(state:, at_ms: 100, timer: timer_for(died, 0))
  assert said(at_home) == []
    as "at home nothing is aggroed: the body is not near"
}

pub fn a_near_player_told_player_died_is_not_aggroed_at_the_home_timer_and_one_approached_again_is_test() -> Nil {
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
    tell(
      state:,
      at_ms: 200,
      message: creature_news_support.unseen(by: ConnectionId(5)),
    )
  assert said(unwatched)
    == [
      "0x90a(50, 0) to 2",
      "0x908(20, 1) to 2",
      "turn(kind 18, unit 20) to 2",
      "Released(7) to 5",
    ]
    as "player 5 (threat 3, the target) leaves the list, its entry erased (0x90a 0); player 2 is the target again, and the creature turns to it"
  // The map's Unseen of the same viewer ends its sight: the fight drops the entry as for an
  // Unwatched, the creature sends no 0x355 (the map tells the viewer), and the release is one
  // tell to the player through the map, for the stay the entry held.
  let #(unseen_state, unseen) =
    tell_raw(
      state:,
      at_ms: 200,
      message: creature.Unseen(
        by: ConnectionId(5),
        generation: generation.first(),
      ),
    )
  assert creature_news_support.said_to_the_map(unseen)
    == [
      "0x90a(50, 0) to all",
      "0x908(20, 1) to all",
      "turn(kind 18, unit 20) to all",
      "Released(7) to 5",
    ]
    as "the erased entry and the new target are news for every viewer, and player 5 is released through the map: no 0x355 and no news to a connection"
  assert creature_fight.threatened(state: creature.fight(state: unseen_state))
    == set.from_list([ConnectionId(2)])
    as "player 5's threat entry went with its sight"
  // The same player sees the creature again from a new sight, in a new stay: the earlier
  // entry's threat is not held.
  let #(back_state, _) =
    tell(
      state: unseen_state,
      at_ms: 300,
      message: creature.Seen(
        by: ConnectionId(5),
        stay: map_support.stay(count: 6),
        generation: generation.after(generation: generation.first()),
      ),
    )
  assert creature_fight.threatened(state: creature.fight(state: back_state))
    == set.from_list([ConnectionId(2)])
    as "with the player back as a viewer under the new generation, the old entry's threat is not held"
  // The creature holds the viewer under the new generation, with a threat entry from a
  // strike in the stay it was seen in: an Unseen of the sight before it is not this
  // viewer's end, and the Unseen of the sight it holds is.
  let later = generation.after(generation: generation.first())
  let #(held, _) =
    tell(
      state: unseen_state,
      at_ms: 300,
      message: creature.Seen(
        by: ConnectionId(5),
        stay: map_support.stay(count: 5),
        generation: later,
      ),
    )
  let #(held, _) =
    tell(
      state: held,
      at_ms: 400,
      message: strike_of(number: 5, cast_id: 3, blows: [#(1, 3, 1.0)]),
    )
  assert creature_fight.threatened(state: creature.fight(state: held))
    == set.from_list([ConnectionId(2), ConnectionId(5)])
    as "the viewer seen under the new generation threatens again"
  let #(stale, _) =
    tell(
      state: held,
      at_ms: 500,
      message: creature.Unseen(
        by: ConnectionId(5),
        generation: generation.first(),
      ),
    )
  assert creature_fight.threatened(state: creature.fight(state: stale))
    == set.from_list([ConnectionId(2), ConnectionId(5)])
    as "an Unseen of the earlier sight finds the viewer held under a later generation and changes nothing"
  let #(ended, _) =
    tell(
      state: stale,
      at_ms: 600,
      message: creature.Unseen(by: ConnectionId(5), generation: later),
    )
  assert creature_fight.threatened(state: creature.fight(state: ended))
    == set.from_list([ConnectionId(2)])
    as "the Unseen of the generation the creature holds ends the viewer and its threat entry"
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
      "Landed to 2", "KillCredit to 2", "0x937(0) to 2", "0x937(0) to 5",
      "0x88c to 2", "0x88c to 5", "turn(kind 14) to 2", "turn(kind 14) to 5",
      "0x89a(0) to 2", "0x89a(0) to 5", "Released(7) to 2", "Released(7) to 5",
    ]
    as "death.combat_flag: 0x89a (C, 0) and Released to everyone on the threat list, after the turn that freezes the corpse's facing; the credit goes to the killing blow's connection only, after its answer"
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
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  let assert [CreatureAppeared(place:, ..)] = news_to(watched, 9)
  assert x_of(place) == 10.0
    as "it fell 1 s into its run, 10 units along: the corpse lies there, not where the run would end"
  let #(_, expired) = fire(state:, at_ms: 61_000, timer: corpse)
  assert list.map(news_to(expired, 9), creature_news_support.name_of)
    == ["0x355"]
    as "the viewer that saw the corpse is sent its removal at the expiry, and no 0x262: the next life at the spawn is the map's (death.creature_respawn)"
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
              message: creature_news_support.seen(
                by: ConnectionId(n),
                stay: map_support.stay(count: n),
              ),
            )
          #(state, timers(taken))
        }
        Unsee(n) -> {
          let #(state, taken) =
            tell(
              state:,
              at_ms:,
              message: creature_news_support.unseen(by: ConnectionId(n)),
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
  // Player 5's strike was on its way when the map's Unseen of it arrived.
  let #(state, raw) =
    tell_raw(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 1.0)]),
    )
  let taken = creature_news_support.at_each_player(state:, taken: raw)
  assert said(taken) == ["Landed to 5", "0x937(42) to 2"]
    as "the damage applies: 52 - 10, shown to the viewer"
  assert creature_fight.threatened(state: creature.fight(state:)) == set.new()
    as "no threat for a connection that does not see the creature, so no fight starts"
  assert creature_news_support.said_to_the_map(raw)
    == ["answer to 5", "0x937(42) to all"]
    as "the answer goes to the striker through the map, and the health is one news for every viewer"
  // A connection the map's Seen names is a viewer: its strike threatens the creature.
  let #(seen, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: creature.Seen(
        by: ConnectionId(5),
        stay: map_support.stay(count: 5),
        generation: generation.first(),
      ),
    )
  let #(seen, _) =
    tell(
      state: seen,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 2, blows: [#(1, 10, 1.0)]),
    )
  assert creature_fight.threatened(state: creature.fight(state: seen))
    == set.from_list([ConnectionId(5)])
    as "threat for a connection the map's Seen named"
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
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "turn(kind 18, unit 20)", "0x638"]
    as "the viewer's client shows what the others' do: the creature in combat, its target, the turn to it, and its run"
  let assert [
    _,
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
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, watched) =
    tell(
      state:,
      at_ms: 1500,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "turn(kind 19, home)", "0x638"]
    as "out of combat: no 0x89a or 0x908, only the turn to home and the rest of the walk home"
  let assert [_, _, CreatureMoved(path: Running(from:, to:, ..))] =
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
    tell(
      state:,
      at_ms: 200,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert said(secondary)
    == [
      "0x90a(20, 0) to 5",
      "0x90a(20, 0) to 6",
      "Released(7) to 2",
    ]
    as "opcode.0x90a: a threat of 0 erases player 2's entry for the viewers; the target stays"
  let #(_, top) =
    tell(
      state:,
      at_ms: 200,
      message: creature_news_support.unseen(by: ConnectionId(5)),
    )
  assert said(top)
    == [
      "0x90a(50, 0) to 2", "0x90a(50, 0) to 6", "0x908(20, 1) to 2",
      "0x908(20, 1) to 6", "turn(kind 18, unit 20) to 2",
      "turn(kind 18, unit 20) to 6", "Released(7) to 5",
    ]
    as "the top entry is erased too, and the next is named the target and turned to"
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
      armor_removed: 0,
      gates_passed: [],
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
    tell(
      state:,
      at_ms: 500,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
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
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
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
    tell(
      state:,
      at_ms: 100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(state, _) = fire(state:, at_ms: 200, timer: timer_for(leashed, 100))
  let #(state, _) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.seen(
        by: ConnectionId(2),
        stay: stay.next(map_support.stay(count: 2)),
      ),
    )
  let #(_, again) =
    tell(
      state:,
      at_ms: 5000,
      message: creature.Approached(member: step.RingMember(
        by: ConnectionId(2),
        unit_id: 21,
        place: map_spawn_support.at(5.0),
        seq: 7,
        stay: stay.next(map_support.stay(count: 2)),
        hit_radius: place_support.player_hit_radius,
      )),
    )
  assert list.contains(said(again), "0x908(21, 1) to 2")
    as "the equal sequence number is taken, with the new unit 21"
  assert fights_told_for(again)
    == [
      #(
        2,
        stay.next(map_support.stay(count: 2)),
        Threatened(unit_id: unit, life:),
      ),
    ]
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
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: creature_news_support.seen(
        by: ConnectionId(2),
        stay: stay.next(map_support.stay(count: 2)),
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
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert fights_told_for(unwatched)
    == [#(2, map_support.stay(count: 2), Released(unit_id: unit))]
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
      creature_news_support.name_of(news) == "0x638(placed)"
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
    tell(
      state:,
      at_ms: 600,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
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

pub fn a_caster_ending_its_cast_ends_its_states_at_once_and_the_creature_acts_unless_another_players_state_holds_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 stands 5 units off, within reach 8. Player 2's cast 1 stuns the creature at 100
  // (until 2600); in the second case player 5's cast 1, the same cast id of another caster,
  // stuns it at 200.
  let stunned_by = fn(others: List(Int)) {
    let #(state, aggro) =
      tell(
        state: beast(viewers: [2, 5]),
        at_ms: 0,
        message: approached(number: 2, x: 5.0, seq: 1),
      )
    let #(state, first) =
      tell(
        state:,
        at_ms: 100,
        message: controlling(number: 2, cast_id: 1, controls: [
          crowd_control_support.stagger_stun(instance_id: 28_673),
        ]),
      )
    let state =
      list.fold(others, state, fn(state, number) {
        tell(
          state:,
          at_ms: 200,
          message: controlling(number:, cast_id: 1, controls: [
            crowd_control_support.stagger_stun(instance_id: 49_153),
          ]),
        ).0
      })
    #(state, timer_for(aggro, 1500), timer_for(first, 2500))
  }
  let #(state, first_tick, state_ends) = stunned_by([])
  let #(state, ended) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.ControlsEnd(by: ConnectionId(2), cast_id: 1),
    )
  let over =
    unit_news.CrowdControlEnded(
      state: crowd_control_state.Stun,
      cast_id: 1,
      instance_id: 28_673,
    )
  assert state_news(ended, 2) == [over] && state_news(ended, 5) == [over]
    as "player 2's state ends at once with its 0x880 for each viewer, before its own 2500 ms"
  assert !creature.controlled(state:) as "and the creature holds no state"
  assert list.contains(timers_cancelled(ended), state_ends)
    as "and its timer is cancelled"
  let #(state, late) = fire(state:, at_ms: 2600, timer: state_ends)
  assert support.effects_of(late) == []
    as "a timer already waiting in the mailbox writes nothing"
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: first_tick)
  assert list.contains(said(ticked), "0x7ff to 2")
    as "the creature held by nothing else strikes at its next tick"
  let #(state, first_tick, _) = stunned_by([5])
  let #(state, ended) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.ControlsEnd(by: ConnectionId(2), cast_id: 1),
    )
  assert state_news(ended, 2) == [over] && state_news(ended, 5) == [over]
    as "only player 2's state ends, with its 0x880 for each viewer"
  assert creature.controlled(state:)
    as "player 5's cast 1 holds its own state, though its cast id is the same"
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: first_tick)
  assert !list.contains(said(ticked), "0x7ff to 2")
    as "the creature is still stunned and strikes nothing"
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
) -> List(unit_news.News) {
  list.filter(news_to(taken, number), fn(news) {
    list.contains(["0x87f", "0x880"], creature_news_support.name_of(news))
  })
}

/// The states the step's answer to the caster says landed.
fn landed_in(
  taken: ServiceStep(creature.Outgoing),
) -> List(strike_tell.ControlLanded) {
  list.flat_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.Relay(
        payload: relay.Struck(answered: Answered(
          outcome: Landed(controls:, ..),
          ..,
        )),
        ..,
      ) -> controls
      creature.Relay(payload: relay.Struck(..), ..)
      | creature.Relay(payload: relay.Fight(..), ..)
      | creature.Relay(payload: relay.KillCredit(..), ..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> []
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
    unit_news.CrowdControlApplied(
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
        interrupted: None,
      ),
    ]
    as "the answer names it, with the time the creature holds it until: its arrival, 10000 + 1000, plus 166 plus 3000"
  assert creature.controlled(state:)
  assert control_timers(taken) == [#(step.TimerId(11), 3166)]
    as "one timer for the state, 166 + 3000 from the tell; ids 6n + 4 from 10"
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
  assert list.map(state_news(taken, 2), creature_news_support.name_of)
    == ["0x87f"]
    as "no 0x880 comes with the strike: the state ends only at its timer, 3166 ms on (Kick: 166 + 3000)"
  let #(state, ended) = fire(state:, at_ms: 4166, timer: timer_for(taken, 3166))
  let over =
    unit_news.CrowdControlEnded(
      state: crowd_control_state.Knockdown,
      cast_id: 77,
      instance_id: 28_673,
    )
  assert state_news(ended, 2) == [over] && state_news(ended, 5) == [over]
    as "0x880 names the unit's state, the strike's cast and the go's instance id"
  assert !creature.controlled(state:)
  let #(_, again) = fire(state:, at_ms: 4200, timer: step.TimerId(11))
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
    == [#(step.TimerId(11), 2500), #(step.TimerId(18), 2500)]
    as "two 0x87f and a timer for each state"
  let #(state, first) = fire(state:, at_ms: 3500, timer: step.TimerId(11))
  assert list.map(state_news(first, 2), creature_news_support.name_of)
    == ["0x880"]
    && creature.controlled(state:)
    as "one 0x880 for the first, and the second still holds"
  let #(state, second) = fire(state:, at_ms: 3500, timer: step.TimerId(18))
  assert list.map(state_news(second, 2), creature_news_support.name_of)
    == ["0x880"]
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
  assert list.map(state_news(first, 5), creature_news_support.name_of)
    == ["0x87f"]
    && list.map(state_news(second, 5), creature_news_support.name_of)
    == ["0x87f"]
  let #(state, one) = fire(state:, at_ms: 3500, timer: step.TimerId(11))
  assert list.map(state_news(one, 5), creature_news_support.name_of)
    == ["0x880"]
    && creature.controlled(state:)
  let #(state, two) = fire(state:, at_ms: 4000, timer: step.TimerId(18))
  assert list.map(state_news(two, 5), creature_news_support.name_of)
    == ["0x880"]
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
  assert list.contains(timers_cancelled(killed), step.TimerId(11))
    as "the state's timer is cancelled"
  assert !creature.controlled(state:)
  let #(_, late) = fire(state:, at_ms: 3500, timer: step.TimerId(11))
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
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  let names = list.map(news_to(arrived, 9), creature_news_support.name_of)
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
          hit_radius: place_support.player_hit_radius,
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
) -> List(unit_news.News) {
  let armors =
    list.map([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn(armor) {
      unit_news.InterruptArmor(armor:)
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
  assert armor_news(first, 2) == [unit_news.InterruptArmor(armor: 1)]
    && armor_news(first, 5) == [unit_news.InterruptArmor(armor: 1)]
    as "it destroys the row's 1 point and every viewer is told the 1 left"
  assert !creature.controlled(state:)
  let #(state, second) =
    tell(
      state:,
      at_ms: 2000,
      message: stunning(from: 2, cast_id: 2, instance_id: 28_674),
    )
  assert landed_in(second) == []
    && armor_news(second, 2) == [unit_news.InterruptArmor(armor: 0)]
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
        interrupted: None,
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
  assert armor_news(taken, 2) == [unit_news.InterruptArmor(armor: 0)]
    && landed_in(taken) == []
    as "2 points of rows on 1 point of armor leave 0, and none of the strike's states lands"
}

/// The armor the strike's answer says it took off the creature.
fn armor_taken(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.flat_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.Relay(
        payload: relay.Struck(answered: Answered(
          outcome: Landed(armor_removed:, ..),
          ..,
        )),
        ..,
      ) -> [armor_removed]
      creature.Relay(payload: relay.Struck(..), ..)
      | creature.Relay(payload: relay.Fight(..), ..)
      | creature.Relay(payload: relay.KillCredit(..), ..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> []
    }
  })
}

pub fn the_answer_names_the_armor_the_strike_took_never_more_than_it_had_test() -> Nil {
  use <- owned_test.run(5000)
  let stun = crowd_control_support.stagger_stun(instance_id: 28_673)
  let strike = fn(armor) {
    let #(_, taken) =
      tell(
        state: armored(armor:),
        at_ms: 1000,
        message: controlling(number: 2, cast_id: 1, controls: [stun, stun, stun]),
      )
    armor_taken(taken)
  }
  assert strike(creature_life.Armor(points: 2)) == [2]
    as "rows destroying 3 on armor 2: the answer names the 2 it had (the 0x938 shows 0 left)"
  assert strike(creature_life.Armor(points: 5)) == [3]
    as "rows destroying 3 on armor 5: the 3 the rows name"
  assert strike(creature_life.NoArmor) == [0]
    as "a creature with no armor lost none"
  assert strike(creature_life.InfiniteArmor) == [0]
    as "infinite armor loses none"
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
  assert armor_news(refilled, 2) == [unit_news.InterruptArmor(armor: 2)]
    && armor_news(refilled, 5) == [unit_news.InterruptArmor(armor: 2)]
    as "armor is back at its maximum 2, told to every viewer"
  let #(_, again) =
    tell(
      state:,
      at_ms: 16_000,
      message: stunning(from: 2, cast_id: 3, instance_id: 28_675),
    )
  assert landed_in(again) == []
    && armor_news(again, 2) == [unit_news.InterruptArmor(armor: 1)]
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

pub fn a_creature_killed_with_worn_armor_cancels_its_refill_and_shows_its_full_armor_at_the_body_test() -> Nil {
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
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
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
        message: creature_news_support.seen(
          by: ConnectionId(9),
          stay: map_support.stay(count: 9),
        ),
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
  assert armor_news(worn, 2) == [unit_news.InterruptArmor(armor: 0)]
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
  assert armor_news(refilled, 2) == [unit_news.InterruptArmor(armor: 2)]
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
  assert armor_news(next, 2) == [unit_news.InterruptArmor(armor: 1)]
    as "the armor was left at 2"
}

// ---- a property modifier on the creature changes how it fights ----
//
// Expected values come from these places: the chase speed is Creature2DisplayInfo
// runLand 10.0 times Move Speed Multiplier (property 100), which the client
// computes the same way for any unit (`0x1405b45e0`); a change x * multiplier +
// flat is the row's (`Spell4Effects.effectType.11.change`); the blow of effect
// 184741 is 12 (`Spell4Effects.184741`) and a creature's damage is multiplied by
// DamageDealtMultiplier 140 + the effect's damageType, which is 1 (Physical), so
// 141 (`UnitProperty2.damage_heal_multipliers`, `0x140565600`).

/// A row that multiplies a property by `factor`: x becomes x * factor.
fn scaled_by(property property: Int, factor factor: Float) -> Modifier {
  Change(
    property: UnitProperty2Id(property),
    mode: 1,
    multiplier: factor,
    flat: 0.0,
    per_level: 0.0,
  )
}

fn modifier_start(
  cast_id cast_id: Int,
  modifier modifier: Modifier,
) -> creature.Message {
  creature.ModifierStarts(
    by: ConnectionId(9),
    source: cast_support.source_of(cast_id:, effect_id: 1900 + cast_id),
    modifier:,
  )
}

pub fn move_speed_modifier_slows_chase_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.5),
      ),
    )
  let #(_, aggro) =
    tell(state:, at_ms: 100, message: approached(number: 2, x: 30.0, seq: 1))
  let assert Running(from:, to:, speed:, ..) = path_sent(aggro)
  assert x_of(from) == 0.0 && x_of(to) == 26.0
  assert speed == 5.0 as "runLand 10.0 x Move Speed Multiplier 0.5"
}

pub fn move_speed_change_mid_chase_replans_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let assert Running(speed: 10.0, ..) = path_sent(aggro)
  // 1 s in, the creature has run 10 of the 26 units to its path's end.
  let #(state, slowed) =
    tell(
      state:,
      at_ms: 1000,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.5),
      ),
    )
  assert said(slowed)
    == ["other to 2", "other to 5", "0x638 to 2", "0x638 to 5"]
    as "the property first, then the new path"
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(slowed)
  assert x_of(from) == 10.0
    && x_of(to) == 26.0
    && started_ms == start_ms + 1000
    && speed == 5.0
    as "from where the creature stands, to the same end, at the new speed"
  // 2 s in it has run 5 more units at 5.0; the end of the modifier speeds it up.
  let #(state, back) =
    tell(
      state:,
      at_ms: 2000,
      message: creature.ModifierEnds(cast_support.source_of(
        cast_id: 1,
        effect_id: 1901,
      )),
    )
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(back)
  assert x_of(from) == 15.0
    && x_of(to) == 26.0
    && started_ms == start_ms + 2000
    && speed == 10.0
    as "the end replans at the base speed from where it stands"
  // A change to a property the chase does not read sends no path.
  let #(state, other) =
    tell(
      state:,
      at_ms: 2100,
      message: modifier_start(
        cast_id: 2,
        modifier: scaled_by(property: 127, factor: 2.0),
      ),
    )
  assert said(other) == ["other to 2", "other to 5"]
    as "no speed change, no new path"
  // The path ended at 2 s + 11 / 10 = 3.1 s: a speed change after it sends none.
  let #(_, after) =
    tell(
      state:,
      at_ms: 5000,
      message: modifier_start(
        cast_id: 3,
        modifier: scaled_by(property: 100, factor: 2.0),
      ),
    )
  assert said(after) == ["other to 2", "other to 5"]
    as "a creature that stands has no path to replan"
}

pub fn move_speed_change_while_walking_home_replans_the_walk_and_its_arrival_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  // The fighter leaves sight 1 s into the chase: the creature, at 10, walks home at
  // 10 a second and is there at 2 s.
  let #(state, unwatched) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let home = timer_for(unwatched, 1000)
  // Half a second into the walk it has 5 left; at half the speed that takes 1 s.
  let #(state, slowed) =
    tell(
      state:,
      at_ms: 1500,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.5),
      ),
    )
  assert list.map(news_to(slowed, 5), creature_news_support.name_of)
    == ["other", "0x638"]
    as "the property, then the new walk"
  let assert [CreatureMoved(path: Running(from:, to:, started_ms:, speed:, ..))] =
    list.filter(news_to(slowed, 5), fn(news) {
      creature_news_support.name_of(news) == "0x638"
    })
    as "one path to the viewer that stayed"
  assert x_of(from) == 5.0
    && x_of(to) == 0.0
    && started_ms == start_ms + 1500
    && speed == 5.0
    as "from where the creature stands, to home, at the new speed"
  assert timers_cancelled(slowed) == [home]
    as "the arrival the old speed gave is cancelled"
  let assert [#(arrival, 1000)] = timers(slowed)
    as "and a new one starts for the 1 s the 5 units take at 5.0"
  assert arrival != home
  let #(state, stale) = fire(state:, at_ms: 2000, timer: home)
  let #(state, still_walking) =
    tell(
      state:,
      at_ms: 2100,
      message: strike_of(number: 5, cast_id: 2, blows: [#(1, 5, 1.0)]),
    )
  assert said(stale) == [] && said(still_walking) == ["Refused(Returning) to 5"]
    as "the old arrival, fired late, does nothing: the creature is still walking"
  let #(state, arrived) = fire(state:, at_ms: 2500, timer: arrival)
  assert said(arrived)
    == ["0x638(placed) to 5", "turn(kind 19, spawn facing) to 5"]
    as "home: the walk's stop, then the creature takes the facing of its spawn"
  let #(_, struck) =
    tell(
      state:,
      at_ms: 2600,
      message: strike_of(number: 5, cast_id: 3, blows: [#(1, 5, 1.0)]),
    )
  assert !list.contains(said(struck), "Refused(Returning) to 5")
    as "the new arrival ends the return at 2.5 s"
}

// A creature whose run speed is 0 or below stands where it is. The 0 is a root: a property
// modifier on property 100 with multiplier 0 (Spell4Effects 1781); the negative speed is
// what stacked negative flats leave (Spell4Effects 192472, 213219, 5181 and 230841 reach
// -0.1 on property 100). What a negative speed does is the server's choice: no client fact
// covers it, so it is read as 0.

/// A modifier that leaves property 100 at -0.1: x becomes x - 1.1 from 1.0.
fn flats_to_negative_move_speed() -> Modifier {
  Change(
    property: UnitProperty2Id(100),
    mode: 1,
    multiplier: 1.0,
    flat: -1.1,
    per_level: 0.0,
  )
}

/// No 0x638 of any kind: the creature neither runs nor is placed.
fn sends_no_path(taken: ServiceStep(creature.Outgoing)) -> Bool {
  !list.any(said(taken), fn(line) { string.starts_with(line, "0x638") })
}

/// The creature's x at `at_ms` after the start.
fn stands_at(state state: State, at_ms at_ms: Int) -> Float {
  x_of(creature_fight.place_at(
    state: creature.fight(state:),
    now_ms: start_ms + at_ms,
  ))
}

pub fn chase_with_zero_run_speed_stands_still_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  let #(state, aggro) =
    tell(state:, at_ms: 100, message: approached(number: 2, x: 30.0, seq: 1))
  assert sends_no_path(aggro) as "no Running path starts"
  // The tick 1.5 s later and one at 10 s, long past the 2.6 s the 26 units take at 10.
  let #(state, tick) = fire(state:, at_ms: 1600, timer: timer_for(aggro, 1500))
  assert sends_no_path(tick) as "the attack tick starts none either"
  let #(state, late) = fire(state:, at_ms: 10_000, timer: timer_for(tick, 1500))
  assert sends_no_path(late)
  assert stands_at(state:, at_ms: 10_000) == 0.0
    as "where the creature stood, after the time it would have arrived"
}

pub fn walk_home_with_zero_run_speed_stands_still_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  // 1 s into the chase the creature is at 10, and a root takes its run speed to 0.
  let #(state, rooted) =
    tell(
      state:,
      at_ms: 1000,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  assert list.contains(said(rooted), "0x638(placed) to 5")
    as "the run in progress stops where the creature stands"
  // The fighter leaves sight: the creature leashes, with no walk to start.
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x89a(0) to 5")
    && sends_no_path(leashed)
    && timers(leashed) == []
    as "the leash goes on, the rooted creature starts no walk and no arrival timer"
  assert stands_at(state:, at_ms: 20_000) == 10.0
    as "where it stood, after the time the walk would have taken"
  let #(_, refused) =
    tell(
      state:,
      at_ms: 20_000,
      message: strike_of(number: 5, cast_id: 2, blows: [#(1, 5, 1.0)]),
    )
  assert said(refused) == ["Refused(Returning) to 5"]
    as "it has not arrived: it still takes no strike"
}

pub fn negative_run_speed_stands_still_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: modifier_start(
        cast_id: 1,
        modifier: flats_to_negative_move_speed(),
      ),
    )
  let #(state, aggro) =
    tell(state:, at_ms: 100, message: approached(number: 2, x: 30.0, seq: 1))
  assert sends_no_path(aggro) as "a chase at a speed of -1.0 starts no path"
  assert stands_at(state:, at_ms: 10_000) == 0.0
  // The same from 10 units out: the walk home, at a speed below 0, starts none.
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, slowed) =
    tell(
      state:,
      at_ms: 1000,
      message: modifier_start(
        cast_id: 1,
        modifier: flats_to_negative_move_speed(),
      ),
    )
  assert list.contains(said(slowed), "0x638(placed) to 5")
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert sends_no_path(leashed) && timers(leashed) == []
  assert stands_at(state:, at_ms: 20_000) == 10.0
}

pub fn run_speed_restored_moves_again_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 1000,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  let #(_, back) =
    tell(
      state:,
      at_ms: 3000,
      message: creature.ModifierEnds(cast_support.source_of(
        cast_id: 1,
        effect_id: 1901,
      )),
    )
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(back)
  assert x_of(from) == 10.0
    && x_of(to) == 26.0
    && started_ms == start_ms + 3000
    && speed == 10.0
    as "the chase starts from where the creature stood, toward 30 less 0.5 x reach 8"
}

pub fn run_speed_restored_walks_home_again_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 1000,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(state, back) =
    tell(
      state:,
      at_ms: 3000,
      message: creature.ModifierEnds(cast_support.source_of(
        cast_id: 1,
        effect_id: 1901,
      )),
    )
  let assert [CreatureMoved(path: Running(from:, to:, started_ms:, speed:, ..))] =
    list.filter(news_to(back, 5), fn(news) {
      creature_news_support.name_of(news) == "0x638"
    })
    as "the walk home starts"
  assert x_of(from) == 10.0
    && x_of(to) == 0.0
    && started_ms == start_ms + 3000
    && speed == 10.0
    as "from where the creature stood, to home, at the base speed"
  let assert [#(arrival, 1000)] = timers(back)
    as "its arrival is the 1 s the 10 units take"
  let #(state, arrived) = fire(state:, at_ms: 4000, timer: arrival)
  assert said(arrived)
    == ["0x638(placed) to 5", "turn(kind 19, spawn facing) to 5"]
    as "home: the walk's stop, then the creature takes the facing of its spawn"
  assert stands_at(state:, at_ms: 4000) == 0.0
}

// A creature that does not run and the leash. A unit that cannot move leashes by the
// turret rule: it never walks to the circle, so it is at its leash when its target is
// beyond the leash range from home. A creature whose run speed is not above 0 does the
// same (a server's choice: it too never walks to the circle; Creature2 54402 spawns with
// property 100 overridden to 0). A rooted creature that stands away from home holds
// instead of leashing, as one held by a state does (a server's choice): it could not walk
// home, so it would be Returning with nothing to end it.

pub fn creature_that_cannot_run_leashes_by_the_turret_rule_test() -> Nil {
  use <- owned_test.run(5000)
  // Root from the start: the Beast stands at home, and the target is out of reach.
  let rooted = fn(x) {
    let #(state, _) =
      tell(
        state: beast(viewers: [2, 5]),
        at_ms: 0,
        message: modifier_start(
          cast_id: 1,
          modifier: scaled_by(property: 100, factor: 0.0),
        ),
      )
    tell(state:, at_ms: 100, message: approached(number: 2, x:, seq: 1))
  }
  // 100 off is beyond the leash range 55.
  let #(state, aggro) = rooted(100.0)
  let #(_, ticked) = fire(state:, at_ms: 1600, timer: timer_for(aggro, 1500))
  assert list.contains(said(ticked), "0x89a(0) to 5")
    as "the target is beyond the leash range from home: the creature leashes"
  // A target within the leash range, out of reach: it stays in the fight.
  let #(state, aggro) = rooted(30.0)
  let #(_, ticked) = fire(state:, at_ms: 1600, timer: timer_for(aggro, 1500))
  assert !list.contains(said(ticked), "0x89a(0) to 5")
    as "a target within the leash range does not end the fight"
}

pub fn rooted_creature_leashing_at_home_rests_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  let #(state, aggro) =
    tell(state:, at_ms: 100, message: approached(number: 2, x: 100.0, seq: 1))
  let #(state, leashed) =
    fire(state:, at_ms: 1600, timer: timer_for(aggro, 1500))
  assert sends_no_path(leashed) as "it stands at home: no walk"
  let assert [#(arrival, 0)] = timers(leashed)
    as "its arrival at home is now, since it is there"
  let #(state, struck) =
    tell(
      state:,
      at_ms: 1600,
      message: strike_of(number: 2, cast_id: 2, blows: [#(1, 5, 1.0)]),
    )
  assert said(struck) == ["Refused(Returning) to 2"]
    as "before its arrival it takes no strike"
  let #(state, arrived) = fire(state:, at_ms: 1600, timer: arrival)
  assert list.contains(said(arrived), "0x89a(1) to 2")
    as "home, it aggroes the player it sees again, as any arrival does"
  let #(_, struck) =
    tell(
      state:,
      at_ms: 1700,
      message: strike_of(number: 2, cast_id: 3, blows: [#(1, 5, 1.0)]),
    )
  assert !list.contains(said(struck), "Refused(Returning) to 2")
    as "home again, it takes a strike"
}

pub fn rooted_creature_at_the_circle_does_not_leash_test() -> Nil {
  use <- owned_test.run(5000)
  // The target is 100 off: the chase runs 10 units a second to the circle at 55.
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 100.0, seq: 1),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 5600,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  // The tick at 6 s finds the creature at the circle, rooted.
  let #(state, held) = fire(state:, at_ms: 6000, timer: timer_for(aggro, 1500))
  assert !list.contains(said(held), "0x89a(0) to 5")
    as "it holds at the circle and keeps fighting"
  let #(state, held) = fire(state:, at_ms: 7500, timer: timer_for(held, 1500))
  assert !list.contains(said(held), "0x89a(0) to 5")
  // Its speed is back: the speed's return starts no path at the circle, and the next
  // tick leashes and walks home.
  let #(state, back) =
    tell(
      state:,
      at_ms: 8000,
      message: creature.ModifierEnds(cast_support.source_of(
        cast_id: 1,
        effect_id: 1901,
      )),
    )
  assert sends_no_path(back)
  let #(_, leashed) = fire(state:, at_ms: 9000, timer: timer_for(held, 1500))
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "restored, it leashes as before"
  let assert Running(from:, to:, ..) = path_sent(leashed)
  assert x_of(from) == 55.0 && x_of(to) == 0.0
}

pub fn speed_restored_while_held_stays_until_control_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, landed) =
    beast_holding(held: crowd_control_state.Root, x: 30.0)
  // The landing's caster stands at 2, in reach: the target moves out again.
  let #(state, _) =
    tell(state:, at_ms: 550, message: moved(number: 2, x: 30.0, seq: 2))
  let #(state, rooted) =
    tell(
      state:,
      at_ms: 600,
      message: modifier_start(
        cast_id: 2,
        modifier: scaled_by(property: 100, factor: 0.0),
      ),
    )
  assert sends_no_path(rooted)
  let #(state, restored) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.ModifierEnds(cast_support.source_of(
        cast_id: 2,
        effect_id: 1902,
      )),
    )
  assert sends_no_path(restored)
    as "the speed is back, but the Root state still holds the creature"
  let #(_, ended) = fire(state:, at_ms: 3000, timer: timer_for(landed, 2500))
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(ended)
  assert x_of(from) == 5.0
    && x_of(to) == 26.0
    && started_ms == start_ms + 3000
    && speed == 10.0
    as "the end of the state starts the chase from where the creature stood"
}

pub fn creature_blow_uses_damage_dealt_multiplier_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 141, factor: 2.0),
      ),
    )
  let #(state, aggro) =
    tell(state:, at_ms: 0, message: approached(number: 2, x: 5.0, seq: 1))
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [#(2, Attacks(tell: Strike(offence:, ..)))] = fights_told(ticked)
  assert list.map(offence.blows, fn(blow) {
      #(blow.spell4_effects_id, blow.damage)
    })
    == [#(184_741, Worked(24))]
    as "effect 184741 is 12 and the Physical multiplier (141) is 2.0"
}

// ---- the Sim-Turret's charge (Spell4 85469, castTime 8000) ----
//
// The turret is Creature2 73494 as the content load starts it, at the origin facing
// -z (yaw 0, `movement_command.kind_14.facing`), with its kind's attack every 3000 ms
// (migration 0029). Its charge's rectangle is TelegraphDamage 16212: 3 wide and 30 long
// from the caster along its facing, and a player's hit radius is 1.2, so a player is
// struck when its centre is within 1.5 + 1.2 = 2.7 aside of the line and within 30 +
// 1.2 ahead.

/// The Exile Sim-Turret at the origin as migration 0029 leaves it, started for these viewers,
/// `Started` taken.
fn turret(viewers viewers: List(Int)) -> State {
  turret_in(
    kinds: spawn_support.turret_kinds(),
    viewers:,
    armor: creature_life.NoArmor,
  ).0
}

/// The same turret as migration 0030 leaves it, guarded by Spell4 85474 and opened by Spell4
/// 85472, with the step of its `Started`.
fn guarded_turret(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  turret_in(
    kinds: spawn_support.guarded_turret_kinds(),
    viewers:,
    armor: creature_life.NoArmor,
  )
}

/// The Exile Sim-Turret of these kinds and this Interrupt Armor at the origin, started for
/// these viewers: the state and the step of its `Started`.
fn turret_in(
  kinds kinds: Kinds,
  viewers viewers: List(Int),
  armor armor: creature_life.InterruptArmor,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let assert Ok(kind) = dict.get(kinds.by_creature, 73_494)
    as "migrations 0029 and 0030 give the Exile turret its kind"
  started_with(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn:,
    kind:,
    viewers:,
    armor:,
  )
}

/// A place `x` along the world's x axis and `z` along its z axis: the turret faces -z, so
/// a negative `z` is ahead of it.
fn at_xz(x x: Float, z z: Float) -> start_place.Place {
  place_support.at(world_id: 3460, world_zone_id: 5967, x:, y: 0.0, z:)
}

fn approached_at(
  number number: Int,
  x x: Float,
  z z: Float,
  seq seq: Int,
) -> creature.Message {
  creature.Approached(member: step.RingMember(
    by: ConnectionId(number),
    unit_id: unit_of(number),
    place: at_xz(x:, z:),
    seq:,
    stay: map_support.stay(count: number),
    hit_radius: place_support.player_hit_radius,
  ))
}

fn moved_at(
  number number: Int,
  x x: Float,
  z z: Float,
  seq seq: Int,
) -> creature.Message {
  creature.TargetMoved(
    by: ConnectionId(number),
    place: at_xz(x:, z:),
    seq:,
    stay: map_support.stay(count: number),
    hit_radius: place_support.player_hit_radius,
  )
}

/// The turret fought by player 2, who comes near 10 units ahead of it at 0 ms: the state
/// and the step of the aggro, which starts the first attack tick at 3000 ms.
fn fought(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  tell(
    state: turret(viewers:),
    at_ms: 0,
    message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
  )
}

/// The guarded turret fought by player 2 the same way.
fn guarded_fought(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  tell(
    state: guarded_turret(viewers:).0,
    at_ms: 0,
    message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
  )
}

/// Player 5 joins the threat list by a light strike and stands at `x`, `z`.
fn with_player_5_at(state state: State, x x: Float, z z: Float) -> State {
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 1, 0.5)]),
    )
  let #(state, _) =
    tell(state:, at_ms: 200, message: moved_at(number: 5, x:, z:, seq: 2))
  state
}

/// The attack tick of 3000 ms opens the charge: the state, the step of its start and the
/// timer of its end, 8000 ms later.
fn charge_opened(
  state state: State,
  aggro aggro: ServiceStep(creature.Outgoing),
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, opened) =
    fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  #(state, opened, timer_for(opened, 8000))
}

/// The cast id the step's 0x7ff gave viewer `number`. A creature that can move turns to
/// face its target first (0x638), so the 0x7ff is the first cast news, not the first news.
fn cast_id_sent(taken: ServiceStep(creature.Outgoing), number: Int) -> Int {
  let assert Ok(CastStarted(start:)) =
    list.find(news_to(taken, number), fn(news) {
      creature_news_support.name_of(news) == "0x7ff"
    })
    as "the step sends the 0x7ff"
  start.cast_id
}

/// Player `number`'s answer that the charge's effect 224644 hit it for 400, to the strike
/// `key`.
fn landed(key key: Key) -> creature.Message {
  creature.StrikeAnswered(answered: Answered(
    key:,
    outcome: Landed(
      descriptions: [
        hit.Description(
          spell4_effects_id: 224_644,
          delay_ms: 0,
          damage: SpellDamageDescription(
            raw_damage: 400,
            scaled_raw_damage: 400,
            absorbed: 0,
            shield_absorbed: 0,
            health_damage_with_overkill: 400,
            overkill: 0,
            glance: 0,
            killed: 0,
            combat_result: combat_result.Hit,
            damage_type: damage_type.Physical,
            hits: [],
          ),
        ),
      ],
      controls: [],
      armor_removed: 0,
      gates_passed: [],
    ),
  ))
}

pub fn a_charge_starts_with_its_cast_time_and_telegraph_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 85469 has castTime 8000 and the telegraph Spell4Telegraph 57886; the client
  // draws it on the caster (`0x140546e60`, `0x14054b1b0.follows_caster`), so the 0x7ff
  // carries no positions.
  let #(state, aggro) = fought(viewers: [2, 5])
  assert said(aggro)
    == [
      "0x908(20, 1) to 2", "0x908(20, 1) to 5", "0x89a(1) to 2", "0x89a(1) to 5",
      "Threatened(7, 3) to 2",
    ]
    as "the 0x908 that names the target goes before any 0x7ff: the client's turret aims at the unit it names (`0x14046cdc0.turret_cast_aim`)"
  assert list.map(timers(aggro), fn(timer) { timer.1 }) == [3000]
    as "the attack tick starts at the kind's interval, 3000 ms"
  let #(_, opened) = fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  assert said(opened) == ["0x7ff to 2", "0x7ff to 5"]
    as "the tick opens the charge: the cast to each viewer and no strike yet"
  assert fights_told(opened) == []
  let assert [CastStarted(start:)] = news_to(opened, 2)
  assert start.spell4_id == 85_469
    && start.caster_unit_id == 7
    && start.primary_target_unit_id == 20
    as "the kind's charge, cast by the turret on its target"
  assert start.telegraph_positions == [] && start.initial_positions == []
    as "no positions: the client draws the rectangle on the turret"
  assert list.map(timers(opened), fn(timer) { timer.1 }) == [8000]
    as "one timer, the cast's end 8000 ms later, and no next attack tick"
}

pub fn at_its_end_the_charge_strikes_each_fighter_inside_its_rectangle_test() -> Nil {
  use <- owned_test.run(5000)
  // The turret faces player 2, 10 units ahead of it. Player 5 stands 5 units aside of
  // that line, beyond 1.5 + 1.2.
  let #(state, aggro) = fought(viewers: [2, 5])
  let state = with_player_5_at(state:, x: 5.0, z: -10.0)
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == ["Attacks to 2"]
    as "the strike goes to the player inside the rectangle only"
  let assert [
    #(
      2,
      Attacks(tell: Strike(
        key:,
        from:,
        striker: _,
        offence:,
        controls: [],
        gates: [],
      )),
    ),
  ] = fights_told(went)
  assert from == address()
    && key.cast_id == cast_id_sent(opened, 2)
    && key.unit_id == 20
    as "the strike answers to the turret and names the charge's cast and the struck unit"
  assert list.map(offence.blows, fn(blow) { blow.spell4_effects_id })
    == [224_644]
    as "the charge's damage effect, Spell4Effects 224644"
  assert list.map(timers(went), fn(timer) { timer.1 }) == [1000]
    as "the strike's 1 s deadline starts, and no attack tick while the round is open"
}

pub fn a_creatures_strike_names_its_unit_and_its_attack_spell4_test() -> Nil {
  use <- owned_test.run(5000)
  // The strike carries the unit and the Spell4 of the cast the viewers were sent (the 0x7ff
  // names the caster and the spell), so a player's procs of blows taken match the spell the
  // client showed.
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [CastStarted(start: instant)] = news_to(ticked, 2)
  let assert [#(2, Attacks(tell: Strike(striker: instant_striker, ..)))] =
    fights_told(ticked)
  assert instant_striker
    == CreatureStriker(
      unit_id: instant.caster_unit_id,
      spell4_id: Spell4Id(instant.spell4_id),
    )
    && instant.spell4_id == 5649
    as "the instant attack's strike names the creature that cast it and its attack spell 5649"
  let #(state, aggro) = fought(viewers: [2, 5])
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let assert [CastStarted(start: charge)] = news_to(opened, 2)
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  let assert [#(2, Attacks(tell: Strike(striker: charge_striker, ..)))] =
    fights_told(went)
  assert charge_striker
    == CreatureStriker(
      unit_id: charge.caster_unit_id,
      spell4_id: Spell4Id(charge.spell4_id),
    )
    && charge.spell4_id == 85_469
    as "the charge's strike names the turret and its charge spell 85469"
}

pub fn a_charge_with_nobody_inside_goes_with_no_target_test() -> Nil {
  use <- owned_test.run(5000)
  // The target walks 40 units off while the turret charges: beyond the 30 of the
  // rectangle, which the turret does not follow.
  let #(state, aggro) = fought(viewers: [2])
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, walked) =
    tell(
      state:,
      at_ms: 5000,
      message: moved_at(number: 2, x: 0.0, z: -40.0, seq: 2),
    )
  assert said(walked) == [] as "the turret never moves: no path is sent"
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == ["0x7f4 to 2", "0x7fe to 2"]
    as "the go and the finish of the cast, and no strike"
  let assert [CastWent(go:), CastFinished(cast_id:)] = news_to(went, 2)
  assert go.targets == []
    && go.cast_id == cast_id_sent(opened, 2)
    && cast_id == go.cast_id
    as "the go names no unit and the cast's own id"
  assert fights_told(went) == []
  assert list.map(timers(went), fn(timer) { timer.1 }) == [3000]
    as "the next attack tick starts"
}

pub fn the_struck_go_and_finish_follow_the_answers_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, went) = fire(state:, at_ms: 11_000, timer: ends)
  let deadline = timer_for(went, 1000)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(went)
  let #(state, answered) = tell(state:, at_ms: 11_100, message: landed(key:))
  assert said(answered) == ["0x7f4 to 2", "0x7fe to 2"]
    as "the go lists the struck player, then the cast finishes"
  let assert [CastWent(go:), CastFinished(cast_id:)] = news_to(answered, 2)
  let assert [target] = go.targets
  let assert [effect] = target.effects
  assert target.unit_id == 20
    && effect.spell4_effects_id == 224_644
    && go.cast_id == cast_id_sent(opened, 2)
    && cast_id == go.cast_id
    as "the go names player 2 and effect 224644, under the charge's cast id"
  assert timers_cancelled(answered) == [deadline]
    as "the last answer closes the round: its deadline is cancelled"
  assert list.map(timers(answered), fn(timer) { timer.1 }) == [3000]
    as "the next attack tick starts when the round closes"
  let #(_, second) =
    fire(state:, at_ms: 14_100, timer: timer_for(answered, 3000))
  assert said(second) == ["0x7ff to 2"] as "that tick opens the next charge"
  assert cast_id_sent(second, 2) != cast_id_sent(opened, 2)
    as "under a cast id of its own"
}

pub fn a_turret_never_chases_or_walks_home_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2, 5])
  // 40 units off: beyond the charge's reach 30 and within the leash range 55 of home, where
  // a creature that runs would chase.
  let #(state, away) =
    tell(
      state:,
      at_ms: 100,
      message: moved_at(number: 2, x: 0.0, z: -40.0, seq: 2),
    )
  assert said(away) == [] as "no path to the target"
  let #(state, ticked) =
    fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  assert said(ticked) == [] as "the tick starts no chase and no charge"
  assert list.map(timers(ticked), fn(timer) { timer.1 }) == [3000]
    as "and goes on ticking"
  let #(_, leashed) =
    tell(
      state:,
      at_ms: 3500,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the target is gone: the turret leashes"
  assert !list.contains(said(leashed), "0x638 to 5")
    && !list.contains(said(leashed), "0x638(placed) to 5")
    && timers(leashed) == []
    as "it walks nowhere: no path and no home timer"
}

pub fn a_charge_faces_its_target_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x14046cdc0.turret_cast_aim`: an aiming turret turns toward the unit its 0x908 names
  // every frame, so at the cast's end the rectangle points at the target where it
  // stands then. Player 2, the target, is 10 units ahead of the turret when the charge
  // opens and walks round it to 10 units along +x; player 5 stands in the opening
  // line, 20 units ahead, and walks out of it behind the turret.
  let #(state, aggro) = fought(viewers: [2, 5])
  let state = with_player_5_at(state:, x: 0.0, z: -20.0)
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, walked) =
    tell(
      state:,
      at_ms: 6000,
      message: moved_at(number: 2, x: 10.0, z: 0.0, seq: 2),
    )
  assert said(walked) == [] as "the turret does not move"
  let #(state, left) =
    tell(
      state:,
      at_ms: 7000,
      message: moved_at(number: 5, x: 0.0, z: 20.0, seq: 3),
    )
  assert said(left) == []
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == ["Attacks to 2"]
    as "the target is struck at its end place, which the opening line missed, and player 5, who stood in that line, is not"
}

pub fn a_second_attack_tick_during_a_charge_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, _) = charge_opened(state:, aggro:)
  let #(_, again) = fire(state:, at_ms: 4000, timer: timer_for(aggro, 3000))
  assert said(again) == [] && timers(again) == []
    as "the tick that opened the charge fires again: no second 0x7ff, no strike and no new tick"
}

pub fn a_stale_cast_end_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(_, old) = fire(state:, at_ms: 5000, timer: step.TimerId(7 * 99 + 3))
  assert said(old) == [] && timers(old) == []
    as "a cast end of another generation fires while the charge is open: it does nothing"
  let #(state, _) = fire(state:, at_ms: 11_000, timer: ends)
  let #(state, again) = fire(state:, at_ms: 11_050, timer: ends)
  assert said(again) == [] && timers(again) == []
    as "the charge struck already: its cast end fires again and finds no charge"
  let #(_, unknown) =
    fire(state:, at_ms: 11_060, timer: step.TimerId(7 * 99 + 3))
  assert said(unknown) == [] && timers(unknown) == []
    as "a cast end of a generation no charge holds does nothing"
}

pub fn death_during_a_charge_ends_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, killed) =
    tell(
      state:,
      at_ms: 5000,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 1_000_000, 1.0)]),
    )
  assert list.contains(said(killed), "0x7fe to 2")
    as "the cast finishes with the death"
  assert !list.contains(said(killed), "0x7f4 to 2") as "and nothing went: no go"
  assert list.contains(timers_cancelled(killed), ends)
    as "the cast end is cancelled"
  let #(_, late) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(late) == [] && timers(late) == []
    as "the cast end that fires all the same finds no charge"
}

pub fn leash_during_a_charge_ends_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2, 5])
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x7fe to 5")
    as "the last threat entry is released: the cast finishes"
  assert !list.contains(said(leashed), "0x7f4 to 5")
    as "and nothing went: no go"
  assert list.contains(timers_cancelled(leashed), ends)
    as "the cast end is cancelled"
  let #(_, late) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(late) == [] && timers(late) == []
    as "the cast end that fires all the same finds no charge"
}

pub fn a_viewer_arriving_mid_charge_gets_the_open_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, watched) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff"]
    as "the fight, then the open cast: the 0x908 that names the target goes before the 0x7ff"
  let assert [_, _, _, CastStarted(start:)] = news_to(watched, 9)
  assert start.cast_id == cast_id_sent(opened, 2)
    && start.spell4_id == 85_469
    && start.primary_target_unit_id == 20
    as "the same cast as the others' client holds, so the later go names it"
  let #(state, went) = fire(state:, at_ms: 11_000, timer: ends)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(went)
  let #(_, answered) = tell(state:, at_ms: 11_100, message: landed(key:))
  assert list.contains(said(answered), "0x7f4 to 9")
    && list.contains(said(answered), "0x7fe to 9")
    as "the arriving viewer is told the go and the finish too"
}

pub fn a_viewer_arriving_mid_charge_is_told_the_casts_own_target_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 is the cast's target and stands at (0, -8) where a row fixed on its target is
  // drawn. Player 5 takes the top of the threat list while the cast is under way, so the 0x908
  // a later viewer gets names player 5; its 0x7ff still names player 2, the unit the cast
  // began on (`opcode.0x7ff`: the client draws a client-placed target row on cast 0x158), and
  // carries the entries the start made.
  let #(state, opened, _) =
    target_cast_opened(
      special: target_roar(
        spell4_id: 55_846,
        anchor: area.FixedAtTarget,
        placements: [circle(radius: 4.0)],
      ),
      others: [#(5, 3.0, -8.0)],
    )
  let assert [CastStarted(start:)] = casts_of(opened, 2)
  assert list.length(start.initial_positions) == 1
    && list.length(start.telegraph_positions) == 1
    as "the start made the target's entries"
  let #(state, struck) =
    tell(
      state:,
      at_ms: 3000,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 1.0)]),
    )
  assert names_target(taken: struck, unit_id: 50, to: 2)
    as "player 5 is the target now"
  let #(_, watched) =
    tell(
      state:,
      at_ms: 3500,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert names_target(taken: watched, unit_id: 50, to: 9)
    as "the late viewer's 0x908 names the fight's target now"
  let assert [CastStarted(start: late)] = casts_of(watched, 9)
  assert late.primary_target_unit_id == 20
    as "the open cast is sent on the unit the cast began on, not the one the fight targets now"
  assert late.initial_positions == start.initial_positions
    && late.telegraph_positions == start.telegraph_positions
    as "the same entries as the cast's start"
}

pub fn a_state_that_takes_hold_during_the_charge_breaks_it_so_the_cast_end_strikes_no_one_test() -> Nil {
  use <- owned_test.run(5000)
  // The charge's hint says to use an interrupt on it (Spell4 85469, text 748860) and the
  // turret's tooltip says it is protected "unless it is interrupted while charging" (Spell4
  // 85474, text 748852). Player 2, the target, is 10 units ahead of the turret and player 5
  // stands in the same line, 20 units ahead. Player 5 stuns the turret at 9000 ms and the
  // target then walks 10 units along +x, off the line: with the charge broken there is no
  // strike at the cast's end for the held aim to point.
  let #(state, aggro) = fought(viewers: [2, 5])
  let state = with_player_5_at(state:, x: 0.0, z: -20.0)
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 9000,
      message: controlling(number: 5, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert list.contains(said(stunned), "0x87f to 2")
    as "the state took hold on the turret"
  assert list.contains(said(stunned), "0x7f9 to 2") as "and broke the charge"
  assert list.contains(timers_cancelled(stunned), ends)
    as "the charge's cast end is cancelled"
  let assert [unit_news.CastInterrupted(cast_id:)] =
    list.filter(news_to(stunned, 2), fn(news) {
      creature_news_support.name_of(news) == "0x7f9"
    })
    as "one 0x7f9"
  assert cast_id == cast_id_sent(opened, 2)
    as "of the cast the viewer was told the start of"
  let #(state, walked) =
    tell(
      state:,
      at_ms: 9500,
      message: moved_at(number: 2, x: 10.0, z: 0.0, seq: 2),
    )
  assert said(walked) == [] as "the turret does not move"
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == [] && timers(went) == []
    as "the cast end that fires all the same finds no charge: no strike"
}

pub fn a_stun_on_the_target_during_the_charge_breaks_it_and_the_next_attack_tick_starts_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 4000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert list.drop_while(said(stunned), fn(line) { line != "0x87f to 2" })
    == ["0x87f to 2", "0x7f9 to 2"]
    as "after the strike's own answer: the state, then the broken charge"
  assert list.map(timers(stunned), fn(timer) { timer.1 })
    |> list.sort(int.compare)
    == [2500, 3000]
    as "the state's end and the next attack tick, the kind's interval"
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == [] && timers(went) == []
    as "the cast was broken: its end strikes nobody"
}

pub fn a_turret_leashes_in_place_when_its_target_is_beyond_its_leash_range_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  // 60 units off: beyond the leash range 55 from home.
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: moved_at(number: 2, x: 0.0, z: -60.0, seq: 2),
    )
  let #(state, leashed) =
    fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  assert list.contains(said(leashed), "0x89a(0) to 2")
    && fights_told(leashed) == [#(2, Released(unit_id: unit))]
    as "the turret leashes: out of combat and the player released"
  assert !list.contains(said(leashed), "0x638 to 2")
    && !list.contains(said(leashed), "0x638(placed) to 2")
    && timers(leashed) == []
    as "it has no walk: no path and no home timer, though it is the leash"
  let #(_, again) =
    tell(
      state:,
      at_ms: 4000,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 3),
    )
  assert list.contains(said(again), "0x908(20, 1) to 2")
    as "a player that comes near again is fought again"
}

pub fn a_fighter_released_mid_charge_is_not_struck_test() -> Nil {
  use <- owned_test.run(5000)
  // Both stand in the rectangle; player 5 leaves the threat list while the turret
  // charges.
  let #(state, aggro) = fought(viewers: [2, 5])
  let state = with_player_5_at(state:, x: 0.0, z: -20.0)
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, _) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.unseen(by: ConnectionId(5)),
    )
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == ["Attacks to 2"]
    as "player 5 is off the threat list at the cast's end: only player 2 is struck"
}

// ---- the Sim-Turret's guard and its opening (Spell4 85474 and 85472) ----
//
// Migration 0030 gives both turrets the guard Spell4 85474 "Turret Immune" (effect 224666,
// type 79, immune to Damage) and the opening Spell4 85472 "Moment of Opportunity" (effects
// 224705 state 9, 224715 Fluff and 225189 state 12, each 15000 ms, and a Proxy that puts the
// guard back after 15000 ms). Every id below is a row of the client's tables.

/// The casts' and states' news a viewer is sent, by the names `creature_news_support.name_of` gives them.
fn news_named(
  taken: ServiceStep(creature.Outgoing),
  number: Int,
) -> List(News) {
  list.filter(news_to(taken, number), fn(news) {
    list.contains(
      ["0x87f", "0x880", "0x7f9", "0x7fe", "0x7ff", "0x7f4", "0x811"],
      creature_news_support.name_of(news),
    )
  })
}

fn names_of(news: List(News)) -> List(String) {
  list.map(news, creature_news_support.name_of)
}

/// The outcomes of the strikes the step answers.
fn answers_of(
  taken: ServiceStep(creature.Outgoing),
) -> List(strike_tell.Outcome) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      creature.Relay(
        payload: relay.Struck(answered: Answered(outcome:, ..)),
        ..,
      ) -> Ok(outcome)
      creature.Relay(payload: relay.Fight(..), ..)
      | creature.Relay(payload: relay.KillCredit(..), ..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> Error(Nil)
    }
  })
}

/// A guarded turret fought by player 2 with its charge open at 3000 ms: the state, the id of
/// the guard's cast and of the charge's, and the timer of the charge's end.
type OpenCharge {
  OpenCharge(
    state: State,
    guard_cast: Int,
    charge_cast: Int,
    ends: step.TimerId,
  )
}

fn guarded_charge(viewers viewers: List(Int)) -> OpenCharge {
  let #(turret, started) = guarded_turret(viewers:)
  let assert [_, CastStarted(start:), ..] = news_to(started, 2)
    as "the start sends the 0x262, then the guard's 0x7ff"
  let #(state, aggro) =
    tell(
      state: turret,
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  OpenCharge(
    state:,
    guard_cast: start.cast_id,
    charge_cast: cast_id_sent(opened, 2),
    ends:,
  )
}

/// Player 2's Stagger stun lands on the turret at `at_ms`.
fn stunned_at(
  state state: State,
  at_ms at_ms: Int,
) -> #(State, ServiceStep(creature.Outgoing)) {
  tell(
    state:,
    at_ms:,
    message: controlling(number: 2, cast_id: 1, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ]),
  )
}

/// How many timers of 15000 ms, the opening's length, the step starts.
fn openings_ending(taken: ServiceStep(creature.Outgoing)) -> Int {
  list.length(list.filter(timers(taken), fn(started) { started.1 == 15_000 }))
}

/// A strike of player 2 for `damage`.
fn damaging(damage damage: Int) -> creature.Message {
  strike_of(number: 2, cast_id: 2, blows: [#(1, damage, 1.0)])
}

/// The effects a go lists for the one unit it names, as (effect, instance id, lifetime).
fn effects_listed(go go: spell_go.SpellGo) -> List(#(Int, Int, Int)) {
  let assert [SpellTargetInfo(effects:, ..)] = go.targets
    as "the go names the turret alone"
  list.map(effects, fn(effect) {
    #(effect.spell4_effects_id, effect.instance_id, effect.lifetime_ms)
  })
}

pub fn a_turret_stands_holding_its_guard_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 85474's one effect, 224666, has flags 2 and no end of its own: the client draws
  // the guard from a cast whose target info for the turret holds it, with lifetime 0
  // (`Spell4.85474`, `cast.target_node_end`).
  let #(_, started) = guarded_turret(viewers: [2])
  assert said(started) == ["0x262 to 2", "0x7ff to 2", "0x7f4 to 2"]
    as "the 0x262, then the guard's cast to the viewer: no 0x7fe, which would destroy it"
  let assert [_, CastStarted(start:), CastWent(go:)] = news_to(started, 2)
    as "the 0x262, 0x7ff and 0x7f4"
  assert start.spell4_id == 85_474
    && start.caster_unit_id == unit
    && start.primary_target_unit_id == unit
    as "the guard, cast by the turret on itself"
  assert go.cast_id == start.cast_id as "the go is of the same cast"
  let assert [SpellTargetInfo(unit_id:, ..)] = go.targets
  assert unit_id == unit as "on the turret"
  let assert [#(224_666, instance_id, 0)] = effects_listed(go:)
    as "effect 224666 with lifetime 0"
  assert instance_id != 0
  let #(_, bare) =
    turret_in(
      kinds: spawn_support.turret_kinds(),
      viewers: [2],
      armor: creature_life.NoArmor,
    )
  assert said(bare) == ["0x262 to 2"] as "a turret with no guard is shown none"
}

pub fn a_damaging_strike_on_a_guarded_turret_takes_no_health_test() -> Nil {
  use <- owned_test.run(5000)
  // No client code reads Spell4Effects type 79, so the immunity is the server's
  // (`Spell4Effects.effectType.79`): the strike's damage takes nothing and the answer names no
  // effect, so the striker's connection writes the 0x247 of type 18 (`opcode.0x247.immunity`).
  let #(state, _) = guarded_fought(viewers: [2])
  let #(state, struck) = tell(state:, at_ms: 100, message: damaging(damage: 10))
  let assert [Immune(controls: [], armor_removed: 0, gates_passed: [])] =
    answers_of(struck)
    as "the answer lists no effect"
  assert !list.any(said(struck), fn(line) { string.starts_with(line, "0x937") })
    as "no health news"
  let #(_, lethal) =
    tell(state:, at_ms: 200, message: damaging(damage: 1_000_000))
  assert answers_of(lethal)
    == [Immune(controls: [], armor_removed: 0, gates_passed: [])]
    as "damage past its health takes nothing too"
  assert !list.contains(said(lethal), "KillCredit to 2")
    && !list.contains(said(lethal), "0x88c to 2")
    as "and kills nothing"
}

pub fn a_state_on_a_guarded_turret_outside_a_charge_lands_and_opens_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // The first attack tick is at 3000 ms, so at 1000 ms no charge is open.
  let #(state, _) = guarded_fought(viewers: [2])
  let #(state, stunned) = stunned_at(state:, at_ms: 1000)
  assert names_of(news_named(stunned, 2)) == ["0x87f"]
    as "the state lands and nothing else is told: no cast, no opening"
  assert list.length(landed_in(stunned)) == 1 as "the answer names the state"
  assert !list.any(timers(stunned), fn(timer) { timer.1 == 15_000 })
    as "no opening's end is set"
  let #(_, struck) = tell(state:, at_ms: 1100, message: damaging(damage: 10))
  assert answers_of(struck)
    == [Immune(controls: [], armor_removed: 0, gates_passed: [])]
    as "the turret still takes no damage"
}

pub fn a_stun_during_the_charge_interrupts_it_and_opens_the_turret_test() -> Nil {
  use <- owned_test.run(5000)
  // `cast.interrupt_sequence`: an interrupted creature cast sends 0x7f9 (result 11) and then
  // 0x7fe. Spell4 85472's effects 224705 (state 9) and 225189 (state 12) set states, 224715 is
  // Fluff, and each lasts 15000 ms; the guard's cast is taken off the turret by 0x811.
  let held = guarded_charge(viewers: [2])
  let #(_, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let assert [
    unit_news.CrowdControlApplied(state: crowd_control_state.Stun, ..),
    unit_news.CastInterrupted(cast_id: broken),
    CastStarted(start: opening),
    CastWent(go:),
    unit_news.CastTargetsRemoved(removed:, destroyed: True),
    unit_news.CrowdControlApplied(
      state: crowd_control_state.Vulnerability,
      instance_id: vulnerable,
    ),
    unit_news.CrowdControlApplied(
      state: crowd_control_state.Disable,
      instance_id: disabled,
    ),
  ] = news_named(stunned, 2)
    as "the stun, the broken charge, the opening's cast, the guard's removal, then the opening's states"
  assert broken == held.charge_cast as "the charge's cast is the one broken"
  assert opening.spell4_id == 85_472
    && opening.caster_unit_id == unit
    && opening.primary_target_unit_id == unit
    as "the opening, cast by the turret on itself"
  assert opening.cast_id != held.guard_cast
    && opening.cast_id != held.charge_cast
    as "a cast id neither of the live casts held"
  assert go.cast_id == opening.cast_id
  let assert [
    #(224_705, first, 15_000),
    #(224_715, second, 15_000),
    #(225_189, third, 15_000),
  ] = effects_listed(go:)
    as "the effects in their rows' order, each lasting 15000 ms"
  assert first != 0
    && second != 0
    && third != 0
    && first != second
    && second != third
    && first != third
    as "each with its own non-zero instance id"
  assert vulnerable == first && disabled == third
    as "the 0x87f of each state names its effect's instance id"
  assert removed
    == SpellTargetsRemoved(cast_id: held.guard_cast, unit_ids: [unit])
    as "the guard's cast comes off the turret"
  assert list.contains(timers_cancelled(stunned), held.ends)
    as "the charge's cast end is cancelled"
  assert openings_ending(stunned) == 1
    as "the opening's end is one timer of 15000 ms"
}

pub fn a_knockdown_during_the_charge_also_interrupts_it_test() -> Nil {
  use <- owned_test.run(5000)
  // `cc_state.end` and the tooltip's "unless it is interrupted while charging" name no state:
  // a knockdown holds the creature as a stun does.
  let held = guarded_charge(viewers: [2])
  let #(_, knocked) =
    tell(
      state: held.state,
      at_ms: 4000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.kick_knockdown(instance_id: 28_673),
      ]),
    )
  assert names_of(news_named(knocked, 2))
    == ["0x87f", "0x7f9", "0x7ff", "0x7f4", "0x811", "0x87f", "0x87f"]
    as "the knockdown, the broken charge, the opening, the guard's removal and the opening's states"
  let assert [unit_news.CrowdControlApplied(state:, ..), ..] =
    news_named(knocked, 2)
  assert state == crowd_control_state.Knockdown
  assert openings_ending(knocked) == 1
}

pub fn a_damaging_strike_on_an_opened_turret_takes_health_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, _) = stunned_at(state: held.state, at_ms: 4000)
  let max_health =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0)).health
  let #(_, struck) = tell(state:, at_ms: 5000, message: damaging(damage: 10))
  assert list.contains(
    said(struck),
    "0x937(" <> int.to_string(max_health - 10) <> ") to 2",
  )
    as "the turret takes the 10 the strike gives"
  let assert [Landed(descriptions:, ..)] = answers_of(struck)
    as "the answer to the striker"
  assert descriptions != [] as "lists the hit"
}

pub fn the_opening_ends_after_15_seconds_and_the_guard_returns_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let opening_ends = timer_for(stunned, 15_000)
  let assert [_, _, CastStarted(start: opening), ..] = news_named(stunned, 2)
    as "the stun, the broken charge, then the opening's cast"
  let #(state, _) = fire(state:, at_ms: 6500, timer: timer_for(stunned, 2500))
  let #(state, ended) = fire(state:, at_ms: 19_000, timer: opening_ends)
  let assert [
    unit_news.CrowdControlEnded(
      state: crowd_control_state.Vulnerability,
      cast_id: first_cast,
      instance_id: first_instance,
    ),
    unit_news.CrowdControlEnded(
      state: crowd_control_state.Disable,
      cast_id: second_cast,
      instance_id: second_instance,
    ),
    CastFinished(cast_id: finished),
    CastStarted(start: guard),
    CastWent(go:),
  ] = news_named(ended, 2)
    as "the opening's two states end, its cast finishes, then the guard's new cast"
  assert first_cast == opening.cast_id
    && second_cast == opening.cast_id
    && finished == opening.cast_id
    as "all of the opening's cast"
  assert first_instance != second_instance && first_instance != 0
    as "each state ends by its own effect's instance id"
  assert guard.spell4_id == 85_474
    && guard.caster_unit_id == unit
    && guard.primary_target_unit_id == unit
    as "the guard is cast again"
  assert guard.cast_id != held.guard_cast as "under a new cast id"
  assert go.cast_id == guard.cast_id
  let assert [#(224_666, _, 0)] = effects_listed(go:)
  let #(_, struck) = tell(state:, at_ms: 19_100, message: damaging(damage: 10))
  assert answers_of(struck)
    == [Immune(controls: [], armor_removed: 0, gates_passed: [])]
    as "the turret takes no damage again"
}

pub fn no_charge_starts_while_opened_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 85469 has prerequisiteIdCasterCast 41722, which the opening's state satisfies
  // for no cast: the turret is held while it lasts. Its attack tick goes on and starts nothing.
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let #(state, _) = fire(state:, at_ms: 6500, timer: timer_for(stunned, 2500))
  let #(state, tick) =
    fire(state:, at_ms: 7000, timer: timer_for(stunned, 3000))
  assert said(tick) == [] as "the stun is over but the opening holds the turret"
  assert list.map(timers(tick), fn(timer) { timer.1 }) == [3000]
    as "the next attack tick is all that starts"
  let #(_, again) = fire(state:, at_ms: 10_000, timer: timer_for(tick, 3000))
  assert said(again) == [] as "and again"
}

pub fn a_second_state_in_the_same_round_opens_nothing_more_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, _) = stunned_at(state: held.state, at_ms: 4000)
  let #(_, second) =
    tell(
      state:,
      at_ms: 4500,
      message: controlling(number: 2, cast_id: 3, controls: [
        crowd_control_support.gate_stun(instance_id: 28_674),
      ]),
    )
  assert names_of(news_named(second, 2)) == ["0x87f"]
    as "the second state lands and breaks nothing and opens nothing"
  assert !list.any(timers(second), fn(timer) { timer.1 == 15_000 })
    as "no second opening's end"
}

pub fn a_cast_end_after_an_interrupt_is_stale_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, _) = stunned_at(state: held.state, at_ms: 4000)
  let #(_, late) = fire(state:, at_ms: 11_000, timer: held.ends)
  assert said(late) == [] && timers(late) == []
    as "the cast end of the broken charge finds no charge: no strike, no go, no finish"
}

pub fn an_interrupt_after_the_go_opens_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, went) = fire(state: held.state, at_ms: 11_000, timer: held.ends)
  assert said(went) == ["Attacks to 2"]
    as "the strike is told: the go waits for its answer"
  let #(_, stunned) = stunned_at(state:, at_ms: 11_050)
  assert names_of(news_named(stunned, 2)) == ["0x87f"]
    as "a state after the go lands and breaks nothing"
  assert !list.any(timers(stunned), fn(timer) { timer.1 == 15_000 })
    as "and opens nothing"
}

pub fn a_turret_killed_while_opened_gives_its_kill_credit_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let #(_, killed) =
    tell(state:, at_ms: 5000, message: damaging(damage: 1_000_000))
  assert list.contains(said(killed), "KillCredit to 2")
    as "the turret dies of the strike, which credits its killer"
  let assert [_, _, CastStarted(start: opening), ..] = news_named(stunned, 2)
    as "the opening's cast is the third news of the interrupt"
  let assert [CastFinished(cast_id: finished)] = news_named(killed, 2)
    as "no 0x880, the death clears the client's states; the opening's cast is finished, which the death does not do"
  assert finished == opening.cast_id
  assert list.contains(timers_cancelled(killed), timer_for(stunned, 15_000))
    as "the opening's end is cancelled"
}

/// A turret that is stunned open and then told to despawn: its opening's cast is finished
/// with no 0x880 and its opening timer is cancelled. Called by `creature_test`'s despawn
/// test, which names the three things a despawn drops.
pub fn a_despawned_opening_ends_without_a_0x880() -> Nil {
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let #(gone, despawned) =
    tell(
      state:,
      at_ms: 5000,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 5000),
    )
  let assert [_, _, CastStarted(start: opening), ..] = news_named(stunned, 2)
    as "the opening's cast is the third news of the interrupt"
  let assert [CastFinished(cast_id: finished)] = news_named(despawned, 2)
    as "no 0x880, the removal clears the client's states; the opening's cast is finished, which the removal does not do"
  assert finished == opening.cast_id
  assert list.contains(timers_cancelled(despawned), timer_for(stunned, 15_000))
    as "the opening's end is cancelled"
  let #(_, late) =
    fire(state: gone, at_ms: 19_000, timer: timer_for(stunned, 15_000))
  assert said(late) == [] && timers(late) == []
    as "the opening's end that fires all the same finds no opening"
}

pub fn an_opening_end_after_death_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let #(state, _) =
    tell(state:, at_ms: 5000, message: damaging(damage: 1_000_000))
  let #(_, late) =
    fire(state:, at_ms: 19_000, timer: timer_for(stunned, 15_000))
  assert said(late) == [] && timers(late) == []
    as "the opening's end that fires all the same finds no opening"
  let #(_, arrived) =
    tell(
      state:,
      at_ms: 20_000,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert news_named(arrived, 9) == []
    as "a viewer that arrives at the body is shown no guard: the dead turret holds none"
}

pub fn a_respawned_turret_stands_guarded_test() -> Nil {
  use <- owned_test.run(5000)
  let held = guarded_charge(viewers: [2])
  let #(state, _) = stunned_at(state: held.state, at_ms: 4000)
  let #(state, killed) =
    tell(state:, at_ms: 5000, message: damaging(damage: 1_000_000))
  let #(_, expired) =
    fire(state:, at_ms: 65_000, timer: timer_for(killed, 60_000))
  assert list.map(news_to(expired, 2), creature_news_support.name_of)
    == ["0x355"]
    && creature_news_support.said_to_the_map(expired) == ["expired 7 of life 3"]
    as "the killed turret's corpse timer removes it and expires it: the next life is its map's start"
  let #(state, stood) = guarded_turret(viewers: [2])
  let assert [_, CastStarted(start:), CastWent(go:)] = news_to(stood, 2)
    as "the next life's start: the 0x262, the guard's cast and nothing of the opening"
  assert start.spell4_id == 85_474
    && start.caster_unit_id == unit
    && start.primary_target_unit_id == unit
  assert start.cast_id == held.guard_cast
    as "the new life's guard numbers its casts from the start, so its first cast has the first life's id: the viewer finishes a unit's casts before its 0x355 (`viewers.unit_removed`)"
  assert go.cast_id == start.cast_id
  let assert [#(224_666, _, 0)] = effects_listed(go:)
  let #(_, struck) = tell(state:, at_ms: 65_100, message: damaging(damage: 10))
  assert answers_of(struck)
    == [Immune(controls: [], armor_removed: 0, gates_passed: [])]
    as "it takes no damage"
}

pub fn two_charges_under_a_held_guard_take_different_cast_ids_test() -> Nil {
  use <- owned_test.run(5000)
  // The guard holds the cast id of number 1 of the unit's id space for as long as it is up,
  // and the fight's casts take the next free ids (`cast.mint`).
  let held = guarded_charge(viewers: [2])
  let #(state, went) = fire(state: held.state, at_ms: 11_000, timer: held.ends)
  let assert [#(2, Attacks(tell: Strike(key: first_key, ..)))] =
    fights_told(went)
  let #(state, answered) =
    tell(state:, at_ms: 11_100, message: landed(key: first_key))
  let #(state, again) =
    fire(state:, at_ms: 14_100, timer: timer_for(answered, 3000))
  let second = cast_id_sent(again, 2)
  assert second != held.charge_cast && second != held.guard_cast
    as "the second charge takes an id neither the first charge nor the guard holds"
  let #(_, late) = tell(state:, at_ms: 14_200, message: landed(key: first_key))
  assert said(late) == [] && timers_cancelled(late) == []
    as "a late answer to the first charge does not close the second"
}

pub fn a_viewer_arriving_while_the_turret_is_opened_is_told_the_opening_with_the_time_left_test() -> Nil {
  use <- owned_test.run(5000)
  // A viewer that comes near after the opening started is shown the opening the way the
  // others were, with what is left of its 15000 ms as each effect's lifetime (the client ends
  // a node only by 0x7fe, `cast.target_node_end`), the instance ids the others were told, and
  // then the states by 0x87f.
  let held = guarded_charge(viewers: [2])
  let #(state, stunned) = stunned_at(state: held.state, at_ms: 4000)
  let assert [_, _, _, CastWent(go: first), ..] = news_named(stunned, 2)
    as "the stun, the broken charge, the opening's cast"
  let #(state, _) = fire(state:, at_ms: 6500, timer: timer_for(stunned, 2500))
  let #(_, arrived) =
    tell(
      state:,
      at_ms: 9000,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  let assert [
    CastStarted(start:),
    CastWent(go:),
    unit_news.CrowdControlApplied(state: first_state, instance_id: first_id),
    unit_news.CrowdControlApplied(state: second_state, instance_id: second_id),
  ] = news_named(arrived, 9)
    as "the opening's cast, then the two states"
  assert start.spell4_id == 85_472
    && start.caster_unit_id == unit
    && start.primary_target_unit_id == unit
  let assert [
    #(224_705, id_a, 10_000),
    #(224_715, id_b, 10_000),
    #(225_189, id_c, 10_000),
  ] = effects_listed(go:)
    as "the effects as before, 15000 - (9000 - 4000) ms left"
  let assert [
    #(224_705, told_a, 15_000),
    #(224_715, told_b, 15_000),
    #(225_189, told_c, 15_000),
  ] = effects_listed(go: first)
  assert id_a == told_a && id_b == told_b && id_c == told_c
    as "each under the instance id the others were told"
  assert first_state == crowd_control_state.Vulnerability
    && first_id == id_a
    && second_state == crowd_control_state.Disable
    && second_id == id_c
}

// What a held state lets a creature do. Expected values come from the client's rows, read
// with `table_rows`. The states that stop a creature moving are the ones whose
// `CCStates.flags` hold the value 2: Stun (30) and Root (195) do; Snare (129), Polymorph (0)
// and Fear (4) do not (`UnitHasCCStateFlag02`, 0x14045e630). The states that refuse the
// Beast's attack are the ones in the ccStateMask of Spell4CCConditions 1, the row Spell4
// 5649 names for its caster: 0 Stun, 1 Sleep, 5 Polymorph, 6 Fear, 8 Knockdown, 9
// Vulnerability, 12 Disable, 16 Knockback, 18 Pull, 19 PositionSwitch, 24 Subdue, 26
// DisableCinematic and 27 AbilityRestriction, so not Root (2) and not Snare (21). The
// Sim-Turret's charge, Spell4 85469, names row 2, which masks nothing. That a creature
// holding Stun, Knockdown or Knockback casts nothing is a retail record (WildStar wiki,
// Combat, "Moment of Opportunity"). Jim decided on 2026-11-11 that a state of any kind
// landing during a charge breaks it. A Sim-Turret starts no charge while it holds any
// other state either, as before: a gap, issue 801.

/// The Beast fought by player 2 standing `x` units off from 0 ms and struck by player 2 at
/// 500 ms with this state for 2500 ms: the state, the step of the aggro and the step of the
/// landing.
fn beast_holding(
  held held: crowd_control_state.CrowdControlState,
  x x: Float,
) -> #(State, ServiceStep(creature.Outgoing), ServiceStep(creature.Outgoing)) {
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x:, seq: 1),
    )
  let #(state, landed) =
    tell(
      state:,
      at_ms: 500,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: held,
          duration_ms: 2500,
          instance_id: 28_673,
        ),
      ]),
    )
  #(state, aggro, landed)
}

pub fn a_creature_attacks_or_chases_as_its_states_allow_test() -> Nil {
  use <- owned_test.run(5000)
  // Root, in reach: no mask of the attack's row has it, so the 1500 ms tick strikes.
  let #(state, aggro, landed) =
    beast_holding(held: crowd_control_state.Root, x: 5.0)
  assert list.contains(said(landed), "0x87f to 2")
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert list.contains(said(ticked), "0x7ff to 2")
    as "Root is in no mask of the attack's row: the creature strikes in reach"
  // Root, out of reach: its flags hold the value 2, so the run stops where it stands and
  // no chase starts.
  let #(state, _, rooted) =
    beast_holding(held: crowd_control_state.Root, x: 30.0)
  let assert [CreaturePlaced(place:, ..)] =
    list.filter(news_to(rooted, 2), fn(news) {
      creature_news_support.name_of(news) == "0x638(placed)"
    })
    as "the running path stops with 0x638 of kind 2"
  assert x_of(place) == 5.0 as "10 units a second for 500 ms from x = 0"
  let #(_, moved_away) =
    tell(state:, at_ms: 700, message: moved(number: 2, x: 35.0, seq: 2))
  assert said(moved_away) == []
    as "the player moves and the rooted creature starts no chase"
  // Polymorph, in reach: the row masks it, so the tick strikes nothing, and the next one
  // strikes once the state is over.
  let #(state, aggro, landed) =
    beast_holding(held: crowd_control_state.Polymorph, x: 5.0)
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert !list.contains(said(ticked), "0x7ff to 2") && fights_told(ticked) == []
    as "Polymorph is in the attack's row: no strike"
  let #(state, ended) =
    fire(state:, at_ms: 3000, timer: timer_for(landed, 2500))
  assert list.contains(said(ended), "0x880 to 2")
  let #(_, struck) = fire(state:, at_ms: 3000, timer: timer_for(ticked, 1500))
  assert list.contains(said(struck), "0x7ff to 2")
    as "the tick after the state strikes again"
  // Polymorph, out of reach: its flags hold no 2, so the run goes on and the creature
  // chases the target that moves.
  let #(state, _, polymorphed) =
    beast_holding(held: crowd_control_state.Polymorph, x: 30.0)
  assert !list.contains(said(polymorphed), "0x638(placed) to 2")
    as "the run is not stopped"
  let #(_, moved_away) =
    tell(state:, at_ms: 700, message: moved(number: 2, x: 35.0, seq: 2))
  assert x_of(creature_path.end(path: path_sent(moved_away))) == 31.0
    as "it runs toward 35, 0.5 x reach 8 short"
  // Snare, in reach: neither the mask nor the flags have it, so the strike and the chase
  // both go on.
  let #(state, aggro, _) =
    beast_holding(held: crowd_control_state.Snare, x: 5.0)
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert list.contains(said(ticked), "0x7ff to 2")
    as "Snare is in no mask of the attack's row: the creature strikes"
  let #(state, _, snared) =
    beast_holding(held: crowd_control_state.Snare, x: 30.0)
  assert !list.contains(said(snared), "0x638(placed) to 2")
    as "Snare stops no run"
  let #(_, moved_away) =
    tell(state:, at_ms: 700, message: moved(number: 2, x: 35.0, seq: 2))
  assert x_of(creature_path.end(path: path_sent(moved_away))) == 31.0
    as "and the creature chases"
}

pub fn any_state_landing_breaks_a_charge_test() -> Nil {
  use <- owned_test.run(5000)
  // Snare is in neither the turret's caster row (2, which masks nothing) nor the flags that
  // stop movement.
  list.each(
    [
      #("Snare", crowd_control_state.Snare),
      #("Fear", crowd_control_state.Fear),
      #("Polymorph", crowd_control_state.Polymorph),
    ],
    fn(row) {
      let #(name, held) = row
      let #(state, aggro) = fought(viewers: [2])
      let #(state, _, ends) = charge_opened(state:, aggro:)
      let #(state, landed) =
        tell(
          state:,
          at_ms: 4000,
          message: controlling(number: 2, cast_id: 1, controls: [
            crowd_control_support.holding(
              state: held,
              duration_ms: 2500,
              instance_id: 28_673,
            ),
          ]),
        )
      assert list.contains(said(landed), "0x87f to 2")
        && list.contains(said(landed), "0x7f9 to 2")
        as {
          "holding " <> name <> ": the state took hold and broke the charge"
        }
      assert list.contains(timers_cancelled(landed), ends)
        as { "holding " <> name <> ": the charge's cast end is cancelled" }
      let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
      assert said(went) == [] && timers(went) == []
        as {
          "holding "
          <> name
          <> ": the cast end that fires all the same strikes nobody"
        }
    },
  )
}

/// A Beast whose attack's caster row masks nothing, fought by player 2 from 5 units off.
fn unmasked_beast() -> State {
  let spawn = spawn_support.battle_beast(number: 1, x: 0.0)
  beast_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(
      ..spawn,
      combat: creature_life.Combat(
        ..spawn.combat,
        attack: creature_life.Attack(..spawn.combat.attack, caster_cc_mask: 0),
      ),
    ),
    viewers: [2],
    armor: creature_life.NoArmor,
  )
}

pub fn a_creature_holding_hard_crowd_control_starts_no_cast_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("Stun", crowd_control_state.Stun),
      #("Knockdown", crowd_control_state.Knockdown),
      #("Knockback", crowd_control_state.Knockback),
    ],
    fn(row) {
      let #(name, held) = row
      let holding =
        controlling(number: 2, cast_id: 1, controls: [
          crowd_control_support.holding(
            state: held,
            duration_ms: 5000,
            instance_id: 28_673,
          ),
        ])
      // A turret, whose charge's row masks nothing: no charge at its 3000 ms tick.
      let #(state, aggro) = fought(viewers: [2])
      let #(state, _) = tell(state:, at_ms: 100, message: holding)
      let #(_, ticked) =
        fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
      assert said(ticked) == [] && fights_told(ticked) == []
        as "the turret holding the state opens no charge"
      // A Beast whose strike's row masks nothing: no strike at its 1500 ms tick.
      let #(state, aggro) =
        tell(
          state: unmasked_beast(),
          at_ms: 0,
          message: approached(number: 2, x: 5.0, seq: 1),
        )
      let #(state, _) = tell(state:, at_ms: 100, message: holding)
      let #(_, ticked) =
        fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
      assert !list.contains(said(ticked), "0x7ff to 2")
        && fights_told(ticked) == []
        as {
          "holding "
          <> name
          <> ": and the creature holding the state strikes nothing"
        }
    },
  )
}

pub fn a_turret_holding_any_other_state_starts_no_charge_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, landed) =
    tell(
      state:,
      at_ms: 100,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: crowd_control_state.Snare,
          duration_ms: 4000,
          instance_id: 28_673,
        ),
      ]),
    )
  let #(state, ticked) =
    fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  assert said(ticked) == [] && fights_told(ticked) == []
    as "the turret holding Snare starts no charge at its charge time"
  let #(state, ended) =
    fire(state:, at_ms: 4100, timer: timer_for(landed, 4000))
  assert list.contains(said(ended), "0x880 to 2")
  let #(_, opened) = fire(state:, at_ms: 6000, timer: timer_for(ticked, 3000))
  assert list.contains(said(opened), "0x7ff to 2")
    as "once the Snare has ended the next tick charges"
}

// ---- a thrown creature (issue 788) ----
//
// The throws below are one row's worth: kind 4 (away from the reference unit), 10 m, a
// flight of 375 ms, flags 0 (the columns of Spell4Effects 73826), the reference unit 5
// behind the creature along x. The creature at x runs to x + 10 in 375 ms. Player 2 stands
// 30 off at x = 30, so a chasing beast runs from its spawn toward 30 - 0.5 x 8 = 26 at
// 10 units a second (`Spell4.5649`'s reach 8, runLand 10.0), and is at x = 10 a second in.

/// The throw of Spell4Effects 73826: 10 m away from a unit at x = -5, over 375 ms.
fn knockback() -> creature.Message {
  knockback_from(unit_at: map_spawn_support.at(-5.0))
}

/// The same throw away from a unit at `unit_at`.
fn knockback_from(unit_at unit_at: start_place.Place) -> creature.Message {
  creature.Thrown(throw: forced_move.Throw(
    move: forced_move.Move(
      way: forced_move.Away,
      mover: forced_move.Flight,
      min_distance: 10.0,
      max_distance: 10.0,
      flight_ms: 375,
      gravity: 0.0,
      flags: 0,
      height: 0.0,
    ),
    draws: forced_move.Draws(distance: 0.0, angle: 0.0),
    reference: forced_move.Reference(place: unit_at, radius: 0.0),
  ))
}

/// The beast chasing player 2, 30 off, for these viewers, and the step of the aggro.
fn chasing(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  tell(
    state: beast(viewers:),
    at_ms: 0,
    message: approached(number: 2, x: 30.0, seq: 1),
  )
}

/// The chasing beast thrown 1 s into its run, at x = 10: the state, the step of the throw
/// and the timer of the flight's end, 375 ms on.
fn thrown_chasing(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, _) = chasing(viewers:)
  let #(state, thrown) = tell(state:, at_ms: 1000, message: knockback())
  #(state, thrown, timer_for(thrown, 375))
}

/// The Knockback state of Spell4Effects 56250 (`table_rows -- Spell4Effects 56250`): delayTime 0,
/// durationTime 0, state 16, dataBits03 1, which names helper 36010 whose throw is
/// Spell4Effects 73826: kind 4 (away from the reference unit), 10.0 m, 375 ms, no gravity,
/// flags 1, height 2.0. The reference unit is 5 behind the creature along x.
fn knockback_state(instance_id instance_id: Int) -> strike_tell.ControlTell {
  strike_tell.ControlTell(
    effect_id: 56_250,
    instance_id:,
    row: crowd_control.Row(
      state: crowd_control_state.Knockback,
      delay_ms: 0,
      lasts: lasts.For(duration_ms: 0),
      armor_removed: 1,
    ),
    throw: Some(forced_move.Throw(
      move: forced_move.Move(
        way: forced_move.Away,
        mover: forced_move.Flight,
        min_distance: 10.0,
        max_distance: 10.0,
        flight_ms: 375,
        gravity: 0.0,
        flags: 1,
        height: 2.0,
      ),
      draws: forced_move.Draws(distance: 0.0, angle: 0.0),
      reference: forced_move.Reference(
        place: map_spawn_support.at(-5.0),
        radius: 0.0,
      ),
    )),
  )
}

pub fn a_landed_knockback_throws_the_creature_in_the_same_step_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let #(_, struck) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        knockback_state(instance_id: 28_673),
      ]),
    )
  assert list.length(landed_in(struck)) == 1
    as "the answer names the state that landed"
  let before_flight =
    list.take_while(said(struck), fn(line) { line != "0x638 to 2" })
  assert list.contains(before_flight, "0x87f to 2")
    as "the state's news comes before the flight"
  assert list.filter(said(struck), fn(line) { line == "0x638 to 2" })
    == ["0x638 to 2"]
    && list.filter(said(struck), fn(line) { line == "0x638 to 5" })
    == ["0x638 to 5"]
    as "each viewer is sent the flight once, in the same step"
  let assert [CreatureMoved(path:)] =
    list.filter(news_to(struck, 2), fn(news) {
      creature_news_support.name_of(news) == "0x638"
    })
    as "the viewer is sent one flight"
  let assert [#(first_ms, first_x), #(last_ms, last_x)] = timed_xs(path:)
  assert first_ms == start_ms + 1000
    && place_support.near(left: first_x, right: 10.0)
    && last_ms == start_ms + 1375
    && place_support.near(left: last_x, right: 20.0)
    as "from where the creature is, 1 s into its run at x = 10, to 10 further away from the unit behind it, 375 ms later"
  assert list.any(timers(struck), fn(timer) { timer.1 == 375 })
    as "the flight's end is a timer"
}

pub fn an_immune_knockback_does_not_throw_test() -> Nil {
  use <- owned_test.run(5000)
  // The same strike with a blow and the Knockback state: an unguarded Beast is thrown, and the
  // Beast guarded by Spell4 85474 (`Spell4Effects` type 79 immunity) takes the blow as `Immune`,
  // keeps the state as it does today and is not thrown.
  let strike_with_blow = fn() {
    let assert creature.Strike(tell:) = damaging(damage: 10)
    creature.Strike(
      tell: Strike(..tell, controls: [knockback_state(instance_id: 28_673)]),
    )
  }
  let #(open, _) = chasing(viewers: [2])
  let #(_, thrown) = tell(state: open, at_ms: 1000, message: strike_with_blow())
  assert list.contains(said(thrown), "0x638 to 2")
    as "an unguarded Beast that takes the blow and the state is thrown"
  let assert Ok(turret) =
    dict.get(spawn_support.guarded_turret_kinds().by_creature, 73_494)
    as "the guarded turret's kind carries the guard"
  let #(guarded, _) =
    started_with(
      source: spawn_source.Stored(id: SpawnId(1)),
      spawn: spawn_support.battle_beast(number: 1, x: 0.0),
      kind: Kind(..beast_kind(), guard: turret.guard),
      viewers: [2],
      armor: creature_life.NoArmor,
    )
  let #(guarded, _) =
    tell(
      state: guarded,
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(_, struck) =
    tell(state: guarded, at_ms: 1000, message: strike_with_blow())
  let assert [Immune(controls: [_], ..)] = answers_of(struck)
    as "the guard takes the blow as immune and the state still lands"
  assert !list.contains(said(struck), "0x638 to 2")
    as "an immune creature is not thrown"
}

/// The path's points as (time, x) pairs.
fn timed_xs(path path: creature_path.Path) -> List(#(Int, Float)) {
  let assert Timed(first:, rest:, ..) = path as "the path is a timed path"
  list.map([first, ..rest], fn(point) { #(point.0, x_of(point.1)) })
}

pub fn a_thrown_creature_sends_its_viewers_the_flight_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, thrown, _) = thrown_chasing(viewers: [2, 5])
  assert said(thrown) == ["0x638 to 2", "0x638 to 5"]
    as "one 0x638 for each viewer, and no other news"
  let assert [CreatureMoved(path:)] = news_to(thrown, 2)
  let assert [#(first_ms, first_x), #(last_ms, last_x)] = timed_xs(path:)
  assert first_ms == start_ms + 1000
    && place_support.near(left: first_x, right: 10.0)
    && last_ms == start_ms + 1375
    && place_support.near(left: last_x, right: 20.0)
    as "from where the creature is, 1 s into its run at x = 10, to 10 further away from the unit behind it, 375 ms later"
  assert news_to(thrown, 5) == news_to(thrown, 2)
    as "both viewers read the same path"
  assert list.map(timers(thrown), fn(timer) { timer.1 }) == [375]
    as "the flight's end is the one timer started"
  let #(_, moved_on) =
    tell(state:, at_ms: 1100, message: moved(number: 2, x: 35.0, seq: 2))
  assert said(moved_on) == []
    as "the target moving in flight plans no path: the flight is the viewers' only 0x638"
}

pub fn a_thrown_creature_does_not_chase_or_attack_until_it_lands_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 stands 5 off, in reach 8: the tick at 1500 ms would strike. The creature is
  // thrown at 1400 ms to x = 10, landing at 1775 ms.
  let #(state, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, thrown) = tell(state:, at_ms: 1400, message: knockback())
  let lands = timer_for(thrown, 375)
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == [] && fights_told(ticked) == []
    as "the tick in flight starts no round: no 0x7ff and no strike"
  assert list.map(timers(ticked), fn(timer) { timer.1 }) == [1500]
    as "the attack tick goes on at its interval"
  let #(state, moved_off) =
    tell(state:, at_ms: 1600, message: moved(number: 2, x: 15.0, seq: 2))
  assert said(moved_off) == []
    as "the target moving 5 from where the creature will land starts no chase"
  let #(state, landed) = fire(state:, at_ms: 1775, timer: lands)
  assert said(landed) == []
    as "landing in reach of the target sends nothing: a client keeps a timed path's last point"
  let #(_, struck) = fire(state:, at_ms: 3000, timer: timer_for(ticked, 1500))
  assert list.contains(said(struck), "0x7ff to 2")
    as "the next tick after the landing strikes again"
}

pub fn a_bare_throw_resumes_the_chase_from_the_landing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2])
  let #(_, landed) = fire(state:, at_ms: 1375, timer: lands)
  assert said(landed) == ["0x638 to 2"]
    as "the landing sends no kind 2: the one 0x638 is the new chase"
  let assert Running(from:, to:, started_ms:, speed:, ..) = path_sent(landed)
  assert place_support.near(left: x_of(from), right: 20.0)
    && x_of(to) == 26.0
    && started_ms == start_ms + 1375
    && speed == 10.0
    as "from the landing at x = 20 toward 30 - 0.5 x 8, at run speed 10"
}

/// The creature the sim turret is, but running at 10 and of an ordinary unit type, so
/// that a throw moves it: Spell4 85469's charge, opened at 3000 ms, ending 8000 ms later.
fn charger(viewers viewers: List(Int)) -> State {
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let assert Ok(kind) =
    dict.get(spawn_support.turret_kinds().by_creature, 73_494)
    as "migrations 0029 gives the Exile turret its kind"
  started_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(
      ..spawn,
      unit_type: creature_unit_type.NonPlayer,
      combat: creature_life.Combat(
        ..spawn.combat,
        attack: creature_life.Attack(..spawn.combat.attack, run_speed: 10.0),
      ),
    ),
    kind:,
    viewers:,
    armor: creature_life.NoArmor,
  )
}

pub fn a_throw_breaks_an_open_charge_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: charger(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, thrown) = tell(state:, at_ms: 4000, message: knockback())
  assert said(thrown) == ["0x7f9 to 2", "0x638 to 2"]
    as "the charge is broken as a state breaks it, then the flight is sent"
  let assert [unit_news.CastInterrupted(cast_id:)] =
    list.filter(news_to(thrown, 2), fn(news) {
      creature_news_support.name_of(news) == "0x7f9"
    })
  assert cast_id == cast_id_sent(opened, 2)
    as "of the cast the viewer was told the start of"
  assert timers_cancelled(thrown) == [ends]
    as "the charge's cast end is cancelled"
  assert list.map(timers(thrown), fn(timer) { timer.1 })
    |> list.sort(int.compare)
    == [375, 3000]
    as "the flight's end and the next attack tick, the kind's interval"
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  assert said(went) == [] && timers(went) == []
    as "the cast end that fires all the same strikes nobody"
}

pub fn a_throw_that_moves_the_creature_nowhere_leaves_an_open_charge_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: charger(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  let #(state, _, ends) = charge_opened(state:, aggro:)
  // Away from a unit at the creature's own place has no way to go: the creature is not moved.
  let #(_, thrown) =
    tell(
      state:,
      at_ms: 4000,
      message: knockback_from(unit_at: map_spawn_support.at(0.0)),
    )
  assert said(thrown) == [] && timers(thrown) == []
    as "no path, no timer and no 0x7f9: the creature moved nowhere"
  assert !list.contains(timers_cancelled(thrown), ends)
    as "the charge's cast end stays"
}

pub fn a_state_landing_mid_flight_lets_the_flight_finish_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2])
  let #(_, stunned) =
    tell(
      state:,
      at_ms: 1100,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert list.contains(said(stunned), "0x87f to 2")
    as "the state took hold on the flying creature"
  assert !list.contains(said(stunned), "0x638(placed) to 2")
    as "its flight is not stopped: no kind 2 where it is"
  assert !list.contains(timers_cancelled(stunned), lands)
    as "and its landing stays timed"
}

pub fn a_flight_ending_while_a_state_holds_does_not_resume_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2])
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1100,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, landed) = fire(state:, at_ms: 1375, timer: lands)
  assert said(landed) == ["turn(kind 14) to 2"] && timers(landed) == []
    as "the stunned creature lands and starts no chase: it only stands as it faces, which the flight put off"
  let #(_, ended) = fire(state:, at_ms: 3700, timer: timer_for(stunned, 2500))
  let assert Running(from:, ..) = path_sent(ended)
    as "when the state ends it chases again"
  assert place_support.near(left: x_of(from), right: 20.0)
    as "from where it landed"
}

pub fn a_state_ending_mid_flight_does_not_resume_until_the_landing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2])
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1050,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: crowd_control_state.Stun,
          duration_ms: 100,
          instance_id: 28_673,
        ),
      ]),
    )
  let #(state, ended) =
    fire(state:, at_ms: 1150, timer: timer_for(stunned, 100))
  assert list.contains(said(ended), "0x880 to 2") as "the state ends in flight"
  assert !list.contains(said(ended), "0x638 to 2")
    as "and the creature starts no chase before it lands"
  let #(_, landed) = fire(state:, at_ms: 1375, timer: lands)
  assert said(landed) == ["0x638 to 2"] as "it chases at the landing"
}

pub fn a_leash_in_flight_walks_home_from_the_landing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2, 5])
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the only player on the threat list is gone: the creature leashes"
  assert !list.contains(said(leashed), "0x638 to 5")
    && !list.contains(said(leashed), "0x638(placed) to 5")
    as "the flight is not replaced by a walk from where the arc is"
  assert !list.contains(timers_cancelled(leashed), lands)
    && timers(leashed) == []
    as "the landing stays timed and no walk or home timer starts in flight"
  let #(_, landed) = fire(state:, at_ms: 1375, timer: lands)
  let assert [
    CreatureFaces(face: creature_turn.Point(..), ..),
    CreatureMoved(path: Running(from:, to:, started_ms:, ..)),
  ] = news_to(landed, 5)
    as "at the landing the creature turns to home and walks home, and the one watcher left is sent them"
  assert place_support.near(left: x_of(from), right: 20.0)
    && x_of(to) == 0.0
    && started_ms == start_ms + 1375
    as "from the landing at x = 20 to its spawn"
  assert list.length(timers(landed)) == 1 as "with the home timer of that walk"
}

pub fn a_second_throw_mid_flight_starts_from_where_the_first_had_reached_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, first_lands) = thrown_chasing(viewers: [2])
  // 150 ms into the 375 ms flight from x = 10 to 20: 0.4 of the way, at x = 14.
  let #(_, second) = tell(state:, at_ms: 1150, message: knockback())
  assert said(second) == ["0x638 to 2"]
  let assert [CreatureMoved(path:)] = news_to(second, 2)
  let assert [#(first_ms, first_x), #(last_ms, last_x)] = timed_xs(path:)
  assert first_ms == start_ms + 1150
    && place_support.near(left: first_x, right: 14.0)
    && last_ms == start_ms + 1525
    && place_support.near(left: last_x, right: 24.0)
    as "from x = 14 to 10 further, over 375 ms from the second throw"
  assert timers_cancelled(second) == [first_lands]
    as "the first flight's end is cancelled"
  assert list.map(timers(second), fn(timer) { timer.1 }) == [375]
}

pub fn a_stale_flight_end_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, first_lands) = thrown_chasing(viewers: [2])
  let #(state, second) = tell(state:, at_ms: 1150, message: knockback())
  let #(state, _) =
    tell(state:, at_ms: 1300, message: moved(number: 2, x: 50.0, seq: 2))
  let #(state, stale) = fire(state:, at_ms: 1375, timer: first_lands)
  assert said(stale) == [] && timers(stale) == []
    as "the first flight's end, of an older generation, does nothing"
  let #(state, still_flying) =
    tell(state:, at_ms: 1400, message: moved(number: 2, x: 51.0, seq: 3))
  assert said(still_flying) == []
    as "the creature is still in its second flight: the stale end did not land it"
  let #(_, landed) = fire(state:, at_ms: 1525, timer: timer_for(second, 375))
  assert said(landed) == ["0x638 to 2"]
    as "the second flight's own end lands the creature, and it chases the target at 51"
}

pub fn a_creature_killed_mid_flight_lies_at_the_landing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, lands) = thrown_chasing(viewers: [2, 5])
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1100,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 60, 1.0)]),
    )
  assert !list.contains(said(killed), "0x638(placed) to 5")
    as "no kind 2: the viewers' kind 3 path holds its last point"
  assert timers_cancelled(killed) == [lands] as "the flight's end is cancelled"
  let #(_, watched) =
    tell(
      state:,
      at_ms: 3000,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  let assert [CreatureAppeared(place:, ..), ..] = news_to(watched, 9)
  assert place_support.near(left: x_of(place), right: 20.0)
    as "a viewer arriving later finds the corpse at the landing"
}

pub fn an_arriving_viewer_mid_flight_is_sent_the_rest_of_the_path_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _, _) = thrown_chasing(viewers: [2])
  // 100 ms into the flight from x = 10 to 20: x = 10 + 10 x 100 / 375.
  let #(_, watched) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "turn(kind 18, unit 20)", "0x638"]
    as "the creature in combat, its target, the turn to it, and its flight"
  let assert [CreatureAppeared(place:, ..), _, _, _, CreatureMoved(path:)] =
    news_to(watched, 9)
  assert place_support.near(
    left: x_of(place),
    right: 10.0 +. 10.0 *. 100.0 /. 375.0,
  )
    as "it appears where it is in the flight"
  let assert [#(first_ms, first_x), #(last_ms, last_x)] = timed_xs(path:)
  assert first_ms == start_ms + 1100
    && place_support.near(left: first_x, right: 10.0 +. 10.0 *. 100.0 /. 375.0)
    && last_ms == start_ms + 1375
    && place_support.near(left: last_x, right: 20.0)
    as "the rest of the path: from there, now, to the landing"
}

pub fn a_turret_is_not_thrown_test() -> Nil {
  use <- owned_test.run(5000)
  // The sim turret's run speed is 0: a creature that never moves ignores a throw.
  let #(state, aggro) = fought(viewers: [2])
  let #(state, thrown) = tell(state:, at_ms: 100, message: knockback())
  assert said(thrown) == [] && timers(thrown) == []
    as "no path, no timer, no news"
  let #(_, opened) = fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  assert said(opened) == ["0x7ff to 2"] as "and the fight goes on as it was"
}

// ---- a creature placed as part of a map object ----

/// The Thrasher Fern (Creature2 28318) of the world database's spawn 10663, placed as
/// part of the map object 1238827 (`active_prop_id`), with a Beast's attack and its run
/// speed of 10, so that only its link keeps it still. Started for these viewers.
fn fern(viewers viewers: List(Int)) -> State {
  beast_from(
    source: spawn_source.Stored(id: SpawnId(10_663)),
    spawn: Spawn(
      ..spawn_support.battle_beast(number: 10_663, x: 0.0),
      creature_id: Creature2Id(28_318),
      world_object_id: 1_238_827,
    ),
    viewers:,
    armor: creature_life.NoArmor,
  )
}

pub fn a_creature_placed_as_part_of_a_map_object_attacks_a_target_in_reach_from_where_it_stands_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: fern(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  assert sends_no_path(aggro) as "the target is within reach 8: no move"
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == ["0x7ff to 2", "Attacks to 2"]
    as "the tick strikes the target and sends no movement message"
  assert stands_at(state:, at_ms: 1500) == 0.0 as "it stands at its spawn point"
}

pub fn a_creature_placed_as_part_of_a_map_object_does_not_chase_a_target_that_leaves_its_reach_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: fern(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  // 30 off: beyond reach 8 and within the leash range 55 of home, where a creature that
  // moves would chase.
  let #(state, away) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 30.0, seq: 2))
  assert said(away) == [] as "no path to the target"
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == [] as "the tick starts no chase and strikes nobody"
  let #(state, later) =
    fire(state:, at_ms: 3000, timer: timer_for(ticked, 1500))
  assert said(later) == []
  assert stands_at(state:, at_ms: 10_000) == 0.0
    as "at its spawn point, after the time a chase of 26 units at 10 would take"
}

pub fn a_creature_placed_as_part_of_a_map_object_leaves_combat_without_a_walk_home_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: fern(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 700,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(said(leashed), "0x89a(0) to 5")
    as "the only player on the threat list is gone: the creature leaves combat"
  assert sends_no_path(leashed) && timers(leashed) == []
    as "it is at home already: no walk, no arrival timer, no home timer"
  let #(_, struck) =
    tell(
      state:,
      at_ms: 800,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 5, 1.0)]),
    )
  assert !list.contains(said(struck), "Refused(Returning) to 5")
    as "it is not Returning, so the next player's strike lands"
}

pub fn a_creature_placed_as_part_of_a_map_object_leaves_combat_in_place_when_its_target_is_beyond_its_leash_range_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    tell(
      state: fern(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  // 100 off is beyond the leash range 55 of home.
  let #(state, away) =
    tell(state:, at_ms: 100, message: moved(number: 2, x: 100.0, seq: 2))
  assert said(away) == [] as "no path to the target"
  let #(state, ticked) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert list.contains(said(ticked), "0x89a(0) to 5")
    as "the target is beyond the leash range: the creature leaves combat"
  assert sends_no_path(ticked) && timers(ticked) == []
    as "it walks nowhere: no path, no arrival timer, no home timer"
  assert stands_at(state:, at_ms: 20_000) == 0.0
    as "it stands at its spawn point"
}

pub fn a_creature_placed_as_part_of_a_map_object_is_not_moved_by_a_forced_move_test() -> Nil {
  use <- owned_test.run(5000)
  // Its run speed is 10, so only its link keeps it where it is: a knockback (away, in
  // flight), a pull (toward a unit at x = 20, in flight) and a push (away, at once).
  let moves = [
    #(
      "knockback",
      forced_move.Away,
      forced_move.Flight,
      map_spawn_support.at(-5.0),
    ),
    #(
      "pull",
      forced_move.Toward,
      forced_move.Flight,
      map_spawn_support.at(20.0),
    ),
    #("push", forced_move.Away, forced_move.AtOnce, map_spawn_support.at(-5.0)),
  ]
  list.each(moves, fn(one) {
    let #(name, way, mover, unit_at) = one
    let #(state, aggro) =
      tell(
        state: fern(viewers: [2]),
        at_ms: 0,
        message: approached(number: 2, x: 5.0, seq: 1),
      )
    let #(state, thrown) =
      tell(
        state:,
        at_ms: 100,
        message: creature.Thrown(throw: forced_move.Throw(
          move: forced_move.Move(
            way:,
            mover:,
            min_distance: 10.0,
            max_distance: 10.0,
            flight_ms: 375,
            gravity: 0.0,
            flags: 0,
            height: 0.0,
          ),
          draws: forced_move.Draws(distance: 0.0, angle: 0.0),
          reference: forced_move.Reference(place: unit_at, radius: 0.0),
        )),
      )
    assert said(thrown) == [] && timers(thrown) == []
      as { name <> ": no path, no flight timer, no news" }
    assert stands_at(state:, at_ms: 100) == 0.0
      && stands_at(state:, at_ms: 1000) == 0.0
      as { name <> ": it stands at its spawn point" }
    let #(_, struck) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
    assert said(struck) == ["0x7ff to 2", "Attacks to 2"]
      as { name <> ": the fight goes on as it was" }
  })
}

pub fn the_same_creature_placed_with_no_map_object_chases_test() -> Nil {
  use <- owned_test.run(5000)
  let free =
    beast_from(
      source: spawn_source.Stored(id: SpawnId(10_663)),
      spawn: Spawn(
        ..spawn_support.battle_beast(number: 10_663, x: 0.0),
        creature_id: Creature2Id(28_318),
        world_object_id: 0,
      ),
      viewers: [2, 5],
      armor: creature_life.NoArmor,
    )
  let #(_, aggro) =
    tell(state: free, at_ms: 0, message: approached(number: 2, x: 30.0, seq: 1))
  let assert Running(to:, speed:, ..) = path_sent(aggro)
  assert x_of(to) == 26.0 && speed == 10.0
    as "30 - 0.5 x 8, at run speed 10: the link, not the creature, keeps it still"
}

// A creature's special: Rootbrute Grimspore's Earthen Roar (Spell4 55317). The client's
// rows, read for this block (each value below is from them):
// - Spell4 55317: castTime 3000, targetMaxRange 5.0, Spell4AoeTargetConstraints 116 (angle
//   360, targetCount 10, minRange 0, maxRange 10.0), Spell4CCConditions 1 (ccStateMask
//   218 960 739).
// - SpellPhase 11191 (phaseDelay 2500) and 11192 (phaseDelay 500): gos at 2500 and 3000 ms,
//   the first with phase 0 and the second, the strike, phase 1.
// - Spell4Effects 131967 (type 8, damage, targetFlags 4, phaseFlags 2: go 1) and 131968
//   (type 35, targetFlags 1, durationTime 1000, phaseFlags 0xffff0002: go 1).
// - TelegraphDamage 7880: shape 4, a cone from 0 to 5.5 m, 40 degrees across, on the
//   caster (targetTypeFlags 1), so the special's reach is the smaller of 10.0 and 5.5.
// - The 10 000 ms cooldown is a server choice, a guess (nothing in the client or the retail
//   record gives a cadence).
// The creature is the Virtual Battle Beast of this file (it moves, 8.0 reach for its
// instant attack 5649 every 1500 ms) with the special planted by hand.

/// A beast that casts the special, at the origin facing -z, for these viewers, `Started` taken.
fn rootbrute_with(
  special special: creature_life.Special,
  viewers viewers: List(Int),
) -> State {
  let spawn = spawn_support.battle_beast(number: 1, x: 0.0)
  started_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(
      ..spawn,
      combat: creature_life.Combat(..spawn.combat, specials: [special]),
    ),
    kind: beast_kind(),
    viewers:,
    armor: creature_life.NoArmor,
  )
}

fn rootbrute(viewers viewers: List(Int)) -> State {
  rootbrute_with(special: spawn_support.earthen_roar(hold_ms: 1000), viewers:)
}

/// The creature fought by player 2, who comes near 4 units ahead of it at 0 ms: the state
/// and the step of the aggro, which starts the first attack tick at 1500 ms.
fn roar_fought(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  turn_fought(state: rootbrute(viewers:))
}

/// The attack tick of 1500 ms opens the special: the state, the step of its start and the
/// timer of its first go, 2500 ms later.
fn roar_opened(
  state state: State,
  aggro aggro: ServiceStep(creature.Outgoing),
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, opened) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  #(state, opened, timer_for(opened, 2500))
}

/// The first go at 4000 ms (1500 + 2500): the state, the step and the timer of the strike
/// go, 500 ms later.
fn first_go_passed(
  state state: State,
  go go: step.TimerId,
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, passed) = fire(state:, at_ms: 4000, timer: go)
  #(state, passed, timer_for(passed, 500))
}

/// The strike go at 4500 ms.
fn strike_go_reached(
  state state: State,
  strike strike: step.TimerId,
) -> #(State, ServiceStep(creature.Outgoing)) {
  fire(state:, at_ms: 4500, timer: strike)
}

fn casts_of(
  taken: ServiceStep(creature.Outgoing),
  number: Int,
) -> List(unit_news.News) {
  list.filter(news_to(taken, number), fn(news) {
    creature_news_support.name_of(news) == "0x7ff"
  })
}

pub fn a_ready_special_in_reach_is_chosen_and_opens_its_cast_test() -> Nil {
  use <- owned_test.run(5000)
  // The target is 4 units ahead, within the special's 5.5 and the instant attack's 8: the
  // special is chosen, being first listed and ready. The beast moves, so it first turns to
  // face its target (0x638); a creature that cannot move aims itself.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(_, opened) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(opened) == ["0x638 to 2", "0x7ff to 2"]
    as "the facing, then the cast of the special: no strike yet"
  let assert [CastStarted(start:)] = casts_of(opened, 2)
  assert start.spell4_id == 55_317
    && start.caster_unit_id == 7
    && start.primary_target_unit_id == 20
    as "Earthen Roar, cast by the creature on its target"
  assert fights_told(opened) == []
  assert list.map(timers(opened), fn(timer) { timer.1 }) == [2500]
    as "one timer, the first go 2500 ms later (SpellPhase 11191), and no attack tick"
}

pub fn the_specials_cast_start_carries_the_entries_of_its_server_placed_rows_test() -> Nil {
  use <- owned_test.run(5000)
  // Earthen Roar's row 7880 has TelegraphDamage flags 0x105000 and targetTypeFlags 1: the client
  // draws it only at a telegraph position of (7880, the caster), which it looks up for the
  // caster's initial position (`0x140546e60`, `spell.telegraph_position`). The creature at the
  // origin turns to its target 3 ahead and 3 aside first, so the pose is yaw pi / 4 (the
  // `turned_to_face` kind 14 turn); the row has no offset or rotation.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: -3.0, z: -3.0, seq: 1),
    )
  let #(_, opened, _) = roar_opened(state:, aggro:)
  let assert [CastStarted(start:)] = casts_of(opened, 2)
  let pose = SpellPosition(x: 0, y: 0, z: 0)
  let yaw = float32.to_bits(0.785_398_163_397_448_3)
  assert start.initial_positions
    == [
      SpellInitialPosition(
        unit_id: 7,
        target_flags: 1,
        position: pose,
        yaw:,
        anchor_unit_id: 0,
      ),
    ]
    as "the caster's one initial position, at its turned pose, with the caster's role bit"
  assert start.telegraph_positions
    == [
      SpellTelegraphPosition(
        telegraph_damage_id: 7880,
        unit_id: 7,
        target_flags: 1,
        position: pose,
        yaw:,
        anchor_unit_id: 0,
      ),
    ]
    as "the entry the cone is drawn from: row 7880 on the caster, at the same pose"
}

pub fn a_creature_that_can_move_turns_to_face_its_target_before_the_special_test() -> Nil {
  use <- owned_test.run(5000)
  // The client never turns a creature by itself (`creature.facing`) and the cone is drawn from
  // the 0x7ff's entry, which holds the facing the creature has when the cast starts
  // (`0x14054b1b0.fixed_placement`): the target 3 ahead and 3 aside is at atan2(3, 3) = pi / 4
  // off the creature's facing, which is the yaw of a kind 14 turn.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: -3.0, z: -3.0, seq: 1),
    )
  let #(_, opened, _) = roar_opened(state:, aggro:)
  assert list.map(news_to(opened, 2), creature_news_support.name_of)
    == ["0x638", "0x7ff"]
    as "the turn goes before the cast"
  let assert [
    CreatureMoved(path: Timed(first:, rest: [], turned_to: Some(facing))),
    ..
  ] = news_to(opened, 2)
    as "a one-point timed path that turns the creature"
  assert place_support.near(left: facing.yaw, right: 0.785_398_163_397_448_3)
    && start_place.x(first.1) == 0.0
    as "turned along the bearing to the target, in place"
}

pub fn a_special_on_cooldown_leaves_the_auto_attack_and_is_ready_again_after_it_test() -> Nil {
  use <- owned_test.run(5000)
  // The cooldown (10 000 ms, a guess) counts from the cast's start at 1500 ms, so the special
  // is ready again at 11 500 ms.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  let hold = timer_for(closed, 1000)
  let #(state, after) = fire(state:, at_ms: 5600, timer: hold)
  let assert [CastStarted(start: auto_start)] = casts_of(after, 2)
  assert auto_start.spell4_id == 5649
    as "on cooldown: the instant attack of the kind is cast"
  let assert [#(2, Attacks(tell: Strike(key: auto_key, ..)))] =
    fights_told(after)
    as "and it strikes at once"
  let #(state, _) = tell(state:, at_ms: 5700, message: landed(key: auto_key))
  let #(state, still_on) =
    fire(state:, at_ms: 11_499, timer: timer_for(after, 1500))
  let assert [CastStarted(start: auto_again)] = casts_of(still_on, 2)
  assert auto_again.spell4_id == 5649
    as "1 ms before the cooldown ends it is still the instant attack"
  let assert [#(2, Attacks(tell: Strike(key: again_key, ..)))] =
    fights_told(still_on)
  let #(state, _) = tell(state:, at_ms: 11_499, message: landed(key: again_key))
  let #(_, ready) =
    fire(state:, at_ms: 11_500, timer: timer_for(still_on, 1500))
  let assert [CastStarted(start: again)] = casts_of(ready, 2)
  assert again.spell4_id == 55_317
    as "at the cooldown's end the special is chosen"
}

pub fn a_new_fight_starts_with_its_specials_ready_test() -> Nil {
  use <- owned_test.run(5000)
  // The special's cooldown (to 11 500 ms) is spent at 1500 ms; the leash ends the fight
  // at 5000 ms, the creature is home and a player sees it and comes near again at 7000 ms: the new
  // fight's first tick casts the special.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, _) = roar_opened(state:, aggro:)
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let home = timer_for(leashed, 0)
  let #(state, _) = fire(state:, at_ms: 5000, timer: home)
  let #(state, _) =
    tell(
      state:,
      at_ms: 6500,
      message: creature_news_support.seen(
        by: ConnectionId(2),
        stay: map_support.stay(count: 2),
      ),
    )
  let #(state, again) =
    tell(
      state:,
      at_ms: 7000,
      message: approached_at(number: 2, x: 0.0, z: -4.0, seq: 5),
    )
  let #(_, ticked) = fire(state:, at_ms: 8500, timer: timer_for(again, 1500))
  let assert [CastStarted(start:)] = casts_of(ticked, 2)
  assert start.spell4_id == 55_317
    as "before 11 500 ms, the special is cast again: a new fight starts with its specials ready"
}

pub fn a_target_beyond_every_reach_is_chased_and_not_cast_at_test() -> Nil {
  use <- owned_test.run(5000)
  // 30 units ahead: beyond the special's 5.5 and the instant attack's 8, so the creature
  // chases and casts nothing.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -30.0, seq: 1),
    )
  assert list.contains(said(aggro), "0x638 to 2")
    as "out of reach of both: a chase"
  let #(_, chased) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert casts_of(chased, 2) == [] as "and no cast"
}

pub fn a_creature_holding_a_state_casts_no_special_test() -> Nil {
  use <- owned_test.run(5000)
  // A state held (a stun, landed at 1000 ms, ending 2500 ms later) starts no charge
  // (`creature_fight` doc), so the tick at 1500 ms casts nothing: not the special, and not the
  // instant attack, which a Stun refuses.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, stunned) = stunned_at(state:, at_ms: 1000)
  assert list.contains(said(stunned), "0x87f to 2")
  let #(_, ticked) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(ticked) == [] && casts_of(ticked, 2) == []
    as "no cast while the state holds"
}

pub fn the_gos_wait_the_phase_delays_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  assert list.map(timers(opened), fn(timer) { timer.1 }) == [2500]
    as "the first go 2500 ms after the cast (SpellPhase 11191)"
  let #(_, passed) = fire(state:, at_ms: 4000, timer: go)
  assert list.map(timers(passed), fn(timer) { timer.1 }) == [500]
    as "the second 500 ms after the first (SpellPhase 11192)"
}

pub fn a_late_go_timer_arms_the_next_go_for_what_is_left_of_its_due_time_test() -> Nil {
  use <- owned_test.run(5000)
  // The cast started at 1500 ms, so the second go is due at 4500 ms whenever the first is
  // handled: 300 ms late leaves 200 ms; later than the due time leaves 0.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(_, late) = fire(state:, at_ms: 4300, timer: go)
  assert list.map(timers(late), fn(timer) { timer.1 }) == [200]
  let #(_, later) = fire(state:, at_ms: 5000, timer: go)
  assert list.map(timers(later), fn(timer) { timer.1 }) == [0]
  // Ice Breath's go 1 (due at 4,500 ms) handled 300 ms late strikes then: its deadline is
  // 1,000 ms from then, and go 2 (due at 5,000 ms) is armed for the 200 ms left.
  let #(state, aggro) = ice_fought(viewers: [2])
  let #(state, _, first) = ice_opened(state:, aggro:)
  let #(state, zero) = fire(state:, at_ms: 4100, timer: first)
  let #(_, struck) = fire(state:, at_ms: 4800, timer: timer_for(zero, 400))
  assert struck_numbers(struck) == [2]
  assert list.sort(list.map(timers(struck), fn(timer) { timer.1 }), int.compare)
    == [200, 1000]
    as "the deadline 1,000 ms from the late handling, and the next go for what is left"
}

pub fn a_go_before_the_strike_is_sent_with_its_phase_and_no_target_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(_, passed, strike) = first_go_passed(state:, go:)
  assert said(passed) == ["0x7f4 to 2"] && fights_told(passed) == []
    as "the go, and no strike"
  let assert [CastWent(went)] = news_to(passed, 2)
  assert went.phase == 0
    && went.targets == []
    && went.cast_id == cast_id_sent(opened, 2)
    as "phase 0, no unit, the cast's id"
  assert strike != go as "the next go's timer is of a new generation"
}

pub fn the_strike_go_strikes_only_the_fighters_inside_the_cone_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature faces its target, player 2, 4 ahead. The cone reaches 5.5 and is 40
  // degrees across, grown by a player's hit radius 1.2. Player 5 stands 2 ahead and 0.5 aside:
  // inside. Player 6 stands 5 aside and level with the creature: within 5.5 of it, but 90
  // degrees off the facing: outside.
  let #(state, aggro) = roar_fought(viewers: [2, 5, 6])
  let state = with_player_at(state:, number: 5, x: 0.5, z: -2.0)
  let state = with_player_at(state:, number: 6, x: 5.0, z: 0.0)
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(_, struck) = strike_go_reached(state:, strike:)
  assert struck_numbers(struck) == [2, 5]
    as "players 2 and 5 are struck; 6 is not"
  let assert [#(_, Attacks(tell: Strike(key:, striker:, offence:, ..))), ..] =
    fights_told(struck)
  assert key.occasion == strike_tell.AtGo(phase: 1)
    && key.cast_id == cast_id_sent(opened, 2)
    as "the strike go is phase 1, under the cast's id"
  assert striker == CreatureStriker(unit_id: 7, spell4_id: Spell4Id(55_317))
    as "named by the creature and the special"
  assert list.map(offence.blows, fn(blow) { blow.spell4_effects_id })
    == [131_967]
    as "the damage effect, Spell4Effects 131967"
  assert list.map(timers(struck), fn(timer) { timer.1 }) == [1000]
    as "the strike deadline, and no attack tick while the round is open"
}

pub fn a_specials_cone_faces_its_target_test() -> Nil {
  use <- owned_test.run(5000)
  // The target stands 3 ahead and 3 aside, so the creature turns 45 degrees to it when the cast
  // begins and stays so (the client does not turn it, and the server's cone follows the facing
  // the client has). Player 5 stands straight ahead at 5: 45 degrees off the new facing, outside
  // the cone even grown by 1.2. The target then walks round to the other side: it is outside
  // the cone, which has not turned.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2, 5]),
      at_ms: 0,
      message: approached_at(number: 2, x: -3.0, z: -3.0, seq: 1),
    )
  let state = with_player_at(state:, number: 5, x: 0.0, z: -5.0)
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(_, struck) = strike_go_reached(state:, strike:)
  assert list.map(fights_told(struck), fn(told) { told.0 }) == [2]
    as "the target on the facing is struck, player 5 straight ahead is not"
  let #(state, aggro) = roar_fought(viewers: [2, 5])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, walked) =
    tell(
      state:,
      at_ms: 4200,
      message: moved_at(number: 2, x: 4.0, z: -1.0, seq: 3),
    )
  assert said(walked) == [] as "the creature does not move while it casts"
  let #(_, struck) = strike_go_reached(state:, strike:)
  assert fights_told(struck) == []
    as "the target walked off the cone, which has not turned"
}

/// Player `number` joins the threat list by a light strike and stands at `x`, `z`.
fn with_player_at(
  state state: State,
  number number: Int,
  x x: Float,
  z z: Float,
) -> State {
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number:, cast_id: number, blows: [#(1, 1, 0.5)]),
    )
  let #(state, _) =
    tell(state:, at_ms: 200, message: moved_at(number:, x:, z:, seq: 2))
  state
}

pub fn the_closing_go_carries_the_strike_phase_and_the_finish_follows_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert said(closed)
    == ["0x7f4 to 2", "0x7fe to 2", "turn(kind 18, unit 20) to 2"]
    as "the go lists the struck player, then the cast finishes, then the creature turns to its target again"
  let assert [CastWent(went), CastFinished(cast_id:), _] = news_to(closed, 2)
  assert went.phase == 1
    && list.map(went.targets, fn(target) { target.unit_id }) == [20]
    && went.cast_id == cast_id_sent(opened, 2)
    && cast_id == went.cast_id
    as "phase 1 names player 2 under the cast's id"
  // Nobody inside at the strike go: the go names no unit.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, walked) =
    tell(
      state:,
      at_ms: 4200,
      message: moved_at(number: 2, x: 20.0, z: 0.0, seq: 3),
    )
  assert said(walked) == []
  let #(_, empty) = strike_go_reached(state:, strike:)
  assert said(empty)
    == ["0x7f4 to 2", "0x7fe to 2", "turn(kind 18, unit 20) to 2"]
    as "no strike, the go and the finish, then the creature turns to its target again"
  let assert [CastWent(went), ..] = news_to(empty, 2)
  assert went.phase == 1 && went.targets == []
}

pub fn an_answer_after_the_deadline_is_left_out_of_a_specials_go_test() -> Nil {
  use <- owned_test.run(5000)
  // The strike round's rule is the same for a special: the deadline closes the round, and a
  // late answer finds no round.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, deadline) =
    fire(state:, at_ms: 5500, timer: timer_for(struck, 1000))
  let assert [CastWent(went), ..] = news_to(deadline, 2)
  assert went.phase == 1 && went.targets == []
    as "the deadline closes the go with nobody in it"
  let #(_, late) = tell(state:, at_ms: 5600, message: landed(key:))
  assert said(late) == [] && timers(late) == []
    as "the answer after it changes nothing"
}

pub fn the_next_attack_tick_waits_the_delay_rows_hold_after_a_special_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 131968 (type 35, aimed at the caster, durationTime 1000, on go 1). What
  // the client does with type 35 is not in its code (`Spell4Effects.effectType.35`): the
  // hold is a guess, counted from the round's close.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert list.map(timers(closed), fn(timer) { timer.1 }) == [1000]
    as "the next attack tick starts 1000 ms after the round closes"
}

pub fn a_special_with_no_delay_row_waits_the_attack_interval_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    turn_fought(
      state: rootbrute_with(
        special: spawn_support.earthen_roar(hold_ms: 0),
        viewers: [2],
      ),
    )
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert list.map(timers(closed), fn(timer) { timer.1 }) == [1500]
    as "the kind's attack interval"
}

pub fn a_creature_in_its_hold_neither_chases_nor_strikes_test() -> Nil {
  use <- owned_test.run(5000)
  // The hold runs from 4600 ms to 5600 ms. The target runs 30 off at 5000 ms: the creature,
  // which would chase, stands; a tick of an old generation does nothing; the hold's own tick
  // then acts.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  let #(state, moved) =
    tell(
      state:,
      at_ms: 5000,
      message: moved_at(number: 2, x: 0.0, z: -30.0, seq: 3),
    )
  assert said(moved) == [] as "no chase while it holds"
  let #(state, old) = fire(state:, at_ms: 5100, timer: timer_for(aggro, 1500))
  assert said(old) == [] && timers(old) == []
    as "the first tick of the fight is of an old generation"
  let #(_, acted) = fire(state:, at_ms: 5600, timer: timer_for(closed, 1000))
  assert list.contains(said(acted), "0x638 to 2")
    as "when the hold's tick fires the creature chases the target"
}

/// The special's fight with players 2 and 3 on its threat list, 3 the target, the cast open at
/// 1500 ms, and the target runs to 30 ahead during the cast (the creature starts no path: it
/// casts). The strike go at 4500 ms then finds player 2 alone inside the cone: the round is
/// `Striking`, awaiting player 2's answer, with the target far out of reach. The state and the
/// key of the strike told to player 2.
fn roar_striking_with_a_far_target() -> #(State, strike_tell.Key) {
  let #(state, aggro) = roar_fought(viewers: [2, 3])
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 3, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 200,
      message: moved_at(number: 3, x: 0.0, z: -3.0, seq: 2),
    )
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, running) =
    tell(
      state:,
      at_ms: 2000,
      message: moved_at(number: 3, x: 0.0, z: -30.0, seq: 3),
    )
  assert said(running) == [] as "no path while the cast is open"
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
    as "player 2 alone is in the cone"
  #(state, key)
}

pub fn no_path_starts_while_a_charged_round_strikes_or_holds_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature stands through the cast, the strikes and the hold that follows a special (a
  // guess for the last: `Spell4Effects.effectType.35`). Every way the fight asks for a chase,
  // each with the target 30 away so that a chase would start, starts none: the target moves,
  // a fighter that is not the target leaves, a state that held it ends, and the answer that
  // kills a fighter retargets.
  let #(striking, key) = roar_striking_with_a_far_target()
  let #(_, moved) =
    tell(
      state: striking,
      at_ms: 4600,
      message: moved_at(number: 3, x: 0.0, z: -31.0, seq: 4),
    )
  assert sends_no_path(moved) as "the target moves while the strikes are out"
  let #(_, left) =
    tell(
      state: striking,
      at_ms: 4600,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert sends_no_path(left) as "a fighter leaves while the strikes are out"
  let #(stunned_state, stunned) = stunned_at(state: striking, at_ms: 4550)
  let assert [#(control_ends, _), ..] = control_timers(stunned)
    as "the stun starts its own timer"
  let #(_, ended) = fire(state: stunned_state, at_ms: 4700, timer: control_ends)
  assert sends_no_path(ended)
    as "the state that held it ends while the strikes are out"
  let #(held_state, killed) =
    tell(state: striking, at_ms: 4600, message: killing_answer(key:))
  assert sends_no_path(killed)
    as "the answer that kills fighter 2 closes the round and retargets, with the hold set first"
  let #(_, in_hold) =
    tell(
      state: held_state,
      at_ms: 4700,
      message: moved_at(number: 3, x: 0.0, z: -32.0, seq: 5),
    )
  assert sends_no_path(in_hold) as "the target moves in the hold"
}

pub fn a_ready_special_closes_to_its_own_reach_test() -> Nil {
  use <- owned_test.run(5000)
  // The target is 6.5 ahead: beyond the special's 5.5 (the cone's far edge) and within the
  // instant attack's 8. The special is ready, so the creature goes for it: it runs in from
  // the start of the fight, to within the special's reach, and the first tick casts the
  // special, not the instant attack.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -6.5, seq: 1),
    )
  let assert Running(to:, ..) = path_sent(aggro)
  assert creature_path.distance(from: to, to: at_xz(x: 0.0, z: -6.5)) <=. 5.5
    as "the path ends within the special's reach of the target"
  let #(_, cast) = fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let assert [CastStarted(start:)] = casts_of(cast, 2)
  assert start.spell4_id == 55_317
    as "with the target in its reach the special is cast, and fights_told is empty until its go"
  assert fights_told(cast) == []
}

pub fn a_special_that_adds_the_targets_radius_casts_from_that_much_farther_test() -> Nil {
  use <- owned_test.run(5000)
  // The client holds the gap between the two edges to the spell's range (`0x1403b2240`), so a
  // special that adds the target's hit radius (1.2 for a player) to its reach of 16 casts at
  // 17.0 (within 17.2) and runs in from 17.5 to within 17.2; one that does not add it runs in
  // from 17.0 to within 16. Each target stands beyond the instant attack's reach of 8.
  list.each(
    [
      #(True, -17.0, None, "within the reach and the target's radius: a cast"),
      #(True, -17.5, Some(17.2), "beyond them: the creature runs in"),
      #(False, -17.0, Some(16.0), "17.0 is beyond 16 without the radius"),
    ],
    fn(row) {
      let #(adds_target_radius, z, ends_within, reason) = row
      let roar = spawn_support.earthen_roar(hold_ms: 1000)
      let special =
        creature_life.Special(
          ..roar,
          attack: creature_life.Attack(
            ..roar.attack,
            reach: 16.0,
            adds_target_radius:,
          ),
        )
      let #(state, aggro) =
        tell(
          state: rootbrute_with(special:, viewers: [2]),
          at_ms: 0,
          message: approached_at(number: 2, x: 0.0, z:, seq: 1),
        )
      case ends_within {
        None -> {
          assert sends_no_path(aggro) as reason
          let #(_, cast) =
            fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
          let assert [CastStarted(start:)] = casts_of(cast, 2)
          assert start.spell4_id == 55_317 as reason
        }
        Some(reach) -> {
          let assert Running(to:, ..) = path_sent(aggro)
          assert creature_path.distance(from: to, to: at_xz(x: 0.0, z:))
            <=. reach
            as reason
        }
      }
    },
  )
}

pub fn a_state_between_gos_breaks_the_special_and_the_cooldown_stays_spent_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, stunned) = stunned_at(state:, at_ms: 4200)
  assert list.drop_while(said(stunned), fn(line) { line != "0x87f to 2" })
    == ["0x87f to 2", "0x7f9 to 2"]
    as "the state, then the broken cast: 0x7f9 (the viewer's connection writes the 0x7fe after it)"
  let assert [unit_news.CastInterrupted(cast_id:)] =
    list.filter(news_to(stunned, 2), fn(news) {
      creature_news_support.name_of(news) == "0x7f9"
    })
  assert cast_id == cast_id_sent(opened, 2)
  assert list.contains(timers_cancelled(stunned), strike)
    as "the pending go's timer is cancelled"
  assert list.contains(list.map(timers(stunned), fn(timer) { timer.1 }), 1500)
    as "the next attack tick comes after the interval, not the hold"
  let #(_, late) = strike_go_reached(state:, strike:)
  assert said(late) == [] && timers(late) == []
    as "the go's timer that fires all the same finds no cast: nothing strikes"
  let #(state, held) =
    fire(state:, at_ms: 5700, timer: timer_for(stunned, 1500))
  assert said(held) == [] as "the state still holds: no cast"
  let ends = timer_for(stunned, 2500)
  let #(state, _) = fire(state:, at_ms: 6700, timer: ends)
  let #(_, after) = fire(state:, at_ms: 7200, timer: timer_for(held, 1500))
  let assert [CastStarted(start:)] = casts_of(after, 2)
  assert start.spell4_id == 5649
    as "the cooldown the broken cast spent (to 11 500 ms) is still running: the instant attack"
}

/// Earthen Roar's cast with a cast time of 0 and the first gos of a Multiphase special that
/// starts at 0 (Savage Shred, Spell4 34252: delays 0, 1, 199, 500): the gos at 0 and 1 ms
/// strike nobody, the three after strike with the roar's cone.
fn roar_with_gos_at_0_and_1_ms() -> creature_life.Special {
  spawn_support.special_with_charged(
    special: spawn_support.earthen_roar(hold_ms: 1000),
    change: fn(cast) {
      let assert creature_life.Charged(inside:, ..) = cast
        as "Earthen Roar is a charge"
      let strike =
        Some(creature_life.GoStrike(spell4_effects_ids: [131_967], inside:))
      creature_life.Charged(..cast, cast_ms: 0, gos: [
        creature_life.Go(at_ms: 0, strike: None),
        creature_life.Go(at_ms: 1, strike: None),
        creature_life.Go(at_ms: 200, strike:),
        creature_life.Go(at_ms: 700, strike:),
        creature_life.Go(at_ms: 1200, strike:),
      ])
    },
  )
}

pub fn a_state_that_lands_after_two_gos_at_0_and_1_ms_breaks_only_the_gos_to_come_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    turn_fought(
      state: rootbrute_with(special: roar_with_gos_at_0_and_1_ms(), viewers: [2]),
    )
  let #(state, opened) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  assert said(opened) == ["0x638 to 2", "0x7ff to 2"]
    as "the 0x7ff comes with the turn, and no go is written in it"
  let #(state, first) = fire(state:, at_ms: 1500, timer: timer_for(opened, 0))
  assert said(first) == ["0x7f4 to 2"]
    as "the go at 0 writes its entry, striking nobody"
  let #(state, second) = fire(state:, at_ms: 1501, timer: timer_for(first, 1))
  assert said(second) == ["0x7f4 to 2"] as "and the go at 1 ms"
  let strike = timer_for(second, 199)
  let #(state, stunned) = stunned_at(state:, at_ms: 1600)
  assert list.drop_while(said(stunned), fn(line) { line != "0x87f to 2" })
    == ["0x87f to 2", "0x7f9 to 2"]
    as "the state, then the broken cast: 0x7f9 (the viewer's connection writes the 0x7fe after it)"
  let assert [unit_news.CastInterrupted(cast_id:)] =
    list.filter(news_to(stunned, 2), fn(news) {
      creature_news_support.name_of(news) == "0x7f9"
    })
  assert cast_id == cast_id_sent(opened, 2)
  assert list.contains(timers_cancelled(stunned), strike)
    as "the pending go's timer is cancelled"
  assert list.contains(list.map(timers(stunned), fn(timer) { timer.1 }), 1500)
    as "the next attack tick comes after the interval, not the hold"
  let #(state, late) = fire(state:, at_ms: 1700, timer: strike)
  assert said(late) == [] && fights_told(late) == [] && timers(late) == []
    as "the go at 200 ms fires all the same and strikes nobody: no strike of the gos to come is told"
  let #(state, held) =
    fire(state:, at_ms: 3100, timer: timer_for(stunned, 1500))
  assert said(held) == [] as "the state still holds: no cast"
  let #(state, _) = fire(state:, at_ms: 4100, timer: timer_for(stunned, 2500))
  let #(_, after) = fire(state:, at_ms: 4600, timer: timer_for(held, 1500))
  let assert [CastStarted(start:)] = casts_of(after, 2)
  assert start.spell4_id == 5649
    as "the cooldown the broken cast spent (to 11 500 ms) is still running: the instant attack"
}

pub fn an_interrupt_after_the_strike_go_breaks_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, stunned) = stunned_at(state:, at_ms: 4550)
  assert !list.contains(said(stunned), "0x7f9 to 2")
    as "the strikes are out: nothing breaks"
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert list.contains(said(closed), "0x7f4 to 2") as "the go still goes"
}

pub fn death_between_gos_ends_the_special_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, killed) =
    tell(
      state:,
      at_ms: 4200,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 1_000_000, 1.0)]),
    )
  assert list.contains(said(killed), "0x7fe to 2")
    as "the cast finishes with the death"
  assert !list.contains(said(killed), "0x7f4 to 2")
    as "and the strike go never went"
  assert list.contains(timers_cancelled(killed), strike)
    as "the pending go's timer is cancelled"
  let #(_, late) = strike_go_reached(state:, strike:)
  assert said(late) == [] && timers(late) == []
}

pub fn leash_between_gos_ends_the_special_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 4200,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert list.contains(timers_cancelled(leashed), strike)
    as "the pending go's timer is cancelled"
  let #(_, late) = strike_go_reached(state:, strike:)
  assert said(late) == [] && timers(late) == []
    as "and its late firing does nothing"
}

pub fn a_stale_go_timer_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, again) = fire(state:, at_ms: 4100, timer: go)
  assert said(again) == [] && timers(again) == []
    as "the first go's timer fires again after it went: it is of an old generation"
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, _) = tell(state:, at_ms: 4600, message: landed(key:))
  let #(_, after) = fire(state:, at_ms: 4700, timer: strike)
  assert said(after) == [] && timers(after) == []
    as "the strike go's timer fires after the round closed: nothing"
}

pub fn a_second_attack_tick_during_a_special_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, _) = roar_opened(state:, aggro:)
  let #(_, again) = fire(state:, at_ms: 2000, timer: timer_for(aggro, 1500))
  assert said(again) == [] && timers(again) == []
    as "the tick that opened the cast fires again: no second 0x7ff and no new tick"
}

pub fn a_viewer_arriving_between_gos_gets_the_open_cast_and_the_gos_so_far_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let watched_at = fn(state, at_ms, number) {
    tell(
      state:,
      at_ms:,
      message: creature_news_support.seen(
        by: ConnectionId(number),
        stay: map_support.stay(count: number),
      ),
    )
  }
  let #(state, watched) = watched_at(state, 4200, 9)
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff", "0x7f4"]
    as "the fight, the open cast, then the go that went"
  let assert [_, _, _, CastStarted(start:), CastWent(went)] =
    news_to(watched, 9)
  assert start.cast_id == cast_id_sent(opened, 2)
    && start.spell4_id == 55_317
    && went.cast_id == start.cast_id
    && went.phase == 0
    && went.targets == []
    as "the same cast and its first go, so the later go names it"
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, watched) = watched_at(state, 4550, 8)
  assert list.map(news_to(watched, 8), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff", "0x7f4"]
    as "while the strikes are out the same: the cast and the first go"
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert list.contains(said(closed), "0x7f4 to 9")
    && list.contains(said(closed), "0x7fe to 8")
    as "both viewers are told the strike go and the finish"
}

pub fn the_sim_turrets_charge_has_one_go_that_strikes_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 85469: castTime 8000 and no phases (Spell4 85469, 86978): one go, at the cast time,
  // that strikes, and no hold.
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let assert creature_life.Charged(cast_ms:, gos:, hold_ms:, inside:, ..) =
    spawn.combat.attack.cast
  assert cast_ms == 8000 && hold_ms == 0 as "the cast time 8000, and no hold"
  let assert [creature_life.Go(at_ms: 8000, strike: Some(strike))] = gos
    as "one go, at 8000 ms, that strikes"
  assert strike.inside == inside && strike.spell4_effects_ids == [224_644]
    as "with the charge's own shapes and its damage row, Spell4Effects 224644 (type 8, every phase)"
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, ends) = charge_opened(state:, aggro:)
  let #(state, went) = fire(state:, at_ms: 11_000, timer: ends)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(went)
  assert key.occasion == strike_tell.AtGo(phase: 0)
  let #(_, closed) = tell(state:, at_ms: 11_100, message: landed(key:))
  let assert [CastWent(go), ..] = news_to(closed, 2)
  assert go.phase == 0 as "the go is phase 0"
  assert list.map(timers(closed), fn(timer) { timer.1 }) == [3000]
    as "the next attack tick after the interval: no hold"
}

/// The special's fight with players 2 and 3 on its threat list, 3 the target (a strike of 3
/// damage against the aggro threat of 1 that player 2 came with), both standing in the cone
/// ahead of the creature, the cast open at 1500 ms and its first go gone at 4000 ms: the state
/// and the timer of the strike go.
fn roar_fought_by_two() -> #(State, step.TimerId) {
  let #(state, aggro) = roar_fought(viewers: [2, 3])
  let #(state, _) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 3, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 200,
      message: moved_at(number: 3, x: 0.0, z: -3.0, seq: 2),
    )
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  #(state, strike)
}

pub fn a_fighter_who_is_not_the_target_leaving_between_gos_leaves_the_cast_to_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 leaves sight at 4200 ms, between the gos. The threat list still holds 3, the
  // target, so the fight goes on: the cast and its pending go are left alone, and the strike
  // go strikes the one fighter that is left.
  let #(state, strike) = roar_fought_by_two()
  let #(state, left) =
    tell(
      state:,
      at_ms: 4200,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert !list.contains(said(left), "0x7f9 to 3")
    && !list.contains(said(left), "0x7fe to 3")
    as "the cast goes on for the viewer that is left"
  assert timers_cancelled(left) == []
    as "the pending go's timer stands: the fight did not end"
  let #(_, struck) = strike_go_reached(state:, strike:)
  let assert [#(3, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  assert key.occasion == strike_tell.AtGo(phase: 1)
    as "the strike go tells player 3 alone to take the hit"
}

pub fn the_target_leaving_between_gos_leaves_the_cast_and_the_strike_goes_to_the_next_fighter_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 3, the target, leaves sight at 4200 ms; 2 is the next on the threat list. The
  // fight goes on with 2 as its target and the cast is not broken.
  let #(state, strike) = roar_fought_by_two()
  let #(state, left) =
    tell(
      state:,
      at_ms: 4200,
      message: creature_news_support.unseen(by: ConnectionId(3)),
    )
  assert list.contains(said(left), "0x908(20, 1) to 2")
    as "the creature's target becomes player 2"
  assert !list.contains(said(left), "0x7f9 to 2")
    && !list.contains(said(left), "0x7fe to 2")
    as "the cast goes on for the viewer that is left"
  assert timers_cancelled(left) == []
    as "the pending go's timer stands: the fight did not end"
  let #(_, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  assert key.unit_id == 20 as "the strike go tells player 2 to take the hit"
}

pub fn a_control_before_the_first_gos_timer_breaks_the_cast_and_the_late_timer_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // The stun lands at 2000 ms, 500 ms after the cast opened; the first go was due at 4000.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, stunned) = stunned_at(state:, at_ms: 2000)
  let assert [unit_news.CastInterrupted(cast_id:)] =
    list.filter(news_to(stunned, 2), fn(news) {
      creature_news_support.name_of(news) == "0x7f9"
    })
  assert cast_id == cast_id_sent(opened, 2)
    as "the broken cast is the one that opened"
  assert list.contains(timers_cancelled(stunned), go)
    as "the first go's timer is cancelled"
  let #(_, late) = fire(state:, at_ms: 4000, timer: go)
  assert said(late) == [] && timers(late) == []
    as "the timer that fires all the same finds no cast: no go is sent"
}

pub fn a_death_after_the_strike_go_leaves_the_strikes_that_went_out_standing_test() -> Nil {
  use <- owned_test.run(5000)
  // The strike go at 4500 ms tells player 2 to take the hit; the creature is killed at
  // 4550 ms, before the answer. The strike told is not taken back, the go never goes, and
  // the answer that comes after is dropped: nothing is sent twice.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, killed) =
    tell(
      state:,
      at_ms: 4550,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 1_000_000, 1.0)]),
    )
  assert fights_told(killed) == [#(2, Released(unit_id: 7))]
    as "the death releases the player; no strike is told again and none is taken back"
  assert list.contains(said(killed), "0x7fe to 2")
    && !list.contains(said(killed), "0x7f4 to 2")
    as "the cast finishes with the death and the strike go never goes"
  let #(_, answered) = tell(state:, at_ms: 4600, message: landed(key:))
  assert said(answered) == [] && timers(answered) == []
    as "the answer of the strike already out is dropped"
}

pub fn a_despawn_between_gos_finishes_the_cast_removes_the_creature_and_starts_its_respawn_test() -> Nil {
  use <- owned_test.run(5000)
  // A despawn of delay 0 arrives at 4200 ms (the go that sent it struck at 4100): the fight
  // ends and the cast finishes (0x7fe) before the viewers are told the creature is gone
  // (0x355); the kind's respawn time, 60 000 ms, starts; the go's timer that fires after
  // finds nothing.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, gone) =
    tell(
      state:,
      at_ms: 4200,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 4200),
    )
  let to_2 =
    list.filter(said(gone), fn(line) { string.ends_with(line, " to 2") })
  assert list.drop_while(to_2, fn(line) { line != "0x7fe to 2" })
    == ["0x7fe to 2", "0x89a(0) to 2", "Released(7) to 2", "0x355 to 2"]
    as "the fight ends (the cast finishes, the player is released), then the creature is removed from view"
  assert list.contains(timers_cancelled(gone), strike)
    as "the pending go's timer is cancelled"
  assert list.map(timers(gone), fn(timer) { timer.1 }) == [60_000]
    as "the corpse timer for the kind's respawn time"
  let #(_, late) = strike_go_reached(state:, strike:)
  assert said(late) == [] && timers(late) == []
    as "the go's late timer does nothing"
}

pub fn a_retire_between_gos_stops_the_creature_and_sends_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // A live creature told to retire stops at once and sends no news, whether a viewer is still
  // held or the map has taken the viewer's sight away first (the leash then finished the
  // cast): the map's removal is the client's cleanup, as `Retire`'s doc says.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, _) = first_go_passed(state:, go:)
  let #(_, retired) = tell(state:, at_ms: 4200, message: creature.Retire)
  assert support.effects_of(retired) == [step.Stop]
    as "stops at once, in the middle of its cast, with no 0x7fe"
  let #(state, _) =
    tell(
      state:,
      at_ms: 4200,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, retired) = tell(state:, at_ms: 4300, message: creature.Retire)
  assert support.effects_of(retired) == [step.Stop]
    as "the same once the map has removed the viewer"
}

// A creature's auto-attacks in turn: the Virtual Battle Beast (Creature2 73464) built as the
// load builds a creature (`spawn_support.autos_creature`), given these auto-attacks by its
// kind. The retail record lists a creature's pair of auto-attacks (Skeech Scratcher's Punch 5649
// and Jab 5652) and the client's Spell4 descriptions number them "#1" and "#2"
// (`table_rows -- Spell4 5649 5652`); the order is a guess. From the client's rows: 5649 and
// 5652 have the same damage rows (184741, 184742 for difficulty up to 6), both for 12 at the
// Beast's level; targetMaxRange 5.0 (a reach of 5.0 + 3.0, the Beast's hit radius) and Scrab's
// 25870 has 10.0 (reach 13.0). The attack interval is 1500 ms (migration 0010, a server choice).

/// The Beast with these auto-attacks in turn, started for these viewers, `Started` taken.
fn striking_in_turn(
  spell4_ids spell4_ids: List(Int),
  viewers viewers: List(Int),
) -> State {
  started_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: spawn_support.autos_creature(
      number: 1,
      creature_id: 73_464,
      spell4_ids:,
    ),
    kind: creature_kind.kind_of(
      kinds: spawn_support.kinds_with_beast_autos(spell4_ids:),
      creature2_id: 73_464,
    ),
    viewers:,
    armor: creature_life.NoArmor,
  )
}

/// Player 2 comes near 4 units ahead of the creature at 0 ms: the state and the step of the
/// aggro, which starts the first attack tick at 1500 ms.
fn turn_fought(state state: State) -> #(State, ServiceStep(creature.Outgoing)) {
  tell(
    state:,
    at_ms: 0,
    message: approached_at(number: 2, x: 0.0, z: -4.0, seq: 1),
  )
}

/// The attack tick `tick` at `at_ms`, which strikes player 2: the state after player 2's
/// answer 100 ms later, the step of the tick and the Spell4 its cast start and its strike name.
fn tick_strikes(
  state state: State,
  at_ms at_ms: Int,
  tick tick: step.TimerId,
) -> #(State, ServiceStep(creature.Outgoing), Int) {
  let #(state, taken) = fire(state:, at_ms:, timer: tick)
  let assert [CastStarted(start:)] = casts_of(taken, 2)
    as "the tick casts one attack at its viewer"
  let assert [#(2, Attacks(tell: Strike(key:, striker:, ..)))] =
    fights_told(taken)
    as "and strikes player 2"
  assert striker
    == CreatureStriker(unit_id: unit, spell4_id: Spell4Id(start.spell4_id))
    as "the strike names the spell the 0x7ff does"
  let #(state, _) = tell(state:, at_ms: at_ms + 100, message: landed(key:))
  #(state, taken, start.spell4_id)
}

pub fn a_creature_strikes_its_auto_attacks_in_turn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    turn_fought(state: striking_in_turn(spell4_ids: [5649, 5652], viewers: [2]))
  let #(state, first, lead) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  let #(state, second, alternate) =
    tick_strikes(state:, at_ms: 3000, tick: timer_for(first, 1500))
  let #(_, _, again) =
    tick_strikes(state:, at_ms: 4500, tick: timer_for(second, 1500))
  assert [lead, alternate, again] == [5649, 5652, 5649]
    as "the lead first, then the alternate, then the lead again: the page's Punch and Jab, #1 and #2"
  let assert [#(2, Attacks(tell: Strike(offence:, ..)))] = fights_told(second)
  assert list.map(offence.blows, fn(blow) { blow.spell4_effects_id })
    == [184_742]
    as "the alternate's strike carries its own damage row, 184742, not the lead's 184741"
}

pub fn each_auto_attack_waits_the_attack_interval_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    turn_fought(state: striking_in_turn(spell4_ids: [5649, 5652], viewers: [2]))
  let #(state, first, _) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  let #(_, second, _) =
    tick_strikes(state:, at_ms: 3000, tick: timer_for(first, 1500))
  let delays = fn(taken) {
    list.sort(list.map(timers(taken), fn(timer) { timer.1 }), int.compare)
  }
  assert delays(first) == [1000, 1500]
    as "the lead's strike starts the strike deadline and the next tick after the interval"
  assert delays(second) == [1000, 1500]
    as "the alternate's strike waits the same interval"
}

pub fn a_refused_auto_attack_does_not_advance_the_turn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    turn_fought(state: striking_in_turn(spell4_ids: [5649, 5652], viewers: [2]))
  let #(state, first, lead) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  assert lead == 5649 as "the lead strikes first"
  // A stun landed at 2000 ms ends 2500 ms later, at 4500 ms; a Stun refuses an instant attack.
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 2000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let state_ends = timer_for(stunned, 2500)
  let #(state, refused) =
    fire(state:, at_ms: 3000, timer: timer_for(first, 1500))
  assert casts_of(refused, 2) == [] && fights_told(refused) == []
    as "the tick finds the player in reach and strikes nothing: the creature is stunned"
  let #(state, _) = fire(state:, at_ms: 4500, timer: state_ends)
  let #(_, _, next) =
    tick_strikes(state:, at_ms: 4500, tick: timer_for(refused, 1500))
  assert next == 5652
    as "the refused tick left the turn where it was: the alternate, due after the lead, strikes"
}

pub fn a_special_between_autos_leaves_the_turn_unchanged_test() -> Nil {
  use <- owned_test.run(5000)
  // The special, ready at the start of the fight, is cast at the first tick (1500 ms); its
  // strike go is at 4500 ms and the hold ends at 5600 ms. The auto-attack after it is the lead,
  // the one that was due, and the alternate follows.
  let beast =
    spawn_support.autos_creature(number: 1, creature_id: 73_464, spell4_ids: [
      5649,
      5652,
    ])
  let state =
    started_from(
      source: spawn_source.Stored(id: SpawnId(1)),
      spawn: Spawn(
        ..beast,
        combat: creature_life.Combat(..beast.combat, specials: [
          spawn_support.earthen_roar(hold_ms: 1000),
        ]),
      ),
      kind: creature_kind.kind_of(
        kinds: spawn_support.kinds_with_beast_autos(spell4_ids: [5649, 5652]),
        creature2_id: 73_464,
      ),
      viewers: [2],
      armor: creature_life.NoArmor,
    )
  let #(state, aggro) = turn_fought(state:)
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  let #(state, after, first_auto) =
    tick_strikes(state:, at_ms: 5600, tick: timer_for(closed, 1000))
  assert first_auto == 5649
    as "after the special the creature strikes the lead: the special took no turn"
  let #(_, _, second_auto) =
    tick_strikes(state:, at_ms: 7100, tick: timer_for(after, 1500))
  assert second_auto == 5652 as "and then the alternate"
}

pub fn a_new_fight_opens_with_the_lead_auto_attack_test() -> Nil {
  use <- owned_test.run(5000)
  // The lead strikes at 1500 ms, so the alternate is due; the leash ends the fight at 5000 ms,
  // the creature is home, and a player comes near again at 7000 ms: the new fight's first
  // tick strikes the lead.
  let #(state, aggro) =
    turn_fought(state: striking_in_turn(spell4_ids: [5649, 5652], viewers: [2]))
  let #(state, _, _) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 5000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(state, _) = fire(state:, at_ms: 5000, timer: timer_for(leashed, 0))
  let #(state, _) =
    tell(
      state:,
      at_ms: 6500,
      message: creature_news_support.seen(
        by: ConnectionId(2),
        stay: map_support.stay(count: 2),
      ),
    )
  let #(state, again) =
    tell(
      state:,
      at_ms: 7000,
      message: approached_at(number: 2, x: 0.0, z: -4.0, seq: 5),
    )
  let #(_, _, first) =
    tick_strikes(state:, at_ms: 8500, tick: timer_for(again, 1500))
  assert first == 5649
    as "a fight opens with the lead, not the alternate the earlier fight left due"
}

pub fn the_next_alternates_reach_is_closed_in_on_test() -> Nil {
  use <- owned_test.run(5000)
  // Scrab's Pinch 25870 (targetMaxRange 10.0, reach 13.0) leads and Punch 5649 (reach 8.0)
  // follows. The target stands 10 ahead: the lead strikes from there; the alternate does not
  // reach it, so the next tick runs in to the alternate's reach, and the one after strikes.
  let #(state, aggro) =
    tell(
      state: striking_in_turn(spell4_ids: [25_870, 5649], viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  assert !list.contains(said(aggro), "0x638 to 2")
    as "within the lead's reach 13.0 no path starts"
  let #(state, first, lead) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  assert lead == 25_870 as "the lead strikes from 10 away"
  let #(state, closing) =
    fire(state:, at_ms: 3000, timer: timer_for(first, 1500))
  assert casts_of(closing, 2) == [] && fights_told(closing) == []
    as "the alternate's 8.0 does not reach the target: no strike"
  assert list.contains(said(closing), "0x638 to 2")
    as "the creature runs in to the alternate's reach"
  let #(_, _, alternate) =
    tick_strikes(state:, at_ms: 4500, tick: timer_for(closing, 1500))
  assert alternate == 5649 as "then the alternate strikes"
}

pub fn a_round_naming_an_alternates_spell_finds_its_attack_test() -> Nil {
  use <- owned_test.run(5000)
  // The alternate's strike is out at 3000 ms; at 3100 ms a modifier doubles the creature's
  // Physical damage (property 141) and its values are worked out again; player 2's answer at
  // 3200 ms names the alternate's spell, which the creature finds among its alternates.
  let #(state, aggro) =
    turn_fought(state: striking_in_turn(spell4_ids: [5649, 5652], viewers: [2]))
  let #(state, first, _) =
    tick_strikes(state:, at_ms: 1500, tick: timer_for(aggro, 1500))
  let #(state, second) =
    fire(state:, at_ms: 3000, timer: timer_for(first, 1500))
  let assert [#(2, Attacks(tell: Strike(key:, offence:, ..)))] =
    fights_told(second)
  assert list.map(offence.blows, fn(blow) { blow.damage }) == [Worked(12)]
    as "the alternate's blow before the change: 12"
  let #(state, _) =
    tell(
      state:,
      at_ms: 3100,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 141, factor: 2.0),
      ),
    )
  let #(state, answered) = tell(state:, at_ms: 3200, message: landed(key:))
  assert !list.contains(said(answered), "Refused(Dead)")
    as "the answer is taken: the round's spell is found among the alternates"
  let #(_, third) = fire(state:, at_ms: 4500, timer: timer_for(second, 1500))
  let assert [#(2, Attacks(tell: Strike(offence: lead_offence, ..)))] =
    fights_told(third)
  assert list.map(lead_offence.blows, fn(blow) { blow.damage }) == [Worked(24)]
    as "the next strike, the lead's, is worked out from the doubled multiplier: 12 x 2"
}

// ---- a fighting creature keeps facing its target (movement kind 18, 19 and 14) ----
// Evidence: `movement_command.kind_18` (a unit faced every update until a later rotation
// command), `movement_command.kind_19` (a point), `movement_command.kind_14.facing` (the yaw
// that faces a target at (dx, dz) is atan2(-dx, -dz)) and `creature.facing` (the client turns a
// creature only by those commands; a path of kind 4 leaves its rotation). The choices the
// client does not settle are the server's (guesses): a Stun, Knockdown, Knockback or an opened
// guard stands the creature as it faces; a Root leaves it turning; the creature turns again at
// the close of a charged round and through the hold after it.

/// The faces the step sends viewer `number`, in order.
fn faces_to(
  taken: ServiceStep(creature.Outgoing),
  number: Int,
) -> List(creature_turn.Face) {
  news_to(taken, number)
  |> list.filter(fn(news) {
    string.starts_with(creature_news_support.name_of(news), "turn(")
  })
  |> list.map(fn(news) {
    let assert CreatureFaces(face:, ..) = news as "a turn news is CreatureFaces"
    face
  })
}

/// The yaw that faces a target at (dx, dz) from a creature, by the client's own direction
/// (`movement_command.kind_14.facing`): atan2(-dx, -dz). A target along +x is minus a quarter
/// turn, along -x a quarter turn, along -z (ahead of a creature that faces 0) 0.
const quarter_turn = 1.5707963267948966

fn yaw_of_face(face: creature_turn.Face) -> Float {
  let assert creature_turn.Fixed(facing:) = face as "a fixed facing"
  facing.yaw
}

fn home() -> start_place.Place {
  spawn_support.battle_beast(number: 1, x: 0.0).place
}

/// The lines of the step that are the turn of the creature or a path, in order: what a client
/// is told about where the creature faces and runs.
fn turns_and_paths(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.filter(said(taken), fn(line) {
    string.starts_with(line, "turn(") || string.starts_with(line, "0x638")
  })
}

pub fn a_creature_that_takes_its_target_faces_it_before_it_runs_test() -> Nil {
  use <- owned_test.run(5000)
  // Aggro by a walk-in 30 off: the turn goes after 0x908, 0x89a and the threat told to the
  // player, and before the path, since a kind 4 path does not turn the creature.
  let #(_, aggro) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  assert said(aggro)
    == [
      "0x908(20, 1) to 2", "0x89a(1) to 2", "Threatened(7, 3) to 2",
      "turn(kind 18, unit 20) to 2", "0x638 to 2",
    ]
    as "0x908, 0x89a, the turn to the player's unit, then the path"
  let assert [CreatureFaces(face:, at_ms:)] =
    list.filter(news_to(aggro, 2), fn(news) {
      string.starts_with(creature_news_support.name_of(news), "turn(")
    })
  assert face == creature_turn.Unit(unit_id: 20) && at_ms == start_ms
    as "kind 18 names the player's unit, at the step's monotonic time"
  // The same for a strike on a resting creature.
  let #(_, struck) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 5, 1.0)]),
    )
  assert list.filter(said(struck), fn(line) {
      string.starts_with(line, "0x908")
      || string.starts_with(line, "0x89a")
      || string.starts_with(line, "turn(")
    })
    == ["0x908(20, 5) to 2", "0x89a(1) to 2", "turn(kind 18, unit 20) to 2"]
    as "a strike that starts the fight turns the creature after the 0x908 and 0x89a"
}

pub fn a_target_circling_a_creature_in_reach_sends_the_viewers_nothing_new_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature runs toward 26 (30 less half its reach 8), then the player circles it: each
  // place is within reach 8 of the path's end, so no path, and the client keeps the creature
  // facing the unit (`movement_command.kind_18`): nothing is sent.
  let #(state, _) = chasing(viewers: [2])
  let places = [#(28.0, 3.0), #(24.0, 3.0), #(24.0, -3.0), #(28.0, -3.0)]
  let #(state, circled, _) =
    list.fold(places, #(state, [], 2), fn(so_far, place) {
      let #(state, sent, seq) = so_far
      let #(state, taken) =
        tell(
          state:,
          at_ms: 100 * seq,
          message: moved_at(number: 2, x: place.0, z: place.1, seq:),
        )
      #(state, [taken, ..sent], seq + 1)
    })
  assert list.length(circled) == 4
    && list.all(circled, fn(taken) { said(taken) == [] && timers(taken) == [] })
    as "four moves round the creature send no turn, no path and start no timer"
  let #(_, away) =
    tell(state:, at_ms: 700, message: moved(number: 2, x: 45.0, seq: 9))
  assert said(away) == ["0x638 to 2"]
    as "a move beyond reach of the path's end plans a new path, which sends no turn"
}

pub fn a_target_that_takes_the_threat_turns_the_creature_to_it_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(state, topped) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 2.0)]),
    )
  assert faces_to(topped, 2) == [creature_turn.Unit(unit_id: 50)]
    && faces_to(topped, 5) == [creature_turn.Unit(unit_id: 50)]
    as "player 5's strike tops the list: one turn to player 5, to each viewer"
  let #(state, again) =
    tell(
      state:,
      at_ms: 200,
      message: strike_of(number: 5, cast_id: 2, blows: [#(1, 5, 1.0)]),
    )
  let #(_, lower) =
    tell(
      state:,
      at_ms: 300,
      message: strike_of(number: 2, cast_id: 3, blows: [#(1, 1, 1.0)]),
    )
  assert faces_to(again, 2) == [] && faces_to(lower, 2) == []
    as "a strike by the target, or one that does not top it, sends no turn"
}

pub fn a_target_that_dies_or_is_unwatched_turns_the_creature_to_the_next_entry_and_a_last_one_makes_it_face_home_test() -> Nil {
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
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 2.0)]),
    )
  let #(_, died) =
    tell(state:, at_ms: 200, message: creature.PlayerDied(by: ConnectionId(5)))
  assert faces_to(died, 2) == [creature_turn.Unit(unit_id: 20)]
    as "the top entry's player died with another left: the turn is to the next entry"
  let #(_, unwatched) =
    tell(
      state:,
      at_ms: 200,
      message: creature_news_support.unseen(by: ConnectionId(5)),
    )
  assert faces_to(unwatched, 2) == [creature_turn.Unit(unit_id: 20)]
    as "and the same when it leaves sight"
  // The last entry leaves while the creature runs: it turns to home before the walk home.
  let #(state, _) = chasing(viewers: [2, 5])
  let #(_, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert turns_and_paths(leashed) == ["turn(kind 19, home) to 5", "0x638 to 5"]
    as "the leash turns the creature to home, then it runs there"
  assert faces_to(leashed, 5) == [creature_turn.Point(place: home())]
    as "kind 19 names the spawn's place"
}

pub fn a_charge_turns_the_creature_with_a_kind_14_and_holds_that_turn_until_the_round_closes_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 2 stands ahead; the cone is fixed from the wind-up to the round's close, whoever
  // takes the threat, and the creature turns to its target again only then.
  let #(state, aggro) = roar_fought(viewers: [2, 5])
  assert faces_to(aggro, 2) == [creature_turn.Unit(unit_id: 20)]
    as "the fight starts facing the target"
  let #(state, opened, go) = roar_opened(state:, aggro:)
  assert said(opened)
    == ["0x638 to 2", "0x638 to 5", "0x7ff to 2", "0x7ff to 5"]
    as "the kind 14 turn in place goes before the 0x7ff and replaces the kind 18"
  assert faces_to(opened, 2) == []
    as "no kind 18 or 19 is sent beside it: the charge's turn is the one rotation"
  let #(state, retargeted) =
    tell(
      state:,
      at_ms: 2000,
      message: strike_of(number: 5, cast_id: 9, blows: [#(1, 30, 1.0)]),
    )
  let #(state, moved_by_target) =
    tell(
      state:,
      at_ms: 2100,
      message: moved_at(number: 2, x: 1.0, z: -4.0, seq: 5),
    )
  assert faces_to(retargeted, 2) == []
    && faces_to(moved_by_target, 2) == []
    && said(moved_by_target) == []
    as "a new top entry and a moving target during the wind-up send no turn"
  let #(state, first, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  assert faces_to(first, 2) == [] && faces_to(struck, 2) == []
    as "the go and the strike go send no turn: the round is not closed"
  let #(_, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  assert said(closed)
    == [
      "0x7f4 to 2", "0x7f4 to 5", "0x7fe to 2", "0x7fe to 5",
      "turn(kind 18, unit 50) to 2", "turn(kind 18, unit 50) to 5",
    ]
    as "the close of the round, not the strike, turns the creature to its target, now player 5, after the go and the finish"
}

pub fn a_creature_in_the_hold_after_a_special_stands_still_and_faces_its_target_test() -> Nil {
  use <- owned_test.run(5000)
  // The hold (1000 ms after the close at 4600 ms, a guess of the client's NpcExecutionDelay)
  // starts no path, but the creature turns to the target it has, even a new one.
  let #(state, aggro) = roar_fought(viewers: [2, 5])
  let #(state, _, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(state, struck) = strike_go_reached(state:, strike:)
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(struck)
  let #(state, closed) = tell(state:, at_ms: 4600, message: landed(key:))
  let hold = timer_for(closed, 1000)
  let #(state, far) =
    tell(
      state:,
      at_ms: 4700,
      message: moved_at(number: 2, x: 0.0, z: -40.0, seq: 5),
    )
  assert said(far) == [] as "the target runs off: no path in the hold"
  let #(state, topped) =
    tell(
      state:,
      at_ms: 4800,
      message: strike_of(number: 5, cast_id: 9, blows: [#(1, 30, 1.0)]),
    )
  assert faces_to(topped, 2) == [creature_turn.Unit(unit_id: 50)]
    && sends_no_path(topped)
    as "a new target in the hold is faced, and no path starts"
  let #(_, ticked) = fire(state:, at_ms: 5600, timer: hold)
  assert list.contains(said(ticked), "0x7ff to 2")
    as "the next attack tick ends the hold"
}

pub fn a_stunned_creature_stands_turned_as_it_was_and_turns_again_when_the_state_ends_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature runs toward player 2, 30 off along +x, and is at 10 after a second: a Stun
  // stops it there, facing the player (minus a quarter turn, the way of +x), and it turns
  // again when the state ends, before it runs.
  let #(state, _) = chasing(viewers: [2])
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert turns_and_paths(stunned)
    == ["0x638(placed) to 2", "turn(kind 14) to 2"]
    as "the run stops where it stands, then one kind 14 holds the facing"
  let assert [face] = faces_to(stunned, 2)
  assert float.loosely_equals(
    yaw_of_face(face),
    0.0 -. quarter_turn,
    tolerating: 0.000_001,
  )
    as "along the bearing to the player at +x: atan2(-20, 0)"
  let #(state, moved) =
    tell(
      state:,
      at_ms: 1200,
      message: moved_at(number: 2, x: 30.0, z: 8.0, seq: 5),
    )
  assert said(moved) == [] as "the player moves: the stunned creature turns not"
  let #(_, ended) = fire(state:, at_ms: 3600, timer: timer_for(stunned, 2500))
  assert turns_and_paths(ended) == ["turn(kind 18, unit 20) to 2", "0x638 to 2"]
    as "when the state ends the creature turns to the player again, then runs"
}

pub fn a_rooted_creature_still_turns_to_its_target_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 30.0, seq: 1),
    )
  let #(state, rooted) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: crowd_control_state.Root,
          duration_ms: 5000,
          instance_id: 28_674,
        ),
      ]),
    )
  assert turns_and_paths(rooted) == ["0x638(placed) to 2", "0x638(placed) to 5"]
    as "a Root stops the run and sends no turn"
  let #(_, topped) =
    tell(
      state:,
      at_ms: 1100,
      message: strike_of(number: 5, cast_id: 2, blows: [#(1, 30, 1.0)]),
    )
  assert faces_to(topped, 2) == [creature_turn.Unit(unit_id: 50)]
    && sends_no_path(topped)
    as "the rooted creature still turns to a new target, and starts no path"
}

pub fn a_stun_ending_while_a_root_holds_turns_the_creature_again_and_starts_no_path_test() -> Nil {
  use <- owned_test.run(5000)
  // The outer rule: the creature stays still while the Root holds, so the Stun's end is no
  // `ControlEnded`, yet the creature may turn again.
  let #(state, _) = chasing(viewers: [2])
  let #(state, _) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: crowd_control_state.Root,
          duration_ms: 9000,
          instance_id: 28_674,
        ),
      ]),
    )
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1100,
      message: controlling(number: 2, cast_id: 2, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  assert list.length(faces_to(stunned, 2)) == 1
    as "the Stun stands the creature as it faces"
  let #(_, ended) = fire(state:, at_ms: 3700, timer: timer_for(stunned, 2500))
  assert faces_to(ended, 2) == [creature_turn.Unit(unit_id: 20)]
    as "the Stun ends while the Root holds: the creature turns to the player again"
  assert sends_no_path(ended) as "and starts no path, the Root holding"
}

/// The charger (a turret that moves) guarded as migration 0030 guards the turrets.
fn guarded_charger(viewers viewers: List(Int)) -> State {
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let assert Ok(kind) =
    dict.get(spawn_support.guarded_turret_kinds().by_creature, 73_494)
    as "migration 0030 gives the Exile turret its guarded kind"
  started_from(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(
      ..spawn,
      unit_type: creature_unit_type.NonPlayer,
      combat: creature_life.Combat(
        ..spawn.combat,
        attack: creature_life.Attack(..spawn.combat.attack, run_speed: 10.0),
      ),
    ),
    kind:,
    viewers:,
    armor: creature_life.NoArmor,
  )
}

pub fn a_root_that_breaks_a_charge_leaves_the_creature_standing_as_the_opened_guard_holds_it_test() -> Nil {
  use <- owned_test.run(5000)
  // The Root takes hold during the charge: the charge breaks, and the effect of the break
  // opens the guard, which the fight rule is told of by the creature's rule (`Reconsidered`),
  // so the creature ends standing as it faced, never left tracking its target.
  let #(state, aggro) =
    tell(
      state: guarded_charger(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  let #(state, opened, _) = charge_opened(state:, aggro:)
  assert faces_to(opened, 2) == [] as "the charge's kind 14 is the only turn"
  let #(state, broken) =
    tell(
      state:,
      at_ms: 4000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.holding(
          state: crowd_control_state.Root,
          duration_ms: 9000,
          instance_id: 28_674,
        ),
      ]),
    )
  let assert Ok(creature_turn.Fixed(..)) = list.last(faces_to(broken, 2))
    as "whatever the break sent, the last turn is a fixed facing: the opened creature stands"
  let #(_, moved) =
    tell(
      state:,
      at_ms: 4100,
      message: moved_at(number: 2, x: 5.0, z: -10.0, seq: 5),
    )
  assert said(moved) == []
    as "and it does not follow its target while the guard is open"
}

pub fn a_creature_that_cannot_move_is_never_sent_a_turn_test() -> Nil {
  use <- owned_test.run(5000)
  // A turret aims itself (`0x14046cdc0.turret_cast_aim`) and `creature.facing` leaves objects
  // to their own: aggro, retarget, charge and death send it no turn.
  let #(state, aggro) = fought(viewers: [2, 5])
  assert faces_to(aggro, 2) == [] as "aggro"
  let #(state, topped) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 30, 1.0)]),
    )
  assert faces_to(topped, 2) == [] as "retarget"
  let #(state, opened, _) = charge_opened(state:, aggro:)
  assert faces_to(opened, 2) == [] && !list.contains(said(opened), "0x638 to 2")
    as "charge: no kind 18 and no kind 14"
  let #(_, killed) =
    tell(
      state:,
      at_ms: 4000,
      message: killing(number: 5, cast_id: 2, controls: []),
    )
  assert faces_to(killed, 2) == [] && faces_to(killed, 5) == [] as "death"
}

pub fn a_leashed_creature_faces_home_while_it_runs_and_its_spawn_yaw_when_it_arrives_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert turns_and_paths(leashed) == ["turn(kind 19, home) to 5", "0x638 to 5"]
    as "the turn to home goes before the walk home"
  let #(_, arrived) = fire(state:, at_ms: 2000, timer: timer_for(leashed, 1000))
  assert faces_to(arrived, 5)
    == [creature_turn.Home(facing: start_place.facing(home()))]
    as "on arrival one turn gives the facing of the spawn's 0x262, which the viewer blends"
  // A leash while a Stun holds the creature starts no walk and no turn: both wait for the end
  // of the state.
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, held) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert turns_and_paths(held) == [] && timers(held) == []
    as "leashed in a stun: it stands as it faces and starts no walk"
  let #(_, ended) = fire(state:, at_ms: 3600, timer: timer_for(stunned, 2500))
  assert turns_and_paths(ended) == ["turn(kind 19, home) to 5", "0x638 to 5"]
    as "when the state ends the creature turns to home and walks"
}

/// The yaw of a creature at (x, z) that faces a target at (x, z), by the client's direction
/// (`movement_command.kind_14.facing`): atan2(-dx, -dz).
fn facing_yaw(from from: #(Float, Float), to to: #(Float, Float)) -> Float {
  maths.atan2(0.0 -. { to.0 -. from.0 }, 0.0 -. { to.1 -. from.1 })
}

pub fn a_target_standing_on_the_creature_leaves_the_facing_it_showed_last_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature runs toward 26, the player circles to (28, 3) at 200 ms, and at 1 s, with the
  // creature at (10, 0), the player steps onto its ground point: the client keeps the
  // creature as it faces the player's last place, along the bearing from (10, 0) to (28, 3),
  // and not the spawn's yaw or the yaw of the path (`movement_command.kind_18`).
  let #(state, _) = chasing(viewers: [2])
  let #(state, _) =
    tell(
      state:,
      at_ms: 200,
      message: moved_at(number: 2, x: 28.0, z: 3.0, seq: 2),
    )
  let #(state, onto) =
    tell(
      state:,
      at_ms: 1000,
      message: moved_at(number: 2, x: 10.0, z: 0.0, seq: 3),
    )
  assert faces_to(onto, 2) == []
    as "a target on the creature's point sends no turn"
  let turned = facing_yaw(from: #(10.0, 0.0), to: #(28.0, 3.0))
  assert turned != { start_place.facing(home()) }.yaw
    as "the turn the test starts from is a real one"
  let yaw_at = fn(state, at_ms) {
    {
      start_place.facing(creature_fight.place_at(
        state: creature.fight(state:),
        now_ms: start_ms + at_ms,
      ))
    }.yaw
  }
  assert float.loosely_equals(
    yaw_at(state, 1000),
    turned,
    tolerating: 0.000_001,
  )
    as "the creature shows the facing it had before the player stood on it"
  let #(_, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: killing(number: 2, cast_id: 1, controls: []),
    )
  let assert [face] = faces_to(killed, 2)
  assert float.loosely_equals(yaw_of_face(face), turned, tolerating: 0.000_001)
    as "and its death freezes that facing"
}

pub fn a_killed_or_despawned_creature_is_turned_where_it_faces_and_stops_following_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature runs toward 26, the player circles to (28, 3), and a killing blow lands at 1 s:
  // the creature is at (10, 0), so the corpse is turned along the bearing to (28, 3), the newest
  // sighting, after the kind 2 that stops its run. A kind 18 left to the client would turn
  // the corpse after the player.
  let #(state, _) = chasing(viewers: [2])
  let #(state, _) =
    tell(
      state:,
      at_ms: 200,
      message: moved_at(number: 2, x: 28.0, z: 3.0, seq: 2),
    )
  let #(state, killed) =
    tell(
      state:,
      at_ms: 1000,
      message: killing(number: 2, cast_id: 1, controls: []),
    )
  assert turns_and_paths(killed) == ["0x638(placed) to 2", "turn(kind 14) to 2"]
    as "the run stops, then one kind 14 freezes the facing"
  let assert [face] = faces_to(killed, 2)
  assert float.loosely_equals(
    yaw_of_face(face),
    facing_yaw(from: #(10.0, 0.0), to: #(28.0, 3.0)),
    tolerating: 0.000_001,
  )
    as "along the bearing from where it fell to the player's newest place"
  let #(state, later) =
    tell(
      state:,
      at_ms: 1100,
      message: moved_at(number: 2, x: 5.0, z: 5.0, seq: 3),
    )
  let #(state, again) =
    tell(
      state:,
      at_ms: 1200,
      message: killing(number: 2, cast_id: 2, controls: []),
    )
  assert said(later) == [] && faces_to(again, 2) == []
    as "a dead creature follows no one, and a second blow or a repeated death turns it no more"
  let #(_, expired) =
    fire(state:, at_ms: 61_000, timer: timer_for(killed, 60_000))
  assert faces_to(expired, 2) == []
    as "the corpse timer turns no one: the next life's fight, which turns it toward the player near it, is its start's"
  // A despawn is a death for the fight.
  let #(state, _) = chasing(viewers: [2])
  let #(_, gone) =
    tell(
      state:,
      at_ms: 1000,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 1000),
    )
  assert list.length(faces_to(gone, 2)) == 1
    as "a despawn freezes the facing as a death does"
}

pub fn a_creature_that_dies_walking_home_or_in_a_charge_or_in_flight_freezes_the_facing_it_had_test() -> Nil {
  use <- owned_test.run(5000)
  // Walking home from (10, 0) the creature faces home: at 1.2 s it is at (8, 0) and a despawn
  // freezes it facing +x's opposite, a quarter turn.
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, _) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, home_gone) =
    tell(
      state:,
      at_ms: 1200,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 1200),
    )
  let assert [face] = faces_to(home_gone, 5)
  assert float.loosely_equals(
    yaw_of_face(face),
    facing_yaw(from: #(8.0, 0.0), to: #(0.0, 0.0)),
    tolerating: 0.000_001,
  )
    as "walking home: frozen facing home, not stale"
  // In a charge the facing is the charge's already: nothing more is sent.
  let #(state, aggro) = roar_fought(viewers: [2])
  let #(state, _, _) = roar_opened(state:, aggro:)
  let #(_, charge_gone) =
    tell(
      state:,
      at_ms: 3000,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 3000),
    )
  assert faces_to(charge_gone, 2) == []
    as "a death in a charge adds no turn to the charge's kind 14"
  // In a flight the position movement is left alone: a rotation only, no kind 2.
  let #(state, thrown, _) = thrown_chasing(viewers: [2])
  assert faces_to(thrown, 2) == [] as "a throw that turns nothing sends no turn"
  let #(_, flight_gone) =
    tell(
      state:,
      at_ms: 1200,
      message: creature.Despawn(delay_ms: 0, went_at_ms: 1200),
    )
  let assert [face] = faces_to(flight_gone, 2)
    as "dying in flight sends one turn"
  let assert creature_turn.Fixed(..) = face
    as "the corpse is held by a kind 14, which no kind 19 toward a point it flies from can turn"
  assert !list.contains(said(flight_gone), "0x638(placed) to 2")
    as "dying in flight sends the turn alone: no kind 2 stops the flight the server still holds"
}

/// A knockback that turns the creature to face the unit that threw it (the row's flag 4,
/// `forced_move` `turn_of`).
fn turning_knockback() -> creature.Message {
  let assert creature.Thrown(throw:) = knockback() as "a knockback is a throw"
  creature.Thrown(
    throw: forced_move.Throw(
      ..throw,
      move: forced_move.Move(..throw.move, flags: 4),
    ),
  )
}

pub fn a_thrown_creature_is_turned_back_to_its_target_when_it_lands_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2])
  let #(state, thrown) = tell(state:, at_ms: 1000, message: turning_knockback())
  assert faces_to(thrown, 2) == []
    && list.length(list.filter(said(thrown), fn(line) { line == "0x638 to 2" }))
    == 1
    as "a throw whose path carries its own kind 14 sends only that path"
  let #(state, midway) =
    tell(
      state:,
      at_ms: 1200,
      message: moved_at(number: 2, x: 40.0, z: 6.0, seq: 5),
    )
  assert said(midway) == [] as "no turn during the flight"
  let #(_, landed) = fire(state:, at_ms: 1375, timer: timer_for(thrown, 375))
  assert turns_and_paths(landed)
    == ["turn(kind 18, unit 20) to 2", "0x638 to 2"]
    as "at the landing the creature turns to its target again, then runs"
}

pub fn a_viewer_arriving_mid_fight_is_sent_the_current_turn_after_the_0x262_test() -> Nil {
  use <- owned_test.run(5000)
  let watch = fn(state, at_ms) {
    tell(
      state:,
      at_ms:,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  }
  // In reach: the combat flag, the target, then the turn.
  let #(state, _) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(_, in_reach) = watch(state, 100)
  assert list.map(news_to(in_reach, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "turn(kind 18, unit 20)"]
    as "in reach: the turn after 0x908"
  // In a wind-up the 0x262 carries the cone's yaw, so no turn is sent: the player stands 4
  // along -x, a quarter turn from the spawn's yaw 0.
  let #(state, aggro) =
    tell(
      state: rootbrute(viewers: [2]),
      at_ms: 0,
      message: approached_at(number: 2, x: -4.0, z: 0.0, seq: 1),
    )
  let #(state, _, _) = roar_opened(state:, aggro:)
  let #(_, winding) = watch(state, 2000)
  let assert [CreatureAppeared(place:, ..), ..] = news_to(winding, 9)
  assert float.loosely_equals(
    { start_place.facing(place) }.yaw,
    quarter_turn,
    tolerating: 0.000_001,
  )
    as "mid-wind-up the 0x262 is turned as the cone is"
  assert list.map(news_to(winding, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff", "0x638"]
    || list.map(news_to(winding, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff"]
    as "and no turn news follows: the charge's rotation is fixed"
  // At rest: the 0x262 alone, in the spawn's facing.
  let #(_, rest) = watch(beast(viewers: [2]), 0)
  assert list.map(news_to(rest, 9), creature_news_support.name_of) == ["0x262"]
    as "at rest nothing follows the 0x262"
}

pub fn a_creatures_pose_follows_its_facing_test() -> Nil {
  use <- owned_test.run(5000)
  let yaw_at = fn(state, at_ms) {
    {
      start_place.facing(creature_fight.place_at(
        state: creature.fight(state:),
        now_ms: start_ms + at_ms,
      ))
    }.yaw
  }
  let #(state, _) = chasing(viewers: [2, 5])
  assert float.loosely_equals(
    yaw_at(state, 1000),
    0.0 -. quarter_turn,
    tolerating: 0.000_001,
  )
    as "chasing a player at +x: the bearing to the player's newest sighting"
  let #(leashed, _) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert float.loosely_equals(
    yaw_at(leashed, 1000),
    quarter_turn,
    tolerating: 0.000_001,
  )
    as "walking home from (10, 0): the bearing to home, along -x"
  assert float.loosely_equals(
    yaw_at(beast(viewers: [2]), 0),
    { start_place.facing(home()) }.yaw,
    tolerating: 0.000_001,
  )
    as "at rest: the spawn's yaw"
  let #(opened, _) = roar_fought(viewers: [2])
  assert float.loosely_equals(yaw_at(opened, 0), 0.0, tolerating: 0.000_001)
    as "facing a target straight ahead along -z: yaw 0"
}

pub fn a_creature_that_walks_home_and_finds_a_player_near_turns_to_the_spawn_before_it_turns_to_the_player_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 5 stands 3 off the spawn and is near while the creature fights player 2 and runs;
  // the leash walks it home, and its arrival aggroes player 5 at once: the spawn's facing,
  // then the new fight's turn, in that order.
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, _) =
    tell(state:, at_ms: 100, message: approached(number: 5, x: 3.0, seq: 1))
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, arrived) = fire(state:, at_ms: 2000, timer: timer_for(leashed, 1000))
  assert list.filter(said(arrived), fn(line) {
      string.starts_with(line, "turn(") || string.starts_with(line, "0x908")
    })
    == [
      "turn(kind 19, spawn facing) to 5", "0x908(50, 1) to 5",
      "turn(kind 18, unit 50) to 5",
    ]
    as "the spawn's facing, the new target, then the turn to it"
}

pub fn a_walk_home_after_a_leash_in_a_state_starts_one_fresh_arrival_timer_test() -> Nil {
  use <- owned_test.run(5000)
  // A Stun holds the creature while the leash comes: no walk, no timer. When the state ends
  // the walk starts with one arrival timer no running timer has the id of, and it fires once.
  let #(state, aggro) = chasing(viewers: [2, 5])
  let #(state, stunned) =
    tell(
      state:,
      at_ms: 1000,
      message: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
    )
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1100,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert timers(leashed) == [] as "no walk, so no arrival timer"
  let #(state, ended) =
    fire(state:, at_ms: 3600, timer: timer_for(stunned, 2500))
  let running =
    list.flatten([
      list.map(timers(aggro), fn(started) { started.0 }),
      list.map(timers(stunned), fn(started) { started.0 }),
    ])
  let started = list.map(timers(ended), fn(started) { started.0 })
  assert list.length(started) == 1
    && !list.any(started, fn(id) { list.contains(running, id) })
    as "the walk's arrival timer is new: no running timer has its id"
  let assert [#(arrival, 1000)] = timers(ended)
    as "the 10 units home take a second"
  let #(_, arrived) = fire(state:, at_ms: 4600, timer: arrival)
  assert faces_to(arrived, 5)
    == [creature_turn.Home(facing: start_place.facing(home()))]
    as "it arrives once, taking the spawn's facing, which the viewer blends"
}

// ---- the chase's arrival: the stop the client's walk animation needs
//
// A path the client runs ends silently, and the movement state the path frame carries
// (kind 11 and kind 24) never expires, so the creature that arrives is told it stands
// (`creature_fight` module doc). The beast at x = 0 chasing player 2 at x = 30 stops
// 0.5 x reach 8 = 4 short of it, at x = 26, 2600 ms on at run speed 10.

/// What a step does to the chase's arrival timer, in order.
type Arrival {
  ArrivalStarted(after_ms: Int)
  ArrivalCancelled
}

fn arrival_timers(taken: ServiceStep(creature.Outgoing)) -> List(Arrival) {
  list.filter_map(support.service_timers(taken), fn(timer) {
    case timer {
      #(id, Some(after_ms)) if id == creature.chase_arrival_timer ->
        Ok(ArrivalStarted(after_ms:))
      #(id, None) if id == creature.chase_arrival_timer -> Ok(ArrivalCancelled)
      #(_, _) -> Error(Nil)
    }
  })
}

/// The position of the first of `lines` that names `name`, or -1.
fn line_of(lines: List(String), name: String) -> Int {
  case list.drop_while(lines, fn(line) { !string.starts_with(line, name) }) {
    [] -> -1
    rest -> list.length(lines) - list.length(rest)
  }
}

pub fn a_chase_sends_the_turn_before_the_path_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = chasing(viewers: [2, 5])
  let #(_, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let cases = [
    #("a fight's start", aggro, "turn(kind 18, unit 20) to 5"),
    #("the walk home after a leash", leashed, "turn(kind 19, home) to 5"),
  ]
  list.each(cases, fn(row) {
    let #(reason, taken, turn) = row
    let lines = said(taken)
    assert line_of(lines, turn) >= 0
      && line_of(lines, turn) < line_of(lines, "0x638 to 5")
      as reason
  })
}

pub fn a_chase_path_cancels_and_restarts_the_arrival_timer_for_the_paths_end_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = chasing(viewers: [2, 5])
  let #(_, second) =
    tell(state:, at_ms: 1000, message: moved(number: 2, x: 60.0, seq: 2))
  let #(_, sped) =
    tell(
      state:,
      at_ms: 500,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 2.0),
      ),
    )
  let #(_, in_reach) =
    tell(
      state: beast(viewers: [2, 5]),
      at_ms: 0,
      message: approached(number: 2, x: 5.0, seq: 1),
    )
  let #(leash_state, _) = chasing(viewers: [2, 5])
  let #(leash_state, leashed) =
    tell(
      state: leash_state,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, home_sped) =
    tell(
      state: leash_state,
      at_ms: 1500,
      message: modifier_start(
        cast_id: 1,
        modifier: scaled_by(property: 100, factor: 2.0),
      ),
    )
  let cases = [
    #("the first path: 26 m at 10 m/s", first, [
      ArrivalCancelled,
      ArrivalStarted(after_ms: 2600),
    ]),
    #(
      "a second path from x = 10, clipped at the leash circle 55 from the spawn: 45 m, the old timer cancelled first, since the shell ends a creature that starts a running timer",
      second,
      [ArrivalCancelled, ArrivalStarted(after_ms: 4500)],
    ),
    #("a speed doubled 0.5 s in: 21 m left at 20 m/s", sped, [
      ArrivalCancelled,
      ArrivalStarted(after_ms: 1050),
    ]),
    #("a target in reach: no path", in_reach, []),
    #("the walk home of a leash has its own timer", leashed, []),
    #("a speed change while walking home restarts that one", home_sped, []),
  ]
  list.each(cases, fn(row) {
    let #(reason, taken, expected) = row
    assert arrival_timers(taken) == expected as reason
  })
}

pub fn the_arrival_timer_sends_the_creature_placed_where_the_chase_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, arrived) =
    fire(state:, at_ms: 2600, timer: creature.chase_arrival_timer)
  let assert [CreaturePlaced(place:, at_ms:)] = news_to(arrived, 5)
    as "one placement for the viewer"
  assert x_of(place) == 26.0 && at_ms == start_ms + 2600
    as "where the path ends, 4 short of the target, at the time it arrives"
  assert said(arrived) == ["0x638(placed) to 2", "0x638(placed) to 5"]
    && timers(arrived) == []
    as "each viewer is placed, and nothing else is sent or timed"
  let #(_, followed) =
    tell(state:, at_ms: 2700, message: moved(number: 2, x: 60.0, seq: 2))
  let assert Running(from:, ..) = path_sent(followed)
    as "the target moved: the chase goes on"
  assert x_of(from) == 26.0 as "from the end of the path it arrived at"
}

pub fn the_arrival_timer_of_a_path_that_is_no_longer_run_sends_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let #(left_home, _) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let cases = [
    #(
      "stood by a state",
      tell(
        state:,
        at_ms: 100,
        message: controlling(number: 2, cast_id: 1, controls: [
          crowd_control_support.stagger_stun(instance_id: 28_673),
        ]),
      ).0,
      200,
    ),
    #(
      "killed",
      tell(
        state:,
        at_ms: 100,
        message: killing(number: 2, cast_id: 1, controls: []),
      ).0,
      200,
    ),
    #("thrown", tell(state:, at_ms: 100, message: knockback()).0, 200),
    #("walking home", left_home, 1500),
  ]
  list.each(cases, fn(row) {
    let #(reason, held, at_ms) = row
    let #(_, fired) =
      fire(state: held, at_ms:, timer: creature.chase_arrival_timer)
    assert said(fired) == [] && timers(fired) == [] as reason
  })
}

pub fn a_run_stood_between_its_end_and_its_arrival_timer_is_stopped_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let stun =
    controlling(number: 2, cast_id: 1, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ])
  let #(walking_home, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let cases = [
    #("stood by a state", state, 2600, stun, creature.chase_arrival_timer),
    #(
      "killed",
      state,
      2600,
      killing(number: 2, cast_id: 1, controls: []),
      creature.chase_arrival_timer,
    ),
    #("walking home", walking_home, 2000, stun, timer_for(leashed, 1000)),
  ]
  list.each(cases, fn(row) {
    let #(reason, run, at_ms, message, timer) = row
    let #(stood, standing) = tell(state: run, at_ms:, message:)
    let #(_, fired) = fire(state: stood, at_ms:, timer:)
    assert list.length(
        list.filter(list.append(said(standing), said(fired)), fn(line) {
          line == "0x638(placed) to 5"
        }),
      )
      == 1
      as reason
  })
}

pub fn the_walk_home_arrival_sends_the_creature_placed_at_home_before_the_turn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = chasing(viewers: [2, 5])
  let #(state, leashed) =
    tell(
      state:,
      at_ms: 1000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  let #(_, at_home) = fire(state:, at_ms: 2000, timer: timer_for(leashed, 1000))
  let assert [CreaturePlaced(place:, ..), ..] = news_to(at_home, 5)
    as "the first news is the stop"
  assert x_of(place) == 0.0 as "at the spawn"
  assert said(at_home)
    == ["0x638(placed) to 5", "turn(kind 19, spawn facing) to 5"]
    as "the stop, then the spawn's facing it takes on arrival"
}

// ---- where a charge's picture is and where its hit is ----
//
// The Sim-Turret of the tests below stands at the origin and aims at its 0x908 target, player 2,
// who comes near at (3, -4): the aim is atan2(-3, 4) = -0.6435011 (yaw 0 faces -z,
// `movement_command.kind_14.facing`), the way (0.6, -0.8), so player 5 at (12, -16), 20 along
// that line, is in the 30 m rectangle. Player 2 then walks to (-8, -1), behind the turret's
// start aim and where the aim would turn to if it followed. Spell4 85469's row 16212 is
// changed for the cases: no client row of a spell that loads is a fixed row of a turret, and
// seven of the loadable following-caster spells lack propertyFlags 0x2.

/// The yaw of the turret's aim at the start: the bearing of (3, -4) from the origin.
const start_aim = -0.643_501_108_793_284_4

/// The Sim-Turret built over these tables at the origin, started for players 2 and 5.
fn turret_over(tables tables: store.Tables) -> State {
  let spawn =
    spawn_support.sim_turret_over(
      tables: character_tables.content_over(tables:),
      number: 1,
      place: map_spawn_support.at(0.0),
    )
  let assert Ok(kind) =
    dict.get(spawn_support.turret_kinds().by_creature, 73_494)
    as "migration 0029 gives the Exile turret its kind"
  started_with(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn:,
    kind:,
    viewers: [2, 5],
    armor: creature_life.NoArmor,
  ).0
}

/// The turret opens its charge at 3000 ms with player 2 at (3, -4) and player 5 on the line of
/// its aim, then player 2 walks to (-8, -1) at 5000 ms: the state, the step that opened the
/// charge and the timer of its end.
fn turret_walked_round(
  state state: State,
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, aggro) =
    tell(
      state:,
      at_ms: 0,
      message: approached_at(number: 2, x: 3.0, z: -4.0, seq: 1),
    )
  let state = with_player_5_at(state:, x: 12.0, z: -16.0)
  let #(state, opened, ends) = charge_opened(state:, aggro:)
  let #(state, _) =
    tell(
      state:,
      at_ms: 5000,
      message: moved_at(number: 2, x: -8.0, z: -1.0, seq: 3),
    )
  #(state, opened, ends)
}

/// The players the end of the charge strikes, in order.
fn struck_at_the_end(state state: State, ends ends: step.TimerId) -> List(Int) {
  let #(_, went) = fire(state:, at_ms: 11_000, timer: ends)
  struck_numbers(went)
}

pub fn a_turret_strikes_a_fixed_caster_row_from_the_pose_stored_at_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 16212 with flag 0x1000: the client draws it once at the turret's initial position and
  // it stays there (`0x14054b1b0.fixed_placement`), though the turret's aim turns with its
  // target (`0x14046cdc0.turret_cast_aim` turns the aim, not a fixed picture). The 0x7ff names
  // the start aim; after player 2 walks round, the rectangle is still that one: player 5 on its
  // line is struck, player 2 is not.
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 16_212,
    with: [#("telegraphDamageFlags", planted_table.Integer(0x1000))],
  )
  let #(state, opened, ends) = turret_walked_round(state: turret_over(tables:))
  let assert [CastStarted(start:)] = news_to(opened, 2)
  assert start.initial_positions
    == [
      SpellInitialPosition(
        unit_id: 7,
        target_flags: 1,
        position: SpellPosition(x: 0, y: 0, z: 0),
        yaw: float32.to_bits(start_aim),
        anchor_unit_id: 0,
      ),
    ]
    && start.telegraph_positions == []
    as "an initial position at the aim at the start, and no telegraph position for a 0x1000 row"
  assert struck_at_the_end(state:, ends:) == [5]
    as "the rectangle the 0x7ff showed, not turned to the target"
}

pub fn a_turret_whose_spell_lacks_the_aim_bit_holds_its_aim_from_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 85469 has propertyFlags 0x40002; a cast without bit 0x2 holds the aim where it was
  // when the cast began (`0x14046cdc0.turret_cast_aim`). With propertyFlags 0 the rectangle,
  // drawn on the turret each frame, stays along the start aim: player 5 is struck and player 2,
  // who walked round it, is not. The unchanged spell turns to player 2: it strikes player 2
  // and not player 5.
  let held = {
    use tables <- fixture_tables.changed(table: "Spell4", id: 85_469, with: [
      #("propertyFlags", planted_table.Integer(0)),
    ])
    let #(state, _, ends) = turret_walked_round(state: turret_over(tables:))
    struck_at_the_end(state:, ends:)
  }
  assert held == [5] as "the aim held from the cast's start"
  let #(state, _, ends) =
    turret_walked_round(state: turret_over(tables: fixture_tables.shared()))
  assert struck_at_the_end(state:, ends:) == [2]
    as "with bit 0x2 the aim follows the 0x908 target, as the client's does"
}

pub fn a_viewer_arriving_mid_charge_gets_the_entries_of_the_cast_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 16212 with flags 0x5000 is drawn at a telegraph position of (16212, the turret), made at
  // the start from the aim at the start. A viewer that arrives after player 2 walked round is
  // sent those entries, not ones made from where the turret would aim now
  // (`TelegraphDamage.telegraphDamageFlags.0x1000`: a fixed row "stays where the server put it").
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 16_212,
    with: [#("telegraphDamageFlags", planted_table.Integer(0x5000))],
  )
  let #(state, opened, _) = turret_walked_round(state: turret_over(tables:))
  let assert [CastStarted(start:)] = news_to(opened, 2)
  assert list.map(start.telegraph_positions, fn(entry) { entry.yaw })
    == [float32.to_bits(start_aim)]
    as "the start's entry holds the start aim"
  let #(_, watched) =
    tell(
      state:,
      at_ms: 6000,
      message: creature_news_support.seen(
        by: ConnectionId(9),
        stay: map_support.stay(count: 9),
      ),
    )
  let assert Ok(CastStarted(start: late)) =
    list.find(news_to(watched, 9), fn(news) {
      creature_news_support.name_of(news) == "0x7ff"
    })
    as "the arriving viewer is sent the open cast"
  assert late.initial_positions == start.initial_positions
    && late.telegraph_positions == start.telegraph_positions
    as "the same entries as the cast's start, not the aim toward where player 2 stands now"
}

/// The strike go of Spell4 `spell4_id`, loaded for the Beast as the content load builds it,
/// reached at its time for a Beast that player 2 fights at (0, -4.5) with player 5 at (4.5, 0)
/// and player 6 at (-4.5, 0): the players the strike goes to, in order.
fn struck_by_the_loaded_special(spell4_id spell4_id: Int) -> List(Int) {
  let assert [special] =
    spawn_support.special_creature(number: 1, creature_id: 73_464, spell4_id:).combat.specials
    as "the Beast's kind lists the one special"
  let assert creature_life.Charged(gos:, ..) = special.attack.cast
    as "the spell is a charge"
  let #(state, aggro) =
    tell(
      state: rootbrute_with(special:, viewers: [2, 5, 6]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -4.5, seq: 1),
    )
  let state = with_player_at(state:, number: 5, x: 4.5, z: 0.0)
  let state = with_player_at(state:, number: 6, x: -4.5, z: 0.0)
  let #(state, opened) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  let #(_, struck) = through_the_gos(state:, step: opened, gos:, passed_ms: 0)
  struck_numbers(struck)
}

/// Each go of the cast at its time, from the one the step armed, up to the strike go: the
/// step of the strike go.
fn through_the_gos(
  state state: State,
  step taken: ServiceStep(creature.Outgoing),
  gos gos: List(creature_life.Go),
  passed_ms passed_ms: Int,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let assert [go, ..rest] = gos as "the cast has a strike go"
  let #(state, fired) =
    fire(
      state:,
      at_ms: 1500 + go.at_ms,
      timer: timer_for(taken, go.at_ms - passed_ms),
    )
  case go.strike {
    Some(_) -> #(state, fired)
    None -> through_the_gos(state:, step: fired, gos: rest, passed_ms: go.at_ms)
  }
}

pub fn the_rotated_cone_of_52448_strikes_where_the_client_draws_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 52448's row 7182 is a cone 4 to 5 m out and 240 degrees across with rotationDegrees
  // -90 and flag 0x1000. The client draws it as if the creature faced yaw - 90 degrees, so at
  // yaw 0 (the target straight ahead, -z) its centre line points to +x (`0x14054b1b0.shape_turn`:
  // "Spell4 52448's row 7182 placed at yaw 0 is centred on +x"). Player 5, 4.5 out at +x, is in
  // it; player 6, 4.5 out at -x, is 180 degrees off its centre line, beyond its 120 degree half
  // angle and out of reach of the row's other circle (radius 2); player 2, 4.5 ahead, is 90
  // degrees off, inside.
  assert struck_by_the_loaded_special(spell4_id: 52_448) == [2, 5]
    as "the fighter at +x and the target ahead are struck, the one at -x is not"
}

/// Earthen Roar with its area row taking one unit in `order`: the cone (5.5 m, 40 degrees) is
/// the hit shape and the row's range and count cap it.
fn roar_in_order(order order: area.Order) -> creature_life.Special {
  let roar = spawn_support.earthen_roar(hold_ms: 1000)
  let assert creature_life.Charged(area: row, ..) as charged = roar.attack.cast
    as "Earthen Roar is a charge"
  creature_life.Special(
    ..roar,
    attack: creature_life.Attack(
      ..roar.attack,
      cast: creature_life.Charged(
        ..charged,
        area: area.Row(..row, order:, target_count: 1),
      ),
    ),
  )
}

/// The fighters struck by the special of `order` when players 2, 4, 5 and 7 fight the Beast and
/// all four stand in its cone (player 2 4 ahead, 5 2 ahead, 4 3 ahead and 0.3 aside, 7 2.5
/// ahead and 0.3 the other aside), and the cast id of its round.
fn struck_in_order(order order: area.Order) -> #(List(Int), Int) {
  let #(state, aggro) =
    turn_fought(
      state: rootbrute_with(special: roar_in_order(order:), viewers: [
        2,
        4,
        5,
        7,
      ]),
    )
  let state = with_player_at(state:, number: 5, x: 0.0, z: -2.0)
  let state = with_player_at(state:, number: 4, x: 0.3, z: -3.0)
  let state = with_player_at(state:, number: 7, x: -0.3, z: -2.5)
  let #(state, opened, go) = roar_opened(state:, aggro:)
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(_, struck) = strike_go_reached(state:, strike:)
  #(list.map(fights_told(struck), fn(told) { told.0 }), cast_id_sent(opened, 2))
}

pub fn a_furthest_special_strikes_the_far_fighter_and_a_random_one_by_its_cast_id_test() -> Nil {
  use <- owned_test.run(5000)
  // Nearest strikes player 5, 2 ahead; Furthest strikes player 2, 4 ahead, the farthest in the
  // cone (the order is the rule's, `area` tests 1 and 2). Random strikes by the round's cast id
  // as its seed (the guess marked in `area`: the MurmurHash3 finalizer of
  // `seed * 0x9E3779B1 + unit_id`, masked to 32 bits; a unit's id is 10 times its number).
  // Worked outside the code for cast id 2147497985: units 20, 50, 40 and 70 give 1852897559,
  // 3119742477, 3645587042 and 2859683438, so unit 20, player 2, is first. With the seed 0 a
  // plain `select` would pass, they give 3528132897, 4276596341, 1732903491 and 3699139156,
  // so unit 40, player 4, is first: a strike that ignored the round would fail here.
  assert struck_in_order(order: area.Nearest).0 == [5]
    as "the nearest fighter in the cone"
  assert struck_in_order(order: area.Furthest).0 == [2]
    as "the farthest fighter in the cone"
  let #(struck, cast_id) = struck_in_order(order: area.Random)
  assert cast_id == 2_147_497_985 as "the round's cast id"
  assert struck == [2] as "the fighter the cast id's mix puts first"
  assert struck_in_order(order: area.Random) == #(struck, cast_id)
    as "the same round, the same fighter"
}

/// A circle placed on the centre, as a TelegraphDamage row of shape 0 gives it.
fn circle(radius radius: Float) -> area.Placement {
  area.Placement(
    shape: area.Circle(radius:),
    ahead: 0.0,
    aside: 0.0,
    turn_degrees: 0.0,
  )
}

/// Earthen Roar's timeline (casts 3000 ms, goes at 2500 and 3000 ms, strikes at the second)
/// as the real spell `spell4_id` with its hit on the `placements` around `anchor`, and a reach
/// of 20 so the target 8 units off is in reach. The draws are the spell's own rows.
fn target_roar(
  spell4_id spell4_id: Int,
  anchor anchor: area.Anchor,
  placements placements: List(area.Placement),
) -> creature_life.Special {
  let roar = spawn_support.earthen_roar(hold_ms: 1000)
  let assert creature_life.Charged(gos:, ..) as charged = roar.attack.cast
    as "Earthen Roar is a charge"
  let inside = area.InsideShapes(placements:)
  creature_life.Special(
    ..roar,
    attack: creature_life.Attack(
      ..roar.attack,
      spell4_id: Spell4Id(spell4_id),
      reach: 20.0,
      cast: creature_life.Charged(
        ..charged,
        anchor:,
        inside:,
        gos: list.map(gos, fn(go) {
          creature_life.Go(
            ..go,
            strike: option.map(go.strike, fn(strike) {
              creature_life.GoStrike(..strike, inside:)
            }),
          )
        }),
        draws: telegraph_entries.draws_of(
          tables: fixture_tables.shared(),
          spell4_id: Spell4Id(spell4_id),
        ),
      ),
    ),
  )
}

/// The Beast casting `special` at player 2, who comes near at (0, -8) facing -z at 0 ms; each
/// of `others` (number, x, z) joins the fight standing there. The cast opens at 1500 ms: the
/// state, the step of its start and the timer of its first go.
fn target_cast_opened(
  special special: creature_life.Special,
  others others: List(#(Int, Float, Float)),
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, aggro) =
    tell(
      state: rootbrute_with(special:, viewers: [
        2,
        ..list.map(others, fn(other) { other.0 })
      ]),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -8.0, seq: 1),
    )
  let state =
    list.fold(others, state, fn(state, other) {
      with_player_at(state:, number: other.0, x: other.1, z: other.2)
    })
  roar_opened(state:, aggro:)
}

/// The step of the strike go of the open cast, after the go before it.
fn strike_go_of_the_cast(
  state state: State,
  go go: step.TimerId,
) -> ServiceStep(creature.Outgoing) {
  let #(state, _, strike) = first_go_passed(state:, go:)
  let #(_, struck) = strike_go_reached(state:, strike:)
  struck
}

/// The player moving to `x`, `z` and turning to face `yaw`.
fn moved_facing(
  number number: Int,
  x x: Float,
  z z: Float,
  yaw yaw: Float,
  seq seq: Int,
) -> creature.Message {
  creature.TargetMoved(
    by: ConnectionId(number),
    place: start_place.turned(
      place: at_xz(x:, z:),
      facing: start_place.Facing(yaw:, pitch: 0.0, roll: 0.0),
    ),
    seq:,
    stay: map_support.stay(count: number),
    hit_radius: place_support.player_hit_radius,
  )
}

pub fn a_charge_on_a_target_row_opens_with_the_target_in_its_0x7ff_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 7874 (0x905000, targetTypeFlags 2) of Laser Bolt 55846 is drawn from the entries of
  // its target: player 2 (unit 20) at (0, -8) facing -z, which the creature at the origin
  // faces too. The entries carry the role bit 2 and no entry names the creature (unit 7); the
  // 0x7ff's own place is the creature's (`opcode.0x7ff`, `spell.initial_position_flags`).
  let #(_, opened, _) =
    target_cast_opened(
      special: target_roar(
        spell4_id: 55_846,
        anchor: area.FixedAtTarget,
        placements: [circle(radius: 4.0)],
      ),
      others: [],
    )
  let assert [CastStarted(start:)] = casts_of(opened, 2)
  let target_place =
    SpellPosition(
      x: float32.to_bits(0.0),
      y: float32.to_bits(0.0),
      z: float32.to_bits(-8.0),
    )
  assert start.spell4_id == 55_846
    && start.caster_unit_id == 7
    && start.primary_target_unit_id == 20
  assert start.position
    == SpellPosition(
      x: float32.to_bits(0.0),
      y: float32.to_bits(0.0),
      z: float32.to_bits(0.0),
    )
    as "the cast's own place is the creature's"
  assert start.initial_positions
    == [
      SpellInitialPosition(
        unit_id: 20,
        target_flags: 2,
        position: target_place,
        yaw: float32.to_bits(0.0),
        anchor_unit_id: 0,
      ),
    ]
    as "one initial position, the target's, with the role bit 2"
  assert start.telegraph_positions
    == [
      SpellTelegraphPosition(
        telegraph_damage_id: 7874,
        unit_id: 20,
        target_flags: 2,
        position: target_place,
        yaw: float32.to_bits(0.0),
        anchor_unit_id: 0,
      ),
    ]
    as "one telegraph position of the row on the target"
}

pub fn a_fixed_target_row_strikes_around_where_the_target_stood_at_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 7874 is a circle of 4 and Laser Bolt's area row 116 reaches 10. The creature stands at
  // (0, 0); player 2, the target, at (0, -8); player 5 at (3, -8), 3 from the circle's centre,
  // inside 4 plus the player hit radius 1.2; player 6 at (8, -8), 8 from it, outside 5.2 though
  // within the area row's 10. Player 2 then steps to (0, -14), 6 from the centre, outside
  // 5.2. The circle stays where the start put it (Jim's answer on the series: a guess,
  // marked): only player 5 is struck. A centre that followed player 2 would strike player 2,
  // and the creature as centre none of them.
  let #(state, _, go) =
    target_cast_opened(
      special: target_roar(
        spell4_id: 55_846,
        anchor: area.FixedAtTarget,
        placements: [circle(radius: 4.0)],
      ),
      others: [#(5, 3.0, -8.0), #(6, 8.0, -8.0)],
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 3000,
      message: moved_at(number: 2, x: 0.0, z: -14.0, seq: 3),
    )
  assert struck_numbers(strike_go_of_the_cast(state:, go:)) == [5]
    as "the fighter in the circle where the target stood is struck, the target who left is not"
}

pub fn a_client_placed_target_row_strikes_around_the_cast_targets_place_at_the_strike_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 4796 of Spell4 46353 is client-placed, a circle of 5: the client draws it on the unit
  // of cast 0x158 each frame (`0x14054b1b0`). Player 2, the target, stands at (0, -8) at the
  // start with player 6 at (2, -8) and player 5 at (0, -19). Player 2 steps to (0, -16)
  // before the strike go: player 5 is 3 from it, inside 5 plus 1.2, and player 6 is 8.2 from
  // it, outside 6.2 though it was inside the start's circle: player 2 and player 5 are struck.
  let #(state, _, go) =
    target_cast_opened(
      special: target_roar(
        spell4_id: 46_353,
        anchor: area.FollowsTarget,
        placements: [circle(radius: 5.0)],
      ),
      others: [#(5, 0.0, -19.0), #(6, 2.0, -8.0)],
    )
  let #(state, _) =
    tell(
      state:,
      at_ms: 3000,
      message: moved_at(number: 2, x: 0.0, z: -16.0, seq: 3),
    )
  assert struck_numbers(strike_go_of_the_cast(state:, go:)) == [2, 5]
    as "the circle is around where the target stands at the strike"
}

/// A case of `a_cone_on_the_target_turns_with_the_targets_facing_test`: the yaw the target
/// turns to before the strike go and the fighters struck besides the target.
type TargetTurn {
  TargetTurn(reason: String, yaw: Float, struck: List(Int))
}

pub fn a_cone_on_the_target_turns_with_the_targets_facing_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 48590's rows 5671 and 5672 (client-placed, targetTypeFlags 2) are two 180 degree
  // cones out to 15 with rotations -45 and 225: together all but a 90 degree wedge centred on
  // -x of the unit's facing (`0x14054b1b0.shape_turn`: rotation -45 points to (+0.71, -0.71),
  // 225 to (+0.71, +0.71) at yaw 0, the wedge between them at -x). The target stands at
  // (0, -8) with a fighter 8 to its -x side (player 5) and one 8 to its +x side (player 6).
  // The target itself, at the apex, is not asserted. Gap: the facing the cones turn with is
  // the newest sighting's, not the client's current yaw of the unit.
  let cones = [
    area.Placement(
      shape: area.Cone(inner: 0.0, outer: 15.0, degrees: 180.0),
      ahead: 0.0,
      aside: 0.0,
      turn_degrees: -45.0,
    ),
    area.Placement(
      shape: area.Cone(inner: 0.0, outer: 15.0, degrees: 180.0),
      ahead: 0.0,
      aside: 0.0,
      turn_degrees: 225.0,
    ),
  ]
  [
    TargetTurn(
      reason: "facing -z: the wedge is at -x, so the fighter at +x is struck",
      yaw: 0.0,
      struck: [6],
    ),
    TargetTurn(
      reason: "turned to yaw pi: the wedge is at +x, so the fighter at -x is struck",
      yaw: 3.141_592_653_589_793,
      struck: [5],
    ),
  ]
  |> list.each(fn(case_) {
    let #(state, _, go) =
      target_cast_opened(
        special: target_roar(
          spell4_id: 46_353,
          anchor: area.FollowsTarget,
          placements: cones,
        ),
        others: [#(5, -8.0, -8.0), #(6, 8.0, -8.0)],
      )
    let #(state, _) =
      tell(
        state:,
        at_ms: 3000,
        message: moved_facing(
          number: 2,
          x: 0.0,
          z: -8.0,
          yaw: case_.yaw,
          seq: 3,
        ),
      )
    assert list.filter(
        struck_numbers(strike_go_of_the_cast(state:, go:)),
        fn(number) { number != 2 },
      )
      == case_.struck
      as case_.reason
  })
}

pub fn a_target_row_uses_the_cast_target_not_the_0x908_target_of_the_moment_test() -> Nil {
  use <- owned_test.run(5000)
  // A circle of 5 follows the cast's target, player 2 at (0, -8), with player 6 beside it at
  // (2, -8). Player 5 at (0, -19) strikes harder after the cast opened, so the creature's
  // 0x908 target is player 5 (`opcode.0x908`) while the cast is still on player 2
  // (`opcode.0x7ff`, cast 0x158): the circle is around player 2 and the fighter beside it, and
  // player 5, 11 away, is outside it. A circle around player 5 would strike player 5 alone.
  let #(state, _, go) =
    target_cast_opened(
      special: target_roar(
        spell4_id: 46_353,
        anchor: area.FollowsTarget,
        placements: [circle(radius: 5.0)],
      ),
      others: [#(5, 0.0, -19.0), #(6, 2.0, -8.0)],
    )
  let #(state, retargeted) =
    tell(
      state:,
      at_ms: 3000,
      message: strike_of(number: 5, cast_id: 1, blows: [#(1, 10, 1.0)]),
    )
  assert names_target(taken: retargeted, unit_id: 50, to: 2)
    as "player 5 is the 0x908 target now"
  assert struck_numbers(strike_go_of_the_cast(state:, go:)) == [2, 6]
    as "the circle is still around the cast's target"
}

/// A case of `a_target_row_strikes_while_its_cast_target_is_in_the_world_test`: the spell and
/// anchor of the row, what happens to the cast's target after the cast opened, and the players
/// its circle strikes.
type TargetDeparture {
  TargetDeparture(
    reason: String,
    spell4_id: Int,
    anchor: area.Anchor,
    departure: creature.Message,
    struck: List(Int),
  )
}

pub fn a_target_row_strikes_while_its_cast_target_is_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  // The client removes a unit-placed or server-placed telegraph when the unit it is bound to
  // is no longer found in its world, and not when the unit leaves the fight
  // (`0x14054b1b0.unit_gone`, for a server-placed row too). Player 2, the cast's target, stands at
  // (0, -8) with player 6 beside it at (2, -8) and player 5 far off at (0, -19). A target that
  // dies or leaves the creature's ring stays in the world, as a body or as a unit: a row
  // following it is still drawn on it, and a fixed row is still drawn at its stored place. A
  // target the map no longer shows the creature (`Unwatched`: it left, logged out or camped,
  // or was despawned) is gone from the viewers' world, so neither row is drawn and nobody
  // is struck.
  [
    TargetDeparture(
      reason: "a target that died leaves a body: the row on it still strikes the fighter beside it",
      spell4_id: 46_353,
      anchor: area.FollowsTarget,
      departure: creature.PlayerDied(by: ConnectionId(2)),
      struck: [6],
    ),
    TargetDeparture(
      reason: "a target that died leaves the fixed row where it stood",
      spell4_id: 55_846,
      anchor: area.FixedAtTarget,
      departure: creature.PlayerDied(by: ConnectionId(2)),
      struck: [6],
    ),
    TargetDeparture(
      reason: "a target that left the ring is still in the world: both fighters are struck",
      spell4_id: 46_353,
      anchor: area.FollowsTarget,
      departure: creature.Withdrew(by: ConnectionId(2)),
      struck: [2, 6],
    ),
    TargetDeparture(
      reason: "a target the creature no longer sees takes the following row with it",
      spell4_id: 46_353,
      anchor: area.FollowsTarget,
      departure: creature_news_support.unseen(by: ConnectionId(2)),
      struck: [],
    ),
    TargetDeparture(
      reason: "a target the creature no longer sees takes the fixed row with it",
      spell4_id: 55_846,
      anchor: area.FixedAtTarget,
      departure: creature_news_support.unseen(by: ConnectionId(2)),
      struck: [],
    ),
  ]
  |> list.each(fn(case_) {
    let #(state, _, go) =
      target_cast_opened(
        special: target_roar(
          spell4_id: case_.spell4_id,
          anchor: case_.anchor,
          placements: [circle(radius: 4.0)],
        ),
        others: [#(5, 0.0, -19.0), #(6, 2.0, -8.0)],
      )
    let #(state, _) = tell(state:, at_ms: 3000, message: case_.departure)
    let struck = strike_go_of_the_cast(state:, go:)
    assert struck_numbers(struck) == case_.struck as case_.reason
    case case_.struck {
      [] -> {
        let assert [CastWent(went), ..] = news_to(struck, 5)
        assert went.phase == 1 && went.targets == []
          as { case_.reason <> ": the go names no unit" }
        assert list.contains(said(struck), "0x7fe to 5")
          as { case_.reason <> ": the cast finishes" }
        Nil
      }
      [_, ..] -> Nil
    }
  })
}

// ---- a charged cast with several hits: Yeti Snowstalker's Ice Breath (Spell4 55635) ----
//
// The client's rows, read for this block (each value below is from them):
// - Spell4 55635: castTime 3800, targetMaxRange 5.0, Spell4AoeTargetConstraints 116 (angle
//   360, targetCount 10, minRange 0, maxRange 10.0), Spell4CCConditions 1.
// - SpellPhase 11479 to 11482 (`table_rows -- SpellPhase spell4IdOwner=55635`): delays 2600,
//   400, 500 and 300, so the gos are at 2600, 3000, 3500 and 3800 ms.
// - Spell4Effects 132757 (type 8, damage, phaseFlags 6: gos 1 and 2) and 132758 (type 35,
//   durationTime 500, phaseFlags 0xffff0008: go 3), `table_rows -- Spell4Effects spellId=55635`.
// - TelegraphDamage 7956 and 7957 (`table_rows -- TelegraphDamage 7956 7957`): cones from 0 to
//   5.5 m, 20 degrees across, on the caster, turned +10 and -10 degrees
//   (`0x14054b1b0.shape_turn`).
// The creature is the Beast of this file with the special planted by hand
// (`spawn_support.ice_breath`). The cast opens at 1,500 ms and its gos fall at 4,100, 4,500,
// 5,000 and 5,300 ms; a strike's deadline is 1,000 ms after it (`strike_tell.deadline_ms`).

/// The times the gos of Ice Breath fall, counted from the test's start: the cast opens at 1,500
/// ms.
const ice_go_times_ms = [4100, 4500, 5000, 5300]

/// The Beast casting Ice Breath, fought by player 2 who comes near 4 units ahead of it at 0
/// ms: the state and the step of the aggro.
fn ice_fought(
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  ice_fought_with(special: spawn_support.ice_breath(hold_ms: 500), viewers:)
}

fn ice_fought_with(
  special special: creature_life.Special,
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  turn_fought(state: rootbrute_with(special:, viewers:))
}

/// The attack tick of 1,500 ms opens Ice Breath: the state, the step of its start and the
/// timer of its first go, 2,600 ms later.
fn ice_opened(
  state state: State,
  aggro aggro: ServiceStep(creature.Outgoing),
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  opened_for(state:, aggro:, first_go_ms: 2600)
}

/// The same for a cast whose first go falls `first_go_ms` after its start.
fn opened_for(
  state state: State,
  aggro aggro: ServiceStep(creature.Outgoing),
  first_go_ms first_go_ms: Int,
) -> #(State, ServiceStep(creature.Outgoing), step.TimerId) {
  let #(state, opened) =
    fire(state:, at_ms: 1500, timer: timer_for(aggro, 1500))
  #(state, opened, timer_for(opened, first_go_ms))
}

/// An Ice Breath cast partly run: the state, the step that opened it, the step of the go last
/// handled, the timers of the gos handled (by go) and of the go to come (none after the last),
/// and each strike's deadline timer and key (by go; every strike is told to player 2).
type Ice {
  Ice(
    state: State,
    opened: ServiceStep(creature.Outgoing),
    went: ServiceStep(creature.Outgoing),
    handled: List(step.TimerId),
    pending: Option(step.TimerId),
    deadlines: List(#(Int, step.TimerId)),
    keys: List(#(Int, Key)),
  )
}

/// Ice Breath's gos handled at their times, from the first up to go `through`, with player 2
/// inside both cones: every strike is out and none answered.
fn ice_through(
  state state: State,
  aggro aggro: ServiceStep(creature.Outgoing),
  through through: Int,
) -> Ice {
  let #(state, opened, first) = ice_opened(state:, aggro:)
  let start =
    Ice(
      state:,
      opened:,
      went: opened,
      handled: [],
      pending: Some(first),
      deadlines: [],
      keys: [],
    )
  list.fold(list.take([0, 1, 2, 3], through + 1), start, ice_go)
}

/// The go `phase` handled at its time.
fn ice_go(ice ice: Ice, phase phase: Int) -> Ice {
  let assert Some(timer) = ice.pending as "a go is still to come"
  let assert Ok(at_ms) = list.first(list.drop(ice_go_times_ms, phase))
  let #(state, went) = fire(state: ice.state, at_ms:, timer:)
  let strikes = phase == 1 || phase == 2
  Ice(
    ..ice,
    state:,
    went:,
    handled: list.append(ice.handled, [timer]),
    pending: case phase {
      0 -> Some(timer_for(went, 400))
      1 -> Some(timer_for(went, 500))
      2 -> Some(timer_for(went, 300))
      _ -> None
    },
    deadlines: case strikes {
      True -> list.append(ice.deadlines, [#(phase, timer_for(went, 1000))])
      False -> ice.deadlines
    },
    keys: case strikes {
      True ->
        list.append(ice.keys, [#(phase, strike_key(taken: went, number: 2))])
      False -> ice.keys
    },
  )
}

/// The key of the strike the step tells player `number` to take.
fn strike_key(
  taken taken: ServiceStep(creature.Outgoing),
  number number: Int,
) -> Key {
  let assert Ok(#(_, Attacks(tell: Strike(key:, ..)))) =
    list.find(fights_told(taken), fn(told) { told.0 == number })
    as "the step tells that player to take a strike"
  key
}

/// Player 2's answer that the strike of go `phase` landed, at `at_ms`.
fn ice_answered(
  ice ice: Ice,
  phase phase: Int,
  at_ms at_ms: Int,
) -> #(Ice, ServiceStep(creature.Outgoing)) {
  let assert Ok(key) = list.key_find(ice.keys, phase)
    as "that go struck player 2"
  let #(state, answered) = tell(state: ice.state, at_ms:, message: landed(key:))
  #(Ice(..ice, state:), answered)
}

/// The go and finish frames the step sends viewer `number`, in order: each 0x7f4 with its
/// phase and the units it names, the 0x7fe and the 0x7f9.
fn frames_of(
  taken taken: ServiceStep(creature.Outgoing),
  number number: Int,
) -> List(String) {
  list.filter_map(news_to(taken, number), fn(news) {
    case creature_news_support.name_of(news) {
      "0x7f4" -> {
        let assert CastWent(go:) = news as "a 0x7f4 is a go"
        Ok(
          "0x7f4 phase "
          <> int.to_string(go.phase)
          <> " ["
          <> string.join(
            list.map(go.targets, fn(target) { int.to_string(target.unit_id) }),
            ",",
          )
          <> "]",
        )
      }
      "0x7fe" -> Ok("0x7fe")
      "0x7f9" -> Ok("0x7f9")
      _ -> Error(Nil)
    }
  })
}

/// The timers the step cancels, each named by the go it belongs to: "cancels deadline N" (the
/// strike deadline of go N) or "cancels the pending go" (the `CastEnds` of `ice`).
fn cancels_named(
  taken taken: ServiceStep(creature.Outgoing),
  ice ice: Ice,
) -> List(String) {
  list.map(timers_cancelled(taken), fn(timer) {
    case list.find(ice.deadlines, fn(deadline) { deadline.1 == timer }) {
      Ok(#(phase, _)) -> "cancels deadline " <> int.to_string(phase)
      Error(Nil) ->
        case ice.pending == Some(timer) {
          True -> "cancels the pending go"
          False -> "cancels another timer"
        }
    }
  })
}

/// What the step does to the cast of `ice`: the timers it cancels (by go), the frames viewer
/// `number` is sent and the timers it starts.
fn observed(
  taken taken: ServiceStep(creature.Outgoing),
  ice ice: Ice,
  number number: Int,
) -> List(String) {
  list.flatten([
    cancels_named(taken:, ice:),
    frames_of(taken:, number:),
    list.map(timers(taken), fn(started) {
      "starts " <> int.to_string(started.1)
    }),
  ])
}

/// The strikes the step tells players to take, each as the go and the player.
fn strikes_of(taken taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.map(fights_told(taken), fn(told) {
    let assert Attacks(tell: Strike(key:, ..)) = told.1
      as "a creature's tell to a fighter is a strike"
    let assert strike_tell.AtGo(phase:) = key.occasion
      as "the strike of a charge is keyed to its go"
    "strike at go " <> int.to_string(phase) <> " to " <> int.to_string(told.0)
  })
}

pub fn each_damage_go_strikes_at_its_phase_and_the_cast_finishes_after_the_last_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = ice_fought(viewers: [2])
  let #(state, opened, first) = ice_opened(state:, aggro:)
  // Go 0, the cast bar's: 0x7f4 phase 0 with no target.
  let #(state, zero) = fire(state:, at_ms: 4100, timer: first)
  assert frames_of(taken: zero, number: 2) == ["0x7f4 phase 0 []"]
    && fights_told(zero) == []
    as "go 0 names no unit and strikes nobody"
  // Go 1 at 4,500 strikes player 2 under the key of go 1, with blow 132757 alone.
  let #(state, one) = fire(state:, at_ms: 4500, timer: timer_for(zero, 400))
  let assert [#(2, Attacks(tell: Strike(key: one_key, offence:, ..)))] =
    fights_told(one)
  assert one_key.occasion == strike_tell.AtGo(phase: 1)
    && one_key.cast_id == cast_id_sent(opened, 2)
    as "the strike of go 1 is keyed to its go, under the cast's id"
  assert list.map(offence.blows, fn(blow) { blow.spell4_effects_id })
    == [132_757]
    as "Spell4Effects 132757 alone"
  assert frames_of(taken: one, number: 2) == []
    as "go 1 is written when it is answered"
  let #(state, answered_one) =
    tell(state:, at_ms: 4550, message: landed(key: one_key))
  assert frames_of(taken: answered_one, number: 2) == ["0x7f4 phase 1 [20]"]
    as "0x7f4 phase 1 lists player 2"
  // Go 2 at 5,000.
  let #(state, two) = fire(state:, at_ms: 5000, timer: timer_for(one, 500))
  let two_key = strike_key(taken: two, number: 2)
  assert two_key.occasion == strike_tell.AtGo(phase: 2)
    as "the strike of go 2 is keyed to go 2"
  let #(state, answered_two) =
    tell(state:, at_ms: 5050, message: landed(key: two_key))
  assert frames_of(taken: answered_two, number: 2) == ["0x7f4 phase 2 [20]"]
    as "0x7f4 phase 2 lists player 2"
  // Go 3, the last, at 5,300: its 0x7f4, then the finish, and the hold counts from here.
  let #(_, last) = fire(state:, at_ms: 5300, timer: timer_for(two, 300))
  assert frames_of(taken: last, number: 2) == ["0x7f4 phase 3 []", "0x7fe"]
    as "the last go names no unit, and the cast finishes after it"
  assert list.map(timers(last), fn(started) { started.1 }) == [500]
    as "the next attack tick comes 500 ms after the close (Spell4Effects 132758)"
}

/// A row of the table of overlapping rounds: what its scene does, as lines, and the lines
/// the rule gives.
type Overlap {
  Overlap(reason: String, run: fn() -> List(String), expected: List(String))
}

pub fn the_rounds_of_overlapping_hits_are_written_in_go_order_test() -> Nil {
  use <- owned_test.run(5000)
  let through = fn(go) {
    let #(state, aggro) = ice_fought(viewers: [2])
    ice_through(state:, aggro:, through: go)
  }
  [
    Overlap(
      reason: "both strikes out and none answered: each answer closes its own round, under its own deadline",
      run: fn() {
        let ice = through(2)
        let #(ice, one) = ice_answered(ice:, phase: 1, at_ms: 5100)
        let #(ice, two) = ice_answered(ice:, phase: 2, at_ms: 5150)
        list.flatten([
          [
            case
              list.key_find(ice.deadlines, 1) == list.key_find(ice.deadlines, 2)
            {
              True -> "the deadlines share a timer"
              False -> "the deadlines are two timers"
            },
          ],
          observed(taken: one, ice:, number: 2),
          observed(taken: two, ice:, number: 2),
        ])
      },
      expected: [
        "the deadlines are two timers",
        "cancels deadline 1",
        "0x7f4 phase 1 [20]",
        "cancels deadline 2",
        "0x7f4 phase 2 [20]",
      ],
    ),
    Overlap(
      reason: "go 2 answered first: nothing is written until go 1's answer, which writes both in order",
      run: fn() {
        let ice = through(2)
        let #(ice, two) = ice_answered(ice:, phase: 2, at_ms: 5010)
        let #(ice, one) = ice_answered(ice:, phase: 1, at_ms: 5020)
        list.append(
          observed(taken: two, ice:, number: 2),
          observed(taken: one, ice:, number: 2),
        )
      },
      expected: [
        "cancels deadline 2",
        "cancels deadline 1",
        "0x7f4 phase 1 [20]",
        "0x7f4 phase 2 [20]",
      ],
    ),
    Overlap(
      reason: "go 1 never answered: its deadline writes it with no target, then go 2 behind it; its late answer changes nothing",
      run: fn() {
        let ice = through(2)
        let #(ice, two) = ice_answered(ice:, phase: 2, at_ms: 5100)
        let assert Ok(deadline) = list.key_find(ice.deadlines, 1)
        let #(state, closed) =
          fire(state: ice.state, at_ms: 5500, timer: deadline)
        let ice = Ice(..ice, state:)
        let #(ice, late) = ice_answered(ice:, phase: 1, at_ms: 5600)
        list.flatten([
          observed(taken: two, ice:, number: 2),
          observed(taken: closed, ice:, number: 2),
          observed(taken: late, ice:, number: 2),
        ])
      },
      expected: [
        "cancels deadline 2",
        "0x7f4 phase 1 []",
        "0x7f4 phase 2 [20]",
      ],
    ),
    Overlap(
      reason: "the last go waits behind go 2's open round: no finish and no hold until go 2's answer, which writes phase 2, phase 3 and the finish",
      run: fn() {
        let ice = through(2)
        let #(ice, _) = ice_answered(ice:, phase: 1, at_ms: 5100)
        let ice = ice_go(ice:, phase: 3)
        let waited = observed(taken: ice.went, ice:, number: 2)
        let #(ice, two) = ice_answered(ice:, phase: 2, at_ms: 5400)
        list.append(waited, observed(taken: two, ice:, number: 2))
      },
      expected: [
        "cancels deadline 2",
        "0x7f4 phase 2 [20]",
        "0x7f4 phase 3 []",
        "0x7fe",
        "starts 500",
      ],
    ),
    Overlap(
      reason: "a deadline and the next go due in the same millisecond give the same frames in either order",
      run: fn() {
        // Strike gos 1,000 ms apart (as Spell4 45746's), so go 1's deadline and go 2 fall at
        // 5,500 ms.
        let spaced = fn() {
          let special =
            spawn_support.special_with_charged(
              spawn_support.ice_breath(hold_ms: 500),
              fn(charged) {
                let assert creature_life.Charged(
                  gos: [_, first, second, last],
                  ..,
                ) = charged
                  as "Ice Breath has four gos"
                creature_life.Charged(..charged, gos: [
                  creature_life.Go(at_ms: 2000, strike: None),
                  creature_life.Go(..first, at_ms: 3000),
                  creature_life.Go(..second, at_ms: 4000),
                  creature_life.Go(..last, at_ms: 4500),
                ])
              },
            )
          let #(state, aggro) = ice_fought_with(special:, viewers: [2])
          let #(state, _, first_go) =
            opened_for(state:, aggro:, first_go_ms: 2000)
          let #(state, zero) = fire(state:, at_ms: 3500, timer: first_go)
          let #(state, one) =
            fire(state:, at_ms: 4500, timer: timer_for(zero, 1000))
          let assert [#(deadline, 1000), #(next_go, 1000)] = timers(one)
            as "the strike's deadline and the next go, both 1,000 ms on"
          #(state, deadline, next_go)
        }
        let #(state, deadline, next_go) = spaced()
        let #(state, closed) = fire(state:, at_ms: 5500, timer: deadline)
        let #(_, struck) = fire(state:, at_ms: 5500, timer: next_go)
        let deadline_first =
          list.sort(
            list.append(
              frames_of(taken: closed, number: 2),
              strikes_of(taken: struck),
            ),
            string.compare,
          )
        let #(state, deadline, next_go) = spaced()
        let #(state, struck) = fire(state:, at_ms: 5500, timer: next_go)
        let #(_, closed) = fire(state:, at_ms: 5500, timer: deadline)
        let go_first =
          list.sort(
            list.append(
              frames_of(taken: closed, number: 2),
              strikes_of(taken: struck),
            ),
            string.compare,
          )
        list.append(deadline_first, go_first)
      },
      expected: [
        "0x7f4 phase 1 []",
        "strike at go 2 to 2",
        "0x7f4 phase 1 []",
        "strike at go 2 to 2",
      ],
    ),
  ]
  |> list.each(fn(row) {
    assert row.run() == row.expected as row.reason
  })
}

pub fn a_hit_that_selects_nobody_is_an_empty_entry_and_the_cast_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  // Row (a): player 2 steps out of both cones (9 away, beyond the cones' 5.5 and the hit
  // radius 1.2) before go 1 and back before go 2: go 1 is an empty entry, written at once;
  // go 2 strikes it again; the cast reaches its last go.
  let #(state, aggro) = ice_fought(viewers: [2])
  let #(state, _, first) = ice_opened(state:, aggro:)
  let #(state, zero) = fire(state:, at_ms: 4100, timer: first)
  let #(state, away) =
    tell(
      state:,
      at_ms: 4300,
      message: moved_at(number: 2, x: 0.0, z: -9.0, seq: 3),
    )
  assert said(away) == [] as "the creature does not move while it casts"
  let #(state, one) = fire(state:, at_ms: 4500, timer: timer_for(zero, 400))
  assert fights_told(one) == []
    && frames_of(taken: one, number: 2) == ["0x7f4 phase 1 []"]
    as "go 1 selects nobody: its 0x7f4 names no unit and is written at once"
  let #(state, _) =
    tell(
      state:,
      at_ms: 4800,
      message: moved_at(number: 2, x: 0.0, z: -4.0, seq: 4),
    )
  let #(state, two) = fire(state:, at_ms: 5000, timer: timer_for(one, 500))
  let key = strike_key(taken: two, number: 2)
  assert key.occasion == strike_tell.AtGo(phase: 2)
    as "go 2 strikes player 2 again"
  let #(state, answered) = tell(state:, at_ms: 5050, message: landed(key:))
  assert frames_of(taken: answered, number: 2) == ["0x7f4 phase 2 [20]"]
  let #(_, last) = fire(state:, at_ms: 5300, timer: timer_for(two, 300))
  assert frames_of(taken: last, number: 2) == ["0x7f4 phase 3 []", "0x7fe"]
    as "the cast reaches its last go and finishes"
  // Row (b): the hits are on the cast's target (`FollowsTarget`), which is no longer a viewer,
  // with player 5 still fighting: go 1 and go 2 are empty entries written in order, go 3 is
  // written and the cast finishes.
  let on_target =
    spawn_support.special_with_charged(
      spawn_support.ice_breath(hold_ms: 500),
      fn(charged) {
        let assert creature_life.Charged(..) = charged
          as "Ice Breath is a charge"
        creature_life.Charged(..charged, anchor: area.FollowsTarget)
      },
    )
  let #(state, aggro) = ice_fought_with(special: on_target, viewers: [2, 5])
  let state = with_player_at(state:, number: 5, x: 0.0, z: -3.0)
  let #(state, _, first) = ice_opened(state:, aggro:)
  let #(state, gone) =
    tell(
      state:,
      at_ms: 2000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert frames_of(taken: gone, number: 5) == []
  let #(state, zero) = fire(state:, at_ms: 4100, timer: first)
  let #(state, one) = fire(state:, at_ms: 4500, timer: timer_for(zero, 400))
  let #(state, two) = fire(state:, at_ms: 5000, timer: timer_for(one, 500))
  let #(_, last) = fire(state:, at_ms: 5300, timer: timer_for(two, 300))
  assert list.flat_map([zero, one, two, last], frames_of(taken: _, number: 5))
    == [
      "0x7f4 phase 0 []",
      "0x7f4 phase 1 []",
      "0x7f4 phase 2 []",
      "0x7f4 phase 3 []",
      "0x7fe",
    ]
    as "a row on a target that is gone strikes nobody: each go is an empty entry, written in order"
  assert list.all([one, two], fn(taken) { fights_told(taken) == [] })
    as "and nobody is told to take a strike"
}

/// Ice Breath's worked positions (the creature at (0, 0) turned to player 2 at (0, -4),
/// facing -z): player 5 at (-1.545, -4.755), 5.0 away and 18 degrees toward -x, inside the +10
/// degree cone (0 to 20 degrees toward -x) and outside the -10 degree cone; player 6 at the
/// mirror place inside the -10 cone only.
fn ice_with_players(
  special special: creature_life.Special,
) -> #(State, ServiceStep(creature.Outgoing)) {
  let #(state, aggro) = ice_fought_with(special:, viewers: [2, 5, 6])
  let state = with_player_at(state:, number: 5, x: -1.545, z: -4.755)
  let state = with_player_at(state:, number: 6, x: 1.545, z: -4.755)
  #(state, aggro)
}

/// The special with the blows and gos named, whatever else Ice Breath holds.
fn ice_with_gos(gos gos: List(creature_life.Go)) -> creature_life.Special {
  spawn_support.special_with_charged(
    spawn_support.ice_breath(hold_ms: 500),
    fn(charged) {
      let assert creature_life.Charged(..) = charged as "Ice Breath is a charge"
      creature_life.Charged(..charged, gos:)
    },
  )
}

pub fn each_hit_strikes_the_fighters_and_the_blows_that_name_its_go_test() -> Nil {
  use <- owned_test.run(5000)
  let ice_gos = fn(first, second) {
    ice_with_gos(gos: [
      creature_life.Go(at_ms: 2600, strike: None),
      creature_life.Go(
        at_ms: 3000,
        strike: Some(creature_life.GoStrike(
          spell4_effects_ids: [132_757],
          inside: first,
        )),
      ),
      creature_life.Go(
        at_ms: 3500,
        strike: Some(creature_life.GoStrike(
          spell4_effects_ids: [132_757],
          inside: second,
        )),
      ),
      creature_life.Go(at_ms: 3800, strike: None),
    ])
  }
  // Row (a): who stands inside each go's own shapes.
  [
    #(
      "the cones of rows 7956 and 7957: player 5 is inside the first only, player 6 the second only, player 2 on the axis both",
      spawn_support.ice_breath(hold_ms: 500),
      [2, 5],
      [2, 6],
    ),
    #(
      "a go whose shapes are the same for both hits strikes the same fighters at both",
      ice_gos(
        spawn_support.ice_breath_cone(turn_degrees: 10.0),
        spawn_support.ice_breath_cone(turn_degrees: 10.0),
      ),
      [2, 5],
      [2, 5],
    ),
  ]
  |> list.each(fn(row) {
    let #(reason, special, first_struck, second_struck) = row
    let #(state, aggro) = ice_with_players(special:)
    let ice = ice_through(state:, aggro:, through: 2)
    assert struck_numbers(ice.went) == second_struck as reason
    // Go 1's step is not kept by `ice_through`: run the cast again to its first strike.
    let #(state, aggro) = ice_with_players(special:)
    let ice = ice_through(state:, aggro:, through: 1)
    assert struck_numbers(ice.went) == first_struck as reason
  })
  // Row (b): Spell4 45951's gos 200, 1,000, 1,200 and 1,800 ms with its two damage rows,
  // 107436 (phaseFlags 2: go 1) and 107454 (phaseFlags 8: go 3); crit chance, severity and
  // strikethrough are the attack's.
  let blow = fn(id) {
    Blow(
      spell4_effects_id: id,
      damage_type: 1,
      damage: Worked(21),
      delay_ms: 0,
      threat_multiplier: 1.0,
    )
  }
  let two_rows =
    spawn_support.special_with_charged(
      spawn_support.ice_breath(hold_ms: 0),
      fn(charged) {
        let assert creature_life.Charged(..) = charged
          as "Ice Breath is a charge"
        creature_life.Charged(..charged, cast_ms: 1800, gos: [
          creature_life.Go(at_ms: 200, strike: None),
          creature_life.Go(
            at_ms: 1000,
            strike: Some(creature_life.GoStrike(
              spell4_effects_ids: [107_436],
              inside: spawn_support.ice_breath_cone(turn_degrees: 10.0),
            )),
          ),
          creature_life.Go(at_ms: 1200, strike: None),
          creature_life.Go(
            at_ms: 1800,
            strike: Some(creature_life.GoStrike(
              spell4_effects_ids: [107_454],
              inside: spawn_support.ice_breath_cone(turn_degrees: 10.0),
            )),
          ),
        ])
      },
    )
  let special =
    creature_life.Special(
      ..two_rows,
      attack: creature_life.Attack(
        ..two_rows.attack,
        offence: Offence(
          blows: [blow(107_436), blow(107_454)],
          crit_chance: 0.25,
          crit_severity: 1.75,
          strikethrough: 0.125,
        ),
      ),
    )
  let #(state, aggro) = ice_fought_with(special:, viewers: [2])
  let #(state, _, first) = opened_for(state:, aggro:, first_go_ms: 200)
  let #(state, zero) = fire(state:, at_ms: 1700, timer: first)
  let #(state, one) = fire(state:, at_ms: 2500, timer: timer_for(zero, 800))
  let #(state, two) = fire(state:, at_ms: 2700, timer: timer_for(one, 200))
  let #(_, three) = fire(state:, at_ms: 3300, timer: timer_for(two, 600))
  let blows_of = fn(taken) {
    let assert [#(2, Attacks(tell: Strike(offence:, ..)))] = fights_told(taken)
    #(
      list.map(offence.blows, fn(blow) { blow.spell4_effects_id }),
      offence.crit_chance,
      offence.crit_severity,
      offence.strikethrough,
    )
  }
  assert blows_of(one) == #([107_436], 0.25, 1.75, 0.125)
    as "the strike at go 1 carries blow 107436 alone, with the attack's crit and strikethrough"
  assert blows_of(three) == #([107_454], 0.25, 1.75, 0.125)
    as "the strike at go 3 carries blow 107454 alone"
}

pub fn a_fighter_the_first_hit_killed_is_not_struck_by_the_second_test() -> Nil {
  use <- owned_test.run(5000)
  // Row (a): players 2 and 7 both on the axis. Both are struck at go 1; player 7 answers, then
  // player 2's killing answer: go 2 strikes player 7 alone.
  let #(state, aggro) = ice_fought(viewers: [2, 7])
  let state = with_player_at(state:, number: 7, x: 0.0, z: -5.0)
  let ice = ice_through(state:, aggro:, through: 1)
  assert struck_numbers(ice.went) == [2, 7]
    as "both fighters are struck by go 1"
  let key_7 = strike_key(taken: ice.went, number: 7)
  let #(state, _) =
    tell(state: ice.state, at_ms: 4510, message: landed(key: key_7))
  let #(state, killed) =
    tell(
      state:,
      at_ms: 4520,
      message: killing_answer(key: strike_key(taken: ice.went, number: 2)),
    )
  assert list.contains(said(killed), "Released(7) to 2")
  let assert Some(pending) = ice.pending
  let #(_, two) = fire(state:, at_ms: 5000, timer: pending)
  assert struck_numbers(two) == [7] as "go 2 strikes the fighter that is left"
  // Row (b): player 2 alone. Its killing answer writes go 1 listing it, then the threat list is
  // empty and the leash runs inside the answer: the pending go cancelled, the cast finished,
  // the fighter released; nothing strikes at 5,000.
  let #(state, aggro) = ice_fought(viewers: [2])
  let ice = ice_through(state:, aggro:, through: 1)
  let #(state, killed) =
    tell(
      state: ice.state,
      at_ms: 4550,
      message: killing_answer(key: strike_key(taken: ice.went, number: 2)),
    )
  assert frames_of(taken: killed, number: 2) == ["0x7f4 phase 1 [20]", "0x7fe"]
    as "go 1 lists the killed fighter, then the cast finishes"
  let assert Some(pending) = ice.pending
  assert list.contains(timers_cancelled(killed), pending)
    as "the pending go's timer is cancelled"
  assert list.contains(said(killed), "Released(7) to 2")
  let #(state, late) = fire(state:, at_ms: 5000, timer: pending)
  assert said(late) == [] && timers(late) == []
    as "the old go timer does nothing"
  let assert Ok(deadline) = list.key_find(ice.deadlines, 1)
  let #(_, after) = fire(state:, at_ms: 5550, timer: deadline)
  assert said(after) == [] && timers(after) == []
    as "and so does go 1's deadline"
}

/// What interrupts an Ice Breath cast: a Stagger stun on the creature, or a knockback throw
/// that carries it 10 units past its target.
type Break {
  Stun
  Throw
}

/// A row of the table of breaks between hits: the gos handled (`through`), the hits answered
/// before the break, what breaks the cast and when, the frames the break sends viewer 2, the
/// timers it cancels (`cancels_named`), whether a second state follows and finds nothing, and the answer
/// that arrives after the break with the frames it sends.
type BreakRow {
  BreakRow(
    reason: String,
    through: Int,
    answered: List(Int),
    interrupt: Break,
    at_ms: Int,
    frames: List(String),
    cancelled: List(String),
    second_state: Bool,
    then_answer: Option(Int),
    then_frames: List(String),
  )
}

fn broken_by(
  state state: State,
  interrupt interrupt: Break,
  at_ms at_ms: Int,
) -> #(State, ServiceStep(creature.Outgoing)) {
  case interrupt {
    Stun -> stunned_at(state:, at_ms:)
    Throw ->
      tell(
        state:,
        at_ms:,
        message: knockback_from(unit_at: at_xz(x: 0.0, z: 5.0)),
      )
  }
}

pub fn a_state_between_hits_ends_the_rest_of_the_cast_and_closes_the_open_rounds_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  [
    BreakRow(
      reason: "a stun after go 1's strike went out with no answer, go 2 pending: go 1 is written with no target, then the 0x7f9",
      through: 1,
      answered: [],
      interrupt: Stun,
      at_ms: 4600,
      frames: ["0x7f4 phase 1 []", "0x7f9"],
      cancelled: ["cancels the pending go", "cancels deadline 1"],
      second_state: False,
      then_answer: Some(1),
      then_frames: [],
    ),
    BreakRow(
      reason: "a stun after go 1 was answered and written, before go 2: the 0x7f9 alone",
      through: 1,
      answered: [1],
      interrupt: Stun,
      at_ms: 4800,
      frames: ["0x7f9"],
      cancelled: ["cancels the pending go"],
      second_state: False,
      then_answer: None,
      then_frames: [],
    ),
    BreakRow(
      reason: "a stun with go 2's round open and go 3 pending: go 2 is written with no target, then the 0x7f9, and phase 3 is never written",
      through: 2,
      answered: [1],
      interrupt: Stun,
      at_ms: 5100,
      frames: ["0x7f4 phase 2 []", "0x7f9"],
      cancelled: ["cancels the pending go", "cancels deadline 2"],
      second_state: False,
      then_answer: Some(2),
      then_frames: [],
    ),
    BreakRow(
      reason: "a stun once every go is reached breaks nothing: go 2's answer writes phase 2, phase 3 and the finish",
      through: 3,
      answered: [1],
      interrupt: Stun,
      at_ms: 5350,
      frames: [],
      cancelled: [],
      second_state: False,
      then_answer: Some(2),
      then_frames: ["0x7f4 phase 2 [20]", "0x7f4 phase 3 []", "0x7fe"],
    ),
    BreakRow(
      reason: "a second state in the same round finds no cast: one 0x7f9",
      through: 1,
      answered: [],
      interrupt: Stun,
      at_ms: 4600,
      frames: ["0x7f4 phase 1 []", "0x7f9"],
      cancelled: ["cancels the pending go", "cancels deadline 1"],
      second_state: True,
      then_answer: None,
      then_frames: [],
    ),
    BreakRow(
      reason: "a throw between hits breaks as a state does",
      through: 1,
      answered: [],
      interrupt: Throw,
      at_ms: 4600,
      frames: ["0x7f4 phase 1 []", "0x7f9"],
      cancelled: ["cancels the pending go", "cancels deadline 1"],
      second_state: False,
      then_answer: None,
      then_frames: [],
    ),
  ]
  |> list.each(fn(row) {
    let #(state, aggro) = ice_fought(viewers: [2])
    let ice = ice_through(state:, aggro:, through: row.through)
    let ice =
      list.fold(row.answered, ice, fn(ice, phase) {
        ice_answered(ice:, phase:, at_ms: 4550).0
      })
    let #(state, broken) =
      broken_by(state: ice.state, interrupt: row.interrupt, at_ms: row.at_ms)
    assert frames_of(taken: broken, number: 2) == row.frames as row.reason
    assert cancels_named(taken: broken, ice:) == row.cancelled
      as {
        row.reason <> ": the pending go and each open deadline are cancelled"
      }
    let started = list.map(timers(broken), fn(started) { started.1 })
    assert list.contains(started, 1500) == { row.frames != [] }
      as {
        row.reason
        <> ": a broken cast starts the next attack tick after the interval, not the hold"
      }
    // What fires after the break does nothing: the go timers and the deadlines.
    case row.frames {
      [] -> Nil
      [_, ..] ->
        list.each(
          list.flatten([
            ice.handled,
            option.values([ice.pending]),
            list.map(ice.deadlines, fn(deadline) { deadline.1 }),
          ]),
          fn(timer) {
            let #(_, fired) = fire(state:, at_ms: 6000, timer:)
            assert said(fired) == [] && timers(fired) == []
              as { row.reason <> ": a timer of the broken cast does nothing" }
          },
        )
    }
    let state = case row.second_state {
      False -> state
      True -> {
        let #(state, second) =
          tell(
            state:,
            at_ms: row.at_ms + 50,
            message: controlling(number: 2, cast_id: 3, controls: [
              crowd_control_support.gate_stun(instance_id: 28_674),
            ]),
          )
        assert frames_of(taken: second, number: 2) == []
          as { row.reason <> ": the second state finds no cast" }
        state
      }
    }
    case row.then_answer {
      None -> Nil
      Some(phase) -> {
        let assert Ok(key) = list.key_find(ice.keys, phase)
        let #(_, after) =
          tell(state:, at_ms: row.at_ms + 70, message: landed(key:))
        assert frames_of(taken: after, number: 2) == row.then_frames
          as row.reason
      }
    }
    // The special's cooldown stays spent: once the throw's flight is over, the next attack tick
    // (the hit left the target 6 units off) casts the instant attack, not the special again.
    case row.interrupt {
      Stun -> Nil
      Throw -> {
        assert list.contains(
          list.drop_while(said(broken), fn(line) { line != "0x7f9 to 2" }),
          "0x638 to 2",
        )
          as { row.reason <> ": the flight's 0x638 follows the 0x7f9" }
        let #(state, _) =
          fire(state:, at_ms: row.at_ms + 375, timer: timer_for(broken, 375))
        let #(_, ticked) =
          fire(state:, at_ms: row.at_ms + 1500, timer: timer_for(broken, 1500))
        let assert [CastStarted(start:)] = casts_of(ticked, 2)
        assert start.spell4_id == 5649
          as { row.reason <> ": the cooldown the cast spent is still running" }
      }
    }
  })
}

/// The Sim-Turret of migration 0030 (guarded by Spell4 85474, opened by 85472) with its
/// charge's gos replaced: the state and the step of its `Started`.
fn guarded_turret_with(
  gos gos: List(creature_life.Go),
  viewers viewers: List(Int),
) -> #(State, ServiceStep(creature.Outgoing)) {
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let kinds = spawn_support.guarded_turret_kinds()
  let assert Ok(kind) = dict.get(kinds.by_creature, 73_494)
    as "migrations 0029 and 0030 give the Exile turret its kind"
  started_with(
    source: spawn_source.Stored(id: SpawnId(1)),
    spawn: Spawn(
      ..spawn,
      combat: creature_life.Combat(
        ..spawn.combat,
        attack: spawn_support.attack_with_charged(
          attack: spawn.combat.attack,
          change: fn(charged) {
            let assert creature_life.Charged(..) = charged
              as "the turret's attack is a charge"
            creature_life.Charged(..charged, gos:)
          },
        ),
      ),
    ),
    kind:,
    viewers:,
    armor: creature_life.NoArmor,
  )
}

pub fn a_stun_between_hits_of_a_guarded_creatures_cast_opens_it_once_after_the_cast_is_closed_test() -> Nil {
  use <- owned_test.run(5000)
  // The Sim-Turret's charge with its one strike replaced by two strikes (at 3,000 and 5,000
  // ms) and a last go (8,000 ms): no client turret casts a multi-hit cast, so this cast is
  // planted. The charge opens at 3,000 ms, so the gos fall at 6,000, 8,000 and 11,000 ms.
  let spawn =
    spawn_support.sim_turret(number: 1, place: map_spawn_support.at(0.0))
  let assert creature_life.Charged(
    gos: [creature_life.Go(strike: Some(strike), ..)],
    ..,
  ) = spawn.combat.attack.cast
    as "the turret's charge has one go, which strikes"
  let #(turret, started) =
    guarded_turret_with(
      gos: [
        creature_life.Go(at_ms: 3000, strike: Some(strike)),
        creature_life.Go(at_ms: 5000, strike: Some(strike)),
        creature_life.Go(at_ms: 8000, strike: None),
      ],
      viewers: [2],
    )
  let assert [_, CastStarted(start: guard), ..] = news_to(started, 2)
    as "the start sends the 0x262, then the guard's 0x7ff"
  let #(state, aggro) =
    tell(
      state: turret,
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  let #(state, opened) =
    fire(state:, at_ms: 3000, timer: timer_for(aggro, 3000))
  let charge_cast = cast_id_sent(opened, 2)
  let #(state, first) =
    fire(state:, at_ms: 6000, timer: timer_for(opened, 3000))
  let assert [#(2, Attacks(..))] = fights_told(first)
    as "the first hit is out, unanswered"
  let #(_, stunned) = stunned_at(state:, at_ms: 6500)
  let assert [
    unit_news.CrowdControlApplied(state: crowd_control_state.Stun, ..),
    CastWent(go: written),
    unit_news.CastInterrupted(cast_id: broken),
    CastStarted(start: opening),
    CastWent(go: opening_go),
    unit_news.CastTargetsRemoved(removed:, destroyed: True),
    unit_news.CrowdControlApplied(state: crowd_control_state.Vulnerability, ..),
    unit_news.CrowdControlApplied(state: crowd_control_state.Disable, ..),
  ] = news_named(stunned, 2)
    as "the stun, the open hit's 0x7f4, the 0x7f9, then the guard's opening: its cast, the guard's removal, its states"
  assert written.cast_id == charge_cast
    && written.phase == 0
    && written.targets == []
    && broken == charge_cast
    as "the hit is written for the charge, with no target, before the 0x7f9"
  assert opening.spell4_id == 85_472
    && opening.cast_id != guard.cast_id
    && opening.cast_id != charge_cast
    && opening_go.cast_id == opening.cast_id
    && removed == SpellTargetsRemoved(cast_id: guard.cast_id, unit_ids: [unit])
    as "the opening's cast id is neither the guard's nor the charge's"
  assert openings_ending(stunned) == 1 as "one opening, one 15,000 ms timer"
}

pub fn death_and_the_leash_between_hits_cancel_every_timer_and_close_the_cast_once_test() -> Nil {
  use <- owned_test.run(5000)
  // Viewer 3 only watches, so it is told what the fighters' leaving leaves to send.
  [
    DeathRow(
      reason: "death with go 1's round open and go 2 pending: the pending go and go 1's deadline are cancelled, one 0x7fe and no 0x7f4",
      through: 1,
      answered: [],
      ends: Death,
      at_ms: 4600,
      frames: ["0x7fe"],
      cancelled: ["cancels the pending go", "cancels deadline 1"],
    ),
    DeathRow(
      reason: "the leash with strikes out at go 1 and go 2 and go 3 pending: both open rounds are written with no target, in order, then one 0x7fe",
      through: 2,
      answered: [],
      ends: Leash,
      at_ms: 5100,
      frames: ["0x7f4 phase 1 []", "0x7f4 phase 2 []", "0x7fe"],
      cancelled: [
        "cancels the pending go",
        "cancels deadline 1",
        "cancels deadline 2",
      ],
    ),
    DeathRow(
      reason: "death with every go reached, go 2's round open and go 3 complete behind it: go 2's deadline is cancelled once, one 0x7fe and no 0x7f4",
      through: 3,
      answered: [1],
      ends: Death,
      at_ms: 5350,
      frames: ["0x7fe"],
      cancelled: ["cancels deadline 2"],
    ),
    DeathRow(
      reason: "the leash with every go reached: phase 2, then phase 3 with no target, then the 0x7fe",
      through: 3,
      answered: [1],
      ends: Leash,
      at_ms: 5350,
      frames: ["0x7f4 phase 2 []", "0x7f4 phase 3 []", "0x7fe"],
      cancelled: ["cancels deadline 2"],
    ),
  ]
  |> list.each(fn(row) {
    let #(state, aggro) = ice_fought(viewers: [2, 3])
    let ice = ice_through(state:, aggro:, through: row.through)
    let ice =
      list.fold(row.answered, ice, fn(ice, phase) {
        ice_answered(ice:, phase:, at_ms: 4550).0
      })
    let #(state, ended) = case row.ends {
      Death ->
        tell(
          state: ice.state,
          at_ms: row.at_ms,
          message: strike_of(number: 2, cast_id: 1, blows: [
            #(1, 1_000_000, 1.0),
          ]),
        )
      Leash ->
        tell(
          state: ice.state,
          at_ms: row.at_ms,
          message: creature_news_support.unseen(by: ConnectionId(2)),
        )
    }
    assert frames_of(taken: ended, number: 3) == row.frames as row.reason
    assert cancels_named(taken: ended, ice:) == row.cancelled
      as { row.reason <> ": every timer of the cast is cancelled once" }
    // Whatever fires after: the go timers, the deadlines and a late answer do nothing.
    list.each(
      list.flatten([
        ice.handled,
        option.values([ice.pending]),
        list.map(ice.deadlines, fn(deadline) { deadline.1 }),
      ]),
      fn(timer) {
        let #(_, fired) = fire(state:, at_ms: 6000, timer:)
        assert frames_of(taken: fired, number: 3) == [] && timers(fired) == []
          as { row.reason <> ": a timer of the closed cast does nothing" }
      },
    )
    list.each(ice.keys, fn(keyed) {
      let #(_, late) = tell(state:, at_ms: 6000, message: landed(key: keyed.1))
      assert frames_of(taken: late, number: 3) == []
        as { row.reason <> ": a late answer writes nothing" }
    })
  })
}

type EndsBy {
  Death
  Leash
}

type DeathRow {
  DeathRow(
    reason: String,
    through: Int,
    answered: List(Int),
    ends: EndsBy,
    at_ms: Int,
    frames: List(String),
    cancelled: List(String),
  )
}

pub fn a_viewer_arriving_between_hits_is_told_only_the_gos_already_written_test() -> Nil {
  use <- owned_test.run(5000)
  let watched_at = fn(state, at_ms, number) {
    tell(
      state:,
      at_ms:,
      message: creature_news_support.seen(
        by: ConnectionId(number),
        stay: map_support.stay(count: number),
      ),
    )
  }
  // Row (a): player 9 watches at 4,800, go 1's round open: the cast and phase 0 only; phase 1
  // reaches it once, when go 1 closes.
  let #(state, aggro) = ice_fought(viewers: [2])
  let ice = ice_through(state:, aggro:, through: 1)
  let #(state, watched) = watched_at(ice.state, 4800, 9)
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff", "0x7f4"]
    as "the fight, the open cast and its first go only"
  let assert [_, _, _, CastStarted(start:), CastWent(went)] =
    news_to(watched, 9)
  assert start.cast_id == cast_id_sent(ice.opened, 2)
    && went.cast_id == start.cast_id
    && went.phase == 0
    && went.targets == []
    as "the same cast and its first go, so the later go names it"
  let assert Ok(key) = list.key_find(ice.keys, 1)
  let #(_, closed) = tell(state:, at_ms: 4850, message: landed(key:))
  assert frames_of(taken: closed, number: 9) == ["0x7f4 phase 1 [20]"]
    as "go 1 reaches the late viewer once, when it closes"
  // Row (b): player 9 watches at 5,350, every go reached, go 2's round open and go 3 complete
  // behind it: the cast and phases 0 and 1; phases 2 and 3 and the finish at go 2's close.
  let #(state, aggro) = ice_fought(viewers: [2])
  let ice = ice_through(state:, aggro:, through: 3)
  let #(ice, _) = ice_answered(ice:, phase: 1, at_ms: 4550)
  let #(state, watched) = watched_at(ice.state, 5350, 9)
  assert list.map(news_to(watched, 9), creature_news_support.name_of)
    == ["0x262", "0x89a(1)", "0x908(20, 1)", "0x7ff", "0x7f4", "0x7f4"]
    as "the cast and the two gos already written"
  assert frames_of(taken: watched, number: 9)
    == ["0x7f4 phase 0 []", "0x7f4 phase 1 []"]
  let assert Ok(key) = list.key_find(ice.keys, 2)
  let #(_, closed) = tell(state:, at_ms: 5400, message: landed(key:))
  assert frames_of(taken: closed, number: 9)
    == ["0x7f4 phase 2 [20]", "0x7f4 phase 3 []", "0x7fe"]
    as "the rest reaches the late viewer when go 2 closes"
  // Row (c): player 9 watches at 4,650 after a state broke the cast at 4,600: no cast news.
  let #(state, aggro) = ice_fought(viewers: [2])
  let ice = ice_through(state:, aggro:, through: 1)
  let #(state, _) = stunned_at(state: ice.state, at_ms: 4600)
  let #(_, watched) = watched_at(state, 4650, 9)
  assert !list.any(news_to(watched, 9), fn(news) {
    list.contains(["0x7ff", "0x7f4"], creature_news_support.name_of(news))
  })
    as "the cast is closed: the viewer is sent none of it"
}

pub fn a_timer_or_an_answer_that_comes_again_leaves_the_other_rounds_alone_test() -> Nil {
  use <- owned_test.run(5000)
  let through = fn(go) {
    let #(state, aggro) = ice_fought(viewers: [2])
    ice_through(state:, aggro:, through: go)
  }
  [
    Overlap(
      reason: "go 1's go timer fires again after go 2 is armed: an old generation, nothing strikes",
      run: fn() {
        let ice = through(2)
        let assert [_, first, ..] = ice.handled
        let #(_, again) = fire(state: ice.state, at_ms: 5100, timer: first)
        list.append(
          said(again),
          list.map(timers(again), fn(started) { int.to_string(started.1) }),
        )
      },
      expected: [],
    ),
    Overlap(
      reason: "go 1's deadline fires after its round closed by answers while go 2's is open: go 2's stays open and its answer still closes it",
      run: fn() {
        let ice = through(2)
        let #(ice, _) = ice_answered(ice:, phase: 1, at_ms: 4550)
        let assert Ok(deadline) = list.key_find(ice.deadlines, 1)
        let #(state, fired) =
          fire(state: ice.state, at_ms: 5500, timer: deadline)
        let ice = Ice(..ice, state:)
        let #(_, two) = ice_answered(ice:, phase: 2, at_ms: 5550)
        list.append(
          observed(taken: fired, ice:, number: 2),
          observed(taken: two, ice:, number: 2),
        )
      },
      expected: ["cancels deadline 2", "0x7f4 phase 2 [20]"],
    ),
    Overlap(
      reason: "the same answer twice: the second is not written",
      run: fn() {
        let ice = through(1)
        let #(ice, first) = ice_answered(ice:, phase: 1, at_ms: 4550)
        let #(ice, second) = ice_answered(ice:, phase: 1, at_ms: 4560)
        list.append(
          observed(taken: first, ice:, number: 2),
          observed(taken: second, ice:, number: 2),
        )
      },
      expected: ["cancels deadline 1", "0x7f4 phase 1 [20]"],
    ),
    Overlap(
      reason: "the last answer, then the deadline: the entry is written once",
      run: fn() {
        let ice = through(1)
        let #(ice, answered) = ice_answered(ice:, phase: 1, at_ms: 4550)
        let assert Ok(deadline) = list.key_find(ice.deadlines, 1)
        let #(_, fired) = fire(state: ice.state, at_ms: 5500, timer: deadline)
        list.append(
          observed(taken: answered, ice:, number: 2),
          observed(taken: fired, ice:, number: 2),
        )
      },
      expected: ["cancels deadline 1", "0x7f4 phase 1 [20]"],
    ),
    Overlap(
      reason: "the deadline, then the last answer: the entry is written once",
      run: fn() {
        let ice = through(1)
        let assert Ok(deadline) = list.key_find(ice.deadlines, 1)
        let #(state, fired) =
          fire(state: ice.state, at_ms: 5500, timer: deadline)
        let ice = Ice(..ice, state:)
        let #(ice, answered) = ice_answered(ice:, phase: 1, at_ms: 5510)
        list.append(
          observed(taken: fired, ice:, number: 2),
          observed(taken: answered, ice:, number: 2),
        )
      },
      expected: ["0x7f4 phase 1 []"],
    ),
  ]
  |> list.each(fn(row) {
    assert row.run() == row.expected as row.reason
  })
}

// ---- the player whose state broke a charge is told which spell it broke (opcode.0x247.interrupted) ----
//
// The mark rides the answer to the strike whose first landed state broke the charge, for the
// stunner's connection to write the combat log line. The charges are the Sim-Turret's
// (Spell4 85469, castTime 8000) and Rootbrute Grimspore's Earthen Roar (Spell4 55317).

const turret_charge = 85_469

const earthen_roar = 55_317

/// The mark of each state the step's answers list, in order: the spell of the charge the state
/// broke, or none.
fn marks_of(
  taken: ServiceStep(creature.Outgoing),
) -> List(Option(strike_tell.Interrupted)) {
  list.flat_map(answers_of(taken), fn(outcome) {
    case outcome {
      Landed(controls:, ..) | Immune(controls:, ..) ->
        list.map(controls, fn(control) { control.interrupted })
      strike_tell.Deflected(..) | Refused(..) -> []
    }
  })
}

fn marked(spell4_id spell4_id: Int) -> Option(strike_tell.Interrupted) {
  Some(strike_tell.Interrupted(spell4_id: Spell4Id(spell4_id)))
}

/// A strike of player `number` with a blow of 10 and these states.
fn striking_with(
  number number: Int,
  cast_id cast_id: Int,
  controls controls: List(strike_tell.ControlTell),
) -> creature.Message {
  let assert creature.Strike(tell:) =
    strike_of(number:, cast_id:, blows: [#(1, 10, 1.0)])
    as "strike_of gives a strike"
  creature.Strike(tell: Strike(..tell, controls:))
}

/// A scene with a charge open: its state, the time in ms a state strikes it at, and the spell
/// of the charge.
type OpenCast {
  OpenCast(reason: String, state: State, at_ms: Int, spell4_id: Int)
}

fn open_casts(viewers viewers: List(Int)) -> List(OpenCast) {
  let #(bare, aggro) = fought(viewers:)
  let #(bare, _, _) = charge_opened(state: bare, aggro:)
  let #(roar, roar_aggro) = roar_fought(viewers:)
  let #(before_gos, _, first_go) = roar_opened(state: roar, aggro: roar_aggro)
  let #(between_gos, _, _) = first_go_passed(state: before_gos, go: first_go)
  [
    OpenCast(
      reason: "the Sim-Turret's charge",
      state: bare,
      at_ms: 4000,
      spell4_id: turret_charge,
    ),
    OpenCast(
      reason: "the guarded Sim-Turret's charge",
      state: guarded_charge(viewers:).state,
      at_ms: 4000,
      spell4_id: turret_charge,
    ),
    OpenCast(
      reason: "Earthen Roar before its first go",
      state: before_gos,
      at_ms: 2000,
      spell4_id: earthen_roar,
    ),
    OpenCast(
      reason: "Earthen Roar between its gos",
      state: between_gos,
      at_ms: 4200,
      spell4_id: earthen_roar,
    ),
  ]
}

pub fn a_break_names_the_spell_of_the_charge_it_broke_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(open_casts(viewers: [2]), fn(scene) {
    let #(_, stunned) =
      tell(
        state: scene.state,
        at_ms: scene.at_ms,
        message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
      )
    assert marks_of(stunned) == [marked(spell4_id: scene.spell4_id)]
      as { scene.reason <> ": the state's mark names the charge's Spell4" }
    assert list.contains(said(stunned), "0x7f9 to 2")
      as { scene.reason <> ": the charge is broken in the same step" }
  })
}

type StateRow {
  StateRow(
    reason: String,
    scene: Int,
    strike: creature.Message,
    marks: List(Option(strike_tell.Interrupted)),
    thrown: Bool,
  )
}

pub fn the_first_state_a_strike_lands_in_a_charge_is_marked_with_the_charges_spell_test() -> Nil {
  use <- owned_test.run(5000)
  // Scene 0 is the Sim-Turret's charge, 1 the guarded turret's, 2 Earthen Roar before its
  // first go, whose beast moves and so can be thrown.
  [
    StateRow(
      reason: "a Stagger stun that lands on Earthen Roar",
      scene: 2,
      strike: stunning(from: 2, cast_id: 1, instance_id: 28_673),
      marks: [marked(spell4_id: earthen_roar)],
      thrown: False,
    ),
    StateRow(
      reason: "a stun with a blow on the guarded turret, which takes the blow as immune and the state",
      scene: 1,
      strike: striking_with(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
      ]),
      marks: [marked(spell4_id: turret_charge)],
      thrown: False,
    ),
    StateRow(
      reason: "Kick's knockdown on the turret",
      scene: 0,
      strike: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.kick_knockdown(instance_id: 28_673),
      ]),
      marks: [marked(spell4_id: turret_charge)],
      thrown: False,
    ),
    StateRow(
      reason: "a knockback with its throw: one mark, and the flight still starts",
      scene: 2,
      strike: controlling(number: 2, cast_id: 1, controls: [
        knockback_state(instance_id: 28_673),
      ]),
      marks: [marked(spell4_id: earthen_roar)],
      thrown: True,
    ),
    StateRow(
      reason: "a strike with two states: only the first is marked",
      scene: 2,
      strike: controlling(number: 2, cast_id: 1, controls: [
        crowd_control_support.stagger_stun(instance_id: 28_673),
        crowd_control_support.kick_knockdown(instance_id: 28_674),
      ]),
      marks: [marked(spell4_id: earthen_roar), None],
      thrown: False,
    ),
  ]
  |> list.each(fn(row) {
    let assert Ok(scene) =
      list.first(list.drop(open_casts(viewers: [2]), row.scene))
      as "the scene exists"
    let #(_, taken) =
      tell(state: scene.state, at_ms: scene.at_ms, message: row.strike)
    assert marks_of(taken) == row.marks as row.reason
    assert list.contains(said(taken), "0x638 to 2") == row.thrown
      as { row.reason <> ": the throw starts the flight, or none" }
  })
}

pub fn two_players_stunning_one_charge_mark_only_the_first_strike_the_creature_took_test() -> Nil {
  use <- owned_test.run(5000)
  [#(2, 5), #(5, 2)]
  |> list.each(fn(order) {
    let #(first, second) = order
    let order =
      "player "
      <> int.to_string(first)
      <> "'s strike first, then player "
      <> int.to_string(second)
      <> "'s"
    let #(state, aggro) = fought(viewers: [2, 5])
    let #(state, _, _) = charge_opened(state:, aggro:)
    let #(state, first_taken) =
      tell(
        state:,
        at_ms: 4000,
        message: stunning(from: first, cast_id: 1, instance_id: 28_673),
      )
    let #(_, second_taken) =
      tell(
        state:,
        at_ms: 4100,
        message: controlling(number: second, cast_id: 1, controls: [
          crowd_control_support.gate_stun(instance_id: 28_674),
        ]),
      )
    assert marks_of(first_taken) == [marked(spell4_id: turret_charge)]
      as { order <> ": the strike the creature took first is marked" }
    assert marks_of(second_taken) == [None]
      as { order <> ": the second strike's state lands and is not marked" }
    assert list.contains(
      said(second_taken),
      "0x87f to " <> int.to_string(first),
    )
      as { order <> ": the second state is shown to the viewers (0x87f)" }
    assert !list.contains(said(second_taken), "0x7f9 to 2")
      as { order <> ": and breaks nothing more" }
  })
}

pub fn a_state_that_breaks_no_charge_marks_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let armored_turret = fn(armor) {
    turret_in(kinds: spawn_support.turret_kinds(), viewers: [2], armor:).0
  }
  let approached_turret = fn(armor) {
    tell(
      state: armored_turret(armor),
      at_ms: 0,
      message: approached_at(number: 2, x: 0.0, z: -10.0, seq: 1),
    )
  }
  let charging = fn(armor) {
    let #(state, aggro) = approached_turret(armor)
    charge_opened(state:, aggro:)
  }
  let #(striking, _, striking_ends) = charging(creature_life.NoArmor)
  let #(striking, _) =
    fire(state: striking, at_ms: 11_000, timer: striking_ends)
  [
    #(
      "armor above 0 takes the state's point and no state lands",
      charging(creature_life.Armor(points: 2)).0,
      4000,
    ),
    #(
      "infinite armor: no state lands",
      charging(creature_life.InfiniteArmor).0,
      4000,
    ),
    #(
      "no round open: the first attack tick is still to come",
      approached_turret(creature_life.NoArmor).0,
      1000,
    ),
    #("the round is striking: the last go is out", striking, 11_050),
    #(
      "a resting creature, in no fight",
      armored_turret(creature_life.NoArmor),
      0,
    ),
  ]
  |> list.each(fn(row) {
    let #(reason, state, at_ms) = row
    let #(_, taken) =
      tell(
        state:,
        at_ms:,
        message: stunning(from: 2, cast_id: 1, instance_id: 28_673),
      )
    assert list.all(marks_of(taken), fn(mark) { mark == None }) as reason
    assert !list.contains(said(taken), "0x7f9 to 2")
      as { reason <> ": no charge is broken" }
  })
}

pub fn a_death_or_a_leash_in_a_charge_marks_no_answer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) = fought(viewers: [2])
  let #(state, _, _) = charge_opened(state:, aggro:)
  let assert creature.Strike(tell: lethal) =
    strike_of(number: 2, cast_id: 1, blows: [#(1, 1_000_000, 1.0)])
    as "strike_of gives a strike"
  let #(_, killed) =
    tell(
      state:,
      at_ms: 4000,
      message: creature.Strike(
        tell: Strike(..lethal, controls: [
          crowd_control_support.stagger_stun(instance_id: 28_673),
        ]),
      ),
    )
  assert marks_of(killed) == [] && !list.contains(said(killed), "0x7f9 to 2")
    as "a stun strike that kills in the charge: the states drop with the creature, nothing is marked, nothing is broken"
  let #(_, leashed) =
    tell(
      state:,
      at_ms: 4000,
      message: creature_news_support.unseen(by: ConnectionId(2)),
    )
  assert marks_of(leashed) == [] && !list.contains(said(leashed), "0x7f9 to 2")
    as "the last fighter leaving ends the fight with no interrupter: no 0x7f9 and no answer"
}

type BreakOp {
  Approach(Int)
  StunBy(Int)
  WoundBy(Int)
  KillBy(Int)
  FireAll
}

fn break_op_of(numbers: #(Int, Int)) -> BreakOp {
  let player = numbers.1 % 3 * 3 + 2
  case numbers.0 % 8 {
    0 -> Approach(player)
    1 | 2 | 3 -> StunBy(player)
    4 | 5 -> WoundBy(player)
    6 -> KillBy(player)
    _ -> FireAll
  }
}

fn armor_of_run(number: Int) -> creature_life.InterruptArmor {
  case number % 3 {
    0 -> creature_life.NoArmor
    1 -> creature_life.Armor(points: 1)
    _ -> creature_life.InfiniteArmor
  }
}

/// The ids of the casts the step tells viewer 2 are broken (0x7f9).
fn broken_casts(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(news_to(taken, 2), fn(news) {
    case creature_news_support.name_of(news) {
      "0x7f9" -> {
        let assert unit_news.CastInterrupted(cast_id:) = news
          as "a 0x7f9 is a CastInterrupted"
        Ok(cast_id)
      }
      _ -> Error(Nil)
    }
  })
}

/// The breaches of "each 0x7f9 comes with one marked state in its step, and a cast is broken
/// once" over the operations on a turret watched by players 2, 5 and 8, each `FireAll`
/// firing every timer the creature started. `marks_in` counts the marked states of a step,
/// which the harness check plants.
fn unpaired_breaks(
  armor armor: creature_life.InterruptArmor,
  ops ops: List(BreakOp),
  marks_in marks_in: fn(ServiceStep(creature.Outgoing)) -> Int,
) -> List(String) {
  let #(state, _) =
    turret_in(kinds: spawn_support.turret_kinds(), viewers: [2, 5, 8], armor:)
  let #(_, _, _, _, found) =
    list.fold(ops, #(state, [], 0, [], []), fn(held, op) {
      let #(state, pending, at_ms, broken, found) = held
      let at_ms = at_ms + 100
      let #(state, taken) = case op {
        Approach(n) ->
          one_step(
            state:,
            at_ms:,
            message: approached_at(number: n, x: 0.0, z: -10.0, seq: at_ms),
          )
        StunBy(n) ->
          one_step(
            state:,
            at_ms:,
            message: stunning(from: n, cast_id: at_ms, instance_id: at_ms),
          )
        WoundBy(n) ->
          one_step(
            state:,
            at_ms:,
            message: strike_of(number: n, cast_id: at_ms, blows: [#(1, 1, 1.0)]),
          )
        KillBy(n) ->
          one_step(
            state:,
            at_ms:,
            message: strike_of(number: n, cast_id: at_ms, blows: [
              #(1, 1_000_000, 1.0),
            ]),
          )
        FireAll ->
          list.fold(
            pending,
            #(state, []),
            fn(so_far, timer: #(step.TimerId, Int)) {
              let #(state, taken) = so_far
              let #(state, more) = fire(state:, at_ms:, timer: timer.0)
              #(state, list.append(taken, [more]))
            },
          )
      }
      let pending = case op {
        FireAll -> list.flat_map(taken, timers)
        Approach(..) | StunBy(..) | WoundBy(..) | KillBy(..) ->
          list.append(pending, list.flat_map(taken, timers))
      }
      let casts = list.flat_map(taken, broken_casts)
      let marks = list.fold(taken, 0, fn(sum, step) { sum + marks_in(step) })
      let found = case list.length(casts) == marks {
        True -> found
        False -> [
          "at "
            <> int.to_string(at_ms)
            <> " ms the step breaks "
            <> int.to_string(list.length(casts))
            <> " cast(s) and marks "
            <> int.to_string(marks),
          ..found
        ]
      }
      let found = case
        list.any(casts, fn(cast) { list.contains(broken, cast) })
      {
        True -> ["a cast id is broken twice", ..found]
        False -> found
      }
      #(state, pending, at_ms, list.append(casts, broken), found)
    })
  found
}

/// The step of one message, as a list of the one step.
fn one_step(
  state state: State,
  at_ms at_ms: Int,
  message message: creature.Message,
) -> #(State, List(ServiceStep(creature.Outgoing))) {
  let #(state, taken) = tell(state:, at_ms:, message:)
  #(state, [taken])
}

fn marked_states(taken: ServiceStep(creature.Outgoing)) -> Int {
  list.length(list.filter(marks_of(taken), option.is_some))
}

pub fn over_random_strikes_each_break_marks_exactly_one_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(armor, numbers) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(0, 2),
    qcheck.generic_list(
      qcheck.tuple2(qcheck.bounded_int(0, 1000), qcheck.bounded_int(0, 1000)),
      qcheck.bounded_int(from: 1, to: 40),
    ),
  ))
  assert unpaired_breaks(
      armor: armor_of_run(armor),
      ops: list.map(numbers, break_op_of),
      marks_in: marked_states,
    )
    == []
    as "a 0x7f9 comes with one marked state of its step, and no cast is broken twice"
}

pub fn the_harness_names_a_break_whose_state_is_not_marked_test() -> Nil {
  use <- owned_test.run(5000)
  // The planted bug: no step marks anything.
  assert unpaired_breaks(
      armor: creature_life.NoArmor,
      ops: [Approach(2), FireAll, StunBy(2)],
      marks_in: fn(_) { 0 },
    )
    != []
}

pub fn a_player_who_wakes_in_a_ring_after_its_killing_answer_and_death_is_near_and_aggroed_test() -> Nil {
  use <- owned_test.run(5000)
  // The stream the map sends a creature that killed player 2: the killing answer, the
  // map's `PlayerDied`, then the wake's `Approached`, in the order the player's connection
  // told them (one sender). Player 2 is a viewer of the creature, as is player 5.
  let #(state, key) = struck_once_among(viewers: [2, 5])
  let player = ConnectionId(2)
  let #(answered, answer_step) =
    tell(state:, at_ms: 1600, message: killing_answer(key:))
  let home = timer_for(answer_step, 0)
  let near_and_listed = fn(state: State) {
    #(
      set.contains(creature_fight.near(state: creature.fight(state:)), player),
      set.contains(
        creature_fight.threatened(state: creature.fight(state:)),
        player,
      ),
    )
  }
  assert near_and_listed(answered) == #(False, False)
    as "the killing answer alone drops the player from near and the threat list"
  let #(died, _) =
    tell(state: answered, at_ms: 1650, message: creature.PlayerDied(by: player))
  assert near_and_listed(died) == #(False, False)
    as "and the death after it finds nothing to drop"
  // The wake, as a viewer of the creature in the stay it names and as a player that is not.
  let a_viewer_wakes = approached(number: 2, x: 5.0, seq: 3)
  let a_stranger_wakes =
    creature.Approached(member: step.RingMember(
      by: player,
      unit_id: unit_of(2),
      place: map_spawn_support.at(5.0),
      seq: 3,
      stay: map_support.stay(count: 9),
      hit_radius: place_support.player_hit_radius,
    ))
  let #(woke, _) = tell(state: died, at_ms: 1700, message: a_viewer_wakes)
  assert near_and_listed(woke).0 as "the player that wakes in the ring is near"
  let #(_, at_home) = fire(state: woke, at_ms: 1800, timer: home)
  assert list.contains(said(at_home), "0x908(20, 1) to 2")
    && list.contains(said(at_home), "Threatened(7, 3) to 2")
    as "and the home timer aggroes it: it is told it is threatened and is the target"
  let #(stranger, _) = tell(state: died, at_ms: 1700, message: a_stranger_wakes)
  assert near_and_listed(stranger).0
    as "a player that wakes in the ring in a stay the creature has no sight of is near too"
  let #(_, at_home) = fire(state: stranger, at_ms: 1800, timer: home)
  assert !aggroes(at_home)
    as "but the creature aggroes only a viewer of the stay: no threat for it"
  // The wake with no answer before it (the answer lost to the deadline or never sent).
  let #(state, _) = struck_once_among(viewers: [2, 5])
  let #(state, death_step) =
    tell(state:, at_ms: 1600, message: creature.PlayerDied(by: player))
  let #(woke, _) = tell(state:, at_ms: 1700, message: a_viewer_wakes)
  let #(_, at_home) =
    fire(state: woke, at_ms: 1800, timer: timer_for(death_step, 0))
  assert aggroes(at_home)
    as "a wake after the death alone is aggroed at the home timer as well"
}

pub fn a_strike_told_after_the_players_death_threatens_the_creature_and_its_first_strike_is_refused_dead_test() -> Nil {
  use <- owned_test.run(5000)
  // A `Died` proc's cast, or a standing spell's tick, makes the player's connection tell a
  // strike after the death it told the map; the map passes both on in that order.
  let #(state, died) =
    tell(
      state: beast(viewers: [2]),
      at_ms: 0,
      message: creature.PlayerDied(by: ConnectionId(2)),
    )
  assert said(died) == []
    as "the death of a player the creature has no entry for changes nothing"
  let #(state, struck) =
    tell(
      state:,
      at_ms: 100,
      message: strike_of(number: 2, cast_id: 1, blows: [#(1, 3, 1.0)]),
    )
  assert creature_fight.threatened(state: creature.fight(state:))
    == set.from_list([ConnectionId(2)])
    as "the strike of the dead player's connection puts it on the threat list: the creature keeps no list of the dead"
  let #(state, ticked) =
    fire(state:, at_ms: 1600, timer: timer_for(struck, 1500))
  let assert [#(2, Attacks(tell: Strike(key:, ..)))] = fights_told(ticked)
    as "the creature's first attack is a strike on that player"
  let #(state, refused) =
    tell(
      state:,
      at_ms: 1700,
      message: creature.StrikeAnswered(answered: Answered(
        key:,
        outcome: Refused(why: strike_tell.Dead),
      )),
    )
  assert list.contains(said(refused), "Released(7) to 2")
    as "the player is refused Dead: the creature releases it"
  assert creature_fight.threatened(state: creature.fight(state:)) == set.new()
    as "and drops it from the threat list"
}
