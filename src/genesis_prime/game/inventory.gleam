//// The player's moves of held items: the client's 0x182, which a drag in the bags
//// or the character window sends, a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in
//// the world.
////
//// ```
//// 0x182 {from, to} ─▶ take(items, life, tables, message, body)
////                      ├─ refused ─▶ Refused([Send(0x56A guid, code)])       no ask, items unchanged
////                      └─ accepted ─▶ Asks(moving) ─▶ the connection asks the store (request(moving, ..))
////                                                     and waits in MovingItem, frames held
//// the store's answer ─▶ answered(items, moving, answer) ─▶ ItemsMoved:    0x569 or 0x568, items updated
////                                                         NothingMoved:   Note, 0x56A code 5, items unchanged
////                                                         MoveRefused(c): Fault naming c, 0x56A code 5
//// ```
////
//// - **A move is one message.** A move, a swap, an equip and an unequip are all
////   0x182: from {location 9 bits, bag index 32} to {location 9, bag index 32};
////   a swap is a move onto an occupied slot (`opcode.0x182`). The client sends
////   one at a time and refuses the others with PlayerBusy until 0x569, 0x568,
////   0x56A or 0x17F clears its wait (`opcode.0x182`).
//// - **The replies.** An empty destination is answered 0x569, the item's guid and
////   its new place as one 64-bit value, bag index in bits 0 to 7 and location in
////   bits 8 to 15 (`opcode.0x569`). An occupied destination is answered 0x568,
////   two {guid, place} pairs: the moved item at the destination and the other
////   item at the source (`opcode.0x568`). A refusal is 0x56A, a guid the client
////   does not read and a GenericError code (`opcode.0x56a`).
//// - **The guid is the item's identity** and stays with it when it moves
////   (`opcode.0x111.guid`).
//// - **The check order** is the client's (`opcode.0x182`, `0x1403ad100`,
////   `0x1403aecd0`, `0x1403b11b0`), so a refusal's code is the one the client
////   would show:
////   1. the player is dead: 57 Player_CantDoWhileDead
////   2. the destination location is 100 to 299: 32 Item_Locked
////   3. no held item at the source: 1 Params
////   4. the same slot, a destination location of 300 or more, an equipped index
////      above 30 or an inventory index of 96 or more: 1 Params
////   5. in combat with either side equipped: 63 Player_CannotWhileInCombat
////   6. either side the bank, a bank bag slot (equipped 21 to 30) or location 10,
////      which the server never opens: 2 PlayerBusy
////   7. an inventory destination index of 16 or more, the usable size with no
////      bags worn: 37 Item_BagToSmall
////   8. an item entering location 0 at a slot whose bit is not in its equipped
////      slot flags (`item_property.equipped_slot_flags`), or at bag slot 17 to 20:
////      31 Item_NotValidforSlot; for both items of a swap when the source is
////      equipped
////   9. any other location the server keeps no items at (3 to 99 except 10): 1
////      Params, a server choice
//// - **The store's answer** decides the reply, so storage and the client agree
////   after it: `NothingMoved` and `MoveRefused` leave `items` as they were and
////   answer 0x56A code 5 DbFailure, and the connection stays. A store that is
////   unavailable, not running or past its deadline ends the connection with
////   reason 8, which the connection decides.
//// - **Left to other steps:** gear properties, max health, worn visuals and the
////   cast's weapon, which still read the fixed loadout, not the held items.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/item_property
import genesis_prime/game/player_life.{type Life}
import genesis_prime/message/item_action_failed.{ItemActionFailed}
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/items_swapped.{ItemsSwapped}
import genesis_prime/step.{type LogLevel, LogError, LogInfo}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemMove,
  type ItemsAnswer, type SessionEpoch, ItemsMoved, MoveRefused, NothingMoved,
}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// The inventory message of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x0182, the player moves an item to a place.
  MoveAsked
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// A move the rule accepted and the store is asked for: `moves` is one move, or
/// two for a swap, `items` the held items as they stand once the store has
/// moved them, and `moved` the frame (0x569 or 0x568) the client is answered
/// with then. `guid` is the moved item's, which a refusal's 0x56A names.
pub type Moving {
  Moving(guid: Int, moves: List(ItemMove), items: List(HeldItem), moved: Frame)
}

/// What the rule makes of a move the client sent.
pub type Taken {
  /// The move breaks a check: the effects answer it, no ask is made and the
  /// items are unchanged.
  Refused(effects: List(Effect))
  /// The move passes every check: the store is asked for it.
  Asks(moving: Moving)
}

/// Why the move is refused without an answer: the client's own code never sends
/// it. The connection ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
}

/// The location the worn items are held at (`opcode.0x182`).
const equipped = 0

/// The location of the inventory.
const in_bags = 1

/// The location of the bank.
const bank = 2

