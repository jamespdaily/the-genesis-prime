//// A creature's rule (`genesis_prime/world_map/creature`), run as the pure rule it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The doc comment of `genesis_prime/world_map/creature` (its sequence and its
////   failure table): told `Watched(by)` it sends that connection its 0x262; told
////   `Unwatched(by)` its 0x355, if that connection was a viewer; it watches its
////   map run and stops with it.
//// - Design C (the Design artifact of issue 274, section 2): every message about a
////   unit comes from its owner's process, so the 0x262 and the 0x355 are the
////   creature's own sends, to the viewer's connection.
//// - The map's clock: `server_time_estimate_start` is the milliseconds since the
////   map started, from the origin the creature was given (`map.server_time`).
//// - The creature's values are the Virtual Battle Beast's (`spawn_support`).

import cast_support
import connection_rule_support as support
import crowd_control_support
import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, PropertiesChanged, Removed,
}
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/strike_tell.{Answered, Key, Landed, Refused, Strike}
import genesis_prime/game/unit_properties.{type Modifier, type Source, Change}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/step.{
  type ConnectionId, type Event, type ServiceEvent, type ServiceStep, Connection,
  ConnectionId, CreatureStart, OwnEffect, OwnEvent, Reply, Send, StartCreature,
  StartServiceTimer, Started, Stop, TimerId, Told, WatchEnded, WatchId,
}
import genesis_prime/table/id.{
  Creature2Id, Faction2Id, Spell4Id, UnitProperty2Id,
}
import genesis_prime/world_map/creature.{
  type State, Retire, Settings, Unwatched, Watched,
}
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import place_support
import spawn_support

const ship = MapId(world_id: 3460, instance: 0)

/// The time the map's clock started at on the monotonic clock.
const clock_origin_ms = 5000

/// A creature standing at a Battle Beast spawn as unit 7 of the first run.
fn creature() -> State {
  creature_for(viewers: [])
}

/// The same creature, started for these players, who see the spawn.
fn creature_for(viewers viewers: List(ConnectionId)) -> State {
  creature_at(spawn: spawn_support.battle_beast(number: 1, x: 0.0), viewers:)
}

/// A creature standing at this spawn as unit 7 of the first run, started for these
/// players.
fn creature_at(
  spawn spawn: Spawn,
  viewers viewers: List(ConnectionId),
) -> State {
  creature_from(source: spawn_source.Stored(id: SpawnId(1)), spawn:, viewers:)
}

/// The same creature, started at this source's spawn.
fn creature_from(
  source source: spawn_source.SpawnSource,
  spawn spawn: Spawn,
  viewers viewers: List(ConnectionId),
) -> State {
  creature.new(Settings(
    creature: CreatureStart(
      map: ship,
      incarnation: 1,
      unit_id: 7,
      life: 3,
      spawn: source,
      clock_origin_ms:,
      viewers: list.map(viewers, fn(viewer) {
        let ConnectionId(number) = viewer
        #(viewer, map_support.stay(count: number))
      }),
    ),
    spawn:,
    kind: Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
      guard: option.None,
    ),
    numbers: spawn_support.numbers,
  ))
}

fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(creature.Message)),
) -> #(State, ServiceStep(creature.Outgoing)) {
  creature.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// What the step sends, to the connection's number: the news it carries.
fn sent(taken: ServiceStep(creature.Outgoing)) -> List(#(Int, PeerNews)) {
  list.map(sent_for(taken), fn(sent) { #(sent.0, sent.2) })
}

/// What the step sends, to the connection's number: the stay it is for and the
/// news it carries.
fn sent_for(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, Stay, PeerNews)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(
        to: Connection(ConnectionId(number)),
        message: creature.News(stay:, news:),
      )) -> Ok(#(number, stay, news))
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | Stop -> Error(Nil)
    }
  })
}

pub fn a_creature_watches_its_run_and_sends_its_0x262_to_each_player_who_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  assert support.watches(taken) == [#(WatchId(1), step.Map(ship, 1))]
    as "the creature watches the run that started it, so it ends with it"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 6500,
      event: OwnEvent(
        Told(Watched(by: ConnectionId(5), stay: map_support.stay(count: 5))),
      ),
    )
  let assert [#(5, stay, PeerNews(unit_id:, news: CreatureAppeared(unit:, ..)))] =
    sent_for(taken)
    as "one 0x262, to the connection of the player who sees the creature"
  assert unit_id == 7 as "the news names the creature's unit"
  assert stay == map_support.stay(count: 5)
    as "for the viewer's stay the map's Watched named, so a news of an earlier stay is dropped"
  assert unit.unit_id == 7 && unit.creature_id == 73_464
  assert unit.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock: 6500 ms on the monotonic clock, 1500 after the map started"
}

pub fn a_creature_sends_its_0x355_once_to_a_player_who_stops_seeing_it_and_nothing_to_one_that_never_saw_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(
        Told(Watched(by: ConnectionId(5), stay: map_support.stay(count: 5))),
      ),
    )
  let #(state, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  let assert [#(5, PeerNews(unit_id: 7, news: Removed))] = sent(taken)
    as "a player who stops seeing it is sent its 0x355"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 8000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  assert sent(taken) == []
    as "a connection that is not a viewer is sent nothing"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 9000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(6)))),
    )
  assert sent(taken) == [] as "a connection that never saw it is sent nothing"
}

