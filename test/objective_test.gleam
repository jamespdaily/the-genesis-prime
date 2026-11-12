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
//// The collect, visit and quest-collectible tests (`objective.settle`, types 4, 33, 17
//// and 32) read these places. The client counts nothing for these types: it stores
//// the server's 0x361 value and the objective is done once the value reaches the
//// count (`0x1406115a0`, `QuestObjective.type.4.progress`).
//// - `0x140552550` (accept check 7): the items held are those at locations 0, 1, 8
////   and 9 (mask 0x303), summed over their stacks.
//// - `QuestObjective.type.33`: its data is a TradeskillSchematic2 id, and it counts
////   that schematic's output item (`item2IdOutput`): schematic 374 gives Item2 21484.
//// - `QuestObjective.type.17`, `Prerequisite.prerequisiteTypeId.26` (`0x1403c92e0`):
////   a visit's data is a WorldZone id, and a zone matches when it is the player's zone
////   or one of its parents. The zone chain 5998, 5997, 4961 is from the WorldZone rows
////   (`parentZoneId`). Row 6375 has data 0 and count 0 and names no zone.
//// - `QuestObjective.type.32`, `Creature2.questAnimStateId` (`0x1405a8b30`): the
////   creature 12919 names quest 3741, objective index 0, whose objective 4813 is a
////   type 32 of count 6 and flags 4. Quest 5857's objective index 1 (8784, type 32,
////   flags 3) waits for index 0.
////
//// The finish tests (`objective.settle`, type 24) read these places. The client gives a
//// type 24 objective no rule and shows only the server's 0x361 value
//// (`QuestObjective.type.24`); the objective's data is the Quest2 id it waits for.
//// - quest 7540: objectives 13654 (type 24, data 6305, count 1) and 13655 (type 24,
////   data 6306, count 1), both flags 0.
//// - quest 9492: objective 18249 (type 22, flags 0, marker WorldLocation2 46118, World
////   51, zone 2548, centre (3897.5508, -769.8461, -2380.6116), radius 1.0, no vertical
////   limit) and 18123 (type 24, data 9494, flags 3, which waits for 18249).
//// - quest 10502: objectives 21208 to 21211, type 24, naming quests 10503 to 10506, all
////   of repeat period 4 (yearly, `Quest2.questRepeatPeriodEnum`); 10503 has the one
////   objective 21212 (type 47, flags 1024, count 15).
//// - the yearly reset is the server's choice, the first daily reset of the year
////   (`quest_log_test`): 2025-01-01 10:00:00 UTC, 1_735_725_600 Unix seconds, for a
////   settle at 2025-04-24 20:26:40 UTC.
////
//// The quests, from the client's rows in the fixture:
//// - 1854: objective 1959, type 4, item 3993, count 3. 1855: 1957, item 3995, count
////   3. 1856: 1960, item 3997, count 3.
//// - 2347: objectives 2709, 2710 and 2711, type 4, items 4857, 4858 and 4859, count 1.
//// - 2989: objective 3866, type 4, item 5913, count 12.
//// - 7415: objective 13485, type 33, schematic 374, count 1.
//// - 1862: objective 1965, type 17, zone 263, count 1, flags 0.
//// - 10520: objective 0 is 21294 (type 14, count 3), 1 is 21297 (type 22, flags
////   0x21), 2 is 21295 (type 22, flags 3), 3 is 21296 (type 2, creature 73499, flags 3)
////   and 4 is 21298 (type 17, zone 5998, flags 3).
//// - `QuestObjective.type.23`: a use of any unit in the objective's TargetGroup counts
////   one for each unit: a second use of the same unit counts nothing (the server's choice,
////   Jim, 2026-11-11; the client keeps no record of the units used).
////   QuestObjective 21094 (quest 10415, group 14175 of creatures 72197, 72198, 72231 ...,
////   count 8, flags 4); the Bon Voyage objectives of quest 10528 (21326
////   talk, 21327 travel, 21328 and 21329 choices, 21342 an optional type 14) and
////   quest 10530 (21347, 21348, 21349, 21350), whose choices (type 23, flags 33) share
////   a group of both terminals, so the choice of each terminal is the server's.

import fixture_tables
import genesis_prime/game/communicator
import genesis_prime/game/objective.{
  Add, Advanced, Button, Cast, CastTarget, CompleteByServer, Killed, Remove,
  SendProgress, SendState, TalkedTo, Used,
}
import genesis_prime/game/quest_log
import genesis_prime/game/start_place
import genesis_prime/game/target_group
import genesis_prime/store.{ActiveQuest, HeldItem, QuestRow}
import genesis_prime/table/id.{
  Creature2Id, Faction2Id, Item2Id, Spell4Id, UnitRaceId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support

const talk_target = 12_484

/// The unit of a creature as the group test of a type 3 or 12 objective reads it: these
/// objectives name the Creature2 id only, so its faction and race are 0.
fn plain_unit(creature creature: id.Creature2Id) -> target_group.Unit {
  target_group.Unit(
    creature_id: creature,
    faction_id: Faction2Id(0),
    unit_race_id: UnitRaceId(0),
  )
}

fn a_talk(creature: id.Creature2Id) -> objective.Event {
  TalkedTo(target: plain_unit(creature:), checklist_index: 0)
}

/// A use of a creature as its own unit: the unit's id is the creature's, so uses of
/// different creatures are uses of different units.
fn a_use(creature: id.Creature2Id) -> objective.Event {
  a_use_of(creature:, unit: quest_support.unit_ref(unit_id: creature.value))
}

/// A use of a creature as this unit of a map run.
fn a_use_of(
  creature creature: id.Creature2Id,
  unit unit: quest_log.UnitRef,
) -> objective.Event {
  Used(target: plain_unit(creature:), checklist_index: 0, unit:, by_item: False)
}

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
    objective.advance(
      log:,
      tables:,
      event: a_talk(Creature2Id(talk_target)),
      now_ms: 0,
    )
  assert talked.effects
    == [
      SendProgress(quest_id: 3668, objective_index: 0, progress: 1),
      SendProgress(quest_id: 6961, objective_index: 0, progress: 1),
      SendState(quest_id: 6961, state: 2),
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
      event: a_talk(Creature2Id(talk_target)),
      now_ms: 0,
    )
    == Advanced(log: talked.log, effects: [])
    as "a done objective and gated objectives take nothing from a second talk"
  assert objective.advance(
      log:,
      tables:,
      event: a_talk(Creature2Id(unnamed)),
      now_ms: 0,
    )
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
      event: a_talk(Creature2Id(talk_target)),
      now_ms: 0,
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
    objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(use_target)),
      now_ms: 0,
    )
  assert used.effects
    == [
      SendProgress(quest_id: 9207, objective_index: 0, progress: 1),
      SendState(quest_id: 9207, state: 2),
      SendProgress(quest_id: 9428, objective_index: 1, progress: 1),
      SendState(quest_id: 9428, state: 2),
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
      event: a_use(Creature2Id(use_target)),
      now_ms: 0,
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

/// A faction no TargetGroup row of the fixture names (`table_rows -- TargetGroup`), for
/// the kills these tests count by creature.
const unlisted_faction = 1441

/// A killed unit of this creature and faction. Its race, which only a type 12 group
/// reads, is 0: no group of these tests names it.
fn killed(creature creature: Int, faction faction: Int) -> objective.Event {
  Killed(target_group.Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(faction),
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
      event: killed(creature: kill_target, faction: unlisted_faction),
      now_ms: 0,
    )
  assert slain.effects
    == [
      SendProgress(quest_id: 1804, objective_index: 0, progress: 333),
      SendProgress(quest_id: 1857, objective_index: 0, progress: 1),
      SendState(quest_id: 1857, state: 2),
      CompleteByServer(quest_id: 1857),
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
      event: killed(creature: stranger, faction: unlisted_faction),
      now_ms: 0,
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
      event: killed(creature: kill_target, faction: unlisted_faction),
      now_ms: 0,
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
      event: killed(creature: group_member, faction: unlisted_faction),
      now_ms: 0,
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
      event: killed(creature: stranger, faction: unlisted_faction),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a creature outside the group advances neither"

  // TargetGroup 847 is type 3 with Faction2 248: objective 4183 of quest 3204 (type 8,
  // count 35) follows the unit's faction. Objective 4182 is done.
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
      event: killed(creature: stranger, faction: 248),
      now_ms: 0,
    )
  assert by_faction.effects
    == [SendProgress(quest_id: 3204, objective_index: 1, progress: 28)]
    as "a unit of Faction2 248 is in the type 3 group: floor(1000 / 35)"
  assert objective.advance(
      log: factions,
      tables:,
      event: killed(creature: stranger, faction: 249),
      now_ms: 0,
    )
    == Advanced(log: factions, effects: [])
    as "a unit of another faction is not"

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
      event: killed(creature: 4976, faction: unlisted_faction),
      now_ms: 0,
    )
    == Advanced(log: clustered, effects: [])
    as "a type 15 objective takes no kill by its data"
  use ranked <- with_objectives(edits: [#(1890, "type", 46)])
  assert objective.advance(
      log: clustered,
      tables: ranked,
      event: killed(creature: 4976, faction: unlisted_faction),
      now_ms: 0,
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
      event: killed(creature: group_member, faction: unlisted_faction),
      now_ms: 0,
    )
  assert slain.effects
    == [SendProgress(quest_id: 1804, objective_index: 0, progress: 333)]
    as "5007 is not the creature of objective 1889, but is in its reward pane: it advances by an equal share (count 3); the talk of 6961 and the use of 9207, whose panes hold it too, take no kill"
  assert kill_masks_of(log: slain.log, quest_id: 1805) == [2, 0, 0, 0, 0, 0]
    as "1890 is type 15, whose reward pane is a named group (TargetGroup.type.1: every creature of the list, each once): 5007 is the group's second entry (5006 is the first), so a kill sets bit 1 of its mask and its progress, which only the server's 0x361 gives the client (opcode.0x361), stays 0 until both are dead: no SendProgress(1805, 0, 500) is sent"
  assert objective.advance(
      log:,
      tables:,
      event: killed(creature: stranger, faction: unlisted_faction),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a creature outside every pane changes nothing"
}

/// The kill masks of a quest's active entry as the log is saved: one 7-bit value for each
/// of the six objective slots.
fn kill_masks_of(
  log log: quest_log.QuestLog,
  quest_id quest_id: Int,
) -> List(Int) {
  let assert [QuestRow(active: Some(ActiveQuest(kill_mask:, ..)), ..)] =
    quest_log.rows(log:, now_ms: 0)
    |> list.filter(fn(row) { row.quest_id == quest_id })
    as "the quest is in the active list"
  kill_mask
}

/// The log after the player's blow kills this creature, and the effects.
fn slain(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  creature creature: Int,
) -> objective.Advanced {
  objective.advance(
    log:,
    tables:,
    event: killed(creature:, faction: unlisted_faction),
    now_ms: 0,
  )
}

/// Kills these creatures one after another and gives the log at the end and the effects
/// each kill gave.
fn slain_in_turn(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  creatures creatures: List(Int),
) -> #(quest_log.QuestLog, List(List(objective.Effect))) {
  let #(log, effects) =
    list.fold(creatures, #(log, []), fn(so_far, creature) {
      let advanced = slain(log: so_far.0, tables:, creature:)
      #(advanced.log, [advanced.effects, ..so_far.1])
    })
  #(log, list.reverse(effects))
}

/// A quest held accepted with these objectives done and these progress values.
fn group_quest_log(
  quest_id quest_id: Int,
  done_mask done_mask: Int,
  progress progress: List(Int),
) -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id:,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask:,
      progress:,
    ),
  ])
}

