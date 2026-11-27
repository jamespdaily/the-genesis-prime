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
import game_connection_support.{
  type Step, Appears, AppearsLater, MapSaysGone, Moves, MovesLater, Removes,
}
import game_wire_support
import genesis_prime/client_connection.{
  ForStay, FromMap, FromStore, SentByMap, SentByMove, SentByPeer, TellMoved,
}
import genesis_prime/connection/cipher
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/client_casts
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/connection/viewers
import genesis_prime/game/effect_kind
import genesis_prime/game/faction_level
import genesis_prime/game/held_changes
import genesis_prime/game/held_state
import genesis_prime/game/move_stamp
import genesis_prime/game/objective.{SpawnedUnit}
import genesis_prime/game/player_address.{PlayerAddress, Viewer}
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{
  Appeared, CastFinished, LookChanged, PeerNews, PropertiesChanged, Removed,
}
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
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
import genesis_prime/message/spell_effect_tick
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
import genesis_prime/server
import genesis_prime/step.{
  ConnectionId, LogError, LogInfo, LogWarning, Map, OwnEffect, OwnEvent, Woken,
}
import genesis_prime/store.{Character, ForItems, ForSelect, ItemsSaved, Listed}
import genesis_prime/table/id.{ClassId, Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_fight
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/creature_unit_type.{NonPlayer}
import genesis_prime/world_map/generation
import genesis_prime/world_map/map.{
  Left, ObjectsSeen, ObjectsUnseen, SeenBy, UnseenBy,
}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/static_object.{type Created}
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import legal_order_support
import map_spawn_support
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
import world_watch_support

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
  let create_and_held_move = [0x0262, 0x0638]
  let remove = [0x0355]
  // A move of the sight the 0x262 has not come for is held, and the 0x262 of that sight
  // writes it after itself (genesis_prime/game/move_stamp).
  // Each sequence is what two senders can produce for one unit: the owner's
  // messages in the order it sent them, and the map's Gone after the owner's
  // end, anywhere among them. A player's removal is the map's PlayerUnseen, so each row
  // with one runs the viewer's memory of the sight that ended. A move before its
  // 0x262 stands for a notice the map relayed late.
  list.each(
    [
      #([Appears], [create]),
      #([Appears, Appears], [create, none]),
      #([Moves], [none]),
      #([Moves, Appears], [none, create_and_held_move]),
      #([Removes], [none]),
      #([Removes, AppearsLater], [none, create]),
      #([Appears, Moves], [create, move]),
      #([Appears, Removes], [create, remove]),
      #([Appears, Removes, Moves], [create, remove, none]),
      #([Appears, Removes, Removes], [create, remove, none]),
      #([Appears, Removes, AppearsLater], [create, remove, create]),
      #([Appears, Moves, Removes, AppearsLater, MovesLater], [
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
          generation: generation.first(),
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
  let in_stay = fn(stay, sent) { game_connection_support.for_stay(stay, sent) }
  let kinds =
    list.append(
      list.map(
        [
          Appeared(
            unit: game_connection_support.another_unit(),
            generation: generation.first(),
          ),
          Removed,
          held_cast_started(cast_id: 2_147_497_985, caster: 7),
        ],
        fn(news) { SentByPeer(PeerNews(unit_id: 9, news:)) },
      ),
      [
        SentByMove(game_connection_support.moving(
          unit_id: 9,
          generation: generation.first(),
          server_time_ms: 1,
          commands: game_connection_support.moved_unit_commands(),
        )),
      ],
    )
  // The unit is shown first, so that every kind would be written but for its stay.
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  list.each(kinds, fn(sent) {
    let #(_, taken) =
      game_connection_support.feed(
        shown,
        in_stay(map_support.stay(count: 2), sent),
      )
    assert support.writes(taken) == []
      as "another stay: in another run or map the unit id may name another unit"
    assert !support.stops(taken) && support.logs(taken) == []
      as "news that was on its way when the viewer left is no bug"
  })
  let #(_, taken) =
    game_connection_support.feed(
      shown,
      in_stay(
        game_connection_support.own_stay(),
        SentByPeer(PeerNews(unit_id: 9, news: Removed)),
      ),
    )
  assert game_connection_support.written_ids(taken) == [0x0355]
    as "the stay the viewer is in"
  let #(_, taken) =
    game_connection_support.feed(
      shown,
      in_stay(
        game_connection_support.own_stay(),
        SentByPeer(PeerNews(
          unit_id: 9,
          news: held_cast_started(cast_id: 2_147_497_985, caster: 7),
        )),
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
        generation: game_connection_support.viewer_sight(2),
      )),
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(2),
        generation: game_connection_support.viewer_sight(2),
      )),
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
        generation: game_connection_support.viewer_sight(2),
      )),
    )
  let assert [PeerNews(news: Appeared(unit: created, ..), ..)] =
    game_connection_support.snapshot_items(taken)
    as "the viewer's snapshot, told to the map at once, holds the unit"
  let assert [passive] = created.tail.casts
    as "the Engineer's innate passive is the one cast it holds"
  assert game_connection_support.snapshot_items(taken)
    == [
      game_connection_support.told(news: Appeared(
        unit: appearance_at(
          place: game_connection_support.entry_place(),
          time_ms: 1000,
          casts: [engineer_passive(cast_id: passive.cast_id)],
        ),
        generation: game_connection_support.viewer_sight(2),
      )),
    ]
    as "the snapshot holds the unit at once, from the origin the map's Joined carried, and its copy lists the passive's buffs"
  assert game_connection_support.tells_to_players_but_moves(taken) == []
    as "and the connection tells the viewer's connection nothing itself: the map relays the snapshot"
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
          generation: game_connection_support.viewer_sight(2),
        )),
      )
    let assert [PeerNews(news: Appeared(unit:, ..), ..)] =
      game_connection_support.snapshot_items(taken)
    assert list.map(unit.tail.stats, fn(stat) { stat.stat_id })
      == [0, 10, 15, 20]
      as "health, level, sheathed and shield only: no class slot's stat and no stat 1"
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

/// The stat ids of the 0x262 a first viewer is sent of the player in `state`.
fn stat_ids_a_viewer_is_sent(state state: game_connection.State) -> List(Int) {
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
        generation: game_connection_support.viewer_sight(2),
      )),
    )
  let assert [PeerNews(news: Appeared(unit:, ..), ..)] =
    game_connection_support.snapshot_items(taken)
    as "the viewer's snapshot holds the unit"
  list.map(unit.tail.stats, fn(stat) { stat.stat_id })
}

pub fn a_player_seen_out_of_combat_is_created_with_stat_15_and_one_in_combat_is_created_with_none_test() -> Nil {
  use <- owned_test.run(10_000)
  let resting =
    game_connection_support.watched_by(game_connection_support.in_world(), [5])
  assert list.contains(stat_ids_a_viewer_is_sent(state: resting), 15)
    as "unit.weapon_sheathed: out of combat the viewer's copy is created sheathed, with stat 15"
  let #(fighting, _) =
    game_connection_support.feed(
      resting,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert !list.contains(stat_ids_a_viewer_is_sent(state: fighting), 15)
    as "a viewer is sent no 0x89a when a unit comes into sight, so a unit already in combat is created drawn (a new unit starts drawn, 0x140454a1f): no stat 15"
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
        generation: game_connection_support.viewer_sight(2),
      )),
    )
  let assert [PeerNews(news: Appeared(unit:, ..), ..)] =
    game_connection_support.snapshot_items(taken)
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
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(2),
        generation: game_connection_support.viewer_sight(2),
      )),
    )
  assert game_connection_support.tells_to_players_but_moves(taken) == []
    as "the viewer that stops seeing the unit is sent nothing by the owner: its removal, for the sight that ended, is the map's PlayerUnseen"
  assert list.map(
      game_connection_support.viewer_moves(
        taken: game_connection_support.read(state, moves).1,
      ),
      fn(sent) { sent.0 },
    )
    == [3]
    as "a viewer the map took back is sent no more moves"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(8),
        generation: game_connection_support.viewer_sight(8),
      )),
    )
  assert game_connection_support.tells_to_players_but_moves(taken) == []
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
      game_connection_support.viewer_moves(
        taken: game_connection_support.read(state, moves).1,
      ),
      fn(sent) { sent.0 },
    )
    == [2]
    as "a viewer the map named twice is sent one move"
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
  assert game_connection_support.tells_to_players_but_moves(taken) == []
    as "a camp tells no viewer a removal: the map ends each sight when it takes the leave (PlayerUnseen)"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.leave_asked()
    as "and the leave of the map is asked in the same step"
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
  assert game_connection_support.tells_no_player(taken)
    as "no viewer: no 0x638 is sent"
}

