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
//// - A DespawnUnit effect (Spell4Effects type 97) removes the creature after its delay: the
////   client sees only the 0x355 (`opcode.0x355`) and holds no respawn time, so the creature
////   comes back at the kind's respawn time (`death.creature_respawn`, 60 000 ms here) as a
////   corpse does. The delay runs from the go. The rest of its rule is the doc comment of
////   `creature.Despawn`.
//// - A UnitStateSet effect (Spell4Effects type 15) holds a unit state on the creature from the
////   go for its delay plus duration. The client reads no such row, so what a state does is the
////   server's reading (`genesis_prime/shared/unit_state`); the rest of the rule is the doc
////   comment of `creature.UnitStates`.

import ask_support
import cast_support
import connection_rule_support as support
import creature_fight_test
import creature_news_support
import crowd_control_support
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/start_place
import genesis_prime/map/message as map_message
import genesis_prime/message/float32
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/shared/creature_combat
import genesis_prime/shared/creature_kind.{Kind}
import genesis_prime/shared/forced_move
import genesis_prime/shared/hit.{Blow, Offence, Rolls, Worked}
import genesis_prime/shared/kill_credit.{Credit}
import genesis_prime/shared/strike_tell.{Answered, Key, Landed, Refused, Strike}
import genesis_prime/shared/unit_casts.{
  type CastView, CastView, EndsAt, HeldEffect, ViewTarget,
}
import genesis_prime/shared/unit_fields
import genesis_prime/shared/unit_news.{
  type PeerNews, CreatureAppeared, CreatureMoved, PeerNews, PropertiesChanged,
  Removed,
}
import genesis_prime/shared/unit_properties.{type Modifier, type Source, Change}
import genesis_prime/shared/unit_state
import genesis_prime/step.{
  type ConnectionId, type Event, type ServiceEvent, type ServiceStep, Connection,
  ConnectionId, CreatureStart, OwnEffect, OwnEvent, Reply, Send, StartCreature,
  StartServiceTimer, Started, Stop, TimerId, Told, WatchEnded, WatchId,
}
import genesis_prime/table/id.{
  Creature2Id, Faction2Id, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/world_map/creature.{type State, Retire, Settings}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set
import gleam/string
import inbound_support
import map_spawn_support
import map_support
import owned_test
import place_support
import prerequisite_support
import spawn_support
import world_watch_support

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
        #(map_support.address(number:), generation.first())
      }),
      ring: [],
    ),
    spawn:,
    kind: Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      alternate_spell4_ids: [],
      attack_interval_ms: 1500,
      guard: option.None,
      specials: [],
    ),
    numbers: spawn_support.numbers,
  ))
}

fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(creature.Message)),
) -> #(State, ServiceStep(creature.Outgoing)) {
  let #(state, taken) = feed_raw(state:, at_ms:, event:)
  #(state, creature_news_support.at_each_player(state:, taken:))
}

/// The same, the step as the creature sends it: to its map, news once for all its viewers.
fn feed_raw(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(creature.Message)),
) -> #(State, ServiceStep(creature.Outgoing)) {
  creature.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// What the step tells the viewers (`creature_news_support.at_each_player`): the connection's
/// number and the news it carries.
fn sent(taken: ServiceStep(creature.Outgoing)) -> List(#(Int, PeerNews)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(
        to: Connection(ConnectionId(number)),
        message: creature.Broadcast(news:, ..),
      )) -> Ok(#(number, news))
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
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(5)))),
    )
  let assert [#(5, PeerNews(unit_id:, news: CreatureAppeared(unit:, ..)))] =
    sent(taken)
    as "one 0x262, to the connection of the player who sees the creature"
  assert unit_id == 7 as "the news names the creature's unit"
  assert unit.unit_id == 7 && unit.creature_id == 73_464
  assert unit.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock: 6500 ms on the monotonic clock, 1500 after the map started"
}

pub fn a_creatures_0x262_names_its_spawn_and_not_its_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  // A quest objective remembers a use by the spawn of the creature used, so the news the
  // viewer takes carries the creature's spawn (31 here), which is not its unit (7).
  let spawn = spawn_support.battle_beast(number: 31, x: 0.0)
  let #(state, _) =
    feed(
      state: creature_from(
        source: spawn_source.Stored(id: SpawnId(31)),
        spawn:,
        viewers: [],
      ),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(_, taken) =
    feed(
      state:,
      at_ms: 6500,
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(5)))),
    )
  let assert [#(5, PeerNews(unit_id: 7, news: CreatureAppeared(spawn_id:, ..)))] =
    sent(taken)
    as "one 0x262 of the creature, unit 7"
  assert spawn_id == SpawnId(31) as "it names the spawn the creature stands at"
}

pub fn a_creature_sends_its_0x355_once_to_a_player_who_stops_seeing_it_and_nothing_to_one_that_never_saw_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(5)))),
    )
  let #(state, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(creature_news_support.unseen(by: ConnectionId(5)))),
    )
  assert support.effects_of(taken) == []
    as "a player who stops seeing it is sent nothing: its 0x355 comes from the map's notice, once, whatever the creature held"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 8000,
      event: OwnEvent(Told(creature_news_support.unseen(by: ConnectionId(5)))),
    )
  assert sent(taken) == []
    as "a connection that is not a viewer is sent nothing"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 9000,
      event: OwnEvent(Told(creature_news_support.unseen(by: ConnectionId(6)))),
    )
  assert sent(taken) == [] as "a connection that never saw it is sent nothing"
  // The map's `Unseen` is the creature's end of sight: the creature drops the viewer and
  // sends nothing, since the map tells the viewer's connection its 0x355.
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(
        Told(creature.Seen(
          by: map_support.address(number: 5),
          generation: generation.first(),
        )),
      ),
    )
  assert set.contains(creature.viewers(state), map_support.address(number: 5))
    as "the map's Seen makes the connection a viewer"
  let #(state, unseen) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(
        Told(creature.Unseen(
          by: map_support.address(number: 5),
          generation: generation.first(),
        )),
      ),
    )
  assert support.effects_of(unseen) == []
    as "the creature sends no 0x355 when its viewer's sight ends"
  assert !set.contains(creature.viewers(state), map_support.address(number: 5))
    as "and no longer holds the viewer"
}

pub fn a_creature_names_a_viewer_by_its_address_and_an_unseen_of_an_earlier_address_keeps_the_later_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  // One joiner, two joins of one run: the map names the first unit by address 5 and the
  // second by address 6, each under its own sight.
  let earlier = map_support.address(number: 5)
  let later = map_support.address(number: 6)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(state, _) =
    told(
      state:,
      at_ms: 6000,
      message: creature.Seen(by: earlier, generation: generation.first()),
    )
  let #(state, snapshot) =
    told(
      state:,
      at_ms: 6100,
      message: creature.Seen(
        by: later,
        generation: generation.after(generation: generation.first()),
      ),
    )
  assert list.map(snapshots(snapshot), fn(sent) { #(sent.0, sent.1) })
    == [#(6, generation.after(generation: generation.first()))]
    as "the second Seen is answered with a snapshot for its own address"
  let #(state, _) =
    told(
      state:,
      at_ms: 6200,
      message: creature.Unseen(by: earlier, generation: generation.first()),
    )
  assert creature.viewers(state) == set.from_list([later])
    as "the Unseen of the earlier address ends that viewer only: the later address is still a viewer"
  let #(state, _) =
    told(
      state:,
      at_ms: 6300,
      message: creature.Unseen(by: earlier, generation: generation.first()),
    )
  assert creature.viewers(state) == set.from_list([later])
    as "a second Unseen of the earlier address changes nothing"
  let #(state, _) =
    told(
      state:,
      at_ms: 6400,
      message: creature.Unseen(
        by: later,
        generation: generation.after(generation: generation.first()),
      ),
    )
  assert creature.viewers(state) == set.new()
    as "the Unseen of the later address, under its own generation, ends it"
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
    feed_raw(
      state: creature_for(viewers: [ConnectionId(2), ConnectionId(5)]),
      at_ms: 6500,
      event: OwnEvent(Started),
    )
  let assert [
    #(2, PeerNews(unit_id: 7, news: CreatureAppeared(unit: first, ..))),
    #(5, PeerNews(unit_id: 7, news: CreatureAppeared(unit: second, ..))),
  ] = sent(creature_news_support.at_each_player(state:, taken:))
    as "one 0x262 for each first viewer, in the order the map gave them"
  assert first.tail.server_time_estimate_start == 1500
    && second.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock at the creature's start"
  let assert [#(2, first_generation, [first_burst]), #(5, _, [_])] =
    snapshots(taken)
    as "the creature answers each first viewer with a snapshot of its picture, in the order the map gave them"
  assert first_generation == generation.first()
    as "under the generation the map numbered the viewer with in the start"
  assert first_burst.unit_id == 7
  assert effects_named(taken) == ["other", "snapshot for 2", "snapshot for 5"]
    as "a start with an empty ring does no more: the watch on its run and a snapshot for each viewer, no fight"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(creature_news_support.unseen(by: ConnectionId(2)))),
    )
  assert support.effects_of(taken) == []
    as "a first viewer is a viewer: the map's Unseen of the generation its start named ends it, and the creature sends nothing"
  assert creature.viewers(state)
    == set.from_list([map_support.address(number: 5)])
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

/// The snapshots the step sends its map: the viewer's number, the generation and the
/// burst.
fn snapshots(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, Generation, List(PeerNews))) {
  list.filter_map(creature_news_support.to_the_map(taken), fn(sent) {
    case sent {
      creature.Snapshot(by:, generation:, burst:, ..) ->
        Ok(#(unit_address.number(address: by), generation, burst))
      creature.Broadcast(..) | creature.Relay(..) | creature.Expired(..) ->
        Error(Nil)
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
      key: Key(cast_id:, occasion: strike_tell.AtGo(phase: 0), unit_id: 7),
      from: step.Unit(map_support.address(number: 2)),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 1,
            damage_type:,
            damage: Worked(damage),
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
        hit_radius: place_support.player_hit_radius,
        rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
      ),
      controls: [],
      gates: [],
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
      creature.Relay(
        payload: map_message.Struck(answered: Answered(outcome: Landed(..), ..)),
        ..,
      ) -> "answer to " <> int.to_string(one.0)
      creature.Relay(payload: map_message.Struck(..), ..) ->
        "refusal to " <> int.to_string(one.0)
      creature.Broadcast(news: PeerNews(news: unit_news.Health(..), ..), ..) ->
        "health to " <> int.to_string(one.0)
      creature.Broadcast(news: PeerNews(news: unit_news.Died, ..), ..) ->
        "death to " <> int.to_string(one.0)
      creature.Broadcast(news: PeerNews(news: Removed, ..), ..) ->
        "removal to " <> int.to_string(one.0)
      creature.Broadcast(news: PeerNews(news: CreatureAppeared(..), ..), ..) ->
        "creation to " <> int.to_string(one.0)
      creature.Relay(payload: map_message.KillCredit(..), ..) ->
        "credit to " <> int.to_string(one.0)
      creature.Broadcast(..)
      | creature.Relay(payload: map_message.Fight(..), ..)
      | creature.Expired(..)
      | creature.Snapshot(..) -> "other"
    }
  })
}

pub fn a_creature_answers_the_caster_before_it_tells_any_viewer_its_health_and_death_test() -> Nil {
  use <- owned_test.run(5000)
  let #(struck, raw) =
    feed_raw(
      state: watched_by_two(),
      at_ms: 6000,
      event: OwnEvent(Told(strike_of(damage: 60, cast_id: 1))),
    )
  let taken = creature_news_support.at_each_player(state: struck, taken: raw)
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
  assert creature_news_support.said_to_the_map(raw)
    == ["answer to 2", "credit to 2", "0x937(0) to all", "0x88c to all"]
    as "to the map, in one step so in one stream: the answer and the credit to the caster, then the health and the death once for every viewer"
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
      creature.Relay(payload: map_message.KillCredit(..), ..) -> True
      creature.Relay(payload: map_message.Struck(..), ..)
      | creature.Relay(payload: map_message.Fight(..), ..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> False
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
        creature.Relay(
          unit_id: 7,
          life: 3,
          to: map_support.address(number: 2),
          payload: map_message.KillCredit(credit: Credit(
            unit_id: 7,
            creature_id: Creature2Id(73_464),
            faction_id: Faction2Id(1441),
            level: 1,
          )),
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
        creature.Relay(
          unit_id: 7,
          life: 3,
          to: map_support.address(number: 2),
          payload: map_message.Struck(answered: Answered(
            key: Key(
              cast_id: 2,
              occasion: strike_tell.AtGo(phase: 0),
              unit_id: 7,
            ),
            outcome: Refused(why: strike_tell.Dead),
          )),
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
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(9)))),
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
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(9)))),
    )
  let assert [#(9, PeerNews(news: CreatureAppeared(unit:, life: 3, ..), ..))] =
    sent(taken)
  assert creature_unit.health_of(unit:) == 0
    as "opcode.0x262.creature: stat 0 of 0 makes the client create the creature dead"
  let #(_, seen) =
    told_raw(
      state:,
      at_ms: 7000,
      message: seen_by_nine(generation: generation.first()),
    )
  let assert [
    #(9, _, [PeerNews(news: CreatureAppeared(unit: seen_unit, ..), ..)]),
  ] = snapshots(seen)
    as "the map's Seen is answered with the corpse as a snapshot of one 0x262"
  assert creature_unit.health_of(unit: seen_unit) == 0
}

