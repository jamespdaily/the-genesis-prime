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
//// - `SpellLevel.spell4Id.no_prerequisite`: the committed rows hold the Medic's abilities
////   of levels 4 to 9 (`ability_book_test`): 614 (level 4, Spell4Base 26038), 1087 (5,
////   25692), 1191, 1194 and 1221 (6, 25530, 25579, 38210), 632 (8, 47675) and 1021 (9,
////   16336). A rise to level 9 grants them in the order of level and row id, in the slots
////   after the bag of 4 items, and one 0x1a0 holds each at tier 1 in the four action sets
////   (`opcode.0x1a0`).
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
//// - A `!go` into another world is the leave and join of the Holocrypt's move: the old
////   map is asked to take the player out, the new world's map to take it in (`opcode.0xad`
////   names the world the client loads), and the entry burst has no 0x25E and no 0x35F
////   (`game_connection_departures`). WorldLocation2 8300 is in World 870, zone 1227, at the
////   float bits 0xc5f0a7c4, 0xc46b4091, 0xc424d2a8. WorldZone 1189 is in top zone 483 by
////   parentZoneId (1530, 495, 1215). The reply is the Design's choice (a System line).

import ability_book_support as book_support
import ability_points_support as points_support
import cast_support
import character_support
import character_tables
import connection_rule_support as rule_support
import departures_support
import experience_support
import fixture_tables
import game_client
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Answer, type Request, AskMap, AskStore, FromMap, FromStore, Removed,
  TellMoved, TellTargetMoved,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/dev_command as connection_dev_command
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/departures
import genesis_prime/game/loadout
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, AccountDisconnected, LostUserServer,
}
import genesis_prime/message/enter_world
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/float32
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/player_health
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
  type ConnectionEvent, type ConnectionStep, type Event, type Outcome,
  CancelTimer, ConnectionId, OwnEffect, OwnEvent, StartTimer, StoppedWaiting,
  TimerFired, TimerId, Unwatch, Watch, WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{ForItems, Items, Move, SavePlace}
