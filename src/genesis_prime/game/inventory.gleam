//// The player's changes of held items: the client's 0x182, which a drag in the
//// bags or the character window sends, 0x17D, which splits a stack, and 0x149,
//// which destroys one, a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in
//// the world.
////
//// ```
//// 0x182 {from, to}    ─▶ take(items, life, tables, wearer, message, body)
//// 0x17D {guid, place, count}
//// 0x149 {place}
////                      ├─ refused ─▶ Refused([Send(0x56A guid, code)])       no ask, items unchanged
////                      └─ accepted ─▶ Asks(moving) ─▶ the connection asks the store (request(moving, ..))
////                                                     and waits in MovingItem, frames held
//// the store's answer ─▶ answered(items, moving, answer) ─▶ ItemsSaved:    the change's replies, items updated
////                                                         ItemMade(guid): a split's replies, the new stack held
////                                                         ItemsNotSaved:  Warning, 0x56A code 5, items unchanged
////                                                         SaveRefused(c): Fault naming c, 0x56A code 5
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
////   4. the same slot, a destination location of 300 or more or an equipped
////      index above 30: 1 Params
////   5. in combat with either side equipped: 63 Player_CannotWhileInCombat
////   6. either side the bank, a bank bag slot (equipped 21 to 30) or location 10,
////      which the server never opens: 2 PlayerBusy
////   7. an inventory destination index of 96 or more, past the slot array: 1
////      Params (0x1403ad100 tests it after 5 and 6)
////   8. an inventory destination index of 16 or more, the usable size with no
////      bags worn: 37 Item_BagToSmall
////   9. an item entering an equipping location (0, 8 or 9) from another one, whose
////      Item2.bindFlags holds bit 1, while an item of its Item2 is worn, unless
////      the item at the destination is of that Item2: 30 Item_Unique
////   10. an item entering location 0 whose type, category and family flags lack
////      0x400, at a slot whose bit is not in its equipped slot flags
////      (`item_property.equipped_slot_flags`), or at bag slot 17 to 20: 31
////      Item_NotValidforSlot
////   11. an item entering location 0 that the character may not wear
////      (`equip_requirement`): race 39, class 40, faction 132, prerequisites 144,
////      proficiency 41, level 42. A prerequisite on a condition type the server
////      does not read is refused with 144 and a Warning that names the type.
////   For a swap checks 9 to 11 are made again for the item at the destination
////   going to the source, after the moved item's. An item with no row in the
////   tables is the server's own broken state, not a code: the connection ends
////   (`NoItemRow`). The client's rune-unique loop is not built; it waits for the
////   issue "Items, equipment, vendors, levels and currency work on the real
////   client".
////   12. any other location the server keeps no items at (3 to 99 except 10): 1
////       Params, a server choice
//// - **What the client never sends.** The client refuses locally, before its dead
////   check and without sending 0x182, a destination location above 299, an
////   unset (0xffffffff) destination index and an equipped destination index
////   above 30 with Item_InventoryFull 27 (`opcode.0x182`, sender 0x1403c17d0, the
////   only one of 0x182), so no input here is answered 27.
//// - **The store's answer** decides the reply, so storage and the client agree
////   after it: `ItemsNotSaved` and `SaveRefused` leave `items` as they were and
////   answer 0x56A code 5 DbFailure, and the connection stays. A store that is
////   unavailable, not running or past its deadline ends the connection with
////   reason 8, which the connection decides.
//// - **Stacks.** A split is 0x17D {guid 64, location 9, bag index 32, count 32}
////   and a delete 0x149 {location 9, bag index 32}; a merge is a 0x182 onto a
////   stack of the same stackable Item2 with room under its maxStackCount, and
////   onto any other occupied slot a 0x182 is the swap (`0x1406d50f0`, which does
////   not test the target stack's room). Every reply to a split or a merge has
////   the reason 0 (StackSplit), which raises no further notice (`0x1403b8060`), and
////   a delete is answered 0x148 with the reason 21 (PlayerRequested). Replies, in
////   order: a split 0x17F of the source then 0x111 of the new stack; a full merge
////   0x17F of the target then 0x148 of the source; a partial merge 0x17F of the
////   target at maxStackCount then 0x17F of the source; the order is the server's
////   choice.
//// - **The split's checks** (a 0x56A {the held item's guid, or 0 for none; code},
////   no ask, items unchanged), in this order; the client's split path has no dead
////   or combat check, so none is made here:
////   1. no held item has the guid: 1 Params
////   2. the count is 0, or the held count or more: 1 Params
////   3. the destination is the bank, a bank bag slot or location 10: 2 PlayerBusy
////   4. the destination is not the inventory, or its index is 96 or more: 1 Params
////   5. an inventory index of 16 or more: 37 Item_BagToSmall
////   6. an item is held at the destination: 1 Params
//// - **The delete's checks** (0x56A guid 0 for the first two), in this order:
////   1. location 300 or more, bag index 0xffffffff or an equipped index of 31 or
////      more: 1 Params
////   2. no held item at the place: 1 Params
////   3. no Item2 row for the held item: the connection ends (`NoItemRow`)
////   4. Item2.flags holds 0x10000: 156 Item_CannotBeDeleted
////   The client's sender (`opcode.0x149`, `0x1403c1360`) also sends nothing for
////   a worn bag and for an item in a trade; no worn bag is held until #587 and
////   there is no trade.
//// - **Left to other steps:** gear properties, max health, worn visuals and the
////   cast's weapon, which still read the fixed loadout, not the held items.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/equip_requirement.{type Wearer}
import genesis_prime/game/item_property
import genesis_prime/game/player_life.{type Life}
import genesis_prime/message/float32
import genesis_prime/message/held_item
import genesis_prime/message/item_action_failed.{ItemActionFailed}
import genesis_prime/message/item_added.{ItemAdded}
import genesis_prime/message/item_count_changed.{ItemCountChanged}
import genesis_prime/message/item_delete
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/item_removed.{ItemRemoved}
import genesis_prime/message/item_split
import genesis_prime/message/items_swapped.{ItemsSwapped}
import genesis_prime/message/shared_item.{SharedItem}
import genesis_prime/step.{type LogLevel, LogError, LogWarning}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemMove,
  type ItemsAnswer, type SessionEpoch, ItemMade, ItemsNotSaved, ItemsSaved,
  SaveRefused,
}
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The inventory message of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x0182, the player moves an item to a place.
  MoveAsked
  /// 0x017D, the player splits a stack onto an empty place.
  SplitAsked
  /// 0x0149, the player destroys the item at a place.
  DeleteAsked
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// A change the rule accepted and the store is asked for: `change` is what is
/// saved, `items` the held items as they stand once the store has saved it (a
/// split's new stack is added with the guid the store makes), and `guid` the
/// item the player named, which a refusal's 0x56A names.
pub type Moving {
  Moving(guid: Int, change: Change, items: List(HeldItem))
}

