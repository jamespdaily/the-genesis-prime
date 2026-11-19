//// The development commands on the game connection (`genesis_prime/game/connection/dev_command`),
//// run as the pure rule it is: a line said on Say in, the frames and effects out. Expected
//// values come from these places.
//// - `opcode.0x1ac`: the client takes experience only by message, adding the first value to
////   its own; the source kind 1 is Cheat (`opcode.0x1ac.kind.1`). No message lowers it.
//// - `opcode.0x938`: stat 10 is the level. `opcode.0x169`: ability points, 0 for levels 1 to
////   9 (XpPerLevel.abilityPointsPerLevel).
//// - XpPerLevel.minXpForLevel: level 3 from 1710, 4 from 2860, 9 from 17330.
//// - The rise's frames are those of a gain of any source: `experience_book_test` (a Medic's
////   3 to 4 writes 0x1ac, 0x938, 0x111, 0x1a0, 0x93a, with the ability of Spell4Base 26038
////   in slot 4; 5 to 6 adds 25530, 25579 and 38210) and `experience_points_test`.
//// - `SpellLevel.spell4Id.no_prerequisite`: the committed rows hold a Medic's abilities up to
////   level 6 (`ability_book_test`): 614 (level 4, Spell4Base 26038), 1087 (5, 25692), 1191,
////   1194 and 1221 (6, 25530, 25579, 38210). A rise to level 9 grants all five, in that
////   order, in slots 4 to 8 after the bag of 4 items, and one 0x1a0 holds each at tier 1 in
////   the four action sets (`opcode.0x1a0`).
//// - The line each command is answered with is the design's choice (a System line,
////   ChatChannel row 2).
//// - `opcode.0x35c.complete_unheld`, `0x1405fbdc0.state_3`: the client takes 0x35c state 3
////   for a quest with no log entry. Quest2 2910 holds a limit of 30000 ms, 1857 is daily
////   (questRepeatPeriodEnum 1) and 10503 yearly (4); the tests' clock is 2025-04-24 20:26:40
////   UTC, the latest daily reset 2025-04-24 10:00 and the latest yearly reset 2025-01-01
////   10:00 (`quest_log_test`).
//// - QuestObjective 18604 (type 24, data 9695) of Quest2 9497 is done when quest 9695 is
////   finished; no Creature2 row receives 9497 or 9695, so the server completes them
////   (`communicator.completed_by_server`).

import ability_book_support as book_support
import ability_points_support as points_support
import character_support
import character_tables
import connection_rule_support as rule_support
import departures_support
import experience_support
import fixture_tables
import game_client
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request, TellMoved, TellTargetMoved}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/float32
import genesis_prime/message/quest_objective_progress.{
  type QuestObjectiveProgress, QuestObjectiveProgress,
}
import genesis_prime/message/quest_state.{type QuestState, QuestState}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, OwnEffect, OwnEvent, Unwatch, Watch,
}
import genesis_prime/store
import genesis_prime/table/id.{Item2Id}
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import item_expiry_support
import message_support
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import quest_turn_in_support

/// A Medic (class 4), level 3, holding 1800 experience: 90 past level 3's 1710.
fn medic() -> game_connection.State {
  dev_support.in_world_at(class_id: 4, level: 3, experience: 1800)
}

