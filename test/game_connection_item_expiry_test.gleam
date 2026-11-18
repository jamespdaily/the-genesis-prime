//// The game connection's timer for the moment a held item runs out
//// (`genesis_prime/game/connection/item_expiry`, `genesis_prime/game/item_expiry`): one timer,
//// set for the earliest moment of the items held, moved by every change of them, and on its
//// firing the earliest item that is due is deleted as the player's own delete is, with
//// the reason Expired. Expected values come from these places.
//// - `opcode.0x148.expired`: the removal is 0x148 with the reason 26 (Expired), which the client
////   raises as ItemRemoved and shows nothing for; the client itself removes nothing when the
////   time is up (`opcode.0x111.time_left`).
//// - `opcode.0x111.time_left`: the 0x111 of an item carries the milliseconds to its moment,
////   at least 1.
//// - The clock: the tests' connection enters at the system time
////   `game_connection_support.filetime` and at the monotonic time 1000; each step is
////   `after_ms` after that, on both clocks (`item_expiry_support.clock`), so a moment is
////   `item_expiry_support.unix_at(after_ms)`.
//// - The server's own choices, marked as guesses in the rules: a stack keeps the earlier moment
////   of what was put in it; an item bought back keeps the moment it had when it was sold (the
////   countdown does not stop on the buyback list); a refused removal tries again after
////   `movement.save_period_ms`.
//// - Failure table, `item_expiry`'s rows: a firing with nothing due starts the timer again; a
////   store that cannot answer an expiry ends the connection with reason 8.

import character_support
import connection_rule_support as support
import fixture_tables
import game_connection_support
import genesis_prime/account_session.{Claimed}
import genesis_prime/client_connection.{
  type Request, AskStore, FromMap, FromSessions, FromStore,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings} as connection_state
