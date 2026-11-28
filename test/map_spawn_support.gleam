//// What the tests of a map that starts and stops creatures share: the map's
//// inputs as a connection or a timer makes them, at a time of the test's choosing,
//// and the effects of a step by kind. A rule's test drives the clock through the
//// inputs' times, so no test waits.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/map/message.{Join, Leave, Moved} as map_message
import genesis_prime/shared/creature_kind.{type Kinds, Kind, Kinds}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId,
  CancelServiceTimer, Connection, ConnectionId, Creature, OwnEffect, OwnEvent,
  Reply, Send, ServiceTimerFired, StartCreature, StartServiceTimer, Started,
  Told,
}
import genesis_prime/table/id.{type PrerequisiteId, Spell4Id}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import map_support
import place_support
import spawn_support

/// The time the map starts at on the monotonic clock.
pub const started_at_ms = 5000

pub const ship = MapId(world_id: 3460, instance: 0)

/// Far from every spawn the tests stand: no creature is in sight there.
pub const far = 50_000.0

/// A place `x` units along the world's x axis in Warfare Woods.
pub fn at(x: Float) -> Place {
  standing(x:, y: 0.0)
}

/// A place in Warfare Woods `x` along and `y` up, at z 0.
pub fn standing(x x: Float, y y: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y:,
    z: 0.0,
  )
}

pub fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(map_message.Message)),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  map.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// A map with a spawn at each of these x positions, numbered from 1, started.
pub fn started(
  at xs: List(Float),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  started_with(at: xs, kinds: default_kinds())
}

/// The kinds of the tests' maps: the server's 60 s default for every creature.
pub fn default_kinds() -> Kinds {
  Kinds(
    default: Kind(
      respawn_ms: map_support.respawn_ms,
      attack_spell4_id: Spell4Id(5649),
      alternate_spell4_ids: [],
      attack_interval_ms: 1500,
      guard: option.None,
      specials: [],
    ),
    by_creature: dict.new(),
  )
}

/// The same with the kinds the test chooses.
pub fn started_with(
  at xs: List(Float),
  kinds kinds: Kinds,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  let state =
    map_support.standing_with(
      incarnation: 1,
      spawns: list.index_map(xs, fn(x, index) {
        spawn_support.battle_beast(number: index + 1, x:)
      }),
      kinds:,
    )
  feed(state:, at_ms: started_at_ms, event: OwnEvent(Started))
}

/// A map with these spawns, started, on the default kinds.
pub fn started_with_spawns(spawns spawns: List(Spawn)) -> State {
  let state =
    map_support.standing_with(incarnation: 1, spawns:, kinds: default_kinds())
  let #(state, _) = feed(state:, at_ms: started_at_ms, event: OwnEvent(Started))
  state
}

/// A join of connection `connection` at `x`, at time `at_ms`.
pub fn join(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  join_as(state:, at_ms:, connection:, x:, alive: True)
}

/// A join of connection `connection` at `x`, at time `at_ms`, of a player that enters
/// alive or, with `alive` False, dead.
pub fn join_as(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
  alive alive: Bool,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  join_hiding(state:, at_ms:, connection:, x:, alive:, hidden: set.new())
}

/// A join of connection `connection` at `x`, at time `at_ms`, of a player for whom
/// these visibility prerequisites fail.
pub fn join_hiding(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
  alive alive: Bool,
  hidden hidden: Set(PrerequisiteId),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      caller: CallerId(connection),
      message: Join(
        joiner: ConnectionId(connection),
        character: map_support.character(100 + connection),
        place: at(x),
        alive:,
        hidden:,
      ),
    )),
  )
}

/// The connection's tell that the visibility prerequisites failing for its player
/// are now these, at time `at_ms`.
pub fn visibility_changed(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  hidden hidden: Set(PrerequisiteId),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.VisibilityChanged(
        unit: map_support.address(number: connection),
        hidden:,
      )),
    ),
  )
}

/// A move of connection `connection` to `x`, at time `at_ms`.
pub fn move(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: Moved(
        unit: map_support.address(number: connection),
        place: at(x),
        seq: at_ms,
      )),
    ),
  )
}

/// A leave of connection `connection`, at time `at_ms`.
pub fn leave(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      CallerId(99),
      Leave(unit: map_support.address(number: connection)),
    )),
  )
}

/// The sweep timer's firing, at time `at_ms`.
pub fn sweep(
  state state: State,
  at_ms at_ms: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(ServiceTimerFired(timer: map.sweep_timer)),
  )
}

