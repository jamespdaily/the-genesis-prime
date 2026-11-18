//// The kill_objective content table (migration 0044, `genesis_prime/content/kill_objective`)
//// and the load's check of its rows (`genesis_prime/game/kill_objective`): the visible
//// scripted objectives whose text asks only to kill. Expected values come from these places.
//// - `QuestObjective.type.5`: a type 5 objective is done only by the server's 0x361, and
////   `0x140550c50` counts a unit of the objective's reward pane for an objective of any
////   type, so a row's pane is the list of creatures whose kill counts for it.
//// - A row must be a kill the server can see done: a visible (flag 0x8 clear), required
////   (flag 0x20 clear) type 5 objective that no creature links (`objective_link.is_linked`),
////   with a marker row, whose pane lists a creature of CreationTypeEnum 0 (the one the
////   server fights, `creation_type`), and that no spell effect or item names
////   (`Spell4Effects.effectType.42`, `0x140398cc0`).
//// - The fixture's rows (`table_rows -- QuestObjective 15996 7515 4849 1962 9659`,
////   `TargetGroup`, `Creature2`): 15996 (quest 3170, type 5, flags 3, pane 6336 that lists
////   Creature2 9635 of CreationTypeEnum 0, marker WorldLocation2 in World 22) is a kill;
////   7515 (quest 5101, flags 17, pane 7617 that lists Creature2 20041 of CreationTypeEnum 10)
////   has no creature the server fights; 4849 (quest 3769) is named by Spell4Effects 89873;
////   1962 (quest 1859) has no marker; 9659 (quest 6296, type 12) is linked by Creature2 27768.
//// - Migration 0044: 9 rows, each a `server_choice` with its reason.

import client_tables
import content_support
import genesis_prime/content/refusal.{RowId}
import genesis_prime/game/kill_objective.{Row}
import genesis_prime/game/objective
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId}
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import quest_support
import unitest

/// The objective of quest 3170 the fixture holds as a kill: a visible, required, marked,
/// unlinked type 5 whose pane lists one creature the server fights.
const blood_for_blood = 15_996

/// The 9 objectives migration 0044 lists.
const kill_ids = [8010, 8281, 8537, 8866, 8867, 9252, 14_676, 14_681, 15_996]

/// What a row of the table does to the load.
type Outcome {
  Accepted
  Refused(saying: String)
}

/// A row to check: the QuestObjective cells edited first (id, column, value), the objective
/// named, what the load does with it and why.
type Case {
  Case(
    why: String,
    edits: List(#(Int, String, Int)),
    objective: Int,
    outcome: Outcome,
  )
}

pub fn the_kill_table_refuses_a_row_that_is_not_a_fightable_visible_required_unlinked_type_5_with_a_pane_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(cases(), fn(row) {
    use tables <- quest_support.with_objectives(edits: row.edits)
    let selected =
      kill_objective.select(rows: [Row(objective_id: row.objective)], tables:)
    case row.outcome {
      Accepted -> {
        assert selected == Ok(set.from_list([row.objective]))
          as { row.why <> ": the load takes the row" }
      }
      Refused(saying:) -> {
        let assert Error([refusal]) = selected
          as { row.why <> ": one refusal for the objective" }
        assert refusal.row == RowId(row.objective)
        assert string.contains(refusal.rule, saying)
          as {
            row.why
            <> ": the rule says "
            <> saying
            <> "; it said "
            <> refusal.rule
          }
      }
    }
  })
}