pub fn a_move_is_sent_to_each_viewer_in_the_owners_copy_with_its_own_generation_and_stay_in_chunks_of_31_after_the_map_is_told_the_place_and_to_no_one_else_test() -> Nil {
  use <- owned_test.run(10_000)
  // The viewers 2 and 3 are in the owner's copy, each with its own sight; connection 4
  // is not, and the owner itself is connection 1. Forty positions are two chunks, since a
  // 0x638's count is 5 bits (opcode.0x638).
  let positions =
    list.index_map(list.repeat(Nil, 40), fn(_, n) { int.to_float(n) })
  let sent =
    list.prepend(
      list.map(positions, fn(x) {
        game_client.position_command(x:, y: 0.0, z: 0.0)
      }),
      movement_command.Time(MovementTime(time: 99)),
    )
  let relayed =
    list.map(positions, fn(x) {
      relayed_movement.Position(UnitPositionCommand(
        x: float32.to_bits(x),
        y: float32.to_bits(0.0),
        z: float32.to_bits(0.0),
        blends: 0,
      ))
    })
  let #(first, second) = list.split(relayed, 31)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.watched_by(game_connection_support.in_world(), [
        3,
        2,
      ]),
      game_connection_support.moves_message(sent),
    )
  assert game_connection_support.move_order(taken:)
    == [
      "the map's place",
      "a viewer's move",
      "a viewer's move",
      "a viewer's move",
      "a viewer's move",
    ]
    as "the map is told the place first, then each viewer's chunks"
  assert game_connection_support.move_tells(taken:)
    == list.flat_map([2, 3], fn(viewer) {
      [
        #(
          viewer,
          game_connection_support.viewer_stay(viewer),
          game_connection_support.moved_for(
            viewer:,
            server_time_ms: 1000,
            commands: first,
          ),
        ),
        #(
          viewer,
          game_connection_support.viewer_stay(viewer),
          game_connection_support.moved_for(
            viewer:,
            server_time_ms: 1000,
            commands: second,
          ),
        ),
      ]
    })
    as "to each viewer of the copy, in its stay and stamped with its own sight, the relayed commands in order as 31 and then 9, from the map's clock at the input (the first 0x637 of a connection at 1000 ms from origin 0); none to connection 4 or to the owner itself"
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
    let assert [#(2, move)] = game_connection_support.viewer_moves(taken:)
    move.server_time_ms
  }
  let create_time = fn(monotonic_ms) {
    let assert [PeerNews(news: Appeared(unit:, ..), ..)] =
      game_connection_support.snapshot_items(at(
        monotonic_ms,
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(2),
          stay: game_connection_support.viewer_stay(2),
          unit_id: game_connection_support.viewer_unit_id(2),
          generation: game_connection_support.viewer_sight(2),
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
  assert game_connection_support.tells_no_player(
    game_connection_support.read(again, moves).1,
  )
    as "the player that camped and entered again starts with no viewers, whoever saw the first one"
  let #(again, _) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(4),
          stay: game_connection_support.viewer_stay(4),
          unit_id: game_connection_support.viewer_unit_id(4),
          generation: game_connection_support.viewer_sight(4),
        )),
      ),
    )
  assert list.map(
      game_connection_support.viewer_moves(
        taken: game_connection_support.read(again, moves).1,
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
    assert game_connection_support.tells_no_player(taken) as why
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
    && game_connection_support.tells_no_player(taken)
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
  let assert [#(2, move)] = game_connection_support.viewer_moves(taken: first)
  assert list.length(move.commands) == 1 as "the kind 10 is not relayed"
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
        generation: game_connection_support.viewer_sight(3),
      )),
    ),
    #(
      "a peer's 0x262",
      SentByPeer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(
          unit: game_connection_support.another_unit(),
          generation: generation.first(),
        ),
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
fn object_unit(unit_id: Int) -> #(SpawnId, Created) {
  spawn_support.seen(
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
  )
}

pub fn a_creature_and_an_object_shown_carry_their_spawn_id_to_the_picture_test() -> Nil {
  use <- owned_test.run(10_000)
  // A quest objective remembers a use by the spawn of the object used, so the picture keeps
  // the spawn of each creature (its 0x262 news names it) and each static object (the map's
  // `ObjectsSeen` names it), and the use of a unit reads it from the picture
  // (`casting.spawned_unit`), with the unit id the use is released by.
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  let session =
    game_connection_support.session_in(status: connection_state.InWorld(
      holder: game_connection_support.holder(),
      entered:,
    ))
  let now = step.Now(monotonic_ms: 0, filetime: 0)
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 100.0,
      y: 12.5,
      z: -40.0,
    )
  let beast = spawn_support.beast_at(number: 31, place:)
  let assert client_connection.Continue(session:, ..) =
    viewers.viewer_takes(
      session:,
      now:,
      entered:,
      news: PeerNews(
        unit_id: 40,
        news: unit_news.CreatureAppeared(
          spawn_id: SpawnId(31),
          unit_type: NonPlayer,
          unit: creature_unit.create(
            in_combat: False,
            spawn: beast,
            unit_id: 40,
            health: 52,
            interrupt_armor: option.None,
            server_time_estimate_start: 0,
          ),
          life: 4,
          place:,
          hit_radius: beast.combat.hit_radius,
          attackable: beast.combat.attackable,
          hostile_to: beast.combat.hostile_to,
          fights: beast.combat.fights,
        ),
      ),
    )
    as "a viewer takes the creature's 0x262 news"
  let assert Some(entered) = connection_state.entered_of(session.status)
    as "the player is in the world"
  let assert client_connection.Continue(session:, ..) =
    viewers.map_sent(
      session:,
      now:,
      entered:,
      notice: map.ObjectsSeen(units: [
        spawn_support.seen(
          object: spawn_support.holoring(number: 21, place:),
          unit_id: 20,
        ),
      ]),
    )
    as "the player takes the map's notice of an object"
  let assert Some(entered) = connection_state.entered_of(session.status)
    as "the player is in the world"
  let assert Ok(creature) = dict.get(entered.shown, 40)
    as "the creature is shown"
  let assert shown.ShownCreature(spawn_id: creature_spawn, ..) = creature
    as "the creature is a shown creature"
  assert creature_spawn == SpawnId(31)
    as "the picture keeps the spawn the creature's news named"
  let assert Ok(object) = dict.get(entered.shown, 20) as "the object is shown"
  let assert shown.ShownObject(spawn_id: object_spawn, ..) = object
    as "the object is a shown object"
  assert object_spawn == SpawnId(21)
    as "the picture keeps the spawn the map's notice named, which is not its unit id"
  assert casting.spawned_unit(shown: creature, unit_id: 40)
    == Ok(SpawnedUnit(unit_id: 40, spawn_id: SpawnId(31)))
    as "the use of the creature is counted by its spawn"
  assert casting.spawned_unit(shown: object, unit_id: 20)
    == Ok(SpawnedUnit(unit_id: 20, spawn_id: SpawnId(21)))
    as "the use of the object is counted by its spawn"
  assert casting.spawned_unit(
      shown: shown.ShownPlayer(state: player_state_support.a_player()),
      unit_id: 9,
    )
    == Error(Nil)
    as "another player's unit stands at no spawn"
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
    unit_news.CrowdControlApplied(
      state: crowd_control_state.Knockdown,
      instance_id: 28_673,
    )
  let ended =
    unit_news.CrowdControlEnded(
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
      SentByPeer(PeerNews(unit_id:, news: unit_news.InterruptArmor(armor: 1))),
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
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(2),
        generation: game_connection_support.viewer_sight(2),
      )),
    )
  let assert [LookChanged(..), PropertiesChanged(..), ..] =
    game_connection_support.news_broadcast(answered)
    as "each viewer held when the answer comes is told the look and then the properties"
  assert game_connection_support.news_broadcast(unseen) == []
    as "then the viewer that left is told nothing by the unit's owner: its removal is the map's"
  assert game_connection_support.news_broadcast(unseen) == []
    as "and the viewer that stayed is told nothing more"
  // The viewer's own connection: its client showed the unit, then the map said the unit
  // is gone, so the look and the properties the player told it find no unit shown and
  // are dropped, as any news of a unit not shown is. A viewer that still shows the unit
  // writes them, so the empty writes are the drop and not news the viewer never writes.
  let told = list.take(game_connection_support.news_broadcast(answered), 2)
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
        news: unit_news.CreatureMoved(path: flight),
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
              news: Appeared(
                game_connection_support.another_unit_casting(casts:, cast_id:),
                generation: generation.first(),
              ),
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
  news news: unit_news.News,
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
) -> unit_news.News {
  Appeared(
    unit_create_player.UnitCreatePlayer(
      ..game_connection_support.another_unit_casting(casts:, cast_id: 0),
      unit_id:,
    ),
    generation: generation.first(),
  )
}

/// The create of the player unit `unit_id` that lists no cast, as its owner sends it.
fn appears(
  unit_id unit_id: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(unit_id:, news: created_listing(unit_id:, casts: []))
}

/// The create of the player unit `unit_id` that lists the cast `cast_id` of `caster`.
fn lists(
  unit_id unit_id: Int,
  cast_id cast_id: Int,
  caster caster: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(
    unit_id:,
    news: created_listing(unit_id:, casts: [
      game_connection_support.listed_cast(cast_id:, caster:),
    ]),
  )
}

/// The start of the cast `cast_id` of `caster` that the ally `unit_id` tells the viewer.
fn the_allys_start(
  unit_id unit_id: Int,
  cast_id cast_id: Int,
  caster caster: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(unit_id:, news: held_cast_started(cast_id:, caster:))
}

/// The end of the cast `cast_id` that the ally `unit_id` tells the viewer.
fn the_allys_end(
  unit_id unit_id: Int,
  cast_id cast_id: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(unit_id:, news: unit_news.HeldCastEnded(cast_id:))
}

/// The finish of the cast `cast_id` that its caster `unit_id` tells the viewer.
fn the_casters_finish(
  unit_id unit_id: Int,
  cast_id cast_id: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(unit_id:, news: CastFinished(cast_id:))
}

