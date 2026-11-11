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
//// the run's end (WatchEnded(run)) ─▶ Stop                             (the map is gone: so are its players)
////
//// caster's connection c0
//// Strike(key, c0, striker, offence) ─▶ the hit rule on its health (genesis_prime/world_map/creature_life)
////                                    alive: Send(c0, Struck(Landed | Deflected))   Send(each viewer, Health(h', dead))
////                                    landed: the fight takes StruckBy (genesis_prime/world_map/creature_fight)
////                                    killed: Send(each viewer, Died); StartServiceTimer(corpse, respawn_ms); the fight takes Killed
////                                            Send(c0, KillCredit(unit, creature row, faction, level)), once, for the blow that killed it
////                                    dead:  Send(c0, Struck(Refused(Dead)))
////                                    walking home: Send(c0, Struck(Refused(Returning)))
//// Approached(c, unit, place, seq), Withdrew(c), PlayerDied(c) from the map,
//// TargetMoved(c, place, seq), StrikeAnswered(answered) from a connection,
//// the attack tick, the cast end of a charge, the strike deadline, the home timer ─▶ the fight (genesis_prime/world_map/creature_fight)
//// the corpse timer ─────▶ alive again at full health, properties from the bases, every source cleared,
////                         stood_again_ms = now
////                                                         Send(each viewer, Removed), then CreatureAppeared
////                         told Retire while dead: Stop (no viewer: the spawn's next creature starts full)
////
//// caster's connection c0, a property modifier of its spell, for the life the go struck
//// ModifierStarts(c0, source, m, struck_at_ms)
////                         dead, or struck_at_ms < stood_again_ms: dropped
////                         else ─▶ apply(source, m) to its properties (genesis_prime/game/unit_properties)
////                                    Send(each viewer, PropertiesChanged(changed entries)) ─▶ writes 0x93a if shown
////                                    the rules take the new values: run speed, defence, offence,
////                                    maximum health, Interrupt Armor's maximum
////                                    c0's first modifier: Watch(c0's watch, Connection(c0))
//// ModifierEnds(source) ─────────▶ remove(source)          Send(each viewer, PropertiesChanged(changed entries))
//// c0's watch ends (WatchEnded) ─▶ remove every source of c0, each as ModifierEnds does
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
//// - **A strike's crowd-control states** land after its damage, on a creature that
////   lives and whose Interrupt Armor is already 0 (a strike on armor above 0 wears it down
////   instead), and the answer's `Landed` names the ones that did; while the creature holds one it does not act
////   (genesis_prime/world_map/creature_control).
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
////   (`FightTold`), and its four timers: the attack tick, the cast end of a charge, the strike
////   deadline and the walk home. An attack with a cast time (`Kind.cast_ms` above 0, the
////   Sim-Turrets') is a charge: the fight opens it on an attack tick and carries it out as
////   the 0x7ff, the `CastEnds` timer, the strikes to the fighters inside its rectangle and the
////   go, with no movement of the unit (`Fighter.stationary`); the creature takes no message for
////   it beyond its own timer.
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
//// - **A property modifier** of a player's spell is told by the caster's connection
////   through the creature registry with no watch, as a strike is; the caster's cast owns
////   its time and the creature owns the values and every rule that reads them. A
////   respawn keeps the process and its registry address, so the address does not fence
////   it: a start carries the monotonic time of the go that struck, and the creature
////   drops a start struck before it last stood again, or one that reaches it
////   dead. An end needs no fence, since a respawn clears every source. A modifier on
////   another player, and stacking across casters, are not handled here.
//// - **Only the run's watch stops the creature.** Each caster's connection whose
////   modifier the creature holds is watched under its own id, from 2 on, and its end
////   takes that caster's modifiers off.
//// - **The map run's end** ends the creature: it watches the run by the pid the
////   run gave when it started the creature, not through Maps, which is waiting
////   on the run's start while the run starts its creatures.
////
//// What happens at each failure point of a creature:
////
//// | Point | What happens |
//// |---|---|
//// | the creature crashes | its map's watch ends; the map sends every player `Gone(unit)` and starts the spawn again, after the respawn time and only if a player sees it then, as a new unit |
//// | the creature crashes while it charges | the same: its `CastEnds` timer goes with the process, no 0x7fe is sent, and the map's `Gone` removes the unit from each viewer |
//// | the creature dies while it charges | the fight cancels the `CastEnds` timer and finishes the cast (0x7fe); the corpse timer starts as for any kill (`death_during_a_charge_ends_it_test`) |
//// | a `CastEnds` fires after its charge ended | the fight finds no charge of that generation and does nothing (`a_stale_cast_end_does_nothing_test`) |
//// | the creature is told `Retire` | it stops, and the map's watch ends; the map takes that as a clean stop |
//// | the creature is told `Retire` while dead | it stops at its respawn, and the map's watch ends then |
//// | the creature is struck while dead | the strike is answered `Refused(Dead)`; no health changes and no news is sent |
//// | two strikes reach it one after the other | each is answered in turn on the health the one before left; the second finds a corpse if the first killed |
//// | the caster's connection has ended when the creature answers | the send is dropped by the registry; the hit and its news stand |
//// | the killing blow's caster has left the world, or its stay has changed, when the credit arrives | the connection drops the credit (`stay_sent`): no experience is given, the death and its news stand |
//// | a second strike reaches the creature after the killing one | it finds a corpse and is answered `Refused(Dead)`; it sends no credit, so a kill is credited once |
//// | a viewer arrives while the creature is dead | its 0x262 carries health 0, which the client creates dead |
//// | the creature crashes while retiring | the same watch end: the map takes it as a clean stop, since no client shows the unit |
//// | the map run ends | the creature's watch on the run ends and it stops |
//// | the creature supervisor restarts | every creature ends and so does every map (genesis_prime/server): the world subtree is `rest_for_one` |
//// | a viewer's connection ends | a send to it is dropped; the map sends `Unwatched`, and the creature forgets it |
//// | a `Watched` or `Unwatched` reaches a creature that has ended | dropped: the registry finds no process |
//// | the creature crashes while it holds a modifier | the map starts the spawn again as a new unit with no modifier; the caster's later `ModifierEnds` is dropped by the registry |
//// | the same source starts twice | it is held once |
//// | a `ModifierStarts` struck before the creature last stood again reaches it | dropped: it was struck on the life before |
//// | a `ModifierStarts` reaches the creature while it is dead | dropped |
//// | a `ModifierStarts` or `ModifierEnds` reaches a creature that has ended | dropped: the registry finds no process |
//// | the caster's connection ends before a modifier's end | the creature's watch on it ends, and it removes every source of that caster |
//// | a `ModifierEnds` comes twice, or for a source not held | it changes nothing |
//// | the caster dies | its casts finish, and each modifier they hold on a creature ends |
//// | the creature dies while it holds a modifier | the modifier stays held and no rule reads it; its end still removes it |
//// | the creature respawns | its properties start again from the bases and every source is cleared; a later `ModifierEnds` for a cleared source changes nothing |
//// | a viewer arrives while a modifier lasts | its 0x262 carries the current value (`unit_properties.overlay`) |
//// | a modifier lowers the interrupt armor maximum below the armor the creature wears | the worn armor is clamped to the new maximum and the viewers are sent 0x938 of it |
//// | a modifier raises or lowers the interrupt armor maximum of a creature at full armor | the armor stays full at the new maximum and the viewers are sent 0x938 of it |
//// | a modifier raises the interrupt armor maximum of a creature that wears armor down | the armor it wears stays, and no 0x938 is sent |

