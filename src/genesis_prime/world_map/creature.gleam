//// One creature: the process that owns a creature's unit in one run of one map,
//// from the time a player first sees its spawn to the time it has gone unseen
//// for the idle stop. It sends the 0x262 and the 0x355 of its own unit to each
//// player who sees it, and owns its health: it takes the strikes a caster's
//// connection tells it, decides what each does (genesis_prime/world_map/creature_life)
//// and sends the 0x937 and 0x88c of its unit, the answer to the caster, and, after
//// its corpse timer, the 0x355 and 0x262 of its respawn. Which players see it, when
//// it starts and when it stops are the map's (genesis_prime/world_map/map), so every
//// message about a unit comes from the unit's owner and a viewer has one sender for
//// each unit.
////
//// This is the rule of a service shell (genesis_prime/service/shell), started
//// by the creature supervisor (genesis_prime/world_map/creature_supervisor)
//// when its map's `StartCreature` effect is carried out, and found by its
//// `Creature` address in the registry (genesis_prime/world_map/creature_registry).
//// Its state, the players who see it, lives only in the process: a crash loses
//// it, and the map, which watches the creature, tells every player the unit is
//// `Gone`, starts the spawn again as another unit after the respawn time if a
//// player sees it then, with those players as its first viewers.
////
//// From the start to the end of a creature, and what the players in sight are
//// sent:
////
//// ```
//// map                     creature                                    player's connection
////                         Started ─▶ Watch(map run)                   (the shell monitors the run)
////                                    for each first viewer c (CreatureStart.viewers):
////                                      Send(c, CreatureAppeared) ───▶ writes 0x262 once
//// Watched(by: c) ───────▶ viewers + c; Send(c, CreatureAppeared) ───▶ writes 0x262 once
//// Unwatched(by: c) ─────▶ viewers - c, if c was a viewer:
////                                    Send(c, Removed) ──────────────▶ writes 0x355 if shown
//// Retire ───────────────▶ Stop                                        (no one sees it: the map sent every
////                                                                      viewer Unwatched, 60 s ago or more)
//// the run's end (WatchEnded) ─▶ Stop                                  (the map is gone: so are its players)
////
//// caster's connection c0
//// Strike(key, c0, striker, offence) ─▶ the hit rule on its health (genesis_prime/world_map/creature_life)
////                                    alive: Send(c0, Struck(Landed | Deflected))   Send(each viewer, Health(h', dead))
////                                    landed: the fight takes StruckBy (genesis_prime/world_map/creature_fight)
////                                    killed: Send(each viewer, Died); StartServiceTimer(corpse, respawn_ms); the fight takes Killed
////                                    dead:  Send(c0, Struck(Refused(Dead)))
////                                    walking home: Send(c0, Struck(Refused(Returning)))
//// Approached(c, unit, place, seq), Withdrew(c) from the map,
//// TargetMoved(c, place, seq), StrikeAnswered(answered) from a connection,
//// the attack tick, the strike deadline, the home timer ─▶ the fight (genesis_prime/world_map/creature_fight)
//// the corpse timer ─────▶ alive again at full health      Send(each viewer, Removed), then CreatureAppeared
////                         told Retire while dead: Stop (no viewer: the spawn's next creature starts full)
//// ```
////
//// - **The unit** is `creature_unit.create(spawn, unit_id, time)`, stamped with
////   the map's server time at the moment it is sent, from the clock origin the
////   map gave (`map.server_time`).
//// - **Retire** is the map's word that no player has seen the creature for the
////   idle stop, so it ends cleanly: the map's watch on it ends, and the spawn is
////   dormant with its unit id kept. A creature takes `Retire` once and has no
////   viewer to tell: its viewers went with their `Unwatched`. A creature that lies
////   dead when told to retire stops at its respawn, since its map keeps the spawn
////   retiring until it ends and a corpse is never shown to a viewer that comes
////   after.
//// - **A strike** is told by the connection of the caster through the creature
////   registry with no watch (genesis_prime/world_map/creature_registry `tell`), and
////   answered by a send to that connection. A strike for a creature that has ended is
////   dropped by the registry and left out at the caster's deadline
////   (genesis_prime/game/strike).
//// - **The corpse timer** is the creature's own, whatever its viewers: it starts at the
////   kill for the kind's respawn time and fires with no viewer too
////   (genesis_prime/world_map/creature_kind).
//// - **The fight** is creature_fight's, whose module holds its sequence from aggro
////   to home and what happens at each of its deadlines; the creature carries out its
////   effects: news to its viewers, tells to the players in the fight
////   (`FightTold`), and its three timers.
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
//// | the creature crashes | its map's watch ends; the map sends every player `Gone(unit)` and starts the spawn again, after the respawn time and only if a player sees it then, as a new unit |
//// | the creature is told `Retire` | it stops, and the map's watch ends; the map takes that as a clean stop |
//// | the creature is told `Retire` while dead | it stops at its respawn, and the map's watch ends then |
//// | the creature is struck while dead | the strike is answered `Refused(Dead)`; no health changes and no news is sent |
//// | two strikes reach it one after the other | each is answered in turn on the health the one before left; the second finds a corpse if the first killed |
//// | the caster's connection has ended when the creature answers | the send is dropped by the registry; the hit and its news stand |
//// | a viewer arrives while the creature is dead | its 0x262 carries health 0, which the client creates dead |
//// | the creature crashes while retiring | the same watch end: the map takes it as a clean stop, since no client shows the unit |
//// | the map run ends | the creature's watch on the run ends and it stops |
//// | the creature supervisor restarts | every creature ends and so does every map (genesis_prime/server): the world subtree is `rest_for_one` |
//// | a viewer's connection ends | a send to it is dropped; the map sends `Unwatched`, and the creature forgets it |
//// | a `Watched` or `Unwatched` reaches a creature that has ended | dropped: the registry finds no process |

