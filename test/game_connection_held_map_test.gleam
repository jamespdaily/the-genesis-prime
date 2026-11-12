//// What the game connection does with a message a map sends it (a kill's credit, a
//// creature's strike) or a timer that fires (the save, quest reset and quest deadline
//// timers) while the connection waits on the store, in a buy, a sale, a turn-in, an
//// item move, a summon or the periodic place save (`genesis_prime/game/connection`),
//// and what a firing does while the player leaves the map. Expected values come from
//// these places.
//// - The stay rule of `experience_flow_test`: a credit told for a stay other than the
////   connection's current one is dropped.
//// - The frames of a buy, a sale and a turn-in are the ones their own tests state
////   (`interaction_test`, `game_connection_quest_turn_in_test`); the kill's frames are
////   `game_connection_objective_test`'s: `opcode.0x1ac` the experience, then
////   `opcode.0x361` the objective's progress and `opcode.0x35c` the quest's state.
//// - A level 1 Engineer's health is 736 and its shield 450; the Beast's 12 Physical
////   strike takes the shield to 448 and the health to 735
////   (`game_connection_fight_test`).
//// - Failure table: a connection whose ask is not answered in time ends with
////   `opcode.0x36a` reason 8 and holds nothing more to take.
//// - The timers: the save timer is 60,000 ms (`movement.save_period_ms`); quest 1872 with
////   a time limit of 60,000 ms entered at 1,000 ms is due at 61,000 ms, and its botch is
////   0x35C {quest 1872, state 4, objective 0} (`game_connection_quest_deadline_test`); the
////   reset of Monday 2025-04-28 10:00 UTC is 0x362 with time 1,745,834,400 and the daily
////   bit (`game_connection_quest_log_test`). A timer that fires in a status outside the
////   world still ends the connection with an error line (`game_connection_save_test`).

import character_tables
import connection_rule_support as support
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, FromMap, FromStore, SentByKill,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/experience.{Credit}
import genesis_prime/message/bit_stream
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_place
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/quest_periodic_reset.{QuestPeriodicReset}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/step.{
  type ConnectionEvent, type Event, OwnEffect, OwnEvent, StartTimer, TimerFired,
}
import genesis_prime/store.{HeldItem, ItemsSaved, NewStack}
import genesis_prime/table/id.{Creature2Id, Faction2Id, Item2Id}
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/map.{Join, Left}
import genesis_prime/world_map/stay.{type Stay}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import quest_support
import quest_turn_in_support
import quest_walker_support
import spawn_support
import vendor_support

const beast = 73_464

/// The unit of Dorian Walker in the tests' picture.
const walker_unit = 40

/// The credit of the Beast (Creature2 73464, level 1, no faction) as unit `unit_id`,
/// told to the connection for `stay`.
fn kill_of(
  unit_id unit_id: Int,
  stay stay: Stay,
) -> Event(ConnectionEvent(Message, Answer)) {
  connection_support.for_stay(
    stay:,
    sent: SentByKill(Credit(
      unit_id:,
      creature_id: Creature2Id(beast),
      faction_id: Faction2Id(0),
      level: 1,
    )),
  )
}

/// The units the 0x1ac frames of a step name as the source of the experience, in order.
fn kill_sources(taken taken: step.ConnectionStep(Request)) -> List(Int) {
  list.map(experience_support.gains(taken:), fn(gained) {
    gained.source_unit_id
  })
}

/// The client's 0x035D for quest `quest_id` and no reward choice.
fn turn_in_of(quest_id quest_id: Int) -> BitArray {
  connection_support.world_message(
    message_id: 0x035D,
    body: quest_turn_in_support.body(scene: quest_turn_in_support.scene(
      quest_id:,
    )),
  )
}

