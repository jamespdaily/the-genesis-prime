//// A creature that expired and the next life its map starts, in a running world: real
//// maps, creatures and registry on a driven clock, with plain processes for the players'
//// connections. Expected values come from these places.
//// - The Design of run A (issue 1410), 4.1: the creature's corpse timer removes its unit
////   (0x355), tells its map it expired and stops; the map starts the next life under the
////   same unit id, which the viewer is shown created again (0x262), so the client sees the
////   removal and then the creation of the same unit (`death.creature_respawn`).
//// - The creature registry (`creature_registry`): an address is one creature process in
////   one run, so a tell addressed to the life that ended finds no creature.
//// - A creature's life is the number of the watch its map opened on it: the first player's
////   connection takes watch 1, so the first creature a player sees has life 2.
//// - The Virtual Defense Dagun (Creature2 73465) is hostile to the tests' Dominion players
////   and the aggro range is 10 units (migration 0010): a ready player within it is aggroed
////   by a creature that starts.

import ask_support
import cast_support
import driven_time
import genesis_prime/client_connection.{type Message, ForStay, SentByFoe}
import genesis_prime/game/strike_tell.{Threatened}
import genesis_prime/game/unit_news.{CreatureAppeared, PeerNews}
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/service
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{UnitProperty2Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import gleam/erlang/process
import gleam/int
import gleam/list
import map_support
import owned_test
import place_support
import spawn_support
import world_support
import world_watch_support

/// What a connection is shown of a unit, in the order the connection was sent it: the
/// unit removed (0x355), or created (0x262) with the life it names.
type Shown {
  Removed
  Created(unit: UnitCreateCreature, life: Int)
}

fn shown(message: Message) -> Result(Shown, Nil) {
  case world_watch_support.appeared_news(message) {
    Ok(PeerNews(news: CreatureAppeared(unit:, life:, ..), ..)) ->
      Ok(Created(unit:, life:))
    Ok(PeerNews(..)) | Error(Nil) ->
      case world_watch_support.is_removal(message) {
        True -> Ok(Removed)
        False -> Error(Nil)
      }
  }
}

pub fn a_creature_that_expired_is_removed_and_created_again_by_a_new_life_under_the_same_unit_id_and_the_old_address_finds_no_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  let respawn_ms = 1000
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms:,
      idle_stop_ms: 60_000,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let first_life = 2
  let first_pid =
    world_watch_support.creature_pid(
      time:,
      world:,
      run:,
      unit_id: first.unit_id,
      life: first_life,
    )
  // A caster's modifier, which a creature that stood again in its own process cleared.
  let assert Ok(Nil) =
    creature_registry.tell(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: first_life,
      message: creature.ModifierStarts(
        by: ConnectionId(1),
        source: cast_support.source_of(cast_id: 1, effect_id: 1921),
        modifier: Change(
          property: UnitProperty2Id(100),
          mode: 3,
          multiplier: 1.0,
          flat: 0.5,
          per_level: 0.0,
        ),
        struck_at_ms: world_watch_support.clock_ms(time:),
      ),
    )
    as "the creature is found by its address and told"
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: first_life,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, _, _) = world_watch_support.heard_up_to_answer(received:, cast_id: 1)
  driven_time.advance(time:, ms: respawn_ms)
  let removal_then_creation = [
    world_watch_support.next(
      received:,
      what: "the corpse's 0x355 or the next life's 0x262",
      wanted: shown,
    ),
    world_watch_support.next(
      received:,
      what: "the next of the corpse's 0x355 and the next life's 0x262",
      wanted: shown,
    ),
  ]
  let assert [Removed, Created(unit: again, life: next_life)] =
    removal_then_creation
    as "death.creature_respawn: the 0x355 and then the 0x262, from the map's one stream"
  assert again.unit_id == first.unit_id as "the same unit id"
  assert creature_unit.health_of(unit: again) == 52
    && again.tail.properties == []
    as "at full health and from the base properties: no trace of the modifier the first life held"
  assert next_life != first_life
    as "a new life: the map numbers every life, so the address of the life that ended is not the next life's"
  let _ended =
    ask_support.ended(
      watched: process.monitor(first_pid),
      what: "the creature that expired to be gone",
    )
  assert creature_registry.find(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: first_life,
    )
    == Error(Nil)
    as "the registry finds no creature at the old life's address"
  let next_pid =
    world_watch_support.creature_pid(
      time:,
      world:,
      run:,
      unit_id: first.unit_id,
      life: next_life,
    )
  assert next_pid != first_pid
    as "and one at the new life's, a process of its own"
  world_support.stop(world:)
}

pub fn two_ring_players_are_both_aggroed_by_the_life_that_replaces_their_killed_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // A Dagun, hostile to the Dominion players, at x = 0; two ready players stand in its
  // ring, 5 units off either side. The first `Approached` makes a creature fight and later
  // ones add no threat, so a respawn that told the creature of the players one by one would
  // aggro only the first; the batch aggro of a creature that stands again aggroes both
  // (`creature_fight`, `Approached` and `aggro`).
  let respawn_ms = 1000
  let time = driven_time.new()
  let world =
    world_support.start(
      time:,
      spawns: [spawn_support.dagun(number: 1, x: 0.0)],
      respawn_ms:,
      idle_stop_ms: 60_000,
      sweep_ms: world_watch_support.sweep_ms,
    )
  let run = world_watch_support.started(world)
  let first = world_support.connection(world:, id: 1)
  let second = world_support.connection(world:, id: 2)
  let place = fn(x) {
    place_support.at(
      world_id: 3460,
      world_zone_id: spawn_support.warfare_woods,
      x:,
      y: 0.0,
      z: 0.0,
    )
  }
  let _unit_1 =
    world_watch_support.join_at(
      run:,
      connection: 1,
      character: map_support.character(number: 101),
      place: place(5.0),
    )
  let _unit_2 =
    world_watch_support.join_at(
      run:,
      connection: 2,
      character: map_support.character(number: 102),
      place: place(-5.0),
    )
  let beast =
    world_watch_support.next(
      received: first,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let _found =
    world_watch_support.creature_pid(
      time:,
      world:,
      run:,
      unit_id: beast.unit_id,
      life: 2,
    )
  let _ready =
    list.map([1, 2], fn(connection) {
      service.tell_subject(
        run.subject,
        map.Ready(connection: ConnectionId(connection), seq: 0),
      )
    })
  driven_time.wait_until_quiet(time)
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: beast.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, _, _) =
    world_watch_support.heard_up_to_answer(received: first, cast_id: 1)
  driven_time.advance(time:, ms: respawn_ms)
  list.each([#(1, first), #(2, second)], fn(player) {
    let heard =
      world_support.sent_before_the_marker(
        world:,
        id: player.0,
        received: player.1,
      )
    let threatened =
      list.filter_map(heard, fn(message) {
        case message {
          ForStay(sent: SentByFoe(Threatened(unit_id:, ..)), ..) -> Ok(unit_id)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      })
    assert threatened == [beast.unit_id]
      as {
        "the player of connection "
        <> int.to_string(player.0)
        <> " is told it is threatened once by the creature that replaced the killed one"
      }
  })
  world_support.stop(world:)
}
