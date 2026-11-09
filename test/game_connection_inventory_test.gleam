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
//// - `opcode.0x111.guid`: a split makes a stack whose guid only the store knows, so
////   the client's next 0x182 of that stack, sent while the split's ask is out, is
////   taken after the answer and finds the stack by its place with that guid.
//// - `step.EffectsThenAsk`: the effects before an ask are written before the ask is
////   made, and the shell takes no other input while an ask is out, so the frames
////   the client sent meanwhile are held and taken after the answer.
//// - The same rule as the summon's: the player is in the world while the store
////   moves the item, so a close then saves the place as in the world.
//// - Failure table, `inventory.answered`'s row for a store that is unavailable or
////   past its deadline: the move's outcome is unknown, so the connection ends and
////   the client is told 0x036A reason 8 (LostUserServer), as for any server fault.

import character_support
import connection_rule_support as support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/bit_stream
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/step.{
  EndedBeforeAnswer, LogError, NoAnswerInTime, NotRunning, OwnEvent,
}
import genesis_prime/store.{
  type HeldItem, AccountId, CharacterId, ForItems, HeldItem, ItemMade, ItemMove,
  ItemPlace, Items, ItemsSaved, MoveItems, SplitItem,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{None}
import owned_test
import world_entry_support

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
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
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

pub fn a_move_the_store_cannot_answer_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      NotRunning,
      NoAnswerInTime,
      EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, taken) =
        game_connection_support.read(
          game_connection_support.in_world(),
          chest_unequipped(),
        )
      let #(state, answered) =
        game_connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: LogError)) == 1
        as "a move whose outcome is unknown is an error line"
      assert game_connection_support.written_ids(answered) == []
        as "no 0x569, 0x568 or 0x56A: nothing says whether the item moved"
      let #(_, saved) =
        game_connection_support.answer(
          state:,
          taken: answered,
          outcome: game_connection_support.place_saved(),
        )
      assert game_connection_support.disconnect(
          saved,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8"
    },
  )
}

/// Item2 1039, a stackable item of the client's tables that holds 20.
const stackable_item2 = 1039

/// The Engineer's seven worn items and a stack of 10 of Item2 1039 in inventory
/// slot 1, guid 20.
fn stack() -> HeldItem {
  HeldItem(
    item_guid: 20,
    item2_id: Item2Id(fixture_tables.root("Item2", stackable_item2)),
    location: 1,
    bag_index: 1,
    stack_count: 10,
  )
}

fn holding_a_stack() -> game_connection.State {
  game_connection_support.in_world_holding(
    items: list.append(
      world_entry_support.novice_items(
        character: game_connection_support.world_character(),
      ),
      [stack()],
    ),
  )
}

/// A 0x17d of 3 of the stack to the empty inventory slot 2, inside 0x038C.
fn three_split_off() -> BitArray {
  let assert Ok(body) =
    item_split.encode(ItemSplit(
      item_guid: 20,
      to: item_place.ItemPlace(location: 1, bag_index: 2),
      count: 3,
    ))
  game_connection_support.world_message(
    message_id: item_split.message_id,
    body:,
  )
}

/// A 0x182 of whatever is in inventory slot 2 to the empty inventory slot 3.
fn slot_2_to_slot_3() -> BitArray {
  let assert Ok(body) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: 1, bag_index: 2),
      to: item_place.ItemPlace(location: 1, bag_index: 3),
    ))
  game_connection_support.world_message(message_id: 0x0182, body:)
}

pub fn a_split_answer_comes_before_the_frames_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(holding_a_stack(), three_split_off())
  assert game_connection_support.ask_request(taken)
    == AskStore(
      Items(SplitItem(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        source: stack(),
        count: 3,
        to: ItemPlace(location: 1, bag_index: 2),
      )),
    )
    as "opcode.0x17d: the accepted split is the store's ask, fenced by the login's epoch and the stack as held"
  assert support.writes(taken) == []
    as "nothing is written before the store has made the stack"
  let #(state, held) = game_connection_support.read(state, slot_2_to_slot_3())
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the 0x182 of the new stack is held while the split's ask is out"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemMade(item_guid: 77)))),
    )
  assert game_connection_support.written_ids(answered) == [0x017F, 0x0111]
    as "opcode.0x17f then opcode.0x111: the source's count and the new stack, with the store's guid, go out before the held 0x182 is handled"
  assert game_connection_support.ask_request(answered)
    == AskStore(
      Items(
        MoveItems(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          moves: [
            ItemMove(
              item_guid: 77,
              from: ItemPlace(location: 1, bag_index: 2),
              to: ItemPlace(location: 1, bag_index: 3),
            ),
          ],
        ),
      ),
    )
    as "opcode.0x111.guid: the held 0x182 finds the new stack at its slot, and asks for it by the guid the store made"
}
