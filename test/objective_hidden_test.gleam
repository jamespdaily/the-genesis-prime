//// A hidden scripted objective with no target (`genesis_prime/game/objective`): a
//// QuestObjective of type 5, flag 8 and data 0 that no creature links completes by itself
//// once the quest's other required objectives are done. Expected values come from these
//// places.
//// - `QuestObjective.flags.8`: the client hides an objective with flag 8 from the player
////   (`Quest:GetVisibleObjectiveData`, `0x1406652e0`) and lists no row for it in the quest
////   log; it still needs its done bit for the quest to be Achieved.
//// - `QuestObjective.type.5`: a scripted objective is done only by the server's 0x361.
//// - `0x1405fbc40` (the Achieved rule): every objective without flag 0x20 must be done, so
////   a hidden required objective that nothing completes holds the quest Accepted.
//// - `opcode.0x361` and `opcode.0x35c`: the objective's progress, then the quest's state 2.
//// - The completion itself is a server choice: neither the client nor the retail records
////   say what retail did.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`), each count 1 unless
//// said:
//// - quest 6296 (Nature's Uprising): objective 0 is 9658 (type 8, count 7), objective 1 is
////   9659 (type 12, count 4), objective 2 is 16132 (type 5, flags 8, data 0). The saved
////   row of the live character: state 1, done mask 3, progress {1000, 4, 0}.
//// - quest 3673: objective 0 is 4748 (type 14, count 3), objectives 1 to 3 are 4888 to
////   4890 (type 12, flags 0x28, optional and hidden), objective 4 is 13391 (type 5, flags 8,
////   data 0).
//// - quest 1859: objective 0 is 1962 (type 5, flags 0, data 0), objective 1 is 1963 (type
////   2).

import character_tables
import client_tables
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/communicator
import genesis_prime/game/objective.{
  type Advanced, Advanced, SendProgress, SendState,
}
import genesis_prime/game/objective_link
import genesis_prime/game/quest_log
import genesis_prime/message/quest_log as quest_message
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/creature2
import genesis_prime/table/id.{PrerequisiteId, Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/set
import message_support
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support
import unitest
import world_entry_support

const nature = 6296

/// The time the settles run at: 2025-04-24 20:26:40 UTC in Unix milliseconds, the entry
/// time of the connection tests (`world_entry_support.filetime`).
const settled_at_ms = 1_745_526_400_000

fn settled(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
) -> Advanced {
  objective.settle(
    log:,
    tables:,
    items: [],
    zones: [],
    place: place_support.live_character_place(),
    shown: dict.new(),
    now_ms: 0,
    numbers: spawn_support.numbers,
    unix_ms: settled_at_ms,
  )
}

/// Runs the body on the fixture's tables with these QuestObjective cells changed.
fn with_objectives(
  edits edits: List(#(Int, String, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(edits, fixture_tables.rows(), fn(rows, edit) {
      case
        fixture_tables.change(rows:, table: "QuestObjective", id: edit.0, with: [
          #(edit.1, Integer(edit.2)),
        ])
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// Nature's Uprising as the live character saved it: objectives 0 and 1 done.
fn saved_nature() -> QuestRow {
  quest_support.active(
    quest_id: nature,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 3,
    progress: [1000, 4, 0],
  )
}

pub fn the_last_other_required_objective_completes_the_hidden_one_then_achieves_the_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 9658 (type 8, count 7) is changed to a kill of the Beast, Creature2 73464,
  // count 1, so one kill is the last other required objective; objective 1 is done.
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 9658, with: [
    #("type", Integer(2)),
    #("data", Integer(73_464)),
    #("count", Integer(1)),
  ])
  let #(state, _) =
    connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.active(
        quest_id: nature,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 2,
        progress: [0, 4, 0],
      ),
    ])
  let #(_, credit) =
    experience_support.credited(state:, creature_id: 73_464, level: 1)
  assert connection_support.written(taken: credit)
    |> list.filter(fn(frame) {
      frame.message_id == 0x0361 || frame.message_id == 0x035C
    })
    |> list.map(fn(frame) { #(frame.message_id, frame.body) })
    == [
      progress(quest: nature, index: 0, progress: 1),
      progress(quest: nature, index: 2, progress: 1),
      state_of(quest: nature, state: 2),
    ]
    as "opcode.0x361 for the kill's objective, then 0x361 for the hidden objective at 1 of 1, then 0x35c state 2"
}

/// A 0x361 of the client's reader.
fn progress(
  quest quest: Int,
  index index: Int,
  progress progress: Int,
) -> #(Int, BitArray) {
  #(
    0x0361,
    message_support.packed([#(15, quest), #(32, index), #(32, progress)]),
  )
}

/// A 0x35c of the client's reader with objective id 0.
fn state_of(quest quest: Int, state state: Int) -> #(Int, BitArray) {
  #(0x035C, message_support.packed([#(15, quest), #(32, state), #(32, 0)]))
}