/// One raise: the line said, what the frames start and end with, the gain and
/// the levels written, the abilities the rise adds (bag index and Spell4Base, in order),
/// the line answered and what the player holds afterwards.
type Raise {
  Raise(
    text: String,
    starts: List(Int),
    ends: List(Int),
    gain: Int,
    levels: List(Int),
    added: List(#(Int, Int)),
    line: String,
    held: #(Int, Int),
    why: String,
  )
}

pub fn a_raise_writes_the_frames_of_an_experience_gain_and_the_level_rise_then_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Raise(
        text: "!level 4",
        starts: [0x01C2, 0x01AC, 0x0938, 0x0111],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 1060,
        levels: [4],
        added: [#(4, 26_038)],
        line: "level 4, experience 2860",
        held: #(4, 2860),
        why: "level 4 starts at 2860, 1060 above 1800; the Medic's 3 to 4 adds Spell4Base 26038",
      ),
      Raise(
        text: "!xp 2859",
        starts: [0x01C2, 0x01AC],
        ends: [0x01AC, 0x01C8],
        gain: 1059,
        levels: [],
        added: [],
        line: "level 3, experience 2859",
        held: #(3, 2859),
        why: "2859 is one short of level 4: a gain and no level",
      ),
      Raise(
        text: "!level 9",
        starts: [0x01C2, 0x01AC, 0x0938],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 15_530,
        levels: [9],
        added: [
          #(4, 26_038),
          #(5, 25_692),
          #(6, 25_530),
          #(7, 25_579),
          #(8, 38_210),
        ],
        line: "level 9, experience 17330",
        held: #(9, 17_330),
        why: "level 9 starts at 17330: one 0x938 for the whole jump, and the five abilities the rows hold for levels 4 to 6",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.text)
      let ids = support.written_ids(taken)
      assert list.take(ids, list.length(row.starts)) == row.starts as row.why
      assert list.drop(ids, list.length(ids) - list.length(row.ends))
        == row.ends
        as "the frames end with the player's line"
      assert experience_support.gains(taken:)
        == [
          ExperienceGained(
            experience: row.gain,
            rest_experience_used: 0,
            bonus_experience: 0,
            source_kind: 1,
            source_unit_id: 0,
          ),
        ]
        as row.why
      assert list.map(experience_support.level_writes(taken:), fn(written) {
          written.1
        })
        == row.levels
        as row.why
      let frames = book_support.written(taken:)
      let added = book_support.added_in(frames:)
      assert list.map(added, fn(item) { #(item.bag_index, item.base) })
        == row.added
        as "the rise adds exactly the abilities its levels grant, in order, once each"
      assert list.all(added, fn(item) { item.reason == 49 })
        as "opcode.0x111.ability_level_up: reason 49, as the entry's"
      assert book_support.tiers_in(frames:)
        == book_support.tiers_of(
          bases: list.map(row.added, fn(item) { item.1 }),
        )
        as "one 0x1a0 holds each added ability at tier 1 in the four action sets"
      assert points_support.points_in(frames:) == []
        as "levels 1 to 9 give no ability points"
      assert support.system_lines(taken) == [row.line] as row.why
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == row.held
        as "the player holds the level and experience reached"
    },
  )
}

pub fn a_lowering_or_an_equal_target_changes_nothing_and_says_so_in_one_system_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "!level 2",
        "!level 2 would lower level 3; the client takes experience only upward: use a character at or below level 2",
        "a level below the held 3",
      ),
      #(
        "!xp 1500",
        "!xp 1500 would lower experience 1800; the client takes experience only upward: use a character at or below experience 1500",
        "an experience below the held 1800",
      ),
      #(
        "!xp 1800",
        "already at level 3, experience 1800",
        "the experience held",
      ),
      #(
        "!level 3",
        "already at level 3, experience 1800",
        "the level held, though 1800 is above its 1710",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8]
        as "opcode.0x1ac: no frame lowers the client's experience, so none is written"
      assert support.system_lines(taken) == [row.1] as row.2
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == #(3, 1800) as "nothing changed"
    },
  )
}

pub fn the_next_save_holds_the_commanded_level_and_experience_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = dev_support.said(state: medic(), text: "!level 4")
  let #(_, taken) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(
    experience:,
    level:,
    ..,
  ))) = support.ask_request(taken)
    as "the save timer asks the store to save the place"
  assert #(level, experience) == #(4, 2860)
    as "XpPerLevel: level 4 starts at 2860, which the save keeps"
}

pub fn each_accepted_command_is_logged_once_at_info_and_a_refused_one_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, accepted) = dev_support.said(state: medic(), text: "!level 4")
  let assert [line] = rule_support.logs_of(step: accepted, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!level 4")
    && string.contains(line.text, "experience 1800")
    && string.contains(line.text, "experience 2860")
    as "it names the command and the values it changed"
  let #(_, refused) = dev_support.said(state: medic(), text: "!level 51")
  assert rule_support.logs(refused) == []
    as "a refused command is its System line, with no log"
}

// ---- !item ----
//
// Expected values: Item2 90021 (maxStackCount 1, maxCharges 5), 14838 (maxStackCount 50),
// 37649 (maxStackCount 1, maxCharges 1, expirationTimeMinutes 30) and 48169 (a random-stat
// row, ItemStat 432) are the client's rows (`fixture_tables`); the stacks go to the first free
// bag slots (`vendor_purchase`), and the Novice set is worn at location 0, so slot 0 is free.
// A given item is a purchase of cost 0 in credits (the design's choice); its frames are
// `opcode.0x111` and `opcode.0x17f` with the reason 4, Cheat (`opcode.0x111.reason_cheat`).

/// The tests' connection with the development commands on, holding `credits`, in the world.
fn holding(credits credits: Int) -> game_connection.State {
  support.entered_with_dev_commands(
    tables: character_tables.shared(),
    quests: [],
    items: [],
    credits:,
  )
}

/// The stack the connection's ask makes of a given item at the first bag slot.
fn new_stack(
  count count: Int,
  charges charges: Int,
  expires_at_unix_ms expires_at_unix_ms: Option(Int),
) -> store.NewStack {
  store.NewStack(
    location: 1,
    bag_index: 0,
    stack_count: count,
    words: store.ItemWords(
      random_stats: 0,
      charges:,
      item_flags: 0,
      expires_at_unix_ms:,
    ),
  )
}

/// The purchase of cost 0 the connection asks the store for: the account 7, the character 42
/// and the epoch 1 the tests' connection holds.
fn asked_for(
  item2_id item2_id: Int,
  held held: Int,
  make make: List(store.NewStack),
) -> client_connection.Request {
  client_connection.AskStore(
    store.Items(store.BuyFromVendor(
      account_id: store.AccountId(7),
      character_id: store.CharacterId(42),
      session_epoch: character_support.epoch(1),
      currency_type_id: 1,
      held:,
      cost: 0,
      grow: [],
      make:,
      item2_id: Item2Id(item2_id),
    )),
  )
}

