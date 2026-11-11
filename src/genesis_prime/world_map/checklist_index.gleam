//// The checklist index of each spawn: the unit's bit in the mask of every checklist
//// objective that counts it.
////
//// The client tests a unit against an objective's mask by `mask & (1 << index)` and counts
//// an index of 32 or more as never counted (`0x140611680`), and the server's mask has 32
//// bits (`opcode.0x361`), so the targets of one objective must hold distinct indexes in
//// 0 to 31 for the objective to reach its count. The world data's indexes do not: all
//// three spawns of Creature2 73500 carry 0. So the index is worked out from the client's
//// tables and the spawn list. In spawn order, each target spawn takes the lowest index
//// that no target spawn already given one holds in any of its objectives. With none
//// free (an objective of more than 32 targets holds all 32), it takes an index free in
//// every one of its objectives of 32 targets or fewer, which can still be distinct, and
//// of those the least held in all its objectives, so a big objective still completes on
//// distinct targets up to its count. A spawn that no checklist counts takes 0, the
//// index the client reads of a unit no objective counts.

import genesis_prime/game/quest_log
import genesis_prime/game/target_group.{type Unit}
import genesis_prime/table/id.{
  Creature2Id, PathSoldierActivateId, QuestObjectiveId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// The bits of the server's mask.
const mask_bits = 32

/// A spawn the index may be given to, and the unit as the client's group test reads
/// it.
pub type Candidate {
  Candidate(spawn: SpawnId, unit: Unit)
}

/// One checklist objective (a QuestObjective row) of a quest and the spawns that are its
/// targets, in spawn order.
pub type Checklist {
  Checklist(
    quest_id: Int,
    objective_id: Int,
    count: Int,
    targets: List(SpawnId),
  )
}

/// The checklist objectives of the quests (types 14, 18 and 28), each with the
/// candidates that are its targets: for types 14 and 18 the members of the objective's
/// TargetGroup, for type 28 the unit of its PathSoldierActivate row.
pub fn checklists(
  tables tables: table_store.Tables,
  candidates candidates: List(Candidate),
) -> List(Checklist) {
  let units =
    list.group(candidates, fn(candidate) { candidate.unit })
    |> dict.map_values(fn(_, found) {
      list.map(found, fn(candidate) { candidate.spawn })
    })
    |> dict.to_list
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
    |> list.filter_map(fn(objective_id) {
      use row <- result.try(quest_objective.get(
        tables:,
        id: QuestObjectiveId(objective_id),
      ))
      use <- bool.guard(
        when: !list.contains([14, 18, 28], row.type_)
          || !quest_log.is_checklist(tables:, objective: row),
        return: Error(Nil),
      )
      let targets =
        list.filter(units, fn(found) {
          is_target(tables:, objective: row, unit: found.0)
        })
        |> list.flat_map(fn(found) { found.1 })
        |> list.sort(by: by_spawn)
      Ok(Checklist(
        quest_id: quest.id,
        objective_id:,
        count: row.count,
        targets:,
      ))
    })
  })
}

fn is_target(
  tables tables: table_store.Tables,
  objective objective: quest_objective.QuestObjective,
  unit unit: Unit,
) -> Bool {
  case objective.type_ {
    28 ->
      case
        path_soldier_activate.get(
          tables:,
          id: PathSoldierActivateId(objective.data),
        )
      {
        Ok(row) -> unit.creature_id == Creature2Id(row.creature2_id)
        Error(Nil) -> False
      }
    _ -> target_group.contains(tables:, group: objective.data, unit:)
  }
}

fn by_spawn(a: SpawnId, b: SpawnId) -> order.Order {
  let SpawnId(a) = a
  let SpawnId(b) = b
  int.compare(a, b)
}

/// The index of each target spawn of the checklists, by the rule above. A spawn that is
/// no target is not in the result.
fn indexes(checklists checklists: List(Checklist)) -> Dict(SpawnId, Int) {
  let memberships =
    list.index_fold(checklists, dict.new(), fn(found, checklist, at) {
      list.fold(checklist.targets, found, fn(found, spawn) {
        dict.upsert(found, spawn, fn(before) {
          [at, ..option.unwrap(before, [])]
        })
      })
    })
  let small =
    list.index_fold(checklists, set.new(), fn(found, checklist, at) {
      case list.length(checklist.targets) <= mask_bits {
        True -> set.insert(found, at)
        False -> found
      }
    })
  let spawns = dict.keys(memberships) |> list.sort(by: by_spawn)
  let #(indexes, _) =
    list.fold(spawns, #(dict.new(), dict.new()), fn(state, spawn) {
      let #(indexes, held) = state
      let in = result.unwrap(dict.get(memberships, spawn), or: [])
      let index = pick(in:, held:, small:)
      let held =
        list.fold(in, held, fn(held, checklist) {
          dict.upsert(held, checklist, fn(before) {
            option.unwrap(before, dict.new())
            |> dict.upsert(index, fn(count) { option.unwrap(count, 0) + 1 })
          })
        })
      #(dict.insert(indexes, spawn, index), held)
    })
  indexes
}

/// The index for a spawn in the checklists `in`: the lowest that none holds, else the
/// lowest that none of the `small` checklists (32 targets or fewer) holds and, of those,
/// the least held in all of them, else the least held one. `held` is, for each
/// checklist, how many of its targets hold each index.
fn pick(
  in checklists: List(Int),
  held held: Dict(Int, Dict(Int, Int)),
  small small: Set(Int),
) -> Int {
  let counts = held_by(checklists:, held:)
  let small_counts =
    held_by(checklists: list.filter(checklists, set.contains(small, _)), held:)
  let #(_, _, index) =
    int.range(from: 0, to: mask_bits, with: #(2, 0, 0), run: fn(best, index) {
      let in_small = case dict.has_key(small_counts, index) {
        True -> 1
        False -> 0
      }
      let used = result.unwrap(dict.get(counts, index), or: 0)
      let against_best =
        int.compare(in_small, best.0)
        |> order.break_tie(int.compare(used, best.1))
      case best.0 == 2 || against_best == order.Lt {
        True -> #(in_small, used, index)
        False -> best
      }
    })
  index
}

/// How many targets of the checklists hold each index, summed over the checklists.
fn held_by(
  checklists checklists: List(Int),
  held held: Dict(Int, Dict(Int, Int)),
) -> Dict(Int, Int) {
  list.fold(checklists, dict.new(), fn(counts, checklist) {
    dict.get(held, checklist)
    |> result.unwrap(or: dict.new())
    |> dict.fold(counts, fn(counts, index, count) {
      dict.upsert(counts, index, fn(before) { option.unwrap(before, 0) + count })
    })
  })
}

/// The index of each candidate: its checklist index when it is a target, else 0.
pub fn assign(
  tables tables: table_store.Tables,
  candidates candidates: List(Candidate),
) -> Dict(SpawnId, Int) {
  let targets = indexes(checklists: checklists(tables:, candidates:))
  list.fold(candidates, targets, fn(found, candidate) {
    case dict.has_key(found, candidate.spawn) {
      True -> found
      False -> dict.insert(found, candidate.spawn, 0)
    }
  })
}