pub fn a_hidden_objective_waits_while_a_required_objective_is_open_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1 (type 12, count 4) is at 3 of 4, so it is open and required.
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: nature,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [1000, 3, 0],
      ),
    ])
  assert settled(log:, tables:) == Advanced(log:, effects: [])
    as "an open required objective keeps the hidden one at 0 and the quest Accepted"
}

pub fn an_open_optional_objective_does_not_hold_the_hidden_one_back_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 0 (type 14, count 3, the only required one) is done with its three units
  // (progress is the mask 7); objectives 1 to 3 (flags 0x28) stay open.
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 3673,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [7, 0, 0, 0, 0],
      ),
    ])
  let done = settled(log:, tables:)
  assert list.take(done.effects, 2)
    == [
      SendProgress(quest_id: 3673, objective_index: 4, progress: 1),
      SendState(quest_id: 3673, state: 2),
    ]
    as "opcode.0x361 for the hidden objective, then 0x35c state 2: the open optional objectives (flag 0x20) do not count (0x1405fbc40)"
  assert quest_log.stored_state(log: done.log, quest_id: 3673) == 2
    as "the quest is Achieved"
}

pub fn a_visible_scripted_objective_is_never_completed_by_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1 (type 2) is done; objective 0 (type 5, flags 0, data 0) is visible.
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 1859,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 2,
        progress: [0, 1],
      ),
    ])
  assert settled(log:, tables:) == Advanced(log:, effects: [])
    as "a type 5 objective with no flag 8 is left to real triggers, so the quest stays Accepted"
}

