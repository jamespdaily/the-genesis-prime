//// The development commands on the game connection (`genesis_prime/game/connection/dev_command`),
//// run as the pure rule it is: a line said on Say in, the frames and effects out. Expected
//// values come from these places.
//// - `opcode.0x1ac`: the client takes experience only by message, adding the first value to
////   its own; the source kind 1 is Cheat (`opcode.0x1ac.kind.1`). No message lowers it.
//// - `opcode.0x938`: stat 10 is the level. `opcode.0x169`: ability points, 0 for levels 1 to
////   9 (XpPerLevel.abilityPointsPerLevel).
//// - XpPerLevel.minXpForLevel: level 3 from 1710, 4 from 2860, 9 from 17330.
//// - The rise's frames are those of a gain of any source: `experience_book_test` and
////   `experience_points_test`; the abilities a rise grants are their tests', not these.
//// - The line each command is answered with is the design's choice (a System line,
////   ChatChannel row 2).
//// - `opcode.0x35c.complete_unheld`, `0x1405fbdc0.state_3`: the client takes 0x35c state 3
////   for a quest with no log entry. Quest2 2910 holds a limit of 30000 ms; the tests' clock is
////   2025-04-24 20:26:40 UTC.
//// - A `!go` into another world is the leave and join of the Holocrypt's move: the old
////   map is asked to take the player out, the new world's map to take it in (`opcode.0xad`
////   names the world the client loads), and the entry burst has no 0x25E and no 0x35F
////   (`game_connection_departures`). WorldLocation2 8300 is in World 870, zone 1227, at the
////   float bits 0xc5f0a7c4, 0xc46b4091, 0xc424d2a8. WorldZone 1189 is in top zone 483 by
////   parentZoneId (1530, 495, 1215). The reply is the Design's choice (a System line).

import character_support
import character_tables
import connection_rule_support as rule_support
import departures_support
import experience_support
import game_client
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Answer, type Request, AskMap, AskStore, FromStore, TellMoved,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/dev_command as connection_dev_command
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/map/message as map_message
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, AccountDisconnected, LostUserServer,
}
import genesis_prime/message/enter_world
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/float32
import genesis_prime/message/quest_state.{type QuestState, QuestState}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/shared/chat_channel
import genesis_prime/shared/chat_tell
import genesis_prime/shared/strike_tell
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, type Outcome,
  CancelTimer, ConnectionId, OwnEffect, OwnEvent, StoppedWaiting, TimerFired,
  TimerId, Woken,
}
import genesis_prime/store.{Items, Move, SavePlace}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/world_map/map_id.{type MapId, MapId}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import item_expiry_support
import map_support
import owned_test
import place_support
import quest_support
import quest_turn_in_support

/// A Medic (class 4), level 3, holding 1800 experience: 90 past level 3's 1710.
fn medic() -> game_connection.State {
  dev_support.in_world_at(class_id: 4, level: 3, experience: 1800)
}