/// What a step does, one entry for each effect in order: what the creature tells its map
/// by name (`creature_news_support.said_to_the_map`), `stop`, and `other` for any other.
fn effects_named(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: step.Map(..), ..)) ->
        string.join(
          creature_news_support.said_to_the_map(step.Effects([effect])),
          ", ",
        )
      Stop -> "stop"
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..) -> "other"
    }
  })
}

/// The Beast, unit 7 of life 3, struck dead at 6000 with the viewers 2 and 5.
fn dead_by_two() -> State {
  told(
    state: watched_by_two(),
    at_ms: 6000,
    message: strike_of(damage: 60, cast_id: 1),
  ).0
}

/// A run-only Beast, unit 7 of life 3, started for the viewers 2 and 5.
fn run_only_by_two() -> State {
  let beast = spawn_support.battle_beast(number: -1, x: 0.0)
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
  ).0
}

pub fn the_corpse_timer_removes_a_creature_tells_its_map_it_expired_and_stops_it_test() -> Nil {
  use <- owned_test.run(5000)
  // `death.creature_respawn`: the client sees the 0x355 and then the 0x262 of the same unit; the
  // 0x262 comes from the map's next life (Design run A, 4.1), so the creature's last
  // sends are the removal, once for all its viewers, and its expiry, and then it stops.
  let unwatched_dead = fn() {
    let #(state, _) =
      feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
    told(state:, at_ms: 6000, message: strike_of(damage: 60, cast_id: 1)).0
  }
  let to_retire = told(state: dead_by_two(), at_ms: 80_000, message: Retire).0
  let run_only_dead =
    told(
      state: run_only_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 60, cast_id: 1),
    ).0
  list.each(
    [
      #(
        "a dead creature with two viewers: the removal, once for both, then the expiry",
        dead_by_two(),
        ["0x355 to all", "expired 7 of life 3", "stop"],
      ),
      #(
        "a despawned creature: its 0x355 went at the despawn, so only the expiry",
        despawned_by_two(),
        ["expired 7 of life 3", "stop"],
      ),
      #(
        "a dead creature with no viewer: no removal to broadcast",
        unwatched_dead(),
        ["expired 7 of life 3", "stop"],
      ),
      #(
        "a dead creature told to retire: it stops and tells the map no expiry, which would start a life",
        to_retire,
        ["stop"],
      ),
      #(
        "a run-only creature: no expiry, its map ends the spawn when it stops",
        run_only_dead,
        ["0x355 to all", "stop"],
      ),
    ],
    fn(row) {
      let #(_, taken) =
        feed_raw(
          state: row.1,
          at_ms: 90_000,
          event: OwnEvent(step.ServiceTimerFired(corpse_timer)),
        )
      assert effects_named(taken) == row.2 as row.0
    },
  )
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
      event: OwnEvent(Told(creature_news_support.seen(by: ConnectionId(9)))),
    )
  let assert [#(9, PeerNews(news: CreatureAppeared(unit:, ..), ..)), ..] =
    sent(taken)
  assert creature_unit.health_of(unit:) == 428
    as "the recorded 442 less the strike's 14: stat 0 is the current health"
  assert unit.tail.properties == base_health_442()
    as "opcode.0x262.creature: property 7 is the recorded maximum, so the bar reads 428 of 442"
}

pub fn a_recorded_creature_that_starts_is_shown_at_its_recorded_health_with_its_recorded_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  // The next life of a killed creature is a creature its map starts, and its start is its
  // first picture (`death.creature_respawn`: full health, the server's value).
  let #(_, taken) =
    feed_raw(
      state: creature_at(spawn: recorded_beast(), viewers: [ConnectionId(2)]),
      at_ms: 66_000,
      event: OwnEvent(Started),
    )
  let assert [#(2, _, [PeerNews(news: CreatureAppeared(unit:, ..), ..), ..])] =
    snapshots(taken)
    as "death.creature_respawn: a full 0x262 to the viewer"
  assert creature_unit.health_of(unit:) == 442
    as "it starts at the recorded value, not the client's formula"
  assert unit.tail.properties == base_health_442()
    as "and sends it as Base Health"
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

/// The unit of the caster whose spells put modifiers on the creature.
fn caster() -> UnitAddress {
  map_support.address(number: 9)
}

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

/// The same, the step as the creature sends it: to its map.
fn told_raw(
  state state: State,
  at_ms at_ms: Int,
  message message: creature.Message,
) -> #(State, ServiceStep(creature.Outgoing)) {
  feed_raw(state:, at_ms:, event: OwnEvent(Told(message)))
}

fn starting(
  source source: Source,
  modifier modifier: Modifier,
) -> creature.Message {
  creature.ModifierStarts(by: caster(), source:, modifier:)
}

/// The creature after the caster's start of this modifier, struck as it arrived.
fn holding(
  state state: State,
  source source: Source,
  modifier modifier: Modifier,
  at_ms at_ms: Int,
) -> State {
  told(state:, at_ms:, message: starting(source:, modifier:)).0
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
      PeerNews(news: unit_news.Health(health:, dead:), ..) ->
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
      PeerNews(news: unit_news.InterruptArmor(armor:), ..) ->
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
      message: starting(source: sprint_source(), modifier: sprint()),
    )
  assert sent(taken)
    == [
      #(2, PeerNews(unit_id: 7, news: PropertiesChanged([speed_up()]))),
      #(5, PeerNews(unit_id: 7, news: PropertiesChanged([speed_up()]))),
    ]
    as "0x93a of the unit, to each viewer: Move Speed Multiplier 1.0 x 1.0 + 0.5"
  assert support.watches(taken) == []
    as "a start opens no watch: the creature watches its map's run and no connection"
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
  assert unwatches(taken) == []
    as "the caster's last source ends with no Unwatch: no connection was watched"
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
      message: creature_news_support.seen(by: ConnectionId(8)),
    )
  let assert [#(8, PeerNews(news: CreatureAppeared(unit:, ..), ..))] =
    sent(taken)
    as "one 0x262, to the viewer that arrived"
  assert unit.tail.properties == [speed_up()]
    as "its property list carries the current value of the property a modifier changes"
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
  // A caster's end names only the source: the caster keeps one node for each unit, so an
  // end sent for an earlier go reaches the creature after a later go started the same
  // source, and is that start's own (`cast/state`, `cast/control`). The creature checks
  // no go of an end.
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
      message: starting(source: sprint_source(), modifier: sprint()),
    )
  assert support.effects_of(again) == []
    as "the same source is held once: nothing changes and nothing is sent"
  let #(_, ended) =
    told(state:, at_ms: 7000, message: creature.ModifierEnds(sprint_source()))
  assert property_news(ended) == [#(2, [speed_back()]), #(5, [speed_back()])]
    as "one end restores the value, whichever go started the source"
}

pub fn a_modifier_a_throw_a_despawn_and_unit_states_are_dropped_by_a_dead_or_despawned_creature_and_taken_by_a_living_one_test() -> Nil {
  use <- owned_test.run(5000)
  // A tell is addressed to the creature's life by the registry's address, so the creature
  // reads no time: what it refuses is a tell that reaches a body (`creature_life.is_dead`).
  // `CastViewSet` is kept by a corpse, which keeps its nodes (`cast.target_node_end`).
  let at_7000 = 7000
  let tells = [
    #(
      "a modifier start",
      starting(source: sprint_source(), modifier: sprint()),
      fn(taken) {
        property_news(taken) == [#(2, [speed_up()]), #(5, [speed_up()])]
      },
    ),
    #("a throw", a_throw(), fn(taken) { flown_to(taken) == [2, 5] }),
    #("a despawn", despawn_at(delay_ms: 0, went_at_ms: at_7000), fn(taken) {
      kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    }),
    #(
      "unit states",
      unit_states_at(rows: [state_6_for_8500()], went_at_ms: at_7000),
      fn(taken) {
        unit_state_news(taken)
        == [#(2, held(state: 6, number: 1)), #(5, held(state: 6, number: 1))]
      },
    ),
  ]
  let bodies = [
    #("a dead creature", dead_by_two()),
    #("a despawned creature", despawned_by_two()),
  ]
  list.each(tells, fn(tell) {
    let #(name, message, taken_as_expected) = tell
    let #(_, taken) = told(state: watched_by_two(), at_ms: at_7000, message:)
    assert taken_as_expected(taken)
      as { name <> " to a living creature is taken" }
    list.each(bodies, fn(body) {
      let #(state, dropped) = told(state: body.1, at_ms: at_7000, message:)
      assert support.effects_of(dropped) == []
        as { name <> " to " <> body.0 <> " sends nothing" }
      assert state == body.1
        as { name <> " to " <> body.0 <> " changes nothing" }
    })
  })
  list.each(
    [
      #("a living", watched_by_two(), True),
      #("a dead", dead_by_two(), True),
      #("a despawned", despawned_by_two(), False),
    ],
    fn(body) {
      let #(state, set) =
        told(
          state: body.1,
          at_ms: at_7000,
          message: creature.CastViewSet(
            by: map_support.address(number: 9),
            view: view_a(),
          ),
        )
      assert watch_changes(set) == []
        as {
          "a cast view reaching "
          <> body.0
          <> " creature is kept and its caster is not watched"
        }
      // A despawned creature shows no 0x262, so no arrival lists the view it holds.
      assert !body.2 || arrival_holds(state:) == [#(view_a().cast_id, 1)]
        as {
          body.0
          <> " creature lists the view it was told to a viewer that arrives"
        }
    },
  )
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
  let assert process.Abnormal(crash) =
    ask_support.ended_running(fn() {
      let _stepped = feed(state:, at_ms: 7000, event: WatchEnded(WatchId(2)))
      Nil
    })
    as "a watch that is not the run's crashes the creature"
  assert decode.run(crash, ask_support.crash_message())
    == Ok(
      "a creature watches only its map's run: a watch that ended is not the run's",
    )
    as "with the message that says the creature opens no other watch"
}

/// A strike of the caster's connection `caster` whose Stagger stun lands a state on the
/// Beast.
fn stunning_strike_from_the_caster(cast_id cast_id: Int) -> creature.Message {
  let assert creature.Strike(tell:) = stunning_strike(cast_id:)
  creature.Strike(tell: Strike(..tell, from: step.Unit(caster())))
}

