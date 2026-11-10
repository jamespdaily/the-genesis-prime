//// A player's request to talk to a unit on the game connection
//// (`genesis_prime/game/interaction`): the client's 0x7EA, which it sends when the
//// player right-clicks a quest giver, and the server's 0x357, which alone opens
//// the unit's dialog. Expected values come from these places.
//// - `opcode.0x7ea` and `opcode.0x357`: the request is a unit id and a kind, 37
////   (TalkTo) for any quest giver, and the answer is 0x357 with the unit id; unit 0
////   with kind 0x65 is the client's own end of an interaction, and kind 0x31 is a
////   vendor.
//// - `opcode.0x90b`, `opcode.0xbc`, `opcode.0x106`, `0x1403add00` (CheckInteractionTarget):
////   a vendor's kind 0x31 is answered with 0x90b (the stock, in position order, price
////   slots of kind 0 so the client prices each item itself, multipliers 1.0, open 1) and
////   0xbc with no entries; a request the client would refuse is answered with 0x106 and
////   a 0x90b that refuses: unit not shown 59; not a creature, no stock or dead 16; gap
////   over 9.0 17; Hostile 62, in that order.
//// - `0x14039d5d0`, `0x140554470`, `0x14047a060`: the client sends the request only
////   for a creature that is alive, not Hostile to the player and a quest giver, and opens the
////   dialog only within 6.0 of the creature edge to edge. `opcode.0x7ea` adds 3.0 to a
////   request's range.
//// - `0x1403ad690`: the gap is the distance less both hit radii. The player's is the
////   Race table's hitRadius, 1.2 (0x3f99999a, every playable race); Dorian Walker's is
////   Creature2DisplayInfo 25510's, 1.1 (0x3f8ccccd), the one entry of the display group
////   28097 of Creature2 74812.
//// - Creature2 74812 (Dorian Walker) gives quest 10528 and receives quest 10520;
////   Creature2 73464, the Virtual Battle Beast, gives and receives none.

import character_support
import character_tables
import connection_rule_support as support
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, AskStore, CreatureAppeared, FromStore, LookChanged,
  PropertiesChanged,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/interaction
import genesis_prime/game/random_stat_word
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/game/vendor
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/buyback_removed
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/dialog_responses_shown.{DialogResponsesShown}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/generic_error.{GenericError}
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/item_count_changed.{ItemCountChanged}
import genesis_prime/message/item_place
import genesis_prime/message/item_removed.{ItemRemoved}
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/message/unit_item_visuals_changed
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/vendor_item.{type VendorItem, VendorItem}
import genesis_prime/message/vendor_items.{VendorItems}
import genesis_prime/message/vendor_price_slot.{VendorPriceSlot}
import genesis_prime/step.{type ConnectionEvent, type Event, LogWarning}
import genesis_prime/store
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{type Hostile, Hostile}
import genesis_prime/world_map/creature_unit
import gleam/list
import gleam/option.{None}
import gleam/set
import owned_test
import planted_table.{Integer}
import quest_support
import spawn_support
import vendor_support

/// The edge gap a request is answered up to: 6.0 for a quest kind, plus the 3.0 a
/// request may add (`opcode.0x7ea`).
const reach = 9.0

/// The player's hit radius (Race.hitRadius, 0x3f99999a) and Dorian Walker's
/// (Creature2DisplayInfo 25510's hitRadius, 0x3f8ccccd).
const player_radius = vendor_support.player_radius

const walker_radius = vendor_support.walker_radius

const walker_unit = vendor_support.walker_unit

/// A creature that is Hostile to neither player faction.
const friendly = Hostile(exile: False, dominion: False)

/// A creature that is Hostile to both player factions (the client's disposition of
/// the creature toward the player is 0, `0x14045a950`).
const hostile = Hostile(exile: True, dominion: True)

/// The 0x262 news of Dorian Walker, standing `gap` from the player's edge straight
/// ahead of the player, with `health` and `hostile_to`.
fn walker_appears(
  unit_id unit_id: Int,
  gap gap: Float,
  health health: Int,
  hostile_to hostile_to: Hostile,
) -> Event(ConnectionEvent(Message, Answer)) {
  let entry = connection_support.entry_place()
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { gap +. player_radius +. walker_radius },
    )
  let walker = spawn_support.dorian_walker(number: 1, place:)
  connection_support.sent_by_a_peer(connection_support.news_of(
    unit_id:,
    news: CreatureAppeared(
      unit: creature_unit.create(
        spawn: walker,
        unit_id:,
        health:,
        interrupt_armor: None,
        server_time_estimate_start: 0,
      ),
      life: 4,
      place:,
      hit_radius: walker.combat.hit_radius,
      attackable: walker.combat.attackable,
      hostile_to:,
    ),
  ))
}

