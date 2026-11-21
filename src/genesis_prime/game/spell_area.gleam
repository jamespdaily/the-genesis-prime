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
////   A phase with a damage effect, a crowd-control state, a property change of struck
////   units (a type 11 row aimed only at other units) or a Proxy aimed at the area
////   selects units; one aimed at the cast's target strikes the primary target; with
////   neither it strikes nobody and its go is written at once. A stun with no damage
////   still selects and strikes (Gate's 30436, Stagger's 38780), and so does a spell
////   holding only a property row aimed at the target (Fissure's child 41886, row 94370)
////   or the area (Defense Grid Aura 54475, rows 129039, 183223, 183224). An absorb, an
////   armor or a look row aimed at others names no creature to change and selects nobody
////   (`spell_plan.StruckChange`).
////   A damage row aimed at its caster alone (targetFlags 1) loads and strikes
////   nobody, since the phase keeps only the rows aimed past the caster; the coverage
////   measure does not count it as handled (`strikes_past_caster`).
////   No plan holds a spell with a type 11 row aimed at other units, since
////   `spell_plan.build` plans each class's level-1 tier-1 trees only, which hold none.
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
//// - **A periodic damage row** (a tickTime) strikes the units of its go once for each
////   tick of its schedule (genesis_prime/game/ticking), each tick its own 0x7f8 from the
////   server: the go selects with it as with any row, and `PhaseStrike.ticking` holds it
////   apart from the rows that strike once. A row that lasts until removed (flags bit 2)
////   is left out by the load (`TickingUntilRemoved`), and `checker` refuses a spell that holds
////   one, so no planned ability's press waits on a damage row that is never played.
//// - **Order.** Every area row of the level-1 abilities has `targetSelection`
////   1, and none strikes a dead unit (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`). A creature's special may also select Furthest (2)
////   or Random (3); orders 4 and 5 need a unit's health, which a creature's sight of a
////   fighter does not hold (`SelectionNeedsHealth`).
//// - **Two readings** read a spell's rows: a player's ability (`PlayerReading`: Closest
////   and the shapes of the level-1 trees) and a creature's special (`CreatureReading`: also
////   Furthest, Random, rings, crosses, pies and unhalved boxes), so a player's strike
////   refuses orders 2 to 5 and shapes 1, 3, 5 and 6.
//// - **Where a hit is centred** is its anchor, one for the spell (`anchor_of`): a hit row is
////   placed on the caster (`targetTypeFlags` 1) or on the cast's target (0 or 2), and drawn where
////   the cast's 0x7ff puts it and stays there (TelegraphDamage flag 0x4000 or 0x1000:
////   `FixedAtCaster`, `FixedAtTarget`) or follows its unit (`FollowsCaster`, `FollowsTarget`). A creature special whose rows, or whose hit twin and
////   drawn row, are not placed alike is refused (`PlacedApart`), so the hit is always where the
////   picture is (`0x140546e60.placement_branches`, `0x14054b1b0.fixed_placement`,
////   `0x14054b1b0.follows_caster`). A player's row placed at the position the cast holds
////   (`targetTypeFlags` 8) is `FixedAtCaster` whatever its flags: the client stores that
////   position and yaw once, when the cast starts (`0x14053a210.held_position`). A player's hit
////   rows alone decide the anchor, and a spell with none is `FollowsTarget`, struck around
////   its primary target. Nullifier 58868 (row 2789, flags 1 with 0x1000) is `FixedAtCaster`;
////   its phase holds no damage row and selects no area, so its anchor moves no strike.
//// - **Who the primary target is** follows from how the spell is started
////   (genesis_prime/game/spell_plan `Start`): the caster for a press and a Proxy on the caster,
////   another unit for a Proxy on each struck unit and a proc. A row on the target of a spell
////   started on another unit is built only as a circle with no offset, which reads no yaw
////   (`start_placed`), and a pressed spell's row on the target only when the spell is cast at
////   the caster, since the press names the caster and reads no other target
////   (`targeting_given`, `target_mechanic.kind_of`).
//// - **Which spells** are read: the spells of each level-1 ability's tree
////   (genesis_prime/game/spell_plan), its threshold stages (Spell4Thresholds) included,
////   a Proxy behind a target prerequisite excepted, since it is never started. A spell
////   with no area row selects nobody.
//// - **What fails the load:** a row the tree names that the tables lack; a
////   `targetSelection` other than 1 (a creature's: other than 1 to 3, with 4 and 5 named by
////   `SelectionNeedsHealth`); a valid-targets bitmask other than 0 on a spell
////   with an area row; a hit row placed on anything but the caster, the cast's target and the
////   held position (`targetTypeFlags` other than 0, 1, 2 and 8; for a creature other than 0 to
////   2: `TelegraphOnStruckUnits` for bit 4, else `TelegraphNotOnCaster`); a spell's hit rows
////   placed apart (`PlacedApart`); a pressed spell whose hit row is on the target and whose
////   target mechanic is not cast at the caster (`TargetingNotBuilt`); a spell started on
////   another unit whose hit row on the target is not a circle with no offset
////   (`HitRowOffTheStrikeCentre`); a shape
////   the rule does not build (for a player 1, 3, 5, 6, or 8 with
////   a box that has a width or a length: the box's height, p4, is never tested; for a
////   creature 8 with such a box alone); a damage effect
////   (type 8) aimed by a flag value not read; a formula that reads a parameter the
////   player's value does not (genesis_prime/game/damage `unread`: the weapon kinds 6
////   and 9, the passed-in value 18, and any kind above 26; the vital kinds are read,
////   the target's finished when the blow lands); and a phase that
////   selects units from a spell with no area row; a creature's drawn hit row timed from a go
////   (flag 0x2000: `TelegraphTimedFromAGo`).
//// - **Each go of a creature's cast** is struck with the hit rows its phase names that the client
////   is drawing at the go's time (`hit_shapes_by_go`, genesis_prime/game/telegraph_window); a
////   player's strike takes the spell's shapes for every go (`SpellArea.shapes`).

import genesis_prime/game/area.{
  type Anchor, type Inside, type Placement, type Row, Box, Circle, Cone,
  FixedAtCaster, FixedAtTarget, FollowsCaster, FollowsTarget, Furthest,
  InsideRow, InsideShapes, Nearest, Placement, Random, Rectangle, Row,
}
import genesis_prime/game/damage.{type Formula}
import genesis_prime/game/effect_kind
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Aim, type Spell, type Start}
import genesis_prime/game/spend
import genesis_prime/game/target_mechanic
import genesis_prime/game/telegraph_entries
import genesis_prime/game/telegraph_window
import genesis_prime/game/ticking
import genesis_prime/gap
import genesis_prime/table/id.{
  type Spell4EffectsId, type Spell4Id, Spell4AoeTargetConstraintsId,
  Spell4EffectsId, Spell4TargetMechanicsId, Spell4ValidTargetsId,
  TelegraphDamageId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_target_mechanics
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/telegraph_damage
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Whose area a spell's rows are read for: what the strike of each can take differs, since a
/// player's strike has the health of the units it shows and a creature's does not, and a
/// player's abilities (the level-1 trees) hold only the shapes and orders that
/// `PlayerReading` builds.
pub type Reading {
  /// A player's ability: Closest alone, and the circle, box, cone and rectangle shapes.
  PlayerReading
  /// A creature's special: Closest, Furthest and Random, and also the ring, cross, pie and
  /// unhalved-box shapes (`0x14054d170.shapes_1_3_5_6`).
  CreatureReading
}

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
    condition: spell_plan.Condition,
    tag: spend.Tag,
  )
}

