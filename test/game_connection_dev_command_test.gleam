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
import genesis_prime/client_connection
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/step
import genesis_prime/store
import gleam/list
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
