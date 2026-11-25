//// What the whole-world creature tests share: a world of beasts on a driven clock, the
//// joins of players standing in sight of them, the connections' messages read in order,
//// and the strikes the caster's connection tells a creature through the registry.

import ask_support
import cast_support
import driven_time
import genesis_prime/client_connection.{
  type Message, ForStay, SentByMap, SentByPeer,
}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/hit.{Blow, Offence, Rolls, Worked}
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{Key, Strike}
import genesis_prime/game/unit_news.{type PeerNews, CreatureAppeared, PeerNews}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/service/shell
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{type Character}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import gleam/dict
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
/// once it runs. A creature joins its address before its first step, inside the
/// map's step that starts it, so it is found once the clock's participants are
/// quiet; a creature the map never starts ends the wait at once, naming its address
/// (`driven_time.wait_for`).
pub fn creature_pid(
  time time: driven_time.Time,
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
  driven_time.wait_for(
    time:,
    what: "the creature of unit "
      <> int.to_string(unit_id)
      <> " and life "
      <> int.to_string(life)
      <> " in the run "
      <> int.to_string(run.incarnation)
      <> " of the map "
      <> int.to_string(ship.world_id)
      <> "/"
      <> int.to_string(ship.instance)
      <> " to be started and join its address",
    condition: fn() { find() != Error(Nil) },
  )
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
  world_support.start(
    time:,
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
    case is_removal(message) {
      True -> Ok(Nil)
      False -> Error(Nil)
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

/// Whether the message is a creature's removal from the connection's sight (0x355): the
/// removal news a creature broadcasts for its own removal, or the map's notice that the
/// player no longer sees the unit.
pub fn is_removal(message: Message) -> Bool {
  case message {
    ForStay(sent: SentByPeer(PeerNews(news: unit_news.Removed, ..)), ..) -> True
    ForStay(sent: SentByMap(map.UnitUnseen(..)), ..) -> True
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
  let pid = creature_pid(time:, world:, run:, unit_id: beast.unit_id, life: 2)
  Watched(world:, run:, time:, caster:, viewer:, beast:, appeared:, pid:)
}

/// Tells the creature of the unit and life in the run what a cast's effect asked of it, the
/// way the caster's connection does through the registry; stops the test when the registry
/// holds no creature at that address.
pub fn told_creature(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
  request request: client_connection.Request,
) -> Nil {
  let assert Ok(Nil) =
    server.tell_creature(
      creatures: world.creatures,
      to: step.Creature(
        map: ship,
        incarnation: run.incarnation,
        unit_id:,
        life:,
      ),
      request:,
    )
    as "the creature is found by its address and told"
  Nil
}

/// The effects of a press of the planted spell whose go (at `went_at_ms`) strikes these
/// creatures, each a unit id and its life, struck at `struck_at_ms`, and then asks for
/// `kind` on each struck unit: the press's effects followed by the go's.
pub fn effects_of_a_go_on_creatures(
  kind kind: spell_plan.Kind,
  units units: List(#(Int, Int)),
  struck_at_ms struck_at_ms: Int,
  went_at_ms went_at_ms: Int,
) -> List(cast_state.Effect) {
  let assert [#(first, _), ..] = units
  let #(state, pressed) =
    cast_support.pressed_raw_in(
      plans: cast_support.plans_starting_on_each_struck(
        started: cast_support.with_effects(
          spell: cast_support.child(spell4_id: 30_600, base: 21_614),
          kinds: [kind],
        ),
      ),
      state: cast_state.new(),
      caster: cast_support.caster(),
      bag_index: 11,
      target: first,
      at: struck_at_ms,
    )
  let struck =
    list.map(units, fn(unit) {
      cast_support.creature_hit(unit_id: unit.0, life: unit.1, struck_at_ms:)
    })
  let #(_, answered) =
    cast_support.answered_each(
      caster: cast_support.caster(),
      state:,
      effects: pressed,
      at: went_at_ms,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  list.append(pressed, answered)
}

/// The clock's time before and 250 ms after it is driven on: a go's strike and the go.
pub fn times_of_a_go_after_250_ms(watched watched: Watched) -> #(Int, Int) {
  let struck_at_ms = clock_ms(time: watched.time)
  driven_time.advance(time: watched.time, ms: 250)
  let went_at_ms = clock_ms(time: watched.time)
  assert went_at_ms == struck_at_ms + 250
  #(struck_at_ms, went_at_ms)
}