import genesis_prime/table/id.{Item2Id, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import item_expiry_support
import map_support
import message_support
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import quest_turn_in_support
import vendor_support

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

/// The abilities a Medic of level 3 gains by a rise to `level`, as the bag index and the
/// Spell4Base, from the fixture's SpellLevel rows of class 4 with no prerequisite: each level's
/// rows in the order of their ids, in the slots after the bag the level 3 Medic holds, which
/// is its level 1 abilities, those of levels 2 and 3 and the innate
/// (`ability_book_test`: "the three abilities and the innate").
fn medic_abilities_gained_to(level level: Int) -> List(#(Int, Int)) {
  let tables = fixture_tables.shared()
  let medic_rows =
    spell_level.all(tables)
    |> list.filter(fn(row) {
      row.class_id == 4 && loadout.is_class_ability(row:)
    })
  let held_at_3 =
    list.count(medic_rows, fn(row) { row.character_level <= 3 }) + 1
  medic_rows
  |> list.filter(fn(row) {
    row.character_level > 3 && row.character_level <= level
  })
  |> list.sort(fn(first, second) {
    int.compare(first.character_level, second.character_level)
    |> order.break_tie(int.compare(first.id, second.id))
  })
  |> list.index_map(fn(row, index) {
    let assert Ok(spell) = spell4.get(tables:, id: Spell4Id(row.spell4_id))
      as "a SpellLevel row names a Spell4 row"
    #(held_at_3 + index, spell.spell4_base_id_base_spell)
  })
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
        added: medic_abilities_gained_to(level: 9),
        line: "level 9, experience 17330",
        held: #(9, 17_330),
        why: "level 9 starts at 17330: one 0x938 for the whole jump, and the abilities the fixture's Medic rows hold for levels 4 to 9, in the order of level and then row id (SpellLevel 632 is Nullifier at level 8, 1021 Triage at level 9)",
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
  let assert client_connection.AskStore(Items(store.BuyFromVendor(
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
  let assert client_connection.AskStore(Items(store.BuyFromVendor(
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
  let assert client_connection.AskStore(Items(store.TurnInQuest(
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
  let assert client_connection.AskStore(Items(store.TurnInQuest(..))) =
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

// ---- !currency ----
//
// Expected values come from these places.
// - `opcode.0x919` and `opcode.0xdd.with_0x919`: a set writes the 0x919 total, and the 0xdd
//   gain only when the total is higher; the 0x1c8 line is the command's System line.
// - `character_currency` holds one row for each currency the player has: the connection
//   holds what the store's load gave (a missing row reads as 0) and the request names it.
// - The tests' player is account 7, character 42, epoch 1 (`game_connection_support`).

const credits_800 = store.HeldCurrency(currency_type_id: 1, amount: 800)

/// The player holding these currencies after it said the line.
fn granting(
  currencies currencies: List(store.HeldCurrency),
  text text: String,
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  dev_support.said(
    state: dev_support.in_world_holding_currencies(currencies:),
    text:,
  )
}

/// The step after the store answered the ask `taken` ended with.
fn answered(
  state state: game_connection.State,
  taken taken: step.ConnectionStep(Request),
  outcome outcome: Outcome(Answer),
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  support.answer(state:, taken:, outcome:)
}

/// The step after this event, at the monotonic time 1 ms.
fn fed(
  state state: game_connection.State,
  event event: Event(ConnectionEvent(client_connection.Message, Answer)),
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  support.at(state:, ms: 1, event:)
}

pub fn a_currency_command_asks_the_store_and_waits_in_granting_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        [credits_800],
        "!currency 1 5000",
        800,
        5000,
        "a character with credits",
      ),
      #([], "!currency 1 5000", 0, 5000, "no credits row reads as 0 held"),
      #(
        [store.HeldCurrency(currency_type_id: 1, amount: 8000)],
        "!currency 1 100",
        8000,
        100,
        "a lowering is asked too",
      ),
    ],
    fn(row) {
      let #(currencies, text, held, after, why) = row
      let #(_, taken) = granting(currencies:, text:)
      assert support.ask_request(taken)
        == dev_support.currency_asked(currency_type_id: 1, held:, after:)
        as why
      let assert Some(ask) = rule_support.asked(taken)
      assert ask.deadline_ms == rule_support.now_ms + 4000
        as "the settings' ask deadline from the time of the input"
      assert support.written_ids(taken) == [0x01C2]
        as "opcode.0x1c2: the line is answered before the ask, and nothing else is written until the answer"
      assert !rule_support.stops(taken)
    },
  )
}

pub fn a_chat_line_during_the_grant_waits_and_reads_the_new_amount_after_the_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(state, second) = dev_support.said(state:, text: "!currency 1 100")
  let #(state, third) = dev_support.said(state:, text: "!level 4")
  assert rule_support.asked(second) == None
    && support.written_ids(second) == []
    && rule_support.asked(third) == None
    && support.written_ids(third) == []
    as "the bytes of two lines wait in the connection while the first ask is out: nothing is asked or written"
  let #(state, first_answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert support.ask_request(first_answer)
    == dev_support.currency_asked(currency_type_id: 1, held: 5000, after: 100)
    as "the held second line is read after the answer, when the player holds the new 5000"
  let #(_, second_answer) =
    answered(
      state:,
      taken: first_answer,
      outcome: dev_support.currency_set(amount: 100),
    )
  assert list.contains(support.written_ids(second_answer), 0x01AC)
    as "opcode.0x1ac: the held !level 4 is taken after the second answer and raises the level"
  // The held bytes are bounded: past the limit the connection ends.
  let #(state, _) = granting(currencies: [], text: "!currency 1 5000")
  let #(state, kept) =
    support.read(state, <<0:size(rule_support.held_limit * 8)>>)
  assert !rule_support.stops(kept)
    as "bytes up to the limit are kept for after the answer"
  let #(_, over) = support.read(state, <<0>>)
  assert rule_support.stops(over) && rule_support.asked(over) == None
    as "one byte past the limit ends the connection with nothing asked"
}

pub fn a_map_message_and_a_timer_during_the_grant_are_taken_in_order_after_its_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(state, struck) =
    support.at(
      state:,
      ms: 1,
      event: support.a_beast_strike(support.own_unit_id),
    )
  assert support.written_ids(struck) == [] && rule_support.asked(struck) == None
    as "the strike on the player waits behind the ask"
  let #(state, fired) =
    support.fired_at(state:, timer: connection_state.save_timer, ms: 2)
  assert support.written_ids(fired) == [] && rule_support.asked(fired) == None
    as "the save timer waits behind the ask and does not end the connection"
  let assert Some(ask) = rule_support.asked(taken)
  let #(_, answer) =
    support.at(
      state:,
      ms: 3,
      event: OwnEvent(step.Answered(
        ask: ask.ask,
        outcome: dev_support.currency_set(amount: 5000),
      )),
    )
  let ids = support.written_ids(answer)
  assert list.take(ids, 3) == [0x0919, 0x00DD, 0x01C8]
    as "the command's frames and line come first"
  assert list.last(ids) == Ok(player_health.message_id)
    as "the strike is taken after them, its health the last frame"
  let assert client_connection.AskStore(store.Move(store.SavePlace(health:, ..))) =
    support.ask_request(answer)
    as "the held save timer is taken last and asks to save the place"
  assert health == Some(735)
    as "the place is saved with the health the strike left, so the save came after it"
}

/// A player of another connection, who speaks.
fn another_speaker() -> chat_tell.Speaker {
  chat_tell.Speaker(
    realm_id: 1,
    character_id: 7,
    name: "Zed Other",
    faction_id: 167,
    unit_id: 9,
    map: support.camp_map(),
    incarnation: support.incarnation,
  )
}

fn a_line(
  channel_type channel_type: chat_channel.ChannelType,
) -> chat_tell.Line {
  chat_tell.Line(channel_type:, channel_id: 0, text: [0x48, 0x69], formats: [])
}

/// The chat tells the step sends other connections.
fn chat_tells(
  taken taken: step.ConnectionStep(Request),
) -> List(#(step.Address, chat_tell.Tell)) {
  list.filter_map(rule_support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.Tell(to:, request: client_connection.TellChat(tell:))) ->
        Ok(#(to, tell))
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

pub fn a_chat_delivery_during_the_grant_is_dropped_and_a_whisper_is_answered_not_heard_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let said =
    chat_tell.Said(
      speaker: another_speaker(),
      line: a_line(channel_type: chat_channel.Say),
    )
  let #(_, said) =
    fed(state:, event: OwnEvent(Woken(client_connection.SentByChat(said))))
  assert support.written_ids(said) == []
    && chat_tells(taken: said) == []
    && !rule_support.stops(said)
    as "a said line is dropped: the player waits on the store, so the client's chat is not written"
  let whisper =
    chat_tell.Whisper(
      whisper: 5,
      speaker: another_speaker(),
      from: ConnectionId(8),
      line: a_line(channel_type: chat_channel.Whisper),
    )
  let #(_, whispered) =
    fed(state:, event: OwnEvent(Woken(client_connection.SentByChat(whisper))))
  assert support.written_ids(whispered) == []
    && chat_tells(taken: whispered)
    == [#(step.Connection(ConnectionId(8)), chat_tell.NotHeard(whisper: 5))]
    as "a whisper is answered NotHeard to its sender"
}

pub fn a_connection_end_during_the_grant_saves_the_place_then_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "the peer closed",
        OwnEvent(step.PeerClosed),
        rule_support.now_ms + 4000,
        None,
      ),
      #(
        "a read failed",
        OwnEvent(step.ReadFailed(step.OtherSocketFailure(reason: "broken"))),
        rule_support.now_ms + 4000,
        None,
      ),
      #(
        "the server stops with less time than the ask's deadline",
        step.Stopping(deadline_ms: 3000),
        3000,
        Some(LostUserServer),
      ),
      #(
        "another login takes the account's session",
        support.taken_over(),
        rule_support.now_ms + 4000,
        Some(AccountDisconnected),
      ),
    ],
    fn(row) {
      let #(why, event, deadline_ms, notice) = row
      let #(state, asking) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      assert support.ask_request(asking)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: 800,
          after: 5000,
        )
        as "the connection waits on the store"
      let #(state, ending) = support.feed(state:, event:)
      assert support.ask_request(ending)
        == support.save_asked(1, support.entry_place())
        as { why <> ": the place is saved first, as in the world" }
      let assert Some(ask) = rule_support.asked(ending)
      assert ask.deadline_ms == deadline_ms as why
      let #(_, saved) =
        support.answer(state:, taken: ending, outcome: support.place_saved())
      assert rule_support.stops(saved)
        as { why <> ": then the connection ends" }
      assert option.map(notice, fn(_) {
          support.disconnect(saved, support.keyed())
        })
        == notice
        as why
    },
  )
}

