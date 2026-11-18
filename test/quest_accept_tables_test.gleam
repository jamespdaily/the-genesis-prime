//// The accept check against every quest of the client's Quest2 table.
//// Expected values come from these places.
//// - `0x140552550` (CanAcceptQuest): the checks and what each reads; a row it needs
////   that the tables lack is a load that fails (CLAUDE.md), so no quest may end in a
////   check error.
//// - Each gap names the column that makes it: `Quest2.factionIdPreq0` to `02` for a
////   reputation, `Quest2.flags` 0x80000 for a contract, `Quest2.preqItem` for the
////   per-item counter of a prerequisite item, `Quest2.questRepeatPeriodEnum` with a
////   periodic group that draws or limits for a periodic draw, and a Prerequisite row
////   of that type (nested rows followed) for a prerequisite type. A gap is counted
////   for every quest whose own columns reach it, whatever the first check to stop a
////   particular player is.
////
//// The counts of each verdict are printed for the issue's coverage measure.

import client_tables
import content_support
import genesis_prime/game/objective
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest.{
  type Verdict, Acceptable, Asker, NotRead, Refused,
}
import genesis_prime/game/quest_log
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/quest2.{type Quest2}
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import owned_test
import prerequisite_support
import quest_support
import unitest

const exile = 167

fn verdict_of(tables: table_store.Tables, target: Quest2) -> Verdict {
  let asker =
    Asker(
      player: prerequisite_support.player(),
      factions: Factions(current: exile, base: exile),
      log: quest_support.log_of(rows: []),
      checker: prerequisite_support.empty_checker(),
    )
  let assert Ok(verdict) =
    quest.can_accept(tables:, quest: target, asker:, mask: quest.every_check)
    as {
      "quest "
      <> int.to_string(quest2.id(target).value)
      <> " runs the accept check against the client's tables"
    }
  verdict
}

fn has_flag(target: Quest2, flag: Int) -> Bool {
  int.bitwise_and(target.flags, flag) != 0
}