pub fn a_creature_stops_when_its_run_ends_and_when_the_server_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(_, taken) = feed(state:, at_ms: 6000, event: WatchEnded(WatchId(1)))
  assert support.stops(taken) as "the end of its run ends the creature"
  let #(_, taken) =
    feed(state:, at_ms: 6000, event: step.Stopping(deadline_ms: 11_000))
  assert support.stops(taken) as "the server stopping ends it"
}

pub fn a_creature_told_to_retire_stops_with_nothing_to_send_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(_, taken) = feed(state:, at_ms: 80_000, event: OwnEvent(Told(Retire)))
  assert support.stops(taken)
    as "the map's Retire ends the creature: no player has seen it for the idle stop"
  assert sent(taken) == []
    as "its viewers went with their Unwatched, so there is no 0x355 left to send"
}

pub fn a_creature_started_for_players_sends_each_its_0x262_as_it_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // The map's start of a creature names its first viewers (CreatureStart), so a
  // burst of starts is not followed by a burst of Watched sends.
  let #(state, taken) =
    feed(
      state: creature_for(viewers: [ConnectionId(2), ConnectionId(5)]),
      at_ms: 6500,
      event: OwnEvent(Started),
    )
  let assert [
    #(2, PeerNews(unit_id: 7, news: CreatureAppeared(unit: first, ..))),
    #(5, PeerNews(unit_id: 7, news: CreatureAppeared(unit: second, ..))),
  ] = sent(taken)
    as "one 0x262 for each first viewer, in the order the map gave them"
  assert first.tail.server_time_estimate_start == 1500
    && second.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock at the creature's start"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(2)))),
    )
  let assert [#(2, PeerNews(news: Removed, ..))] = sent(taken)
    as "a first viewer is a viewer: it is sent the 0x355 when it stops seeing the creature"
  Nil
}

/// What the step sends, in order, as the creature's sends of any kind.
fn outgoing(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, creature.Outgoing)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: Connection(ConnectionId(number)), message:)) ->
        Ok(#(number, message))
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | Stop -> Error(Nil)
    }
  })
}

/// A strike of the caster's connection 2 with one blow of `damage` of the Magic
/// type on the Beast unit 7, with rolls no deflect and no crit.
fn strike_of(damage damage: Int, cast_id cast_id: Int) -> creature.Message {
  typed_strike(damage:, damage_type: 3, cast_id:)
}

/// The same strike with a blow of this damage type: 1 Physical, 2 Tech, 3 Magic.
fn typed_strike(
  damage damage: Int,
  damage_type damage_type: Int,
  cast_id cast_id: Int,
) -> creature.Message {
  creature.Strike(
    tell: Strike(
      key: Key(cast_id:, phase: 0, unit_id: 7),
      from: step.Connection(ConnectionId(2)),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 1,
            damage_type:,
            damage:,
            delay_ms: 0,
            threat_multiplier: 1.0,
          ),
        ],
        crit_chance: 0.0,
        crit_severity: 1.5,
        strikethrough: 0.0,
      ),
      striker: strike_tell.PlayerStriker(
        unit_id: 1,
        place: place_support.at(
          world_id: 3460,
          world_zone_id: 5967,
          x: 0.0,
          y: 0.0,
          z: 0.0,
        ),
        seq: 1,
        stay: map_support.stay(count: 2),
        hit_radius: place_support.player_hit_radius,
        rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
      ),
      controls: [],
    ),
  )
}

/// The creature started for the viewers 2 and 5, standing.
fn watched_by_two() -> State {
  let #(state, _) =
    feed(
      state: creature_for(viewers: [ConnectionId(2), ConnectionId(5)]),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  state
}

fn kinds_of(sent: List(#(Int, creature.Outgoing))) -> List(String) {
  list.map(sent, fn(one) {
    case one.1 {
      creature.Struck(answered: Answered(outcome: Landed(..), ..), ..) ->
        "answer to " <> int.to_string(one.0)
      creature.Struck(..) -> "refusal to " <> int.to_string(one.0)
      creature.News(
        stay: _,
        news: PeerNews(news: client_connection.Health(..), ..),
      ) -> "health to " <> int.to_string(one.0)
      creature.News(stay: _, news: PeerNews(news: client_connection.Died, ..)) ->
        "death to " <> int.to_string(one.0)
      creature.News(stay: _, news: PeerNews(news: Removed, ..)) ->
        "removal to " <> int.to_string(one.0)
      creature.News(stay: _, news: PeerNews(news: CreatureAppeared(..), ..)) ->
        "creation to " <> int.to_string(one.0)
      creature.KillCredit(..) -> "credit to " <> int.to_string(one.0)
      creature.News(..) | creature.FightTold(..) -> "other"
    }
  })
}

pub fn a_creature_answers_the_caster_before_it_tells_any_viewer_its_health_and_death_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  assert kinds_of(outgoing(taken))
    == [
      "answer to 2",
      "credit to 2",
      "health to 2",
      "health to 5",
      "death to 2",
      "death to 5",
    ]
    as "the answer goes first, one sender in one order: the caster's connection knows the strike before it is told the health it left, so it can hold the news for the go (genesis_prime/game/strike); the killer's credit follows its answer"
  assert support.effects_of(taken)
    |> list.any(fn(effect) {
      effect
      == OwnEffect(StartServiceTimer(timer: TimerId(1), after_ms: 60_000))
    })
    as "the kill starts the corpse timer for the kind's respawn time"
}

/// The credits among what the step sends: the connection and the credit.
fn credits(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, creature.Outgoing)) {
  list.filter(outgoing(taken), fn(one) {
    case one.1 {
      creature.KillCredit(..) -> True
      creature.Struck(..) | creature.News(..) | creature.FightTold(..) -> False
    }
  })
}

