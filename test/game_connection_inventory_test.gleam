//// The game connection's rule (`genesis_prime/game/connection`) on an item move
//// (`genesis_prime/game/inventory`): the client's 0x182 asks the store and the
//// connection waits for its answer. Expected values come from these places.
//// - `opcode.0x182`: the client sends one move at a time and refuses the others
////   with PlayerBusy until 0x569, 0x568, 0x56A or 0x17F clears its wait, so the
////   answer is the next thing the connection writes for the player.
//// - `opcode.0x569`: the answer to a move to an empty place is the item's guid and
////   its place, location * 256 + bag index: the chest piece (guid 1, the first of
////   the Engineer's Novice set, `novice_tables`) unequipped to inventory slot 0 is
////   guid 1 at place 256.
//// - `opcode.0x1c2`: a chat line is answered with the speaker's own line.
//// - `step.EffectsThenAsk`: the effects before an ask are written before the ask is
////   made, and the shell takes no other input while an ask is out, so the frames
////   the client sent meanwhile are held and taken after the answer.
//// - The same rule as the summon's: the player is in the world while the store
////   moves the item, so a close then saves the place as in the world.

import character_support
import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/message/bit_stream
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/step.{OwnEvent}
import genesis_prime/store.{
  AccountId, CharacterId, ForItems, ItemMove, ItemPlace, Items, ItemsMoved,
  MoveItems,
}
import gleam/option.{None}
import owned_test

/// A 0x182 of the chest piece from the worn slot 0 to inventory slot 0, as the
/// client sends it, inside 0x038C.
fn chest_unequipped() -> BitArray {
  let assert Ok(body) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: 0, bag_index: 0),
      to: item_place.ItemPlace(location: 1, bag_index: 0),
    ))
  game_connection_support.world_message(message_id: 0x0182, body:)
}

/// A 0x1c3 of the Say channel, as the client sends it.
fn say_hello() -> BitArray {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [],
      chat_message_id: 1,
    ))
  game_connection_support.world_message(send_chat_line.message_id, body)
}

/// The store's ask for the chest piece's move: the tests' account and character,
/// the epoch their load gave, and the one move.
fn move_asked() -> client_connection.Request {
  AskStore(
    Items(
      MoveItems(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        moves: [
          ItemMove(
            item_guid: 1,
            from: ItemPlace(location: 0, bag_index: 0),
            to: ItemPlace(location: 1, bag_index: 0),
          ),
        ],
      ),
    ),
  )
}

pub fn a_move_answer_comes_before_the_frames_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  assert game_connection_support.ask_request(taken) == move_asked()
    as "opcode.0x182: the accepted move is the store's ask, fenced by the login's epoch"
  assert support.writes(taken) == []
    as "nothing is written before the store has moved the item"
  let #(state, held) = game_connection_support.read(state, say_hello())
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the client's frames are held while the ask is out"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemsMoved))),
    )
  assert game_connection_support.written_ids(answered) == [0x0569, 0x01C2]
    as "opcode.0x569 then opcode.0x1c2: the move's answer goes out first, then the held line is taken and answered"
  let assert [first, ..] = game_connection_support.written(answered)
  assert item_moved.decode(first.body)
    == Ok(ItemMoved(item_guid: 1, place: 256))
    as "opcode.0x569: guid 1 at location 1, bag index 0, which is 256"
}

pub fn a_connection_that_ends_while_a_move_waits_saves_its_place_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the player is in the world while the store moves the item, so its place is saved as in InWorld"
}
