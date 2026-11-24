//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover other players'
//// units, what an owner sends and what a viewer writes, and the messages of an
//// earlier stay.

import cast_support
import character_tables
import connection_rule_support as support
import fixture_tables
import game_client
import game_connection_support.{type Step, Appears, MapSaysGone, Moves, Removes}
import genesis_prime/client_connection.{
  Appeared, CastFinished, ForStay, FromMap, FromStore, LookChanged, Moving,
  PeerNews, PropertiesChanged, Removed, SentByMap, SentByPeer, TellMoved,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/connection/viewers
import genesis_prime/game/effect_kind
import genesis_prime/game/faction_level
import genesis_prime/game/held_changes
import genesis_prime/game/player_address.{PlayerAddress, Viewer}
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_properties
import genesis_prime/message/crowd_control_state
import genesis_prime/message/float32
import genesis_prime/message/item_place
import genesis_prime/message/movement_command
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_position
import genesis_prime/message/spell_started
import genesis_prime/message/spell_target_info
import genesis_prime/message/spell_targets_removed
import genesis_prime/message/start_movement
import genesis_prime/message/unit_cc_state_applied.{UnitCcStateApplied}
import genesis_prime/message/unit_cc_state_ended.{UnitCcStateEnded}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/step.{
  ConnectionId, LogError, LogInfo, LogWarning, Map, OwnEffect, OwnEvent, Woken,
}
import genesis_prime/store.{Character, ForItems, ForSelect, ItemsSaved, Listed}
import genesis_prime/table/id.{ClassId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/map.{
  Left, ObjectsSeen, ObjectsUnseen, SeenBy, UnseenBy,
}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/static_object.{type Created}
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import map_support
import owned_test
import place_support
import planted_table
import player_state_support
import quest_support
import server_proxy_support
import simple_unit_support
import spawn_support
import world_entry_support

// ---- other players' units ----
//
// Expected values: 0x262, 0x638 and 0x355 are what the client creates, moves
// and removes a unit with (opcode.0x262, opcode.0x638, opcode.0x355); the
// reset bit and the kept bit are 0, the values of a unit the client does not
// control (opcode.0x638); the client keeps one unit per id from its 0x262 to
// its 0x355 and a 0x262 for a unit it has does nothing (0x1403d9760), so a
// viewer writes a 0x262 only for a unit its client does not hold, and a 0x638
// or 0x355 only for one it holds; after the player's own leave the client holds
// no world, so a send for another unit is dropped and nothing is written; an
// accepted 0x637 tells the map where the movement rule says the player stands,
// which is `start_place.moved` of the last position in the world's frame
// (genesis_prime/game/movement).

// ---- the viewer: what it writes ----

/// The messages written for each step, in order, when a viewer in the world is
/// fed the steps one after another.
fn written_by(steps: List(Step)) -> List(List(Int)) {
  let #(_, written) =
    list.fold(steps, #(game_connection_support.in_world(), []), fn(held, step) {
      let #(state, written) = held
      let #(state, taken) =
        game_connection_support.feed(
          state,
          game_connection_support.event_of(step),
        )
      assert !support.stops(taken) && support.logs(taken) == []
        as "a message that lands in any order is no bug"
      #(
        state,
        list.append(written, [game_connection_support.written_ids(taken)]),
      )
    })
  written
}

pub fn a_viewer_writes_a_0x262_only_for_a_unit_its_client_does_not_hold_and_a_0x638_or_0x355_only_for_one_it_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let none = []
  let create = [0x0262]
  let move = [0x0638]
  let remove = [0x0355]
  // Each sequence is what two senders can produce for one unit: the owner's
  // messages in the order it sent them, and the map's Gone after the owner's
  // end, anywhere among them.
  list.each(
    [
      #([Appears], [create]),
      #([Appears, Appears], [create, none]),
      #([Moves], [none]),
      #([Moves, Appears], [none, create]),
      #([Removes], [none]),
      #([Removes, Appears], [none, create]),
      #([Appears, Moves], [create, move]),
      #([Appears, Removes], [create, remove]),
      #([Appears, Removes, Moves], [create, remove, none]),
      #([Appears, Removes, Removes], [create, remove, none]),
      #([Appears, Removes, Appears], [create, remove, create]),
      #([Appears, Moves, Removes, Appears, Moves], [
        create,
        move,
        remove,
        create,
        move,
      ]),
      #([MapSaysGone], [none]),
      #([MapSaysGone, MapSaysGone], [none, none]),
      #([Appears, MapSaysGone], [create, remove]),
      #([Appears, Moves, MapSaysGone, Moves], [create, move, remove, none]),
      #([Appears, MapSaysGone, Removes], [create, remove, none]),
      #([Appears, MapSaysGone, Appears], [create, remove, none]),
      #([MapSaysGone, Appears], [none, none]),
      #([MapSaysGone, Moves], [none, none]),
      #([MapSaysGone, Removes], [none, none]),
      #([MapSaysGone, Appears, Moves], [none, none, none]),
      #([Appears, Removes, MapSaysGone, Appears], [
        create,
        remove,
        none,
        none,
      ]),
    ],
    fn(case_) {
      assert written_by(case_.0) == case_.1
    },
  )
}

pub fn what_a_viewer_writes_is_the_owners_message_as_the_client_takes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let assert [Frame(message_id: 0x0262, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x262: another player is created with the player's own 0x262"
  assert unit_create_player.decode(body)
    == Ok(game_connection_support.another_unit())
  let #(state, taken) =
    game_connection_support.feed(state, game_connection_support.event_of(Moves))
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x638"
  assert unit_movement.decode(body)
    == Ok(UnitMovement(
      unit_id: 9,
      server_time: 7,
      reset_movement: 0,
      kept: 0,
      commands: game_connection_support.moved_unit_commands(),
    ))
    as "the reset bit is 0 (the unit's movement is not rebuilt) and the kept bit 0, with the commands in order"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.event_of(Removes),
    )
  let assert [Frame(message_id: 0x0355, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x355"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 9, chest_world_object_delay: 0))
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.event_of(MapSaysGone),
    )
  let assert [Frame(message_id: 0x0355, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "a unit the map reports gone is removed from the client"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 9, chest_world_object_delay: 0))
}

pub fn a_0x262_or_0x355_naming_the_viewers_own_unit_or_unit_0_is_refused_with_an_error_line_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client makes the controlled unit of a 0x262 with unit id 0 or its own
  // unit's id (0x1403d9760), and removes a unit with a 0x355 (0x1403d9590): neither
  // may be written for a unit that is not another player's.
  list.each([0, game_connection_support.own_unit_id], fn(unit_id) {
    list.each(
      [
        Appeared(
          unit: UnitCreatePlayer(
            ..game_connection_support.another_unit(),
            unit_id:,
          ),
        ),
        Removed,
      ],
      fn(news) {
        let #(state, taken) =
          game_connection_support.feed(
            game_connection_support.in_world(),
            game_connection_support.sent_by_a_peer(
              game_connection_support.news_of(unit_id:, news:),
            ),
          )
        assert support.writes(taken) == []
          as "nothing is written for the viewer's own unit or unit 0"
        assert list.length(support.logs_of(step: taken, level: LogError)) == 1
          as "the owner's connection is wrong: an error line"
        assert !support.stops(taken)
        let #(_, taken) =
          game_connection_support.feed(
            state,
            game_connection_support.event_of(Appears),
          )
        assert game_connection_support.written_ids(taken) == [0x0262]
          as "another player's unit is still written after it"
      },
    )
  })
}

pub fn news_for_another_stay_is_dropped_for_each_kind_and_this_stays_is_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let in_stay = fn(stay, news) {
    game_connection_support.for_stay(
      stay,
      SentByPeer(PeerNews(unit_id: 9, news:)),
    )
  }
  let kinds = [
    Appeared(unit: game_connection_support.another_unit()),
    Moving(
      server_time_ms: 1,
      commands: game_connection_support.moved_unit_commands(),
    ),
    Removed,
    held_cast_started(cast_id: 2_147_497_985, caster: 7),
  ]
  // The unit is shown first, so that every kind would be written but for its stay.
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  list.each(kinds, fn(news) {
    let #(_, taken) =
      game_connection_support.feed(
        shown,
        in_stay(map_support.stay(count: 2), news),
      )
    assert support.writes(taken) == []
      as "another stay: in another run or map the unit id may name another unit"
    assert !support.stops(taken) && support.logs(taken) == []
      as "news that was on its way when the viewer left is no bug"
  })
  let #(_, taken) =
    game_connection_support.feed(
      shown,
      in_stay(game_connection_support.own_stay(), Removed),
    )
  assert game_connection_support.written_ids(taken) == [0x0355]
    as "the stay the viewer is in"
  let #(_, taken) =
    game_connection_support.feed(
      shown,
      in_stay(
        game_connection_support.own_stay(),
        held_cast_started(cast_id: 2_147_497_985, caster: 7),
      ),
    )
  assert game_connection_support.written_ids(taken) == [0x07FF, 0x07F4]
    as "the start an ally tells is written in the stay the viewer is in"
}

pub fn after_the_players_own_leave_nothing_more_is_written_for_other_units_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.camped_out()
  list.each(
    [
      game_connection_support.event_of(Appears),
      game_connection_support.event_of(Moves),
      game_connection_support.event_of(Removes),
      game_connection_support.event_of(MapSaysGone),
    ],
    fn(event) {
      let #(_, taken) = game_connection_support.feed(state, event)
      assert support.writes(taken) == []
        as "the player is in character select: the client holds no world to create, move or remove a unit in"
      assert support.logs_of(step: taken, level: LogError) == []
        as "a send that was on its way when the player left is no bug"
    },
  )
  list.each(
    [
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
      )),
      game_connection_support.sent_by_the_map(UnseenBy(by: ConnectionId(2))),
    ],
    fn(event) {
      let #(_, taken) = game_connection_support.feed(state, event)
      assert support.effects_of(taken) == []
        as "a notice for a player that is not in the world changes nothing and sends nothing"
    },
  )
}

pub fn a_player_that_enters_again_shows_no_unit_and_has_none_gone_test() -> Nil {
  use <- owned_test.run(10_000)
  // Unit 9 is shown, camped away from, and the player enters the same map again:
  // the client holds no unit, so the unit is created once more.
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let #(state, _) =
    game_connection_support.read(
      shown,
      game_connection_support.camp_request_message(True),
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Left)),
    )
  assert game_connection_support.written_ids(taken) == [0x0594]
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(again, _) =
    game_connection_support.entered_from(
      state,
      game_connection_support.world_character(),
    )
  let #(_, taken) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(game_connection_support.event_of(
        Appears,
      )),
    )
  assert game_connection_support.written_ids(taken) == [0x0262]
    as "what the player's client held before its camp is not held now"
}

// ---- the owner: what it sends ----

/// What an owner standing at `place` sends a viewer: the record it was entered
/// with (the client's own 0x262 of it, `player_in`) at that place, stamped
/// `time_ms` on the map's clock, without its class resource: the test player is an
/// Engineer, whose resource is stat 3 and ResourceMax property 10. The entry then
/// starts the Engineer's passive (Class.spell4IdInnateAbilityPassive00, Spell4 45000),
/// whose effects 104980, 177521, 177522 and 229304 write properties 141 to 143
/// (DamageDealtMultiplier, default 1.0) and 60 (RatingMultiHitAmount, converted from
/// property 47), each still at its UnitProperty2 default; the owner's record lists them.
fn appearance_at(
  place place: Place,
  time_ms time_ms: Int,
  casts casts: List(UnitCreateCast),
) -> UnitCreatePlayer {
  let #(position, rotation) = player_unit.standing(place)
  let player =
    game_connection_support.player_in(game_connection_support.entered().1)
  UnitCreatePlayer(
    ..player,
    tail: UnitCreateTail(
      ..player.tail,
      stats: list.filter(player.tail.stats, fn(stat) { stat.stat_id != 3 }),
      properties: list.sort(
        list.append(
          list.filter(player.tail.properties, fn(property) {
            property.property_id != 10
          }),
          [
            UnitProperty(property_id: 60, base: 0, value: 0),
            UnitProperty(property_id: 141, base: 0x3F800000, value: 0x3F800000),
            UnitProperty(property_id: 142, base: 0x3F800000, value: 0x3F800000),
            UnitProperty(property_id: 143, base: 0x3F800000, value: 0x3F800000),
          ],
        ),
        fn(left, right) { int.compare(left.property_id, right.property_id) },
      ),
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      server_time_estimate_start: time_ms,
      casts:,
    ),
  )
}