/// A periodic damage row (a tickTime): the damage of each tick and when the ticks land.
pub type TickingDamage {
  TickingDamage(damage: DamageEffect, schedule: ticking.Schedule)
}

/// A damage row as the area reads it: one that strikes once at its go, or one that
/// strikes once for each tick.
pub type RowDamage {
  Once(effect: DamageEffect)
  Periodic(effect: TickingDamage)
}

/// What one phase of a spell strikes, for a cast that spent a given number of
/// points (`phase`).
pub type PhaseStrike {
  PhaseStrike(
    /// The damage effects that fire once in the phase and aim at the area or the
    /// cast's target.
    damage: List(DamageEffect),
    /// The periodic damage effects that fire in the phase and aim at the area or the
    /// cast's target: each strikes the units of the go at each of its ticks.
    ticking: List(TickingDamage),
    /// The crowd-control states that fire in the phase, which aim at the area, the
    /// cast's target or both.
    controls: List(spell_plan.CrowdControl),
    /// The target apply prerequisites of the rows of the phase aimed past the caster that
    /// the struck creature checks (`spell_plan.StruckGate`), whatever the row does: the
    /// strike tells each unit a gate's aim names the gate, so a phase with a gated go row
    /// and nothing else still strikes.
    gates: List(spell_plan.StruckGate),
    /// Whether the phase selects units from the area: a damage effect (periodic or
    /// not), a crowd-control state or a property change of struck units aimed at the area, or a
    /// Proxy that starts its spell on each struck unit (genesis_prime/game/spell_plan
    /// `OnEachStruck`).
    selects_area: Bool,
    /// Whether the phase strikes the cast's own target: a damage effect (periodic or
    /// not), a crowd-control state or a property change of struck units aimed at it.
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
    /// Where the hit is centred, one for the spell, from its hit rows (`anchor_of`):
    /// `FollowsTarget` for a spell with none, which strikes around its primary target.
    anchor: Anchor,
    /// Every damage effect of the spell that strikes once, each with its tag.
    damage: List(DamageEffect),
    /// Every periodic damage effect of the spell, each with its schedule; a row that
    /// lasts until removed (`TickingUntilRemoved`) is not among them.
    ticking: List(TickingDamage),
    /// The spell as the plan holds it, whose Proxies aimed at each struck unit
    /// make a phase select the area.
    spell: Spell,
  )
}

/// Why the areas cannot be built from the tables. Every error but `TickingUntilRemoved`
/// fails the area load; a periodic row that lasts until removed is left out of its
/// spell's area, and `checker` refuses the spell.
pub type AreaError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// A spell strikes an area in one of its phases but names no area row.
  NoAreaRow(spell4_id: Int)
  /// An area row selects in an order the reading does not build (a player's: not Closest, 1;
  /// a creature's: not 1 to 3 and not 4 or 5).
  SelectionNotBuilt(spell4_id: Int, target_selection: Int)
  /// A creature's area row selects by a unit's health (`targetSelection` 4,
  /// LowestAbsoluteHealth, or 5, MissingMostHealth), which its sight of a fighter lacks.
  SelectionNeedsHealth(spell4_id: Int, target_selection: Int)
  /// A spell's valid targets hold a bit: it would strike the dead or more.
  ValidTargetsNotAlive(spell4_id: Int, target_bitmask: Int)
  /// A hit row is placed on what the reading does not build: for a player's ability anything
  /// but the caster, the cast's target and the position the cast holds (`targetTypeFlags` other
  /// than 0, 1, 2 and 8); for a creature's special the ground (bit 8) or two units at once (3, 9).
  TelegraphNotOnCaster(
    spell4_id: Int,
    telegraph_id: Int,
    target_type_flags: Int,
  )
  /// A creature special's hit row is placed on each unit the strike finds (`targetTypeFlags`
  /// bit 4): the client makes a circle for each unit of the go's list, which the cast cannot
  /// know when it starts.
  TelegraphOnStruckUnits(
    spell4_id: Int,
    telegraph_id: Int,
    target_type_flags: Int,
  )
  /// A pressed spell's hit row is placed on the cast's target (`targetTypeFlags` 0 or 2) but
  /// the spell's target mechanic is not one that names the caster: the press does not read the
  /// player's target (`kind` is `Targeted`, `Ground` or `Unread`), so the hit would land on the
  /// caster.
  TargetingNotBuilt(spell4_id: Int, kind: target_mechanic.Kind)
  /// A hit row placed on the cast's target is not centred on the unit the strike centres on:
  /// the spell is started on a unit that is not its caster (`start`), the strike knows that
  /// unit's place and no facing, and the row's shape is turned or moved by the unit's facing.
  HitRowOffTheStrikeCentre(spell4_id: Int, start: Start)
  /// A hit row's shape is not one the rule builds.
  ShapeNotBuilt(spell4_id: Int, telegraph_id: Int, shape: Int)
  /// A creature special's rows are placed apart, so no one centre is where the picture is:
  /// one on the caster and another on the target, one drawn where the cast started (flag
  /// 0x4000 or 0x1000) and another following its unit, or a hit twin (flag 0x40) placed
  /// otherwise than the drawn row. `telegraph_id` is the first hit row and `other_telegraph_id`
  /// the first row placed otherwise.
  PlacedApart(spell4_id: Int, telegraph_id: Int, other_telegraph_id: Int)
  /// A drawn hit row is timed from a phase's go instead of the cast's start (flag 0x2000), a
  /// window the creature reading does not build.
  TelegraphTimedFromAGo(spell4_id: Int, telegraph_id: Int)
  /// A damage effect is aimed by a flag value not read.
  AimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A damage effect's formula reads a parameter a player's value does not.
  FormulaNotRead(spell4_id: Int, effect_id: Int, parameter_kind: Int)
  /// A periodic damage effect lasts until removed (flags bit 2), which no schedule
  /// ends: the load leaves the row out, `checker` refuses its spell and the coverage measure
  /// counts it as not read.
  TickingUntilRemoved(spell4_id: Int, effect_id: Int)
  /// A periodic damage effect lives shorter than one tick (genesis_prime/game/ticking
  /// `NoTick`).
  TickingNoTick(spell4_id: Int, effect_id: Int, tick_ms: Int, duration_ms: Int)
  /// A damage effect's multiplier (`dataBits00`, read as 32 bits) is an infinity or a
  /// number that is not one.
  MultiplierNotFinite(spell4_id: Int, effect_id: Int, bits: Int)
  /// A damage effect is behind an apply prerequisite the strike cannot check for the units
  /// it reaches (`spell_plan.row_condition_of`).
  ApplyGateNotRead(error: spell_plan.PlanError)
}

