//// Two players on one map: the burst a player entering is written before the 0x0262 of a
//// player in sight, how each sees the other appear, move and leave, and the worn visuals one
//// sees of the other.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import connection_rule_support as support
import driven_time
import game_client
import game_wire_support.{
  TwoEntered, burst_length, connected_as, create_request, created_result,
  in_select, listed_entries, send_play, start, two_players_enter_one_map,
  unit_of, worn_in,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/float32
import genesis_prime/message/item_move
import genesis_prime/message/item_place
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/store.{AccountId}
import gleam/dict
import gleam/list
import gleam/result
import login_support
import novice_tables
import owned_test

pub fn a_player_entering_is_written_its_whole_burst_before_the_0x262_of_a_player_in_sight_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_burst:, second_burst:, ..) as entered =
    two_players_enter_one_map(time:)
  assert list.map(first_burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
    as "the first player enters an empty map: its burst only"
  assert list.map(list.take(second_burst, burst_length()), fn(frame) {
      frame.message_id
    })
    == game_client.world_entry_ids
    as "the second player's whole entry burst comes before the 0x262 of the first: a 0x262 of another unit that landed while the client waits on 0x636 could take control (0x1403d9760)"
  let assert [_, own, ..] = second_burst
  assert unit_of(own) == 2 as "the second player's own unit is the map's second"
  let assert [seen_first] = list.drop(second_burst, burst_length())
  assert unit_of(seen_first) == 1
    as "the first player's unit is created for the second player"
  assert unit_of(entered.seen_second) == 2
    as "the second player's unit is created for the first player"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_player_in_sight_is_sent_the_worn_visuals_the_player_wears_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    first_burst:,
    second_burst:,
    seen_second:,
    ..,
  ) = two_players_enter_one_map(time:)
  let worn = novice_tables.worn_visuals(class_id: 4, faction_id: 166)
  let decoded = fn(frame: Frame) {
    let assert Ok(player) = unit_create_player.decode(frame.body)
      as "0x262 decodes"
    player
  }
  assert worn_in(player: game_client.unit_create_player_in(frames: first_burst))
    == worn
    as "opcode.0x262.worn_visuals: the Exile Medic is drawn in its own set: chest 4106, legs 4107, shoulder 4158, feet 4105, hands 4104 and weapon 3280 (Item2.novice_visuals)"
  let assert [seen_first] = list.drop(second_burst, burst_length())
  assert worn_in(player: decoded(seen_first)) == worn
    as "opcode.0x262.other_player: the second player's client is sent the first's 0x262 with the same worn visuals"
  assert worn_in(player: decoded(seen_second)) == worn
    as "opcode.0x262.other_player: the first player's client is sent the second's 0x262 with its worn visuals"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The position a 0x638 of the unit `unit_id` ends at, which is the position of
/// its last kind 2 command.
fn moved_to(frame: Frame, unit_id: Int) -> #(Float, Float, Float) {
  assert frame.message_id == 0x0638 as "the frame is a 0x638"
  let assert Ok(relayed) = unit_movement.decode(frame.body) as "0x638 decodes"
  assert relayed.unit_id == unit_id
    && relayed.reset_movement == 0
    && relayed.kept == 0
  game_client.observe(
    others: dict.from_list([#(unit_id, #(0.0, 0.0, 0.0))]),
    frame:,
  )
  |> dict.get(unit_id)
  |> result.unwrap(#(0.0, 0.0, 0.0))
}

// Every frame the first client reads about the second player's unit comes from
// the second player's own connection, one sender, so its order is the BEAM's
// promise; the second's connection sends a move only to a player it has been
// told sees it, which the first's 0x262 of it shows it has. The only frame
// from another sender is the map's `Gone` when the second's connection ends, and
// the first's connection writes a move that lands after it as nothing.
pub fn two_players_on_one_map_see_each_other_appear_move_and_leave_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    second_character:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter_one_map(time:)
  assert unit_of(seen_second) == 2
    as "the second player's unit is created for the first, by the second's own connection"
  // The second player moves five times at once; only the first sees it, each
  // move as the second's own connection sent it, in the order sent.
  list.each([0.0, 1.0, 2.0, 3.0, 4.0], fn(step) {
    game_client.send_world(
      game: second,
      message_id: 0x0637,
      body: game_client.moves_body(client_clock: 0x1234, commands: [
        game_client.position_command(x: 100.5 +. step, y: 50.25, z: -200.75),
      ]),
    )
  })
  let #(moves, first_have) =
    game_client.read_kept(game: first, have: first_have, count: 5)
  assert list.map(moves, fn(frame) { moved_to(frame, 2) })
    == [
      #(100.5, 50.25, -200.75),
      #(101.5, 50.25, -200.75),
      #(102.5, 50.25, -200.75),
      #(103.5, 50.25, -200.75),
      #(104.5, 50.25, -200.75),
    ]
    as "opcode.0x638: each move is sent to the viewer, in the order sent"
  // The second player camps out: the first sees its unit go, after its moves.
  game_client.send_world(game: second, message_id: 0x00BF, body: <<1>>)
  let #(_countdown, second_have) =
    game_client.read_message(
      game: second,
      have: second_have,
      message_id: 0x0092,
    )
  game_client.send_world(game: second, message_id: 0x00C0, body: <<>>)
  let #(left, second_have) = game_client.next(game: second, have: second_have)
  assert left.message_id == 0x0594
    as "the camp returns the client to character select"
  let #(gone, first_have) = game_client.next(game: first, have: first_have)
  assert gone.message_id == 0x0355 as "opcode.0x355: the unit is removed"
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == 2
  // It plays again as a new unit, which the first sees appear.
  game_client.send(game: second, message_id: 0x07E0, body: <<>>)
  let #(_list, second_have) =
    game_client.read_message(
      game: second,
      have: second_have,
      message_id: 0x0117,
    )
  send_play(game: second, character_id: second_character)
  let #(_again, _second_have) =
    game_client.read_entry_kept(game: second, have: second_have)
  let #(back, first_have) = game_client.next(game: first, have: first_have)
  assert unit_of(back) == 3 as "a new unit, never an id given before"
  // The first's 0x262 of it shows the second's connection knows the first sees
  // it, so this move is sent to the first.
  game_client.send_world(
    game: second,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1235, commands: [
      game_client.position_command(x: 7.5, y: 8.5, z: 9.5),
    ]),
  )
  let #(moved_again, first_have) =
    game_client.next(game: first, have: first_have)
  assert moved_to(moved_again, 3) == #(7.5, 8.5, 9.5)
    as "the rejoined player's moves are sent to the run it joined"
  // The second player's client drops: its connection ends, sends nothing, and
  // the map tells the first's connection the unit is gone.
  game_client.close(game: second)
  let #(dropped, _first_have) = game_client.next(game: first, have: first_have)
  assert dropped.message_id == 0x0355
  let assert Ok(destroyed) = unit_destroyed.decode(dropped.body)
  assert destroyed.unit_id == 3
    as "the connection that drops is removed for the first player by the map's Gone"
  game_client.close(game: first)
  login_support.stop(started)
}