/// The cast the Engineer's passive (Spell4 45000) is in a unit create: a cast of the unit
/// on itself, in state 3 (its first go has gone), with its own unit as the one target and
/// each of its four property rows (Spell4Effects 104980, 177521 and 177522, type 11, and
/// 229304, type 145 UnitPropertyConversion: all flags 2, until removed, each a modifier row
/// that gives the node its life) numbered from 1, delay 0 and lifetime 0. The cast id is
/// the cast rule's counter, which no client rule fixes.
fn engineer_passive(cast_id cast_id: Int) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: game_connection_support.own_unit_id,
    primary_target_unit_id: game_connection_support.own_unit_id,
    cast_id:,
    spell4_id: 45_000,
    started: 0,
    targets: [
      own_target(
        effects: list.index_map(
          [104_980, 177_521, 177_522, 229_304],
          fn(effect_id, index) {
            cast_support.listed_effect_info(
              effect_id:,
              instance_id: index + 1,
              delay_ms: 0,
              lifetime_ms: 0,
            )
          },
        ),
      ),
    ],
    initial_positions: [],
    telegraph_positions: [],
  )
}

pub fn a_watched_makes_the_owner_send_the_viewer_its_0x262_at_its_current_place_stamped_from_the_maps_clock_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
      )),
    )
  let assert [#(2, PeerNews(news: Appeared(unit: created), ..))] =
    game_connection_support.peer_tells(taken)
    as "the viewer is sent the unit at once"
  let assert [passive] = created.tail.casts
    as "the Engineer's innate passive is the one cast it holds"
  assert game_connection_support.peer_tells(taken)
    == [
      #(
        2,
        game_connection_support.told(
          news: Appeared(
            unit: appearance_at(
              place: game_connection_support.entry_place(),
              time_ms: 1000,
              casts: [engineer_passive(cast_id: passive.cast_id)],
            ),
          ),
        ),
      ),
    ]
    as "the viewer is sent the unit at once, from the origin the map's Joined carried: the map sends the client no unit, and its copy lists the passive's buffs"
  assert support.writes(taken) == []
}

pub fn a_viewers_copy_of_a_player_carries_no_class_resource_stat_or_maximum_test() -> Nil {
  use <- owned_test.run(30_000)
  // The player's own 0x262 holds the class slot as a stat (slot + 2) and its
  // ResourceMax property (opcode.0x262.resource_stats, UnitProperty2.ResourceMax_0), and
  // a healer's Focus as stat 1 and property 5 (`ApplyUnitStat` 0x1403d9a60 case 1,
  // `GetMaxFocus` 0x14064a810); a 0x935 goes to the player only, so a viewer's copy of a
  // stat would go stale (the step's design). Property 5 is the true maximum and stays.
  // Class id, the class slot's stat and maximum property, whether Focus is held.
  [
    #(2, 3, 10, False),
    #(3, 3, 10, True),
    #(4, 3, 10, True),
    #(7, 6, 13, True),
  ]
  |> list.each(fn(row) {
    let #(class_id, resource_stat, resource_max, holds_focus) = row
    let #(state, entered) =
      game_connection_support.entered_as(
        Character(
          ..game_connection_support.world_character(),
          class_id: ClassId(class_id),
        ),
      )
    let own = game_connection_support.player_in(entered)
    assert list.any(own.tail.stats, fn(stat) { stat.stat_id == resource_stat })
      && list.any(own.tail.properties, fn(property) {
        property.property_id == resource_max
      })
      as "the player's own record carries the class resource"
    assert list.any(own.tail.stats, fn(stat) { stat.stat_id == 1 })
      == holds_focus
      && list.any(own.tail.properties, fn(property) {
        property.property_id == 5
      })
      == holds_focus
      as "and a healer's own record carries Focus: stat 1 and property 5"
    let #(_, taken) =
      game_connection_support.feed(
        state,
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(2),
          stay: game_connection_support.viewer_stay(2),
          unit_id: game_connection_support.viewer_unit_id(2),
        )),
      )
    let assert [#(2, PeerNews(news: Appeared(unit:), ..))] =
      game_connection_support.peer_tells(taken)
    assert list.map(unit.tail.stats, fn(stat) { stat.stat_id }) == [0, 10, 20]
      as "health, level and shield only: no class slot's stat and no stat 1"
    assert !list.any(unit.tail.properties, fn(property) {
      property.property_id == resource_max
    })
      as "no ResourceMax of the class slot"
    assert list.any(unit.tail.properties, fn(property) {
        property.property_id == 5
      })
      == holds_focus
      as "property 5, the Focus maximum, stays: it is a gear budget property like the rest and 0x93a keeps it current"
  })
}

pub fn a_move_the_owner_took_before_a_watched_is_in_the_0x262_the_new_viewer_is_sent_test() -> Nil {
  use <- owned_test.run(10_000)
  // The owner moves with nobody watching, then the map tells it a player sees it.
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.moves_message([
        game_client.position_command(x: 1.5, y: 2.5, z: 3.5),
      ]),
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
      )),
    )
  let assert [#(2, PeerNews(news: Appeared(unit:), ..))] =
    game_connection_support.peer_tells(taken)
  let assert [start_movement.Position(at), start_movement.Rotation(_)] =
    unit.tail.movement_commands
  assert at.x == float32.to_bits(1.5)
    && at.y == float32.to_bits(2.5)
    && at.z == float32.to_bits(3.5)
    as "the place the owner stands at now, not the one it entered at"
}

pub fn an_unwatched_makes_the_owner_send_that_viewer_its_0x355_and_no_more_moves_test() -> Nil {
  use <- owned_test.run(10_000)
  let moves =
    game_connection_support.moves_message([
      game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
    ])
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [
      2,
      3,
    ])
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(by: ConnectionId(2))),
    )
  assert game_connection_support.peer_tells(taken)
    == [#(2, game_connection_support.told(news: Removed))]
    as "the viewer that stops seeing the unit is sent its removal, and only that one"
  assert list.map(
      game_connection_support.peer_tells(
        game_connection_support.read(state, moves).1,
      ),
      fn(sent) { sent.0 },
    )
    == [3]
    as "a viewer the map took back is sent no more moves"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(by: ConnectionId(8))),
    )
  assert game_connection_support.peer_tells(taken) == []
    && support.logs(taken) == []
    as "an Unwatched for a connection that is no viewer changes nothing and is no bug"
}

pub fn a_watched_twice_sends_the_0x262_twice_and_is_one_viewer_for_the_moves_test() -> Nil {
  use <- owned_test.run(10_000)
  let moves =
    game_connection_support.moves_message([
      game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
    ])
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [
      2,
      2,
    ])
  assert list.map(
      game_connection_support.peer_tells(
        game_connection_support.read(state, moves).1,
      ),
      fn(sent) { sent.0 },
    )
    == [2]
    as "a viewer the map named twice is sent one move: the viewer's own record drops the second 0x262"
}

pub fn the_owners_camp_sends_each_viewer_its_0x355_before_the_leave_is_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [
        3,
        2,
      ]),
      game_connection_support.camp_request_message(True),
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.peer_tells(taken)
    == [
      #(2, game_connection_support.told(news: Removed)),
      #(3, game_connection_support.told(news: Removed)),
    ]
    as "its 0x355 to every viewer: the map's Unwatched after the leave would be a second sender"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.leave_asked()
    as "and the leave of the map is asked in the same step, after the tells"
}

pub fn an_accepted_0x637_tells_the_map_the_place_the_movement_keeps_and_nothing_else_test() -> Nil {
  use <- owned_test.run(10_000)
  let sent = [
    movement_command.Time(MovementTime(time: 99)),
    game_client.position_command(x: 1.5, y: 2.5, z: 3.5),
    movement_command.Mode(MovementMode(mode: 1)),
  ]
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.moves_message(sent),
    )
  assert game_connection_support.told_the_map(taken)
    == [
      OwnEffect(step.Tell(
        to: Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
        request: TellMoved(
          connection: ConnectionId(1),
          place: game_connection_support.standing_at(x: 1.5, y: 2.5, z: 3.5),
          seq: 1,
        ),
      )),
    ]
    as "the place is the movement's (the last position of the world's frame); the map decides sight and carries no move; the map is the run the connection watches; the first accepted 0x637 of the connection is its move 1"
  assert game_connection_support.peer_tells(taken) == []
    as "no viewer: no 0x638 is sent"
}

pub fn an_accepted_0x637_sends_one_0x638_to_each_viewer_with_the_relayed_commands_in_order_stamped_from_the_maps_clock_test() -> Nil {
  use <- owned_test.run(10_000)
  let sent = [
    movement_command.Time(MovementTime(time: 99)),
    game_client.position_command(x: 1.5, y: 2.5, z: 3.5),
    movement_command.Mode(MovementMode(mode: 1)),
  ]
  let relayed = [
    relayed_movement.Position(UnitPositionCommand(
      x: 0x3FC00000,
      y: 0x40200000,
      z: 0x40600000,
      blends: 0,
    )),
    relayed_movement.Mode(MovementMode(mode: 1)),
  ]
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [
        3,
        2,
      ]),
      game_connection_support.moves_message(sent),
    )
  assert game_connection_support.peer_tells(taken)
    == [
      #(
        2,
        game_connection_support.told(news: Moving(
          server_time_ms: 1000,
          commands: relayed,
        )),
      ),
      #(
        3,
        game_connection_support.told(news: Moving(
          server_time_ms: 1000,
          commands: relayed,
        )),
      ),
    ]
    as "one 0x638 per viewer, never to the mover itself, the commands in the order sent without kind 0, the sender's own clock (movement_command.kind_0); the time is the input's 1000 ms from the map's origin 0"
}

pub fn a_move_of_40_commands_is_sent_to_each_viewer_as_31_and_9_in_order_and_the_encoder_refuses_32_test() -> Nil {
  use <- owned_test.run(10_000)
  let commands =
    list.index_map(list.repeat(Nil, 40), fn(_, n) {
      game_client.position_command(x: int.to_float(n), y: 0.0, z: 0.0)
    })
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [2]),
      game_connection_support.moves_message(commands),
    )
  let assert [
    #(2, PeerNews(news: Moving(commands: first, ..), ..)),
    #(2, PeerNews(news: Moving(commands: second, ..), ..)),
  ] = game_connection_support.peer_tells(taken)
    as "opcode.0x638: the count is 5 bits, so 40 commands are two messages"
  assert list.length(first) == 31 && list.length(second) == 9
  assert unit_movement.encode(UnitMovement(
      unit_id: game_connection_support.own_unit_id,
      server_time: 1,
      reset_movement: 0,
      kept: 0,
      commands: list.append(first, [
        relayed_movement.Mode(MovementMode(mode: 0)),
      ]),
    ))
    |> result.is_error
    as "32 commands do not fit the 5-bit count"
}

pub fn an_owners_clock_is_the_origin_joined_carried_mod_2_to_the_32_for_its_0x638_and_its_0x262_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.joining()
  let assert map.Joined(unit:, loadout:, incarnation:, clock_origin_ms: _) =
    game_connection_support.map_answer(taken)
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(map.Joined(unit:, loadout:, incarnation:, clock_origin_ms: 600)),
      ),
    )
  let moves =
    game_connection_support.moves_message([
      game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
    ])
  let at = fn(monotonic_ms, event) {
    game_connection.step(state, support.input_at_ms(ms: monotonic_ms, event:)).1
  }
  let move_time = fn(monotonic_ms) {
    let state = game_connection_support.watched_by(state, [2])
    let taken =
      game_connection.step(
        state,
        support.input_at_ms(ms: monotonic_ms, event: OwnEvent(step.Read(moves))),
      ).1
    let assert [#(2, PeerNews(news: Moving(server_time_ms:, ..), ..))] =
      game_connection_support.peer_tells(taken)
    server_time_ms
  }
  let create_time = fn(monotonic_ms) {
    let assert [#(2, PeerNews(news: Appeared(unit:), ..))] =
      game_connection_support.peer_tells(at(
        monotonic_ms,
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(2),
          stay: game_connection_support.viewer_stay(2),
          unit_id: game_connection_support.viewer_unit_id(2),
        )),
      ))
    unit.tail.server_time_estimate_start
  }
  assert move_time(600 + 250) == 250
    as "the map started at 600 ms on the monotonic clock, so 850 is 250 ms into its life"
  assert move_time(600 + 4_294_967_296 + 900) == 900
    as "the 32-bit field wraps after 49.7 days of one map's life, as the map's own clock does"
  assert create_time(600 + 400) == 400
  assert create_time(600 + 4_294_967_296 + 100) == 100
}

