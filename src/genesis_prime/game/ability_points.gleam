//// The ability points a character has, and the 0x0169 that tells the client: the points to
//// spend and the total the player can hold (`opcode.0x169`). The spellbook window shows both
//// and enables a tier button while the points to spend are above 0; the interface menu's
//// Abilities button alerts while they are (`lua.Abilities.UpdateInterfaceMenuAlerts`).
////
//// ```
//// world entry   ─▶ frame(tables, level, spent)           after 0x092C, before 0x025E
//// level rise    ─▶ after_rise(tables, from, to, spent)   after the 0x0938 of the new level
////                    [] when the total is the same, else the one frame of the new level
//// a save        ─▶ points_frame(total, spent)            after the 0x01A0 of the held tiers
//// ```
////
//// - **The total of a level** is the sum of `XpPerLevel.abilityPointsPerLevel` over the rows
////   with ID 1 to the level: 0 up to level 9, one more per level from 10, 41 at 50. The
////   client never adds the column up; this sum is the server's.
//// - **The points to spend** are the total less the points the held tiers cost
////   (genesis_prime/game/spell_tier `spent`, over the tiers the builder's Save (0x00B1) bought:
////   genesis_prime/game/limited_action_set). A tier button enables on the points to spend, and
////   the Abilities button alerts while they are above 0.
//// - **The tiers last** until the next map change, Holocrypt rejoin, camp or login, which
////   starts every ability at tier 1 and so spends no point (`gaps`).

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/gap
import genesis_prime/message/ability_points.{AbilityPoints}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/bool
import gleam/list

/// The points a character of the level has in all: the sum of `abilityPointsPerLevel` over
/// the XpPerLevel rows from ID 1 to the level. The table load requires a row for every level
/// to the highest (`level.requirements`), so no row in that range is missing.
pub fn total(tables tables: table_store.Tables, level level: Int) -> Int {
  xp_per_level.all(tables)
  |> list.filter(fn(row) { row.id >= 1 && row.id <= level })
  |> list.fold(from: 0, with: fn(sum, row) {
    sum + row.ability_points_per_level
  })
}

/// 0x0169 for a character of the level: the points to spend are the total less those spent.
pub fn frame(
  tables tables: table_store.Tables,
  level level: Int,
  spent spent: Int,
) -> Frame {
  points_frame(total: total(tables:, level:), spent:)
}

/// 0x0169 for a total and the points spent: the rule refuses a save that spends above the total
/// and the level never falls, so a negative points to spend stops the caller.
pub fn points_frame(total total: Int, spent spent: Int) -> Frame {
  let assert Ok(body) =
    ability_points.encode(AbilityPoints(
      ability_points: total - spent,
      total_ability_points: total,
    ))
    as "the rule refuses a save that spends above the total, so the points to spend are 0 or more and fit 32 bits"
  Frame(message_id: ability_points.message_id, body:)
}

/// The frames a rise from one level to another sends: none when the two levels have the same
/// total, else the one frame of the new level, whatever the number of levels the rise crossed.
pub fn after_rise(
  tables tables: table_store.Tables,
  from_level from_level: Int,
  to_level to_level: Int,
  spent spent: Int,
) -> List(Frame) {
  use <- bool.guard(
    when: total(tables:, level: from_level) == total(tables:, level: to_level),
    return: [],
  )
  [frame(tables:, level: to_level, spent:)]
}

/// What the ability points do not do: the spending the client offers for them.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Abilities",
      missing: "The tiers a player buys are kept only until the next map change, Holocrypt rejoin, camp or login: the place save carries the bars and no tier, so each of those starts every ability at tier 1 and gives every point back.",
    ),
  ]
}