import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight, type Tell as StrikeTell, Answered, CreatureStriker,
  PlayerStriker, Refused,
}
import genesis_prime/game/unit_properties.{
  type Modifier, type Properties, type Source,
}
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, CreatureNotStarted, Effects, OwnEffect, OwnEvent, Send,
  ServiceTimerFired, Started, Stop, Stopping, TimerId, Told, Watch, WatchEnded,
  WatchId,
}
import genesis_prime/table/id.{type Creature2Id, type Faction2Id, Faction2Id}
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_fight.{
  type Fighter, AttackTick, CastEnds, Fighter, HomeArrival, StrikeDeadline,
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
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// The watch on the map run that started the creature: the only watch whose end stops
/// it.
const run_watch = WatchId(1)

/// The id of the first watch on a caster's connection; each later one takes the next.
const first_caster_watch = 2

/// The corpse timer. The fight's timers are numbered from it by kind and
/// generation (`timer_id`), so none is 1.
const corpse_timer = TimerId(1)

/// The timer of the creature's Interrupt Armor refill: 2, which no fight timer is (they
/// start at 5) and no control's (they start at 9).
const refill_timer = TimerId(2)

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
  /// The map: the player of connection `by` died, so it leaves the creature's ring's
  /// players and its threat list.
  PlayerDied(by: ConnectionId)
  /// The connection of a player on the creature's threat list: its player, in its
  /// stay `stay`, stands at `place`, its move `seq`.
  TargetMoved(by: ConnectionId, place: Place, seq: Int, stay: Stay)
  /// The connection of a player the creature struck answers the strike.
  StrikeAnswered(answered: Answered)
  /// The connection `by` of a caster: a property modifier of its spell starts on the
  /// creature, struck by a go at the monotonic time `struck_at_ms`. It is dropped when
  /// the creature has stood again since then, or lies dead: a respawn keeps the
  /// registry address, so the address does not tell the lives apart.
  ModifierStarts(
    by: ConnectionId,
    source: Source,
    modifier: Modifier,
    struck_at_ms: Int,
  )
  /// A caster's connection: the property modifier of `source` ends on the creature.
  ModifierEnds(source: Source)
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
  /// The credit for a kill, for the connection of the player whose blow killed the
  /// creature, in the stay the killing strike was told for: the creature's unit, its
  /// Creature2 row, its Faction2 (its spawn row's) and its level. Sent once per death,
  /// after the strike's answer (genesis_prime/game/experience).
  KillCredit(
    stay: Stay,
    unit_id: Int,
    creature_id: Creature2Id,
    faction_id: Faction2Id,
    level: Int,
  )
}

