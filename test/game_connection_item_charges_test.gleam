//// The game connection's spend of an item's charge (`genesis_prime/game/connection/item_spend`):
//// the player's 0x943 of a charged item asks the store to save what the use spends, and
//// the cast's frames wait for the answer. Expected values come from these places.
//// - `opcode.0xca`, `opcode.0x17f` and `opcode.0x148`: the client never spends a charge
////   itself, so the server tells it: a lowered charge count is 0xca (guid, charges), a
////   lowered stack 0x17f (guid, count, reason 1) and the last of either 0x148 (guid, reason 1,
////   `Item.CodeEnumItemUpdateReason` ConsumeCharge).
//// - `opcode.0x7fc`: a cast the server will not start is answered with the client's cast
////   id, the spell and a result; the spend that was not saved is the server's failure, 1
////   (`UnableToCreateSpell`).
//// - The order the coordinator chose: the spend is saved, then the inventory frame is
////   written, then the cast's effects are released (`opcode.0x7fd`, then the go and the
////   finish, `opcode.0x7f4`, `opcode.0x7fe`).
//// - `step.EffectsThenAsk`: the shell takes no input while an ask is out, so a frame the
////   client sent meanwhile is held and taken after the answer.
//// - Failure table, `item_charge`'s rows: a store that is unavailable, past its deadline or
////   gone, or a connection that ends while the ask is out, leaves the outcome unknown: the
////   connection ends with 0x036A reason 8 and nothing of the cast is released.
//// - The items the store holds are the ones a use spends: the real store
////   (`account_store_support`) saves each request under the epoch of a login and a load gives
////   the rows back.
//// Time is the step's own clock: Spell4 26663's spellCoolDown is 2000 ms, so the uses are
//// 5 s apart.

import account_store_support.{type Store}
import character_support
import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Answer, type Request, FromStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/cast_result
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_added
import genesis_prime/message/item_charges_changed
import genesis_prime/message/item_count_changed
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/message/item_removed
import genesis_prime/message/player_health
import genesis_prime/message/spell_cast_refused
import genesis_prime/step.{
  type ConnectionStep, type Outcome, EndedBeforeAnswer, LogError, LogWarning,
  NoAnswerInTime, NotRunning, OwnEvent,
}
import genesis_prime/store.{
  type HeldItem, type ItemsRequest, type NewItem, AccountId, CharacterCreated,
  CharacterId, DeleteItem, ForItems, ItemsNotSaved, ItemsSaved, NewItem,
  SaveRefused, SpendItem,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import item_charge_support as support_items
import owned_test
import planted_table.{Integer}

/// Item2 1039, a stackable item (it holds 20) of the client's tables, given the grenade's
/// spell (ItemSpecial 4363) and one charge for these tests.
const the_stack_row = 1039

const grenade_special = 4363

const single_place = ItemPlace(location: 1, bag_index: 0)

const stack_place = ItemPlace(location: 1, bag_index: 1)

/// The tables with the grenade holding at most 3 charges and Item2 1039 casting the
/// grenade's spell with one.
fn with_charged_rows(body: fn(table_store.Tables) -> a) -> a {
  charged_rows(cast_time_ms: None, cooldown_ms: 0, body:)
}

/// `with_charged_rows` with Spell4 26663's spellCoolDown changed to `cooldown_ms` (0 lets a
/// second use at once through, a use inside the cooldown is refused 15) and its castTime
/// to `cast_time_ms` when given, so its go waits for a timer.
fn charged_rows(
  cast_time_ms cast_time_ms: Option(Int),
  cooldown_ms cooldown_ms: Int,
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Item2",
      id: support_items.grenade,
      with: [#("maxCharges", Integer(3))],
    )
    as "Item2 12444 is in the fixture"
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Item2", id: the_stack_row, with: [
      #("maxCharges", Integer(1)),
      #("itemSpecialId00", Integer(grenade_special)),
    ])
    as "Item2 1039 is in the fixture"
  let assert Ok(rows) =
    fixture_tables.change(
      rows:,
      table: "Spell4",
      id: support_items.grenade_spell,
      with: list.flatten([
        [#("spellCoolDown", Integer(cooldown_ms))],
        case cast_time_ms {
          Some(cast_time_ms) -> [#("castTime", Integer(cast_time_ms))]
          None -> []
        },
      ]),
    )
    as "Spell4 26663 is in the fixture"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The grenade with this many charges at {1, 0}.
fn single(charges charges: Int) -> HeldItem {
  support_items.held(
    guid: 4_000_001,
    item2: support_items.grenade,
    location: 1,
    bag_index: 0,
    count: 1,
    charges:,
  )
}

/// A stack of this many of the stack row, each with one charge, at {1, 1}.
fn stack(count count: Int) -> HeldItem {
  support_items.held(
    guid: 4_000_002,
    item2: the_stack_row,
    location: 1,
    bag_index: 1,
    count:,
    charges: 1,
  )
}

/// A press of the item at `place` with this client cast id, at `ms`.
fn pressed(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
  place place: ItemPlace,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(step.Read(support_items.press(client_cast_id:, place:))),
  )
}

/// The store's answer to the ask in the step, at `ms`.
fn answered_at(
  state state: game_connection.State,
  taken taken: ConnectionStep(Request),
  outcome outcome: Outcome(Answer),
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(step.Answered(ask: ask.ask, outcome:)),
  )
}

