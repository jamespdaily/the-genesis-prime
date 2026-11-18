//// The game connection's equip of a bind-on-equip item on the real store
//// (`genesis_prime/game/inventory`, `genesis_prime/game/item_flags`): the client's 0x182 into a
//// worn slot binds the item, the store saves the bit with the move, and the client is told.
//// Expected values come from these places.
//// - `0x1403c17d0.equip_confirm`: the client asks to confirm an equip of a bind-on-equip item
////   that is not soulbound and sends nothing new for the confirm: it sends the same 0x182 the
////   server binds on, and never sets the bit itself.
//// - `opcode.0x567`: the answer's item flags message, after the move's own 0x569 or 0x568.
//// - `opcode.0x111.shared_item_unnamed`: the entry carries the byte the store holds.
//// - Failure table, `item_flags`' rows: an equip whose ask is out when the connection ends
////   binds nothing (the store was never asked); one the store committed and the connection
////   never heard of leaves the item worn and bound, and the next entry's 0x111 carries the
////   byte, which resyncs the client.
//// - The items are the Engineer's Novice set of the tests' character
////   (`world_entry_support.novice_items`), whose chest piece row has its bindFlags changed to
////   bind on equip, a spare chest piece and a glove of bind-on-pickup rows.

import account_store_support.{type Stored}
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Request, AskStore, FromMap, FromStore,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/item_added
import genesis_prime/message/item_flags_changed
import genesis_prime/message/item_place
import genesis_prime/step.{type ConnectionStep, OwnEvent}
import genesis_prime/store.{
  type HeldItem, type ItemsRequest, type NewItem, ForItems, Items, MoveItems,
  NewItem,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{None}
import item_flags_support
import owned_test
import world_entry_support

/// A stored character holding the Engineer's Novice set and these items.
fn stored_holding(items items: List(NewItem)) -> Stored {
  account_store_support.stored_holding(
    worn: list.map(
      world_entry_support.novice_items(
        character: connection_support.world_character(),
      ),
      fn(item) {
        NewItem(
          item2_id: item.item2_id,
          location: item.location,
          bag_index: item.bag_index,
          stack_count: 1,
          charges: 0,
        )
      },
    ),
    items:,
  )
}

/// A chest piece of the Engineer's chest row in an inventory slot.
fn spare_chest(bag_index bag_index: Int) -> NewItem {
  NewItem(
    item2_id: Item2Id(item_flags_support.chest()),
    location: 1,
    bag_index:,
    stack_count: 1,
    charges: 0,
  )
}

/// The held item of the store at the place.
fn item_at(items items: List(HeldItem), place place: #(Int, Int)) -> HeldItem {
  let assert Ok(item) =
    list.find(items, fn(item) {
      item.location == place.0 && item.bag_index == place.1
    })
    as "the store holds an item at the place"
  item
}

/// The connection entered with exactly the items the store holds, on these tables, and the
/// step of the entry, whose frames are the 0x111s the client is sent.
fn entered_with(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let fresh =
    connection_support.accepted(
      Settings(..connection_support.settings(), tables:),
    ).0
  let #(state, taken) =
    connection_support.joining_holding_items(
      in_character_select: connection_support.in_select_from(fresh),
      character: connection_support.world_character(),
      saved_health: None,
      saved_experience: None,
      quests: [],
      items:,
    )
  connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(connection_support.map_answer(taken))),
  )
}

/// The (guid, place, flags byte) of each 0x111 of the frames.
fn added_in(frames frames: List(Frame)) -> List(#(Int, #(Int, Int), Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0111 -> {
        let assert Ok(added) = item_added.decode(frame.body)
          as "the 0x111 decodes"
        let item = added.held_item.item
        Ok(#(item.item_guid, #(item.location, item.bag_index), item.item_flags))
      }
      _ -> Error(Nil)
    }
  })
}

/// The flags byte of the 0x111 the entry sends for the item.
fn entry_flags(
  entry entry: ConnectionStep(Request),
  guid guid: Int,
) -> #(#(Int, Int), Int) {
  let assert Ok(#(_, place, item_flags)) =
    list.find(
      added_in(frames: connection_support.written(taken: entry)),
      fn(sent) { sent.0 == guid },
    )
    as "the entry sends the item"
  #(place, item_flags)
}