/// A creature's players in sight, each by its connection with the stay the map
/// named it for, its health, its fight, the crowd-control states it holds, whether
/// it was told to retire while it lay dead, its properties with the modifiers of
/// players' spells on them, the watch on each caster's connection whose modifiers it
/// holds, the caster's connection of each modifier's source in the order the
/// modifiers started, the id its next watch on a caster's connection takes, and the
/// monotonic time it last stood again (none in its first life).
pub opaque type State {
  State(
    settings: Settings,
    body: Body,
    life: Life,
    fight: creature_fight.State,
    control: creature_control.State,
    retiring: Bool,
    viewers: Dict(ConnectionId, Stay),
    properties: Properties,
    casters: Dict(ConnectionId, WatchId),
    held_by: List(#(Source, ConnectionId)),
    next_watch: Int,
    stood_again_ms: Option(Int),
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
  let body = base_body(settings:)
  State(
    settings:,
    body:,
    life: creature_life.new(body:),
    fight: creature_fight.new(home: settings.spawn.place),
    control: creature_control.new(),
    retiring: False,
    viewers: dict.from_list(settings.creature.viewers),
    properties: base_properties(settings:),
    casters: dict.new(),
    held_by: [],
    next_watch: first_caster_watch,
    stood_again_ms: None,
  )
}

/// What the creature brings to a fight with no modifier held: the spawn's health and
/// combat values.
fn base_body(settings settings: Settings) -> Body {
  Body(
    max_health: settings.spawn.health,
    combat: settings.spawn.combat,
    respawn_ms: settings.kind.respawn_ms,
  )
}

/// The creature's properties with no modifier held: the spawn's bases, and for a spawn
/// whose health is recorded, Base Health (property 7) at that health, which is the
/// maximum the client holds for it (`creature_unit`).
fn base_properties(settings settings: Settings) -> Properties {
  let spawn = settings.spawn
  let bases = case spawn.health_source {
    unit_fields.Recorded ->
      list.key_set(
        spawn.bases,
        unit_properties.base_health,
        int.to_float(spawn.health),
      )
    unit_fields.ClientDefault -> spawn.bases
  }
  unit_properties.of_creature(bases:, level: spawn.level)
}

/// The creature's fight: whether it rests, fights or walks home, for a test.
pub fn fight(state state: State) -> creature_fight.State {
  state.fight
}

/// Whether the creature holds a crowd-control state, for a test.
pub fn controlled(state state: State) -> Bool {
  creature_control.holds(state: state.control)
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
  let run_only = spawn_source.is_run_only(creature.spawn)
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
    OwnEvent(Told(message: PlayerDied(by:))) ->
      fought_alone(state:, input: creature_fight.PlayerDied(by:), now_ms:)
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
    OwnEvent(ServiceTimerFired(timer:)) if timer == corpse_timer && run_only -> #(
      state,
      Effects(
        list.append(
          list.map(sorted_viewers(state:), fn(viewer) {
            news_to(creature:, viewer:, news: Removed)
          }),
          [Stop],
        ),
      ),
    )
    OwnEvent(ServiceTimerFired(timer:)) if timer == corpse_timer ->
      case
        creature_life.corpse_timer_fired(
          life: state.life,
          body: base_body(settings: state.settings),
          retiring: state.retiring,
        )
      {
        Ends -> #(state, Effects([Stop]))
        StandsAgain(life:) -> {
          let #(state, unwatched) =
            stood_again(state: State(..state, life:), now_ms:)
          let #(state, fought) =
            fought(state:, input: creature_fight.StoodAgain, now_ms:)
          #(
            state,
            Effects(
              list.flatten([
                unwatched,
                list.flat_map(sorted_viewers(state:), fn(viewer) {
                  [
                    news_to(creature:, viewer:, news: Removed),
                    appeared(state:, viewer:, now_ms:),
                  ]
                }),
                fought,
              ]),
            ),
          )
        }
      }
    OwnEvent(ServiceTimerFired(timer:)) if timer == refill_timer -> {
      let #(control, effects) =
        creature_control.refilled(
          state: state.control,
          armor: state.body.combat.interrupt_armor,
        )
      let state = State(..state, control:)
      #(state, Effects(carried(state:, effects:)))
    }
    OwnEvent(ServiceTimerFired(timer:)) ->
      case control_of(timer:), fight_timer(timer:) {
        Ok(number), _ -> control_ended(state:, number:, now_ms:)
        Error(Nil), Ok(timer) ->
          fought_alone(
            state:,
            input: creature_fight.TimerFired(timer:),
            now_ms:,
          )
        Error(Nil), Error(Nil) ->
          panic as "a creature starts no timer but its corpse's, its armor refill's, its fight's and its controls'"
      }
    OwnEvent(Told(message: ModifierStarts(
      by:,
      source:,
      modifier:,
      struck_at_ms:,
    ))) ->
      modifier_started(state:, by:, source:, modifier:, struck_at_ms:, now_ms:)
    OwnEvent(Told(message: ModifierEnds(source:))) ->
      modifier_ended(state:, source:, now_ms:)
    WatchEnded(watch:) if watch == run_watch -> #(state, Effects([Stop]))
    WatchEnded(watch:) -> caster_gone(state:, watch:, now_ms:)
    OwnEvent(Asked(..)) | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no creature"
  }
}