/// What an accepted change saves, with the rows as they are held, which fence
/// the store's statement.
pub type Change {
  /// One move, or two for a swap, answered with `moved`, the frame (0x569 or
  /// 0x568) the client gets once they are saved.
  Moved(moves: List(ItemMove), moved: Frame)
  /// `count` of the stack `source` put onto the stack `target`, of the same
  /// Item2: the source goes when none of it is left.
  Merged(source: HeldItem, target: HeldItem, count: Int)
  /// `count` of the stack `source` made into a new stack at the empty place `to`.
  Split(source: HeldItem, count: Int, to: store.ItemPlace)
  /// The whole stack `item` destroyed.
  Deleted(item: HeldItem)
}

/// What the rule makes of a move the client sent.
pub type Taken {
  /// The move breaks a check: the effects answer it, no ask is made and the
  /// items are unchanged.
  Refused(effects: List(Effect))
  /// The move passes every check: the store is asked for it.
  Asks(moving: Moving)
}

/// Why the move ends the connection with no answer: the client's own code never
/// sends it, or the server's own state is broken.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A held item whose slot the tables cannot give: the server holds an item the
  /// client's tables have no row for, which is the server's own state broken.
  NoItemRow(item2_id: Item2Id)
}

/// Why a move does not pass the checks: the code of the check it breaks, which
/// the client is answered with, or a refusal that ends the connection.
type Stop {
  Code(code: Int)
  /// A prerequisite of the item rests on a condition type the server does not
  /// read: the client would decide it, so the move is refused with 144 and logged.
  Unread(item2_id: Item2Id, prerequisite_type: Int)
  Broken(refusal: Refusal)
}

/// The location the worn items are held at (`opcode.0x182`).
const equipped = 0