pub fn an_item_command_asks_the_store_for_a_purchase_of_no_cost_and_waits_in_buying_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    dev_support.said(state: holding(credits: 700), text: "!item 90021")
  assert support.written_ids(taken) == [0x01C2]
    as "opcode.0x1c2: only the line's own answer, the items are shown after the store's"
  assert support.ask_request(taken)
    == asked_for(item2_id: 90_021, held: 700, make: [
      new_stack(count: 1, charges: 5, expires_at_unix_ms: None),
    ])
    as "a purchase of cost 0 holding the 700 credits, one stack with the row's 5 charges and no roll (no random-stat row)"
  let assert Some(ask) = rule_support.asked(taken)
  assert ask.deadline_ms == rule_support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  let #(_, held) = dev_support.said(state:, text: "!item 90021")
  assert support.written_ids(held) == [] && rule_support.asked(held) == None
    as "the connection waits for the answer in Buying: a second line is held, not run"
  // Item2 48169 has a random-stat row, so the stack is made with a rolled word.
  let #(_, rolling) =
    dev_support.said(state: holding(credits: 0), text: "!item 48169")
  let assert client_connection.AskStore(store.Items(store.BuyFromVendor(
    make: [made],
    held: 0,
    ..,
  ))) = support.ask_request(rolling)
    as "a character with no credits row holds 0"
  assert made.words.random_stats != 0
    as "ItemStat 432's kind-2 entries are rolled as a bought item's are"
}

pub fn an_item_answer_updates_the_items_and_writes_the_frames_and_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  let expires = Some(item_expiry_support.unix_at(30 * 60_000))
  let #(state, taken) =
    dev_support.said(state: holding(credits: 0), text: "!item 37649")
  assert support.ask_request(taken)
    == asked_for(item2_id: 37_649, held: 0, make: [
      new_stack(count: 1, charges: 1, expires_at_unix_ms: expires),
    ])
    as "Item2 37649 runs out 30 minutes after it is made (expirationTimeMinutes 30)"
  let #(state, answered) =
    support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        client_connection.FromStore(
          store.ForItems(
            store.Bought(amount: 0, made: [
              item_expiry_support.held(
                guid: 900,
                item2: 37_649,
                location: 1,
                bag_index: 0,
                count: 1,
                expires_at_unix_ms: expires,
              ),
            ]),
          ),
        ),
      ),
    )
  assert support.written_ids(answered) == [0x0111, 0x01C8]
    as "the stack's 0x111 and one line, and no 0x919: the credits did not change"
  assert support.system_lines(answered) == ["gave 1 x Item2 37649"]
  assert item_expiry_support.timers(taken: answered) == [#("start", 1_800_000)]
    as "the timed item starts the item expiry timer for its lifetime"
  assert item_expiry_support.times_left(taken: answered) == [#(900, 1_800_000)]
    as "opcode.0x111.time_left: the new item is sent with its whole lifetime"
  let #(_, next) = dev_support.said(state:, text: "!item 90021")
  let assert client_connection.AskStore(store.Items(store.BuyFromVendor(
    make: [second],
    ..,
  ))) = support.ask_request(next)
    as "the next item is asked for"
  assert second.bag_index == 1
    as "the connection holds the new stack in slot 0, so the next one goes to slot 1"
}

pub fn a_store_that_gives_no_answer_to_an_item_ask_ends_the_connection_with_reason_8_and_saves_the_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    dev_support.said(state: holding(credits: 0), text: "!item 90021")
  let #(state, answered) =
    support.answer(state:, taken:, outcome: step.NoAnswerInTime)
  assert support.written_ids(answered) == []
    as "no item frame: the items were never shown"
  let assert client_connection.AskStore(store.Move(store.SavePlace(..))) =
    support.ask_request(answered)
    as "the place is saved once, as in the world"
  assert list.length(rule_support.logs_of(step: answered, level: step.LogError))
    == 1
    as "a purchase whose outcome is unknown is an error line"
  let #(_, ended) =
    support.answer(state:, taken: answered, outcome: support.place_saved())
  assert support.disconnect(ended, support.keyed()) == LostUserServer
    as "0x036A reason 8 when the save is answered, and the connection ends"
}

pub fn a_collect_objective_the_given_item_closes_advances_after_the_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 1854's objective 1959 (type 4, count 3) names Item2 3993, which the Item2 table
  // lacks, so its data is changed to 14838 as `game_connection_objective_test` does.
  let rows = case
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 1959,
      with: [#("data", Integer(14_838))],
    )
  {
    Ok(changed) -> changed
    Error(refusal) -> panic as fixture_tables.describe(refusal)
  }
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let state =
    support.entered_with_dev_commands(
      tables:,
      quests: [quest_support.accepted(quest_id: 1854, progress: [0])],
      items: [],
      credits: 0,
    )
  let #(state, taken) = dev_support.said(state:, text: "!item 14838 3")
  let #(_, answered) =
    support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        client_connection.FromStore(
          store.ForItems(
            store.Bought(amount: 0, made: [
              item_expiry_support.held(
                guid: 900,
                item2: 14_838,
                location: 1,
                bag_index: 0,
                count: 3,
                expires_at_unix_ms: None,
              ),
            ]),
          ),
        ),
      ),
    )
  assert support.written_ids(answered) == [0x0111, 0x01C8, 0x0361, 0x035C]
    as "the stack and the line, then the objective's progress and its state: the items close it"
  let quest_frames =
    list.filter_map(support.written(answered), fn(frame) {
      case frame.message_id == 0x0361 || frame.message_id == 0x035C {
        True -> Ok(#(frame.message_id, frame.body))
        False -> Error(Nil)
      }
    })
  assert quest_frames
    == [
      #(0x0361, message_support.packed([#(15, 1854), #(32, 0), #(32, 3)])),
      #(0x035C, message_support.packed([#(15, 1854), #(32, 2), #(32, 0)])),
    ]
    as "opcode.0x361: 3 of 3 for objective 0, and opcode.0x35c: the quest is Achieved (2)"
}

