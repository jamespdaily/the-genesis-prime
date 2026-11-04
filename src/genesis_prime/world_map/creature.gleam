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
//// Watched(by: c, stay) ─▶ viewers + c with its stay; Send(c, CreatureAppeared) ─▶ writes 0x262 once
////                         (every send to c names its stay; c drops one of an earlier stay)
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
////   viewer's connection writes it once, as it does for a player's unit. The
////   second `Watched` names the stay the creature tells that player by from then
////   on (genesis_prime/world_map/stay).
//// - **A stay travels from the message that caused the work.** A strike's answer
////   goes for the stay the strike was told for; the fight holds each player in
////   the stay of the message that put it in the fight (the map's `Approached`, the
////   player's strike) and tells it for that stay; a player's strike or move of a
////   stay other than the one its `Watched` named starts and moves nothing
////   (genesis_prime/world_map/creature_fight).
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
  type Answered, type Fight, type Tell as StrikeTell, Answered, CreatureStriker,
  PlayerStriker, Refused,
}
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, Asked, Connection,
  CreatureNotStarted, Effects, OwnEffect, OwnEvent, Send, ServiceTimerFired,
  Started, Stop, Stopping, TimerId, Told, Watch, WatchEnded, WatchId,
}
import genesis_prime/world_map/creature_fight.{
  type Fighter, AttackTick, Fighter, HomeArrival, StrikeDeadline,
}
import genesis_prime/world_map/creature_kind.{type Kind}
import genesis_prime/world_map/creature_life.{
  type Body, type Life, Body, Died, Ends, Health, StandsAgain, StopAtRespawn,
  StopNow,
}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// The watch on the map run that started the creature.
const run_watch = WatchId(1)

/// The corpse timer. The fight's timers are numbered from it by kind and
/// generation (`timer_id`), so none is 1.
const corpse_timer = TimerId(1)

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
  /// The player of connection `by`, in its stay `stay`, sees the creature.
  Watched(by: ConnectionId, stay: Stay)
  /// The player of connection `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
  /// No player has seen the creature for the idle stop: end.
  Retire
  /// A caster's connection strikes the creature (genesis_prime/game/strike_tell).
  Strike(tell: StrikeTell)
  /// The map: the ready player of connection `by`, unit `unit_id`, in its stay
  /// `stay`, entered the creature's ring at `place`, its connection's move `seq`.
  Approached(by: ConnectionId, unit_id: Int, place: Place, seq: Int, stay: Stay)
  /// The map: the player of connection `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The connection of a player on the creature's threat list: its player, in its
  /// stay `stay`, stands at `place`, its move `seq`.
  TargetMoved(by: ConnectionId, place: Place, seq: Int, stay: Stay)
  /// The connection of a player the creature struck answers the strike.
  StrikeAnswered(answered: Answered)
}

/// What a creature sends a connection without waiting.
pub type Outgoing {
  /// News of the creature's own unit for a viewer, in the viewer's stay `stay`:
  /// its 0x262, 0x355, 0x937, 0x88c and the fight's 0x908, 0x90a, 0x89a, 0x638,
  /// 0x7ff, 0x7f4, 0x7fb and 0x7fe.
  News(stay: Stay, news: PeerNews)
  /// The answer to a strike, for the connection that told it, in the stay the
  /// strike was told for.
  Struck(stay: Stay, answered: Answered)
  /// A tell to the connection of a player in the creature's fight, in the
  /// player's stay `stay`: it threatens or releases the player, or strikes it.
  FightTold(stay: Stay, told: Fight)
}

/// A creature's players in sight, each by its connection with the stay the map
/// named it for, its health, its fight and whether it was told to retire while it
/// lay dead.
pub opaque type State {
  State(
    settings: Settings,
    body: Body,
    life: Life,
    fight: creature_fight.State,
    retiring: Bool,
    viewers: Dict(ConnectionId, Stay),
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
/// and it stands at full health at its spawn, resting.
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
    fight: creature_fight.new(home: settings.spawn.place),
    retiring: False,
    viewers: dict.from_list(settings.creature.viewers),
  )
}