fn saved() -> Outcome(Answer) {
  step.Answer(FromStore(ForItems(ItemsSaved)))
}

fn ids(taken taken: ConnectionStep(Request)) -> List(Int) {
  connection_support.written_ids(taken)
}

/// The first frame with this message id.
fn frame_of(
  taken taken: ConnectionStep(Request),
  message_id message_id: Int,
) -> Frame {
  let assert [frame, ..] =
    list.filter(connection_support.written(taken:), fn(frame) {
      frame.message_id == message_id
    })
    as "the step wrote the message"
  frame
}

/// The 0x7fc the step wrote: the client cast id, the spell and the result.
fn refusal_of(taken taken: ConnectionStep(Request)) -> #(Int, Int, Int) {
  let assert Ok(refused) =
    spell_cast_refused.decode(frame_of(taken:, message_id: 0x07FC).body)
    as "the 0x7fc decodes"
  #(
    refused.client_cast_id,
    refused.spell4_id,
    cast_result.to_value(refused.result),
  )
}

/// What the inventory frame at the head of a saved spend's answer tells.
type Told {
  Charges(guid: Int, charges: Int)
  Count(guid: Int, count: Int, reason: Int)
  Removed(guid: Int, reason: Int)
}

fn told_by(frame frame: Frame) -> Told {
  case frame.message_id {
    0x00CA -> {
      let assert Ok(changed) = item_charges_changed.decode(frame.body)
        as "the 0xca decodes"
      Charges(guid: changed.item_guid, charges: changed.charges)
    }
    0x017F -> {
      let assert Ok(changed) = item_count_changed.decode(frame.body)
        as "the 0x17f decodes"
      Count(
        guid: changed.item_guid,
        count: changed.count,
        reason: changed.reason,
      )
    }
    0x0148 -> {
      let assert Ok(removed) = item_removed.decode(frame.body)
        as "the 0x148 decodes"
      Removed(guid: removed.item_guid, reason: removed.reason)
    }
    other ->
      panic as {
        "the head of the answer is no inventory frame: " <> int.to_string(other)
      }
  }
}

/// A saved spend of one item: what the store is asked, and what the client is told first.
type Spending {
  Spending(
    items: List(HeldItem),
    place: ItemPlace,
    asks: ItemsRequest,
    told: Told,
    why: String,
  )
}