pub fn a_creature_drops_the_sources_and_views_of_a_gone_caster_keeps_its_controls_sends_the_property_news_once_and_watches_only_its_run_test() -> Nil {
  use <- owned_test.run(5000)
  let other = map_support.address(number: 10)
  let stranger = map_support.address(number: 77)
  // The caster holds two sources, a view and a control; a second caster holds a view.
  let holdings = [
    starting(source: sprint_source(), modifier: sprint()),
    starting(source: thorns_source(), modifier: thorns()),
    creature.CastViewSet(by: caster(), view: view_a()),
    stunning_strike_from_the_caster(cast_id: 7),
    creature.CastViewSet(by: other, view: view_b()),
    creature.ModifierStarts(
      by: other,
      source: doubling_source(),
      modifier: doubling(),
    ),
  ]
  let #(state, watched) =
    list.fold(holdings, #(watched_by_two(), []), fn(held, message) {
      let #(state, steps) = held
      let #(state, taken) =
        told(state:, at_ms: 6000 + 100 * list.length(steps), message:)
      #(state, [taken, ..steps])
    })
  assert list.flat_map(watched, watch_changes) == []
    as "no holding opens a watch: the creature watches its map's run and no connection"
  assert ended_states(
      told(
        state:,
        at_ms: 6400,
        message: creature.ControlsEnd(by: other, cast_id: 7),
      ).1,
    )
    == []
    as "the stun is the caster's: another connection's end for the same cast id ends nothing"
  let #(gone_state, gone) =
    told(state:, at_ms: 7000, message: creature.CasterGone(by: caster()))
  assert property_news(gone)
    == [
      #(2, [speed_back()]),
      #(5, [speed_back()]),
      #(2, [changed(property: 150, base: 0.0, value: 0.0)]),
      #(5, [changed(property: 150, base: 0.0, value: 0.0)]),
    ]
    as "each source of the caster ends as a ModifierEnds ends it, in the order they started, each with its news once"
  assert ended_states(gone) == []
    as "the stun the caster's cast landed stands: only sources and views are dropped, and the stun ends by its own timer"
  assert watch_changes(gone) == [] as "and no Unwatch follows"
  let assert [stun_timer] =
    list.filter(list.flat_map(watched, timers_started), fn(started) {
      result.is_ok(creature.control_of(timer: started.0))
    })
    as "the strike held one state, with its timer"
  assert ended_states(
      fired(state: gone_state, at_ms: 8800, timer: stun_timer.0).1,
    )
    == [2, 5]
    as "the stun's own timer ends it, with its 0x880 for each viewer"
  assert arrival_holds(state: gone_state) == [#(view_b().cast_id, 1)]
    as "the caster's view goes and the other caster's stays"
  let #(again_state, again) =
    told(
      state: gone_state,
      at_ms: 7100,
      message: creature.CasterGone(by: caster()),
    )
  assert support.effects_of(again) == [] && again_state == gone_state
    as "a second CasterGone for the same connection changes nothing"
  let #(stranger_state, stranger_gone) =
    told(
      state: gone_state,
      at_ms: 7200,
      message: creature.CasterGone(by: stranger),
    )
  assert support.effects_of(stranger_gone) == [] && stranger_state == gone_state
    as "a connection that holds nothing changes nothing"
  let #(_, late) =
    told(
      state: gone_state,
      at_ms: 7300,
      message: creature.ModifierEnds(sprint_source()),
    )
  assert support.effects_of(late) == []
    as "a later end for a source the departure removed changes nothing"
  let #(last_state, last) =
    told(
      state: gone_state,
      at_ms: 7400,
      message: creature.CasterGone(by: other),
    )
  assert arrival_holds(state: last_state) == []
    as "the other caster's departure drops its view"
  assert property_news(last)
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
    as "and its source, held all along, ends with its news once"
  // A creature that lies dead and was told to retire still holds a view until its corpse
  // expires; the map's word reaches it in that state.
  let #(dead, _) =
    after(inputs: [
      view_set(by: 9, view: view_a(), at_ms: 6000),
      killed_at(at_ms: 7000),
      #(7500, OwnEvent(Told(Retire))),
    ])
  assert arrival_holds(state: dead) == [#(view_a().cast_id, 1)]
    as "the dead creature told to retire holds the caster's view, and its corpse's 0x262 lists it"
  let #(dead_gone, _) =
    told(
      state: dead,
      at_ms: 8000,
      message: creature.CasterGone(by: map_support.address(number: 9)),
    )
  assert arrival_holds(state: dead_gone) == []
    as "a dead creature told to retire drops a gone caster's view before its corpse expires"
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
      message: starting(source: thorns_source(), modifier: thorns()),
    )
  assert support.effects_of(dropped) == []
    as "a start that reaches the creature while it is dead is dropped"
  let #(_, ended) =
    told(state:, at_ms: 9000, message: creature.ModifierEnds(sprint_source()))
  assert property_news(ended) == [#(2, [speed_back()]), #(5, [speed_back()])]
    as "the source it held before it died ends as always"
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
      message: starting(source:, modifier: halving),
    )
  assert sent(started)
    == [
      #(2, PeerNews(unit_id: 7, news: PropertiesChanged([half]))),
      #(5, PeerNews(unit_id: 7, news: PropertiesChanged([half]))),
      #(2, PeerNews(unit_id: 7, news: unit_news.Health(26, False))),
      #(5, PeerNews(unit_id: 7, news: unit_news.Health(26, False))),
    ]
    as "the property first, then the health the lowered maximum leaves"
  let #(_, arrived) =
    told(
      state:,
      at_ms: 7000,
      message: creature_news_support.seen(by: ConnectionId(8)),
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
        creature.Relay(
          payload: map_message.Struck(answered: Answered(
            outcome: Landed(controls:, ..),
            ..,
          )),
          ..,
        ) -> controls
        creature.Relay(payload: map_message.Struck(..), ..)
        | creature.Relay(payload: map_message.Fight(..), ..)
        | creature.Relay(payload: map_message.KillCredit(..), ..)
        | creature.Snapshot(..)
        | creature.Expired(..)
        | creature.Broadcast(..) -> []
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
          combat: creature_combat.Combat(
            ..beast.combat,
            interrupt_armor: creature_combat.Armor(points:),
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

// ---- a thrown creature (issue 788) ----
//
// The throw of Spell4Effects 73826: kind 4 (away from a unit), 10 m, a flight of 375 ms,
// flags 0 (the row's columns), the reference unit 5 behind the creature along x.

/// A throw of that row.
fn a_throw() -> creature.Message {
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
    reference: forced_move.Reference(
      place: map_spawn_support.at(-5.0),
      radius: 0.0,
    ),
  ))
}

/// The numbers of the viewers the step sends a 0x638 flight, in order.
fn flown_to(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(outgoing(taken), fn(one) {
    case one.1 {
      creature.Broadcast(news: PeerNews(news: CreatureMoved(..), ..), ..) ->
        Ok(one.0)
      creature.Broadcast(..)
      | creature.Relay(..)
      | creature.Expired(..)
      | creature.Snapshot(..) -> Error(Nil)
    }
  })
}

/// The timers the step starts, as the timer and its time, but for the chase's arrival
/// timer, which the fight test file covers.
fn timers_started(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(step.TimerId, Int)) {
  list.filter(support.service_timers_started(taken), fn(started) {
    started.0 != creature.chase_arrival_timer
  })
}

fn fired(
  state state: State,
  at_ms at_ms: Int,
  timer timer: step.TimerId,
) -> #(State, ServiceStep(creature.Outgoing)) {
  feed(state:, at_ms:, event: OwnEvent(step.ServiceTimerFired(timer)))
}

pub fn a_thrown_creature_sends_one_0x638_to_each_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(state: watched_by_two(), at_ms: 6000, message: a_throw())
  assert flown_to(taken) == [2, 5]
    as "opcode.0x638: one flight to each viewer, in the order they began to watch"
  assert list.length(outgoing(taken)) == 2
    as "and no other send: the flight carries the whole news"
}

pub fn a_throw_at_a_dead_or_returning_creature_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(dead, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 60, cast_id: 1),
    )
  let #(_, to_dead) = told(state: dead, at_ms: 6500, message: a_throw())
  assert support.effects_of(to_dead) == []
    as "a creature that lies dead is not thrown"
  // Player 2 draws the creature into a fight and runs out of its ring: after the leash
  // it walks home (1500 ms ticks, the fourth, at 12000, leashes it).
  let #(state, aggro) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: creature.Approached(member: step.RingMember(
        by: map_support.address(number: 2),
        unit_id: 20,
        place: map_spawn_support.at(5.0),
        seq: 1,
        hit_radius: place_support.player_hit_radius,
      )),
    )
  let #(state, _) =
    told(
      state:,
      at_ms: 6000,
      message: creature.TargetMoved(
        by: map_support.address(number: 2),
        place: map_spawn_support.at(100.0),
        seq: 2,
        hit_radius: place_support.player_hit_radius,
      ),
    )
  let #(state, _) =
    told(
      state:,
      at_ms: 6000,
      message: creature.Withdrew(by: map_support.address(number: 2)),
    )
  let assert [#(t1, 1500)] = timers_started(aggro)
    as "the aggro starts the attack tick, 1500 ms on"
  let #(state, tick1) = fired(state:, at_ms: 7500, timer: t1)
  let assert [#(t2, 1500), ..] = timers_started(tick1)
  let #(state, tick2) = fired(state:, at_ms: 9000, timer: t2)
  let assert [#(t3, 1500), ..] = timers_started(tick2)
  let #(state, tick3) = fired(state:, at_ms: 10_500, timer: t3)
  let assert [#(t4, 1500), ..] = timers_started(tick3)
  let #(state, leashed) = fired(state:, at_ms: 12_000, timer: t4)
  assert list.any(timers_started(leashed), fn(started) { started.1 == 5500 })
    as "the leash starts the walk home, 55 m at 10 m a second: 5500 ms"
  let #(_, to_returning) = told(state:, at_ms: 12_100, message: a_throw())
  assert support.effects_of(to_returning) == []
    as "a creature that walks home is not thrown"
}

pub fn a_creature_killed_after_a_throw_expires_like_any_other_and_its_next_life_starts_at_home_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, thrown) =
    told(state: watched_by_two(), at_ms: 6000, message: a_throw())
  let assert [#(_, 375)] = timers_started(thrown)
    as "the throw starts one timer, for the landing 375 ms on"
  let #(state, _) =
    told(state:, at_ms: 6100, message: strike_of(damage: 60, cast_id: 1))
  let #(_, expired) =
    feed_raw(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(TimerId(1))),
    )
  assert effects_named(expired)
    == ["0x355 to all", "expired 7 of life 3", "stop"]
    as "death.creature_respawn: the removal and the expiry, as for a creature never thrown; the thrown one stops, so the landing of its life has no one to land"
  let #(_, next) =
    feed_raw(
      state: creature_for(viewers: [ConnectionId(2)]),
      at_ms: 66_000,
      event: OwnEvent(Started),
    )
  let assert [#(2, _, [PeerNews(news: CreatureAppeared(place:, ..), ..), ..])] =
    snapshots(next)
    as "the next life is started by the map at the spawn"
  assert start_place.x(place) == 0.0
    as "the spawn's x, where the creature stood before the throw moved it to x = 10"
}

pub fn the_flight_end_timer_has_its_own_id_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, thrown) =
    told(state: watched_by_two(), at_ms: 6000, message: a_throw())
  let assert [#(landing, 375)] = timers_started(thrown)
    as "the throw starts one timer, 375 ms on"
  let TimerId(number) = landing
  assert number % 7 == 6 && number > 6
    as "the 7-slot numbering of a generation g: attack tick 7g, home 7g + 1, deadline 7g + 2, cast 7g + 3, control 7g + 4, guard 7g + 5, flight 7g + 6"
  assert creature.control_of(timer: landing) == Error(Nil)
    as "it is no control's"
  let #(_, landed) = fired(state:, at_ms: 6375, timer: landing)
  assert timers_started(landed) == []
    as "firing it lands the creature, which, with no player near, starts nothing"
}

// ---- a strike's gates (issue 817) ----
//
// The expected values are the Creature2 row 73464's (`table_rows -- Creature2 73464`:
// level 1, faction 1441, creature2DifficultyId 1) and the client's comparison codes
// (1 equal, 2 not equal, 3 greater, 4 at least, 5 less, 6 at most), not what the
// support feeds in.

/// The gate of the row `effect_id` with one condition, as (type, comparison, objectId,
/// value).
fn gate(
  effect_id effect_id: Int,
  condition condition: #(Int, Int, Int, Int),
) -> strike_tell.Gate {
  strike_tell.Gate(
    effect_id:,
    prerequisite: prerequisite_support.single(id: effect_id, condition:),
  )
}

/// The same strike with these gates.
fn gated(
  strike strike: creature.Message,
  gates gates: List(strike_tell.Gate),
) -> creature.Message {
  let assert creature.Strike(tell:) = strike
  creature.Strike(tell: Strike(..tell, gates:))
}

/// The answer the step sends the caster's connection 2.
fn answer_of(taken: ServiceStep(creature.Outgoing)) -> strike_tell.Outcome {
  let answers =
    list.filter_map(support.sends(taken), fn(one) {
      case one {
        #(
          2,
          creature.Relay(
            payload: map_message.Struck(answered: Answered(outcome:, ..)),
            ..,
          ),
        ) -> Ok(outcome)
        _ -> Error(Nil)
      }
    })
  let assert [outcome] = answers as "the strike is answered once, to its caster"
  outcome
}