/// Strange Brew, whose one objective 14233 (type 15, count 1, flags 4) names the pane
/// TargetGroup 4793: Raken 38117, Elja 38125 and Meloth 40502.
const strange_brew = 7908

const raken = 38_117

const elja = 38_125

const meloth = 40_502

pub fn a_named_group_objective_completes_once_every_pane_member_is_killed_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log = quest_support.log_of(rows: [quest_support.untouched(strange_brew)])
  let #(after, effects) =
    slain_in_turn(log:, tables:, creatures: [raken, elja, meloth])
  assert effects
    == [
      [],
      [],
      [
        SendProgress(quest_id: strange_brew, objective_index: 0, progress: 1),
        SendState(quest_id: strange_brew, state: 2),
      ],
    ]
    as "the first two kills of the pane's three give no effect (progress stays 0, opcode.0x361), and the third completes objective 14233 (count 1: 0x140551840) and the quest"
  let #(after_two, _) = slain_in_turn(log:, tables:, creatures: [raken, elja])
  assert kill_masks_of(log: after_two, quest_id: strange_brew)
    == [3, 0, 0, 0, 0, 0]
    as "Raken and Elja are entries 0 and 1 of the pane (TargetGroup 4793: 38117, 38125, 40502): the mask is 0b011"
  assert kill_masks_of(log: after, quest_id: strange_brew) == [7, 0, 0, 0, 0, 0]
    as "all three entries are marked"
}

pub fn a_named_group_of_one_completes_on_its_one_kill_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Power Unleashed: objective 0 is 6902 (type 14, count 2), and objective 1 is 6182
  // (type 15, count 1, flags 7: it waits for every earlier objective), whose pane 4672
  // is {16660}; 8142 and 8143 follow, with flags 44.
  let log =
    group_quest_log(quest_id: 4512, done_mask: 1, progress: [3, 0, 0, 0])
  assert slain(log:, tables:, creature: 16_662).effects == []
    as "16662, the Cluster - Corrupter row, is not in pane 4672, so it counts nothing"
  assert slain(log:, tables:, creature: 16_660).effects
    == [
      SendProgress(quest_id: 4512, objective_index: 1, progress: 1),
      SendState(quest_id: 4512, state: 2),
    ]
    as "the group's one creature completes objective 6182 (count 1), and the quest is Achieved: objectives 8142 and 8143 have flag 0x20 (flags 44), which the client's state skips (0x1405fbc40)"
}

pub fn the_eldan_augmentor_needs_the_augmentor_and_digstone_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Objective 7750 (type 15, count 1, flags 7) waits for 7734 (type 17), and its pane
  // 6353 is {19333, 23420}; objective 17769 follows.
  let waiting =
    group_quest_log(quest_id: 4851, done_mask: 0, progress: [0, 0, 0])
  assert slain_in_turn(log: waiting, tables:, creatures: [19_333, 23_420]).1
    == [[], []]
    as "7750 waits for every earlier objective (flag 2, 0x140553790) and 7734 is open: the unreachable objective takes nothing"
  let log = group_quest_log(quest_id: 4851, done_mask: 1, progress: [1, 0, 0])
  let #(after, effects) =
    slain_in_turn(log:, tables:, creatures: [19_333, 17_996, 23_420])
  assert effects
    == [
      [],
      [],
      [SendProgress(quest_id: 4851, objective_index: 1, progress: 1)],
    ]
    as "19333 alone gives no effect, Digstone 17996 (faction 171) is in no pane and counts nothing, and 23420 completes objective 7750"
  assert kill_masks_of(log: after, quest_id: 4851) == [0, 3, 0, 0, 0, 0]
    as "both entries of pane 6353 are marked in the objective's slot 1"
}

pub fn portside_needs_darugna_and_blackbeak_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Objective 8354 (index 3, type 15, count 1, flags 7) waits for objectives 8224, 8226
  // and 8232, and 8685 follows; its pane 5347 is {24100, 24106}.
  let log =
    group_quest_log(quest_id: 5578, done_mask: 7, progress: [1, 1, 1, 0, 0])
  let #(after, effects) =
    slain_in_turn(log:, tables:, creatures: [24_106, 24_100])
  assert effects
    == [
      [],
      [SendProgress(quest_id: 5578, objective_index: 3, progress: 1)],
    ]
    as "24106 is the pane's second entry and 24100 its first: objective 8354 completes on the second kill"
  assert kill_masks_of(log: after, quest_id: 5578) == [0, 0, 0, 3, 0, 0]
    as "both entries are marked in slot 3"
}

pub fn what_must_be_done_needs_venator_and_a_grimvoid_thug_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Objective 8908 is the quest's only one; its pane 7097 is {26124, 33577}.
  let log = quest_support.log_of(rows: [quest_support.untouched(5922)])
  assert slain_in_turn(log:, tables:, creatures: [26_124]).1 == [[]]
    as "26124 alone does not complete objective 8908"
  assert slain_in_turn(log:, tables:, creatures: [33_577]).1 == [[]]
    as "nor does 33577 alone"
  let done = [
    SendProgress(quest_id: 5922, objective_index: 0, progress: 1),
    SendState(quest_id: 5922, state: 2),
  ]
  assert slain_in_turn(log:, tables:, creatures: [26_124, 33_577]).1
    == [[], done]
    as "the two together complete it"
  assert slain_in_turn(log:, tables:, creatures: [33_577, 26_124]).1
    == [[], done]
    as "in either order"
}

pub fn double_trouble_needs_both_inventors_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Objective 7396 (index 1, type 15, count 1, flags 4) follows 7397 (type 12), which is
  // done; its pane 8534 is {20230, 17532}.
  let log = group_quest_log(quest_id: 4961, done_mask: 1, progress: [1, 0])
  assert slain_in_turn(log:, tables:, creatures: [17_532, 20_275, 20_230]).1
    == [
      [],
      [],
      [
        SendProgress(quest_id: 4961, objective_index: 1, progress: 1),
        SendState(quest_id: 4961, state: 2),
      ],
    ]
    as "17532 then 20230 complete objective 7396, and 20275, a text-token row (Q4755 Quest Target) in no pane, counts nothing between them"
}

pub fn a_second_kill_of_the_same_group_member_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log = quest_support.log_of(rows: [quest_support.untouched(strange_brew)])
  let #(after, effects) =
    slain_in_turn(log:, tables:, creatures: [raken, raken, elja])
  assert effects == [[], [], []]
    as "one creature counts once: the second Raken is no new member, and Elja is the second of three"
  assert kill_masks_of(log: after, quest_id: strange_brew) == [3, 0, 0, 0, 0, 0]
    as "the mask stays 0b011"
  assert quest_log.objective_progress(
      log: after,
      quest: quest_of(id: strange_brew, tables:),
      index: 0,
    )
    == 0
    as "the objective is still open"
}

pub fn a_kill_in_the_pane_of_a_type_8_or_16_objective_still_counts_one_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 1804's objective 1889 is type 2, 1806's 1891 is type 8 and 1807's 1892 is type
  // 16; the type 8 and 16 objectives name TargetGroup 307 as their data, and each is
  // given it as its reward pane too.
  use tables <- with_objectives(edits: [
    #(1889, "targetGroupIdRewardPane", 307),
    #(1891, "targetGroupIdRewardPane", 307),
    #(1892, "targetGroupIdRewardPane", 307),
  ])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1804, progress: [0]),
      quest_support.accepted(quest_id: 1806, progress: [0]),
      quest_support.accepted(quest_id: 1807, progress: [0]),
    ])
  let advanced = slain(log:, tables:, creature: group_member)
  assert advanced.effects
    == [
      SendProgress(quest_id: 1804, objective_index: 0, progress: 333),
      SendProgress(quest_id: 1806, objective_index: 0, progress: 250),
      SendProgress(quest_id: 1807, objective_index: 0, progress: 500),
    ]
    as "0x140550c50: the pane counts for every kill type, and the group rule is limited to type 15: types 2, 8 and 16 advance by an equal share of their counts (3, 4 and 2) as before"
  assert list.map([1804, 1806, 1807], fn(quest_id) {
      kill_masks_of(log: advanced.log, quest_id:)
    })
    == [
      [0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0],
    ]
    as "none of them changes a kill mask"
}