/// A connection with Dorian Walker in its picture `gap` away, alive, whose player holds
/// no quest.
fn with_walker(gap gap: Float) -> game_connection.State {
  with_walker_for(state: connection_support.in_world(), gap:)
}

/// Dorian Walker `gap` away, alive, in the picture of this connection.
fn with_walker_for(
  state state: game_connection.State,
  gap gap: Float,
) -> game_connection.State {
  connection_support.feed(
    state:,
    event: walker_appears(
      unit_id: walker_unit,
      gap:,
      health: 52,
      hostile_to: friendly,
    ),
  ).0
}

pub fn talk_to_giver_in_range_opens_dialog_test() -> Nil {
  use <- owned_test.run(10_000)
  // Walker receives quest 10520 and the player holds it Accepted, which the client's
  // marking of the creature shows (opcode.0x7ea, `0x1405a8d40`).
  let state =
    with_walker_for(
      state: connection_support.entered_with_quests(quests: [
        quest_support.accepted(10_520, progress: [0, 0, 0, 0, 0]),
      ]).0,
      gap: reach -. 0.1,
    )
  let #(state, taken) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 37,
    )
  let assert [Frame(message_id: 0x0357, body:)] =
    connection_support.written(taken:)
    as "a TalkTo of a giver within 6.0 + 3.0 is answered with 0x357 alone"
  assert unit_dialog_open.decode(body)
    == Ok(UnitDialogOpen(unit_id: walker_unit, field_2: 0))
    as "opcode.0x357: the answer names the unit"
  assert support.logs_of(step: taken, level: LogWarning) == []
  let #(_, again) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 37,
    )
  assert connection_support.written_ids(again) == [0x0357]
    as "a repeated request is answered again: the connection keeps no interaction"
}

/// A giver that does only one of giving and receiving (a row that gives or receives
/// is a quest giver as well), asked for its dialog from 1.0 away by a player whose log
/// holds this quest Accepted, which the client's marking shows for either list.
fn only_one_is_a_giver(
  tables tables: table_store.Tables,
  held held: Int,
) -> Nil {
  let #(_, taken) =
    connection_support.interaction_requested(
      state: connection_support.feed(
        state: connection_support.medic_in_holding(tables:, quests: [
          quest_support.accepted(held, progress: [0, 0, 0, 0, 0]),
        ]),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 52,
          hostile_to: friendly,
        ),
      ).0,
      unit_id: walker_unit,
      kind: 37,
    )
  assert connection_support.written_ids(taken) == [0x0357]
}

pub fn a_creature_that_only_gives_a_quest_is_a_giver_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Creature2", id: 74_812, with: [
    #("questIdReceive00", Integer(0)),
  ])
  only_one_is_a_giver(tables:, held: 10_528)
}

pub fn a_creature_that_only_receives_a_quest_is_a_giver_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Creature2", id: 74_812, with: [
    #("questIdGiven00", Integer(0)),
  ])
  only_one_is_a_giver(tables:, held: 10_520)
}

pub fn talk_to_refused_sends_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the connection, the request's unit, and the words of its
  // one warning.
  let cases = [
    #("an unseen unit", connection_support.in_world(), 99, "not shown"),
    #(
      "a dead creature",
      connection_support.feed(
        state: connection_support.in_world(),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 0,
          hostile_to: friendly,
        ),
      ).0,
      walker_unit,
      "dead",
    ),
    #(
      "a creature whose row has no quest",
      connection_support.feed(
        state: connection_support.in_world(),
        event: connection_support.beast_appears(unit_id: 41),
      ).0,
      41,
      "no quest",
    ),
    #(
      "a creature that is Hostile to the player",
      connection_support.feed(
        state: connection_support.in_world(),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 52,
          hostile_to: hostile,
        ),
      ).0,
      walker_unit,
      "Hostile",
    ),
    #(
      "a giver beyond the reach",
      with_walker(gap: reach +. 0.1),
      walker_unit,
      "too far",
    ),
    #(
      "another player's unit",
      connection_support.viewer_showing_unit_9(),
      9,
      "not a creature",
    ),
  ]
  use #(what, state, unit_id, words) <- list.each(cases)
  let #(state, first) =
    connection_support.interaction_requested(state:, unit_id:, kind: 37)
  assert connection_support.written_ids(first) == []
    as { what <> " is answered with nothing" }
  let assert [line] = support.logs_of(step: first, level: LogWarning)
    as { what <> " is logged once as a warning" }
  assert support.says(line:, words:) as { what <> " says why: " <> words }
  assert !support.stops(first) as { what <> " leaves the connection up" }
  let #(_, second) =
    connection_support.interaction_requested(state:, unit_id:, kind: 37)
  assert connection_support.written_ids(second) == []
  assert support.logs_of(step: second, level: LogWarning) == []
    as { what <> " is a debug line the second time" }
}

