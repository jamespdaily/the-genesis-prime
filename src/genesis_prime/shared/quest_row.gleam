//// The quest as the client keeps it beside its log, read once from the client's
//// tables: a quest's Quest2 id and its objectives with their QuestObjective kind,
//// flags and count (`quest_of`), and the arithmetic of an objective's flags, mask
//// and needed count that the quest log and its view share.
////
//// ```
//// the tables, a Quest2 id ─▶ quest_of ─▶ the quest, or the row the client lacks
//// ```
////
//// - **A quest is read from the tables**, never from the log: its objectives in slot
////   order with the empty slots left out (`0x1405a8a40`).
//// - **An objective's flags** decide whether it is optional (`0x1405fbc40`), whether
////   it is reachable (`0x140553790`) and whether its progress is a count or
////   thousandths (`0x1406113b0`).

import genesis_prime/game/objective_kind
import genesis_prime/message/float32
import genesis_prime/table/id.{Quest2Id, QuestObjectiveId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// One objective of a quest as the client keeps it (`0x1405a8a40`, the quest record's
/// words 0x18 and after): its QuestObjective id, kind (the row's type and data decoded,
/// `objective_kind`), flags, count and data (the id of
/// the row its type names, a Creature2 id for types 3 and 12), the TargetGroup row of
/// its reward pane (0 for none), and whether it counts its progress as bits
/// (`0x1405517a0`), its time limit in milliseconds (`maxTimeAllowedMS`, 0 for none), and
/// whether it names a place to go to (`marked`: one of its four `worldLocationsIdIndicator`
/// columns names a WorldLocation2 row the table holds, as `place_objective.markers` reads
/// them; `place_objective` imports this module, so it cannot be called from here).
pub type Objective {
  Objective(
    objective_id: Int,
    kind: objective_kind.Kind,
    flags: Int,
    count: Int,
    data: Int,
    reward_pane: Int,
    checklist: Bool,
    time_limit_ms: Int,
    marked: Bool,
  )
}

/// A quest as the client keeps it beside its log: its Quest2 id and its objectives in
/// slot order, the empty slots left out.
pub type Quest {
  Quest(id: Int, objectives: List(Objective))
}

/// Why a quest cannot be read from the tables.
pub type QuestRowError {
  /// The client has no Quest2 row for the id: an unknown quest.
  NoQuestRow
  /// A slot of the quest names a QuestObjective row the client's table lacks.
  NoObjectiveRow(objective_id: Int)
}

/// The QuestObjective flag of an optional objective, which the client's quest state and
/// reachability skip (`0x1405fbc40`, `0x140553790`).
pub const optional_flag = 0x20

/// The QuestObjective flag that keeps a kill objective's progress a count.
const counted_flag = 0x200

/// The bits of a checklist's mask: the server's 0x35f and 0x361 carry 32.
pub const mask_bits = 32

/// The quest with this Quest2 id, each objective read from QuestObjective.
pub fn quest_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Quest, QuestRowError) {
  use row <- result.try(
    quest2.get(tables:, id: Quest2Id(id)) |> result.replace_error(NoQuestRow),
  )
  use objectives <- result.map(
    list.try_map(objective_ids(quest: row), fn(objective_id) {
      use row <- result.map(
        quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
        |> result.replace_error(NoObjectiveRow(objective_id:)),
      )
      objective_of(tables:, row:)
    }),
  )
  Quest(id:, objectives:)
}

/// The objectives of the quest, in the order of its six slots, left out where a
/// slot is empty (0).
pub fn objective_ids(quest quest: Quest2) -> List(Int) {
  [
    quest.objective0,
    quest.objective01,
    quest.objective02,
    quest.objective03,
    quest.objective04,
    quest.objective05,
  ]
  |> list.filter(fn(objective) { objective != 0 })
}

/// One QuestObjective row as the client keeps it.
pub fn objective_of(
  tables tables: table_store.Tables,
  row row: quest_objective.QuestObjective,
) -> Objective {
  Objective(
    objective_id: row.id,
    kind: objective_kind.of_row(row),
    flags: row.flags,
    count: row.count,
    data: row.data,
    reward_pane: row.target_group_id_reward_pane,
    checklist: objective_kind.is_checklist(
      tables:,
      kind: objective_kind.of_row(row),
    ),
    time_limit_ms: row.max_time_allowed_ms,
    marked: list.any(
      [
        row.world_locations_id_indicator00,
        row.world_locations_id_indicator01,
        row.world_locations_id_indicator02,
        row.world_locations_id_indicator03,
      ],
      fn(marker_id) {
        marker_id != 0
        && result.is_ok(world_location2.get(
          tables:,
          id: WorldLocation2Id(marker_id),
        ))
      },
    ),
  )
}

