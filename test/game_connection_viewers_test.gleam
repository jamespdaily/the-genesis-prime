//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover other players'
//// units, what an owner sends and what a viewer writes, and the messages of an
//// earlier stay.

import connection_rule_support as support
import game_client
import game_connection_support.{type Step, Appears, MapSaysGone, Moves, Removes}
import genesis_prime/client_connection.{
  Appeared, ForStay, FromMap, FromStore, Moving, PeerNews, Removed, SentByMap,
  SentByPeer, TellMoved,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/message/float32
import genesis_prime/message/movement_command
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/relayed_movement
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/step.{
  ConnectionId, LogError, LogInfo, Map, OwnEffect, OwnEvent, Woken,
}
import genesis_prime/store.{Character, ForSelect, Listed}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map.{
  Left, ObjectsSeen, ObjectsUnseen, SeenBy, UnseenBy,
}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/static_object
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/result
import map_support
import owned_test
import place_support
import spawn_support

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
    == Ok(UnitDestroyed(unit_id: 9, field_2: 0))
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
    == Ok(UnitDestroyed(unit_id: 9, field_2: 0))
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
/// Engineer, whose resource is stat 3 and ResourceMax property 10.
fn appearance_at(place: Place, time_ms: Int) -> UnitCreatePlayer {
  let #(position, rotation) = player_unit.standing(place)
  let player =
    game_connection_support.player_in(game_connection_support.entered().1)
  UnitCreatePlayer(
    ..player,
    tail: UnitCreateTail(
      ..player.tail,
      stats: list.filter(player.tail.stats, fn(stat) { stat.stat_id != 3 }),
      properties: list.filter(player.tail.properties, fn(property) {
        property.property_id != 10
      }),
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      server_time_estimate_start: time_ms,
    ),
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
      )),
    )
  assert game_connection_support.peer_tells(taken)
    == [
      #(
        2,
        game_connection_support.told(
          news: Appeared(unit: appearance_at(
            game_connection_support.entry_place(),
            1000,
          )),
        ),
      ),
    ]
    as "the viewer is sent the unit at once, from the origin the map's Joined carried: the map sends the client no unit"
  assert support.writes(taken) == []
}

pub fn a_viewers_copy_of_a_player_carries_no_class_resource_stat_or_maximum_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player's own 0x262 holds the Engineer's Volatility as stat 3 and
  // ResourceMax_1 as property 10 (opcode.0x262.resource_stats,
  // UnitProperty2.ResourceMax_0); a 0x935 goes to the player only, so a viewer's
  // copy would go stale (the step's design).
  let own =
    game_connection_support.player_in(game_connection_support.entered().1)
  assert list.any(own.tail.stats, fn(stat) { stat.stat_id == 3 })
    && list.any(own.tail.properties, fn(property) { property.property_id == 10 })
    as "the player's own record carries the resource"
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
      )),
    )
  let assert [#(2, PeerNews(news: Appeared(unit:), ..))] =
    game_connection_support.peer_tells(taken)
  assert list.map(unit.tail.stats, fn(stat) { stat.stat_id }) == [0, 10, 20]
    as "health, level and shield only: no stat 3"
  assert !list.any(unit.tail.properties, fn(property) {
    property.property_id == 10
  })
    as "no ResourceMax_1"
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
  let assert map.Joined(unit:, loadout:, max_health:, incarnation:, ..) =
    game_connection_support.map_answer(taken)
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(map.Joined(
          unit:,
          loadout:,
          max_health:,
          incarnation:,
          clock_origin_ms: 600,
        )),
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
  let unrelayed = movement_command.Kind26(MovementKind26(field_2: 0))
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
  assert support.says(line, words: "kind 26")
  let assert [#(2, PeerNews(news: Moving(commands:, ..), ..))] =
    game_connection_support.peer_tells(first)
  assert list.length(commands) == 1 as "the kind 26 is not relayed"
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
/// unit 9, a creature's threat, its strike on the player's unit `unit_id`, and its
/// release.
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
fn object_unit(unit_id: Int) -> UnitCreateStatic {
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
    == Ok(UnitDestroyed(unit_id: 20, field_2: 0))
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
    == Ok(UnitDestroyed(unit_id: 20, field_2: 0))
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