pub fn end_and_dialog_reply_are_accepted_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = with_walker(gap: 1.0)
  // The client's own end of an interaction (opcode.0x7ea), and its 0x356 (opcode.0x356).
  let #(state, ended) =
    connection_support.interaction_requested(state:, unit_id: 0, kind: 0x65)
  assert connection_support.written_ids(ended) == []
  assert support.logs_of(step: ended, level: LogWarning) == []
  let #(_, replied) =
    connection_support.read(
      state:,
      bytes: connection_support.world_message(message_id: 0x0356, body: <<>>),
    )
  assert connection_support.written_ids(replied) == []
  assert support.logs_of(step: replied, level: LogWarning) == []
}

/// 1.0 as the client's reader holds a float (0x3f800000).
const one = 0x3F800000

/// The item the client's reader gets for a stocked row (`0x140097ae0`): named by its
/// position, kind 0, the Item2 row, and every other column 0 with price slots of kind 0.
fn stocked_item(unique_id unique_id: Int, item_id item_id: Int) -> VendorItem {
  let no_price = VendorPriceSlot(kind: 0, amount: 0, currency_id: 0)
  VendorItem(
    unique_id:,
    kind: 0,
    entry_id: item_id,
    currency_type_id: 0,
    stock_count: 0,
    prerequisite_id: 0,
    amount: 0,
    tab_id: 0,
    flags: 0,
    field_10: 0,
    field_11: 0,
    price_slot_1: no_price,
    price_slot_2: no_price,
  )
}

/// A connection whose picture holds Dorian Walker as unit 40, `gap` away with `health`
/// and `hostile_to`, and whose server's vendors are those of `creature_ids`.
fn walker_among_vendors(
  creature_ids creature_ids: List(Int),
  gap gap: Float,
  health health: Int,
  hostile_to hostile_to: Hostile,
) -> game_connection.State {
  connection_support.feed(
    state: connection_support.in_world_stocking(
      vendors: vendor_support.stocking(creature_ids:),
    ),
    event: walker_appears(unit_id: walker_unit, gap:, health:, hostile_to:),
  ).0
}

pub fn vendor_in_range_opens_its_window_with_its_stock_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    walker_among_vendors(
      creature_ids: [74_812],
      gap: reach -. 0.1,
      health: 52,
      hostile_to: friendly,
    )
  let #(state, taken) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  let assert [
    Frame(message_id: 0x090B, body: items),
    Frame(message_id: 0x00BC, body: buyback),
  ] = connection_support.written(taken:)
    as "a vendor within 6.0 + 3.0 is answered with 0x90b, then 0xbc, and nothing else"
  assert vendor_items.decode(items)
    == Ok(VendorItems(
      unit_id: walker_unit,
      tabs: [],
      items: [
        stocked_item(unique_id: 1, item_id: 12_078),
        stocked_item(unique_id: 2, item_id: 14_838),
        stocked_item(unique_id: 3, item_id: 20_791),
      ],
      buy_multiplier: one,
      sell_multiplier: one,
      open: 1,
      full_list: 1,
      refuse: 0,
    ))
    as "opcode.0x90b: the stock in position order, no tabs, multipliers 1.0, open and full list, no refusal"
  assert buyback_list.decode(buyback) == Ok(BuybackList(entries: []))
    as "opcode.0xbc: nothing has been sold to the vendor"
  assert support.logs_of(step: taken, level: LogWarning) == []
  let #(_, again) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  assert connection_support.written_ids(again) == [0x090B, 0x00BC]
    as "a repeated request is answered again: the connection keeps no interaction"
}