pub fn each_item_use_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, accepted) =
    dev_support.said(state: holding(credits: 0), text: "!item 90021 2")
  let assert [line] = rule_support.logs_of(step: accepted, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!item 90021 2")
    as "it names the command and its values"
  let full =
    support.entered_with_dev_commands(
      tables: character_tables.shared(),
      quests: [],
      items: list.index_map(list.repeat(Nil, 16), fn(_, index) {
        item_expiry_support.held(
          guid: 700 + index,
          item2: 14_838,
          location: 1,
          bag_index: index,
          count: 50,
          expires_at_unix_ms: None,
        )
      }),
      credits: 0,
    )
  let #(_, refused) = dev_support.said(state: full, text: "!item 90021")
  assert support.system_lines(refused)
    == ["bag full: no room for 1 x Item2 90021"]
    as "a bag with no room is one system line"
  assert support.written_ids(refused) == [0x01C2, 0x01C8]
    && rule_support.asked(refused) == None
    && rule_support.logs(refused) == []
    as "nothing is asked and a refused command has no log"
}

// ---------------------------------------------------------------- !quest

/// The Unix seconds of the tests' clock: the FILETIME 133,900,000,000,000,000 is
/// 2025-04-24 20:26:40 UTC.
const now_seconds = 1_745_526_400

/// The daily quest reset before `now_seconds`: 2025-04-24 10:00 UTC
/// (`quest_log_test`).
const daily_reset_seconds = 1_745_488_800

/// The first FILETIME after the next daily reset (2025-04-25 10:00 UTC, one second
/// past it) and after the next yearly reset (2026-01-01 10:00 UTC, one second past
/// it).
const after_the_next_daily_reset = 133_900_488_010_000_000

const after_the_next_yearly_reset = 134_117_352_010_000_000

/// The quest states the step writes, decoded.
fn quest_states_written(
  taken taken: ConnectionStep(Request),
) -> List(QuestState) {
  support.decoded(
    support.written(taken:),
    quest_state.message_id,
    quest_state.decode,
  )
}

/// The effects of the step that start or cancel the quest deadline timer.
fn deadline_timer_effects(
  taken taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(rule_support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.StartTimer(timer:, ..))
      | step.OwnEffect(step.CancelTimer(timer:)) ->
        timer == connection_state.quest_deadline_timer
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

/// One quest done by command: what the log holds, the quest, the timer effects the step
/// holds, and why.
type Completion {
  Completion(
    held: List(store.QuestRow),
    quest_id: Int,
    timer: List(step.Effect(step.ConnectionEffect(Request))),
    why: String,
  )
}

pub fn a_completed_quest_is_completed_in_the_log_and_told_as_state_3_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Completion(
        held: [],
        quest_id: 5972,
        timer: [],
        why: "a quest with no entry: the client takes state 3 for it (opcode.0x35c.complete_unheld)",
      ),
      Completion(
        held: [quest_support.timed(2910, progress: [0], quest_ms_left: 0)],
        quest_id: 2910,
        timer: [
          step.OwnEffect(step.CancelTimer(connection_state.quest_deadline_timer)),
        ],
        why: "Quest2 2910's limit is 30000 ms: the entry's running deadline timer is cancelled with the quest completed",
      ),
      Completion(
        held: [quest_turn_in_support.achieved(quest_id: 10_520)],
        quest_id: 10_520,
        timer: [],
        why: "an Achieved quest a creature receives is completed in the log as well",
      ),
    ],
    fn(row) {
      let state =
        dev_support.in_world_holding_quests(level: 1, quests: row.held)
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(row.quest_id) <> " done",
        )
      assert support.written_ids(taken) == [0x01C2, 0x035C, 0x01C8] as row.why
      assert quest_states_written(taken:)
        == [QuestState(quest_id: row.quest_id, state: 3, objective_id: 0)]
        as row.why
      assert support.system_lines(taken)
        == ["quest " <> int.to_string(row.quest_id) <> " completed"]
        as row.why
      assert deadline_timer_effects(taken:) == row.timer as row.why
      assert dev_support.saved_quests(state:)
        == [quest_support.completed(row.quest_id, at: now_seconds)]
        as "the log holds the quest Completed at now, and nothing else"
    },
  )
}

pub fn a_quest_already_done_is_answered_so_and_writes_no_frame_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        quest_support.completed(quest_support.one_time, at: 1_700_000_000),
        "a quest with no period that was completed",
      ),
      #(
        quest_support.completed(
          quest_support.daily,
          at: daily_reset_seconds + 100,
        ),
        "a daily quest completed after the latest daily reset",
      ),
    ],
    fn(row) {
      let held = row.0
      let state = dev_support.in_world_holding_quests(level: 1, quests: [held])
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(held.quest_id) <> " done",
        )
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.1
      assert support.system_lines(taken)
        == ["quest " <> int.to_string(held.quest_id) <> " is already done"]
        as row.1
      assert dev_support.saved_quests(state:) == [held]
        as "the entry is as it was"
      assert rule_support.logs(taken) == []
        as "a command that changes nothing is its line, with no log"
    },
  )
}