/// The location the server never opens (`opcode.0x182`).
const never_opened = 10

/// The inventory size with no bags worn: slots 0 to 15 (`opcode.0x182`).
const usable_inventory_size = 16

/// The client's GenericError codes of a refused move (`opcode.0x56a`,
/// `GameLib.CodeEnumGenericError`): 1 Params.
const params = 1

/// 2 PlayerBusy.
const player_busy = 2

/// 5 DbFailure.
const db_failure = 5

/// 31 Item_NotValidforSlot.
const not_valid_for_slot = 31

/// 32 Item_Locked.
const item_locked = 32

/// 37 Item_BagToSmall.
const bag_too_small = 37

/// 57 Player_CantDoWhileDead.
const cant_do_while_dead = 57

/// 63 Player_CannotWhileInCombat.
const cannot_while_in_combat = 63

/// What the client's 0x0182 is answered with: a refusal with the code of the
/// first check it breaks, or the store's ask, or the refusal for a body the
/// client's reader refuses.
pub fn take(
  items items: List(HeldItem),
  life life: Life,
  tables tables: table_store.Tables,
  message message: Message,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  let MoveAsked = message
  use move <- result.try(
    item_move.decode(body)
    |> client_connection.decoded(message_id: item_move.message_id)
    |> result.map_error(NotDecoded),
  )
  let source = held_at(items:, place: move.from)
  let destination = held_at(items:, place: move.to)
  case checked(life:, tables:, move:, source:, destination:) {
    Error(code) ->
      Ok(
        Refused([
          Send(failed(
            guid: result.map(source, fn(item) { item.item_guid })
              |> result.unwrap(0),
            code:,
          )),
        ]),
      )
    Ok(item) -> Ok(Asks(moving(items:, move:, item:, destination:)))
  }
}

/// The item held at the place, if any.
fn held_at(
  items items: List(HeldItem),
  place place: ItemPlace,
) -> Result(HeldItem, Nil) {
  list.find(items, fn(item) {
    item.location == place.location && item.bag_index == place.bag_index
  })
}

/// The item the move moves, or the code of the first check the move breaks, in
/// the client's order (this module's doc).
fn checked(
  life life: Life,
  tables tables: table_store.Tables,
  move move: item_move.ItemMove,
  source source: Result(HeldItem, Nil),
  destination destination: Result(HeldItem, Nil),
) -> Result(HeldItem, Int) {
  let from = move.from
  let to = move.to
  use <- refuse(
    when: player_life.state(life:) == player_life.Dead,
    code: cant_do_while_dead,
  )
  use <- refuse(
    when: to.location >= 100 && to.location <= 299,
    code: item_locked,
  )
  use item <- result.try(result.replace_error(source, params))
  use <- refuse(
    when: from == to
      || to.location >= 300
      || out_of_range(from)
      || out_of_range(to),
    code: params,
  )
  use <- refuse(
    when: player_life.in_combat(life:)
      && { from.location == equipped || to.location == equipped },
    code: cannot_while_in_combat,
  )
  use <- refuse(when: closed(from) || closed(to), code: player_busy)
  use <- refuse(
    when: to.location == in_bags && to.bag_index >= usable_inventory_size,
    code: bag_too_small,
  )
  use <- refuse(
    when: !fits(tables:, item:, place: to)
      || case destination {
      Ok(other) -> !fits(tables:, item: other, place: from)
      Error(Nil) -> False
    },
    code: not_valid_for_slot,
  )
  use <- refuse(when: to.location >= 3 && to.location <= 99, code: params)
  Ok(item)
}

/// Stops with the code when the check fails.
fn refuse(
  when refused: Bool,
  code code: Int,
  then next: fn() -> Result(a, Int),
) -> Result(a, Int) {
  use <- bool.guard(when: refused, return: Error(code))
  next()
}

/// The equipped slots end at index 30 and the inventory at 95.
fn out_of_range(place: ItemPlace) -> Bool {
  { place.location == equipped && place.bag_index > 30 }
  || { place.location == in_bags && place.bag_index >= 96 }
}

/// A place the server never opens: the bank, a bank bag's slot (equipped 21 to
/// 30) and location 10.
fn closed(place: ItemPlace) -> Bool {
  place.location == bank
  || place.location == never_opened
  || {
    place.location == equipped && place.bag_index >= 21 && place.bag_index <= 30
  }
}

/// Whether the item may be at the place: any place but an equipped one takes it;
/// an equipped one takes it when the bit of the place is in the item's equipped
/// slot flags and it is no bag slot (17 to 20). Flags that cannot be read are no
/// flags.
fn fits(
  tables tables: table_store.Tables,
  item item: HeldItem,
  place place: ItemPlace,
) -> Bool {
  use <- bool.guard(when: place.location != equipped, return: True)
  let flags =
    item_property.equipped_slot_flags(tables:, item2_id: item.item2_id.value)
    |> result.unwrap(0)
  let bit = int.bitwise_shift_left(1, place.bag_index)
  !{ place.bag_index >= 17 && place.bag_index <= 20 }
  && int.bitwise_and(flags, bit) != 0
}