pub fn the_answer_saved_writes_the_frame_then_releases_the_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  list.each(
    [
      Spending(
        items: [stack(count: 5)],
        place: stack_place,
        asks: SpendItem(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          item: stack(count: 5),
          stack_count: 4,
          charges: 1,
        ),
        told: Count(guid: 4_000_002, count: 4, reason: 1),
        why: "a stack of 5 is lowered to 4 by 0x17f with reason 1 (ConsumeCharge)",
      ),
      Spending(
        items: [single(charges: 3)],
        place: single_place,
        asks: SpendItem(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          item: single(charges: 3),
          stack_count: 1,
          charges: 2,
        ),
        told: Charges(guid: 4_000_001, charges: 2),
        why: "an item of 3 charges holds 2: 0xca",
      ),
      Spending(
        items: [single(charges: 1)],
        place: single_place,
        asks: DeleteItem(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          item: single(charges: 1),
        ),
        told: Removed(guid: 4_000_001, reason: 1),
        why: "the last charge removes the item by 0x148 with reason 1",
      ),
    ],
    fn(row) {
      let state = support_items.seeing_a_shack(tables:, items: row.items)
      let #(state, taken) =
        pressed(state:, client_cast_id: 9, place: row.place, at: 0)
      assert support_items.spend_asked(taken) == row.asks
        as "the spend is asked with the item as held"
      assert ids(taken:) == []
        as "nothing is written before the store has saved the spend: no frame, no cast"
      let #(state, answered) =
        answered_at(state:, taken:, outcome: saved(), at: 0)
      assert list.take(ids(taken: answered), 4) |> list.drop(1)
        == [0x07FD, 0x07F4, 0x07FE]
        as "opcode.0x7fd, then the go and the finish of Spell4 26663 (castTime 0): the cast's frames follow the inventory frame"
      let counted = list.drop(ids(taken: answered), 4)
      assert counted != [] && list.all(counted, fn(id) { id == 0x0361 })
        as "opcode.0x361: the count of quest 4743's objectives, which the go raised, comes last: after the inventory frame and the cast's frames"
      let assert [first, ..] = connection_support.written(taken: answered)
      assert told_by(frame: first) == row.told as row.why
      let #(_, again) =
        pressed(state:, client_cast_id: 9, place: row.place, at: 1)
      assert ids(taken: again) == [] && support.asked(again) == None
        as "the press id is recorded once the spend is saved: the same id spends nothing"
    },
  )
}

pub fn a_press_resent_while_its_save_is_pending_is_dropped_after_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  let state = support_items.seeing_a_shack(tables:, items: [single(charges: 3)])
  let #(state, taken) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 0)
  let #(state, held) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 1)
  assert ids(taken: held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the resent 0x943 waits behind the ask"
  let #(state, answered) = answered_at(state:, taken:, outcome: saved(), at: 2)
  assert list.length(list.filter(ids(taken: answered), fn(id) { id == 0x00CA }))
    == 1
    && support.asked(answered) == None
    as "the answer is followed by the held press, which writes nothing and asks nothing: one spend in all"
  let #(_, next) =
    pressed(state:, client_cast_id: 10, place: single_place, at: 5000)
  assert support_items.spend_asked(next)
    == SpendItem(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      item: single(charges: 2),
      stack_count: 1,
      charges: 1,
    )
    as "the item was lowered once: the next press asks with 2 charges held"
}

/// The answers that cancel the cast.
fn refusing_answers() -> List(#(Outcome(Answer), step.LogLevel)) {
  [
    #(step.Answer(FromStore(ForItems(ItemsNotSaved))), LogWarning),
    #(
      step.Answer(FromStore(ForItems(SaveRefused(constraint: "a_check")))),
      LogError,
    ),
  ]
}

