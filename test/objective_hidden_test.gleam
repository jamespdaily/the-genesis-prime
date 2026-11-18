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
import content_support
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/communicator
import genesis_prime/game/held_objective
import genesis_prime/game/objective.{
  type Advanced, Advanced, CompleteByServer, SendProgress, SendState,
}
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_link
import genesis_prime/game/quest_log
import genesis_prime/message/quest_log as quest_message
import genesis_prime/store.{type HeldItem, type QuestRow, HeldItem}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Item2Id, PrerequisiteId, Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/tradeskill_schematic2
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set
import gleam/string
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
  settled_holding(log:, tables:, items: [])
}

fn settled_holding(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> Advanced {
  settled_with(log:, tables:, items:, held: [])
}

/// The settle with these QuestObjective ids held: scripts only an instance run or a PvP
/// match completes.
fn settled_held(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  held held: List(Int),
) -> Advanced {
  settled_with(log:, tables:, items: [], held:)
}

fn settled_with(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  items items: List(HeldItem),
  held held: List(Int),
) -> Advanced {
  objective.settle(
    log:,
    tables:,
    items:,
    zones: [],
    place: place_support.live_character_place(),
    shown: dict.new(),
    now_ms: 0,
    numbers: spawn_support.numbers,
    arrival_objectives: set.new(),
    held_objectives: set.from_list(held),
    unix_ms: settled_at_ms,
    scripts: objective.no_rows(),
  )
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

pub fn a_hidden_script_with_data_completes_like_one_without_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296 as saved, its hidden objective 16132 given data 4965: a type 5 objective's
  // data has no single meaning and the client reads none of it (`QuestObjective.type.5`),
  // so a hidden one with data is a script like one without. A quest's objectives are read
  // when its log loads, so the log is built from the edited tables. The real rows are the
  // hidden type 5 objectives with data no creature links: 5607/8295, 7025/12833 and
  // 7025/12834.
  use edited <- quest_support.with_objectives(edits: [#(16_132, "data", 4965)])
  let assert Ok(held) =
    quest_log.from_rows(rows: [saved_nature()], tables: edited)
  assert settled(log: held, tables: edited).effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361: the hidden objective completes with its data, then state 2"
  // It still waits for the quest's other required objectives, as one without data does.
  let waiting = nature_log(tables: edited, done_mask: 1, progress: [1000, 3, 0])
  assert settled(log: waiting, tables: edited)
    == Advanced(log: waiting, effects: [])
    as "an open required objective keeps it at 0"
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

/// Nature's Uprising with its objective 0 (9658) a second hidden scripted objective: type
/// 5, flag 8, data 0, count 1. Objective 0 is the one the edit can use: the fixture's
/// Creature2 27768 links objective 1 (9659) by questAnimObjectiveIndex 1 and no fixture
/// creature links objective 0, so it stays unlinked, which is what completes a hidden
/// objective. Objective 1 (type 12, count 4) is then the only required objective that is
/// not hidden.
fn with_two_hidden(body body: fn(table_store.Tables) -> a) -> a {
  quest_support.with_objectives(
    edits: [
      #(9658, "type", 5),
      #(9658, "flags", 8),
      #(9658, "data", 0),
      #(9658, "count", 1),
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
          done_mask: 2,
          progress: [0, 4, 0],
        ),
      ],
      tables:,
    )
  let done = settled(log:, tables:)
  assert done.effects
    == [
      SendProgress(quest_id: nature, objective_index: 0, progress: 1),
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
  // Objective 0 is a hidden script already done and objective 1 is done (done mask 3);
  // objective 2 is the one waiting.
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
          progress: [1, 4, 0],
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
  use tables <- quest_support.with_objectives(edits: [
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

/// Nature's Uprising (6296) edited to the shape of quest 3315 with a third, optional
/// objective that 3315 lacks: objective 0 (9658) a hidden script (type 5, flag 8, data 0,
/// count 1), objective 1 (9659) a use with the flags the client's row of 3315's objective
/// 4314 has, 3, and objective 2 (16132) an optional kill, so the script is the quest's
/// only objective the server completes. `locked_flags` is objective 1's
/// flags: 3 keeps it closed until the script is done (`0x140553790`, bit 2), 1 does not.
fn with_script_then(
  locked_flags locked_flags: Int,
  body body: fn(table_store.Tables) -> a,
) -> a {
  quest_support.with_objectives(
    edits: [
      #(9658, "type", 5),
      #(9658, "flags", 8),
      #(9658, "data", 0),
      #(9658, "count", 1),
      #(9659, "flags", locked_flags),
      #(16_132, "type", 2),
      #(16_132, "data", 73_464),
      #(16_132, "flags", 0x20),
    ],
    body:,
  )
}

pub fn a_hidden_script_before_a_locked_objective_completes_and_opens_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_script_then(locked_flags: 3)
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
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
  assert !quest_log.objective_open(log:, quest:, index: 1)
    as "0x140553790: flag 2 keeps objective 1 closed until every earlier objective without flag 0x20 is done"
  let done = settled(log:, tables:)
  assert done.effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the script alone: it does not wait for the objective that waits for it, and the quest stays Accepted"
  assert quest_log.objective_open(log: done.log, quest:, index: 1)
    as "0x140553790: with the script done the flag 2 objective is reachable, so a unit can complete it"
}

pub fn a_hidden_script_still_waits_for_an_open_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1 has flag 1 only: it follows the earlier objectives that are done or
  // reachable, and the script (no flag 1 or 2) is always reachable, so objective 1 is
  // open from the start and nothing keeps it behind the script (`0x140553790`, bit 1).
  use tables <- with_script_then(locked_flags: 1)
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: nature,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 0,
          progress: [0, 3, 0],
        ),
      ],
      tables:,
    )
  assert quest_log.objective_open(log:, quest:, index: 1)
    as "0x140553790: flag 1 with a reachable script before it is open"
  assert settled(log:, tables:) == Advanced(log:, effects: [])
    as "the script waits for every other required objective that can be done before it, as the server's rule says"
}

pub fn a_hidden_script_behind_a_visible_objective_completes_once_that_objective_is_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 2 is a second hidden script with flags 11 (bits 8, 2 and 1), as the second
  // script of quests 9282 and 9839 has: bit 2 keeps it closed until objective 1, the
  // visible use after the first script, is done (`0x140553790`).
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 8),
    #(9658, "data", 0),
    #(9658, "count", 1),
    #(9659, "flags", 3),
    #(16_132, "type", 5),
    #(16_132, "flags", 11),
    #(16_132, "data", 0),
    #(16_132, "count", 1),
  ])
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let logged = fn(done_mask, progress) {
    let assert Ok(log) =
      quest_log.from_rows(
        rows: [
          quest_support.active(
            quest_id: nature,
            state: 1,
            placeholder: 0,
            tracked: False,
            done_mask:,
            progress:,
          ),
        ],
        tables:,
      )
    log
  }
  let first = settled(log: logged(0, [0, 0, 0]), tables:)
  assert first.effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the first script alone: the second stays closed behind objective 1, which is not done (0x140553790)"
  assert !quest_log.objective_done(log: first.log, quest:, index: 2)
    as "an objective the client keeps closed is not marked done"
  let second = settled(log: logged(3, [1, 4, 0]), tables:)
  assert second.effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "with objective 1 done the second script is reachable, so it completes and the quest is Achieved (0x1405fbc40)"
}