/// The effect ids a landed, immune or deflected answer names as passed.
fn passed(outcome: strike_tell.Outcome) -> List(Int) {
  case outcome {
    Landed(gates_passed:, ..)
    | strike_tell.Immune(gates_passed:, ..)
    | strike_tell.Deflected(gates_passed:) -> gates_passed
    Refused(..) -> []
  }
}

pub fn strike_row_failing_its_gate_lands_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // The Beast is level 1: a gate of level 2 fails.
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 10, cast_id: 1), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 2)),
      ]),
    )
  assert answer_of(taken)
    == Landed(
      descriptions: [],
      controls: [],
      armor_removed: 0,
      gates_passed: [],
    )
    as "the blow of the failed row is dealt nothing and no gate passed"
  assert list.all(health_news(taken), fn(news) { news.1 == 52 })
    as "the Beast keeps its 52 health"
  // A failed row's state is not taken either, and wears no armor down.
  let #(_, stunned) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: gated(strike: stunning_strike(cast_id: 2), gates: [
        gate(effect_id: 83_827, condition: #(1, 1, 0, 2)),
      ]),
    )
  let assert Landed(controls:, gates_passed:, ..) = answer_of(stunned)
  assert controls == [] as "the stun of the failed row is not taken"
  assert gates_passed == [] as "no gate passed"
  assert armor_left(stunned) == []
    as "and it destroyed no point of the 3 Interrupt Armor"
}

pub fn strike_row_passing_its_gate_lands_as_before_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, ungated) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 10, cast_id: 1),
    )
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 10, cast_id: 1), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  let assert Landed(descriptions:, ..) = answer_of(ungated)
  assert list.length(descriptions) == 1 as "the strike has one blow"
  assert answer_of(taken)
    == Landed(descriptions:, controls: [], armor_removed: 0, gates_passed: [1])
    as "level 1 is the Beast's: the gate passes and the blow lands as without it"
  assert health_news(taken) == health_news(ungated)
    as "the health news is the ungated strike's"
}

pub fn gate_reads_the_creature_when_the_strike_arrives_test() -> Nil {
  use <- owned_test.run(5000)
  // At most 39 health: the Beast has 52 now and 39 after a strike of 13.
  let at_most_39 = [gate(effect_id: 1, condition: #(73, 6, 1, 39))]
  let #(state, first) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(
        strike: strike_of(damage: 10, cast_id: 1),
        gates: at_most_39,
      ),
    )
  assert passed(answer_of(first)) == []
    as "52 health is above 39: the first strike's gate fails"
  let #(state, _) =
    told(state:, at_ms: 6100, message: strike_of(damage: 13, cast_id: 2))
  let #(_, third) =
    told(
      state:,
      at_ms: 6200,
      message: gated(
        strike: strike_of(damage: 10, cast_id: 3),
        gates: at_most_39,
      ),
    )
  assert passed(answer_of(third)) == [1]
    as "39 health is at most 39 when this strike arrives: its gate passes"
  assert health_news(third) == [#(2, 29, False), #(5, 29, False)]
    as "and its blow of 10 lands on the 39"
  // 75 percent of 52 is 39: the same health read as a percentage.
  let #(_, percent) =
    told(
      state:,
      at_ms: 6200,
      message: gated(strike: strike_of(damage: 10, cast_id: 4), gates: [
        gate(effect_id: 1, condition: #(71, 1, 1, 75)),
      ]),
    )
  assert passed(answer_of(percent)) == [1]
    as "39 of 52 is 75.0 percent: equal to 75"
}

pub fn strike_gates_read_the_creature_row_and_the_spawn_it_names_test() -> Nil {
  use <- owned_test.run(5000)
  // One strike with a gate for each type, all out of combat. The effect ids name the gate
  // only: no blow or state carries them.
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 1, cast_id: 1), gates: [
        gate(effect_id: 11, condition: #(1, 1, 0, 1)),
        gate(effect_id: 12, condition: #(4, 1, 0, 1441)),
        gate(effect_id: 13, condition: #(250, 1, 0, 1441)),
        gate(effect_id: 14, condition: #(38, 1, 0, 73_464)),
        gate(effect_id: 15, condition: #(3, 2, 0, 5)),
        gate(effect_id: 16, condition: #(3, 1, 0, 5)),
        gate(effect_id: 17, condition: #(28, 1, 0, 0)),
        gate(effect_id: 18, condition: #(28, 2, 0, 0)),
        gate(effect_id: 19, condition: #(73, 1, 1, 52)),
        gate(effect_id: 20, condition: #(73, 1, 3, 0)),
        gate(effect_id: 21, condition: #(73, 1, 2, 100)),
        gate(effect_id: 22, condition: #(39, 1, 0, 0)),
      ]),
    )
  assert passed(answer_of(taken)) == [11, 12, 13, 14, 15, 18, 19, 20, 21]
    as "level 1, faction 1441, base faction 1441, Creature2 73464, class 23 (no Class row), not in combat, 52 health, no shield and full breath pass; class equal to 5, in combat and being a player do not"
}

pub fn gate_reads_the_difficulty_of_the_creature_row_test() -> Nil {
  use <- owned_test.run(5000)
  // Creature2 73464 has creature2DifficultyId 1 (`table_rows -- Creature2 73464`), and the
  // spawn is the Beast as the load builds it.
  let #(state, _) =
    feed(
      state: creature_at(spawn: spawn_support.loaded_beast(), viewers: [
        ConnectionId(2),
        ConnectionId(5),
      ]),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(_, taken) =
    told(
      state:,
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 1, cast_id: 1), gates: [
        gate(effect_id: 11, condition: #(179, 1, 1, 0)),
        gate(effect_id: 12, condition: #(179, 1, 2, 0)),
      ]),
    )
  assert passed(answer_of(taken)) == [11]
    as "difficulty 1 equals the objectId 1, not 2"
}

pub fn strike_with_every_gate_failed_does_not_pull_the_creature_test() -> Nil {
  use <- owned_test.run(5000)
  // The server's choice: no client or retail source says whether a cast whose rows all fail
  // their target gate pulls the creature. Nothing reached it, so it is not pulled.
  let in_combat = [gate(effect_id: 1, condition: #(28, 1, 0, 0))]
  let #(state, first) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 1, cast_id: 1), gates: in_combat),
    )
  assert answer_of(first)
    == Landed(
      descriptions: [],
      controls: [],
      armor_removed: 0,
      gates_passed: [],
    )
    as "the creature is at home, so the one gated row fails and the answer lands nothing"
  assert health_news(first) == []
    as "nothing reached the creature, so no hit is rolled and no health is sent"
  let #(state, second) =
    told(
      state:,
      at_ms: 6100,
      message: gated(strike: strike_of(damage: 1, cast_id: 2), gates: in_combat),
    )
  assert passed(answer_of(second)) == []
    as "the first strike put the creature in no fight: the second still finds it at home"
  let #(state, ungated) =
    told(state:, at_ms: 6200, message: strike_of(damage: 1, cast_id: 3))
  assert health_news(ungated) != []
    as "a strike with a row no gate holds back still lands and is shown"
  let #(_, after) =
    told(
      state:,
      at_ms: 6300,
      message: gated(strike: strike_of(damage: 1, cast_id: 4), gates: in_combat),
    )
  assert passed(answer_of(after)) == [1]
    as "that landing put the creature in a fight: the gate now passes"
}

pub fn gate_reads_the_interrupt_armor_the_creature_wears_test() -> Nil {
  use <- owned_test.run(5000)
  let armor_is = fn(points) {
    [gate(effect_id: 1, condition: #(73, 1, 20, points))]
  }
  let #(state, first) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: gated(
        strike: strike_of(damage: 1, cast_id: 1),
        gates: armor_is(3),
      ),
    )
  assert passed(answer_of(first)) == [1] as "3 points of armor worn"
  let #(state, _) =
    told(state:, at_ms: 6100, message: stunning_strike(cast_id: 2))
  let #(_, after) =
    told(
      state:,
      at_ms: 6200,
      message: gated(
        strike: strike_of(damage: 1, cast_id: 3),
        gates: armor_is(2),
      ),
    )
  assert passed(answer_of(after)) == [1]
    as "the stun destroyed 1 point: 2 are worn when this strike arrives"
  let #(_, bare) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(
        strike: strike_of(damage: 1, cast_id: 4),
        gates: armor_is(0),
      ),
    )
  assert passed(answer_of(bare)) == [1] as "no armor: Vital 20 reads 0"
}

pub fn gate_of_a_type_the_creature_does_not_read_passes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // Type 64 reads a player's resource slot, which a creature has none of: the check says it
  // cannot read it (`NotRead`), and an unread gate does not pass.
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 10, cast_id: 1), gates: [
        gate(effect_id: 1, condition: #(64, 1, 1, 0)),
      ]),
    )
  assert answer_of(taken)
    == Landed(
      descriptions: [],
      controls: [],
      armor_removed: 0,
      gates_passed: [],
    )
    as "the row of an unread gate lands nothing"
}

pub fn two_strikes_in_turn_each_get_their_own_answer_and_gates_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 10, cast_id: 1), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 2)),
      ]),
    )
  let #(_, second) =
    told(
      state:,
      at_ms: 6000,
      message: gated(strike: strike_of(damage: 10, cast_id: 2), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  assert passed(answer_of(first)) == []
  assert passed(answer_of(second)) == [1]
    as "the second strike is checked on its own gate, whatever the first's"
}

pub fn deflected_strike_still_answers_the_gates_it_passed_test() -> Nil {
  use <- owned_test.run(5000)
  // A deflect roll of 0.01 is below the Beast's deflect chance of 0.016
  // (`Creature2.73464.crit_deflect_glance`).
  let assert creature.Strike(tell:) = strike_of(damage: 10, cast_id: 1)
  let assert strike_tell.PlayerStriker(..) as striker = tell.striker
  let deflected =
    creature.Strike(
      tell: Strike(
        ..tell,
        striker: strike_tell.PlayerStriker(
          ..striker,
          rolls: Rolls(crit: 0.5, deflect: 0.01, glance: 0.5),
        ),
        gates: [
          gate(effect_id: 11, condition: #(1, 1, 0, 1)),
          gate(effect_id: 12, condition: #(1, 1, 0, 2)),
        ],
      ),
    )
  let #(_, taken) =
    told(state: watched_by_two(), at_ms: 6000, message: deflected)
  assert answer_of(taken) == strike_tell.Deflected(gates_passed: [11])
    as "the deflect checked the gates: the one that holds is answered, the other is not"
}

pub fn dead_creature_refuses_a_gated_strike_test() -> Nil {
  use <- owned_test.run(5000)
  let #(dead, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 60, cast_id: 1),
    )
  let #(_, taken) =
    told(
      state: dead,
      at_ms: 6100,
      message: gated(strike: strike_of(damage: 10, cast_id: 2), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  assert answer_of(taken) == Refused(why: strike_tell.Dead)
    as "a corpse reads no gate: it refuses, though the gate would hold"
}

// ---- a DespawnUnit effect (Spell4Effects type 97) ----
//
// The Beast is watched by connections 2 and 5 from 5000; a go at 6000 told it `Despawn`.
// The respawn time is the kind's 60 000 ms, the corpse timer is `TimerId(1)` and the
// despawn timer `TimerId(3)`.

/// A despawn whose go was at `went_at_ms`, struck 100 ms before as its round opened.
fn despawn_at(
  delay_ms delay_ms: Int,
  went_at_ms went_at_ms: Int,
) -> creature.Message {
  creature.Despawn(delay_ms:, went_at_ms:)
}

/// The timers the step cancels.
fn timers_cancelled(
  taken: ServiceStep(creature.Outgoing),
) -> List(step.TimerId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.CancelServiceTimer(timer:)) -> Ok(timer)
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | Stop -> Error(Nil)
    }
  })
}

/// The watched Beast after a despawn of delay 0 at 6000.
fn despawned_by_two() -> State {
  told(
    state: watched_by_two(),
    at_ms: 6000,
    message: despawn_at(delay_ms: 0, went_at_ms: 6000),
  ).0
}

/// The Beast with a despawn of delay 4000 pending since the go at 6000, due at 10 000, and
/// the step that took it.
fn despawning_at_10_000() -> #(State, ServiceStep(creature.Outgoing)) {
  told(
    state: watched_by_two(),
    at_ms: 6000,
    message: despawn_at(delay_ms: 4000, went_at_ms: 6000),
  )
}

const despawn_timer = TimerId(3)

const corpse_timer = TimerId(1)

pub fn a_despawn_of_delay_0_removes_the_creature_for_each_viewer_and_starts_its_respawn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: despawn_at(delay_ms: 0, went_at_ms: 6000),
    )
  assert kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    as "opcode.0x355 to each viewer, in the order of their connections"
  assert timers_started(taken) == [#(corpse_timer, 60_000)]
    as "the kind's respawn time (death.creature_respawn), and no despawn timer for a delay of 0"
  assert timers_cancelled(taken) == []
    as "no despawn was pending, so none is cancelled"
}