pub fn an_abandoned_quest_retaken_starts_its_group_with_no_kills_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log = quest_support.log_of(rows: [quest_support.untouched(strange_brew)])
  let #(killed_once, _) = slain_in_turn(log:, tables:, creatures: [raken])
  assert kill_masks_of(log: killed_once, quest_id: strange_brew)
    == [1, 0, 0, 0, 0, 0]
    as "Raken is marked"
  // The abandon request holds the quest in the side list as state 6
  // (`quest_log.hold`, as `quest.gleam` does), dropping its active entry.
  let abandoned =
    quest_log.hold(
      log: killed_once,
      quest_id: strange_brew,
      state: quest_log.Abandoned,
    )
  let retaken =
    quest_log.accept(
      log: abandoned,
      quest: quest_of(id: strange_brew, tables:),
      max_time_ms: 0,
      now_ms: 0,
    )
  assert kill_masks_of(log: retaken, quest_id: strange_brew)
    == [0, 0, 0, 0, 0, 0]
    as "the retaken quest's new entry starts with no kill"
  let #(after, effects) =
    slain_in_turn(log: retaken, tables:, creatures: [elja, meloth])
  assert effects == [[], []]
    as "Elja and Meloth alone do not complete the group: Raken died before the abandon"
  assert kill_masks_of(log: after, quest_id: strange_brew) == [6, 0, 0, 0, 0, 0]
    as "the mask is 0b110"
}

pub fn a_completed_quest_holds_no_group_mask_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log = quest_support.log_of(rows: [quest_support.untouched(strange_brew)])
  let #(achieved, _) =
    slain_in_turn(log:, tables:, creatures: [raken, elja, meloth])
  assert quest_log.state(
      log: achieved,
      quest: quest_of(id: strange_brew, tables:),
    )
    == 2
    as "the third kill makes the quest Achieved"
  let turned_in =
    quest_log.complete(log: achieved, quest_id: strange_brew, at_seconds: 1000)
  assert quest_log.rows(log: turned_in, now_ms: 0)
    == [quest_support.completed(strange_brew, at: 1000)]
    as "a turned-in quest is Completed(at:), which holds no entry and so no kill mask (migration 0021: only an active row holds its entry, so its store row has a null kill_mask)"
}

/// A held item stack. Its guid only has to differ between the stacks of one test.
fn held(
  item item: Int,
  at location: Int,
  slot bag_index: Int,
  stack stack_count: Int,
) -> store.HeldItem {
  HeldItem(
    item_guid: item * 1000 + location * 10 + bag_index,
    item2_id: Item2Id(item),
    location:,
    bag_index:,
    stack_count:,
    random_stats: 0,
  )
}

/// The time the settles run at: 2025-04-24 20:26:40 UTC in Unix milliseconds, the entry
/// time of the connection tests (`world_entry_support.filetime`).
const settled_at_ms = 1_745_526_400_000

fn settled(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  items items: List(store.HeldItem),
  zones zones: List(Int),
) -> objective.Advanced {
  settled_at(
    log:,
    tables:,
    items:,
    zones:,
    place: place_support.live_character_place(),
  )
}

fn settled_at(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  items items: List(store.HeldItem),
  zones zones: List(Int),
  place place: start_place.Place,
) -> objective.Advanced {
  objective.settle(
    log:,
    tables:,
    items:,
    zones:,
    place:,
    shown: dict.new(),
    now_ms: 0,
    numbers: spawn_support.numbers,
    unix_ms: settled_at_ms,
  )
}

pub fn settle_counts_held_type_4_items_in_the_counted_locations_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 2710 of quest 2347 waits for objective 2709 (flags 2), which the
  // player holds no item for: the count does not wait with it.
  use tables <- with_objectives(edits: [#(2710, "flags", 2)])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1854, progress: [0]),
      quest_support.active(
        quest_id: 1855,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [3],
      ),
      quest_support.active(
        quest_id: 1856,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [3],
      ),
      quest_support.accepted(quest_id: 2347, progress: [0, 0, 0]),
      quest_support.completed(quest_id: 2989, at: 1_700_000_000),
    ])
  let items = [
    // 1854's item 3993: a stack in the inventory (location 1) and one at location
    // 8 count; five in the bank (location 2) count for nothing (0x140552550).
    held(item: 3993, at: 1, slot: 0, stack: 1),
    held(item: 3993, at: 8, slot: 0, stack: 1),
    held(item: 3993, at: 2, slot: 0, stack: 5),
    // 1855's item 3995: one of the three needed.
    held(item: 3995, at: 0, slot: 0, stack: 1),
    // 1856's item 3997: five held, two more than needed.
    held(item: 3997, at: 9, slot: 0, stack: 5),
    // 2347's items 4857 (four) and 4858 (one); 4859 is not held.
    held(item: 4857, at: 1, slot: 3, stack: 4),
    held(item: 4858, at: 9, slot: 1, stack: 1),
    // 2989 is completed, whatever is held for it.
    held(item: 5913, at: 1, slot: 5, stack: 12),
  ]
  let counted = settled(log:, tables:, items:, zones: [])
  assert counted.effects
    == [
      SendProgress(quest_id: 1854, objective_index: 0, progress: 2),
      SendProgress(quest_id: 1855, objective_index: 0, progress: 1),
      SendState(quest_id: 1855, state: 1),
      SendProgress(quest_id: 2347, objective_index: 0, progress: 1),
      SendProgress(quest_id: 2347, objective_index: 1, progress: 1),
    ]
    as "quests in id order: 1854 holds 1 + 1 of 3 (the bank's five do not count); 1855, Achieved, falls from 3 to 1 and is Accepted again; 1856 holds more than the 3 it had, which changes nothing; 2347's capped four and its unreachable second objective are counted, its third is not held; 2989 is completed and untouched"
  assert quest_log.stored_state(log: counted.log, quest_id: 1854) == 1
    as "1854 stays Accepted"
  assert quest_log.stored_state(log: counted.log, quest_id: 1855) == 1
    as "1855 is Accepted again"
  assert quest_log.stored_state(log: counted.log, quest_id: 1856) == 2
    as "1856 stays Achieved"
  assert quest_log.stored_state(log: counted.log, quest_id: 2989) == 3
    as "2989 stays completed"
  assert settled(log: counted.log, tables:, items:, zones: [])
    == Advanced(log: counted.log, effects: [])
    as "a second count of the same items changes nothing"
}

pub fn settle_counts_type_33_through_the_schematic_output_item_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 7415, progress: [0]),
    ])
  // Objective 13485 names schematic 374, whose output is Item2 21484.
  let by_schematic_id =
    settled(
      log:,
      tables:,
      items: [held(item: 374, at: 1, slot: 0, stack: 1)],
      zones: [],
    )
  assert by_schematic_id == Advanced(log:, effects: [])
    as "the item whose id is the schematic's id is not the one it counts"
  let made =
    settled(
      log:,
      tables:,
      items: [held(item: 21_484, at: 1, slot: 0, stack: 1)],
      zones: [],
    )
  assert made.effects
    == [
      SendProgress(quest_id: 7415, objective_index: 0, progress: 1),
      SendState(quest_id: 7415, state: 2),
    ]
    as "the schematic's output item held counts for the objective"
  assert quest_log.stored_state(log: made.log, quest_id: 7415) == 2
    as "and finishes the quest"
}

pub fn settle_sends_progress_before_the_state_both_ways_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1854, progress: [0]),
    ])
  let up =
    settled(
      log:,
      tables:,
      items: [held(item: 3993, at: 1, slot: 0, stack: 3)],
      zones: [],
    )
  assert up.effects
    == [
      SendProgress(quest_id: 1854, objective_index: 0, progress: 3),
      SendState(quest_id: 1854, state: 2),
      CompleteByServer(quest_id: 1854),
    ]
    as "the third item: 0x361 then 0x35c 2"
  let down =
    settled(
      log: up.log,
      tables:,
      items: [held(item: 3993, at: 1, slot: 0, stack: 2)],
      zones: [],
    )
  assert down.effects
    == [
      SendProgress(quest_id: 1854, objective_index: 0, progress: 2),
      SendState(quest_id: 1854, state: 1),
    ]
    as "losing one: 0x361 then 0x35c 1"
  assert quest_log.stored_state(log: down.log, quest_id: 1854) == 1
    as "the quest is Accepted again"

  // Three objectives lost at once are three 0x361 and one 0x35c.
  let all_three =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 2347,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b111,
        progress: [1, 1, 1],
      ),
    ])
  assert settled(log: all_three, tables:, items: [], zones: []).effects
    == [
      SendProgress(quest_id: 2347, objective_index: 0, progress: 0),
      SendProgress(quest_id: 2347, objective_index: 1, progress: 0),
      SendProgress(quest_id: 2347, objective_index: 2, progress: 0),
      SendState(quest_id: 2347, state: 1),
    ]
    as "the state is sent once, after the quest's progress messages"
}