pub fn every_hidden_script_quest_can_finish_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // Each quest with an unlinked hidden script, a player having done every required
  // objective that is open and is not such a script, until none more is open
  // (`0x140553790` through `quest_log.objective_open`): the scripts are then the only
  // required objectives left, and the rule must complete each, over as many settles as
  // the player's work between them needs.
  let stuck =
    quest2.all(tables)
    |> list.filter_map(fn(row) {
      let assert Ok(quest) = quest_log.quest_of(tables:, id: row.id)
        as "the Quest2 row's objectives are rows of the table"
      case unlinked_hidden_scripts(tables:, quest:) {
        [] -> Error(Nil)
        scripts ->
          case completes_every_script(tables:, quest:, scripts:) {
            True -> Error(Nil)
            False -> Ok(quest.id)
          }
      }
    })
  assert stuck == []
    as "a script that waits for a required objective the client keeps closed until the script is done never completes, so its quest never finishes (0x140553790)"
}

/// The indexes of the quest's hidden scripted objectives that no creature links: type 5,
/// flag 8, whatever the data.
fn unlinked_hidden_scripts(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
) -> List(Int) {
  list.index_map(quest.objectives, fn(objective, index) { #(index, objective) })
  |> list.filter(fn(pair) {
    let #(index, objective) = pair
    objective.kind == objective_kind.Scripted
    && int.bitwise_and(objective.flags, 8) != 0
    && !objective_link.is_linked(tables:, quest_id: quest.id, index:)
  })
  |> list.map(fn(pair) { pair.0 })
}

/// Whether the settle of the quest, with every other required objective done, sends the
/// progress of each of the `scripts`.
fn completes_every_script(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  scripts scripts: List(Int),
) -> Bool {
  let sent =
    sent_over_settles(
      tables:,
      quest:,
      scripts:,
      held: [],
      done_mask: 0,
      sent: [],
    )
  list.all(scripts, list.contains(sent, _))
}

/// The indexes of the `scripts` the settles complete: settles with the player's work
/// done, again with the scripts the last settle completed and the objectives they opened
/// done, while a settle completes a script not completed before: a script the client keeps
/// closed behind an objective is completed by a later settle (`0x140553790`). A script is
/// complete when the settled log holds its done bit, which a count-0 script has with no
/// progress sent. The `held` objective ids are the scripts the settle leaves open.
fn sent_over_settles(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  scripts scripts: List(Int),
  held held: List(Int),
  done_mask done_mask: Int,
  sent sent: List(Int),
) -> List(Int) {
  let log = player_done(tables:, quest:, scripts:, done_mask:)
  let settled =
    settled_with(log:, tables:, items: held_for(tables:, quest:), held:).log
  let done =
    list.index_map(quest.objectives, fn(_, index) { index })
    |> list.filter(quest_log.objective_done(log: settled, quest:, index: _))
  let completed =
    list.filter(done, fn(index) {
      list.contains(scripts, index)
      && !quest_log.objective_done(log:, quest:, index:)
    })
  let new_scripts =
    list.filter(completed, fn(index) { !list.contains(sent, index) })
  let sent = list.append(sent, new_scripts)
  case new_scripts {
    [] -> sent
    _ ->
      sent_over_settles(
        tables:,
        quest:,
        scripts:,
        held:,
        done_mask: list.fold(done, 0, fn(mask, index) {
          int.bitwise_or(mask, int.bitwise_shift_left(1, index))
        }),
        sent:,
      )
  }
}

/// The items a player who did the quest's collect (type 4) and make (type 33) objectives
/// holds: each objective's item, in its count, in the bags. The rule counts these
/// objectives from the held items at every settle, so the done bits mean nothing without
/// them.
fn held_for(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
) -> List(HeldItem) {
  list.filter_map(quest.objectives, fn(objective) {
    let item2_id = case
      objective_kind.collected_item(objective.kind),
      objective_kind.crafted_schematic(objective.kind)
    {
      Ok(item2_id), _ -> Ok(item2_id)
      Error(Nil), Ok(schematic_id) ->
        tradeskill_schematic2.get(tables:, id: schematic_id)
        |> result.map(tradeskill_schematic2.item2_id_output)
      Error(Nil), Error(Nil) -> Error(Nil)
    }
    use item2_id <- result.map(item2_id)
    HeldItem(
      item_guid: objective.objective_id,
      item2_id:,
      location: 1,
      bag_index: 0,
      stack_count: objective.count,
      words: store.ItemWords(
        random_stats: 0,
        charges: 0,
        item_flags: 0,
        expires_at_unix_ms: option.None,
      ),
    )
  })
}

/// The log of a quest in which every required objective that is open and not one of the
/// `scripts` is done, again until none is open.
fn player_done(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  scripts scripts: List(Int),
  done_mask done_mask: Int,
) -> quest_log.QuestLog {
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: quest.id,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask:,
          progress: list.map(quest.objectives, fn(_) { 0 }),
        ),
      ],
      tables:,
    )
    as "the saved row is one the client takes"
  let next =
    quest_log.open_objectives(log:, quest:)
    |> list.filter(fn(open) {
      let #(index, objective) = open
      !list.contains(scripts, index)
      && int.bitwise_and(objective.flags, quest_log.optional_flag) == 0
    })
  case next {
    [] -> log
    _ ->
      player_done(
        tables:,
        quest:,
        scripts:,
        done_mask: list.fold(next, done_mask, fn(mask, open) {
          int.bitwise_or(mask, int.bitwise_shift_left(1, open.0))
        }),
      )
  }
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

