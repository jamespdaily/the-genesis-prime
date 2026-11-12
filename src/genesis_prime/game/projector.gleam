//// The training simulation's four projectors and where each puts the player: the rule behind
//// "continue to the Combat Simulation", the Housing, Mission and Cryo projectors, and the
//// rows of the `projector_landing` content table the load refuses. The client's projector
//// spell moves no one (`Spell4Effects.87061`, `WorldLocation2.npe_zone_arrivals`) and no
//// client column ties a projector to a place, so the landing is the server's choice, kept
//// in the table with the objective that asks for the projector.
////
//// ```
//// content.load: rows ─▶ select(rows, tables) ─▶ Landings | refusals (the load stops)
//// the cast's go ─▶ landing(landings, creature, faction, link) ─ Ok(place) ─▶ connection/projector
////                                                           └ Error ──────▶ no move
////
//// Combat 73735 ─▶ 51615 Warfare Woods (5967)      Housing 73741 ─▶ 51617 Skyplot (5969)
//// Mission 73743 ─▶ 51616 Solitude of Secrets (5968)
//// Cryo 73745 ─▶ 51658 Exile Docking Bay (5998) | 51657 Dominion Docking Bay (5999)
//// ```
////
//// - **The row** is the creature, the faction enum (Quest2 `questPlayerFactionEnum`: 0
////   Exile, 1 Dominion), the objective that asks for the use and the WorldLocation2 row of
////   the landing. The objective ties the landing to the client's own text: a type 12 (use)
////   of the creature, or a type 17 (zone) of a zone the landing lies in or under.
//// - **The gate is the projector's own prerequisite** (`objective_link.of`), as for every
////   creature with an activation: only an open link moves the player. The same link is
////   read at the press and again at the go. No tutorial quest can be abandoned in between
////   (Quest2.flags 0x4000 on each, `CanAbandonQuest`).
//// - **The count** is the objective rule's (`objective.Used`), which counts the open
////   use or zone objective; the move runs in the same rule step, after it.
////
//// Failure table:
////
//// | What goes wrong | What happens | Where |
//// |---|---|---|
//// | A row names no Creature2 row, or a creature that does not cast Spell4 87061 | The load stops, naming the row | `select` |
//// | A row's landing has no WorldLocation2 row, or lies outside World 3460 | The load stops, naming the row | `select` |
//// | A row's objective has no row, is not a use of the creature or a zone the landing lies in or under | The load stops, naming the row | `select` |
//// | A row's objective is in no quest, or in a quest of the other faction | The load stops, naming the row | `select` |
//// | A creature that is not a projector | No landing, no move | `landing` |
//// | The link is closed, unread or absent (the quest is not held, or its objective is not open) | No landing, no move | `landing` |
//// | The link is closed at the go | No landing, no move | `landing` |
//// | A character of neither faction | Crash | `landing` |

import genesis_prime/content/refusal
import genesis_prime/game/activate.{type Link, OpenLink}
import genesis_prime/game/quest_log
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/tutorial
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  type Creature2Id, Creature2Id, QuestObjectiveId, WorldLocation2Id, WorldZoneId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// The table's name in the log and in a refusal.
pub const table = "projector_landing"

/// The spell every projector casts when used (Spell4 87061, `Spell4Effects.87061`).
const projector_spell = 87_061

/// The QuestObjective type of a use of one creature (`QuestObjective.type.12`).
const use_a_creature_type = 12

/// The QuestObjective type of reaching a zone (`QuestObjective.type.17`).
const reach_a_zone_type = 17

/// One row of the projector_landing table as the load reads it.
pub type Row {
  Row(
    creature_id: Int,
    faction_enum: Int,
    objective_id: Int,
    world_location2_id: Int,
  )
}

