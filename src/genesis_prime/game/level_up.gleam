//// The level-up fanfare: the client's 0x07A5 asks for the cast of the Level Up spell of a
//// level, which draws the full-screen "Level Up" text and plays the announcer's voice.
//// A feature of the game connection's rule (genesis_prime/game/connection) taken from inside
//// 0x038C with the player in the world.
////
//// ```
//// load: Spell4Base 53378's Spell4 rows ─▶ plan of each tier ─▶ Fanfares (level ─▶ Spell)
//// 0x07A5 {level} ─▶ take(fanfares, player_level, body)
////      level 2 to the player's level ─▶ Fanfare(spell): the connection casts it (cast.level_up_started)
////      level 0 or 1                  ─▶ NoFanfare: a debug line, nothing cast
////      a level above the player's    ─▶ a refusal that ends the connection
////      a body the client's reader would refuse ─▶ a refusal that ends the connection
//// ```
////
//// - **Who asks.** The client's fanfare, 2000 ms after its level rises, with its unit's
////   level, and the Level Up Unlocks window's Replay button, with any level 2 to 50 not
////   above its unit's (`opcode.0x7a5`, `lua.LevelUpUnlocks.ReplayLevelUp`). The client
////   draws and plays nothing for it itself: the answer is a cast (`spell.level_up.cast`).
//// - **The tier.** Spell4Base 53378 holds 49 Spell4 rows, tierIndex 1 to 49, and tier n is
////   the fanfare of level n + 1. A tier is found by its tierIndex: the Spell4 ids are not
////   consecutive (`Spell4.tierIndex.level_up`).
//// - **No fanfare** for level 0 or 1: the stock window lists levels 2 to 50, so only an
////   addon's own call sends them.
//// - **The refusal** of a level above the player's: the client's `ReplayLevelUp` sends none
////   (`0x140703b5b`), and its fanfare sends its unit's own level.
//// - **The load fails** when a level from 2 to the highest has no tier, a tier cannot be
////   planned, or a tier holds no full-screen row aimed at the caster.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/message/replay_level_up
import genesis_prime/shared/level
import genesis_prime/shared/spell_plan.{type Spell}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The Spell4Base of the Level Up spell, whose tiers are the fanfares of levels 2 to 50
/// (`Spell4.tierIndex.level_up`).
const level_up_base = Spell4BaseId(53_378)

/// The plan of each level's fanfare, by level.
pub type Fanfares {
  Fanfares(spells: Dict(Int, Spell))
}

const fanfares_key: table_store.DerivedKey(Fanfares) =
  table_store.DerivedKey("LevelUpFanfares")

/// What a 0x07A5 the client may send asks for.
pub type Taken {
  /// Cast this tier of the Level Up spell.
  Fanfare(spell: Spell)
  /// A level with no fanfare (0 and 1).
  NoFanfare(level: Int)
}

/// Why a 0x07A5 is refused: the client's own code never sends it. The connection ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A level above the player's own.
  AbovePlayerLevel(level: Int, player_level: Int)
}

/// Why the fanfares cannot be built from the tables.
type BuildError {
  /// GameFormula 145 holds no highest level.
  NoHighestLevel
  /// No Spell4 of Spell4Base 53378 has the tierIndex of this level's fanfare.
  NoTier(level: Int, tier_index: Int)
  /// The tier's tree cannot be planned.
  TierNotPlanned(level: Int, error: spell_plan.PlanError)
  /// The tier's plan holds no full-screen row aimed at the caster.
  TierShowsNothing(level: Int, spell4_id: Int)
}

/// The fanfares as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees' sources.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: fanfares_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe_build)
  })
}

/// The fanfares the tables' load built.
pub fn fanfares(tables tables: table_store.Tables) -> Fanfares {
  table_store.derived(tables:, key: fanfares_key)
}