/// The location of the inventory.
const in_bags = 1

/// The locations the client's move check treats as equipping: the worn slots,
/// 8 and 9 (0x1403ad100).
const equip_like_locations = [0, 8, 9]

/// The location of the bank.
const bank = 2

/// The location the server never opens (`opcode.0x182`).
const never_opened = 10

/// The inventory size with no bags worn: slots 0 to 15 (`opcode.0x182`).
const usable_inventory_size = 16

/// The size of the inventory's slot array: 0x1403ad100 refuses an inventory
/// destination index at or past it with Params.
const inventory_slots = 96

/// The client's GenericError codes of a refused move (`opcode.0x56a`,
/// `GameLib.CodeEnumGenericError`): 1 Params.
const params = 1

/// 2 PlayerBusy.
const player_busy = 2

/// 5 DbFailure.
const db_failure = 5

/// 30 Item_Unique.
const item_unique = 30

/// 31 Item_NotValidforSlot.
const not_valid_for_slot = 31

/// 32 Item_Locked.
const item_locked = 32

/// 37 Item_BagToSmall.
const bag_too_small = 37

/// 156 Item_CannotBeDeleted.
const cannot_be_deleted = 156

/// 57 Player_CantDoWhileDead.
const cant_do_while_dead = 57

/// 63 Player_CannotWhileInCombat.
const cannot_while_in_combat = 63

/// The reason of the replies to a split and a merge: 0 StackSplit, which raises
/// no notice (0x1403b8060).
const stack_split = 0

/// The reason of the reply to a delete: 21 PlayerRequested (0x1403b8250).
const player_requested = 21

/// A bag index the client's delete never sends (0x1403c1360).
const unset_bag_index = 0xffffffff

/// The location from which the client's delete sends nothing (0x1403c1360).
const first_location_never_deleted = 300

/// What the client's message is answered with: a refusal with the code of the
/// first check it breaks, or the store's ask, or the refusal for a body the
/// client's reader refuses.
pub fn take(
  items items: List(HeldItem),
  life life: Life,
  tables tables: table_store.Tables,
  wearer wearer: Wearer,
  message message: Message,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  case message {
    MoveAsked -> take_move(items:, life:, tables:, wearer:, body:)
    SplitAsked -> take_split(items:, body:)
    DeleteAsked -> take_delete(items:, tables:, body:)
  }
}

/// A 0x56A that refuses with the code, naming the item the player named.
fn refused_with(
  item item: Result(HeldItem, Nil),
  code code: Int,
) -> Result(Taken, Refusal) {
  Ok(
    Refused([
      Send(failed(
        guid: result.map(item, fn(item) { item.item_guid }) |> result.unwrap(0),
        code:,
      )),
    ]),
  )
}

/// What a 0x017D is answered with: the first of the split's checks it breaks
/// (this module's doc), else the ask.
fn take_split(
  items items: List(HeldItem),
  body body: BitArray,
) -> Result(Taken, Refusal) {
  use split <- result.try(
    item_split.decode(body)
    |> client_connection.decoded(message_id: item_split.message_id)
    |> result.map_error(NotDecoded),
  )
  let to = split.to
  let source = list.find(items, fn(item) { item.item_guid == split.item_guid })
  case source {
    Error(Nil) -> refused_with(item: source, code: params)
    Ok(item) ->
      case split.count < 1 || split.count >= item.stack_count {
        True -> refused_with(item: source, code: params)
        False ->
          case split_code(items:, to:) {
            Error(code) -> refused_with(item: source, code:)
            Ok(Nil) -> {
              let place =
                store.ItemPlace(location: to.location, bag_index: to.bag_index)
              Ok(
                Asks(Moving(
                  guid: item.item_guid,
                  change: Split(source: item, count: split.count, to: place),
                  items: restacked(
                    items:,
                    guid: item.item_guid,
                    count: item.stack_count - split.count,
                  ),
                )),
              )
            }
          }
      }
  }
}

/// The code of the first of a split's checks on the destination that it breaks.
/// The order is the split's own (closed before the location test), so it does
/// not call `checked`'s place checks.
fn split_code(
  items items: List(HeldItem),
  to to: ItemPlace,
) -> Result(Nil, Int) {
  use <- bool.guard(when: closed(to), return: Error(player_busy))
  use <- bool.guard(
    when: to.location != in_bags || to.bag_index >= inventory_slots,
    return: Error(params),
  )
  use <- bool.guard(
    when: to.bag_index >= usable_inventory_size,
    return: Error(bag_too_small),
  )
  case held_at(items:, place: to) {
    Ok(_) -> Error(params)
    Error(Nil) -> Ok(Nil)
  }
}

