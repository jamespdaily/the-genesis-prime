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

import ability_book_support as book_support
import ability_points_support as points_support
import character_support
import character_tables
import connection_rule_support as rule_support
import experience_support
import fixture_tables
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/step
import genesis_prime/store
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import item_expiry_support
import message_support
import owned_test
import planted_table.{Integer}
import quest_support

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
