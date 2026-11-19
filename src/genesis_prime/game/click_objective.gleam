//// The visible scripted objectives that ask only to click a creature: the rows of the
//// `click_objective` content table the load checks. A QuestObjective of type 5 is done only
//// by the server's 0x361 (`QuestObjective.type.5`), and the client counts a unit of the
//// objective's reward pane TargetGroup for an objective of any type (`0x140550c50`), so the
//// server counts an activation of a pane creature for a row of this table
//// (`objective.counts`) and the objective's creatures stand at its marker
//// (`objective_spawn.place`). No client table or code says which type 5 objectives ask only
//// for a click: each is a row the table states with its reason.
////
//// ```
//// content.load: ids ─▶ select(ids, tables) ─▶ Set(objective id) | refusals (the load stops)
//// each connection's settings ─▶ the set ─▶ objective.advance(Used) ─▶ a pane activation counts one
//// ```
////
//// - **A row must be a click the server can see done.** The objective is a visible,
////   required script no creature links (`objective.visible_script_broken` is empty in
////   every quest that lists it), it has a marker whose WorldLocation2 row exists, its reward
////   pane lists, for each player faction its quest allows, a creature the client offers a click
////   on (`activate.offers_click`) that is not Hostile to the faction (the client offers a
////   hostile unit no use, `activate.Withheld`) and whose activate spells the server builds and
////   holds no effect no rule reads (`click_built`), and no spell effect or item names it
////   (`objective_action.named`): an objective a cast advances stays open until the cast
////   counts, not when a creature is clicked.
////
//// - **A pane creature's start** is not checked by the load, which has no spawn table;
////   `objective_spawn.place` stands one at the marker where no stored row serves it. A row
////   for a marker in a world with no stored spawn loads, and keeps the quest from
////   completing until the world has one.
////
//// The failure points are those of `objective_row`.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/activate
import genesis_prime/game/effect_kind
import genesis_prime/game/faction_level
import genesis_prime/game/objective
import genesis_prime/game/objective_action
import genesis_prime/game/objective_row
import genesis_prime/game/quest
import genesis_prime/gap
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/spawn
import gleam/dict
import gleam/list
import gleam/set.{type Set}

/// The table's name in the log and in a refusal.
pub const table = "click_objective"

/// The QuestObjective ids the table's rows hold, or every row the load refuses.
pub fn select(
  ids ids: List(Int),
  tables tables: table_store.Tables,
) -> Result(Set(Int), List(Refusal)) {
  objective_row.select(
    table:,
    ids:,
    tables:,
    broken: fn(tables, quest, index, listed_objective) {
      let levels = faction_level.of(tables:)
      list.flatten([
        objective.visible_script_broken(
          tables:,
          quest_id: quest.id,
          index:,
          objective: listed_objective,
        ),
        objective_row.marker_broken(
          tables:,
          objective_id: listed_objective.objective_id,
        ),
        list.flat_map(players_of(tables:, quest_id: quest.id), fn(player) {
          objective_row.pane_broken(
            tables:,
            objective: listed_objective,
            action: "click",
            wanted: clickable(
              tables:,
              levels:,
              player: player.0,
              creature_id: _,
            ),
            missing: "no creature the client offers a click on that is not Hostile to the "
              <> player.1
              <> " faction and whose activate spell the server builds",
          )
        })
          |> list.unique,
        case objective_action.named(tables:, quest_id: quest.id, index:) {
          True -> [
            "a spell effect or an item names it, so a cast advances it, not a click",
          ]
          False -> []
        },
      ])
    },
  )
}

/// The player factions the quest allows, each with its name: 0 Exile, 1 Dominion, 2 either
/// (`quest.allowed_factions`).
fn players_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(#(Int, String)) {
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "a quest an objective is listed in has its Quest2 row"
  list.map(quest.allowed_factions(quest: row), fn(faction) {
    case faction == spawn.exile_faction {
      True -> #(faction, "Exile")
      False -> #(faction, "Dominion")
    }
  })
}

/// Whether the client offers a click on the creature to a player of the faction: its row
/// offers one (`activate.offers_click`), the creature is not Hostile to the faction (the
/// client offers a hostile unit no use, `activate.Withheld`), and the server builds every
/// activate spell its columns name.
fn clickable(
  tables tables: table_store.Tables,
  levels levels: faction_level.Levels,
  player player: Int,
  creature_id creature_id: Int,
) -> Bool {
  case creature2.get(tables, Creature2Id(creature_id)) {
    Ok(row) ->
      activate.offers_click(row:)
      && !faction_level.hostile(levels:, from: player, to: row.faction_id)
      && click_built(tables:, row:)
    Error(Nil) -> False
  }
}

/// Whether the server builds every activate spell the creature's columns name: its plan is
/// built (`activate.Planned`) and no effect row of the spell is of a type no rule reads
/// (`effect_kind.is_read`). The activate cast drops a row of a type no rule reads, so a spell
/// with one does something the server does not, and the click would count while the
/// spell's real effect is lost. The server cannot tell which column the client picks for a
/// player, so each must build.
fn click_built(
  tables tables: table_store.Tables,
  row row: creature2.Creature2,
) -> Bool {
  let activations = activate.activations(tables:)
  activate.creature_of(row:).columns
  |> list.filter(fn(column) { column.spell4_id != 0 })
  |> list.all(fn(column) {
    case dict.get(activations.spells, column.spell4_id) {
      Ok(activate.Planned(..)) ->
        !list.any(spell4_effects.all(tables), fn(effect) {
          effect.spell_id == column.spell4_id
          && !effect_kind.is_read(effect_type: effect.effect_type)
        })
      Ok(activate.NoSpell4Row)
      | Ok(activate.CannotBePlanned(..))
      | Error(Nil) -> False
    }
  })
}

/// What the load of click objectives does not check.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Click objectives",
      missing: "that a pane creature of a click objective starts in its marker's world: the load has no spawn table to check it, so a row for a marker in a world with no stored spawn loads and keeps the quest from completing",
    ),
  ]
}