pub fn a_periodic_quest_done_in_an_earlier_period_is_completed_again_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        quest_support.daily,
        daily_reset_seconds - 1,
        "one second before the latest daily reset",
      ),
      #(
        10_503,
        1_735_646_400,
        "before the latest yearly reset, 2025-01-01 10:00 UTC",
      ),
    ],
    fn(row) {
      let held = quest_support.completed(row.0, at: row.1)
      let state = dev_support.in_world_holding_quests(level: 1, quests: [held])
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(row.0) <> " done",
        )
      assert quest_states_written(taken:)
        == [QuestState(quest_id: row.0, state: 3, objective_id: 0)]
        as row.2
      assert dev_support.saved_quests(state:)
        == [quest_support.completed(row.0, at: now_seconds)]
        as "the entry is Completed at now"
    },
  )
}

pub fn a_periodic_quests_completion_is_read_the_same_after_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(quest_support.daily, after_the_next_daily_reset, "the daily reset"),
      #(10_503, after_the_next_yearly_reset, "the yearly reset"),
    ],
    fn(row) {
      let text = "!quest " <> int.to_string(row.0) <> " done"
      let #(first, _) =
        dev_support.said(
          state: dev_support.in_world_holding_quests(level: 1, quests: []),
          text:,
        )
      let saved = dev_support.saved_quests(state: first)
      assert saved == [quest_support.completed(row.0, at: now_seconds)]
        as "the command's completion is saved at now"
      let #(_, before_the_reset) =
        dev_support.said(
          state: dev_support.in_world_holding_quests(level: 1, quests: saved),
          text:,
        )
      assert support.system_lines(before_the_reset)
        == ["quest " <> int.to_string(row.0) <> " is already done"]
        as "a new login before the reset reads the saved row as finished"
      let relogged =
        dev_support.in_world_holding_quests(level: 1, quests: saved)
      let #(_, after_the_reset) =
        dev_support.said_at(state: relogged, text:, filetime: row.1)
      assert quest_states_written(taken: after_the_reset)
        == [QuestState(quest_id: row.0, state: 3, objective_id: 0)]
        as row.2
    },
  )
}

pub fn the_quest_the_command_completes_finishes_the_quest_waiting_on_it_and_the_server_completes_that_one_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest2 9497 holds QuestObjective 18252 (type 3, done here) and 18604 (type 24, flags 3,
  // data 9695: done when quest 9695 is finished). No Creature2 row receives 9497, so the
  // server completes it once it is Achieved (`communicator.completed_by_server`).
  let state =
    dev_support.in_world_holding_quests(level: 1, quests: [
      quest_support.active(
        quest_id: 9497,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [1, 0],
      ),
    ])
  let #(state, taken) = dev_support.said(state:, text: "!quest 9695 done")
  assert quest_states_written(taken:)
    == [
      QuestState(quest_id: 9695, state: 3, objective_id: 0),
      QuestState(quest_id: 9497, state: 2, objective_id: 0),
    ]
    as "0x35c: 9695 Completed, then 9497 Achieved, which its objective 18604 waiting on 9695 makes"
  assert support.decoded(
      support.written(taken:),
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    )
    == [
      QuestObjectiveProgress(quest_id: 9497, objective_index: 1, progress: 1),
    ]
    as "0x361: the type 24 objective 18604, the second of 9497, is done"
  assert list.last(support.written_ids(taken)) == Ok(0x01C8)
    as "the command's line is written after the follow-ups' frames"
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(
    quests: asked,
    ..,
  ))) = support.ask_request(taken)
    as "the connection asks the store for a turn-in, as it does for a quest the server completes"
  assert asked
    == [
      quest_support.completed(9497, at: now_seconds),
      quest_support.completed(9695, at: now_seconds),
    ]
    as "the turn-in saves the log with 9497 Completed beside the 9695 the command completed"
  let #(state, answered) =
    support.answer(state:, taken:, outcome: support.turn_in_saved(taken:))
  assert quest_states_written(taken: answered)
    == [QuestState(quest_id: 9497, state: 3, objective_id: 0)]
    as "the turn-in's answer tells the client 9497 is Completed"
  assert dev_support.saved_quests(state:)
    == [
      quest_support.completed(9497, at: now_seconds),
      quest_support.completed(9695, at: now_seconds),
    ]
    as "both quests are Completed in the log"
}

pub fn the_next_save_holds_the_completed_quest_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    dev_support.said(
      state: dev_support.in_world_holding_quests(level: 1, quests: []),
      text: "!quest 5972 done",
    )
  let #(_, taken) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(quests:, ..))) =
    support.ask_request(taken)
    as "the save timer asks the store to save the place and the quests"
  assert quests == [quest_support.completed(5972, at: now_seconds)]
    as "store.SavePlace carries a Completed row, state 3 with its completion time"
}