import genesis_prime/game/movement
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_delete
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/item_removed
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/message/vendor_buyback.{VendorBuyback}
import genesis_prime/step.{type ConnectionStep, type Outcome, NoAnswerInTime}
import genesis_prime/store.{
  type HeldItem, DeleteItem, ForItems, Items, ItemsNotSaved, ItemsSaved,
  SaveRefused,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import item_expiry_support
import owned_test
import planted_table.{Integer}
import vendor_support
import world_entry_support

fn saved() -> Outcome(client_connection.Answer) {
  step.Answer(FromStore(ForItems(ItemsSaved)))
}

/// A 0x149 of the item at the inventory slot, inside 0x038C.
fn deleted_at(bag_index bag_index: Int) -> BitArray {
  let assert Ok(body) =
    item_delete.encode(
      item_delete.ItemDelete(place: ItemPlace(location: 1, bag_index:)),
    )
    as "a place fits the message"
  game_connection_support.world_message(
    message_id: item_delete.message_id,
    body:,
  )
}

/// A 0x17D of `count` of the stack of the guid to the empty inventory slot.
fn split_to(
  guid guid: Int,
  bag_index bag_index: Int,
  count count: Int,
) -> BitArray {
  let assert Ok(body) =
    item_split.encode(ItemSplit(
      item_guid: guid,
      to: ItemPlace(location: 1, bag_index:),
      count:,
    ))
    as "a guid, a place and a count fit the message"
  game_connection_support.world_message(
    message_id: item_split.message_id,
    body:,
  )
}

/// The guid and reason of each 0x148 the step wrote.
fn removed_in(taken taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  list.filter_map(game_connection_support.written(taken:), fn(frame: Frame) {
    case frame.message_id == item_removed.message_id {
      True -> {
        let assert Ok(removed) = item_removed.decode(frame.body)
          as "the 0x148 decodes"
        Ok(#(removed.item_guid, removed.reason))
      }
      False -> Error(Nil)
    }
  })
}

/// The word of a stack a sale sold that runs out at the moment.
fn sold_word(
  guid guid: Int,
  expires_at_unix_ms expires_at_unix_ms: Int,
) -> store.SoldWord {
  store.SoldWord(
    item_guid: guid,
    words: store.ItemWords(
      ..store.plain_words,
      expires_at_unix_ms: Some(expires_at_unix_ms),
    ),
  )
}

/// The tables with the stackable and the single row running out after an hour, for the
/// scenes that make timed items.
fn with_timed_rows(body: fn(table_store.Tables) -> a) -> a {
  item_expiry_support.tables_with(
    lifetimes: [
      #(item_expiry_support.single, 60),
      #(item_expiry_support.stackable, 1),
    ],
    body:,
  )
}

/// Three items in the inventory: g101 runs out at 60,000 ms, g102 at 30,000 ms and g103 never.
fn three_items() -> List(HeldItem) {
  [
    item_expiry_support.single_in_slot(
      guid: 101,
      bag_index: 0,
      expires_at_unix_ms: item_expiry_support.unix_at(60_000),
    ),
    item_expiry_support.single_in_slot(
      guid: 102,
      bag_index: 1,
      expires_at_unix_ms: item_expiry_support.unix_at(30_000),
    ),
    item_expiry_support.lasting(guid: 103, bag_index: 2),
  ]
}

pub fn every_change_of_the_held_items_moves_the_timer_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  // The entry starts the timer for the earliest moment: g102's, 30,000 ms away.
  let #(entered, entry) =
    item_expiry_support.entered_holding(tables:, items: three_items())
  assert item_expiry_support.timers(taken: entry) == [#("start", 30_000)]
    as "the entry starts the timer for the earliest moment, 30,000 ms away"
  // The player deletes the earliest, g102, at 5,000 ms: the timer moves to g101's 60,000 ms.
  let #(state, taken) =
    item_expiry_support.read_at(
      state: entered,
      bytes: deleted_at(bag_index: 1),
      after_ms: 5000,
    )
  assert item_expiry_support.timers(taken:) == []
    as "the ask is out: the timer moves with the answer"
  let #(_, answered) =
    item_expiry_support.answered_at(
      state:,
      taken:,
      outcome: saved(),
      after_ms: 5000,
    )
  assert item_expiry_support.timers(taken: answered)
    == [#("cancel", 0), #("start", 55_000)]
    as "the deleted item's moment is no longer the earliest: the timer moves to the next, 60,000 - 5,000 ms"
  // The player deletes the item that never runs out: the timer stays.
  let #(state, taken) =
    item_expiry_support.read_at(
      state: entered,
      bytes: deleted_at(bag_index: 2),
      after_ms: 5000,
    )
  let #(_, answered) =
    item_expiry_support.answered_at(
      state:,
      taken:,
      outcome: saved(),
      after_ms: 5000,
    )
  assert item_expiry_support.timers(taken: answered) == []
    as "an item with no moment is no deadline: the timer is not moved"
  // The last timed item deleted cancels the timer.
  let #(alone, _) =
    item_expiry_support.entered_holding(tables:, items: [
      item_expiry_support.single_in_slot(
        guid: 101,
        bag_index: 0,
        expires_at_unix_ms: item_expiry_support.unix_at(60_000),
      ),
    ])
  let #(state, taken) =
    item_expiry_support.read_at(
      state: alone,
      bytes: deleted_at(bag_index: 0),
      after_ms: 5000,
    )
  let #(_, answered) =
    item_expiry_support.answered_at(
      state:,
      taken:,
      outcome: saved(),
      after_ms: 5000,
    )
  assert item_expiry_support.timers(taken: answered) == [#("cancel", 0)]
    as "no timed item is left, so the timer is cancelled and not started"
  // A purchase of a timed item at the vendor makes it with a moment one lifetime from now (the
  // stackable row lasts a minute), which the store writes with the new row and the client is told
  // as its time left.
  let state = at_the_vendor(tables:, credits: 1000, items: [])
  let #(state, taken) =
    game_connection_support.purchase_requested(
      state:,
      unique_id: 2,
      quantity: 1,
    )
  let assert AskStore(Items(store.BuyFromVendor(make: [made], ..))) =
    game_connection_support.ask_request(taken)
    as "the purchase asks the store to make one stack"
  assert made.words.expires_at_unix_ms
    == Some(item_expiry_support.unix_at(60_000))
    as "the new stack runs out one lifetime, 60,000 ms, from the purchase"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForItems(
            store.Bought(amount: 933, made: [
              item_expiry_support.held(
                guid: 900,
                item2: item_expiry_support.stackable,
                location: made.location,
                bag_index: made.bag_index,
                count: 1,
                expires_at_unix_ms: made.words.expires_at_unix_ms,
              ),
            ]),
          ),
        ),
      ),
    )
  assert item_expiry_support.timers(taken: answered) == [#("start", 60_000)]
    as "the first timed item starts the timer for its lifetime"
  assert item_expiry_support.times_left(taken: answered) == [#(900, 60_000)]
    as "opcode.0x111.time_left: the new item is sent with its whole lifetime"
  // A sale of the only timed item, a stack of 5, takes its moment off the timer.
  let state =
    at_the_vendor(tables:, credits: 1000, items: [
      item_expiry_support.held(
        guid: 104,
        item2: item_expiry_support.stackable,
        location: 1,
        bag_index: 3,
        count: 5,
        expires_at_unix_ms: Some(item_expiry_support.unix_at(25_000)),
      ),
    ])
  let #(state, taken) =
    game_connection_support.sale_requested(
      state:,
      place: ItemPlace(location: 1, bag_index: 3),
      quantity: 5,
    )
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForItems(
            store.Sold(amount: 1100, words: [
              sold_word(
                guid: 104,
                expires_at_unix_ms: item_expiry_support.unix_at(25_000),
              ),
            ]),
          ),
        ),
      ),
    )
  assert item_expiry_support.timers(taken: answered) == [#("cancel", 0)]
    as "the stack sold is no longer held, so its moment is no deadline and the timer is cancelled"
}

pub fn a_split_stack_is_sent_with_its_sources_moment_and_a_merged_one_runs_out_at_the_earlier_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  // The rule (`item_expiry.earlier`) and the store's statements are tested apart; this is
  // what the connection adds: the held items carry the moments on.
  // A stack of 10 that runs out at 50,000 ms, split by 3 to slot 5 at 2,000 ms.
  let stack =
    item_expiry_support.held(
      guid: 104,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 3,
      count: 10,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(50_000)),
    )
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: [stack])
  let #(state, taken) =
    item_expiry_support.read_at(
      state: entered,
      bytes: split_to(guid: 104, bag_index: 5, count: 3),
      after_ms: 2000,
    )
  let #(_, answered) =
    item_expiry_support.answered_at(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(store.ItemMade(item_guid: 204)))),
      after_ms: 2000,
    )
  assert item_expiry_support.timers(taken: answered) == []
    as "the split changes no moment: the earliest is the same"
  assert item_expiry_support.times_left(taken: answered) == [#(204, 48_000)]
    as "opcode.0x111.time_left: the new stack carries the source's moment, 50,000 - 2,000 ms away"
  // A merge of the stack that runs out at 20,000 ms onto the one that runs out at 50,000 ms
  // leaves the target the earlier moment.
  let later = stack
  let earlier =
    item_expiry_support.held(
      guid: 105,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 4,
      count: 5,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(20_000)),
    )
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: [later, earlier])
  let #(state, taken) =
    item_expiry_support.read_at(
      state: entered,
      bytes: game_connection_support.item_moved_message(
        from: ItemPlace(location: 1, bag_index: 4),
        to: ItemPlace(location: 1, bag_index: 3),
      ),
      after_ms: 1000,
    )
  let #(state, _) =
    item_expiry_support.answered_at(
      state:,
      taken:,
      outcome: saved(),
      after_ms: 1000,
    )
  let #(_, firing) =
    item_expiry_support.fired_at(
      state:,
      timer: item_expiry_support.timer,
      after_ms: 20_000,
    )
  assert item_expiry_support.deleted_by(taken: firing)
    == item_expiry_support.held(
      guid: 104,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 3,
      count: 15,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(20_000)),
    )
    as "the target of the merge holds 15 and runs out at the earlier moment, 20,000 ms"
}

