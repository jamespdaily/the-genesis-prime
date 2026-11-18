//// The rules of a timed item (`genesis_prime/game/item_expiry`): its lifetime, the moment it
//// runs out, the time left the client is sent and which item the connection's timer is set
//// for. Expected values come from these places.
//// - `Item2.expirationTimeMinutes`: the item's lifetime in minutes, 0 for none; 37 of the
////   client's 72,106 rows hold a positive value, the longest 28,800 minutes (20 days).
//// - `opcode.0x111.time_left`: the client keeps its clock plus the value sent and reads 0 as
////   no countdown, showing the row's full lifetime and never counting down, so a timed item
////   is sent at least 1; the tooltip's difference is a signed 32-bit number, so the value is
////   below 2^31 milliseconds.
//// - `0x1404445d0.proxy`: a proxy row (Item2.flags 0x4000) takes its fields from Item2
////   74201, which holds no lifetime.
//// - The moments are Unix milliseconds the tests pass; the merge rule (the earlier moment) and
////   the order of items that run out together (the lower guid first) are the server's own
////   choices, which the rule's doc names.

import client_tables
import game_connection_support
import genesis_prime/game/deadline_timer.{
  CancelDeadlineTimer, StartDeadlineTimer,
}
import genesis_prime/game/item_expiry
import genesis_prime/game/item_property.{NoRow}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import item_expiry_support
import owned_test
import unitest
import world_entry_support

const two_to_the_31 = 2_147_483_648

pub fn the_lifetime_of_each_kind_of_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // 1039 stacks to 20 and 2509 holds a stack of 1: any row serves for its lifetime.
  use tables <- item_expiry_support.tables_with(lifetimes: [
    #(item_expiry_support.single, 30),
    #(item_expiry_support.stackable, 60),
    #(1039, 28_800),
  ])
  let lifetime = fn(item2_id) {
    item_expiry.lifetime_ms(tables:, item2_id: Item2Id(item2_id))
  }
  assert lifetime(item_expiry_support.single) == Ok(1_800_000)
    as "a 30-minute row lasts 1,800,000 ms"
  assert lifetime(item_expiry_support.stackable) == Ok(3_600_000)
    as "a stackable 60-minute row lasts 3,600,000 ms"
  assert lifetime(1039) == Ok(1_728_000_000)
    as "a 28,800-minute row lasts 1,728,000,000 ms, below 2^31"
  assert 1_728_000_000 < two_to_the_31
    as "the longest lifetime fits the tooltip's 31 bits"
  assert lifetime(2509) == Ok(0) as "a row that does not run out lasts 0"
  assert lifetime(999_999_999) == Error(NoRow(table: "Item2", id: 999_999_999))
    as "a row the tables lack is an error, not a lifetime of 0"
  // No row of the Novice set a character starts with runs out, so its start makes no moment.
  assert list.all(
    world_entry_support.novice_items(
      character: game_connection_support.world_character(),
    ),
    fn(item) { lifetime(item.item2_id.value) == Ok(0) },
  )
    as "a character's starting items are made with no moment"
}

pub fn the_clients_timed_rows_are_37_and_each_fits_the_tooltips_31_bits_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = item2.all(tables)
  let timed = list.filter(rows, fn(row) { row.expiration_time_minutes > 0 })
  assert list.length(timed) == 37
    as "Item2.expirationTimeMinutes: 37 of the client's rows hold a positive lifetime"
  assert list.all(rows, fn(row) { row.expiration_time_minutes >= 0 })
    as "no row holds a negative lifetime"
  assert list.all(timed, fn(row) {
    row.expiration_time_minutes * 60_000 < two_to_the_31
  })
    as "opcode.0x111.time_left: the longest lifetime fits the tooltip's signed 32 bits"
  assert list.all(timed, fn(row) { int.bitwise_and(row.flags, 0x4000) == 0 })
    as "0x1404445d0.proxy: no timed row is a proxy, so the own row's column is the client's value"
  let assert Ok(source) = item2.get(tables:, id: Item2Id(74_201))
    as "the proxy source row"
  assert source.expiration_time_minutes == 0
    as "0x1404445d0.proxy: the row a proxy takes its fields from holds no lifetime"
}

pub fn a_new_timed_item_runs_out_one_lifetime_from_now_and_a_bought_back_one_keeps_its_moment_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- item_expiry_support.tables_with(lifetimes: [
    #(item_expiry_support.single, 60),
    #(item_expiry_support.stackable, 1),
  ])
  // An item made at `now` (a purchase, a reward) runs out when its lifetime has passed; an
  // item bought back keeps the moment it had when it was sold, whether it has passed or not,
  // and a row with no lifetime is made with none.
  let cases = [
    // #(Item2, the moment kept, now, the moment made, why)
    #(
      item_expiry_support.single,
      None,
      1000,
      Ok(Some(3_601_000)),
      "a 60-minute row: now plus 3,600,000 ms",
    ),
    #(
      item_expiry_support.stackable,
      None,
      5_000_000,
      Ok(Some(5_060_000)),
      "a 1-minute row: now plus 60,000 ms",
    ),
    #(2509, None, 1000, Ok(None), "a row with no lifetime has no moment"),
    #(
      item_expiry_support.single,
      Some(500_000),
      1000,
      Ok(Some(500_000)),
      "a bought back item keeps the moment it had, not a new lifetime",
    ),
    #(
      item_expiry_support.single,
      Some(500),
      1000,
      Ok(Some(500)),
      "a kept moment already past stays past, so the item is removed at once",
    ),
    #(
      2509,
      Some(42_000),
      1000,
      Ok(Some(42_000)),
      "a kept moment is kept for any row",
    ),
    #(
      999_999_999,
      None,
      1000,
      Error(NoRow(table: "Item2", id: 999_999_999)),
      "a row the tables lack is an error, not a lifetime of 0",
    ),
  ]
  list.each(cases, fn(row) {
    let #(item2_id, kept, now_unix_ms, expected, why) = row
    assert item_expiry.made_at(
        tables:,
        item2_id: Item2Id(item2_id),
        kept:,
        now_unix_ms:,
      )
      == expected
      as why
  })
}