pub fn a_viewer_set_is_empty_after_a_camp_and_a_new_join_and_comes_back_only_by_the_maps_new_notices_test() -> Nil {
  use <- owned_test.run(10_000)
  let moves =
    game_connection_support.moves_message([
      game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
    ])
  // The player has viewers, camps out, picks its character again and enters.
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [2]),
      game_connection_support.camp_request_message(True),
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Left)),
    )
  assert game_connection_support.written_ids(taken) == [0x0594]
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(again, _) =
    game_connection_support.entered_from(
      state,
      game_connection_support.world_character(),
    )
  assert game_connection_support.peer_tells(
      game_connection_support.read(again, moves).1,
    )
    == []
    as "the player that camped and entered again starts with no viewers, whoever saw the first one"
  let #(again, _) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(4),
          stay: game_connection_support.viewer_stay(4),
          unit_id: game_connection_support.viewer_unit_id(4),
        )),
      ),
    )
  assert list.map(
      game_connection_support.peer_tells(
        game_connection_support.read(again, moves).1,
      ),
      fn(sent) { sent.0 },
    )
    == [4]
    as "the map's join sends the new notices"
}

pub fn a_refused_0x637_tells_the_map_and_the_viewers_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.refused_messages(), fn(refused) {
    let #(bytes, why) = refused
    let #(_, taken) =
      game_connection_support.read(
        game_connection_support.watched_by(game_connection_support.in_world(), [
          2,
        ]),
        bytes,
      )
    assert game_connection_support.told_the_map(taken) == [] as why
    assert game_connection_support.peer_tells(taken) == [] as why
  })
}

pub fn a_0x637_with_nothing_to_relay_tells_nobody_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [2]),
      game_connection_support.moves_message([
        movement_command.Time(MovementTime(time: 5)),
      ]),
    )
  assert game_connection_support.told_the_map(taken) == []
    && game_connection_support.peer_tells(taken) == []
    as "kind 0 alone is the sender's own clock: nothing to relay"
}

pub fn a_command_kind_that_is_not_relayed_is_named_once_a_connection_and_not_relayed_test() -> Nil {
  use <- owned_test.run(10_000)
  let unrelayed = movement_command.Kind10(MovementKind10(blends: 0))
  let message =
    game_connection_support.moves_message([
      unrelayed,
      game_client.position_command(x: 1.0, y: 1.0, z: 1.0),
    ])
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [2]),
      message,
    )
  let assert [line] = support.logs_of(step: first, level: LogInfo)
    as "an info line names the kind"
  assert support.says(line, words: "kind 10")
  let assert [#(2, PeerNews(news: Moving(commands:, ..), ..))] =
    game_connection_support.peer_tells(first)
  assert list.length(commands) == 1 as "the kind 10 is not relayed"
  let #(_, second) = game_connection_support.read(state, message)
  assert support.logs_of(step: second, level: LogInfo) == []
    as "named once on a connection"
}

// ---- messages of an earlier stay
//
// Expected values: each join of a map is a new stay of the player, after every
// earlier one (genesis_prime/world_map/stay). A message sent for one stay can
// reach the connection after the leave that ended it (the Holocrypt's, the
// camp's) and the next join, even in the same run of the map, or in a run that
// restarted and gave the player the same unit id again. That client holds none
// of the earlier stay's units and fights none of its creatures, so such a message
// is dropped: nothing written, told or answered. The same message for the stay
// the player is in is taken.

/// What other processes send the tests' player for a stay, in an order the
/// player takes each of: the map's `SeenBy` of connection 3, a peer's 0x262 of
/// unit 9, a creature's threat, its strike on the player's unit `unit_id`, a heal
/// strike of the player of connection 3 (answered by a tell, which is its effect),
/// and the creature's release.
fn stay_messages(
  unit_id unit_id: Int,
) -> List(#(String, client_connection.StaySent)) {
  let assert OwnEvent(Woken(ForStay(sent: strike, ..))) =
    game_connection_support.a_beast_strike(unit_id)
    as "a strike is a creature's message for a stay"
  [
    #(
      "the map's SeenBy",
      SentByMap(SeenBy(
        by: ConnectionId(3),
        stay: game_connection_support.viewer_stay(3),
        unit_id: game_connection_support.viewer_unit_id(3),
      )),
    ),
    #(
      "a peer's 0x262",
      SentByPeer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(unit: game_connection_support.another_unit()),
      )),
    ),
    #(
      "a creature's threat",
      client_connection.SentByFoe(strike_tell.Threatened(unit_id: 7, life: 3)),
    ),
    #("a creature's strike", strike),
    #(
      "a player's heal strike",
      game_connection_support.a_player_strike(
        from: 3,
        stay: game_connection_support.viewer_stay(3),
        cast_id: 100,
        outgoing: 1.0,
        heals: [#(effect_kind.Health, 40)],
      ),
    ),
    #(
      "a creature's release",
      client_connection.SentByFoe(strike_tell.Released(unit_id: 7)),
    ),
  ]
}

/// Checks the tests' player in `state`, in its stay `stay` as unit `unit_id`
/// after its first stay as unit 5: each message of the first stay is dropped,
/// and each of `stay`, in order, is taken.
fn takes_only_its_own_stay(
  state state: game_connection.State,
  stay stay: Stay,
  unit_id unit_id: Int,
) -> Nil {
  list.each(
    stay_messages(unit_id: game_connection_support.own_unit_id),
    fn(message) {
      let #(_, taken) =
        game_connection_support.feed(
          state,
          game_connection_support.for_stay(
            game_connection_support.own_stay(),
            message.1,
          ),
        )
      assert support.effects_of(taken) == []
        as { message.0 <> " of the stay before is dropped" }
    },
  )
  list.fold(stay_messages(unit_id:), state, fn(state, message) {
    let #(state, taken) =
      game_connection_support.feed(
        state,
        game_connection_support.for_stay(stay, message.1),
      )
    assert support.effects_of(taken) != []
      as { message.0 <> " of this stay is taken" }
    state
  })
  Nil
}

pub fn a_strike_answer_of_the_stay_before_a_camp_is_dropped_though_the_next_stays_strike_has_its_key_test() -> Nil {
  use <- owned_test.run(10_000)
  // The cast rule counts its casts from 1 in each stay and the Beast is unit 40 in
  // both, so the next stay's strike has the key of the earlier one: an answer of
  // the earlier strike, delayed past the camp and the entry, would close the new
  // round with what the old strike did.
  let medic =
    Character(..game_connection_support.world_character(), class_id: ClassId(4))
  let #(first, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(_, pressed) =
    game_connection_support.press_paralytic_surge(
      state: first,
      client_cast_id: 1,
    )
  let assert [#(40, old_key)] = game_connection_support.strikes_told(pressed)
  let #(again, _) =
    game_connection_support.entered_from(
      game_connection_support.camp_from(first),
      medic,
    )
  let #(again, _) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(
        game_connection_support.beast_appears(unit_id: 40),
      ),
    )
  let #(again, pressed) =
    game_connection_support.press_paralytic_surge(
      state: again,
      client_cast_id: 1,
    )
  let assert [#(40, key)] = game_connection_support.strikes_told(pressed)
  assert key == old_key as "the same key in both stays"
  let #(_, late) =
    game_connection_support.feed(again, game_connection_support.landed(key:))
  assert !list.contains(game_connection_support.written_ids(late), 0x07F4)
    as "the earlier stay's answer closes no round of this stay: no go is written"
  let #(_, own) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(game_connection_support.landed(
        key:,
      )),
    )
  assert list.contains(game_connection_support.written_ids(own), 0x07F4)
    as "this stay's answer closes the round: its go is written"
}

pub fn messages_of_the_stay_before_the_holocrypt_are_dropped_after_its_join_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.at_the_holocrypt()
  assert game_connection_support.player_in(taken).unit_id == 6
  takes_only_its_own_stay(state:, stay: map_support.stay(count: 2), unit_id: 6)
}

pub fn messages_of_the_stay_before_a_camp_are_dropped_after_the_next_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(camped, _) = game_connection_support.camped_out()
  let #(state, taken) =
    game_connection_support.read(camped, game_connection_support.select_start())
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(state, taken) =
    game_connection_support.joining_from(
      state,
      game_connection_support.world_character(),
    )
  let #(_, joined) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_after_a_stay(),
      taken:,
    )
  let #(state, entry) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(joined)),
    )
  assert game_connection_support.player_in(entry).unit_id == 6
  takes_only_its_own_stay(state:, stay: map_support.stay(count: 2), unit_id: 6)
}

pub fn messages_of_the_stay_before_are_dropped_in_a_restarted_run_that_gives_the_same_unit_id_test() -> Nil {
  use <- owned_test.run(10_000)
  // The Holocrypt's join reaches a run of the map that started after the old one
  // ended, with four players in it: it gives the player unit 5 again, the unit
  // id of the stay before.
  let #(state, taken) =
    game_connection_support.at_the_holocrypt_in(
      game_connection_support.map_run_with_four_players(
        game_connection_support.incarnation + 1,
      ),
    )
  assert game_connection_support.player_in(taken).unit_id
    == game_connection_support.own_unit_id
  takes_only_its_own_stay(
    state:,
    stay: map_support.stay(count: 2),
    unit_id: game_connection_support.own_unit_id,
  )
}

// ---- static objects ----
//
// Expected values: the map owns static objects and tells the connection which
// its player sees (`ObjectsSeen`) and stops seeing (`ObjectsUnseen`), the
// issue's "Design" artifact; the client keeps one unit per id from its 0x262 to
// its 0x355 and ignores a 0x262 for an id it holds (`opcode.0x262`), and removes a
// unit with a 0x355 (`opcode.0x355`), so a viewer writes a 0x262 only for an
// object its client does not show and is not gone, and a 0x355 only for one it
// shows.

/// The 0x262 of a Holoring (Creature2 73416, a type 10 object of world 3460's
/// start) as unit `unit_id`.
fn object_unit(unit_id: Int) -> Created {
  static_object.create(
    object: spawn_support.holoring(
      number: unit_id,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x: 1.0,
        y: 2.0,
        z: 3.0,
      ),
    ),
    unit_id:,
    server_time_estimate_start: 0,
  )
}

pub fn objects_seen_writes_a_0x262_for_each_object_not_shown_and_not_gone_and_nothing_twice_test() -> Nil {
  use <- owned_test.run(10_000)
  // Unit 9 is gone (the map's Gone of a player's unit, `MapSaysGone`): no 0x262 is
  // written for it, so no ghost is made.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(MapSaysGone),
    )
  let seen =
    game_connection_support.sent_by_the_map(
      ObjectsSeen(units: [object_unit(20), object_unit(9), object_unit(21)]),
    )
  let #(state, taken) = game_connection_support.feed(state, seen)
  let written =
    game_connection_support.heard(taken, game_connection_support.keyed())
  assert list.map(written, fn(frame) { frame.message_id }) == [0x0262, 0x0262]
    as "one 0x262 for each object not shown and not gone"
  assert list.map(written, fn(frame) {
      unit_create_static.decode(frame.body)
      |> result.map(fn(unit) { unit.unit_id })
    })
    == [Ok(20), Ok(21)]
    as "each is the object's own 0x262, in the notice's order"
  let #(_, again) = game_connection_support.feed(state, seen)
  assert support.writes(again) == []
    as "the client already shows both: nothing is written"
}