/// A connection's tell that a player's use released the unit `unit_id`, at time
/// `at_ms`.
pub fn released(
  state state: State,
  at_ms at_ms: Int,
  unit_id unit_id: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Told(message: map_message.Released(unit_id:))),
  )
}

/// The unit id and life of the creature of the spawn, in any state that runs one.
pub fn creature_of(state state: State, spawn spawn: Int) -> #(Int, Int) {
  case map.spawn_state(state:, spawn: SpawnId(spawn)) {
    Ok(map.Live(unit_id:, life:, ..))
    | Ok(map.Retiring(unit_id:, life:))
    | Ok(map.Respawning(unit_id:, life:))
    | Ok(map.Releasing(unit_id:, life:, ..)) -> #(unit_id, life)
    Ok(map.WaitingForRestart) | Ok(map.Failed) | Error(Nil) ->
      panic as "the spawn holds no creature"
  }
}

/// The relation the map holds between the creature of a spawn and a connection, while the
/// spawn is live or releasing.
pub fn relation_of(
  state state: State,
  spawn spawn: Int,
  connection connection: Int,
) -> Option(map.Relation) {
  case map.spawn_state(state:, spawn: SpawnId(spawn)) {
    Ok(map.Live(relations:, ..)) | Ok(map.Releasing(relations:, ..)) ->
      dict.get(relations, map_support.address(number: connection))
      |> option.from_result
    Ok(map.Retiring(..))
    | Ok(map.Respawning(..))
    | Ok(map.WaitingForRestart)
    | Ok(map.Failed)
    | Error(Nil) -> None
  }
}

/// The generation of the relation the map holds.
pub fn generation_of(
  state state: State,
  spawn spawn: Int,
  connection connection: Int,
) -> Generation {
  let assert Some(map.Relation(generation:, ..)) =
    relation_of(state:, spawn:, connection:)
    as "the map holds the relation"
  generation
}