pub fn a_watch_that_ends_or_a_claim_timer_that_fires_during_the_grant_ends_the_connection_as_a_bug_test() -> Nil {
  use <- owned_test.run(60_000)
  let claim_timer = TimerId(1)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(_, watch) = fed(state:, event: WatchEnded(WatchId(2)))
  assert support.ask_request(watch)
    == support.save_asked(1, support.entry_place())
    && list.length(rule_support.logs_of(step: watch, level: step.LogError)) == 1
    as "the map's watch ending is a bug: one error line, and the held player's place is saved first, as for any end"
  let #(state, held) =
    fed(state:, event: OwnEvent(step.TimerFired(claim_timer)))
  assert rule_support.asked(held) == None && !rule_support.stops(held)
    as "a firing in the wait is held, as every timer is"
  let #(_, answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert support.ask_request(answer)
    == support.save_asked(1, support.entry_place())
    && list.length(rule_support.logs_of(step: answer, level: step.LogError))
    == 1
    as "taken after the answer, a claim timer the rule did not start is a bug: one error line and the place saved"
}

/// One answer of the store to a `!currency 1 5000` of a player holding 800 credits.
type Answered {
  Answered(
    why: String,
    outcome: Outcome(Answer),
    ids: List(Int),
    lines: List(String),
    warnings: Int,
    errors: Int,
    held_after: Int,
  )
}