fn game_connection_support_epoch() -> store.SessionEpoch {
  character_support.epoch(1)
}

pub fn the_timer_asks_for_the_earliest_due_item_and_the_answer_removes_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  // g102 and g104 run out together at 30,000 ms, g101 at 60,000 ms.
  let items = [
    item_expiry_support.single_in_slot(
      guid: 101,
      bag_index: 0,
      expires_at_unix_ms: item_expiry_support.unix_at(60_000),
    ),
    item_expiry_support.single_in_slot(
      guid: 102,
      bag_index: 1,
      expires_at_unix_ms: item_expiry_support.unix_at(30_000),
    ),
    item_expiry_support.lasting(guid: 103, bag_index: 2),
    item_expiry_support.single_in_slot(
      guid: 104,
      bag_index: 3,
      expires_at_unix_ms: item_expiry_support.unix_at(30_000),
    ),
  ]
  let #(entered, _) = item_expiry_support.entered_holding(tables:, items:)
  // Fired early (the clock is 10,000 ms in): nothing is due, the timer starts again for
  // what is left.
  let #(_, early) =
    item_expiry_support.fired_at(
      state: entered,
      timer: item_expiry_support.timer,
      after_ms: 10_000,
    )
  assert support.asked(early) == None as "an early firing asks nothing"
  assert item_expiry_support.timers(taken: early)
    == [#("cancel", 0), #("start", 20_000)]
    as "a firing before the earliest moment starts the timer again for the 20,000 ms left"
  // On time: the lower guid goes first.
  let #(state, firing) =
    item_expiry_support.fired_at(
      state: entered,
      timer: item_expiry_support.timer,
      after_ms: 30_000,
    )
  assert item_expiry_support.items_asked(taken: firing)
    == DeleteItem(
      account_id: store.AccountId(7),
      character_id: store.CharacterId(42),
      session_epoch: game_connection_support_epoch(),
      item: item_expiry_support.single_in_slot(
        guid: 102,
        bag_index: 1,
        expires_at_unix_ms: item_expiry_support.unix_at(30_000),
      ),
    )
    as "the earliest due item, the lower guid of the two, is asked of the store as a delete"
  assert game_connection_support.written_ids(firing) == []
    as "nothing is written before the store has deleted the item"
  let #(state, answered) =
    item_expiry_support.answered_at(
      state:,
      taken: firing,
      outcome: saved(),
      after_ms: 30_000,
    )
  assert removed_in(taken: answered) == [#(102, 26)]
    as "opcode.0x148.expired: 0x148 for the item with the reason 26"
  assert item_expiry_support.timers(taken: answered)
    == [#("cancel", 0), #("start", 0)]
    as "the second item that runs out at the same moment is due at once: the timer starts in 0 ms"
  let #(state, firing) =
    item_expiry_support.fired_at(
      state:,
      timer: item_expiry_support.timer,
      after_ms: 30_000,
    )
  let #(state, answered) =
    item_expiry_support.answered_at(
      state:,
      taken: firing,
      outcome: saved(),
      after_ms: 30_000,
    )
  assert removed_in(taken: answered) == [#(104, 26)]
  assert item_expiry_support.timers(taken: answered)
    == [#("cancel", 0), #("start", 30_000)]
    as "the timer goes on to g101, 60,000 - 30,000 ms away"
  // A firing that finds nothing due, as the second of two firings does after the first
  // removed the item, starts the timer again.
  let #(_, stale) =
    item_expiry_support.fired_at(
      state:,
      timer: item_expiry_support.timer,
      after_ms: 31_000,
    )
  assert support.asked(stale) == None as "nothing due: nothing asked"
  assert item_expiry_support.timers(taken: stale)
    == [#("cancel", 0), #("start", 29_000)]
    as "a_firing_with_nothing_due_restarts_the_timer: the timer starts again for g101"
}

pub fn a_refused_expiry_keeps_the_item_and_tries_again_later_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  let cases = [
    #(
      ItemsNotSaved,
      "a later login holds the character, or the item is not where the server holds it",
    ),
    #(
      SaveRefused(constraint: "character_item_one_per_slot"),
      "the store refused the change",
    ),
  ]
  list.each(cases, fn(row) {
    let #(answer, why) = row
    let #(entered, _) =
      item_expiry_support.entered_holding(tables:, items: [
        item_expiry_support.single_in_slot(
          guid: 101,
          bag_index: 0,
          expires_at_unix_ms: item_expiry_support.unix_at(30_000),
        ),
      ])
    let #(state, firing) =
      item_expiry_support.fired_at(
        state: entered,
        timer: item_expiry_support.timer,
        after_ms: 30_000,
      )
    let #(state, answered) =
      item_expiry_support.answered_at(
        state:,
        taken: firing,
        outcome: step.Answer(FromStore(ForItems(answer))),
        after_ms: 30_000,
      )
    assert removed_in(taken: answered) == []
      && game_connection_support.written_ids(answered) == []
      as {
        why
        <> ": the item is held and the client is told nothing, not even a 0x56A"
      }
    assert list.any(support.effects_of(answered), fn(effect) {
      case effect {
        step.Log(line) -> support.says(line, "the item was not deleted")
        step.OwnEffect(_) | step.Watch(..) | step.Unwatch(..) | step.Stop ->
          False
      }
    })
      as { why <> ": the refusal is logged" }
    assert item_expiry_support.timers(taken: answered)
      == [#("start", movement.save_period_ms)]
      as {
        why
        <> ": the timer starts again after the save period, so a refusal cannot spin"
      }
    // The item is still held: the next firing asks for it again.
    let #(_, again) =
      item_expiry_support.fired_at(
        state:,
        timer: item_expiry_support.timer,
        after_ms: 30_000 + movement.save_period_ms,
      )
    assert item_expiry_support.deleted_by(taken: again).item_guid == 101
      as { why <> ": the item is asked for again" }
  })
}

pub fn a_store_that_cannot_answer_an_expiry_ends_the_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  let cases = [
    step.Answer(FromStore(store.Unavailable)),
    step.NotRunning,
    NoAnswerInTime,
    step.EndedBeforeAnswer,
  ]
  list.each(cases, fn(outcome) {
    let #(entered, _) =
      item_expiry_support.entered_holding(tables:, items: [
        item_expiry_support.single_in_slot(
          guid: 101,
          bag_index: 0,
          expires_at_unix_ms: item_expiry_support.unix_at(30_000),
        ),
      ])
    let #(state, firing) =
      item_expiry_support.fired_at(
        state: entered,
        timer: item_expiry_support.timer,
        after_ms: 30_000,
      )
    let #(state, answered) =
      item_expiry_support.answered_at(
        state:,
        taken: firing,
        outcome:,
        after_ms: 30_000,
      )
    assert removed_in(taken: answered) == []
      as "no 0x148 is written: nothing says the store deleted the item"
    // The connection ends once it has saved the place it stood at.
    let #(_, ended) =
      game_connection_support.answer(
        state:,
        taken: answered,
        outcome: game_connection_support.place_saved(),
      )
    assert game_connection_support.disconnect(
        ended,
        game_connection_support.keyed(),
      )
      == LostUserServer
      as "the connection ends with 0x036A reason 8, as every item ask"
  })
}

/// The connection holding `items` besides the Novice set and `credits`, with the vendor Dorian
/// Walker's window open, on these tables.
fn at_the_vendor(
  tables tables: table_store.Tables,
  credits credits: Int,
  items items: List(HeldItem),
) -> game_connection.State {
  let fresh =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        tables:,
        vendors: vendor_support.stocking(creature_ids: [74_812]),
      ),
    ).0
  vendor_support.at_the_vendor(
    state: game_connection_support.entered_stocking_holding(
      in_character_select: game_connection_support.in_select_from(fresh),
      credits:,
      items:,
    ),
  )
}