pub fn a_vendor_open_the_client_would_refuse_is_refused_with_its_code_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the connection, the request's unit, the client's code
  // (opcode.0x7ea, CheckInteractionTarget 0x1403add00) and the words of its one warning.
  let cases = [
    #(
      "an unseen unit",
      walker_among_vendors(
        creature_ids: [74_812],
        gap: 1.0,
        health: 52,
        hostile_to: friendly,
      ),
      99,
      59,
      "not shown",
    ),
    #(
      "another player's unit",
      connection_support.viewer_showing_unit_9(),
      9,
      16,
      "not a creature",
    ),
    #(
      "a creature with no stock",
      walker_among_vendors(
        creature_ids: [73_464],
        gap: 1.0,
        health: 52,
        hostile_to: friendly,
      ),
      walker_unit,
      16,
      "no stock",
    ),
    #(
      "a dead vendor",
      walker_among_vendors(
        creature_ids: [74_812],
        gap: 1.0,
        health: 0,
        hostile_to: friendly,
      ),
      walker_unit,
      16,
      "dead",
    ),
    #(
      "a vendor beyond the reach",
      walker_among_vendors(
        creature_ids: [74_812],
        gap: reach +. 0.1,
        health: 52,
        hostile_to: friendly,
      ),
      walker_unit,
      17,
      "too far",
    ),
    #(
      "a vendor that is Hostile to the player",
      walker_among_vendors(
        creature_ids: [74_812],
        gap: 1.0,
        health: 52,
        hostile_to: hostile,
      ),
      walker_unit,
      62,
      "Hostile",
    ),
    #(
      "a vendor that is both beyond the reach and Hostile: the range is checked first",
      walker_among_vendors(
        creature_ids: [74_812],
        gap: reach +. 0.1,
        health: 52,
        hostile_to: hostile,
      ),
      walker_unit,
      17,
      "too far",
    ),
  ]
  use #(what, state, unit_id, code, words) <- list.each(cases)
  let #(state, first) =
    connection_support.interaction_requested(state:, unit_id:, kind: 0x31)
  let assert [
    Frame(message_id: 0x0106, body: error),
    Frame(message_id: 0x090B, body: refusal),
  ] = connection_support.written(taken: first)
    as { what <> " is answered with 0x106, then the refusing 0x90b" }
  assert generic_error.decode(error) == Ok(GenericError(code:))
    as { what <> " is refused with the client's code" }
  assert vendor_items.decode(refusal)
    == Ok(VendorItems(
      unit_id:,
      tabs: [],
      items: [],
      buy_multiplier: one,
      sell_multiplier: one,
      open: 1,
      full_list: 0,
      refuse: 1,
    ))
    as { what <> " closes the window with no stock (opcode.0x90b)" }
  let assert [line] = support.logs_of(step: first, level: LogWarning)
    as { what <> " is logged once as a warning" }
  assert support.says(line:, words:) as { what <> " says why: " <> words }
  assert !support.stops(first) as { what <> " leaves the connection up" }
  let #(_, second) =
    connection_support.interaction_requested(state:, unit_id:, kind: 0x31)
  assert connection_support.written_ids(second) == [0x0106, 0x090B]
    as { what <> " is refused again" }
  assert support.logs_of(step: second, level: LogWarning) == []
    as { what <> " is a debug line the second time" }
}

/// What the rule says of the vendor window for a message and its body, over a picture
/// with Dorian Walker in reach who is a vendor and a quest giver.
fn window_after(
  message message: interaction.Message,
  body body: BitArray,
) -> interaction.Window {
  let assert Ok(taken) =
    interaction.take(
      message:,
      body:,
      player: interaction.Player(
        race_id: id.RaceId(1),
        faction: shown.Dominion,
        place: connection_support.entry_place(),
      ),
      picture: vendor_support.picture_with_walker(gap: 1.0),
      tables: character_tables.shared(),
      vendors: vendor_support.stocking(creature_ids: [74_812]),
      now_ms: 0,
      offers: fn(_) { interaction.Offered },
      talk_targets: set.new(),
      logged: set.new(),
    )
    as "the body is one the client's reader accepts"
  taken.window
}

fn request_body(unit_id unit_id: Int, kind kind: Int) -> BitArray {
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(unit_id:, kind:))
    as "a unit id and a 7-bit kind fit the message"
  body
}

pub fn an_opened_vendor_is_held_and_any_other_interaction_answer_clears_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(walkers) =
    vendor.get(
      vendors: vendor_support.stocking(creature_ids: [74_812]),
      creature_id: id.Creature2Id(74_812),
    )
    as "the vendors of the test hold Dorian Walker"
  assert window_after(
      message: interaction.Requested,
      body: request_body(unit_id: walker_unit, kind: 0x31),
    )
    == interaction.Opens(opened: vendor.Opened(
      unit_id: walker_unit,
      vendor: walkers,
    ))
    as "opcode.0x7ea: a vendor request the client's check accepts opens the window the 0xBE needs"
  let closes = [
    #(
      "a vendor request the client would refuse",
      request_body(unit_id: 99, kind: 0x31),
    ),
    #(
      "a request to talk to a quest giver",
      request_body(unit_id: walker_unit, kind: 37),
    ),
    #("the client's own end", request_body(unit_id: 0, kind: 0x65)),
    #(
      "a kind the server does not take",
      request_body(unit_id: walker_unit, kind: 5),
    ),
  ]
  list.each(closes, fn(closing) {
    assert window_after(message: interaction.Requested, body: closing.1)
      == interaction.Closes
      as {
        "opcode.0x7ea: the client closes the vendor window before each request it sends, so "
        <> closing.0
        <> " ends it"
      }
  })
  let assert Ok(shown_body) =
    dialog_responses_shown.encode(DialogResponsesShown)
    as "the message has no fields"
  assert window_after(message: interaction.ResponsesShown, body: shown_body)
    == interaction.Keeps
    as "opcode.0x7ea: 0x356 is not an interaction request, so the client's window stays"
}

