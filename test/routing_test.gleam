//// The routing table (`genesis_prime/game/routing`). Expected values come
//// from these places.
//// - The ids of the client's messages: the movement messages 0x0637, 0x063A,
////   0x00D5, 0x063B, 0x00F2, 0x00FB and 0x00FC and the camp messages 0x00BF
////   and 0x00C0 are the ones the client sends inside 0x038C with the player in
////   the world (opcode.0x38c; the movement and camp modules' doc comments), and
////   0x058F, 0x07E0, 0x07DD, 0x025C, 0x0352, 0x0786 and 0x038C the ones it
////   sends in its wrapper (the game connection's module doc).
//// - The reports and window requests (`genesis_prime/game/dropped`): the twelve
////   the client sends through SendWorldMessage, so inside 0x038C with the player
////   in the world (`world_sender` of the coverage measure, fact 0x1403f4900), and
////   0x0241, which it sends on its own from character select
////   (`opcode.0x241`), and which is read in the world too.
//// - The rule that a message with no row is unhandled: the building-an-engine
////   skill ("Nothing is dropped silently") and the game connection's tests of
////   the log (`an_unhandled_message_id_is_a_warning_the_first_time_on_a_connection_and_a_debug_line_after_test`).

import code_rule/source.{SourceFile}
import code_rule/syntax
import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/character_select
import genesis_prime/game/dropped
import genesis_prime/game/innate_choice
import genesis_prime/game/interaction
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
  #(0x0635, movement.ControlEchoed),
]

const camp_rows = [#(0x00BF, camp.CampAsked), #(0x00C0, camp.CampOver)]

const cast_rows = [
  #(0x009A, cast.Pressed),
  #(0x04DB, cast.KeyHeld),
  #(0x0801, cast.Cancelled),
  #(0x0805, cast.Answered),
]

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
  // 0x082D and 0x07CC are messages the game connection's tests log as unhandled.
  list.each([0x07CC, 0x082D], fn(id) {
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
  use path <- list.each([
    "src/genesis_prime/game/connection.gleam",
    "src/genesis_prime/game/connection/casting.gleam",
    "src/genesis_prime/game/connection/chat.gleam",
    "src/genesis_prime/game/connection/dropped.gleam",
    "src/genesis_prime/game/connection/effects.gleam",
    "src/genesis_prime/game/connection/frames.gleam",
    "src/genesis_prime/game/connection/interaction.gleam",
    "src/genesis_prime/game/connection/life.gleam",
    "src/genesis_prime/game/connection/login.gleam",
    "src/genesis_prime/game/connection/movement.gleam",
    "src/genesis_prime/game/connection/select.gleam",
    "src/genesis_prime/game/connection/state.gleam",
    "src/genesis_prime/game/connection/viewers.gleam",
    "src/genesis_prime/game/connection/world.gleam",
  ])
  let imported =
    syntax.imported_modules(SourceFile(path:, text: source.read(path)))
  list.each(
    [
      "player_movement", "world_zone_changed", "movement_send_interval_answer",
      "move_speed_setting", "terrain_loaded", "fall_value", "fell_below_floor",
      "camp_request", "camp_finished", "camp_countdown",
      "character_select_start", "create_character_carrier", "delete_character",
      "rename_character", "play_character", "interaction_request",
      "dialog_responses_shown", "cast_activate", "cast_objective_ability",
      "client_activate_unit", "item_use",
    ],
    fn(name) {
      assert !list.contains(imported, "genesis_prime/message/" <> name)
        as {
          "the connection ("
          <> path
          <> ") decodes "
          <> name
          <> ", which is its feature's dispatch (genesis_prime/game/routing)"
        }
    },
  )
}

pub fn the_press_the_hold_and_the_cancel_of_a_cast_are_rows_taken_inside_0x038c_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(cast_rows, fn(row) {
    let #(id, message) = row
    assert routing.route(AtWorld, InsideWorldMessage, id)
      == Ok(routing.Cast(message:))
      as {
        "0x"
        <> int.to_base16(id)
        <> " is a cast row in the world (opcode.0x9a, opcode.0x4db, opcode.0x801)"
      }
    assert routing.route(AtCharacterSelect, InsideWorldMessage, id)
      == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken in character select" }
    assert routing.route(AtWorld, OnItsOwn, id) == Error(Nil)
      as { "0x" <> int.to_base16(id) <> " is not taken outside 0x038C" }
  })
}

pub fn item_use_is_taken_in_the_world_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert routing.route(AtWorld, InsideWorldMessage, 0x0943)
    == Ok(routing.ItemUse)
    as "0x0943 is the item-use row in the world (opcode.0x943: the client sends it from inside 0x038C, from StartItemUseCast 0x140398cc0)"
  assert routing.route(AtCharacterSelect, InsideWorldMessage, 0x0943)
    == Error(Nil)
    as "it is not taken in character select"
  assert routing.route(BeforeHelloReply, InsideWorldMessage, 0x0943)
    == Error(Nil)
    as "it is not taken before the hello reply"
  assert routing.route(AtWorld, OnItsOwn, 0x0943) == Error(Nil)
    as "it is not taken outside 0x038C"
}