pub fn a_despawn_sends_no_health_death_or_credit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(wounded, _) =
    told(
      state: watched_by_two(),
      at_ms: 5500,
      message: strike_of(damage: 10, cast_id: 1),
    )
  let #(_, taken) =
    told(
      state: wounded,
      at_ms: 6000,
      message: despawn_at(delay_ms: 0, went_at_ms: 6000),
    )
  assert health_news(taken) == [] as "no 0x937"
  assert credits(taken) == [] as "no kill credit to the caster's connection"
  assert kinds_of(outgoing(taken))
    |> list.filter(fn(kind) { kind != "other" })
    == ["removal to 2", "removal to 5"]
    as "of the viewers' news only the 0x355s: no 0x88c death and no corpse (the strike's fight ends with its combat state, which kinds_of calls other)"
  assert !support.stops(taken)
}

pub fn a_delayed_despawn_starts_one_timer_for_the_go_plus_the_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = despawning_at_10_000()
  assert timers_started(taken) == [#(despawn_timer, 4000)]
    as "the go at 6000 and a delay of 4000: due at 10000, 4000 ms from the tell at 6000"
  assert list.length(support.effects_of(taken)) == 1
    as "nothing is sent before the timer fires, and no corpse timer starts"
  let #(_, late) =
    told(
      state: watched_by_two(),
      at_ms: 6300,
      message: despawn_at(delay_ms: 4000, went_at_ms: 6000),
    )
  assert timers_started(late) == [#(despawn_timer, 3700)]
    as "the delay runs from the go, not from the tell's arrival"
}

pub fn the_despawn_timer_firing_removes_the_creature_for_each_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = despawning_at_10_000()
  let #(_, taken) = fired(state:, at_ms: 10_000, timer: despawn_timer)
  assert kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    as "opcode.0x355 to each viewer when the go plus the delay comes"
  assert timers_started(taken) == [#(corpse_timer, 60_000)]
    as "the respawn time is counted from the removal"
}

pub fn a_despawn_already_due_removes_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 8000,
      message: despawn_at(delay_ms: 1000, went_at_ms: 6000),
    )
  assert kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    as "the go at 6000 and 1000 ms: due at 7000, past at the tell at 8000"
  assert timers_started(taken) == [#(corpse_timer, 60_000)]
    as "no despawn timer for a due time already past"
}

pub fn the_earlier_of_two_pending_despawns_stays_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = despawning_at_10_000()
  let #(_, later) =
    told(
      state:,
      at_ms: 6100,
      message: despawn_at(delay_ms: 5000, went_at_ms: 6000),
    )
  assert support.effects_of(later) == []
    as "due at 11000, after the pending 10000: no timer effect, since the shell ends a process that starts a running timer id"
  let #(_, same) =
    told(
      state:,
      at_ms: 6100,
      message: despawn_at(delay_ms: 4000, went_at_ms: 6000),
    )
  assert support.effects_of(same) == [] as "the same due time: no timer effect"
  let #(_, due) = fired(state:, at_ms: 10_000, timer: despawn_timer)
  assert kinds_of(outgoing(due)) == ["removal to 2", "removal to 5"]
    as "the pending timer stands and removes at 10000"
  let #(sooner, taken) =
    told(
      state:,
      at_ms: 6100,
      message: despawn_at(delay_ms: 1000, went_at_ms: 6000),
    )
  let assert [
    OwnEffect(step.CancelServiceTimer(timer: cancelled)),
    OwnEffect(StartServiceTimer(timer: started, after_ms: 900)),
  ] = support.effects_of(taken)
    as "due at 7000, ahead: the pending timer is cancelled, then started again for 900 ms"
  assert cancelled == despawn_timer && started == despawn_timer
  let #(_, removed) = fired(state: sooner, at_ms: 7000, timer: despawn_timer)
  assert kinds_of(outgoing(removed)) == ["removal to 2", "removal to 5"]
  let #(_, past) =
    told(
      state:,
      at_ms: 8000,
      message: despawn_at(delay_ms: 1000, went_at_ms: 6000),
    )
  assert timers_cancelled(past) == [despawn_timer]
    && kinds_of(outgoing(past)) == ["removal to 2", "removal to 5"]
    && timers_started(past) == [#(corpse_timer, 60_000)]
    as "due at 7000, past at 8000: the pending timer is cancelled and the creature leaves now, with no timer started for the despawn"
}

pub fn a_creature_killed_with_a_despawn_pending_cancels_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = despawning_at_10_000()
  let #(dead, taken) =
    told(state:, at_ms: 7000, message: strike_of(damage: 60, cast_id: 1))
  assert kinds_of(outgoing(taken))
    == [
      "answer to 2",
      "credit to 2",
      "health to 2",
      "health to 5",
      "death to 2",
      "death to 5",
    ]
    as "the death path is unchanged"
  assert timers_cancelled(taken) == [despawn_timer]
    as "the pending despawn is cancelled at the kill"
  assert timers_started(taken) == [#(corpse_timer, 60_000)]
  let #(_, stale) = fired(state: dead, at_ms: 10_000, timer: despawn_timer)
  assert support.effects_of(stale) == []
    as "a fire already queued when the creature died removes nothing"
}

pub fn a_despawn_at_a_dead_or_despawned_creature_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(dead, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: strike_of(damage: 60, cast_id: 1),
    )
  let #(_, to_dead) =
    told(
      state: dead,
      at_ms: 6500,
      message: despawn_at(delay_ms: 0, went_at_ms: 6500),
    )
  assert support.effects_of(to_dead) == [] as "a corpse is not removed"
  let #(_, to_gone) =
    told(
      state: despawned_by_two(),
      at_ms: 6500,
      message: despawn_at(delay_ms: 0, went_at_ms: 6500),
    )
  assert support.effects_of(to_gone) == []
    as "a creature already gone is not removed again, and its respawn is not restarted"
}

/// Player 2, at x = 5, comes near the Beast, which stands at x = 0.
fn approached_by_2() -> creature.Message {
  creature.Approached(member: step.RingMember(
    by: map_support.address(number: 2),
    unit_id: 20,
    place: map_spawn_support.at(5.0),
    seq: 1,
    hit_radius: place_support.player_hit_radius,
  ))
}

/// The connections the step releases from the creature, unit 7, as the number of each.
fn released_unit_7(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(outgoing(taken), fn(one) {
    case one.1 {
      creature.Relay(
        payload: map_message.Fight(told: strike_tell.Released(unit_id: 7)),
        ..,
      ) -> Ok(one.0)
      creature.Relay(..)
      | creature.Snapshot(..)
      | creature.Expired(..)
      | creature.Broadcast(..) -> Error(Nil)
    }
  })
}

/// The viewers the step sends the end of combat (0x908's combat state off), as the number
/// of each.
fn combat_ended_for(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: unit_news.CombatState(in_combat: False), ..) -> Ok(one.0)
      PeerNews(..) -> Error(Nil)
    }
  })
}

pub fn a_despawn_ends_the_creatures_fight_and_releases_its_players_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, aggro) =
    told(state: watched_by_two(), at_ms: 6000, message: approached_by_2())
  let assert [#(attack_tick, 1500)] = timers_started(aggro)
    as "the aggro starts the attack tick, 1500 ms on"
  let #(state, taken) =
    told(
      state:,
      at_ms: 6200,
      message: despawn_at(delay_ms: 0, went_at_ms: 6200),
    )
  assert released_unit_7(taken) == [2]
    as "player 2, whom the creature fought, is released, as at a death"
  assert combat_ended_for(taken) == [2, 5] as "the viewers see the combat end"
  let #(_, late) = fired(state:, at_ms: 7500, timer: attack_tick)
  assert outgoing(late) == [] as "no attack after the removal"
}

/// The crowd-control states the step ends for viewers (0x880), as the viewers' numbers.
fn ended_states(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: unit_news.CrowdControlEnded(..), ..) -> Ok(one.0)
      PeerNews(..) -> Error(Nil)
    }
  })
}

/// A strike of connection 2 for 1 damage that carries Kick's Knockdown.
fn knocking_strike(cast_id cast_id: Int) -> creature.Message {
  let assert creature.Strike(tell:) = strike_of(damage: 1, cast_id:)
  creature.Strike(
    tell: Strike(..tell, controls: [
      crowd_control_support.kick_knockdown(instance_id: 28_673),
    ]),
  )
}

pub fn a_despawn_drops_states_armor_and_an_opening_without_a_0x880_test() -> Nil {
  use <- owned_test.run(5000)
  let #(held, knocked) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: knocking_strike(cast_id: 1),
    )
  let state_timers =
    list.filter_map(timers_started(knocked), fn(started) {
      case creature.control_of(timer: started.0) {
        Ok(_) -> Ok(started.0)
        Error(Nil) -> Error(Nil)
      }
    })
  assert state_timers != [] as "the knockdown holds a state, with its timer"
  let #(_, taken) =
    told(
      state: held,
      at_ms: 6500,
      message: despawn_at(delay_ms: 0, went_at_ms: 6500),
    )
  assert list.all(state_timers, fn(timer) {
    list.contains(timers_cancelled(taken), timer)
  })
    as "each state's timer is cancelled"
  assert ended_states(taken) == []
    as "cc_state.end: no 0x880, the client drops the states with the unit's removal"
  // Worn armor: a Stagger stun wears 1 of 3 points, which the refill timer would give back.
  let #(worn, wearing) =
    told(
      state: armored_by_two(points: 3),
      at_ms: 6000,
      message: stunning_strike(cast_id: 2),
    )
  assert armor_left(wearing) == [#(2, 2), #(5, 2)]
  let #(_, taken) =
    told(
      state: worn,
      at_ms: 6500,
      message: despawn_at(delay_ms: 0, went_at_ms: 6500),
    )
  assert list.contains(timers_cancelled(taken), TimerId(2))
    as "the armor refill timer is cancelled"
  assert armor_left(taken) == [] && ended_states(taken) == []
    as "no 0x938 and no 0x880 are sent"
  // A guarded turret's open opening: its support is the fight test's.
  creature_fight_test.a_despawned_opening_ends_without_a_0x880()
}

pub fn a_throw_and_a_modifier_at_a_despawned_creature_are_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, thrown) =
    told(state: despawned_by_two(), at_ms: 6500, message: a_throw())
  assert support.effects_of(thrown) == []
    as "a creature that is gone is not thrown"
  let #(_, modified) =
    told(
      state: despawned_by_two(),
      at_ms: 6500,
      message: starting(source: thorns_source(), modifier: thorns()),
    )
  assert support.effects_of(modified) == []
    as "a modifier that reaches the creature while it is gone is dropped"
  let #(_, struck) =
    told(
      state: despawned_by_two(),
      at_ms: 6500,
      message: gated(strike: strike_of(damage: 10, cast_id: 2), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  assert answer_of(struck) == Refused(why: strike_tell.Despawned)
    as "a strike is refused as despawned, and reads no gate though the gate would hold"
  assert kinds_of(outgoing(struck)) == ["refusal to 2"]
}

pub fn a_viewer_arriving_while_despawned_is_sent_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    told(
      state: despawned_by_two(),
      at_ms: 7000,
      message: creature_news_support.seen(by: ConnectionId(9)),
    )
  assert support.effects_of(taken) == []
    as "opcode.0x355: the unit is gone to the client, and no 0x262 shows a creature that is not there"
  assert set.contains(creature.viewers(state), map_support.address(number: 9))
    as "the viewer is recorded"
}

pub fn a_viewer_that_arrived_while_despawned_is_sent_nothing_at_the_expiry_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    told(
      state: despawned_by_two(),
      at_ms: 7000,
      message: creature_news_support.seen(by: ConnectionId(9)),
    )
  let #(_, taken) =
    feed_raw(
      state:,
      at_ms: 66_000,
      event: OwnEvent(step.ServiceTimerFired(corpse_timer)),
    )
  assert effects_named(taken) == ["expired 7 of life 3", "stop"]
    as "death.creature_respawn: the creature sends no 0x355 (it went at the despawn) and no 0x262; its map starts the next life for the players who see the spawn then, the late viewer included"
}