/// A sentence that says why the areas cannot be built, naming the table, the
/// spell and the row, for the message a failed area load stops the server with.
pub fn describe(error error: AreaError) -> String {
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
    SelectionNotBuilt(spell4_id:, target_selection:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an area row that selects in order "
      <> int.to_string(target_selection)
      <> ", which is not built (a player's ability takes Closest, 1; a creature's special 1 to 3)"
    SelectionNeedsHealth(spell4_id:, target_selection:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an area row that selects in order "
      <> int.to_string(target_selection)
      <> ", by a unit's health, which a creature's sight of a fighter does not hold"
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
      <> ", and only the caster (1), the cast's target (0 and 2) and the cast's start position (8) are built for a player, the caster and the cast's target (0 to 2) for a creature"
    TargetingNotBuilt(spell4_id:, kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph placed on the cast's target and is cast at "
      <> case kind {
        target_mechanic.Caster -> "the caster"
        target_mechanic.Targeted -> "a unit the cast names"
        target_mechanic.Ground -> "a place on the ground"
        target_mechanic.Unread(target_type:) ->
          "a target of kind " <> int.to_string(target_type)
      }
      <> ", and the press does not read its target"
    HitRowOffTheStrikeCentre(spell4_id:, start:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph placed on the cast's target and is started "
      <> case start {
        spell_plan.Pressed -> "by a press"
        spell_plan.Proxied(target: spell_plan.OnCaster) -> "on the caster"
        spell_plan.Proxied(target: spell_plan.OnEachStruck) ->
          "on each struck unit"
        spell_plan.FromProc -> "by a proc"
      }
      <> ", on a unit whose facing the strike does not know, and the row's shape is not a circle at that unit's place"
    TelegraphOnStruckUnits(spell4_id:, telegraph_id:, target_type_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph "
      <> int.to_string(telegraph_id)
      <> " placed by flags "
      <> int.to_string(target_type_flags)
      <> ", on each unit the strike finds, which the cast cannot know when it starts"
    ShapeNotBuilt(spell4_id:, telegraph_id:, shape:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph "
      <> int.to_string(telegraph_id)
      <> " of shape "
      <> int.to_string(shape)
      <> ", which is not built"
    PlacedApart(spell4_id:, telegraph_id:, other_telegraph_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a telegraph "
      <> int.to_string(telegraph_id)
      <> " and another, "
      <> int.to_string(other_telegraph_id)
      <> ", placed on another unit or drawn another way (at the cast's start, or following its unit), which no one centre serves"
    TelegraphTimedFromAGo(spell4_id:, telegraph_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a hit telegraph "
      <> int.to_string(telegraph_id)
      <> " timed from a go (flag 0x2000), a window the load does not read"
    AimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a damage effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", "
      <> spell_plan.aim_values_read_text(target_flags:)
    FormulaNotRead(spell4_id:, effect_id:, parameter_kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a damage effect "
      <> int.to_string(effect_id)
      <> " whose formula reads parameter type "
      <> int.to_string(parameter_kind)
      <> ", which a player's value does not"
    TickingUntilRemoved(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a periodic damage effect "
      <> int.to_string(effect_id)
      <> " that lasts until removed, which is not read"
    TickingNoTick(spell4_id:, effect_id:, tick_ms:, duration_ms:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a periodic damage effect "
      <> int.to_string(effect_id)
      <> " with a tickTime of "
      <> int.to_string(tick_ms)
      <> " and a durationTime of "
      <> int.to_string(duration_ms)
      <> ", shorter than one tick"
    ApplyGateNotRead(error:) -> spell_plan.describe(error:)
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
/// missing row or an area the rule does not build fails the load, and a periodic damage
/// row is left out of its spell's area.
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
  let started =
    dict.values(spell_plan.plans_with_later(tables:))
    |> list.flat_map(spells_of_tree)
  let effects = spell_plan.effects_by_spell(tables:)
  let links = telegraph_links_by_spell(tables:)
  list.try_fold(started, dict.new(), fn(areas, started) {
    let #(spell, start) = started
    let id = spell.spell4_id.value
    use area <- result.try(case dict.get(areas, id) {
      Ok(area) -> Ok(area)
      Error(Nil) -> area_of(tables:, effects:, links:, spell:)
    })
    use Nil <- result.map(start_checked(tables:, area:, start:))
    dict.insert(areas, id, area)
  })
}

/// What a later ability's spells must pass to be planned (genesis_prime/game/spell_plan
/// `Checker`): the area of each is built as `build` builds it, and an error of what the
/// rule does not build leaves the ability out of the plans, so no ability holds a
/// spell the load of the areas would refuse.
pub fn checker(tables tables: table_store.Tables) -> spell_plan.Checker {
  let effects = spell_plan.effects_by_spell(tables:)
  let links = telegraph_links_by_spell(tables:)
  fn(spell: Spell, start: Start) {
    let id = spell.spell4_id.value
    area_of(tables:, effects:, links:, spell:)
    |> result.try(fn(area) { start_checked(tables:, area:, start:) })
    |> result.try(fn(_) {
      case until_removed_damage_row_of(tables:, effects:, id:) {
        Some(error) -> Error(error)
        None -> Ok(Nil)
      }
    })
    |> result.map_error(plan_error_of(error: _, spell4_id: id))
  }
}

/// An area error as the plan's: the one inside an apply gate as itself, a missing row or a
/// number that is no number as a fault of the data, and the rest as what the area rule
/// does not build.
fn plan_error_of(
  error error: AreaError,
  spell4_id spell4_id: Int,
) -> spell_plan.PlanError {
  case error {
    ApplyGateNotRead(error: inner) -> inner
    NoRow(..) | NoAreaRow(..) | MultiplierNotFinite(..) ->
      spell_plan.AreaDataFault(spell4_id:, reason: describe(error:))
    SelectionNotBuilt(..)
    | SelectionNeedsHealth(..)
    | ValidTargetsNotAlive(..)
    | TelegraphNotOnCaster(..)
    | TargetingNotBuilt(..)
    | HitRowOffTheStrikeCentre(..)
    | TelegraphOnStruckUnits(..)
    | ShapeNotBuilt(..)
    | PlacedApart(..)
    | TelegraphTimedFromAGo(..)
    | AimNotRead(..)
    | FormulaNotRead(..)
    | TickingUntilRemoved(..)
    | TickingNoTick(..) ->
      spell_plan.AreaNotBuilt(spell4_id:, reason: describe(error:))
  }
}

/// The spell, the stage spells a RapidTap or ChargeRelease ability casts and every
/// spell the Proxies of any of them start, below them, each with how it is started. A Proxy
/// behind a prerequisite may start its child, so the child is read: one behind a target
/// prerequisite starts it on a unit that passes (genesis_prime/game/spell_plan
/// `GatedOnCasterAndTarget`).
fn spells_of_tree(spell: Spell) -> List(#(Spell, Start)) {
  spell_plan.tree_started(spell:, started: fn(_) { True })
}

/// Whether a spell with an area row, started as `start`, strikes where its hit is drawn
/// (`start_placed`) and, pressed, is cast at what its hit row is placed on (`targeting_given`).
fn start_checked(
  tables tables: table_store.Tables,
  area area: SpellArea,
  start start: Start,
) -> Result(Nil, AreaError) {
  case area.row {
    None -> Ok(Nil)
    Some(_) ->
      case start_placed(anchor: area.anchor, start:, shapes: area.shapes) {
        False ->
          Error(HitRowOffTheStrikeCentre(
            spell4_id: area.spell4_id.value,
            start:,
          ))
        True -> targeting_given(tables:, area:, start:)
      }
  }
}

/// Whether the strike centres a spell started as `start` where its hit rows are drawn. A
/// press and a Proxy on the caster have the caster as their primary target, so every anchor is
/// the caster's place. A spell started on a struck unit or by a proc has another unit as its
/// primary target, whose place the strike knows and whose yaw it does not (`strike.select`: yaw
/// 0.0): a row on the caster is centred on the caster, and a row on the target only when every
/// hit shape is a circle with no offset, which reads no yaw (`area.in_shape`; a turned circle is
/// the same circle). Any other shape of a row on the target is turned or moved by the unit's
/// facing on the client (`0x14054b1b0.follows_caster`).
pub fn start_placed(
  anchor anchor: Anchor,
  start start: Start,
  shapes shapes: List(Placement),
) -> Bool {
  case start {
    spell_plan.Pressed | spell_plan.Proxied(target: spell_plan.OnCaster) -> True
    spell_plan.Proxied(target: spell_plan.OnEachStruck) | spell_plan.FromProc ->
      case anchor {
        FollowsCaster | FixedAtCaster -> True
        FollowsTarget | FixedAtTarget -> list.all(shapes, is_plain_circle)
      }
  }
}

/// Whether the placement is a circle on its unit's own place.
fn is_plain_circle(placement placement: Placement) -> Bool {
  case placement {
    Placement(shape: Circle(..), ahead: 0.0, aside: 0.0, ..) -> True
    Placement(..) -> False
  }
}

/// The refusal of a pressed spell whose hit row is placed on the cast's target but whose target
/// mechanic is not cast at the caster: the press names the caster as the primary target
/// (`cast` `press_of`) and does not read the player's target or a spot (0x9b), so the hit would
/// land on the caster. A spell with no hit row and every other start are built.
fn targeting_given(
  tables tables: table_store.Tables,
  area area: SpellArea,
  start start: Start,
) -> Result(Nil, AreaError) {
  case start, placed_on_the_target(area:) {
    spell_plan.Pressed, True -> {
      use kind <- result.try(target_kind_of(tables:, spell: area.spell))
      case kind {
        target_mechanic.Caster -> Ok(Nil)
        target_mechanic.Targeted
        | target_mechanic.Ground
        | target_mechanic.Unread(..) ->
          Error(TargetingNotBuilt(spell4_id: area.spell4_id.value, kind:))
      }
    }
    spell_plan.Pressed, False
    | spell_plan.Proxied(..), _
    | spell_plan.FromProc, _
    -> Ok(Nil)
  }
}

/// Whether the spell has a hit row and it is placed on the cast's target: a spell with no hit
/// row has no shapes and is centred on its primary target only by default.
fn placed_on_the_target(area area: SpellArea) -> Bool {
  case area.shapes, area.anchor {
    [], _ -> False
    [_, ..], FollowsTarget | [_, ..], FixedAtTarget -> True
    [_, ..], FollowsCaster | [_, ..], FixedAtCaster -> False
  }
}

/// The kind of the target mechanic the spell's Spell4Base names.
fn target_kind_of(
  tables tables: table_store.Tables,
  spell spell: Spell,
) -> Result(target_mechanic.Kind, AreaError) {
  use base <- result.try(
    spell4_base.get(tables:, id: spell.spell4_base_id)
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: spell.spell4_base_id.value,
    )),
  )
  spell4_target_mechanics.get(
    tables:,
    id: Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
  )
  |> result.map(target_mechanic.of_row)
  |> result.replace_error(NoRow(
    table: "Spell4TargetMechanics",
    id: base.spell4_target_mechanic_id,
  ))
}

/// The Spell4Telegraph rows of each spell, in table order, grouped once.
pub fn telegraph_links_by_spell(
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
  use area_row <- result.try(area_row_of(
    tables:,
    id:,
    row:,
    reading: PlayerReading,
  ))
  use Nil <- result.try(case area_row {
    Some(..) -> valid_targets_checked(tables:, id:, base:)
    None -> Ok(Nil)
  })
  use shapes <- result.try(hit_shapes_of(
    tables:,
    links:,
    id:,
    reading: PlayerReading,
  ))
  use anchor <- result.try(anchor_of(
    tables:,
    links:,
    id:,
    reading: PlayerReading,
  ))
  use #(damage, ticking) <- result.try(damage_effects_of(tables:, effects:, id:))
  let area =
    SpellArea(
      spell4_id: spell.spell4_id,
      row: area_row,
      shapes:,
      anchor:,
      damage:,
      ticking:,
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
  reading reading: Reading,
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
      let row_of = fn(order) {
        Ok(
          Some(Row(
            min_range: constraints.min_range,
            max_range: constraints.max_range,
            degrees: constraints.angle,
            target_count: constraints.target_count,
            order:,
          )),
        )
      }
      case constraints.target_selection, reading {
        1, PlayerReading | 1, CreatureReading -> row_of(Nearest)
        2, CreatureReading -> row_of(Furthest)
        3, CreatureReading -> row_of(Random)
        4, CreatureReading | 5, CreatureReading ->
          Error(SelectionNeedsHealth(
            spell4_id: id,
            target_selection: constraints.target_selection,
          ))
        selection, PlayerReading | selection, CreatureReading ->
          Error(SelectionNotBuilt(spell4_id: id, target_selection: selection))
      }
    }
  }
}

/// The telegraph rows of the spell that say who is hit: the never-drawn twins (flag
/// 0x40), or the rows drawn when it has none, less the drawn rows with bit 0x20, which
/// are pictures of another spell's hit shape (a spell's own copy of its child's beam),
/// unless every drawn row has it: then they are all kept
/// (`TelegraphDamage.telegraphDamageFlags.0x20.rows`). The phases a row fires in are
/// not read here: `SpellArea.shapes` holds for each of a player's gos, and a creature's cast
/// takes them go by go (`hit_shapes_by_go`). A Spell4Telegraph row whose
/// TelegraphDamage row the table lacks gives no shape, as the client leaves it out of its
/// spell's telegraphs (`Spell4Telegraph.telegraphDamageId.no_row`). The shapes of the
/// spell `id` that its Spell4Telegraph rows in `links` choose, or the refusal of one; a row
/// of a shape that is two boxes gives two.
pub fn hit_shapes_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
  reading reading: Reading,
) -> Result(List(Placement), AreaError) {
  list.try_map(hit_rows_of(tables:, links:, id:), fn(row) {
    placements_of(id:, row:, reading:)
  })
  |> result.map(list.flatten)
}

/// The TelegraphDamage rows the spell `id`'s Spell4Telegraph rows name, in the table's order;
/// a link to a row the table lacks gives none.
fn linked_rows_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
) -> List(telegraph_damage.TelegraphDamage) {
  dict.get(links, id)
  |> result.unwrap([])
  |> list.filter_map(fn(link) {
    telegraph_damage.get(
      tables:,
      id: TelegraphDamageId(link.telegraph_damage_id),
    )
  })
}

/// The TelegraphDamage rows of the spell `id` that say who is hit, as `hit_shapes_of`
/// chooses them.
fn hit_rows_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
) -> List(telegraph_damage.TelegraphDamage) {
  hit_rows_among(rows: linked_rows_of(tables:, links:, id:))
}

/// Whether the row is a never-drawn twin (flag 0x40) that says who is hit in place of a
/// drawn row.
fn is_twin(row row: telegraph_damage.TelegraphDamage) -> Bool {
  spell_effect.has_flag(flags: row.telegraph_damage_flags, bit: 0x40)
}

/// The rows among a spell's linked rows that say who is hit: its twins, else its drawn rows
/// (`telegraph_entries.drawn_rows`) less those with bit 0x20 unless all have it.
fn hit_rows_among(
  rows rows: List(telegraph_damage.TelegraphDamage),
) -> List(telegraph_damage.TelegraphDamage) {
  case list.filter(rows, is_twin) {
    [] -> {
      let drawn = telegraph_entries.drawn_rows(rows:)
      case
        list.filter(drawn, fn(row) {
          !spell_effect.has_flag(flags: row.telegraph_damage_flags, bit: 0x20)
        })
      {
        [] -> drawn
        own -> own
      }
    }
    twins -> twins
  }
}

/// What a row the reading builds is placed on: the caster, the cast's target or, for a
/// player, the position and facing the cast holds from its start.
type Role {
  OnTheCaster
  OnTheTarget
  OnTheStart
}

/// What a row is placed on, or `Error(Nil)` for flags the reading builds no anchor for: the
/// caster for 1, the cast's target for 0 and 2, and the position the cast holds for 8 (a
/// player's only) (`0x140546e60.placement_branches`: the client-placed target is the cast's
/// unit when the flags are 0 or have bit 2).
fn role_of(
  target_type_flags target_type_flags: Int,
  reading reading: Reading,
) -> Result(Role, Nil) {
  case reading, target_type_flags {
    PlayerReading, 1 | CreatureReading, 1 -> Ok(OnTheCaster)
    PlayerReading, 8 -> Ok(OnTheStart)
    PlayerReading, 0
    | PlayerReading, 2
    | CreatureReading, 0
    | CreatureReading, 2
    -> Ok(OnTheTarget)
    PlayerReading, _ | CreatureReading, _ -> Error(Nil)
  }
}

/// What a hit row is placed on, or the refusal of a row the reading does not build: for a
/// creature a row on each struck unit (bit 4) is refused by name, since the cast cannot know
/// them when it starts, and the ground (bit 8) or two units at once (3, 9) as not on the
/// caster; for a player anything but the caster, the cast's target and the position the cast
/// holds (`0x140546e60.placement_branches`).
fn placed_on_a_unit_built(
  id id: Int,
  row row: telegraph_damage.TelegraphDamage,
  reading reading: Reading,
) -> Result(Role, AreaError) {
  let flags = row.target_type_flags
  case role_of(target_type_flags: flags, reading:) {
    Ok(role) -> Ok(role)
    Error(Nil) ->
      case reading, spell_effect.has_flag(flags:, bit: 4) {
        CreatureReading, True ->
          Error(TelegraphOnStruckUnits(
            spell4_id: id,
            telegraph_id: row.id,
            target_type_flags: flags,
          ))
        CreatureReading, False | PlayerReading, _ ->
          Error(TelegraphNotOnCaster(
            spell4_id: id,
            telegraph_id: row.id,
            target_type_flags: flags,
          ))
      }
  }
}

/// The anchor one row gives: its unit, and fixed where the 0x7ff puts it (flag 0x4000 or
/// 0x1000) or following the unit each frame (`0x14054b1b0.fixed_placement`,
/// `0x14054b1b0.follows_caster`); a row at the position the cast holds is fixed whatever its
/// placing flags (`0x14053a210.held_position`).
fn anchor_of_row(
  row row: telegraph_damage.TelegraphDamage,
  role role: Role,
) -> Anchor {
  case role, telegraph_entries.placing_of(flags: row.telegraph_damage_flags) {
    OnTheStart, _ -> FixedAtCaster
    OnTheCaster, telegraph_entries.OnTheUnit -> FollowsCaster
    OnTheCaster, telegraph_entries.AtInitialPosition
    | OnTheCaster, telegraph_entries.AtTelegraphPosition
    -> FixedAtCaster
    OnTheTarget, telegraph_entries.OnTheUnit -> FollowsTarget
    OnTheTarget, telegraph_entries.AtInitialPosition
    | OnTheTarget, telegraph_entries.AtTelegraphPosition
    -> FixedAtTarget
  }
}

/// The anchor a row gives, or the refusal of a row on units the reading does not build
/// (`placed_on_a_unit_built`).
fn anchored(
  id id: Int,
  row row: telegraph_damage.TelegraphDamage,
  reading reading: Reading,
) -> Result(Anchor, AreaError) {
  use role <- result.map(placed_on_a_unit_built(id:, row:, reading:))
  anchor_of_row(row:, role:)
}

/// Where the hit rows of the spell `id` are drawn, so where its hit is centred: the anchor its
/// rows give (`anchor_of_row`), for a spell with none `FollowsCaster` for a creature's and
/// `FollowsTarget` for a player's (the primary target, as a spell with no hit row strikes
/// around it). When the hit rows give different anchors, no one centre is where the picture is:
/// `PlacedApart` names the first hit row and the first row that differs from it. A creature's
/// hit twin (flag 0x40, never drawn) must also give the anchor of the rows the client draws
/// (`telegraph_entries.drawn_rows`), and a drawn row beside a twin is refused like a hit row
/// when it is on units the reading does not build; a player's drawn rows are not compared with
/// its hit rows (`gaps`).
fn anchor_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
  reading reading: Reading,
) -> Result(Anchor, AreaError) {
  let linked = linked_rows_of(tables:, links:, id:)
  let hit_rows = hit_rows_among(rows: linked)
  case hit_rows {
    [] ->
      Ok(case reading {
        PlayerReading -> FollowsTarget
        CreatureReading -> FollowsCaster
      })
    [first, ..] -> {
      use anchor <- result.try(anchored(id:, row: first, reading:))
      let drawn = case reading, list.any(hit_rows, is_twin) {
        CreatureReading, True -> telegraph_entries.drawn_rows(rows: linked)
        CreatureReading, False | PlayerReading, _ -> []
      }
      use others <- result.try(
        list.try_map(list.append(hit_rows, drawn), fn(row) {
          use found <- result.map(anchored(id:, row:, reading:))
          #(row, found)
        }),
      )
      case list.find(others, fn(other) { other.1 != anchor }) {
        Ok(#(other, _)) ->
          Error(PlacedApart(
            spell4_id: id,
            telegraph_id: first.id,
            other_telegraph_id: other.id,
          ))
        Error(Nil) -> Ok(anchor)
      }
    }
  }
}

/// The placements of a hit row: its shape from the client's drawing (`0x14054d170`, case
/// by case), each on the row's offset and turn. A player's reading builds the circle (0), box
/// (2), cone (4), rectangle (7) and a long cone (8) with no box; a creature's also the ring
/// (1), the cross (3, two boxes), the pie (5) and the unhalved box (6). A shape 8 with a box
/// is refused for both: its box's geometry is not read.
fn placements_of(
  id id: Int,
  row row: telegraph_damage.TelegraphDamage,
  reading reading: Reading,
) -> Result(List(Placement), AreaError) {
  use _role <- result.try(placed_on_a_unit_built(id:, row:, reading:))
  let not_built =
    Error(ShapeNotBuilt(
      spell4_id: id,
      telegraph_id: row.id,
      shape: row.damage_shape_enum,
    ))
  let placed = fn(shape, turn_degrees) {
    Placement(
      shape:,
      ahead: row.z_position_offset,
      aside: row.x_position_offset,
      turn_degrees:,
    )
  }
  let turn = row.rotation_degrees
  let cone = fn(degrees) {
    Cone(inner: row.param00, outer: row.param01, degrees:)
  }
  case row.damage_shape_enum, reading {
    0, PlayerReading | 0, CreatureReading ->
      Ok([placed(Circle(radius: row.param00), turn)])
    2, PlayerReading | 2, CreatureReading ->
      Ok([placed(Box(width: row.param00, length: row.param02), turn)])
    4, PlayerReading | 4, CreatureReading ->
      Ok([placed(cone(row.param02), turn)])
    7, PlayerReading | 7, CreatureReading ->
      Ok([placed(Rectangle(width: row.param00, length: row.param02), turn)])
    8, PlayerReading | 8, CreatureReading ->
      case row.param03 == 0.0 && row.param05 == 0.0 {
        True -> Ok([placed(cone(row.param02), turn)])
        False -> not_built
      }
    1, CreatureReading -> Ok([placed(cone(360.0), turn)])
    3, CreatureReading ->
      Ok([
        placed(Box(width: row.param00, length: row.param02), turn),
        placed(Box(width: row.param02, length: row.param00), turn),
      ])
    5, CreatureReading ->
      Ok([
        placed(
          cone(float.clamp(360.0 -. row.param02, min: 0.0, max: 360.0)),
          turn +. 180.0,
        ),
      ])
    6, CreatureReading ->
      Ok([
        placed(Box(width: 2.0 *. row.param00, length: 2.0 *. row.param02), turn),
      ])
    _, PlayerReading | _, CreatureReading -> not_built
  }
}

/// The damage rows of the spell (effect type 8), each read by `damage_row_of`.
fn damage_rows_of(
  tables tables: table_store.Tables,
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  id id: Int,
) -> List(Result(RowDamage, AreaError)) {
  dict.get(effects, id)
  |> result.unwrap([])
  |> list.filter(fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.Damage
  })
  |> list.map(fn(effect) { damage_row_of(tables:, spell4_id: id, effect:) })
}

/// The first damage row of the spell that lasts until removed (`TickingUntilRemoved`), which
/// the area load leaves out and `checker` refuses.
fn until_removed_damage_row_of(
  tables tables: table_store.Tables,
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  id id: Int,
) -> Option(AreaError) {
  damage_rows_of(tables:, effects:, id:)
  |> list.find_map(fn(row) {
    case row {
      Error(TickingUntilRemoved(..) as error) -> Ok(error)
      Ok(_) | Error(_) -> Error(Nil)
    }
  })
  |> option.from_result
}

/// The damage effects of the spell (effect type 8), each with the unit it aims at and
/// its formula: those that strike once, and the periodic ones with their schedules. A
/// periodic row that lasts until removed (`TickingUntilRemoved`) is left out and the
/// load goes on; any other refusal fails it.
fn damage_effects_of(
  tables tables: table_store.Tables,
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  id id: Int,
) -> Result(#(List(DamageEffect), List(TickingDamage)), AreaError) {
  damage_rows_of(tables:, effects:, id:)
  |> list.try_map(fn(row) {
    case row {
      Ok(row) -> Ok(Some(row))
      Error(TickingUntilRemoved(..)) -> Ok(None)
      Error(error) -> Error(error)
    }
  })
  |> result.map(fn(rows) {
    let rows = option.values(rows)
    #(
      list.filter_map(rows, fn(row) {
        case row {
          Once(effect:) -> Ok(effect)
          Periodic(..) -> Error(Nil)
        }
      }),
      list.filter_map(rows, fn(row) {
        case row {
          Periodic(effect:) -> Ok(effect)
          Once(..) -> Error(Nil)
        }
      }),
    )
  })
}

/// One damage row (effect type 8) of the spell `spell4_id` as a damage effect, or the error
/// that refuses it: its dataBits00 must be a finite 32-bit float, its targetFlags one the
/// rule aims by (1 to 7), its formula must read only the parameter types a player's
/// value reads (genesis_prime/game/damage `unread`). A row with a tickTime is periodic,
/// with the schedule of its ticks (genesis_prime/game/ticking `schedule_of`), read before
/// its apply gates so that an until-removed row is left out whatever its gates are. Every
/// refusal but `TickingUntilRemoved` fails the area load, and `TickingUntilRemoved`
/// leaves the row out. The area load and the coverage measure both read a row through it.
pub fn damage_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowDamage, AreaError) {
  use formula <- result.try(
    damage.formula_of(effect:)
    |> result.replace_error(MultiplierNotFinite(
      spell4_id:,
      effect_id: effect.id,
      bits: effect.data_bits00,
    )),
  )
  use aim <- result.try(
    spell_plan.aim_of(target_flags: effect.target_flags)
    |> result.replace_error(AimNotRead(
      spell4_id:,
      effect_id: effect.id,
      target_flags: effect.target_flags,
    )),
  )
  use Nil <- result.try(case damage.unread(formula:) {
    Some(damage.Unread(parameter_kind:)) ->
      Error(FormulaNotRead(spell4_id:, effect_id: effect.id, parameter_kind:))
    None -> Ok(Nil)
  })
  use schedule <- result.try(case effect.tick_time {
    0 -> Ok(None)
    tick_ms ->
      ticking.schedule_of(row: spell_plan.lasting_row_of(effect:), tick_ms:)
      |> result.map(Some)
      |> result.map_error(fn(error) {
        case error {
          ticking.UntilRemoved ->
            TickingUntilRemoved(spell4_id:, effect_id: effect.id)
          ticking.NoTick(tick_ms:, duration_ms:) ->
            TickingNoTick(
              spell4_id:,
              effect_id: effect.id,
              tick_ms:,
              duration_ms:,
            )
        }
      })
  })
  use condition <- result.map(
    spell_plan.row_condition_of(tables:, effect:, aim:)
    |> result.map_error(ApplyGateNotRead),
  )
  let damage =
    DamageEffect(
      effect_id: Spell4EffectsId(effect.id),
      damage_type: effect.damage_type,
      delay_ms: effect.delay_time,
      phase_flags: effect.phase_flags,
      aim:,
      formula:,
      threat_multiplier: effect.threat_multiplier,
      condition:,
      tag: spell_plan.tag_of(effect:),
    )
  case schedule {
    None -> Once(effect: damage)
    Some(schedule) -> Periodic(effect: TickingDamage(damage:, schedule:))
  }
}

/// What the spell's phase strikes with the effects a cast that spent `spent` points
/// chooses (genesis_prime/game/spend `applies`); the flags are worked out from the
/// effects, crowd-control states, property changes, throws, despawns and unit states of
/// struck units and Proxies that are left.
fn phase_of(
  spell spell: SpellArea,
  phase phase: Int,
  spent spent: Option(Int),
) -> PhaseStrike {
  let fires = fn(effect: DamageEffect) {
    spell_effect.names_phase(phase_flags: effect.phase_flags, phase:)
    && spend.applies(tag: effect.tag, spent:)
  }
  let firing = list.filter(spell.damage, fires)
  let ticking_firing = list.filter(spell.ticking, fn(row) { fires(row.damage) })
  let controls =
    spell_plan.controls_in_phase(spell: spell.spell, phase:, spent:)
  let changes =
    list.filter_map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_modifier,
      ),
      fn(modifier) {
        case modifier.change {
          spell_plan.StruckChange(aim:, ..) -> Ok(aim)
          spell_plan.PropertyChange(..)
          | spell_plan.LookChange(..)
          | spell_plan.AbsorbChange(..) -> Error(Nil)
        }
      },
    )
  let throws =
    list.map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_struck_move,
      ),
      fn(move) { move.aim },
    )
  let despawns =
    list.map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_despawn,
      ),
      fn(despawn) { despawn.aim },
    )
  let unit_states =
    list.map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_unit_state,
      ),
      fn(unit_state) { unit_state.aim },
    )
  let gates =
    spell_plan.struck_gates_in_phase(spell: spell.spell, phase:, spent:)
  let strikes = fn(reaches: fn(Aim) -> Bool) {
    list.any(firing, fn(effect) { reaches(effect.aim) })
    || list.any(gates, fn(gate) { reaches(gate.aim) })
    || list.any(throws, reaches)
    || list.any(despawns, reaches)
    || list.any(unit_states, reaches)
    || list.any(ticking_firing, fn(row) { reaches(row.damage.aim) })
    || list.any(controls, fn(control) { reaches(control.aim) })
    || list.any(changes, reaches)
  }
  PhaseStrike(
    damage: list.filter(firing, fn(effect) {
      spell_plan.reaches_past_caster(aim: effect.aim)
    }),
    ticking: list.filter(ticking_firing, fn(row) {
      spell_plan.reaches_past_caster(aim: row.damage.aim)
    }),
    controls:,
    gates:,
    selects_area: strikes(fn(aim) { spell_plan.reaches_area(aim:) })
      || list.any(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_proxy,
      ),
      fn(proxy) { proxy.target == spell_plan.OnEachStruck },
    ),
    strikes_primary_target: strikes(fn(aim) {
      spell_plan.reaches_primary_target(aim:)
    }),
  )
}

