//// The one table from a client message id to the feature of the game
//// connection's rule (genesis_prime/game/connection) that takes it, and the
//// stage of the connection it is taken in. A new message of the player in the
//// world is one row here and the feature's own code and tests.
////
//// ```
//// whole frame in the client's wrapper 0x0244 ─▶ route(stage, OnItsOwn, id)
////                                                 ─▶ Hello, CharacterSelect(message), WorldEntry or WorldMessage
//// the frame inside 0x038C                    ─▶ route(stage, InsideWorldMessage, id)
////                                                 ─▶ Movement(message), Camp(message), Chat(message), Cast(message),
////                                                    Activation, Life(message), Innate(message), Interaction(message), Quest(message),
////                                                    Inventory(message), VendorPurchase, VendorSale, VendorSellJunk or Dropped(message)
//// a message with no row, or one not taken at the stage ─▶ Error(Nil): the rule logs it as unhandled
//// ```
////
//// - **A row names the feature's own kind of message**, so each feature's
////   dispatch is a case in the feature, over its own type
////   (genesis_prime/game/character_select, genesis_prime/game/movement,
////   genesis_prime/game/camp), and the connection holds none.
//// - **The stages** are where the connection is when a message is taken: before
////   the hello reply, in character select, or with the player in the world. In
////   any other state, with an ask out or a claim waiting, no frame is taken.
//// - **0x058F** is taken once, before the hello reply; a second one ends the
////   connection, which is the rule's shared part, not a feature's.
//// - **0x038C** carries one whole frame, which is every message the client sends
////   in the world (opcode.0x38c); the player's movement and camp messages are
////   taken from inside it with the player in the world, and any other is
////   unhandled.
//// - **The dropped messages** (genesis_prime/game/dropped) are taken and
////   answered with nothing: the reports and requests inside 0x038C with the
////   player in the world, and 0x241 on its own in character select and in the
////   world.

import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/character_select
import genesis_prime/game/chat
import genesis_prime/game/dropped
import genesis_prime/game/innate_choice
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/quest
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_sale
import genesis_prime/message/ability_hold
import genesis_prime/message/camp_finished
import genesis_prime/message/camp_request
import genesis_prime/message/cancel_cast
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_activate
import genesis_prime/message/character_select_start
import genesis_prime/message/choose_resurrection
import genesis_prime/message/client_option
import genesis_prime/message/create_character_carrier
import genesis_prime/message/credd_exchange_request
import genesis_prime/message/delete_character
import genesis_prime/message/dialog_responses_shown
import genesis_prime/message/fall_value
import genesis_prime/message/fell_below_floor
import genesis_prime/message/frame_time_report
import genesis_prime/message/game_hello_reply
import genesis_prime/message/graphics_report
import genesis_prime/message/innate_index_chosen
import genesis_prime/message/input_key_set_request
import genesis_prime/message/interaction_request
import genesis_prime/message/item_delete
import genesis_prime/message/item_move
import genesis_prime/message/item_split
import genesis_prime/message/move_speed_setting
import genesis_prime/message/movement_send_interval_answer
import genesis_prime/message/network_report
import genesis_prime/message/own_auctions_request
import genesis_prime/message/own_commodity_orders_request
import genesis_prime/message/play_character
import genesis_prime/message/player_movement
import genesis_prime/message/pre_game_activity
import genesis_prime/message/quest_accept
import genesis_prime/message/quest_retry
import genesis_prime/message/rename_character
import genesis_prime/message/scanbot_request
import genesis_prime/message/send_chat_line
import genesis_prime/message/send_whisper
import genesis_prime/message/terrain_loaded
import genesis_prime/message/trade_cancel
import genesis_prime/message/watchdog_report
import genesis_prime/message/window_opened
import genesis_prime/message/world_message
import genesis_prime/message/world_zone_changed
import gleam/list
import gleam/result

