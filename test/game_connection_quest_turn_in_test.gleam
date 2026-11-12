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
import experience_support
import game_connection_support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/random_stat_word
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/generic_error.{GenericError}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/step
import genesis_prime/store.{
  type QuestRow, AccountId, Character, CharacterId, ForItems, HeldItem, Items,
  ItemsNotSaved, NewStack, QuestRow, SaveRefused, TurnInQuest, TurnedIn,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import message_support
import owned_test
import planted_table.{type Cell, Integer}
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
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x00DD, 0x035C]
    as "an item added for each stack made, then the experience, then the credits held and, per opcode.0xdd, the credits gained, then the quest's state"
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
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x00DD, 0x035C, 0x0361]
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

/// Quest 9376's reward is Item2 48169, a bracer with three kind-2 entries on the group 11,
/// which has five rows (`random_stat_test`): the connection draws entropy for the stack and
/// the store is asked to make it with a word that holds three choices, each within 1 to 5
/// and no two the same.
pub fn a_turn_in_asks_the_store_to_make_a_random_stat_reward_with_a_rolled_word_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(9376),
  ])
  let state =
    quest_walker_support.in_world_with_walker(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 9376),
    ])
  let #(_, taken) =
    game_connection_support.read(state:, bytes: turn_in_of(quest_id: 9376))
  let assert TurnInQuest(placed: [placed], ..) = asked_turn_in(taken:)
    as "one reward item"
  assert placed.item2_id == Item2Id(48_169)
  let assert [NewStack(random_stats: word, ..)] = placed.make as "one stack"
  assert random_stat_word.has_data(word:)
    as "the stack is made with a word the client reads"
  let choices =
    list.map([0, 1, 2], fn(entry) { random_stat_word.choice(word:, entry:) })
  assert list.all(choices, fn(choice) { choice >= 1 && choice <= 5 })
    as "each entry takes one of the five rows of its group"
  assert list.unique(choices) == choices as "no two entries take the same row"
}