pub fn leaving_cancels_the_timer_and_saves_no_item_time_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  // The moment is saved with the item (the store's statements write it), so the place's save
  // carries no item time; the camp's save is the place's, and leaving cancels the timer.
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: three_items())
  let #(state, started) =
    item_expiry_support.read_at(
      state: entered,
      bytes: game_connection_support.camp_request_message(True),
      after_ms: 1000,
    )
  let #(state, saving) =
    item_expiry_support.read_at(
      state:,
      bytes: game_connection_support.camp_finished_message(),
      after_ms: 13_000,
    )
  let assert AskStore(store.Move(store.SavePlace(..))) =
    game_connection_support.ask_request(saving)
    as "the camp's end asks the store to save the place"
  let #(left_state, left) =
    item_expiry_support.answered_at(
      state:,
      taken: saving,
      outcome: game_connection_support.place_saved(),
      after_ms: 13_000,
    )
  let #(_, camped_out) =
    item_expiry_support.answered_at(
      state: left_state,
      taken: left,
      outcome: step.Answer(FromMap(map.Left)),
      after_ms: 13_000,
    )
  assert list.contains(
    list.flatten([
      item_expiry_support.timers(taken: started),
      item_expiry_support.timers(taken: saving),
      item_expiry_support.timers(taken: left),
      item_expiry_support.timers(taken: camped_out),
    ]),
    #("cancel", 0),
  )
    as "leaving the world cancels the item expiry timer with the others"
}

