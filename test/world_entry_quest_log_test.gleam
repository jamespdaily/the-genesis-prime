//// What world entry sends in 0x035F, the player's quest log
//// (`genesis_prime/game/world_entry`, `genesis_prime/game/quest_log`). Expected
//// values come from these places.
//// - `opcode.0x35f.entry_order` and `lua.event.QuestInit`: the client takes the
////   quest log once per play, after the player's own state (0x25E), and the log
////   belongs to the client's process, not to a game object (`quest_log.process_wide`),
////   so the Holocrypt's join, which reuses the game object, sends none.
//// - The lists of the message (`opcode.0x35f`): the completed list, the second list
////   (states 4 to 7), then the active list, each in quest id order. An active
////   entry's flags word is the tracked bit shifted by 1 and the done mask shifted by
////   2: tracked with a done mask of 1 is 2 + 4 = 6.
//// - The reset time is the latest daily or weekly reset before the entry time,
////   2025-04-24 10:00:00 UTC (the entry is made at 2025-04-24 20:26:40 UTC,
////   `world_entry_support.filetime`), 1745488800 Unix seconds.

import cast_support
import character_tables
import game_connection_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/quest_log
import genesis_prime/message/quest_active.{QuestActive}
import genesis_prime/message/quest_completed.{QuestCompleted}
import genesis_prime/message/quest_known.{QuestKnown}
import genesis_prime/message/quest_log as quest_message
import gleam/list
import owned_test
import quest_support
import world_entry_support

const reset_time = 1_745_488_800

/// The one 0x35F among the frames, decoded.
fn quest_log_of(frames frames: List(Frame)) -> quest_message.QuestLog {
  let frame =
    world_entry_support.only_frame(
      frames:,
      message_id: quest_message.message_id,
    )
  let assert Ok(message) = quest_message.decode(frame.body) as "0x35F decodes"
  message
}

/// The message ids of the frames from the first 0x25E on, as many as `count`.
fn from_the_character_state(
  frames frames: List(Frame),
  count count: Int,
) -> List(Int) {
  cast_support.ids(frames:)
  |> list.drop_while(fn(id) { id != 0x025E })
  |> list.take(count)
}

pub fn the_play_entry_sends_the_quest_log_after_the_character_state_and_a_holocrypt_rejoin_sends_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let character =
    world_entry_support.character(class: 2, faction: 166, level: 1)
  // A character with no quests is sent the empty log, right after 0x25E.
  let #(effects, entered) = world_entry_support.entry(tables:, character:)
  let frames = world_entry_support.frames_of(effects:)
  assert from_the_character_state(frames:, count: 2) == [0x025E, 0x035F]
    as "opcode.0x35f.entry_order: 0x35F follows 0x25E, also when the character has no quest"
  assert quest_log_of(frames:)
    == quest_message.QuestLog(completed: [], known: [], active: [], reset_time:)
    as "the empty log is three empty lists and the latest reset time"
  assert quest_log.told_reset(entered.quests) == reset_time
    as "the log the connection keeps remembers the time the client was told"
  // A character with quests is sent each in its list, in quest id order.
  let #(effects, _) =
    world_entry_support.entry_at(
      tables:,
      character:,
      items: world_entry_support.novice_items(character:),
      quests: [
        quest_support.completed(quest_id: quest_support.daily, at: reset_time),
        quest_support.active(
          quest_id: quest_support.one_time,
          state: 1,
          placeholder: 0,
          tracked: True,
          done_mask: 1,
          progress: [5, 0, 3],
        ),
        quest_support.known(
          quest_id: quest_support.daily_two_objectives,
          state: 6,
        ),
        quest_support.active(
          quest_id: quest_support.daily_with_a_placeholder,
          state: 2,
          placeholder: quest_support.placeholder_objective,
          tracked: False,
          done_mask: 0,
          progress: [1],
        ),
      ],
      now: world_entry_support.now(),
    )
  let frames = world_entry_support.frames_of(effects:)
  assert from_the_character_state(frames:, count: 2) == [0x025E, 0x035F]
  assert quest_log_of(frames:)
    == quest_message.QuestLog(
      completed: [QuestCompleted(quest_id: 1857, in_current_period: 1)],
      known: [QuestKnown(quest_id: 3204, state: 6)],
      active: [
        QuestActive(
          quest_id: 2347,
          state: 1,
          placeholder_objective_id: 0,
          flags: 6,
          progress: [5, 0, 3],
          quest_ms_left: 0,
          objective_ms_left: [0, 0, 0],
        ),
        QuestActive(
          quest_id: 6216,
          state: 2,
          placeholder_objective_id: 9461,
          flags: 0,
          progress: [1],
          quest_ms_left: 0,
          objective_ms_left: [0],
        ),
      ],
      reset_time:,
    )
    as "the saved quests are sent as the saved rows give them, each in its list"
  // The Holocrypt's join of a dead player with quests sends no quest log.
  let dead =
    game_connection_support.killed(
      game_connection_support.watched_by(
        state: game_connection_support.entered_with_quests(quests: [
          quest_support.accepted(quest_id: quest_support.daily, progress: [1]),
        ]).0,
        viewers: [2],
      ),
    ).0
  let #(_, rejoined) = game_connection_support.at_the_holocrypt_from(dead:)
  let ids =
    cast_support.ids(frames: game_connection_support.written(taken: rejoined))
  assert list.contains(ids, 0x00AD)
    as "the player joins the Holocrypt: the world is loaded again"
  assert !list.contains(ids, 0x035F)
    as "quest_log.process_wide: the client keeps its quest log across the join, so a second 0x35F would add to it again"
}