/// The creature's fight: whether it rests, fights or walks home, for a test.
pub fn fight(state state: State) -> creature_fight.State {
  state.fight
}

/// The connections whose players see the creature.
pub fn viewers(state state: State) -> Set(ConnectionId) {
  set.from_list(dict.keys(state.viewers))
}

/// One input in, the new state and what the shell must do out, as the sequence
/// above gives. An input a service's shell never gives a creature is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
  let creature = state.settings.creature
  let now_ms = input.now.monotonic_ms
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
          appeared(state:, viewer:, now_ms:)
        })
      ]),
    )
    OwnEvent(Told(message: Watched(by:, stay:))) -> #(
      State(..state, viewers: dict.insert(state.viewers, by, stay)),
      Effects([
        appeared(state:, viewer: #(by, stay), now_ms:),
        ..list.map(
          creature_fight.arrival_news(state: state.fight, now_ms:),
          fn(news) { news_to(creature:, viewer: #(by, stay), news:) },
        )
      ]),
    )
    OwnEvent(Told(message: Unwatched(by:))) ->
      case dict.get(state.viewers, by) {
        Ok(stay) -> {
          let state = State(..state, viewers: dict.delete(state.viewers, by))
          let #(state, fought) =
            fought(state:, input: creature_fight.Unwatched(by:), now_ms:)
          #(
            state,
            Effects([
              news_to(creature:, viewer: #(by, stay), news: Removed),
              ..fought
            ]),
          )
        }
        Error(Nil) -> #(state, Effects([]))
      }
    OwnEvent(Told(message: Retire)) ->
      case creature_life.on_retire(life: state.life) {
        StopNow -> #(state, Effects([Stop]))
        StopAtRespawn -> #(State(..state, retiring: True), Effects([]))
      }
    OwnEvent(Told(message: Strike(tell:))) -> struck(state:, tell:, now_ms:)
    OwnEvent(Told(message: Approached(by:, unit_id:, place:, seq:, stay:))) ->
      fought_alone(
        state:,
        input: creature_fight.Approached(by:, unit_id:, place:, seq:, stay:),
        now_ms:,
      )
    OwnEvent(Told(message: Withdrew(by:))) ->
      fought_alone(state:, input: creature_fight.Withdrew(by:), now_ms:)
    OwnEvent(Told(message: TargetMoved(by:, place:, seq:, stay:))) ->
      fought_alone(
        state:,
        input: creature_fight.TargetMoved(by:, place:, seq:, stay:),
        now_ms:,
      )
    OwnEvent(Told(message: StrikeAnswered(answered:))) ->
      fought_alone(
        state:,
        input: creature_fight.StrikeAnswered(answered:),
        now_ms:,
      )
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
          let #(state, fought) =
            fought(state:, input: creature_fight.StoodAgain, now_ms:)
          #(
            state,
            Effects(list.append(
              list.flat_map(sorted_viewers(state:), fn(viewer) {
                [
                  news_to(creature:, viewer:, news: Removed),
                  appeared(state:, viewer:, now_ms:),
                ]
              }),
              fought,
            )),
          )
        }
      }
    OwnEvent(ServiceTimerFired(timer:)) ->
      case fight_timer(timer:) {
        Ok(timer) ->
          fought_alone(
            state:,
            input: creature_fight.TimerFired(timer:),
            now_ms:,
          )
        Error(Nil) ->
          panic as "a creature starts no timer but its corpse's and its fight's"
      }
    WatchEnded(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(..)) | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no creature"
  }
}