/// The start of the cast `cast_id` that its caster's own connection tells the viewer.
fn the_casters_start(
  cast_id cast_id: Int,
  caster caster: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  from_unit(
    unit_id: caster,
    news: unit_news.CastStarted(start: game_connection_support.spell_started_of(
      cast_id:,
      caster:,
    )),
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
  let ally_ends = the_allys_end(unit_id: ally, cast_id:)
  let caster_appears = appears(unit_id: caster)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let caster_finishes = the_casters_finish(unit_id: caster, cast_id:)
  let caster_removes_the_ally =
    from_unit(
      unit_id: caster,
      news: unit_news.CastTargetsRemoved(
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
        the_allys_end(unit_id: other_ally, cast_id:),
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
  check_written_rows(rows:)
}

/// Each row is a reason, the events that bring the connection in the world to its setup, the
/// events then fed one by one, and the writes (as `Written`) each of those events made: the
/// writes of each step are compared with the expected ones of that step.
fn check_written_rows(
  rows rows: List(
    #(
      String,
      List(
        step.Event(
          step.ConnectionEvent(
            client_connection.Message,
            client_connection.Answer,
          ),
        ),
      ),
      List(
        step.Event(
          step.ConnectionEvent(
            client_connection.Message,
            client_connection.Answer,
          ),
        ),
      ),
      List(List(Written)),
    ),
  ),
) -> Nil {
  list.each(rows, fn(row) {
    let #(reason, setup, steps, expected) = row
    let #(_, written) =
      list.fold(
        steps,
        #(game_connection_support.fed(events: setup), []),
        fn(so_far, event) {
          let #(state, written) = so_far
          let #(state, taken) = game_connection_support.feed(state, event)
          #(state, list.append(written, [written_of(taken:)]))
        },
      )
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
) -> unit_news.News {
  unit_news.HeldCastStarted(
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

/// The cast id of the cast the viewer holds with no caster after `orphaned_by_its_caster_leaving`.
const orphan_id = 100

/// The unit of the player that cast it: the player of connection 3.
fn orphan_caster_unit() -> Int {
  game_connection_support.viewer_unit_id(3)
}

/// A viewer that holds a kept change of a cast from another player's connection 3 and was
/// told the cast by its caster, whose unit then leaves: the cast `orphan_id` is held with no caster.
fn orphaned_by_its_caster_leaving() -> List(
  step.Event(
    step.ConnectionEvent(client_connection.Message, client_connection.Answer),
  ),
) {
  let orphan_caster = orphan_caster_unit()
  let kept_source =
    unit_properties.Source(
      cast_id: orphan_id,
      effect_id: Spell4EffectsId(62_024),
    )
  [
    game_connection_support.sent_by_the_map(SeenBy(
      by: ConnectionId(3),
      stay: game_connection_support.viewer_stay(3),
      unit_id: orphan_caster,
      generation: game_connection_support.viewer_sight(3),
    )),
    game_connection_support.for_stay(
      stay: game_connection_support.own_stay(),
      sent: client_connection.SentByPlayer(
        client_connection.Change(change: held_changes.PlayerChangeStarts(
          from: ConnectionId(3),
          from_stay: game_connection_support.viewer_stay(3),
          source: kept_source,
          change: held_changes.Applies(held_changes.Absorb(amount: 300, mask: 7)),
          sight: held_changes.KeptWhenUnseen,
          spell4_id: Spell4Id(32_823),
          effect: unit_casts.HeldEffect(
            effect_id: kept_source.effect_id,
            starts_ms: 1000,
            ends: unit_casts.EndsAt(ms: 11_000),
          ),
        )),
      ),
    ),
    from_unit(
      unit_id: orphan_caster,
      news: created_listing(unit_id: orphan_caster, casts: []),
    ),
    from_unit(
      unit_id: orphan_caster,
      news: unit_news.CastStarted(
        start: game_connection_support.spell_started_of(
          cast_id: orphan_id,
          caster: orphan_caster,
        ),
      ),
    ),
    from_unit(unit_id: orphan_caster, news: Removed),
  ]
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
  let ally_appears = appears(unit_id: ally)
  let ally_starts = the_allys_start(unit_id: ally, cast_id:, caster:)
  let ally_ends = the_allys_end(unit_id: ally, cast_id:)
  let ally_lists = lists(unit_id: ally, cast_id:, caster:)
  let caster_appears = appears(unit_id: caster)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let caster_finishes = the_casters_finish(unit_id: caster, cast_id:)
  let assert unit_news.HeldCastStarted(start:, go:) =
    held_cast_started(cast_id:, caster:)
  let written = [Started(start:), Went(go:)]
  let orphan_caster = orphan_caster_unit()
  let orphaned_by_its_caster_leaving =
    list.append(orphaned_by_its_caster_leaving(), [ally_appears])
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
  check_written_rows(rows:)
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
      game_connection_support.cast_starts(
        game_connection_support.news_broadcast(taken),
      )
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

/// The news the Medic's connection tells the map after Discharge, pressed at 1000 ms with
/// the connection 2 watching, run to the end of its casts, and the casts the watcher 2 was
/// told started. Discharge's first go, 410 ms in, starts a Power Charge (Spell4 42569) that no
/// go of Discharge ends: its cast lingers until its buff ends.
fn discharge_told_to_the_map() -> #(
  List(spell_started.SpellStarted),
  List(unit_news.News),
) {
  let tables = character_tables.shared()
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
  let #(_, ran) =
    game_connection_support.casts_run(
      state:,
      pending: game_connection_support.cast_timers(steps: pressed, ms: 1000),
      until_ms: 100_000,
      steps: [],
    )
  let steps = list.append(pressed, ran)
  #(
    list.flat_map(steps, fn(taken) {
      game_connection_support.cast_starts(
        game_connection_support.news_broadcast(taken),
      )
    }),
    list.flat_map(steps, fn(taken) {
      game_connection_support.news_broadcast(taken)
    }),
  )
}

/// Whether the news end the cast `cast_id` for the viewer: its 0x811 that takes the Medic's
/// node off it, or its 0x7fe.
fn told_of(told told: List(unit_news.News), cast_id cast_id: Int) -> Bool {
  list.contains(told, CastFinished(cast_id:))
  || list.any([False, True], fn(destroyed) {
    list.contains(
      told,
      unit_news.CastTargetsRemoved(
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
      game_connection_support.cast_starts(
        game_connection_support.news_broadcast(taken),
      )
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
/// `cast.target_node_end`: the caster tells the map Discharge's finish and the end of the
/// Power Charge it left, once each, for the viewers' ledgers to judge.
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
  // The caster tells the map each news of Discharge's life once, whoever is in sight; which of
  // them a viewer writes is its ledger's decision, stated by the ledger rows of
  // `a_cast_finished_at_the_viewer_before_the_allys_start_is_written_no_start_and_the_start_first_is_dropped_then_the_finish_written_test`.
  let #(started, told) = discharge_told_to_the_map()
  let assert [discharge, ..] = started
  let assert Ok(power_charge) =
    list.find(started, fn(start) { start.spell4_id == 42_569 })
    as "the first go starts a Power Charge"
  assert discharge.spell4_id == 58_832
  assert list.contains(told, CastFinished(cast_id: discharge.cast_id))
    as "Discharge's finish is told to the map"
  assert told_of(told:, cast_id: power_charge.cast_id)
    as "the Power Charge's end is told to the map"
  assert list.count(told, fn(news) {
      list.any([False, True], fn(destroyed) {
        news
        == unit_news.CastTargetsRemoved(
          removed: spell_targets_removed.SpellTargetsRemoved(
            cast_id: power_charge.cast_id,
            unit_ids: [game_connection_support.own_unit_id],
          ),
          destroyed:,
        )
      })
    })
    == 1
    as "and told once"
}

/// `opcode.0x262.casts` and `cast.target_node_end`: the casts a viewer's ledger holds are those
/// its create lists, and the map relays it the news of every cast, so what the create lists
/// decides which news the viewer writes a frame for. Discharge's Power Charge (Spell4 42569)
/// is given a cast time of 1000 ms, so that this child cast of the first go (410 ms in) waits
/// 1000 ms before its own first go makes its node: a create at 1500 ms does not list it, and
/// a create at 2600 ms, after the node, does.
pub fn a_create_lists_only_the_casts_that_hold_a_node_when_it_is_built_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Spell4", id: 42_569, with: [
    #("castTime", planted_table.Integer(1000)),
  ])
  list.each(
    [
      #(
        "a viewer that comes while the Power Charge waits for its first go is listed Discharge, the current cast, and not the Power Charge: it holds no node yet",
        1500,
        True,
        False,
      ),
      #(
        "a viewer that comes after the node is listed the Power Charge",
        2600,
        False,
        True,
      ),
    ],
    fn(row) {
      let #(name, at_ms, lists_discharge, lists_power_charge) = row
      let #(state, _, bag_index) =
        game_connection_support.entered_with_server_proxies(
          class_id: 4,
          ability: discharge_base,
          proxies: server_proxy_support.none(),
          tables:,
        )
      let #(state, steps) =
        game_connection_support.pressed_until(
          state: game_connection_support.watched_by(state:, viewers: [2]),
          bag_index:,
          client_cast_id: 1,
          ms: 1000,
          until_ms: at_ms,
        )
      let started =
        list.flat_map(steps, fn(taken) {
          game_connection_support.cast_starts(
            game_connection_support.news_broadcast(taken),
          )
        })
      let assert [discharge, ..] = started
      let assert Ok(power_charge) =
        list.find(started, fn(start) { start.spell4_id == 42_569 })
        as "the first go starts a Power Charge"
      let listed =
        list.map(
          game_connection_support.created_at(state:, viewer: 3, ms: at_ms).tail.casts,
          fn(cast) { cast.cast_id },
        )
      assert list.contains(listed, discharge.cast_id) == lists_discharge as name
      assert list.contains(listed, power_charge.cast_id) == lists_power_charge
        as name
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
    from_the_caster(Appeared(
      game_connection_support.another_unit_casting(
        casts: [game_connection_support.listed_cast(cast_id: given, caster: 9)],
        cast_id: given,
      ),
      generation: generation.first(),
    ))
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
      let state = game_connection_support.fed(events: setup)
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
    generation: game_connection_support.viewer_sight(viewer),
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
          let assert SeenBy(by:, stay:, unit_id:, ..) = notice
            as "the rows hold SeenBy notices"
          #(by, Viewer(stay:, unit_id:, generation: generation.first()))
        })
        |> dict.from_list
      let picture =
        list.map(shown_units, fn(unit_id) { #(unit_id, player) })
        |> dict.from_list
      let expected =
        list.filter_map(notices, fn(notice) {
          let assert SeenBy(by:, stay:, unit_id:, ..) = notice
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
        generation: game_connection_support.viewer_sight(3),
      )),
    )
  let #(_, moved) =
    game_connection_support.read(
      state,
      game_connection_support.moves_message([
        game_client.position_command(x: 1.0, y: 2.0, z: 3.0),
      ]),
    )
  assert list.map(game_connection_support.move_tells(taken: moved), fn(sent) {
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
      unit_news.Health(health: 0, dead: True),
      unit_news.CameBack,
      unit_news.Died,
      unit_news.CombatState(in_combat: True),
      unit_news.CrowdControlApplied(
        state: crowd_control_state.Stun,
        instance_id: 5,
      ),
      unit_news.CrowdControlEnded(
        state: crowd_control_state.Stun,
        cast_id: 6,
        instance_id: 5,
      ),
      unit_news.Removed,
    ])
    == [
      [0x0937],
      [0x088C],
      [0x088C],
      [0x089A],
      [0x087F],
      [0x0880],
      [0x0355],
    ]
    as "each news writes the frames it wrote before the picture held a player's state: Health 0x937, CameBack and Died 0x88c, CombatState 0x89a, 0x87f, 0x880 and 0x355"
}

/// The ids of the messages the viewer writes for each news of the unit 9 in turn, once the
/// unit's 0x262 has come.
fn written_for_news(news news: List(unit_news.News)) -> List(List(Int)) {
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
    news: unit_news.News,
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
    unit_news.PropertiesChanged(properties: [
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
      Appeared(
        unit: player_with(
          faction: 167,
          health: 5000,
          pvp_flags: 0,
          group_id: 0,
          place: there,
        ),
        generation: generation.first(),
      ),
    )
  assert copy_of(session, 9) == #(True, 5000, players_base_health)
    as "the copy holds the health stat and the Base Health of the 0x262"
  let hurt = take(session, 9, unit_news.Health(health: 4200, dead: False))
  assert copy_of(hurt, 9) == #(True, 4200, players_base_health)
    as "a Health news sets the health and keeps the maximum"
  let dead = take(hurt, 9, unit_news.Health(health: 0, dead: True))
  assert copy_of(dead, 9) == #(False, 0, players_base_health)
    as "a Health news with the dead bit sets the player dead at health 0"
  let revived = take(dead, 9, unit_news.Health(health: 3000, dead: False))
  assert copy_of(revived, 9) == #(True, 3000, players_base_health)
    as "a Health news without it sets the player alive again"
  // A death by the Health news alone (no Died news follows) also empties what the copy holds
  // (`shown.with_alive`: a dead unit holds no crowd-control state).
  let held_of = fn(session: connection_state.Session, unit_id: Int) {
    let assert Some(entered) = connection_state.entered_of(session.status)
      as "the player is in the world"
    let assert Ok(shown.ShownPlayer(state:)) = dict.get(entered.shown, unit_id)
      as "the unit is a shown player"
    state.held
  }
  let stunned =
    take(
      revived,
      9,
      unit_news.CrowdControlApplied(
        state: crowd_control_state.Stun,
        instance_id: 5,
      ),
    )
  assert held_of(stunned, 9)
    == [held_state.HeldState(state: crowd_control_state.Stun, instance_id: 5)]
    as "the copy holds the stun its owner's news gave"
  let stunned_and_hurt =
    take(stunned, 9, unit_news.Health(health: 2500, dead: False))
  assert held_of(stunned_and_hurt, 9) != []
    as "a Health news without the dead bit keeps what the copy holds"
  let killed = take(stunned, 9, unit_news.Health(health: 0, dead: True))
  assert copy_of(killed, 9) == #(False, 0, players_base_health)
    as "a Health news alone with the dead bit sets the player dead"
  assert held_of(killed, 9) == []
    as "and the dead player holds no crowd-control state, though no Died news followed"
  let grown = take(revived, 9, property_7(7000))
  assert copy_of(grown, 9) == #(True, 3000, 7000)
    as "a PropertiesChanged news with property 7 sets the maximum and keeps the health"
  let other_property =
    take(
      grown,
      9,
      unit_news.PropertiesChanged(properties: [
        UnitProperty(property_id: 8, base: 0, value: 0),
      ]),
    )
  assert copy_of(other_property, 9) == #(True, 3000, 7000)
    as "a PropertiesChanged news without property 7 keeps the maximum"
  let unshown = take(grown, 77, unit_news.Health(health: 1, dead: False))
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

/// What a unit's removal writes to the client, as the tests tell it apart: the finish of a
/// cast, the 0x355 of a unit, or any other frame by its opcode.
type RemovalWrote {
  CastFinish(cast_id: Int)
  UnitRemoved(unit_id: Int)
  RemovalWroteOther(opcode: Int)
}

fn removal_wrote(frames frames: List(Frame)) -> List(RemovalWrote) {
  list.map(frames, fn(frame) {
    case frame.message_id {
      0x07FE -> CastFinish(cast_id: cast_support.finished_cast_id(frame))
      0x0355 -> {
        let assert [unit_id] =
          game_wire_support.destroyed_units(frames: [frame])
          as "a 0x355 the viewer wrote removes one unit"
        UnitRemoved(unit_id:)
      }
      opcode -> RemovalWroteOther(opcode:)
    }
  })
}

/// How a unit's removal reaches the viewer: as the owner's `Removed` news, as the map's
/// `Gone`, as the map's `ObjectsUnseen`, as the map's `Unseen` of a creature, or as a call of the removal function with the
/// casts it is to keep.
type Remover {
  ByRemovedNews
  ByMapsGone
  ByObjectsUnseen
  ByUnitUnseen
  Directly(keeping: List(Int))
}

/// The unit shown to the player of the tests, and the casts of the unit its client holds.
type RemovedScene {
  RemovedScene(
    shown: Bool,
    written: List(Int),
    borrowed: List(Int),
    kept_when_unseen: List(Int),
  )
}

fn remover_name(remover: Remover) -> String {
  case remover {
    ByRemovedNews -> "by a removal news"
    ByMapsGone -> "by the map's gone"
    ByObjectsUnseen -> "by the map's objects unseen"
    ByUnitUnseen -> "by the map's creature unseen"
    Directly(keeping:) ->
      "by the function, keeping "
      <> string.join(list.map(keeping, int.to_string), ", ")
  }
}

const removed_unit_id = 40

/// The player in the world, its client holding what the scene says of unit 40: the casts the
/// unit's own frames started, the casts an ally listed, and a held change of a spell that
/// outlives its caster's sight for each cast in `kept_when_unseen`.
fn viewer_of(scene scene: RemovedScene) -> connection_state.Session {
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  let casts =
    list.fold(scene.written, client_casts.new(), fn(casts, cast_id) {
      client_casts.written(casts:, cast_id:, caster_unit_id: removed_unit_id)
    })
  let casts =
    list.fold(scene.borrowed, casts, fn(casts, cast_id) {
      client_casts.borrow(casts:, cast_id:, ally_unit_id: removed_unit_id)
    })
  let held =
    list.fold(scene.kept_when_unseen, held_changes.new(), fn(held, cast_id) {
      held_changes.started(
        held:,
        by: ConnectionId(3),
        unit_id: removed_unit_id,
        source: unit_properties.Source(
          cast_id:,
          effect_id: Spell4EffectsId(62_024),
        ),
        sight: held_changes.KeptWhenUnseen,
        spell4_id: Spell4Id(32_823),
        effect: unit_casts.HeldEffect(
          effect_id: Spell4EffectsId(62_024),
          starts_ms: 1000,
          ends: unit_casts.EndsAt(ms: 11_000),
        ),
        trigger: None,
      ).0
    })
  let entered =
    world_entry.Entered(
      ..entered,
      shown: case scene.shown {
        True ->
          dict.insert(
            entered.shown,
            removed_unit_id,
            shown.ShownPlayer(state: player_state_support.a_player()),
          )
        False -> entered.shown
      },
      client_casts: casts,
      held:,
    )
  game_connection_support.session_in(status: connection_state.InWorld(
    holder: game_connection_support.holder(),
    entered:,
  ))
}

pub fn a_unit_removal_writes_each_casts_finish_before_the_0x355_for_every_caller_and_keeps_only_what_a_removal_keeps_test() -> Nil {
  use <- owned_test.run(10_000)
  // Client fact `cast.target_node_end`: the client keeps a cast of a spell with
  // propertyFlags 0x100 when its caster's unit is removed and keeps no other, so the viewer
  // writes the 0x7fe of each cast of the unit it started, in cast id order, before the
  // unit's 0x355, except the casts a held change keeps, which it holds with no caster
  // instead. A removal news keeps those; the map's `Gone` and `ObjectsUnseen` end the held
  // changes too, so they keep none. A cast an ally listed is never finished by the unit's frames. Each row: the
  // unit as its client holds it, how it is removed, what is written, and the casts still
  // held (cast ids 100 to 103) and orphaned after. The rows of the two callers are the
  // output of the arms before the removal was one function.
  let unit = removed_unit_id
  let casts =
    RemovedScene(shown: True, written: [], borrowed: [], kept_when_unseen: [])
  let two_written = RemovedScene(..casts, written: [102, 101])
  let one_kept =
    RemovedScene(..casts, written: [101, 100], kept_when_unseen: [100])
  let one_borrowed = RemovedScene(..casts, written: [101], borrowed: [103])
  let not_shown = RemovedScene(..casts, shown: False)
  let rows = [
    #(
      "a shown unit with no cast is written its 0x355 only, by each caller",
      casts,
      [
        ByRemovedNews,
        ByMapsGone,
        ByObjectsUnseen,
        ByUnitUnseen,
        Directly(keeping: []),
      ],
      [UnitRemoved(unit)],
      [],
      [],
    ),
    #(
      "two written casts are finished in cast id order before the 0x355, by each caller",
      two_written,
      [
        ByRemovedNews,
        ByMapsGone,
        ByObjectsUnseen,
        ByUnitUnseen,
        Directly(keeping: []),
      ],
      [CastFinish(101), CastFinish(102), UnitRemoved(unit)],
      [],
      [],
    ),
    #(
      "a removal news keeps the cast a held change keeps: no finish, and the cast is held with no caster",
      one_kept,
      [ByRemovedNews, Directly(keeping: [100])],
      [CastFinish(101), UnitRemoved(unit)],
      [100],
      [100],
    ),
    #(
      "the map's gone finishes every written cast, the kept one too, and holds none",
      one_kept,
      [
        ByMapsGone,
        ByObjectsUnseen,
        ByUnitUnseen,
        Directly(keeping: []),
      ],
      [CastFinish(100), CastFinish(101), UnitRemoved(unit)],
      [],
      [],
    ),
    #(
      "a cast an ally listed is not finished by the unit, and the unit no longer holds it",
      one_borrowed,
      [
        ByRemovedNews,
        ByMapsGone,
        ByObjectsUnseen,
        ByUnitUnseen,
        Directly(keeping: []),
      ],
      [CastFinish(101), UnitRemoved(unit)],
      [],
      [],
    ),
    #(
      "a unit that is not shown writes nothing",
      not_shown,
      [
        ByRemovedNews,
        ByMapsGone,
        ByObjectsUnseen,
        ByUnitUnseen,
        Directly(keeping: []),
      ],
      [],
      [],
      [],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, scene, removers, written, held_after, orphans_after) = row
    list.each(removers, fn(remover) {
      let reason = reason <> " (" <> remover_name(remover) <> ")"
      let session = viewer_of(scene:)
      let assert Some(entered) = connection_state.entered_of(session.status)
        as "the player is in the world"
      let now = step.Now(monotonic_ms: 0, filetime: 0)
      let #(session, effects, ended) = case remover {
        ByRemovedNews -> {
          let assert client_connection.Continue(session:, effects:) =
            viewers.viewer_takes(
              session:,
              now:,
              entered:,
              news: PeerNews(unit_id: unit, news: Removed),
            )
            as reason
          #(session, effects, [])
        }
        ByMapsGone -> {
          let assert client_connection.Continue(session:, effects:) =
            viewers.map_sent(
              session:,
              now:,
              entered:,
              notice: map.Gone(unit_id: unit),
            )
            as reason
          #(session, effects, [])
        }
        ByObjectsUnseen -> {
          let assert client_connection.Continue(session:, effects:) =
            viewers.map_sent(
              session:,
              now:,
              entered:,
              notice: map.ObjectsUnseen(unit_ids: [unit]),
            )
            as reason
          #(session, effects, [])
        }
        ByUnitUnseen -> {
          let assert client_connection.Continue(session:, effects:) =
            viewers.map_sent(
              session:,
              now:,
              entered:,
              notice: map.UnitUnseen(
                unit_id: unit,
                generation: generation.first(),
              ),
            )
            as reason
          #(session, effects, [])
        }
        Directly(keeping:) -> {
          let #(session, removal) =
            viewers.unit_removed(
              session:,
              now:,
              entered:,
              unit_id: unit,
              keeping:,
            )
          #(session, removal.written, removal.ended)
        }
      }
      assert removal_wrote(frames: game_connection_support.heard(
          taken: step.Effects(effects:),
          cipher: cipher.base(),
        ))
        == written
        as reason
      assert ended == []
        as { reason <> ": the player's casts hold no node on the unit" }
      let assert Some(after) = connection_state.entered_of(session.status)
        as "the player is still in the world"
      assert list.filter([100, 101, 102, 103], fn(cast_id) {
          client_casts.is_held(casts: after.client_casts, cast_id:, now_ms: 0)
        })
        == held_after
        as { reason <> ": the casts the client still holds" }
      assert client_casts.orphans(casts: after.client_casts) == orphans_after
        as { reason <> ": the casts held with no caster" }
      assert !dict.has_key(after.shown, unit)
        as { reason <> ": the unit is no longer shown" }
    })
  })
  // The map's `Gone` marks the unit gone whether or not it was shown, so a 0x262 of the
  // owner that ended, which lands after it, shows no ghost.
  list.each([casts, not_shown], fn(scene) {
    let session = viewer_of(scene:)
    let assert Some(entered) = connection_state.entered_of(session.status)
      as "the player is in the world"
    let assert client_connection.Continue(session:, ..) =
      viewers.map_sent(
        session:,
        now: step.Now(monotonic_ms: 0, filetime: 0),
        entered:,
        notice: map.Gone(unit_id: unit),
      )
    let assert Some(after) = connection_state.entered_of(session.status)
      as "the player is still in the world"
    assert set.contains(after.gone, unit)
  })
  // The player's own cast holds a node on the Beast 40 that lingers with no 0x7fe: each
  // caller that ends the Beast writes the 0x355 and then the cast's 0x7fe the cast rule
  // asks (`ended`), as the client drops the node with the 0x355 and the lingering cast
  // then ends with its 0x7fe (`cast.target_node_end`, `0x1404550d0`), and tells the viewer
  // of the cast its finish. The order of the held changes' finishes among them is the
  // job of `a_caster_leaving_the_sight_of_a_player_that_holds_its_kept_change_is_not_finished_on_the_players_client_test`.
  use tables <- game_connection_support.with_a_lingering_node_row()
  list.each(
    [
      #(
        "by a removal news",
        game_connection_support.sent_by_a_peer(game_connection_support.news_of(
          unit_id: 40,
          news: Removed,
        )),
      ),
      #(
        "by the map's gone",
        game_connection_support.sent_by_the_map(map.Gone(unit_id: 40)),
      ),
      #(
        "by the map's objects unseen",
        game_connection_support.sent_by_the_map(
          map.ObjectsUnseen(unit_ids: [40]),
        ),
      ),
    ],
    fn(row) {
      let #(reason, event) = row
      let #(state, _, cast_id) =
        game_connection_support.medic_with_a_lingering_node_on_beast(tables)
      let #(_, removed) = game_connection_support.feed(state, event)
      assert game_connection_support.written_ids(removed) == [0x0355, 0x07FE]
        as {
          reason
          <> ": the unit's 0x355, then the 0x7fe of the lingering cast its nodes left"
        }
      assert list.contains(
        game_connection_support.news_broadcast(removed),
        CastFinished(cast_id:),
      )
        as { reason <> ": the viewer told the cast's start is told its finish" }
    },
  )
}

