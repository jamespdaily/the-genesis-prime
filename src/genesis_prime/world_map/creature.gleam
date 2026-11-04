//// One creature: the process that owns a creature's unit in one run of one map.
//// It sends the 0x262 and the 0x355 of its own unit to each player who sees it
//// and decides nothing else: which players see it is the map's (genesis_prime/
//// world_map/map), so every message about a unit comes from the unit's owner
//// and a viewer has one sender for each unit.
////
//// This is the rule of a service shell (genesis_prime/service/shell), started
//// by the creature supervisor (genesis_prime/world_map/creature_supervisor)
//// when its map's `StartCreature` effect is carried out, and found by its
//// `Creature` address in the registry (genesis_prime/world_map/creature_registry).
//// Its state, the players who see it, lives only in the process: a crash loses
//// it, and the map, which watches the creature, tells every player the unit is
//// `Gone`, starts the spawn again as another unit after the respawn time, and
//// tells the new creature who sees it.
////
//// From the start to the end of a creature, and what the players in sight are
//// sent:
////
//// ```
//// map                     creature                                    player's connection
////                         Started ─▶ Watch(map run)                   (the shell monitors the run)
//// Watched(by: c) ───────▶ viewers + c; Send(c, CreatureAppeared) ───▶ writes 0x262 once
//// Unwatched(by: c) ─────▶ viewers - c, if c was a viewer:
////                                    Send(c, Removed) ──────────────▶ writes 0x355 if shown
//// the run's end (WatchEnded) ─▶ Stop                                  (the map is gone: so are its players)
//// ```
////
//// - **The unit** is `creature_unit.create(spawn, unit_id, time)`, stamped with
////   the map's server time at the moment it is sent, from the clock origin the
////   map gave (`map.server_time`).
//// - **A viewer that is not a connection any more** is dropped by the send (the
////   registry finds no process); the map's `Unwatched` follows from its end.
//// - **A `Watched` twice from one connection** sends the 0x262 twice; the
////   viewer's connection writes it once, as it does for a player's unit.
//// - **The map run's end** ends the creature: it watches the run by the pid the
////   run gave when it started the creature, not through Maps, which is waiting
////   on the run's start while the run starts its creatures.
////
//// What happens at each failure point of a creature:
////
//// | Point | What happens |
//// |---|---|
//// | the creature crashes | its map's watch ends; the map sends every player `Gone(unit)` and starts the spawn again, after the respawn time, as a new unit |
//// | the map run ends | the creature's watch on the run ends and it stops |
//// | the creature supervisor restarts | every creature ends and so does every map (genesis_prime/server): the world subtree is `rest_for_one` |
//// | a viewer's connection ends | a send to it is dropped; the map sends `Unwatched`, and the creature forgets it |
//// | a `Watched` or `Unwatched` reaches a creature that has ended | dropped: the registry finds no process |

import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, Asked, Connection,
  CreatureNotStarted, Effects, OwnEffect, OwnEvent, Send, ServiceTimerFired,
  Started, Stop, Stopping, Told, Watch, WatchEnded, WatchId,
}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// The watch on the map run that started the creature.
const run_watch = WatchId(1)

/// What a creature is started with: which creature of which run it is, the
/// spawn it stands at and the map's clock (`CreatureStart`).
pub type Settings {
  Settings(creature: CreatureStart)
}

/// What the map tells a creature.
pub type Message {
  /// The player of connection `by` sees the creature.
  Watched(by: ConnectionId)
  /// The player of connection `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
}

/// A creature's players in sight.
pub opaque type State {
  State(settings: Settings, viewers: Set(ConnectionId))
}

/// The creature's rule, as its service shell runs it.
pub fn rule(
  creature creature: CreatureStart,
) -> ServiceRule(Settings, State, Message, PeerNews) {
  step.Rule(name: rule_name, settings: Settings(creature:), new:, step:)
}

/// A creature's first state: no viewers.
pub fn new(settings: Settings) -> State {
  State(settings:, viewers: set.new())
}

/// One input in, the new state and what the shell must do out, as the sequence
/// above gives. An input a service's shell never gives a creature is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(PeerNews)) {
  let creature = state.settings.creature
  case input.event {
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Started) -> #(
      state,
      Effects([
        Watch(
          watch: run_watch,
          target: step.Map(map: creature.map, incarnation: creature.incarnation),
        ),
      ]),
    )
    OwnEvent(Told(message: Watched(by:))) -> {
      let unit =
        creature_unit.create(
          spawn: creature.spawn,
          unit_id: creature.unit_id,
          server_time_estimate_start: map.server_time(
            origin_ms: creature.clock_origin_ms,
            monotonic_ms: input.now.monotonic_ms,
          ),
        )
      #(
        State(..state, viewers: set.insert(state.viewers, by)),
        Effects([news_to(creature:, viewer: by, news: CreatureAppeared(unit:))]),
      )
    }
    OwnEvent(Told(message: Unwatched(by:))) ->
      case set.contains(state.viewers, by) {
        True -> #(
          State(..state, viewers: set.delete(state.viewers, by)),
          Effects([news_to(creature:, viewer: by, news: Removed)]),
        )
        False -> #(state, Effects([]))
      }
    WatchEnded(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(..))
    | OwnEvent(ServiceTimerFired(..))
    | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no timer and no creature"
  }
}

/// The send of news about the creature's own unit to a viewer's connection.
fn news_to(
  creature creature: CreatureStart,
  viewer viewer: ConnectionId,
  news news: client_connection.News,
) -> Effect(ServiceEffect(PeerNews)) {
  OwnEffect(Send(
    to: Connection(viewer),
    message: PeerNews(
      map: creature.map,
      incarnation: creature.incarnation,
      unit_id: creature.unit_id,
      news:,
    ),
  ))
}

/// What the map's `Outgoing` means to a creature: `Watched` and `Unwatched`,
/// each by the connection whose player sees or stops seeing it. Any other is no
/// message to a creature, and `Error(Nil)`.
pub fn told_by_map(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Watched(by:) -> Ok(Watched(by:))
    map.Unwatched(by:) -> Ok(Unwatched(by:))
    map.Joined(..) | map.Left | map.Gone(..) -> Error(Nil)
  }
}