pub fn a_killing_strike_sends_the_killer_one_credit_test() -> Nil {
  use <- owned_test.run(5000)
  // The Beast has 52 health (spawn_support.battle_beast): a strike of 10 leaves it
  // standing, one of 60 kills it.
  let #(wounded, taken) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 10, cast_id: 1))),
    )
  assert credits(taken) == []
    as "hit.Landed killed bit: a strike that leaves the creature standing is no kill"
  let #(dead, taken) =
    feed(
      state: wounded,
      at_ms: 6100,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 2))),
    )
  assert credits(taken)
    == [
      #(
        2,
        creature.KillCredit(
          stay: map_support.stay(count: 2),
          unit_id: 7,
          creature_id: Creature2Id(73_464),
          faction_id: Faction2Id(1441),
          level: 1,
        ),
      ),
    ]
    as "the killing blow sends the connection of the player who struck it, for the stay the strike came from, one credit naming the unit, the Creature2 row of the spawn (73464), its Faction2 (1441, the faction of the spawn row spawn_support.battle_beast, which the creature's 0x262 sends as its faction) and its level 1 (opcode.0x262.creature_level)"
  let #(_, taken) =
    feed(
      state: dead,
      at_ms: 6200,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 3))),
    )
  assert credits(taken) == []
    as "a strike on the corpse is refused as dead (Refused(Dead)) and credits nothing"
}

pub fn a_creature_struck_while_it_lies_dead_refuses_without_news_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 6100,
      event: OwnEvent(Told(strike_of(damage: 18, cast_id: 2))),
    )
  assert outgoing(taken)
    == [
      #(
        2,
        creature.Struck(
          stay: map_support.stay(count: 2),
          answered: Answered(
            key: Key(cast_id: 2, phase: 0, unit_id: 7),
            outcome: Refused(why: strike_tell.Dead),
          ),
        ),
      ),
    ]
    as "a second strike finds the corpse: refused as dead, no 0x937"
}

pub fn a_viewer_that_arrives_mid_fight_is_sent_the_creature_at_its_current_health_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 14, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(
        Told(Watched(by: ConnectionId(9), stay: map_support.stay(count: 9))),
      ),
    )
  let assert [#(9, PeerNews(news: CreatureAppeared(unit:, ..), ..)), ..] =
    sent(taken)
  assert creature_unit.health_of(unit:) == 38
    as "the Beast has 52 health and the strike took 14: opcode.0x262.creature carries the current health in stat 0, so the bar a viewer sees is the one the others see"
}

pub fn a_viewer_that_arrives_while_the_creature_lies_dead_is_sent_it_created_dead_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(
        Told(Watched(by: ConnectionId(9), stay: map_support.stay(count: 9))),
      ),
    )
  let assert [#(9, PeerNews(news: CreatureAppeared(unit:, life: 3, ..), ..))] =
    sent(taken)
  assert creature_unit.health_of(unit:) == 0
    as "opcode.0x262.creature: stat 0 of 0 makes the client create the creature dead"
}

pub fn the_corpse_timer_removes_and_creates_the_creature_again_at_full_health_for_each_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  assert kinds_of(outgoing(taken))
    == ["removal to 2", "creation to 2", "removal to 5", "creation to 5"]
    as "death.creature_respawn: 0x355, then a full 0x262 with the same unit id, to each viewer"
  let assert [
    _,
    #(
      2,
      creature.News(
        stay: _,
        news: PeerNews(news: CreatureAppeared(unit:, ..), ..),
      ),
    ),
    ..
  ] = outgoing(taken)
  assert creature_unit.health_of(unit:) == 52 && unit.unit_id == 7
}

