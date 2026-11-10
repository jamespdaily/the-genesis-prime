//// The activate cast of a creature the player right-clicks, a collectible such as the
//// Seaspine Mollusk: which spell it casts, how far the player may stand from it, and
//// the plans the cast runs from.
////
//// ```
//// Creature2 row ─▶ creature_of ─▶ pick(columns, check) ─▶ Picked(spell) | NoActivateSpell | Unread
//// the spell's Spell4 row and Activate effects ─▶ Planned (built once when the tables load)
//// range_of(creature, planned, caster body, target body) ─▶ Within | TooClose | TooFar | TooHigh
//// ```
////
//// - **The spell** is the first of the creature's four activate columns whose prerequisite
////   is 0 or passes for the player with the creature as the second unit, even when that
////   column's spell is 0; when none passes it is GameFormula 414's dataint0 (8)
////   (`0x14046c580`). Spell 0 is refused with result 100.
//// - **The range** is edge to edge, in three dimensions, with no margin: the gap is the
////   distance between the two units less both hit radii, never below 0
////   (`opcode.0x97.range`, `0x1403b2240`). A spell among the creature's columns is held to
////   the creature's own limits (a max of 0 falls back to the spell's), any other spell to
////   the Spell4 row's (`0x1403ad860`, `0x1403ad8f0`).
//// - **The plans** hold each activate spell's Spell4 row, plan and Activate effects, and
////   the Prerequisite rows the columns name; the Creature2 rows are read from the tables
////   when an activation arrives (the derivation stores none of the 8,463 creatures that
////   have an activate column).
//// - Gaps: the client's per-unit vertical offset and the creature words 0x6c and 0x148 that
////   make the client pick no spell are not modelled.

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/creature2
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Spell4EffectsId, GameFormulaId, Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set

/// The GameFormula row whose dataint0 is the spell a creature casts when none of its
/// columns passes (`0x14046c580`).
const default_spell_formula = 414

/// One of a creature's four activate columns.
pub type Column {
  Column(prerequisite_id: Int, spell4_id: Int)
}

/// What a Creature2 row says of its activate cast.
pub type Creature {
  Creature(
    columns: List(Column),
    /// Creature2.activateSpellCastTime: the cast time of an activate cast, whatever
    /// the spell's own is.
    cast_time_ms: Int,
    /// Creature2.activateSpellMinRange and activateSpellMaxRange.
    min_range: Float,
    max_range: Float,
  )
}

/// The creature's activate columns in order, with its cast time and range.
pub fn creature_of(row row: creature2.Creature2) -> Creature {
  Creature(
    columns: [
      Column(row.prerequisite_id_activate_spell00, row.spell4_id_activate00),
      Column(row.prerequisite_id_activate_spell01, row.spell4_id_activate01),
      Column(row.prerequisite_id_activate_spell02, row.spell4_id_activate02),
      Column(row.prerequisite_id_activate_spell03, row.spell4_id_activate03),
    ],
    cast_time_ms: row.activate_spell_cast_time,
    min_range: row.activate_spell_min_range,
    max_range: row.activate_spell_max_range,
  )
}

/// Which spell a creature casts for a player.
pub type Pick {
  /// The Spell4 id of the spell, never 0.
  Picked(spell4_id: Int)
  /// The creature has no activate spell for the player: result 100.
  NoActivateSpell
  /// A column's prerequisite holds a condition the server does not read, so the
  /// client's pick cannot be told.
  Unread(prerequisite_type: Int)
}

/// The spell the creature casts: the first column whose prerequisite is 0 or whose
/// `check` passes, else `default_spell`; spell 0 is no activate spell.
pub fn pick(
  creature creature: Creature,
  default_spell default_spell: Int,
  check check: fn(Int) -> prerequisite.Verdict,
) -> Pick {
  let chosen =
    list.try_fold(creature.columns, default_spell, fn(default, column) {
      case column.prerequisite_id {
        0 -> Error(Ok(column.spell4_id))
        prerequisite_id ->
          case check(prerequisite_id) {
            prerequisite.Passes -> Error(Ok(column.spell4_id))
            prerequisite.Fails -> Ok(default)
            prerequisite.NotRead(prerequisite_type:) ->
              Error(Error(prerequisite_type))
          }
      }
    })
  case chosen {
    Ok(spell4_id) | Error(Ok(spell4_id)) ->
      case spell4_id {
        0 -> NoActivateSpell
        _ -> Picked(spell4_id:)
      }
    Error(Error(prerequisite_type)) -> Unread(prerequisite_type:)
  }
}

