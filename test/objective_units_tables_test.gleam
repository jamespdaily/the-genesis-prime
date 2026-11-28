//// The creatures each objective of the client's tables lists (`objective_units.units_of`)
//// against the creatures a use of or a cast at them counts for (`rule.counts`), over
//// every objective of every quest, so that the two cannot drift. Expected values come from
//// these places.
//// - `0x140550c50`: type 12 counts a unit by the Creature2 id in its data, type 23 by the
////   TargetGroup in its data, and any type by its reward pane; `Creature2.objective_link`
////   (`QuestObjective.type.32.sources`): types 5 and 32 count the creatures whose
////   questAnim or prerequisite columns name the objective.
//// - `TargetGroup.type.1`: only a group of that type names creatures by their ids; the
////   expected creatures of a group are read from the group's own rows
////   (`target_group.listed_creatures`), and the expected linked creatures from each
////   creature's own columns (`objective_link.links`), not from the list under test.
//// - A departures choice objective counts only its own terminal (`departures`).
//// - A group names creatures only when it is of type 1 and holds a non-zero word (it is
////   tested by its own row, `group_expectation`); every other group, and a cast with no
////   reward pane, is a unit the server cannot list.
////
//// Every objective's classification (listed, unlisted, no unit event) is asserted against
//// these sources before its creatures are.
////
//// A list is sound when every creature it holds is one a use (a cast, for type 11) counts,
//// complete when it holds every creature the same sources name, and unique.

import client_tables
import genesis_prime/game/departures
import genesis_prime/game/objective as rule
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_units.{Listed}
import genesis_prime/game/target_group
import genesis_prime/shared/objective_link
import genesis_prime/shared/quest_row
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  Creature2Id, Faction2Id, TargetGroupId, UnitRaceId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/target_group as target_group_row
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import quest_support
import unitest

/// The creatures whose rows name each (quest, index), read from each row with `links`.
fn linked_by_their_rows(
  tables tables: table_store.Tables,
) -> Dict(#(Int, Int), List(Int)) {
  list.fold(creature2.all(tables), dict.new(), fn(linked, row) {
    list.fold(
      objective_link.links(tables:, creature_id: Creature2Id(row.id)),
      linked,
      fn(linked, pair) {
        dict.upsert(linked, pair, fn(creatures) {
          case creatures {
            Some(creatures) -> [row.id, ..creatures]
            None -> [row.id]
          }
        })
      },
    )
  })
}

/// The unit of a creature as a use or a cast at it is counted: its Creature2 id, the race of
/// its row, and no faction (a type 1 group names creature ids only).
fn unit_of(
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
) -> target_group.Unit {
  target_group.Unit(
    creature_id: Creature2Id(creature_id),
    faction_id: Faction2Id(0),
    unit_race_id: case creature2.get(tables, Creature2Id(creature_id)) {
      Ok(row) -> creature2.unit_race_id(row)
      Error(Nil) -> UnitRaceId(0)
    },
  )
}

/// The event that counts a unit for the objective: a cast of its spell at the unit for a
/// type 11, a use of the unit for the rest.
fn event_for(
  tables tables: table_store.Tables,
  objective objective: quest_row.Objective,
  creature_id creature_id: Int,
) -> rule.Event {
  let unit = unit_of(tables:, creature_id:)
  let ref = quest_support.unit_ref(unit_id: 1)
  case objective_kind.cast_spell(objective.kind) {
    Ok(spell4_id) ->
      rule.Cast(spell4_id:, target: Some(rule.CastTarget(unit:, ref:)))
    Error(Nil) ->
      rule.Used(target: unit, checklist_index: 0, unit: ref, by_item: False)
  }
}

/// What the objective's own sources say `units_of` answers: the creatures they name, no
/// creature to list (a group or a pane that names none, a cast with no pane), or no unit
/// event at all.
type Expectation {
  ExpectListed(creatures: List(Int))
  ExpectUnlisted
  ExpectNoUnitEvent
}