pub fn a_currency_answer_updates_the_amounts_and_writes_the_frames_and_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Answered(
        why: "CurrencySet: the total and the gain, then the line",
        outcome: dev_support.currency_set(amount: 5000),
        ids: [0x0919, 0x00DD, 0x01C8],
        lines: ["credits 5000"],
        warnings: 0,
        errors: 0,
        held_after: 5000,
      ),
      Answered(
        why: "ItemsNotSaved: the warning and the not-set line, nothing changed",
        outcome: step.Answer(FromStore(store.ForItems(store.ItemsNotSaved))),
        ids: [0x01C8],
        lines: ["!currency 1 was not set"],
        warnings: 1,
        errors: 0,
        held_after: 800,
      ),
      Answered(
        why: "SaveRefused: the error and the not-set line, nothing changed",
        outcome: step.Answer(
          FromStore(
            store.ForItems(store.SaveRefused(
              constraint: "character_currency_type_is_kept",
            )),
          ),
        ),
        ids: [0x01C8],
        lines: ["!currency 1 was not set"],
        warnings: 0,
        errors: 1,
        held_after: 800,
      ),
    ],
    fn(row) {
      let #(state, taken) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      let #(state, answer) = answered(state:, taken:, outcome: row.outcome)
      assert support.written_ids(answer) == row.ids as row.why
      assert support.system_lines(answer) == row.lines as row.why
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogWarning,
        ))
        == row.warnings
        as row.why
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogError,
        ))
        == row.errors
        as row.why
      assert !rule_support.stops(answer) && rule_support.asked(answer) == None
        as "the connection goes on in the world"
      let #(_, next) = dev_support.said(state:, text: "!currency 1 1")
      assert support.ask_request(next)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: row.held_after,
          after: 1,
        )
        as { row.why <> ": the next ask holds the total the answer left" }
    },
  )
}

pub fn a_store_that_gives_no_answer_to_a_currency_ask_ends_the_connection_with_reason_8_and_saves_the_place_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(step.Answer(FromStore(store.Unavailable)), 1),
      #(step.NotRunning, 1),
      #(step.NoAnswerInTime, 1),
      #(step.EndedBeforeAnswer, 1),
      #(StoppedWaiting, 0),
    ],
    fn(row) {
      let #(outcome, errors) = row
      let #(state, taken) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      let #(state, answer) = answered(state:, taken:, outcome:)
      assert support.ask_request(answer)
        == support.save_asked(1, support.entry_place())
        as "one SavePlace ask, as in the world"
      let assert Some(ask) = rule_support.asked(answer)
      assert ask.deadline_ms == rule_support.now_ms + 4000
        as "the settings' ask deadline, not a stop's"
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogError,
        ))
        == errors
        as "an error line for a store that failed, none for a stop"
      assert support.written_ids(answer) == []
        as "no frame and no line: nothing says whether the total was set"
      let #(_, saved) =
        support.answer(state:, taken: answer, outcome: support.place_saved())
      assert support.disconnect(saved, support.keyed()) == LostUserServer
        as "the place saved, 0x036A reason 8"
    },
  )
}

pub fn each_currency_use_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let assert [line] = rule_support.logs_of(step: taken, level: step.LogInfo)
    as "one info line for an accepted command, before its ask"
  assert string.contains(line.text, "!currency 1 5000")
    && string.contains(line.text, "800")
    as "it names the command and the total held"
  let #(_, answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert rule_support.logs(answer) == []
    as "the answer logs nothing more for a set that was saved"
  let #(_, refused) =
    granting(currencies: [credits_800], text: "!currency 99 1")
  assert rule_support.logs(refused) == []
    as "a refused command is its System line, with no log"
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

pub fn a_position_is_written_as_a_plain_decimal_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        -7700.0,
        "-7700.0",
        "a whole number that float.to_string writes as -7.7e3",
      ),
      #(100.0, "100.0", "a whole number it writes plainly"),
      #(20_000.0, "20000.0", "a whole number it writes as 2.0e4"),
      #(-7700.970703125, "-7700.970703125", "a fraction it writes plainly"),
      #(0.00001, "0.00001", "a fraction below one it writes as 1.0e-5"),
      #(-0.00000015, "-0.00000015", "a negative fraction it writes as -1.5e-7"),
      #(0.0, "0.0", "zero"),
    ],
    fn(row) {
      assert connection_dev_command.plain_decimal(value: row.0) == row.1
        as row.2
    },
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

// A `!go` into another world: the leave of the old map and the join of the new one
// (`opcode.0xad`), as the Holocrypt's and the departures' moves do them. World 870 is
// WorldLocation2 8300's world, zone 1227, at x -7700.970703125, y -941.0088500976562,
// z -659.29150390625 (the row's float bits 0xc5f0a7c4, 0xc46b4091, 0xc424d2a8).

/// The map of World 22, which the tests' player in World 22 joined.
fn map_of_world_22() -> MapId {
  MapId(world_id: 22, instance: 0)
}

/// The player in World 22 after the earlier commands of a sitting: level 4 (experience
/// 2860, XpPerLevel.minXpForLevel), quest 5972 done and 5000 credits, seen by these
/// viewers, holding a health of 1 (the store's saved health).
fn commanded_in_world_22(viewers viewers: List(Int)) -> game_connection.State {
  let state =
    support.watched_by(
      state: dev_support.in_world_22(saved_health: Some(1)),
      viewers:,
    )
  let #(state, _) = dev_support.said(state:, text: "!level 4")
  let #(state, _) = dev_support.said(state:, text: "!quest 5972 done")
  let #(state, granting) = dev_support.said(state:, text: "!currency 1 5000")
  support.answer(
    state:,
    taken: granting,
    outcome: dev_support.currency_set(amount: 5000),
  ).0
}