pub fn a_buy_the_store_cannot_answer_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  // A buy whose outcome is unknown (the 0x919, 0x111 and 0x106 say what the store did) is
  // an error line and reason 8 once the place is saved, as a move the store cannot answer.
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      step.NotRunning,
      step.NoAnswerInTime,
      step.EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, _) =
        connection_support.feed(
          state: connection_support.in_world_stocking_holding_credits(
            vendors: vendor_support.stocking(creature_ids: [74_812]),
            credits: 100,
          ),
          event: walker_appears(
            unit_id: walker_unit,
            gap: reach -. 0.1,
            health: 52,
            hostile_to: friendly,
          ),
        )
      let #(state, _) =
        connection_support.interaction_requested(
          state:,
          unit_id: walker_unit,
          kind: 0x31,
        )
      let #(state, taken) =
        connection_support.purchase_requested(state:, unique_id: 2, quantity: 1)
      let assert AskStore(store.Items(store.BuyFromVendor(cost: 67, ..))) =
        connection_support.ask_request(taken)
        as "opcode.0xbe: position 2 is Item2 14838 at 67 credits, within the 100 held"
      let #(state, answered) =
        connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: step.LogError))
        == 1
        as "a buy whose outcome is unknown is an error line"
      assert connection_support.written_ids(answered) == []
        as "no 0x919, 0x111, 0x17F or 0x106: nothing says whether the buy was saved"
      let #(_, saved) =
        connection_support.answer(
          state:,
          taken: answered,
          outcome: connection_support.place_saved(),
        )
      assert connection_support.disconnect(saved, connection_support.keyed())
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8"
    },
  )
}

/// Dorian Walker's window open on a connection that holds 100 credits and, besides the Novice
/// set, 5 of Item2 20791 (guid 500, inventory slot 0).
fn selling_state() -> game_connection.State {
  let #(state, _) =
    connection_support.feed(
      state: connection_support.in_world_stocking_holding(
        vendors: vendor_support.stocking(creature_ids: [74_812]),
        credits: 100,
        items: [
          store.HeldItem(
            item_guid: 500,
            item2_id: id.Item2Id(20_791),
            location: 1,
            bag_index: 0,
            stack_count: 5,
            random_stats: 0,
          ),
        ],
      ),
      event: walker_appears(
        unit_id: walker_unit,
        gap: sale_reach -. 0.1,
        health: 52,
        hostile_to: friendly,
      ),
    )
  let #(state, _) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  state
}

/// The edge gap a sale is accepted up to: 6.0 (`opcode.0x166`), within the window's `reach`.
const sale_reach = 6.0

/// The store's ask for a sale of `quantity` of the stack of 20791, which holds `held`, while
/// the connection holds `credits_held`: the tests' account and character, the epoch their load
/// gave, and the one stack. Each item is worth 1 credit (`item_price_test`).
fn sale_asked(
  held held: Int,
  quantity quantity: Int,
  credits_held credits_held: Int,
) -> client_connection.Request {
  AskStore(
    store.Items(
      store.SellToVendor(
        account_id: store.AccountId(7),
        character_id: store.CharacterId(42),
        session_epoch: character_support.epoch(1),
        currency_type_id: 1,
        held: credits_held,
        after: credits_held + quantity,
        sold: [
          store.SoldStack(
            item_guid: 500,
            location: 1,
            held_count: held,
            sold_count: quantity,
          ),
        ],
      ),
    ),
  )
}

pub fn a_sell_sent_while_the_store_works_is_held_and_taken_after_test() -> Nil {
  use <- owned_test.run(10_000)
  let place = item_place.ItemPlace(location: 1, bag_index: 0)
  let #(state, taken) =
    connection_support.sale_requested(
      state: selling_state(),
      place:,
      quantity: 2,
    )
  assert connection_support.ask_request(taken)
    == sale_asked(held: 5, quantity: 2, credits_held: 100)
    as "opcode.0x166: 2 of the 5 held, at the 1 credit each item sells for, fenced by the login's epoch and the 100 credits held"
  assert support.writes(taken) == []
    as "nothing is written before the store has saved the sale"
  let #(state, held) =
    connection_support.sale_requested(state:, place:, quantity: 3)
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the client's frames are held while the ask is out"
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          store.ForItems(
            store.Sold(amount: 102, words: [
              store.SoldWord(item_guid: 500, random_stats: 0),
            ]),
          ),
        ),
      ),
    )
  assert connection_support.written_ids(answered) == [0x0919, 0x017F, 0x00BA]
    as "opcode.0x919 (the total), 0x17F (3 left, reason 7) and 0xBA (the buyback entry): the sale's answer goes out first, then the held line is taken"
  assert connection_support.ask_request(answered)
    == sale_asked(held: 3, quantity: 3, credits_held: 102)
    as "the held 0x166 is taken against the state after the first sale: 3 are left and 102 credits are held"
}