import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight, type Tell as StrikeTell,
}
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, Asked, Connection,
  CreatureNotStarted, Effects, OwnEffect, OwnEvent, Send, ServiceTimerFired,
  Started, Stop, Stopping, TimerId, Told, Watch, WatchEnded, WatchId,
}
import genesis_prime/world_map/creature_fight
import genesis_prime/world_map/creature_kind.{type Kind}
import genesis_prime/world_map/creature_life.{
  type Body, type Life, Body, Died, Ends, Health, StandsAgain, StopAtRespawn,
  StopNow,
}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// The watch on the map run that started the creature.
const run_watch = WatchId(1)

/// The corpse timer.
const corpse_timer = TimerId(1)

/// The fight's attack tick (genesis_prime/world_map/creature_fight).
const attack_timer = TimerId(2)

/// The fight's strike deadline.
const strike_deadline_timer = TimerId(3)

/// The fight's walk home.
const home_timer = TimerId(4)

/// What a creature is started with: which creature of which run it is and the
/// map's clock (`CreatureStart`), the spawn it stands at, found by the id the start
/// names, the kind the server chose for its Creature2 row, and the run's game
/// numbers.
pub type Settings {
  Settings(
    creature: CreatureStart,
    spawn: Spawn,
    kind: Kind,
    numbers: GameNumbers,
  )
}

/// What the map and the connections tell a creature.
pub type Message {
  /// The player of connection `by` sees the creature.
  Watched(by: ConnectionId)
  /// The player of connection `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
  /// No player has seen the creature for the idle stop: end.
  Retire
  /// A caster's connection strikes the creature (genesis_prime/game/strike_tell).
  Strike(tell: StrikeTell)
  /// The map: the ready player of connection `by`, unit `unit_id`, entered the
  /// creature's ring at `place`, its connection's move `seq`.
  Approached(by: ConnectionId, unit_id: Int, place: Place, seq: Int)
  /// The map: the player of connection `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The connection of a player on the creature's threat list: its player
  /// stands at `place`, its move `seq`.
  TargetMoved(by: ConnectionId, place: Place, seq: Int)
  /// The connection of a player the creature struck answers the strike.
  StrikeAnswered(answered: Answered)
}

/// What a creature sends a connection without waiting.
pub type Outgoing {
  /// News of the creature's own unit for a viewer: its 0x262, 0x355, 0x937 and
  /// 0x88c.
  News(news: PeerNews)
  /// The answer to a strike, for the connection that told it.
  Struck(answered: Answered)
  /// A tell to the connection of a player in the creature's fight: it threatens
  /// or releases the player, or strikes it.
  FightTold(told: Fight)
}

/// A creature's players in sight, its health, its fight and whether it was told
/// to retire while it lay dead.
pub opaque type State {
  State(
    settings: Settings,
    body: Body,
    life: Life,
    fight: creature_fight.State,
    retiring: Bool,
    viewers: Set(ConnectionId),
  )
}

/// The creature's rule, as its service shell runs it.
pub fn rule(
  creature creature: CreatureStart,
  spawn spawn: Spawn,
  kind kind: Kind,
  numbers numbers: GameNumbers,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(creature:, spawn:, kind:, numbers:),
    new:,
    step:,
  )
}

/// A creature's first state: the players the map started it for are its viewers,
/// and it stands at full health.
pub fn new(settings: Settings) -> State {
  let body =
    Body(
      max_health: settings.spawn.health,
      combat: settings.spawn.combat,
      respawn_ms: settings.kind.respawn_ms,
    )
  State(
    settings:,
    body:,
    life: creature_life.new(body:),
    fight: creature_fight.new(),
    retiring: False,
    viewers: set.from_list(settings.creature.viewers),
  )
}

