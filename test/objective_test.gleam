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

import fixture_tables
import genesis_prime/game/objective.{
  Advanced, Killed, SendProgress, SendState, TalkedTo, Used,
}
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/store.{HeldItem}
import genesis_prime/table/id.{Creature2Id, Faction2Id, Item2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/list
import owned_test
import place_support
import planted_table.{Integer}
import quest_support

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

fn a_use(creature: id.Creature2Id) -> objective.Event {
  Used(target: plain_unit(creature:), checklist_index: 0)
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
    == [
      SendProgress(quest_id: 1804, objective_index: 0, progress: 333),
      SendProgress(quest_id: 1805, objective_index: 0, progress: 500),
    ]
    as "5007 is not the creature of objective 1889 and no cluster of 1890, but is in their reward pane: each advances by an equal share (counts 3 and 2); the talk of 6961 and the use of 9207, whose panes hold it too, take no kill"
  assert objective.advance(
      log:,
      tables:,
      event: killed(creature: stranger, faction: unlisted_faction),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a creature outside every pane changes nothing"
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

fn settled(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  items items: List(store.HeldItem),
  zones zones: List(Int),
) -> objective.Advanced {
  objective.settle(
    log:,
    tables:,
    items:,
    zones:,
    place: place_support.live_character_place(),
    shown: dict.new(),
    now_ms: 0,
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