pub fn a_despawned_creature_waits_the_kinds_respawn_time_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: despawn_at(delay_ms: 0, went_at_ms: 6000),
    )
  assert timers_started(taken) == [#(corpse_timer, 60_000)]
    as "the kind's respawn_ms, 60000, counted from the removal"
  let #(_, delayed) =
    fired(state: despawning_at_10_000().0, at_ms: 10_000, timer: despawn_timer)
  assert timers_started(delayed) == [#(corpse_timer, 60_000)]
    as "a delayed despawn counts the respawn from its removal, not from the go: the delay is not taken off it"
}

pub fn a_creature_retiring_with_a_despawn_pending_stops_now_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = despawning_at_10_000()
  let #(_, taken) = told(state:, at_ms: 7000, message: Retire)
  assert support.stops(taken)
    as "the creature stands: it stops now, and the pending despawn goes with it"
}

pub fn a_run_only_creature_that_is_despawned_stops_at_its_corpse_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, removed) =
    told(
      state: run_only_by_two(),
      at_ms: 6000,
      message: despawn_at(delay_ms: 0, went_at_ms: 6000),
    )
  assert kinds_of(outgoing(removed)) == ["removal to 2", "removal to 5"]
  let #(_, taken) = fired(state:, at_ms: 66_000, timer: corpse_timer)
  assert support.stops(taken) as "the creature stops, so its map ends the spawn"
  assert outgoing(taken) == []
    as "each viewer was sent its 0x355 at the removal: no second one, and no 0x262 that stands it again"
}

// ---- held unit states (issue 795) ----
//
// A go's UnitStateSet rows (Spell4Effects type 15) reach the Beast as `UnitStates`; state 6
// (row 64365's, Spell4 32683 "Stun/Immune - 8 seconds": 8500 ms) is read as one that blocks
// hostile effects (`unit_state.blocks_hostile`, a reading guessed from spell names). The Beast
// is watched by connections 2 and 5 from 5000, and a go at 6000 told it the state, which ends
// at 14 500. The unit-state timer is `TimerId(4)`. The Beast's health is 52.

const unit_state_timer = TimerId(4)

/// The rows of a go at `went_at_ms`, struck 100 ms before as its round opened.
fn unit_states_at(
  rows rows: List(unit_state.Row),
  went_at_ms went_at_ms: Int,
) -> creature.Message {
  creature.UnitStates(rows:, went_at_ms:)
}

/// Row 64365: state 6 for 8500 ms, no delay.
fn state_6_for_8500() -> unit_state.Row {
  unit_state.Row(state: 6, delay_ms: 0, duration_ms: 8500)
}

/// The watched Beast after a go at 6000 holds state 6 on it until 14 500.
fn invulnerable_by_two() -> State {
  holding_state_6(state: watched_by_two())
}

/// This creature after a go at 6000 holds state 6 on it until 14 500.
fn holding_state_6(state state: State) -> State {
  told(
    state:,
    at_ms: 6000,
    message: unit_states_at(rows: [state_6_for_8500()], went_at_ms: 6000),
  ).0
}

/// The unit-state news the step sends, as the viewer's number and the news, in order.
fn unit_state_news(
  taken: ServiceStep(creature.Outgoing),
) -> List(#(Int, unit_news.News)) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: unit_news.UnitStateHeld(state:, number:), ..) ->
        Ok(#(one.0, unit_news.UnitStateHeld(state:, number:)))
      PeerNews(news: unit_news.UnitStateEnded(number:), ..) ->
        Ok(#(one.0, unit_news.UnitStateEnded(number:)))
      PeerNews(..) -> Error(Nil)
    }
  })
}

fn held(state state: Int, number number: Int) -> unit_news.News {
  unit_news.UnitStateHeld(state:, number:)
}

fn unit_state_ended(number number: Int) -> unit_news.News {
  unit_news.UnitStateEnded(number:)
}

/// The viewers the step sends a state that took hold on the creature.
fn states_applied_to(taken: ServiceStep(creature.Outgoing)) -> List(Int) {
  list.filter_map(sent(taken), fn(one) {
    case one.1 {
      PeerNews(news: unit_news.CrowdControlApplied(..), ..) -> Ok(one.0)
      PeerNews(..) -> Error(Nil)
    }
  })
}

/// Whether the answer is the creature's immunity.
fn is_immune(outcome: strike_tell.Outcome) -> Bool {
  case outcome {
    strike_tell.Immune(..) -> True
    Landed(..) | strike_tell.Deflected(..) | Refused(..) -> False
  }
}

/// A strike of connection 2 with Stagger's Stun and no blow.
fn stunning_strike_without_blows(cast_id cast_id: Int) -> creature.Message {
  let assert creature.Strike(tell:) = strike_of(damage: 1, cast_id:)
  creature.Strike(
    tell: Strike(..tell, offence: Offence(..tell.offence, blows: []), controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ]),
  )
}

pub fn a_held_unit_state_is_told_to_each_viewer_in_connection_order_and_ended_by_timer_4_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: unit_states_at(rows: [state_6_for_8500()], went_at_ms: 6000),
    )
  assert unit_state_news(taken)
    == [#(2, held(state: 6, number: 1)), #(5, held(state: 6, number: 1))]
    as "each viewer, in the order of the connections, is told the state under its number"
  assert timers_started(taken) == [#(unit_state_timer, 8500)]
    as "one timer, for the end at 14 500"
  let #(_, ended) = fired(state:, at_ms: 14_500, timer: unit_state_timer)
  assert unit_state_news(ended)
    == [#(2, unit_state_ended(number: 1)), #(5, unit_state_ended(number: 1))]
    as "its fire ends the state for each viewer"
  assert timers_started(ended) == [] as "no state is left, so no timer"
}

pub fn the_unit_state_timer_has_its_own_id_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: unit_states_at(rows: [state_6_for_8500()], went_at_ms: 6000),
    )
  let assert [#(started, 8500)] = timers_started(taken)
    as "the hold starts one timer, 8500 ms on"
  let TimerId(number) = started
  assert number == 4
  assert number != 1 && number != 2 && number != 3
    as "not the corpse's, the refill's or the despawn's"
  assert number < 7
    as "a fight timer is 7 times a generation from 1, plus 0 to 3 or 6: from 7"
  assert creature.control_of(timer: started) == Error(Nil)
    as "a control's id is 4 above 7 times a number from 1, so from 11"
  let #(_, despawn_fired) = fired(state:, at_ms: 7000, timer: despawn_timer)
  assert unit_state_news(despawn_fired) == []
    as "another timer's fire ends no state"
}

pub fn a_strike_with_blows_at_an_invulnerable_creature_is_answered_immune_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: gated(strike: strike_of(damage: 10, cast_id: 1), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  assert answer_of(taken)
    == strike_tell.Immune(controls: [], armor_removed: 0, gates_passed: [1])
    as "the blow is answered immune, naming the gate that passed"
  assert health_news(taken) == [] as "no health is lost and no 0x937 is sent"
  let #(_, killing) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: strike_of(damage: 60, cast_id: 2),
    )
  assert answer_of(killing)
    == strike_tell.Immune(controls: [], armor_removed: 0, gates_passed: [])
    as "damage past the creature's health takes nothing too"
  let kinds = kinds_of(outgoing(killing))
  assert !list.contains(kinds, "credit to 2")
    && !list.contains(kinds, "death to 2")
    && !list.contains(kinds, "death to 5")
    as "and kills nothing: no credit and no death"
}

pub fn a_strike_with_only_states_at_an_invulnerable_creature_lands_none_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: holding_state_6(state: armored_by_two(points: 3)),
      at_ms: 7000,
      message: stunning_strike_without_blows(cast_id: 1),
    )
  assert answer_of(taken)
    == strike_tell.Immune(controls: [], armor_removed: 0, gates_passed: [])
    as "the state is not taken"
  assert states_applied_to(taken) == [] as "no 0x87f is sent"
  assert armor_left(taken) == [] as "no armor is worn, so no 0x938"
}

pub fn a_strike_with_no_hostile_content_ignores_the_unit_state_test() -> Nil {
  use <- owned_test.run(5000)
  // A go row of gates only: neither blows nor states reach the creature.
  let assert creature.Strike(tell:) = strike_of(damage: 1, cast_id: 1)
  let gate_only =
    creature.Strike(
      tell: Strike(..tell, offence: Offence(..tell.offence, blows: []), gates: [
        gate(effect_id: 1, condition: #(1, 1, 0, 1)),
      ]),
    )
  let #(_, held) =
    told(state: invulnerable_by_two(), at_ms: 7000, message: gate_only)
  let #(_, free) =
    told(state: watched_by_two(), at_ms: 7000, message: gate_only)
  assert answer_of(held) == answer_of(free)
    as "answered as for a creature that holds no state"
  assert !is_immune(answer_of(held))
}

pub fn a_strike_after_the_state_ends_lands_normally_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: strike_of(damage: 10, cast_id: 1),
    )
  let #(state, ended) = fired(state:, at_ms: 14_500, timer: unit_state_timer)
  assert list.length(unit_state_news(ended)) == 2
  let #(_, hit) =
    told(state:, at_ms: 15_000, message: strike_of(damage: 10, cast_id: 2))
  let assert Landed(descriptions: [_], ..) = answer_of(hit)
    as "the blow lands as on any creature"
  assert list.all(health_news(hit), fn(news) { news.1 == 42 })
    as "the Beast loses 10 of its 52 health"
  let #(_, stunned) =
    told(
      state: holding_state_6(state: armored_by_two(points: 3)),
      at_ms: 14_600,
      message: stunning_strike(cast_id: 3),
    )
  let assert Landed(armor_removed: 1, ..) = answer_of(stunned)
    as "the stun wears one point of the armor after the end, as on any creature"
  assert armor_left(stunned) == [#(2, 2), #(5, 2)]
}

pub fn a_strike_after_the_end_but_before_the_timer_fires_lands_normally_test() -> Nil {
  use <- owned_test.run(5000)
  // The hold ended at 14 500; its timer's message has not reached the creature yet.
  let #(_, hit) =
    told(
      state: invulnerable_by_two(),
      at_ms: 14_500,
      message: strike_of(damage: 10, cast_id: 1),
    )
  let assert Landed(descriptions: [_], ..) = answer_of(hit)
    as "a hold past its end blocks nothing"
  Nil
}

pub fn a_tick_at_an_invulnerable_creature_is_answered_immune_test() -> Nil {
  use <- owned_test.run(5000)
  let assert creature.Strike(tell:) = strike_of(damage: 3, cast_id: 1)
  let tick = fn(number) {
    creature.Strike(
      tell: Strike(
        ..tell,
        key: Key(
          cast_id: 1,
          occasion: strike_tell.AtTick(
            effect_id: id.Spell4EffectsId(9),
            go: 1,
            tick: number,
          ),
          unit_id: 7,
        ),
      ),
    )
  }
  let #(state, first) =
    told(state: invulnerable_by_two(), at_ms: 7000, message: tick(1))
  let #(_, second) = told(state:, at_ms: 8000, message: tick(2))
  assert is_immune(answer_of(first)) && is_immune(answer_of(second))
    as "each tick is answered immune"
  assert health_news(first) == [] && health_news(second) == []
    as "and costs no health"
}

pub fn an_immune_strike_threatens_the_creature_as_a_guarded_one_does_test() -> Nil {
  use <- owned_test.run(5000)
  // The guard's `Immune` threatens the creature with the threat of no description (a guess):
  // the strike pulls the creature into a fight as a landed strike does.
  let #(_, blocked) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: strike_of(damage: 10, cast_id: 1),
    )
  let #(_, landed) =
    told(
      state: watched_by_two(),
      at_ms: 7000,
      message: strike_of(damage: 10, cast_id: 1),
    )
  assert timers_started(blocked) == timers_started(landed)
    as "the creature starts the attack tick it starts for any strike that threatens it"
  assert timers_started(blocked) != []
}

