//// The game connection's quest turn-in (`genesis_prime/game/connection/quest_turn_in`,
//// `genesis_prime/game/quest_turn_in`): the client's 0x035D read inside 0x038C with
//// Dorian Walker (Creature2 74812) in reach, and the store's answer. Expected values
//// come from these places.
//// - `opcode.0x35c`: the answer is the quest in 15 bits, the state in 32 and the
////   objective in 32; a turn-in is state 3 (`0x1405fbdc0.state_3`) with objective 0.
//// - `opcode.0x111`, `opcode.0x1ac`, `opcode.0x938`, `opcode.0x919`: an item made, the
////   experience of kind 3, the level the experience makes and the credits the player holds.
//// - The turn-in's time is the connection's clock in Unix seconds: the tests' FILETIME
////   133,900,000,000,000,000 is 13,390,000,000,000 ms after 1601, and 11,644,473,600,000 ms
////   lie between 1601 and 1970, so 1,745,526,400 s after 1970.
//// - The quest rows saved are the next login's: a quest saved Completed is no longer
////   Achieved, so a second turn-in of it is refused and asks nothing (`0x140553030`).
//// - Failure table, a store that cannot say what it did ends the connection with reason 8;
////   a store that changed nothing or refused the save leaves the player in the world with
////   the quest Achieved; a connection that ends while the turn-in waits asks the store
////   nothing more, because the turn-in's own save carries the place.

import character_tables
import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/step
import genesis_prime/store.{
  type QuestRow, AccountId, CharacterId, ForItems, HeldItem, Items,
  ItemsNotSaved, NewStack, QuestRow, SaveRefused, TurnInQuest, TurnedIn,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{None, Some}
import message_support
import owned_test
import planted_table.{Integer}
import quest_support
import quest_turn_in_support
import quest_walker_support

/// The Unix second the tests' connection is at.
const unix_seconds = 1_745_526_400

/// The client's 0x035D for quest `quest_id` and no reward choice.
fn turn_in_of(quest_id quest_id: Int) -> BitArray {
  game_connection_support.world_message(
    message_id: 0x035D,
    body: quest_turn_in_support.body(scene: quest_turn_in_support.scene(
      quest_id:,
    )),
  )
}

/// The store's ask for a turn-in, the pieces a test checks.
fn asked_turn_in(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> store.ItemsRequest {
  let assert AskStore(Items(request)) =
    game_connection_support.ask_request(taken)
    as "the accepted turn-in is the store's ask"
  request
}

pub fn turned_in_answer_sends_rewards_then_state_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 10520 gives 1055 experience, which is the level 2 (XpPerLevel 2 starts at 655).
  let state =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
    )
  let #(state, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 10_520))
  let assert TurnInQuest(
    account_id:,
    character_id:,
    save_sequence:,
    experience:,
    level:,
    quests:,
    credits_held:,
    credits_after:,
    placed:,
    ..,
  ) = asked_turn_in(taken:)
    as "a TurnInQuest"
  assert account_id == AccountId(7) && character_id == CharacterId(42)
  assert save_sequence == 1 as "the first save of the connection"
  assert experience == 1055 && level == 2
    as "the override 1055 from 0 is level 2's range"
  assert quests
    == [
      QuestRow(
        quest_id: 10_520,
        state: 3,
        completed_at: Some(unix_seconds),
        active: None,
      ),
    ]
    as "the log is saved with the quest Completed at the connection's Unix second"
  assert credits_held == 0 && credits_after == 0 && placed == []
    as "quest 10520 has no reward row, and difficulty 6 pays no credits"
  assert support.writes(taken) == []
    as "nothing is written before the store has saved the turn-in"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(TurnedIn(credits: 0, made: [])))),
    )
  assert game_connection_support.written_ids(answered)
    == [0x01AC, 0x0938, 0x093A, 0x035C]
    as "the experience, the level it made and the properties the level moves, then the quest's state last"
  let frames = game_connection_support.written(answered)
  let assert [gained, ..] = frames
  assert experience_gained.decode(gained.body)
    == Ok(ExperienceGained(
      experience: 1055,
      rest_experience_used: 0,
      bonus_experience: 0,
      source_kind: 3,
      source_unit_id: 0,
    ))
    as "opcode.0x1ac: kind 3 for a quest, from no unit"
  let assert Ok(state_frame) = list.last(frames)
  assert quest_state.decode(state_frame.body)
    == Ok(QuestState(quest_id: 10_520, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest in state 3 with objective 0"
}

pub fn turned_in_rewards_are_written_before_the_experience_and_the_state_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 gives Item2 81917 and 29661 (one of each), 152 experience and 145 credits.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(5859),
  ])
  let state =
    quest_walker_support.in_world_with_walker(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 5859),
    ])
  let #(state, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 5859))
  let assert TurnInQuest(credits_after:, placed:, ..) = asked_turn_in(taken:)
  assert credits_after == 145
  assert list.map(placed, fn(one) { one.item2_id })
    == [Item2Id(81_917), Item2Id(29_661)]
  let made =
    list.index_map(placed, fn(one, index) {
      let assert [
        NewStack(location:, bag_index:, stack_count:, random_stats: 0),
      ] = one.make
        as "one stack of each, the Item2s' counts being 1"
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
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(TurnedIn(credits: 145, made:)))),
    )
  assert game_connection_support.written_ids(answered)
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x035C]
    as "an item added for each stack made, then the experience, then the credits held, then the quest's state"
}

