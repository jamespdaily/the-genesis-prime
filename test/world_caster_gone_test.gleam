//// What a creature holds for a caster ends with the caster's end, in a running world:
//// real maps, creatures and registry on a driven clock, with plain processes for the
//// players' connections. Expected values come from these places.
//// - The map's word `CasterGone` (genesis_prime/world_map/map, relay): a player's leave and
////   its connection's end are told to every running creature once, by the map alone, and a
////   start or a view is admitted only from a player in the map in the stay named
////   (`relay.inbound_kind_of`), so a caster's holdings on a creature end through one sender.
//// - The creature (genesis_prime/world_map/creature): a creature that takes `CasterGone`
////   drops the connection's sources (each with its property news), views and controls (each
////   with its 0x880), whatever state it is in; a creature watches its map's run and no
////   connection.
//// - A creature's 0x262 lists the casts it holds a view of (`opcode.0x262.casts`) and the
////   properties it holds (`opcode.0x93a`), which a later viewer is shown.

import crowd_control_support
import genesis_prime/client_connection.{type Message, ForStay, SentByPeer}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{
  CrowdControlEnded, PeerNews, PropertiesChanged,
}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/relay
import gleam/erlang/process.{type Subject}
import gleam/list
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
        ForStay(sent: SentByPeer(PeerNews(news: PropertiesChanged(..), ..)), ..) ->
          Ok(PropertiesWritten)
        ForStay(sent: SentByPeer(PeerNews(news: CrowdControlEnded(..), ..)), ..) ->
          Ok(ControlEnded)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

fn told(watched watched: Watched, payload payload: relay.Inbound) -> Nil {
  world_watch_support.told_creature(
    run: watched.run,
    unit_id: watched.beast.unit_id,
    life:,
    payload:,
  )
}

/// The strike of connection 1 on the beast that lands a stun: a state the creature holds
/// for that connection's cast.
fn stunning_strike(watched watched: Watched) -> relay.Inbound {
  let tell = inbound_support.strike(unit_id: watched.beast.unit_id)
  relay.Strike(
    tell: strike_tell.Strike(..tell, controls: [
      crowd_control_support.stagger_stun(instance_id: 28_673),
    ]),
  )
}

fn a_modifier() -> relay.Inbound {
  relay.ModifierStarts(
    source: inbound_support.source(),
    modifier: inbound_support.modifier(),
  )
}

/// The view of cast 1 as the caster's current cast, which a creature's 0x262 lists.
fn a_view() -> relay.Inbound {
  relay.CastViewSet(
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

/// The 0x262 a player that comes into sight of the beast after this is sent.
fn shown_to_a_newcomer(watched watched: Watched) -> UnitCreateCreature {
  let newcomer = world_support.connection(world: watched.world, id: 3)
  let _unit = world_watch_support.join(run: watched.run, connection: 3)
  world_watch_support.next(
    received: newcomer,
    what: "the beast's 0x262",
    wanted: world_watch_support.appearance,
  )
}

/// Whether the newcomer is shown the beast as it was made: no cast held on it and the
/// properties its 0x262 listed first.
fn shown_as_made(watched watched: Watched) -> Bool {
  let shown = shown_to_a_newcomer(watched:)
  shown.tail.casts == []
  && shown.tail.properties == watched.beast.tail.properties
}

pub fn a_start_told_after_its_casters_leave_holds_nothing_on_the_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  told(watched:, payload: a_modifier())
  told(watched:, payload: a_view())
  world_watch_support.left(run: watched.run, connection: 1)
  let _written = heard(watched:, id: 2, received: watched.viewer)
  // The connection that left tells a start and a view again, as one that has not taken
  // its leave yet may.
  told(watched:, payload: a_modifier())
  told(watched:, payload: a_view())
  assert heard(watched:, id: 2, received: watched.viewer) == []
    as "a start told after the caster's leave changes no property the viewers are sent"
  assert shown_as_made(watched:)
    as "a later viewer is shown the creature's base properties and no view of the connection that left"
  world_support.stop(world: watched.world)
}

pub fn a_connection_that_ends_holding_a_modifier_a_view_and_a_control_on_a_creature_leaves_nothing_of_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  holding(watched:)
  world_support.end_connection(world: watched.world, id: 1)
  assert heard(watched:, id: 2, received: watched.viewer)
    == [PropertiesWritten, ControlEnded]
    as "the viewer is written the property restored once and the stun's end once"
  assert list.length(
      mailbox_support.monitored(mailbox_support.settled(watched.pid)),
    )
    == 1
    as "the creature monitors one process, its map's run, and no connection"
  assert shown_as_made(watched:)
    as "a later viewer is shown no view and the base properties"
  world_support.stop(world: watched.world)
}

pub fn a_normal_leave_then_the_connections_death_holds_nothing_and_the_second_end_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  holding(watched:)
  // The camp's step ends the source and the view through the map first; the stun is
  // ended by the leave alone.
  told(watched:, payload: relay.ModifierEnds(source: inbound_support.source()))
  told(
    watched:,
    payload: relay.CastViewEnds(cast_id: inbound_support.view().cast_id),
  )
  world_watch_support.left(run: watched.run, connection: 1)
  assert heard(watched:, id: 2, received: watched.viewer)
    == [PropertiesWritten, ControlEnded]
    as "the connection's own ends write the property restored and the leave ends the stun it never ended"
  assert shown_as_made(watched:)
    as "after the leave a later viewer is shown no source, no view and no stun of the connection"
  world_support.end_connection(world: watched.world, id: 1)
  assert heard(watched:, id: 2, received: watched.viewer) == []
    as "the connection's death after its leave changes nothing the viewers are sent"
  assert shown_as_made(watched:) as "and nothing of it is held on the creature"
  world_support.stop(world: watched.world)
}

pub fn a_creature_that_lies_dead_and_retiring_drops_a_gone_casters_view_before_its_corpse_expires_test() -> Nil {
  use <- owned_test.run(10_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  told(watched:, payload: a_view())
  world_watch_support.strike_with(
    run: watched.run,
    unit_id: watched.beast.unit_id,
    life:,
    damage_type: 3,
    damage: 60,
    cast_id: 9,
  )
  let #(_, _, _) =
    world_watch_support.heard_up_to_answer(received: watched.caster, cast_id: 9)
  // The corpse is told to retire, as the map does when no one has seen it for the idle stop:
  // it lies dead until its corpse timer and holds the view until then.
  let assert Ok(Nil) =
    creature_registry.tell(
      watched.world.creatures,
      map: world_watch_support.ship,
      incarnation: watched.run.incarnation,
      unit_id: watched.beast.unit_id,
      life:,
      message: creature.Retire,
    )
    as "the creature is found by its address and told to retire"
  world_watch_support.left(run: watched.run, connection: 1)
  let shown = shown_to_a_newcomer(watched:)
  assert shown.tail.casts == []
    as "the dead creature that was told to retire was told the caster is gone: a viewer that arrives is shown no view of it"
  world_support.stop(world: watched.world)
}