pub fn a_firing_in_a_busy_status_is_held_until_it_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  // The moment of g104 (a stack of 10 in slot 3) comes at 30,000 ms, while the connection waits
  // on the store in each status that returns the player to the world: the firing is held, and
  // taken once the answer has put the player back.
  // SpendingCharge and TurningIn are tried in `game_connection_item_charges_test` and
  // `game_connection_quest_turn_in_test`, whose scenes they need.
  let stack =
    item_expiry_support.held(
      guid: 104,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 3,
      count: 10,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
    )
  let delete_asked = fn(taken) {
    case support.asked(taken) {
      Some(_) -> item_expiry_support.deleted_by(taken:).item_guid == 104
      None -> False
    }
  }
  let held_while = fn(state, taken, answer, why) {
    let #(state, firing) =
      item_expiry_support.fired_at(
        state:,
        timer: item_expiry_support.timer,
        after_ms: 30_000,
      )
    assert support.asked(firing) == None
      && game_connection_support.written_ids(firing) == []
      as { why <> ": the firing is held, so nothing is asked or written" }
    let #(_, answered) =
      item_expiry_support.answered_at(
        state:,
        taken:,
        outcome: answer,
        after_ms: 30_500,
      )
    assert delete_asked(answered)
      as {
        why
        <> ": once the answer has returned the player to the world, the held firing asks for the delete"
      }
  }
  // MovingItem: a split's ask is out.
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: [stack])
  let #(state, taken) =
    item_expiry_support.read_at(
      state: entered,
      bytes: split_to(guid: 104, bag_index: 5, count: 3),
      after_ms: 29_000,
    )
  held_while(
    state,
    taken,
    step.Answer(FromStore(ForItems(store.ItemMade(item_guid: 204)))),
    "MovingItem",
  )
  // SavingPlace: the periodic save's ask is out.
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: [stack])
  let #(state, taken) =
    item_expiry_support.fired_at(
      state: entered,
      timer: connection_state.save_timer,
      after_ms: 29_000,
    )
  held_while(state, taken, game_connection_support.place_saved(), "SavingPlace")
  // Buying: a purchase's ask is out.
  let state = at_the_vendor(tables:, credits: 1000, items: [stack])
  let #(state, taken) =
    game_connection_support.purchase_requested(
      state:,
      unique_id: 1,
      quantity: 1,
    )
  held_while(
    state,
    taken,
    step.Answer(FromStore(ForItems(store.Bought(amount: 1000, made: [])))),
    "Buying",
  )
  // Selling: a sale's ask is out.
  let state = at_the_vendor(tables:, credits: 1000, items: [stack])
  let #(state, taken) =
    game_connection_support.sale_requested(
      state:,
      place: ItemPlace(location: 1, bag_index: 3),
      quantity: 3,
    )
  held_while(
    state,
    taken,
    step.Answer(
      FromStore(
        ForItems(
          store.Sold(amount: 1000, words: [
            sold_word(
              guid: 104,
              expires_at_unix_ms: item_expiry_support.unix_at(30_000),
            ),
          ]),
        ),
      ),
    ),
    "Selling",
  )
}