// ---- a visible scripted objective with no marker (`stand_in_scripts`) ----
//
// A visible one is a QuestObjective of type 5 with flags 0x8 and 0x20 clear, no
// `worldLocationsIdIndicator`, no creature linking it, and any data. The client completes
// it by nothing but the server's 0x361 (`QuestObjective.type.5`), and the Achieved rule
// (`0x1405fbc40`) waits for it, so it is completed the way a hidden script is, once the
// quest's other required objectives are done (a script the server can complete is
// completed). The scripts only an instance run or a PvP match can complete are held:
// the settle leaves them open.

/// The edits that make QuestObjective `id` a visible script as quest 9060's objective
/// 16317 is: type 5, the given flags, data 0, count 1, no marker.
fn visible_script(id id: Int, flags flags: Int) -> List(#(Int, String, Int)) {
  [
    #(id, "type", 5),
    #(id, "flags", flags),
    #(id, "data", 0),
    #(id, "count", 1),
    #(id, "worldLocationsIdIndicator00", 0),
    #(id, "worldLocationsIdIndicator01", 0),
    #(id, "worldLocationsIdIndicator02", 0),
    #(id, "worldLocationsIdIndicator03", 0),
  ]
}

/// Nature's Uprising's objectives 1 and 2 made optional (flag 0x20, the kill the shape
/// `with_script_then` gives objective 2), so a script edited into objective 0 is the
/// quest's only required objective.
fn others_optional() -> List(#(Int, String, Int)) {
  [
    #(9659, "flags", 0x20),
    #(16_132, "type", 2),
    #(16_132, "data", 73_464),
    #(16_132, "flags", 0x20),
  ]
}

