//// The one fence of a tell to a creature, in a running world: real maps, creatures and
//// registry on a driven clock, with plain processes for the players' connections. Expected
//// values come from these places.
//// - The creature registry (`creature_registry`): an address is one creature process in one
////   run, so a tell addressed to the life that ended finds no creature, whatever the tell
////   says, and the same tell to the life that replaced it is taken.
//// - The Design of run A (issue 1410), 9.2: a tell holds no time of the life it is for.
//// A tell is shown to change nothing when the frames the players are sent after it equal
//// those of a world that was told nothing, and to change something when they differ in the
//// frame the row names. Each row is run in three worlds that differ only in what is told
//// after the next life stands: nothing, the tell by the old life's address, and that and
//// the same tell by the new life's address.

import cast_support
import crowd_control_support
import driven_time
import genesis_prime/client_connection.{
  type Message, ForStay, SentByFoe, SentByMap, SentByPeer, SentByTarget,
}
import genesis_prime/game/forced_move
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{type Key, Answered, Landed}
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{CreatureAppeared, PeerNews}
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/game/unit_state
import genesis_prime/step.{ConnectionId, RingMember}
import genesis_prime/table/id.{Spell4Id, UnitProperty2Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/registry.{type MapProcess}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/string
import map_support
import owned_test
import place_support
import spawn_support
import world_support.{type World}
import world_watch_support

const respawn_ms = 1000

/// Which creature the world stands: a Battle Beast, which fights no one, or a Dagun, which
/// is hostile to the tests' Dominion players.
type Kind {
  Beast
  Dagun
}

/// A world with the creature's first life dead and its next life standing, and the
/// connections of three players: 1 and 2 see the creature, 3 has not joined.
type Scene {
  Scene(
    time: driven_time.Time,
    world: World,
    run: MapProcess,
    unit_id: Int,
    first_life: Int,
    next_life: Int,
    connections: List(#(Int, Subject(Message))),
  )
}

/// What a row tells after the next life stands: nothing, the tell to the life that ended, or
/// that and the same tell to the life that replaced it.
type Told {
  ToNoOne
  ToTheLifeThatEnded
  ToBothLives
}

/// One kind of tell. `prepare` makes a life hold the state the tell would change and gives
/// the tell; `settle` runs after the tell, to bring the change to a frame.
type Row {
  Row(
    name: String,
    kind: Kind,
    prepare: fn(Scene, Int) -> creature.Message,
    settle: fn(Scene) -> Nil,
    changes: String,
  )
}

fn modifier_source() -> unit_properties.Source {
  cast_support.source_of(cast_id: 1, effect_id: 1921)
}

fn modifier_starts(scene scene: Scene) -> creature.Message {
  creature.ModifierStarts(
    by: ConnectionId(1),
    source: modifier_source(),
    modifier: Change(
      property: UnitProperty2Id(100),
      mode: 3,
      multiplier: 1.0,
      flat: 0.5,
      per_level: 0.0,
    ),
    struck_at_ms: world_watch_support.clock_ms(time: scene.time),
  )
}

fn cast_view(scene scene: Scene) -> unit_casts.CastView {
  unit_casts.CastView(
    caster_unit_id: 10,
    cast_id: 4_294_967_297,
    spell4_id: Spell4Id(41_886),
    primary_target: scene.unit_id,
    gone: True,
    current: True,
    targets: [],
  )
}

fn cast_view_set(scene scene: Scene) -> creature.Message {
  creature.CastViewSet(
    by: ConnectionId(1),
    view: cast_view(scene:),
    struck_at_ms: world_watch_support.clock_ms(time: scene.time),
  )
}

fn thrown(scene scene: Scene) -> creature.Message {
  creature.Thrown(
    throw: forced_move.Throw(
      move: forced_move.Move(
        way: forced_move.Away,
        mover: forced_move.Flight,
        min_distance: 10.0,
        max_distance: 10.0,
        flight_ms: 375,
        gravity: 0.0,
        flags: 1,
        height: 2.0,
      ),
      draws: forced_move.Draws(distance: 0.0, angle: 0.0),
      reference: forced_move.Reference(
        place: world_watch_support.sight_place(),
        radius: 0.5,
      ),
    ),
    struck_at_ms: world_watch_support.clock_ms(time: scene.time),
  )
}

fn despawn(scene scene: Scene) -> creature.Message {
  let now_ms = world_watch_support.clock_ms(time: scene.time)
  creature.Despawn(delay_ms: 0, struck_at_ms: now_ms, went_at_ms: now_ms)
}

fn unit_states(scene scene: Scene) -> creature.Message {
  let now_ms = world_watch_support.clock_ms(time: scene.time)
  creature.UnitStates(
    rows: [unit_state.Row(state: 6, delay_ms: 0, duration_ms: 8500)],
    struck_at_ms: now_ms,
    went_at_ms: now_ms,
  )
}

/// A player's strike of 5 damage, carrying a stun when `stunning`.
fn strike(
  scene scene: Scene,
  cast_id cast_id: Int,
  stunning stunning: Bool,
) -> creature.Message {
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id: scene.unit_id,
      damage_type: 3,
      damage: 5,
      cast_id:,
      occasion: strike_tell.AtGo(phase: 0),
    )
  creature.Strike(
    tell: strike_tell.Strike(..tell, controls: case stunning {
      True -> [crowd_control_support.stagger_stun(instance_id: 28_673)]
      False -> []
    }),
  )
}

/// The ring member of the connection's player, standing 5 units from the creature.
fn member(connection connection: Int) -> step.RingMember {
  RingMember(
    by: ConnectionId(connection),
    unit_id: connection * 10,
    place: place_at(x: 5.0),
    seq: 1,
    stay: map_support.stay(count: 1),
    hit_radius: place_support.player_hit_radius,
  )
}

fn place_at(x x: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y: 0.0,
    z: 0.0,
  )
}

