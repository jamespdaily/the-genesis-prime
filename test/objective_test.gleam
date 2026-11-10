//// The objective rule (`genesis_prime/game/objective`): what a talk to a creature or
//// a use of one does to the log's open objectives, and what the client is told.
//// Expected values come from these places.
//// - `QuestObjective.type.3` and `0x1404dd4c0.objective_creature`: a type 3 objective
////   is a talk and a type 12 objective a use, and the data of both is a Creature2 id.
//// - `0x140553110` (the talk marker) and `0x1405510d0` and `0x140553790`: the client
////   names a creature a target only for an objective that is open, so a done or
////   unreachable objective takes nothing. None of them has a state test but
////   `0x1405510d0`'s, for state 3 (completed), so an Achieved quest's open objectives
////   (those with flag 0x20, `0x1405fbc40`) take the event.
//// - `opcode.0x361`: one message for each objective that changes, with the objective's
////   index and its new progress; `opcode.0x35c`: state 2 once the quest's last open
////   objective is done, which is sent only for the event that makes it so.
//// - The order of the effects (a quest at a time, in quest id order, its progress then
////   its state) is this step's design choice, not a client fact: the client takes each
////   message on its own.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`), each count 1:
//// - quest 3668: objective 0 is 4744 (type 3, creature 12484); objectives 1 and 2 are
////   gated, of types 5 and 8.
//// - quest 6961: objective 12889 (type 3, creature 57050).
//// - quest 9207: objective 17932 (type 12, creature 58487).
//// - quest 9428: objective 0 is 17988 (type 3, creature 59216, flags 3); objective 1 is
////   17989 (type 12, creature 58487, flags 3, which waits for objective 0).
//// - quest 5622: objective 0 is 10263 (type 3, creature 41301, flags 0x20); objectives
////   1 and 2 are 8742 and 8305 (type 3, flags 3).
////
//// No real row names one creature in two quests, or a type 3 and a type 12 objective
//// at once, so each test points the objectives it needs at one creature by changing
//// the objective's data (`QuestObjective.data`); the change is the one reason a row is
//// edited here.

import fixture_tables
import genesis_prime/game/objective.{
  Advanced, SendAchieved, SendProgress, TalkedTo, Used,
}
import genesis_prime/game/quest_log
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import owned_test
import planted_table.{Integer}
import quest_support

const talk_target = 12_484

const use_target = 58_487

const unnamed = 57_050

/// Runs the body on the fixture's tables with these QuestObjective rows' data (the
/// creature id) changed, built on the body's heap.
fn pointed_at(
  data data: List(#(Int, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(data, fixture_tables.rows(), fn(rows, objective) {
      case
        fixture_tables.change(
          rows:,
          table: "QuestObjective",
          id: objective.0,
          with: [#("data", Integer(objective.1))],
        )
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

pub fn a_talk_advances_each_open_type_3_objective_naming_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 12889 of quest 6961 names the creature quest 3668's objective 4744 names,
  // and objective 17932 of quest 9207, a use, names it too, as does objective 10263 of
  // quest 5622.
  use tables <- pointed_at(data: [
    #(12_889, talk_target),
    #(17_932, talk_target),
    #(10_263, talk_target),
  ])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9207, progress: [0]),
      quest_support.accepted(quest_id: 6961, progress: [0]),
      quest_support.accepted(quest_id: 3668, progress: [0, 0, 0]),
    ])
  let talked =
    objective.advance(log:, tables:, event: TalkedTo(Creature2Id(talk_target)))
  assert talked.effects
    == [
      SendProgress(quest_id: 3668, objective_index: 0, progress: 1),
      SendProgress(quest_id: 6961, objective_index: 0, progress: 1),
      SendAchieved(quest_id: 6961),
    ]
    as "quests in id order, one 0x361 for each type 3 objective naming the creature, and 0x35c 2 for 6961, whose only objective is done; 3668 has objectives 1 and 2 open and 9207's type 12 objective is not a talk"
  assert quest_log.stored_state(log: talked.log, quest_id: 3668) == 1
    as "3668 stays Accepted"
  assert quest_log.stored_state(log: talked.log, quest_id: 6961) == 2
    as "6961 is Achieved"
  assert quest_log.stored_state(log: talked.log, quest_id: 9207) == 1
    as "9207 is untouched"

  assert objective.advance(
      log: talked.log,
      tables:,
      event: TalkedTo(Creature2Id(talk_target)),
    )
    == Advanced(log: talked.log, effects: [])
    as "a done objective and gated objectives take nothing from a second talk"
  assert objective.advance(log:, tables:, event: TalkedTo(Creature2Id(unnamed)))
    == Advanced(log:, effects: [])
    as "a creature no open objective names changes nothing"

  let achieved =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 5622,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b110,
        progress: [0, 1, 1],
      ),
    ])
  let late =
    objective.advance(
      log: achieved,
      tables:,
      event: TalkedTo(Creature2Id(talk_target)),
    )
  assert late.effects
    == [SendProgress(quest_id: 5622, objective_index: 0, progress: 1)]
    as "an Achieved quest's open optional objective counts the talk, and the client is not told Achieved again"
  assert quest_log.stored_state(log: late.log, quest_id: 5622) == 2
    as "5622 stays Achieved"
}

pub fn a_use_advances_each_open_type_12_objective_naming_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 12889 of quest 6961, a talk, names the creature objectives 17932 and
  // 17989 name.
  use tables <- pointed_at(data: [#(12_889, use_target)])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9207, progress: [0]),
      quest_support.accepted(quest_id: 6961, progress: [0]),
      quest_support.active(
        quest_id: 9428,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0],
      ),
    ])
  let used =
    objective.advance(log:, tables:, event: Used(Creature2Id(use_target)))
  assert used.effects
    == [
      SendProgress(quest_id: 9207, objective_index: 0, progress: 1),
      SendAchieved(quest_id: 9207),
      SendProgress(quest_id: 9428, objective_index: 1, progress: 1),
      SendAchieved(quest_id: 9428),
    ]
    as "quests in id order, one 0x361 for each type 12 objective naming the creature and 0x35c 2 for each quest it finishes; 6961's type 3 objective naming the same creature is not a use"
  assert quest_log.stored_state(log: used.log, quest_id: 6961) == 1
    as "6961 is untouched"
  assert quest_log.stored_state(log: used.log, quest_id: 9207) == 2
    as "9207 is Achieved"
  assert quest_log.stored_state(log: used.log, quest_id: 9428) == 2
    as "9428 is Achieved"

  let waiting =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9428, progress: [0, 0]),
    ])
  assert objective.advance(
      log: waiting,
      tables:,
      event: Used(Creature2Id(use_target)),
    )
    == Advanced(log: waiting, effects: [])
    as "9428's objective 1 has flag 2 and waits for objective 0, so it takes nothing (0x140553790)"
  assert quest_log.state(log: used.log, quest: quest_of(id: 9428, tables:)) == 2
    as "the state the client computes agrees"
}

fn quest_of(id id: Int, tables tables: table_store.Tables) -> quest_log.Quest {
  let assert Ok(quest) = quest_log.quest_of(tables:, id:)
    as "the fixture holds the quest's rows"
  quest
}
