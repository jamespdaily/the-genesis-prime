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
import connection_rule_support as rule_support
import experience_support
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{type Answer, type Request, FromStore}
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/player_health
import genesis_prime/step.{
  type ConnectionEvent, type Event, type Outcome, ConnectionId, OwnEvent,
  StoppedWaiting, TimerId, WatchEnded, WatchId, Woken,
}
import genesis_prime/store
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

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