pub fn objects_unseen_writes_a_0x355_for_each_shown_object_and_none_for_one_not_shown_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(
        ObjectsSeen(units: [object_unit(20)]),
      ),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(ObjectsUnseen(unit_ids: [20, 22])),
    )
  let assert [Frame(message_id: 0x0355, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "one 0x355, for the shown object 20 and not for 22"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 20, chest_world_object_delay: 0))
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(
        ObjectsSeen(units: [object_unit(20)]),
      ),
    )
  assert game_connection_support.written_ids(taken) == [0x0262]
    as "removed, the object is created again when it is seen again"
}

pub fn an_object_notice_naming_the_players_own_unit_or_unit_0_writes_nothing_for_it_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client makes the controlled unit of a 0x262 with unit id 0 or its own
  // unit's id (0x1403d9760), and removes a unit with a 0x355 (0x1403d9590): the
  // other units of the same notice are written.
  let own = game_connection_support.own_unit_id
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(
        ObjectsSeen(units: [object_unit(own), object_unit(20), object_unit(0)]),
      ),
    )
  assert list.map(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      fn(frame) {
        unit_create_static.decode(frame.body)
        |> result.map(fn(unit) { #(frame.message_id, unit.unit_id) })
      },
    )
    == [Ok(#(0x0262, 20))]
    as "a 0x262 for object 20 only"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 2
    as "an error line for each of unit 0 and the player's own unit"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(
        ObjectsUnseen(unit_ids: [own, 20, 0]),
      ),
    )
  let assert [Frame(message_id: 0x0355, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "a 0x355 for object 20 only"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 20, chest_world_object_delay: 0))
  assert list.length(support.logs_of(step: taken, level: LogError)) == 2
    as "an error line for each of unit 0 and the player's own unit"
}

pub fn an_object_notice_for_another_stay_is_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(
        ObjectsSeen(units: [object_unit(20)]),
      ),
    )
  list.each(
    [ObjectsSeen(units: [object_unit(21)]), ObjectsUnseen(unit_ids: [20])],
    fn(notice) {
      let #(_, taken) =
        game_connection_support.feed(
          shown,
          game_connection_support.for_stay(
            map_support.stay(count: 2),
            SentByMap(notice),
          ),
        )
      assert support.effects_of(taken) == []
        as "a notice of another stay names units of another run or map"
    },
  )
}

pub fn a_shown_units_crowd_control_news_is_written_as_0x87f_and_0x880_and_none_for_a_unit_not_shown_test() -> Nil {
  use <- owned_test.run(10_000)
  // Unit 9 is shown by `Appears`; unit 77 is not. The states' news comes from the
  // creature that owns the unit, for the viewer's stay (`opcode.0x87f`, `opcode.0x880`).
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let news_of = fn(unit_id, news) {
    game_connection_support.for_stay(
      game_connection_support.own_stay(),
      SentByPeer(PeerNews(unit_id:, news:)),
    )
  }
  let applied =
    client_connection.CrowdControlApplied(
      state: crowd_control_state.Knockdown,
      instance_id: 28_673,
    )
  let ended =
    client_connection.CrowdControlEnded(
      state: crowd_control_state.Knockdown,
      cast_id: 2_147_500_000,
      instance_id: 28_673,
    )
  let #(_, taken) = game_connection_support.feed(shown, news_of(9, applied))
  let assert [Frame(message_id: 0x087F, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x87f"
  assert unit_cc_state_applied.decode(body)
    == Ok(UnitCcStateApplied(
      unit_id: 9,
      state: crowd_control_state.Knockdown,
      instance_id: 28_673,
    ))
  let #(_, taken) = game_connection_support.feed(shown, news_of(9, ended))
  let assert [Frame(message_id: 0x0880, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x880"
  assert unit_cc_state_ended.decode(body)
    == Ok(UnitCcStateEnded(
      unit_id: 9,
      state: crowd_control_state.Knockdown,
      cast_id: 2_147_500_000,
      instance_id: 28_673,
      keeps_flag_4_entries: 0,
    ))
  list.each([applied, ended], fn(news) {
    let #(_, taken) = game_connection_support.feed(shown, news_of(77, news))
    assert support.writes(taken) == []
      as "a unit the viewer's client does not show is written nothing"
  })
}

pub fn a_shown_units_interrupt_armor_news_is_written_as_0x938_of_stat_21_and_none_for_a_unit_not_shown_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let news_of = fn(unit_id) {
    game_connection_support.for_stay(
      game_connection_support.own_stay(),
      SentByPeer(PeerNews(
        unit_id:,
        news: client_connection.InterruptArmor(armor: 1),
      )),
    )
  }
  let #(_, taken) = game_connection_support.feed(shown, news_of(9))
  let assert [Frame(message_id: 0x0938, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x938"
  assert unit_stat_changed.decode(body)
    == Ok(UnitStatChanged(
      unit_id: 9,
      change: unit_stat_change.InterruptArmor(UnitStatInterruptArmor(value: 1)),
    ))
    as "stat 21 with the current armor (opcode.0x938.interrupt_armor)"
  let #(_, taken) = game_connection_support.feed(shown, news_of(77))
  assert support.writes(taken) == []
    as "a unit the viewer's client does not show is written nothing"
}

pub fn a_viewer_that_leaves_between_the_save_and_the_news_is_dropped_like_other_news_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [
      2,
      3,
    ])
  // The chest comes off: the store is asked to move it.
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.item_moved_message(
        from: item_place.ItemPlace(location: 0, bag_index: 0),
        to: item_place.ItemPlace(location: 1, bag_index: 0),
      ),
    )
  let #(state, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  // The map's UnseenBy of viewer 2 comes while the ask is out, and the shell takes it
  // only after the answer's step (genesis_prime/game/connection/viewers.map_sent), so
  // the news goes to both viewers held when the answer comes, and viewer 2's removal
  // follows it.
  let #(_, unseen) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(by: ConnectionId(2))),
    )
  list.each([2, 3], fn(viewer) {
    let assert [LookChanged(..), PropertiesChanged(..), ..] =
      game_connection_support.news_told(taken: answered, viewer:)
      as "each viewer held when the answer comes is told the look and then the properties"
    Nil
  })
  assert game_connection_support.news_told(taken: unseen, viewer: 2)
    == [Removed]
    as "then the viewer that left is told the unit is removed"
  assert game_connection_support.news_told(taken: unseen, viewer: 3) == []
    as "and the viewer that stayed is told nothing more"
  // The viewer's own connection: its client showed the unit, then the map said the unit
  // is gone, so the look and the properties the player told it find no unit shown and
  // are dropped, as any news of a unit not shown is. A viewer that still shows the unit
  // writes them, so the empty writes are the drop and not news the viewer never writes.
  let told =
    list.take(game_connection_support.news_told(taken: answered, viewer: 2), 2)
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let #(gone, _) =
    game_connection_support.feed(
      shown,
      game_connection_support.event_of(MapSaysGone),
    )
  let written = fn(state, news) {
    game_connection_support.written_ids(
      game_connection_support.feed(
        state,
        game_connection_support.news_sent_by_a_peer(unit_id: 9, news:),
      ).1,
    )
  }
  assert list.map(told, written(shown, _)) == [[0x0933], [0x093A]]
    as "a viewer whose client shows the unit writes 0x933 for the look and 0x93a for the properties"
  assert list.map(told, written(gone, _)) == [[], []]
    as "a viewer whose client no longer shows the unit writes nothing"
}

/// The player's picture keeps each object with its faction's disposition toward the
/// player's faction, so a click on it is judged as the client judges a unit
/// (`0x14045a950`): the Faction2 rows make faction 170 Hostile to the Exile and 219 not,
/// and a Hostile unit's quest kinds are dropped (`0x14047a060`). Creature2 12545 is a
/// Simple unit that gives and receives quest 3689, which the Exile holds.
pub fn an_object_is_shown_with_its_factions_hostility_test() -> Nil {
  use <- owned_test.run(10_000)
  let exile =
    game_connection_support.in_world_as_exile_holding(quests: [
      quest_support.accepted(3689, progress: []),
    ])
  let clicked = fn(faction_id) {
    game_connection_support.interaction_requested(
      state: simple_unit_support.seen_by(
        state: exile,
        creature_id: 12_545,
        faction_id:,
        gap: 1.0,
      ),
      unit_id: simple_unit_support.unit,
      kind: 37,
    ).1
  }
  let neutral = clicked(219)
  assert game_connection_support.written_ids(neutral) == [0x0357]
    as "an object of faction 219 is not Hostile to the Exile: its dialog opens"
  let hostile = clicked(170)
  assert game_connection_support.written_ids(hostile) == []
    as "an object of faction 170 is Hostile to the Exile: nothing is answered"
  let assert [line] = support.logs_of(step: hostile, level: LogWarning)
    as "and the refusal is logged once"
  assert support.says(line:, words: "Hostile")
    as "the line says the unit is Hostile to the player"
}

/// A thrown creature's flight is a 0x638 of kind 0 then kind 3 (`movement_command.kind_0`,
/// `movement_command.kind_3`): the map's time (the monotonic time less the map's start,
/// 600 ms here) at each of the path's times and the path's points as float bits (IEEE 754
/// binary32: 1.0 is 0x3F800000, 2.0 0x40000000, -3.0 0xC0400000, 4.0 0x40800000, 5.0
/// 0x40A00000 and 6.0 0x40C00000).
pub fn a_viewer_writes_the_creatures_kind_3_flight_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.joining()
  let assert map.Joined(unit:, loadout:, incarnation:, clock_origin_ms: _) =
    game_connection_support.map_answer(taken)
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(map.Joined(unit:, loadout:, incarnation:, clock_origin_ms: 600)),
      ),
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.creature_of_beast_appears_facing(
        unit_id: 40,
        creature_id: 11_070,
        yaw: 0.7,
      ),
    )
  let at = fn(x, y, z) {
    place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
  }
  let flight =
    creature_path.Timed(
      first: #(1000, at(1.0, 2.0, -3.0)),
      rest: [#(1375, at(4.0, 5.0, 6.0))],
      turned_to: option.None,
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.news_sent_by_a_peer(
        unit_id: 40,
        news: client_connection.CreatureMoved(path: flight),
      ),
    )
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x638: one message for the flight"
  assert unit_movement.decode(body)
    == Ok(
      UnitMovement(
        unit_id: 40,
        server_time: 400,
        reset_movement: 0,
        kept: 1,
        commands: [
          relayed_movement.Time(MovementTime(time: 400)),
          relayed_movement.TimedPath(
            MovementTimedPath(times: [400, 775], points: [
              MovementFloatVector(x: 0x3F800000, y: 0x40000000, z: 0xC0400000),
              MovementFloatVector(x: 0x40800000, y: 0x40A00000, z: 0x40C00000),
            ]),
          ),
          relayed_movement.MoveAsked(MovementMoveAsked(
            x: 0,
            y: 0,
            z: 0,
            blends: 1,
          )),
          relayed_movement.StateFlags(MovementStateFlags(flags: 0)),
        ],
      ),
    )
    as "kind 0 at 1000 - 600, kind 3 with the times 400 and 775 and the two points, then the stop that ends any walk, with the kept bit 1 and state 0, so the arc is not pulled down (`unit.ground_lift.server_commands`)"
}

pub fn an_object_unseen_and_seen_again_under_the_same_id_writes_a_0x355_then_a_0x262_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client removes a unit with a 0x355 (0x1403d9590) and ignores a 0x262 for a
  // unit it holds (0x1403d9760): a released static object comes back under its id
  // only if the removal made the connection forget it, and it never becomes gone.
  let seen =
    game_connection_support.sent_by_the_map(
      ObjectsSeen(units: [object_unit(20)]),
    )
  let #(state, _) =
    game_connection_support.feed(game_connection_support.in_world(), seen)
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(ObjectsUnseen(unit_ids: [20])),
    )
  assert game_connection_support.written_ids(taken) == [0x0355]
    as "the removal is a 0x355"
  let #(state, taken) = game_connection_support.feed(state, seen)
  let written =
    game_connection_support.heard(taken, game_connection_support.keyed())
  assert list.map(written, fn(frame) {
      unit_create_static.decode(frame.body)
      |> result.map(fn(unit) { unit.unit_id })
    })
    == [Ok(20)]
    as "the object is created again under the same unit id"
  let #(_, again) = game_connection_support.feed(state, seen)
  assert support.writes(again) == []
    as "a second notice of the shown object writes nothing"
}

