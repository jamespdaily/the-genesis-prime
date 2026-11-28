//// The map's check of a player's faction (`genesis_prime/world_map/map`
//// `hostile_to_player_faction`) answers as `shown.faction_of` did for every Faction2
//// row of the client's tables: Dominion is 166 and Exile 167 (`spawn.dominion_faction`,
//// `spawn.exile_faction`, `world_data.creature_disposition`), and a faction of neither
//// is no player faction, so no creature is hostile to it.

import client_tables
import genesis_prime/game/shown
import genesis_prime/table/faction2
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

pub fn the_map_checks_a_faction_as_shown_did_for_every_faction_id_of_the_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let row_ids =
    faction2.all(client_tables.shared())
    |> list.map(fn(row) { row.id })
  let past_every_row = list.fold(row_ids, 0, int.max) + 1
  let ids =
    list.flatten([
      row_ids,
      [spawn.exile_faction, spawn.dominion_faction, past_every_row],
    ])
  let hostilities = [
    Hostile(exile: False, dominion: False),
    Hostile(exile: True, dominion: False),
    Hostile(exile: False, dominion: True),
    Hostile(exile: True, dominion: True),
  ]
  list.each(ids, fn(faction_id) {
    list.each(hostilities, fn(hostile_to) {
      let expected = case shown.faction_of(faction_id:) {
        Ok(shown.Exile) -> hostile_to.exile
        Ok(shown.Dominion) -> hostile_to.dominion
        Error(Nil) -> False
      }
      assert map.hostile_to_player_faction(hostile_to:, faction_id:) == expected
        as {
          "faction "
          <> int.to_string(faction_id)
          <> " with "
          <> string.inspect(hostile_to)
        }
    })
  })
  assert list.contains(row_ids, spawn.exile_faction)
    && list.contains(row_ids, spawn.dominion_faction)
    as "the two player factions are rows of the table"
}