/// Dorian Walker (Creature2 74812), friendly and in reach of the player, with his
/// window open.
fn at_the_vendor(state state: game_connection.State) -> game_connection.State {
  let place = vendor_support.ahead_of_the_player(hit_radius: 1.0, gap: 1.0)
  let walker = spawn_support.dorian_walker(number: 1, place:)
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.creature_appears(
        unit_id: walker_unit,
        creature_id: 74_812,
        display_info_id: walker.display_info_id,
        outfit_info_id: walker.outfit_info_id,
        hit_radius: walker.combat.hit_radius,
        place: vendor_support.ahead_of_the_player(
          hit_radius: walker.combat.hit_radius,
          gap: 1.0,
        ),
        hostile_to: Hostile(exile: False, dominion: False),
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

/// The player holds 5 of Item2 20791 (guid 500) and 100 credits at Dorian Walker, and
/// sells 2: the connection waits on the store.
fn selling() -> #(game_connection.State, step.ConnectionStep(Request)) {
  connection_support.sale_requested(
    state: at_the_vendor(
      state: connection_support.in_world_stocking_holding(
        vendors: vendor_support.stocking(creature_ids: [74_812]),
        credits: 100,
        items: [
          HeldItem(
            item_guid: 500,
            item2_id: Item2Id(20_791),
            location: 1,
            bag_index: 0,
            stack_count: 5,
            random_stats: 0,
          ),
        ],
      ),
    ),
    place: item_place.ItemPlace(location: 1, bag_index: 0),
    quantity: 2,
  )
}

/// The store's answer to the sale: 102 credits are held, the 2 items sold.
fn sale_saved() -> step.Outcome(Answer) {
  step.Answer(
    FromStore(
      store.ForItems(
        store.Sold(amount: 102, words: [
          store.SoldWord(item_guid: 500, random_stats: 0),
        ]),
      ),
    ),
  )
}

/// The frames of the sale's answer (`interaction_test`).
const sale_frames = [0x0919, 0x00DD, 0x017F, 0x00BA]

/// A connection with quest 1857 accepted, whose objective (type 2, count 1) names the
/// Beast, with 100 credits and no items, `then` given it in the world.
fn with_the_beast_quest(then then: fn(game_connection.State) -> Nil) -> Nil {
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 1961, with: [
    #("data", Integer(beast)),
  ])
  let fresh =
    connection_support.accepted(
      connection_state.Settings(
        ..connection_support.settings(),
        tables:,
        vendors: vendor_support.stocking(creature_ids: [74_812]),
      ),
    ).0
  then(
    connection_support.entered_stocking_with_quests(
      in_character_select: connection_support.in_select_from(fresh),
      credits: 100,
      items: [],
      quests: [quest_support.accepted(quest_id: 1857, progress: [0])],
    ),
  )
}

/// That connection buys Item2 14838 at Dorian Walker for 67 of its 100 credits: the
/// connection waits on the store.
fn buying(
  then then: fn(game_connection.State, step.ConnectionStep(Request)) -> Nil,
) -> Nil {
  use state <- with_the_beast_quest
  let #(state, taken) =
    connection_support.purchase_requested(
      state: at_the_vendor(state:),
      unique_id: 2,
      quantity: 1,
    )
  then(state, taken)
}

/// The store's answer to the buy: 33 credits are held, the stack of Item2 14838 made.
fn buy_saved() -> step.Outcome(Answer) {
  step.Answer(
    FromStore(
      store.ForItems(
        store.Bought(amount: 33, made: [
          HeldItem(
            item_guid: 900,
            item2_id: Item2Id(14_838),
            location: 1,
            bag_index: 0,
            stack_count: 1,
            random_stats: 0,
          ),
        ]),
      ),
    ),
  )
}

pub fn a_kill_during_a_buy_counts_once_the_buy_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  use state, taken <- buying
  let #(state, held) =
    connection_support.feed(
      state:,
      event: kill_of(
        unit_id: experience_support.creature_unit_id,
        stay: connection_support.own_stay(),
      ),
    )
  assert connection_support.written_ids(held) == []
    as "nothing is written before the store has saved the buy"
  let #(_, answered) =
    connection_support.answer(state:, taken:, outcome: buy_saved())
  let ids = connection_support.written_ids(answered)
  assert list.drop_while(ids, fn(id) { id != 0x0111 })
    == [0x0111, 0x01AC, 0x0361, 0x035C]
    as "the buy's own frames, then the kill's: the experience, then objective 0 of quest 1857 at 1 of 1 and the quest Achieved"
  assert kill_sources(taken: answered) == [experience_support.creature_unit_id]
    as "one experience, for the unit that was killed"
}

