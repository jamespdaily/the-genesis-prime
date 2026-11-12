//// The departures terminals at the end of the training simulation, and where each lands
//// the player: the rule behind "Bon Voyage" (Quest2 10528, Exile; 10530, Dominion).
////
//// ```
//// 0x97 ─▶ the terminal's prerequisite (`objective_link.of`) ─ closed ─▶ 0x7fc, no 0x7fd
////                                                           └ open ───▶ 0x7fd ─▶ yes ─▶ the cast's Activated(unit, creature)
//// Activated ─▶ landing ─ Ok(place) ─▶ objective.Used counts what is open
////                                      ─▶ Entered.departing = Some(place), 0 ms `timer`
//// timer ─▶ connection/departures.due ─▶ leave the tutorial map, join the landing's
//// world entry ─▶ recovered ─▶ a login between the count and the move enters at the landing
//// ```
////
//// - **The terminals** (`terminals`): each terminal's Creature2, the faction's quest and
////   travel objective, its own choice objective and its landing's WorldLocation2 row.
////   Each Exile choice objective's `worldLocationsIdIndicator00` names a WorldLocation2
////   row in world 3460 (21328 names 51696, 21329 names 51695), and the world data's
////   spawns of the Exile terminals stand within 0.6 of those rows (73606 of 51696, 73605
////   of 51695, source: the world database). The Dominion pair's indicators (21349 names
////   52748, 21350 names 52747) have no spawn to compare, so their match to Levian Bay and
////   Crimson Isle rests on the objectives' texts ("fairly sure"). No client column ties a
////   terminal to its landing: that match is the texts too.
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
////   it. Crimson Isle lands at 8223, as `start_place` does.
//// - **The client's gate** (`Creature2.prerequisiteIdAnimState`): each Exile terminal has
////   the prerequisite 41793 and each Dominion terminal 42982, flags 1 (any of): the faction's
////   quest has its objective 1 open, or is in state 2 or 3
////   (`departures.no_client_gate`). The server offers the terminal exactly when the
////   client does (`objective_link.of`), so a player without the quest or with the talk not
////   done is refused with 0x7fc before 0x7fd, and a press with the travel done and the quest
////   achieved or completed is offered. `landing` gives the landing in those same cases, so
////   that yes moves the player again, and counts only what is still open.
//// - **The count** (`QuestObjective.type.23`): the client counts a use of any unit in the
////   objective's TargetGroup with no mask, and the three objectives of a faction share one
////   group, so `choice_terminal` ties each choice objective to its terminal for
////   `objective.counts`.
//// - **The move** is an in-world 0xad and the usual burst (`0x1403b6de0.resets`) with the
////   quest log kept (`quest_log.process_wide`), which the Holocrypt's leave and join do
////   (`connection/departures`).
//// - **The recovery** (`recovered`): a save between the count and the move holds the
////   counted choice and a place in the tutorial, and the next login enters at the
////   choice's landing, so no failure between them strands the player at a terminal whose
////   travel is done.
////
//// Failure table:
////
//// | What goes wrong | What happens | Where |
//// |---|---|---|
//// | A press without the quest, or with the talk not done | 0x7fc TargetIsNotUseable before 0x7fd; no window, nothing counted, no move | `objective_link.of`, `cast.activation_pressed` |
//// | A press on a terminal of the other faction | Closed link, as above | `objective_link.of` |
//// | A press, or a second yes, with the travel done (quest state 2 or 3) | Offered, as the client offers it; the yes moves the player to the landing and counts nothing | `landing` |
//// | No, or the timeout | 0x7f9 146 and 0x7fe; nothing counted, no move | `cast.answered` |
//// | A yes for a cast that is not live | Debug log; nothing counted, no move | `cast.answered` |
//// | The quest is abandoned while the window is open, then yes | The cast goes and finishes; nothing counted, no move | `landing` refuses at `Activated` |
//// | The terminal has left the player's picture by the go | Nothing counted, no move; the player may press again | `connection/casting.cast_effects` `Activated` branch |
//// | The timer fires once the player is no longer in the world (camp, end) or is dead | Nothing | `connection/departures.due` |
//// | The timer fires while the connection holds the player but is not in the world (an ask is out, the claim of the account waits) | The timer is started again, and the leave begins once the player is in the world | `connection/departures.due` |
//// | The player logs out between the count and the timer | The camp's save holds the counted choice and the tutorial place; the next login enters at the landing | `recovered`, `world_entry.loaded` |
//// | The client disconnects between the count and the timer | The disconnect's save holds the same; the next login enters at the landing | `recovered`, `world_entry.loaded` |
//// | The player dies between the count and the timer | The death's save holds the same; the next login enters at the landing | `recovered`, `world_entry.loaded` |
//// | The server stops gracefully between the count and the timer | Each connection's final save holds the same; the next login enters at the landing | `recovered`, `world_entry.loaded` |
//// | The server stops between the count and the next save | The save before the count holds the log without it: the player logs in in the tutorial with the travel open and presses again | the save timer |
//// | A saved log with a choice counted, saved in the tutorial after a failed move | The login enters at the landing | `recovered` |
//// | A saved log with a choice counted, saved outside the tutorial | The login enters at the saved place | `recovered` |
//// | The old map gives no answer to the leave | The connection ends (LostUserServer) | `connection/world.leave_answered` |
//// | The landing map refuses the join | 0x594, then character select, and a warning is logged; nothing is saved, so the next login enters the tutorial with the travel open, or at the landing after a save of the counted choice, and is refused the same way | `connection/world.entry_answered` with `FromInWorld`, `world_entry.joined` |
//// | The landing map gives no answer to the join | The connection ends (LostUserServer) | `connection/world.entry_answered` |
//// | Client frames during the leave and the join | They wait, as for the Holocrypt | `connection/world` |
//// | The old stay's news after the leave | Dropped by the stay check | `genesis_prime/world_map/stay` |
//// | A 0x637 the client sent before the 0xad reached it | Dropped until the first 0xf2; the map is told nothing | `connection/movement`, `InWorldLoading` |
//// | The client lacks a terminal's Creature2, QuestObjective, Quest2 or WorldLocation2 row | The table load fails at start | `requirements` |

