//// The departures terminals at the end of the training simulation, and where each lands
//// the player: the rule behind "Bon Voyage" (Quest2 10528, Exile; 10530, Dominion).
////
//// ```
//// 0x97 ─▶ link ─ closed ─▶ 0x7fc, no 0x7fd           (objective_link.of asks `link` first)
////              └ open ───▶ 0x7fd ─▶ yes ─▶ the cast's Activated(unit, creature)
//// Activated ─▶ landing ─ Ok(place) ─▶ objective.Used counts travel + the terminal's choice
////                                      ─▶ Entered.departing = Some(place), 0 ms `timer`
//// timer ─▶ connection/departures.due ─▶ leave the tutorial map, join the landing's
//// ```
////
//// - **The terminals** (`terminals`, "fairly sure": no client column ties a terminal to its
////   choice objective or its landing; the match is the names and texts,
////   `departures.terminal_choice`): each terminal's Creature2, the faction's quest and
////   travel objective, its own choice objective and its landing's WorldLocation2 row.
////
////   | Terminal | Spell4 | Choice objective | Landing | World / zone |
////   |---|---|---|---|---|
////   | 73606 Northern Wilds | 34680 | 21328 | 42074 | 426 / 648 |
////   | 73605 Everstar Grove | 34681 | 21329 | 41641 | 990 / 1417 |
////   | 74773 Levian Bay | 50279 | 21349 | 42148 | 1387 / 1411 |
////   | 74772 Crimson Isle | 37270 | 21350 | 8223 | 870 / 1236 |
////
////   The travel objective is 21327 (Exile, quest 10528, after the talk 21326) or 21348
////   (Dominion, quest 10530, after the talk 21347); either terminal of the faction counts
////   it. Crimson Isle lands at 8223, as `start_place` already does (the coordinator's
////   choice, 2026-11-11).
//// - **No client gate** (`departures.no_client_gate`): every terminal and terminal spell has
////   0 in every prerequisite and quest column, so the client offers the yes to anyone in
////   range and the server decides: the link is open while the faction's travel objective is
////   open, and a player without the quest, or with the talk not done, or with the travel
////   done, is refused with 0x7fc before 0x7fd (Jim's decision, 2026-11-11).
//// - **The count** (`QuestObjective.type.23`): the client counts a use of any unit in the
////   objective's TargetGroup with no mask, and the three objectives of a faction share one
////   group, so `choice_terminal` ties each choice objective to its terminal for
////   `objective.counts`.
//// - **The move** is an in-world 0xad and the usual burst (`0x1403b6de0.resets`) with the
////   quest log kept (`quest_log.process_wide`), which the Holocrypt's leave and join already
////   do (`connection/departures`).
////
//// Failure table:
////
//// | What goes wrong | What happens | Where |
//// |---|---|---|
//// | A press without the quest, with the talk not done, or with travel already done | 0x7fc TargetIsNotUseable before 0x7fd; no window, nothing counted, no move | `link`, `objective_link.of`, `cast.activation_pressed` |
//// | A press on a terminal of the other faction | Closed link, as above | `link` |
//// | No, or the timeout | 0x7f9 146 and 0x7fe; nothing counted, no move | `cast.answered` (existing) |
//// | A second yes, or a yes for a cast that is not live | Debug log; nothing counted, no second move | `cast.answered` (existing) |
//// | The quest is abandoned while the window is open, then yes | The cast goes and finishes; nothing counted, no move | `landing` refuses at `Activated` |
//// | The terminal has left the player's picture by the go | Nothing counted, no move; the player may press again | `connection/casting.cast_effects` `Activated` branch (existing check) |
//// | The timer fires once the player is no longer in the world (camp, end) or is dead | Nothing | `connection/departures.due` |
//// | The old map gives no answer to the leave | The connection ends (LostUserServer) | `connection/world.leave_answered` (existing) |
//// | The landing map refuses the join | 0x594, then character select | `connection/world.entry_answered` with `FromInWorld` (existing) |
//// | The landing map gives no answer to the join | The connection ends (LostUserServer) | `connection/world.entry_answered` (existing) |
//// | Client frames during the leave and the join | They wait, as for the Holocrypt | existing |
//// | The old stay's news after the leave | Dropped by the stay check | existing |
//// | A 0x637 the client sent before the 0xad reached it | Dropped until the first 0xf2; the map is told nothing | `connection/movement`, `InWorldLoading` (existing) |
//// | The server stops between the count and the next save | The player logs in at the last saved place in the tutorial and presses again | the save timer (existing) |
//// | The client lacks a terminal's Creature2, QuestObjective or WorldLocation2 row | The table load fails at start | `requirement` |