fn target_moved(connection connection: Int, x x: Float) -> creature.Message {
  creature.TargetMoved(
    by: ConnectionId(connection),
    place: place_at(x:),
    seq: 2,
    stay: map_support.stay(count: 1),
    hit_radius: place_support.player_hit_radius,
  )
}

/// Tells the creature of `life` the message through the registry.
fn told(
  scene scene: Scene,
  life life: Int,
  message message: creature.Message,
) -> Result(Nil, Nil) {
  creature_registry.tell(
    scene.world.creatures,
    map: world_watch_support.ship,
    incarnation: scene.run.incarnation,
    unit_id: scene.unit_id,
    life:,
    message:,
  )
}

fn told_and_taken(
  scene scene: Scene,
  life life: Int,
  message message: creature.Message,
) -> Nil {
  let assert Ok(Nil) = told(scene:, life:, message:)
    as "the creature is found by its address and told"
  driven_time.wait_until_quiet(scene.time)
}

/// Everything each connection has been sent, as one description of each message.
fn heard(scene scene: Scene) -> List(String) {
  list.flat_map(scene.connections, fn(connection) {
    world_support.sent_before_the_marker(
      world: scene.world,
      id: connection.0,
      received: connection.1,
    )
    |> list.map(fn(message) {
      "connection " <> int.to_string(connection.0) <> ": " <> described(message)
    })
  })
}

/// The first word of a value's text: its constructor.
fn named(value value: a) -> String {
  let assert [name, ..] = string.split(string.inspect(value), "(")
  name
}

/// What a message is, for a comparison of what two worlds sent: the news or fight it
/// carries by name, and how many casts a creature's 0x262 lists.
fn described(message: Message) -> String {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(news: CreatureAppeared(unit:, ..), ..)),
      ..,
    ) ->
      "appeared with "
      <> int.to_string(list.length(unit.tail.casts))
      <> " casts"
    ForStay(sent: SentByPeer(PeerNews(news:, ..)), ..) -> named(value: news)
    ForStay(sent: SentByFoe(fight), ..) -> named(value: fight)
    ForStay(sent: SentByTarget(..), ..) -> "answer to a strike"
    ForStay(sent: SentByMap(notice), ..) -> named(value: notice)
    ForStay(..) -> "another message to a stay"
    client_connection.SentBySessions(..) | client_connection.SentByChat(..) ->
      "a message not for a stay"
  }
}