pub fn a_sale_the_store_cannot_answer_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  // As the buy's: a sale whose outcome is unknown (the 0x919, 0x17F and 0xBA say what the
  // store did) is an error line and reason 8 once the place is saved.
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      step.NotRunning,
      step.NoAnswerInTime,
      step.EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, taken) =
        connection_support.sale_requested(
          state: selling_state(),
          place: item_place.ItemPlace(location: 1, bag_index: 0),
          quantity: 2,
        )
      assert connection_support.ask_request(taken)
        == sale_asked(held: 5, quantity: 2, credits_held: 100)
        as "opcode.0x166: the accepted sale is the store's ask"
      let #(state, answered) =
        connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: step.LogError))
        == 1
        as "a sale whose outcome is unknown is an error line"
      assert connection_support.written_ids(answered) == []
        as "no 0x919, 0x17F, 0xBA or 0x106: nothing says whether the sale was saved"
      let #(_, saved) =
        connection_support.answer(
          state:,
          taken: answered,
          outcome: connection_support.place_saved(),
        )
      assert connection_support.disconnect(saved, connection_support.keyed())
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8"
    },
  )
}

/// The player sells `quantity` of its stack of 20791 at slot 0 and the store saves the sale,
/// leaving `credits` credits held.
fn sold(
  state state: game_connection.State,
  quantity quantity: Int,
  credits credits: Int,
) -> game_connection.State {
  let #(state, taken) =
    connection_support.sale_requested(
      state:,
      place: item_place.ItemPlace(location: 1, bag_index: 0),
      quantity:,
    )
  connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(
      FromStore(
        store.ForItems(
          store.Sold(amount: credits, words: [
            store.SoldWord(item_guid: 500, random_stats: 0),
          ]),
        ),
      ),
    ),
  ).0
}

/// The entries of the 0xBC the vendor's window opens with, as the id, the Item2, the quantity
/// and the credits of each in the order sent, and the connection after the request.
fn buyback_listed(
  state state: game_connection.State,
) -> #(game_connection.State, List(#(Int, Int, Int, Int))) {
  let #(state, taken) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  let assert [Frame(message_id: 0x090B, ..), Frame(message_id: 0x00BC, body:)] =
    connection_support.written(taken:)
    as "a vendor within reach is answered with 0x90b, then 0xbc"
  let assert Ok(BuybackList(entries:)) = buyback_list.decode(body)
    as "opcode.0xbc: the list decodes"
  #(
    state,
    list.map(entries, fn(entry) {
      #(entry.buyback_id, entry.item_id, entry.quantity, entry.amount_1)
    }),
  )
}