/// `opcode.0x262.casts`, `cast.unknown_caster` and `CreateCast 0x140561780`: the client
/// makes every cast a create lists, whether or not it knows the caster, and links it into
/// the unit it names as its caster; a cast id 0 is filed as a pending cast, which makes the
/// client skip the rest of the list. So a viewer writes the entries of the unit the create
/// is for and the entries of other players' casts the unit holds, with a cast id above 0 and
/// a caster that is not the viewer (its cast rule finished such a cast when it dropped the
/// last node, `proc.nodes_left`), and records as its own to finish only the casts of the
/// unit the create is for (a 0x7fe is written only for a recorded cast, as for a watched
/// one).
pub fn a_unit_create_lists_the_casts_of_the_unit_and_the_casts_of_others_it_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let id = 2_147_497_985
  let own = game_connection_support.listed_cast(cast_id: id, caster: 9)
  let held_from_another =
    game_connection_support.listed_cast(cast_id: id, caster: 7)
  list.each(
    [
      #(
        "an entry of the created unit is kept and recorded",
        [own],
        id,
        [own],
        id,
        [0x07FE],
      ),
      #(
        "an entry whose caster is another unit is kept and not recorded (the created unit's CastFinished for it writes no 0x7fe), and the cast in progress stays the created unit's own, which is none",
        [held_from_another],
        id,
        [held_from_another],
        0,
        [],
      ),
      #(
        "an entry whose caster is the viewer's own unit is dropped",
        [
          game_connection_support.listed_cast(
            cast_id: id,
            caster: game_connection_support.own_unit_id,
          ),
        ],
        id,
        [],
        0,
        [],
      ),
      #(
        "an entry with cast id 0 is dropped and not recorded",
        [game_connection_support.listed_cast(cast_id: 0, caster: 9)],
        0,
        [],
        0,
        [],
      ),
    ],
    fn(row) {
      let #(name, casts, cast_id, kept, written_cast_id, finished) = row
      let #(state, taken) =
        game_connection_support.feed(
          game_connection_support.in_world(),
          game_connection_support.sent_by_a_peer(
            game_connection_support.news_of(
              unit_id: 9,
              news: Appeared(game_connection_support.another_unit_casting(
                casts:,
                cast_id:,
              )),
            ),
          ),
        )
      let assert [created] =
        game_connection_support.decoded(
          game_connection_support.heard(taken, game_connection_support.keyed()),
          0x0262,
          unit_create_player.decode,
        )
        as name
      assert created.tail.casts == kept as name
      assert created.tail.cast_id == written_cast_id as name
      let #(_, taken) =
        game_connection_support.feed(
          state,
          game_connection_support.sent_by_a_peer(
            game_connection_support.news_of(
              unit_id: 9,
              news: CastFinished(cast_id:),
            ),
          ),
        )
      assert game_connection_support.written_ids(taken) == finished as name
    },
  )
}

/// What a viewer writes that the test below tells apart: the 0x811 of a cast naming units, the
/// 0x7fe of a cast, or any other frame by its opcode.
type Written {
  TargetsRemoved(cast_id: Int, unit_ids: List(Int))
  Finished(cast_id: Int)
  /// A 0x7ff as the client reads it.
  Started(start: spell_started.SpellStarted)
  /// A 0x7f4 as the client reads it.
  Went(go: spell_go.SpellGo)
  Other(opcode: Int)
}

fn written_of(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(Written) {
  list.map(
    game_connection_support.heard(taken, game_connection_support.keyed()),
    fn(frame) {
      case frame.message_id {
        0x0811 -> {
          let assert Ok(removed) = spell_targets_removed.decode(frame.body)
            as "a 0x811 the viewer wrote decodes"
          TargetsRemoved(cast_id: removed.cast_id, unit_ids: removed.unit_ids)
        }
        0x07FE -> {
          let assert Ok(finished) = spell_finished.decode(frame.body)
            as "a 0x7fe the viewer wrote decodes"
          Finished(cast_id: finished.cast_id)
        }
        0x07FF -> {
          let assert Ok(start) = spell_started.decode(frame.body)
            as "a 0x7ff the viewer wrote decodes"
          Started(start:)
        }
        0x07F4 -> {
          let assert Ok(go) = spell_go.decode(frame.body)
            as "a 0x7f4 the viewer wrote decodes"
          Went(go:)
        }
        opcode -> Other(opcode:)
      }
    },
  )
}

/// News of the unit `unit_id` as its owner sends it to the viewer.
fn from_unit(
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  game_connection_support.sent_by_a_peer(game_connection_support.news_of(
    unit_id:,
    news:,
  ))
}

/// The create of the player unit `unit_id` that lists `casts`, no cast in progress.
fn created_listing(
  unit_id unit_id: Int,
  casts casts: List(UnitCreateCast),
) -> client_connection.News {
  Appeared(
    unit_create_player.UnitCreatePlayer(
      ..game_connection_support.another_unit_casting(casts:, cast_id: 0),
      unit_id:,
    ),
  )
}

/// `opcode.0x811`, `cast.target_node_end` and `cast.unknown_caster`: a cast an ally's create
/// listed is ended at a viewer by one party. When the caster told the viewer the cast, its
/// own frames end it and the ally's end is dropped; when the viewer was never told it, or
/// was told it and saw it finished, the ally's `HeldCastEnded` writes one 0x811 naming the
/// ally, never a 0x7fe (that would end the cast's nodes on other units too). A cast the
/// ally's create borrowed stays borrowed when the caster's create or start reaches the
/// viewer after it, so the caster's removal, finish and start write nothing for it
/// (`viewers.written_cast_frames`: a frame is written only for a cast the viewer wrote the
/// start of).
pub fn a_cast_an_ally_listed_is_ended_for_the_viewer_by_the_ally_only_when_its_caster_did_not_tell_the_viewer_the_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let other_ally = 10
  let caster = 7
  let cast_id = 2_147_497_985
  let listed = [
    game_connection_support.listed_cast(cast_id:, caster:),
  ]
  let ally_lists =
    from_unit(
      unit_id: ally,
      news: created_listing(unit_id: ally, casts: listed),
    )
  let ally_ends =
    from_unit(unit_id: ally, news: client_connection.HeldCastEnded(cast_id:))
  let caster_appears =
    from_unit(
      unit_id: caster,
      news: created_listing(unit_id: caster, casts: []),
    )
  let caster_starts =
    from_unit(
      unit_id: caster,
      news: client_connection.CastStarted(
        start: game_connection_support.spell_started_of(cast_id:, caster:),
      ),
    )
  let caster_finishes = from_unit(unit_id: caster, news: CastFinished(cast_id:))
  let caster_removes_the_ally =
    from_unit(
      unit_id: caster,
      news: client_connection.CastTargetsRemoved(
        removed: spell_targets_removed.SpellTargetsRemoved(cast_id:, unit_ids: [
          ally,
        ]),
        destroyed: True,
      ),
    )
  let ended_on = fn(unit_ids) { TargetsRemoved(cast_id:, unit_ids:) }
  // What reaches the viewer before the steps asserted, the steps, and what each writes.
  let rows = [
    #(
      "the viewer was never told the cast: the ally's end writes one 0x811 naming the ally, and a second writes nothing",
      [ally_lists],
      [ally_ends, ally_ends],
      [[ended_on([ally])], []],
    ),
    #(
      "the caster told the viewer the cast before the ally's create: the ally's end writes nothing and the caster's own 0x811 naming the ally is written",
      [caster_appears, caster_starts, ally_lists],
      [ally_ends, caster_removes_the_ally],
      [[], [ended_on([ally])]],
    ),
    #(
      "the caster's finish was written before the ally's create: the ally's end writes the 0x811",
      [caster_appears, caster_starts, caster_finishes, ally_lists],
      [ally_ends],
      [[ended_on([ally])]],
    ),
    #(
      "the caster's create lists the cast after the ally's: the cast stays borrowed, the caster's finish writes nothing and the ally's end writes the 0x811",
      [
        ally_lists,
        from_unit(
          unit_id: caster,
          news: created_listing(unit_id: caster, casts: listed),
        ),
      ],
      [caster_finishes, ally_ends],
      [[], [ended_on([ally])]],
    ),
    #(
      "the caster leaves the viewer's sight after the ally's create borrowed the cast: its removal writes no 0x7fe, and the ally's end then writes the 0x811",
      [
        ally_lists,
        from_unit(
          unit_id: caster,
          news: created_listing(unit_id: caster, casts: listed),
        ),
      ],
      [from_unit(unit_id: caster, news: Removed), ally_ends],
      [[Other(0x0355)], [ended_on([ally])]],
    ),
    #(
      "the caster's start reaches the viewer after the ally's create: it is dropped, so the caster's finish writes nothing and the ally's end writes the 0x811",
      [caster_appears, ally_lists],
      [caster_starts, caster_finishes, ally_ends],
      [[], [], [ended_on([ally])]],
    ),
    #(
      "two allies listed one cast: each end names its own ally alone",
      [
        ally_lists,
        from_unit(
          unit_id: other_ally,
          news: created_listing(unit_id: other_ally, casts: listed),
        ),
      ],
      [
        ally_ends,
        from_unit(
          unit_id: other_ally,
          news: client_connection.HeldCastEnded(cast_id:),
        ),
      ],
      [[ended_on([ally])], [ended_on([other_ally])]],
    ),
    #(
      "the ally leaves the viewer's sight, then its end: nothing",
      [ally_lists],
      [from_unit(unit_id: ally, news: Removed), ally_ends],
      [[Other(0x0355)], []],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, setup, steps, expected) = row
    let state =
      list.fold(setup, game_connection_support.in_world(), fn(state, event) {
        game_connection_support.feed(state, event).0
      })
    let #(_, written) =
      list.fold(steps, #(state, []), fn(so_far, event) {
        let #(state, written) = so_far
        let #(state, taken) = game_connection_support.feed(state, event)
        #(state, list.append(written, [written_of(taken:)]))
      })
    assert written == expected as reason
  })
}

/// The ally 9's tell of the cast `cast_id` of the unit `caster` it holds, as it builds it
/// (`landing.cast_went`): the 0x7ff naming the ally as primary target and the 0x7f4 that lists
/// Spell4Effects 62024 on the ally alone with instance count 1, ignore-cooldown 1 and no
/// positions (`opcode.0x7ff`, `opcode.0x7f4`), written out here, not built by `held_start`.
fn held_cast_started(
  cast_id cast_id: Int,
  caster caster: Int,
) -> client_connection.News {
  client_connection.HeldCastStarted(
    start: spell_started.SpellStarted(
      ..game_connection_support.spell_started_of(cast_id:, caster:),
      spell4_id: 32_823,
      root_spell4_id: 32_823,
      primary_target_unit_id: 9,
    ),
    go: spell_go.SpellGo(
      cast_id:,
      ignore_cooldown: 1,
      destination: spell_position.SpellPosition(x: 0, y: 0, z: 0),
      targets: [
        cast_support.listed_target_info(
          unit_id: 9,
          index: 0,
          count: 1,
          effects: [
            cast_support.listed_effect_info(
              effect_id: 62_024,
              instance_id: 1,
              delay_ms: 0,
              lifetime_ms: 10_000,
            ),
          ],
        ),
      ],
      initial_positions: [],
      telegraph_positions: [],
      missiles: [],
      phase: 0,
    ),
  )
}