/// Whether the row strikes a unit but its caster. A row aimed at its caster alone loads
/// and strikes nobody, because a damage row never strikes its own caster, so the
/// coverage measure does not count it as handled.
pub fn strikes_past_caster(row row: RowDamage) -> Bool {
  case row {
    Once(effect:) -> spell_plan.reaches_past_caster(aim: effect.aim)
    Periodic(effect:) -> spell_plan.reaches_past_caster(aim: effect.damage.aim)
  }
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
  inside_of(shapes: spell.shapes)
}

fn inside_of(shapes shapes: List(Placement)) -> Inside {
  case shapes {
    [] -> InsideRow
    shapes -> InsideShapes(placements: shapes)
  }
}

/// What a creature's spell strikes: the area row, how a unit counts as inside it (the same
/// pair a player's cast selects by, `inside`) and the anchor its hit is centred by.
pub type CreatureArea {
  CreatureArea(row: Row, inside: Inside, anchor: Anchor)
}

/// The area of a spell read from its own rows, for a spell no player's ability tree
/// holds, such as a creature's charge. `None` for a spell with no
/// `Spell4AoeTargetConstraints` row. A row the tables lack, a shape the rule does not
/// build, or hit rows placed apart, is the refusal.
pub fn area_of_spell(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Spell4Id,
) -> Result(Option(CreatureArea), AreaError) {
  let id = spell4_id.value
  use row <- result.try(
    spell4.get(tables:, id: spell4_id)
    |> result.replace_error(NoRow(table: "Spell4", id:)),
  )
  use area_row <- result.try(area_row_of(
    tables:,
    id:,
    row:,
    reading: CreatureReading,
  ))
  case area_row {
    None -> Ok(None)
    Some(area_row) -> {
      let links = telegraph_links_by_spell(tables:)
      use shapes <- result.try(hit_shapes_of(
        tables:,
        links:,
        id:,
        reading: CreatureReading,
      ))
      use anchor <- result.map(anchor_of(
        tables:,
        links:,
        id:,
        reading: CreatureReading,
      ))
      Some(CreatureArea(row: area_row, inside: inside_of(shapes:), anchor:))
    }
  }
}