/// What a 0x0149 is answered with: the first of the delete's checks it breaks
/// (this module's doc), else the ask.
fn take_delete(
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  use delete <- result.try(
    item_delete.decode(body)
    |> client_connection.decoded(message_id: item_delete.message_id)
    |> result.map_error(NotDecoded),
  )
  let place = delete.place
  use <- bool.lazy_guard(
    when: place.location >= first_location_never_deleted
      || place.bag_index == unset_bag_index
      || out_of_equipped_range(place),
    return: fn() { refused_with(item: Error(Nil), code: params) },
  )
  case held_at(items:, place:) {
    Error(Nil) -> refused_with(item: Error(Nil), code: params)
    Ok(item) ->
      case item_property.deletable(tables:, item2_id: item.item2_id.value) {
        Error(_) -> Error(NoItemRow(item2_id: item.item2_id))
        Ok(False) -> refused_with(item: Ok(item), code: cannot_be_deleted)
        Ok(True) ->
          Ok(
            Asks(Moving(
              guid: item.item_guid,
              change: Deleted(item:),
              items: without(items:, guid: item.item_guid),
            )),
          )
      }
  }
}

/// The items with the stack of the guid holding `count`.
fn restacked(
  items items: List(HeldItem),
  guid guid: Int,
  count count: Int,
) -> List(HeldItem) {
  changed(items:, guid:, with: fn(item) {
    store.HeldItem(..item, stack_count: count)
  })
}

/// The items with `change` made to the item of the guid.
fn changed(
  items items: List(HeldItem),
  guid guid: Int,
  with change: fn(HeldItem) -> HeldItem,
) -> List(HeldItem) {
  list.map(items, fn(item) {
    case item.item_guid == guid {
      True -> change(item)
      False -> item
    }
  })
}

/// The items but the one of the guid.
fn without(items items: List(HeldItem), guid guid: Int) -> List(HeldItem) {
  list.filter(items, fn(item) { item.item_guid != guid })
}

/// What a 0x0182 is answered with.
fn take_move(
  items items: List(HeldItem),
  life life: Life,
  tables tables: table_store.Tables,
  wearer wearer: Wearer,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  use move <- result.try(
    item_move.decode(body)
    |> client_connection.decoded(message_id: item_move.message_id)
    |> result.map_error(NotDecoded),
  )
  let source = held_at(items:, place: move.from)
  let destination = held_at(items:, place: move.to)
  case checked(life:, items:, tables:, wearer:, move:, source:, destination:) {
    Error(Broken(refusal:)) -> Error(refusal)
    Error(Code(code:)) -> refused_with(item: source, code:)
    Error(Unread(item2_id:, prerequisite_type:)) ->
      Ok(
        Refused([
          Log(
            level: LogWarning,
            text: "the item is not worn: Item2 "
              <> int.to_string(item2_id.value)
              <> " needs a prerequisite on PrerequisiteType "
              <> int.to_string(prerequisite_type)
              <> ", which the server does not read, so it is refused with the client's code 144",
          ),
          Send(failed(
            guid: result.map(source, fn(item) { item.item_guid })
              |> result.unwrap(0),
            code: equip_requirement.prerequisite_failed,
          )),
        ]),
      )
    Ok(item) ->
      case merge(items:, tables:, item:, destination:) {
        Error(refusal) -> Error(refusal)
        Ok(Some(merging)) -> Ok(Asks(merging))
        Ok(None) -> Ok(Asks(moving(items:, move:, item:, destination:)))
      }
  }
}