pub fn every_quest_runs_the_accept_check_and_counts_its_gaps_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let quests = quest2.all(tables)
  let verdicts =
    list.map(quests, fn(target) { #(target, verdict_of(tables, target)) })
  // Every quest got a verdict: a missing Prerequisite, Episode or periodic group
  // row would have stopped the run above.
  assert list.length(verdicts) == list.length(quests)
  // A quest whose rows the table lacks has no gaps to count: its verdict stops on
  // that row, so `gaps` states the same error. Every other quest has its gaps.
  let #(stated, lacking) =
    list.partition(quests, fn(target) {
      result.is_ok(quest.gaps(tables:, quest: target))
    })
  assert list.length(lacking) == 2
    as "only the two quests naming a Prerequisite row the table lacks"
  let gaps_of = fn(target) {
    let assert Ok(found) = quest.gaps(tables:, quest: target)
    found
  }
  // A gap a check stops on is one the quest's own columns reach.
  list.each(verdicts, fn(pair) {
    let #(target, verdict) = pair
    case verdict {
      NotRead(gap:) -> {
        assert list.contains(gaps_of(target), gap)
          as {
            "quest "
            <> int.to_string(quest2.id(target).value)
            <> ": a gap the check stops on is one its own columns reach"
          }
        Nil
      }
      Acceptable | Refused(..) -> Nil
    }
  })
  let reached = list.flat_map(stated, gaps_of)
  // The gaps whose columns the table states directly, counted from the table.
  assert list.count(reached, fn(gap) { gap == quest.Contract })
    == list.count(stated, fn(target) { has_flag(target, 0x80000) })
    as "a contract gap for each quest with flags 0x80000"
  assert list.count(reached, fn(gap) { gap == quest.Reputation })
    == list.count(stated, fn(target) {
      target.faction_id_preq0 != 0
      || target.faction_id_preq01 != 0
      || target.faction_id_preq02 != 0
    })
    as "a reputation gap for each quest that names a faction"
  assert list.count(reached, fn(gap) { gap == quest.PrerequisiteItemCounter })
    == list.count(stated, fn(target) { target.preq_item != 0 })
    as "an item-counter gap for each quest that needs an item"
  let reached_counts =
    list.fold(reached, dict.new(), fn(counts, gap) {
      dict.upsert(counts, quest.describe_gap(gap:), fn(count) {
        case count {
          Some(count) -> count + 1
          None -> 1
        }
      })
    })
  io.println(
    "quests whose own columns reach each gap:\n"
    <> string.join(
      reached_counts
        |> dict.to_list
        |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
        |> list.map(fn(pair) { int.to_string(pair.1) <> "  " <> pair.0 }),
      "\n",
    ),
  )
  // A quest naming a Prerequisite id the table lacks fails the client's evaluator
  // (`0x1404a1ca0`), so no such quest is acceptable: it is refused by check 12 or
  // by an earlier check.
  let dangling =
    list.filter(verdicts, fn(pair) {
      pair.0.prerequisite_id != 0
      && result.is_error(prerequisite_table.get(
        tables:,
        id: PrerequisiteId(pair.0.prerequisite_id),
      ))
    })
  assert list.all(dangling, fn(pair) { pair.1 != Acceptable })
    as "a prerequisite with no row fails"
  io.println(
    int.to_string(list.length(dangling))
    <> " quests name a Prerequisite id with no row",
  )
  let counts =
    list.fold(verdicts, dict.new(), fn(counts, pair) {
      let label = case pair.1 {
        Acceptable -> "acceptable"
        Refused(code:) -> "refused " <> int.to_string(code)
        NotRead(gap:) -> "not read: " <> quest.describe_gap(gap:)
      }
      dict.upsert(counts, label, fn(count) {
        case count {
          Some(count) -> count + 1
          None -> 1
        }
      })
    })
  let lines =
    counts
    |> dict.to_list
    |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
    |> list.map(fn(pair) { int.to_string(pair.1) <> "  " <> pair.0 })
  io.println(
    "quests "
    <> int.to_string(list.length(quests))
    <> ":\n"
    <> string.join(lines, "\n"),
  )
  assert dict.get(counts, "acceptable") != Error(Nil)
    as "some quest is acceptable to a clean level 1 Exile"
  Nil
}

/// The ids of the quests whose Prerequisite, with every row it nests (type 11, whose
/// objectId is the nested row), holds a condition of this type, read from the raw rows.
fn quests_behind(
  tables tables: table_store.Tables,
  type_id type_id: Int,
) -> List(Int) {
  quest2.all(tables)
  |> list.filter(fn(target) {
    reaches(tables:, type_id:, row_id: target.prerequisite_id, seen: [])
  })
  |> list.map(fn(target) { quest2.id(target).value })
  |> list.sort(int.compare)
}

fn reaches(
  tables tables: table_store.Tables,
  type_id type_id: Int,
  row_id row_id: Int,
  seen seen: List(Int),
) -> Bool {
  case
    list.contains(seen, row_id),
    prerequisite_table.get(tables:, id: PrerequisiteId(row_id))
  {
    True, _ | _, Error(Nil) -> False
    False, Ok(row) ->
      list.any(prerequisite.kept_conditions(row:), fn(condition) {
        condition.0 == type_id
        || {
          condition.0 == prerequisite.nested_type
          && reaches(tables:, type_id:, row_id: condition.2, seen: [
            row_id,
            ..seen
          ])
        }
      })
  }
}

pub fn the_one_quest_behind_a_title_check_is_10510_and_each_store_text_objective_is_decided_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert quests_behind(tables:, type_id: 288) == [10_510]
    as "Prerequisite.prerequisiteTypeId.288: the table's one condition of the type (row 43305, title 400) is nested in 43306, which only Quest2 10510 names"
  list.each(quest2.all(tables), fn(target) {
    // The two quests that name a Prerequisite row the table lacks state no gaps.
    case quest.gaps(tables:, quest: target) {
      Ok(found) -> {
        assert !list.contains(
          found,
          quest.PrerequisiteType(prerequisite_type: 288),
        )
          as "type 288 is read, so no quest names it as a gap"
        Nil
      }
      Error(quest.PrerequisiteNotLoaded(..)) -> Nil
      Error(quest.NoEpisodeRow(..)) | Error(quest.NoPeriodicGroupRow(..)) ->
        panic as "only a prerequisite row the table lacks stops the gaps"
    }
  })
  let held = content_support.held_objective_ids()
  // Each case: QuestObjective id, its quest, its script, whether the migrated database
  // holds it, and why. The ids are the five whose text names the In-Game Store
  // (`client_files.py text` 745285, 753381, 753384, 753435 and 753437), with flags 64,
  // 96, 40, 40 and 96 (`table_rows -- QuestObjective 21267 21371 21372 21374 21375`).
  let purchase = "a purchase the server has no store for"
  let opening =
    "opening the store is not a purchase: a creature's row links it, so a use of that creature counts it"
  let cases = [
    #(21_267, 10_510, objective.StandInWithQuest, True, purchase),
    #(
      21_371,
      10_540,
      objective.Optional,
      False,
      "an optional purchase: its flag leaves it open",
    ),
    #(
      21_375,
      10_541,
      objective.Optional,
      False,
      "an optional purchase: its flag leaves it open",
    ),
    #(21_372, 10_540, objective.UsedByCreature, False, opening),
    #(21_374, 10_541, objective.UsedByCreature, False, opening),
  ]
  list.each(cases, fn(case_) {
    let #(objective_id, quest_id, script, is_held, reason) = case_
    let assert Ok(target) = quest_log.quest_of(tables:, id: quest_id)
      as "the quest is a row of the table"
    let assert Ok(#(index, found)) =
      list.index_map(target.objectives, fn(found, index) { #(index, found) })
      |> list.find(fn(pair) { { pair.1 }.objective_id == objective_id })
      as "the quest names the objective"
    assert objective.script_of(
        tables:,
        quest_id:,
        index:,
        objective: found,
        arrival_objectives: set.new(),
        scripts: objective.no_rows(),
      )
      == script
      as reason
    assert set.contains(held, objective_id) == is_held as reason
  })
}