pub fn a_refused_spend_cancels_the_cast_and_leaves_the_item_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  // The last row is the delete of the last charge: it is fenced on the held charges too,
  // so a store that finds other charges changes nothing and answers ItemsNotSaved.
  list.each([single(charges: 3), single(charges: 1)], fn(item) {
    list.each(refusing_answers(), fn(answer) {
      let #(outcome, level) = answer
      let state = support_items.seeing_a_shack(tables:, items: [item])
      let #(state, taken) =
        pressed(state:, client_cast_id: 9, place: single_place, at: 0)
      let #(state, answered) = answered_at(state:, taken:, outcome:, at: 0)
      assert ids(taken: answered) == [0x07FC]
        as "only the 0x7fc is written: no inventory frame, no cast frame"
      assert refusal_of(taken: answered) == #(9, support_items.grenade_spell, 1)
        as "opcode.0x7fc: the client's cast id, the item's spell and UnableToCreateSpell"
      assert list.length(support.logs_of(step: answered, level:)) == 1
        as "the refusal is logged once, as an error when the store refused by a constraint"
      let #(_, again) =
        pressed(state:, client_cast_id: 9, place: single_place, at: 5000)
      assert support_items.spend_asked(again)
        == support_items.spend_asked(taken)
        as "the item is as held and the press id was not taken: the same press is a new press and asks the same"
    })
  })
}

pub fn a_store_that_cannot_answer_a_spend_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      NotRunning,
      NoAnswerInTime,
      EndedBeforeAnswer,
    ],
    fn(outcome) {
      let state =
        support_items.seeing_a_shack(tables:, items: [single(charges: 3)])
      let #(state, taken) =
        pressed(state:, client_cast_id: 9, place: single_place, at: 0)
      let #(state, answered) = answered_at(state:, taken:, outcome:, at: 0)
      assert list.length(support.logs_of(step: answered, level: LogError)) == 1
        as "a spend whose outcome is unknown is an error line"
      assert ids(taken: answered) == []
        as "no inventory frame and no cast frame: nothing says whether the charge was spent"
      let #(_, saved) =
        answered_at(
          state:,
          taken: answered,
          outcome: connection_support.place_saved(),
          at: 0,
        )
      assert connection_support.disconnect(saved, connection_support.keyed())
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8"
    },
  )
}

pub fn a_use_sent_while_the_spend_is_out_is_taken_after_its_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  let state =
    support_items.seeing_a_shack(tables:, items: [
      single(charges: 1),
      stack(count: 5),
    ])
  let #(state, taken) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 0)
  let #(state, held) =
    pressed(state:, client_cast_id: 10, place: stack_place, at: 1)
  assert ids(taken: held) == [] && support.asked(held) == None
    as "a second 0x943 of another id waits behind the ask"
  let #(state, answered) = answered_at(state:, taken:, outcome: saved(), at: 2)
  assert support_items.spend_asked(answered)
    == SpendItem(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      item: stack(count: 5),
      stack_count: 4,
      charges: 1,
    )
    as "the held press is taken after the answer and asks to spend the stack"
  let #(state, _) =
    answered_at(state:, taken: answered, outcome: saved(), at: 3)
  let #(_, gone) =
    pressed(state:, client_cast_id: 11, place: single_place, at: 5000)
  assert ids(taken: gone) == [0x07FC] && refusal_of(taken: gone) == #(11, 0, 22)
    as "opcode.0x7fc: the single item was removed by the first answer, so its place holds nothing: ItemBad (22)"
}