pub fn a_creature_strike_during_a_turn_in_is_taken_after_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 gives Item2 81917 and 29661, 152 experience (level 1 stays) and 145 credits.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(5859),
  ])
  let state =
    quest_walker_support.in_world_with_walker(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 5859),
    ])
  let #(state, taken) =
    connection_support.read(state:, bytes: turn_in_of(quest_id: 5859))
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(
    placed:,
    ..,
  ))) = connection_support.ask_request(taken)
    as "the accepted turn-in is the store's ask"
  let #(state, held) =
    connection_support.feed(
      state:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
  assert connection_support.written_ids(held) == []
    as "the strike is not taken before the store has answered"
  let made =
    list.index_map(placed, fn(one, index) {
      let assert [
        NewStack(location:, bag_index:, stack_count:, random_stats: 0),
      ] = one.make
        as "one stack of each"
      HeldItem(
        item_guid: 900 + index,
        item2_id: one.item2_id,
        location:,
        bag_index:,
        stack_count:,
        random_stats: 0,
      )
    })
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(store.ForItems(store.TurnedIn(credits: 145, made:))),
      ),
    )
  assert connection_support.written_ids(answered)
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x00DD, 0x035C, 0x0938, 0x092F]
    as "the turn-in's frames, the quest's state last, then the strike's: the shield and the health"
  let frames = connection_support.written(taken: answered)
  let assert Ok(health) = list.last(frames)
  assert player_health.decode(health.body)
    == Ok(PlayerHealth(
      unit_id: connection_support.own_unit_id,
      health: 735,
      reason_mask: 0,
    ))
    as "the player's health falls from 736 by the 1 the strike takes after its shield"
}

pub fn map_messages_held_while_the_store_works_are_taken_in_arrival_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = selling()
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 8, stay: connection_support.own_stay()),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 7, stay: connection_support.own_stay()),
    )
  let #(_, answered) =
    connection_support.answer(state:, taken:, outcome: sale_saved())
  assert connection_support.written_ids(answered)
    == list.append(sale_frames, [0x01AC, 0x01AC])
    as "the sale's frames, then one experience for each kill"
  assert kill_sources(taken: answered) == [8, 7]
    as "the kill of unit 8 came first, so its experience is written first"
}

pub fn a_held_message_for_another_stay_is_dropped_when_taken_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = selling()
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 8, stay: connection_support.viewer_stay(2)),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 7, stay: connection_support.own_stay()),
    )
  let #(_, answered) =
    connection_support.answer(state:, taken:, outcome: sale_saved())
  assert kill_sources(taken: answered) == [7]
    as "the kill told for another stay of the player counts for nothing, the one of the present stay does"
}

pub fn a_connection_that_ends_while_holding_map_messages_takes_none_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
    )
  let #(state, taken) =
    connection_support.read(state:, bytes: turn_in_of(quest_id: 10_520))
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 7, stay: connection_support.own_stay()),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
  let #(_, answered) =
    connection_support.answer(state:, taken:, outcome: step.NoAnswerInTime)
  assert list.length(support.logs_of(step: answered, level: step.LogError)) == 1
    as "a turn-in whose outcome is unknown is an error line"
  assert connection_support.written_ids(answered) == [0x036A]
    as "no frame but the disconnect notice: nothing held is taken"
  assert support.asked(answered) == None
    as "no save follows: the turn-in's own may still commit"
  assert connection_support.disconnect(answered, connection_support.keyed())
    == LostUserServer
    as "0x036A reason 8"
}

pub fn a_kill_during_the_periodic_save_counts_once_the_save_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  use state <- with_the_beast_quest
  let #(state, taken) =
    connection_support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(..))) =
    connection_support.ask_request(taken)
    as "the save timer asks the store to save the place"
  let #(state, held) =
    connection_support.feed(
      state:,
      event: kill_of(
        unit_id: experience_support.creature_unit_id,
        stay: connection_support.own_stay(),
      ),
    )
  assert connection_support.written_ids(held) == []
    as "nothing is written before the store has saved the place"
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: connection_support.place_saved(),
    )
  assert connection_support.written_ids(answered) == [0x01AC, 0x0361, 0x035C]
    as "the kill's experience, then objective 0 of quest 1857 at 1 of 1 and the quest Achieved"
  assert kill_sources(taken: answered) == [experience_support.creature_unit_id]
    as "one experience, for the unit that was killed"
}