/// An Activate effect of a spell: its row and the delay the go lists it with.
pub type ActivateEffect {
  ActivateEffect(effect_id: Spell4EffectsId, delay_ms: Int)
}

/// The limits of a spell cast at a unit from its Spell4 row (targetMinRange,
/// targetMaxRange and targetVerticalRange).
pub type Limits {
  Limits(min: Float, max: Float, vertical: Float)
}

/// What the plans hold of an activate spell.
pub type Planned {
  /// The spell's plan, its Activate effects in row order and its Spell4 limits. A spell of
  /// a method the cast rule does not build is held too: the press is refused as an
  /// ability's is (`cast.verdict`).
  Planned(spell: Spell, effects: List(ActivateEffect), limits: Limits)
  /// The Spell4 table has no row for the spell: result 4.
  NoSpell4Row
  /// The spell's tree cannot be planned: the reason in words.
  CannotBePlanned(why: String)
}

/// The activate spells' plans and the Prerequisite rows of the columns, as the load
/// built them.
pub type Activations {
  Activations(
    /// Each Prerequisite a creature's activate column names, by id.
    prerequisites: Dict(Int, Prerequisite),
    /// Each spell an activate column names, and the default spell, by Spell4 id.
    spells: Dict(Int, Planned),
    /// GameFormula 414's dataint0.
    default_spell: Int,
  )
}

const activations_key: table_store.DerivedKey(Activations) =
  table_store.DerivedKey("Activations")

/// The activations as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees: a missing
/// GameFormula or Prerequisite row, or a cycle in the Prerequisite rows, fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: activations_key, build: fn(tables) {
    build(tables:)
    |> result.map_error(fn(error) {
      case error {
        NoDefaultSpellFormula ->
          "the table GameFormula has no row "
          <> int.to_string(default_spell_formula)
        PrerequisiteNotLoaded(error:) -> spell_plan.describe(error:)
      }
    })
  })
}

/// Why the activations cannot be built from the tables.
type BuildError {
  NoDefaultSpellFormula
  PrerequisiteNotLoaded(error: spell_plan.PlanError)
}

/// The activations the tables' load built.
pub fn activations(tables tables: table_store.Tables) -> Activations {
  table_store.derived(tables:, key: activations_key)
}