pub fn entering_a_zone_advances_open_type_17_objectives_in_its_chain_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // Objective 1965 of quest 1862 names zone 263.
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1862, progress: [0]),
    ])
  assert settled(log:, tables:, items: [], zones: [12])
    == Advanced(log:, effects: [])
    as "an unrelated zone changes nothing"
  let entered = settled(log:, tables:, items: [], zones: [263])
  assert entered.effects
    == [
      SendProgress(quest_id: 1862, objective_index: 0, progress: 1),
      SendState(quest_id: 1862, state: 2),
      CompleteByServer(quest_id: 1862),
    ]
    as "entering the zone finishes the visit and the quest"
  assert settled(log: entered.log, tables:, items: [], zones: [12])
    == Advanced(log: entered.log, effects: [])
    as "a done visit stays done when the player leaves"

  // Zone 5998 is inside 5997, which is inside 4961 (WorldZone parentZoneId).
  use parent <- with_objectives(edits: [#(1965, "data", 5997)])
  assert settled(log:, tables: parent, items: [], zones: [5998, 5997, 4961]).effects
    == [
      SendProgress(quest_id: 1862, objective_index: 0, progress: 1),
      SendState(quest_id: 1862, state: 2),
      CompleteByServer(quest_id: 1862),
    ]
    as "a visit naming a parent zone counts in the child zone (prerequisite 26 walks parentZoneId upward)"
  assert settled(log:, tables: parent, items: [], zones: [4000])
    == Advanced(log:, effects: [])
    as "a zone outside the chain does not"
  use child <- with_objectives(edits: [#(1965, "data", 5998)])
  assert settled(log:, tables: child, items: [], zones: [5997, 4961])
    == Advanced(log:, effects: [])
    as "a visit naming the child zone does not count in the parent"
  use none <- with_objectives(edits: [#(1965, "data", 0)])
  assert settled(log:, tables: none, items: [], zones: [0])
    == Advanced(log:, effects: [])
    as "data 0 names no zone (row 6375's shape), though the chain of zone 0 is [0]"
}

pub fn settle_counts_a_visit_once_its_objective_opens_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let standing_in = [5998, 5997, 4961]
  // Quest 10520's visit (objective index 4, zone 5998, flags 3) waits for the
  // objectives of index 0, 2 and 3; index 3 is a kill of creature 73499.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_520,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b101,
        progress: [7, 0, 1, 0, 0],
      ),
    ])
  assert settled(log:, tables:, items: [], zones: standing_in)
    == Advanced(log:, effects: [])
    as "standing in the zone counts nothing while the visit waits for an earlier objective"
  let slain =
    objective.advance(
      log:,
      tables:,
      event: killed(creature: 73_499, faction: unlisted_faction),
      now_ms: 0,
    )
  assert slain.effects
    == [SendProgress(quest_id: 10_520, objective_index: 3, progress: 1)]
    as "the kill opens the visit but does not count it"
  let opened = settled(log: slain.log, tables:, items: [], zones: standing_in)
  assert opened.effects
    == [
      SendProgress(quest_id: 10_520, objective_index: 4, progress: 1),
      SendState(quest_id: 10_520, state: 2),
    ]
    as "the player still stands in the zone, so the visit counts once it is open"

  // A quest taken while standing in the zone counts at once.
  let taken =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1862, progress: [0]),
    ])
  assert settled(log: taken, tables:, items: [], zones: [263]).effects
    == [
      SendProgress(quest_id: 1862, objective_index: 0, progress: 1),
      SendState(quest_id: 1862, state: 2),
      CompleteByServer(quest_id: 1862),
    ]
    as "a quest accepted in the zone counts its visit at accept"
}

/// Runs the body on the fixture's tables with creature 12919's quest-anim columns
/// naming this quest and objective index, built on the body's heap.
fn with_quest_anim(
  quest quest: Int,
  index index: Int,
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows = case
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Creature2",
      id: 12_919,
      with: [
        #("questAnimStateId", Integer(quest)),
        #("questAnimObjectiveIndex", Integer(index)),
      ],
    )
  {
    Ok(changed) -> changed
    Error(refusal) -> panic as fixture_tables.describe(refusal)
  }
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

pub fn using_a_quest_anim_creature_advances_its_named_type_32_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12919's questAnim columns name quest 3741, objective index 0
  // (objective 4813, type 32, count 6).
  use tables <- with_objectives(edits: [])
  let collectible = Creature2Id(12_919)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 3741, progress: [0]),
    ])
  let used =
    objective.advance(log:, tables:, event: a_use(collectible), now_ms: 0)
  assert used.effects
    == [SendProgress(quest_id: 3741, objective_index: 0, progress: 1)]
    as "one cast of the collectible is one of the six"
  let again =
    objective.advance(
      log: used.log,
      tables:,
      event: a_use(collectible),
      now_ms: 0,
    )
  assert again.effects
    == [SendProgress(quest_id: 3741, objective_index: 0, progress: 2)]
    as "and each later one is one more"

  let done =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 3741,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [6],
      ),
    ])
  assert objective.advance(
      log: done,
      tables:,
      event: a_use(collectible),
      now_ms: 0,
    )
    == Advanced(log: done, effects: [])
    as "a done objective takes nothing"
  let finished =
    quest_support.log_of(rows: [quest_support.completed(quest_id: 3741, at: 1)])
  assert objective.advance(
      log: finished,
      tables:,
      event: a_use(collectible),
      now_ms: 0,
    )
    == Advanced(log: finished, effects: [])
    as "a completed quest takes nothing"
  let other =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1805, progress: [0, 0]),
    ])
  assert objective.advance(
      log: other,
      tables:,
      event: a_use(collectible),
      now_ms: 0,
    )
    == Advanced(log: other, effects: [])
    as "a creature naming another quest does nothing for a quest whose type 32 objective it does not name"

  // Quest 5857's objective index 1 (8784, type 32, flags 3) waits for index 0.
  use named_elsewhere <- with_quest_anim(quest: 5857, index: 1)
  let waiting =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 5857, progress: [0, 0]),
    ])
  assert objective.advance(
      log: waiting,
      tables: named_elsewhere,
      event: a_use(collectible),
      now_ms: 0,
    )
    == Advanced(log: waiting, effects: [])
    as "an unreachable objective takes nothing (0x140553790)"
  let reachable =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 5857,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0],
      ),
    ])
  assert objective.advance(
      log: reachable,
      tables: named_elsewhere,
      event: a_use(collectible),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 5857, objective_index: 1, progress: 1)]
    as "the same objective counts once the one before it is done"
  assert objective.advance(
      log:,
      tables: named_elsewhere,
      event: a_use(collectible),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "and the creature now names quest 5857, so quest 3741's objective takes nothing from it"
}

/// Quest 10518 (the Exile tutorial) with its objective 0 done and the other five open.
fn exile_mine_log() -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id: 10_518,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0, 0, 0, 0, 0],
    ),
  ])
}

pub fn a_use_of_a_mine_counts_its_exile_type_5_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 73463's prerequisiteIdAnimState is Prerequisite 41818: type 43 on quest
  // 10518 index 1 or on quest 10524 index 1. Objective 21287 is index 1 of quest 10518,
  // type 5 with count 1 and flags 3 (it waits for objective 0).
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: exile_mine_log(),
      tables:,
      event: a_use(Creature2Id(73_463)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 10_518, objective_index: 1, progress: 1)]
    as "the use counts the one the objective needs"
}

pub fn a_use_of_the_same_mine_counts_the_dominion_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21313 is index 1 of quest 10524, type 5 with count 1 and flags 3.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_524,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0, 0, 0],
      ),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(73_463)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 10_524, objective_index: 1, progress: 1)]
    as "the same creature counts the Dominion quest's objective"
}

pub fn a_quest_anim_link_counts_a_type_5_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 4989's questAnim columns name quest 2020, objective index 1: objective
  // 2744, type 5 with count 1 and flags 1.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 2020, progress: [0, 0, 0, 0, 0, 0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(4989)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 2020, objective_index: 1, progress: 1)]
    as "the link counts whatever the objective's type is"
  assert objective.advance(
      log:,
      tables:,
      event: Used(
        target: plain_unit(creature: Creature2Id(4989)),
        checklist_index: 0,
        unit: quest_support.unit_ref(unit_id: 4989),
        by_item: True,
      ),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "an item's spell at the same creature is not the creature's own activate cast, so the link does not count it"
}

pub fn a_prerequisite_link_counts_a_type_32_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12321 has no questAnim column and prerequisiteIdAnimState 12379: type 6 on
  // quest 3655 and type 43 on quest 3655 index 0, whose objective 4722 is type 32 with
  // count 8.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 3655, progress: [0, 0]),
    ])
  let used =
    objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(12_321)),
      now_ms: 0,
    )
  assert used.effects
    == [SendProgress(quest_id: 3655, objective_index: 0, progress: 1)]
    as "one use is one of the eight"
  assert objective.advance(
      log: used.log,
      tables:,
      event: a_use(Creature2Id(12_321)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 3655, objective_index: 0, progress: 2)]
    as "and each later use is one more"
}

pub fn a_use_counts_nothing_once_its_linked_objective_is_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12919's questAnim columns name quest 3741, objective index 0: objective
  // 4813, type 32 with count 6.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 3741,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [6],
      ),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(12_919)),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a done objective counts no more uses"
}

pub fn a_link_to_an_objective_not_yet_reachable_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10518's objective 21287 has flags 3, so it waits for objective 0 (21286).
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 10_518, progress: [0, 0, 0, 0, 0, 0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(73_463)),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "an unreachable objective takes nothing (0x140553790)"
}

pub fn a_link_to_a_type_4_objective_counts_nothing_by_the_link_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 7952's questAnim columns name quest 2731, objective index 0: objective
  // 3422, type 4 (a held item), whose progress is what the player holds.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 2731, progress: [0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(7952)),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a use does not count an objective the server counts by what is held"
}

pub fn a_nested_prerequisite_link_counts_its_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 19277 has no questAnim column and prerequisiteIdAnimState 7341, whose type 11
  // condition names Prerequisite 7340: type 6 on quest 4975 and type 43 on quest 4975
  // index 0, whose objective 15980 is type 5 with count 3 (Prerequisite
  // .prerequisiteTypeId.11 and .43).
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 4975, progress: [0, 0, 0, 0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(19_277)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 4975, objective_index: 0, progress: 1)]
    as "the objective the nested row names counts the use"
}

/// A quest of the finish tests' rows, completed at some time before the settles.
fn finished_quest(quest_id quest_id: Int) -> store.QuestRow {
  quest_support.completed(quest_id:, at: 1_745_000_000)
}

/// Quest 7540 accepted with nothing counted, and these other quests.
fn named_by_finish_objective(
  rows rows: List(store.QuestRow),
) -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: 7540, progress: [0, 0]),
    ..rows
  ])
}

pub fn a_finished_quest_completes_the_open_objective_that_names_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log = named_by_finish_objective(rows: [finished_quest(quest_id: 6305)])
  assert settled(log:, tables:, items: [], zones: []).effects
    == [SendProgress(quest_id: 7540, objective_index: 0, progress: 1)]
    as "quest 6305 is completed, so objective 13654 (type 24, data 6305) counts; 6306 is not in the log, so 13655 waits, and the quest stays Accepted"
}

pub fn a_quest_finished_before_its_objective_opened_counts_at_once_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    named_by_finish_objective(rows: [
      finished_quest(quest_id: 6305),
      finished_quest(quest_id: 6306),
    ])
  assert settled(log:, tables:, items: [], zones: []).effects
    == [
      SendProgress(quest_id: 7540, objective_index: 0, progress: 1),
      SendProgress(quest_id: 7540, objective_index: 1, progress: 1),
      SendState(quest_id: 7540, state: 2),
    ]
    as "a quest accepted after both named quests were completed counts both objectives in its first settle and is Achieved"
}