/// How a creature's cast of the spell counts a unit as inside its area at each go, in go order,
/// for a cast whose gos fall `go_times_ms` after its start. A go strikes with the hit rows
/// (`hit_shapes_of`) that the client is drawing at the go's time (genesis_prime/game/telegraph_window)
/// and, for a cast whose phase the client compares with a row's (`spell_plan.compares_telegraph_phase`),
/// whose phaseFlags name the go (bit n is go n): the shapes of those rows, or `None` when the
/// spell has hit rows and the go has none, so it strikes nobody. A hit twin (flag 0x40) is
/// never drawn, so it is chosen by its phase alone. A spell with no hit row is read by its area
/// row at every go (`InsideRow`). A drawn hit row timed from a go (flag 0x2000) is refused, as
/// is a row the creature reading does not build.
pub fn hit_shapes_by_go(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Spell4Id,
  go_times_ms go_times_ms: List(Int),
) -> Result(List(Option(Inside)), AreaError) {
  let id = spell4_id.value
  use row <- result.try(
    spell4.get(tables:, id: spell4_id)
    |> result.replace_error(NoRow(table: "Spell4", id:)),
  )
  use base <- result.try(
    spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: row.spell4_base_id_base_spell,
    )),
  )
  let phased = spell_plan.compares_telegraph_phase(row:, base:)
  let links = telegraph_links_by_spell(tables:)
  let hit_rows = hit_rows_of(tables:, links:, id:)
  use Nil <- result.try(
    list.try_each(hit_rows, fn(row) {
      case !is_twin(row:) && telegraph_window.timed_from_a_go(row:) {
        True ->
          Error(TelegraphTimedFromAGo(spell4_id: id, telegraph_id: row.id))
        False -> Ok(Nil)
      }
    }),
  )
  use placed <- result.try(
    list.try_map(hit_rows, fn(row) {
      use placements <- result.map(placements_of(
        id:,
        row:,
        reading: CreatureReading,
      ))
      #(row, placements)
    }),
  )
  Ok(
    list.index_map(go_times_ms, fn(_, go) {
      shapes_at_go(placed:, go_times_ms:, go:, phased:)
    }),
  )
}