/// The creatures a step starts, each with the watch it is to be under, in the
/// order named.
pub fn starts(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(step.WatchId, step.CreatureStart)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartCreature(watch:, creature:)) -> Ok(#(watch, creature))
      OwnEffect(step.Register(..))
      | OwnEffect(step.Unregister(..))
      | OwnEffect(Reply(..))
      | OwnEffect(Send(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The first viewers a creature is started for, each by its unit address, in the order
/// the map named them.
pub fn first_viewers(start start: step.CreatureStart) -> List(UnitAddress) {
  list.map(start.viewers, fn(viewer) { viewer.0 })
}

/// The timers a step starts, each with its id's number and its delay.
pub fn timers(taken: ServiceStep(map_message.Outgoing)) -> List(#(Int, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartServiceTimer(timer: step.TimerId(number), after_ms:)) ->
        Ok(#(number, after_ms))
      OwnEffect(step.Register(..))
      | OwnEffect(step.Unregister(..))
      | OwnEffect(Reply(..))
      | OwnEffect(Send(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// What the step sends, to whom, in order.
pub fn sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(step.Address, map_message.Outgoing)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to:, message:)) -> Ok(#(to, message))
      OwnEffect(step.Register(..))
      | OwnEffect(step.Unregister(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// What the step sends to creatures, by the creature's unit id, its life and what it says
/// (`Watched by 1`), in the order sent.
pub fn creatures_told(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, Int, String)) {
  list.filter_map(sends(taken), fn(sent) {
    case sent.0 {
      Creature(unit_id:, life:, ..) -> Ok(#(unit_id, life, said(sent.1)))
      Connection(..)
      | step.Unit(..)
      | step.Sessions
      | step.HandOff
      | step.Store
      | step.Maps
      | step.Map(..)
      | step.CharacterNamed(..)
      | step.ZoneChannel(..) -> Error(Nil)
    }
  })
}

/// What the step sends to creatures, by the creature's unit id and what it says
/// (`Watched by 1`), in the order sent.
pub fn creature_sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  list.map(creatures_told(taken), fn(sent) { #(sent.0, sent.2) })
}

/// What the step tells creatures of the rings, by the creature's unit id and what
/// it says (`Approached by 1`, `Withdrew by 1`), in the order sent.
pub fn ring_sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  creature_sends(taken)
  |> list.filter(fn(sent) {
    case sent.1 {
      "Approached by " <> _ | "Withdrew by " <> _ -> True
      _ -> False
    }
  })
}

/// What the step tells creatures of the rings and of a death, by the creature's unit id
/// and what it says (`Approached by 1`, `PlayerDied by 1`), in the order sent.
pub fn ring_and_death_sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  creature_sends(taken)
  |> list.filter(fn(sent) {
    case sent.1 {
      "Approached by " <> _ | "Withdrew by " <> _ | "PlayerDied by " <> _ ->
        True
      _ -> False
    }
  })
}

/// What the step tells creatures of a death, by the creature's unit id and what it
/// says (`PlayerDied by 1`), in the order sent.
pub fn death_sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  creature_sends(taken)
  |> list.filter(fn(sent) {
    case sent.1 {
      "PlayerDied by " <> _ -> True
      _ -> False
    }
  })
}

/// What the step sends to players' connections, by the connection's number and
/// what it says, in connection order.
pub fn player_sends(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  support.sends(taken)
  |> list.map(fn(sent) { #(sent.0, said(sent.1)) })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

pub fn said(message: map_message.Outgoing) -> String {
  case message {
    map_message.Noticed(notice: map_message.SeenBy(by:, ..)) ->
      "Watched by " <> int.to_string(unit_address.rank(address: by))
    map_message.Noticed(notice: map_message.Gone(unit_id:)) ->
      "Gone " <> int.to_string(unit_id)
    map_message.Noticed(notice: map_message.ObjectsSeen(units:)) ->
      "Objects seen "
      <> string.join(
        list.map(units, fn(unit) {
          int.to_string(static_object.unit_id(created: unit.1))
        }),
        " ",
      )
    map_message.Noticed(notice: map_message.ObjectsUnseen(unit_ids:)) ->
      "Objects unseen " <> string.join(list.map(unit_ids, int.to_string), " ")
    map_message.Noticed(notice: map_message.UnseenBy(by:, ..)) ->
      "Unwatched by " <> int.to_string(unit_address.rank(address: by))
    map_message.Seen(by:, ..) ->
      "Seen by " <> int.to_string(unit_address.rank(address: by))
    map_message.Unseen(by:, ..) ->
      "Unseen by " <> int.to_string(unit_address.rank(address: by))
    map_message.Noticed(notice: map_message.UnitUnseen(unit_id:, ..)) ->
      "Creature unseen " <> int.to_string(unit_id)
    map_message.Noticed(notice: map_message.PlayerUnseen(unit_id:, ..)) ->
      "Player unseen " <> int.to_string(unit_id)
    map_message.Relayed(..) -> "Relayed"
    map_message.Retire -> "Retire"
    map_message.Approached(member: step.RingMember(by:, ..)) ->
      "Approached by " <> int.to_string(unit_address.rank(address: by))
    map_message.Withdrew(by:) ->
      "Withdrew by " <> int.to_string(unit_address.rank(address: by))
    map_message.PlayerDied(by:) ->
      "PlayerDied by " <> int.to_string(unit_address.rank(address: by))
    map_message.CasterGone(by:) ->
      "CasterGone by " <> int.to_string(unit_address.rank(address: by))
    map_message.ToldCreature(by:, payload:) ->
      "Told "
      <> inbound_name(payload)
      <> " by "
      <> int.to_string(unit_address.rank(address: by))
    map_message.Joined(..)
    | map_message.NotJoined(..)
    | map_message.Summoned(..)
    | map_message.NotSummoned(..)
    | map_message.Left -> "an answer"
  }
}

/// A move of connection `connection` to `place`, which holds a facing, at time
/// `at_ms`.
pub fn move_to(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  place place: Place,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: Moved(
        unit: map_support.address(number: connection),
        place:,
        seq: at_ms,
      )),
    ),
  )
}

/// The first 0xF2 of connection `connection`'s client, at time `at_ms`.
pub fn ready(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.Ready(
        unit: map_support.address(number: connection),
        seq: 0,
      )),
    ),
  )
}

/// The connection's tell that its player entered stealth (`stealthed` True) or left
/// it, at time `at_ms`.
pub fn stealth(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  stealthed stealthed: Bool,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.StealthChanged(
        unit: map_support.address(number: connection),
        stealthed:,
      )),
    ),
  )
}

/// The connection's tell that its player died (`alive` False) or woke where its body
/// lies, at time `at_ms`.
pub fn life(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  alive alive: Bool,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.LifeChanged(
        unit: map_support.address(number: connection),
        alive:,
      )),
    ),
  )
}

/// A development summon of Creature2 `creature_id` by connection `connection`'s
/// player, asked by caller `caller`, at time `at_ms`, with no level.
pub fn summon(
  state state: State,
  at_ms at_ms: Int,
  caller caller: Int,
  connection connection: Int,
  creature_id creature_id: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  summon_at_level(
    state:,
    at_ms:,
    caller:,
    connection:,
    creature_id:,
    level: None,
  )
}

