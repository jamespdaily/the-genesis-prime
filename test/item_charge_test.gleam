//// What a use of an item spends (`genesis_prime/game/item_charge`). Expected values come
//// from these places.
//// - `opcode.0x111.charges` and `opcode.0xca`: the client never spends a charge or lowers a
////   count for a use, so the server does; the client reads a stack count of 0 as 1, so a
////   stack at 1 is removed rather than lowered (the check
////   `character_item_stack_count_is_positive` also refuses 0).
//// - `Item2.maxCharges.proxy` and `item_property.max_charges`: a row whose effective
////   maxCharges is 0 holds none, so a use takes nothing from it (the server's choice).
//// - storing-data: a request holds the item as the connection holds it, so the statement
////   changes the row only while it is as held.

import genesis_prime/game/item_charge.{
  ChargeLowered, Gone, NothingToSpend, StackLowered,
}
import genesis_prime/store.{
  type HeldItem, AccountId, CharacterId, DeleteItem, Items, SpendItem,
}
import gleam/list
import gleam/option.{None, Some}
import item_charge_support as support
import owned_test
import qcheck

/// A use of an item with this count and these charges, on a row with this stack limit
/// and this effective maxCharges, spends this.
type Row {
  Row(
    count: Int,
    charges: Int,
    stack_limit: option.Option(Int),
    max_charges: Int,
    spends: item_charge.Spend,
    why: String,
  )
}

pub fn a_use_spends_as_the_stack_or_the_charge_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      Row(
        5,
        1,
        Some(20),
        1,
        StackLowered(4),
        "a stack of 5 loses one from its count",
      ),
      Row(1, 1, Some(20), 1, Gone, "a stack of 1 is removed, not lowered to 0"),
      Row(
        1,
        99,
        None,
        99,
        ChargeLowered(98),
        "a single item with 99 of 99 loses one charge",
      ),
      Row(
        1,
        2,
        None,
        3,
        ChargeLowered(1),
        "a single item with 2 of 3 loses one charge",
      ),
      Row(1, 1, None, 99, Gone, "a single item at its last charge is removed"),
      Row(
        1,
        1,
        None,
        1,
        Gone,
        "a single item of 1 charge is used up by its one use",
      ),
      Row(
        1,
        99,
        Some(1),
        99,
        ChargeLowered(98),
        "a row that stacks one high is a single item",
      ),
      Row(
        1,
        0,
        None,
        0,
        NothingToSpend,
        "a single item with no charges is not consumed",
      ),
      Row(
        5,
        0,
        Some(20),
        0,
        NothingToSpend,
        "a stack with no charges is not consumed",
      ),
    ],
    fn(row) {
      let item =
        support.held(
          guid: 5,
          item2: 2509,
          location: 1,
          bag_index: 0,
          count: row.count,
          charges: row.charges,
        )
      assert item_charge.spend(
          item:,
          stack_limit: row.stack_limit,
          max_charges: row.max_charges,
        )
        == row.spends
        as row.why
    },
  )
}

/// The checks of `character_item` that every saved spend must keep: the count stays at
/// least 1, the charges at least 1 for an item that is kept, and the item is removed only
/// when its last charge or its last of the stack is used.
pub fn a_spend_never_leaves_an_item_that_is_empty_test() -> Nil {
  use <- owned_test.run(10_000)
  qcheck.given(
    qcheck.tuple3(
      qcheck.bounded_int(from: 1, to: 99),
      qcheck.bounded_int(from: 1, to: 9999),
      qcheck.bounded_int(from: 1, to: 99),
    ),
    fn(drawn) {
      let #(count, charges, limit) = drawn
      let item =
        support.held(
          guid: 5,
          item2: 2509,
          location: 1,
          bag_index: 0,
          count:,
          charges:,
        )
      case item_charge.spend(item:, stack_limit: Some(limit), max_charges: 1) {
        StackLowered(stack_count:) -> {
          assert limit > 1 && stack_count == count - 1 && stack_count >= 1
            as "a lowered stack keeps at least 1"
        }
        ChargeLowered(charges: left) -> {
          assert limit == 1 && left == charges - 1 && left >= 1
            as "lowered charges keep at least 1"
        }
        Gone -> {
          assert { limit > 1 && count == 1 } || { limit == 1 && charges == 1 }
            as "an item goes only with its last of the stack or last charge"
        }
        NothingToSpend -> {
          panic as "an item with maxCharges 1 is always spent"
        }
      }
    },
  )
}

pub fn a_spend_asks_the_store_with_the_item_as_held_test() -> Nil {
  use <- owned_test.run(10_000)
  let stack =
    support.held(
      guid: 20,
      item2: 1039,
      location: 1,
      bag_index: 3,
      count: 5,
      charges: 1,
    )
  let single =
    support.held(
      guid: 21,
      item2: 2509,
      location: 1,
      bag_index: 4,
      count: 1,
      charges: 99,
    )
  let asked = fn(item: HeldItem, spend) {
    item_charge.request(
      spend:,
      item:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: support.epoch(),
    )
  }
  assert asked(stack, StackLowered(4))
    == Some(
      Items(SpendItem(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: support.epoch(),
        item: stack,
        stack_count: 4,
        charges: 1,
      )),
    )
    as "a lowered stack names the item as held (guid, place, count 5, charges 1) and the new count with the same charges"
  assert asked(single, ChargeLowered(98))
    == Some(
      Items(SpendItem(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: support.epoch(),
        item: single,
        stack_count: 1,
        charges: 98,
      )),
    )
    as "lowered charges name the item as held and the new charges with the same count"
  assert asked(single, Gone)
    == Some(
      Items(DeleteItem(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: support.epoch(),
        item: single,
      )),
    )
    as "the last charge deletes the item as held, charges included"
  assert asked(single, NothingToSpend) == None
    as "a row with no charges asks nothing"
}