/// How a unit counts as inside at go `go` of a cast with the hit rows `placed` (each with its
/// placements): `InsideRow` when the spell has no hit row, `None` when it has some and none is
/// drawn then. A row's phase is read only when the client compares it (`phased`).
fn shapes_at_go(
  placed placed: List(#(telegraph_damage.TelegraphDamage, List(Placement))),
  go_times_ms go_times_ms: List(Int),
  go go: Int,
  phased phased: Bool,
) -> Option(Inside) {
  use <- bool.guard(when: placed == [], return: Some(InsideRow))
  let struck =
    list.filter(placed, fn(found) {
      let #(row, _) = found
      {
        !phased
        || spell_effect.names_phase(phase_flags: row.phase_flags, phase: go)
      }
      && { is_twin(row:) || telegraph_window.drawn_at(row:, go_times_ms:, go:) }
    })
  case struck {
    [] -> None
    [_, ..] ->
      Some(inside_of(shapes: list.flat_map(struck, fn(found) { found.1 })))
  }
}

/// How many gos the spell has (`spell_plan.go_count`): a pulse of a channel and a
/// phase of a Multiphase spell are each a go. The count is at least 1: a spell held
/// until its release has no go of its own, and its phase 0 is one no go asks for.
pub fn phase_count(spell spell: SpellArea) -> Int {
  int.max(1, spell_plan.go_count(spell: spell.spell))
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

/// What the area rule leaves undone.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Spell telegraphs",
      missing: "a player's ability whose drawn row is placed by the server (flag 0x1000 or 0x4000: Telekinetic Strike, Nullifier, Personal Defense Unit, Flash Bang, Field Probes and Rapid Fire) is sent no initial or telegraph position in its 0x7ff and 0x7fd, so the client draws none of that row; only a creature's special is sent them",
    ),
    gap.Entry(
      area: "Creature target and ground rows",
      missing: "a creature's hit row placed on the ground (targetTypeFlags bit 8, 34 listed spells with it alone) or on each unit the strike finds (bit 4, 3 listed spells) is refused, as is one placed on two units at once (flags 3 and 9); a player's ability whose hit row is placed on each struck unit (bit 4) or on two units at once is refused, and so is one whose row is placed on the target of a spell that is started on another unit with a shape that reads the unit's facing (the strike knows a unit's place, not its yaw) or that is pressed while its target mechanic names a target or a spot (the press reads neither)",
    ),
    gap.Entry(
      area: "Player hit rows by anchor",
      missing: "a player's drawn row placed otherwise than its hit rows is not compared with them, so the picture and the hit disagree when the caster has moved between the start and the go (three planned abilities); a player's strike takes every hit row of the spell at each go, so a cast whose rows differ by phase strikes their union at every go (six planned abilities)",
    ),
    gap.Entry(
      area: "Player held position",
      missing: "the yaw of a player's row placed at the position the cast holds is the caster's facing yaw, where the client copies its own unit word, which the server does not hold (a guess); a flag-8 row of a child cast on each struck unit is centred on the caster's place when the child starts, where retail may centre it on the struck unit (a guess, one planned ability); a row fixed at the target (flag 0x1000 or 0x4000, targetTypeFlags 0 or 2) of a child cast on a struck unit is centred on where the picture shows that unit at the go, where the client puts it at the entry the 0x7ff carries (a guess)",
    ),
    gap.Entry(
      area: "Damage rows that last until removed",
      missing: "a damage row that lasts until removed (flags bit 2) is never played, so an ability whose tree holds one is refused when its plan is built (Unsteady Miasma, whose child's only damage row, 229624, ticks until removed; Telekinetic Storm, whose 32828 holds 62036; Pyrokinetic Flame, whose 43973 holds 100978) and stays unplanned",
    ),
    gap.Entry(
      area: "Creature hit rows by go",
      missing: "a creature's cast strikes with the hit rows the client draws at the go, and for a cast whose phase the client compares (a Multiphase cast, or a channel whose spellChannelFlags has bit 1) that its phase names: a row still counts as drawn at a go equal to its end, and a hit twin (flag 0x40, never drawn) is struck by its phase alone (at every go for a cast whose phase the client does not compare), both guesses the client's code does not settle; a hit row behind a caster prerequisite (prerequisiteIdCaster, which the client draws only while the caster passes it) is read as drawn whatever the caster, no row of the retail-listed specials has one; a drawn hit row timed from a go (flag 0x2000) is refused",
    ),
    gap.Entry(
      area: "Creature area orders and shapes",
      missing: "a creature's area that selects by a unit's health (Spell4AoeTargetConstraints targetSelection 4 and 5, 2 listed creature spells) is refused, since a creature's sight of a fighter holds no health; a hit row of shape 8 with a box (param03 or param05 above 0) is refused for a creature and a player, its box not read; Random's order is a guess, the client naming it and ordering nothing",
    ),
  ]
}
