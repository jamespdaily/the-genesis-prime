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
////   A phase with a damage effect, a crowd-control state or a Proxy aimed at the area
////   selects units; one aimed at the cast's target strikes the primary target; with
////   neither it strikes nobody and its go is written at once. A stun with no damage
////   still selects and strikes (Gate's 30436, Stagger's 38780).
//// - **Who is inside** is the telegraph's shape capped by the area row: the never-drawn
////   twin rows (flag 0x40) are the hit shapes, or the drawn rows where a spell has no
////   twin, less the drawn rows with bit 0x20 (the picture of a child spell's beam,
////   `TelegraphDamage.telegraphDamageFlags.0x20.rows`) unless every drawn row has it,
////   and a unit must also be within the area row's range. A spell with no
////   telegraph row (42297) is read by its area row's range and arc alone. Kick is a
////   cone from 1 to 7 m over 100 degrees (`Spell4.58591.area`).
//// - **The points a cast spent.** A damage effect keeps its row's tag
////   (`Spell4Effects.emmComparison`, genesis_prime/game/spend), and `phase` keeps
////   only the effects and Proxies whose tag holds for the points the cast spent above
////   its base cost, then works out `selects_area` and `strikes_primary_target` from
////   what is left. A cast with no spend keeps every effect.
//// - **Closest first.** Every area row of the level-1 abilities has `targetSelection`
////   1, and none strikes a dead unit (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`).
//// - **Which spells** are read: the spells of each level-1 ability's tree
////   (genesis_prime/game/spell_plan), its threshold stages (Spell4Thresholds) included,
////   a Proxy behind a target prerequisite excepted, since it is never started. A spell
////   with no area row selects nobody.
//// - **What fails the load:** a row the tree names that the tables lack; a
////   `targetSelection` other than 1; a valid-targets bitmask other than 0 on a spell
////   with an area row; a hit row placed on any unit but the caster (`targetTypeFlags`
////   other than 1); a shape the rule does not build (1, 3, 5, 6, or 8 with a box that
////   has a width or a length: the box's height, p4, is never tested); a damage effect
////   (type 8) aimed by a flag value not read; a formula that reads a parameter the
////   player's value does not (genesis_prime/game/damage `unread`); and a phase that
////   selects units from a spell with no area row. A hit row's phases are not read, so
////   a spell's shapes hold for each of its gos. Each gap is stated where it is
////   enforced.

import genesis_prime/game/area.{
  type Inside, type Placement, type Row, Box, Circle, Cone, InsideRow,
  InsideShapes, Placement, Rectangle, Row,
}
import genesis_prime/game/damage.{type Formula}
import genesis_prime/game/effect_kind
import genesis_prime/game/spell_plan.{
  type Aim, type Spell, AimsAtArea, AimsAtBoth, AimsAtPrimaryTarget,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{
  type Spell4EffectsId, type Spell4Id, Spell4AoeTargetConstraintsId,
  Spell4EffectsId, Spell4ValidTargetsId, TelegraphDamageId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/telegraph_damage
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A damage effect of a spell: its row, damage type and delay, the phases it fires
/// in, who it aims at, the formula its value is worked out by and the tag that
/// chooses it by the points the cast spent (genesis_prime/game/spend).
pub type DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId,
    damage_type: Int,
    delay_ms: Int,
    phase_flags: Int,
    aim: Aim,
    formula: Formula,
    threat_multiplier: Float,
    tag: spend.Tag,
  )
}

/// What one phase of a spell strikes, for a cast that spent a given number of
/// points (`phase`).
pub type PhaseStrike {
  PhaseStrike(
    /// The damage effects that fire in the phase and aim at the area or the cast's
    /// target.
    damage: List(DamageEffect),
    /// The crowd-control states that fire in the phase, which aim at the area, the
    /// cast's target or both.
    controls: List(spell_plan.CrowdControl),
    /// Whether the phase selects units from the area: a damage effect or a
    /// crowd-control state aimed at the area, or a Proxy that starts its spell on each
    /// struck unit (genesis_prime/game/spell_plan `OnEachStruck`).
    selects_area: Bool,
    /// Whether the phase strikes the cast's own target: a damage effect or a
    /// crowd-control state aimed at it.
    strikes_primary_target: Bool,
  )
}

