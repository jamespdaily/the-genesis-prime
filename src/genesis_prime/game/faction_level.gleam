//// A faction's level toward another, 0 to 10, as the client works it out
//// (GetFactionLevelTo `0x140787760`), and whether that level is Hostile
//// (FactionDispositionFromLevel `0x140787830`: 0 to 2 Hostile, 3 to 7 Neutral, 8 to
//// 10 Friendly).
////
//// ```
//// Faction2 and Faction2Relationship ─▶ build ─▶ Levels(parents, levels)
//// Levels, a faction, another         ─▶ level / hostile
//// ```
////
//// - **The lineage** of a faction is the faction and its parents, nearest first
////   (`0x140717560`). A faction with no parent, a parent that is 0 and a parent
////   already met end it, so a cycle cannot loop.
//// - **The level** is the first relationship found, for the other faction and then each
////   of its parents, between it and this faction or, failing that, any of this
////   faction's parents in turn; with none, 10 when the other is this faction and 5
////   otherwise. A relationship is filed under both orders, as the client files it.
//// - **Built once**, when the tables load (genesis_prime/table/loader/derivation), for the
////   rules that read a faction's level per request (genesis_prime/game/communicator);
////   `build` is the same walk's input for a reader that has the tables and no load
////   (genesis_prime/world_map/spawn).

import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// Each faction's parent and the level of each pair of factions that has a relationship.
pub opaque type Levels {
  Levels(parents: Dict(Int, Int), levels: Dict(#(Int, Int), Int))
}

/// The highest level the client calls Hostile (FactionDispositionFromLevel `0x140787830`,
/// `world_data.creature_disposition`).
const highest_hostile_level = 2

/// The key of the levels in the tables' store.
const levels_key: table_store.DerivedKey(Levels) =
  table_store.DerivedKey("FactionLevels")

/// The levels as a value the tables' load builds once, under the tables' key.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: levels_key, build: fn(tables) {
    Ok(build(tables:))
  })
}

/// The levels the load built, for rules that ask per request.
pub fn of(tables tables: table_store.Tables) -> Levels {
  table_store.derived(tables:, key: levels_key)
}

/// The levels worked out from the Faction2 and Faction2Relationship rows of the tables.
pub fn build(tables tables: table_store.Tables) -> Levels {
  Levels(
    parents: list.fold(faction2.all(tables), dict.new(), fn(found, faction) {
      dict.insert(found, faction.id, faction.faction2_id_parent)
    }),
    levels: list.fold(
      faction2_relationship.all(tables),
      dict.new(),
      fn(found, relationship) {
        found
        |> dict.insert(
          #(relationship.faction_id0, relationship.faction_id1),
          relationship.faction_level,
        )
        |> dict.insert(
          #(relationship.faction_id1, relationship.faction_id0),
          relationship.faction_level,
        )
      },
    ),
  )
}

/// A faction and its parents, nearest first: the chain the client walks.
fn lineage(levels levels: Levels, faction faction: Int) -> List(Int) {
  lineage_loop(levels:, faction:, met: [])
}

fn lineage_loop(
  levels levels: Levels,
  faction faction: Int,
  met met: List(Int),
) -> List(Int) {
  case faction == 0 || list.contains(met, faction) {
    True -> list.reverse(met)
    False ->
      lineage_loop(
        levels:,
        faction: dict.get(levels.parents, faction) |> result.unwrap(0),
        met: [faction, ..met],
      )
  }
}

/// A faction's level, 0 to 10, toward another (GetFactionLevelTo `0x140787760`, the
/// reputation a player's faction may carry aside): for the other faction and then each
/// of its parents, the first relationship it has with this faction or, failing that,
/// with any of this faction's parents in turn; with none, 10 when the other is this
/// faction and 5 otherwise.
pub fn level(levels levels: Levels, from this: Int, to other: Int) -> Int {
  let own = lineage(levels:, faction: this)
  let found =
    list.find_map(lineage(levels:, faction: other), fn(candidate) {
      list.find_map(own, fn(relative) {
        dict.get(levels.levels, #(relative, candidate))
      })
    })
  case found {
    Ok(level) -> level
    Error(Nil) ->
      case this == other {
        True -> 10
        False -> 5
      }
  }
}

/// Whether a faction is Hostile toward another: its level is 0 to 2.
pub fn hostile(levels levels: Levels, from this: Int, to other: Int) -> Bool {
  level(levels:, from: this, to: other) <= highest_hostile_level
}