pub fn opening_a_vendor_sends_the_buyback_list_oldest_first_test() -> Nil {
  use <- owned_test.run(10_000)
  // Nothing has been sold: the Buyback tab is cleared by an empty 0xBC.
  let #(state, listed) = buyback_listed(state: selling_state())
  assert listed == []
    as "opcode.0xbc: an empty list clears the tab; nothing has been sold"
  // 2 and then 3 of the 5 items of 20791 are sold at the 1 credit each item sells for
  // (`item_price_test`): entries 1 and 2, the credits each sale paid.
  let state = sold(state:, quantity: 2, credits: 102)
  let state = sold(state:, quantity: 3, credits: 105)
  let #(state, listed) = buyback_listed(state:)
  assert listed == [#(1, 20_791, 2, 2), #(2, 20_791, 3, 3)]
    as "opcode.0xbc: every entry held, the oldest sale first, as 0xBA adds the newest last"
  let #(_, again) = buyback_listed(state:)
  assert again == listed
    as "a second opening sends the same list: the list belongs to the player, not the window"
}

pub fn the_buyback_list_survives_a_world_change_and_is_empty_after_entering_the_world_again_test() -> Nil {
  use <- owned_test.run(60_000)
  // The player sells 2 of its 5 (entry 1), is struck dead and chooses the Holocrypt: the
  // world is joined again through `world_entry.Joining`, which carries the list.
  let state = sold(state: selling_state(), quantity: 2, credits: 102)
  let dead =
    connection_support.killed(
      connection_support.watched_by(state:, viewers: [2]),
    ).0
  let #(rejoined, _) = connection_support.at_the_holocrypt_from(dead:)
  // The join removes every unit; the vendor is shown again, in the player's second stay,
  // and opened again.
  let #(rejoined, _) =
    connection_support.feed(
      state: rejoined,
      event: connection_support.in_second_stay(walker_appears(
        unit_id: walker_unit,
        gap: sale_reach -. 0.1,
        health: 52,
        hostile_to: friendly,
      )),
    )
  let #(rejoined, listed) = buyback_listed(state: rejoined)
  assert listed == [#(1, 20_791, 2, 2)]
    as "the Holocrypt's join is a change of world, not a new entry: the entry sold before it is still held"
  // A sale after the join takes the next id, not 1 again.
  let rejoined = sold(state: rejoined, quantity: 3, credits: 105)
  let #(rejoined, listed) = buyback_listed(state: rejoined)
  assert listed == [#(1, 20_791, 2, 2), #(2, 20_791, 3, 3)]
    as "an id is given once in a world entry, also across the join"
  // The player camps out and plays the character again on the same connection: a new play
  // entry, whose store holds the 5 of 20791 and 100 credits again, and in whose picture the
  // vendor is shown again (the connection's third stay: the first, the Holocrypt's join).
  let #(camped, _, _) = experience_support.camped(state: rejoined)
  let entered =
    connection_support.entered_stocking_holding(
      in_character_select: camped,
      credits: 100,
      items: [
        store.HeldItem(
          item_guid: 500,
          item2_id: id.Item2Id(20_791),
          location: 1,
          bag_index: 0,
          stack_count: 5,
          random_stats: 0,
        ),
      ],
    )
  let #(entered, _) =
    connection_support.feed(
      state: entered,
      event: connection_support.in_stay(
        count: 3,
        event: walker_appears(
          unit_id: walker_unit,
          gap: sale_reach -. 0.1,
          health: 52,
          hostile_to: friendly,
        ),
      ),
    )
  let #(entered, listed) = buyback_listed(state: entered)
  assert listed == [] as "a play's entry holds no sale of an earlier one"
  let entered = sold(state: entered, quantity: 2, credits: 102)
  let #(_, listed) = buyback_listed(state: entered)
  assert listed == [#(1, 20_791, 2, 2)]
    as "the ids start at 1 on each play entry, on the same connection"
}

pub fn a_buy_back_through_the_connection_saves_the_shortened_list_test() -> Nil {
  use <- owned_test.run(10_000)
  // 2 of the 5 items of 20791 are sold for 2 credits (entry 1), leaving 3 held and 102
  // credits.
  let state = sold(state: selling_state(), quantity: 2, credits: 102)
  let #(state, taken) =
    connection_support.buyback_requested(state:, buyback_id: 1)
  assert connection_support.ask_request(taken)
    == AskStore(
      store.Items(store.BuyFromVendor(
        account_id: store.AccountId(7),
        character_id: store.CharacterId(42),
        session_epoch: character_support.epoch(1),
        currency_type_id: 1,
        held: 102,
        cost: 2,
        grow: [
          store.StackGrowth(item_guid: 500, held_count: 3, new_count: 5),
        ],
        make: [],
        item2_id: id.Item2Id(20_791),
      )),
    )
    as "opcode.0xbb: the entry's 2 items for the 2 credits the sale paid, back into the held stack of 3"
  assert support.writes(taken) == []
    as "nothing is written before the store has saved the buy back"
  // The store saved it: 100 credits are left.
  let #(state, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(store.ForItems(store.Bought(amount: 100, made: []))),
      ),
    )
  let assert [total, grown, removed] =
    connection_support.written(taken: answered)
    as "a 0x919, a 0x17F for the grown stack, then a 0xBD"
  assert currency_changed.decode(total.body)
    == Ok(CurrencyChanged(kind: 0, total: 100, field_3: 0, field_4: 0))
    as "opcode.0x919: kind 0 sets the credits to the total the store left"
  assert grown.message_id == item_count_changed.message_id
  assert item_count_changed.decode(grown.body)
    == Ok(ItemCountChanged(item_guid: 500, count: 5, reason: 16))
    as "Item.CodeEnumItemUpdateReason: Buyback is 16"
  assert removed.message_id == buyback_removed.message_id
  assert buyback_removed.decode(removed.body)
    == Ok(buyback_removed.BuybackRemoved(buyback_id: 1))
    as "opcode.0xbd: the id of the entry bought back"
  let #(state, listed) = buyback_listed(state:)
  assert listed == []
    as "the entry left the list the connection holds: opening the vendor sends none"
  // The same entry again: it is no longer held.
  let #(_, again) = connection_support.buyback_requested(state:, buyback_id: 1)
  assert support.asked(again) == None
    as "an entry already bought back asks the store nothing"
  let assert [refusal] = connection_support.written(taken: again)
    as "and is answered with one message"
  assert refusal.message_id == generic_error.message_id
  assert generic_error.decode(refusal.body) == Ok(GenericError(code: 14))
    as "enum 14, Vendor_UnknownItem"
}

pub fn selling_a_worn_item_sends_0x148_then_0x933_and_0x93a_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    connection_support.watched_by(state: selling_state(), viewers: [2, 3])
  // The Engineer's chest is worn at location 0, bag index 0 (ItemSlot 1), as guid 1.
  let #(state, taken) =
    connection_support.sale_requested(
      state:,
      place: item_place.ItemPlace(location: 0, bag_index: 0),
      quantity: 1,
    )
  let assert AskStore(store.Items(store.SellToVendor(sold:, ..))) =
    connection_support.ask_request(taken)
    as "0x1403d6a10 refuses only a worn bag at location 0: a worn chest is a sale like any other"
  assert sold
    == [
      store.SoldStack(item_guid: 1, location: 0, held_count: 1, sold_count: 1),
    ]
    as "the store is asked to delete the worn stack at location 0"
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          store.ForItems(
            store.Sold(amount: 150, words: [
              store.SoldWord(item_guid: 1, random_stats: 0),
            ]),
          ),
        ),
      ),
    )
  assert connection_support.written_ids(answered)
    == [0x0919, 0x0148, 0x00BA, 0x0933, 0x093A, 0x092F]
    as "the sale's total, the removal, the buyback entry, then the look and the properties as the delete of a worn item sends them, then the health the lower maximum caps"
  let assert [total] =
    connection_support.decoded(
      connection_support.written(answered),
      0x0919,
      currency_changed.decode,
    )
  assert total == CurrencyChanged(kind: 0, total: 150, field_3: 0, field_4: 0)
    as "opcode.0x919: the total the store left"
  let assert [removed] =
    connection_support.decoded(
      connection_support.written(answered),
      0x0148,
      item_removed.decode,
    )
  assert removed == ItemRemoved(item_guid: 1, reason: 7)
    as "Item.CodeEnumItemUpdateReason: Vendor is 7; opcode.0x148.model_unchanged: the frame changes no model, so the 0x933 below is the server's"
  let assert [looks] =
    connection_support.decoded(
      connection_support.written(answered),
      0x0933,
      unit_item_visuals_changed.decode,
    )
  assert looks.unit_id == connection_support.own_unit_id
    as "opcode.0x933: the look is the player's own unit's; its content is the gear step's"
  let assert [properties] =
    connection_support.decoded(
      connection_support.written(answered),
      0x093A,
      unit_properties_changed.decode,
    )
  assert properties.unit_id == connection_support.own_unit_id
    as "opcode.0x93a: the properties are the player's own unit's; their values are the gear step's"
  list.each([2, 3], fn(viewer) {
    let assert [LookChanged(..), PropertiesChanged(..), ..] =
      connection_support.news_told(taken: answered, viewer:)
      as "opcode.0x93a.other_unit: each viewer is told the look, then the properties"
  })
}

