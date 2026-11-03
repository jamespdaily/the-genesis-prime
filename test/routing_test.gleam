//// The routing table (`genesis_prime/game/routing`). Expected values come
//// from these places.
//// - The ids of the client's messages: the movement messages 0x0637, 0x063A,
////   0x00D5, 0x063B, 0x00F2, 0x00FB and 0x00FC and the camp messages 0x00BF
////   and 0x00C0 are the ones the client sends inside 0x038C with the player in
////   the world (opcode.0x38c; the movement and camp modules' doc comments), and
////   0x058F, 0x07E0, 0x07DD, 0x025C, 0x0352, 0x0786 and 0x038C the ones it
////   sends in its wrapper (the game connection's module doc).
//// - The rule that a message with no row is unhandled: the building-an-engine
////   skill ("Nothing is dropped silently") and the game connection's tests of
////   the log (`an_unhandled_message_id_is_a_warning_the_first_time_on_a_connection_and_a_debug_line_after_test`).

import code_rule/source.{SourceFile}
import code_rule/syntax
import genesis_prime/game/camp
import genesis_prime/game/character_select
import genesis_prime/game/movement
import genesis_prime/game/routing.{
  AtCharacterSelect, AtWorld, BeforeHelloReply, InsideWorldMessage, OnItsOwn,
}
import gleam/int
import gleam/list
import owned_test

const stages = [BeforeHelloReply, AtCharacterSelect, AtWorld]

const movement_rows = [
  #(0x0637, movement.PlayerMoved),
  #(0x063A, movement.ZoneChanged),
  #(0x00D5, movement.IntervalAnswered),
  #(0x063B, movement.SpeedChosen),
  #(0x00F2, movement.TerrainReady),
  #(0x00FB, movement.Fell),
  #(0x00FC, movement.FellBelowFloor),
]

const camp_rows = [#(0x00BF, camp.CampAsked), #(0x00C0, camp.CampOver)]

pub fn movement_messages_are_rows_taken_inside_0x038c_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(movement_rows, fn(row) {
    let #(id, message) = row
    assert routing.route(AtWorld, InsideWorldMessage, id)
      == Ok(routing.Movement(message:))
      as { "0x" <> int.to_base16(id) <> " is a movement row in the world" }
    assert routing.route(AtCharacterSelect, InsideWorldMessage, id)
      == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken in character select" }
    assert routing.route(AtWorld, OnItsOwn, id) == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken outside 0x038C" }
  })
}

pub fn camp_messages_are_rows_taken_inside_0x038c_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(camp_rows, fn(row) {
    let #(id, message) = row
    assert routing.route(AtWorld, InsideWorldMessage, id)
      == Ok(routing.Camp(message:))
      as { "0x" <> int.to_base16(id) <> " is a camp row in the world" }
    assert routing.route(AtCharacterSelect, InsideWorldMessage, id)
      == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken in character select" }
    assert routing.route(AtWorld, OnItsOwn, id) == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken outside 0x038C" }
  })
}

pub fn the_messages_in_the_clients_wrapper_are_rows_with_the_stages_that_take_them_test() -> Nil {
  use <- owned_test.run(5000)
  assert routing.route(BeforeHelloReply, OnItsOwn, 0x058F) == Ok(routing.Hello)
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x07E0)
    == Ok(routing.CharacterSelect(character_select.Started))
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x025C)
    == Ok(routing.CharacterSelect(character_select.CreateAsked))
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x0352)
    == Ok(routing.CharacterSelect(character_select.DeleteAsked))
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x0786)
    == Ok(routing.CharacterSelect(character_select.RenameAsked))
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x07DD)
    == Ok(routing.WorldEntry)
  assert routing.route(AtWorld, OnItsOwn, 0x07DD) == Error(Nil)
    as "a play is taken only in character select"
  assert routing.route(BeforeHelloReply, OnItsOwn, 0x07E0) == Error(Nil)
    as "before the hello reply only 0x058F is taken"
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x038C)
    == Ok(routing.WorldMessage)
  assert routing.route(AtWorld, OnItsOwn, 0x038C) == Ok(routing.WorldMessage)
}

pub fn a_message_with_no_row_is_taken_at_no_stage_either_way_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x0635 is the client's echo of 0x0636, and 0x0241 and 0x082D are messages
  // the game connection's tests log as unhandled.
  list.each([0x0635, 0x0241, 0x082D], fn(id) {
    list.each(stages, fn(stage) {
      assert routing.route(stage, OnItsOwn, id) == Error(Nil)
      assert routing.route(stage, InsideWorldMessage, id) == Error(Nil)
    })
  })
}

pub fn every_message_id_is_in_one_row_test() -> Nil {
  use <- owned_test.run(5000)
  let ids =
    list.append(
      routing.message_ids(OnItsOwn),
      routing.message_ids(InsideWorldMessage),
    )
  assert list.length(ids) == list.length(list.unique(ids))
    as "a message id is one row, so one feature takes it"
}

pub fn the_connection_imports_no_message_only_a_feature_decodes_test() -> Nil {
  use <- owned_test.run(5000)
  let path = "src/genesis_prime/game/connection.gleam"
  let imported =
    syntax.imported_modules(SourceFile(path:, text: source.read(path)))
  list.each(
    [
      "player_movement", "zone_value_changed", "movement_send_interval_answer",
      "move_speed_setting", "terrain_loaded", "fall_value", "fell_below_floor",
      "camp_request", "camp_finished", "camp_countdown",
      "character_select_start", "create_character_carrier", "delete_character",
      "rename_character", "play_character",
    ],
    fn(name) {
      assert !list.contains(imported, "genesis_prime/message/" <> name)
        as {
          "the connection decodes "
          <> name
          <> ", which is its feature's dispatch (genesis_prime/game/routing)"
        }
    },
  )
}
