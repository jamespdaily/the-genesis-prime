//// Shared scenes of the timed item tests: the tables with Item2 rows given a lifetime, items
//// held with the moment they run out, and the timer and store effects of a connection step.
//// The rows are the client's own (`fixture_tables`): Item2 12402 is a single item with no
//// charges and 14838 stacks to 50; neither runs out in the client's table
//// (`Item2.expirationTimeMinutes` is 0), so the tests give them a lifetime.

import connection_rule_support as support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{type Request, AskStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/step.{
  type ConnectionStep, type Outcome, CancelTimer, Input, Now, OwnEffect,
  OwnEvent, StartTimer, TimerId,
}
import genesis_prime/store.{type HeldItem, HeldItem}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option, None, Some}
import planted_table.{Integer}

/// The Item2 row of a single item: a stack of 1, no charges.
pub const single = 12_402

/// The Item2 row of a stackable item: stacks to 50, one charge.
pub const stackable = 14_838

/// The connection's timer for the moment a held item runs out (`connection/state`).
pub const timer = TimerId(13)

/// Runs the body on the tables with each row given a lifetime in minutes
/// (`Item2.expirationTimeMinutes`), built on the body's heap.
pub fn tables_with(
  lifetimes lifetimes: List(#(Int, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(lifetimes, fixture_tables.rows(), fn(rows, lifetime) {
      let assert Ok(changed) =
        fixture_tables.change(rows:, table: "Item2", id: lifetime.0, with: [
          #("expirationTimeMinutes", Integer(lifetime.1)),
        ])
        as "the fixture holds the Item2 row and its column"
      changed
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// An item held that runs out at `expires_at_unix_ms`, none for an item that does not.
pub fn held(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  count count: Int,
  expires_at_unix_ms expires_at_unix_ms: Option(Int),
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: count,
    words: store.ItemWords(
      random_stats: 0,
      charges: 0,
      item_flags: 0,
      expires_at_unix_ms:,
    ),
  )
}

/// A single item in the inventory slot, running out at the moment.
pub fn single_in_slot(
  guid guid: Int,
  bag_index bag_index: Int,
  expires_at_unix_ms expires_at_unix_ms: Int,
) -> HeldItem {
  held(
    guid:,
    item2: single,
    location: 1,
    bag_index:,
    count: 1,
    expires_at_unix_ms: Some(expires_at_unix_ms),
  )
}

/// A single item with no moment, which never runs out.
pub fn lasting(guid guid: Int, bag_index bag_index: Int) -> HeldItem {
  held(
    guid:,
    item2: single,
    location: 1,
    bag_index:,
    count: 1,
    expires_at_unix_ms: None,
  )
}

/// The moves of the item expiry timer in the step, in order: ("start", the milliseconds) and
/// ("cancel", 0).
pub fn timers(taken taken: ConnectionStep(Request)) -> List(#(String, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer: started, after_ms:)) if started == timer ->
        Ok(#("start", after_ms))
      OwnEffect(CancelTimer(cancelled)) if cancelled == timer ->
        Ok(#("cancel", 0))
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The store's items request the step asks.
pub fn items_asked(taken taken: ConnectionStep(Request)) -> store.ItemsRequest {
  let assert AskStore(store.Items(request)) =
    game_connection_support.ask_request(taken)
    as "the step asks the store for an items change"
  request
}

/// The item the step's ask deletes.
pub fn deleted_by(taken taken: ConnectionStep(Request)) -> HeldItem {
  let assert store.DeleteItem(item:, ..) = items_asked(taken:)
    as "the step asks the store to delete an item"
  item
}

/// The monotonic time of the connection's entry (`connection_rule_support.now_ms`).
const entry_ms = 1000

/// The Unix milliseconds `after_ms` after the connection's entry, whose system time is
/// `game_connection_support.filetime`.
pub fn unix_at(after_ms after_ms: Int) -> Int {
  support.unix_ms_of_filetime(filetime: game_connection_support.filetime)
  + after_ms
}

/// The clock `after_ms` after the connection's entry: the monotonic time and the system time
/// advance together.
pub fn clock(after_ms after_ms: Int) -> step.Now {
  Now(
    monotonic_ms: entry_ms + after_ms,
    filetime: game_connection_support.filetime + after_ms * 10_000,
  )
}

/// A step of the connection `after_ms` after its entry.
pub fn at(
  state state: game_connection.State,
  after_ms after_ms: Int,
  event event: step.Event(
    step.ConnectionEvent(client_connection.Message, client_connection.Answer),
  ),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, Input(now: clock(after_ms:), event:))
}

/// The client's bytes `after_ms` after the entry.
pub fn read_at(
  state state: game_connection.State,
  bytes bytes: BitArray,
  after_ms after_ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(state:, after_ms:, event: OwnEvent(step.Read(bytes)))
}

/// The timer's firing `after_ms` after the entry.
pub fn fired_at(
  state state: game_connection.State,
  timer timer: step.TimerId,
  after_ms after_ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(state:, after_ms:, event: OwnEvent(step.TimerFired(timer)))
}

/// The answer to the ask the step ends in, `after_ms` after the entry.
pub fn answered_at(
  state state: game_connection.State,
  taken taken: ConnectionStep(Request),
  outcome outcome: Outcome(client_connection.Answer),
  after_ms after_ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  at(state:, after_ms:, event: OwnEvent(step.Answered(ask: ask.ask, outcome:)))
}

/// The connection of the tests' character in the world on these tables, holding these items
/// besides the Novice set, and the step that took it in.
pub fn entered_holding(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.entered_with_quests_and_items_on(
    tables:,
    quests: [],
    items:,
  )
}
