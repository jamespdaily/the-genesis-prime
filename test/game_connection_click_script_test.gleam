//// A click script on a running game connection: the 0x97 cast of the activate spell at a creature
//// of the reward pane of a type 5 objective in the click table counts for it, and the client
//// is told. Expected values come from these places.
//// - `opcode.0x361`: quest id (15 bits), objective index (32) and progress (32), written by the
////   widths of the client's reader (`message_support.packed`), not by our codec.
//// - `opcode.0x35c`: quest id (15), state (32) and objective id (32); state 2 is Achieved, and
////   objective id 0 leaves the quest's objectives as they are.
//// - `opcode.0x97`, `opcode.0x7fd`, `opcode.0x7f4` and `opcode.0x7fe`: a use is the client's
////   0x97, answered by the start of the cast; its go and finish come after the cast time of
////   the creature's activate spell, and the use is complete at the go.
//// - `QuestObjective.type.5`: nothing the client sends completes a type 5 objective, so a quest
////   whose objective is a click script sends no 0x361 on accept, and one 0x361 for the click.
////
//// The client's rows in the fixture (`table_rows -- Quest2 6591`, `QuestObjective 16165 16170
//// 10523 10256`, `Creature2 51440`): quest 6591 has objective 16165 (type 22, a place), 16170
//// (type 5, count 1, flags 3, reward pane 6299 = Creature2 51440), 10523 (type 3, flags 57)
//// and 10256 (type 2, Creature2 51440, flags 7). Creature2 51440 has activate spell 1817,
//// activateSpellCastTime 0, activateSpellMaxRange 2.0, display group 29010 (display 26831,
//// hitRadius 1.0) and factionId 170. Creature2 30238 and 31037 receive the quest.

import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/objective
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/shared/faction_level
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{type QuestRow}
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/set
import message_support
import owned_test
import quest_support
import vendor_support

const pyrius = 51_440

const pyrius_display = 26_831

const pyrius_radius = 1.0

const unit = 40

const clients_cast_id = 9

fn progress_frame(
  index index: Int,
  progress progress: Int,
) -> #(Int, BitArray) {
  message_support.quest_progress_frame(quest: 6591, index:, progress:)
}

/// The ids and bodies the step writes to the client, in order.
fn written(taken taken: ConnectionStep(Request)) -> List(#(Int, BitArray)) {
  connection_support.written_pairs(taken:)
}

/// What the steps tell of quests: their 0x361 and 0x35c frames.
fn quest_frames(
  steps steps: List(ConnectionStep(Request)),
) -> List(#(Int, BitArray)) {
  list.flat_map(steps, fn(taken) { written(taken:) })
  |> list.filter(fn(frame) { frame.0 == 0x0361 || frame.0 == 0x035C })
}

/// The tests' settings with these objectives in the click table.
fn clicking(clicks clicks: List(Int)) -> connection_state.Settings {
  connection_state.Settings(
    ..connection_support.settings(),
    script_rows: objective.ScriptRows(
      ..objective.no_rows(),
      clicks: set.from_list(clicks),
    ),
  )
}

/// Quest 6591 accepted with these objectives (by index) done, each at its count.
fn quest_with(done done: List(Int)) -> QuestRow {
  quest_support.active(
    quest_id: 6591,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: list.fold(done, 0, fn(mask, index) {
      mask + int.bitwise_shift_left(1, index)
    }),
    progress: list.map([0, 1, 2, 3], fn(index) {
      case list.contains(done, index) {
        True -> 1
        False -> 0
      }
    }),
  )
}

/// The bytes of the client's 0x97 right-click of `unit_id`, inside the client's 0x038C.
fn right_click_bytes(unit_id unit_id: Int) -> BitArray {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: clients_cast_id,
      target_unit_id: unit_id,
    ))
    as "the message fits"
  connection_support.world_message(message_id: cast_activate.message_id, body:)
}

/// The connection after the player sees Creature2 51440 as unit 40, a unit the map says
/// is hostile to neither faction (the creature's faction 170 is not Hostile to either,
/// `faction_level`).
fn seeing_pyrius(state state: game_connection.State) -> game_connection.State {
  let tables = fixture_tables.shared()
  let hostile =
    spawn.hostile_to_players(
      levels: faction_level.build(tables:),
      faction_id: 170,
    )
  connection_support.feed(
    state:,
    event: connection_support.creature_appears(
      unit_id: unit,
      creature_id: pyrius,
      display_info_id: pyrius_display,
      outfit_info_id: 0,
      hit_radius: pyrius_radius,
      place: vendor_support.ahead_of_the_player(
        hit_radius: pyrius_radius,
        gap: 1.0,
      ),
      hostile_to: hostile,
    ),
  ).0
}

/// The right-click at 0 ms and the cast's timers to its go: the click's step and the steps
/// after it.
fn clicked(
  state state: game_connection.State,
) -> List(ConnectionStep(Request)) {
  let #(state, started) =
    connection_support.at(
      state:,
      ms: 0,
      event: step.OwnEvent(step.Read(right_click_bytes(unit_id: unit))),
    )
  let #(_, go) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms: 0),
      until_ms: 5000,
      steps: [],
    )
  [started, ..go]
}

pub fn using_the_confront_target_sends_the_type_5_click_objectives_progress_and_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  // The entry's quest log message carries each objective's progress, not a 0x361, so what the
  // entry did to objective 16170 shows in what the click does next.
  // Without the click table the objective is a stand-in, done when the quest is accepted, so
  // the click finds it done and counts nothing: the rule this step replaces.
  let #(standing_in, _) =
    connection_support.entered_with_quests_in(
      settings: clicking(clicks: []),
      quests: [quest_with(done: [0])],
    )
  assert quest_frames(steps: clicked(state: seeing_pyrius(state: standing_in)))
    == []
    as "a stand-in objective is done at accept, so the click finds it done and sends no 0x361"

  // With objective 16170 in the click table the accept completes nothing, so the click does.
  let #(state, _) =
    connection_support.entered_with_quests_in(
      settings: clicking(clicks: [16_170]),
      quests: [quest_with(done: [0])],
    )
  let steps = clicked(state: seeing_pyrius(state:))
  assert quest_frames(steps:) == [progress_frame(index: 1, progress: 1)]
    as "opcode.0x361: objective 1 (16170) is at 1 of 1 once the cast goes, and the kill objective 10256 behind it keeps the quest Accepted"

  // With the quest's last required objective, the kill 10256, already done, the click is the
  // quest's last step: the quest is Achieved (opcode.0x35c state 2), and the creatures that
  // receive it (Creature2 30238 and 31037) turn it in, so the server does not complete it.
  let #(finishing, _) =
    connection_support.entered_with_quests_in(
      settings: clicking(clicks: [16_170]),
      quests: [quest_with(done: [0, 3])],
    )
  assert quest_frames(steps: clicked(state: seeing_pyrius(state: finishing)))
    == [
      progress_frame(index: 1, progress: 1),
      #(0x035C, message_support.packed([#(15, 6591), #(32, 2), #(32, 0)])),
    ]
    as "opcode.0x361 then opcode.0x35c: the click completes the last required objective and Achieves the quest"

  // An earlier cast at the creature, while the place objective 16165 before it is open, counts
  // nothing (`0x140553790`).
  let #(closed, _) =
    connection_support.entered_with_quests_in(
      settings: clicking(clicks: [16_170]),
      quests: [quest_with(done: [])],
    )
  assert quest_frames(steps: clicked(state: seeing_pyrius(state: closed))) == []
    as "objective 16170 is closed behind 16165, so the activation completes nothing"
}