pub fn an_accepted_quest_command_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = dev_support.in_world_holding_quests(level: 1, quests: [])
  let #(_, taken) = dev_support.said(state:, text: "!quest 5972 done")
  let assert [line] = rule_support.logs_of(step: taken, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!quest 5972 done")
    as "it names the command and the quest"
  assert rule_support.logs(taken) == [line] as "and no other line"
}

pub fn a_command_for_a_quest_the_server_is_completing_runs_after_its_turn_in_and_finds_it_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quests 9497 and 9695 are Achieved and no Creature2 row receives either, so the entry
  // queues the server's completion of both: 9497 is asked of the store first and 9695
  // waits in the queue. The command line for 9695 is held behind the asks.
  let #(state, entry) =
    support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: support.world_character(),
      quests: [
        quest_turn_in_support.achieved(quest_id: 9497),
        quest_turn_in_support.achieved(quest_id: 9695),
      ],
    )
  let #(state, held) = dev_support.said(state:, text: "!quest 9695 done")
  assert support.written_ids(held) == []
    as "the line waits while the store works"
  let #(state, second) =
    support.answer(
      state:,
      taken: entry,
      outcome: support.turn_in_saved(taken: entry),
    )
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(..))) =
    support.ask_request(second)
    as "the answer's input asks for the quest that waited in the queue"
  let #(_, third) =
    support.answer(
      state:,
      taken: second,
      outcome: support.turn_in_saved(taken: second),
    )
  assert quest_states_written(taken: third)
    == [QuestState(quest_id: 9695, state: 3, objective_id: 0)]
    as "the server's completion writes 9695's state 3 once, and the command writes none"
  assert support.system_lines(third) == ["quest 9695 is already done"]
    as "the held command finds the quest finished by the server's completion"
}

// A `!go`: the placement the client takes as the server's move within a world
// (`opcode.0x83c`, `opcode.0x639`, `opcode.0x638`, `opcode.0x636`, `opcode.0x635`).

/// The tests' player, standing in World 3460 at the place of `world_character()`.
fn camp_player() -> game_connection.State {
  dev_support.in_world_as(
    character: support.world_character(),
    experience: None,
  )
}

/// A place in World 3460.
fn in_camp(zone zone: Int, x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: zone, x:, y:, z:)
}

/// WorldLocation2 51615, Warfare Woods, in World 3460: its facing quaternion is
/// (0, 0xb157d016, 0, 1), a turn of 2 * asin(-3.1404900902032296e-9) about the vertical.
fn warfare_woods() -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 5967,
      x: -50.53350067138672,
      y: -861.4010009765625,
      z: 307.8080139160156,
      facing: start_place.Facing(
        yaw: -6.280980180406459e-9,
        pitch: 0.0,
        roll: 0.0,
      ),
    )
    as "the row's world is not 0"
  place
}

/// The 32-bit float bits the client's position command carries for a place.
fn position_bits(place place: Place) -> UnitPositionCommand {
  UnitPositionCommand(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
    blends: 0,
  )
}

/// The position the one 0x638 among the frames puts the player at.
fn placed_at(frames frames: List(Frame)) -> UnitPositionCommand {
  let assert [placement] =
    list.filter(frames, fn(frame) { frame.message_id == 0x0638 })
    as "the move writes one 0x638"
  let assert Ok(moved) = unit_movement.decode(placement.body)
    as "the frame is a 0x638"
  let assert [relayed_movement.Position(position), ..] = moved.commands
    as "the first command is the position"
  position
}

/// One `!go` in the player's world, with what the player sees of it.
type Placed {
  Placed(
    text: String,
    viewers: List(Int),
    fighter: Bool,
    place: Place,
    line: String,
    why: String,
  )
}