/// The plan of a level's fanfare, or `Error(Nil)` for a level below 2 or above the highest.
pub fn spell_of(
  fanfares fanfares: Fanfares,
  level level: Int,
) -> Result(Spell, Nil) {
  dict.get(fanfares.spells, level)
}

fn build(tables tables: table_store.Tables) -> Result(Fanfares, BuildError) {
  use highest <- result.try(
    level.highest_level(tables) |> result.replace_error(NoHighestLevel),
  )
  let sources = spell_plan.sources_of(tables:)
  let tiers =
    spell4.all(tables)
    |> list.filter(fn(row) {
      spell4.spell4_base_id_base_spell(row) == level_up_base
    })
    |> list.map(fn(row) { #(row.tier_index, row) })
    |> dict.from_list
  int.range(from: 2, to: highest + 1, with: Ok([]), run: fn(so_far, level) {
    use spells <- result.try(so_far)
    use spell <- result.map(tier_of(tables:, sources:, tiers:, level:))
    [#(level, spell), ..spells]
  })
  |> result.map(fn(spells) { Fanfares(spells: dict.from_list(spells)) })
}

/// The plan of the tier that is the fanfare of this level, or why it cannot be.
fn tier_of(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  tiers tiers: Dict(Int, spell4.Spell4),
  level level: Int,
) -> Result(Spell, BuildError) {
  use row <- result.try(
    dict.get(tiers, level - 1)
    |> result.replace_error(NoTier(level:, tier_index: level - 1)),
  )
  use spell <- result.try(
    spell_plan.spell_alone(tables:, sources:, spell4_id: row.id, chain: [])
    |> result.map_error(TierNotPlanned(level:, error: _)),
  )
  case spell_plan.payloads(spell:, as_kind: spell_plan.as_lasting) {
    [] -> Error(TierShowsNothing(level:, spell4_id: row.id))
    [_, ..] -> Ok(spell)
  }
}

fn describe_build(error error: BuildError) -> String {
  case error {
    NoHighestLevel -> "the table GameFormula has no highest level"
    NoTier(level:, tier_index:) ->
      "the table Spell4 has no row of Spell4Base 53378 with tierIndex "
      <> int.to_string(tier_index)
      <> ", the fanfare of level "
      <> int.to_string(level)
    TierNotPlanned(level:, error:) ->
      "the fanfare of level "
      <> int.to_string(level)
      <> " cannot be planned: "
      <> spell_plan.describe(error:)
    TierShowsNothing(level:, spell4_id:) ->
      "the fanfare of level "
      <> int.to_string(level)
      <> " (Spell4 "
      <> int.to_string(spell4_id)
      <> ") holds no full-screen row aimed at the caster, so it would show nothing"
  }
}

/// What the client's 0x07A5 asks for: the fanfare of the level, when the player's level
/// is at least it and it is 2 or more, else no fanfare or the refusal.
pub fn take(
  fanfares fanfares: Fanfares,
  player_level player_level: Int,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  replay_level_up.decode(body)
  |> client_connection.decoded(message_id: replay_level_up.message_id)
  |> result.map_error(NotDecoded)
  |> result.try(fn(asked) {
    let level = asked.level
    case level > player_level, spell_of(fanfares:, level:) {
      True, _ -> Error(AbovePlayerLevel(level:, player_level:))
      False, Ok(spell) -> Ok(Fanfare(spell:))
      False, Error(Nil) -> Ok(NoFanfare(level:))
    }
  })
}

/// The debug line of a level that has no fanfare.
pub fn describe_no_fanfare(level level: Int) -> String {
  "0x07A5 asks for the fanfare of level "
  <> int.to_string(level)
  <> ", which has none: the Level Up spell has tiers for levels 2 and up, and nothing is cast"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    AbovePlayerLevel(level:, player_level:) ->
      "0x07A5 asks for the fanfare of level "
      <> int.to_string(level)
      <> ", but the player is level "
      <> int.to_string(player_level)
      <> ": the client sends its unit's own level or an earlier one, never a level above it"
  }
}