pub fn a_place_arrival_opens_a_finish_objective_that_counts_in_the_same_pass_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9492, progress: [0, 0]),
      finished_quest(quest_id: 9494),
    ])
  let at_the_marker =
    place_support.at(
      world_id: 51,
      world_zone_id: 2548,
      x: 3897.55078125,
      y: -769.8460693359375,
      z: -2380.611572265625,
    )
  assert settled(log:, tables:, items: [], zones: []).effects == []
    as "away from the marker the place objective is not done, so the finish objective behind it (flags 3) is not open"
  assert settled_at(log:, tables:, items: [], zones: [], place: at_the_marker).effects
    == [
      SendProgress(quest_id: 9492, objective_index: 0, progress: 1),
      SendProgress(quest_id: 9492, objective_index: 1, progress: 1),
      SendState(quest_id: 9492, state: 2),
      CompleteByServer(quest_id: 9492),
    ]
    as "the arrival completes 18249, which opens 18123, which counts in the same call"
}

pub fn an_achieved_quest_not_yet_turned_in_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    named_by_finish_objective(rows: [
      quest_support.active(
        quest_id: 6305,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b11,
        progress: [1, 1],
      ),
    ])
  assert settled(log:, tables:, items: [], zones: []).effects == []
    as "6305 is Achieved, not completed: the objective's text reads \"Complete quest\" (text 742846)"
}

pub fn an_abandoned_quest_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    named_by_finish_objective(rows: [
      quest_support.known(quest_id: 6305, state: 6),
    ])
  assert settled(log:, tables:, items: [], zones: []).effects == []
    as "state 6 is Abandoned, which is not a completion"
}

pub fn a_quest_missing_from_the_log_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log = named_by_finish_objective(rows: [])
  assert settled(log:, tables:, items: [], zones: []).effects == []
    as "the settle reads one character's log, and 6305 and 6306 are not in it"
}

pub fn a_yearly_quest_finished_before_this_years_reset_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let owner = quest_support.accepted(quest_id: 10_502, progress: [0, 0, 0, 0])
  // The yearly reset before the settle is 2025-01-01 10:00:00 UTC, 1_735_725_600.
  let before_reset =
    quest_support.log_of(rows: [
      owner,
      quest_support.completed(quest_id: 10_503, at: 1_735_725_599),
    ])
  assert settled(log: before_reset, tables:, items: [], zones: []).effects == []
    as "10503 (yearly) was completed a second before this year's reset: the client's completed bit is clear (0x1405fb350.completed_bit), so the objective does not count"
  let after_reset =
    quest_support.log_of(rows: [
      owner,
      quest_support.completed(quest_id: 10_503, at: 1_735_725_601),
    ])
  assert settled(log: after_reset, tables:, items: [], zones: []).effects
    == [SendProgress(quest_id: 10_502, objective_index: 0, progress: 1)]
    as "completed a second after the reset, the bit is set and the objective counts"
}

pub fn a_counted_finish_objective_stays_done_when_its_quest_is_taken_again_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_502,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0],
      ),
      quest_support.accepted(quest_id: 10_503, progress: [0]),
    ])
  let after = settled(log:, tables:, items: [], zones: [])
  assert after.effects == []
    as "10503 is Active again: the objective is not lowered and nothing is told"
  assert quest_log.objective_progress(
      log: after.log,
      quest: quest_of(id: 10_502, tables:),
      index: 0,
    )
    == 1
    as "the returned log still holds the count: a silent lowering fails here"
}

pub fn a_counted_finish_objective_is_not_told_again_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log = named_by_finish_objective(rows: [finished_quest(quest_id: 6305)])
  let first = settled(log:, tables:, items: [], zones: [])
  assert first.effects
    == [SendProgress(quest_id: 7540, objective_index: 0, progress: 1)]
    as "the first settle tells the count"
  assert settled(log: first.log, tables:, items: [], zones: []).effects == []
    as "a second settle of the returned log sends nothing: one 0x361 for each change"
}

// The cast objectives (`QuestObjective.type.11`) read these rows. The client counts
// nothing for a type 11 objective; it shows the spell as a button (`0x176`, kind 2) and
// the server's 0x361 value counts.
// - quest 7618: objective 13884, spell 40471, count 1, flags 0.
// - quest 3915: objectives 5101 (type 5), 5102 and 5103 (type 5, flags 3) and 5197 (type
//   11, flags 3, spell 25306, count 1), which waits for the three before it.
// - quest 6431: objective 9881 (type 22) and 9882 (type 11, flags 0, data 0: no spell).
// - quest 3955: objective 5181, spell 25287, count 20.
// - quest 6372: objectives 9771, 9767, 9768, 9769 and 9770; 9771, 9768 and 9770 are
//   type 11 of spell 33300 (flags 3, count 1), 9767 is type 3 and 9769 type 22.

const the_first_cast_quest = 7618

const the_first_cast_objective = 13_884

const the_first_cast_spell = 40_471

const the_gated_cast_quest = 3915

const the_gated_cast_objective = 5197

const the_gated_cast_spell = 25_306

const the_counted_cast_quest = 3955

const the_counted_cast_spell = 25_287

const the_shared_cast_quest = 6372

const the_shared_cast_spell = 33_300

fn buttons_of(log log: quest_log.QuestLog) -> List(#(Int, Int)) {
  objective.buttons(log:, tables: fixture_tables.shared())
  |> set.to_list
  |> list.map(fn(button) { #({ button.spell4_id }.value, button.objective_id) })
}

pub fn an_open_cast_objective_holds_its_spell_as_a_button_test() -> Nil {
  use <- owned_test.run(60_000)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
    ])
  assert buttons_of(log:) == [#(the_first_cast_spell, the_first_cast_objective)]
    as "QuestObjective.type.11.button: row 13884 (type 11, data 40471) is open, so its spell is a button for it"
}

pub fn a_cast_objective_opens_its_button_only_when_reachable_test() -> Nil {
  use <- owned_test.run(60_000)
  let waiting =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_gated_cast_quest, progress: [
        0,
        0,
        0,
        0,
      ]),
    ])
  assert buttons_of(log: waiting) == []
    as "0x140553790: row 5197 has flags 3 and waits for the three objectives before it"
  let reached =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: the_gated_cast_quest,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b111,
        progress: [1, 1, 1, 0],
      ),
    ])
  assert buttons_of(log: reached)
    == [#(the_gated_cast_spell, the_gated_cast_objective)]
    as "with those done the objective is reachable and open"
}

pub fn a_done_cast_objective_holds_no_button_test() -> Nil {
  use <- owned_test.run(60_000)
  let open =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
    ])
  assert buttons_of(log: open)
    == [#(the_first_cast_spell, the_first_cast_objective)]
    as "row 13884 at progress 0 is open and holds its button, so the empty set below is the done objective's"
  let done =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: the_first_cast_quest,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1],
      ),
    ])
  assert buttons_of(log: done) == []
    as "0x1403b9fb0: the button is taken away once the objective is at its count of 1"
}

pub fn a_cast_objective_with_no_spell_holds_no_button_test() -> Nil {
  use <- owned_test.run(60_000)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 6431, progress: [0, 0]),
    ])
  assert buttons_of(log:) == []
    as "0x14039b340 refuses a spell with no Spell4 row (22): row 9882's data 0 names none, so its button would be dead"
}

pub fn button_changes_remove_what_closed_and_add_what_opened_test() -> Nil {
  use <- owned_test.run(60_000)
  let first = Button(Spell4Id(the_shared_cast_spell), 9768)
  let second = Button(Spell4Id(the_shared_cast_spell), 9770)
  assert objective.button_changes(
      held: set.from_list([first]),
      now: set.from_list([second]),
    )
    == [Remove(first), Add(second)]
    as "0x1403b9fb0: an entry is keyed by spell, kind and id, so the closed objective's is removed and the opened one's added, removes first"
  assert objective.button_changes(
      held: set.from_list([first]),
      now: set.from_list([first]),
    )
    == []
    as "a duplicate add is ignored by the client, so what is held already is not sent again"
}

fn cast_of(spell spell: Int) -> objective.Event {
  Cast(spell4_id: Spell4Id(spell), target: None)
}

pub fn a_cast_of_the_objective_spell_completes_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
    ])
  let cast =
    objective.advance(
      log:,
      tables:,
      event: cast_of(spell: the_first_cast_spell),
      now_ms: 0,
    )
  assert cast.effects
    == [
      SendProgress(
        quest_id: the_first_cast_quest,
        objective_index: 0,
        progress: 1,
      ),
      SendState(quest_id: the_first_cast_quest, state: 2),
    ]
    as "opcode.0x361: row 13884's count is 1, so one cast fills it and the quest is Achieved; the client counts nothing for type 11"
}

pub fn each_cast_counts_one_up_to_the_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_counted_cast_quest, progress: [0]),
    ])
  let after =
    list.index_fold(list.repeat(Nil, 20), log, fn(log, _, at) {
      let number = at + 1
      let cast =
        objective.advance(
          log:,
          tables:,
          event: cast_of(spell: the_counted_cast_spell),
          now_ms: 0,
        )
      let progress =
        SendProgress(
          quest_id: the_counted_cast_quest,
          objective_index: 0,
          progress: number,
        )
      case number {
        20 -> {
          assert cast.effects
            == [
              progress,
              SendState(quest_id: the_counted_cast_quest, state: 2),
              CompleteByServer(quest_id: the_counted_cast_quest),
            ]
            as "row 5181's count is 20: the 20th cast changes the state"
          Nil
        }
        _ -> {
          assert cast.effects == [progress]
            as "each cast before the count tells one more"
          Nil
        }
      }
      cast.log
    })
  assert objective.advance(
      log: after,
      tables:,
      event: cast_of(spell: the_counted_cast_spell),
      now_ms: 0,
    )
    == Advanced(log: after, effects: [])
    as "a done objective takes nothing from a 21st cast"
}