/// One input in, the new state and what the shell must do out, as the sequence
/// above gives. An input a service's shell never gives a creature is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
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
        ..list.map(creature.viewers, fn(viewer) {
          appeared(state:, viewer:, now: input.now)
        })
      ]),
    )
    OwnEvent(Told(message: Watched(by:))) -> #(
      State(..state, viewers: set.insert(state.viewers, by)),
      Effects([appeared(state:, viewer: by, now: input.now)]),
    )
    OwnEvent(Told(message: Unwatched(by:))) ->
      case set.contains(state.viewers, by) {
        True -> #(
          State(..state, viewers: set.delete(state.viewers, by)),
          Effects([news_to(creature:, viewer: by, news: Removed)]),
        )
        False -> #(state, Effects([]))
      }
    OwnEvent(Told(message: Retire)) ->
      case creature_life.on_retire(life: state.life) {
        StopNow -> #(state, Effects([Stop]))
        StopAtRespawn -> #(State(..state, retiring: True), Effects([]))
      }
    OwnEvent(Told(message: Strike(tell:))) -> {
      let reaction =
        creature_life.struck(life: state.life, body: state.body, strike: tell)
      // The answer goes first: the caster's connection then knows the strike
      // before it is told the health it left, one sender in one order.
      let answer =
        OwnEffect(Send(
          to: tell.from,
          message: Struck(answered: reaction.answer),
        ))
      let news =
        list.flat_map(reaction.news, fn(news) {
          list.map(map.sorted_connections(state.viewers), fn(viewer) {
            news_to(creature:, viewer:, news: viewer_news(news))
          })
        })
      let corpse = case reaction.corpse_for_ms {
        Some(after_ms) -> [
          OwnEffect(step.StartServiceTimer(timer: corpse_timer, after_ms:)),
        ]
        None -> []
      }
      #(
        State(..state, life: reaction.life),
        Effects(list.flatten([[answer], news, corpse])),
      )
    }
    OwnEvent(ServiceTimerFired(timer:)) if timer == corpse_timer ->
      case
        creature_life.corpse_timer_fired(
          life: state.life,
          body: state.body,
          retiring: state.retiring,
        )
      {
        Ends -> #(state, Effects([Stop]))
        StandsAgain(life:) -> {
          let state = State(..state, life:)
          #(
            state,
            Effects(
              list.flat_map(map.sorted_connections(state.viewers), fn(viewer) {
                [
                  news_to(creature:, viewer:, news: Removed),
                  appeared(state:, viewer:, now: input.now),
                ]
              }),
            ),
          )
        }
      }
    OwnEvent(Told(message: Approached(..)))
    | OwnEvent(Told(message: Withdrew(..)))
    | OwnEvent(Told(message: TargetMoved(..)))
    | OwnEvent(Told(message: StrikeAnswered(..))) ->
      todo as "the fight's messages: the build carries them to creature_fight"
    OwnEvent(ServiceTimerFired(timer:))
      if timer == attack_timer
      || timer == strike_deadline_timer
      || timer == home_timer
    -> todo as "the fight's timers: the build carries them to creature_fight"
    WatchEnded(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(..))
    | OwnEvent(ServiceTimerFired(..))
    | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no timer but its corpse's and its fight's, and no creature"
  }
}

/// What a viewer's connection writes of a news of the creature's health.
fn viewer_news(news: creature_life.News) -> client_connection.News {
  case news {
    Health(health:, dead:) -> client_connection.Health(health:, dead:)
    Died -> client_connection.Died
  }
}

/// The send of the creature's 0x262 to a viewer, stamped with the map's time, at
/// its current health.
fn appeared(
  state state: State,
  viewer viewer: ConnectionId,
  now now: step.Now,
) -> Effect(ServiceEffect(Outgoing)) {
  let creature = state.settings.creature
  news_to(
    creature:,
    viewer:,
    news: CreatureAppeared(
      unit: creature_unit.create(
        spawn: state.settings.spawn,
        unit_id: creature.unit_id,
        health: creature_life.health(life: state.life),
        server_time_estimate_start: map.server_time(
          origin_ms: creature.clock_origin_ms,
          monotonic_ms: now.monotonic_ms,
        ),
      ),
      life: creature.life,
      place: state.settings.spawn.place,
      hit_radius: state.body.combat.hit_radius,
      attackable: state.body.combat.attackable,
    ),
  )
}

/// The send of news about the creature's own unit to a viewer's connection.
fn news_to(
  creature creature: CreatureStart,
  viewer viewer: ConnectionId,
  news news: client_connection.News,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(viewer),
    message: News(PeerNews(
      map: creature.map,
      incarnation: creature.incarnation,
      unit_id: creature.unit_id,
      news:,
    )),
  ))
}

/// What the map's `Outgoing` means to a creature: `Watched` and `Unwatched`,
/// each by the connection whose player sees or stops seeing it, `Approached` and
/// `Withdrew`, by the connection whose ready player entered or left its ring, and
/// `Retire`. Any other is no message to a creature, and `Error(Nil)`.
pub fn told_by_map(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Watched(by:) -> Ok(Watched(by:))
    map.Unwatched(by:) -> Ok(Unwatched(by:))
    map.Approached(by:, unit_id:, place:, seq:) ->
      Ok(Approached(by:, unit_id:, place:, seq:))
    map.Withdrew(by:) -> Ok(Withdrew(by:))
    map.Retire -> Ok(Retire)
    map.Joined(..) | map.NotJoined(..) | map.Left | map.Gone(..) -> Error(Nil)
  }
}
