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

import connection_rule_support as support
import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/strike_tell.{Answered, Key, Landed, Refused, Strike}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/step.{
  type ConnectionId, type Event, type ServiceEvent, type ServiceStep, Connection,
  ConnectionId, CreatureStart, OwnEffect, OwnEvent, Reply, Send, StartCreature,
  StartServiceTimer, Started, Stop, TimerId, Told, WatchEnded, WatchId,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature.{
  type State, Retire, Settings, Unwatched, Watched,
}
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
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

/// The stay of the player of connection `number`, as the map names it: its
/// `number`th, so each player's is its own.
fn stay_of(number: Int) -> Stay {
  map_support.stay(count: number)
}

/// A creature standing at this spawn as unit 7 of the first run, started for these
/// players.
fn creature_at(
  spawn spawn: Spawn,
  viewers viewers: List(ConnectionId),
) -> State {
  creature.new(Settings(
    creature: CreatureStart(
      map: ship,
      incarnation: 1,
      unit_id: 7,
      life: 3,
      spawn_id: SpawnId(1),
      clock_origin_ms:,
      viewers: list.map(viewers, fn(viewer) {
        let ConnectionId(number) = viewer
        #(viewer, stay_of(number))
      }),
    ),
    spawn:,
    kind: Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
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
      event: OwnEvent(Told(Watched(by: ConnectionId(5), stay: stay_of(5)))),
    )
  let assert [#(5, stay, PeerNews(unit_id:, news: CreatureAppeared(unit:, ..)))] =
    sent_for(taken)
    as "one 0x262, to the connection of the player who sees the creature"
  assert unit_id == 7 as "the news names the creature's unit"
  assert stay == stay_of(5)
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
      event: OwnEvent(Told(Watched(by: ConnectionId(5), stay: stay_of(5)))),
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

/// A strike of the caster's connection 2 with one blow of `damage` on the Beast
/// unit 7, with rolls no deflect and no crit.
fn strike_of(damage damage: Int, cast_id cast_id: Int) -> creature.Message {
  creature.Strike(
    tell: Strike(
      key: Key(cast_id:, phase: 0, unit_id: 7),
      from: step.Connection(ConnectionId(2)),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 1,
            damage_type: 3,
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
        stay: stay_of(2),
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
      "health to 2",
      "health to 5",
      "death to 2",
      "death to 5",
    ]
    as "the answer goes first, one sender in one order: the caster's connection knows the strike before it is told the health it left, so it can hold the news for the go (genesis_prime/game/strike)"
  assert support.effects_of(taken)
    |> list.any(fn(effect) {
      effect
      == OwnEffect(StartServiceTimer(timer: TimerId(1), after_ms: 60_000))
    })
    as "the kill starts the corpse timer for the kind's respawn time"
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
          stay: stay_of(2),
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
      event: OwnEvent(Told(Watched(by: ConnectionId(9), stay: stay_of(9)))),
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
      event: OwnEvent(Told(Watched(by: ConnectionId(9), stay: stay_of(9)))),
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
  [UnitProperty(property_id: 7, field_2: 0x43DD0000, value: 0x43DD0000)]
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
      event: OwnEvent(Told(Watched(by: ConnectionId(9), stay: stay_of(9)))),
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