pub fn a_run_only_creatures_corpse_timer_removes_it_for_each_viewer_and_stops_it_test() -> Nil {
  use <- owned_test.run(5000)
  // A summon does not respawn (a server choice, it is a test tool): where a
  // stored spawn's creature stands again at the corpse timer, a run-only one's
  // 0x355 goes to each viewer and the creature stops, so its map ends the spawn.
  let beast = spawn_support.battle_beast(number: -1, x: 0.0)
  let #(state, _) =
    feed(
      state: creature_from(
        source: spawn_source.RunOnly(spawn_source.Summoned(
          id: SpawnId(-1),
          creature_id: beast.creature_id,
          level: None,
          place: beast.place,
        )),
        spawn: beast,
        viewers: [ConnectionId(2), ConnectionId(5)],
      ),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  assert kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    as "a 0x355 to each viewer, and no 0x262 that stands it again"
  assert support.stops(taken) as "the creature stops"
}

pub fn a_creature_that_lies_dead_when_told_to_retire_stops_at_its_respawn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let #(state, taken) =
    feed(state:, at_ms: 80_000, event: OwnEvent(Told(Retire)))
  assert !support.stops(taken)
    as "the map keeps the spawn retiring until the creature ends, so the corpse waits"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 90_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  assert support.stops(taken) && outgoing(taken) == []
    as "at its respawn it stops, with no viewer to tell"
}

pub fn a_creature_that_stands_carries_its_life_hit_radius_and_whom_it_may_be_attacked_by_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    feed(
      state: creature_for(viewers: [ConnectionId(2)]),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let assert [
    #(
      2,
      PeerNews(
        news: CreatureAppeared(life: 3, hit_radius: 3.0, attackable:, unit:, ..),
        ..,
      ),
    ),
  ] = sent(taken)
  assert creature_unit.health_of(unit:) == 52
    && attackable == spawn_support.beast_combat().attackable
    as "life 3 is the number of the map's watch it was started under; the hit radius of the Beast's display is 3.0 (Spell4.32812.area)"
}

/// A Battle Beast spawn whose health is the world database's recorded 442, the
/// value of Creature2 11945 (`world_data.spawn_health`).
fn recorded_beast() -> Spawn {
  Spawn(
    ..spawn_support.battle_beast(number: 1, x: 0.0),
    health: 442,
    health_source: unit_fields.Recorded,
  )
}

/// The property list a recorded 442 is sent as: Base Health, property 7, with 442.0
/// in both words, 0x43DD0000 as a 32-bit float (sign 0, exponent 135, mantissa
/// 0x5D0000), as the player's vector sends its own (`opcode.0x262.health`).
fn base_health_442() -> List(unit_property.UnitProperty) {
  [UnitProperty(property_id: 7, base: 0x43DD0000, value: 0x43DD0000)]
}

pub fn a_viewer_that_arrives_while_a_recorded_creature_is_hurt_is_sent_its_current_health_and_its_recorded_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: creature_at(spawn: recorded_beast(), viewers: [ConnectionId(2)]),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 14, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(
        Told(Watched(by: ConnectionId(9), stay: map_support.stay(count: 9))),
      ),
    )
  let assert [#(9, PeerNews(news: CreatureAppeared(unit:, ..), ..)), ..] =
    sent(taken)
  assert creature_unit.health_of(unit:) == 428
    as "the recorded 442 less the strike's 14: stat 0 is the current health"
  assert unit.tail.properties == base_health_442()
    as "opcode.0x262.creature: property 7 is the recorded maximum, so the bar reads 428 of 442"
}

pub fn a_recorded_creature_comes_back_at_its_recorded_health_with_its_recorded_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: creature_at(spawn: recorded_beast(), viewers: [ConnectionId(2)]),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 442, cast_id: 1))),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  let assert [
    _,
    #(
      2,
      creature.News(
        stay: _,
        news: PeerNews(news: CreatureAppeared(unit:, ..), ..),
      ),
    ),
  ] = outgoing(taken)
    as "death.creature_respawn: 0x355, then a full 0x262 to the viewer"
  assert creature_unit.health_of(unit:) == 442
    as "it comes back at the recorded value, not the client's formula"
  assert unit.tail.properties == base_health_442()
    as "and sends it as Base Health again"
}

// ---- property modifiers of players' spells ----
//
// Expected values come from these places: the Beast's base values, which
// `unit_properties_test` works out from the client's tables (Move Speed
// Multiplier 100 is 1.0, Base Health 7 is 52.6204948425293, Armor 42 and Interrupt
// Armor Threshold 44 are 0.0, property 127 is 1.2750000953674316, property 150 is
// 0.0); a row's change x * multiplier + flat (`Spell4Effects.effectType.11.change`,
// `UnitProperty2.damage_heal_multipliers`); the module doc of
// `genesis_prime/world_map/creature` for who is told what and when; the Armor 150
// mitigation 0.5996959 at level 1 that `player_life_test` pins from GameFormula
// 1234 (`0x140464240`).

/// The connection of the caster whose spells put modifiers on the creature.
const caster = ConnectionId(9)

/// A Move Speed Multiplier row: x becomes x * 1.0 + 0.5.
fn sprint() -> Modifier {
  Change(
    property: UnitProperty2Id(100),
    mode: 3,
    multiplier: 1.0,
    flat: 0.5,
    per_level: 0.0,
  )
}

fn sprint_source() -> Source {
  cast_support.source_of(cast_id: 1, effect_id: 1921)
}

/// A row that adds 5.0 to property 150.
fn thorns() -> Modifier {
  Change(
    property: UnitProperty2Id(150),
    mode: 1,
    multiplier: 1.0,
    flat: 5.0,
    per_level: 0.0,
  )
}