pub fn a_hidden_scripted_objective_with_data_is_not_completed_by_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296 as saved, its hidden objective 16132 given data 4965 (a value the rule
  // does not read as a bare script): the rule leaves it open. A quest's objectives are
  // read when its log loads, so the log is built from the edited tables.
  use edited <- with_objectives(edits: [#(16_132, "data", 4965)])
  let assert Ok(held) =
    quest_log.from_rows(rows: [saved_nature()], tables: edited)
  assert settled(log: held, tables: edited) == Advanced(log: held, effects: [])
    as "a hidden type 5 objective with data is not the rule's"
  // The same row with the data it has in the table is the rule's, which shows the data
  // is what held it back.
  use plain <- with_objectives(edits: [])
  let assert Ok(fresh) =
    quest_log.from_rows(rows: [saved_nature()], tables: plain)
  assert list.take(settled(log: fresh, tables: plain).effects, 1)
    == [SendProgress(quest_id: nature, objective_index: 2, progress: 1)]
    as "opcode.0x361: with data 0 the hidden objective completes"
}

pub fn a_login_completes_the_hidden_objective_of_a_saved_quest_and_sends_it_achieved_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log = quest_support.log_of(rows: [saved_nature()])
  let done = settled(log:, tables:)
  assert done.effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "the saved row of Jim's character gets the hidden objective and state 2, with no server completion since Lucy Lazarin receives the quest"
  assert communicator.receivers_of(tables:, quest_id: nature) != []
    as "Lucy Lazarin (Creature2 45639) receives the quest, so the player turns it in"

  // The log the client is sent at entry.
  let #(_, entry) =
    connection_support.entered_with_quests(quests: [saved_nature()])
  let log_frame =
    world_entry_support.only_frame(
      frames: connection_support.written(taken: entry),
      message_id: quest_message.message_id,
    )
  let assert Ok(message) = quest_message.decode(log_frame.body)
    as "the quest log frame decodes"
  assert list.map(message.active, fn(active) {
      #(active.quest_id, active.state, active.progress)
    })
    == [#(nature, 2, [1000, 4, 1])]
    as "opcode.0x35f: the entry log holds the quest Achieved with the hidden objective at 1"
}

pub fn the_completed_hidden_objective_and_the_achieved_state_survive_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let done = settled(log: quest_support.log_of(rows: [saved_nature()]), tables:)
  let rows = quest_log.rows(log: done.log, now_ms: 0)
  let assert [row] = rows as "the log saves the one quest it holds"
  assert row.quest_id == nature
  assert row.state == 2
  let assert Some(active) = row.active as "an Achieved quest saves its entry"
  assert active.done_mask == 7
    as "objectives 0, 1 and 2 are done: bits 0 to 2 of the mask"
  assert active.progress == [1000, 4, 1]
  let assert Ok(relogged) = quest_log.from_rows(rows:, tables:)
    as "the saved rows are ones the client takes"
  assert settled(log: relogged, tables:) == Advanced(log: relogged, effects: [])
    as "a relog changes nothing and sends nothing more"
  assert quest_log.stored_state(log: relogged, quest_id: nature) == 2
}

/// Nature's Uprising with its objective 1 (9659) a second hidden scripted objective: type
/// 5, flag 8, data 0, count 1. Objective 0 is then the only required objective that is not
/// hidden.
fn with_two_hidden(body body: fn(table_store.Tables) -> a) -> a {
  with_objectives(
    edits: [
      #(9659, "type", 5),
      #(9659, "flags", 8),
      #(9659, "data", 0),
      #(9659, "count", 1),
    ],
    body:,
  )
}

pub fn two_hidden_objectives_of_one_quest_complete_together_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_two_hidden
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: nature,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 1,
          progress: [1000, 0, 0],
        ),
      ],
      tables:,
    )
  let done = settled(log:, tables:)
  assert done.effects
    == [
      SendProgress(quest_id: nature, objective_index: 1, progress: 1),
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 for each hidden objective at 1 of 1, then one 0x35c state 2: neither waits for the other, though 0x1405fbc40 needs both"
  let assert [row] = quest_log.rows(log: done.log, now_ms: 0)
    as "the log saves the one quest it holds"
  let assert Some(active) = row.active as "an Achieved quest saves its entry"
  assert active.done_mask == 7 as "objectives 0, 1 and 2 are done"
}

pub fn a_done_hidden_objective_beside_a_waiting_one_is_not_counted_again_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1 is a hidden script already done (done mask 3, progress 1); objective 2 is
  // the one waiting.
  use tables <- with_two_hidden
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: nature,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 3,
          progress: [1000, 1, 0],
        ),
      ],
      tables:,
    )
  let done = settled(log:, tables:)
  assert done.effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 only for the waiting objective, and the one 0x35c state 2"
  assert settled(log: done.log, tables:) == Advanced(log: done.log, effects: [])
    as "the settled quest is left as it is, nothing sent again"
}

pub fn a_quest_with_no_other_required_objective_completes_its_hidden_one_at_once_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objectives 0 and 1 are made optional (flag 0x20), so the hidden objective 2 is the
  // quest's only required objective and there is nothing to wait for.
  use tables <- with_objectives(edits: [
    #(9658, "flags", 0x20),
    #(9659, "flags", 0x20),
  ])
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: nature,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 0,
          progress: [0, 0, 0],
        ),
      ],
      tables:,
    )
  assert settled(log:, tables:).effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 for the hidden objective, then 0x35c state 2, with both optional objectives still open"
}

pub fn a_hidden_objective_a_creature_links_is_left_to_that_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Beast's row (Creature2 73464) names objective 2 of quest 6296 in its questAnim
  // columns, which is how the client links a creature to an objective
  // (`Creature2.questAnimStateId`, `Creature2.questAnimObjectiveIndex`).
  use tables <- fixture_tables.changed(table: "Creature2", id: 73_464, with: [
    #("questAnimStateId", Integer(nature)),
    #("questAnimObjectiveIndex", Integer(2)),
  ])
  let log = quest_support.log_of(rows: [saved_nature()])
  assert settled(log:, tables:) == Advanced(log:, effects: [])
    as "a hidden objective with a creature to use is that creature's to complete, so the rule leaves it and the quest Accepted"
}