pub fn a_failed_write_while_a_viewer_takes_a_relayed_burst_ends_the_connection_and_the_map_unsees_the_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // Expected values: a write of a step that failed leaves the later effects of the step
  // uncarried and ends the connection (`step.WriteFailed`); a connection that ends is the
  // watch's end for the map, which removes the player and tells each creature it had a
  // relation with `Unseen` (the doc comment of `genesis_prime/world_map/map`).
  let beast = spawn_support.battle_beast(number: 1, x: 0.0)
  let #(map_state, joined) =
    map_spawn_support.join(
      state: map_spawn_support.started_with_spawns(spawns: [beast]),
      at_ms: 6000,
      connection: 1,
      x: 0.0,
    )
  let assert [#(_, start)] = map_spawn_support.starts(joined)
    as "the viewer's join starts the creature"
  let assert [#(watch, _)] = support.watches(joined)
    as "the join opens the watch on the viewer's connection"
  let #(creature_state, _) =
    legal_order_support.creature_started(start:, spawn: beast, at_ms: 6000)
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id: start.unit_id,
      damage_type: 3,
      damage: 5,
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
    )
  let #(creature_state, _) =
    creature.step(
      creature_state,
      support.input_at_ms(
        ms: 6100,
        event: OwnEvent(step.Told(creature.Strike(tell:))),
      ),
    )
  assert creature_fight.threatened(state: creature.fight(state: creature_state))
    == set.from_list([ConnectionId(1)])
    as "the viewer's strike put it on the creature's threat list"
  // The creature's snapshot reaches the map, which relays its burst, two news, to the viewer.
  let assert Ok(map.Live(unit_id:, life:, relations:, ..)) =
    map.spawn_state(state: map_state, spawn: SpawnId(1))
  let assert Ok(map.Relation(generation: held, ..)) =
    dict.get(relations, ConnectionId(1))
  let #(map_state, relayed) =
    map_spawn_support.feed(
      state: map_state,
      at_ms: 6200,
      event: OwnEvent(
        step.Told(
          map.Snapshot(
            unit_id:,
            life:,
            by: ConnectionId(1),
            generation: held,
            burst: [
              PeerNews(
                unit_id:,
                news: unit_news.Health(health: 52, dead: False),
              ),
              PeerNews(
                unit_id:,
                news: unit_news.Health(health: 40, dead: False),
              ),
            ],
          ),
        ),
      ),
    )
  let assert [first, _second] =
    list.filter_map(support.sends(relayed), fn(sent) {
      server.map_message(outgoing: sent.1)
    })
    as "the burst is relayed as two messages for the viewer"
  let #(viewer, _) =
    game_connection_support.feed(
      state: game_connection_support.in_world(),
      event: OwnEvent(Woken(first)),
    )
  // The step's write fails: the connection ends, and writes nothing more.
  let #(_, failed) =
    game_connection_support.feed(
      state: viewer,
      event: OwnEvent(step.WriteFailed(step.SendTimedOut)),
    )
  assert support.asked(failed) != None
    as "a failed write ends the connection that holds a player in the world: it starts with the save of the player's place (`connection_state.end_with`), so the burst's second message is never taken"
  assert support.writes(failed) == [] as "and no frame follows the failed one"
  // The map takes the watch's end of the viewer's connection.
  let #(_, ended) =
    map_spawn_support.feed(
      state: map_state,
      at_ms: 6300,
      event: step.WatchEnded(watch:),
    )
  let assert [
    #(step.Creature(unit_id: told_unit, ..), unseen),
    #(step.Creature(..), caster_gone),
  ] =
    list.filter(map_spawn_support.sends(ended), fn(sent) {
      case sent.0 {
        step.Creature(..) -> True
        _ -> False
      }
    })
    as "the map tells the creature the viewer's sight ended, then that the viewer is gone"
  assert creature.told_by_map(caster_gone)
    == Ok(creature.CasterGone(by: ConnectionId(1)))
    as "and the second tell is the map's CasterGone of the viewer's connection"
  assert told_unit == unit_id
  let assert Ok(told) = creature.told_by_map(unseen)
  assert told == creature.Unseen(by: ConnectionId(1), generation: held)
    as "under the generation of the sight the viewer held"
  let #(creature_state, _) =
    creature.step(
      creature_state,
      support.input_at_ms(ms: 6400, event: OwnEvent(step.Told(told))),
    )
  assert !set.contains(creature.viewers(state: creature_state), ConnectionId(1))
    as "the creature's copy of its viewers drops the connection"
  assert creature_fight.threatened(state: creature.fight(state: creature_state))
    == set.new()
    as "and its threat entry goes with it"
}