fn thorns_source() -> Source {
  cast_support.source_of(cast_id: 2, effect_id: 1922)
}

/// A row that doubles property 127.
fn doubling() -> Modifier {
  Change(
    property: UnitProperty2Id(127),
    mode: 1,
    multiplier: 2.0,
    flat: 0.0,
    per_level: 0.0,
  )
}

fn doubling_source() -> Source {
  cast_support.source_of(cast_id: 3, effect_id: 1923)
}

/// The entry of 0x93a for a property, as its 32-bit float bits.
fn changed(
  property property: Int,
  base base: Float,
  value value: Float,
) -> UnitProperty {
  UnitProperty(
    property_id: property,
    base: float32.to_bits(base),
    value: float32.to_bits(value),
  )
}

/// What a start of `sprint` changes: Move Speed Multiplier from 1.0 to 1.5.
fn speed_up() -> UnitProperty {
  changed(property: 100, base: 1.0, value: 1.5)
}

/// What the end of `sprint` changes back.
fn speed_back() -> UnitProperty {
  changed(property: 100, base: 1.0, value: 1.0)
}

fn told(
  state state: State,
  at_ms at_ms: Int,
  message message: creature.Message,
) -> #(State, ServiceStep(creature.Outgoing)) {
  feed(state:, at_ms:, event: OwnEvent(Told(message)))
}

fn starting(
  source source: Source,
  modifier modifier: Modifier,
  struck_at_ms struck_at_ms: Int,
) -> creature.Message {
  creature.ModifierStarts(by: caster, source:, modifier:, struck_at_ms:)
}

/// The creature after the caster's start of this modifier, struck as it arrived.
fn holding(
  state state: State,
  source source: Source,
  modifier modifier: Modifier,
  at_ms at_ms: Int,
) -> State {
  told(
    state:,
    at_ms:,
    message: starting(source:, modifier:, struck_at_ms: at_ms),
  ).0
}

/// The properties the step sends to each viewer, as the number of the viewer and the
/// entries, in order.
fn property_news(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, List(UnitProperty))) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: PropertiesChanged(properties:), ..) ->
        Ok(#(one.0, properties))
      PeerNews(..) -> Error(Nil)
    }
  })
}

/// The watches the step drops, in order.
fn unwatches(taken: ServiceStep(creature.Outgoing)) -> List(step.WatchId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      step.Unwatch(watch:) -> Ok(watch)
      OwnEffect(..) | step.Watch(..) | step.Log(..) | Stop -> Error(Nil)
    }
  })
}

/// The health news the step sends, as the number of the viewer, the health and
/// whether it is dead.
fn health_news(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, Int, Bool)) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: client_connection.Health(health:, dead:), ..) ->
        Ok(#(one.0, health, dead))
      PeerNews(..) -> Error(Nil)
    }
  })
}

/// The Interrupt Armor news the step sends, as the number of the viewer and the
/// armor left.
fn armor_left(taken: ServiceStep(creature.Outgoing)) -> List(#(Int, Int)) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: client_connection.InterruptArmor(armor:), ..) ->
        Ok(#(one.0, armor))
      PeerNews(..) -> Error(Nil)
    }
  })
}

pub fn modifier_start_sends_properties_changed_to_viewers_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: starting(
        source: sprint_source(),
        modifier: sprint(),
        struck_at_ms: 6000,
      ),
    )
  assert sent(taken)
    == [
      #(2, PeerNews(unit_id: 7, news: PropertiesChanged([speed_up()]))),
      #(5, PeerNews(unit_id: 7, news: PropertiesChanged([speed_up()]))),
    ]
    as "0x93a of the unit, to each viewer: Move Speed Multiplier 1.0 x 1.0 + 0.5"
  assert support.watches(taken) == [#(WatchId(2), Connection(caster))]
    as "the creature watches the caster's connection, under its own id: the run's is 1"
}

pub fn modifier_end_restores_value_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let #(_, taken) =
    told(state:, at_ms: 7000, message: creature.ModifierEnds(sprint_source()))
  assert property_news(taken) == [#(2, [speed_back()]), #(5, [speed_back()])]
    as "the value goes back to the base, 1.0"
  assert unwatches(taken) == [WatchId(2)]
    as "it was the caster's last source: the creature stops watching the connection"
}

pub fn late_viewer_sees_current_value_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let #(_, taken) =
    told(
      state:,
      at_ms: 7000,
      message: Watched(by: ConnectionId(8), stay: map_support.stay(count: 8)),
    )
  let assert [#(8, PeerNews(news: CreatureAppeared(unit:, ..), ..))] =
    sent(taken)
    as "one 0x262, to the viewer that arrived"
  assert unit.tail.properties == [speed_up()]
    as "its property list carries the current value of the property a modifier changes"
}

pub fn start_for_another_life_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 60, cast_id: 1),
    )
  let #(state, _) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  let #(_, late) =
    told(
      state:,
      at_ms: 66_500,
      message: starting(
        source: sprint_source(),
        modifier: sprint(),
        struck_at_ms: 65_000,
      ),
    )
  assert support.effects_of(late) == []
    as "struck at 65000, before the creature stood again at 66000: a start of the life before"
  let #(_, now) =
    told(
      state:,
      at_ms: 66_500,
      message: starting(
        source: sprint_source(),
        modifier: sprint(),
        struck_at_ms: 66_000,
      ),
    )
  assert property_news(now) == [#(2, [speed_up()]), #(5, [speed_up()])]
    as "struck at the moment it stood again: the new life's"
}

