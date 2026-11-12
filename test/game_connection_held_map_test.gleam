//// What the game connection does with a message a map sends it (a kill's credit, a
//// creature's strike) while the connection waits on the store, in a buy, a sale or a
//// turn-in (`genesis_prime/game/connection`). Expected values come from these places.
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

import character_tables
import connection_rule_support as support
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, FromStore, SentByKill,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/experience.{Credit}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_place
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/step.{type ConnectionEvent, type Event}
import genesis_prime/store.{HeldItem, NewStack}
import genesis_prime/table/id.{Creature2Id, Faction2Id, Item2Id}
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/stay.{type Stay}
import gleam/list
import gleam/option.{None}
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
/// Beast, that buys Item2 14838 at Dorian Walker for 67 of its 100 credits: the
/// connection waits on the store.
fn buying(
  then then: fn(game_connection.State, step.ConnectionStep(Request)) -> Nil,
) -> Nil {
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
  let state =
    at_the_vendor(
      state: connection_support.entered_stocking_with_quests(
        in_character_select: connection_support.in_select_from(fresh),
        credits: 100,
        items: [],
        quests: [quest_support.accepted(quest_id: 1857, progress: [0])],
      ),
    )
  let #(state, taken) =
    connection_support.purchase_requested(state:, unique_id: 2, quantity: 1)
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

pub fn a_held_message_for_an_earlier_stay_is_dropped_when_taken_test() -> Nil {
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

pub fn a_connection_that_ends_while_holding_map_messages_saves_as_before_test() -> Nil {
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