pub fn a_held_kill_that_achieves_a_quest_leaves_the_next_held_message_for_the_completion_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 1857 (no creature receives it) is Achieved by the kill of unit 7, held during the
  // buy; the kill of unit 8 is held behind it. The server completes the quest right after
  // the first kill is taken, so the second waits for the completion's answer.
  use state, taken <- buying
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(
        unit_id: experience_support.creature_unit_id,
        stay: connection_support.own_stay(),
      ),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: kill_of(unit_id: 8, stay: connection_support.own_stay()),
    )
  let #(state, bought) =
    connection_support.answer(state:, taken:, outcome: buy_saved())
  assert list.drop_while(connection_support.written_ids(bought), fn(id) {
      id != 0x0111
    })
    == [0x0111, 0x01AC, 0x0361, 0x035C]
    as "the buy's frames and the first kill's; the second kill is not taken while the completion waits"
  assert kill_sources(taken: bought) == [experience_support.creature_unit_id]
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(
    quests:,
    credits_held:,
    credits_after:,
    ..,
  ))) = connection_support.ask_request(bought)
    as "the quest no creature receives is completed by the server: the store is asked"
  assert list.map(quests, fn(row) { #(row.quest_id, row.state) })
    == [#(1857, 3)]
    as "the log is saved with the quest Completed"
  assert credits_held == 33
    as "the credits the buy left, which the completion's answer adds to"
  let #(_, completed) =
    connection_support.answer(
      state:,
      taken: bought,
      outcome: step.Answer(
        FromStore(
          store.ForItems(store.TurnedIn(credits: credits_after, made: [])),
        ),
      ),
    )
  let ids = connection_support.written_ids(completed)
  assert list.drop(ids, list.length(ids) - 2) == [0x035C, 0x01AC]
    as "the completion's frames end with the quest's state, then the held kill is taken"
  assert list.last(kill_sources(taken: completed)) == Ok(8)
    as "the experience of the second kill is the last frame"
}

// ---- timers that fire while the connection waits ----

/// A FILETIME of 2025-04-28 10:00:00 UTC, a Monday: a daily reset, passed since the
/// tests' connection entered on the Friday before.
const monday_10 = 133_903_080_000_000_000

/// 0x35C {quest 1872, state 4, objective 0}.
const botched_1872 = <<0x50, 0x07, 0x02, 0, 0, 0, 0, 0, 0, 0>>

/// Whether the step leaves the connection open: nothing stops it and no error is logged.
fn stays_open(taken taken: step.ConnectionStep(Request)) -> Bool {
  !support.stops(taken)
  && support.logs_of(step: taken, level: step.LogError) == []
}

/// The save timer started again, in the step's effects.
fn restarts_the_save_timer(taken taken: step.ConnectionStep(Request)) -> Bool {
  list.contains(
    support.effects_of(taken),
    OwnEffect(StartTimer(connection_state.save_timer, 60_000)),
  )
}

/// The connection after `timer` fired at `ms`.
fn fired_at(
  state state: game_connection.State,
  timer timer: step.TimerId,
  ms ms: Int,
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  connection_support.at(state:, ms:, event: OwnEvent(TimerFired(timer)))
}

/// The connection after the ask of `taken` was answered with `outcome` at `ms`.
fn answered_at(
  state state: game_connection.State,
  taken taken: step.ConnectionStep(Request),
  outcome outcome: step.Outcome(Answer),
  ms ms: Int,
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  let assert Some(ask) = support.asked(taken) as "the step ends in an ask"
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(step.Answered(ask: ask.ask, outcome:)),
  )
}

/// The 0x35C bodies the step writes, in order.
fn quest_states(taken taken: step.ConnectionStep(Request)) -> List(BitArray) {
  connection_support.written(taken:)
  |> list.filter(fn(frame) { frame.message_id == 0x035C })
  |> list.map(fn(frame) { frame.body })
}

/// The Exile of `selling` with quest 1872 (time limit 60,000 ms, a full timer) in its
/// log, selling 2 of its 5 of Item2 20791 at Dorian Walker: the connection waits on the
/// store.
fn selling_with_a_timed_quest(
  then then: fn(game_connection.State, step.ConnectionStep(Request)) -> Nil,
) -> Nil {
  use tables <- quest_support.with_time_limits(limits: [#(1872, 60_000)])
  let fresh =
    connection_support.accepted(
      connection_state.Settings(
        ..connection_support.settings(),
        tables:,
        vendors: vendor_support.stocking(creature_ids: [74_812]),
      ),
    ).0
  let #(state, taken) =
    connection_support.sale_requested(
      state: at_the_vendor(
        state: connection_support.entered_stocking_with_quests(
          in_character_select: connection_support.in_select_from(fresh),
          credits: 100,
          items: [
            HeldItem(
              item_guid: 500,
              item2_id: Item2Id(20_791),
              location: 1,
              bag_index: 0,
              stack_count: 5,
              random_stats: 0,
            ),
          ],
          quests: [quest_support.timed(1872, progress: [], quest_ms_left: 0)],
        ),
      ),
      place: item_place.ItemPlace(location: 1, bag_index: 0),
      quantity: 2,
    )
  then(state, taken)
}

/// The player holds 5 of Item2 20791 in inventory slot 0 and no other item, and moves
/// them to slot 1: the connection waits on the store.
fn moving_an_item() -> #(game_connection.State, step.ConnectionStep(Request)) {
  connection_support.read(
    state: connection_support.entered_with_items_and_quests(
      items: [
        HeldItem(
          item_guid: 500,
          item2_id: Item2Id(20_791),
          location: 1,
          bag_index: 0,
          stack_count: 5,
          random_stats: 0,
        ),
      ],
      quests: [],
    ),
    bytes: connection_support.item_moved_message(
      from: item_place.ItemPlace(location: 1, bag_index: 0),
      to: item_place.ItemPlace(location: 1, bag_index: 1),
    ),
  )
}

/// The development connection after the player said `!summon 75048`: the map is
/// asked.
fn summoning() -> #(game_connection.State, step.ConnectionStep(Request)) {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("!summon 75048"),
      formats: [],
      chat_message_id: 1,
    ))
    as "a chat line fits the message"
  connection_support.read(
    state: connection_support.in_world_with_dev_commands(),
    bytes: connection_support.world_message(
      message_id: send_chat_line.message_id,
      body:,
    ),
  )
}