import genesis_prime/game/quest_log.{type Quest, type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group
import genesis_prime/game/tutorial
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  type Creature2Id, Creature2Id, Faction2Id, QuestObjectiveId, WorldLocation2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import gleam/bool
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// One departures terminal: its Creature2, the faction's quest and travel objective
/// (a QuestObjective id), its own choice objective and the WorldLocation2 row it
/// lands the player at.
type Terminal {
  Terminal(
    creature_id: Int,
    quest_id: Int,
    travel_objective_id: Int,
    choice_objective_id: Int,
    landing_location_id: Int,
  )
}

/// The four terminals (the table above).
const terminals: List(Terminal) = [
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
  /// The client does not offer the terminal: the quest is not held, or its talk is not
  /// done.
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

/// The states of a quest in the client's log that the terminal's prerequisite tests with
/// its type 6 conditions (`quest_log.state`): achieved and completed.
const achieved = 2

const completed = 3

/// The QuestObjective type of a use of a unit of a TargetGroup, which the travel and the
/// choice objectives are (`QuestObjective.type.23`).
const use_a_group_type = 23

/// The terminal of a creature.
fn terminal_of(creature_id creature_id: Creature2Id) -> Result(Terminal, Nil) {
  list.find(terminals, fn(terminal) {
    terminal.creature_id == creature_id.value
  })
}

/// The quest the terminal's faction holds, read from the tables the load checked
/// (`requirements`).
fn quest_of(
  tables tables: table_store.Tables,
  terminal terminal: Terminal,
) -> Quest {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: terminal.quest_id)
    as "the load checked the terminal's quest and its objectives"
  quest
}

/// The slot of the objective in the quest.
fn index_of(
  quest quest: Quest,
  objective_id objective_id: Int,
) -> Result(Int, Nil) {
  list.index_map(quest.objectives, fn(objective, index) { #(index, objective) })
  |> list.find(fn(slot) { { slot.1 }.objective_id == objective_id })
  |> result.map(fn(slot) { slot.0 })
}

/// The slot of an objective the load checked is one of the terminal's quest.
fn checked_index_of(quest quest: Quest, objective_id objective_id: Int) -> Int {
  let assert Ok(index) = index_of(quest:, objective_id:)
    as "the load checked that the quest holds the terminal's objectives"
  index
}

/// Whether the terminal's travel objective is open in the log: the quest is in the
/// active list, the travel is not done and its talk is (`quest_log.objective_open`).
fn travel_open(
  tables tables: table_store.Tables,
  quests quests: QuestLog,
  terminal terminal: Terminal,
) -> Bool {
  let quest = quest_of(tables:, terminal:)
  quest_log.objective_open(
    log: quests,
    quest:,
    index: checked_index_of(quest:, objective_id: terminal.travel_objective_id),
  )
}

/// Whether the terminal's choice objective is done in a quest the log holds in its
/// active list.
fn choice_done(
  tables tables: table_store.Tables,
  quests quests: QuestLog,
  terminal terminal: Terminal,
) -> Bool {
  let quest = quest_of(tables:, terminal:)
  list.contains(quest_log.active_ids(log: quests), terminal.quest_id)
  && quest_log.objective_done(
    log: quests,
    quest:,
    index: checked_index_of(quest:, objective_id: terminal.choice_objective_id),
  )
}

/// The place of the terminal's landing row.
fn landing_row(
  tables tables: table_store.Tables,
  terminal terminal: Terminal,
) -> Result(Place, Nil) {
  use row <- result.try(world_location2.get(
    tables:,
    id: WorldLocation2Id(terminal.landing_location_id),
  ))
  start_place.of_row(row:)
}

/// The place of the terminal's landing row, which the load checked.
fn place_of(
  tables tables: table_store.Tables,
  terminal terminal: Terminal,
) -> Place {
  let assert Ok(place) = landing_row(tables:, terminal:)
    as "the load checked the terminal's landing row"
  place
}

/// The landing of a terminal for the player's log, when the client offers the terminal
/// (`Prerequisite` 41793 and 42982): the faction's travel objective is open, or its quest
/// is achieved (state 2) or completed (state 3). The WorldLocation2 row's place.
pub fn landing(
  tables tables: table_store.Tables,
  quests quests: QuestLog,
  creature_id creature_id: Creature2Id,
) -> Result(Place, Refusal) {
  use terminal <- result.try(
    terminal_of(creature_id:) |> result.replace_error(NotATerminal),
  )
  let quest_state =
    quest_log.state(log: quests, quest: quest_of(tables:, terminal:))
  case
    travel_open(tables:, quests:, terminal:)
    || quest_state == achieved
    || quest_state == completed
  {
    True -> Ok(place_of(tables:, terminal:))
    False -> Error(TravelClosed)
  }
}

/// The terminal a choice objective belongs to, by the objective's QuestObjective id (its
/// `worldLocationsIdIndicator00` row, in world 3460, is the terminal's place; see the
/// module doc); `None` for an objective that is not a terminal's choice, which any unit
/// of its group counts (`objective.counts`).
pub fn choice_terminal(objective_id objective_id: Int) -> Option(Creature2Id) {
  list.find(terminals, fn(terminal) {
    terminal.choice_objective_id == objective_id
  })
  |> result.map(fn(terminal) { Creature2Id(terminal.creature_id) })
  |> option.from_result
}

/// The place a character enters the world at, given the place it was saved at and its
/// saved quest log: the landing of the terminal whose choice objective the log holds done
/// while the saved place is still in the training simulation (a save between the count
/// and the move), the saved place otherwise.
pub fn recovered(
  tables tables: table_store.Tables,
  quests quests: QuestLog,
  place place: Place,
) -> Place {
  use <- bool.guard(
    when: start_place.world_id(place) != tutorial.training_world,
    return: place,
  )
  case
    list.find(terminals, fn(terminal) {
      choice_done(tables:, quests:, terminal:)
    })
  {
    Ok(terminal) -> place_of(tables:, terminal:)
    Error(Nil) -> place
  }
}

const from_table = "the server's departures terminals"

/// Whether the objective of the pair is a use of a TargetGroup (type 23) whose group holds
/// the pair's terminal, so a use of the terminal counts it (`objective.counts`).
fn counts_its_terminal(
  tables tables: table_store.Tables,
  pair pair: #(Int, Terminal),
) -> Bool {
  let #(objective_id, terminal) = pair
  case
    quest_objective.get(tables:, id: QuestObjectiveId(objective_id)),
    creature2.get(tables:, id: Creature2Id(terminal.creature_id))
  {
    Ok(objective), Ok(creature) ->
      objective.type_ == use_a_group_type
      && target_group.contains(
        tables:,
        group: objective.data,
        unit: target_group.Unit(
          creature_id: Creature2Id(terminal.creature_id),
          faction_id: Faction2Id(creature.faction_id),
          unit_race_id: creature2.unit_race_id(creature),
        ),
      )
    _, _ -> False
  }
}

/// The load's checks that each terminal's Creature2, its travel and choice objectives
/// (QuestObjective rows of type 23 whose TargetGroup holds the terminal), its quest with
/// those objectives in its slots and its landing's WorldLocation2 row (in a world) are in
/// the client's tables, so a client without one fails the server's start.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table:,
      column: "Creature2 id",
      to_table: "Creature2",
      missing: fn(tables) {
        list.map(terminals, fn(terminal) { terminal.creature_id })
        |> list.filter(fn(creature_id) {
          result.is_error(creature2.get(tables:, id: Creature2Id(creature_id)))
        })
      },
    ),
    table_store.Requirement(
      from_table:,
      column: "QuestObjective id",
      to_table: "QuestObjective",
      missing: fn(tables) {
        list.flat_map(terminals, fn(terminal) {
          [
            #(terminal.travel_objective_id, terminal),
            #(terminal.choice_objective_id, terminal),
          ]
        })
        |> list.filter(fn(pair) { !counts_its_terminal(tables:, pair:) })
        |> list.map(fn(pair) { pair.0 })
        |> list.unique
      },
    ),
    table_store.Requirement(
      from_table:,
      column: "Quest2 id",
      to_table: "Quest2",
      missing: fn(tables) {
        list.filter(terminals, fn(terminal) {
          quest_log.quest_of(tables:, id: terminal.quest_id)
          |> result.map(fn(quest) {
            result.is_error(index_of(
              quest:,
              objective_id: terminal.travel_objective_id,
            ))
            || result.is_error(index_of(
              quest:,
              objective_id: terminal.choice_objective_id,
            ))
          })
          |> result.unwrap(True)
        })
        |> list.map(fn(terminal) { terminal.quest_id })
        |> list.unique
      },
    ),
    table_store.Requirement(
      from_table:,
      column: "WorldLocation2 id",
      to_table: "WorldLocation2",
      missing: fn(tables) {
        list.filter(terminals, fn(terminal) {
          result.is_error(landing_row(tables:, terminal:))
        })
        |> list.map(fn(terminal) { terminal.landing_location_id })
      },
    ),
  ]
}