pub fn a_go_in_the_same_world_places_the_player_at_once_and_tells_the_map_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Placed(
        text: "!go 3460 5967 100 -50 200",
        viewers: [],
        fighter: False,
        place: in_camp(zone: 5967, x: 100.0, y: -50.0, z: 200.0),
        line: "moved to world 3460, zone 5967, (100.0, -50.0, 200.0)",
        why: "coordinates: the place is as asked, with the facing the player has",
      ),
      Placed(
        text: "!go 51615",
        viewers: [],
        fighter: False,
        place: warfare_woods(),
        line: "moved to world 3460, zone 5967, (-50.53350067138672, -861.4010009765625, 307.8080139160156)",
        why: "WorldLocation2 51615: a named place is the row's own world, zone, position and facing",
      ),
      Placed(
        text: "!go 3460 5967 100 -50 200",
        viewers: [2],
        fighter: True,
        place: in_camp(zone: 5967, x: 100.0, y: -50.0, z: 200.0),
        line: "moved to world 3460, zone 5967, (100.0, -50.0, 200.0)",
        why: "a viewer is sent the move and a fighter is told the place",
      ),
    ],
    fn(row) {
      let state = support.watched_by(state: camp_player(), viewers: row.viewers)
      let state = case row.fighter {
        True ->
          support.feed(
            state:,
            event: support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
          ).0
        False -> state
      }
      let #(state, taken) = dev_support.said(state:, text: row.text)
      let frames = support.written(taken:)
      assert support.written_ids(taken)
        == [0x01C2, 0x083C, 0x0639, 0x0638, 0x0636, 0x01C8]
        as "the answer to the line, the client's placement, then the system line"
      assert placed_at(frames:) == position_bits(place: row.place) as row.why
      assert support.decoded(frames, 0x0636, client_control_granted.decode)
        == [
          ClientControlGranted(
            echo_value: 1,
            reset_movement: 1,
            unit_id: support.own_unit_id,
          ),
        ]
        as "opcode.0x636: the echo is the next move number, 1, and the player's own unit takes control back"
      assert support.system_lines(taken) == [row.line] as row.why
      assert support.told_the_map(taken)
        == [
          support.map_tell(TellMoved(
            connection: ConnectionId(1),
            place: row.place,
            seq: 1,
          )),
        ]
        as "the map is told the move with the echo's number"
      assert list.count(support.peer_tells(taken), fn(tell) {
          list.contains(row.viewers, tell.0)
        })
        == list.length(row.viewers)
        as "opcode.0x638: each player who sees the unit is sent the move"
      assert support.told_creatures(taken)
        == case row.fighter {
          True -> [
            #(
              7,
              TellTargetMoved(
                connection: ConnectionId(1),
                place: row.place,
                seq: 1,
                stay: support.own_stay(),
                hit_radius: place_support.player_hit_radius,
              ),
            ),
          ]
          False -> []
        }
        as "a creature fighting the player is told the place"
      assert list.length(rule_support.logs_of(step: taken, level: step.LogInfo))
        == 1
        as "one info line for the accepted command"
      assert dev_support.saved_place(state:) == row.place
        as "the next save holds the commanded place"
      let #(state, dropped) =
        support.read(
          state,
          support.moves_message([
            game_client.position_command(
              x: 29.128599166870117,
              y: -853.87158203125,
              z: -560.18798828125,
            ),
          ]),
        )
      assert rule_support.effects_of(dropped) == []
        as "a 0x637 sent from the old place before the client took the placement is no move"
      assert dev_support.saved_place(state:) == row.place
        as "and it moves nothing"
    },
  )
}

/// A 0x635, the client's answer to the 0x636.
fn echo_message(echo_value echo_value: Int) -> BitArray {
  let assert Ok(body) =
    client_control_echoed.encode(ClientControlEchoed(echo_value:))
    as "an echo of 32 bits fits"
  support.world_message(message_id: client_control_echoed.message_id, body:)
}

pub fn a_second_go_after_the_echo_is_numbered_after_the_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = dev_support.said(state: camp_player(), text: "!go 51615")
  let #(state, _) = support.read(state, echo_message(echo_value: 1))
  let #(_, taken) = dev_support.said(state:, text: "!go 3460 5967 1 2 3")
  assert support.moves_told(taken) == [2]
    as "the connection counts its moves: the second placement is 2"
}

/// What a zone report after a `!go` into a zone leaves.
type Reported {
  Reported(
    commanded: Int,
    reported: Int,
    held: Int,
    written: List(Int),
    groups: List(step.ConnectionEffect(Request)),
    progress: List(QuestObjectiveProgress),
    why: String,
  )
}

pub fn the_zone_the_client_reports_after_a_go_replaces_the_commanded_one_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Reported(
        commanded: 648,
        reported: 648,
        held: 648,
        written: [0x01DA],
        groups: [
          step.LeaveGroup(support.zone_group(4961)),
          step.JoinGroup(support.zone_group(35)),
        ],
        progress: [],
        why: "the report of the commanded zone changes the place's zone to itself, and the chat group follows it from the old top zone 4961 to 35, as the client's own move would",
      ),
      Reported(
        commanded: 648,
        reported: 5968,
        held: 5968,
        written: [0x0361, 0x035C],
        groups: [],
        progress: [
          QuestObjectiveProgress(
            quest_id: 10_540,
            objective_index: 1,
            progress: 1,
          ),
        ],
        why: "the client's own zone replaces the commanded one in the place, and settles the objectives on it: WorldZone 5968 is below 4964, so the arrival counts",
      ),
    ],
    fn(row) {
      let state =
        support.entered_under(
          settings: support.settings_with_dev_commands(),
          character: store.Character(
            ..support.world_character(),
            faction_id: spawn.exile_faction,
          ),
          quests: [
            quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0]),
          ],
        ).0
      let #(state, _) =
        dev_support.said(
          state:,
          text: "!go 3460 " <> int.to_string(row.commanded) <> " 1 2 3",
        )
      assert start_place.world_zone_id(dev_support.saved_place(state:))
        == row.commanded
        as "the `!go` itself sets only the place's zone"
      let #(state, _) = support.read(state, echo_message(echo_value: 1))
      let #(state, reported) =
        support.read(
          state,
          support.zone_changed_message(old: row.commanded, new: row.reported),
        )
      assert support.written_ids(reported) == row.written as row.why
      assert list.filter_map(rule_support.effects_of(reported), fn(effect) {
          case effect {
            OwnEffect(step.JoinGroup(address:)) -> Ok(step.JoinGroup(address:))
            OwnEffect(step.LeaveGroup(address:)) ->
              Ok(step.LeaveGroup(address:))
            OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
              Error(Nil)
          }
        })
        == row.groups
        as row.why
      assert support.decoded(
          support.written(taken: reported),
          0x0361,
          quest_objective_progress.decode,
        )
        == row.progress
        as row.why
      assert start_place.world_zone_id(dev_support.saved_place(state:))
        == row.held
        as row.why
    },
  )
}