/// A created Warrior of CharacterCreation row 466 for the account, played into
/// the map: its client, in the world, with the bytes read beyond its entry.
fn created_warrior_enters(
  game game: game_client.Game,
  name name: String,
) -> #(game_client.Game, BitArray) {
  game_client.send_create(game:, body: create_request(name))
  let created = created_result(game)
  let _list = listed_entries(game)
  send_play(game:, character_id: created.character_id)
  let #(_burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  #(game, have)
}

pub fn a_second_player_sees_the_first_take_off_its_chest_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let #(started, port, account) = start(time:)
  let first = in_select(started:, port:, account:)
  let second_guid = support.guid_of(0x22)
  let second_account =
    AccountId(login_support.insert_other(
      started:,
      login_name: "player2",
      game_account_id: second_guid,
    ))
  let second =
    connected_as(
      started:,
      port:,
      account: second_account,
      login_name: "player2",
      game_account_id: second_guid,
      key: support.guid_of(2),
    )
  let #(first, first_have) = created_warrior_enters(game: first, name: "Zed Qu")
  let #(second, second_have) =
    created_warrior_enters(game: second, name: "Ann Qu")
  // The second's entry is followed by the 0x262 of the first, which names its unit.
  let #(seen_first, second_have) =
    game_client.next(game: second, have: second_have)
  let first_unit = unit_of(seen_first)
  let #(_seen_second, _first_have) =
    game_client.next(game: first, have: first_have)
  // The first takes its chest, held at worn slot 0, into its first bag slot.
  let assert Ok(move) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: 0, bag_index: 0),
      to: item_place.ItemPlace(location: 1, bag_index: 0),
    ))
    as "0x182 encodes"
  game_client.send_world(game: first, message_id: 0x0182, body: move)
  let is_properties = fn(frame: Frame) { frame.message_id == 0x093A }
  let #(seen, _second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, is_properties)
    })
  let assert [look] =
    list.filter(seen, fn(frame) { frame.message_id == 0x0933 })
    as "the second client is written one 0x933 when the first's chest comes off"
  assert unit_item_visuals_changed.decode(look.body)
    == Ok(
      UnitItemVisualsChanged(unit_id: first_unit, item_visuals: [
        ItemVisual(slot: 1, display_id: 0, item_color_set_id: 0, dye: 0),
      ]),
    )
    as "opcode.0x933.empty_display: the first's chest slot 1 is emptied on the second's screen"
  let assert [properties] = list.filter(seen, is_properties) as "and one 0x93a"
  let assert Ok(changed) = unit_properties_changed.decode(properties.body)
  assert changed.unit_id == first_unit
  assert list.filter(changed.properties, fn(entry) {
      entry.property_id == 7 || entry.property_id == 42
    })
    == [
      UnitProperty(
        property_id: 7,
        base: float32.to_bits(586.0),
        value: float32.to_bits(586.0),
      ),
      UnitProperty(
        property_id: 42,
        base: float32.to_bits(187.5),
        value: float32.to_bits(187.5),
      ),
    ]
    as "player.level1_gear_properties: without the chest's quarter of the 600 Base Health and its 62.5 Armor, 736 falls to 586 and 250 to 187.5"
  assert list.map(seen, fn(frame) { frame.message_id })
    |> list.filter(fn(id) { id == 0x0933 || id == 0x093A })
    == [0x0933, 0x093A]
    as "the look comes before the properties"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}