/// The feature that takes a message, with the feature's own kind of it.
pub type Feature {
  /// The client's reply to the hello, 0x058F: the connection's own, shared
  /// part (the re-key and the hand-off).
  Hello
  CharacterSelect(message: character_select.Message)
  /// The client's request to play a character, 0x07DD
  /// (genesis_prime/game/world_entry).
  WorldEntry
  /// 0x038C, which carries every message the client sends in the world.
  WorldMessage
  Movement(message: movement.Message)
  Camp(message: camp.Message)
  /// A chat line or a whisper (genesis_prime/game/chat).
  Chat(message: chat.Message)
  /// The press or hold of an ability or the cancel of a cast
  /// (genesis_prime/game/cast).
  Cast(message: cast.Message)
  /// The right-click of a unit, the client's cast of its activate spell
  /// (genesis_prime/game/cast `activate`).
  Activation
  /// The player's choice of how to come back from death
  /// (genesis_prime/game/player_life).
  Life(message: player_life.Message)
  /// The player's choice of an innate (genesis_prime/game/innate_choice).
  Innate(message: innate_choice.Message)
  /// The player's request to talk to a unit, and the client's note that a dialog
  /// it opened has responses (genesis_prime/game/interaction).
  Interaction(message: interaction.Message)
  /// The player's accept of a quest and retry of a botched one
  /// (genesis_prime/game/quest).
  Quest(message: quest.Message)
  /// The player's move, split or delete of a held item (genesis_prime/game/inventory).
  Inventory(message: inventory.Message)
  /// The player's buy from the open vendor, 0x00BE (genesis_prime/game/vendor_purchase).
  VendorPurchase
  /// The player's sale of one stack or part of one to the open vendor, 0x0166
  /// (genesis_prime/game/vendor_sale).
  VendorSale
  /// The player's sale of all junk to the open vendor, 0x0167
  /// (genesis_prime/game/vendor_sale).
  VendorSellJunk
  /// A report or request taken and dropped (genesis_prime/game/dropped).
  Dropped(message: dropped.Message)
}

/// Where the connection is when it takes a message.
pub type Stage {
  /// The hello is sent and the reply 0x058F awaited.
  BeforeHelloReply
  /// The client is in character select.
  AtCharacterSelect
  /// The player is in the world.
  AtWorld
}

/// Where a message arrives: on its own, in the client's wrapper, or inside
/// 0x038C.
pub type Arrival {
  OnItsOwn
  InsideWorldMessage
}

/// One row: a message id, how it arrives, the feature that takes it and the
/// stages it is taken in.
type Row {
  Row(
    message_id: Int,
    arrival: Arrival,
    feature: Feature,
    taken_in: List(Stage),
  )
}