// ---- a player's move at its viewer: the sight number it is stamped with
//
// Expected values: the rule of genesis_prime/game/move_stamp (a viewer applies a move only
// for the generation it holds, drops an older one, holds a newer one until the map's notice
// of its generation, and remembers a unit that left by the last generation that ended).
// Each move is made by the mover's own rule from a copy that holds the viewer at the sight
// the row names, then given the unit 9's id, so the viewer shows it as the unit it holds.

/// The generation the row's number names: the `n`th the tests' map gave.
fn sight(n n: Int) -> generation.Generation {
  game_connection_support.viewer_sight(n)
}

/// A move of the unit 9 for the sight `sight_number`, as the mover's rule sends it to a
/// viewer whose sight of it is that one, with the position x.
fn move_of_unit_9(
  sight_number sight_number: Int,
  x x: Float,
) -> move_stamp.Move {
  let state =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
        generation: sight(n: sight_number),
      )),
    ).0
  let #(_, taken) =
    game_connection_support.read(state, game_connection_support.a_move(x))
  let assert [#(2, _, move)] = game_connection_support.move_tells(taken:)
    as "the mover sends its one viewer one chunk"
  move_stamp.Move(..move, unit_id: 9)
}

/// The player in the world, its client holding nothing yet.
fn moving_viewer() -> connection_state.Session {
  game_connection_support.session_in(status: connection_state.InWorld(
    holder: game_connection_support.holder(),
    entered: world_entry_support.entered_after(clock_origin_ms: 600),
  ))
}