pub fn end_for_unknown_source_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: creature.ModifierEnds(sprint_source()),
    )
  assert support.effects_of(taken) == []
}

pub fn same_source_started_twice_is_held_once_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let #(state, again) =
    told(
      state:,
      at_ms: 6100,
      message: starting(
        source: sprint_source(),
        modifier: sprint(),
        struck_at_ms: 6100,
      ),
    )
  assert support.effects_of(again) == []
    as "the same source is held once: nothing changes, nothing is sent, no second watch"
  let #(_, ended) =
    told(state:, at_ms: 7000, message: creature.ModifierEnds(sprint_source()))
  assert property_news(ended) == [#(2, [speed_back()]), #(5, [speed_back()])]
    as "one end restores the value"
}

pub fn caster_connection_end_removes_its_modifiers_test() -> Nil {
  use <- owned_test.run(5000)
  let other = ConnectionId(10)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let state =
    holding(state:, source: thorns_source(), modifier: thorns(), at_ms: 6100)
  let #(state, other_start) =
    told(
      state:,
      at_ms: 6200,
      message: creature.ModifierStarts(
        by: other,
        source: doubling_source(),
        modifier: doubling(),
        struck_at_ms: 6200,
      ),
    )
  assert support.watches(other_start) == [#(WatchId(3), Connection(other))]
    as "a second caster's connection is watched under the next id"
  let #(state, gone) = feed(state:, at_ms: 7000, event: WatchEnded(WatchId(2)))
  assert property_news(gone)
    == [
      #(2, [speed_back()]),
      #(5, [speed_back()]),
      #(2, [changed(property: 150, base: 0.0, value: 0.0)]),
      #(5, [changed(property: 150, base: 0.0, value: 0.0)]),
    ]
    as "each of the connection's sources ends as a ModifierEnds ends it, in the order they started"
  assert !support.stops(gone) && unwatches(gone) == []
    as "the creature goes on, and the watch that fired needs no Unwatch"
  let #(state, late) =
    told(state:, at_ms: 7100, message: creature.ModifierEnds(sprint_source()))
  assert support.effects_of(late) == []
    as "a later end for a source the connection's end removed changes nothing"
  let #(_, kept) =
    told(state:, at_ms: 7200, message: creature.ModifierEnds(doubling_source()))
  assert property_news(kept)
    == [
      #(2, [
        changed(
          property: 127,
          base: 1.2750000953674316,
          value: 1.2750000953674316,
        ),
      ]),
      #(5, [
        changed(
          property: 127,
          base: 1.2750000953674316,
          value: 1.2750000953674316,
        ),
      ]),
    ]
    as "the other caster's modifier was held all along"
}

pub fn run_watch_end_still_stops_creature_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let #(_, run_ended) = feed(state:, at_ms: 7000, event: WatchEnded(WatchId(1)))
  assert support.stops(run_ended) as "the run's end ends the creature"
  let #(_, caster_ended) =
    feed(state:, at_ms: 7000, event: WatchEnded(WatchId(2)))
  assert !support.stops(caster_ended) as "a caster's connection ending does not"
}

pub fn dead_creature_holds_modifiers_until_end_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 6000,
    )
  let #(state, _) =
    told(state:, at_ms: 7000, message: strike_of(damage: 60, cast_id: 1))
  let #(state, dropped) =
    told(
      state:,
      at_ms: 8000,
      message: starting(
        source: thorns_source(),
        modifier: thorns(),
        struck_at_ms: 8000,
      ),
    )
  assert support.effects_of(dropped) == []
    as "a start that reaches the creature while it is dead is dropped"
  let #(_, ended) =
    told(state:, at_ms: 9000, message: creature.ModifierEnds(sprint_source()))
  assert property_news(ended) == [#(2, [speed_back()]), #(5, [speed_back()])]
    as "the source it held before it died ends as always"
}

pub fn respawn_clears_modifiers_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    holding(
      state: watched_by_two(),
      source: sprint_source(),
      modifier: sprint(),
      at_ms: 5500,
    )
  let #(state, _) =
    told(state:, at_ms: 6000, message: strike_of(damage: 60, cast_id: 1))
  let #(state, stood) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  assert unwatches(stood) == [WatchId(2)]
    as "the creature stops watching a caster whose modifiers it cleared"
  assert kinds_of(outgoing(stood))
    == ["removal to 2", "creation to 2", "removal to 5", "creation to 5"]
  let assert [
    _,
    #(
      2,
      creature.News(news: PeerNews(news: CreatureAppeared(unit:, ..), ..), ..),
    ),
    ..
  ] = outgoing(stood)
  assert unit.tail.properties == []
    as "its properties start again from the bases: the new 0x262 lists none"
  let #(state, late) =
    told(state:, at_ms: 66_500, message: creature.ModifierEnds(sprint_source()))
  assert support.effects_of(late) == []
    as "an end for a cleared source changes nothing"
  let #(_, old) =
    told(
      state:,
      at_ms: 66_600,
      message: starting(
        source: sprint_source(),
        modifier: sprint(),
        struck_at_ms: 65_000,
      ),
    )
  assert support.effects_of(old) == []
    as "and a start struck on the life before is dropped"
}

