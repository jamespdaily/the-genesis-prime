//// The item, vendor and inventory actions of a scripted client: each encodes its
//// message with the codec, sends it as a world message, reads what the server wrote
//// in answer and gives that decoded. The answer to every action but opening the vendor
//// is all the server wrote up to its pong, which is all it wrote before it took the
//// ping (`game_client.read_until_pong`).

import game_client.{type Game}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/buyback_added
import genesis_prime/message/buyback_entry.{type BuybackEntry}
import genesis_prime/message/buyback_removed
import genesis_prime/message/currency_changed.{type CurrencyChanged}
import genesis_prime/message/held_item.{type HeldItem}
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/item_action_failed.{type ItemActionFailed}
import genesis_prime/message/item_added
import genesis_prime/message/item_count_changed.{type ItemCountChanged}
import genesis_prime/message/item_delete.{ItemDelete}
import genesis_prime/message/item_move.{ItemMove}
import genesis_prime/message/item_moved.{type ItemMoved}
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/message/item_removed.{type ItemRemoved}
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/message/items_swapped.{type ItemsSwapped}
import genesis_prime/message/vendor_buyback.{VendorBuyback}
import genesis_prime/message/vendor_items.{type VendorItems}
import genesis_prime/message/vendor_purchase.{VendorPurchase}
import genesis_prime/message/vendor_sale.{VendorSale}
import gleam/int
import gleam/list
import gleam/result

/// What the server wrote in answer to an action, each message kind decoded in the
/// order it came, and every frame as it came.
pub type Answer {
  Answer(
    frames: List(Frame),
    /// 0x111: an item the character now holds.
    added: List(HeldItem),
    /// 0x17F: a stack whose count changed.
    count_changed: List(ItemCountChanged),
    /// 0x148: an item that is gone.
    removed: List(ItemRemoved),
    /// 0x569: an item moved to a place.
    moved: List(ItemMoved),
    /// 0x568: two items that swapped places.
    swapped: List(ItemsSwapped),
    /// 0x56A: an item action the server refused.
    refused: List(ItemActionFailed),
    /// 0x919: a currency's new total.
    currencies: List(CurrencyChanged),
    /// 0xBA: an entry added to the Buyback list.
    buyback_added: List(BuybackEntry),
    /// 0xBD: the ids of the entries that left the Buyback list.
    buyback_removed: List(Int),
  )
}

/// The answer the frames make, each message decoded as the client's reader reads it.
pub fn answer_in(frames frames: List(Frame)) -> Answer {
  Answer(
    frames:,
    added: decoded(frames, item_added.message_id, fn(body) {
      item_added.decode(body) |> result.map(fn(message) { message.held_item })
    }),
    count_changed: decoded(
      frames,
      item_count_changed.message_id,
      item_count_changed.decode,
    ),
    removed: decoded(frames, item_removed.message_id, item_removed.decode),
    moved: decoded(frames, item_moved.message_id, item_moved.decode),
    swapped: decoded(frames, items_swapped.message_id, items_swapped.decode),
    refused: decoded(
      frames,
      item_action_failed.message_id,
      item_action_failed.decode,
    ),
    currencies: decoded(
      frames,
      currency_changed.message_id,
      currency_changed.decode,
    ),
    buyback_added: decoded(frames, buyback_added.message_id, fn(body) {
      buyback_added.decode(body) |> result.map(fn(message) { message.entry })
    }),
    buyback_removed: decoded(frames, buyback_removed.message_id, fn(body) {
      buyback_removed.decode(body)
      |> result.map(fn(message) { message.buyback_id })
    }),
  )
}

fn decoded(
  frames: List(Frame),
  message_id: Int,
  decode: fn(BitArray) -> Result(a, e),
) -> List(a) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == message_id {
      True -> {
        let assert Ok(message) = decode(frame.body)
          as "the client's reader reads a message the server wrote"
        Ok(message)
      }
      False -> Error(Nil)
    }
  })
}

/// The place a 0x569 gives as one 64-bit value: the bag index in bits 0 to 7 and the
/// location in bits 8 to 15 (opcode.0x569).
pub fn place_of(value value: Int) -> ItemPlace {
  ItemPlace(
    location: int.bitwise_and(int.bitwise_shift_right(value, 8), 0xFF),
    bag_index: int.bitwise_and(value, 0xFF),
  )
}

/// Right-clicks the unit, which opens its vendor window: the 0x90B the server answers
/// with, and the bytes beyond it.
pub fn open_vendor(
  game game: Game,
  have have: BitArray,
  unit_id unit_id: Int,
) -> #(VendorItems, BitArray) {
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(unit_id:, kind: 0x31))
    as "0x7EA encodes"
  game_client.send_world(
    game:,
    message_id: interaction_request.message_id,
    body:,
  )
  let #(frames, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == vendor_items.message_id })
    })
  let assert [window] =
    decoded(frames, vendor_items.message_id, vendor_items.decode)
    as "the server answers a vendor request with one window"
  #(window, have)
}

/// Buys `quantity` lots of the window's item at its unique id.
pub fn buy(
  game game: Game,
  have have: BitArray,
  unique_id unique_id: Int,
  quantity quantity: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    vendor_purchase.encode(VendorPurchase(unique_id:, quantity:))
    as "0xBE encodes"
  acted(game:, have:, message_id: vendor_purchase.message_id, body:)
}

/// Sells `quantity` of the item at the place to the open vendor.
pub fn sell(
  game game: Game,
  have have: BitArray,
  place place: ItemPlace,
  quantity quantity: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) = vendor_sale.encode(VendorSale(place:, quantity:))
    as "0x166 encodes"
  acted(game:, have:, message_id: vendor_sale.message_id, body:)
}

/// Buys back the entry of the Buyback list.
pub fn buy_back(
  game game: Game,
  have have: BitArray,
  buyback_id buyback_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) = vendor_buyback.encode(VendorBuyback(buyback_id:))
    as "0xBB encodes"
  acted(game:, have:, message_id: vendor_buyback.message_id, body:)
}

/// Moves the item at one place to another: a move, an equip, an unequip, a merge or a
/// swap, as the destination decides.
pub fn move(
  game game: Game,
  have have: BitArray,
  from from: ItemPlace,
  to to: ItemPlace,
) -> #(Answer, BitArray) {
  let assert Ok(body) = item_move.encode(ItemMove(from:, to:))
    as "0x182 encodes"
  acted(game:, have:, message_id: item_move.message_id, body:)
}

/// Splits `count` off the stack of the item guid into the place.
pub fn split(
  game game: Game,
  have have: BitArray,
  item_guid item_guid: Int,
  to to: ItemPlace,
  count count: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) = item_split.encode(ItemSplit(item_guid:, to:, count:))
    as "0x17D encodes"
  acted(game:, have:, message_id: item_split.message_id, body:)
}

/// Deletes the item at the place.
pub fn delete(
  game game: Game,
  have have: BitArray,
  place place: ItemPlace,
) -> #(Answer, BitArray) {
  let assert Ok(body) = item_delete.encode(ItemDelete(place:))
    as "0x149 encodes"
  acted(game:, have:, message_id: item_delete.message_id, body:)
}

fn acted(
  game game: Game,
  have have: BitArray,
  message_id message_id: Int,
  body body: BitArray,
) -> #(Answer, BitArray) {
  game_client.send_world(game:, message_id:, body:)
  let #(frames, have) = game_client.read_until_pong(game:, have:, number: 1)
  #(answer_in(frames:), have)
}