/// The log of quest 6296 with this done mask and progress, read from `tables`.
fn nature_log(
  tables tables: table_store.Tables,
  done_mask done_mask: Int,
  progress progress: List(Int),
) -> quest_log.QuestLog {
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id: nature,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask:,
          progress:,
        ),
      ],
      tables:,
    )
  log
}

// ---- the client's visible scripts and the held rows ----

/// Every visible stand-in with the quest of the client's quests, those with no marker row:
/// the Quest2 row, the objective's index in its quest, and the quest as the log reads it.
fn visible_rows(
  tables tables: table_store.Tables,
) -> List(#(quest2.Quest2, Int, quest_log.Quest)) {
  quest2.all(tables)
  |> list.flat_map(fn(row) {
    let assert Ok(quest) = quest_log.quest_of(tables:, id: row.id)
      as "the Quest2 row's objectives are rows of the table"
    list.index_map(quest.objectives, fn(objective, index) {
      #(index, objective)
    })
    |> list.filter_map(fn(pair) {
      let #(index, objective) = pair
      case
        objective.visible_script_broken(
          tables:,
          quest_id: quest.id,
          index:,
          objective:,
        )
      {
        [] if !objective.marked -> Ok(#(row, index, quest))
        _ -> Error(Nil)
      }
    })
  })
}

fn objective_at(quest quest: quest_log.Quest, index index: Int) -> Int {
  let assert Ok(objective) = list.drop(quest.objectives, index) |> list.first
    as "the index is one of the quest's objectives"
  objective.objective_id
}

pub fn every_contentfinder_instance_row_is_held_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = visible_rows(tables:)
  // Quest2.questContentFinderTypeEnum 1 to 4 name an instance, an adventure, a dungeon or
  // a match the quest is done in; 5 names "Equip the item" quests of no event.
  let content_finder = fn(wanted: fn(Int) -> Bool) {
    list.filter(rows, fn(row) {
      wanted({ row.0 }.quest_content_finder_type_enum)
    })
    |> list.map(fn(row) { objective_at(quest: row.2, index: row.1) })
  }
  let instance = content_finder(fn(kind) { kind >= 1 && kind <= 4 })
  let equip = content_finder(fn(kind) { kind == 5 })
  assert list.length(rows) == 519
    as "the visible scripts with no marker row, no link and no optional flag: the 516 with no marker column and the 3 whose marker names no WorldLocation2 row (Quest2 2937, 2965 and 3063)"
  assert list.length(instance) == 52
    as "rows of Quest2 with an instance enum 1 to 4"
  assert list.length(equip) == 10
    as "rows of Quest2 with enum 5, the equip objectives"
  assert list.filter(instance, fn(id) { !set.contains(held, id) }) == []
    as "every row of a quest with a content finder enum 1 to 4 needs an instance run or a match"
  assert list.filter(equip, set.contains(held, _)) == []
    as "an equip objective needs no instance, so none is held"
}