/// The table. A stage not listed for a row logs the message as unhandled, but
/// for 0x058F and a message before the hello reply (the rule ends the
/// connection for both).
const table = [
  Row(
    game_hello_reply.message_id,
    OnItsOwn,
    Hello,
    [BeforeHelloReply, AtCharacterSelect, AtWorld],
  ),
  Row(
    character_select_start.message_id,
    OnItsOwn,
    CharacterSelect(character_select.Started),
    [AtCharacterSelect],
  ),
  Row(
    create_character_carrier.message_id,
    OnItsOwn,
    CharacterSelect(character_select.CreateAsked),
    [AtCharacterSelect],
  ),
  Row(play_character.message_id, OnItsOwn, WorldEntry, [AtCharacterSelect]),
  Row(
    delete_character.message_id,
    OnItsOwn,
    CharacterSelect(character_select.DeleteAsked),
    [AtCharacterSelect],
  ),
  Row(
    rename_character.message_id,
    OnItsOwn,
    CharacterSelect(character_select.RenameAsked),
    [AtCharacterSelect],
  ),
  Row(
    world_message.message_id,
    OnItsOwn,
    WorldMessage,
    [AtCharacterSelect, AtWorld],
  ),
  Row(
    player_movement.message_id,
    InsideWorldMessage,
    Movement(movement.PlayerMoved),
    [AtWorld],
  ),
  Row(
    world_zone_changed.message_id,
    InsideWorldMessage,
    Movement(movement.ZoneChanged),
    [AtWorld],
  ),
  Row(
    movement_send_interval_answer.message_id,
    InsideWorldMessage,
    Movement(movement.IntervalAnswered),
    [AtWorld],
  ),
  Row(
    move_speed_setting.message_id,
    InsideWorldMessage,
    Movement(movement.SpeedChosen),
    [AtWorld],
  ),
  Row(
    terrain_loaded.message_id,
    InsideWorldMessage,
    Movement(movement.TerrainReady),
    [AtWorld],
  ),
  Row(
    fall_value.message_id,
    InsideWorldMessage,
    Movement(movement.Fell),
    [AtWorld],
  ),
  Row(
    fell_below_floor.message_id,
    InsideWorldMessage,
    Movement(movement.FellBelowFloor),
    [AtWorld],
  ),
  Row(
    send_chat_line.message_id,
    InsideWorldMessage,
    Chat(chat.LineSent),
    [AtWorld],
  ),
  Row(
    send_whisper.message_id,
    InsideWorldMessage,
    Chat(chat.WhisperSent),
    [AtWorld],
  ),
  Row(
    cast_ability.message_id,
    InsideWorldMessage,
    Cast(cast.Pressed),
    [AtWorld],
  ),
  Row(cast_activate.message_id, InsideWorldMessage, Activation, [AtWorld]),
  Row(
    ability_hold.message_id,
    InsideWorldMessage,
    Cast(cast.KeyHeld),
    [AtWorld],
  ),
  Row(
    cancel_cast.message_id,
    InsideWorldMessage,
    Cast(cast.Cancelled),
    [AtWorld],
  ),
  Row(
    choose_resurrection.message_id,
    InsideWorldMessage,
    Life(player_life.ResurrectionChosen),
    [AtWorld],
  ),
  Row(
    innate_index_chosen.message_id,
    InsideWorldMessage,
    Innate(innate_choice.IndexChosen),
    [AtWorld],
  ),
  Row(
    interaction_request.message_id,
    InsideWorldMessage,
    Interaction(interaction.Requested),
    [AtWorld],
  ),
  Row(
    dialog_responses_shown.message_id,
    InsideWorldMessage,
    Interaction(interaction.ResponsesShown),
    [AtWorld],
  ),
  Row(
    quest_accept.message_id,
    InsideWorldMessage,
    Quest(quest.Accept),
    [AtWorld],
  ),
  Row(quest_retry.message_id, InsideWorldMessage, Quest(quest.Retry), [AtWorld]),
  Row(
    item_move.message_id,
    InsideWorldMessage,
    Inventory(inventory.MoveAsked),
    [AtWorld],
  ),
  Row(
    item_split.message_id,
    InsideWorldMessage,
    Inventory(inventory.SplitAsked),
    [AtWorld],
  ),
  Row(
    item_delete.message_id,
    InsideWorldMessage,
    Inventory(inventory.DeleteAsked),
    [AtWorld],
  ),
  Row(vendor_purchase.message_id, InsideWorldMessage, VendorPurchase, [AtWorld]),
  Row(vendor_sale.sale_message_id, InsideWorldMessage, VendorSale, [AtWorld]),
  Row(
    vendor_sale.junk_message_id,
    InsideWorldMessage,
    VendorSellJunk,
    [AtWorld],
  ),
  Row(
    camp_request.message_id,
    InsideWorldMessage,
    Camp(camp.CampAsked),
    [AtWorld],
  ),
  Row(
    camp_finished.message_id,
    InsideWorldMessage,
    Camp(camp.CampOver),
    [AtWorld],
  ),
  Row(
    watchdog_report.message_id,
    InsideWorldMessage,
    Dropped(dropped.WatchdogReport),
    [AtWorld],
  ),
  Row(
    frame_time_report.message_id,
    InsideWorldMessage,
    Dropped(dropped.FrameTimeReport),
    [AtWorld],
  ),
  Row(
    network_report.message_id,
    InsideWorldMessage,
    Dropped(dropped.NetworkReport),
    [AtWorld],
  ),
  Row(
    graphics_report.message_id,
    InsideWorldMessage,
    Dropped(dropped.GraphicsReport),
    [AtWorld],
  ),
  Row(
    window_opened.message_id,
    InsideWorldMessage,
    Dropped(dropped.WindowOpened),
    [AtWorld],
  ),
  Row(
    client_option.message_id,
    InsideWorldMessage,
    Dropped(dropped.ClientOption),
    [AtWorld],
  ),
  Row(
    scanbot_request.message_id,
    InsideWorldMessage,
    Dropped(dropped.ScanbotRequest),
    [AtWorld],
  ),
  Row(
    own_auctions_request.message_id,
    InsideWorldMessage,
    Dropped(dropped.OwnAuctionsRequest),
    [AtWorld],
  ),
  Row(
    own_commodity_orders_request.message_id,
    InsideWorldMessage,
    Dropped(dropped.OwnCommodityOrdersRequest),
    [AtWorld],
  ),
  Row(
    credd_exchange_request.message_id,
    InsideWorldMessage,
    Dropped(dropped.CreddExchangeRequest),
    [AtWorld],
  ),
  Row(
    trade_cancel.message_id,
    InsideWorldMessage,
    Dropped(dropped.TradeCancel),
    [AtWorld],
  ),
  Row(
    input_key_set_request.message_id,
    InsideWorldMessage,
    Dropped(dropped.InputKeySetRequest),
    [AtWorld],
  ),
  Row(
    pre_game_activity.message_id,
    OnItsOwn,
    Dropped(dropped.PreGameActivity),
    [AtCharacterSelect, AtWorld],
  ),
]

/// The feature that takes the message with this id, arriving this way, at this
/// stage; `Error(Nil)` for a message with no row or one not taken at the
/// stage.
pub fn route(
  stage stage: Stage,
  arrival arrival: Arrival,
  message_id message_id: Int,
) -> Result(Feature, Nil) {
  list.find(table, fn(row) {
    row.message_id == message_id
    && row.arrival == arrival
    && list.contains(row.taken_in, stage)
  })
  |> result.map(fn(row) { row.feature })
}

/// The ids of the messages that arrive this way, in the table's order, whatever
/// stage takes them.
pub fn message_ids(arrival arrival: Arrival) -> List(Int) {
  list.filter_map(table, fn(row) {
    case row.arrival == arrival {
      True -> Ok(row.message_id)
      False -> Error(Nil)
    }
  })
}