/// Dorian Walker sells Item2 48169, a bracer with three kind-2 random stat entries in the
/// first position. Two buys on one connection draw their entropy one after the other from
/// the connection's seed, so the two stacks are made with different words: the connection
/// keeps the link its draw advanced.
pub fn two_buys_of_a_random_stat_item_on_one_connection_make_different_words_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    connection_support.in_world_stocking_holding_credits(
      vendors: vendor_support.stocking_items(creature_ids: [74_812], items: [
        fixture_tables.root("Item2", 48_169),
      ]),
      credits: 1_000_000,
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: walker_appears(
        unit_id: walker_unit,
        gap: reach -. 0.1,
        health: 52,
        hostile_to: friendly,
      ),
    )
  let #(state, _) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  let buy = fn(state, guid) {
    let #(state, taken) =
      connection_support.purchase_requested(state:, unique_id: 1, quantity: 1)
    let assert AskStore(store.Items(store.BuyFromVendor(make: [stack], ..))) =
      connection_support.ask_request(taken)
      as "position 1 is Item2 48169, one unit, one stack"
    let #(state, _) =
      connection_support.answer(
        state:,
        taken:,
        outcome: step.Answer(
          FromStore(
            store.ForItems(
              store.Bought(amount: 900_000, made: [
                store.HeldItem(
                  item_guid: guid,
                  item2_id: id.Item2Id(48_169),
                  location: stack.location,
                  bag_index: stack.bag_index,
                  stack_count: stack.stack_count,
                  random_stats: stack.random_stats,
                ),
              ]),
            ),
          ),
        ),
      )
    #(state, stack.random_stats)
  }
  let #(state, first) = buy(state, 900)
  let #(_, second) = buy(state, 901)
  assert random_stat_word.has_data(word: first)
    && random_stat_word.has_data(word: second)
    as "each stack is made with a rolled word the client reads"
  assert first != second
    as "the second buy drew its own bytes, not the first's again"
}