/// The connection whose 0xBE bought one of Dorian Walker's lots with 100 credits held:
/// it waits on the store.
fn buying_plainly() -> #(game_connection.State, step.ConnectionStep(Request)) {
  connection_support.purchase_requested(
    state: at_the_vendor(
      state: connection_support.in_world_stocking_holding_credits(
        vendors: vendor_support.stocking(creature_ids: [74_812]),
        credits: 100,
      ),
    ),
    unique_id: 2,
    quantity: 1,
  )
}

/// The player's turn-in of quest 5859 at Dorian Walker: the connection waits on the
/// store.
fn turning_in(
  then then: fn(game_connection.State, step.ConnectionStep(Request)) -> Nil,
) -> Nil {
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(5859),
  ])
  let #(state, taken) =
    connection_support.read(
      state: quest_walker_support.in_world_with_walker(tables:, quests: [
        quest_turn_in_support.achieved(quest_id: 5859),
      ]),
      bytes: turn_in_of(quest_id: 5859),
    )
  then(state, taken)
}

/// Whether the step ends in the store's ask to save the player's place.
fn asks_to_save_the_place(taken taken: step.ConnectionStep(Request)) -> Bool {
  case connection_support.ask_request(taken) {
    client_connection.AskStore(store.Move(store.SavePlace(..))) -> True
    _ -> False
  }
}

/// Whether the step ends in the map's ask to join.
fn asks_to_join(taken taken: step.ConnectionStep(Request)) -> Bool {
  case connection_support.ask_request(taken) {
    client_connection.AskMap(message: Join(..), ..) -> True
    _ -> False
  }
}

pub fn a_save_timer_firing_while_a_buy_waits_saves_the_place_once_the_buy_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  use state, taken <- buying
  let #(state, fired) =
    fired_at(state:, timer: connection_state.save_timer, ms: 2000)
  assert stays_open(taken: fired)
    as "a timer of the in-world play that fires during the buy does not end the connection"
  assert support.asked(fired) == None
    && connection_support.written_ids(fired) == []
    as "nothing is asked or written before the store has answered the buy"
  let #(_, answered) =
    connection_support.answer(state:, taken:, outcome: buy_saved())
  assert asks_to_save_the_place(taken: answered)
    as "the place's save the timer was due to ask follows the buy's answer"
  assert restarts_the_save_timer(taken: answered)
    as "the save timer, which fired, starts again with the save"
}