/// A property modifier of the caster of connection `by` starts on the creature: it is
/// applied to the creature's properties, the entries that changed go to every viewer as
/// `PropertiesChanged`, the rules that read a changed property take its new value,
/// and the caster's connection is watched from its first modifier on. The same source
/// twice is held once. A start struck before the creature last stood again, or one that
/// reaches it dead, changes nothing.
fn modifier_started(
  state state: State,
  by by: ConnectionId,
  source source: Source,
  modifier modifier: Modifier,
  struck_at_ms struck_at_ms: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let struck_before_this_life = case state.stood_again_ms {
    Some(stood_ms) -> struck_at_ms < stood_ms
    None -> False
  }
  case
    creature_life.is_dead(life: state.life)
    || struck_before_this_life
    || result.is_ok(list.key_find(state.held_by, source))
  {
    True -> #(state, Effects([]))
    False -> {
      let #(properties, changed) =
        unit_properties.apply(properties: state.properties, source:, modifier:)
      let state =
        State(..state, held_by: list.append(state.held_by, [#(source, by)]))
      let #(state, watching) = watching(state:, by:)
      let news = changed_news(state:, changed:)
      let #(state, revalued) = revalued(state:, properties:, now_ms:)
      #(state, Effects(list.flatten([watching, news, revalued])))
    }
  }
}

/// The creature stands again at `now_ms`: it holds no source from its life before, its
/// body and properties are the spawn's again, and a start struck before now is
/// dropped. The effects drop the watch on each caster whose modifiers it cleared. The
/// viewers are sent the creature as new, whose 0x262 lists none of them.
fn stood_again(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let unwatched =
    list.unique(list.map(state.held_by, fn(held) { held.1 }))
    |> list.filter_map(fn(by) {
      dict.get(state.casters, by)
      |> result.map(fn(watch) { step.Unwatch(watch:) })
    })
  #(
    State(
      ..state,
      body: base_body(settings: state.settings),
      properties: base_properties(settings: state.settings),
      casters: dict.new(),
      held_by: [],
      stood_again_ms: Some(now_ms),
    ),
    unwatched,
  )
}

/// The creature's properties are now `properties`: its body's combat values and
/// maximum health follow them (`spawn.values_of`). A health above the new maximum
/// falls to it, with a 0x937 for the viewers; a lower maximum that is raised again
/// adds none. An Interrupt Armor maximum that changed goes to the controls, which keep
/// the armor in use and the viewers' stat 21 one value. A run speed that changed goes
/// to the fight, which runs on the path it holds at the new speed. The property news is
/// the caller's.
fn revalued(
  state state: State,
  properties properties: Properties,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let values = spawn.values_of(spawn: state.settings.spawn, properties:)
  let run_speed_before = state.body.combat.attack.run_speed
  let health_before = creature_life.health(life: state.life)
  let body =
    Body(..state.body, max_health: values.max_health, combat: values.combat)
  let life =
    creature_life.clamped(life: state.life, max_health: body.max_health)
  let #(control, armor) =
    creature_control.maximum_changed(
      state: state.control,
      before: state.body.combat.interrupt_armor,
      after: body.combat.interrupt_armor,
    )
  let state = State(..state, properties:, body:, life:, control:)
  let armor = carried(state:, effects: armor)
  let health = case
    creature_life.health(life:) != health_before,
    creature_life.is_dead(life:)
  {
    True, False ->
      to_viewers(
        state:,
        news: client_connection.Health(
          health: creature_life.health(life:),
          dead: False,
        ),
      )
    _, _ -> []
  }
  let #(state, fought) = case body.combat.attack.run_speed != run_speed_before {
    True -> fought(state:, input: creature_fight.SpeedChanged, now_ms:)
    False -> #(state, [])
  }
  #(state, list.flatten([health, armor, fought]))
}

/// The property modifier of `source` ends on the creature: it is removed, the entries
/// that changed go to every viewer, and the rules take the values back. A source the
/// creature does not hold changes nothing. The watch on its caster's connection
/// ends with the caster's last source.
fn modifier_ended(
  state state: State,
  source source: Source,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, effects) = source_removed(state:, source:, now_ms:)
  #(state, Effects(effects))
}