/// Whether bit `index` of a mask of the six objectives is set. The client's objective indexes run 0
/// to 5; a later one is never done.
pub fn done_in(mask mask: Int, index index: Int) -> Bool {
  index < 6 && int.bitwise_and(mask, int.bitwise_shift_left(1, index)) != 0
}

pub fn has_flag(flags flags: Int, flag flag: Int) -> Bool {
  int.bitwise_and(flags, flag) != 0
}

/// Whether every objective of the quest without flag 0x20 is done, as `done` says for
/// its index (`0x1405fbc40`); a quest with no objectives is.
pub fn every_objective_is_done(
  quest quest: Quest,
  done done: fn(Int) -> Bool,
) -> Bool {
  list.index_map(quest.objectives, fn(objective, index) {
    has_flag(flags: objective.flags, flag: optional_flag) || done(index)
  })
  |> list.all(fn(done) { done })
}

/// Whether the objective at `index` is reachable (`0x140553790`) when `done` says which
/// objectives are done: never at or past the count; always for objective type 0; with
/// flag 2, when every earlier objective without flag 0x20 is done; else with flag 1, when
/// every earlier objective is done or itself reachable; with neither flag, always.
pub fn reachable_when(
  quest quest: Quest,
  index index: Int,
  done done: fn(Int) -> Bool,
) -> Bool {
  case list.drop(quest.objectives, index) {
    [] -> False
    [Objective(kind: objective_kind.Unconditional, ..), ..] -> True
    [objective, ..] -> {
      let earlier =
        list.index_map(list.take(quest.objectives, index), fn(before, at) {
          #(at, before)
        })
      case
        has_flag(flags: objective.flags, flag: 2),
        has_flag(flags: objective.flags, flag: 1)
      {
        True, _ ->
          list.all(earlier, fn(before) {
            let #(at, objective) = before
            has_flag(flags: objective.flags, flag: optional_flag) || done(at)
          })
        False, True ->
          list.all(earlier, fn(before) {
            done(before.0) || reachable_when(quest:, index: before.0, done:)
          })
        False, False -> True
      }
    }
  }
}

/// The objective kinds whose raw progress is thousandths of completion when flag 0x200
/// is clear (`0x1406113b0`): the kills.
fn is_percent_kind(objective objective: Objective) -> Bool {
  objective_kind.is_kill(objective.kind)
  && !has_flag(flags: objective.flags, flag: counted_flag)
}

/// Whether the objective's stored progress is thousandths of completion: a percent kind
/// objective of a count above 1.
pub fn is_thousandths(objective objective: Objective) -> Bool {
  is_percent_kind(objective:) && objective.count > 1
}

/// How much progress completes the objective (`0x140551840`): 100 for a percent kind
/// objective of a count above 1, else its count.
pub fn needed(objective objective: Objective) -> Int {
  use <- bool.guard(when: is_thousandths(objective:), return: 100)
  objective.count
}

pub fn set_bits(of number: Int) -> Int {
  case number {
    0 -> 0
    _ ->
      int.bitwise_and(number, 1)
      + set_bits(of: int.bitwise_shift_right(number, 1))
  }
}

/// An objective's progress in a log entry (`0x1406113b0`): the stored value, its set
/// bits for a checklist, and above 1 for a percent kind objective, whatever its count,
/// the thousandths of completion as a share of the needed count, worked in 32-bit
/// floats.
pub fn in_log_progress(
  objective objective: Objective,
  stored stored: Int,
) -> Int {
  let raw = case objective.checklist {
    True -> set_bits(of: stored)
    False -> stored
  }
  case raw > 1 && is_percent_kind(objective:) {
    False -> raw
    True -> {
      let share =
        float32.product(
          left: float32.rounded(value: int.to_float(raw)),
          right: float32.rounded(value: 0.001),
        )
      float32.product(
        left: float32.rounded(value: int.to_float(needed(objective:))),
        right: share,
      )
      |> float.truncate
    }
  }
}