/// A strike on the creature: refused while it walks home; else the hit rule on its
/// health, the answer first, then the health news, the corpse timer, and the fight's
/// part: a landed player's strike adds its threat, a kill ends the fight.
fn struck(
  state state: State,
  tell tell: StrikeTell,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case creature_fight.refusal(state: state.fight) {
    Error(why) -> #(
      state,
      Effects(answer_to(
        tell:,
        answered: Answered(key: tell.key, outcome: Refused(why:)),
      )),
    )
    Ok(Nil) -> {
      let reaction =
        creature_life.struck(life: state.life, body: state.body, strike: tell)
      // The answer goes first: the caster's connection then knows the strike
      // before it is told the health it left, one sender in one order.
      let answer = answer_to(tell:, answered: reaction.answer)
      let news =
        list.flat_map(reaction.news, fn(news) {
          to_viewers(state:, news: viewer_news(news))
        })
      let corpse = case reaction.corpse_for_ms {
        Some(after_ms) -> [
          OwnEffect(step.StartServiceTimer(timer: corpse_timer, after_ms:)),
        ]
        None -> []
      }
      let state = State(..state, life: reaction.life)
      let input = case
        reaction.answer.outcome,
        tell.striker,
        tell.from,
        reaction.corpse_for_ms
      {
        _, _, _, Some(..) -> Some(creature_fight.Killed)
        strike_tell.Landed(descriptions:),
          PlayerStriker(unit_id:, place:, seq:, stay:, ..),
          Connection(by),
          None
        ->
          Some(creature_fight.StruckBy(
            by:,
            unit_id:,
            place:,
            seq:,
            stay:,
            threat: creature_fight.threat_of(
              offence: tell.offence,
              descriptions:,
            ),
          ))
        _, _, _, None -> None
      }
      let #(state, fought) = case input {
        Some(input) -> fought(state:, input:, now_ms:)
        None -> #(state, [])
      }
      #(state, Effects(list.flatten([answer, news, corpse, fought])))
    }
  }
}

/// The answer to a strike, sent to the caster's connection for the stay the
/// strike was told for: the caster's connection takes it only in that stay. A
/// strike with no player striker has no stay to answer for, and no answer: no
/// creature strikes a creature.
fn answer_to(
  tell tell: StrikeTell,
  answered answered: Answered,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case tell.striker {
    PlayerStriker(stay:, ..) -> [
      OwnEffect(Send(to: tell.from, message: Struck(stay:, answered:))),
    ]
    CreatureStriker -> []
  }
}

/// The creature's fight takes the input, and its effects are the creature's.
fn fought_alone(
  state state: State,
  input input: creature_fight.Input,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, effects) = fought(state:, input:, now_ms:)
  #(state, Effects(effects))
}

/// The fight's step and its effects carried out: news to every viewer, a tell to a
/// player for the stay the fight holds it in, the health restored with its 0x937,
/// and the fight's timers.
fn fought(
  state state: State,
  input input: creature_fight.Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(fight, effects) =
    creature_fight.step(
      state: state.fight,
      fighter: fighter_of(state:),
      viewers: state.viewers,
      alive: !creature_life.is_dead(life: state.life),
      input:,
      now_ms:,
    )
  let state = State(..state, fight:)
  list.fold(effects, #(state, []), fn(so_far, effect) {
    let #(state, done) = so_far
    let #(state, more) = case effect {
      creature_fight.ToViewers(news:) -> #(state, to_viewers(state:, news:))
      creature_fight.ToPlayer(to:, stay:, told:) -> #(state, [
        OwnEffect(Send(to: Connection(to), message: FightTold(stay:, told:))),
      ])
      creature_fight.RestoreHealth -> {
        let life = creature_life.new(body: state.body)
        #(
          State(..state, life:),
          to_viewers(
            state:,
            news: client_connection.Health(
              health: creature_life.health(life:),
              dead: False,
            ),
          ),
        )
      }
      creature_fight.StartTimer(timer:, after_ms:) -> #(state, [
        OwnEffect(step.StartServiceTimer(timer: timer_id(timer:), after_ms:)),
      ])
      creature_fight.CancelTimer(timer:) -> #(state, [
        OwnEffect(step.CancelServiceTimer(timer: timer_id(timer:))),
      ])
    }
    #(state, list.append(done, more))
  })
}

/// What the creature fights with: its unit and address, its spawn as home, its
/// attack, its kind's interval and the run's numbers.
fn fighter_of(state state: State) -> Fighter {
  let creature = state.settings.creature
  Fighter(
    unit_id: creature.unit_id,
    address: step.Creature(
      map: creature.map,
      incarnation: creature.incarnation,
      unit_id: creature.unit_id,
      life: creature.life,
    ),
    home: state.settings.spawn.place,
    attack: state.body.combat.attack,
    interval_ms: state.settings.kind.attack_interval_ms,
    numbers: state.settings.numbers,
  )
}