/// The effects of removing the modifier of `source`, as `modifier_ended` carries them
/// out.
fn source_removed(
  state state: State,
  source source: Source,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  case list.key_pop(state.held_by, source) {
    Error(Nil) -> #(state, [])
    Ok(#(by, held_by)) -> {
      let state = State(..state, held_by:)
      let #(properties, changed) =
        unit_properties.remove(properties: state.properties, source:)
      let news = changed_news(state:, changed:)
      let #(state, revalued) = revalued(state:, properties:, now_ms:)
      let #(state, unwatched) = unwatching_last(state:, by:)
      #(state, list.flatten([news, revalued, unwatched]))
    }
  }
}

/// The watch `watch` on a caster's connection ended: every source of that caster is
/// removed in the order they started, each as `modifier_ended` removes it. The watch
/// that fired is forgotten first, so no `Unwatch` follows its last source. A watch that
/// is no caster's changes nothing.
fn caster_gone(
  state state: State,
  watch watch: WatchId,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case
    list.find(dict.to_list(state.casters), fn(caster) { caster.1 == watch })
  {
    Error(Nil) -> #(state, Effects([]))
    Ok(#(by, _)) -> {
      let sources =
        list.filter_map(state.held_by, fn(held) {
          case held.1 == by {
            True -> Ok(held.0)
            False -> Error(Nil)
          }
        })
      let state = State(..state, casters: dict.delete(state.casters, by))
      let #(state, effects) =
        list.fold(sources, #(state, []), fn(so_far, source) {
          let #(state, done) = so_far
          let #(state, more) = source_removed(state:, source:, now_ms:)
          #(state, list.append(done, more))
        })
      #(state, Effects(effects))
    }
  }
}