pub fn communicator_turn_in_sends_rewards_then_state_as_the_unit_dialog_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 10519 (flags 0x4008) is turned in over the communicator with no creature shown
  // to the player: the store is asked for what it is asked when the same player turns it
  // in at a receiver (Dorian Walker, given the quest), and the answer is written in the
  // unit dialog's order.
  let over_the_communicator =
    game_connection_support.world_message(
      message_id: 0x035D,
      body: quest_turn_in_support.body(
        scene: quest_turn_in_support.Scene(
          ..quest_turn_in_support.scene(quest_id: 10_519),
          by_communicator: 1,
        ),
      ),
    )
  let held = [quest_turn_in_support.achieved(quest_id: 10_519)]
  let alone =
    quest_walker_support.in_world_as(
      tables: character_tables.shared(),
      quests: held,
      character: Character(
        ..game_connection_support.world_character(),
        faction_id: 167,
      ),
    )
  let #(alone, by_communicator) =
    game_connection_support.read(state: alone, bytes: over_the_communicator)
  let assert TurnInQuest(
    experience:,
    level:,
    quests:,
    credits_held:,
    credits_after:,
    placed:,
    ..,
  ) = asked_turn_in(taken: by_communicator)
    as "the communicator's turn-in asks the store"
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(10_519),
  ])
  let at_the_unit =
    quest_walker_support.in_world_with_walker(tables:, quests: held)
  let #(at_the_unit, by_unit) =
    game_connection_support.read(
      state: at_the_unit,
      bytes: turn_in_of(quest_id: 10_519),
    )
  let assert TurnInQuest(
    experience: unit_experience,
    level: unit_level,
    quests: unit_quests,
    credits_held: unit_credits_held,
    credits_after: unit_credits_after,
    placed: unit_placed,
    ..,
  ) = asked_turn_in(taken: by_unit)
    as "the unit's turn-in asks the store"
  assert experience == unit_experience && level == unit_level
  assert quests == unit_quests
  assert credits_held == unit_credits_held
  assert credits_after == unit_credits_after
  assert placed == unit_placed
  assert quests
    == [
      QuestRow(
        quest_id: 10_519,
        state: 3,
        completed_at: Some(unix_seconds),
        active: None,
      ),
    ]
  let answer =
    step.Answer(FromStore(ForItems(TurnedIn(credits: credits_after, made: []))))
  let #(_, answered_by_communicator) =
    game_connection_support.answer(
      state: alone,
      taken: by_communicator,
      outcome: answer,
    )
  let #(_, answered_by_unit) =
    game_connection_support.answer(
      state: at_the_unit,
      taken: by_unit,
      outcome: answer,
    )
  assert game_connection_support.written_ids(answered_by_communicator)
    == game_connection_support.written_ids(answered_by_unit)
    as "the same frames in the same order"
  let assert Ok(state_frame) =
    list.last(game_connection_support.written(answered_by_communicator))
  assert quest_state.decode(state_frame.body)
    == Ok(QuestState(quest_id: 10_519, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest in state 3 with objective 0, last"
}

pub fn turning_in_a_quest_completes_another_quests_objective_that_names_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 7540's objective 13654 (type 24, data 6305, count 1) waits for quest 6305 to
  // be completed (`QuestObjective.type.24`); Dorian Walker is made to receive 6305, whose
  // rewards are three choices (Quest2Reward 3276, 4784 and 4785), so the player picks 3276.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.receiving(6305),
  ])
  let state =
    quest_walker_support.in_world_with_walker(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 6305),
      quest_support.accepted(quest_id: 7540, progress: [0, 0]),
    ])
  let #(state, taken) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.world_message(
        message_id: 0x035D,
        body: quest_turn_in_support.body(
          scene: quest_turn_in_support.Scene(
            ..quest_turn_in_support.scene(quest_id: 6305),
            reward_id: 3276,
          ),
        ),
      ),
    )
  let assert TurnInQuest(quests: saved, ..) = asked_turn_in(taken:)
    as "the accepted turn-in is the store's ask"
  assert list.any(saved, fn(row) { row.quest_id == 6305 && row.state == 3 })
    as "the ask saves quest 6305 completed, the quest the objective names"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(TurnedIn(credits: 0, made: [])))),
    )
  let frames = game_connection_support.written(answered)
  let assert [state_frame, progress_frame] =
    list.drop(frames, list.length(frames) - 2)
    as "the turn-in's state frame is followed by the other quest's progress"
  assert state_frame.message_id == 0x035C
    && state_frame.body
    == message_support.packed([#(15, 6305), #(32, 3), #(32, 0)])
    as "opcode.0x35c: quest 6305 is completed (state 3, objective 0)"
  assert progress_frame.message_id == 0x0361
    && progress_frame.body
    == message_support.packed([#(15, 7540), #(32, 0), #(32, 1)])
    as "opcode.0x361: quest 7540's objective 0 holds 1 of 1, after the completion that names it"
}

// ---- the server completes a quest no creature receives ----
//
// Quest 1857 (Quest2: flags 0, no Creature2 names it as its receiver) has one objective,
// 1961, a kill of one creature (type 2, count 1), which these tests make the Beast
// (Creature2 73464). It has no reward row, so the rows 4819 and 4821 of quest 5859 (the
// fixed items Item2 81917 and 29661) are moved to it where a test needs items. Quest
// 5859 (flags 0; Creature2 26071 receives it, so `quest_turn_in_support.unreceived_5859`
// clears that) is the quest a log holds Achieved at entry.

const beast = 73_464

/// The rows that make 1857's objective a kill of the Beast and give the quest the two
/// fixed items of quest 5859.
fn the_beast_quest_rows() -> List(#(String, Int, List(#(String, Cell)))) {
  [
    #("QuestObjective", 1961, [#("data", Integer(beast))]),
    #("Quest2Reward", 4819, [#("quest2Id", Integer(1857))]),
    #("Quest2Reward", 4821, [#("quest2Id", Integer(1857))]),
  ]
}

/// `then` run on the connection in the world on the tables the beast quest's rows and these
/// `changes` make, holding quest 1857 Accepted with nothing done.
fn with_the_beast_quest(
  changes changes: List(#(String, Int, List(#(String, Cell)))),
  then then: fn(game_connection.State) -> Nil,
) -> Nil {
  use tables <- quest_turn_in_support.with_changes(changes: list.append(
    the_beast_quest_rows(),
    changes,
  ))
  then(
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.accepted(quest_id: 1857, progress: [0]),
    ]).0,
  )
}

/// The Beast killed in the player's own stay.
fn the_beast_killed(
  state state: game_connection.State,
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  experience_support.credited(state:, creature_id: beast, level: 1)
}

/// The quest ids and states of the rows a turn-in saves.
fn saved_states(rows rows: List(QuestRow)) -> List(#(Int, Int)) {
  list.map(rows, fn(row) { #(row.quest_id, row.state) })
}

/// The state the 0x35c frame last written says the quest is in.
fn last_state_written(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> quest_state.QuestState {
  let assert Ok(frame) = list.last(game_connection_support.written(taken))
    as "a frame is written"
  let assert Ok(state) = quest_state.decode(frame.body)
    as "the last frame is a quest's state"
  state
}

pub fn a_server_completion_saves_the_quest_completed_and_answers_like_a_turn_in_test() -> Nil {
  use <- owned_test.run(10_000)
  use state <- with_the_beast_quest(changes: [])
  let #(state, killed) = the_beast_killed(state:)
  assert game_connection_support.written_ids(killed) == [0x01AC, 0x0361, 0x035C]
    as "the kill's experience, the progress and the state 2 the quest is Achieved in, as before the server completes it"
  let assert TurnInQuest(quests:, placed:, credits_held:, credits_after:, ..) =
    asked_turn_in(taken: killed)
    as "the quest no creature receives is completed by the server: the store is asked"
  assert quests
    == [
      QuestRow(
        quest_id: 1857,
        state: 3,
        completed_at: Some(unix_seconds),
        active: None,
      ),
    ]
    as "the log is saved with the quest Completed at the connection's Unix second"
  assert list.map(placed, fn(one) { one.item2_id })
    == [Item2Id(81_917), Item2Id(29_661)]
    as "the fixed items of its reward rows"
  assert credits_held == 0 && credits_after > 0
    as "the player held no credits and the quest pays some"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken: killed,
      outcome: game_connection_support.turn_in_saved(taken: killed),
    )
  let ids = game_connection_support.written_ids(answered)
  assert list.take(ids, 2) == [0x0111, 0x0111]
    as "opcode.0x111: an item added for each stack made, first, as at a creature's turn-in"
  assert list.take(list.drop(ids, 2), 1) == [0x01AC] as "then the experience"
  assert list.drop(ids, list.length(ids) - 3) == [0x0919, 0x00DD, 0x035C]
    as "the credits held and gained, then the quest's state last"
  assert last_state_written(taken: answered)
    == QuestState(quest_id: 1857, state: 3, objective_id: 0)
    as "opcode.0x35c: the quest in state 3 with objective 0"
}

pub fn two_quests_achieved_in_one_step_are_completed_one_after_the_other_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 1854's objective 1959 is made a kill of one Beast too (type 2, count 1), so one
  // kill achieves both quests. Neither has a receiver or a reward row.
  use tables <- quest_turn_in_support.with_changes(changes: [
    #("QuestObjective", 1961, [#("data", Integer(beast))]),
    #("QuestObjective", 1959, [
      #("type", Integer(2)),
      #("data", Integer(beast)),
      #("count", Integer(1)),
    ]),
  ])
  let #(state, _) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.accepted(quest_id: 1854, progress: [0]),
      quest_support.accepted(quest_id: 1857, progress: [0]),
    ])
  let #(state, killed) = the_beast_killed(state:)
  let assert TurnInQuest(quests: first, credits_after: first_credits, ..) =
    asked_turn_in(taken: killed)
    as "the first quest's completion is asked at the end of the kill's step"
  assert saved_states(rows: first) == [#(1854, 3), #(1857, 2)]
    as "the first ask saves quest 1854 Completed; quest 1857 is Achieved still, its completion waits"
  let #(state, first_answered) =
    game_connection_support.answer(
      state:,
      taken: killed,
      outcome: game_connection_support.turn_in_saved(taken: killed),
    )
  assert last_state_written(taken: first_answered)
    == QuestState(quest_id: 1854, state: 3, objective_id: 0)
    as "opcode.0x35c: quest 1854 is completed first, the answer's last frame"
  let assert TurnInQuest(quests: second, credits_held:, ..) =
    asked_turn_in(taken: first_answered)
    as "the answer returns the player to the world and the next completion is asked in the same step"
  assert saved_states(rows: second) == [#(1854, 3), #(1857, 3)]
    as "the second ask saves both Completed"
  assert credits_held == first_credits
    as "the second completion reads the credits the first one gave"
  let #(_, second_answered) =
    game_connection_support.answer(
      state:,
      taken: first_answered,
      outcome: game_connection_support.turn_in_saved(taken: first_answered),
    )
  assert last_state_written(taken: second_answered)
    == QuestState(quest_id: 1857, state: 3, objective_id: 0)
    as "opcode.0x35c: quest 1857 is completed second"
  assert support.asked(second_answered) == None as "no completion is left"
}

pub fn a_refused_server_completion_leaves_the_quest_achieved_and_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 1857's reward row 4819 is changed to a fixed TradeSkillXp row (Quest2Reward type
  // 4), which the rule refuses for every player (Quest2Reward 2471 of quest 5084 is the
  // client's own such row); the client refuses it only for a player with no learned
  // tradeskill. The tradeskill experience issue (#677) removes this refusal, and this
  // test then needs another refusal.
  use state <- with_the_beast_quest(changes: [
    #("Quest2Reward", 4819, [#("quest2RewardTypeId", Integer(4))]),
  ])
  let #(state, killed) = the_beast_killed(state:)
  assert game_connection_support.written_ids(killed) == [0x01AC, 0x0361, 0x035C]
    as "the kill's frames, the quest Achieved last: the refusal sends nothing"
  assert support.asked(killed) == None as "nothing is asked of the store"
  let assert [warning] = support.logs_of(step: killed, level: step.LogWarning)
    as "one warning says why"
  assert string.contains(warning.text, "tradeskill")
    as "the warning names the tradeskill reward, so no other check made the refusal"
  // The player is in the world: the next kill is taken at once, and the place save asks
  // the store to keep the log with the quest Achieved.
  let #(state, next) = the_beast_killed(state:)
  assert game_connection_support.written_ids(next) == [0x01AC]
    as "the next kill's experience is written, no other message waits"
  let #(_, saving) =
    game_connection_support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(store.Move(store.SavePlace(quests:, ..))) =
    game_connection_support.ask_request(saving)
    as "the save timer asks the store to save the place"
  assert saved_states(rows: quests) == [#(1857, 2)]
    as "the log holds the quest Achieved: the refused completion changed nothing"
}

pub fn a_full_bag_server_completion_sends_0x106_code_27_and_asks_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player holds 15 stacks of Item2 179, which holds one to a stack, and quest 5859
  // (Achieved in the saved log) gives two stacks.
  let filler =
    list.index_map(list.repeat(Nil, 15), fn(_, index) {
      quest_turn_in_support.in_bag(
        guid: 700 + index,
        item2_id: 179,
        index:,
        count: 1,
      )
    })
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.unreceived_5859(),
  ])
  let #(state, entered) =
    game_connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [quest_turn_in_support.achieved(quest_id: 5859)],
      items: filler,
    )
  assert support.asked(entered) == None
    as "the completion is refused before the store is asked"
  let assert Ok(refusal) = list.last(game_connection_support.written(entered))
    as "the entry's last frame is the refusal"
  assert refusal.message_id == 0x0106
    && generic_error.decode(refusal.body) == Ok(GenericError(code: 27))
    as "opcode.0x106: code 27, Item_InventoryFull"
  let #(_, saving) =
    game_connection_support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(store.Move(store.SavePlace(quests:, ..))) =
    game_connection_support.ask_request(saving)
    as "the player is in the world: the save timer asks the store to save the place"
  assert saved_states(rows: quests) == [#(5859, 2)]
    as "the quest is Achieved still, to be completed on a later login"
}