pub fn a_go_settles_the_objectives_at_the_new_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: store.Character(
        ..support.world_character(),
        faction_id: spawn.exile_faction,
      ),
      quests: [quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0])],
    ).0
  let #(_, taken) = dev_support.said(state:, text: "!go 3460 5968 1 2 3")
  let frames = support.written(taken:)
  assert support.decoded(frames, 0x0361, quest_objective_progress.decode)
    == [
      QuestObjectiveProgress(quest_id: 10_540, objective_index: 1, progress: 1),
    ]
    as "QuestObjective 21373 (type 17, data 4964): the commanded zone 5968 is below 4964, so the arrival counts at the `!go`, not only at the client's next report"
  assert support.written_ids(taken)
    == [0x01C2, 0x083C, 0x0639, 0x0638, 0x0636, 0x01C8, 0x0361, 0x035C]
    as "the objectives are settled after the placement and its line"
}

/// An Exile holding the Combat Simulation (Quest2 10527) with its projector, Creature2 73735,
/// in view, made with the development commands on: pressing the projector starts a cast.
fn exile_before_the_combat_projector() -> game_connection.State {
  departures_support.seeing(
    state: support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: store.Character(
        ..support.world_character(),
        faction_id: spawn.exile_faction,
      ),
      quests: [
        quest_support.active(
          quest_id: 10_527,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 13,
          progress: [1, 0, 1, 1, 0],
        ),
      ],
    ).0,
    creature_id: 73_735,
  )
}

pub fn a_go_stops_the_cast_in_progress_before_the_placement_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: departures_support.clients_cast_id,
      target_unit_id: departures_support.terminal_unit,
    ))
    as "the message fits"
  let #(state, pressed) =
    support.at(
      state: exile_before_the_combat_projector(),
      ms: 0,
      event: OwnEvent(
        step.Read(support.world_message(
          message_id: cast_activate.message_id,
          body: press,
        )),
      ),
    )
  assert list.contains(support.written_ids(pressed), 0x07FD)
    as "opcode.0x7fd: the press confirms the cast, which runs 1000 ms"
  let #(_, went) =
    support.at(
      state:,
      ms: 500,
      event: OwnEvent(
        step.Read(support.chat_line_message(4, "!go 3460 5967 1 2 3")),
      ),
    )
  let ids = support.written_ids(went)
  let position = fn(id) {
    let assert Ok(index) =
      list.index_map(ids, fn(found, index) { #(found, index) })
      |> list.key_find(id)
      as "the frame is written"
    index
  }
  assert position(0x07FE) < position(0x083C)
    as "opcode.0x83c stops the current cast, so its finish is written before the placement"
  assert support.cast_timers(steps: [pressed, went], ms: 0) == []
    as "the cast's go and finish timers are cancelled: the projector's own move never comes"
}

pub fn a_go_is_refused_while_the_player_is_dead_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #("!go 3460 5967 100 -50 200", "the player's world"),
      #("!go 870 1227 -7700 -941 -659", "another world"),
    ],
    fn(row) {
      let #(state, _) = support.killed(camp_player())
      let before = dev_support.saved_place(state:)
      let #(state, taken) = dev_support.said(state:, text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.1
      assert support.system_lines(taken)
        == ["!go is refused while the player is dead"]
        as row.1
      assert rule_support.asked(taken) == None as "no ask is made"
      assert support.told_the_map(taken) == [] as row.1
      assert dev_support.saved_place(state:) == before
        as "the departures' move refuses a dead player the same way: nothing changed"
    },
  )
}

pub fn a_go_the_tables_refuse_never_leaves_the_map_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "!go 99999 1189 0 0 0",
        "!go: World 99999 is not in the client's tables",
        "a world with no row: the client's load fails on it (opcode.0xad)",
      ),
      #(
        "!go 3460 6009 99999 0 0",
        "!go: x 99999 is outside -32768 to 32768",
        "a position outside the box the client clamps to",
      ),
    ],
    fn(row) {
      let state = camp_player()
      let before = dev_support.saved_place(state:)
      let #(state, taken) = dev_support.said(state:, text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.2
      assert support.system_lines(taken) == [row.1] as row.2
      assert rule_support.asked(taken) == None as "no Leave is asked"
      assert support.told_the_map(taken) == [] as row.2
      assert dev_support.saved_place(state:) == before as "nothing changed"
    },
  )
}

pub fn a_go_to_another_world_is_refused_with_one_line_until_it_is_built_test() -> Nil {
  use <- owned_test.run(60_000)
  let origin =
    place_support.at(world_id: 22, world_zone_id: 1189, x: 1.0, y: 2.0, z: 3.0)
  let state = dev_support.in_world_at_place(place: origin)
  let #(state, taken) =
    dev_support.said(state:, text: "!go 870 1227 -7700 -941 -659")
  assert support.written_ids(taken) == [0x01C2, 0x01C8]
    as "the line is answered with one system line and nothing else"
  assert support.system_lines(taken) == ["!go to another world is not built"]
  assert rule_support.asked(taken) == None as "no Leave is asked"
  assert support.told_the_map(taken) == []
  assert rule_support.logs(taken) == [] as "a refused command writes no log"
  assert dev_support.saved_place(state:) == origin as "nothing changed"
}