/// A creature of the guarded turret's kind standing at the Beast's spawn as unit 7, started
/// for the viewer 2 at 5000 ms.
fn guarded_by_two() -> State {
  let assert Ok(turret) =
    dict.get(spawn_support.guarded_turret_kinds().by_creature, 73_494)
    as "the guarded turret's kind carries the guard"
  let #(guarded, _) =
    feed(
      state: creature.new(Settings(
        creature: CreatureStart(
          map: ship,
          incarnation: 1,
          unit_id: 7,
          life: 3,
          spawn: spawn_source.Stored(id: SpawnId(1)),
          clock_origin_ms:,
          viewers: [
            #(map_support.address(number: 2), generation.first()),
          ],
          ring: [],
        ),
        spawn: spawn_support.battle_beast(number: 1, x: 0.0),
        kind: Kind(
          respawn_ms: 60_000,
          attack_spell4_id: Spell4Id(5649),
          alternate_spell4_ids: [],
          attack_interval_ms: 1500,
          guard: turret.guard,
          specials: [],
        ),
        numbers: spawn_support.numbers,
      )),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  guarded
}

pub fn a_guarded_creature_with_a_held_state_answers_one_immune_test() -> Nil {
  use <- owned_test.run(5000)
  let guarded = guarded_by_two()
  let with_stun = fn(state) {
    let assert creature.Strike(tell:) = strike_of(damage: 10, cast_id: 1)
    told(
      state:,
      at_ms: 7000,
      message: creature.Strike(
        tell: Strike(..tell, controls: [
          crowd_control_support.stagger_stun(instance_id: 28_673),
        ]),
      ),
    )
  }
  let #(_, guard_only) = with_stun(guarded)
  let assert strike_tell.Immune(controls: [_], ..) = answer_of(guard_only)
    as "the guard alone takes the blow as immune and lets the state land"
  let #(_, both) = with_stun(holding_state_6(state: guarded))
  assert answer_of(both)
    == strike_tell.Immune(controls: [], armor_removed: 0, gates_passed: [])
    as "with the state held the creature answers one immune and the state does not land"
}

pub fn a_throw_at_an_invulnerable_creature_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, thrown) =
    told(state: invulnerable_by_two(), at_ms: 7000, message: a_throw())
  assert support.effects_of(thrown) == []
    as "a creature that takes no hostile effect is not thrown"
  let #(state, _) = fired(state:, at_ms: 14_500, timer: unit_state_timer)
  let #(_, after) = told(state:, at_ms: 14_600, message: a_throw())
  assert flown_to(after) == [2, 5] as "after the end the throw moves it"
  let #(_, before_timer) =
    told(state: invulnerable_by_two(), at_ms: 14_500, message: a_throw())
  assert flown_to(before_timer) == [2, 5]
    as "a hold past its end blocks no throw, though its timer has not fired"
}

pub fn a_modifier_at_a_creature_holding_a_blocking_state_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, modified) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: starting(source: thorns_source(), modifier: thorns()),
    )
  assert support.effects_of(modified) == []
    as "a creature that takes no hostile effect takes no struck-change modifier, as it takes no throw"
  let #(state, _) = fired(state:, at_ms: 14_500, timer: unit_state_timer)
  let #(_, after) =
    told(
      state:,
      at_ms: 14_600,
      message: starting(source: thorns_source(), modifier: thorns()),
    )
  assert support.effects_of(after) != []
    as "once the state has ended the same modifier lands: the earlier one was dropped, not held"
}

pub fn a_despawn_still_removes_an_invulnerable_creature_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: despawn_at(delay_ms: 0, went_at_ms: 7000),
    )
  assert kinds_of(outgoing(taken)) == ["removal to 2", "removal to 5"]
    as "a removal is not a hostile effect"
}

pub fn a_viewer_arriving_while_states_are_held_is_told_them_after_the_0x262_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: unit_states_at(
        rows: [
          state_6_for_8500(),
          unit_state.Row(state: 13, delay_ms: 0, duration_ms: 2000),
        ],
        went_at_ms: 6000,
      ),
    )
  let nine = ConnectionId(9)
  let #(state, arrived) =
    told(state:, at_ms: 7000, message: creature_news_support.seen(by: nine))
  assert kinds_of(outgoing(arrived)) == ["creation to 9", "other", "other"]
    as "the 0x262, then one news per held state"
  assert unit_state_news(arrived)
    == [#(9, held(state: 6, number: 1)), #(9, held(state: 13, number: 2))]
  let #(state, again) =
    told(state:, at_ms: 7500, message: creature_news_support.seen(by: nine))
  assert kinds_of(outgoing(again)) == ["creation to 9", "other", "other"]
    as "a repeated Watched is told the creature and its states again"
  let #(state, ended) = fired(state:, at_ms: 8000, timer: unit_state_timer)
  assert unit_state_news(ended)
    == [
      #(2, unit_state_ended(number: 2)),
      #(5, unit_state_ended(number: 2)),
      #(9, unit_state_ended(number: 2)),
    ]
    as "the state that ended is ended for the new viewer too"
  let #(state, late) =
    told(
      state:,
      at_ms: 8100,
      message: creature_news_support.seen(by: ConnectionId(11)),
    )
  assert unit_state_news(late) == [#(11, held(state: 6, number: 1))]
    as "only the state still held is told"
  let #(_, left) =
    told(state:, at_ms: 8200, message: creature_news_support.unseen(by: nine))
  assert outgoing(left) == []
    as "a viewer that leaves is sent nothing by the creature: the map tells it the unit is gone"
}

pub fn a_viewer_a_creature_starts_with_is_told_the_states_it_holds_test() -> Nil {
  use <- owned_test.run(5000)
  // The Started input tells each viewer the creature as it stands, held states included.
  let #(state, _) =
    told(
      state: creature_for(viewers: [ConnectionId(2)]),
      at_ms: 6000,
      message: unit_states_at(rows: [state_6_for_8500()], went_at_ms: 6000),
    )
  let #(_, started) = feed(state:, at_ms: 7000, event: OwnEvent(Started))
  assert unit_state_news(started) == [#(2, held(state: 6, number: 1))]
}

pub fn a_despawn_clears_the_held_unit_states_test() -> Nil {
  use <- owned_test.run(5000)
  let #(gone, removed) =
    told(
      state: invulnerable_by_two(),
      at_ms: 7000,
      message: despawn_at(delay_ms: 0, went_at_ms: 7000),
    )
  assert timers_cancelled(removed) == [unit_state_timer]
    as "the running timer is cancelled with the removal"
  assert unit_state_news(removed) == []
    as "no UnitStateEnded: the Removed clears the viewers' pictures"
  let #(_, stale) = fired(state: gone, at_ms: 14_500, timer: unit_state_timer)
  assert support.effects_of(stale) == []
    as "a fire already queued at the removal ends nothing"
}

pub fn a_kill_clears_the_held_unit_states_and_cancels_the_timer_test() -> Nil {
  use <- owned_test.run(5000)
  // State 1 has no reading, so a creature that holds it can be killed.
  let #(state, _) =
    told(
      state: watched_by_two(),
      at_ms: 6000,
      message: unit_states_at(
        rows: [unit_state.Row(state: 1, delay_ms: 0, duration_ms: 8500)],
        went_at_ms: 6000,
      ),
    )
  let #(dead, killed) =
    told(state:, at_ms: 7000, message: strike_of(damage: 60, cast_id: 1))
  assert timers_cancelled(killed) == [unit_state_timer]
    as "a kill cancels the running timer"
  let #(_, stale) = fired(state: dead, at_ms: 14_500, timer: unit_state_timer)
  assert support.effects_of(stale) == []
    as "a fire already queued at the kill ends nothing"
}

// ---- the views players' casts tell the creature ----
//
// A cast's view is a node of its go on the creature (`creature.CastViewSet`). Expected
// values come from `cast.target_node_end` (a corpse keeps its nodes until they end),
// `cast_state.caster_of` (a cast id names its caster) and `opcode.0x262.casts`, `opcode.0x7f4.effect_time` and
// `opcode.0x7f4.effect_delay` (the entry's delay is the delay still to run and its
// lifetime the time left, at the arrival's time).

/// The effect row a view holds: Fissure's Spell4Effects 94370, a type 11 row.
const view_effect_id = 94_370

/// The cast number `number` of the caster unit `unit`, which holds `count` stacks on the
/// Beast, unit 7, from `starts_ms` to `ends_ms`; gone, and not the caster's current cast.
fn view_with(
  unit unit: Int,
  number number: Int,
  count count: Int,
  starts_ms starts_ms: Int,
  ends_ms ends_ms: Int,
) -> CastView {
  CastView(
    caster_unit_id: unit,
    cast_id: cast_state.cast_id(unit_id: unit, number:),
    spell4_id: Spell4Id(41_886),
    primary_target: 7,
    gone: True,
    current: False,
    targets: [
      ViewTarget(unit_id: 7, count:, effects: [
        HeldEffect(
          effect_id: Spell4EffectsId(view_effect_id),
          starts_ms:,
          ends: EndsAt(ms: ends_ms),
        ),
      ]),
    ],
  )
}

/// The view of cast number 1 of unit 21 with one stack, held from 6000 to 14 000.
fn view_a() -> CastView {
  view_with(unit: 21, number: 1, count: 1, starts_ms: 6000, ends_ms: 14_000)
}

/// The view of cast number 2 of unit 21 with one stack, held from 6000 to 14 000.
fn view_b() -> CastView {
  view_with(unit: 21, number: 2, count: 1, starts_ms: 6000, ends_ms: 14_000)
}

/// One input at a time on the monotonic clock.
type At =
  #(Int, Event(ServiceEvent(creature.Message)))

fn view_set(by by: Int, view view: CastView, at_ms at_ms: Int) -> At {
  #(
    at_ms,
    OwnEvent(
      Told(creature.CastViewSet(by: map_support.address(number: by), view:)),
    ),
  )
}

fn view_ends(by by: Int, view view: CastView, at_ms at_ms: Int) -> At {
  #(
    at_ms,
    OwnEvent(
      Told(creature.CastViewEnds(
        by: map_support.address(number: by),
        cast_id: view.cast_id,
      )),
    ),
  )
}

/// A strike that kills the Beast.
fn killed_at(at_ms at_ms: Int) -> At {
  #(at_ms, OwnEvent(Told(strike_of(damage: 60, cast_id: 1))))
}

/// The Beast watched by the viewers 2 and 5 after these inputs, and the step of the last.
fn after(inputs inputs: List(At)) -> #(State, ServiceStep(creature.Outgoing)) {
  list.fold(inputs, #(watched_by_two(), step.Effects([])), fn(held, input) {
    feed(state: held.0, at_ms: input.0, event: input.1)
  })
}

/// The 0x262 a viewer arriving at `at_ms` is sent.
fn arrival_create(
  state state: State,
  at_ms at_ms: Int,
) -> unit_create_creature.UnitCreateCreature {
  let #(_, taken) =
    told(
      state:,
      at_ms:,
      message: creature_news_support.seen(by: ConnectionId(20)),
    )
  let assert [
    #(
      20,
      creature.Broadcast(
        news: PeerNews(news: CreatureAppeared(unit:, ..), ..),
        ..,
      ),
    ),
    ..
  ] = outgoing(taken)
  unit
}

/// The cast ids and the stacks on the Beast of each cast a viewer arriving at 20 000 is
/// told.
fn arrival_holds(state state: State) -> List(#(Int, Int)) {
  list.map(arrival_create(state:, at_ms: 20_000).tail.casts, fn(cast) {
    let assert [target] = cast.targets
    #(cast.cast_id, target.instance_count)
  })
}

/// The watches the step starts and ends, in order.
fn watch_changes(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      step.Watch(watch: WatchId(number), target: Connection(ConnectionId(by))) ->
        Ok("watch " <> int.to_string(number) <> " of " <> int.to_string(by))
      step.Unwatch(watch: WatchId(number)) ->
        Ok("unwatch " <> int.to_string(number))
      step.Watch(..) | OwnEffect(..) | step.Log(..) | Stop -> Error(Nil)
    }
  })
}

