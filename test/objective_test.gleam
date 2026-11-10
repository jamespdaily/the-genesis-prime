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
////
//// The kill tests (`QuestObjective.type.2`, `.8`, `.15`, `.16`, `.46`, `0x140550c50`,
//// `0x1403b4a20`) read these rows. An objective whose count is above 1 and whose flag
//// 0x200 is clear is a percent kind: its stored progress is thousandths of the count
//// (`0x1406113b0`), and one kill is an equal share of it.
//// - quest 1804: objective 1889, type 2, Creature2 5006, count 3.
//// - quest 1805: objective 1890, type 15, data 4976, count 2.
//// - quest 1806: objective 1891, type 8, TargetGroup 307, count 4.
//// - quest 1807: objective 1892, type 16, TargetGroup 307, count 2.
//// - quest 1857: objective 1961, type 2, Creature2 5006, count 1, flags 0.
//// - quest 1859: objective 1962 (type 5), then 1963, type 2, flags 3, count 1, which
////   waits for 1962.
//// - quest 1949: objective 2072 (type 9, flag 0x20), then 2073, type 2, Creature2 5006,
////   count 12.
//// - quest 3204: objective 4182 (type 5), then 4183, type 8, flags 3, TargetGroup 847,
////   count 35.
//// - TargetGroup 307 is type 1 with Creature2 5006 and 5007; 847 is type 3 with
////   Faction2 248.

import fixture_tables
import genesis_prime/game/objective.{
  Advanced, Killed, SendAchieved, SendProgress, TalkedTo, Used,
}
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/id.{Creature2Id, Faction2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option, None, Some}
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
  with_objectives(
    edits: list.map(data, fn(objective) { #(objective.0, "data", objective.1) }),
    body:,
  )
}

/// Runs the body on the fixture's tables with these QuestObjective cells changed (the
/// objective's id, the column and its new value), built on the body's heap.
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

const kill_target = 5006

const group_member = 5007

const stranger = 73_464

/// A killed unit of this creature and faction. Its race, which only a type 12 group
/// reads, is 0: no group of these tests names it.
fn killed(
  creature creature: Int,
  faction faction: Option(Int),
) -> objective.Event {
  Killed(target_group.Unit(
    creature_id: Creature2Id(creature),
    faction_id: option.map(faction, Faction2Id),
    unit_race_id: UnitRaceId(0),
  ))
}

pub fn a_kill_advances_each_open_type_2_objective_naming_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1963 of quest 1859 (type 2, flags 3, behind objective 1962) names the
  // creature the open type 2 objectives name, as do objective 12889 of quest 6961, a
  // talk, and objective 17932 of quest 9207, a use.
  use tables <- pointed_at(data: [
    #(1963, kill_target),
    #(12_889, kill_target),
    #(17_932, kill_target),
  ])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9207, progress: [0]),
      quest_support.accepted(quest_id: 6961, progress: [0]),
      quest_support.accepted(quest_id: 1949, progress: [0, 0]),
      quest_support.accepted(quest_id: 1859, progress: [0, 0]),
      quest_support.accepted(quest_id: 1857, progress: [0]),
      quest_support.accepted(quest_id: 1804, progress: [0]),
    ])
  let slain =
    objective.advance(
      log:,
      tables:,
      event: killed(creature: kill_target, faction: None),
    )
  assert slain.effects
    == [
      SendProgress(quest_id: 1804, objective_index: 0, progress: 333),
      SendProgress(quest_id: 1857, objective_index: 0, progress: 1),
      SendAchieved(quest_id: 1857),
      SendProgress(quest_id: 1949, objective_index: 1, progress: 83),
    ]
    as "quests in id order: 1804's percent objective (count 3) is at floor(1000 / 3), 1857's (count 1) is a count and finishes the quest, 1949's objective 1 (count 12) is at floor(1000 / 12); 1859's objective 1963 waits for 1962, and the talk of 6961 and the use of 9207 are not kills"
  assert quest_log.stored_state(log: slain.log, quest_id: 1857) == 2
    as "1857 is Achieved"
  assert quest_log.stored_state(log: slain.log, quest_id: 1804) == 1
    as "1804 stays Accepted, at a third"
  assert quest_log.stored_state(log: slain.log, quest_id: 6961) == 1
    as "6961 is untouched"

  assert objective.advance(
      log:,
      tables:,
      event: killed(creature: stranger, faction: None),
    )
    == Advanced(log:, effects: [])
    as "a creature no open objective names changes nothing"

  // 1949's objective 1 is done, 1804 is known only by its state and 1857 is completed.
  let closed =
    quest_support.log_of(rows: [
      quest_support.known(quest_id: 1804, state: 4),
      quest_support.completed(quest_id: 1857, at: 1_700_000_000),
      quest_support.active(
        quest_id: 1949,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b10,
        progress: [0, 1000],
      ),
    ])
  assert objective.advance(
      log: closed,
      tables:,
      event: killed(creature: kill_target, faction: None),
    )
    == Advanced(log: closed, effects: [])
    as "a done objective, and a quest that is not in the active list, take no kill"
}