pub fn a_cast_of_another_spell_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: cast_of(spell: the_first_cast_spell),
      now_ms: 0,
    ).effects
    != []
    as "row 13884's own spell 40471 counts, so the empty answer below is the other spell's"
  assert objective.advance(
      log:,
      tables:,
      event: cast_of(spell: the_gated_cast_spell),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "row 13884's data is 40471, not 25306"
}

pub fn a_cast_counts_the_open_objective_and_not_one_waiting_on_another_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objectives 9771 and 9767 are done: 9768 is open, and 9770 (index 4, flags 3) waits
  // for 9769, which no cast counts.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: the_shared_cast_quest,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b11,
        progress: [1, 1, 0, 0, 0],
      ),
    ])
  let cast =
    objective.advance(
      log:,
      tables: fixture_tables.shared(),
      event: cast_of(spell: the_shared_cast_spell),
      now_ms: 0,
    )
  assert cast.effects
    == [
      SendProgress(
        quest_id: the_shared_cast_quest,
        objective_index: 2,
        progress: 1,
      ),
    ]
    as "rows 9768, 9770 and 9771 all name spell 33300 (flags 3); only 9768 is open (0x140553790), so only it counts, and the quest is not Achieved"
}

pub fn a_cast_counts_nothing_on_a_quest_not_in_the_active_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let counted =
    objective.advance(
      log: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
      ]),
      tables:,
      event: cast_of(spell: the_first_cast_spell),
      now_ms: 0,
    )
  assert counted.effects != []
    as "the quest in the active list counts the cast, so the empty answers below are its state's"
  let nothing = fn(row) {
    let log = quest_support.log_of(rows: [row])
    assert objective.advance(
        log:,
        tables:,
        event: cast_of(spell: the_first_cast_spell),
        now_ms: 0,
      )
      == Advanced(log:, effects: [])
      as "0x1405510d0: an objective is open only for a quest in the active list"
  }
  nothing(quest_support.completed(quest_id: the_first_cast_quest, at: 1000))
  nothing(quest_support.known(quest_id: the_first_cast_quest, state: 6))
}

/// Quest 10415, whose only objective is 21094 (type 23, flags 4, count 8, group 14175).
fn group_use_log() -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: 10_415, progress: [0]),
  ])
}

/// A Bon Voyage log (quest 10528 for the Exile, 10530 for the Dominion) after the talk:
/// the first objective done.
fn bon_voyage_after_the_talk(quest_id quest_id: Int) -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id:,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0, 0, 0, 0],
    ),
  ])
}

pub fn a_use_of_a_group_unit_counts_a_type_23_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // QuestObjective 21094 is type 23 with TargetGroup 14175 (a list of creatures, 72197
  // first), count 8 and flags 4: a use of one of the group counts one.
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: group_use_log(),
      tables:,
      event: a_use(Creature2Id(72_197)),
      now_ms: 0,
    ).effects
    == [SendProgress(quest_id: 10_415, objective_index: 0, progress: 1)]
    as "a use of a unit in the group counts one toward the objective's count of 8"
}

pub fn a_use_of_a_unit_outside_the_group_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 73606 is in TargetGroup 14367, not in 14175.
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: group_use_log(),
      tables:,
      event: a_use(Creature2Id(73_606)),
      now_ms: 0,
    ).effects
    == []
    as "a unit outside the objective's group counts nothing"
}

pub fn each_use_counts_one_toward_a_larger_count_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let count = fn(log, creature) {
    objective.advance(
      log:,
      tables:,
      event: a_use(Creature2Id(creature)),
      now_ms: 0,
    )
  }
  let first = count(group_use_log(), 72_197)
  let second = count(first.log, 72_198)
  let third = count(second.log, 72_231)
  assert third.effects
    == [SendProgress(quest_id: 10_415, objective_index: 0, progress: 3)]
    as "three uses of three different units of the group are 3 of 8, and the quest is not told it is Achieved"
  assert quest_log.stored_state(log: third.log, quest_id: 10_415) == 1
    as "the quest stays Accepted: 3 of 8 is not done"
}

pub fn the_northern_wilds_terminal_counts_travel_and_its_own_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10528: 21326 (talk), 21327 (travel, type 23), 21328 and 21329 (the choices,
  // type 23, flags 33), the last two with a TargetGroup that holds both terminals,
  // 73605 and 73606.
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_528),
      tables:,
      event: a_use(Creature2Id(73_606)),
      now_ms: 0,
    ).effects
    == [
      SendProgress(quest_id: 10_528, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_528, objective_index: 2, progress: 1),
      SendState(quest_id: 10_528, state: 2),
    ]
    as "the travel (index 1) and the Northern Wilds choice (index 2) count; the Everstar Grove choice (index 3) does not; the travel was the last objective without flag 0x20, so the quest is Achieved"
}

pub fn the_everstar_terminal_counts_only_its_own_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_528),
      tables:,
      event: a_use(Creature2Id(73_605)),
      now_ms: 0,
    ).effects
    == [
      SendProgress(quest_id: 10_528, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_528, objective_index: 3, progress: 1),
      SendState(quest_id: 10_528, state: 2),
    ]
    as "the travel (index 1) and the Everstar Grove choice (index 3) count, not the Northern Wilds choice"
}

pub fn each_dominion_terminal_counts_its_own_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10530: 21347 (talk), 21348 (travel), 21349 (Levian Bay) and 21350 (Crimson
  // Isle), the choices of type 23 with flags 33.
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_530),
      tables:,
      event: a_use(Creature2Id(74_773)),
      now_ms: 0,
    ).effects
    == [
      SendProgress(quest_id: 10_530, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_530, objective_index: 2, progress: 1),
      SendState(quest_id: 10_530, state: 2),
    ]
    as "Levian Bay counts the travel and objective 21349"
  assert objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_530),
      tables:,
      event: a_use(Creature2Id(74_772)),
      now_ms: 0,
    ).effects
    == [
      SendProgress(quest_id: 10_530, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_530, objective_index: 3, progress: 1),
      SendState(quest_id: 10_530, state: 2),
    ]
    as "Crimson Isle counts the travel and objective 21350"
}

pub fn a_talk_to_a_terminal_counts_no_type_23_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  assert objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_528),
      tables:,
      event: a_talk(Creature2Id(73_606)),
      now_ms: 0,
    ).effects
    == []
    as "a type 23 objective counts a use, not a talk"
}

pub fn travel_done_leaves_bon_voyage_achieved_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21342 (index 4) is type 14 with flags 41: it has flag 0x20, so the quest
  // is Achieved without it, and it stays open in the Achieved quest.
  use tables <- with_objectives(edits: [])
  let used =
    objective.advance(
      log: bon_voyage_after_the_talk(quest_id: 10_528),
      tables:,
      event: a_use(Creature2Id(73_606)),
      now_ms: 0,
    )
  let quest = quest_of(id: 10_528, tables:)
  assert quest_log.stored_state(log: used.log, quest_id: 10_528) == 2
    as "the travel done makes Bon Voyage Achieved (0x35c state 2)"
  assert quest_log.objective_done(log: used.log, quest:, index: 1)
    as "the travel is done"
  assert quest_log.objective_done(log: used.log, quest:, index: 2)
    as "the Northern Wilds choice is done"
  assert !quest_log.objective_done(log: used.log, quest:, index: 4)
    as "the optional objective is not"
  assert quest_log.objective_open(log: used.log, quest:, index: 4)
    as "the optional objective is still open in the Achieved quest"
  assert quest_log.active_ids(log: used.log) == [10_528]
    as "the quest is still in the active list, not completed"
}

/// The log of one quest accepted with nothing counted.
fn fresh(quest_id quest_id: Int) -> quest_log.QuestLog {
  quest_support.log_of(rows: [quest_support.untouched(quest_id:)])
}

/// The log and messages after this event.
fn used_by(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  event event: objective.Event,
) -> objective.Advanced {
  objective.advance(log:, tables:, event:, now_ms: 0)
}

pub fn a_second_use_of_the_same_unit_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6723's only objective, 10383, is type 23 on TargetGroup 3568 (Creature2 30826
  // and 30827), count 15. The client's `0x140550c50` (line 142) tests only the group and
  // `0x1405517a0` makes no type 23 a checklist, so the once is the server's choice.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 6723, tables:)
  let use_of_unit_7 =
    a_use_of(
      creature: Creature2Id(30_826),
      unit: quest_support.unit_ref(unit_id: 7),
    )
  let first = used_by(log: fresh(quest_id: 6723), tables:, event: use_of_unit_7)
  assert first.effects
    == [SendProgress(quest_id: 6723, objective_index: 0, progress: 1)]
    as "the first use of the unit counts one"
  let second = used_by(log: first.log, tables:, event: use_of_unit_7)
  assert second.effects == [] as "the same unit again counts nothing"
  assert quest_log.objective_progress(log: second.log, quest:, index: 0) == 1
    as "the progress stays 1"
}

pub fn units_of_one_creature_each_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6607's objective 10278 (index 0) is type 23 on TargetGroup 3437, whose only
  // creature is 30470, with count 4: only four units of that creature finish it.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 6607, tables:)
  let use_unit = fn(log, unit_id) {
    used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(30_470),
        unit: quest_support.unit_ref(unit_id:),
      ),
    ).log
  }
  let progress = fn(log) {
    quest_log.objective_progress(log:, quest:, index: 0)
  }
  let one = use_unit(fresh(quest_id: 6607), 7)
  let two = use_unit(one, 8)
  let three = use_unit(two, 9)
  assert [progress(one), progress(two), progress(three)] == [1, 2, 3]
    as "each unit of the creature counts one"
  assert !quest_log.objective_done(log: three, quest:, index: 0)
    as "3 of 4 is not done"
  let four = use_unit(three, 10)
  assert progress(four) == 4 as "the fourth unit counts the fourth"
  assert quest_log.objective_done(log: four, quest:, index: 0)
    as "the objective is done at its count of 4 (0x361)"
}