pub fn every_stand_in_row_completes_and_every_held_row_stays_open_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let held =
    set.to_list(content_support.objective_ids(table: held_objective.table))
  // For each quest with a visible stand-in, a player having done every other required
  // objective that is open, until none more is: the free stand-ins must all be sent and
  // the held ones none, over as many settles as the player's work between them needs.
  let by_quest =
    list.group(visible_rows(tables:), fn(row) { { row.0 }.id })
    |> dict.to_list
  let results =
    list.flat_map(by_quest, fn(entry) {
      let rows = entry.1
      let assert [#(_, _, quest), ..] = rows as "a group holds a row"
      let visible = list.map(rows, fn(row) { row.1 })
      let scripts =
        list.append(unlinked_hidden_scripts(tables:, quest:), visible)
      let sent =
        sent_over_settles(
          tables:,
          quest:,
          scripts:,
          held:,
          done_mask: 0,
          sent: [],
        )
      list.map(visible, fn(index) {
        let id = objective_at(quest:, index:)
        #(quest.id, id, list.contains(held, id), list.contains(sent, index))
      })
    })
  let completed = list.filter(results, fn(row) { !row.2 })
  let kept = list.filter(results, fn(row) { row.2 })
  assert list.length(completed) == 388 as "visible rows that are not held: 388"
  assert list.length(kept) == 131
    as "held rows: 131 (the 15 marked rows of migration 0039 are not among these 519)"
  let wrong_open = list.filter(completed, fn(row) { !row.3 })
  assert wrong_open == []
    as {
      "stand-in rows (quest, objective) the settles never completed: "
      <> string.inspect(wrong_open)
    }
  let wrong_done = list.filter(kept, fn(row) { row.3 })
  assert wrong_done == []
    as {
      "held rows (quest, objective) the settles completed: "
      <> string.inspect(wrong_done)
    }
}

pub fn a_linked_marked_optional_or_other_type_objective_is_untouched_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case makes one objective of quest 6296 the quest's only candidate that one
  // thing keeps out: the rule leaves it, and the quest stays Accepted.
  let untouched = fn(edits: List(#(Int, String, Int)), why: String) {
    use tables <- quest_support.with_objectives(edits:)
    let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
    assert settled(log:, tables:) == Advanced(log:, effects: []) as why
  }
  let others = [
    #(9658, "flags", 0x20),
    #(16_132, "type", 2),
    #(16_132, "data", 73_464),
    #(16_132, "flags", 0x20),
  ]
  // Creature2 27768 links objective 1 of quest 6296 by its questAnim columns
  // (`objective_link.is_linked`), so a creature is to complete it.
  untouched(
    list.append(visible_script(id: 9659, flags: 0), others),
    "a script a creature links is that creature's to complete",
  )
  untouched(
    list.append(visible_script(id: 9658, flags: 0x20), [
      #(9659, "flags", 0x20),
      #(16_132, "type", 2),
      #(16_132, "data", 73_464),
      #(16_132, "flags", 0x20),
    ]),
    "an optional visible script is not one the quest needs",
  )
  untouched(
    list.append(
      [
        #(9658, "type", 3),
        #(9658, "flags", 0),
        #(9658, "data", 0),
        #(9658, "count", 1),
        #(9658, "worldLocationsIdIndicator00", 0),
        #(9658, "worldLocationsIdIndicator01", 0),
      ],
      others,
    ),
    "an objective of another type is not a script",
  )
  // A marked visible script is not untouched: the place and the stand-in rules take it
  // (`objective_script_place_test`).
  Nil
}

