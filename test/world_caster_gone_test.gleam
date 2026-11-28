//// What a creature holds for a caster ends with the caster's end, in a running world:
//// real maps, creatures and registry on a driven clock, with plain processes for the
//// players' connections. Expected values come from these places.
//// - The map's word `CasterGone` (genesis_prime/world_map/map, relay): a player's leave and
////   its connection's end are told to every running creature once, by the map alone, and a
////   start or a view is admitted only from a player in the map in the stay named
////   (`relay.inbound_kind_of`), so a caster's holdings on a creature end through one sender.
//// - The creature (genesis_prime/world_map/creature): a creature that takes `CasterGone`
////   drops the connection's sources (each with its property news) and views, whatever state
////   it is in; a control it landed stands until its own timer ends it (no 0x880 at the
////   caster's end); a creature watches its map's run and no connection.
//// - A creature's 0x262 lists the casts it holds a view of (`opcode.0x262.casts`) and the
////   properties it holds (`opcode.0x93a`), which a later viewer is shown.

import crowd_control_support
import driven_time
import genesis_prime/client_connection.{type Message, ForUnit, SentByPeer}
import genesis_prime/map/message as map_message
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_casts
import genesis_prime/shared/unit_news.{
  CrowdControlEnded, PeerNews, PropertiesChanged,
}
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/system
import inbound_support
import mailbox_support
import owned_test
import world_support
import world_watch_support.{type Watched}

/// The beast's life in these worlds: the first creature a player sees has life 2.
const life = 2

/// The kinds of news of the creature the connection was sent that these tests read.
type Heard {
  PropertiesWritten
  ControlEnded
}

/// What the connection was sent of the creature's properties and crowd-control ends since the
/// last read, in order. The clock's participants are quiet first.
fn heard(
  watched watched: Watched,
  id id: Int,
  received received: Subject(Message),
) -> List(Heard) {
  list.filter_map(
    world_support.sent_before_the_marker(world: watched.world, id:, received:),
    fn(message) {
      case message {
        ForUnit(sent: SentByPeer(PeerNews(news: PropertiesChanged(..), ..)), ..) ->
          Ok(PropertiesWritten)
        ForUnit(sent: SentByPeer(PeerNews(news: CrowdControlEnded(..), ..)), ..) ->
          Ok(ControlEnded)
        ForUnit(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

fn told(watched watched: Watched, payload payload: map_message.Inbound) -> Nil {
  world_watch_support.told_creature(
    run: watched.run,
    unit_id: watched.beast.unit_id,
    life:,
    payload:,
  )
}

/// The strike of connection 1 on the beast that lands a stun: a state the creature holds
/// for that connection's cast.
fn stunning_strike(watched watched: Watched) -> map_message.Inbound {
  let tell = inbound_support.strike(unit_id: watched.beast.unit_id)
  map_message.Strike(
    tell: strike_tell.Strike(..tell, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ]),
  )
}

fn a_modifier() -> map_message.Inbound {
  map_message.ModifierStarts(
    source: inbound_support.source(),
    modifier: inbound_support.modifier(),
  )
}

/// The view of cast 1 as the caster's current cast, which a creature's 0x262 lists.
fn a_view() -> map_message.Inbound {
  map_message.CastViewSet(
    view: unit_casts.CastView(..inbound_support.view(), current: True),
  )
}

/// Connection 1 holds a modifier, a view and a stun on the beast, and the beast's other
/// viewer, connection 2, has been sent what that wrote: the news is read and dropped.
fn holding(watched watched: Watched) -> Nil {
  told(watched:, payload: a_modifier())
  told(watched:, payload: a_view())
  told(watched:, payload: stunning_strike(watched:))
  let _written = heard(watched:, id: 2, received: watched.viewer)
  Nil
}

/// The 0x262 a player of connection `id` that comes into sight of the beast after this is
/// sent. Each newcomer has its own connection.
fn shown_to_a_newcomer(
  watched watched: Watched,
  id id: Int,
) -> UnitCreateCreature {
  let newcomer = world_support.connection(world: watched.world, id:)
  let _unit = world_watch_support.join(run: watched.run, connection: id)
  world_watch_support.next(
    received: newcomer,
    what: "the beast's 0x262",
    wanted: world_watch_support.appearance,
  )
}

/// Whether the newcomer is shown the beast as it was made: no cast held on it and the
/// properties its 0x262 listed first.
fn shown_as_made(watched watched: Watched, id id: Int) -> Bool {
  let shown = shown_to_a_newcomer(watched:, id:)
  shown.tail.casts == []
  && shown.tail.properties == watched.beast.tail.properties
}

pub fn a_start_told_after_its_casters_leave_holds_nothing_on_the_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  world_watch_support.left(run: watched.run, connection: 1)
  // The connection that left tells a start and a view again, as one that has not taken
  // its leave yet may.
  told(watched:, payload: a_modifier())
  told(watched:, payload: a_view())
  assert heard(watched:, id: 2, received: watched.viewer) == []
    as "a start told after the caster's leave changes no property the viewers are sent"
  assert shown_as_made(watched:, id: 3)
    as "a later viewer is shown the creature's base properties and no view of the connection that left"
  world_support.stop(world: watched.world)
}

pub fn a_connection_that_ends_holding_a_modifier_a_view_and_a_control_on_a_creature_leaves_no_source_no_view_and_no_watch_of_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  holding(watched:)
  assert list.length(
      mailbox_support.monitored(mailbox_support.settled(watched.pid)),
    )
    == 1
    as "the creature monitors one process, its map's run, and no connection that holds on it"
  world_support.end_connection(world: watched.world, id: 1)
  assert heard(watched:, id: 2, received: watched.viewer) == [PropertiesWritten]
    as "the viewer is written the property restored once, and the stun stands: no 0x880 at the caster's end"
  assert shown_as_made(watched:, id: 3)
    as "a later viewer is shown no view and the base properties"
  world_support.stop(world: watched.world)
}

pub fn a_normal_leave_then_the_connections_death_holds_no_source_or_view_of_it_and_the_second_end_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  holding(watched:)
  // The camp's step ends the source through the map first; the view and the stun are
  // not ended by the connection.
  told(
    watched:,
    payload: map_message.ModifierEnds(source: inbound_support.source()),
  )
  world_watch_support.left(run: watched.run, connection: 1)
  assert heard(watched:, id: 2, received: watched.viewer) == [PropertiesWritten]
    as "the connection's own end wrote the property restored once; the leave writes nothing more and the stun stands"
  assert shown_as_made(watched:, id: 3)
    as "after the leave, before the connection's death, a later viewer is shown no view of it"
  world_support.end_connection(world: watched.world, id: 1)
  assert heard(watched:, id: 2, received: watched.viewer) == []
    as "the connection's death after its leave changes nothing the viewers are sent"
  assert shown_as_made(watched:, id: 4)
    as "and no source or view of it is held on the creature"
  world_support.stop(world: watched.world)
}

/// The cast views the creature's process holds and whether it is retiring, read from its
/// state: the service shell's `Running` holds the creature's state as its fourth field,
/// whose eighth is `retiring` and whose twelfth is `views`, a dictionary by cast id.
fn held_views_and_retiring(pid pid: process.Pid) -> #(Int, Bool) {
  let state = system.get_state(pid)
  let assert Ok(views) =
    decode.run(
      state,
      decode.at([3, 11], decode.dict(decode.int, decode.dynamic)),
    )
    as "the creature's state holds its views"
  let assert Ok(retiring) = decode.run(state, decode.at([3, 7], decode.bool))
    as "the creature's state holds whether it is retiring"
  #(dict.size(views), retiring)
}