pub fn base_health_modifier_clamps_health_test() -> Nil {
  use <- owned_test.run(5000)
  // Base Health halved: 52.6204948425293 x 0.5 = 26.31024742126465, a maximum of
  // 26 after truncation, so the creature at 52 is at 26.
  let halving =
    Change(
      property: UnitProperty2Id(7),
      mode: 1,
      multiplier: 0.5,
      flat: 0.0,
      per_level: 0.0,
    )
  let source = cast_support.source_of(cast_id: 1, effect_id: 1924)
  let half =
    changed(property: 7, base: 52.6204948425293, value: 26.31024742126465)
  let #(state, started) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: starting(source:, modifier: halving, struck_at_ms: 6000),
    )
  assert sent(started)
    == [
      #(2, PeerNews(unit_id: 7, news: PropertiesChanged([half]))),
      #(5, PeerNews(unit_id: 7, news: PropertiesChanged([half]))),
      #(2, PeerNews(unit_id: 7, news: client_connection.Health(26, False))),
      #(5, PeerNews(unit_id: 7, news: client_connection.Health(26, False))),
    ]
    as "the property first, then the health the lowered maximum leaves"
  let #(_, arrived) =
    told(
      state:,
      at_ms: 7000,
      message: Watched(by: ConnectionId(8), stay: map_support.stay(count: 8)),
    )
  let assert [#(8, PeerNews(news: CreatureAppeared(unit:, ..), ..))] =
    sent(arrived)
  assert creature_unit.health_of(unit:) == 26
    as "a viewer that arrives after sees the clamped health"
  let #(_, ended) =
    told(state:, at_ms: 8000, message: creature.ModifierEnds(source))
  assert sent(ended)
    == [
      #(
        2,
        PeerNews(
          unit_id: 7,
          news: PropertiesChanged([
            changed(
              property: 7,
              base: 52.6204948425293,
              value: 52.6204948425293,
            ),
          ]),
        ),
      ),
      #(
        5,
        PeerNews(
          unit_id: 7,
          news: PropertiesChanged([
            changed(
              property: 7,
              base: 52.6204948425293,
              value: 52.6204948425293,
            ),
          ]),
        ),
      ),
    ]
    as "the end sends the property only: health the clamp took does not come back"
}

pub fn interrupt_armor_modifier_changes_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  // Interrupt Armor Threshold 44 is 0.0 on the Beast (no armor): a modifier of 3
  // points gives it armor 3, which a Stagger stun wears down by its 1 point
  // (`crowd_control_support.stagger_stun`).
  let source = cast_support.source_of(cast_id: 1, effect_id: 1925)
  let #(state, started) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: starting(
        source:,
        modifier: unit_properties.interrupt_armor_modifier(points: 3),
        struck_at_ms: 6000,
      ),
    )
  assert property_news(started)
    == [
      #(2, [changed(property: 44, base: 0.0, value: 3.0)]),
      #(5, [changed(property: 44, base: 0.0, value: 3.0)]),
    ]
  let #(_, taken) =
    told(state:, at_ms: 7000, message: stunning_strike(cast_id: 2))
  let landed =
    list.flat_map(support.sends(taken), fn(one) {
      case one.1 {
        creature.Struck(
          answered: Answered(outcome: Landed(controls:, ..), ..),
          ..,
        ) -> controls
        creature.Struck(..)
        | creature.News(..)
        | creature.FightTold(..)
        | creature.KillCredit(..) -> []
      }
    })
  assert landed == [] as "the creature has armor now: the stun lands no state"
  assert armor_left(taken) == [#(2, 2), #(5, 2)]
    as "the stun destroyed its 1 point of the 3: 0x938 tells the 2 left"
}

/// A strike of connection 2 whose Stagger stun (`crowd_control_support.stagger_stun`)
/// destroys 1 point of Interrupt Armor.
fn stunning_strike(cast_id cast_id: Int) -> creature.Message {
  let assert creature.Strike(tell: blow) = strike_of(damage: 1, cast_id:)
  creature.Strike(
    tell: Strike(..blow, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ]),
  )
}