pub fn a_map_message_and_a_timer_during_the_spend_are_taken_in_order_after_its_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  let state = support_items.seeing_a_shack(tables:, items: [single(charges: 3)])
  let #(state, taken) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 0)
  // `state.holds_map_messages` and `state.holds_timer`: while the spend is out a message the
  // map sends and the connection's own timer are held, not dropped.
  let #(state, struck) =
    connection_support.at(
      state:,
      ms: 1,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
  assert ids(taken: struck) == [] && support.asked(struck) == None
    as "the strike on the player waits behind the ask"
  let #(state, fired) =
    connection_support.fired_at(
      state:,
      timer: connection_state.save_timer,
      ms: 2,
    )
  assert ids(taken: fired) == [] && support.asked(fired) == None
    as "the save timer waits behind the ask and does not end the connection"
  let #(_, answered) = answered_at(state:, taken:, outcome: saved(), at: 3)
  assert list.take(ids(taken: answered), 4) == [0x00CA, 0x07FD, 0x07F4, 0x07FE]
    as "the spend's frame and the cast's come first"
  assert list.last(ids(taken: answered)) == Ok(player_health.message_id)
    as "the strike is taken after them, its health the last frame"
  let assert Some(ask) = support.asked(answered)
    as "the held save timer is taken after the strike"
  let assert client_connection.AskStore(store.Move(store.SavePlace(..))) =
    ask.request
    as "its ask saves the player's place"
  Nil
}

pub fn a_cast_released_after_a_slow_answer_keeps_its_cooldown_from_the_release_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- charged_rows(cast_time_ms: None, cooldown_ms: 2000, body: _)
  let state = support_items.seeing_a_shack(tables:, items: [single(charges: 3)])
  let #(state, taken) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 0)
  let #(state, _) = answered_at(state:, taken:, outcome: saved(), at: 400)
  // The cooldown (2000 ms) runs from the release at 400 ms and ends at 2400 ms. A press
  // with more than the queue window (500 ms) left is refused 15; one inside the window is
  // held by the server, which an item's use answers 14.
  list.each(
    [
      #(1800, 15, "600 ms left: SpellCooldown (15)"),
      #(2300, 14, "100 ms left, inside the queue window: held, answered 14"),
    ],
    fn(row) {
      let #(at, result, why) = row
      let #(_, again) =
        pressed(state:, client_cast_id: 10, place: single_place, at:)
      assert ids(taken: again) == [0x07FC] as why
      assert refusal_of(taken: again)
        == #(10, support_items.grenade_spell, result)
        as why
    },
  )
}

pub fn a_cast_with_a_cast_time_starts_its_timers_only_after_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- charged_rows(cast_time_ms: Some(1000), cooldown_ms: 0)
  let state = support_items.seeing_a_shack(tables:, items: [single(charges: 3)])
  let #(state, taken) =
    pressed(state:, client_cast_id: 9, place: single_place, at: 0)
  assert connection_support.cast_timers(steps: [taken], ms: 0) == []
    as "the cast's go timer is not started while the spend is out, so it cannot fire before the cast is adopted"
  let #(_, answered) = answered_at(state:, taken:, outcome: saved(), at: 10)
  assert list.length(connection_support.cast_timers(steps: [answered], ms: 10))
    >= 1
    as "the answer releases the cast's effects, its go timer among them"
  assert list.take(ids(taken: answered), 2) |> list.drop(1) == [0x07FD]
    as "opcode.0x7fd follows the inventory frame; the go waits for its timer"
}

// ---- on the real store ----

/// A character the real store holds, with its account.
type Stored {
  Stored(
    store: Store,
    account: store.AccountId,
    character_id: store.CharacterId,
  )
}

/// A stored character holding the Engineer's worn items and these items in its bags.
fn stored_holding(items items: List(NewItem)) -> Stored {
  let store = account_store_support.start_store(pool_size: 2)
  let account =
    account_store_support.insert_account(store:, login_name: "login-1")
  let assert CharacterCreated(character_id:) =
    account_store_support.create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 1,
      items: list.append(character_support.row_466_items(), items),
    )
    as "a character holding the worn items and the bag items"
  Stored(store:, account:, character_id:)
}

fn bag_item(
  item2 item2: Int,
  bag_index bag_index: Int,
  count count: Int,
  charges charges: Int,
) -> NewItem {
  NewItem(
    item2_id: Item2Id(item2),
    location: 1,
    bag_index:,
    stack_count: count,
    charges:,
  )
}