/// A spell's area: its row, the hit shapes of its telegraphs and the effects its
/// phases strike with, which `phase` chooses from by the points a cast spent.
pub type SpellArea {
  SpellArea(
    spell4_id: Spell4Id,
    /// The area row, `None` for a spell with no `Spell4AoeTargetConstraints` row.
    row: Option(Row),
    /// The hit shapes placed on the caster: the never-drawn twins, else the drawn
    /// rows without bit 0x20 (all of them when each has it). Empty for a spell with no
    /// telegraph row.
    shapes: List(Placement),
    /// Every damage effect of the spell, each with its tag.
    damage: List(DamageEffect),
    /// The spell as the plan holds it, whose Proxies aimed at each struck unit
    /// make a phase select the area.
    spell: Spell,
  )
}

/// Why the areas cannot be built from the tables.
pub type AreaError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// A spell strikes an area in one of its phases but names no area row.
  NoAreaRow(spell4_id: Int)
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
  /// A damage effect's multiplier (`dataBits00`, read as 32 bits) is an infinity or a
  /// number that is not one.
  MultiplierNotFinite(spell4_id: Int, effect_id: Int, bits: Int)
}

/// A sentence that says why the areas cannot be built, naming the table, the
/// spell and the row, for the message the server stops with.
fn describe(error error: AreaError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table "
      <> table
      <> " has no row "
      <> int.to_string(id)
      <> ", which a spell's area names"
    NoAreaRow(spell4_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " strikes an area in one of its phases and has no Spell4AoeTargetConstraints row"
    SelectionNotClosest(spell4_id:, target_selection:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an area row that selects in order "
      <> int.to_string(target_selection)
      <> ", and only Closest (1) is built"
    ValidTargetsNotAlive(spell4_id:, target_bitmask:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has valid targets of bitmask "
      <> int.to_string(target_bitmask)
      <> ", and only 0 (the alive) is built"
    TelegraphNotOnCaster(spell4_id:, telegraph_id:, target_type_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph "
      <> int.to_string(telegraph_id)
      <> " placed by flags "
      <> int.to_string(target_type_flags)
      <> ", and only the caster (1) is built"
    ShapeNotBuilt(spell4_id:, telegraph_id:, shape:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph "
      <> int.to_string(telegraph_id)
      <> " of shape "
      <> int.to_string(shape)
      <> ", which is not built"
    AimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a damage effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", which are not read"
    FormulaNotRead(spell4_id:, effect_id:, parameter_kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a damage effect "
      <> int.to_string(effect_id)
      <> " whose formula reads parameter type "
      <> int.to_string(parameter_kind)
      <> ", which a player's value does not"
    MultiplierNotFinite(spell4_id:, effect_id:, bits:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a damage effect "
      <> int.to_string(effect_id)
      <> " whose multiplier, dataBits00 "
      <> int.to_string(bits)
      <> ", is not a finite 32-bit float"
  }
}

/// Every spell of every level-1 ability tree, by Spell4 id, as the load keeps
/// them.
pub type Areas =
  Dict(Int, SpellArea)

const areas_key: table_store.DerivedKey(Areas) =
  table_store.DerivedKey("SpellAreas")

/// The areas as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees: a
/// missing row or an area the rule does not build fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: areas_key, build: fn(tables) {
    build(tables:) |> result.map_error(fn(error) { describe(error:) })
  })
}

/// Builds every spell's area from the loaded tables, or why one cannot be built;
/// the derivation's body, and the function a test of a refused row runs on planted
/// tables. The ability trees must already be derived
/// (genesis_prime/game/spell_plan `plans`).
pub fn build(tables tables: table_store.Tables) -> Result(Areas, AreaError) {
  let spells =
    dict.values(spell_plan.plans(tables:))
    |> list.flat_map(spells_of_tree)
  let effects = spell_plan.effects_by_spell(tables:)
  let links = telegraph_links_by_spell(tables:)
  list.try_fold(spells, dict.new(), fn(areas, spell) {
    let id = spell.spell4_id.value
    case dict.has_key(areas, id) {
      True -> Ok(areas)
      False -> {
        use area <- result.try(area_of(tables:, effects:, links:, spell:))
        Ok(dict.insert(areas, id, area))
      }
    }
  })
}

/// The spell, the stage spells a RapidTap or ChargeRelease ability casts and every
/// spell the Proxies of any of them start, below them. A Proxy behind a prerequisite may
/// start its child, so the child is read: one behind a target prerequisite starts it on a
/// unit that passes (genesis_prime/game/spell_plan `GatedOnCasterAndTarget`).
fn spells_of_tree(spell: Spell) -> List(Spell) {
  spell_plan.tree(spell:, started: fn(_) { True })
}

/// The Spell4Telegraph rows of each spell, in table order, grouped once.
fn telegraph_links_by_spell(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_telegraph.Spell4Telegraph)) {
  list.reverse(spell4_telegraph.all(tables))
  |> list.fold(dict.new(), fn(links, link) {
    dict.upsert(links, link.spell4_id, fn(found) {
      [link, ..option.unwrap(found, [])]
    })
  })
}

fn area_of(
  tables tables: table_store.Tables,
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  spell spell: Spell,
) -> Result(SpellArea, AreaError) {
  let id = spell.spell4_id.value
  use row <- result.try(
    spell4.get(tables:, id: spell.spell4_id)
    |> result.replace_error(NoRow(table: "Spell4", id:)),
  )
  use base <- result.try(
    spell4_base.get(tables:, id: spell.spell4_base_id)
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: spell.spell4_base_id.value,
    )),
  )
  use area_row <- result.try(area_row_of(tables:, id:, row:))
  use Nil <- result.try(case area_row {
    Some(..) -> valid_targets_checked(tables:, id:, base:)
    None -> Ok(Nil)
  })
  use shapes <- result.try(hit_shapes_of(tables:, links:, id:))
  use damage <- result.try(damage_effects_of(effects:, id:))
  let area =
    SpellArea(
      spell4_id: spell.spell4_id,
      row: area_row,
      shapes:,
      damage:,
      spell:,
    )
  // A phase that selects units at some n, every effect chosen being the widest, must
  // have an area row.
  let selects =
    int.range(
      from: 0,
      to: phase_count(spell: area),
      with: [],
      run: fn(found, phase) { [phase, ..found] },
    )
    |> list.any(fn(phase) {
      phase_of(spell: area, phase:, spent: None).selects_area
    })
  use Nil <- result.try(case area_row, selects {
    None, True -> Error(NoAreaRow(spell4_id: id))
    _, _ -> Ok(Nil)
  })
  Ok(area)
}