pub fn the_press_of_an_objective_button_is_a_row_taken_inside_0x038c_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  assert routing.route(AtWorld, InsideWorldMessage, 0x009D)
    == Ok(routing.Shortcut)
    as "0x009D is the shortcut row in the world (opcode.0x9d: the client sends it from inside 0x038C like every message of the world)"
  assert routing.route(AtCharacterSelect, InsideWorldMessage, 0x009D)
    == Error(Nil)
    as "it is not taken in character select"
  assert routing.route(AtWorld, OnItsOwn, 0x009D) == Error(Nil)
    as "it is not taken outside 0x038C"
}

pub fn the_innate_choice_is_a_row_taken_inside_0x038c_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(5000)
  assert routing.route(AtWorld, InsideWorldMessage, 0x016F)
    == Ok(routing.Innate(message: innate_choice.IndexChosen))
    as "0x016F is the innate row in the world (opcode.0x16f: the client sends it from inside 0x038C like every message of the world)"
  assert routing.route(AtCharacterSelect, InsideWorldMessage, 0x016F)
    == Error(Nil)
    as "it is not taken in character select"
  assert routing.route(AtWorld, OnItsOwn, 0x016F) == Error(Nil)
    as "it is not taken outside 0x038C"
}

const interaction_rows = [
  #(0x07EA, interaction.Requested),
  #(0x0356, interaction.ResponsesShown),
]

pub fn interaction_messages_route_to_interaction_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(interaction_rows, fn(row) {
    let #(id, message) = row
    let label = "0x" <> int.to_base16(id)
    assert routing.route(AtWorld, InsideWorldMessage, id)
      == Ok(routing.Interaction(message:))
      as {
        label
        <> " is an interaction row inside 0x038C in the world (opcode.0x7ea, opcode.0x356: the client sends both through SendWorldMessage)"
      }
    assert routing.route(AtCharacterSelect, InsideWorldMessage, id)
      == Error(Nil)
      as { label <> " is not taken in character select" }
    assert routing.route(BeforeHelloReply, InsideWorldMessage, id) == Error(Nil)
      as { label <> " is not taken before the hello reply" }
    list.each(stages, fn(stage) {
      assert routing.route(stage, OnItsOwn, id) == Error(Nil)
        as { label <> " is not taken outside 0x038C" }
    })
  })
}

const dropped_world_rows = [
  #(0x023C, dropped.WatchdogReport),
  #(0x0240, dropped.FrameTimeReport),
  #(0x023F, dropped.NetworkReport),
  #(0x023E, dropped.GraphicsReport),
  #(0x023D, dropped.WindowOpened),
  #(0x012B, dropped.ClientOption),
  #(0x0180, dropped.ScanbotRequest),
  #(0x03ED, dropped.OwnAuctionsRequest),
  #(0x03EC, dropped.OwnCommodityOrdersRequest),
  #(0x0269, dropped.CreddExchangeRequest),
  #(0x018F, dropped.TradeCancel),
  #(0x0570, dropped.InputKeySetRequest),
]

pub fn each_report_and_window_request_is_taken_at_its_stages_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(dropped_world_rows, fn(row) {
    let #(id, message) = row
    let label = "0x" <> int.to_base16(id)
    assert routing.route(AtWorld, InsideWorldMessage, id)
      == Ok(routing.Dropped(message:))
      as { label <> " is a dropped row inside 0x038C in the world" }
    assert routing.route(AtCharacterSelect, InsideWorldMessage, id)
      == Error(Nil)
      as { label <> " is not taken in character select" }
    assert routing.route(BeforeHelloReply, InsideWorldMessage, id) == Error(Nil)
      as { label <> " is not taken before the hello reply" }
    list.each(stages, fn(stage) {
      assert routing.route(stage, OnItsOwn, id) == Error(Nil)
        as { label <> " is not taken outside 0x038C" }
    })
  })
  assert routing.route(AtCharacterSelect, OnItsOwn, 0x0241)
    == Ok(routing.Dropped(message: dropped.PreGameActivity))
    as "0x0241 is taken on its own in character select (opcode.0x241)"
  assert routing.route(AtWorld, OnItsOwn, 0x0241)
    == Ok(routing.Dropped(message: dropped.PreGameActivity))
    as "and in the world, where a 0x0241 read during the store's ask is taken once it is answered"
  assert routing.route(BeforeHelloReply, OnItsOwn, 0x0241) == Error(Nil)
    as "not before the hello reply"
  list.each(stages, fn(stage) {
    assert routing.route(stage, InsideWorldMessage, 0x0241) == Error(Nil)
      as "0x0241 inside 0x038C is not what the client sends"
  })
}