/// The commanded player after a `!go` into World 870: the step of the line, which asks the
/// leave.
fn leaving_world_22() -> #(game_connection.State, step.ConnectionStep(Request)) {
  dev_support.said(
    state: commanded_in_world_22(viewers: [2, 3]),
    text: "!go 870 1227 -7700 -941 -659",
  )
}

/// The commanded player after the leave was answered: the step that asks the join.
fn joining_world_870() -> #(game_connection.State, step.ConnectionStep(Request)) {
  let #(state, leaving) = leaving_world_22()
  dev_support.left_the_map(state:, leaving:)
}

/// The system line of the `!go` into World 870.
const line_of_the_go = "moved to world 870, zone 1227, (-7700.0, -941.0, -659.0)"

type Crossing {
  Crossing(
    text: String,
    x: Float,
    y: Float,
    z: Float,
    line: String,
    why: String,
  )
}

pub fn a_go_to_another_world_leaves_the_map_then_joins_the_new_one_at_the_place_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Crossing(
        text: "!go 870 1227 -7700 -941 -659",
        x: -7700.0,
        y: -941.0,
        z: -659.0,
        line: line_of_the_go,
        why: "coordinates: the place is as asked",
      ),
      Crossing(
        text: "!go 8300",
        x: -7700.970703125,
        y: -941.0088500976562,
        z: -659.29150390625,
        line: "moved to world 870, zone 1227, (-7700.970703125, -941.0088500976562, -659.29150390625)",
        why: "WorldLocation2 8300: a named place is the row's own world, zone and position",
      ),
    ],
    fn(row) {
      let state = commanded_in_world_22(viewers: [2, 3])
      let #(state, leaving) = dev_support.said(state:, text: row.text)
      assert support.written_ids(leaving) == [0x01C2]
        as "opcode.0x1c2: only the line's echo is written before the join"
      assert support.ask_request(leaving)
        == support.leave_asked_from(map: map_of_world_22())
        as "the run of the map that took the player is asked to take it out"
      list.each([2, 3], fn(viewer) {
        assert support.news_told(taken: leaving, viewer:) == [Removed]
          as "the unit's 0x355: each viewer sees the unit leave"
      })
      let effects = rule_support.effects_of(leaving)
      list.each(
        [
          OwnEffect(step.LeaveGroup(step.CharacterNamed("ab cd"))),
          OwnEffect(
            step.LeaveGroup(step.ZoneChannel(
              map: map_of_world_22(),
              incarnation: support.incarnation,
              top_zone_id: 483,
            )),
          ),
          OwnEffect(CancelTimer(TimerId(8))),
          OwnEffect(CancelTimer(connection_state.save_timer)),
          OwnEffect(CancelTimer(TimerId(10))),
          OwnEffect(CancelTimer(TimerId(11))),
          OwnEffect(CancelTimer(TimerId(13))),
        ],
        fn(left_behind) {
          assert list.contains(effects, left_behind)
            as "the chat groups are left (WorldZone 1189 is in top zone 483 by parentZoneId: 1530, 495, 1215) and the stay's regeneration, save, quest reset, quest deadline and item expiry timers cancelled"
        },
      )
      let #(state, joining) = dev_support.left_the_map(state:, leaving:)
      let assert AskMap(
        map: map_id,
        message: map.Join(place:, stay:, alive:, ..),
      ) = support.ask_request(joining)
        as "the answer to the leave is the new world's join"
      assert map_id == MapId(world_id: 870, instance: 0) as row.why
      assert alive as "a player holding a health of 1 is alive"
      assert stay == map_support.stay(count: 2) as "the join is a new stay"
      assert start_place.world_id(place) == 870
        && start_place.world_zone_id(place) == 1227
        && start_place.x(place) == row.x
        && start_place.y(place) == row.y
        && start_place.z(place) == row.z
        as row.why
      assert support.written_ids(joining) == []
        as "nothing is written between the leave's answer and the join's"
      let #(state, joined) = dev_support.joined_world_870(state:, joining:)
      assert game_client.without_passive_cast(ids: support.written_ids(joined))
        == list.append(game_client.holocrypt_entry_ids(), [0x01C8])
        as "the entry burst with no 0x25E and no 0x35F, then the chat burst, then the line"
      let assert [entered] =
        support.decoded(
          support.written(taken: joined),
          enter_world.message_id,
          enter_world.decode,
        )
        as "one 0xAD"
      assert entered.world_id == 870
        && entered.position_x == float32.to_bits(row.x)
        && entered.position_y == float32.to_bits(row.y)
        && entered.position_z == float32.to_bits(row.z)
        as "opcode.0xad: the client loads World 870 at the place"
      assert support.system_lines(joined) == [row.line] as row.why
      let #(_, save) = dev_support.save_timer_fires(state:)
      let assert AskStore(Move(SavePlace(
        place: saved,
        health:,
        experience:,
        level:,
        quests:,
        ..,
      ))) = support.ask_request(save)
        as "the new stay's save timer saves the place"
      assert start_place.world_id(saved) == 870
        && start_place.x(saved) == row.x
        && start_place.y(saved) == row.y
        && start_place.z(saved) == row.z
        as "the next save holds the new place"
      assert health == Some(1) as "the saved health is kept, not made full"
      assert level == 4 && experience == 2860
        as "XpPerLevel: the level and experience a `!level 4` set are kept"
      assert quests == [quest_support.completed(5972, at: now_seconds)]
        as "the quest log is kept"
      let #(_, granting) = dev_support.said(state:, text: "!currency 1 6000")
      assert support.ask_request(granting)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: 5000,
          after: 6000,
        )
        as "the credits are kept"
    },
  )
}

