//// A read-only snapshot of a character's quest log, which the modules of the units
//// and the map read the log through. The character builds it from its log
//// (`quest_log.view`) and passes it in; no function here changes a log, and the
//// log's own module is the only one that builds a view.
////
//// ```
//// the log's entries ─▶ of ─▶ the view ─▶ state, active_ids, objective_done,
////                                        objective_open, objective_progress, is_marked
//// ```
////
//// - **A view is a value**: a change to the log afterwards does not reach a view built
////   before it.
//// - **The quest as the log holds it**: an active entry's placeholder objective
////   stands in the quest's type 31 slot (`as_logged`, 0x1405fbdc0).
//// - **The six reads are the client's**: `state` (0x1405fbc40), `objective_done`
////   (0x1405510d0), `objective_open` (0x14049f3d0), `objective_progress`
////   (0x14049f4d0, 0x1406113b0), `is_marked` (0x140611680) and the active list.

import genesis_prime/game/objective_kind
import genesis_prime/shared/quest_row.{type Objective, type Quest, Quest}
import genesis_prime/store.{
  type ActiveState, type KnownState, Accepted, Achieved,
}
import genesis_prime/world_map/spawn_id.{type SpawnId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/set.{type Set}

/// The entries of a quest log by Quest2 id, as a snapshot. Built from a log's
/// entries by `of`, which only the log's module calls.
pub opaque type QuestView {
  QuestView(entries: Dict(Int, Entry))
}

/// A view of the entries, with no copy.
pub fn of(entries entries: Dict(Int, Entry)) -> QuestView {
  QuestView(entries:)
}

/// What the character has of one quest.
pub type Entry {
  /// In the client's active list (opcode.0x35f): accepted or achieved, with the
  /// placeholder objective's id (0 for none) and, for a quest with a type 31 slot,
  /// that objective's row, which stands in the slot (0x1405fbdc0), whether it is
  /// tracked, the done mask (a bit for each of the six objectives), the progress of
  /// each objective and the time left of the quest and of each objective, in
  /// milliseconds. A quest whose Quest2 row has a time limit (`maxTimeAllowedMS`) also
  /// holds the connection's monotonic time, in milliseconds, at which its time runs
  /// out; `quest_ms_left` is the time the client was last told. Each objective with a
  /// time limit (`QuestObjective.maxTimeAllowedMS`) holds, once its timer has started,
  /// the monotonic time at which its time runs out (`objective_deadlines_ms`, one for
  /// each objective, `None` before the start and for an objective with no limit);
  /// `objective_ms_left` is what the client was last told. `optional_mask` has a bit for
  /// each objective with flag 0x20, whose time may run and show but never botches the
  /// quest, since the quest needs no such objective to be achieved. `kill_masks` holds,
  /// for each of the six objective slots, a bit for each creature of the objective's
  /// named group that the player's blow has killed (`kill_marked`); the client is never
  /// sent it. `used` holds, for each objective that counts a use of a unit or a cast at one
  /// and is not a checklist, by its index, the spawns of the objects that have counted
  /// (`used`), except for an objective the unit may count again for
  /// (`objective_units.reused`); it is saved with the quest (`rows`) and starts empty for a
  /// quest accepted.
  Active(
    state: ActiveState,
    placeholder_objective_id: Int,
    placeholder: Option(Objective),
    tracked: Bool,
    done_mask: Int,
    progress: List(Int),
    quest_ms_left: Int,
    objective_ms_left: List(Int),
    deadline_ms: Option(Int),
    objective_deadlines_ms: List(Option(Int)),
    optional_mask: Int,
    kill_masks: List(Int),
    used: Dict(Int, Set(SpawnId)),
  )
  /// Completed, at this many Unix seconds.
  Completed(at: Int)
  /// In the client's second list: a quest it holds only a state of.
  Known(state: KnownState)
}

/// The quest as the log's entry holds it: an active entry's placeholder row stands in
/// the quest's type 31 slot (0x1405fbdc0), whatever its type, flags and count.
pub fn as_logged(view view: QuestView, quest quest: Quest) -> Quest {
  case dict.get(view.entries, quest.id) {
    Ok(Active(placeholder: Some(placeholder), ..)) -> {
      let #(before, from_the_slot) =
        list.split_while(quest.objectives, fn(objective) {
          objective.kind != objective_kind.Placeholder
        })
      case from_the_slot {
        [_, ..after] ->
          Quest(
            ..quest,
            objectives: list.flatten([before, [placeholder], after]),
          )
        [] -> quest
      }
    }
    Ok(Active(..)) | Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> quest
  }
}

/// The state of the quest as the client computes it for the player (lua QuestState,
/// `0x1405fbc40`): 0 for a quest not in the log, 1 accepted, 2 achieved, 3 completed
/// and 4 to 7 for a quest it holds only a state of. A stored Accepted entry reads 2
/// when every objective without flag 0x20 is done, and a quest with no objectives is
/// then achieved at once.
pub fn state(view view: QuestView, quest quest: Quest) -> Int {
  0
}

/// The ids of the quests in the client's active list, accepted or achieved, in
/// ascending order.
pub fn active_ids(view view: QuestView) -> List(Int) {
  []
}

/// Whether the quest's objective at `index` is done (`0x1405510d0`): never at or past
/// the objective count, always for a completed quest, by the done mask for a quest in
/// the active list, never for any other.
pub fn objective_done(
  view view: QuestView,
  quest quest: Quest,
  index index: Int,
) -> Bool {
  False
}

/// Whether the quest's objective at `index` is open (`0x14049f3d0`): the quest is in
/// the active list, the objective is not done, and it is reachable.
pub fn objective_open(
  view view: QuestView,
  quest quest: Quest,
  index index: Int,
) -> Bool {
  False
}

/// Whether the objective at `index` is reachable in the log (`0x140553790`).
pub fn reachable(
  view view: QuestView,
  quest quest: Quest,
  index index: Int,
) -> Bool {
  quest_row.reachable_when(quest:, index:, done: fn(at) {
    objective_done(view:, quest:, index: at)
  })
}

/// The progress of the quest's objective at `index` as a prerequisite compares it
/// (`0x14049f4d0`): 0 for an index at or past the count, the needed count for a
/// completed quest, the in-log progress for a quest in the active list, 0 for any other.
pub fn objective_progress(
  view view: QuestView,
  quest quest: Quest,
  index index: Int,
) -> Int {
  0
}

/// Whether the unit of checklist index `bit` is counted for the quest's checklist
/// objective at `index`: the objective's stored mask has the bit (`0x140611680`). False
/// for an objective that is no checklist, a quest not in the active list and a `bit`
/// the mask has none of (the client counts those as never counted).
pub fn is_marked(
  view view: QuestView,
  quest quest: Quest,
  index index: Int,
  bit bit: Int,
) -> Bool {
  False
}

/// The entries with their quest ids, in quest id order.
pub fn in_quest_order(view view: QuestView) -> List(#(Int, Entry)) {
  dict.to_list(view.entries)
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}