pub fn a_visible_script_completes_once_the_other_objectives_are_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 1859 of the client's rows: objective 0 (1962) is type 5, flags 0, data 0,
  // count 1, no marker; objective 1 (1963) is a kill, done here.
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
  assert settled(log:, tables:).effects
    == [
      SendProgress(quest_id: 1859, objective_index: 0, progress: 1),
      SendState(quest_id: 1859, state: 2),
      CompleteByServer(quest_id: 1859),
    ]
    as "opcode.0x361 for the visible script, then 0x35c state 2 (0x1405fbc40); no creature receives quest 1859, so the server completes it too (`communicator.completed_by_server`)"
  // Quest 6296 with the script in objective 0 and objective 1 (a use, count 4) not done:
  // the script waits for it.
  use edited <- quest_support.with_objectives(
    edits: list.append(visible_script(id: 9658, flags: 0), [
      #(16_132, "type", 2),
      #(16_132, "data", 73_464),
      #(16_132, "flags", 0x20),
    ]),
  )
  let waiting = nature_log(tables: edited, done_mask: 0, progress: [0, 3, 0])
  assert settled(log: waiting, tables: edited)
    == Advanced(log: waiting, effects: [])
    as "an open required objective keeps the script at 0 and the quest Accepted"
  // The script's data is the id of nothing the server could check (the 72 such rows of
  // the table): the server completes it all the same.
  use with_data <- quest_support.with_objectives(
    edits: list.append(visible_script(id: 9658, flags: 0), [
      #(9658, "data", 4965),
      #(16_132, "type", 2),
      #(16_132, "data", 73_464),
      #(16_132, "flags", 0x20),
    ]),
  )
  let done = nature_log(tables: with_data, done_mask: 2, progress: [0, 4, 0])
  assert settled(log: done, tables: with_data).effects
    == [
      SendProgress(quest_id: nature, objective_index: 0, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "a visible script with data completes too: the rule never reads its data"
}

pub fn a_quest_with_only_a_visible_script_completes_it_on_accept_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_objectives(edits: list.append(
    visible_script(id: 9658, flags: 0),
    others_optional(),
  ))
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  assert settled(log:, tables:).effects
    == [
      SendProgress(quest_id: nature, objective_index: 0, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 for the script, then 0x35c state 2: the quest has no other required objective to wait for"
}

pub fn the_mining_expedition_equip_objective_completes_after_the_collects_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 9060's objectives 16316 (a talk, marked), 16317 (a visible script, flags 0,
  // data 0, count 1, no marker) and 16318 (a collect of 5 of Item2 81821, flags 0): here
  // objective 0 is done, objective 1 the collect of 5 of Item2 175 and objective 2 the
  // script, the order the fixture's rows allow.
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      [
        #(9659, "type", 4),
        #(9659, "flags", 0),
        #(9659, "data", 175),
        #(9659, "count", 5),
      ],
      visible_script(id: 16_132, flags: 0),
    ]),
  )
  let log = nature_log(tables:, done_mask: 1, progress: [1000, 0, 0])
  assert settled(log:, tables:) == Advanced(log:, effects: [])
    as "before the collects the script waits"
  let five =
    HeldItem(
      item_guid: 1,
      item2_id: Item2Id(175),
      location: 1,
      bag_index: 0,
      stack_count: 5,
      words: store.ItemWords(
        random_stats: 0,
        charges: 0,
        item_flags: 0,
        expires_at_unix_ms: option.None,
      ),
    )
  let done = settled_with(log:, tables:, items: [five], held: [])
  assert done.effects
    == [
      SendProgress(quest_id: nature, objective_index: 1, progress: 5),
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 for the collect at 5 of 5, then for the script, then 0x35c state 2: no equipping is needed"
}

pub fn a_held_script_stays_open_after_every_settle_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 9869 has one objective, 18845: type 5, flags 0, data 0, count 1, no marker,
  // and the held table names it (an instance run). Here it is objective 0 of quest 6296.
  use tables <- quest_support.with_objectives(edits: list.append(
    visible_script(id: 9658, flags: 0),
    others_optional(),
  ))
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  let first = settled_held(log:, tables:, held: [9658])
  assert first == Advanced(log:, effects: [])
    as "a held script is not completed, and the quest stays Accepted"
  let second = settled_held(log: first.log, tables:, held: [9658])
  assert second == Advanced(log: first.log, effects: [])
    as "a later settle leaves it open too"
  assert quest_log.stored_state(log: second.log, quest_id: nature) == 1
    as "the quest is still Accepted"
}