pub fn a_kill_in_its_target_group_advances_types_8_and_16_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objectives 1891 (type 8) and 1892 (type 16) name TargetGroup 307, type 1 with
  // Creature2 5006 and 5007. Objective 1890 is type 15 for 4976.
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1807, progress: [0]),
      quest_support.accepted(quest_id: 1806, progress: [0]),
    ])
  use tables <- with_objectives(edits: [])
  let slain =
    objective.advance(
      log:,
      tables:,
      event: killed(creature: group_member, faction: None),
    )
  assert slain.effects
    == [
      SendProgress(quest_id: 1806, objective_index: 0, progress: 250),
      SendProgress(quest_id: 1807, objective_index: 0, progress: 500),
    ]
    as "a creature in TargetGroup 307 advances the type 8 objective (count 4) and the type 16 one (count 2) alike"
  assert objective.advance(
      log:,
      tables:,
      event: killed(creature: stranger, faction: None),
    )
    == Advanced(log:, effects: [])
    as "a creature outside the group advances neither"

  // TargetGroup 847 is type 3 with Faction2 248: objective 4183 of quest 3204 (type 8,
  // count 35) follows the faction the unit was shown with. Objective 4182 is done.
  let factions =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 3204,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0],
      ),
    ])
  let by_faction =
    objective.advance(
      log: factions,
      tables:,
      event: killed(creature: stranger, faction: Some(248)),
    )
  assert by_faction.effects
    == [SendProgress(quest_id: 3204, objective_index: 1, progress: 28)]
    as "a unit of Faction2 248 is in the type 3 group: floor(1000 / 35)"
  assert objective.advance(
      log: factions,
      tables:,
      event: killed(creature: stranger, faction: Some(249)),
    )
    == Advanced(log: factions, effects: [])
    as "a unit of another faction is not"
  assert objective.advance(
      log: factions,
      tables:,
      event: killed(creature: stranger, faction: None),
    )
    == Advanced(log: factions, effects: [])
    as "a unit with no shown faction is in no type 3 group"

  // Types 15 and 46 are not read from their own data: the server holds no cluster
  // value and no rank of a unit. Objective 1890 is type 15 with data 4976, so a kill
  // of Creature2 4976 is the nearest a test can come to a match.
  let clustered =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1805, progress: [0, 0]),
    ])
  assert objective.advance(
      log: clustered,
      tables:,
      event: killed(creature: 4976, faction: None),
    )
    == Advanced(log: clustered, effects: [])
    as "a type 15 objective takes no kill by its data"
  use ranked <- with_objectives(edits: [#(1890, "type", 46)])
  assert objective.advance(
      log: clustered,
      tables: ranked,
      event: killed(creature: 4976, faction: None),
    )
    == Advanced(log: clustered, effects: [])
    as "nor does the same objective as type 46"
}

pub fn a_kill_in_an_objectives_reward_pane_counts_test() -> Nil {
  use <- owned_test.run(60_000)
  // The reward pane of objectives 1889 (type 2, for 5006) and 1890 (type 15, for 4976)
  // is TargetGroup 307, which holds 5006 and 5007, and so is that of objective 12889
  // (type 3) and 17932 (type 12).
  use tables <- with_objectives(edits: [
    #(1889, "targetGroupIdRewardPane", 307),
    #(1890, "targetGroupIdRewardPane", 307),
    #(12_889, "targetGroupIdRewardPane", 307),
    #(17_932, "targetGroupIdRewardPane", 307),
  ])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9207, progress: [0]),
      quest_support.accepted(quest_id: 6961, progress: [0]),
      quest_support.accepted(quest_id: 1805, progress: [0, 0]),
      quest_support.accepted(quest_id: 1804, progress: [0]),
    ])
  let slain =
    objective.advance(
      log:,
      tables:,
      event: killed(creature: group_member, faction: None),
    )
  assert slain.effects
    == [
      SendProgress(quest_id: 1804, objective_index: 0, progress: 333),
      SendProgress(quest_id: 1805, objective_index: 0, progress: 500),
    ]
    as "5007 is not the creature of objective 1889 and no cluster of 1890, but is in their reward pane: each advances by an equal share (counts 3 and 2); the talk of 6961 and the use of 9207, whose panes hold it too, take no kill"
  assert objective.advance(
      log:,
      tables:,
      event: killed(creature: stranger, faction: None),
    )
    == Advanced(log:, effects: [])
    as "a creature outside every pane changes nothing"
}
