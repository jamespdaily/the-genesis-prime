//// What the whole-world creature tests share: a world of beasts on a driven clock, the
//// joins of players standing in sight of them, the connections' messages read in order,
//// and the strikes the caster's connection tells a creature through the registry.

import ask_support
import driven_time
import event_wait
import genesis_prime/client_connection.{
  type Message, type PeerNews, CreatureAppeared, ForStay, PeerNews, SentByMap,
  SentByPeer,
}
import genesis_prime/game/hit.{Blow, Offence, Rolls, Worked}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{Key, Strike}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/service
import genesis_prime/service/shell
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{type Character}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/set
import map_support
import open_wait
import place_support
import spawn_support
import world_support.{type World}

pub const ship = MapId(world_id: 3460, instance: 0)

pub fn started(world: World) -> MapProcess {
  let assert Ok(found) =
    open_wait.named("Maps to answer the find", fn() {
      world_map_registry.find_or_start(
        world.maps,
        ship,
        deadline_ms: ask_support.deadline_far_beyond_the_tests_deadline(),
      )
    })
    as "Maps started the map or found it running"
  found
}

/// The process of the creature that is unit `unit_id` in the run under `life`,
/// once it runs.
pub fn creature_pid(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
) -> Pid {
  let find = fn() {
    creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id:,
      life:,
    )
  }
  event_wait.until("the creature was started and joined its address", fn() {
    find() != Error(Nil)
  })
  let assert Ok(pid) = find() as "the creature is found by its address"
  pid
}

/// The join of the connection as a player standing in sight of the creatures, an
/// ask answered with the player's own unit.
pub fn join(run run: MapProcess, connection connection: Int) -> Int {
  join_at(
    run:,
    connection:,
    character: map_support.character(number: 100 + connection),
    place: sight_place(),
  )
}

/// Where `join` stands the player.
pub fn sight_place() -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x: 100.0,
    y: 0.0,
    z: 0.0,
  )
}

/// The join of the connection as a player standing at `place`.
pub fn join_at(
  run run: MapProcess,
  connection connection: Int,
  character character: Character,
  place place: Place,
) -> Int {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        run.subject,
        map.Join(
          connection: ConnectionId(connection),
          character:,
          place:,
          stay: map_support.stay(count: 1),
          alive: True,
          hidden: set.new(),
        ),
        reply,
      )
    })
  let assert map.Joined(unit:, ..) = answer as "the map answered the join"
  unit.unit_id
}