/// Builds the activations from the loaded tables, or why they cannot be built: the
/// derivation's body.
fn build(tables tables: table_store.Tables) -> Result(Activations, BuildError) {
  use default_spell <- result.try(
    game_formula.get(tables:, id: GameFormulaId(default_spell_formula))
    |> result.map(fn(row) { row.dataint0 })
    |> result.replace_error(NoDefaultSpellFormula),
  )
  let columns =
    creature2.all(tables)
    |> list.flat_map(fn(row) { creature_of(row:).columns })
  let prerequisite_ids =
    list.map(columns, fn(column) { column.prerequisite_id })
    |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
    |> set.from_list
    |> set.to_list
  let rows = prerequisite.table_rows(tables:)
  let arcs = prerequisite.table_arcs(tables:)
  let quests = prerequisite.table_quests(tables:)
  use prerequisites <- result.try(
    list.try_map(prerequisite_ids, fn(prerequisite_id) {
      spell_plan.column_of(id: prerequisite_id, rows:, arcs:, quests:)
      |> result.map(fn(loaded) { #(prerequisite_id, loaded) })
    })
    |> result.map_error(PrerequisiteNotLoaded),
  )
  let spell_ids =
    [default_spell, ..list.map(columns, fn(column) { column.spell4_id })]
    |> list.filter(fn(spell4_id) { spell4_id != 0 })
    |> set.from_list
    |> set.to_list
  let sources = spell_plan.sources_of(tables:)
  Ok(Activations(
    prerequisites: list.filter_map(prerequisites, fn(entry) {
      option.to_result(entry.1, Nil)
      |> result.map(fn(loaded) { #(entry.0, loaded) })
    })
      |> dict.from_list,
    spells: list.map(spell_ids, fn(spell4_id) {
      #(spell4_id, planned(tables:, sources:, spell4_id:))
    })
      |> dict.from_list,
    default_spell:,
  ))
}

fn planned(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Planned {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> NoSpell4Row
    Ok(row) ->
      case spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: []) {
        Error(error) -> CannotBePlanned(why: spell_plan.describe(error:))
        Ok(spell) ->
          Planned(
            spell:,
            effects: spell_plan.effects_of(sources:, spell4_id:)
              |> list.filter(fn(effect) {
                effect_kind.kind_of(effect_type: effect.effect_type)
                == effect_kind.Activate
              })
              |> list.map(fn(effect) {
                ActivateEffect(
                  effect_id: Spell4EffectsId(effect.id),
                  delay_ms: effect.delay_time,
                )
              }),
            limits: Limits(
              min: row.target_min_range,
              max: row.target_max_range,
              vertical: row.target_vertical_range,
            ),
          )
      }
  }
}

/// The prerequisite check of the pick for one subject: a column's prerequisite, by id,
/// with the player as the first unit and the creature as the second. One the plans do
/// not hold is not read (type 0), which no column of the tables names, since the load
/// holds each column's prerequisite.
pub fn checker(
  activations activations: Activations,
  subject subject: prerequisite.Subject,
) -> fn(Int) -> prerequisite.Verdict {
  fn(prerequisite_id) {
    case dict.get(activations.prerequisites, prerequisite_id) {
      Ok(held) -> prerequisite.check(prerequisite: held, subject:)
      Error(Nil) -> prerequisite.NotRead(prerequisite_type: 0)
    }
  }
}

/// What the unit a right-click names is, as the player's connection knows it.
pub type Target {
  /// The unit is not in the player's picture.
  Unseen
  /// Another player's unit.
  AnotherPlayer
  /// A creature with a fight state, whose place moves: its activate cast is not
  /// built.
  Fighter
  /// A static object: the id of its Creature2 row, what the row says of its activate
  /// cast, and where it stands.
  Object(creature_id: Int, creature: Creature, body: Body)
}

/// A unit's body for the range test: where it stands (y is up) and its hit radius.
pub type Body {
  Body(x: Float, y: Float, z: Float, radius: Float)
}

/// How far the caster stands from the target.
pub type Range {
  Within
  /// Result 104.
  TooClose
  /// Result 105.
  TooFar
  /// Result 183.
  TooHigh
}

/// The limits the cast of `spell4_id` at the creature is held to: the creature's own for
/// a spell among its columns, the spell's for any other (`0x1403ad860`, `0x1403ad8f0`).
pub fn limits_for(
  creature creature: Creature,
  spell4_id spell4_id: Int,
  spell spell: Limits,
) -> Limits {
  use <- bool.guard(
    when: !list.any(creature.columns, fn(column) {
      column.spell4_id == spell4_id
    }),
    return: spell,
  )
  Limits(
    min: creature.min_range,
    max: case creature.max_range == 0.0 {
      True -> spell.max
      False -> creature.max_range
    },
    vertical: spell.vertical,
  )
}

/// The gap between two bodies: the distance between their places less both radii, never
/// below 0 (`0x1403b2240`).
fn gap(from from: Body, to to: Body) -> Float {
  let dx = to.x -. from.x
  let dy = to.y -. from.y
  let dz = to.z -. from.z
  let distance = float.square_root(dx *. dx +. dy *. dy +. dz *. dz)
  float.max(result.unwrap(distance, 0.0) -. from.radius -. to.radius, 0.0)
}

/// Whether the caster stands where `limits` allow its activate cast at the target, as
/// the client tests it before it sends the cast (`0x1403b2240`): the minimum, then the
/// maximum, then the height.
pub fn range_of(
  limits limits: Limits,
  caster caster: Body,
  target target: Body,
) -> Range {
  let gap = gap(from: caster, to: target)
  let height =
    float.absolute_value(target.y -. caster.y) -. caster.radius -. target.radius
  case
    gap <. limits.min,
    gap >. limits.max,
    limits.vertical >. -1.0 && height >. limits.vertical
  {
    True, _, _ -> TooClose
    False, True, _ -> TooFar
    False, False, True -> TooHigh
    False, False, False -> Within
  }
}

/// The plan of the spell, or `Error(Nil)` for one the plans do not hold.
pub fn planned_of(
  activations activations: Activations,
  spell4_id spell4_id: Int,
) -> Result(Planned, Nil) {
  dict.get(activations.spells, spell4_id)
}
