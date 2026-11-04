//// The level an amount of experience is, as the client works it out:
//// GetLevelForExperience 0x140029820 (fact `0x140029820`) over the client's
//// XpPerLevel table. A character made from a CharacterCreation row starts with
//// the row's experience (fact `CharacterCreation.xp`), so its level is this
//// function's answer for that amount.

import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId, XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// The GameFormula row whose dataint0 is the highest level (0x14002983e, the
/// id 0x91).
const highest_level_formula = 145

/// The level an amount of experience is: the highest XpPerLevel ID from 1 to
/// the highest level (GameFormula row 145's dataint0) whose minXpForLevel is
/// at most the amount. The client takes the XpPerLevel records by position, from
/// record 0 to the record at the highest level, and gives no level, which this
/// gives as `Error(Nil)`, for an amount below record 0's minXpForLevel or above
/// the last record's, and when the row or a record is missing (the table load
/// requires them, `requirements`).
pub fn for_experience(
  tables tables: table_store.Tables,
  experience experience: Int,
) -> Result(Int, Nil) {
  use highest <- result.try(highest_level(tables))
  let records = list.take(xp_per_level.all(tables), highest + 1)
  use last <- result.try(list.last(records))
  use <- bool.guard(experience > last.min_xp_for_level, Error(Nil))
  list.take_while(records, fn(record) { record.min_xp_for_level <= experience })
  |> list.last
  |> result.map(fn(record) { int.min(record.id, highest) })
}

/// The highest level, from GameFormula row 145's dataint0.
pub fn highest_level(tables: table_store.Tables) -> Result(Int, Nil) {
  game_formula.get(tables:, id: GameFormulaId(highest_level_formula))
  |> result.map(fn(row) { row.dataint0 })
}

/// The load's checks that the rows `for_experience` reads exist, so a client
/// without them fails the server's start: GameFormula row 145, and the XpPerLevel
/// record at the highest level and every record before it. A record is named by
/// its position plus one, which is its ID in the client's data.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "the server's starting level",
      column: "GameFormula id",
      to_table: "GameFormula",
      missing: fn(tables) {
        case highest_level(tables) {
          Ok(_) -> []
          Error(Nil) -> [highest_level_formula]
        }
      },
    ),
    table_store.Requirement(
      from_table: "the server's starting level",
      column: "XpPerLevel record number",
      to_table: "XpPerLevel",
      missing: fn(tables) {
        case highest_level(tables) {
          Error(Nil) -> []
          Ok(highest) ->
            int.range(from: 1, to: highest + 2, with: [], run: fn(missing, id) {
              case xp_per_level.get(tables:, id: XpPerLevelId(id)) {
                Ok(_) -> missing
                Error(Nil) -> [id, ..missing]
              }
            })
            |> list.reverse
        }
      },
    ),
  ]
}