pub fn the_time_sent_is_the_time_left_and_never_0_for_a_timed_item_test() -> Nil {
  use <- owned_test.run(10_000)
  // #(the moment, now, the time sent)
  let cases = [
    #(Some(41_000), 1000, 40_000),
    #(Some(1001), 1000, 1),
    #(Some(1000), 1000, 1),
    #(Some(500), 1000, 1),
    #(Some(1_728_001_000), 1000, 1_728_000_000),
    #(Some(5_000_001_000), 1000, 2_147_483_647),
    #(None, 1000, 0),
  ]
  list.each(cases, fn(row) {
    let #(expires_at_unix_ms, now_unix_ms, expected) = row
    assert item_expiry.time_left_ms(expires_at_unix_ms:, now_unix_ms:)
      == expected
      as "the milliseconds to the moment, at least 1 for a timed item (0 shows the full lifetime and never counts down), 0 for an item that does not run out"
  })
}

pub fn the_earliest_due_item_goes_first_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [
    item_expiry_support.single_in_slot(
      guid: 3,
      bag_index: 2,
      expires_at_unix_ms: 5000,
    ),
    item_expiry_support.single_in_slot(
      guid: 2,
      bag_index: 1,
      expires_at_unix_ms: 3000,
    ),
    item_expiry_support.single_in_slot(
      guid: 1,
      bag_index: 0,
      expires_at_unix_ms: 3000,
    ),
    item_expiry_support.lasting(guid: 4, bag_index: 3),
    item_expiry_support.held(
      guid: 5,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 4,
      count: 20,
      expires_at_unix_ms: Some(7000),
    ),
  ]
  let due = fn(now_unix_ms) {
    list.map(item_expiry.due(items:, now_unix_ms:), fn(item) { item.item_guid })
  }
  assert item_expiry.next_deadline(items) == Some(3000)
    as "the timer is set for the earliest moment"
  assert due(2999) == [] as "nothing is due before the earliest moment"
  assert due(3000) == [1, 2]
    as "at the moment two items that run out together go lower guid first"
  assert due(5000) == [1, 2, 3]
    as "each item whose moment has come, earliest first"
  assert due(99_999) == [1, 2, 3, 5]
    as "a stack is one item, and an item with no moment is never due"
}

pub fn a_split_copies_the_deadline_and_a_merge_keeps_the_earlier_test() -> Nil {
  use <- owned_test.run(10_000)
  // The merge rule: the target keeps the earlier of the two moments, or the one there is.
  let cases = [
    #(Some(5000), Some(9000), Some(5000)),
    #(Some(9000), Some(5000), Some(5000)),
    #(Some(5000), Some(5000), Some(5000)),
    #(None, Some(5000), Some(5000)),
    #(Some(5000), None, Some(5000)),
    #(None, None, None),
  ]
  list.each(cases, fn(row) {
    let #(target, source, expected) = row
    assert item_expiry.earlier(first: target, second: source) == expected
      as "the earlier of the moments present"
  })
}

pub fn the_timer_follows_the_earliest_moment_held_test() -> Nil {
  use <- owned_test.run(10_000)
  // The timer follows the earliest moment held, so a change of the items moves it by the
  // earliest moment before and after.
  let early =
    item_expiry_support.single_in_slot(
      guid: 1,
      bag_index: 0,
      expires_at_unix_ms: 4000,
    )
  let late =
    item_expiry_support.single_in_slot(
      guid: 2,
      bag_index: 1,
      expires_at_unix_ms: 9000,
    )
  let past =
    item_expiry_support.single_in_slot(
      guid: 3,
      bag_index: 2,
      expires_at_unix_ms: 500,
    )
  let none = item_expiry_support.lasting(guid: 4, bag_index: 3)
  // #(items before, items after, now, the timer's moves)
  let cases = [
    #([], [], 1000, []),
    #([none], [none], 1000, []),
    #([], [late], 1000, [StartDeadlineTimer(after_ms: 8000)]),
    #([late], [], 1000, [CancelDeadlineTimer]),
    #([late], [late, none], 1000, []),
    #([late], [late, early], 1000, [
      CancelDeadlineTimer,
      StartDeadlineTimer(after_ms: 3000),
    ]),
    #([early, late], [late], 1000, [
      CancelDeadlineTimer,
      StartDeadlineTimer(after_ms: 8000),
    ]),
    #([], [past], 1000, [StartDeadlineTimer(after_ms: 0)]),
  ]
  list.each(cases, fn(row) {
    let #(before, after, now_unix_ms, expected) = row
    assert item_expiry.timer_moved(before:, after:, now_unix_ms:) == expected
      as "the timer is started for the earliest moment held, moved when it changes, cancelled when none is left, and a moment past starts it in 0 ms"
  })
}