/// A development summon as `summon` is, at `level` when there is one.
pub fn summon_at_level(
  state state: State,
  at_ms at_ms: Int,
  caller caller: Int,
  connection connection: Int,
  creature_id creature_id: Int,
  level level: Option(Int),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      caller: CallerId(caller),
      message: map_message.Summon(
        unit: map_support.address(number: connection),
        creature_id: id.Creature2Id(creature_id),
        level:,
      ),
    )),
  )
}

/// The firing of the timer the map starts for the run-only spawn `spawn`: the
/// shell gives it after the summon's start is carried out, and a failure of the
/// start before it.
pub fn start_settled(
  state state: State,
  at_ms at_ms: Int,
  spawn spawn: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(ServiceTimerFired(timer: step.TimerId(spawn))),
  )
}

/// The end of the creature watched under `watch`, at time `at_ms`: its corpse
/// timer's stop, a crash or any other end ends the watch the same way.
pub fn creature_ended(
  state state: State,
  at_ms at_ms: Int,
  watch watch: step.WatchId,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(state:, at_ms:, event: step.WatchEnded(watch:))
}

/// The start of a creature the shell could not carry out, as it gives the rule
/// that, at time `at_ms`.
pub fn creature_not_started(
  state state: State,
  at_ms at_ms: Int,
  watch watch: step.WatchId,
  reason reason: String,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(step.CreatureNotStarted(watch:, reason:)),
  )
}

/// A creature's tell that it lay dead or despawned until its corpse timer and stops now,
/// at time `at_ms`.
pub fn expired(
  state state: State,
  at_ms at_ms: Int,
  unit_id unit_id: Int,
  life life: Int,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Told(message: map_message.Expired(unit_id:, life:))),
  )
}

/// The connections of the players a creature's start carries in its ring, in the order
/// carried.
pub fn ring_of(start start: step.CreatureStart) -> List(Int) {
  list.map(start.ring, fn(member) { unit_address.rank(address: member.by) })
}

/// What the step tells creatures, by the life of the creature told and what it says
/// (`Approached by 1`), in the order sent.
pub fn lives_told(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, String)) {
  list.map(creatures_told(taken), fn(sent) { #(sent.1, sent.2) })
}

/// How many relays to players the step sends.
pub fn relays_sent(taken: ServiceStep(map_message.Outgoing)) -> Int {
  list.count(player_sends(taken), fn(sent) { sent.1 == "Relayed" })
}

/// The name of a player's tell to a creature, as `said` writes it (`Told Strike by 1`).
pub fn inbound_name(payload: map_message.Inbound) -> String {
  case payload {
    map_message.Strike(..) -> "Strike"
    map_message.TargetMoved(..) -> "TargetMoved"
    map_message.StrikeAnswered(..) -> "StrikeAnswered"
    map_message.ModifierStarts(..) -> "ModifierStarts"
    map_message.ModifierEnds(..) -> "ModifierEnds"
    map_message.Thrown(..) -> "Thrown"
    map_message.Despawn(..) -> "Despawn"
    map_message.UnitStates(..) -> "UnitStates"
    map_message.CastViewSet(..) -> "CastViewSet"
    map_message.CastViewEnds(..) -> "CastViewEnds"
    map_message.ControlsEnd(..) -> "ControlsEnd"
  }
}

/// The tell of the player of the unit `from` to the creature `unit_id` of `life`, taken at
/// time `at_ms`.
pub fn tell_creature(
  state state: State,
  at_ms at_ms: Int,
  from from: UnitAddress,
  unit_id unit_id: Int,
  life life: Int,
  payload payload: map_message.Inbound,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.TellCreature(from:, unit_id:, life:, payload:)),
    ),
  )
}

/// The unit id the step's one `Joined` answer gives the player.
pub fn joined_unit_id(taken: ServiceStep(map_message.Outgoing)) -> Int {
  let assert [unit_id] =
    list.filter_map(support.replies(taken), fn(reply) {
      case reply.1 {
        map_message.Joined(unit:, ..) -> Ok(unit.unit_id)
        map_message.NotJoined(..)
        | map_message.Summoned(..)
        | map_message.NotSummoned(..)
        | map_message.Left
        | map_message.Noticed(..)
        | map_message.Seen(..)
        | map_message.Unseen(..)
        | map_message.Relayed(..)
        | map_message.Retire
        | map_message.Approached(..)
        | map_message.Withdrew(..)
        | map_message.PlayerDied(..)
        | map_message.CasterGone(..)
        | map_message.ToldCreature(..) -> Error(Nil)
      }
    })
    as "a join is answered with one Joined"
  unit_id
}