/// A creature of the Beast's with an Interrupt Armor maximum of `points`, started for
/// the viewers 2 and 5.
fn armored_by_two(points points: Int) -> State {
  let beast = spawn_support.battle_beast(number: 1, x: 0.0)
  let #(state, _) =
    feed(
      state: creature_at(
        spawn: Spawn(
          ..beast,
          combat: creature_life.Combat(
            ..beast.combat,
            interrupt_armor: creature_life.Armor(points:),
          ),
          bases: list.key_set(
            beast.bases,
            unit_properties.interrupt_armor_threshold,
            int.to_float(points),
          ),
        ),
        viewers: [ConnectionId(2), ConnectionId(5)],
      ),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  state
}

/// Stat 21 is clamped to 0 and property 44 (`opcode.0x938.interrupt_armor`), so a
/// creature at full armor shows its maximum, and the maximum is what a modifier
/// makes it: a raise from 0 to 3 shows 3, and the end shows 0.
pub fn raising_the_maximum_of_a_creature_at_full_armor_shows_the_new_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  let source = cast_support.source_of(cast_id: 1, effect_id: 1925)
  let #(state, started) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: starting(
        source:,
        modifier: unit_properties.interrupt_armor_modifier(points: 3),
        struck_at_ms: 6000,
      ),
    )
  assert armor_left(started) == [#(2, 3), #(5, 3)]
    as "the maximum went from 0 to 3 with the armor full: the viewers are shown 3"
  let #(_, ended) =
    told(state:, at_ms: 7000, message: creature.ModifierEnds(source:))
  assert armor_left(ended) == [#(2, 0), #(5, 0)]
    as "the maximum went back to 0: the viewers are shown 0"
}

pub fn lowering_the_maximum_of_a_creature_at_full_armor_shows_the_new_maximum_and_the_control_follows_test() -> Nil {
  use <- owned_test.run(5000)
  let source = cast_support.source_of(cast_id: 1, effect_id: 1925)
  let #(state, started) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: starting(
        source:,
        modifier: unit_properties.interrupt_armor_modifier(points: -1),
        struck_at_ms: 6000,
      ),
    )
  assert armor_left(started) == [#(2, 2), #(5, 2)]
    as "the maximum went from 3 to 2 with the armor full: the viewers are shown 2"
  let #(_, stunned) =
    told(state:, at_ms: 7000, message: stunning_strike(cast_id: 2))
  assert armor_left(stunned) == [#(2, 1), #(5, 1)]
    as "the stun destroyed its 1 point of the 2 it wears, as the viewers were shown"
}

pub fn lowering_the_maximum_below_the_armor_a_creature_wears_clamps_it_and_shows_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, worn) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: stunning_strike(cast_id: 2),
    )
  assert armor_left(worn) == [#(2, 2), #(5, 2)]
    as "the stun destroyed 1 point of the 3"
  let #(state, lowered) =
    told(
      state:,
      at_ms: 7000,
      message: starting(
        source: cast_support.source_of(cast_id: 1, effect_id: 1925),
        modifier: unit_properties.interrupt_armor_modifier(points: -2),
        struck_at_ms: 7000,
      ),
    )
  assert armor_left(lowered) == [#(2, 1), #(5, 1)]
    as "the maximum fell to 1, below the 2 worn: stat 21 is clamped to it"
  let #(_, stunned) =
    told(state:, at_ms: 8000, message: stunning_strike(cast_id: 3))
  assert armor_left(stunned) == [#(2, 0), #(5, 0)]
    as "the stun destroyed the 1 point it wears, as the viewers were shown"
}

pub fn raising_the_maximum_of_a_creature_that_wears_armor_down_leaves_the_armor_it_wears_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, worn) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: stunning_strike(cast_id: 2),
    )
  assert armor_left(worn) == [#(2, 2), #(5, 2)]
    as "the stun destroyed 1 point of the 3"
  let #(state, raised) =
    told(
      state:,
      at_ms: 7000,
      message: starting(
        source: cast_support.source_of(cast_id: 1, effect_id: 1925),
        modifier: unit_properties.interrupt_armor_modifier(points: 2),
        struck_at_ms: 7000,
      ),
    )
  assert armor_left(raised) == []
    as "the maximum rose to 5 and the armor worn stays 2: the viewers are shown no change"
  let #(_, stunned) =
    told(state:, at_ms: 8000, message: stunning_strike(cast_id: 3))
  assert armor_left(stunned) == [#(2, 1), #(5, 1)]
    as "the stun destroyed 1 of the 2 worn, as the viewers were shown"
}

pub fn armor_modifier_changes_creature_mitigation_test() -> Nil {
  use <- owned_test.run(5000)
  // The Beast has no armor (Creature2 73464's mitigation is 0), so a Physical
  // strike of 50 leaves 2 of its 52. With Armor 150 at level 1 the mitigation is
  // 0.5996959, so the strike deals 50 x 0.4003041 = 20.015, which is 20.
  let #(_, bare) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: typed_strike(damage: 50, damage_type: 1, cast_id: 1),
    )
  assert health_news(bare) == [#(2, 2, False), #(5, 2, False)]
  let armor =
    Change(
      property: UnitProperty2Id(42),
      mode: 1,
      multiplier: 1.0,
      flat: 150.0,
      per_level: 0.0,
    )
  let state =
    holding(
      state: watched_by_two(),
      source: cast_support.source_of(cast_id: 1, effect_id: 1926),
      modifier: armor,
      at_ms: 5500,
    )
  let #(_, armored) =
    told(
      state:,
      at_ms: 6000,
      message: typed_strike(damage: 50, damage_type: 1, cast_id: 2),
    )
  assert health_news(armored) == [#(2, 32, False), #(5, 32, False)]
    as "Armor 150 mitigates the strike: 50 becomes 20"
}