/// What a viewer's function of a message about a unit does.
type Done =
  step.Step(
    client_connection.Request,
    step.ConnectionEffect(client_connection.Request),
  )

/// The session after a message about a unit, and what it does.
type Taken =
  #(connection_state.Session, Done)

fn taken_from(
  handled: client_connection.Handled(connection_state.Session),
) -> Taken {
  let assert client_connection.Continue(session:, effects:) = handled
    as "the viewer continues"
  #(session, step.Effects(effects:))
}

fn entered_of(
  session session: connection_state.Session,
) -> world_entry.Entered {
  let assert Some(entered) = connection_state.entered_of(session.status)
    as "the player is in the world"
  entered
}

const at_ms_zero = step.Now(monotonic_ms: 0, filetime: 0)

/// The unit `unit_id` is created in the viewer's client, for the sight `sight_number`.
fn appeared(
  session session: connection_state.Session,
  unit_id unit_id: Int,
  sight_number sight_number: Int,
) -> Taken {
  viewers.viewer_takes(
    session:,
    now: at_ms_zero,
    entered: entered_of(session:),
    news: PeerNews(
      unit_id:,
      news: Appeared(
        unit: UnitCreatePlayer(
          ..game_connection_support.another_unit(),
          unit_id:,
        ),
        generation: sight(n: sight_number),
      ),
    ),
  )
  |> taken_from
}

/// The sight `sight_number` of the unit 9 ends.
fn departed_at(
  session session: connection_state.Session,
  sight_number sight_number: Int,
) -> Taken {
  viewers.map_sent(
    session:,
    now: at_ms_zero,
    entered: entered_of(session:),
    notice: map.PlayerUnseen(unit_id: 9, generation: sight(n: sight_number)),
  )
  |> taken_from
}

/// The map reports the unit 9 gone.
fn reported_gone(session session: connection_state.Session) -> Taken {
  viewers.map_sent(
    session:,
    now: at_ms_zero,
    entered: entered_of(session:),
    notice: map.Gone(unit_id: 9),
  )
  |> taken_from
}

/// The viewer takes a chunk of a move.
fn moved(
  session session: connection_state.Session,
  move move: move_stamp.Move,
) -> Taken {
  viewers.move_sent(
    session:,
    now: at_ms_zero,
    entered: entered_of(session:),
    move:,
  )
  |> taken_from
}

/// The ids of the messages the step writes.
fn written(taken taken: Done) -> List(Int) {
  list.map(frames_of(taken:), fn(frame) { frame.message_id })
}

/// The frames the step writes, as the client reads them from a session that holds the base
/// cipher.
fn frames_of(taken taken: Done) -> List(Frame) {
  game_connection_support.heard(taken:, cipher: game_connection_support.base())
}

/// The x each 0x638 the step writes puts its unit at, in order, as the client's float bits.
fn written_xs(taken taken: Done) -> List(Int) {
  list.filter_map(frames_of(taken:), fn(frame) {
    case frame.message_id == 0x0638 {
      False -> Error(Nil)
      True -> {
        let assert Ok(moved) = unit_movement.decode(frame.body)
          as "a 0x638 decodes"
        let assert [relayed_movement.Position(position), ..] = moved.commands
          as "the first command is the position"
        Ok(position.x)
      }
    }
  })
}

/// The chunks the viewer holds for the unit `unit_id`.
fn chunks_held(
  session session: connection_state.Session,
  unit_id unit_id: Int,
) -> Int {
  case dict.get({ entered_of(session:) }.viewing.holds, unit_id) {
    Ok(waiting) -> list.length(waiting.moves)
    Error(Nil) -> 0
  }
}

/// The place the picture holds for the unit 9.
fn picture_place(session session: connection_state.Session) -> Option(Place) {
  let assert Ok(shown.ShownPlayer(state:)) =
    dict.get({ entered_of(session:) }.shown, 9)
    as "the unit 9 is a shown player"
  state.place
}

pub fn a_move_is_applied_only_for_the_generation_the_viewer_holds_an_older_one_is_dropped_and_a_newer_one_or_one_for_a_unit_not_held_is_held_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each row: what the viewer was told of the unit 9 (True: its 0x262 for the sight `n`,
  // False: the end of the sight `n`), the sight the move is stamped with, whether the
  // move is written and moves the picture, and how many chunks the viewer holds after it.
  let unseen = []
  let held_5 = [#(True, 5)]
  let departed_5 = [#(True, 5), #(False, 5)]
  let rows = [
    #("a move of the held sight", held_5, 5, True, 0),
    #("an older move than the held sight", held_5, 4, False, 0),
    #("a newer move than the held sight", held_5, 6, False, 1),
    #("a move of the sight that ended", departed_5, 5, False, 0),
    #("an older move than the sight that ended", departed_5, 4, False, 0),
    #("a newer move than the sight that ended", departed_5, 6, False, 1),
    #("a move of a unit the viewer holds nothing of", unseen, 3, False, 1),
  ]
  list.each(rows, fn(row) {
    let #(reason, told, stamped, applied, held) = row
    let session =
      list.fold(told, moving_viewer(), fn(session, told) {
        case told {
          #(True, n) -> appeared(session:, unit_id: 9, sight_number: n).0
          #(False, n) -> departed_at(session:, sight_number: n).0
        }
      })
    let #(moved_session, taken) =
      moved(session:, move: move_of_unit_9(sight_number: stamped, x: 77.0))
    assert written(taken:)
      == case applied {
        True -> [0x0638]
        False -> []
      }
      as { reason <> ": what is written" }
    assert chunks_held(session: moved_session, unit_id: 9) == held
      as { reason <> ": what the viewer holds after it" }
    case applied, dict.get({ entered_of(session: moved_session) }.shown, 9) {
      True, Ok(shown.ShownPlayer(state:)) -> {
        let assert Some(place) = state.place
          as "the picture holds the move's place"
        assert start_place.x(place) == 77.0
          as { reason <> ": the picture is at the move's place" }
        Nil
      }
      False, Ok(shown.ShownPlayer(..)) -> {
        assert picture_place(session: moved_session) == picture_place(session:)
          as { reason <> ": the picture does not move" }
        Nil
      }
      _, Ok(_) | _, Error(Nil) -> Nil
    }
  })
}

pub fn the_notice_of_a_generation_writes_the_0x262_then_the_held_moves_of_that_generation_in_order_drops_older_ones_and_keeps_newer_ones_and_a_released_move_moves_the_picture_as_a_move_taken_at_once_does_test() -> Nil {
  use <- owned_test.run(10_000)
  // The viewer holds nothing of the unit 9 and is sent four moves before its notices:
  // 5a, 5b, 4c and 6d, of x 10, 20, 30 and 40.
  let held =
    list.fold(
      [#(5, 10.0), #(5, 20.0), #(4, 30.0), #(6, 40.0)],
      moving_viewer(),
      fn(session, move) {
        let #(sight_number, x) = move
        moved(session:, move: move_of_unit_9(sight_number:, x:)).0
      },
    )
  assert chunks_held(session: held, unit_id: 9) == 4
    as "no notice yet: every move is held"
  let #(session, taken) = appeared(session: held, unit_id: 9, sight_number: 5)
  assert written(taken:) == [0x0262, 0x0638, 0x0638]
    as "the 0x262 first, then the held moves of that sight"
  assert written_xs(taken:) == [float32.to_bits(10.0), float32.to_bits(20.0)]
    as "in the order they arrived; 4c is dropped and 6d is not written"
  assert chunks_held(session:, unit_id: 9) == 1
    as "the move of a later sight is still held"
  let direct =
    list.fold(
      [#(5, 10.0), #(5, 20.0)],
      appeared(session: moving_viewer(), unit_id: 9, sight_number: 5).0,
      fn(session, move) {
        let #(sight_number, x) = move
        moved(session:, move: move_of_unit_9(sight_number:, x:)).0
      },
    )
  assert picture_place(session:) == picture_place(session: direct)
    as "a released move moves the picture as one taken at once does"
  let #(session, taken) = departed_at(session:, sight_number: 5)
  assert written(taken:) == [0x0355] as "the end of the sight writes the 0x355"
  assert chunks_held(session:, unit_id: 9) == 1
    as "and drops nothing of a later sight"
}

pub fn a_unit_that_left_is_remembered_by_its_last_generation_so_a_late_move_of_that_sight_is_dropped_and_not_held_and_a_later_sight_is_held_test() -> Nil {
  use <- owned_test.run(10_000)
  let session =
    appeared(session: moving_viewer(), unit_id: 9, sight_number: 5).0
  let session = departed_at(session:, sight_number: 5).0
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 1.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "a late move of the sight that ended is dropped, and nothing waits for a notice that never comes"
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 6, x: 2.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 1
    as "a move of a later sight is held for its notice"
  let #(session, _) = reported_gone(session:)
  assert chunks_held(session:, unit_id: 9) == 0
    as "the owner's end drops what was held for it"
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 3.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "the memory outlives the owner's end: a late move of the sight is dropped"
  let shown_then_gone =
    appeared(session: moving_viewer(), unit_id: 9, sight_number: 5).0
  let session = reported_gone(session: shown_then_gone).0
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 4.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "a unit shown and then ended by its owner is remembered by the sight it was shown at"
}

pub fn a_notice_of_a_sight_the_viewer_holds_as_ended_writes_nothing_is_an_error_and_its_moves_are_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  let session =
    appeared(session: moving_viewer(), unit_id: 9, sight_number: 5).0
  let session = departed_at(session:, sight_number: 5).0
  let #(session, taken) = appeared(session:, unit_id: 9, sight_number: 5)
  assert written(taken:) == []
    as "the sight 5 ended, so a second notice of it creates no unit the viewer would then never move"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "the map issues generations in order, so a notice older than the sight that ended is its bug"
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 1.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "and a move of that sight is dropped"
  let #(_, taken) = appeared(session:, unit_id: 9, sight_number: 6)
  assert written(taken:) == [0x0262] as "a later sight is shown"
}

pub fn the_maps_gone_before_the_owners_notice_drops_what_is_held_for_the_unit_with_one_warning_that_names_it_and_counts_the_chunks_test() -> Nil {
  use <- owned_test.run(10_000)
  let two_held =
    list.fold([1.0, 2.0], moving_viewer(), fn(session, x) {
      moved(session:, move: move_of_unit_9(sight_number: 5, x:)).0
    })
  let #(session, taken) = reported_gone(session: two_held)
  let assert [warning] = support.logs_of(step: taken, level: LogWarning)
    as "one warning for the whole hold"
  assert string.contains(does: warning.text, contain: "unit 9")
    && string.starts_with(warning.text, "2 held chunks")
    as "it names the unit and counts the chunks"
  assert chunks_held(session:, unit_id: 9) == 0
  // The owner's notice lands after the map's Gone, and its moves after the notice.
  let #(session, taken) = appeared(session:, unit_id: 9, sight_number: 5)
  assert written(taken:) == [] as "a 0x262 after the Gone shows no ghost"
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 3.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "a move of the sight the notice named is dropped, not held for a notice that never comes"
  // A move between the Gone and the owner's notice is held, and the notice drops it.
  let #(session, _) = reported_gone(session: moving_viewer())
  let #(session, taken) =
    moved(session:, move: move_of_unit_9(sight_number: 5, x: 5.0))
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 1
    as "a move after the Gone and before the notice is held"
  let #(session, taken) = appeared(session:, unit_id: 9, sight_number: 5)
  assert written(taken:) == [] && chunks_held(session:, unit_id: 9) == 0
    as "the owner's notice of that sight drops it"
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
    as "with one warning that counts it"
}

pub fn a_hold_that_overflows_again_after_a_notice_released_its_oldest_sight_is_warned_of_again_test() -> Nil {
  use <- owned_test.run(10_000)
  // 8 chunks of the sight 5 and 9 of the sight 6 before any notice: the 17th drops the
  // oldest and is warned of. The notice of the sight 5 releases its 7 chunks left and
  // keeps the 9 of the sight 6; 8 more chunks of the sight 6 overflow that hold.
  let moved_all = fn(session, sights) {
    list.fold(sights, #(session, []), fn(held, sight_number) {
      let #(session, warnings) = held
      let #(session, taken) =
        moved(session:, move: move_of_unit_9(sight_number:, x: 1.0))
      #(
        session,
        list.append(warnings, support.logs_of(step: taken, level: LogWarning)),
      )
    })
  }
  let #(session, warnings) =
    moved_all(
      moving_viewer(),
      list.flatten([list.repeat(5, 8), list.repeat(6, 9)]),
    )
  assert list.length(warnings) == 1 as "the first overflow is warned of"
  let #(session, _) = appeared(session:, unit_id: 9, sight_number: 5)
  assert chunks_held(session:, unit_id: 9) == 9
    as "the sight 6 chunks stay held"
  let #(_, warnings) = moved_all(session, list.repeat(6, 8))
  assert list.length(warnings) == 1
    as "a hold whose oldest sight changed is warned of again when it overflows"
}

pub fn a_viewer_holds_at_most_sixteen_chunks_of_a_unit_drops_the_oldest_with_one_warning_and_loses_every_hold_with_its_stay_test() -> Nil {
  use <- owned_test.run(10_000)
  // 18 chunks of the sight 6 for the unit 9, at x 1 to 18, and 3 of the sight 4 for the
  // unit 8, all before any notice: the 17th and the 18th each drop the oldest.
  let xs =
    list.map(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
      int.to_float,
    )
  let #(session, warnings) =
    list.fold(xs, #(moving_viewer(), []), fn(held, x) {
      let #(session, warnings) = held
      let #(session, taken) =
        moved(session:, move: move_of_unit_9(sight_number: 6, x:))
      #(
        session,
        list.append(warnings, support.logs_of(step: taken, level: LogWarning)),
      )
    })
  assert list.length(warnings) == 1
    as "the hold is warned of once, when its 17th chunk drops the first, and not again for the 18th"
  assert chunks_held(session:, unit_id: 9) == 16
    as "a hold is at most 16 chunks"
  let session =
    list.fold([1.0, 2.0, 3.0], session, fn(session, x) {
      moved(
        session:,
        move: move_stamp.Move(..move_of_unit_9(sight_number: 4, x:), unit_id: 8),
      ).0
    })
  let #(session, taken) = appeared(session:, unit_id: 9, sight_number: 6)
  assert written_xs(taken:)
    == list.map(
      [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
      fn(x) { float32.to_bits(int.to_float(x)) },
    )
    as "the notice releases the 16 chunks the hold kept, in order, without the two dropped oldest"
  assert chunks_held(session:, unit_id: 8) == 3
    as "the other unit's hold is untouched"
  // A new stay holds none: the chunk held in the first stay is not written when the
  // second stay's notice of the unit comes.
  let #(held, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_a_mover(move_of_unit_9(
        sight_number: 6,
        x: 1.0,
      )),
    )
  let #(state, _) =
    game_connection_support.read(
      held,
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
      game_connection_support.in_second_stay(
        game_connection_support.sent_by_a_peer(game_connection_support.news_of(
          unit_id: 9,
          news: Appeared(
            unit: game_connection_support.another_unit(),
            generation: sight(n: 6),
          ),
        )),
      ),
    )
  assert game_connection_support.written_ids(taken) == [0x0262]
    as "the second stay writes the unit's 0x262 and no move: the first stay's hold went with it"
}