fn cases() -> List(Case) {
  [
    Case(
      why: "quest 3170's objective 15996 is a kill of the creature of pane 6336",
      edits: [],
      objective: blood_for_blood,
      outcome: Accepted,
    ),
    Case(
      why: "a type 2 row is not a scripted objective",
      edits: [#(blood_for_blood, "type", 2)],
      objective: blood_for_blood,
      outcome: Refused("not 5 (a scripted objective)"),
    ),
    Case(
      why: "flag 0x8 hides it",
      edits: [#(blood_for_blood, "flags", 3 + 8)],
      objective: blood_for_blood,
      outcome: Refused("flag 0x8 hides it"),
    ),
    Case(
      why: "flag 0x20 makes it optional",
      edits: [#(blood_for_blood, "flags", 3 + 0x20)],
      objective: blood_for_blood,
      outcome: Refused("flag 0x20 makes it optional"),
    ),
    Case(
      why: "Creature2 27768 links objective 9659, made a kill with a pane",
      edits: [
        #(9659, "type", 5),
        #(9659, "flags", 0),
        #(9659, "worldLocationsIdIndicator00", 21_383),
        #(9659, "targetGroupIdRewardPane", 6336),
      ],
      objective: 9659,
      outcome: Refused("a creature links it"),
    ),
    Case(
      why: "no marker row, so no creature can stand at it (objective 1962 of quest 1859)",
      edits: [#(1962, "targetGroupIdRewardPane", 6336)],
      objective: 1962,
      outcome: Refused(
        "none of its worldLocationsIdIndicator markers names a WorldLocation2 row",
      ),
    ),
    Case(
      why: "pane 0 names no unit",
      edits: [#(blood_for_blood, "targetGroupIdRewardPane", 0)],
      objective: blood_for_blood,
      outcome: Refused("has no reward pane"),
    ),
    Case(
      why: "a pane the TargetGroup table has no row for lists no creature",
      edits: [#(blood_for_blood, "targetGroupIdRewardPane", 4_000_000)],
      objective: blood_for_blood,
      outcome: Refused("lists no creature"),
    ),
    Case(
      why: "objective 7515's pane creature 20041 is CreationTypeEnum 10, a static object",
      edits: [],
      objective: 7515,
      outcome: Refused("no creature of creation type 0"),
    ),
    Case(
      why: "Spell4Effects 89873 names objective 4849, given the kill's pane",
      edits: [#(4849, "targetGroupIdRewardPane", 6336)],
      objective: 4849,
      outcome: Refused("a spell effect or an item names it"),
    ),
    Case(
      why: "the QuestObjective table has no row 4000000",
      edits: [],
      objective: 4_000_000,
      outcome: Refused("QuestObjective table has no row"),
    ),
  ]
}

pub fn every_row_of_the_kill_table_is_a_kill_script_with_a_pane_a_fightable_creature_and_a_placeable_marker_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = content_support.kill_objective_ids()
  assert set.to_list(rows) |> list.sort(int.compare) == kill_ids
    as "migration 0044 lists the 9 kills whose creatures start in their marker's world"
  let scripts = objective.ScriptRows(kills: rows)
  let arrivals = content_support.arrival_objective_ids()
  let wrong =
    list.filter_map(quest2.all(tables), fn(row) {
      let assert Ok(quest) = quest_log.quest_of(tables:, id: row.id)
        as "the Quest2 row's objectives are rows of the table"
      Ok(
        list.index_map(quest.objectives, fn(listed, index) {
          #(quest, index, listed)
        })
        |> list.filter(fn(place) {
          set.contains(rows, { place.2 }.objective_id)
        })
        |> list.filter_map(fn(place) {
          let #(quest, index, listed) = place
          let pane =
            target_group.listed_creatures(tables:, group: listed.reward_pane)
          let fights =
            list.any(pane, fn(creature) {
              case creature2.get(tables, Creature2Id(creature)) {
                Ok(creature) -> creature.creation_type_enum == 0
                Error(Nil) -> False
              }
            })
          let assert Ok(row) =
            quest_objective.get(
              tables:,
              id: QuestObjectiveId(listed.objective_id),
            )
            as "the objective's row"
          let worlds =
            place_objective.markers(tables:, objective: row)
            |> list.map(fn(marker) { marker.world_id })
          let script =
            objective.script_of(
              tables:,
              quest_id: quest.id,
              index:,
              objective: listed,
              arrival_objectives: arrivals,
              scripts:,
            )
          case
            script == objective.KillScript
            && pane != []
            && fights
            && worlds != []
            && list.all(worlds, fn(world) { world == 22 || world == 51 })
          {
            True -> Error(Nil)
            False -> Ok(listed.objective_id)
          }
        }),
      )
    })
    |> list.flatten
  assert wrong == []
    as "each of the 9 is the kill script, its pane lists a creature of CreationTypeEnum 0, and its markers are in World 22 or 51, the worlds with stored spawns"
  assert kill_objective.select(
      rows: list.map(kill_ids, fn(id) { Row(objective_id: id) }),
      tables:,
    )
    == Ok(rows)
    as "the load takes every row over the client's own tables"
}

pub fn no_objective_is_in_two_content_tables_and_none_is_held_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let kills = content_support.kill_objective_ids()
  let arrivals = content_support.arrival_objective_ids()
  let held = content_support.held_objective_ids()
  assert set.intersection(kills, arrivals) == set.new()
    as "a row is a kill or an arrival, never both"
  assert set.intersection(kills, held) == set.new()
    as "a held objective stays open whatever its kind, so it is never a kill row: a quest that works today must still complete"
}

/// Why a kill row stays on the stand-in, and what the client's tables show of it.
type Stays {
  /// Its marker is in a world the server holds no stored spawn for, so no creature of its
  /// pane can stand there (`objective_spawn.place` skips it).
  NoSpawnsInWorld(world: Int)
  /// No creature of its pane starts in its marker's world, stored or placed: the load leaves
  /// them out as Friendly to both factions (`spawn.select`), so no player can fight one;
  /// `world_data_counts_test` holds the check against the whole world database.
  NothingStarts
  /// Its reward pane is 0: no unit is the one to kill.
  NoPane
  /// Its pane lists no creature of creation type 0.
  StaticPane
  /// Its text adds a condition the server does not check.
  Condition(text: String)
}

/// A kill row the table leaves on the stand-in: the objective, its quest and index, why.
type Stay {
  Stay(objective: Int, quest: Int, index: Int, why: Stays)
}

pub fn the_kill_rows_left_on_the_stand_in_are_listed_with_their_reasons_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = content_support.kill_objective_ids()
  let arrivals = content_support.arrival_objective_ids()
  let scripts = objective.ScriptRows(kills: rows)
  // The worlds the server holds stored spawns for are 22, 51, 426, 870, 990, 1061 and 1387.
  let silo = Stay(9382, 6157, 0, NoSpawnsInWorld(1421))
  let stays = [
    Stay(4282, 3295, 0, NothingStarts),
    Stay(7272, 5074, 0, NothingStarts),
    Stay(7491, 5074, 1, NothingStarts),
    Stay(7492, 5074, 2, NothingStarts),
    silo,
    Stay(9474, 6161, 1, NoSpawnsInWorld(1421)),
    Stay(9902, 6170, 1, NoSpawnsInWorld(1421)),
    Stay(9516, 6180, 1, NoSpawnsInWorld(1421)),
    Stay(9722, 6283, 1, NoSpawnsInWorld(1463)),
    Stay(9969, 6461, 0, NoSpawnsInWorld(1421)),
    Stay(10_055, 6493, 1, NoSpawnsInWorld(1421)),
    Stay(10_075, 6502, 1, NoSpawnsInWorld(1421)),
    Stay(10_080, 6506, 1, NoSpawnsInWorld(1463)),
    Stay(10_114, 6517, 1, NoSpawnsInWorld(1421)),
    Stay(17_729, 9268, 0, NoSpawnsInWorld(1462)),
    Stay(17_788, 9305, 0, NoSpawnsInWorld(1462)),
    Stay(17_801, 9313, 0, NoSpawnsInWorld(1421)),
    Stay(19_091, 10_013, 0, NoSpawnsInWorld(3040)),
    Stay(
      4299,
      3297,
      1,
      Condition("until you find the one that swallowed a creature"),
    ),
    Stay(8304, 5600, 0, Condition("while a Game Huntress watches")),
    Stay(15_914, 8860, 0, Condition("while an Aurin Hunter watches")),
    Stay(12_588, 6892, 0, Condition("withstand their Pincer Flurry attacks")),
    Stay(13_943, 7657, 1, Condition("zapping security leaks, a tool")),
    Stay(17_733, 9267, 0, Condition("Enrage and kill, a mechanic")),
    Stay(
      17_793,
      9308,
      0,
      Condition("Insult them before killing, an emote first"),
    ),
    Stay(8282, 5536, 0, NoPane),
    Stay(8538, 5723, 0, NoPane),
    Stay(7515, 5101, 1, StaticPane),
  ]
  assert list.length(stays) == 28
    as "the sizing found 37 kill rows: 9 in the table and these 28 left on the stand-in"
  let wrong =
    list.filter_map(stays, fn(stay) {
      let assert Ok(quest) = quest_log.quest_of(tables:, id: stay.quest)
        as "the quest's rows are in the tables"
      let assert Ok(listed) =
        list.drop(quest.objectives, stay.index) |> list.first
        as "the quest has the objective at its index"
      let assert Ok(row) =
        quest_objective.get(tables:, id: QuestObjectiveId(stay.objective))
        as "the objective's row"
      let worlds =
        place_objective.markers(tables:, objective: row)
        |> list.map(fn(marker) { marker.world_id })
      let script =
        objective.script_of(
          tables:,
          quest_id: quest.id,
          index: stay.index,
          objective: listed,
          arrival_objectives: arrivals,
          scripts:,
        )
      let reason_holds = case stay.why {
        NoSpawnsInWorld(world:) ->
          worlds != []
          && list.all(worlds, fn(marker_world) { marker_world == world })
          && !list.contains([22, 51], world)
        NothingStarts -> True
        NoPane -> listed.reward_pane == 0
        StaticPane ->
          kill_objective.select(
            rows: [Row(objective_id: stay.objective)],
            tables:,
          )
          != Ok(set.from_list([stay.objective]))
        Condition(_) -> True
      }
      case
        listed.objective_id == stay.objective
        && script == objective.StandInOnAccept
        && reason_holds
        && !set.contains(rows, stay.objective)
      {
        True -> Error(Nil)
        False -> Ok(stay.objective)
      }
    })
  assert wrong == []
    as "each listed row is the stand-in on accept, outside the kill table, and its reason holds in the client's tables"
}