/// The guid and byte of each 0x567 the step wrote.
fn flags_told(taken taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  list.filter_map(connection_support.written(taken:), fn(frame) {
    case frame.message_id == item_flags_changed.message_id {
      False -> Error(Nil)
      True -> {
        let assert Ok(changed) = item_flags_changed.decode(frame.body)
          as "the 0x567 decodes"
        Ok(#(changed.item_guid, changed.item_flags))
      }
    }
  })
}

/// The 0x182 of the player, as the client sends it.
fn move_message(from from: #(Int, Int), to to: #(Int, Int)) -> BitArray {
  connection_support.item_moved_message(
    from: item_place.ItemPlace(location: from.0, bag_index: from.1),
    to: item_place.ItemPlace(location: to.0, bag_index: to.1),
  )
}

/// What a move of the player's asks the store and what the step after its answer wrote.
type Moved {
  Moved(
    state: game_connection.State,
    asked: ItemsRequest,
    answered: ConnectionStep(Request),
  )
}

/// The player's move, the real store's answer to its ask, and the step of the answer.
fn moved_on_the_store(
  stored stored: Stored,
  state state: game_connection.State,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Moved {
  let #(state, taken) = connection_support.read(state, move_message(from:, to:))
  let assert AskStore(Items(asked)) = connection_support.ask_request(taken)
    as "the accepted move is the store's ask"
  let outcome =
    step.Answer(
      FromStore(account_store_support.ask(
        store: stored.store,
        request: Items(account_store_support.own_request(
          stored:,
          request: asked,
        )),
      )),
    )
  let #(state, answered) = connection_support.answer(state:, taken:, outcome:)
  Moved(state:, asked:, answered:)
}

/// The flags set by each move of the ask.
fn flags_set_by(request request: ItemsRequest) -> List(Int) {
  let assert MoveItems(moves:, ..) = request as "a move asks MoveItems"
  list.map(moves, fn(move) { move.flags_set })
}

/// Equipping a bind-on-equip item binds it, in the store and for the client, and nothing
/// unbinds it: the ask carries the bit, the answer writes 0x569 then 0x567 with the whole byte
/// then the gear frames, an unequip and a second equip write no 0x567, a relog sends the byte
/// in the entry's 0x111, a bind-on-pickup glove is never bound, and a swap onto the worn slot
/// binds the item that comes in.
pub fn equipping_a_bind_on_equip_item_binds_it_and_the_binding_survives_unequipping_and_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- item_flags_support.with_bind_flags(
    item2_id: item_flags_support.chest(),
    bind_flags: item_flags_support.bind_on_equip,
    flags: None,
  )
  let stored =
    stored_holding(items: [spare_chest(bag_index: 0), spare_chest(bag_index: 2)])
  let #(_, rows) = account_store_support.loaded(stored:)
  let chest = item_at(items: rows, place: #(1, 0))
  let second_chest = item_at(items: rows, place: #(1, 2))
  let glove = item_at(items: rows, place: #(0, 5))
  let #(state, entry) = entered_with(tables:, items: rows)
  assert entry_flags(entry:, guid: chest.item_guid) == #(#(1, 0), 0)
    as "the entry's 0x111 of an unbound bind-on-equip chest piece holds 0"
  let flags_held = fn(guid) {
    let assert Ok(item) =
      list.find(account_store_support.loaded(stored:).1, fn(item) {
        item.item_guid == guid
      })
      as "the store holds the item"
    item.words.item_flags
  }
  // Unequip the Novice chest piece to free the slot, then equip the spare.
  let first = moved_on_the_store(stored:, state:, from: #(0, 0), to: #(1, 5))
  assert flags_set_by(request: first.asked) == [0] as "the unequip sets no bit"
  assert list.take(connection_support.written_ids(first.answered), 1)
    == [0x0569]
  assert flags_told(taken: first.answered) == []
  let equip =
    moved_on_the_store(stored:, state: first.state, from: #(1, 0), to: #(0, 0))
  assert flags_set_by(request: equip.asked) == [1]
    as "the equip of an unbound bind-on-equip item asks for bit 0"
  let ids = connection_support.written_ids(equip.answered)
  assert list.take(ids, 2) == [0x0569, 0x0567]
    as "opcode.0x569 then opcode.0x567, then the gear frames"
  assert list.length(ids) > 2 as "the gear frames follow"
  assert flags_told(taken: equip.answered) == [#(chest.item_guid, 1)]
    as "opcode.0x567: the item and its whole byte"
  assert flags_held(chest.item_guid) == 1
    as "the client's byte is the store's byte"
  // Unequip it and equip it again: it stays bound and nothing tells the client again.
  let off =
    moved_on_the_store(stored:, state: equip.state, from: #(0, 0), to: #(1, 0))
  assert flags_told(taken: off.answered) == []
  assert flags_held(chest.item_guid) == 1 as "unequipping keeps the bit"
  let again =
    moved_on_the_store(stored:, state: off.state, from: #(1, 0), to: #(0, 0))
  assert flags_set_by(request: again.asked) == [0]
    as "a soulbound item adds no bit"
  assert flags_told(taken: again.answered) == []
    as "an equip of a bound item writes no 0x567"
  // The relog: the next entry sends the byte.
  let #(_, rows) = account_store_support.loaded(stored:)
  let #(_, entry) = entered_with(tables:, items: rows)
  assert entry_flags(entry:, guid: chest.item_guid) == #(#(0, 0), 1)
    as "the relog's 0x111 of the chest piece carries 1"
  assert entry_flags(entry:, guid: second_chest.item_guid).1 == 0
    as "the second chest piece, never worn, still carries 0"
  // The bind-on-pickup glove is worn and unworn with no bit, before and after a relog.
  let #(state, _) = entered_with(tables:, items: rows)
  let glove_off =
    moved_on_the_store(stored:, state:, from: #(0, 5), to: #(1, 6))
  let glove_on =
    moved_on_the_store(stored:, state: glove_off.state, from: #(1, 6), to: #(
      0,
      5,
    ))
  assert flags_told(taken: glove_on.answered) == []
    && flags_set_by(request: glove_on.asked) == [0]
    as "a bind-on-pickup item is not bound by an equip"
  let #(_, rows) = account_store_support.loaded(stored:)
  let #(_, entry) = entered_with(tables:, items: rows)
  assert entry_flags(entry:, guid: glove.item_guid).1 == 0
    as "after a relog the glove's 0x111 still holds 0"
  // A swap puts the second unbound piece onto the worn chest's slot.
  let #(state, _) = entered_with(tables:, items: rows)
  let swap = moved_on_the_store(stored:, state:, from: #(1, 2), to: #(0, 0))
  assert flags_set_by(request: swap.asked) == [1, 0]
    as "the incoming piece binds and the displaced one is not touched"
  assert list.take(connection_support.written_ids(swap.answered), 2)
    == [0x0568, 0x0567]
    as "opcode.0x568 then opcode.0x567"
  assert flags_told(taken: swap.answered) == [#(second_chest.item_guid, 1)]
  account_store_support.stop(stored.store)
}

/// The frames that say an item moved or changed.
const move_frames = [0x0569, 0x0568, 0x0567]

/// An equip whose answer never reaches the connection, because the connection ends: the store
/// was asked and committed (the row is worn and bound), nothing is written for it, and the
/// next entry's 0x111 carries the byte, so the client resyncs.
pub fn a_crash_after_the_bind_commits_resyncs_the_client_on_reload_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- item_flags_support.with_bind_flags(
    item2_id: item_flags_support.chest(),
    bind_flags: item_flags_support.bind_on_equip,
    flags: None,
  )
  let stored = stored_holding(items: [spare_chest(bag_index: 0)])
  let #(_, rows) = account_store_support.loaded(stored:)
  let chest = item_at(items: rows, place: #(1, 0))
  // The chest slot is taken by the Novice chest piece: the equip is a swap.
  let #(state, _) = entered_with(tables:, items: rows)
  let #(state, taken) =
    connection_support.read(state, move_message(from: #(1, 0), to: #(0, 0)))
  let assert AskStore(Items(asked)) = connection_support.ask_request(taken)
    as "the accepted move is the store's ask"
  let assert ForItems(store.ItemsSaved) =
    account_store_support.ask(
      store: stored.store,
      request: Items(account_store_support.own_request(stored:, request: asked)),
    )
    as "the real store applies the move"
  // The answer is never delivered: the connection ends.
  let #(_, closing) = connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert list.filter(connection_support.written_ids(closing), fn(id) {
      list.contains(move_frames, id)
    })
    == []
    as "nothing is written for the move the connection never heard of"
  let #(_, reloaded) = account_store_support.loaded(stored:)
  let #(_, entry) = entered_with(tables:, items: reloaded)
  assert entry_flags(entry:, guid: chest.item_guid) == #(#(0, 0), 1)
    as "the reload sends the chest piece worn and bound"
  account_store_support.stop(stored.store)
}

/// An equip whose ask is out when the connection ends: the store was never asked, so the row
/// is as it was, and the next entry's 0x111 sends the item in the bag, unbound.
pub fn a_crash_before_the_bind_commits_leaves_the_item_unbound_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- item_flags_support.with_bind_flags(
    item2_id: item_flags_support.chest(),
    bind_flags: item_flags_support.bind_on_equip,
    flags: None,
  )
  let stored = stored_holding(items: [spare_chest(bag_index: 0)])
  let #(_, rows) = account_store_support.loaded(stored:)
  let chest = item_at(items: rows, place: #(1, 0))
  let #(state, _) = entered_with(tables:, items: rows)
  let #(state, taken) =
    connection_support.read(state, move_message(from: #(1, 0), to: #(0, 0)))
  assert support.asked(taken) != None as "the equip asks the store"
  let #(_, closing) = connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert list.filter(connection_support.written_ids(closing), fn(id) {
      list.contains(move_frames, id)
    })
    == []
    as "nothing is written for the equip"
  let #(_, reloaded) = account_store_support.loaded(stored:)
  let #(_, entry) = entered_with(tables:, items: reloaded)
  assert entry_flags(entry:, guid: chest.item_guid) == #(#(1, 0), 0)
    as "the reload sends the chest piece in the bag, unbound"
  account_store_support.stop(stored.store)
}