pub fn a_creature_keeps_the_cast_views_it_is_told_test() -> Nil {
  use <- owned_test.run(5000)
  let id_a = view_a().cast_id
  let two_stacks =
    view_with(unit: 21, number: 1, count: 2, starts_ms: 6000, ends_ms: 14_000)
  list.each(
    [
      #(
        "a CastViewSet is kept, whatever the time of the go it names",
        [view_set(by: 9, view: view_a(), at_ms: 6000)],
        [#(id_a, 1)],
      ),
      #(
        "a second set for the same cast replaces the first: the later count",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_set(by: 9, view: two_stacks, at_ms: 6500),
        ],
        [#(id_a, 2)],
      ),
      #(
        "CastViewEnds removes it",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_ends(by: 9, view: view_a(), at_ms: 7000),
        ],
        [],
      ),
      #(
        "an end for a cast it does not hold changes nothing",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_ends(by: 9, view: view_b(), at_ms: 7000),
        ],
        [#(id_a, 1)],
      ),
      #(
        "an end from another connection than the holder's changes nothing",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_ends(by: 10, view: view_a(), at_ms: 7000),
        ],
        [#(id_a, 1)],
      ),
      #(
        "a set reaching a dead creature is kept, and the corpse's 0x262 lists it",
        [
          killed_at(at_ms: 6000),
          view_set(by: 9, view: view_a(), at_ms: 7000),
        ],
        [#(id_a, 1)],
      ),
      #(
        "a set that replaces another connection's entry for the cast id keeps the later one",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_set(by: 10, view: view_a(), at_ms: 6100),
        ],
        [#(id_a, 1)],
      ),
    ],
    fn(row) {
      let #(state, last) = after(inputs: row.1)
      assert arrival_holds(state:) == row.2 as row.0
      assert watch_changes(last) == []
        as { row.0 <> ": the creature opens and ends no watch" }
    },
  )
}

/// The listing of one target of the Beast, as a unit create lists it: the Spell4 41 886
/// cast of unit `unit` that has gone, with the one effect row.
fn listed_cast(
  unit unit: Int,
  number number: Int,
  count count: Int,
  delay_ms delay_ms: Int,
  lifetime_ms lifetime_ms: Int,
) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: unit,
    primary_target_unit_id: 7,
    cast_id: cast_state.cast_id(unit_id: unit, number:),
    spell4_id: 41_886,
    started: 0,
    targets: [
      cast_support.listed_target_info(unit_id: 7, index: 0, count:, effects: [
        cast_support.listed_effect_info(
          effect_id: view_effect_id,
          instance_id: 1,
          delay_ms:,
          lifetime_ms:,
        ),
      ]),
    ],
    initial_positions: [],
    telegraph_positions: [],
  )
}

pub fn a_creature_unit_create_lists_the_views_it_keeps_test() -> Nil {
  use <- owned_test.run(5000)
  let second_caster =
    view_with(unit: 22, number: 1, count: 3, starts_ms: 6000, ends_ms: 14_000)
  list.each(
    [
      #("a creature holding no view lists none", [], 10_000, []),
      #(
        "two casters' views are both listed",
        [
          view_set(by: 9, view: view_a(), at_ms: 6000),
          view_set(by: 10, view: second_caster, at_ms: 6100),
        ],
        10_000,
        [
          listed_cast(
            unit: 21,
            number: 1,
            count: 1,
            delay_ms: 0,
            lifetime_ms: 4000,
          ),
          listed_cast(
            unit: 22,
            number: 1,
            count: 3,
            delay_ms: 0,
            lifetime_ms: 4000,
          ),
        ],
      ),
      #(
        "an effect's lifetime is its end less the arrival's time, not the tell's",
        [view_set(by: 9, view: view_a(), at_ms: 6000)],
        12_000,
        [
          listed_cast(
            unit: 21,
            number: 1,
            count: 1,
            delay_ms: 0,
            lifetime_ms: 2000,
          ),
        ],
      ),
      #(
        "a corpse lists its views",
        [
          killed_at(at_ms: 6000),
          view_set(by: 9, view: view_a(), at_ms: 7000),
        ],
        10_000,
        [
          listed_cast(
            unit: 21,
            number: 1,
            count: 1,
            delay_ms: 0,
            lifetime_ms: 4000,
          ),
        ],
      ),
      #(
        "the tail's cast id stays 0 though the view's cast is its caster's current cast",
        [
          view_set(
            by: 9,
            view: CastView(..view_a(), current: True),
            at_ms: 6000,
          ),
        ],
        10_000,
        [
          listed_cast(
            unit: 21,
            number: 1,
            count: 1,
            delay_ms: 0,
            lifetime_ms: 4000,
          ),
        ],
      ),
    ],
    fn(row) {
      let #(state, _) = after(inputs: row.1)
      let unit = arrival_create(state:, at_ms: row.2)
      assert unit.tail.casts == row.3 as row.0
      assert unit.tail.cast_id == 0 as row.0
    },
  )
}

/// The map's `Seen` of the player of connection 9, for the generation, as the creature takes it.
fn seen_by_nine(generation generation: Generation) -> creature.Message {
  creature.Seen(by: map_support.address(number: 9), generation:)
}

pub fn a_creature_answers_a_seen_with_a_snapshot_of_its_burst_live_dead_or_despawned_test() -> Nil {
  use <- owned_test.run(5000)
  let first_sight = generation.first()
  let struck = fn(state, damage) {
    told(state:, at_ms: 6000, message: strike_of(damage:, cast_id: 1)).0
  }
  // Each case: the creature as it stands, and the names of the burst it answers the viewer's
  // `Seen` with, in order: the 0x262 first, then what the viewer is first sent after it.
  let cases = [
    #("a standing creature", watched_by_two(), ["0x262"]),
    #("a creature that holds a state", invulnerable_by_two(), [
      "0x262",
      "unit state held",
    ]),
    #("a creature with a guard cast", guarded_by_two(), [
      "0x262",
      "0x7ff",
      "0x7f4",
    ]),
    #("a creature in a fight", struck(watched_by_two(), 14), [
      "0x262",
      "0x89a(1)",
      "0x908",
      "turn(kind 18, unit 1)",
    ]),
    #("a creature that lies dead", struck(watched_by_two(), 60), ["0x262"]),
    #("a despawned creature", despawned_by_two(), []),
  ]
  list.each(cases, fn(row) {
    let #(name, state, burst_names) = row
    let #(_, taken) =
      told_raw(
        state:,
        at_ms: 7000,
        message: seen_by_nine(generation: first_sight),
      )
    let assert [#(9, generation, burst)] = snapshots(taken)
      as { name <> " answers the Seen with one snapshot for the viewer" }
    assert generation == first_sight
      as { name <> ": under the generation the Seen named" }
    assert list.map(burst, fn(news) { burst_name(news.news) }) == burst_names
      as { name <> ": the burst, in the order the viewer writes it" }
    assert support.sends(taken) == []
      as {
        name <> ": nothing is sent to a connection, the map relays the burst"
      }
  })
  let #(_, dead) =
    told_raw(
      state: struck(watched_by_two(), 60),
      at_ms: 7000,
      message: seen_by_nine(generation: first_sight),
    )
  let assert [#(9, _, [PeerNews(news: CreatureAppeared(unit:, ..), ..)])] =
    snapshots(dead)
  assert creature_unit.health_of(unit:) == 0
    as "opcode.0x262.creature: a corpse is created dead, with health 0"
}

/// The name of a news the burst holds: the opcode of the frame the viewer writes for it,
/// with no value but a combat flag's.
fn burst_name(news: unit_news.News) -> String {
  case news {
    unit_news.UnitStateHeld(..) -> "unit state held"
    unit_news.Targeting(..) -> "0x908"
    _ -> creature_news_support.name_of(news)
  }
}

pub fn a_seen_a_snapshot_and_an_unseen_taken_twice_change_nothing_the_second_time_test() -> Nil {
  use <- owned_test.run(5000)
  let first_sight = generation.first()
  // A `Seen` taken twice is answered twice, and the second answer is the same.
  let #(state, first) =
    told_raw(
      state: watched_by_two(),
      at_ms: 7000,
      message: seen_by_nine(generation: first_sight),
    )
  let #(state, second) =
    told_raw(
      state:,
      at_ms: 7100,
      message: seen_by_nine(generation: first_sight),
    )
  let names = fn(taken) {
    list.map(snapshots(taken), fn(snapshot) {
      #(
        snapshot.0,
        snapshot.1,
        list.map(snapshot.2, fn(news) { burst_name(news.news) }),
      )
    })
  }
  assert names(second) == names(first) && names(first) != []
    as "a second Seen of the same viewer is answered again with a snapshot of the same viewer, generation and picture (its 0x262 carries the time the creature built it at)"
  // An `Unseen` taken twice: the first drops the viewer, the second finds no entry.
  let #(state, unseen) =
    told_raw(
      state:,
      at_ms: 7200,
      message: creature.Unseen(
        by: map_support.address(number: 9),
        generation: first_sight,
      ),
    )
  assert !set.contains(creature.viewers(state), map_support.address(number: 9))
    as "the first Unseen drops the viewer"
  assert support.sends(unseen) == []
    as "and the creature sends no 0x355: the map tells the viewer"
  let #(after, again) =
    told_raw(
      state:,
      at_ms: 7300,
      message: creature.Unseen(
        by: map_support.address(number: 9),
        generation: first_sight,
      ),
    )
  assert support.effects_of(again) == [] && after == state
    as "a second Unseen finds no entry and changes nothing"
  // The map takes the snapshot of its relation twice: the first is relayed, the second is
  // dropped because the relation no longer awaits it.
  let map_state =
    map_spawn_support.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(map_state, _) =
    map_spawn_support.join(state: map_state, at_ms: 6000, connection: 9, x: 0.0)
  let assert Ok(map.Live(unit_id:, life:, relations:, ..)) =
    map.spawn_state(state: map_state, spawn: SpawnId(1))
  let assert Ok(map.Relation(generation: held, ..)) =
    dict.get(relations, ConnectionId(9))
  let snapshot =
    map_message.Snapshot(
      unit_id:,
      life:,
      by: map_support.address(number: 9),
      generation: held,
      burst: [
        PeerNews(unit_id:, news: unit_news.Health(health: 52, dead: False)),
      ],
    )
  let #(map_state, first_taken) =
    map_spawn_support.feed(
      state: map_state,
      at_ms: 7000,
      event: OwnEvent(Told(snapshot)),
    )
  let #(_, second_taken) =
    map_spawn_support.feed(
      state: map_state,
      at_ms: 7100,
      event: OwnEvent(Told(snapshot)),
    )
  assert list.length(support.sends(first_taken)) == 1
    as "the map relays the first snapshot"
  assert support.sends(second_taken) == []
    as "and drops the second: the relation does not await it"
}

pub fn each_tell_a_player_sends_a_creature_reaches_it_as_the_message_its_rule_takes_with_the_sender_the_map_validated_test() -> Nil {
  use <- owned_test.run(5000)
  // The sender and the stay the relay named: the map's, never the payload's. Each row is the
  // creature message the rule of that tell takes, by the kind's name; the payloads are the
  // tests' own (`inbound_support.payloads`).
  let by = map_support.address(number: 4)
  let tell = inbound_support.strike(unit_id: 7)
  let place = inbound_support.place()
  let source = inbound_support.source()
  let rows = [
    #("Strike", creature.Strike(tell:)),
    #(
      "TargetMoved",
      creature.TargetMoved(by:, place:, seq: 9, hit_radius: 0.75),
    ),
    #(
      "StrikeAnswered",
      creature.StrikeAnswered(answered: inbound_support.answered(unit_id: 7)),
    ),
    #(
      "ModifierStarts",
      creature.ModifierStarts(
        by:,
        source:,
        modifier: inbound_support.modifier(),
      ),
    ),
    #("ModifierEnds", creature.ModifierEnds(source:)),
    #("Thrown", creature.Thrown(throw: world_watch_support.throw())),
    #("Despawn", creature.Despawn(delay_ms: 500, went_at_ms: 6000)),
    #(
      "UnitStates",
      creature.UnitStates(rows: inbound_support.rows(), went_at_ms: 6000),
    ),
    #("CastViewSet", creature.CastViewSet(by:, view: inbound_support.view())),
    #("CastViewEnds", creature.CastViewEnds(by:, cast_id: 1)),
    #("ControlsEnd", creature.ControlsEnd(by:, cast_id: 1)),
  ]
  list.each(inbound_support.payloads(unit_id: 7), fn(sent) {
    let #(kind, payload) = sent
    let assert Ok(expected) = list.key_find(rows, kind)
      as "a row for each kind the tests send"
    assert creature.told_by_map(map_message.ToldCreature(by:, payload:))
      == Ok(expected)
      as {
        kind
        <> " reaches the creature as its own message, with the relay's sender"
      }
  })
  assert list.map(rows, fn(row) { row.0 })
    == list.map(inbound_support.payloads(unit_id: 7), fn(row) { row.0 })
    as "a row for each kind the tests send"
}