pub fn the_same_unit_id_in_another_map_run_counts_test() -> Nil {
  use <- owned_test.run(60_000)
  // Unit ids start at 1 again in each run of a map (`world_map/map`), so unit 7 of
  // incarnation 2 is another unit than unit 7 of incarnation 1.
  use tables <- with_objectives(edits: [])
  let first_run = quest_support.unit_ref(unit_id: 7)
  let second_run = quest_log.UnitRef(..first_run, incarnation: 2)
  let use_in = fn(log, run) {
    used_by(
      log:,
      tables:,
      event: a_use_of(creature: Creature2Id(30_826), unit: run),
    )
  }
  let first = use_in(fresh(quest_id: 6723), first_run)
  let second = use_in(first.log, second_run)
  assert second.effects
    == [SendProgress(quest_id: 6723, objective_index: 0, progress: 2)]
    as "unit 7 of the next run counts as another unit"
}

pub fn a_fake_drop_in_the_reward_pane_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 18561 (quest 9682, index 4) is type 23 with data TargetGroup 10971 (a union
  // of 10968, 10969 and 10958: Creature2 65280, 65282 and 65281, "Real Drop") and reward
  // pane 12216, which adds 10970 (Creature2 65279, "Fake Drop 1"). The pane only marks
  // and shows targets; progress comes only from the server's 0x361.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 9682,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1111,
        progress: [0b111_1111_1111, 1, 1, 1, 0],
      ),
    ])
  assert used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(65_279),
        unit: quest_support.unit_ref(unit_id: 7),
      ),
    ).effects
    == []
    as "a use of the fake drop of the reward pane counts nothing"
  assert used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(65_281),
        unit: quest_support.unit_ref(unit_id: 8),
      ),
    ).effects
    == [SendProgress(quest_id: 9682, objective_index: 4, progress: 1)]
    as "a use of a real drop of the data group counts one"
}

pub fn a_type_23_objective_with_no_group_counts_no_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // QuestObjective 8323 (quest 5568) has data 0 and reward pane 0, and TargetGroup has no
  // row 0.
  use tables <- with_objectives(edits: [])
  let count_use = fn(creature, unit_id) {
    used_by(
      log: fresh(quest_id: 5568),
      tables:,
      event: a_use_of(
        creature: Creature2Id(creature),
        unit: quest_support.unit_ref(unit_id:),
      ),
    ).effects
  }
  assert count_use(30_826, 7) == []
    as "a creature of another group counts nothing"
  assert count_use(65_281, 8) == []
    as "a creature of another group counts nothing"
}

pub fn a_use_after_the_objective_is_done_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 3167's objective 4143 (index 0) is type 23 on TargetGroup 7687 (Creature2 9868
  // and 9869), count 1, and done here.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 3167,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0, 0, 0],
      ),
    ])
  assert used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(9869),
        unit: quest_support.unit_ref(unit_id: 12),
      ),
    ).effects
    == []
    as "an objective at its count is not open and takes no use"
}

pub fn the_use_that_reaches_the_count_achieves_the_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 4522's only objective, 6167, is type 23 on TargetGroup 4314 (Creature2 16645,
  // 16646 and 16647), count 5.
  use tables <- with_objectives(edits: [])
  let uses = [
    #(16_645, 1),
    #(16_646, 2),
    #(16_647, 3),
    #(16_645, 4),
    #(16_646, 5),
  ]
  let #(log, effects) =
    list.fold(uses, #(fresh(quest_id: 4522), []), fn(so_far, one) {
      let advanced =
        used_by(
          log: so_far.0,
          tables:,
          event: a_use_of(
            creature: Creature2Id(one.0),
            unit: quest_support.unit_ref(unit_id: one.1),
          ),
        )
      #(advanced.log, list.append(so_far.1, [advanced.effects]))
    })
  assert effects
    == [
      [SendProgress(quest_id: 4522, objective_index: 0, progress: 1)],
      [SendProgress(quest_id: 4522, objective_index: 0, progress: 2)],
      [SendProgress(quest_id: 4522, objective_index: 0, progress: 3)],
      [SendProgress(quest_id: 4522, objective_index: 0, progress: 4)],
      [
        SendProgress(quest_id: 4522, objective_index: 0, progress: 5),
        SendState(quest_id: 4522, state: 2),
        CompleteByServer(quest_id: 4522),
      ],
    ]
    as "five units count 1 to 5, and the fifth achieves the quest"
  assert used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(16_647),
        unit: quest_support.unit_ref(unit_id: 6),
      ),
    ).effects
    == []
    as "a sixth unit counts nothing: the objective is done"
}

pub fn one_use_counts_once_for_each_objective_of_its_set_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quests 5531 (objective 8271) and 5718 (8527) each have a type 23 objective on
  // TargetGroup 6355 (Creature2 24308 and 24310), count 12; each remembers its own
  // units.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.untouched(quest_id: 5531),
      quest_support.untouched(quest_id: 5718),
    ])
  let use_of_unit_7 =
    a_use_of(
      creature: Creature2Id(24_308),
      unit: quest_support.unit_ref(unit_id: 7),
    )
  let first = used_by(log:, tables:, event: use_of_unit_7)
  assert first.effects
    == [
      SendProgress(quest_id: 5531, objective_index: 0, progress: 1),
      SendProgress(quest_id: 5718, objective_index: 0, progress: 1),
    ]
    as "one use counts for both quests' objectives"
  assert used_by(log: first.log, tables:, event: use_of_unit_7).effects == []
    as "the same use again counts for neither"
}

pub fn use_targets_leaves_out_a_used_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 9122's objective 16479 (index 2) is type 23 on TargetGroup 8374 (captives
  // 52900 to 52905, none with an activate spell), count 9, flags 4.
  use tables <- with_objectives(edits: [])
  let captive = fn(creature) { plain_unit(creature: Creature2Id(creature)) }
  let log = fresh(quest_id: 9122)
  assert objective.use_targets(log:, tables:)(
    captive(52_900),
    0,
    quest_support.unit_ref(unit_id: 7),
  )
    as "an unused captive of the group is offered"
  let used =
    used_by(
      log:,
      tables:,
      event: a_use_of(
        creature: Creature2Id(52_900),
        unit: quest_support.unit_ref(unit_id: 7),
      ),
    )
  let offered = objective.use_targets(log: used.log, tables:)
  assert !offered(captive(52_900), 0, quest_support.unit_ref(unit_id: 7))
    as "the unit used already is not offered again"
  assert offered(captive(52_901), 0, quest_support.unit_ref(unit_id: 8))
    as "another captive of the group is still offered"
}

pub fn a_type_23_use_counts_nothing_for_another_type_on_the_same_group_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 9122: 16477 (index 0, type 12, flags 4), 16478 (index 1, type 17, flags 3),
  // 16479 (index 2, type 23), 16480 (index 3, type 8, flags 516) and 16579 (index 4,
  // type 22, flags 3). Flags 3 wait for every earlier objective, so a fresh log has
  // indexes 0, 2 and 3 open, and with 16477 done 1, 2 and 3 are.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 9122, tables:)
  let after_16477 =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 9122,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0, 0],
      ),
    ])
  let counts_only_index_2 = fn(log) {
    let used =
      used_by(
        log:,
        tables:,
        event: a_use_of(
          creature: Creature2Id(52_900),
          unit: quest_support.unit_ref(unit_id: 7),
        ),
      )
    assert used.effects
      == [SendProgress(quest_id: 9122, objective_index: 2, progress: 1)]
      as "only the type 23 objective counts the use"
    assert list.map([0, 1, 3, 4], fn(index) {
        quest_log.objective_progress(log: used.log, quest:, index:)
      })
      == list.map([0, 1, 3, 4], fn(index) {
        quest_log.objective_progress(log:, quest:, index:)
      })
      as "the other objectives' progress is as it was"
  }
  counts_only_index_2(fresh(quest_id: 9122))
  counts_only_index_2(after_16477)
}

/// A cast of the spell at this unit of a map run.
fn cast_at(
  spell spell: Int,
  creature creature: Int,
  unit unit: quest_log.UnitRef,
) -> objective.Event {
  Cast(
    spell4_id: Spell4Id(spell),
    target: Some(CastTarget(
      unit: plain_unit(creature: Creature2Id(creature)),
      ref: unit,
    )),
  )
}

/// A cast of the spell at this unit of the first run.
fn cast_at_unit(
  spell spell: Int,
  creature creature: Int,
  unit_id unit_id: Int,
) -> objective.Event {
  cast_at(spell:, creature:, unit: quest_support.unit_ref(unit_id:))
}

pub fn a_targeted_cast_counts_only_a_unit_in_the_reward_pane_test() -> Nil {
  use <- owned_test.run(60_000)
  // QuestObjective 14295 (quest 7757) is a type 11 cast of Spell4 69507 with TargetGroup
  // 8954 as its reward pane and count 8. TargetGroup 8954 lists 38290 and not 58762,
  // which the spell's cast group 7102 lists. The pane counts a unit for any objective
  // type (`0x140550c50`).
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 7757, tables:)
  let outside =
    used_by(
      log: fresh(quest_id: 7757),
      tables:,
      event: cast_at_unit(spell: 69_507, creature: 58_762, unit_id: 900),
    )
  assert outside.effects == []
    as "a unit of the cast group that the pane lacks counts nothing"
  assert quest_log.objective_progress(log: outside.log, quest:, index: 0) == 0
    as "the progress stays 0"
  let inside =
    used_by(
      log: fresh(quest_id: 7757),
      tables:,
      event: cast_at_unit(spell: 69_507, creature: 38_290, unit_id: 901),
    )
  assert inside.effects
    == [SendProgress(quest_id: 7757, objective_index: 0, progress: 1)]
    as "a unit of the pane counts one"
}

pub fn a_targeted_cast_with_no_pane_counts_any_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // QuestObjective 4098 (quest 3145, Spell4 7103, count 10) has reward pane 0, so any
  // unit counts (issue 724's decision 2c); TargetGroup 836, its spell's cast group, lists
  // 9369 and not 24571.
  use tables <- with_objectives(edits: [])
  let first =
    used_by(
      log: fresh(quest_id: 3145),
      tables:,
      event: cast_at_unit(spell: 7103, creature: 9369, unit_id: 900),
    )
  assert first.effects
    == [SendProgress(quest_id: 3145, objective_index: 0, progress: 1)]
    as "a unit of the group counts one"
  let second =
    used_by(
      log: first.log,
      tables:,
      event: cast_at_unit(spell: 7103, creature: 24_571, unit_id: 901),
    )
  assert second.effects
    == [SendProgress(quest_id: 3145, objective_index: 0, progress: 2)]
    as "a unit the cast group lacks counts too, as the objective names no pane"
}