/// What a viewer writes for the start the ally 9 tells of a cast it holds (`HeldCastStarted`):
/// the cast's 0x7ff then its 0x7f4, once, when the viewer shows the ally and holds the cast
/// in no state; the cast is then borrowed from the ally, so the ally's `HeldCastEnded` writes
/// one 0x811 naming the ally (`opcode.0x811`: the node, and the cast with its last node, for
/// cast method 0). Nothing is written, and nothing borrowed, when the ally is not shown or is
/// gone, or when the viewer holds the cast already (`opcode.0x7ff`: a cast id already live
/// restarts that cast): written by its caster, borrowed from an ally's create or an earlier
/// start, or held with no caster after its caster left while the viewer held a kept change of
/// it. A viewer that does not show the caster still makes the cast (`cast.unknown_caster`).
pub fn a_cast_an_ally_starts_is_written_once_borrowed_from_the_ally_and_dropped_when_the_viewer_holds_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let caster = 7
  let cast_id = 2_147_497_985
  let ally_appears =
    from_unit(unit_id: ally, news: created_listing(unit_id: ally, casts: []))
  let ally_starts =
    from_unit(unit_id: ally, news: held_cast_started(cast_id:, caster:))
  let ally_ends =
    from_unit(unit_id: ally, news: client_connection.HeldCastEnded(cast_id:))
  let ally_lists =
    from_unit(
      unit_id: ally,
      news: created_listing(unit_id: ally, casts: [
        game_connection_support.listed_cast(cast_id:, caster:),
      ]),
    )
  let caster_appears =
    from_unit(
      unit_id: caster,
      news: created_listing(unit_id: caster, casts: []),
    )
  let caster_starts =
    from_unit(
      unit_id: caster,
      news: client_connection.CastStarted(
        start: game_connection_support.spell_started_of(cast_id:, caster:),
      ),
    )
  let caster_finishes = from_unit(unit_id: caster, news: CastFinished(cast_id:))
  let assert client_connection.HeldCastStarted(start:, go:) =
    held_cast_started(cast_id:, caster:)
  let written = [Started(start:), Went(go:)]
  // A viewer that holds a kept change of a cast from another player's connection 3 and was
  // told the cast by its caster, whose unit then leaves: the cast is held with no caster.
  let orphan_id = 100
  let orphan_caster = game_connection_support.viewer_unit_id(3)
  let kept_source =
    unit_properties.Source(
      cast_id: orphan_id,
      effect_id: Spell4EffectsId(62_024),
    )
  let orphaned_by_its_caster_leaving = [
    game_connection_support.sent_by_the_map(SeenBy(
      by: ConnectionId(3),
      stay: game_connection_support.viewer_stay(3),
      unit_id: orphan_caster,
    )),
    game_connection_support.for_stay(
      stay: game_connection_support.own_stay(),
      sent: client_connection.SentByCaster(
        change: held_changes.PlayerChangeStarts(
          from: ConnectionId(3),
          from_stay: game_connection_support.viewer_stay(3),
          source: kept_source,
          change: held_changes.Absorb(amount: 300, mask: 7),
          sight: held_changes.KeptWhenUnseen,
          spell4_id: Spell4Id(32_823),
          effect: unit_casts.HeldEffect(
            effect_id: kept_source.effect_id,
            starts_ms: 1000,
            ends: unit_casts.EndsAt(ms: 11_000),
          ),
        ),
      ),
    ),
    from_unit(
      unit_id: orphan_caster,
      news: created_listing(unit_id: orphan_caster, casts: []),
    ),
    from_unit(
      unit_id: orphan_caster,
      news: client_connection.CastStarted(
        start: game_connection_support.spell_started_of(
          cast_id: orphan_id,
          caster: orphan_caster,
        ),
      ),
    ),
    from_unit(unit_id: orphan_caster, news: Removed),
    ally_appears,
  ]
  // What reaches the viewer before the steps asserted, the steps, and what each writes.
  let rows = [
    #(
      "the ally is shown and the cast is held in no state: the 0x7ff then the 0x7f4, once; the cast is borrowed from the ally, whose end writes one 0x811 and a second writes nothing",
      [ally_appears],
      [ally_starts, ally_ends, ally_ends],
      [written, [TargetsRemoved(cast_id:, unit_ids: [ally])], []],
    ),
    #(
      "the ally was never shown: nothing is written, and nothing is borrowed for its end to write",
      [],
      [ally_starts, ally_ends],
      [[], []],
    ),
    #(
      "the map said the ally is gone: nothing is written, and nothing is borrowed",
      [ally_appears, game_connection_support.event_of(MapSaysGone)],
      [ally_starts, ally_ends],
      [[], []],
    ),
    #(
      "the caster told the viewer the cast first: nothing is written, the ally's end writes nothing and the caster's finish still writes its 0x7fe",
      [caster_appears, caster_starts, ally_appears],
      [ally_starts, ally_ends, caster_finishes],
      [[], [], [Finished(cast_id:)]],
    ),
    #(
      "the ally's create listed the cast, so it is borrowed: the start writes nothing and the end writes the one 0x811",
      [ally_lists],
      [ally_starts, ally_ends],
      [[], [TargetsRemoved(cast_id:, unit_ids: [ally])]],
    ),
    #(
      "the ally started the cast already, as when a cast tells again: the second start writes nothing and one end writes one 0x811",
      [ally_appears],
      [ally_starts, ally_starts, ally_ends],
      [written, [], [TargetsRemoved(cast_id:, unit_ids: [ally])]],
    ),
    #(
      "the cast is held with no caster, because its caster left the viewer's sight while the viewer held a kept change of it: the start writes nothing",
      orphaned_by_its_caster_leaving,
      [
        from_unit(
          unit_id: ally,
          news: held_cast_started(cast_id: orphan_id, caster: orphan_caster),
        ),
      ],
      [[]],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, setup, steps, expected) = row
    let state =
      list.fold(setup, game_connection_support.in_world(), fn(state, event) {
        game_connection_support.feed(state, event).0
      })
    let #(_, taken) =
      list.fold(steps, #(state, []), fn(so_far, event) {
        let #(state, taken) = so_far
        let #(state, one) = game_connection_support.feed(state, event)
        #(state, list.append(taken, [written_of(taken: one)]))
      })
    assert taken == expected as reason
  })
}

/// Gamma Rays (Spell4 29874: castTime 1250 ms, a Normal cast with a cast bar) and Discharge
/// (Spell4 58832: Channeled, first go 410 ms after the press), the Medic's level-1
/// abilities with a cast bar, by Spell4Base.
const gamma_rays_base = 16_322

/// Gate (Spell4 34355), the Spellslinger's level-1 ability, by Spell4Base.
const gate_base = 20_325

const discharge_base = 38_201

/// A Medic of the real tables that pressed the ability `ability` at 1000 ms, watched by the
/// connection 2 and run to `until_ms`: the casts the watcher was told started, in order, and
/// the 0x262 the player sends the arriving viewer 3.
fn medic_casting_seen_by_a_new_viewer(
  ability ability: Int,
  until_ms until_ms: Int,
) -> #(List(spell_started.SpellStarted), UnitCreatePlayer) {
  let #(state, _, bag_index) =
    game_connection_support.entered_with_spell_trees(class_id: 4, ability:)
  let #(state, steps) =
    game_connection_support.pressed_until(
      state: game_connection_support.watched_by(state:, viewers: [2]),
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms:,
    )
  let starts =
    list.flat_map(steps, fn(taken) {
      game_connection_support.cast_starts(game_connection_support.news_told(
        taken:,
        viewer: 2,
      ))
    })
  assert starts != [] as "the watcher is told the pressed cast started"
  #(starts, game_connection_support.created_at(state:, viewer: 3, ms: until_ms))
}

/// The target info a unit create lists for the player's own unit with these effects: the
/// first target, flags 0, a count of 1 and a Hit.
fn own_target(
  effects effects: List(spell_effect_info.SpellEffectInfo),
) -> spell_target_info.SpellTargetInfo {
  cast_support.listed_target_info(
    unit_id: game_connection_support.own_unit_id,
    index: 0,
    count: 1,
    effects:,
  )
}

/// A viewer's coming into sight of the Medic or leaving it, at a time.
type Move {
  Comes(at_ms: Int)
  Goes(at_ms: Int)
}

/// The news the Medic's connection tells the viewer 3 after Discharge, pressed at 1000 ms
/// with the connection 2 watching, as the viewer comes and goes by `moves`, and the casts
/// the watcher 2 was told started. Discharge's first go, 410 ms in, starts a Power Charge
/// (Spell4 42569) that no go of Discharge ends: its cast lingers until its buff ends.
fn discharge_told_to_a_viewer(
  moves moves: List(Move),
) -> #(List(spell_started.SpellStarted), List(client_connection.News)) {
  discharge_told_on(tables: character_tables.shared(), moves:)
}

/// `discharge_told_to_a_viewer` on these tables.
fn discharge_told_on(
  tables tables: store_tables.Tables,
  moves moves: List(Move),
) -> #(List(spell_started.SpellStarted), List(client_connection.News)) {
  let #(state, _, bag_index) =
    game_connection_support.entered_with_server_proxies(
      class_id: 4,
      ability: discharge_base,
      proxies: server_proxy_support.none(),
      tables:,
    )
  let #(state, pressed) =
    game_connection_support.pressed_until(
      state: game_connection_support.watched_by(state:, viewers: [2]),
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1000,
    )
  let #(state, pending, steps) =
    list.fold(
      moves,
      #(state, game_connection_support.cast_timers(steps: pressed, ms: 1000), [
        pressed,
      ]),
      fn(held, move) {
        let #(state, pending, steps) = held
        let #(state, pending, ran) =
          game_connection_support.casts_left(
            state:,
            pending:,
            until_ms: move.at_ms,
            steps: [],
          )
        let notice = case move {
          Comes(..) ->
            SeenBy(
              by: ConnectionId(3),
              stay: game_connection_support.viewer_stay(3),
              unit_id: game_connection_support.viewer_unit_id(3),
            )
          Goes(..) -> UnseenBy(by: ConnectionId(3))
        }
        let #(state, moved) =
          game_connection_support.at(
            state:,
            ms: move.at_ms,
            event: game_connection_support.sent_by_the_map(notice),
          )
        #(state, pending, list.append(steps, [ran, [moved]]))
      },
    )
  let #(_, ran) =
    game_connection_support.casts_run(
      state:,
      pending:,
      until_ms: 100_000,
      steps: [],
    )
  let steps = list.flatten([list.flatten(steps), ran])
  #(
    list.flat_map(steps, fn(taken) {
      game_connection_support.cast_starts(game_connection_support.news_told(
        taken:,
        viewer: 2,
      ))
    }),
    list.flat_map(steps, fn(taken) {
      game_connection_support.news_told(taken:, viewer: 3)
    }),
  )
}

/// Whether the news end the cast `cast_id` for the viewer: its 0x811 that takes the Medic's
/// node off it, or its 0x7fe.
fn told_of(
  told told: List(client_connection.News),
  cast_id cast_id: Int,
) -> Bool {
  list.contains(told, CastFinished(cast_id:))
  || list.any([False, True], fn(destroyed) {
    list.contains(
      told,
      client_connection.CastTargetsRemoved(
        removed: spell_targets_removed.SpellTargetsRemoved(cast_id:, unit_ids: [
          game_connection_support.own_unit_id,
        ]),
        destroyed:,
      ),
    )
  })
}

/// `opcode.0x262.casts` and `InitUnitFromCreate 0x140456960` (the unit is filed before its
/// list, so its own buffs are built in the same frame): a unit create lists each cast of the
/// player that holds a node with a listed effect, whatever the cast bar says, with each effect's
/// delay still to run and time left from now (`opcode.0x7f4.effect_delay`,
/// `opcode.0x7f4.effect_time`). A Spellslinger's Gate (Spell4 34355, row 67777: a property
/// modifier of delay 180 and duration 400 on the caster) 100 ms after its go has 80 ms of delay
/// to run and 480 ms to live, and the cast is not the current cast; the Engineer's passive
/// outlives its owner's death, so a viewer that arrives to the corpse is listed it.
pub fn a_player_that_comes_into_sight_lists_its_buffs_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, bag_index) =
    game_connection_support.entered_with_spell_trees(
      class_id: 7,
      ability: gate_base,
    )
  let #(state, steps) =
    game_connection_support.pressed_until(
      state: game_connection_support.watched_by(state:, viewers: [2]),
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1100,
    )
  let assert [gate, ..] =
    list.flat_map(steps, fn(taken) {
      game_connection_support.cast_starts(game_connection_support.news_told(
        taken:,
        viewer: 2,
      ))
    })
    as "the watcher is told the pressed cast started"
  let created = game_connection_support.created_at(state:, viewer: 3, ms: 1100)
  assert gate.spell4_id == 34_355
  assert created.tail.casts
    == [
      UnitCreateCast(
        caster_unit_id: game_connection_support.own_unit_id,
        primary_target_unit_id: gate.primary_target_unit_id,
        cast_id: gate.cast_id,
        spell4_id: 34_355,
        started: 0,
        targets: [
          own_target(effects: [
            cast_support.listed_effect_info(
              effect_id: 67_777,
              instance_id: 1,
              delay_ms: 80,
              lifetime_ms: 480,
            ),
          ]),
        ],
        initial_positions: [],
        telegraph_positions: [],
      ),
    ]
    as "Gate's one target is the Spellslinger, row 67777 at delay 80 and lifetime 480"
  assert created.tail.cast_id == 0
    as "Gate is no longer the current cast, yet it is listed for its buff"
  let #(dead, _) =
    game_connection_support.killed(
      game_connection_support.watched_by(
        state: game_connection_support.in_world(),
        viewers: [2],
      ),
    )
  let corpse = game_connection_support.created_for(state: dead, viewer: 3)
  let assert [passive] = corpse.tail.casts
    as "the passive is listed to a viewer that arrives to the corpse"
  assert passive == engineer_passive(cast_id: passive.cast_id)
  assert corpse.tail.cast_id == 0
}