/// The items of the bags the store holds now, as a login finds them. A login raises the
/// character's epoch, so a request is made under the epoch of the login just before it.
fn loaded(stored stored: Stored) -> #(Int, List(HeldItem)) {
  let #(epoch, items) =
    account_store_support.login(
      store: stored.store,
      account: stored.account,
      character_id: stored.character_id,
    )
  #(epoch, list.filter(items, fn(item) { item.location == 1 }))
}

/// The connection's request made the stored character's own: its account and id, and the
/// epoch of a login just before it.
fn own_request(
  stored stored: Stored,
  request request: ItemsRequest,
) -> ItemsRequest {
  let #(epoch, _) = loaded(stored:)
  let session_epoch = character_support.epoch(epoch)
  case request {
    SpendItem(..) ->
      SpendItem(
        ..request,
        account_id: stored.account,
        character_id: stored.character_id,
        session_epoch:,
      )
    DeleteItem(..) ->
      DeleteItem(
        ..request,
        account_id: stored.account,
        character_id: stored.character_id,
        session_epoch:,
      )
    store.MoveItems(..)
    | store.SplitItem(..)
    | store.MergeItems(..)
    | store.BuyFromVendor(..)
    | store.SellToVendor(..)
    | store.TurnInQuest(..) -> panic as "a use asks a spend or a delete"
  }
}

/// The store's answer to the connection's request.
fn store_answer(
  stored stored: Stored,
  request request: ItemsRequest,
) -> Outcome(Answer) {
  step.Answer(
    FromStore(account_store_support.ask(
      store: stored.store,
      request: store.Items(own_request(stored:, request:)),
    )),
  )
}

/// A press of the item, the store's answer to its spend, and the step of the answer.
fn used_on_the_store(
  stored stored: Stored,
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
  place place: ItemPlace,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = pressed(state:, client_cast_id:, place:, at: ms)
  let outcome =
    store_answer(stored:, request: support_items.spend_asked(taken:))
  answered_at(state:, taken:, outcome:, at: ms)
}

/// The (guid, count, charges) of each 0x111 of the frames.
fn added_in(frames frames: List(Frame)) -> List(#(Int, Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0111 -> {
        let assert Ok(added) = item_added.decode(frame.body)
          as "the 0x111 decodes"
        let item = added.held_item.item
        Ok(#(item.item_guid, item.stack_count, item.charges))
      }
      _ -> Error(Nil)
    }
  })
}