/// The merge a move makes when it lands on a stack of the same Item2 that
/// stacks and has room under the Item2's maxStackCount: as much of the moved
/// stack as fits goes onto it (the drop handler 0x1406d50f0 sends such a drop
/// as a 0x182, and a drop on any other occupied slot as the same message, which
/// swaps). `None` for a move that swaps. An item with no row in the tables is
/// no answer at all.
fn merge(
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  item item: HeldItem,
  destination destination: Result(HeldItem, Nil),
) -> Result(Option(Moving), Refusal) {
  case destination {
    Ok(target) if target.item2_id == item.item2_id -> {
      use limit <- result.map(
        item_property.stack_limit(tables:, item2_id: item.item2_id.value)
        |> result.replace_error(NoItemRow(item2_id: item.item2_id)),
      )
      case limit {
        Some(maximum) if target.stack_count < maximum ->
          Some(merged(
            items:,
            source: item,
            target:,
            count: int.min(item.stack_count, maximum - target.stack_count),
          ))
        Some(_) | None -> None
      }
    }
    Ok(_) | Error(Nil) -> Ok(None)
  }
}

/// The ask and the answer of `count` of the stack `source` put onto the stack
/// `target`: the target is raised and the source goes when none of it is left.
fn merged(
  items items: List(HeldItem),
  source source: HeldItem,
  target target: HeldItem,
  count count: Int,
) -> Moving {
  let raised =
    restacked(items:, guid: target.item_guid, count: target.stack_count + count)
  let left = source.stack_count - count
  Moving(
    guid: source.item_guid,
    change: Merged(source:, target:, count:),
    items: case left {
      0 -> without(items: raised, guid: source.item_guid)
      _ -> restacked(items: raised, guid: source.item_guid, count: left)
    },
  )
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

/// The item the move moves, or the first check the move breaks, in the client's
/// order (this module's doc).
fn checked(
  life life: Life,
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  wearer wearer: Wearer,
  move move: item_move.ItemMove,
  source source: Result(HeldItem, Nil),
  destination destination: Result(HeldItem, Nil),
) -> Result(HeldItem, Stop) {
  let from = move.from
  let to = move.to
  use <- bool.guard(
    when: player_life.state(life:) == player_life.Dead,
    return: Error(Code(cant_do_while_dead)),
  )
  use <- bool.guard(
    when: to.location >= 100 && to.location <= 299,
    return: Error(Code(item_locked)),
  )
  use item <- result.try(result.replace_error(source, Code(params)))
  use <- bool.guard(
    when: from == to
      || to.location >= 300
      || out_of_equipped_range(from)
      || out_of_equipped_range(to),
    return: Error(Code(params)),
  )
  use <- bool.guard(
    when: player_life.in_combat(life:)
      && { from.location == equipped || to.location == equipped },
    return: Error(Code(cannot_while_in_combat)),
  )
  use <- bool.guard(
    when: closed(from) || closed(to),
    return: Error(Code(player_busy)),
  )
  use <- bool.guard(
    when: to.location == in_bags && to.bag_index >= inventory_slots,
    return: Error(Code(params)),
  )
  use <- bool.guard(
    when: to.location == in_bags && to.bag_index >= usable_inventory_size,
    return: Error(Code(bag_too_small)),
  )
  use Nil <- result.try(wearable_at(
    items:,
    tables:,
    wearer:,
    item:,
    from:,
    to:,
    other: destination,
  ))
  use Nil <- result.try(case destination {
    Ok(other) ->
      wearable_at(
        items:,
        tables:,
        wearer:,
        item: other,
        from: to,
        to: from,
        other: Ok(item),
      )
    Error(Nil) -> Ok(Nil)
  })
  use <- bool.guard(
    when: to.location >= 3 && to.location <= 99,
    return: Error(Code(params)),
  )
  Ok(item)
}

/// The equipped slots end at index 30; the client's delete sends nothing for a
/// place past it either (0x1403c1360).
fn out_of_equipped_range(place: ItemPlace) -> Bool {
  place.location == equipped && place.bag_index > 30
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

/// The checks of one item going from a place to another, in the client's order
/// (0x1403ad100): the unique check, then, for an equipped destination, the slot
/// fit and the requirements. `other` is the item held at the destination, which
/// the move gives the place the item leaves.
///
/// Not built: the client's loop that refuses an item whose runes are of a kind
/// another worn item holds (rune-unique); it waits for the issue "Items,
/// equipment, vendors, levels and currency work on the real client".
fn wearable_at(
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  wearer wearer: Wearer,
  item item: HeldItem,
  from from: ItemPlace,
  to to: ItemPlace,
  other other: Result(HeldItem, Nil),
) -> Result(Nil, Stop) {
  let broken = Broken(NoItemRow(item2_id: item.item2_id))
  let item2_id = item.item2_id.value
  let entering = equip_like(to) && !equip_like(from)
  let same_as_other = case other {
    Ok(held) -> held.item2_id == item.item2_id
    Error(Nil) -> False
  }
  use unique_equipped <- result.try(case entering && !same_as_other {
    True ->
      item_property.is_unique_equipped(tables:, item2_id:)
      |> result.replace_error(broken)
    False -> Ok(False)
  })
  let worn_already =
    list.any(items, fn(held) {
      held.location == equipped && held.item2_id == item.item2_id
    })
  use <- bool.guard(
    when: unique_equipped && worn_already,
    return: Error(Code(item_unique)),
  )
  use <- bool.guard(when: to.location != equipped, return: Ok(Nil))
  use slotted <- result.try(
    item_property.is_slotted(tables:, item2_id:) |> result.replace_error(broken),
  )
  use flags <- result.try(
    item_property.equipped_slot_flags(tables:, item2_id:)
    |> result.replace_error(broken),
  )
  let bit = int.bitwise_shift_left(1, to.bag_index)
  use <- bool.guard(
    when: !slotted
      || { to.bag_index >= 17 && to.bag_index <= 20 }
      || int.bitwise_and(flags, bit) == 0,
    return: Error(Code(not_valid_for_slot)),
  )
  case equip_requirement.check(tables:, item2_id: item.item2_id, wearer:) {
    Error(_) -> Error(broken)
    Ok(equip_requirement.Wearable) -> Ok(Nil)
    Ok(equip_requirement.Refused(code:)) -> Error(Code(code))
    Ok(equip_requirement.PrerequisiteNotRead(prerequisite_type:)) ->
      Error(Unread(item2_id: item.item2_id, prerequisite_type:))
  }
}

/// Whether the place is one the client's move check treats as equipping.
fn equip_like(place: ItemPlace) -> Bool {
  list.contains(equip_like_locations, place.location)
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
        change: Moved(
          moves: [first],
          moved: frame_of_move(guid: item.item_guid, place: to),
        ),
        items: relocated(items:, guid: item.item_guid, to: to_place),
      )
    Ok(other) ->
      Moving(
        guid: item.item_guid,
        change: Moved(
          moves: [
            first,
            store.ItemMove(
              item_guid: other.item_guid,
              from: to_place,
              to: from_place,
            ),
          ],
          moved: frame_of_swap(first: #(item.item_guid, to), second: #(
            other.item_guid,
            from,
          )),
        ),
        items: items
          |> relocated(guid: item.item_guid, to: to_place)
          |> relocated(guid: other.item_guid, to: from_place),
      )
  }
}