pub fn a_dead_retiring_creature_holding_a_view_of_a_caster_drops_it_when_the_casters_connection_ends_before_its_corpse_expires_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  world_watch_support.strike_with(
    run: watched.run,
    unit_id: watched.beast.unit_id,
    life:,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, _, outcome) =
    world_watch_support.heard_up_to_answer(received: watched.caster, cast_id: 1)
  let assert strike_tell.Landed(descriptions: [description], ..) = outcome
  assert description.damage.killed == 1
    as "the 60 damage takes the Beast's 52 health to 0"
  told(watched:, payload: a_view())
  // Both players walk out of sight, so no one sees the corpse and the map retires it
  // at the first sweep after the idle stop.
  world_watch_support.moved_to(
    run: watched.run,
    connection: 1,
    x: 50_000.0,
    z: 0.0,
    seq: 1,
  )
  world_watch_support.moved_to(
    run: watched.run,
    connection: 2,
    x: 50_000.0,
    z: 0.0,
    seq: 1,
  )
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the corpse's 0x355",
  )
  world_watch_support.left_sight(
    received: watched.viewer,
    what: "the corpse's 0x355",
  )
  driven_time.advance(time: watched.time, ms: world_watch_support.idle_stop_ms)
  assert held_views_and_retiring(pid: watched.pid) == #(1, True)
    as "the dead creature told to retire holds the caster's view until its corpse expires"
  world_support.end_connection(world: watched.world, id: 1)
  let _map_took_the_end = system.get_state(watched.run.pid)
  assert held_views_and_retiring(pid: watched.pid) == #(0, True)
    as "the map's CasterGone for the connection's end dropped the view of the dead creature, which still retires"
  world_support.stop(world: watched.world)
}
