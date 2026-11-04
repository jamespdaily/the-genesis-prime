//// What the client's tables say a spell strikes, for each spell of each class's
//// level-1 ability trees: the area row, the hit shapes of its telegraphs and the
//// damage effects of each phase with who each aims at. Built once when the tables
//// load, beside the ability trees (genesis_prime/game/spell_plan); the strike rule
//// (genesis_prime/game/strike) reads it and decides nothing from the tables itself.
////
//// ```
//// plans (genesis_prime/game/spell_plan) ─▶ every Spell4 of every tree
////   Spell4 ─▶ spell4AoeTargetConstraintsId ─▶ Spell4AoeTargetConstraints (the area row)
////                                              Spell4Base ─▶ spell4ValidTargetsId ─▶ Spell4ValidTargets
////   Spell4Telegraph rows of the spell ─▶ TelegraphDamage ─▶ the hit shapes
////   Spell4Effects of type Damage ─▶ each effect's formula and the units it aims at (targetFlags)
//// all of them, once, when the tables load ─▶ Areas ─▶ of_spell(spell4 id)
//// ```
////
//// - **Who an effect aims at** is its `targetFlags`: 1 the caster, 2 the cast's own
////   target, 4 the area, 6 both (`Spell4Effects.targetFlags`, a reading of the rows).
////   A phase with a damage effect or a Proxy aimed at the area selects units; one aimed
////   at the cast's target strikes the primary target; with neither it strikes nobody
////   and its go is written at once (Gate's Stun child).
//// - **Who is inside** is the telegraph's shape capped by the area row: the never-drawn
////   twin rows (flag 0x40) are the hit shapes, or the drawn rows where a spell has no
////   twin, and a unit must also be within the area row's range. A spell with no
////   telegraph row (42297) is read by its area row's range and arc alone. Kick is a
////   cone from 1 to 7 m over 100 degrees (`Spell4.58591.area`).
//// - **Closest first.** Every area row of the level-1 abilities has `targetSelection`
////   1, and none strikes a dead unit (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`).
//// - **What fails the load:** a row the tree names that the tables lack; a
////   `targetSelection` other than 1; a valid-targets bitmask other than 0; a hit row
////   placed on any unit but the caster (`targetTypeFlags` other than 1); a shape the
////   rule does not build (1, 3, 5, 6, or 8 with a box); a damage effect aimed by a
////   flag value not read; and a formula that reads a parameter the player's value does
////   not (genesis_prime/game/damage `unread`). Each gap is stated where it is enforced.

import genesis_prime/game/area.{type Inside, type Placement, type Row}
import genesis_prime/game/damage.{type Formula}
import genesis_prime/table/id.{type Spell4EffectsId, type Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Who an effect aims at (`Spell4Effects.targetFlags`).
pub type Aim {
  AimsAtCaster
  AimsAtPrimaryTarget
  AimsAtArea
  AimsAtBoth
  /// A flag value no level-1 ability holds: the load refuses an effect with it.
  OtherAim(flags: Int)
}

/// A damage effect of a spell: its row, damage type and delay, the phases it fires
/// in, who it aims at and the formula its value is worked out by.
pub type DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId,
    damage_type: Int,
    delay_ms: Int,
    phase_flags: Int,
    aim: Aim,
    formula: Formula,
  )
}

/// What one phase of a spell strikes.
pub type PhaseStrike {
  PhaseStrike(
    /// The damage effects that fire in the phase and aim at the area or the cast's
    /// target.
    damage: List(DamageEffect),
    /// Whether the phase selects units from the area: a damage effect aimed at the
    /// area, or a Proxy that starts its spell on each struck unit
    /// (genesis_prime/game/spell_plan `OnEachStruck`).
    selects_area: Bool,
    /// Whether the phase strikes the cast's own target.
    strikes_primary_target: Bool,
  )
}

/// A spell's area: its row, the hit shapes of its telegraphs and each phase's
/// strike.
pub type SpellArea {
  SpellArea(
    spell4_id: Spell4Id,
    /// The area row, `None` for a spell with no `Spell4AoeTargetConstraints` row.
    row: Option(Row),
    /// The hit shapes placed on the caster: the never-drawn twins, else the drawn
    /// rows. Empty for a spell with no telegraph row.
    shapes: List(Placement),
    /// One entry for each go of the spell, in phase order.
    phases: List(PhaseStrike),
  )
}

/// Why the areas cannot be built from the tables.
pub type AreaError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// An area row selects in an order but Closest (`targetSelection` is not 1).
  SelectionNotClosest(spell4_id: Int, target_selection: Int)
  /// A spell's valid targets hold a bit: it would strike the dead or more.
  ValidTargetsNotAlive(spell4_id: Int, target_bitmask: Int)
  /// A hit row is placed on a unit but the caster (`targetTypeFlags` other than 1).
  TelegraphNotOnCaster(
    spell4_id: Int,
    telegraph_id: Int,
    target_type_flags: Int,
  )
  /// A hit row's shape is not one the rule builds.
  ShapeNotBuilt(spell4_id: Int, telegraph_id: Int, shape: Int)
  /// A damage effect is aimed by a flag value not read.
  AimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A damage effect's formula reads a parameter a player's value does not.
  FormulaNotRead(spell4_id: Int, effect_id: Int, parameter_kind: Int)
}

/// A sentence that says why the areas cannot be built, naming the table, the
/// spell and the row, for the message the server stops with.
pub fn describe(error error: AreaError) -> String {
  unbuilt(inputs: error)
}

/// Every spell of every level-1 ability tree, by Spell4 id, as the load keeps
/// them.
pub type Areas =
  Dict(Int, SpellArea)

/// The areas as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees: a
/// missing row or an area the rule does not build fails the load.
pub fn derivation() -> table_store.Derivation {
  unbuilt(inputs: Nil)
}

/// Builds every spell's area from the loaded tables, or why one cannot be built;
/// the derivation's body, and the function a test of a refused row runs on planted
/// tables.
pub fn build(tables tables: table_store.Tables) -> Result(Areas, AreaError) {
  unbuilt(inputs: tables)
}

/// The areas the tables' load built.
pub fn areas(tables tables: table_store.Tables) -> Areas {
  unbuilt(inputs: tables)
}

/// The area of the spell, or `Error(Nil)` for a spell of no level-1 ability's
/// tree.
pub fn of_spell(
  areas areas: Areas,
  spell4_id spell4_id: Spell4Id,
) -> Result(SpellArea, Nil) {
  unbuilt(inputs: #(areas, spell4_id))
}

/// How a unit counts as inside the spell's area: the hit shapes when the spell has
/// any, capped by the area row's range, else the area row's range and arc.
pub fn inside(spell spell: SpellArea) -> Inside {
  unbuilt(inputs: spell)
}

/// What the spell's go of `phase` strikes, or `Error(Nil)` for a phase the spell
/// has none of.
pub fn phase(
  spell spell: SpellArea,
  phase phase: Int,
) -> Result(PhaseStrike, Nil) {
  unbuilt(inputs: #(spell, phase))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