pub fn the_hidden_data_0_scripted_objectives_the_rule_completes_are_the_unlinked_ones_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let hidden =
    quest_objective.all(tables)
    |> list.filter(fn(row) {
      row.type_ == 5 && int.bitwise_and(row.flags, 8) != 0 && row.data == 0
    })
    |> list.map(fn(row) { row.id })
    |> set.from_list
  assert set.size(hidden) == 91
    as "QuestObjective rows of type 5 with flag 8 and data 0: the issue's 91"
  // The (quest, index) slots of the hidden rows, from each Quest2 row's filled objective
  // slots in order, which is the index the log gives an objective.
  let slots =
    quest2.all(tables)
    |> list.flat_map(fn(quest) {
      [
        quest.objective0,
        quest.objective01,
        quest.objective02,
        quest.objective03,
        quest.objective04,
        quest.objective05,
      ]
      |> list.filter(fn(objective) { objective != 0 })
      |> list.index_map(fn(objective, index) { #(quest.id, index, objective) })
    })
    |> list.filter(fn(slot) { set.contains(hidden, slot.2) })
  // The slots some creature's row names, read from its raw columns: the questAnim pair,
  // and the type 43 conditions of comparison 1 of its prerequisite, through the type 11
  // conditions of comparison 1 that nest another (`Creature2.objective_link`,
  // `Prerequisite.prerequisiteTypeId.43`, `.11`).
  let named =
    creature2.all(tables)
    |> list.flat_map(fn(row) {
      let from_anim = case
        row.quest_anim_state_id != 0 && row.quest_anim_objective_index != -1
      {
        True -> [#(row.quest_anim_state_id, row.quest_anim_objective_index)]
        False -> []
      }
      list.append(
        from_anim,
        named_by_prerequisite(
          tables:,
          prerequisite_id: row.prerequisite_id_anim_state,
          above: [],
        ),
      )
    })
    |> set.from_list
  let named_slots =
    list.filter(slots, fn(slot) { set.contains(named, #(slot.0, slot.1)) })
  assert list.filter(slots, fn(slot) {
      objective_link.is_linked(tables:, quest_id: slot.0, index: slot.1)
    })
    == named_slots
    as "the load's set of linked objectives holds exactly the hidden slots the creatures' raw columns name"
  assert list.map(named_slots, fn(slot) { #(slot.0, slot.1) })
    == [
      #(4761, 1),
      #(4829, 0),
      #(4829, 3),
      #(5360, 1),
      #(5360, 2),
      #(5360, 3),
      #(5360, 4),
      #(5374, 2),
    ]
    as "Creature2 21444, 21957, 18431, 22696 to 22699 and 23694 link these hidden slots, which the rule leaves to them"
}

/// The (Quest2 id, index) pairs a Prerequisite row names as open, read from its raw
/// columns: the conditions before the first of type 0, of which type 43 with comparison 1
/// names a Quest2 row and an index, and type 11 with comparison 1 another Prerequisite
/// row to read the same way. `above` holds the rows being read already.
fn named_by_prerequisite(
  tables tables: table_store.Tables,
  prerequisite_id prerequisite_id: Int,
  above above: List(Int),
) -> List(#(Int, Int)) {
  case prerequisite_table.get(tables:, id: PrerequisiteId(prerequisite_id)) {
    Error(Nil) -> []
    Ok(row) ->
      [
        #(
          row.prerequisite_type_id0,
          row.prerequisite_comparison_id0,
          row.object_id0,
          row.value0,
        ),
        #(
          row.prerequisite_type_id1,
          row.prerequisite_comparison_id1,
          row.object_id1,
          row.value1,
        ),
        #(
          row.prerequisite_type_id2,
          row.prerequisite_comparison_id2,
          row.object_id2,
          row.value2,
        ),
      ]
      |> list.take_while(fn(condition) { condition.0 != 0 })
      |> list.flat_map(fn(condition) {
        let #(type_id, comparison, object_id, value) = condition
        case type_id, comparison {
          43, 1 ->
            case quest2.get(tables:, id: Quest2Id(object_id)) {
              Ok(_) -> [#(object_id, int.bitwise_and(value, 0xFFFFFFFF))]
              Error(Nil) -> []
            }
          11, 1 ->
            case list.contains(above, object_id) {
              True -> []
              False ->
                named_by_prerequisite(
                  tables:,
                  prerequisite_id: object_id,
                  above: [prerequisite_id, ..above],
                )
            }
          _, _ -> []
        }
      })
  }
}