pub fn a_players_copy_takes_the_generation_the_map_gave_each_viewer_and_an_unseen_of_an_earlier_generation_leaves_a_newer_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let moves = game_connection_support.a_move(1.5)
  let move_to_2 = fn(state) {
    game_connection_support.viewer_moves(
      taken: game_connection_support.read(state, moves).1,
    )
  }
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
        unit_id: game_connection_support.viewer_unit_id(2),
        generation: sight(n: 5),
      )),
    )
  let assert [#(2, move)] = move_to_2(state)
    as "the viewer of the copy is sent the move"
  assert move.generation == sight(n: 5)
    as "the copy holds the generation the map gave, and stamps the move with it"
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(2),
        generation: sight(n: 3),
      )),
    )
  assert game_connection_support.tells_to_players_but_moves(taken) == []
    as "an end of an earlier sight than the one the copy holds sends no removal"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "and is logged as an error: the map issues an end for the sight the copy holds, so an older one is its bug"
  let assert [#(2, still)] = move_to_2(state)
    as "and the newer entry stays in the copy"
  assert still.generation == sight(n: 5)
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(2),
        generation: sight(n: 5),
      )),
    )
  assert game_connection_support.tells_to_players_but_moves(taken) == []
    as "the end of the sight the copy holds sends the viewer nothing: the removal is the map's"
  assert move_to_2(state) == [] as "and deletes the entry: no more moves"
}

/// The go of the cast `cast_id`, as `held_cast_started` builds the ally's.
fn go_of(cast_id cast_id: Int) -> spell_go.SpellGo {
  let assert unit_news.HeldCastStarted(go:, ..) =
    held_cast_started(cast_id:, caster: 7)
  go
}

/// `viewers.written_cast_frames`: the viewer's own ledger alone decides which frames of a
/// cast it writes (`client_casts.is_written`). A cast the caster told the viewer the start of
/// gets its go, tick, 0x811 and finish; a unit shown with no cast held gets none (a viewer
/// that was never told the start would write a frame the client drops, or one that ends
/// nodes it never made); a cast borrowed from an ally's create gets none, since only the
/// ally ends it (`opcode.0x811`, `cast.unknown_caster`).
pub fn a_cast_the_viewer_holds_as_written_gets_its_casters_frames_a_cast_it_never_got_the_start_of_gets_none_and_a_borrowed_one_none_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let caster = 7
  let cast_id = 2_147_497_985
  let caster_appears = appears(unit_id: caster)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let ally_lists = lists(unit_id: ally, cast_id:, caster:)
  let go = go_of(cast_id:)
  let frames_of_the_cast = [
    from_unit(unit_id: caster, news: unit_news.CastWent(go:)),
    from_unit(
      unit_id: caster,
      news: unit_news.CastTicked(
        tick: spell_effect_tick.SpellEffectTick(
          cast_id:,
          spell4_effects_id: 96_125,
          unit_id: ally,
          descriptions: [],
        ),
      ),
    ),
    from_unit(
      unit_id: caster,
      news: unit_news.CastTargetsRemoved(
        removed: spell_targets_removed.SpellTargetsRemoved(cast_id:, unit_ids: [
          ally,
        ]),
        destroyed: False,
      ),
    ),
    the_casters_finish(unit_id: caster, cast_id:),
  ]
  let none = [[], [], [], []]
  check_written_rows(rows: [
    #(
      "a cast held as written: its go, tick, 0x811 and finish are written",
      [caster_appears, caster_starts],
      frames_of_the_cast,
      [
        [Went(go:)],
        [Other(0x07F8)],
        [TargetsRemoved(cast_id:, unit_ids: [ally])],
        [Finished(cast_id:)],
      ],
    ),
    #(
      "a unit shown with no cast held (the start never reached the viewer): none of the frames is written",
      [caster_appears],
      frames_of_the_cast,
      none,
    ),
    #(
      "a cast borrowed from an ally's create, the caster's start dropped: none of the caster's frames is written",
      [caster_appears, ally_lists, caster_starts],
      frames_of_the_cast,
      none,
    ),
  ])
}