pub fn a_store_purchase_objective_completes_as_a_stand_in_unless_it_is_held_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest2 10510 has one objective, QuestObjective 21267: type 5, flags 0x40 (visible,
  // required), count 1, no marker and no creature link, whose text asks for a purchase in
  // the In-Game Store. The client completes no scripted objective (`QuestObjective.type.5`)
  // and a quest with a required objective open is not Achieved (`0x1405fbc40`).
  let tables = character_tables.shared()
  let assert Ok(quest) = quest_log.quest_of(tables:, id: 10_510)
    as "the fixture holds quest 10510"
  let assert [store_purchase] = quest.objectives
    as "quest 10510 has the one objective"
  assert store_purchase.objective_id == 21_267
  assert objective.script_of(
      tables:,
      quest_id: 10_510,
      index: 0,
      objective: store_purchase,
      arrival_objectives: set.new(),
      scripts: objective.no_rows(),
    )
    == objective.StandInWithQuest
    as "a visible required unmarked unlinked scripted objective is the stand-in's"
  let log =
    quest_support.log_of(rows: [quest_support.untouched(quest_id: 10_510)])
  let completed = [
    SendProgress(quest_id: 10_510, objective_index: 0, progress: 1),
    SendState(quest_id: 10_510, state: 2),
    CompleteByServer(quest_id: 10_510),
  ]
  // Each case: the held ids, and the effects of two settles in a row.
  let cases = [
    #(
      [],
      completed,
      [],
      "with no hold the stand-in completes it with the quest",
    ),
    #(
      [21_267],
      [],
      [],
      "a held objective stays open at the first settle and the next",
    ),
    #(
      [9658],
      completed,
      [],
      "a hold is of one objective: another's does not keep 21267 open",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(held, first_effects, second_effects, reason) = case_
    let first = settled_held(log:, tables:, held:)
    assert first.effects == first_effects as reason
    let second = settled_held(log: first.log, tables:, held:)
    assert second.effects == second_effects as reason
    assert quest_log.stored_state(log: second.log, quest_id: 10_510)
      == case first_effects {
        [] -> 1
        _ -> 2
      }
      as reason
  })
}

pub fn a_hidden_and_a_visible_script_in_one_quest_both_complete_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 4545 holds a visible script (6197), a hidden one (6193) and two collects.
  // Objective 0 is the visible script here, objective 2 the hidden one (16132, flags 8),
  // and objective 1 (a use, count 4) is done.
  use tables <- quest_support.with_objectives(edits: visible_script(
    id: 9658,
    flags: 0,
  ))
  let log = nature_log(tables:, done_mask: 2, progress: [0, 4, 0])
  assert settled(log:, tables:).effects
    == [
      SendProgress(quest_id: nature, objective_index: 0, progress: 1),
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 for each script, then one 0x35c state 2: neither waits for the other, though 0x1405fbc40 needs both"
}

pub fn a_visible_script_before_a_locked_objective_completes_and_opens_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of `a_hidden_script_before_a_locked_objective_completes_and_opens_it_test`
  // with a visible script: objective 1 has flags 3, which keep it closed until every
  // earlier objective without flag 0x20 is done (`0x140553790`, bit 2).
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [
        #(9659, "flags", 3),
        #(16_132, "type", 2),
        #(16_132, "data", 73_464),
        #(16_132, "flags", 0x20),
      ],
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  assert !quest_log.objective_open(log:, quest:, index: 1)
    as "0x140553790: flag 2 keeps objective 1 closed until the script is done"
  let done = settled(log:, tables:)
  assert done.effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the script alone: it does not wait for the objective that waits for it, and the quest stays Accepted"
  assert quest_log.objective_open(log: done.log, quest:, index: 1)
    as "0x140553790: with the script done the flag 2 objective is reachable"
}

pub fn a_visible_script_before_a_chain_of_locked_objectives_completes_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 4553's shape (objectives 6208, 6218, 6217): the script first, then an
  // objective with flags 3 (closed until the script is done), then one with flag 1,
  // which the client keeps closed until each earlier objective is done or reachable
  // (`0x140553790`, bit 1), so it stays closed through the flag 2 objective before it.
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [
        #(9659, "flags", 3),
        #(16_132, "type", 2),
        #(16_132, "data", 73_464),
        #(16_132, "flags", 1),
      ],
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  assert !quest_log.objective_open(log:, quest:, index: 2)
    as "0x140553790: the flag 1 objective is closed while the flag 2 objective before it is"
  assert settled(log:, tables:).effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the script alone: neither objective behind it can be done before it"
}

pub fn a_visible_script_locked_behind_an_undone_script_completes_on_a_later_settle_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of `a_hidden_script_behind_a_visible_objective_completes_once_that_objective_is_done_test`
  // with visible scripts: objective 0 is the first script, objective 1 a use with flags 3,
  // and objective 2 a second script with flags 3 (bit 2 keeps it closed until objective 1
  // is done, `0x140553790`).
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [#(9659, "flags", 3)],
      visible_script(id: 16_132, flags: 3),
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let first =
    settled(
      log: nature_log(tables:, done_mask: 0, progress: [0, 0, 0]),
      tables:,
    )
  assert first.effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the first script alone: the second stays closed behind objective 1, which is not done (0x140553790)"
  assert !quest_log.objective_done(log: first.log, quest:, index: 2)
    as "an objective the client keeps closed is not marked done"
  let second =
    settled(
      log: nature_log(tables:, done_mask: 3, progress: [1, 4, 0]),
      tables:,
    )
  assert second.effects
    == [
      SendProgress(quest_id: nature, objective_index: 2, progress: 1),
      SendState(quest_id: nature, state: 2),
    ]
    as "with objective 1 done the second script is reachable, so it completes and the quest is Achieved (0x1405fbc40)"
}