/// A spell with an area row whose base names valid targets takes only the alive:
/// bitmask 0 (a spell with no area selects nobody, so its valid targets are not read).
fn valid_targets_checked(
  tables tables: table_store.Tables,
  id id: Int,
  base base: spell4_base.Spell4Base,
) -> Result(Nil, AreaError) {
  case base.spell4_valid_target_id {
    0 -> Ok(Nil)
    valid_id -> {
      use valid <- result.try(
        spell4_valid_targets.get(tables:, id: Spell4ValidTargetsId(valid_id))
        |> result.replace_error(NoRow(table: "Spell4ValidTargets", id: valid_id)),
      )
      case valid.target_bitmask {
        0 -> Ok(Nil)
        bitmask ->
          Error(ValidTargetsNotAlive(spell4_id: id, target_bitmask: bitmask))
      }
    }
  }
}

fn area_row_of(
  tables tables: table_store.Tables,
  id id: Int,
  row row: spell4.Spell4,
) -> Result(Option(Row), AreaError) {
  case row.spell4_aoe_target_constraints_id {
    0 -> Ok(None)
    constraints_id -> {
      use constraints <- result.try(
        spell4_aoe_target_constraints.get(
          tables:,
          id: Spell4AoeTargetConstraintsId(constraints_id),
        )
        |> result.replace_error(NoRow(
          table: "Spell4AoeTargetConstraints",
          id: constraints_id,
        )),
      )
      case constraints.target_selection {
        1 ->
          Ok(
            Some(Row(
              min_range: constraints.min_range,
              max_range: constraints.max_range,
              degrees: constraints.angle,
              target_count: constraints.target_count,
            )),
          )
        selection ->
          Error(SelectionNotClosest(spell4_id: id, target_selection: selection))
      }
    }
  }
}