/// The (count, charges) of the 0x111 that the entry after a login sends for the item with
/// this guid, none when it sends none.
fn entry_of_item(
  tables tables: table_store.Tables,
  stored stored: Stored,
  guid guid: Int,
) -> List(#(Int, Int)) {
  let #(_, items) = loaded(stored:)
  support_items.entry_of(tables:, held: items, unset: []).frames
  |> added_in
  |> list.filter(fn(added) { added.0 == guid })
  |> list.map(fn(added) { #(added.1, added.2) })
}

/// The frames that say a cast or an item changed.
const use_frames = [0x07FD, 0x07F4, 0x07FE, 0x017F, 0x00CA, 0x0148]

/// The connection that ends while the spend's ask is out writes no cast frame and no item
/// frame, whichever kind of spend is out. The store was never asked, so its rows stay as they
/// were by construction: what the client keeps after the crash is what it held before the
/// press, and the next login's 0x111 sends the stored charges
/// (`a_crash_after_the_spend_commits_resyncs_the_client_on_reload_test` for the commit).
pub fn a_crash_before_the_spend_commits_leaves_no_effect_and_the_charge_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_charged_rows
  list.each(
    [
      #(single(charges: 3), single_place, "a lowered charge"),
      #(single(charges: 1), single_place, "the last charge, a delete"),
      #(stack(count: 5), stack_place, "a lowered stack"),
    ],
    fn(row) {
      let #(item, place, why) = row
      let state = support_items.seeing_a_shack(tables:, items: [item])
      let #(state, taken) = pressed(state:, client_cast_id: 9, place:, at: 0)
      assert support.asked(taken) != None
        as "the use asks the store to save the spend"
      let #(_, closing) =
        connection_support.feed(state, OwnEvent(step.PeerClosed))
      assert list.filter(ids(taken: closing), fn(id) {
          list.contains(use_frames, id)
        })
        == []
        as { "no cast frame and no item frame is written for " <> why }
    },
  )
}

/// What the store holds after a spend whose answer never reaches the connection.
type Committed {
  Committed(
    items: List(NewItem),
    place: ItemPlace,
    entry: Option(#(Int, Int)),
    why: String,
  )
}

pub fn a_crash_after_the_spend_commits_resyncs_the_client_on_reload_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_charged_rows
  list.each(
    [
      Committed(
        items: [
          bag_item(item2: the_stack_row, bag_index: 1, count: 5, charges: 1),
        ],
        place: stack_place,
        entry: Some(#(4, 1)),
        why: "a stack of 5 reloads as 4",
      ),
      Committed(
        items: [
          bag_item(
            item2: support_items.grenade,
            bag_index: 0,
            count: 1,
            charges: 3,
          ),
        ],
        place: single_place,
        entry: Some(#(1, 2)),
        why: "an item of 3 charges reloads with 2",
      ),
      Committed(
        items: [
          bag_item(
            item2: support_items.grenade,
            bag_index: 0,
            count: 1,
            charges: 1,
          ),
        ],
        place: single_place,
        entry: None,
        why: "the last charge removed the item: no 0x111 for it",
      ),
    ],
    fn(row) {
      let stored = stored_holding(items: row.items)
      let #(_, rows) = loaded(stored:)
      let state = support_items.seeing_a_shack(tables:, items: rows)
      let #(state, taken) =
        pressed(state:, client_cast_id: 9, place: row.place, at: 0)
      let assert ForItems(store.ItemsSaved) =
        account_store_support.ask(
          store: stored.store,
          request: store.Items(own_request(
            stored:,
            request: support_items.spend_asked(taken:),
          )),
        )
        as "the real store applies the spend"
      // The answer is never delivered: the connection ends.
      let #(_, closing) =
        connection_support.feed(state, OwnEvent(step.PeerClosed))
      assert list.filter(ids(taken: closing), fn(id) {
          list.contains(use_frames, id)
        })
        == []
        as "nothing is written for the spend the connection never heard of"
      let assert [item] = rows as "the store holds the item"
      let reloaded = entry_of_item(tables:, stored:, guid: item.item_guid)
      assert reloaded
        == case row.entry {
          Some(entry) -> [entry]
          None -> []
        }
        as row.why
      account_store_support.stop(stored.store)
    },
  )
}

/// The inventory frame the answer wrote and the row the store holds for the item now:
/// what the client was told is what the store holds.
fn the_client_holds_what_the_store_does(
  stored stored: Stored,
  answered answered: ConnectionStep(Request),
) -> Nil {
  let assert [first, ..] = connection_support.written(taken: answered)
    as "the answer wrote the inventory frame"
  let #(_, rows) = loaded(stored:)
  case told_by(frame: first) {
    Charges(guid:, charges:) -> {
      let assert Ok(row) = list.find(rows, fn(row) { row.item_guid == guid })
        as "the item is held"
      assert row.charges == charges
        as "the client's charges are the stored charges"
    }
    Count(guid:, count:, ..) -> {
      let assert Ok(row) = list.find(rows, fn(row) { row.item_guid == guid })
        as "the item is held"
      assert row.stack_count == count
        as "the client's count is the stored count"
    }
    Removed(guid:, ..) -> {
      assert list.find(rows, fn(row) { row.item_guid == guid }) == Error(Nil)
        as "the item is gone from the store as from the client"
    }
  }
}

pub fn using_a_charged_item_until_it_runs_out_and_a_relog_keeping_the_count_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_charged_rows
  let stored =
    stored_holding(items: [
      bag_item(item2: support_items.grenade, bag_index: 0, count: 1, charges: 3),
      bag_item(item2: the_stack_row, bag_index: 1, count: 2, charges: 1),
    ])
  let #(_, rows) = loaded(stored:)
  let assert Ok(single_row) = list.find(rows, fn(row) { row.bag_index == 0 })
  let assert Ok(stack_row) = list.find(rows, fn(row) { row.bag_index == 1 })
  let state = support_items.seeing_a_shack(tables:, items: rows)
  let cast_frames = [0x07FD, 0x07F4, 0x07FE]
  // Use 1 and 2 of the item with 3 charges.
  let #(state, first) =
    used_on_the_store(
      stored:,
      state:,
      client_cast_id: 1,
      place: single_place,
      at: 0,
    )
  let assert [head, ..] = connection_support.written(taken: first)
  assert told_by(frame: head) == Charges(guid: single_row.item_guid, charges: 2)
    as "use 1 writes 0xca with 2 charges"
  assert list.take(ids(taken: first), 4) |> list.drop(1) == cast_frames
    as "then the cast frames"
  the_client_holds_what_the_store_does(stored:, answered: first)
  let #(_, second) =
    used_on_the_store(
      stored:,
      state:,
      client_cast_id: 2,
      place: single_place,
      at: 5000,
    )
  let assert [head, ..] = connection_support.written(taken: second)
  assert told_by(frame: head) == Charges(guid: single_row.item_guid, charges: 1)
    as "use 2 writes 0xca with 1 charge"
  the_client_holds_what_the_store_does(stored:, answered: second)
  // The relog: the character is loaded again and enters with what the store holds.
  assert entry_of_item(tables:, stored:, guid: single_row.item_guid)
    == [#(1, 1)]
    as "the relog's 0x111 carries the charges left, 1"
  let #(_, rows) = loaded(stored:)
  let state = support_items.seeing_a_shack(tables:, items: rows)
  let #(state, third) =
    used_on_the_store(
      stored:,
      state:,
      client_cast_id: 1,
      place: single_place,
      at: 0,
    )
  let assert [head, ..] = connection_support.written(taken: third)
  assert told_by(frame: head) == Removed(guid: single_row.item_guid, reason: 1)
    as "a use after the relog writes 0x148 with reason 1: the last charge"
  the_client_holds_what_the_store_does(stored:, answered: third)
  let #(state, fourth) =
    pressed(state:, client_cast_id: 2, place: single_place, at: 5000)
  assert ids(taken: fourth) == [0x07FC]
    && refusal_of(taken: fourth) == #(2, 0, 22)
    as "a fourth 0x943 finds no item at the place: ItemBad (22), nothing asked"
  // The stack of 2.
  let #(state, stack_first) =
    used_on_the_store(
      stored:,
      state:,
      client_cast_id: 3,
      place: stack_place,
      at: 10_000,
    )
  let assert [head, ..] = connection_support.written(taken: stack_first)
  assert told_by(frame: head)
    == Count(guid: stack_row.item_guid, count: 1, reason: 1)
    as "the first use of the stack writes 0x17f with count 1 and reason 1"
  the_client_holds_what_the_store_does(stored:, answered: stack_first)
  let #(_, stack_second) =
    used_on_the_store(
      stored:,
      state:,
      client_cast_id: 4,
      place: stack_place,
      at: 15_000,
    )
  let assert [head, ..] = connection_support.written(taken: stack_second)
  assert told_by(frame: head) == Removed(guid: stack_row.item_guid, reason: 1)
    as "the second removes the stack with 0x148"
  the_client_holds_what_the_store_does(stored:, answered: stack_second)
  account_store_support.stop(stored.store)
}
