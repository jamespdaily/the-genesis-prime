//// The ability points a character has, and the 0x0169 that tells the client: the points to
//// spend and the total the player can hold (`opcode.0x169`). The spellbook window shows both
//// and enables a tier button while the points to spend are above 0; the interface menu's
//// Abilities button alerts while they are (`lua.Abilities.UpdateInterfaceMenuAlerts`).
////
//// ```
//// world entry   ─▶ frame(tables, level)                  after 0x092C, before 0x025E
//// level rise    ─▶ after_rise(tables, from, to)          after the 0x0938 of the new level
////                    [] when the total is the same, else the one frame of the new level
//// ```
////
//// - **The total of a level** is the sum of `XpPerLevel.abilityPointsPerLevel` over the rows
////   with ID 1 to the level: 0 up to level 9, one more per level from 10, 41 at 50. The
////   client never adds the column up; this sum is the server's.
//// - **Points spent are 0.** The server saves no tier, so every point a level gives is
////   unspent and the two fields are equal. A tier button enables on the unspent points, and
////   a click sends 0x00B1 or 0x017A, which the connection logs as unhandled: tier
////   spending and action set edits are not built (`gaps`).

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/gap
import genesis_prime/message/ability_points.{AbilityPoints}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/bool
import gleam/list

/// The points spent on tiers: none, because the server saves no tier.
const no_tier_points_spent = 0

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
pub fn frame(tables tables: table_store.Tables, level level: Int) -> Frame {
  let total = total(tables:, level:)
  let assert Ok(body) =
    ability_points.encode(AbilityPoints(
      ability_points: total - no_tier_points_spent,
      total_ability_points: total,
    ))
    as "two points of 32 bits fit the message"
  Frame(message_id: ability_points.message_id, body:)
}

/// The frames a rise from one level to another sends: none when the two levels have the same
/// total, else the one frame of the new level, whatever the number of levels the rise crossed.
pub fn after_rise(
  tables tables: table_store.Tables,
  from_level from_level: Int,
  to_level to_level: Int,
) -> List(Frame) {
  use <- bool.guard(
    when: total(tables:, level: from_level) == total(tables:, level: to_level),
    return: [],
  )
  [frame(tables:, level: to_level)]
}

/// What the ability points do not do: the spending the client offers for them.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Abilities",
      missing: "Spending ability points on a tier and editing the action set are not built: a tier button enables on the unspent points and its click is logged as unhandled, so every point a level gives stays unspent.",
    ),
  ]
}