/// The telegraph rows of the spell that say who is hit: the never-drawn twins (flag
/// 0x40), or the rows drawn when it has none, less the drawn rows with bit 0x20, which
/// are pictures of another spell's hit shape (a spell's own copy of its child's beam),
/// unless every drawn row has it: then they are all kept
/// (`TelegraphDamage.telegraphDamageFlags.0x20.rows`). The phases a row fires in are
/// not read, so a spell's shapes hold for each of its gos.
fn hit_shapes_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
) -> Result(List(Placement), AreaError) {
  use rows <- result.try(
    dict.get(links, id)
    |> result.unwrap([])
    |> list.try_map(fn(link) {
      telegraph_damage.get(
        tables:,
        id: TelegraphDamageId(link.telegraph_damage_id),
      )
      |> result.replace_error(NoRow(
        table: "TelegraphDamage",
        id: link.telegraph_damage_id,
      ))
    }),
  )
  let twins =
    list.filter(rows, fn(row) {
      spell_plan.has_flag(flags: row.telegraph_damage_flags, bit: 0x40)
    })
  let chosen = case twins {
    [] -> {
      let drawn =
        list.filter(rows, fn(row) {
          !spell_plan.has_flag(flags: row.telegraph_damage_flags, bit: 0x100)
        })
      case
        list.filter(drawn, fn(row) {
          !spell_plan.has_flag(flags: row.telegraph_damage_flags, bit: 0x20)
        })
      {
        [] -> drawn
        own -> own
      }
    }
    twins -> twins
  }
  list.try_map(chosen, fn(row) { placement_of(id:, row:) })
}

fn placement_of(
  id id: Int,
  row row: telegraph_damage.TelegraphDamage,
) -> Result(Placement, AreaError) {
  use <- bool.guard(
    when: row.target_type_flags != 1,
    return: Error(TelegraphNotOnCaster(
      spell4_id: id,
      telegraph_id: row.id,
      target_type_flags: row.target_type_flags,
    )),
  )
  let not_built =
    Error(ShapeNotBuilt(
      spell4_id: id,
      telegraph_id: row.id,
      shape: row.damage_shape_enum,
    ))
  use shape <- result.try(case row.damage_shape_enum {
    0 -> Ok(Circle(radius: row.param00))
    2 -> Ok(Box(width: row.param00, length: row.param02))
    4 -> Ok(Cone(inner: row.param00, outer: row.param01, degrees: row.param02))
    7 -> Ok(Rectangle(width: row.param00, length: row.param02))
    8 ->
      case row.param03 == 0.0 && row.param05 == 0.0 {
        True ->
          Ok(Cone(inner: row.param00, outer: row.param01, degrees: row.param02))
        False -> not_built
      }
    _ -> not_built
  })
  Ok(Placement(
    shape:,
    ahead: row.z_position_offset,
    aside: row.x_position_offset,
    turn_degrees: row.rotation_degrees,
  ))
}