/// The watch on the caster's connection `by`, started with its first modifier: none
/// for a connection already watched.
fn watching(
  state state: State,
  by by: ConnectionId,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(when: dict.has_key(state.casters, by), return: #(state, []))
  let watch = WatchId(state.next_watch)
  #(
    State(
      ..state,
      casters: dict.insert(state.casters, by, watch),
      next_watch: state.next_watch + 1,
    ),
    [Watch(watch:, target: Connection(by))],
  )
}

/// The end of the watch on the caster's connection `by` when it holds no source
/// any more.
fn unwatching_last(
  state state: State,
  by by: ConnectionId,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(
    when: list.any(state.held_by, fn(held) { held.1 == by }),
    return: #(state, []),
  )
  case dict.get(state.casters, by) {
    Ok(watch) -> #(State(..state, casters: dict.delete(state.casters, by)), [
      step.Unwatch(watch:),
    ])
    Error(Nil) -> #(state, [])
  }
}

/// The 0x93a of the entries a modifier's start or end changed, for every viewer;
/// none when it changed nothing.
fn changed_news(
  state state: State,
  changed changed: List(unit_properties.Changed),
) -> List(Effect(ServiceEffect(Outgoing))) {
  case changed {
    [] -> []
    _ ->
      to_viewers(
        state:,
        news: client_connection.PropertiesChanged(
          properties: unit_properties.entries(changed:),
        ),
      )
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
      let #(state, answered, controlled) =
        controls_after(state:, tell:, reaction:, now_ms:)
      // The answer goes first: the caster's connection then knows the strike
      // before it is told the health it left, one sender in one order.
      let answer = answer_to(tell:, answered:)
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
      let credit = credit_for(state:, tell:, reaction:)
      let state = State(..state, life: reaction.life)
      let input = case
        reaction.answer.outcome,
        tell.striker,
        tell.from,
        reaction.corpse_for_ms
      {
        _, _, _, Some(..) -> Some(creature_fight.Killed)
        strike_tell.Landed(descriptions:, ..),
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
      #(
        state,
        Effects(
          list.flatten([answer, credit, news, corpse, fought, controlled]),
        ),
      )
    }
  }
}

/// The kill credit for the blow that killed the creature: a player's strike that left
/// a corpse sends its connection the creature's row and level, once. A creature
/// dies once per stay, so no other strike reaches a corpse.
fn credit_for(
  state state: State,
  tell tell: StrikeTell,
  reaction reaction: creature_life.Reaction,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case reaction.corpse_for_ms, tell.striker {
    Some(..), PlayerStriker(stay:, ..) -> [
      OwnEffect(Send(
        to: tell.from,
        message: KillCredit(
          stay:,
          unit_id: state.settings.creature.unit_id,
          creature_id: state.settings.spawn.creature_id,
          faction_id: Faction2Id(state.settings.spawn.faction_id),
          level: state.settings.spawn.level,
        ),
      )),
    ]
    Some(..), CreatureStriker -> []
    None, PlayerStriker(..) | None, CreatureStriker -> []
  }
}