pub fn a_relog_with_a_quest_achieved_completes_it_after_the_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 (no receiver; fixed items Item2 81917 and 29661, 152 experience and 145
  // credits at level 4) is saved Achieved, as a player leaves it who logged out before the
  // server completed it.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.unreceived_5859(),
  ])
  let #(state, entered) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 5859),
    ])
  assert list.contains(game_connection_support.written_ids(entered), 0x035F)
    as "opcode.0x35f: the entry tells the client its log, the quest Achieved"
  let assert TurnInQuest(quests:, placed:, credits_after:, ..) =
    asked_turn_in(taken: entered)
    as "after the entry's frames the store is asked for the completion"
  assert quests
    == [
      QuestRow(
        quest_id: 5859,
        state: 3,
        completed_at: Some(unix_seconds),
        active: None,
      ),
    ]
  assert list.map(placed, fn(one) { one.item2_id })
    == [Item2Id(81_917), Item2Id(29_661)]
  assert credits_after == 145
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken: entered,
      outcome: game_connection_support.turn_in_saved(taken: entered),
    )
  assert game_connection_support.written_ids(answered)
    == [0x0111, 0x0111, 0x01AC, 0x0919, 0x00DD, 0x035C]
    as "the frames of a turn-in at a creature of the same quest, the quest's state last"
  assert last_state_written(taken: answered)
    == QuestState(quest_id: 5859, state: 3, objective_id: 0)
}

pub fn a_store_that_cannot_answer_a_server_completion_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.unreceived_5859(),
  ])
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      step.NotRunning,
      step.NoAnswerInTime,
      step.EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, entered) =
        game_connection_support.entered_with_quests_on(tables:, quests: [
          quest_turn_in_support.achieved(quest_id: 5859),
        ])
      let #(_, answered) =
        game_connection_support.answer(state:, taken: entered, outcome:)
      assert list.length(support.logs_of(step: answered, level: step.LogError))
        == 1
        as "a completion whose outcome is unknown is an error line"
      assert game_connection_support.written_ids(answered) == [0x036A]
        as "no frame but the disconnect notice: nothing says whether the completion was saved"
      assert support.asked(answered) == None
        as "no save of the old log follows: the completion's own may still commit"
      assert game_connection_support.disconnect(
          answered,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "0x036A reason 8"
    },
  )
}