/// The damage effects of the spell (effect type 8), each with the unit it aims at and
/// its formula.
fn damage_effects_of(
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  id id: Int,
) -> Result(List(DamageEffect), AreaError) {
  dict.get(effects, id)
  |> result.unwrap([])
  |> list.filter(fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.Damage
  })
  |> list.try_map(fn(effect) {
    use formula <- result.try(
      damage.formula_of(effect:)
      |> result.replace_error(MultiplierNotFinite(
        spell4_id: id,
        effect_id: effect.id,
        bits: effect.data_bits00,
      )),
    )
    let aim = spell_plan.aim_of(target_flags: effect.target_flags)
    use Nil <- result.try(case aim {
      spell_plan.OtherAim(flags:) ->
        Error(AimNotRead(
          spell4_id: id,
          effect_id: effect.id,
          target_flags: flags,
        ))
      spell_plan.AimsAtCaster
      | spell_plan.AimsAtPrimaryTarget
      | AimsAtArea
      | AimsAtBoth -> Ok(Nil)
    })
    use Nil <- result.try(case damage.unread(formula:) {
      Some(damage.Unread(parameter_kind:)) ->
        Error(FormulaNotRead(
          spell4_id: id,
          effect_id: effect.id,
          parameter_kind:,
        ))
      None -> Ok(Nil)
    })
    Ok(DamageEffect(
      effect_id: Spell4EffectsId(effect.id),
      damage_type: effect.damage_type,
      delay_ms: effect.delay_time,
      phase_flags: effect.phase_flags,
      aim:,
      formula:,
      threat_multiplier: effect.threat_multiplier,
      tag: spell_plan.tag_of(effect:),
    ))
  })
}

/// What the spell's phase strikes with the effects a cast that spent `spent` points
/// chooses (genesis_prime/game/spend `applies`); the flags are worked out from the
/// effects, crowd-control states and Proxies that are left.
fn phase_of(
  spell spell: SpellArea,
  phase phase: Int,
  spent spent: Option(Int),
) -> PhaseStrike {
  let bit = spell_plan.phase_bit(phase:)
  let firing =
    list.filter(spell.damage, fn(effect) {
      spell_plan.has_flag(flags: effect.phase_flags, bit:)
      && spend.applies(tag: effect.tag, spent:)
    })
  let controls =
    spell_plan.controls_in_phase(spell: spell.spell, phase:, spent:)
  let strikes = fn(aims) {
    list.any(firing, fn(effect) { list.contains(aims, effect.aim) })
    || list.any(controls, fn(control) { list.contains(aims, control.aim) })
  }
  PhaseStrike(
    damage: list.filter(firing, fn(effect) {
      list.contains([AimsAtPrimaryTarget, AimsAtArea, AimsAtBoth], effect.aim)
    }),
    controls:,
    selects_area: strikes([AimsAtArea, AimsAtBoth])
      || list.any(
      spell_plan.proxies_in_phase(spell: spell.spell, phase:, spent:),
      fn(proxy) { proxy.target == spell_plan.OnEachStruck },
    ),
    strikes_primary_target: strikes([AimsAtPrimaryTarget, AimsAtBoth]),
  )
}

/// The areas the tables' load built.
pub fn areas(tables tables: table_store.Tables) -> Areas {
  table_store.derived(tables:, key: areas_key)
}

/// The area of the spell, or `Error(Nil)` for a spell of no level-1 ability's
/// tree.
pub fn of_spell(
  areas areas: Areas,
  spell4_id spell4_id: Spell4Id,
) -> Result(SpellArea, Nil) {
  dict.get(areas, spell4_id.value)
}

/// How a unit counts as inside the spell's area: the hit shapes when the spell has
/// any, capped by the area row's range, else the area row's range and arc.
pub fn inside(spell spell: SpellArea) -> Inside {
  case spell.shapes {
    [] -> InsideRow
    shapes -> InsideShapes(placements: shapes)
  }
}

/// How many gos the spell has, one for each phase of a Multiphase spell and one for
/// any other.
pub fn phase_count(spell spell: SpellArea) -> Int {
  int.max(1, list.length(spell.spell.phase_delays_ms))
}

/// What the spell's go of `phase` strikes when the cast spent `spent` points above
/// the base cost, or `Error(Nil)` for a phase the spell has none of: only the damage
/// effects and Proxies whose tag holds for n are kept, and the area flags follow from
/// them. A cast with no n keeps every effect.
pub fn phase(
  spell spell: SpellArea,
  phase phase: Int,
  spent spent: Option(Int),
) -> Result(PhaseStrike, Nil) {
  use <- bool.guard(
    when: phase < 0 || phase >= phase_count(spell:),
    return: Error(Nil),
  )
  Ok(phase_of(spell:, phase:, spent:))
}
