//// The accept check against every quest of the client's Quest2 table.
//// Expected values come from these places.
//// - `0x140552550` (CanAcceptQuest): the checks and what each reads; a row it needs
////   that the tables lack is a load that fails (CLAUDE.md), so no quest may end in a
////   check error.
//// - Each gap names the column that makes it: `Quest2.factionIdPreq0` to `02` for a
////   reputation, `Quest2.flags` 0x80000 for a contract, `Quest2.periodicQuestGroupId`
////   for a periodic draw, `Quest2.preqItem` for a prerequisite item place and a
////   Prerequisite row of that type for a prerequisite type. A quest is counted as a
////   gap only where its own row holds that column, so the counts below owe nothing to
////   the order of the checks.
////
//// The counts of each verdict are printed for the issue's coverage measure.

import client_tables
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest.{
  type Verdict, Acceptable, Asker, NotRead, Refused,
}
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
      items: [],
    )
  let assert Ok(verdict) = quest.can_accept(tables:, quest: target, asker:)
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
  // A gap is named only for a quest whose own row holds the thing the gap is about.
  list.each(verdicts, fn(pair) {
    let #(target, verdict) = pair
    let explained = case verdict {
      NotRead(gap: quest.Reputation) ->
        target.faction_id_preq0 != 0
        || target.faction_id_preq01 != 0
        || target.faction_id_preq02 != 0
      NotRead(gap: quest.Contract) -> has_flag(target, 0x80000)
      NotRead(gap: quest.PeriodicDraw(group_id:)) ->
        group_id == target.periodic_quest_group_id && group_id != 0
      NotRead(gap: quest.PrerequisiteItemPlace) -> target.preq_item != 0
      NotRead(gap: quest.PrerequisiteType(..)) -> target.prerequisite_id != 0
      Acceptable | Refused(..) -> True
    }
    assert explained
      as {
        "quest "
        <> int.to_string(quest2.id(target).value)
        <> ": a gap is named only where the quest's own row holds what it is about"
      }
  })
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
