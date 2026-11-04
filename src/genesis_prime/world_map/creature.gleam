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
//// Its state, the players who see it and whether it shows itself, lives only in
//// the process: a crash loses it, and the map, which watches the creature, tells
//// every player the unit is `Gone` and starts the spawn again as another unit.
////
//// From the start to the end of a creature, and what the players in sight are
//// sent:
////
//// ```
//// map                     creature                                    player's connection
////                         Started ─▶ Watch(map run)                   (the shell monitors the run)
////                                    appear_after > 0: StartServiceTimer(appear)
////                                    appear_after = 0: shows itself
//// Watched(by: c) ───────▶ viewers + c; showing: Send(c, CreatureAppeared) ──▶ writes 0x262 once
////                                    not showing yet: nothing
//// Unwatched(by: c) ─────▶ viewers - c; showing and c was a viewer:
////                                    Send(c, Removed) ──────────────────────▶ writes 0x355 if shown
//// the appear timer ─────▶ shows itself: Send(each viewer, CreatureAppeared) ─▶ writes 0x262 once
//// the run's end (WatchEnded) ─▶ Stop                                  (the map is gone: so are its players)
//// ```
////
//// - **Appear.** A creature whose `appear_after_ms` is above 0 stays out of
////   sight until its timer fires, then shows itself to every player who sees it
////   by then. It is how a spawn comes back after its creature crashed
////   (genesis_prime/world_map/map): a creature that crashes in a loop shows
////   itself at most once an `appear_after_ms`.
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
//// | the creature crashes, shown or not | its map's watch ends; the map sends every player `Gone(unit)` and starts the spawn again as a new unit that appears after the respawn time |
//// | the map run ends | the creature's watch on the run ends and it stops |
//// | the creature supervisor restarts | every creature ends and so does every map (genesis_prime/server): the world subtree is `rest_for_one` |
//// | a viewer's connection ends | a send to it is dropped; the map sends `Unwatched`, and the creature forgets it |
//// | a `Watched` or `Unwatched` reaches a creature that has ended | dropped: the registry finds no process |
//// | the appear timer fires after the creature stopped | not possible: the timer lives in the process |

import genesis_prime/client_connection.{type PeerNews}
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type ServiceInput, type ServiceRule,
  type ServiceStep, Asked, CreatureNotStarted, Effects, OwnEvent,
  ServiceTimerFired, Started, Stop, Stopping, Told, WatchEnded,
}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// What a creature is started with: which creature of which run it is, the
/// map's clock and delay (`CreatureStart`), and the spawn it stands at.
pub type Settings {
  Settings(creature: CreatureStart, spawn: Spawn)
}

/// What the map tells a creature.
pub type Message {
  /// The player of connection `by` sees the creature.
  Watched(by: ConnectionId)
  /// The player of connection `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
}

/// A creature's players in sight, and whether it shows itself yet.
pub opaque type State {
  State(settings: Settings, viewers: Set(ConnectionId), showing: Bool)
}

/// The creature's rule, as its service shell runs it.
pub fn rule(
  creature creature: CreatureStart,
  spawn spawn: Spawn,
) -> ServiceRule(Settings, State, Message, PeerNews) {
  step.Rule(name: rule_name, settings: Settings(creature:, spawn:), new:, step:)
}

/// A creature's first state: no viewers, and showing itself when it waits no
/// time.
pub fn new(settings: Settings) -> State {
  State(
    settings:,
    viewers: set.new(),
    showing: settings.creature.appear_after_ms <= 0,
  )
}

/// One input in, the new state and what the shell must do out, as the sequence
/// above gives. An input a service's shell never gives a creature is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(PeerNews)) {
  case input.event {
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Started)
    | OwnEvent(Told(..))
    | OwnEvent(ServiceTimerFired(..))
    | WatchEnded(..) -> panic as "a creature's rule step is not built"
    OwnEvent(Asked(..)) | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no creature"
  }
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