/// The timer id of a fight timer: 2, 3 and 4 above a multiple of 4 for the attack
/// tick, the strike deadline and the walk home, by generation, so none is the
/// corpse timer's 1 and a timer of an old generation is never the new one's.
fn timer_id(timer timer: creature_fight.Timer) -> step.TimerId {
  case timer {
    AttackTick(generation:) -> TimerId(4 * generation + 2)
    StrikeDeadline(generation:) -> TimerId(4 * generation + 3)
    HomeArrival(generation:) -> TimerId(4 * generation + 4)
  }
}

/// The fight timer of a timer id, or `Error(Nil)` for one the fight never starts.
fn fight_timer(timer timer: step.TimerId) -> Result(creature_fight.Timer, Nil) {
  let TimerId(number) = timer
  case number > 4, number % 4 {
    True, 2 -> Ok(AttackTick(generation: { number - 2 } / 4))
    True, 3 -> Ok(StrikeDeadline(generation: { number - 3 } / 4))
    True, 0 -> Ok(HomeArrival(generation: { number - 4 } / 4))
    _, _ -> Error(Nil)
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
/// its current health and where it stands now: at its spawn, on its path, or where
/// it fell.
fn appeared(
  state state: State,
  viewer viewer: #(ConnectionId, Stay),
  now_ms now_ms: Int,
) -> Effect(ServiceEffect(Outgoing)) {
  let creature = state.settings.creature
  let place = creature_fight.place_at(state: state.fight, now_ms:)
  news_to(
    creature:,
    viewer:,
    news: CreatureAppeared(
      unit: creature_unit.create(
        spawn: Spawn(..state.settings.spawn, place:),
        unit_id: creature.unit_id,
        health: creature_life.health(life: state.life),
        server_time_estimate_start: map.server_time(
          origin_ms: creature.clock_origin_ms,
          monotonic_ms: now_ms,
        ),
      ),
      life: creature.life,
      place:,
      hit_radius: state.body.combat.hit_radius,
      attackable: state.body.combat.attackable,
    ),
  )
}

/// The sends of news about the creature's own unit to every viewer, in the order
/// of their connections.
fn to_viewers(
  state state: State,
  news news: client_connection.News,
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.map(sorted_viewers(state:), fn(viewer) {
    news_to(creature: state.settings.creature, viewer:, news:)
  })
}

/// The viewers, each with its stay, in the order of their connections.
fn sorted_viewers(state state: State) -> List(#(ConnectionId, Stay)) {
  map.sorted_by_connection(state.viewers)
}

/// The send of news about the creature's own unit to a viewer's connection, for
/// the viewer's stay.
fn news_to(
  creature creature: CreatureStart,
  viewer viewer: #(ConnectionId, Stay),
  news news: client_connection.News,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(viewer.0),
    message: News(
      stay: viewer.1,
      news: PeerNews(unit_id: creature.unit_id, news:),
    ),
  ))
}

/// What the map's `Outgoing` means to a creature: `Watched` and `Unwatched`,
/// each by the connection whose player sees or stops seeing it, `Approached` and
/// `Withdrew`, by the connection whose ready player entered or left its ring, and
/// `Retire`. Any other is no message to a creature, and `Error(Nil)`.
pub fn told_by_map(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Watched(by:, stay:) -> Ok(Watched(by:, stay:))
    map.Unwatched(by:) -> Ok(Unwatched(by:))
    map.Approached(by:, unit_id:, place:, seq:, stay:) ->
      Ok(Approached(by:, unit_id:, place:, seq:, stay:))
    map.Withdrew(by:) -> Ok(Withdrew(by:))
    map.Retire -> Ok(Retire)
    map.Joined(..) | map.NotJoined(..) | map.Left | map.Noticed(..) ->
      Error(Nil)
  }
}