pub fn reward_items_advance_the_held_item_objectives_of_other_quests_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 gives Item2 81917 (one) and 29661. Quest 1854, taken and holding none, has a
  // type 4 objective (1959, count 3) whose data is changed to 81917, the way 16 Item2s are
  // both an item reward and the data of a type 4 objective in the client's tables.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(5859),
    #("QuestObjective", 1959, [#("data", Integer(81_917))]),
  ])
  let state =
    quest_walker_support.in_world_with_walker(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 5859),
      quest_support.accepted(quest_id: 1854, progress: [0]),
    ])
  let #(state, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 5859))
  let assert TurnInQuest(placed:, ..) = asked_turn_in(taken:)
  let made =
    list.index_map(placed, fn(one, index) {
      let assert [
        NewStack(location:, bag_index:, stack_count:, random_stats: 0),
      ] = one.make
        as "one stack of each, the Item2s' counts being 1"
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
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(TurnedIn(credits: 145, made:)))),
    )
  assert game_connection_support.written_ids(answered)
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x035C, 0x0361]
    as "the turn-in's frames, then the progress of the other quest the reward item counts"
  let assert Ok(progress) = list.last(game_connection_support.written(answered))
  assert progress.body
    == message_support.packed([#(15, 1854), #(32, 0), #(32, 1)])
    as "opcode.0x361: quest 1854's objective 0 holds 1 of 3, the stack of 81917 the reward made"
}

pub fn turn_in_not_saved_leaves_the_quest_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(ItemsNotSaved, step.LogWarning),
      #(SaveRefused(constraint: "character_item_one_per_slot"), step.LogError),
    ],
    fn(case_) {
      let state =
        quest_walker_support.in_world_with_walker(
          tables: character_tables.shared(),
          quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
        )
      let #(state, taken) =
        game_connection_support.read(
          state:,
          bytes: turn_in_of(quest_id: 10_520),
        )
      let assert TurnInQuest(save_sequence: first, ..) = asked_turn_in(taken:)
      // The same message again while the ask is out: it waits behind the first.
      let #(state, held) =
        game_connection_support.read(
          state:,
          bytes: turn_in_of(quest_id: 10_520),
        )
      assert support.writes(held) == [] && support.asked(held) == None
        as "step.EffectsThenAsk: a frame that arrives while the turn-in waits is held"
      let #(_, answered) =
        game_connection_support.answer(
          state:,
          taken:,
          outcome: step.Answer(FromStore(ForItems(case_.0))),
        )
      assert game_connection_support.written(answered) == []
        as "nothing is sent: no 0x106, no experience, no state"
      assert list.length(support.logs_of(step: answered, level: case_.1)) == 1
        as "one line, a warning for a change that did nothing and an error for a refused save"
      // The quest is Achieved still: the held message is taken after the answer and
      // asks the store again, with the next save number.
      let assert TurnInQuest(save_sequence: second, quests:, ..) =
        asked_turn_in(taken: answered)
        as "the player is in the world and the quest is still Achieved"
      assert second == first + 1
        as "the save the store did not make is not reused: the next carries the next number"
      assert list.map(quests, fn(row: QuestRow) { row.state }) == [3]
    },
  )
}

pub fn turned_in_quest_cannot_be_turned_in_again_after_reload_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
    )
  let #(_, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 10_520))
  let assert TurnInQuest(quests: saved, ..) = asked_turn_in(taken:)
  // The next login loads the rows the turn-in saved.
  let reloaded =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: saved,
    )
  let #(_, again) =
    game_connection_support.read(
      state: reloaded,
      bytes: turn_in_of(quest_id: 10_520),
    )
  assert support.asked(again) == None
    as "a Completed quest is not Achieved: nothing is asked"
  assert game_connection_support.written(again) == []
    as "and nothing is written"
}

pub fn connection_that_ends_while_turning_in_asks_nothing_more_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
    )
  let #(state, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 10_520))
  let assert TurnInQuest(quests: saved, ..) = asked_turn_in(taken:)
  let #(_, ended) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert support.asked(ended) == None
    as "the turn-in's own save carries the place, so the end asks for no second save of the old log"
  // The turn-in's save is the only one: the next login loads the quest Completed.
  let reloaded =
    quest_walker_support.in_world_with_walker(
      tables: character_tables.shared(),
      quests: saved,
    )
  let #(_, again) =
    game_connection_support.read(
      state: reloaded,
      bytes: turn_in_of(quest_id: 10_520),
    )
  assert support.asked(again) == None
    as "the quest is Completed on the next login, its rewards given once"
}

pub fn a_turn_in_the_store_cannot_answer_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      step.NotRunning,
      step.NoAnswerInTime,
      step.EndedBeforeAnswer,
    ],
    fn(outcome) {
      let state =
        quest_walker_support.in_world_with_walker(
          tables: character_tables.shared(),
          quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
        )
      let #(state, taken) =
        game_connection_support.read(
          state:,
          bytes: turn_in_of(quest_id: 10_520),
        )
      let #(_, answered) =
        game_connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: step.LogError))
        == 1
        as "a turn whose outcome is unknown is an error line"
      assert game_connection_support.written_ids(answered) == [0x036A]
        as "no frame but the disconnect notice: nothing says whether the turn-in was saved"
      assert support.asked(answered) == None
        as "no save of the old log follows: the turn-in's own may still commit"
      assert game_connection_support.disconnect(
          answered,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "0x036A reason 8"
    },
  )
}