pub fn the_timer_is_cancelled_while_the_connection_waits_to_claim_and_started_again_when_claimed_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_timed_rows
  let #(entered, _) =
    item_expiry_support.entered_holding(tables:, items: three_items())
  // Sessions ends at 4,000 ms after the entry (watch 1 is the rule's watch on it): the wait to
  // claim cancels the timer, and the shell drops a firing already waiting.
  let #(waiting, taken) =
    item_expiry_support.at(
      state: entered,
      after_ms: 4000,
      event: step.WatchEnded(step.WatchId(1)),
    )
  assert item_expiry_support.timers(taken:) == [#("cancel", 0)]
    as "the wait to claim cancels the item expiry timer"
  let #(claiming, claim) =
    item_expiry_support.fired_at(
      state: waiting,
      timer: step.TimerId(1),
      after_ms: 4100,
    )
  // Claimed 4,200 ms in: g102 runs out at 30,000 ms, so 25,800 ms are left.
  let claimed = fn(after_ms) {
    item_expiry_support.answered_at(
      state: claiming,
      taken: claim,
      outcome: step.Answer(FromSessions(Claimed)),
      after_ms:,
    )
  }
  let #(_, taken) = claimed(4200)
  assert item_expiry_support.timers(taken:) == [#("start", 25_800)]
    as "the claim starts the timer again for the earliest moment"
  // Claimed after the moment passed during the wait: the timer starts at once.
  let #(back, taken) = claimed(40_000)
  assert item_expiry_support.timers(taken:) == [#("start", 0)]
    as "a moment that passed during the wait is due at once"
  let #(_, firing) =
    item_expiry_support.fired_at(
      state: back,
      timer: item_expiry_support.timer,
      after_ms: 40_000,
    )
  assert item_expiry_support.deleted_by(taken: firing).item_guid == 102
    as "the item is removed as soon as the connection is back in the world"
}

/// The held stack of 5 of Item2 20791 that runs out at 25,000 ms, in slot 0, which the buyback
/// tests sell whole at Dorian Walker.
fn the_stack_sold() -> HeldItem {
  item_expiry_support.held(
    guid: 500,
    item2: 20_791,
    location: 1,
    bag_index: 0,
    count: 5,
    expires_at_unix_ms: Some(item_expiry_support.unix_at(25_000)),
  )
}

/// The client's 0x00BB for the entry with this id, inside 0x038C.
fn bought_back(buyback_id buyback_id: Int) -> BitArray {
  let assert Ok(body) = vendor_buyback.encode(VendorBuyback(buyback_id:))
    as "a buyback id of 32 bits fits the message"
  game_connection_support.world_message(
    message_id: vendor_buyback.message_id,
    body:,
  )
}

pub fn a_sold_timed_item_is_bought_back_with_the_time_it_had_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- item_expiry_support.tables_with(lifetimes: [#(20_791, 5)])
  // The cases: the buy back 15,000 ms in, 10,000 ms before the moment, and 40,000 ms in, after it.
  // #(when it is bought back, the time left its 0x111 carries, the timer's moves)
  let cases = [
    #(15_000, 10_000, [#("start", 10_000)]),
    #(40_000, 1, [#("start", 0)]),
  ]
  list.each(cases, fn(row) {
    let #(after_ms, time_left, timers) = row
    let state = at_the_vendor(tables:, credits: 1000, items: [the_stack_sold()])
    let #(state, taken) =
      game_connection_support.sale_requested(
        state:,
        place: ItemPlace(location: 1, bag_index: 0),
        quantity: 5,
      )
    let #(state, sold) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: step.Answer(
          FromStore(
            ForItems(
              store.Sold(amount: 1013, words: [
                sold_word(
                  guid: 500,
                  expires_at_unix_ms: item_expiry_support.unix_at(25_000),
                ),
              ]),
            ),
          ),
        ),
      )
    assert item_expiry_support.timers(taken: sold) == [#("cancel", 0)]
      as "the stack sold is no longer held: the timer is cancelled"
    let #(state, taken) =
      item_expiry_support.read_at(
        state:,
        bytes: bought_back(buyback_id: 1),
        after_ms:,
      )
    let assert AskStore(Items(store.BuyFromVendor(make: [made], ..))) =
      game_connection_support.ask_request(taken)
      as "the buy back asks the store to make the stack again"
    assert made.words.expires_at_unix_ms
      == Some(item_expiry_support.unix_at(25_000))
      as "the stack is made with the moment it had when it was sold, not a new lifetime: the countdown does not stop on the buyback list"
    let #(_, answered) =
      item_expiry_support.answered_at(
        state:,
        taken:,
        outcome: step.Answer(
          FromStore(
            ForItems(
              store.Bought(amount: 1000, made: [
                item_expiry_support.held(
                  guid: 900,
                  item2: 20_791,
                  location: made.location,
                  bag_index: made.bag_index,
                  count: 5,
                  expires_at_unix_ms: made.words.expires_at_unix_ms,
                ),
              ]),
            ),
          ),
        ),
        after_ms:,
      )
    assert item_expiry_support.times_left(taken: answered)
      == [#(900, time_left)]
      as "opcode.0x111.time_left: the time left to the same moment, at least 1 once it has passed"
    assert item_expiry_support.timers(taken: answered) == timers
      as "the timer is set for the moment, in 0 ms when it has passed"
  })
}

/// The boots the tests' character wears, at worn slot 4.
fn boots() -> HeldItem {
  let assert Ok(item) =
    list.find(novice_items(), fn(item) {
      item.location == 0 && item.bag_index == 4
    })
    as "the Engineer's set has boots in worn slot 4"
  item
}

fn novice_items() -> List(HeldItem) {
  world_entry_support.novice_items(
    character: game_connection_support.world_character(),
  )
}

pub fn a_worn_timed_item_that_expires_leaves_as_a_delete_does_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case is the held item that runs out at 30,000 ms: the boots worn in slot 4 (the 37
  // timed rows of the client have no worn slot, and the moment is on the item, not the row), a
  // stack of 5 in a bag, an item in the bank.
  let worn =
    store.HeldItem(
      ..boots(),
      words: store.ItemWords(
        ..boots().words,
        expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
      ),
    )
  let in_the_set =
    list.map(novice_items(), fn(item) {
      case item.item_guid == worn.item_guid {
        True -> worn
        False -> item
      }
    })
  let others = [
    item_expiry_support.held(
      guid: 301,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 0,
      count: 5,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
    ),
    item_expiry_support.held(
      guid: 302,
      item2: item_expiry_support.single,
      location: 2,
      bag_index: 0,
      count: 1,
      expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
    ),
  ]
  // #(name, held items, the item that runs out, the ids of the frames of the answer, why)
  let cases = [
    #(
      "a worn item",
      in_the_set,
      worn,
      [0x0148, 0x0933, 0x093A],
      "the delete's 0x148, then the look, then the properties: the gear is worked out again as a delete does",
    ),
    #(
      "a stack of 5 in a bag",
      list.append(novice_items(), others),
      item_expiry_support.held(
        guid: 301,
        item2: item_expiry_support.stackable,
        location: 1,
        bag_index: 0,
        count: 5,
        expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
      ),
      [0x0148],
      "the whole stack goes with one 0x148",
    ),
    #(
      "an item in the bank",
      list.append(novice_items(), list.drop(others, 1)),
      item_expiry_support.held(
        guid: 302,
        item2: item_expiry_support.single,
        location: 2,
        bag_index: 0,
        count: 1,
        expires_at_unix_ms: Some(item_expiry_support.unix_at(30_000)),
      ),
      [0x0148],
      "a banked item goes too",
    ),
  ]
  list.each(cases, fn(row) {
    let #(name, items, item, frame_ids, why) = row
    let state =
      game_connection_support.entered_with_items_and_quests(items:, quests: [])
    let #(state, firing) =
      item_expiry_support.fired_at(
        state:,
        timer: item_expiry_support.timer,
        after_ms: 30_000,
      )
    assert item_expiry_support.deleted_by(taken: firing) == item
      as { name <> ": the whole stack is asked of the store as a delete" }
    let #(_, answered) =
      item_expiry_support.answered_at(
        state:,
        taken: firing,
        outcome: saved(),
        after_ms: 30_000,
      )
    assert list.take(
        game_connection_support.written_ids(answered),
        list.length(frame_ids),
      )
      == frame_ids
      as { name <> ": " <> why }
    assert removed_in(taken: answered) == [#(item.item_guid, 26)]
      as { name <> ": the 0x148 carries the reason 26, Expired" }
  })
  // The row's own flag that refuses the player's delete (Item2.flags 0x10000) does not stop the
  // expiry: it refuses the player's action, not an item that ran out.
  let assert Ok(row) =
    item2.get(
      tables: fixture_tables.shared(),
      id: Item2Id(item_expiry_support.single),
    )
    as "the fixture holds the single item's row"
  use tables <- fixture_tables.changed(
    table: "Item2",
    id: item_expiry_support.single,
    with: [#("flags", Integer(int.bitwise_or(row.flags, 0x10000)))],
  )
  let kept =
    item_expiry_support.single_in_slot(
      guid: 303,
      bag_index: 0,
      expires_at_unix_ms: item_expiry_support.unix_at(30_000),
    )
  let #(state, _) = item_expiry_support.entered_holding(tables:, items: [kept])
  let #(state, firing) =
    item_expiry_support.fired_at(
      state:,
      timer: item_expiry_support.timer,
      after_ms: 30_000,
    )
  assert item_expiry_support.deleted_by(taken: firing) == kept
    as "an item the player cannot delete still expires"
  let #(_, answered) =
    item_expiry_support.answered_at(
      state:,
      taken: firing,
      outcome: saved(),
      after_ms: 30_000,
    )
  assert removed_in(taken: answered) == [#(303, 26)]
    as "its 0x148 carries the reason 26"
}