/// The creature's controls after a strike and its damage: a strike with states asks
/// the controls to take them (`creature_control.land`), which land on a creature
/// the strike left alive and name the ones that did in the answer, and the fight
/// stops the creature's path when it held no state before; a strike that kills a
/// creature that holds states or worn armor drops them with no 0x880
/// (`creature_control.died`). A strike with no state that kills no such creature touches
/// no control, and its answer stands.
fn controls_after(
  state state: State,
  tell tell: StrikeTell,
  reaction reaction: creature_life.Reaction,
  now_ms now_ms: Int,
) -> #(State, Answered, List(Effect(ServiceEffect(Outgoing)))) {
  case
    tell.controls,
    reaction.corpse_for_ms,
    creature_control.holds_anything(state: state.control)
  {
    [], None, _ | [], Some(..), False -> #(state, reaction.answer, [])
    _, Some(..), _ -> {
      let #(control, dropped) = creature_control.died(state: state.control)
      #(
        State(..state, control:),
        reaction.answer,
        carried(state:, effects: dropped),
      )
    }
    [_, ..], None, _ ->
      case reaction.answer.outcome {
        strike_tell.Landed(descriptions:, ..) -> {
          let held = creature_control.holds(state: state.control)
          let landing =
            creature_control.land(
              state: state.control,
              tell:,
              armor: state.body.combat.interrupt_armor,
              refill_ms: state.settings.numbers.interrupt_armor_refill_ms,
              now_ms:,
            )
          let state = State(..state, control: landing.state)
          let #(state, stopped) = case
            !held && creature_control.holds(state: state.control)
          {
            True -> fought(state:, input: creature_fight.Controlled, now_ms:)
            False -> #(state, [])
          }
          #(
            state,
            Answered(
              key: reaction.answer.key,
              outcome: strike_tell.Landed(
                descriptions:,
                controls: landing.landed,
              ),
            ),
            list.append(carried(state:, effects: landing.effects), stopped),
          )
        }
        strike_tell.Deflected | strike_tell.Refused(..) -> #(
          state,
          reaction.answer,
          [],
        )
      }
  }
}

/// The effects the creature's controls ask for, carried out: news to every viewer and
/// the control and refill timers.
fn carried(
  state state: State,
  effects effects: List(creature_control.Effect),
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.flat_map(effects, fn(effect) {
    case effect {
      creature_control.ToViewers(news:) -> to_viewers(state:, news:)
      creature_control.StartTimer(control:, after_ms:) -> [
        OwnEffect(step.StartServiceTimer(
          timer: control_timer(control:),
          after_ms:,
        )),
      ]
      creature_control.CancelTimer(control:) -> [
        OwnEffect(step.CancelServiceTimer(timer: control_timer(control:))),
      ]
      creature_control.StartRefill(after_ms:) -> [
        OwnEffect(step.StartServiceTimer(timer: refill_timer, after_ms:)),
      ]
      creature_control.CancelRefill -> [
        OwnEffect(step.CancelServiceTimer(timer: refill_timer)),
      ]
    }
  })
}

/// A control's timer fired: its state ends with a 0x880, and the fight acts again
/// when it was the last one held.
fn control_ended(
  state state: State,
  number number: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let held = creature_control.holds(state: state.control)
  let #(control, effects) =
    creature_control.ended(state: state.control, number:)
  let state = State(..state, control:)
  let #(state, resumed) = case
    held && !creature_control.holds(state: state.control)
  {
    True -> fought(state:, input: creature_fight.ControlEnded, now_ms:)
    False -> #(state, [])
  }
  #(state, Effects(list.append(carried(state:, effects:), resumed)))
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
/// attack, its kind's interval and cast time, and the run's numbers. Whether it is a turret
/// that stands where it is, is not read yet: shape of #736.
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
    controlled: creature_control.holds(state: state.control),
    cast_ms: state.settings.kind.cast_ms,
    stationary: False,
  )
}