/// `opcode.0x262.casts` and `SetUnitCast 0x1404697a0`: a unit create lists the cast the
/// player holds the bar of, with the id the client looks the cast in progress up by, in
/// state 2 (bit 1) until its first go and state 3 (bit 0) after; a cast that is no longer
/// the current cast and holds no node is not listed, and one that holds a node with a
/// listed effect still is (a Discharge's lingering Power Charge). And
/// `cast.target_node_end`: a viewer is then told the later news of the casts it was
/// listed and of no other (a 0x87f of a cast it does not hold would wait on the unit for
/// ever), and one that left sight is told nothing of the casts it saw before.
pub fn a_player_that_comes_into_sight_lists_its_current_cast_test() -> Nil {
  use <- owned_test.run(60_000)
  let none =
    game_connection_support.created_for(
      state: game_connection_support.medic_in_world(),
      viewer: 3,
    )
  assert none.tail.casts == [] && none.tail.cast_id == 0
    as "a player that casts nothing lists no cast and no cast in progress"
  list.each(
    [
      #(
        "Gamma Rays before its first go, a cast bar: listed in state 2",
        gamma_rays_base,
        29_874,
        1000,
        option.Some(1),
      ),
      #(
        "Discharge, Channeled, 410 ms after its first go: listed in state 3, with the Power Charge its first go left on the Medic, in state 3 with the Medic as its one target (Spell4Effects 96819, until removed)",
        discharge_base,
        58_832,
        1500,
        option.Some(0),
      ),
      #(
        "Gamma Rays after its first go, a Normal cast that is no longer the current cast: not listed",
        gamma_rays_base,
        29_874,
        2600,
        option.None,
      ),
    ],
    fn(row) {
      let #(name, ability, spell4_id, until_ms, started) = row
      let #(starts, created) =
        medic_casting_seen_by_a_new_viewer(ability:, until_ms:)
      let assert [start, ..] = starts
      assert start.spell4_id == spell4_id as name
      case started {
        option.None -> {
          assert created.tail.casts == [] && created.tail.cast_id == 0 as name
        }
        option.Some(started) -> {
          let cast =
            UnitCreateCast(
              caster_unit_id: game_connection_support.own_unit_id,
              primary_target_unit_id: start.primary_target_unit_id,
              cast_id: start.cast_id,
              spell4_id:,
              started:,
              targets: [],
              initial_positions: [],
              telegraph_positions: [],
            )
          let power_charges =
            list.filter(starts, fn(start) { start.spell4_id == 42_569 })
            |> list.map(fn(power_charge) {
              UnitCreateCast(
                ..cast,
                primary_target_unit_id: power_charge.primary_target_unit_id,
                cast_id: power_charge.cast_id,
                spell4_id: 42_569,
                started: 0,
                targets: [
                  own_target(effects: [
                    cast_support.listed_effect_info(
                      effect_id: 96_819,
                      instance_id: 1,
                      delay_ms: 0,
                      lifetime_ms: 0,
                    ),
                  ]),
                ],
              )
            })
          assert created.tail.casts
            == list.sort([cast, ..power_charges], fn(left, right) {
              int.compare(left.cast_id, right.cast_id)
            })
            as name
          assert created.tail.cast_id == start.cast_id as name
        }
      }
    },
  )
  list.each(
    [
      #(
        "a viewer that comes into sight after Discharge's first go is told its finish and the end of the Power Charge the first go left, which its create listed",
        [Comes(1500)],
      ),
      #(
        "a viewer that saw the Power Charge start, left and came back is told the Power Charge's end once: it was listed it again",
        [Comes(1100), Goes(1500), Comes(1600)],
      ),
    ],
    fn(row) {
      let #(name, moves) = row
      let #(started, told) = discharge_told_to_a_viewer(moves:)
      let assert [discharge, ..] = started
      let assert Ok(power_charge) =
        list.find(started, fn(start) { start.spell4_id == 42_569 })
        as "the first go starts a Power Charge"
      assert discharge.spell4_id == 58_832 as name
      assert list.contains(told, CastFinished(cast_id: discharge.cast_id))
        as name
      assert told_of(told:, cast_id: power_charge.cast_id) as name
      assert list.count(told, fn(news) {
          list.any([False, True], fn(destroyed) {
            news
            == client_connection.CastTargetsRemoved(
              removed: spell_targets_removed.SpellTargetsRemoved(
                cast_id: power_charge.cast_id,
                unit_ids: [game_connection_support.own_unit_id],
              ),
              destroyed:,
            )
          })
        })
        == 1
        as name
    },
  )
}

/// `opcode.0x262.casts` and `cast.target_node_end`: a viewer is told the later news of the
/// casts its create listed and of no other. The map's second join of a connection sends each
/// player it sees a second `SeenBy`, and a viewer that already shows the player drops the
/// second create, so the second `SeenBy` lists it nothing and joins it to no cast. Discharge's
/// Power Charge (Spell4 42569) is given a cast time of 1000 ms, so that this child cast of
/// the first go (410 ms in) waits 1000 ms before its own first go makes its node: a viewer that
/// comes at 1500 ms is not listed it, and one that comes again at 2600 ms, after the node, is
/// still not told its end.
pub fn a_second_join_of_a_viewer_joins_it_to_no_cast_it_was_not_listed_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Spell4", id: 42_569, with: [
    #("castTime", planted_table.Integer(1000)),
  ])
  list.each(
    [
      #(
        "a viewer that comes while the Power Charge waits for its first go is not listed it, so it is told nothing of it",
        [Comes(1500)],
      ),
      #("and a second join after the node does not add the viewer to the cast", [
        Comes(1500),
        Comes(2600),
      ]),
    ],
    fn(row) {
      let #(name, moves) = row
      let #(started, told) = discharge_told_on(tables:, moves:)
      let assert [discharge, ..] = started
      let assert Ok(power_charge) =
        list.find(started, fn(start) { start.spell4_id == 42_569 })
        as "the first go starts a Power Charge"
      assert list.contains(told, CastFinished(cast_id: discharge.cast_id))
        as "the viewer was listed Discharge, the current cast, at its first join"
      assert !told_of(told:, cast_id: power_charge.cast_id) as name
    },
  )
}

/// A creature's 0x262 lists a cast that holds a node on it, and its entry makes that node
/// in the client. A viewer not told of the cast is sent none of its 0x7fe, 0x7f9 or 0x811
/// (`written_cast_frames`), so the node would stay until the creature leaves its sight
/// (`cast.target_node_end`): a viewer keeps an entry only for a cast it was told of, by the
/// caster's create or its 0x7ff, and is still to be told the end of (`CreateCast
/// 0x140561780`, `casts_written`).
pub fn a_creatures_entry_is_kept_only_for_a_cast_the_viewer_was_given_test() -> Nil {
  use <- owned_test.run(10_000)
  let given = 2_147_497_985
  let never_given = 2_147_497_986
  let own_cast = 2_147_497_987
  let from_the_caster = fn(news) {
    game_connection_support.sent_by_a_peer(game_connection_support.news_of(
      unit_id: 9,
      news:,
    ))
  }
  let caster_created_with_the_cast =
    from_the_caster(
      Appeared(game_connection_support.another_unit_casting(
        casts: [game_connection_support.listed_cast(cast_id: given, caster: 9)],
        cast_id: given,
      )),
    )
  list.each(
    [
      #(
        "kept when the cast id is one the viewer was given, and the cast stays recorded for its 0x7fe",
        [caster_created_with_the_cast],
        [game_connection_support.listed_cast(cast_id: given, caster: 9)],
        [game_connection_support.listed_cast(cast_id: given, caster: 9)],
        given,
        [0x07FE],
      ),
      #(
        "dropped when the viewer was never given the cast, and no 0x7fe is owed for it",
        [],
        [
          game_connection_support.listed_cast(cast_id: never_given, caster: 9),
        ],
        [],
        never_given,
        [],
      ),
      #(
        "dropped when the cast was given and then finished before the creature's create",
        [caster_created_with_the_cast, from_the_caster(CastFinished(given))],
        [game_connection_support.listed_cast(cast_id: given, caster: 9)],
        [],
        given,
        [],
      ),
      #(
        "dropped when it is the viewer's own cast, which its client holds itself",
        [],
        [
          game_connection_support.listed_cast(
            cast_id: own_cast,
            caster: game_connection_support.own_unit_id,
          ),
        ],
        [],
        own_cast,
        [],
      ),
    ],
    fn(row) {
      let #(name, setup, casts, kept, cast_id, finished) = row
      let state =
        list.fold(setup, game_connection_support.in_world(), fn(state, event) {
          game_connection_support.feed(state, event).0
        })
      let #(state, taken) =
        game_connection_support.feed(
          state,
          game_connection_support.beast_appears_listing(
            unit_id: 40,
            yaw: 0.0,
            casts:,
          ),
        )
      let assert [created] =
        game_connection_support.decoded(
          game_connection_support.written(taken:),
          0x0262,
          unit_create_creature.decode,
        )
        as "the creature's 0x262 is written once"
      assert created.tail.casts == kept as name
      assert created.tail.cast_id == 0 as name
      let #(_, taken) =
        game_connection_support.feed(
          state,
          from_the_caster(CastFinished(cast_id)),
        )
      assert game_connection_support.written_ids(taken) == finished as name
    },
  )
}

/// The map's notice that the player of connection `viewer` sees the tests' player, as the
/// unit `unit_id`.
fn seen_by(viewer viewer: Int, unit_id unit_id: Int) -> map.Notice {
  SeenBy(
    by: ConnectionId(viewer),
    stay: game_connection_support.viewer_stay(viewer),
    unit_id:,
  )
}

