//// What the rules of character select and entering the world read beyond
//// their state, made from the loaded game tables, the server's time and the
//// settings of the game server.

import genesis_prime/character/character.{type Place}
import genesis_prime/character/customisation.{type Customisation}
import genesis_prime/character/select
import genesis_prime/character/world_entry
import genesis_prime/game/game_session.{type Context, Context}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/world
import genesis_prime/table/xp_per_level
import gleam/list
import gleam/option.{None}
import gleam/result

/// The GameFormula row whose dataint0 is the highest character level
/// (GetLevelForExperience 0x140029820 reads row 145).
const highest_level_formula = 145

/// The highest level when the table has no such row (0x140029820 starts from
/// 1).
const lowest_highest_level = 1

/// The context for one input. `server_time` is the time as a Windows
/// FILETIME, `realm_id` the realm the connection is on and `start` the place a
/// character made from a CharacterCreation row starts at. The CharacterCreation
/// `customisation` and `character_slots` are made once from the tables. The
/// CharacterCreation table gives the rows, the XpPerLevel and GameFormula tables the level an
/// experience gives and the World table the worlds that exist.
pub fn build(
  tables tables: Tables,
  start start: fn(CharacterCreation) -> Result(Place, Nil),
  customisation customisation: Customisation,
  character_slots character_slots: Int,
  realm_id realm_id: Int,
  server_time server_time: Int,
) -> Context {
  Context(
    select: select.Context(
      creation: fn(id) { character_creation.get(tables, id) },
      start:,
      level_of: fn(experience) { level_of(tables:, experience:) },
      customisation:,
      character_slots:,
      in_world: None,
      server_time:,
      realm_id:,
    ),
    entry: world_entry.Context(realm_id:, world_exists: fn(id) {
      result.is_ok(world.get(tables, id))
    }),
  )
}

/// The level an amount of experience gives, as the client works it
/// (GetLevelForExperience 0x140029820): the XpPerLevel records are taken by
/// position, from record 0 up to the record at the highest level (GameFormula
/// row 145's dataint0); the level is the ID of the last of the records before
/// that one whose minXpForLevel the experience reaches. An experience below
/// record 0's or above the last record's gives no level in the client; every
/// CharacterCreation row of the client's table has a level, so a table that
/// gives none is not the client's and the caller crashes.
fn level_of(tables tables: Tables, experience experience: Int) -> Int {
  let highest = case game_formula.get(tables, highest_level_formula) {
    Ok(row) -> row.dataint0
    Error(Nil) -> lowest_highest_level
  }
  let records = list.take(xp_per_level.all(tables), highest + 1)
  let assert [first, ..] = records
    as "the XpPerLevel table holds the record of the lowest level"
  let assert Ok(last) = list.last(records)
    as "the XpPerLevel table holds a record at the highest level"
  assert experience >= first.min_xp_for_level
    && experience <= last.min_xp_for_level
    as "the experience gives a level in the client's table"
  let assert Ok(reached) =
    list.take(records, highest)
    |> list.filter(fn(record) { record.min_xp_for_level <= experience })
    |> list.last
    as "the first record is reached by any experience the table gives a level"
  reached.id
}