pub fn a_free_script_beside_a_held_one_completes_and_the_quest_stays_accepted_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quests 10500 and 10501: a free script (21206, flags 0) and a held one (21228, flags 3,
  // closed until the free one is done). Here objective 0 is the free script, objective 1
  // an optional use, and objective 2 the held script with flags 2.
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [#(9659, "flags", 0x20)],
      visible_script(id: 16_132, flags: 2),
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  let first = settled_held(log:, tables:, held: [16_132])
  assert first.effects
    == [SendProgress(quest_id: nature, objective_index: 0, progress: 1)]
    as "opcode.0x361 for the free script alone: it does not wait for the held one, which no player can do, and the quest stays Accepted"
  assert quest_log.objective_open(log: first.log, quest:, index: 2)
    as "0x140553790: with the free script done the held one is reachable"
  let second = settled_held(log: first.log, tables:, held: [16_132])
  assert second == Advanced(log: first.log, effects: [])
    as "the held script stays open"
  assert quest_log.stored_state(log: second.log, quest_id: nature) == 1
    as "the quest stays Accepted"
}

pub fn an_objective_locked_behind_a_held_script_stays_closed_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [#(9659, "flags", 3)],
      [
        #(16_132, "type", 2),
        #(16_132, "data", 73_464),
        #(16_132, "flags", 0x20),
      ],
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  let settled = settled_held(log:, tables:, held: [9658])
  assert settled == Advanced(log:, effects: [])
    as "the held script is left open"
  assert !quest_log.objective_open(log: settled.log, quest:, index: 1)
    as "0x140553790: flag 2 keeps objective 1 closed while the held script is not done"
}

pub fn an_optional_hidden_script_still_completes_only_while_open_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 2 (16132) is a hidden script that is also optional (flags 0x28). It is
  // done once it is open and the other required objectives are, as a hidden script is;
  // the visible half does not take it (it needs flag 0x20 clear).
  use tables <- quest_support.with_objectives(edits: [#(16_132, "flags", 0x28)])
  let waiting = nature_log(tables:, done_mask: 1, progress: [1000, 3, 0])
  assert settled(log: waiting, tables:) == Advanced(log: waiting, effects: [])
    as "an open required objective (objective 1 at 3 of 4) keeps the script at 0"
  let open = nature_log(tables:, done_mask: 3, progress: [1000, 4, 0])
  assert list.take(settled(log: open, tables:).effects, 1)
    == [SendProgress(quest_id: nature, objective_index: 2, progress: 1)]
    as "opcode.0x361 once the required objectives are done"
  let done = nature_log(tables:, done_mask: 7, progress: [1000, 4, 1])
  assert settled(log: done, tables:) == Advanced(log: done, effects: [])
    as "a done script is not counted again"
}

pub fn a_count_zero_script_reaches_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Six rows of the table are visible scripts of count 0, which the client needs 0 of
  // (`0x140551840`): the server's count of 0 is their done bit.
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [#(9658, "count", 0)],
      others_optional(),
    ]),
  )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: nature)
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  assert !quest_log.objective_done(log:, quest:, index: 0)
    as "the saved log has no done bit for it"
  let done = settled(log:, tables:)
  assert quest_log.objective_done(log: done.log, quest:, index: 0)
    as "the done mask holds objective 0 after the settle"
  assert done.effects == [SendState(quest_id: nature, state: 2)]
    as "no 0x361: its progress stays 0, as the client needs 0; then 0x35c state 2"
}

pub fn a_script_with_a_count_above_one_is_set_to_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // Rows of the table are visible scripts of count 30, 150 and 1000.
  use tables <- quest_support.with_objectives(
    edits: list.flatten([
      visible_script(id: 9658, flags: 0),
      [#(9658, "count", 30)],
      others_optional(),
    ]),
  )
  let log = nature_log(tables:, done_mask: 0, progress: [0, 0, 0])
  assert settled(log:, tables:).effects
    == [
      SendProgress(quest_id: nature, objective_index: 0, progress: 30),
      SendState(quest_id: nature, state: 2),
    ]
    as "opcode.0x361 sets the script to its count in one message"
}