pub fn a_pane_only_row_counts_its_pane_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 8539's objective index 1 is 15119 (Spell4 41218, count 1, flags 3, pane 8784
  // of Creature2 39073), which waits for index 0.
  use tables <- with_objectives(edits: [])
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 8539,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0],
      ),
    ])
  let quest = quest_of(id: 8539, tables:)
  assert used_by(
      log:,
      tables:,
      event: cast_at_unit(spell: 41_218, creature: 32_668, unit_id: 900),
    ).effects
    == []
    as "a unit outside pane 8784 counts nothing"
  let counted =
    used_by(
      log:,
      tables:,
      event: cast_at_unit(spell: 41_218, creature: 39_073, unit_id: 901),
    )
  assert list.contains(
    counted.effects,
    SendProgress(quest_id: 8539, objective_index: 1, progress: 1),
  )
    as "the pane's unit counts one"
  assert quest_log.objective_done(log: counted.log, quest:, index: 1)
    as "the objective is done at its count of 1"
}

pub fn a_self_aimed_cast_still_counts_with_no_target_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 7618's objective 13884 (Spell4 40471) is aimed at the caster, so its cast
  // names no unit (issue 724's decision 2c).
  use tables <- with_objectives(edits: [])
  assert used_by(
      log: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: the_first_cast_quest, progress: [0]),
      ]),
      tables:,
      event: Cast(spell4_id: Spell4Id(the_first_cast_spell), target: None),
    ).effects
    == [
      SendProgress(
        quest_id: the_first_cast_quest,
        objective_index: 0,
        progress: 1,
      ),
      SendState(quest_id: the_first_cast_quest, state: 2),
    ]
    as "a cast that names no unit counts one"
}

pub fn a_second_cast_at_the_same_unit_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Jim, 2026-11-11: a targeted cast objective counts each unit once, as a type 23 does.
  // `0x1405517a0` makes no type 11 objective a checklist, so the client keeps no
  // per-unit record and the once is the server's choice.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 3145, tables:)
  let cast = cast_at_unit(spell: 7103, creature: 9369, unit_id: 900)
  let first = used_by(log: fresh(quest_id: 3145), tables:, event: cast)
  assert first.effects
    == [SendProgress(quest_id: 3145, objective_index: 0, progress: 1)]
    as "the first cast at the unit counts one"
  let second = used_by(log: first.log, tables:, event: cast)
  assert second.effects == [] as "the same unit again counts nothing"
  assert quest_log.objective_progress(log: second.log, quest:, index: 0) == 1
    as "the progress stays 1"
}

pub fn casts_at_two_units_of_one_creature_each_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // Unit ids start at 1 again in each run of a map (`world_map/map`), so unit 900 of
  // incarnation 2 is another unit than unit 900 of incarnation 1.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 3145, tables:)
  let first_run = quest_support.unit_ref(unit_id: 900)
  let cast_in = fn(log, unit) {
    used_by(log:, tables:, event: cast_at(spell: 7103, creature: 9369, unit:)).log
  }
  let progress = fn(log) {
    quest_log.objective_progress(log:, quest:, index: 0)
  }
  let one = cast_in(fresh(quest_id: 3145), first_run)
  let two = cast_in(one, quest_log.UnitRef(..first_run, unit_id: 901))
  let three = cast_in(two, quest_log.UnitRef(..first_run, incarnation: 2))
  assert [progress(one), progress(two), progress(three)] == [1, 2, 3]
    as "each unit of the creature counts one, and unit 900 of the next run is another unit"
}

pub fn an_abandoned_and_retaken_quest_forgets_its_cast_units_test() -> Nil {
  use <- owned_test.run(60_000)
  // The used set lives on the quest's entry in the log, which an abandon replaces and an
  // accept starts anew; that a retaken quest starts afresh is the server's choice.
  use tables <- with_objectives(edits: [])
  let quest = quest_of(id: 3145, tables:)
  let cast = cast_at_unit(spell: 7103, creature: 9369, unit_id: 900)
  let first = used_by(log: fresh(quest_id: 3145), tables:, event: cast)
  assert quest_log.objective_progress(log: first.log, quest:, index: 0) == 1
    as "the cast counts one"
  let retaken =
    quest_log.accept(
      log: quest_log.hold(
        log: first.log,
        quest_id: 3145,
        state: quest_log.Abandoned,
      ),
      quest:,
      max_time_ms: 0,
      now_ms: 0,
    )
  let again = used_by(log: retaken, tables:, event: cast)
  assert again.effects
    == [SendProgress(quest_id: 3145, objective_index: 0, progress: 1)]
    as "the retaken quest counts the same unit again, from 0"
}

pub fn an_items_use_does_not_advance_a_type_32_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12919's questAnim columns name quest 3741, objective index 0 (objective
  // 4813, type 32): the objective counts the creature's own activate cast.
  use tables <- with_objectives(edits: [])
  let collectible = Creature2Id(12_919)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 3741, progress: [0]),
    ])
  assert objective.advance(
      log:,
      tables:,
      event: Used(
        target: plain_unit(creature: collectible),
        checklist_index: 0,
        unit: quest_support.unit_ref(unit_id: collectible.value),
        by_item: True,
      ),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "an item's spell at the collectible is not the creature's own activate cast"
  assert objective.advance(log:, tables:, event: a_use(collectible), now_ms: 0).effects
    == [SendProgress(quest_id: 3741, objective_index: 0, progress: 1)]
    as "the creature's own activate cast counts it"
}

// The server's completion of a quest no creature receives (`objective.CompleteByServer`).
// Evidence: quests 1854, 1857 and 1862 have flags 0 and no Creature2 row receives them
// (`communicator.completed_by_server`, whose whole-table measure is in
// `communicator_tables_test`), while Creature2 74812 receives quest 10520
// (`table_rows -- Creature2 questIdReceive00=10520`).

/// Asserts the premise of a test: the client's tables hold this quest as one the server
/// completes (or does not).
fn assert_completed_by_server(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  is is: Bool,
) -> Nil {
  let assert Ok(row) = quest2.get(tables:, id: id.Quest2Id(quest_id))
    as "the fixture holds the quest's row"
  assert communicator.completed_by_server(tables:, quest: row) == is
    as { "quest " <> int.to_string(quest_id) <> " is a server completion" }
}

pub fn a_kill_that_achieves_a_quest_no_creature_receives_emits_its_server_completion_after_state_2_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 1961 of quest 1857 (type 2, Creature2 5006, count 1) is its only one.
  let tables = fixture_tables.shared()
  assert_completed_by_server(tables:, quest_id: 1857, is: True)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1857, progress: [0]),
    ])
  let slain =
    objective.advance(
      log:,
      tables:,
      event: killed(creature: kill_target, faction: unlisted_faction),
      now_ms: 0,
    )
  assert slain.effects
    == [
      SendProgress(quest_id: 1857, objective_index: 0, progress: 1),
      SendState(quest_id: 1857, state: 2),
      CompleteByServer(quest_id: 1857),
    ]
    as "the kill's 0x361, then 0x35c 2, then the server's completion of the quest"
  assert quest_log.stored_state(log: slain.log, quest_id: 1857) == 2
    as "the log holds the quest Achieved until the completion's answer"
}

pub fn a_settle_that_achieves_a_quest_no_creature_receives_emits_its_server_completion_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  assert_completed_by_server(tables:, quest_id: 1854, is: True)
  assert_completed_by_server(tables:, quest_id: 1862, is: True)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 1854, progress: [0]),
      quest_support.accepted(quest_id: 1862, progress: [0]),
    ])
  let up =
    settled(
      log:,
      tables:,
      items: [held(item: 3993, at: 1, slot: 0, stack: 3)],
      zones: [263],
    )
  assert up.effects
    == [
      SendProgress(quest_id: 1854, objective_index: 0, progress: 3),
      SendState(quest_id: 1854, state: 2),
      CompleteByServer(quest_id: 1854),
      SendProgress(quest_id: 1862, objective_index: 0, progress: 1),
      SendState(quest_id: 1862, state: 2),
      CompleteByServer(quest_id: 1862),
    ]
    as "an item objective and a zone objective, each followed by the completion, in quest id order"
  let down =
    settled(
      log: up.log,
      tables:,
      items: [held(item: 3993, at: 1, slot: 0, stack: 2)],
      zones: [263],
    )
  assert down.effects
    == [
      SendProgress(quest_id: 1854, objective_index: 0, progress: 2),
      SendState(quest_id: 1854, state: 1),
    ]
    as "a quest falling back to Accepted is not completed"
}

pub fn a_quest_a_creature_receives_achieved_emits_no_server_completion_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  assert_completed_by_server(tables:, quest_id: 10_520, is: False)
  // Quest 10520's visit (objective index 4, zone 5998) is its last open objective; Dorian
  // Walker (Creature2 74812) receives the quest.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_520,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b01111,
        progress: [7, 1, 1, 1, 0],
      ),
    ])
  assert settled(log:, tables:, items: [], zones: [5998, 5997, 4961]).effects
    == [
      SendProgress(quest_id: 10_520, objective_index: 4, progress: 1),
      SendState(quest_id: 10_520, state: 2),
    ]
    as "the player turns it in at the creature that receives it"
}

pub fn server_completions_lists_the_achieved_qualifying_quests_of_a_log_in_id_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_520,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b11111,
        progress: [7, 1, 1, 1, 1],
      ),
      quest_support.active(
        quest_id: 1857,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [1],
      ),
      quest_support.active(
        quest_id: 1854,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [3],
      ),
      quest_support.accepted(quest_id: 1862, progress: [0]),
      quest_support.completed(quest_id: 5859, at: 1000),
      quest_support.known(quest_id: 1806, state: 5),
    ])
  assert objective.server_completions(log:, tables:) == [1854, 1857]
    as "the Achieved quests no creature receives, by quest id: not 10520 (received), 1862 (Accepted), 5859 (Completed) or 1806 (known only by its state)"
}