/// A world of one creature of `kind` whose first life is struck dead and whose next life
/// stands, with the frames of the first life and the start of the next read and dropped,
/// and the first life holding what `prepare` gives it.
fn scene_of(
  kind kind: Kind,
  prepare_first prepare_first: fn(Scene, Int) -> creature.Message,
) -> Scene {
  let time = driven_time.new()
  let world =
    world_support.start(
      time:,
      spawns: [
        case kind {
          Beast -> spawn_support.battle_beast(number: 1, x: 0.0)
          Dagun -> spawn_support.dagun(number: 1, x: 0.0)
        },
      ],
      respawn_ms:,
      idle_stop_ms: 60_000,
      sweep_ms: world_watch_support.sweep_ms,
    )
  let run = world_watch_support.started(world)
  let connections =
    list.map([1, 2, 3], fn(id) { #(id, world_support.connection(world:, id:)) })
  let assert [#(_, first), ..] = connections
  let _first_unit = world_watch_support.join(run:, connection: 1)
  let _second_unit = world_watch_support.join(run:, connection: 2)
  let appeared =
    world_watch_support.next(
      received: first,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let first_life = 2
  let _found =
    world_watch_support.creature_pid(
      time:,
      world:,
      run:,
      unit_id: appeared.unit_id,
      life: first_life,
    )
  let scene =
    Scene(
      time:,
      world:,
      run:,
      unit_id: appeared.unit_id,
      first_life:,
      next_life: first_life,
      connections:,
    )
  let _held = prepare_first(scene, first_life)
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: scene.unit_id,
    life: first_life,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, _, _) =
    world_watch_support.heard_up_to_answer(received: first, cast_id: 1)
  driven_time.advance(time:, ms: respawn_ms)
  let assert [
    world_watch_support.Removed,
    world_watch_support.Created(life: next_life, ..),
  ] = [
    world_watch_support.next(
      received: first,
      what: "the corpse's 0x355",
      wanted: world_watch_support.shown,
    ),
    world_watch_support.next(
      received: first,
      what: "the next life's 0x262",
      wanted: world_watch_support.shown,
    ),
  ]
    as "the first life is removed and the next life is created"
  let _next_found =
    world_watch_support.creature_pid(
      time:,
      world:,
      run:,
      unit_id: scene.unit_id,
      life: next_life,
    )
  let scene = Scene(..scene, next_life:)
  let _dropped = heard(scene:)
  scene
}

/// What the players are sent after the tell of `row` is told as `telling` says, once the
/// next life stands and holds what the row's `prepare` makes it hold.
fn heard_after(row row: Row, telling telling: Told) -> List(String) {
  let scene = scene_of(kind: row.kind, prepare_first: row.prepare)
  let tell = row.prepare(scene, scene.next_life)
  let _before = heard(scene:)
  case telling {
    ToNoOne -> Nil
    ToTheLifeThatEnded -> refused_at_the_old_address(row:, scene:, tell:)
    ToBothLives -> {
      refused_at_the_old_address(row:, scene:, tell:)
      told_and_taken(scene:, life: scene.next_life, message: tell)
    }
  }
  row.settle(scene)
  let frames = heard(scene:)
  world_support.stop(world: scene.world)
  frames
}

fn refused_at_the_old_address(
  row row: Row,
  scene scene: Scene,
  tell tell: creature.Message,
) -> Nil {
  assert told(scene:, life: scene.first_life, message: tell) == Error(Nil)
    as {
      row.name
      <> ": the registry finds no creature at the address of the life that ended"
    }
}

/// The descriptions in `these` that `others` holds fewer of: one per extra frame.
fn more_in(
  these these: List(String),
  than others: List(String),
) -> List(String) {
  list.fold(others, these, fn(left, other) {
    case list.split_while(left, fn(line) { line != other }) {
      #(before, [_, ..after]) -> list.append(before, after)
      #(_, []) -> left
    }
  })
}

fn nothing_to_settle(_scene: Scene) -> Nil {
  Nil
}

/// A third player comes into sight of the creature, so it is sent the creature's 0x262.
fn a_newcomer_joins(scene scene: Scene) -> Nil {
  let _unit = world_watch_support.join(run: scene.run, connection: 3)
  Nil
}

/// The fight of the player of connection 1 with the creature of `life`, which begins at
/// the ring's tell, and the first attack the creature sends it.
fn fighting(scene scene: Scene, life life: Int) -> Nil {
  told_and_taken(
    scene:,
    life:,
    message: creature.Approached(member: member(connection: 1)),
  )
}

fn rows() -> List(Row) {
  [
    Row(
      name: "ModifierStarts",
      kind: Beast,
      prepare: fn(scene, _life) { modifier_starts(scene:) },
      settle: nothing_to_settle,
      changes: "connection 1: PropertiesChanged",
    ),
    Row(
      name: "ModifierEnds",
      kind: Beast,
      prepare: fn(scene, life) {
        told_and_taken(scene:, life:, message: modifier_starts(scene:))
        creature.ModifierEnds(source: modifier_source())
      },
      settle: nothing_to_settle,
      changes: "connection 1: PropertiesChanged",
    ),
    Row(
      name: "CastViewSet",
      kind: Beast,
      prepare: fn(scene, _life) { cast_view_set(scene:) },
      settle: a_newcomer_joins,
      changes: "connection 3: appeared with 1 casts",
    ),
    Row(
      name: "CastViewEnds",
      kind: Beast,
      prepare: fn(scene, life) {
        told_and_taken(scene:, life:, message: cast_view_set(scene:))
        creature.CastViewEnds(
          by: ConnectionId(1),
          cast_id: cast_view(scene:).cast_id,
        )
      },
      settle: a_newcomer_joins,
      changes: "connection 3: appeared with 0 casts",
    ),
    Row(
      name: "ControlsEnd",
      kind: Beast,
      prepare: fn(scene, life) {
        told_and_taken(
          scene:,
          life:,
          message: strike(scene:, cast_id: 5, stunning: True),
        )
        creature.ControlsEnd(by: ConnectionId(1), cast_id: 5)
      },
      settle: nothing_to_settle,
      changes: "connection 1: CrowdControlEnded",
    ),
    Row(
      name: "Thrown",
      kind: Beast,
      prepare: fn(scene, _life) { thrown(scene:) },
      settle: nothing_to_settle,
      changes: "connection 1: CreatureMoved",
    ),
    Row(
      name: "Despawn",
      kind: Beast,
      prepare: fn(scene, _life) { despawn(scene:) },
      settle: nothing_to_settle,
      changes: "connection 1: Removed",
    ),
    Row(
      name: "UnitStates",
      kind: Beast,
      prepare: fn(scene, _life) { unit_states(scene:) },
      settle: nothing_to_settle,
      changes: "connection 1: UnitStateHeld",
    ),
    Row(
      name: "Strike",
      kind: Beast,
      prepare: fn(scene, _life) { strike(scene:, cast_id: 9, stunning: False) },
      settle: nothing_to_settle,
      changes: "connection 1: answer to a strike",
    ),
    Row(
      name: "Approached",
      kind: Dagun,
      prepare: fn(_scene, _life) {
        creature.Approached(member: member(connection: 1))
      },
      settle: nothing_to_settle,
      changes: "connection 1: Threatened",
    ),
    Row(
      name: "TargetMoved",
      kind: Dagun,
      prepare: fn(scene, life) {
        fighting(scene:, life:)
        target_moved(connection: 1, x: 25.0)
      },
      settle: nothing_to_settle,
      changes: "connection 1: CreatureMoved",
    ),
    Row(
      name: "StrikeAnswered",
      kind: Dagun,
      prepare: fn(scene, life) {
        fighting(scene:, life:)
        driven_time.advance(time: scene.time, ms: 1500)
        let assert [key] =
          list.filter_map(
            world_support.sent_before_the_marker(
              world: scene.world,
              id: 1,
              received: connection_of(scene:, id: 1),
            ),
            attack_key,
          )
          as "the creature struck the player once"
        creature.StrikeAnswered(answered: Answered(
          key:,
          outcome: Landed(
            descriptions: [],
            controls: [],
            armor_removed: 0,
            gates_passed: [],
          ),
        ))
      },
      settle: nothing_to_settle,
      changes: "connection 1: CastWent",
    ),
    Row(
      name: "Withdrew",
      kind: Dagun,
      prepare: fn(scene, life) {
        told_and_taken(
          scene:,
          life:,
          message: strike(scene:, cast_id: 7, stunning: False),
        )
        told_and_taken(
          scene:,
          life:,
          message: creature.Approached(member: member(connection: 2)),
        )
        creature.Withdrew(by: ConnectionId(2))
      },
      settle: fn(scene) {
        told_and_taken(
          scene:,
          life: scene.next_life,
          message: creature.PlayerDied(by: ConnectionId(1)),
        )
        driven_time.advance(time: scene.time, ms: 10_000)
      },
      changes: "connection 2: Threatened",
    ),
    Row(
      name: "PlayerDied",
      kind: Dagun,
      prepare: fn(scene, life) {
        fighting(scene:, life:)
        creature.PlayerDied(by: ConnectionId(1))
      },
      settle: nothing_to_settle,
      changes: "connection 1: Released",
    ),
  ]
}

fn connection_of(scene scene: Scene, id id: Int) -> Subject(Message) {
  let assert Ok(#(_, received)) =
    list.find(scene.connections, fn(c) { c.0 == id })
  received
}

/// The key of the strike a creature sent the player, when the message is that.
fn attack_key(message: Message) -> Result(Key, Nil) {
  case message {
    ForStay(
      sent: SentByFoe(strike_tell.Attacks(tell: strike_tell.Strike(key:, ..))),
      ..,
    ) -> Ok(key)
    _ -> Error(Nil)
  }
}

pub fn a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.length(rows()) == 14
    as "one row for each message a connection or the map tells a creature that changes it, from creature.Message"
  list.each(rows(), fn(row) {
    let nothing = heard_after(row:, telling: ToNoOne)
    let by_the_old_address = heard_after(row:, telling: ToTheLifeThatEnded)
    let by_both = heard_after(row:, telling: ToBothLives)
    assert by_the_old_address == nothing
      as {
        row.name
        <> ": a tell to the life that ended changes nothing the players are sent"
      }
    let changed =
      list.append(
        more_in(these: by_both, than: nothing),
        more_in(these: nothing, than: by_both),
      )
    assert list.any(changed, string.contains(_, row.changes))
      as {
        row.name
        <> ": the same tell to the life that replaced it changes "
        <> row.changes
        <> ", and so the rejection above is not for want of an effect; the frames that differ: "
        <> string.join(list.take(changed, 3), ", ")
      }
  })
}