/// The caster's own restriction news (`CasterRestrictionApplied`, `CasterRestrictionEnded`):
/// 0x87f is written only for a cast the viewer holds as written, which the viewer was told
/// the start of; 0x880 only for a state the viewer's picture holds as it wrote it, so a viewer
/// that came into sight after the 0x87f is written no 0x880 of an instance it never held
/// (`opcode.0x87f`, `opcode.0x880`).
pub fn a_casters_own_restriction_news_is_written_only_for_a_cast_held_as_written_and_its_end_only_for_an_instance_the_picture_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let caster = 7
  let cast_id = 2_147_497_985
  let instance_id = 28_673
  let caster_appears = appears(unit_id: caster)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let ally_lists = lists(unit_id: ally, cast_id:, caster:)
  let applied =
    from_unit(
      unit_id: caster,
      news: unit_news.CasterRestrictionApplied(
        cast_id:,
        state: crowd_control_state.Knockdown,
        instance_id:,
      ),
    )
  let ended =
    from_unit(
      unit_id: caster,
      news: unit_news.CasterRestrictionEnded(
        cast_id:,
        state: crowd_control_state.Knockdown,
        instance_id:,
      ),
    )
  check_written_rows(rows: [
    #(
      "a cast held as written: the 0x87f is written, then the 0x880 of the held instance",
      [caster_appears, caster_starts],
      [applied, ended],
      [[Other(0x087F)], [Other(0x0880)]],
    ),
    #(
      "a cast borrowed from an ally's create: no 0x87f, and so no 0x880",
      [caster_appears, ally_lists, caster_starts],
      [applied, ended],
      [[], []],
    ),
    #("a cast the viewer never held: no 0x87f", [caster_appears], [applied], [
      [],
    ]),
    #(
      "a viewer that came after the 0x87f, whose picture holds no instance: the 0x880 is written none",
      [caster_appears, caster_starts],
      [ended],
      [[]],
    ),
  ])
}

/// A creature's crowd-control news (`CrowdControlApplied`, `CrowdControlEnded`) is not
/// decided by the viewer's cast ledger, which holds none of the creature's: the 0x87f is
/// written for a unit shown with no cast held, and the 0x880 for a viewer that came after
/// the 0x87f and holds no instance (`opcode.0x87f`, `opcode.0x880`).
pub fn a_creature_controlled_by_a_cast_the_viewer_does_not_see_is_written_0x87f_and_a_viewer_that_came_after_the_applied_is_written_0x880_test() -> Nil {
  use <- owned_test.run(10_000)
  let creature = 21
  let shown =
    game_connection_support.sent_by_a_peer(
      game_connection_support.beast_news(
        unit_id: creature,
        yaw: 0.0,
        casts: [],
        as_spawn: fn(spawn) { spawn },
      ),
    )
  check_written_rows(rows: [
    #(
      "no cast is held: the 0x87f is written",
      [shown],
      [
        from_unit(
          unit_id: creature,
          news: unit_news.CrowdControlApplied(
            state: crowd_control_state.Knockdown,
            instance_id: 28_673,
          ),
        ),
      ],
      [[Other(0x087F)]],
    ),
    #(
      "no instance is held (the viewer came after the 0x87f): the 0x880 is written",
      [shown],
      [
        from_unit(
          unit_id: creature,
          news: unit_news.CrowdControlEnded(
            state: crowd_control_state.Knockdown,
            cast_id: 2_147_500_000,
            instance_id: 28_673,
          ),
        ),
      ],
      [[Other(0x0880)]],
    ),
  ])
}

/// `opcode.0x7ff`: a cast id the client holds is not started again. The start an ally tells
/// of a cast it holds (`HeldCastStarted`) is written only where the viewer holds the cast in
/// no state (a hold its caster's finish ended counts) and the caster is not the viewer's own
/// unit, whose cast rule finished the cast and whose ledger never holds it
/// (`viewers.casts_listed`).
pub fn a_held_cast_start_is_written_where_the_cast_is_held_in_no_state_and_its_caster_is_not_the_viewer_and_dropped_otherwise_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let caster = 7
  let cast_id = 2_147_497_985
  let own = game_connection_support.own_unit_id
  // Cast 1 of unit 5 and of unit 8 (`cast.cast_id`: 2^31 + unit x 2^11 + number).
  let own_cast_id = 2_147_493_889
  let cast_id_of_eight = 2_147_500_033
  let ally_appears = appears(unit_id: ally)
  let caster_appears = appears(unit_id: caster)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let ally_starts = fn(cast_id, caster) {
    the_allys_start(unit_id: ally, cast_id:, caster:)
  }
  let orphan_caster = orphan_caster_unit()
  let assert unit_news.HeldCastStarted(start:, go:) =
    held_cast_started(cast_id:, caster:)
  let written = [Started(start:), Went(go:)]
  let assert unit_news.HeldCastStarted(start: start_of_eight, go: go_of_eight) =
    held_cast_started(cast_id: cast_id_of_eight, caster: 8)
  check_written_rows(rows: [
    #(
      "held in no state: written",
      [ally_appears],
      [ally_starts(cast_id, caster)],
      [written],
    ),
    #(
      "held as written by its caster: dropped",
      [caster_appears, caster_starts, ally_appears],
      [ally_starts(cast_id, caster)],
      [[]],
    ),
    #(
      "borrowed from an ally's create: dropped",
      [lists(unit_id: ally, cast_id:, caster:)],
      [ally_starts(cast_id, caster)],
      [[]],
    ),
    #(
      "held with no caster: dropped",
      list.append(orphaned_by_its_caster_leaving(), [ally_appears]),
      [ally_starts(orphan_id, orphan_caster)],
      [[]],
    ),
    #(
      "held with no caster and listed again by its caster: dropped",
      list.append(orphaned_by_its_caster_leaving(), [
        ally_appears,
        lists(unit_id: orphan_caster, cast_id: orphan_id, caster: orphan_caster),
      ]),
      [ally_starts(orphan_id, orphan_caster)],
      [[]],
    ),
    #(
      "an ended hold, the caster's finish written: dropped",
      [
        caster_appears,
        caster_starts,
        the_casters_finish(unit_id: caster, cast_id:),
        ally_appears,
      ],
      [ally_starts(cast_id, caster)],
      [[]],
    ),
    #(
      "the start's caster is the viewer's own unit: dropped",
      [ally_appears],
      [ally_starts(own_cast_id, own)],
      [[]],
    ),
    #(
      "control: a caster that is not the viewer's own unit, held in no state, is written",
      [ally_appears],
      [ally_starts(cast_id_of_eight, 8)],
      [[Started(start: start_of_eight), Went(go: go_of_eight)]],
    ),
  ])
}

/// `cast.target_node_end`: a cast its caster finished at the viewer is held as ended, so
/// the ally's start of the same cast, coming after the finish, writes no new cast; an ally's
/// start that came first is dropped as the caster's start is held, and the caster's finish
/// is then written (`opcode.0x7fe`). A viewer that came into the caster's sight after the go
/// holds the cast as written from the caster's create, so it is written nothing of the
/// finished cast in either order.
pub fn a_cast_finished_at_the_viewer_before_the_allys_start_is_written_no_start_and_the_start_first_is_dropped_then_the_finish_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let caster = 7
  let cast_id = 2_147_497_985
  let caster_appears = appears(unit_id: caster)
  let ally_appears = appears(unit_id: ally)
  let caster_starts = the_casters_start(cast_id:, caster:)
  let caster_finishes = the_casters_finish(unit_id: caster, cast_id:)
  let ally_starts = the_allys_start(unit_id: ally, cast_id:, caster:)
  let ally_ends = the_allys_end(unit_id: ally, cast_id:)
  let setup = [caster_appears, caster_starts, ally_appears]
  let listed_setup = [ally_appears, lists(unit_id: caster, cast_id:, caster:)]
  check_written_rows(rows: [
    #(
      "the finish first: the 0x7fe is written, the ally's start is dropped, and the ally's end writes no 0x811",
      setup,
      [caster_finishes, ally_starts, ally_ends],
      [[Finished(cast_id:)], [], []],
    ),
    #(
      "the ally's start first: it is dropped, the caster's finish is then written, and the ally's end writes no 0x811",
      setup,
      [ally_starts, caster_finishes, ally_ends],
      [[], [Finished(cast_id:)], []],
    ),
    #(
      "a viewer that came after the go, the caster's create listing the cast, the finish first: the 0x7fe is written, the ally's start is dropped, and the ally's end writes no 0x811",
      listed_setup,
      [caster_finishes, ally_starts, ally_ends],
      [[Finished(cast_id:)], [], []],
    ),
    #(
      "a viewer that came after the go, the caster's create listing the cast, the ally's start first: it is dropped, the caster's finish is then written, and the ally's end writes no 0x811",
      listed_setup,
      [ally_starts, caster_finishes, ally_ends],
      [[], [Finished(cast_id:)], []],
    ),
  ])
}

/// The player that cast is the viewer of an ally whose start of that cast arrives after the
/// caster's death. The caster's own ledger never holds its own cast (`casts_listed` drops the
/// entry that names the viewer's own unit as caster), so the ally's start, whose caster is
/// the viewer's own unit, writes none of the 0x7ff, 0x7f4 or 0x811; a viewer whose ledger
/// holds nothing is written the start.
pub fn a_caster_that_died_between_its_go_and_the_allys_start_is_written_nothing_of_its_own_cast_on_the_ally_test() -> Nil {
  use <- owned_test.run(10_000)
  let ally = 9
  let own = game_connection_support.own_unit_id
  // Cast 1 of unit 5 (the viewer's own) and of unit 7 (`cast.cast_id`: 2^31 + unit x 2^11 + number).
  let own_cast_id = 2_147_493_889
  let cast_id = 2_147_497_985
  let ally_lists_the_viewers_own_cast =
    lists(unit_id: ally, cast_id: own_cast_id, caster: own)
  let ally_starts = fn(cast_id, caster) {
    the_allys_start(unit_id: ally, cast_id:, caster:)
  }
  let ally_ends = the_allys_end(unit_id: ally, cast_id: own_cast_id)
  let assert unit_news.HeldCastStarted(start:, go:) =
    held_cast_started(cast_id:, caster: 7)
  check_written_rows(rows: [
    #(
      "the ally's create dropped the viewer's own cast and its start names the viewer as caster: none is written, and the ally's end writes no 0x811",
      [ally_lists_the_viewers_own_cast],
      [ally_starts(own_cast_id, own), ally_ends],
      [[], []],
    ),
    #(
      "control: the same start of another player's cast, with the ledger holding nothing, is written",
      [ally_lists_the_viewers_own_cast],
      [ally_starts(cast_id, 7)],
      [[Started(start:), Went(go:)]],
    ),
  ])
}