/// The items with the item of the guid held at the place.
fn relocated(
  items items: List(HeldItem),
  guid guid: Int,
  to place: store.ItemPlace,
) -> List(HeldItem) {
  changed(items:, guid:, with: fn(item) {
    store.HeldItem(..item, location: place.location, bag_index: place.bag_index)
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

/// 0x111 for an item the character holds, with no charges and full durability,
/// added for `reason`. Every value the client's code does not name is 0
/// (`opcode.0x111.shared_item_unnamed`), the lists empty.
pub fn item_added_frame(
  item_guid item_guid: Int,
  item_id item_id: Int,
  location location: Int,
  bag_index bag_index: Int,
  stack_count stack_count: Int,
  reason reason: Int,
) -> Frame {
  let assert Ok(body) =
    item_added.encode(
      ItemAdded(held_item: held_item.HeldItem(
        item: SharedItem(
          item_guid:,
          field_2: 0,
          item_id:,
          location:,
          bag_index:,
          stack_count:,
          charges: 0,
          field_8: 0,
          field_9: 0,
          field_10: 0,
          durability: float32.to_bits(1.0),
          field_12: 0,
          field_13: 0,
          field_14: 0,
          field_15: 0,
          field_16: 0,
          field_17: 0,
          field_18: 0,
          field_19: 0,
          field_20: 0,
          field_21: 0,
          field_22: 0,
          field_23: 0,
          list_a: [],
          list_b: [],
          field_27: 0,
        ),
        reason:,
      )),
    )
    as "an item of 18 bits, a location of 9 and a guid of 64 bits, a character number below 2^23, fit the message"
  Frame(message_id: item_added.message_id, body:)
}

/// The store's request for an accepted change, fenced by the login's epoch.
pub fn request(
  moving moving: Moving,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
) -> store.Request {
  store.Items(case moving.change {
    Moved(moves:, ..) ->
      store.MoveItems(account_id:, character_id:, session_epoch:, moves:)
    Merged(source:, target:, count:) ->
      store.MergeItems(
        account_id:,
        character_id:,
        session_epoch:,
        source:,
        target:,
        count:,
      )
    Split(source:, count:, to:) ->
      store.SplitItem(
        account_id:,
        character_id:,
        session_epoch:,
        source:,
        count:,
        to:,
      )
    Deleted(item:) ->
      store.DeleteItem(account_id:, character_id:, session_epoch:, item:)
  })
}

/// The held items and the effects the store's answer to the change leaves: the
/// items of `moving` and its replies for `ItemsSaved`, or for `ItemMade` the
/// split's, and the items as they were with a log line and 0x56A code 5 for any
/// other answer.
pub fn answered(
  items items: List(HeldItem),
  moving moving: Moving,
  answer answer: ItemsAnswer,
) -> #(List(HeldItem), List(Effect)) {
  case answer {
    ItemsSaved ->
      case moving.change {
        Moved(moved:, ..) -> #(moving.items, [Send(moved)])
        Merged(source:, target:, count:) -> #(moving.items, [
          Send(count_changed(
            guid: target.item_guid,
            count: target.stack_count + count,
          )),
          Send(case count == source.stack_count {
            True -> removed(guid: source.item_guid, reason: stack_split)
            False ->
              count_changed(
                guid: source.item_guid,
                count: source.stack_count - count,
              )
          }),
        ])
        Deleted(item:) -> #(moving.items, [
          Send(removed(guid: item.item_guid, reason: player_requested)),
        ])
        Split(..) -> panic as "the store answers a split with ItemMade"
      }
    ItemMade(item_guid:) ->
      case moving.change {
        Split(source:, count:, to:) -> #(
          list.append(moving.items, [
            store.HeldItem(
              item_guid:,
              item2_id: source.item2_id,
              location: to.location,
              bag_index: to.bag_index,
              stack_count: count,
            ),
          ]),
          [
            Send(count_changed(
              guid: source.item_guid,
              count: source.stack_count - count,
            )),
            Send(item_added_frame(
              item_guid:,
              item_id: source.item2_id.value,
              location: to.location,
              bag_index: to.bag_index,
              stack_count: count,
              reason: stack_split,
            )),
          ],
        )
        Moved(..) | Merged(..) | Deleted(..) ->
          panic as "the store answers only a split with ItemMade"
      }
    ItemsNotSaved -> #(items, [
      Log(
        level: LogWarning,
        text: not_done(moving.change)
          <> ": a later login holds the character, or the items are not where the client has them",
      ),
      Send(failed(guid: moving.guid, code: db_failure)),
    ])
    SaveRefused(constraint:) -> #(items, [
      Log(
        level: LogError,
        text: not_done(moving.change)
          <> ": the store refused the places by the constraint "
          <> constraint,
      ),
      Send(failed(guid: moving.guid, code: db_failure)),
    ])
  }
}

/// What a change that was not saved did not do, for the log.
pub fn not_done(change: Change) -> String {
  case change {
    Moved(..) -> "the item was not moved"
    Split(..) -> "the stack was not split"
    Merged(..) -> "the stacks were not merged"
    Deleted(..) -> "the item was not deleted"
  }
}

/// The 0x17F that gives a held item's stack its new count, with the reason 0.
fn count_changed(guid guid: Int, count count: Int) -> Frame {
  let assert Ok(body) =
    item_count_changed.encode(ItemCountChanged(
      item_guid: guid,
      count:,
      reason: stack_split,
    ))
    as "a guid, a count and a reason of 6 bits fit 0x17F"
  Frame(message_id: item_count_changed.message_id, body:)
}

/// The 0x148 that takes a held item away.
fn removed(guid guid: Int, reason reason: Int) -> Frame {
  let assert Ok(body) =
    item_removed.encode(ItemRemoved(item_guid: guid, reason:))
    as "a guid and a reason of 6 bits fit 0x148"
  Frame(message_id: item_removed.message_id, body:)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoItemRow(item2_id:) ->
      "a held item has no row in the client's tables for its slot: Item2 "
      <> int.to_string(item2_id.value)
  }
}