pub fn a_players_address_is_found_by_its_unit_id_among_the_connections_that_see_it_test() -> Nil {
  use <- owned_test.run(5000)
  let player = shown.ShownPlayer(state: player_state_support.a_player())
  // Each row: the notices the map sent, the units the picture shows, and the units the
  // cast rule may name, which are the notices' own connections, unit ids and stays.
  list.each(
    [
      #(
        "a shown player whose connection the map named is addressed by that notice's connection, unit id and stay",
        [seen_by(viewer: 3, unit_id: 40)],
        [40],
        [40],
      ),
      #(
        "a shown player no notice named has no address: there is no connection to tell",
        [],
        [40],
        [],
      ),
      #(
        "a notice for a unit the picture does not show gives none: the client was not sent the unit",
        [seen_by(viewer: 3, unit_id: 40)],
        [],
        [],
      ),
      #(
        "of two shown players only the one a notice named is addressed, by its own notice",
        [seen_by(viewer: 4, unit_id: 41)],
        [40, 41],
        [41],
      ),
      #(
        "two notices name two connections, each addressed by its own unit",
        [seen_by(viewer: 3, unit_id: 40), seen_by(viewer: 4, unit_id: 41)],
        [40, 41],
        [40, 41],
      ),
    ],
    fn(row) {
      let #(why, notices, shown_units, expected_units) = row
      let viewers =
        list.map(notices, fn(notice) {
          let assert SeenBy(by:, stay:, unit_id:) = notice
            as "the rows hold SeenBy notices"
          #(by, Viewer(stay:, unit_id:))
        })
        |> dict.from_list
      let picture =
        list.map(shown_units, fn(unit_id) { #(unit_id, player) })
        |> dict.from_list
      let expected =
        list.filter_map(notices, fn(notice) {
          let assert SeenBy(by:, stay:, unit_id:) = notice
            as "the rows hold SeenBy notices"
          case list.contains(expected_units, unit_id) {
            True ->
              Ok(#(unit_id, PlayerAddress(connection: by, unit_id:, stay:)))
            False -> Error(Nil)
          }
        })
        |> dict.from_list
      assert player_address.in_sight(viewers:, picture:) == expected as why
    },
  )
  // A viewer's stay is the one its latest SeenBy named: the connection that saw the player
  // in one stay and sees it again in a later one is told in the later stay, which is the
  // stay `in_sight` addresses it by.
  let later_stay = map_support.stay(count: 30)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [3])
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(3),
        stay: later_stay,
        unit_id: game_connection_support.viewer_unit_id(3),
      )),
    )
  let #(_, moved) =
    game_connection_support.read(
      state,
      game_connection_support.moves_message([
        game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
      ]),
    )
  assert list.map(game_connection_support.peer_tells_for(moved), fn(sent) {
      #(sent.0, sent.1)
    })
    == [#(3, later_stay)]
    as "a player seen again by a connection in a new stay is told its moves in the new stay, not the first"
}

// ---- what a press judges of a player in sight ----

/// The Base Health (property 7) the 0x262 of `player_with` holds.
const players_base_health = 6000

/// The property 7 entry of a unit whose Base Health is `maximum`, both words the same as the
/// server sends a player's (`opcode.0x262.health`).
fn base_health_property(maximum maximum: Int) -> UnitProperty {
  let bits = float32.to_bits(int.to_float(maximum))
  UnitProperty(property_id: 7, base: bits, value: bits)
}

/// The unit 9 as its owner's 0x262 gives it: faction `faction`, health stat `health`, Base
/// Health `players_base_health`, PvP flags and group as sent, standing at `place`.
fn player_with(
  faction faction: Int,
  health health: Int,
  pvp_flags pvp_flags: Int,
  group_id group_id: Int,
  place place: Place,
) -> UnitCreatePlayer {
  let #(position, rotation) = player_unit.standing(place)
  let unit = game_connection_support.another_unit()
  UnitCreatePlayer(
    ..unit,
    group_id:,
    pvp_flags:,
    tail: UnitCreateTail(
      ..unit.tail,
      faction_id: faction,
      stats: [
        unit_fields.integer_stat(
          stat_id: unit_fields.health_stat,
          value: health,
        ),
      ],
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      properties: [base_health_property(maximum: players_base_health)],
    ),
  )
}

pub fn a_player_that_comes_into_sight_is_shown_with_what_a_press_judges_of_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let entered_as = fn(faction) {
    world_entry_support.entry(
      tables:,
      character: world_entry_support.character(class: 3, faction:, level: 1),
    ).1
  }
  let dominion = entered_as(166)
  let exile = entered_as(167)
  let there =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 100.0,
      y: 12.5,
      z: -40.0,
    )
  let shown_to = fn(entered, unit) {
    viewers.player_appeared(tables:, entered:, unit:)
  }
  let seen =
    shown_to(
      dominion,
      player_with(
        faction: 166,
        health: 5000,
        pvp_flags: 0,
        group_id: 0,
        place: there,
      ),
    )
  // opcode.0x262: a unit made with health stat 0 is dead (`death.enter_dead`).
  assert seen.alive as "a health stat above 0 is a living player"
  assert !shown_to(
    dominion,
    player_with(
      faction: 166,
      health: 0,
      pvp_flags: 0,
      group_id: 0,
      place: there,
    ),
  ).alive
    as "a health stat of 0 is a player that lies dead"
  // opcode.0x262.health: the health is stat 0 and the maximum Base Health (property 7), the
  // value Unit:GetMaxHealth reads (0x1404584b0).
  assert seen.health == 5000 && seen.maximum_health == players_base_health
    as "the copy holds the health stat and the Base Health the 0x262 gave"
  assert !seen.in_combat && seen.held == []
    as "a player comes into sight out of combat and holding no state"
  assert seen.hit_radius == place_support.player_hit_radius
    as "unit.hit_radius: a player's radius is its Race row's (display id 0), 1.2 as a 32-bit float"
  // GetUnitDispositionTo `0x14045a950`: the viewer's faction toward the player's, by
  // Faction2Relationship 684 (Dominion 166 and Exile 167: level 0) and a faction toward
  // itself (level 10).
  assert seen.disposition == faction_level.Friendly
    as "a Dominion viewer sees a Dominion player Friendly"
  assert shown_to(
      dominion,
      player_with(
        faction: 167,
        health: 5000,
        pvp_flags: 0,
        group_id: 0,
        place: there,
      ),
    ).disposition
    == faction_level.Hostile
    as "a Dominion viewer sees an Exile player Hostile"
  assert shown_to(
      exile,
      player_with(
        faction: 166,
        health: 5000,
        pvp_flags: 0,
        group_id: 0,
        place: there,
      ),
    ).disposition
    == faction_level.Hostile
    as "and an Exile viewer a Dominion player"
  assert shown_to(
      exile,
      player_with(
        faction: 167,
        health: 5000,
        pvp_flags: 0,
        group_id: 0,
        place: there,
      ),
    ).disposition
    == faction_level.Friendly
    as "and an Exile viewer an Exile player Friendly"
  // 0x1403b48b0: bit 0 of the 0x262's PvP flags is the flag; the group is the 0x262's.
  assert !seen.pvp_flagged && seen.group_id == 0
    as "the server sends PvP flags 0 and group 0, so nobody is flagged and nobody grouped"
  let marked =
    shown_to(
      dominion,
      player_with(
        faction: 166,
        health: 5000,
        pvp_flags: 1,
        group_id: 77,
        place: there,
      ),
    )
  assert marked.pvp_flagged && marked.group_id == 77
    as "bit 0 of the flags and the group id are kept as sent"
  assert !shown_to(
    dominion,
    player_with(
      faction: 166,
      health: 5000,
      pvp_flags: 2,
      group_id: 0,
      place: there,
    ),
  ).pvp_flagged
    as "a flag word with bit 0 clear is not flagged"
  let assert Some(place) = seen.place
    as "the 0x262's position command gives the player a place"
  assert start_place.x(place) == 100.0
    && start_place.y(place) == 12.5
    && start_place.z(place) == -40.0
    as "the place keeps the command's height (unit.ground_lift: the range y is the movement y)"
  assert start_place.world_id(place) == 3460
    as "the place is in the viewer's world"
  assert written_for_news(news: [
      client_connection.Health(health: 0, dead: True),
      client_connection.CameBack,
      client_connection.Died,
      client_connection.CombatState(in_combat: True),
      client_connection.CrowdControlApplied(
        state: crowd_control_state.Stun,
        instance_id: 5,
      ),
      client_connection.CrowdControlEnded(
        state: crowd_control_state.Stun,
        cast_id: 6,
        instance_id: 5,
      ),
      client_connection.Moving(
        server_time_ms: 7,
        commands: game_connection_support.moved_unit_commands(),
      ),
      client_connection.Removed,
    ])
    == [
      [0x0937],
      [0x088C],
      [0x088C],
      [0x089A],
      [0x087F],
      [0x0880],
      [0x0638],
      [0x0355],
    ]
    as "each news writes the frames it wrote before the picture held a player's state: Health 0x937, CameBack and Died 0x88c, CombatState 0x89a, 0x87f, 0x880, 0x638 and 0x355"
}

/// The ids of the messages the viewer writes for each news of the unit 9 in turn, once the
/// unit's 0x262 has come.
fn written_for_news(
  news news: List(client_connection.News),
) -> List(List(Int)) {
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let #(_, written) =
    list.fold(news, #(shown, []), fn(held, news) {
      let #(state, written) = held
      let #(state, taken) =
        game_connection_support.feed(
          state,
          game_connection_support.sent_by_a_peer(
            game_connection_support.news_of(unit_id: 9, news:),
          ),
        )
      #(
        state,
        list.append(written, [game_connection_support.written_ids(taken)]),
      )
    })
  written
}

/// The copy of another player a viewer keeps holds the health and the maximum its 0x262 gave
/// (stat 0 and Base Health, property 7), and follows the owner's news: a `Health` news
/// (0x937) sets the health and the player alive or dead, and a `PropertiesChanged` news
/// (0x93a) with property 7 sets the maximum. A news for a unit not shown changes nothing.
/// The picture is one news behind at worst: a gear change tells each viewer a
/// `PropertiesChanged` news (`connection/properties.rebased`).
pub fn a_players_health_news_and_its_base_health_change_keep_its_copys_health_and_maximum_test() -> Nil {
  use <- owned_test.run(10_000)
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  let there =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 100.0,
      y: 12.5,
      z: -40.0,
    )
  let take = fn(
    session: connection_state.Session,
    unit_id: Int,
    news: client_connection.News,
  ) {
    let assert Some(entered) = connection_state.entered_of(session.status)
      as "the player is in the world"
    let assert client_connection.Continue(session:, ..) =
      viewers.viewer_takes(
        session:,
        now: step.Now(monotonic_ms: 0, filetime: 0),
        entered:,
        news: PeerNews(unit_id:, news:),
      )
      as "a viewer takes the news"
    session
  }
  let copy_of = fn(session: connection_state.Session, unit_id: Int) {
    let assert Some(entered) = connection_state.entered_of(session.status)
      as "the player is in the world"
    let assert Ok(shown.ShownPlayer(state:)) = dict.get(entered.shown, unit_id)
      as "the unit is a shown player"
    #(state.alive, state.health, state.maximum_health)
  }
  let property_7 = fn(maximum) {
    client_connection.PropertiesChanged(properties: [
      base_health_property(maximum:),
    ])
  }
  let session =
    take(
      game_connection_support.session_in(status: connection_state.InWorld(
        holder: game_connection_support.holder(),
        entered:,
      )),
      9,
      Appeared(unit: player_with(
        faction: 167,
        health: 5000,
        pvp_flags: 0,
        group_id: 0,
        place: there,
      )),
    )
  assert copy_of(session, 9) == #(True, 5000, players_base_health)
    as "the copy holds the health stat and the Base Health of the 0x262"
  let hurt =
    take(session, 9, client_connection.Health(health: 4200, dead: False))
  assert copy_of(hurt, 9) == #(True, 4200, players_base_health)
    as "a Health news sets the health and keeps the maximum"
  let dead = take(hurt, 9, client_connection.Health(health: 0, dead: True))
  assert copy_of(dead, 9) == #(False, 0, players_base_health)
    as "a Health news with the dead bit sets the player dead at health 0"
  let revived =
    take(dead, 9, client_connection.Health(health: 3000, dead: False))
  assert copy_of(revived, 9) == #(True, 3000, players_base_health)
    as "a Health news without it sets the player alive again"
  let grown = take(revived, 9, property_7(7000))
  assert copy_of(grown, 9) == #(True, 3000, 7000)
    as "a PropertiesChanged news with property 7 sets the maximum and keeps the health"
  let other_property =
    take(
      grown,
      9,
      client_connection.PropertiesChanged(properties: [
        UnitProperty(property_id: 8, base: 0, value: 0),
      ]),
    )
  assert copy_of(other_property, 9) == #(True, 3000, 7000)
    as "a PropertiesChanged news without property 7 keeps the maximum"
  let unshown =
    take(grown, 77, client_connection.Health(health: 1, dead: False))
  let assert Some(before) = connection_state.entered_of(grown.status)
  let assert Some(after) = connection_state.entered_of(unshown.status)
  assert after.shown == before.shown
    as "a Health news for a player not shown changes nothing"
  let unshown_properties = take(grown, 77, property_7(1))
  let assert Some(after) =
    connection_state.entered_of(unshown_properties.status)
  assert after.shown == before.shown
    as "a PropertiesChanged news for a player not shown changes nothing"
}
