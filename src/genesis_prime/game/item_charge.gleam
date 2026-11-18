//// What a use of an item spends, as a pure rule on the held item, and the cast a use holds
//// back until the store has saved the spend.
////
//// ```
//// 0x943 ─▶ cast.use_item ─ refused, or an id already taken ─▶ Frames: written at once
////                        └ a cast started ─▶ Started(press, cast', effects), all held
////    ─▶ spend(item, stack limit, max charges)
////         NothingToSpend (Item2.maxCharges 0) ─▶ cast' adopted, effects released, nothing asked
////         StackLowered | ChargeLowered         ─▶ ask SpendItem
////         Gone                                 ─▶ ask DeleteItem
////    ─▶ the store's answer (genesis_prime/game/connection/item_spend)
////         ItemsSaved                ─▶ the inventory frame, then cast' adopted, then the effects
////         ItemsNotSaved | SaveRefused ─▶ 0x7fc result 1; the item and the cast are as before
////         the store away, past its deadline, or the connection ended ─▶ the connection ends
//// ```
////
//// - **The client never spends a charge** and never lowers a stack for a use: only 0x111
////   and 0xca write the charges, only 0x17f the count (`opcode.0x111.charges`,
////   `opcode.0xca`), so the server spends and tells.
//// - **A stack loses one from its count** and keeps its charges (every charged stackable
////   row has maxCharges 1; an item that stacks one high is a single item); **a single item
////   loses one charge**; at the last of either the
////   item is removed with 0x148 reason 1, because the client reads a count of 0 as 1.
//// - **A row with maxCharges 0 is not spent** (`item_property.max_charges`, which takes a
////   proxy row's from its source row, `Item2.maxCharges.proxy`).
//// - **The spend is saved before it is shown** and the cast's effects follow the frame, so
////   a crash before the save leaves the cast unreleased and the charge as it was, and a
////   crash after it leaves the stored charge for the next login's 0x111 to send.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/inventory
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type SessionEpoch, HeldItem,
}
import gleam/list
import gleam/option.{type Option, None, Some}

/// What a use does to the item it spends.
pub type Spend {
  /// The item's row holds no charges, so the use takes nothing from it.
  NothingToSpend
  /// The stack has more than one: its count goes to `stack_count`, its charges stay.
  StackLowered(stack_count: Int)
  /// The single item has more than one charge: they go to `charges`, its count stays 1.
  ChargeLowered(charges: Int)
  /// The use takes the last of the stack or the last charge: the item is removed.
  Gone
}

/// A use whose cast is held back until the store answers the spend: the press, the held
/// item as it was, what the use spends, and the state and effects of the cast it started,
/// which the connection applies after the answer (`cast_state.Started`).
pub type Spending {
  Spending(
    press: cast_state.ItemPress,
    item: HeldItem,
    spend: Spend,
    cast: cast_state.State,
    effects: List(cast_state.Effect),
  )
}

/// What one use of `item` spends. `stack_limit` is the row's Item2.maxStackCount when the
/// item stacks (`item_property.stack_limit`), `max_charges` the client's effective maxCharges
/// of the row (`item_property.max_charges`). An item that stacks more than one high loses one
/// from its count; any other loses one charge. The item holds at least one charge when
/// `max_charges` is above 0: the use check refuses it first (result 25).
pub fn spend(
  item item: HeldItem,
  stack_limit stack_limit: Option(Int),
  max_charges max_charges: Int,
) -> Spend {
  case max_charges > 0, stack_limit {
    False, _ -> NothingToSpend
    True, Some(limit) if limit > 1 ->
      case item.stack_count {
        count if count > 1 -> StackLowered(stack_count: count - 1)
        _ -> Gone
      }
    True, Some(_) | True, None ->
      case item.charges {
        charges if charges > 1 -> ChargeLowered(charges: charges - 1)
        _ -> Gone
      }
  }
}

/// The store's request for the spend, fenced by the login's epoch and holding the item as
/// it is: `SpendItem` for a lowered stack or charge count, `DeleteItem` for `Gone`, none
/// for `NothingToSpend`.
pub fn request(
  spend spend: Spend,
  item item: HeldItem,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
) -> Option(store.Request) {
  case spend {
    NothingToSpend -> None
    StackLowered(stack_count:) ->
      Some(
        store.Items(store.SpendItem(
          account_id:,
          character_id:,
          session_epoch:,
          item:,
          stack_count:,
          charges: item.charges,
        )),
      )
    ChargeLowered(charges:) ->
      Some(
        store.Items(store.SpendItem(
          account_id:,
          character_id:,
          session_epoch:,
          item:,
          stack_count: item.stack_count,
          charges:,
        )),
      )
    Gone ->
      Some(
        store.Items(store.DeleteItem(
          account_id:,
          character_id:,
          session_epoch:,
          item:,
        )),
      )
  }
}

/// The held items after a saved spend, and the frame that tells the client: 0x17f with
/// reason 1 for a lowered stack, 0xca for a lowered charge count, 0x148 with reason 1 for
/// `Gone`, none for `NothingToSpend`.
pub fn spent(
  items items: List(HeldItem),
  item item: HeldItem,
  spend spend: Spend,
) -> #(List(HeldItem), Option(Frame)) {
  let replaced = fn(changed) {
    list.map(items, fn(held) {
      case held.item_guid == item.item_guid {
        True -> changed
        False -> held
      }
    })
  }
  case spend {
    NothingToSpend -> #(items, None)
    StackLowered(stack_count:) -> #(
      replaced(HeldItem(..item, stack_count:)),
      Some(inventory.count_changed_frame(
        guid: item.item_guid,
        count: stack_count,
        reason: inventory.consume_charge,
      )),
    )
    ChargeLowered(charges:) -> #(
      replaced(HeldItem(..item, charges:)),
      Some(inventory.charges_changed_frame(guid: item.item_guid, charges:)),
    )
    Gone -> #(
      list.filter(items, fn(held) { held.item_guid != item.item_guid }),
      Some(inventory.item_removed_frame(
        guid: item.item_guid,
        reason: inventory.consume_charge,
      )),
    )
  }
}