/// The answer the objective's own sources give, worked out from the rows and the
/// objective's kind alone, never from `units_of`.
fn expected(
  tables tables: table_store.Tables,
  linked linked: Dict(#(Int, Int), List(Int)),
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_row.Objective,
) -> Expectation {
  case objective.kind {
    objective_kind.UseCreature(creature2_id:) ->
      ExpectListed([creature2_id.value])
    objective_kind.Scripted | objective_kind.CollectVirtualItem(_) ->
      ExpectListed(result_or_empty(dict.get(linked, #(quest_id, index))))
    objective_kind.UseGroup(target_group_id:) ->
      case group_expectation(tables:, group: target_group_id.value) {
        ExpectListed(group) ->
          case
            departures.choice_terminal(objective_id: objective.objective_id)
          {
            None -> ExpectListed(group)
            Some(terminal) ->
              ExpectListed(
                list.filter(group, fn(creature) { creature == terminal.value }),
              )
          }
        ExpectUnlisted -> ExpectUnlisted
        ExpectNoUnitEvent -> ExpectNoUnitEvent
      }
    objective_kind.CastSpell(_) ->
      case objective.reward_pane {
        0 -> ExpectUnlisted
        pane -> group_expectation(tables:, group: pane)
      }
    objective_kind.ChecklistUse(_)
    | objective_kind.ChecklistActivate(_)
    | objective_kind.ChecklistTalk(_)
    | objective_kind.ServerChecklist
    | objective_kind.TalkTo(_)
    | objective_kind.KillCreature(_)
    | objective_kind.KillGroup(_)
    | objective_kind.KillByCluster(_)
    | objective_kind.KillByDifficulty(_)
    | objective_kind.CollectItem(_)
    | objective_kind.CraftItem(_)
    | objective_kind.VisitZone(_)
    | objective_kind.ReachPlace
    | objective_kind.FinishQuest(_)
    | objective_kind.Placeholder
    | objective_kind.Unconditional
    | objective_kind.Unread(_) -> ExpectNoUnitEvent
  }
}

/// What a TargetGroup row says of the creatures it lists, read from the row's own type and
/// words: a group of type 1 names the creatures of its non-zero words, and any other group
/// (a group of a faction or a race, the opposite of a list, nested groups, a missing row,
/// or a type 1 group with no word) names none.
fn group_expectation(
  tables tables: table_store.Tables,
  group group: Int,
) -> Expectation {
  case target_group_row.get(tables:, id: TargetGroupId(group)) {
    Ok(row) if row.type_ == 1 ->
      case
        list.filter(
          [
            row.data0,
            row.data1,
            row.data2,
            row.data3,
            row.data4,
            row.data5,
            row.data6,
          ],
          fn(word) { word != 0 },
        )
      {
        [] -> ExpectUnlisted
        words -> ExpectListed(list.unique(words))
      }
    Ok(_) | Error(Nil) -> ExpectUnlisted
  }
}

/// The name of an expectation for a failing assertion.
fn expectation_name(expectation: Expectation) -> String {
  case expectation {
    ExpectListed(_) -> "listed creatures"
    ExpectUnlisted -> "a unit the server cannot list"
    ExpectNoUnitEvent -> "no unit event"
  }
}

fn result_or_empty(found: Result(List(Int), Nil)) -> List(Int) {
  case found {
    Ok(creatures) -> creatures
    Error(Nil) -> []
  }
}

/// A short name of the objective for a failing assertion.
fn where(
  quest_id quest_id: Int,
  objective objective: quest_row.Objective,
) -> String {
  "objective "
  <> int.to_string(objective.objective_id)
  <> " of quest "
  <> int.to_string(quest_id)
}

pub fn every_creature_an_objective_lists_is_counted_by_its_use_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let linked = linked_by_their_rows(tables:)
  let listed =
    list.flat_map(quest2.all(tables), fn(row) {
      let quest_id = row.id
      case quest_row.quest_of(tables:, id: quest_id) {
        Ok(quest) ->
          list.index_map(quest.objectives, fn(objective, index) {
            #(quest_id, index, objective)
          })
        Error(quest_row.NoQuestRow) | Error(quest_row.NoObjectiveRow(_)) -> []
      }
    })
    |> list.filter_map(fn(found) {
      let #(quest_id, index, objective) = found
      let name = where(quest_id:, objective:)
      let wanted = expected(tables:, linked:, quest_id:, index:, objective:)
      case
        objective_units.units_of(tables:, quest_id:, index:, objective:),
        wanted
      {
        Listed(creatures), ExpectListed(wanted_creatures) -> {
          assert creatures == list.unique(creatures)
            as { name <> " lists each creature once" }
          list.each(creatures, fn(creature) {
            assert rule.counts(
              tables:,
              event: event_for(tables:, objective:, creature_id: creature.value),
              quest_id:,
              index:,
              objective:,
              scripts: rule.no_rows(),
            )
              as {
                name
                <> " counts a use of Creature2 "
                <> int.to_string(creature.value)
                <> " that it lists"
              }
          })
          assert set.from_list(
              list.map(creatures, fn(creature) { creature.value }),
            )
            == set.from_list(wanted_creatures)
            as {
              name <> " lists every creature its own sources name, and no other"
            }
          Ok(objective.kind)
        }
        objective_units.Unlisted, ExpectUnlisted
        | objective_units.NoUnitEvent, ExpectNoUnitEvent
        -> Error(Nil)
        Listed(_), ExpectUnlisted
        | Listed(_), ExpectNoUnitEvent
        | objective_units.Unlisted, ExpectListed(_)
        | objective_units.Unlisted, ExpectNoUnitEvent
        | objective_units.NoUnitEvent, ExpectListed(_)
        | objective_units.NoUnitEvent, ExpectUnlisted
        ->
          panic as {
            name
            <> " is classified otherwise than its own sources say: they say "
            <> expectation_name(wanted)
          }
      }
    })
  let kinds_checked =
    list.fold(listed, set.new(), fn(kinds, kind) {
      set.insert(kinds, case kind {
        objective_kind.UseCreature(_) -> "type 12"
        objective_kind.Scripted -> "type 5"
        objective_kind.CollectVirtualItem(_) -> "type 32"
        objective_kind.UseGroup(_) -> "type 23"
        objective_kind.CastSpell(_) -> "type 11"
        objective_kind.ChecklistUse(_)
        | objective_kind.ChecklistActivate(_)
        | objective_kind.ChecklistTalk(_)
        | objective_kind.ServerChecklist
        | objective_kind.TalkTo(_)
        | objective_kind.KillCreature(_)
        | objective_kind.KillGroup(_)
        | objective_kind.KillByCluster(_)
        | objective_kind.KillByDifficulty(_)
        | objective_kind.CollectItem(_)
        | objective_kind.CraftItem(_)
        | objective_kind.VisitZone(_)
        | objective_kind.ReachPlace
        | objective_kind.FinishQuest(_)
        | objective_kind.Placeholder
        | objective_kind.Unconditional
        | objective_kind.Unread(_) -> "another kind"
      })
    })
  assert kinds_checked
    == set.from_list(["type 12", "type 5", "type 32", "type 23", "type 11"])
    as "the objectives checked are those of the five kinds that list units, and of no other"
}