pub fn a_save_timer_firing_while_a_turn_in_waits_keeps_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  use state, taken <- turning_in
  let #(state, fired) =
    fired_at(state:, timer: connection_state.save_timer, ms: 2000)
  assert stays_open(taken: fired)
    as "a save timer that fires during the turn-in does not end the connection"
  assert support.asked(fired) == None
    as "no second save is asked: the turn-in's own request saves the place"
  assert restarts_the_save_timer(taken: fired)
    as "the save timer that fired starts again at once"
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: connection_support.turn_in_saved(taken:),
    )
  assert stays_open(taken: answered) && support.asked(answered) == None
    as "the answer returns the player to the world with nothing more to save"
  assert !restarts_the_save_timer(taken: answered)
    as "the timer already runs, so it is not started a second time"
}

pub fn a_quest_deadline_passing_while_a_sale_waits_botches_the_quest_once_the_sale_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  use state, taken <- selling_with_a_timed_quest
  let #(state, fired) =
    fired_at(state:, timer: connection_state.quest_deadline_timer, ms: 61_000)
  assert stays_open(taken: fired)
    as "the deadline timer that fires during the sale does not end the connection"
  assert quest_states(taken: fired) == [] && support.asked(fired) == None
    as "the botch waits for the store's answer to the sale"
  let #(_, answered) =
    answered_at(state:, taken:, outcome: sale_saved(), ms: 61_000)
  assert quest_states(taken: answered) == [botched_1872]
    as "quest 1872's time ran out at 61,000 ms: the client is told Botched once"
  assert asks_to_save_the_place(taken: answered) as "the botch is saved"
}

pub fn a_quest_reset_firing_while_an_item_move_waits_sends_the_reset_once_the_move_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = moving_an_item()
  let #(state, fired) =
    connection_support.feed_at(
      state:,
      filetime: monday_10,
      event: OwnEvent(TimerFired(connection_state.quest_reset_timer)),
    )
  assert stays_open(taken: fired) && connection_support.written_ids(fired) == []
    as "the reset timer that fires during the move does not end the connection and writes nothing yet"
  let assert Some(ask) = support.asked(taken) as "the move asks the store"
  let #(_, answered) =
    connection_support.feed_at(
      state:,
      filetime: monday_10,
      event: OwnEvent(step.Answered(
        ask: ask.ask,
        outcome: step.Answer(FromStore(store.ForItems(ItemsSaved))),
      )),
    )
  let resets =
    connection_support.written(taken: answered)
    |> list.filter(fn(frame) { frame.message_id == 0x0362 })
    |> list.map(fn(frame) {
      let assert Ok(message) = quest_periodic_reset.decode(frame.body)
        as "0x362 decodes"
      message
    })
  assert resets == [QuestPeriodicReset(reset_time: 1_745_834_400, periods: 1)]
    as "the Monday's daily reset is sent once, after the move's answer"
  assert list.contains(
    support.effects_of(answered),
    OwnEffect(StartTimer(connection_state.quest_reset_timer, 86_400_000)),
  )
    as "the reset timer starts again for the next day's reset"
}

pub fn a_save_timer_firing_while_a_departure_leaves_the_map_keeps_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, leaving) = connection_support.holocrypt_chosen()
  assert connection_support.ask_request(leaving)
    == connection_support.leave_asked()
  let #(state, fired) =
    fired_at(state:, timer: connection_state.save_timer, ms: 2000)
  assert stays_open(taken: fired) && support.asked(fired) == None
    as "a save timer that fires after the stay's timers were cancelled ends nothing"
  let #(_, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  assert asks_to_join(taken: joining)
    as "the leave's answer goes on to the join"
}

pub fn each_in_world_wait_takes_each_timer_without_ending_the_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  use turning_state, _ <- turning_in
  let waits = [
    #("a summon", summoning().0),
    #("an item move", moving_an_item().0),
    #("a buy", buying_plainly().0),
    #("a sale", selling().0),
    #("a turn-in", turning_state),
    #(
      "the periodic save",
      fired_at(
        state: connection_support.in_world(),
        timer: connection_state.save_timer,
        ms: 2000,
      ).0,
    ),
    #("a camp's save", connection_support.saving_the_camp().0),
    #("a leave of the map", connection_support.leaving_the_map().0),
    #("a departure's leave", connection_support.holocrypt_chosen().0),
  ]
  list.each(waits, fn(wait) {
    let #(name, state) = wait
    list.each(
      [
        connection_state.save_timer,
        connection_state.quest_reset_timer,
        connection_state.quest_deadline_timer,
      ],
      fn(timer) {
        let #(_, fired) = fired_at(state:, timer:, ms: 2000)
        assert stays_open(taken: fired) as name
      },
    )
  })
}