/// The timer id of a fight timer: a multiple of 5 and 1, 2 and 3 above it for the attack
/// tick, the walk home, the strike deadline and the cast end, by generation (from 1), so
/// none is the corpse timer's 1 or the refill timer's 2 and a timer of an old generation is
/// never the new one's. The ids 4 above a multiple of 5 are the controls' (9, 14, 19 ...:
/// `control_timer`), so no two timers of a creature share an id.
fn timer_id(timer timer: creature_fight.Timer) -> step.TimerId {
  case timer {
    AttackTick(generation:) -> TimerId(5 * generation)
    HomeArrival(generation:) -> TimerId(5 * generation + 1)
    StrikeDeadline(generation:) -> TimerId(5 * generation + 2)
    CastEnds(generation:) -> TimerId(5 * generation + 3)
  }
}

/// The timer id of the control numbered `control`: 4 above 5 times it, from 9 (9, 14, 19
/// ...), so none is the corpse timer's 1, the refill timer's 2 or a fight timer's.
fn control_timer(control control: Int) -> step.TimerId {
  TimerId(5 * control + 4)
}

/// The number of the control a timer id is for, or `Error(Nil)` for one that is not a
/// control's: the corpse timer's 1, the refill timer's 2, a fight timer or any other. For
/// a test.
pub fn control_of(timer timer: step.TimerId) -> Result(Int, Nil) {
  let TimerId(number) = timer
  case number >= 9 && number % 5 == 4 {
    True -> Ok({ number - 4 } / 5)
    False -> Error(Nil)
  }
}

/// The fight timer of a timer id, or `Error(Nil)` for one the fight never starts: the
/// corpse timer's, the refill timer's, a control's, or any other.
fn fight_timer(timer timer: step.TimerId) -> Result(creature_fight.Timer, Nil) {
  let TimerId(number) = timer
  case number >= 5, number % 5 {
    True, 0 -> Ok(AttackTick(generation: number / 5))
    True, 1 -> Ok(HomeArrival(generation: { number - 1 } / 5))
    True, 2 -> Ok(StrikeDeadline(generation: { number - 2 } / 5))
    True, 3 -> Ok(CastEnds(generation: { number - 3 } / 5))
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
      unit: creature_unit.overlaid(
        unit: creature_unit.create(
          spawn: Spawn(..state.settings.spawn, place:),
          unit_id: creature.unit_id,
          health: creature_life.health(life: state.life),
          interrupt_armor: creature_control.armor_now(
            state: state.control,
            armor: state.body.combat.interrupt_armor,
          ),
          server_time_estimate_start: map.server_time(
            origin_ms: creature.clock_origin_ms,
            monotonic_ms: now_ms,
          ),
        ),
        properties: state.properties,
      ),
      life: creature.life,
      place:,
      hit_radius: state.body.combat.hit_radius,
      attackable: state.body.combat.attackable,
      hostile_to: state.body.combat.hostile_to,
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
/// `Withdrew`, by the connection whose ready player entered or left its ring,
/// `PlayerDied`, by the connection whose player died, and `Retire`. Any other is no message to a creature, and `Error(Nil)`.
pub fn told_by_map(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Watched(by:, stay:) -> Ok(Watched(by:, stay:))
    map.Unwatched(by:) -> Ok(Unwatched(by:))
    map.Approached(by:, unit_id:, place:, seq:, stay:) ->
      Ok(Approached(by:, unit_id:, place:, seq:, stay:))
    map.Withdrew(by:) -> Ok(Withdrew(by:))
    map.PlayerDied(by:) -> Ok(PlayerDied(by:))
    map.Retire -> Ok(Retire)
    map.Joined(..)
    | map.NotJoined(..)
    | map.Summoned(..)
    | map.NotSummoned(..)
    | map.Left
    | map.Noticed(..) -> Error(Nil)
  }
}
