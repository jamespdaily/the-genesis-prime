//// A timed item: an item whose Item2 row has an expirationTimeMinutes above 0 (37 rows) is
//// made with the moment its lifetime ends, kept with the item as `HeldItem.words.expires_at_unix_ms`
//// (Unix milliseconds, so the countdown runs in real time, also while its owner is logged
//// out), and removed when that moment comes. This module is the rules; the connection
//// (genesis_prime/game/connection/item_expiry) carries them out.
////
//// ```
//// made (purchase, reward, start)  ─▶ made_at: now + lifetime, or the buyback's kept moment
//// split ─▶ the new stack keeps the source's       merge ─▶ the target keeps the earlier
//// entry: the load deletes what ran out while away ─▶ 0x111 sends time_left_ms (moment - now)
//// the timer for next_deadline fires ─▶ due: earliest first ─▶ DeleteItem ─▶ 0x148 reason 26
//// ```
////
//// - **The time left the client is sent** is the 32-bit value after the refund window in
////   0x111, in milliseconds, 0 for none (`opcode.0x111.time_left`): the client keeps the clock
////   plus the value and counts down by itself, shows "Expires in m:ss" while the difference is
////   above 0 and the row's full lifetime when the value is 0, so a timed item is always sent
////   at least 1 (`time_left_ms`), and the longest lifetime, 28,800 minutes, is below the 2^31
////   milliseconds its difference holds.
//// - **The client removes nothing** and sends nothing when the time is up
////   (`opcode.0x111.time_left`), so the server removes the item with 0x148 reason 26 Expired,
////   which raises ItemRemoved and no notice (`opcode.0x148.expired`).
//// - **The countdown runs offline** (Jim's choice; the client holds no rule on it): the moment
////   is wall-clock, and an item past it at load is deleted before the entry sends its items.
//// - **A split and a merge** keep a moment of the same item: a split copies the source's and a
////   merge keeps the earlier of the two (the server's choice; the client holds no rule).
//// - **A timed row saved before the moment was stored** holds none and never runs out.

import genesis_prime/game/deadline_timer.{type DeadlineTimer}
import genesis_prime/game/item_property
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

/// The reason 0x148 carries for an item that ran out: 26 Expired
/// (`Item.CodeEnumItemUpdateReason`, `opcode.0x148.expired`).
pub const expired_reason = 26

/// The milliseconds a row's item lasts: its minutes times 60,000, 0 for a row that does not
/// run out. Only a missing row is an error.
pub fn lifetime_ms(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Result(Int, item_property.ItemPropertyError) {
  item_property.expiration_minutes(tables:, item2_id: item2_id.value)
  |> result.map(fn(minutes) { minutes * 60_000 })
}

/// The moment a new item runs out: `kept` when the item has one already (an item bought back
/// keeps the moment it had when it was sold), else `now_unix_ms` plus its row's lifetime, none
/// for a row that does not run out.
pub fn made_at(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
  kept kept: Option(Int),
  now_unix_ms now_unix_ms: Int,
) -> Result(Option(Int), item_property.ItemPropertyError) {
  case kept {
    Some(_) -> Ok(kept)
    None ->
      lifetime_ms(tables:, item2_id:)
      |> result.map(fn(lifetime) {
        case lifetime {
          0 -> None
          _ -> Some(now_unix_ms + lifetime)
        }
      })
  }
}

/// The most milliseconds a time left can be for the client's tooltip to read it: its
/// difference is a signed 32-bit number (`opcode.0x111.time_left`).
const longest_time_left_ms = 2_147_483_647

/// The time left the client is sent with an item: 0 for an item that does not run out, else
/// the milliseconds to its moment, never below 1, since the client reads 0 as no countdown, and
/// never above what its tooltip reads, which a clock set back far could otherwise pass.
pub fn time_left_ms(
  expires_at_unix_ms expires_at_unix_ms: Option(Int),
  now_unix_ms now_unix_ms: Int,
) -> Int {
  case expires_at_unix_ms {
    None -> 0
    Some(moment) ->
      int.max(1, moment - now_unix_ms) |> int.min(longest_time_left_ms)
  }
}

/// The earlier of two moments, or the one that exists when only one does: the moment a merged
/// stack keeps.
pub fn earlier(
  first first: Option(Int),
  second second: Option(Int),
) -> Option(Int) {
  case first, second {
    Some(one), Some(other) -> Some(int.min(one, other))
    Some(_), None -> first
    None, _ -> second
  }
}

/// The earliest moment any of the items runs out, none when no item does: the moment the
/// connection's timer is set for.
pub fn next_deadline(items: List(HeldItem)) -> Option(Int) {
  list.fold(items, None, fn(earliest, item) {
    earlier(first: earliest, second: item.words.expires_at_unix_ms)
  })
}

/// The items whose moment is `now_unix_ms` or earlier, earliest first and the lower guid first
/// among the same moment.
pub fn due(
  items items: List(HeldItem),
  now_unix_ms now_unix_ms: Int,
) -> List(HeldItem) {
  list.filter(items, fn(item) {
    case item.words.expires_at_unix_ms {
      Some(moment) -> moment <= now_unix_ms
      None -> False
    }
  })
  |> list.sort(fn(first, second) {
    int.compare(
      option.unwrap(first.words.expires_at_unix_ms, 0),
      option.unwrap(second.words.expires_at_unix_ms, 0),
    )
    |> order.break_tie(int.compare(first.item_guid, second.item_guid))
  })
}

/// What the connection's timer is told when the items change from `before` to `after`: the
/// timer follows the earliest moment of the items held (`deadline_timer.moved`).
pub fn timer_moved(
  before before: List(HeldItem),
  after after: List(HeldItem),
  now_unix_ms now_unix_ms: Int,
) -> List(DeadlineTimer) {
  deadline_timer.moved(
    before: next_deadline(before),
    after: next_deadline(after),
    now_ms: now_unix_ms,
  )
}