/// The ask and the answer of an accepted move: one move to an empty place, two
/// for an item that takes the place of another.
fn moving(
  items items: List(HeldItem),
  move move: item_move.ItemMove,
  item item: HeldItem,
  destination destination: Result(HeldItem, Nil),
) -> Moving {
  let from = move.from
  let to = move.to
  let to_place = store.ItemPlace(location: to.location, bag_index: to.bag_index)
  let from_place =
    store.ItemPlace(location: from.location, bag_index: from.bag_index)
  let first =
    store.ItemMove(item_guid: item.item_guid, from: from_place, to: to_place)
  case destination {
    Error(Nil) ->
      Moving(
        guid: item.item_guid,
        moves: [first],
        items: relocated(items:, guid: item.item_guid, to: to_place),
        moved: frame_of_move(guid: item.item_guid, place: to),
      )
    Ok(other) ->
      Moving(
        guid: item.item_guid,
        moves: [
          first,
          store.ItemMove(
            item_guid: other.item_guid,
            from: to_place,
            to: from_place,
          ),
        ],
        items: items
          |> relocated(guid: item.item_guid, to: to_place)
          |> relocated(guid: other.item_guid, to: from_place),
        moved: frame_of_swap(first: #(item.item_guid, to), second: #(
          other.item_guid,
          from,
        )),
      )
  }
}

/// The items with the item of the guid held at the place.
fn relocated(
  items items: List(HeldItem),
  guid guid: Int,
  to place: store.ItemPlace,
) -> List(HeldItem) {
  list.map(items, fn(item) {
    case item.item_guid == guid {
      True ->
        store.HeldItem(
          ..item,
          location: place.location,
          bag_index: place.bag_index,
        )
      False -> item
    }
  })
}

/// A place as the client's messages write it: the bag index in bits 0 to 7 and
/// the location in bits 8 to 15 (`opcode.0x569`).
fn place_value(place: ItemPlace) -> Int {
  place.location * 256 + place.bag_index
}

/// The 0x569 of an item moved to an empty place.
fn frame_of_move(guid guid: Int, place place: ItemPlace) -> Frame {
  let assert Ok(body) =
    item_moved.encode(ItemMoved(item_guid: guid, place: place_value(place)))
    as "a guid and a place of a held item fit 0x569"
  Frame(message_id: item_moved.message_id, body:)
}

/// The 0x568 of two items that traded places: the moved one at the destination
/// and the other at the source.
fn frame_of_swap(
  first first: #(Int, ItemPlace),
  second second: #(Int, ItemPlace),
) -> Frame {
  let assert Ok(body) =
    items_swapped.encode(ItemsSwapped(
      first_guid: first.0,
      first_place: place_value(first.1),
      second_guid: second.0,
      second_place: place_value(second.1),
    ))
    as "two guids and places of held items fit 0x568"
  Frame(message_id: items_swapped.message_id, body:)
}

/// A 0x56A with the code.
fn failed(guid guid: Int, code code: Int) -> Frame {
  let assert Ok(body) =
    item_action_failed.encode(ItemActionFailed(item_guid: guid, code:))
    as "a guid and a code fit 0x56A"
  Frame(message_id: item_action_failed.message_id, body:)
}

/// The store's request for an accepted move, fenced by the login's epoch.
pub fn request(
  moving moving: Moving,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
) -> store.Request {
  store.Items(store.MoveItems(
    account_id:,
    character_id:,
    session_epoch:,
    moves: moving.moves,
  ))
}

/// The held items and the effects the store's answer to the move leaves: the
/// items of `moving` and its 0x569 or 0x568 for `ItemsMoved`, and the items as
/// they were with a log line and 0x56A code 5 for any other answer.
pub fn answered(
  items items: List(HeldItem),
  moving moving: Moving,
  answer answer: ItemsAnswer,
) -> #(List(HeldItem), List(Effect)) {
  case answer {
    ItemsMoved -> #(moving.items, [Send(moving.moved)])
    NothingMoved -> #(items, [
      Log(
        level: LogInfo,
        text: "the item was not moved: a later login holds the character, or the items are not where the client has them",
      ),
      Send(failed(guid: moving.guid, code: db_failure)),
    ])
    MoveRefused(constraint:) -> #(items, [
      Log(
        level: LogError,
        text: "the item was not moved: the store refused the places by the constraint "
          <> constraint,
      ),
      Send(failed(guid: moving.guid, code: db_failure)),
    ])
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}