/// A player holding two stacks of Item2 20791, `sold_stack` (guid 500, bag slot 0, 5) and
/// `kept_stack` (guid 501, bag slot 1, 3), at the vendor Dorian Walker (Creature2
/// 74812) with the development commands on and 1000 credits.
fn at_the_vendor_holding_two_stacks() -> game_connection.State {
  let settings =
    connection_state.Settings(
      ..support.settings_with_dev_commands(),
      vendors: vendor_support.stocking(creature_ids: [74_812]),
    )
  vendor_support.at_the_vendor(
    state: support.entered_stocking_holding(
      in_character_select: support.in_select_from(support.accepted(settings).0),
      credits: 1000,
      items: [
        item_expiry_support.held(
          guid: 500,
          item2: 20_791,
          location: 1,
          bag_index: 0,
          count: 5,
          expires_at_unix_ms: None,
        ),
        item_expiry_support.held(
          guid: 501,
          item2: 20_791,
          location: 1,
          bag_index: 1,
          count: 3,
          expires_at_unix_ms: None,
        ),
      ],
    ),
  )
}

pub fn a_go_to_another_world_keeps_the_bag_and_the_buyback_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = at_the_vendor_holding_two_stacks()
  let #(state, taken) =
    support.sale_requested(
      state:,
      place: ItemPlace(location: 1, bag_index: 0),
      quantity: 5,
    )
  let #(state, _) =
    support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForItems(
            store.Sold(amount: 1013, words: [
              store.SoldWord(item_guid: 500, words: store.plain_words),
            ]),
          ),
        ),
      ),
    )
  let #(state, leaving) =
    dev_support.said(state:, text: "!go 870 1227 29 -853 -560")
  let #(state, joining) = dev_support.left_the_map(state:, leaving:)
  let #(state, _) = dev_support.joined_world_870(state:, joining:)
  let state =
    vendor_support.at_the_vendor_for_a_player_at(
      state:,
      player: place_support.at(
        world_id: 870,
        world_zone_id: 1227,
        x: 29.0,
        y: -853.0,
        z: -560.0,
      ),
      stay_count: 2,
    )
  let #(_, selling) =
    support.sale_requested(
      state:,
      place: ItemPlace(location: 1, bag_index: 1),
      quantity: 3,
    )
  let assert AskStore(Items(store.SellToVendor(sold: [kept], ..))) =
    support.ask_request(selling)
    as "the stack kept in the bag is still held and can be sold"
  assert kept.item_guid == 501 as "the second stack, guid 501"
  let #(_, buying) = support.buyback_requested(state:, buyback_id: 1)
  let assert AskStore(Items(store.BuyFromVendor(grow:, make:, item2_id:, ..))) =
    support.ask_request(buying)
    as "the entry the earlier sale put on the buyback list is still there"
  assert item2_id == Item2Id(20_791) && make == []
    as "the entry is the 5 of Item2 20791 the sale took"
  assert grow
    == [store.StackGrowth(item_guid: 501, held_count: 3, new_count: 8)]
    as "they join the stack of 3 the player kept, guid 501: the bag is still held"
}

/// Impale (Spell4Base 23161) of the Stalker's Novice set, whose go strikes the creatures
/// it reaches (`game_connection_strike_gate`).
const impale_base = 23_161

