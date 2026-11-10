//// A player's experience and level, and what a kill's credit does to them: the pure
//// rule, with its effects for the connection's shell to carry out
//// (genesis_prime/game/connection/experience).
////
//// ```
//// creature: the killing blow ─▶ KillCredit(stay, unit, creature, faction, level) ─▶ the connection
////                                (genesis_prime/world_map/creature)        (this stay's player, in the world)
//// credited(progress, credit, tables, numbers):
////   gain = round(XpPerLevel.baseQuestXpPerLevel[creature level, at most the highest level]
////                × kill_experience_fraction
////                × Creature2Difficulty.clusterContributionValueDifficulty of the creature's Creature2 row
////                × the multiplier of (creature level − player level, from −4 to 4))
////   gain 0, or the player at the highest level ─▶ nothing changes, nothing is sent
////   else experience' = experience + gain, at most the highest level's minXpForLevel
////        level'      = level.for_experience(experience')
////        ─▶ GainSent(experience' − experience, unit)   0x1ac {added, 0, 0, 2, unit}: the
////           amount added, so the client's experience stays the server's at the stop
////        ─▶ LevelRose(level')                0x938 {self, 10, level'}, and a Level news to each viewer
////           (only when level' is above level, once for a crossing of several levels)
//// ```
////
//// - **The amount is the server's choice.** The client has no kill formula: the
////   server sends the amount in 0x1ac (`0x14050cbf0`, `opcode.0x1ac`). The base is the
////   client's XpPerLevel `baseQuestXpPerLevel` at the creature's level, and the fraction and
////   the nine level-gap multipliers are game_number rows, each with its reason
////   (genesis_prime/world_map/game_number, migration 0022). The creature's difficulty
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
//// - **A quest's experience** is the same stop and level rise through `gained` with kind 3.
//// - **Not here:** kill objectives, group sharing and
////   tagging, rest experience, and the stats and points a level gives.

import genesis_prime/game/level
import genesis_prime/table/creature2
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/id.{type Creature2Id, type Faction2Id, XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The credit for a kill a creature tells the connection of the player whose blow
/// killed it: the creature's unit, its Creature2 row, its Faction2 (the one its 0x262
/// sends) and its level, the level its 0x262 sends as stat 10.
pub type Credit {
  Credit(
    unit_id: Int,
    creature_id: Creature2Id,
    faction_id: Faction2Id,
    level: Int,
  )
}

/// A player's experience and the level it makes.
pub type Progress {
  Progress(experience: Int, level: Int)
}

/// The source kind a kill's 0x1ac carries, KillCreature (`CombatFloater.CodeEnumExpReason`).
const kill_kind = 2

/// The source kind a quest's 0x1ac carries, Quest (`CombatFloater.CodeEnumExpReason`).
pub const quest_kind = 3

/// What a gain asks the connection to do.
pub type Effect {
  /// 0x1ac of the source `kind` for a gain above 0, naming the unit that gave it (a
  /// creature's for a kill, 0 for a quest).
  GainSent(gain: Int, kind: Int, unit_id: Int)
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
  use row <- result.map(xp_per_level.get(tables:, id: XpPerLevelId(level)))
  case saved {
    Some(experience) -> experience
    None -> row.min_xp_for_level
  }
}

/// The experience a kill of the creature gives a player of `player_level`: the formula
/// in the module's head, rounded, 0 for a gap that gives nothing and 0 for a creature
/// whose Creature2Difficulty row does not exist (Creature2Difficulty 0, which 17,990
/// Creature2 rows name, has none: kill experience works as the-eldan-experiment's
/// does, which gives 0 there). The creature was spawned from its Creature2 row, and
/// the level-gap multipliers are nine numbers (`game_number`).
fn gain(
  credit credit: Credit,
  player_level player_level: Int,
  highest highest: Int,
  tables tables: table_store.Tables,
  numbers numbers: GameNumbers,
) -> Int {
  let assert Ok(row) =
    xp_per_level.get(
      tables:,
      id: XpPerLevelId(int.clamp(credit.level, min: 1, max: highest)),
    )
    as "the load requires an XpPerLevel row for every level from 1 to the highest"
  let assert Ok(creature) = creature2.get(tables:, id: credit.creature_id)
    as "a creature is spawned from a Creature2 row"
  let difficulty =
    creature2_difficulty.get(
      tables:,
      id: creature2.creature2_difficulty_id(creature),
    )
    |> result.map(fn(row) { row.cluster_contribution_value_difficulty })
    |> result.unwrap(or: 0.0)
  let gap = int.clamp(credit.level - player_level, min: -4, max: 4)
  let assert Ok(multiplier) =
    numbers.kill_experience_multipliers |> list.drop(gap + 4) |> list.first
    as "the nine level-gap multipliers are loaded"
  float.round(
    int.to_float(row.base_quest_xp_per_level)
    *. numbers.kill_experience_fraction
    *. difficulty
    *. multiplier,
  )
}

/// The progress after a credit, and what the connection sends for it: a gain that
/// adds nothing (a gap that gives 0, or the highest level) changes and sends nothing,
/// the gain sent is what was added after the stop at the highest level's
/// minXpForLevel, and a level never falls.
pub fn credited(
  progress progress: Progress,
  credit credit: Credit,
  tables tables: table_store.Tables,
  numbers numbers: GameNumbers,
) -> Credited {
  let assert Ok(highest) = level.highest_level(tables)
    as "the load requires GameFormula row 145"
  let gain =
    gain(credit:, player_level: progress.level, highest:, tables:, numbers:)
  gained(progress:, gain:, kind: kill_kind, unit_id: credit.unit_id, tables:)
}

/// The progress after `gain` experience of the source `kind`, from the unit `unit_id`: the
/// same stop and level rise for every source. A gain that adds nothing (0, or the highest
/// level) changes and sends nothing, and the gain sent is what was added after the stop
/// at the highest level's minXpForLevel.
pub fn gained(
  progress progress: Progress,
  gain gain: Int,
  kind kind: Int,
  unit_id unit_id: Int,
  tables tables: table_store.Tables,
) -> Credited {
  let unchanged = Credited(progress:, effects: [])
  let assert Ok(highest) = level.highest_level(tables)
    as "the load requires GameFormula row 145"
  case progress.level >= highest {
    True -> unchanged
    False -> {
      let assert Ok(top) = xp_per_level.get(tables:, id: XpPerLevelId(highest))
        as "the load requires the XpPerLevel row of the highest level"
      let experience = int.min(progress.experience + gain, top.min_xp_for_level)
      case experience > progress.experience {
        False -> unchanged
        True -> added_to(progress:, experience:, kind:, unit_id:, tables:)
      }
    }
  }
}

/// The progress once `experience` is more than it was: the gain sent is the
/// difference, and the level rises when the experience reaches a higher one.
fn added_to(
  progress progress: Progress,
  experience experience: Int,
  kind kind: Int,
  unit_id unit_id: Int,
  tables tables: table_store.Tables,
) -> Credited {
  let assert Ok(made) = level.for_experience(tables:, experience:)
    as "an experience up to the highest level's minimum has a level"
  let reached = int.max(made, progress.level)
  let rise = case reached > progress.level {
    True -> [LevelRose(level: reached)]
    False -> []
  }
  Credited(progress: Progress(experience:, level: reached), effects: [
    GainSent(gain: experience - progress.experience, kind:, unit_id:),
    ..rise
  ])
}