/// The landing of each projector for each faction enum.
pub opaque type Landings {
  Landings(by_projector: Dict(#(Int, Int), Place))
}

/// Why a creature does not take the player.
pub type Refusal {
  /// The creature is not one of the projectors.
  NotAProjector
  /// The client does not offer the projector: the quest is not held, or the objective
  /// that asks for it is not open.
  NotOffered(link: Link)
}

/// The landings the rows make, or every row the load refuses.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Landings, List(refusal.Refusal)) {
  let #(landings, refusals) =
    list.fold(rows, #([], []), fn(done, row) {
      case row_refusal(row:, tables:) {
        Ok(place) -> #(
          [#(#(row.creature_id, row.faction_enum), place), ..done.0],
          done.1,
        )
        Error(broken) -> #(done.0, [
          refusal.Refusal(
            table:,
            row: refusal.RowId(row.objective_id),
            rule: string.join(broken, "; "),
          ),
          ..done.1
        ])
      }
    })
  case refusals {
    [_, ..] -> Error(list.reverse(refusals))
    [] -> Ok(Landings(by_projector: dict.from_list(landings)))
  }
}

/// The place of a row the load accepts, or the rules it breaks.
fn row_refusal(
  row row: Row,
  tables tables: table_store.Tables,
) -> Result(Place, List(String)) {
  let creature = creature_broken(row:, tables:)
  case landing_of(row:, tables:) {
    Error(broken) -> Error(list.append(creature, broken))
    Ok(#(place, row_world_zone_id)) ->
      case
        list.flatten([
          creature,
          objective_broken(row:, tables:, world_zone_id: row_world_zone_id),
        ])
      {
        [] -> Ok(place)
        broken -> Error(broken)
      }
  }
}

/// The rules the row's creature breaks: it has a Creature2 row that casts the projector
/// spell when used.
fn creature_broken(
  row row: Row,
  tables tables: table_store.Tables,
) -> List(String) {
  case creature2.get(tables:, id: Creature2Id(row.creature_id)) {
    Error(Nil) -> [
      "the client's Creature2 table has no row "
      <> int.to_string(row.creature_id),
    ]
    Ok(creature) ->
      case creature.spell4_id_activate00 == projector_spell {
        True -> []
        False -> [
          "Creature2 "
          <> int.to_string(row.creature_id)
          <> " casts Spell4 "
          <> int.to_string(creature.spell4_id_activate00)
          <> " when used, not the projector spell "
          <> int.to_string(projector_spell),
        ]
      }
  }
}

/// The row's landing: its place and zone, or why it is none: a WorldLocation2 row of
/// the training world.
fn landing_of(
  row row: Row,
  tables tables: table_store.Tables,
) -> Result(#(Place, Int), List(String)) {
  let location = int.to_string(row.world_location2_id)
  use location_row <- result.try(
    world_location2.get(tables:, id: WorldLocation2Id(row.world_location2_id))
    |> result.replace_error([
      "the client's WorldLocation2 table has no row " <> location,
    ]),
  )
  case location_row.world_id == tutorial.training_world {
    False ->
      Error([
        "WorldLocation2 "
        <> location
        <> " is in world "
        <> int.to_string(location_row.world_id)
        <> ", not the training world "
        <> int.to_string(tutorial.training_world),
      ])
    True ->
      start_place.of_row(row: location_row)
      |> result.map(fn(place) { #(place, location_row.world_zone_id) })
      |> result.replace_error([
        "WorldLocation2 " <> location <> " has no place the server can use",
      ])
  }
}

/// The rules the row's objective breaks: it has a row, asks for the use of the creature
/// or for a zone the landing lies in or under, and belongs to a quest of the row's faction.
fn objective_broken(
  row row: Row,
  tables tables: table_store.Tables,
  world_zone_id world_zone_id: Int,
) -> List(String) {
  let objective_text = "QuestObjective " <> int.to_string(row.objective_id)
  case quest_objective.get(tables:, id: QuestObjectiveId(row.objective_id)) {
    Error(Nil) -> [
      "the client's QuestObjective table has no row "
      <> int.to_string(row.objective_id),
    ]
    Ok(objective) ->
      list.flatten([
        case objective.type_ {
          type_ if type_ == use_a_creature_type ->
            case objective.data == row.creature_id {
              True -> []
              False -> [
                objective_text
                <> " is a use of Creature2 "
                <> int.to_string(objective.data)
                <> ", not of "
                <> int.to_string(row.creature_id),
              ]
            }
          type_ if type_ == reach_a_zone_type ->
            case
              list.contains(
                zone_and_parents(tables:, world_zone_id:),
                objective.data,
              )
            {
              True -> []
              False -> [
                objective_text
                <> " reaches zone "
                <> int.to_string(objective.data)
                <> ", which the landing's zone "
                <> int.to_string(world_zone_id)
                <> " is not in",
              ]
            }
          type_ -> [
            objective_text
            <> " is of type "
            <> int.to_string(type_)
            <> ", neither a use of a creature (12) nor reaching a zone (17)",
          ]
        },
        faction_broken(row:, tables:, objective_text:),
      ])
  }
}

/// The rule broken when the quest that holds the objective is not of the row's faction,
/// or when none holds it.
fn faction_broken(
  row row: Row,
  tables tables: table_store.Tables,
  objective_text objective_text: String,
) -> List(String) {
  let holder =
    list.find(quest2.all(tables), fn(quest_row) {
      quest_log.quest_of(tables:, id: quest_row.id)
      |> result.map(fn(quest) {
        list.any(quest.objectives, fn(objective) {
          objective.objective_id == row.objective_id
        })
      })
      |> result.unwrap(False)
    })
  case holder {
    Error(Nil) -> [objective_text <> " is in no quest the client's tables hold"]
    Ok(quest_row) ->
      case quest_row.quest_player_faction_enum == row.faction_enum {
        True -> []
        False -> [
          objective_text
          <> " is in Quest2 "
          <> int.to_string(quest_row.id)
          <> " of faction enum "
          <> int.to_string(quest_row.quest_player_faction_enum)
          <> ", not "
          <> int.to_string(row.faction_enum),
        ]
      }
  }
}

/// The zone and each zone above it (WorldZone `parentZoneId`), from the zone up.
fn zone_and_parents(
  tables tables: table_store.Tables,
  world_zone_id world_zone_id: Int,
) -> List(Int) {
  walk_up(tables:, zone_id: world_zone_id, seen: set.new(), chain: [])
}

fn walk_up(
  tables tables: table_store.Tables,
  zone_id zone_id: Int,
  seen seen: set.Set(Int),
  chain chain: List(Int),
) -> List(Int) {
  use <- bool.guard(
    when: zone_id == 0 || set.contains(seen, zone_id),
    return: chain,
  )
  case world_zone.get(tables:, id: WorldZoneId(zone_id)) {
    Error(Nil) -> [zone_id, ..chain]
    Ok(zone) ->
      walk_up(
        tables:,
        zone_id: zone.parent_zone_id,
        seen: set.insert(seen, zone_id),
        chain: [zone_id, ..chain],
      )
  }
}

/// The place the projector `creature_id` puts a player of the Faction2 `faction_id` at,
/// when the client offers the projector (`link` is open).
pub fn landing(
  landings landings: Landings,
  creature_id creature_id: Creature2Id,
  faction_id faction_id: Int,
  link link: Link,
) -> Result(Place, Refusal) {
  let assert Ok(faction) = shown.faction_of(faction_id:)
    as "a character is an Exile or a Dominion"
  let faction_enum = case faction {
    shown.Exile -> 0
    shown.Dominion -> 1
  }
  use place <- result.try(
    dict.get(landings.by_projector, #(creature_id.value, faction_enum))
    |> result.replace_error(NotAProjector),
  )
  case link {
    OpenLink -> Ok(place)
    activate.NoLink | activate.ClosedLink | activate.UnreadLink(..) ->
      Error(NotOffered(link:))
  }
}