pub fn a_go_to_another_world_leaves_the_cast_and_the_strike_in_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    support.entered_with(
      settings: support.settings_with_dev_commands(),
      class_id: 5,
      saved_health: None,
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: 42,
        creature_id: 48_404,
        yaw: 0.0,
      ),
    )
  let #(state, pressed) =
    support.at(
      state:,
      ms: 1000,
      event: OwnEvent(
        step.Read(support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 1,
            bag_index: support.stalker_bag_index_of(base: impale_base),
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  let #(state, _, pending, steps) =
    support.casts_left_answered(
      state:,
      world: Nil,
      pending: support.cast_timers(steps: [pressed], ms: 1000),
      until_ms: 1400,
      steps: [pressed],
      answer: fn(world, state, _, taken) { #(world, state, [taken]) },
    )
  let #(state, pressed_again) =
    support.at(
      state:,
      ms: 1400,
      event: OwnEvent(
        step.Read(support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 2,
            bag_index: support.stalker_bag_index_of(base: impale_base),
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  assert pending == [] as "the first cast is over with its go"
  assert support.cast_timers(steps: [pressed_again], ms: 1400)
    == [#(1500, TimerId(1002))]
    as "the second press is a cast in progress: its go is a timer due at 1500"
  assert list.any(steps, fn(taken) {
    list.contains(
      rule_support.effects_of(taken),
      OwnEffect(StartTimer(timer: strike.strike_timer, after_ms: 1000)),
    )
  })
    as "the go struck the beast, whose answer is awaited: the strike timer is set"
  let #(_, went) =
    support.at(
      state:,
      ms: 1450,
      event: OwnEvent(
        step.Read(support.chat_line_message(4, "!go 870 1227 -7700 -941 -659")),
      ),
    )
  let effects = rule_support.effects_of(went)
  list.each(
    [
      #(strike.strike_timer, "the open strike round's timer"),
      #(TimerId(1002), "the cast in progress's go timer"),
    ],
    fn(row) {
      assert list.contains(effects, OwnEffect(CancelTimer(row.0))) as row.1
    },
  )
}

pub fn a_go_to_another_world_replies_once_after_the_join_and_not_before_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, leaving) = leaving_world_22()
  let #(state, joining) = dev_support.left_the_map(state:, leaving:)
  assert support.system_lines(leaving) == []
    && support.system_lines(joining) == []
    as "no system line is written before the join is answered"
  let #(_, joined) = dev_support.joined_world_870(state:, joining:)
  assert support.system_lines(joined) == [line_of_the_go]
    as "one line after the join"
  let ids = support.written_ids(joined)
  assert list.last(ids) == Ok(0x01C8)
    as "the line comes after the entry burst and the chat burst"
  assert list.length(list.filter(ids, fn(id) { id == 0x01C8 })) == 1 as "once"
}

pub fn a_new_map_that_refuses_the_join_returns_the_client_to_character_select_and_saves_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, joining) = joining_world_870()
  let #(state, refused) =
    support.answer(
      state:,
      taken: joining,
      outcome: step.Answer(
        FromMap(
          map.NotJoined(reason: map.NoLoadout(class_id: 1, faction_id: 166)),
        ),
      ),
    )
  assert support.written_ids(refused) == [0x0594]
    as "the player is in no map: 0x0594 puts the client in character select"
  assert list.length(rule_support.logs_of(step: refused, level: step.LogWarning))
    == 1
    as "the refusal is logged once"
  assert support.system_lines(refused) == []
    as "the client is no longer in a world"
  assert rule_support.asked(refused) == None as "no save is asked"
  let #(_, listing) = support.read(state, support.select_start())
  assert support.ask_request(listing)
    == AskStore(store.Select(store.ListCharacters(store.AccountId(7))))
    as "a new character select takes the client's 0x07E0"
  list.each(
    [
      #(step.NotRunning, "the new map is not running"),
      #(step.NoAnswerInTime, "the new map gives no answer in time"),
    ],
    fn(row) {
      let #(state, joining) = joining_world_870()
      let #(_, ended) = support.answer(state:, taken: joining, outcome: row.0)
      assert support.disconnect(ended, support.keyed()) == LostUserServer
        as { row.1 <> ": 0x036A reason 8" }
      assert rule_support.asked(ended) == None
        as { row.1 <> ": no SavePlace is asked" }
    },
  )
}

pub fn an_old_map_that_gives_no_answer_ends_the_connection_without_a_save_and_one_that_is_gone_lets_the_join_go_on_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(step.NoAnswerInTime, "the old map gives no answer in time"),
      #(StoppedWaiting, "the server stops while the leave is out"),
    ],
    fn(row) {
      let #(state, leaving) = leaving_world_22()
      let #(_, ended) = support.answer(state:, taken: leaving, outcome: row.0)
      assert support.disconnect(ended, support.keyed()) == LostUserServer
        as { row.1 <> ": 0x036A reason 8, then the end" }
      assert rule_support.asked(ended) == None
        as { row.1 <> ": no SavePlace is asked" }
    },
  )
  let #(state, leaving) = leaving_world_22()
  let #(_, joining) =
    support.answer(state:, taken: leaving, outcome: step.NotRunning)
  let #(map_id, _, _) = departures_support.join_of(taken: joining)
  assert map_id == MapId(world_id: 870, instance: 0)
    as "a map that is gone has nothing to leave: the join goes on"
}

type Ending {
  Ending(
    event: Event(ConnectionEvent(client_connection.Message, Answer)),
    notice: Option(DisconnectReason),
    why: String,
  )
}