/// The next message the connection was sent that `wanted` takes, in the order
/// they came. The wait has no limit of its own: a message that never comes keeps
/// the test waiting past its deadline, which warns and names `what`.
pub fn next(
  received received: Subject(Message),
  what what: String,
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> a {
  open_wait.named("this to arrive: " <> what, fn() { taken(received:, wanted:) })
}

pub fn taken(
  received received: Subject(Message),
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> a {
  case wanted(process.receive_forever(received)) {
    Ok(found) -> found
    Error(Nil) -> taken(received:, wanted:)
  }
}

/// A creature's 0x262 as the connection was sent it, with the unit id it names.
pub fn appearance(message: Message) -> Result(UnitCreateCreature, Nil) {
  case appeared_news(message) {
    Ok(PeerNews(news: CreatureAppeared(unit:, ..), ..)) -> Ok(unit)
    Ok(PeerNews(..)) | Error(Nil) -> Error(Nil)
  }
}

/// The peer news of a creature's appearance, whole as the connection was sent it, so a test
/// can hand the same news to a real connection.
pub fn appeared_news(message: Message) -> Result(PeerNews, Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(news: CreatureAppeared(..), ..) as news),
      ..,
    ) -> Ok(news)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// Short times for a world whose creatures stop: a creature no player has seen
/// for 100 ms stops at the next sweep, every 20 ms.
pub const idle_stop_ms = 100

pub const sweep_ms = 20

/// A world of one Battle Beast at x 0 whose maps and creatures take their time from
/// `time`, so a timer fires only when the test advances it.
pub fn one_beast_timed(
  time time: driven_time.Time,
  respawn_ms respawn_ms: Int,
  idle_stop_ms idle_stop_ms: Int,
) -> World {
  world_support.start_timed(
    time: driven_time.service_time(time),
    spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
    respawn_ms:,
    idle_stop_ms:,
    sweep_ms:,
  )
}

/// The connection is told the creature it saw is out of its sight (0x355). The map
/// sends it in the step that took the player's move, so the map has by then taken
/// the move and read the clock for it.
pub fn left_sight(
  received received: Subject(Message),
  what what: String,
) -> Nil {
  next(received:, what:, wanted: fn(message) {
    case message {
      ForStay(
        sent: SentByPeer(PeerNews(news: client_connection.Removed, ..)),
        ..,
      ) -> Ok(Nil)
      ForStay(..)
      | client_connection.SentBySessions(..)
      | client_connection.SentByChat(..) -> Error(Nil)
    }
  })
}

/// The outcome of the creature's answer to strike `cast_id`, when the message is
/// that answer.
pub fn answer_to(
  message message: Message,
  cast_id cast_id: Int,
) -> Result(strike_tell.Outcome, Nil) {
  case message {
    ForStay(sent: client_connection.SentByTarget(answered:), ..)
      if answered.key.cast_id == cast_id
    -> Ok(answered.outcome)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// The strike of connection 1 on the Beast `unit_id` with one blow of `damage` of
/// `damage_type` (1 Physical, 2 Tech, 3 Magic) and no luck, told through the registry
/// as a caster's connection tells it.
pub fn strike_with(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
  damage_type damage_type: Int,
  damage damage: Int,
  cast_id cast_id: Int,
) -> Nil {
  let assert Ok(Nil) =
    creature_registry.tell(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id:,
      life:,
      message: strike_message(
        unit_id:,
        damage_type:,
        damage:,
        cast_id:,
        occasion: strike_tell.AtGo(phase: 0),
      ),
    )
    as "the creature is found by its address and told"
  Nil
}

/// The strike of connection 1 on the Beast `unit_id` for `occasion`, with one blow of
/// `damage` of `damage_type` and no luck.
pub fn strike_message(
  unit_id unit_id: Int,
  damage_type damage_type: Int,
  damage damage: Int,
  cast_id cast_id: Int,
  occasion occasion: strike_tell.Occasion,
) -> creature.Message {
  strike_message_of(
    unit_id:,
    damage_type:,
    amount: Worked(damage),
    cast_id:,
    occasion:,
  )
}

/// The strike of connection 1 on the Beast `unit_id` for `occasion`, with one blow of
/// `amount` of `damage_type` and no luck.
pub fn strike_message_of(
  unit_id unit_id: Int,
  damage_type damage_type: Int,
  amount amount: hit.Amount,
  cast_id cast_id: Int,
  occasion occasion: strike_tell.Occasion,
) -> creature.Message {
  creature.Strike(
    tell: Strike(
      key: Key(cast_id:, occasion:, unit_id:),
      from: step.Connection(ConnectionId(1)),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 1,
            damage_type:,
            damage: amount,
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
        stay: map_support.stay(count: 1),
        hit_radius: place_support.player_hit_radius,
        rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
      ),
      controls: [],
      gates: [],
    ),
  )
}

/// The driven clock's reading.
pub fn clock_ms(time time: driven_time.Time) -> Int {
  let shell.ServiceTime(clock:, ..) = driven_time.service_time(time)
  let step.Now(monotonic_ms:, ..) = clock()
  monotonic_ms
}

/// What a connection was sent up to the answer to strike `cast_id`: the creatures'
/// 0x262s, how many removals (0x355) came, and the outcome. The creature sends the news
/// and the answer in its own order, so a removal it sent earlier is counted here.
pub fn heard_up_to_answer(
  received received: Subject(Message),
  cast_id cast_id: Int,
) -> #(List(UnitCreateCreature), Int, strike_tell.Outcome) {
  open_wait.named("the answer to strike " <> int.to_string(cast_id), fn() {
    tally(received:, cast_id:, appeared: [], removals: 0)
  })
}

pub fn tally(
  received received: Subject(Message),
  cast_id cast_id: Int,
  appeared appeared: List(UnitCreateCreature),
  removals removals: Int,
) -> #(List(UnitCreateCreature), Int, strike_tell.Outcome) {
  let message = process.receive_forever(received)
  case answer_to(message:, cast_id:), appearance(message), is_removal(message) {
    Ok(outcome), _, _ -> #(list.reverse(appeared), removals, outcome)
    Error(Nil), Ok(unit), _ ->
      tally(received:, cast_id:, appeared: [unit, ..appeared], removals:)
    Error(Nil), Error(Nil), True ->
      tally(received:, cast_id:, appeared:, removals: removals + 1)
    Error(Nil), Error(Nil), False ->
      tally(received:, cast_id:, appeared:, removals:)
  }
}

/// Whether the message is a creature's removal from the connection's sight (0x355).
pub fn is_removal(message: Message) -> Bool {
  case message {
    ForStay(sent: SentByPeer(PeerNews(news: client_connection.Removed, ..)), ..) ->
      True
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> False
  }
}

/// The removals (0x355) a connection has already been sent and not taken. A creature
/// sends in the order it acts and a send is immediate, so a removal it sent before a
/// message the test has taken from the same creature is here already.
pub fn removals_waiting(received received: Subject(Message)) -> Int {
  case process.receive(received, 0) {
    Ok(message) ->
      case is_removal(message) {
        True -> 1 + removals_waiting(received:)
        False -> removals_waiting(received:)
      }
    Error(Nil) -> 0
  }
}

/// The unit the map says is gone, when the message is that.
pub fn gone_unit(message: Message) -> Result(Int, Nil) {
  case message {
    ForStay(sent: SentByMap(map.Gone(unit_id:)), ..) -> Ok(unit_id)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// A timed world of one Battle Beast with the players' connections 1 and 2 standing in
/// sight of it: the beast's 0x262 each was sent (the news itself in `appeared`), the beast's
/// process, and the connections' received messages.
pub type Watched {
  Watched(
    world: World,
    run: MapProcess,
    time: driven_time.Time,
    caster: Subject(Message),
    viewer: Subject(Message),
    beast: UnitCreateCreature,
    appeared: PeerNews,
    pid: Pid,
  )
}

pub fn watched_by_two(respawn_ms respawn_ms: Int) -> Watched {
  let time = driven_time.new()
  let world = one_beast_timed(time:, respawn_ms:, idle_stop_ms:)
  let run = started(world)
  let caster = world_support.connection(world:, id: 1)
  let viewer = world_support.connection(world:, id: 2)
  let _caster_unit = join(run:, connection: 1)
  let _viewer_unit = join(run:, connection: 2)
  let appeared =
    next(received: caster, what: "the beast's 0x262", wanted: appeared_news)
  let assert PeerNews(news: CreatureAppeared(unit: beast, ..), ..) = appeared
    as "the news is a creature's appearance"
  let _shown =
    next(received: viewer, what: "the beast's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: beast.unit_id, life: 2)
  Watched(world:, run:, time:, caster:, viewer:, beast:, appeared:, pid:)
}