import genesis_prime/game/activate
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/id.{type Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/option.{type Option}

/// One departures terminal: its Creature2, the faction's quest and travel objective
/// (a QuestObjective id), its own choice objective and the WorldLocation2 row it
/// lands the player at.
pub type Terminal {
  Terminal(
    creature_id: Int,
    quest_id: Int,
    travel_objective_id: Int,
    choice_objective_id: Int,
    landing_location_id: Int,
  )
}

/// The four terminals (the table above).
pub const terminals: List(Terminal) = [
  Terminal(
    creature_id: 73_606,
    quest_id: 10_528,
    travel_objective_id: 21_327,
    choice_objective_id: 21_328,
    landing_location_id: 42_074,
  ),
  Terminal(
    creature_id: 73_605,
    quest_id: 10_528,
    travel_objective_id: 21_327,
    choice_objective_id: 21_329,
    landing_location_id: 41_641,
  ),
  Terminal(
    creature_id: 74_773,
    quest_id: 10_530,
    travel_objective_id: 21_348,
    choice_objective_id: 21_349,
    landing_location_id: 42_148,
  ),
  Terminal(
    creature_id: 74_772,
    quest_id: 10_530,
    travel_objective_id: 21_348,
    choice_objective_id: 21_350,
    landing_location_id: 8223,
  ),
]

/// Why a terminal does not take the player.
pub type Refusal {
  /// The creature is not one of the terminals.
  NotATerminal
  /// The faction's travel objective is not open: the quest is not held, its talk is
  /// not done, or the travel is done.
  TravelClosed
}

/// The timer that starts the move once the cast's frames are carried out. The
/// connection's own timers are below the cast rule's, which start at 1000
/// (genesis_prime/game/cast `first_timer`).
pub const timer = TimerId(12)

/// Whether the timer is this rule's, for the connection to hand it to
/// `connection/departures.due`.
pub fn owns(timer candidate: TimerId) -> Bool {
  candidate == timer
}

/// The link of a terminal for the player's log: open while the faction's travel
/// objective is open, closed otherwise. `Error(Nil)` for a creature that is not a
/// terminal, whose link its own columns decide (`objective_link.of`).
pub fn link(
  tables _tables: table_store.Tables,
  quests _quests: QuestLog,
  creature_id _creature_id: Creature2Id,
) -> Result(activate.Link, Nil) {
  panic as "shape: departures.link reads the terminal table and the log's travel objective"
}

/// The landing of a terminal for the player's log, while the faction's travel
/// objective is open: the WorldLocation2 row's place (`start_place.place_of_row`).
pub fn landing(
  tables _tables: table_store.Tables,
  quests _quests: QuestLog,
  creature_id _creature_id: Creature2Id,
) -> Result(Place, Refusal) {
  panic as "shape: departures.landing reads the terminal table, the log and the landing's row"
}

/// The terminal a choice objective belongs to, by the objective's QuestObjective id;
/// `None` for an objective that is not a terminal's choice, which any unit of its
/// group counts (`objective.counts`).
pub fn choice_terminal(objective_id _objective_id: Int) -> Option(Creature2Id) {
  panic as "shape: departures.choice_terminal reads the terminal table"
}

/// The load's check that each terminal's Creature2, its quest's objectives (the
/// choice objective of type 23) and its landing's WorldLocation2 row are in the
/// client's tables, so a client without one fails the server's start.
pub fn requirement() -> table_store.Requirement {
  panic as "shape: departures.requirement lists the terminal table's missing rows"
}