pub fn a_connection_that_ends_while_leaving_or_entering_makes_no_final_save_test() -> Nil {
  use <- owned_test.run(60_000)
  let endings = [
    Ending(
      event: OwnEvent(step.PeerClosed),
      notice: None,
      why: "the peer closed",
    ),
    Ending(
      event: support.taken_over(),
      notice: Some(AccountDisconnected),
      why: "another login takes the account's session",
    ),
  ]
  list.each(endings, fn(ending) {
    list.each(
      [
        #("the leave is out", leaving_world_22()),
        #("the join is out", {
          let #(state, leaving) = leaving_world_22()
          dev_support.left_the_map(state:, leaving:)
        }),
      ],
      fn(waiting) {
        let why = ending.why <> " while " <> waiting.0
        let #(_, ended) = support.feed(state: waiting.1.0, event: ending.event)
        assert rule_support.asked(ended) == None
          as { why <> ": no SavePlace is asked" }
        assert rule_support.stops(ended)
          as { why <> ": the connection ends at once" }
        assert option.map(ending.notice, fn(_) {
            support.disconnect(ended, support.keyed())
          })
          == ending.notice
          as why
      },
    )
  })
}

pub fn what_other_processes_send_while_leaving_or_entering_is_dropped_test() -> Nil {
  use <- owned_test.run(60_000)
  let seen_by =
    support.sent_by_the_map(map.SeenBy(
      by: ConnectionId(4),
      stay: support.viewer_stay(4),
      unit_id: support.viewer_unit_id(4),
    ))
  let #(_, taken) =
    support.feed(state: commanded_in_world_22(viewers: []), event: seen_by)
  assert support.peer_tells(taken) != []
    as "the same message is taken by a connection that stands in the world"
  let #(leaving_state, leaving) = leaving_world_22()
  let #(entering_state, _) = joining_world_870()
  list.each(
    [
      #(leaving_state, seen_by, "a map message for the old stay in LeavingMap"),
      #(
        entering_state,
        seen_by,
        "a map message for the old stay in EnteringWorld",
      ),
      #(
        leaving_state,
        OwnEvent(TimerFired(connection_state.save_timer)),
        "the old stay's save timer firing in LeavingMap",
      ),
    ],
    fn(row) {
      let #(_, dropped) = support.feed(state: row.0, event: row.1)
      assert rule_support.effects_of(dropped) == [] as row.2
    },
  )
  let whisper =
    chat_tell.Whisper(
      whisper: 5,
      speaker: another_speaker(),
      from: ConnectionId(8),
      line: a_line(channel_type: chat_channel.Whisper),
    )
  let #(_, whispered) =
    support.feed(
      state: leaving_state,
      event: OwnEvent(Woken(client_connection.SentByChat(whisper))),
    )
  assert chat_tells(taken: whispered)
    == [#(step.Connection(ConnectionId(8)), chat_tell.NotHeard(whisper: 5))]
    as "a whisper in LeavingMap is answered NotHeard to its sender"
  let #(state, joining) =
    dev_support.left_the_map(state: leaving_state, leaving:)
  let #(state, _) = dev_support.joined_world_870(state:, joining:)
  let #(_, late) = support.feed(state:, event: seen_by)
  assert rule_support.effects_of(late) == []
    as "after the join, a message that carries the old stay's number is dropped"
}

pub fn a_go_clears_a_departures_landing_kept_and_its_timer_finds_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // An Exile in the tutorial, which said yes at the Northern Wilds terminal (Creature2 73606,
  // Spell4Base 20650): the yes keeps a landing and starts the 0 ms departures timer.
  let state =
    departures_support.seeing(
      state: support.entered_under(
        settings: support.settings_with_dev_commands(),
        character: store.Character(
          ..support.world_character(),
          faction_id: spawn.exile_faction,
        ),
        quests: [departures_support.after_the_talk(quest_id: 10_528)],
      ).0,
      creature_id: 73_606,
    )
  let #(state, yes) = departures_support.yes(state:, spell4_base_id: 20_650)
  assert departures_support.started_timers(taken: yes)
    == [#(departures.timer, 0)]
    as "the yes keeps a landing and starts the departures timer"
  let #(state, leaving) =
    dev_support.said(state:, text: "!go 870 1227 -7700 -941 -659")
  assert support.ask_request(leaving) == support.leave_asked()
    as "the `!go` leaves the tutorial's map"
  let #(state, fired) = departures_support.timer_fires(state:)
  assert rule_support.effects_of(fired) == []
    as "the timer finds no landing: no second leave and no retry"
  let #(state, joining) = dev_support.left_the_map(state:, leaving:)
  let #(state, _) = dev_support.joined_world_870(state:, joining:)
  let #(_, fired) = departures_support.timer_fires(state:)
  assert rule_support.effects_of(fired) == []
    as "after the join the timer still finds nothing"
}

pub fn each_accepted_go_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #("!go 22 1189 100 -50 200", "in the player's world"),
      #("!go 870 1227 -7700 -941 -659", "into another world"),
    ],
    fn(row) {
      let #(_, taken) =
        dev_support.said(
          state: dev_support.in_world_22(saved_health: None),
          text: row.0,
        )
      let assert [logged] =
        rule_support.logs_of(step: taken, level: step.LogInfo)
        as { row.1 <> ": one info line" }
      assert rule_support.says(logged, "!go") as row.1
    },
  )
}
