//// A player's experience and level, and what a kill's credit does to them: the pure
//// rule, with its effects for the connection's shell to carry out
//// (genesis_prime/game/connection/experience).
////
//// ```
//// creature: the killing blow ─▶ KillCredit(stay, unit, creature, level) ─▶ the connection
////                                (genesis_prime/world_map/creature)        (this stay's player, in the world)
//// credited(progress, credit, tables, numbers):
////   gain = round(XpPerLevel.baseQuestXpPerLevel[creature level, at most the highest level]
////                × kill_experience_fraction
////                × Creature2Difficulty.clusterContributionValueDifficulty of the creature's Creature2 row
////                × the multiplier of (creature level − player level, from −4 to 4))
////   gain 0, or the player at the highest level ─▶ nothing changes, nothing is sent
////   else experience' = experience + gain, at most the highest level's minXpForLevel
////        level'      = level.for_experience(experience')
////        ─▶ GainSent(gain, unit)             0x1ac {gain, 0, 0, 2, unit}
////        ─▶ LevelRose(level')                0x938 {self, 10, level'}, and a Level news to each viewer
////           (only when level' is above level, once for a crossing of several levels)
//// ```
////
//// - **The amount is the server's choice.** The client has no kill formula: the
////   server sends the amount in 0x1ac (`0x14050cbf0`, `opcode.0x1ac`). The base is the
////   client's XpPerLevel `baseQuestXpPerLevel` at the creature's level, and the fraction and
////   the nine level-gap multipliers are game_number rows, each with its reason
////   (genesis_prime/world_map/game_number, migration 0021). The creature's difficulty
////   weight is the client's Creature2Difficulty `clusterContributionValueDifficulty`; no
////   client code shows that column feeds experience, so using it is a server choice too.
//// - **The 0x1ac values** are the gain, 0 rest experience used, 0 for the third value
////   (`opcode.0x1ac.fields`), kind 2 KillCreature (`CombatFloater.CodeEnumExpReason`) and
////   the creature's unit id.
//// - **The level** is `genesis_prime/game/level.for_experience`: the highest XpPerLevel id up
////   to GameFormula 145 (50) whose minXpForLevel is at most the experience
////   (`0x140029820`). At the highest level a credit gives nothing, and a gain that crosses
////   into it stops at its minXpForLevel, so a saved experience stays inside the table's
////   levels (rows above it hold 2147483647, `opcode.0x25e.safe_body`).
//// - **Not here:** kill objectives, quest experience (0x1ac kind 3), group sharing and
////   tagging, rest experience, and the stats and points a level gives.

import genesis_prime/table/id.{type Creature2Id, XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/option.{type Option, None, Some}
import gleam/result

/// The credit for a kill a creature tells the connection of the player whose blow
/// killed it: the creature's unit, its Creature2 row and its level, the level its 0x262
/// sends as stat 10.
pub type Credit {
  Credit(unit_id: Int, creature_id: Creature2Id, level: Int)
}

/// A player's experience and the level it makes.
pub type Progress {
  Progress(experience: Int, level: Int)
}

/// What a credit asks the connection to do.
pub type Effect {
  /// 0x1ac of kind 2 for a gain above 0, naming the creature's unit.
  GainSent(gain: Int, unit_id: Int)
  /// The player's level rose to `level`: 0x938 of stat 10 to its client and a `Level` news
  /// to each viewer, and every holder of the level changes with it.
  LevelRose(level: Int)
}

/// What a credit made of the progress: the new progress and the effects, in order.
pub type Credited {
  Credited(progress: Progress, effects: List(Effect))
}

/// The experience a character enters with: the saved experience, or the least
/// experience of its level when none was saved (`None`), which is what 0x25E sent before
/// experience was saved (`opcode.0x25e.safe_body`). `Error(Nil)` for a level with no
/// XpPerLevel row, which world entry refuses.
pub fn entering(
  tables tables: table_store.Tables,
  level level: Int,
  saved saved: Option(Int),
) -> Result(Int, Nil) {
  case saved {
    Some(experience) -> Ok(experience)
    None ->
      xp_per_level.get(tables:, id: XpPerLevelId(level))
      |> result.map(fn(row) { row.min_xp_for_level })
  }
}

/// The experience a kill of the creature gives a player of `player_level`: the formula
/// in the module's head, rounded, 0 for a gap that gives nothing and for a player at the
/// highest level.
fn gain(
  credit _credit: Credit,
  player_level _player_level: Int,
  tables _tables: table_store.Tables,
  numbers _numbers: GameNumbers,
) -> Int {
  panic as "the build works out the gain: round(baseQuestXpPerLevel x fraction x difficulty weight x gap multiplier)"
}

/// The progress after a credit, and what the connection sends for it.
pub fn credited(
  progress progress: Progress,
  credit credit: Credit,
  tables tables: table_store.Tables,
  numbers numbers: GameNumbers,
) -> Credited {
  let _gain = gain(credit:, player_level: progress.level, tables:, numbers:)
  panic as "the build adds the gain to the experience, finds the level, and asks for 0x1ac and the level rise"
}