/// One raise: the line said, what the frames start and end with, the gain and
/// the levels written, the line answered and what the player holds afterwards.
type Raise {
  Raise(
    text: String,
    starts: List(Int),
    ends: List(Int),
    gain: Int,
    levels: List(Int),
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
        starts: [0x01C2, 0x01AC, 0x0938],
        ends: [0x01C8],
        gain: 1060,
        levels: [4],
        line: "level 4, experience 2860",
        held: #(4, 2860),
        why: "level 4 starts at 2860, 1060 above 1800",
      ),
      Raise(
        text: "!xp 2859",
        starts: [0x01C2, 0x01AC],
        ends: [0x01C8],
        gain: 1059,
        levels: [],
        line: "level 3, experience 2859",
        held: #(3, 2859),
        why: "2859 is one short of level 4: a gain and no level",
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

// ---------------------------------------------------------------- !quest

/// The Unix seconds of the tests' clock: the FILETIME 133,900,000,000,000,000 is
/// 2025-04-24 20:26:40 UTC.
const now_seconds = 1_745_526_400

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
      assert support.ask_request(taken)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: 800,
          after: 5000,
        )
        as "the line asks the store to set 5000 while the player holds 800"
      assert support.written_ids(taken) == [0x01C2]
        as "opcode.0x1c2: the line is answered before the ask, and nothing else is written until the answer"
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
      assert support.placed_at(frames:) == position_bits(place: row.place)
        as row.why
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
      assert support.told_the_map_but_creatures(taken)
        == [
          support.map_tell(TellMoved(
            connection: ConnectionId(1),
            place: row.place,
            seq: 1,
          )),
        ]
        as "the map is told the move with the echo's number"
      assert list.count(support.viewer_moves(taken:), fn(tell) {
          list.contains(row.viewers, tell.0)
        })
        == list.length(row.viewers)
        as "opcode.0x638: each player who sees the unit is sent the move"
      assert support.told_creatures(taken)
        == case row.fighter {
          True -> [
            #(
              7,
              map_message.TargetMoved(
                place: row.place,
                seq: 1,
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

/// A refused `!go`, `!level`, `!item`, `!quest` or `!currency` line and the one line
/// that answers it, with the player it is said by.
type Refused {
  Refused(state: game_connection.State, text: String, line: String, why: String)
}

pub fn a_refused_command_writes_only_its_line_and_asks_tells_logs_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Refused(
        state: camp_player(),
        text: "!go 99999 1189 0 0 0",
        line: "!go: World 99999 is not in the client's tables",
        why: "a world with no row: the client's load fails on it (opcode.0xad)",
      ),
      Refused(
        state: camp_player(),
        text: "!go 3460 6009 99999 0 0",
        line: "!go: x 99999 is outside -32768 to 32768",
        why: "a position outside the box the client clamps to",
      ),
      Refused(
        state: support.killed(camp_player()).0,
        text: "!go 3460 5967 100 -50 200",
        line: "!go is refused while the player is dead",
        why: "a dead player's go in the player's world: the departures' move refuses it the same way",
      ),
      Refused(
        state: support.killed(camp_player()).0,
        text: "!go 870 1227 -7700 -941 -659",
        line: "!go is refused while the player is dead",
        why: "a dead player's go into another world asks no leave",
      ),
      Refused(
        state: camp_player(),
        text: "!level 51",
        line: "!level 51 is outside the levels 1 to 50",
        why: "a level above GameFormula 145's highest",
      ),
      Refused(
        state: holding(credits: 0),
        text: "!item 29213",
        line: "!item does not give a proxy item (29213): the client reads its stack limit and its deletable flag from another item, and the server reads the item's own row",
        why: "Item2 29213 has the proxy flag 0x4000",
      ),
      Refused(
        state: camp_player(),
        text: "!quest 999999 done",
        line: "!quest 999999 names no Quest2 row",
        why: "the client refuses a quest it has no row for",
      ),
      Refused(
        state: dev_support.in_world_holding_quests(level: 1, quests: [
          quest_support.completed(quest_support.one_time, at: now_seconds),
        ]),
        text: "!quest " <> int.to_string(quest_support.one_time) <> " done",
        line: "quest "
          <> int.to_string(quest_support.one_time)
          <> " is already done",
        why: "a quest with no period that was completed is not completed again",
      ),
      Refused(
        state: camp_player(),
        text: "!currency 8 1",
        line: "!currency 8 is no currency type the client keeps (1 to 7 and 9 to 14)",
        why: "CurrencyType has no row 8",
      ),
    ],
    fn(row) {
      let place_before = dev_support.saved_place(state: row.state)
      let quests_before = dev_support.saved_quests(state: row.state)
      let #(state, taken) = dev_support.said(state: row.state, text: row.text)
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.why
      assert support.system_lines(taken) == [row.line] as row.why
      assert rule_support.asked(taken) == None as "nothing is asked"
      assert support.told_the_map(taken) == [] as "the map is told nothing"
      assert rule_support.logs(taken) == []
        as "a refused command is its System line, with no log"
      assert dev_support.saved_place(state:) == place_before
        as "the place is as it was"
      assert dev_support.saved_quests(state:) == quests_before
        as "the quest log is as it was"
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
      assert support.news_broadcast(leaving) == []
        as "each viewer is told nothing by the leaving connection: the unit's 0x355 is the map's PlayerUnseen when it takes the leave"
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
        message: map_message.Join(place:, stay:, alive:, ..),
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

pub fn an_old_map_that_is_gone_lets_the_join_go_on_test() -> Nil {
  use <- owned_test.run(60_000)
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
    support.sent_by_the_map(map_message.SeenBy(
      by: ConnectionId(4),
      stay: support.viewer_stay(4),
      unit_id: support.viewer_unit_id(4),
      generation: support.viewer_sight(4),
    ))
  let #(_, taken) =
    support.feed(state: commanded_in_world_22(viewers: []), event: seen_by)
  assert support.snapshot_items(taken) != []
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
