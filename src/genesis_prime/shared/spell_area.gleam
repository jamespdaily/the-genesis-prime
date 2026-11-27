//// What the client's tables say a spell strikes, for each spell of each class's
//// level-1 ability trees: the area row, the hit shapes of its telegraphs and the
//// damage effects of each phase with who each aims at. Built once when the tables
//// load, beside the ability trees (genesis_prime/shared/spell_plan); the strike rule
//// (genesis_prime/game/strike) reads it and decides nothing from the tables itself.
////
//// ```
//// plans (genesis_prime/shared/spell_plan) ─▶ every Spell4 of every tree
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
////   units (a type 11 row aimed only at other units) or a Proxy with no tickTime aimed at
////   the area selects units; a Proxy with a tickTime aimed at the area selects none at the go
////   and finds its units at each tick (`PhaseStrike.ticks_on_area`); one aimed at the cast's
////   target strikes the primary target; with
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
////   (`Spell4Effects.emmComparison`, genesis_prime/shared/spend), and `phase` keeps
////   only the effects and Proxies whose tag holds for the points the cast spent above
////   its base cost, then works out `selects_area`, `strikes_primary_target` and
////   `ticks_on_area` from what is left. A cast with no spend keeps every effect.
//// - **An instant heal row aimed at the primary target** (`PhaseStrike.heals`, from
////   `Spell4Effects.targetFlags` bit 2 with no delay and no tickTime) is a row a go tells the
////   player that is the primary target; a row with a delay or a tickTime, and one aimed at the
////   caster alone, is not in it.
//// - **An instant heal row aimed at the area of a spell whose area finds the caster's allies**
////   (`SpellArea.finds_allies`, `spell_plan.spell_finds_allies`: a beneficial mechanic, no foe
////   row, an area ordered Closest, Furthest, Random or by missing health) is in `heals` too,
////   and makes the phase select the area: the strike selects the other Friendly players inside
////   it (`shown.ally_candidates`) and tells each the row.
//// - **A periodic damage row** (a tickTime) strikes the units of its go once for each
////   tick of its schedule (genesis_prime/shared/ticking), each tick its own 0x7f8 from the
////   server: the go selects with it as with any row, and `PhaseStrike.ticking` holds it
////   apart from the rows that strike once. A row that lasts until removed (flags bit 2)
////   is left out by the load (`TickingUntilRemoved`), and `checker` refuses a spell that holds
////   one, so no planned ability's press waits on a damage row that is never played.
//// - **A periodic Proxy aimed at the area** (`Spell4Effects.effectType.26.periodic`: the texts
////   574032 and 306769 say it casts "on foes inside the field every Ns") ticks on the units
////   inside the spell's area at each tick: its phase has `ticks_on_area`, so the load asks the
////   same of the area row as of a phase that selects (a row, in an order the server builds),
////   and the go strikes nobody for it. A Proxy that names a beneficial spell is refused by the
////   plan (`spell_plan.PeriodicProxyAtAlliesNotRead`), since the allies in the area are not
////   found. A Proxy with no tickTime aimed at the area of a spell that finds the caster's
////   allies, and a property change aimed at that area (`PhaseStrike.acts_on_each_unit`), make the
////   phase select the area: each ally selected is a hit of the go that no row need reach, and the
////   go starts the child on it or changes it. Such a change strikes no foe (`strikes_area`), so
////   an area ordered by missing health stays built for it.
//// - **Order.** An area row's `targetSelection` is read for a player and a creature alike:
////   Closest (1), Furthest (2) and Random (3) are the orders `area.select_ordered` takes, and
////   no strike selects a dead unit (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`). Orders 4 and 5 (by health) need a unit's health,
////   which the units a strike chooses from do not hold: a creature's row is refused
////   (`SelectionNeedsHealth`). A player's order 4 is read as no area (`SpellArea.row` `None`),
////   refused (`SelectionNeedsHealth`) only for a phase that selects units from it. A player's
////   order 5 (MissingMostHealth) is built for an area that finds the caster's allies when its
////   phases select units by the instant heals alone, the units that hold a health being the
////   allies' copies the caster's connection keeps (`shown.ally_candidates`), or through a Proxy
////   with no tickTime aimed at the area, which starts a child on each of those allies; a phase
////   that also strikes the area with a row, ticks on it, or, where the area finds no allies,
////   selects through a Proxy is refused (`SelectionNeedsHealth`), and a phase that selects
////   nothing leaves it as no area.
//// - **Valid targets** (`Spell4ValidTargets.targetBitmask`, `FillSpellRecord` 0x140568540,
////   `FillSpellAoeConstraints` 0x1405698c0): bits 1, 2 and 256 act at a press, not in an area,
////   and 256 (no pet) excludes no unit of the strike; bits 4 (players only) and 16 (party
////   members only) select no creature (`strikes_creatures`, `strike.select`); bit 128, which
////   no client code reads, is read as clear, a guess; bits 8, 32 and 64 are refused
////   (`ValidTargetsNotBuilt`).
//// - **Two readings** read a spell's rows: a player's ability (`PlayerReading`: the shapes of
////   the level-1 trees) and a creature's special (`CreatureReading`: also rings, crosses,
////   pies and unhalved boxes), so a player's strike refuses shapes 1, 3, 5 and 6.
//// - **Where a hit is centred** is its anchor, one for the spell (`anchor_of`): a hit row is
////   placed on the caster (`targetTypeFlags` 1) or on the cast's target (0 or 2), and drawn where
////   the cast's 0x7ff puts it and stays there (TelegraphDamage flag 0x4000 or 0x1000:
////   `FixedAtCaster`, `FixedAtTarget`) or follows its unit (`FollowsCaster`, `FollowsTarget`).
////   A creature special whose rows, or whose hit twin and drawn row, are not placed alike is
////   refused (`PlacedApart`), so the hit is always where the picture is
////   (`0x140546e60.placement_branches`, `0x14054b1b0.fixed_placement`,
////   `0x14054b1b0.follows_caster`). A player's row placed at the position the cast holds
////   (`targetTypeFlags` 8) is `FixedAtCaster` whatever its flags: the client stores that
////   position and yaw once, when the cast starts (`0x14053a210.held_position`). A player's hit
////   rows alone decide the anchor, and a spell with none is `FollowsTarget`, struck around
////   its primary target. Nullifier 58868 (row 2789, flags 1 with 0x1000) is `FixedAtCaster`;
////   its phase holds no damage row and selects no area, so its anchor moves no strike.
//// - **Who the primary target is** follows from how the spell is started
////   (genesis_prime/shared/spell_plan `Start`): the caster for a press, a Proxy on the caster and
////   a proc aimed at its holder (`AtHolder`), the struck unit for a Proxy on each struck unit,
////   the ally for a Proxy on each ally,
////   and another unit for a proc aimed at one (`AtOtherUnit`, which falls back to the holder
////   when the event has none, so its spell is still built only as for another unit). A row on
////   the target of a spell started on a struck unit, on an ally or by a proc aimed at another
////   unit is built only as a circle with no offset, which reads no yaw (`start_placed`; a spell that draws no hit shape selects by its area row, built only at 360 degrees), and a pressed
////   spell's row on the target only when the spell is cast at the caster, since the press names
////   the caster and reads no other target (`targeting_given`, `target_mechanic.takes_caster`).
//// - **Which spells** are read: the spells of each ability's tree and of each of its tiers
////   (genesis_prime/shared/spell_plan `tier_plans`), its threshold stages (Spell4Thresholds) included,
////   a Proxy behind a target prerequisite excepted, since it is never started. A spell
////   with no area row selects nobody.
//// - **What fails the load:** a row the tree names that the tables lack; a
////   `targetSelection` other than 1 to 5 (4 and 5 are refused by `SelectionNeedsHealth` for a
////   creature, 4 for a player's phase that selects units from the area, and 5 for a player's
////   phase that selects other than by an instant heal or a Proxy that reach the caster's
////   allies); a valid-targets
////   bitmask holding bit 8, 32 or 64 on a spell with an area row; a hit row placed on anything but the
////   caster, the cast's target and the
////   held position (`targetTypeFlags` other than 0, 1, 2 and 8; for a creature other than 0 to
////   2: `TelegraphOnStruckUnits` for bit 4, else `TelegraphNotOnCaster`); a spell's hit rows
////   placed apart (`PlacedApart`); a pressed spell whose hit row is on the target and whose
////   target mechanic is not cast at the caster (`TargetingNotBuilt`); a spell started on
////   another unit, or on an ally, whose hit row on the target is not a circle with no offset
////   (`HitRowOffTheStrikeCentre`); a shape
////   the rule does not build (for a player 1, 3, 5, 6, or 8 with
////   a box that has a width or a length: the box's height, p4, is never tested; for a
////   creature 8 with such a box alone); a damage effect
////   (type 8) aimed by a flag value not read; a formula that reads a parameter the
////   player's value does not (genesis_prime/shared/damage `unread`: the weapon kinds 6
////   and 9, the passed-in value 18, and any kind above 26; the vital kinds are read,
////   the target's finished when the blow lands); and a phase that
////   selects units from a spell with no area row; a creature's drawn hit row timed from a go
////   (flag 0x2000: `TelegraphTimedFromAGo`).
//// - **Each go of a creature's cast** is struck with the hit rows its phase names that the client
////   is drawing at the go's time (`hit_shapes_by_go`, genesis_prime/shared/telegraph_window).
//// - **Each go of a player's cast** is struck with the hit rows its phase names, for a cast whose
////   phase the client compares with a row's (`spell_plan.compares_telegraph_phase`), and with
////   every hit row otherwise (`SpellArea.inside_by_go`). This is a server guess: the client
////   compares a row's phase with a go only to launch client missiles from a telegraph position
////   (`opcode.0x7f4.phase`) and ties no row to the damage of a go; the row's time window is not
////   read, since it would strike nobody at the later gos of a spell that is not phased, such as
////   Discharge 58832 at its second and third pulse.

import genesis_prime/gap
import genesis_prime/shared/area.{
  type Anchor, type Inside, type Placement, type Row, Box, Circle, Cone,
  FixedAtCaster, FixedAtTarget, FollowsCaster, FollowsTarget, Furthest,
  InsideRow, InsideShapes, MissingMostHealth, Nearest, Placement, Random,
  Rectangle, Row,
}
import genesis_prime/shared/damage.{type Formula}
import genesis_prime/shared/effect_kind
import genesis_prime/shared/spell_effect
import genesis_prime/shared/spell_plan.{type Aim, type Spell, type Start}
import genesis_prime/shared/spend
import genesis_prime/shared/target_mechanic
import genesis_prime/shared/telegraph_entries
import genesis_prime/shared/telegraph_window
import genesis_prime/shared/ticking
import genesis_prime/table/id.{
  type Spell4EffectsId, type Spell4Id, Spell4AoeTargetConstraintsId,
  Spell4EffectsId, TelegraphDamageId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/telegraph_damage
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Whose area a spell's rows are read for: the shapes each can take differ, since a player's
/// abilities (the level-1 trees) hold only the shapes `PlayerReading` builds.
pub type Reading {
  /// A player's ability: the circle, box, cone and rectangle shapes.
  PlayerReading
  /// A creature's special: also the ring, cross, pie and unhalved-box shapes
  /// (`0x14054d170.shapes_1_3_5_6`).
  CreatureReading
}

/// A damage effect of a spell: its row, damage type and delay, the phases it fires
/// in, who it aims at, the formula its value is worked out by and the tag that
/// chooses it by the points the cast spent (genesis_prime/shared/spend).
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

/// An instant heal row of a phase aimed at the cast's primary target or, in an area that
/// finds the caster's allies, at the area: the row a go tells the player that is its primary
/// target or each ally the area selected, who heals itself by its own rule
/// (genesis_prime/game/strike `player_answered`). A row with a delay or a period is not one.
pub type InstantHeal {
  InstantHeal(
    effect_id: Spell4EffectsId,
    vital: effect_kind.Vital,
    aim: Aim,
    condition: spell_plan.Condition,
    formula: Formula,
  )
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
    /// not), a crowd-control state or a property change of struck units aimed at the area, a
    /// Proxy that starts its spell on each struck unit (genesis_prime/shared/spell_plan
    /// `OnEachStruck`), or, in an area that finds the caster's allies, an instant heal aimed at
    /// the area (`heals`).
    selects_area: Bool,
    /// Whether a damage effect, a crowd-control state or a property change of struck units
    /// aims at the area, and the area does not find the caster's allies: what strikes the units
    /// it selects, which an area ordered by health cannot serve. A property change of the
    /// allies an area finds is no strike, so it is not counted.
    strikes_area: Bool,
    /// Whether the phase acts on each unit the area selects though no row names a foe: a Proxy
    /// with no tickTime aimed at the area starts a child on each (`OnEachStruck`, `OnEachAlly`),
    /// or, where the area finds the caster's allies, a property change or a Proc aimed at the
    /// area changes or is held by each ally. Where the area finds the caster's allies the units are players and each is a
    /// hit of the go that no row need reach.
    acts_on_each_unit: Bool,
    /// The instant heal rows of the phase aimed at the cast's primary target, which a go
    /// tells the player that is its primary target, and, in an area that finds the caster's
    /// allies, those aimed at the area, which a go tells each ally the area selected.
    heals: List(InstantHeal),
    /// Whether the phase strikes the cast's own target: a damage effect (periodic or
    /// not), a crowd-control state or a property change of struck units aimed at it. A heal
    /// is not counted: a go tells a player its heals through `heals`, and a creature is
    /// not the target of a heal.
    strikes_primary_target: Bool,
    /// Whether the phase arms a periodic Proxy aimed at the area, which finds the units
    /// inside the area at each of its ticks and strikes nobody at the go.
    ticks_on_area: Bool,
  )
}

/// A spell's area: its row, the hit shapes of its telegraphs and the effects its
/// phases strike with, which `phase` chooses from by the points a cast spent.
pub type SpellArea {
  SpellArea(
    spell4_id: Spell4Id,
    /// The area row, `None` for a spell with no `Spell4AoeTargetConstraints` row and for a row
    /// ordered by health that no go of the spell selects units from.
    row: Option(Row),
    /// How a unit counts as inside the area at each go, in go order (`inside`): the hit
    /// rows placed on the caster that the go's phase names, from the never-drawn twins, else
    /// the drawn rows without bit 0x20 (all of them when each has it). `Some(InsideRow)` at
    /// every go for a spell with no hit row, and `None` at a go of a spell with hit rows that
    /// none names, which strikes nobody from the area.
    inside_by_go: List(Option(Inside)),
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
    /// Whether the area finds the caster's allies rather than foes
    /// (`spell_plan.spell_finds_allies`).
    finds_allies: Bool,
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
  /// An area row selects in no order the client names (`targetSelection` 0, None, or above 5).
  SelectionNotBuilt(spell4_id: Int, target_selection: Int)
  /// An area row selects units by a unit's health (`targetSelection` 4, LowestAbsoluteHealth,
  /// or 5, MissingMostHealth) in a case the server does not build: a creature's row, a
  /// player's order 4, and a player's order 5 whose phase selects units from the area other
  /// than by an instant heal that reaches the caster's allies (`SpellArea.finds_allies`).
  SelectionNeedsHealth(spell4_id: Int, target_selection: Int)
  /// A spell's valid targets hold a bit of the area record the strike does not read: the area
  /// may strike the dead (8), picks a creature cluster only (32) or units in combat only (64).
  ValidTargetsNotBuilt(spell4_id: Int, target_bitmask: Int)
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
  /// A periodic damage effect lives shorter than one tick (genesis_prime/shared/ticking
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
      <> ", which is no order the client names (0, None, is not one; 1 to 5 are)"
    SelectionNeedsHealth(spell4_id:, target_selection:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an area row that selects in order "
      <> int.to_string(target_selection)
      <> ", by a unit's health, which the server builds only for the allies an instant heal of a friendly area reaches"
    ValidTargetsNotBuilt(spell4_id:, target_bitmask:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has valid targets of bitmask "
      <> int.to_string(target_bitmask)
      <> ", which holds a bit of 8 (the dead), 32 (a creature cluster only) or 64 (units in combat only) that the strike does not read"
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
        spell_plan.Proxied(target: spell_plan.OnPrimaryTarget) ->
          "on the player the press named"
        spell_plan.Proxied(target: spell_plan.OnEachStruck) ->
          "on each struck unit"
        spell_plan.Proxied(target: spell_plan.OnEachAlly) ->
          "on each ally the area selects"
        spell_plan.FromProc(aim: spell_plan.AtHolder) ->
          "by a proc aimed at its holder"
        spell_plan.FromProc(aim: spell_plan.AtOtherUnit) ->
          "by a proc aimed at another unit"
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

/// Every spell of every ability tree the plans hold, by Spell4 id, as the load keeps them: the
/// level-1 abilities' and the later abilities' trees, the equip spells', and each tier's of
/// those (`spell_plan.tier_plans`).
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
/// tables. The ability trees, their tiers and the AMP spells must already be derived
/// (genesis_prime/shared/spell_plan `plans`, `tier_plans` and `amp_plans`).
pub fn build(tables tables: table_store.Tables) -> Result(Areas, AreaError) {
  let started =
    list.append(
      list.append(
        dict.values(spell_plan.plans_with_later(tables:)),
        dict.values(spell_plan.standing_plans(tables:)),
      )
        |> list.flat_map(spells_of_tree),
      list.append(
        // A tier's alternate is planned inside the tier, not among the plans of its own.
        dict.values(spell_plan.tier_plans(tables:))
          |> list.flat_map(spell_plan.tree_started_with_alternate),
        dict.values(spell_plan.amp_plans(tables:))
          |> list.flat_map(spells_of_tree),
      ),
    )
  let effects = spell_plan.effects_by_spell(tables:)
  let links = telegraph_links_by_spell(tables:)
  list.try_fold(started, dict.new(), fn(areas, started) {
    let #(spell, start) = started
    let id = spell.spell4_id.value
    use area <- result.try(case dict.get(areas, id) {
      Ok(area) -> Ok(area)
      Error(Nil) -> area_of(tables:, effects:, links:, spell:)
    })
    use Nil <- result.map(start_checked(area:, start:))
    dict.insert(areas, id, area)
  })
}

/// What a later ability's spells must pass to be planned (genesis_prime/shared/spell_plan
/// `Checker`): the area of each is built as `build` builds it and no damage row lasts until
/// removed, and an error of what the rule does not build leaves the ability out of the
/// plans, so no ability holds a spell the load of the areas would refuse.
pub fn checker(tables tables: table_store.Tables) -> spell_plan.Checker {
  let effects = spell_plan.effects_by_spell(tables:)
  let links = telegraph_links_by_spell(tables:)
  fn(spell: Spell, start: Start) {
    let id = spell.spell4_id.value
    area_of(tables:, effects:, links:, spell:)
    |> result.try(fn(area) {
      start_checked(area:, start:) |> result.replace(area)
    })
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
/// number that is no number as a fault of the data, and the rest, a spell that selects units
/// with no area row included (Stagger's tier 9 is one), as what the area rule does not build.
fn plan_error_of(
  error error: AreaError,
  spell4_id spell4_id: Int,
) -> spell_plan.PlanError {
  case error {
    ApplyGateNotRead(error: inner) -> inner
    NoRow(..) | MultiplierNotFinite(..) ->
      spell_plan.AreaDataFault(spell4_id:, reason: describe(error:))
    NoAreaRow(..)
    | SelectionNotBuilt(..)
    | SelectionNeedsHealth(..)
    | ValidTargetsNotBuilt(..)
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
/// prerequisite starts it on a unit that passes (genesis_prime/shared/spell_plan
/// `GatedOnCasterAndTarget`).
fn spells_of_tree(spell: Spell) -> List(#(Spell, Start)) {
  spell_plan.tree_started(spell:, started: fn(_) { True })
}

/// Whether a spell with an area row, started as `start`, strikes where its hit is drawn
/// (`start_placed`) and, pressed, is cast at what its hit row is placed on (`targeting_given`).
fn start_checked(
  area area: SpellArea,
  start start: Start,
) -> Result(Nil, AreaError) {
  case area.row {
    None -> Ok(Nil)
    Some(row) ->
      case
        start_placed(
          anchor: area.anchor,
          start:,
          shapes: shapes_of_any_go(area:),
          selected_by_row: case
            list.any(area.inside_by_go, fn(inside) { inside == Some(InsideRow) })
          {
            True -> Some(row)
            False -> None
          },
        )
      {
        False ->
          Error(HitRowOffTheStrikeCentre(
            spell4_id: area.spell4_id.value,
            start:,
          ))
        True -> targeting_given(area:, start:)
      }
  }
}

/// Whether the strike centres a spell started as `start` where its hit rows are drawn. A
/// press and a Proxy on the caster have the caster as their primary target, so every anchor is
/// the caster's place, and so does a proc aimed at its holder (`cast` `proc_started` casts it at
/// the holder). A Proxy aimed at the primary target is read as on the caster, whichever
/// player a bag press named, which holds only because the one child of such a Proxy that has
/// a hit row draws a circle with no offset (Spell4 54912), which the reading below builds
/// too. A spell started on a struck unit, on an ally or by a proc aimed at another unit has
/// another unit as its primary target, whose place the strike knows and whose yaw it does not
/// (`shown.strike_centre_of`: yaw 0.0): a row on the caster is centred on the caster, and a row
/// on the target only when every hit shape is a circle with no offset, which reads no yaw
/// (`area.in_shape`; a turned circle is the same circle), and, for a go that draws no hit
/// shape and so selects by the area row alone (`selected_by_row`), only when the row is all
/// round (360 degrees), since a narrower row reads the facing. Any other shape of a row on the
/// target is turned or moved by the unit's facing on the client (`0x14054b1b0.follows_caster`).
pub fn start_placed(
  anchor anchor: Anchor,
  start start: Start,
  shapes shapes: List(Placement),
  selected_by_row selected_by_row: Option(area.Row),
) -> Bool {
  case start {
    spell_plan.Pressed
    | spell_plan.Proxied(target: spell_plan.OnCaster)
    | spell_plan.Proxied(target: spell_plan.OnPrimaryTarget)
    | spell_plan.FromProc(aim: spell_plan.AtHolder) -> True
    spell_plan.Proxied(target: spell_plan.OnEachStruck)
    | spell_plan.Proxied(target: spell_plan.OnEachAlly)
    | spell_plan.FromProc(aim: spell_plan.AtOtherUnit) ->
      case anchor {
        FollowsCaster | FixedAtCaster -> True
        FollowsTarget | FixedAtTarget ->
          list.all(shapes, is_plain_circle)
          && case selected_by_row {
            Some(row) -> row.degrees >=. 360.0
            None -> True
          }
      }
  }
}

/// Whether the placement is a circle on its unit's own place. An offset of -0.0 moves nothing,
/// which the pattern `0.0` does not match.
fn is_plain_circle(placement placement: Placement) -> Bool {
  case placement {
    Placement(shape: Circle(..), ahead:, aside:, ..) ->
      is_zero(ahead) && is_zero(aside)
    Placement(..) -> False
  }
}

/// Whether the number is 0.0 or -0.0, which are equal as numbers but not as Erlang terms.
fn is_zero(number: Float) -> Bool {
  number >=. 0.0 && number <=. 0.0
}

/// The refusal of a pressed spell whose hit row is placed on the cast's target but whose target
/// mechanic is not cast at the caster. The area build does not know whom a press names, and
/// a press at a creature or at the caster names the caster as the primary target (`cast`
/// `press_of`), so a Targeted spell would hit the caster; every such spell is refused. A
/// spell with no hit row and every other start are built.
fn targeting_given(
  area area: SpellArea,
  start start: Start,
) -> Result(Nil, AreaError) {
  case start, placed_on_the_target(area:) {
    spell_plan.Pressed, True -> {
      let kind = area.spell.targeting.kind
      case target_mechanic.takes_caster(kind) {
        True -> Ok(Nil)
        False ->
          Error(TargetingNotBuilt(spell4_id: area.spell4_id.value, kind:))
      }
    }
    spell_plan.Pressed, False
    | spell_plan.Proxied(..), _
    | spell_plan.FromProc(..), _
    -> Ok(Nil)
  }
}

/// Whether the spell has a hit row and it is placed on the cast's target: a spell with no hit
/// row has no shapes and is centred on its primary target only by default.
fn placed_on_the_target(area area: SpellArea) -> Bool {
  case shapes_of_any_go(area:), area.anchor {
    [], _ -> False
    [_, ..], FollowsTarget | [_, ..], FixedAtTarget -> True
    [_, ..], FollowsCaster | [_, ..], FixedAtCaster -> False
  }
}

/// The hit shapes the spell holds at any of its gos, each go's in order: where the spell is
/// centred and started is one choice for all its gos, so it is checked against every shape.
fn shapes_of_any_go(area area: SpellArea) -> List(Placement) {
  list.flat_map(area.inside_by_go, fn(inside) {
    case inside {
      Some(InsideShapes(placements:)) -> placements
      Some(InsideRow) | None -> []
    }
  })
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
  use read <- result.try(area_row_of(tables:, id:, row:))
  use Nil <- result.try(case read {
    Some(..) -> valid_targets_checked(id:, targeting: spell.targeting)
    None -> Ok(Nil)
  })
  let area_row = case read {
    Some(Ordered(row:)) -> Some(row)
    Some(ByMissingHealth(..)) | Some(ByHealth(..)) | None -> None
  }
  use placed <- result.try(placed_rows(
    id:,
    rows: hit_rows_of(tables:, links:, id:),
    reading: PlayerReading,
  ))
  let phased = spell_plan.compares_telegraph_phase(row:, base:)
  let inside_by_go =
    spell_plan.go_numbers(go_count: phase_count_of(spell:))
    |> list.map(fn(go) {
      shapes_at_go(placed:, go:, phased:, drawn: fn(_) { True })
    })
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
      inside_by_go:,
      anchor:,
      damage:,
      ticking:,
      spell:,
      finds_allies: spell_plan.spell_finds_allies(
        tables:,
        row:,
        effects: result.unwrap(dict.get(effects, id), []),
      ),
    )
  // A phase that selects units at some n, every effect chosen being the widest, or ticks on
  // the units of the area, must have an area row, and one that selects units in an order the
  // server builds. An order by missing health is built only for a friendly area whose phases
  // select units by its instant heals alone.
  let selects = phases_select(area:)
  case read, selects {
    None, True -> Error(NoAreaRow(spell4_id: id))
    Some(ByHealth(target_selection:)), True ->
      Error(SelectionNeedsHealth(spell4_id: id, target_selection:))
    Some(ByMissingHealth(row:)), True ->
      case phases_select_beyond_allies(area:) {
        True -> Error(SelectionNeedsHealth(spell4_id: id, target_selection: 5))
        False -> Ok(SpellArea(..area, row: Some(row)))
      }
    None, False
    | Some(Ordered(..)), _
    | Some(ByMissingHealth(..)), False
    | Some(ByHealth(..)), False
    -> Ok(area)
  }
}

/// Whether some phase of the area selects units from it or ticks on the units it holds.
fn phases_select(area area: SpellArea) -> Bool {
  any_phase(area:, holds: fn(chosen) {
    chosen.selects_area || chosen.ticks_on_area
  })
}

/// Whether some phase selects units from the area by anything the caster's picture cannot
/// order by missing health: a row that strikes the area, a periodic Proxy that ticks on the
/// units in it, or, where the area finds no allies, a Proxy that starts a child on each unit.
/// An instant heal aimed at the area, and a Proxy that starts a child on each ally, select the
/// allies the picture holds a health for.
fn phases_select_beyond_allies(area area: SpellArea) -> Bool {
  any_phase(area:, holds: fn(chosen) {
    chosen.strikes_area
    || chosen.ticks_on_area
    || chosen.acts_on_each_unit
    && !area.finds_allies
  })
}

/// Whether some go of the area's spell has a phase for which `holds` is true.
fn any_phase(
  area area: SpellArea,
  holds holds: fn(PhaseStrike) -> Bool,
) -> Bool {
  spell_plan.go_numbers(go_count: phase_count_of(spell: area.spell))
  |> list.any(fn(phase) { holds(phase_of(spell: area, phase:, spent: None)) })
}

/// Valid-target bits the area record holds and the strike does not read: the area may strike
/// the dead, picks a creature cluster only, or strikes units in combat only
/// (`FillSpellAoeConstraints` 0x1405698c0, record words 6 to 8).
const unbuilt_valid_target_bits = [
  target_mechanic.valid_may_be_dead,
  target_mechanic.valid_creature_cluster,
  target_mechanic.valid_in_combat_only,
]

/// Whether the valid-target bits hold any of `bits`.
fn holds_any(valid_targets valid_targets: Int, bits bits: List(Int)) -> Bool {
  list.any(bits, fn(bit) { spell_effect.has_flag(flags: valid_targets, bit:) })
}

/// A spell with an area row whose base names valid targets is built when the mask holds none
/// of bits 8, 32 and 64. Bits 1, 2, 4, 16 and 256 act where a press is checked
/// (`press_target`) or on which units an area can select (`strikes_creatures`). Bit 128 is
/// copied to the area record's word 9 and read by no client code (0x1405ecf20 names words 6
/// to 8 only); the server reads it as clear, a guess. A spell with no area selects nobody,
/// so its valid targets are not read.
fn valid_targets_checked(
  id id: Int,
  targeting targeting: target_mechanic.Targeting,
) -> Result(Nil, AreaError) {
  let bitmask = targeting.valid_targets
  case holds_any(valid_targets: bitmask, bits: unbuilt_valid_target_bits) {
    False -> Ok(Nil)
    True -> Error(ValidTargetsNotBuilt(spell4_id: id, target_bitmask: bitmask))
  }
}

/// Whether an area whose spell has these valid targets can select another player: not when
/// the mask refuses a player target (bit 1: the client answers 102, `0x1403b2240`) or takes
/// only the caster's group (bit 16, `UnitsShareGroup` 0x140561e60), since no player of the
/// server has a group id but 0 (`player_unit`), so such an area finds the caster alone.
pub fn finds_players(valid_targets valid_targets: Int) -> Bool {
  !holds_any(valid_targets:, bits: [
    target_mechanic.valid_refuses_player,
    target_mechanic.valid_same_group_only,
  ])
}

/// Whether an area whose spell has these valid targets can select a creature: not when the
/// mask names only players (bit 4) or only the caster's party members (bit 16), since the
/// server stands no creature as either.
pub fn strikes_creatures(valid_targets valid_targets: Int) -> Bool {
  !holds_any(valid_targets:, bits: [
    target_mechanic.valid_players_only,
    target_mechanic.valid_same_group_only,
  ])
}

/// What an area row's `targetSelection` reads as.
type OrderRead {
  /// An order `area.select_ordered` takes of every area: Closest, Furthest or Random.
  Ordered(row: Row)
  /// MissingMostHealth (5), which `area.select_ordered` takes only of the allies a friendly
  /// area finds, the units that hold a health.
  ByMissingHealth(row: Row)
  /// LowestAbsoluteHealth (4), which no strike chooses by: the row's selection number.
  ByHealth(target_selection: Int)
}

/// The spell's area row as its order reads: `None` for a spell with no area row, or the refusal
/// of an order the client does not name.
fn area_row_of(
  tables tables: table_store.Tables,
  id id: Int,
  row row: spell4.Spell4,
) -> Result(Option(OrderRead), AreaError) {
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
        Row(
          min_range: constraints.min_range,
          max_range: constraints.max_range,
          degrees: constraints.angle,
          target_count: constraints.target_count,
          order:,
        )
      }
      case constraints.target_selection {
        1 -> Ok(Some(Ordered(row: row_of(Nearest))))
        2 -> Ok(Some(Ordered(row: row_of(Furthest))))
        3 -> Ok(Some(Ordered(row: row_of(Random))))
        4 -> Ok(Some(ByHealth(target_selection: constraints.target_selection)))
        5 -> Ok(Some(ByMissingHealth(row: row_of(MissingMostHealth))))
        selection ->
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
/// not read here: `SpellArea.inside_by_go` and `hit_shapes_by_go` choose them go by go. A
/// Spell4Telegraph row whose TelegraphDamage row the table lacks gives no shape, as the
/// client leaves it out of its
/// spell's telegraphs (`Spell4Telegraph.telegraphDamageId.no_row`). The shapes of the
/// spell `id` that its Spell4Telegraph rows in `links` choose, or the refusal of one; a row
/// of a shape that is two boxes gives two.
pub fn hit_shapes_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
  reading reading: Reading,
) -> Result(List(Placement), AreaError) {
  placed_rows(id:, rows: hit_rows_of(tables:, links:, id:), reading:)
  |> result.map(list.flat_map(_, fn(found) { found.1 }))
}

/// Each of the spell `id`'s hit rows with the placements the reading builds from it, or the
/// refusal of the first row it does not build.
fn placed_rows(
  id id: Int,
  rows rows: List(telegraph_damage.TelegraphDamage),
  reading reading: Reading,
) -> Result(
  List(#(telegraph_damage.TelegraphDamage, List(Placement))),
  AreaError,
) {
  list.try_map(rows, fn(row) {
    use placements <- result.map(placements_of(id:, row:, reading:))
    #(row, placements)
  })
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
pub fn hit_rows_of(
  tables tables: table_store.Tables,
  links links: Dict(Int, List(spell4_telegraph.Spell4Telegraph)),
  id id: Int,
) -> List(telegraph_damage.TelegraphDamage) {
  hit_rows_among(rows: linked_rows_of(tables:, links:, id:))
}

/// Whether the row is a never-drawn twin (flag 0x40) that says who is hit in place of a
/// drawn row.
pub fn is_twin(row row: telegraph_damage.TelegraphDamage) -> Bool {
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
/// value reads (genesis_prime/shared/damage `unread`). A row with a tickTime is periodic,
/// with the schedule of its ticks (genesis_prime/shared/ticking `schedule_of`), read before
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
/// chooses (genesis_prime/shared/spend `applies`); the flags are worked out from the
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
    list.append(
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
      ),
      // A Proc the area's allies hold changes each ally the area selects as a property change
      // aimed at the area does.
      list.filter_map(
        spell_plan.in_phase(
          spell: spell.spell,
          phase:,
          spent:,
          as_kind: spell_plan.as_proc,
        ),
        fn(proc) {
          case proc.holder {
            spell_plan.HeldByAreaAllies -> Ok(spell_plan.AimsAtArea)
            spell_plan.HeldByCaster | spell_plan.HeldByPrimaryTarget ->
              Error(Nil)
          }
        },
      ),
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
  let proxies =
    spell_plan.in_phase(
      spell: spell.spell,
      phase:,
      spent:,
      as_kind: spell_plan.as_proxy,
    )
  let strikes_without_changes = fn(reaches: fn(Aim) -> Bool) {
    list.any(firing, fn(effect) { reaches(effect.aim) })
    || list.any(gates, fn(gate) { reaches(gate.aim) })
    || list.any(throws, reaches)
    || list.any(despawns, reaches)
    || list.any(unit_states, reaches)
    || list.any(ticking_firing, fn(row) { reaches(row.damage.aim) })
    || list.any(controls, fn(control) { reaches(control.aim) })
  }
  let strikes = fn(reaches: fn(Aim) -> Bool) {
    strikes_without_changes(reaches) || list.any(changes, reaches)
  }
  let changes_allies =
    spell.finds_allies
    && list.any(changes, fn(aim) { spell_plan.reaches_area(aim:) })
  let heals =
    list.filter_map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase:,
        spent:,
        as_kind: spell_plan.as_heal,
      ),
      fn(heal) {
        case heal, spell_plan.telling_of(heal:) {
          spell_plan.Heal(effect_id:, vital:, aim:, condition:, formula:, ..),
            spell_plan.ToldAtGo
          ->
            // A row that aims at the area alone is told to the allies the area finds, so only
            // an area that finds them has it.
            case spell_plan.reaches_primary_target(aim:) || spell.finds_allies {
              True ->
                Ok(InstantHeal(effect_id:, vital:, aim:, condition:, formula:))
              False -> Error(Nil)
            }
          spell_plan.Heal(..), spell_plan.ToldAtEachTick
          | spell_plan.Heal(..), spell_plan.NotTold
          | spell_plan.TickingHeal(..), spell_plan.ToldAtGo
          | spell_plan.TickingHeal(..), spell_plan.ToldAtEachTick
          | spell_plan.TickingHeal(..), spell_plan.NotTold
          -> Error(Nil)
        }
      },
    )
  let starts_children =
    list.any(proxies, fn(proxy) {
      proxy.period == None && starts_on_each_unit(proxy:)
    })
  PhaseStrike(
    heals:,
    damage: list.filter(firing, fn(effect) {
      spell_plan.reaches_past_caster(aim: effect.aim)
    }),
    ticking: list.filter(ticking_firing, fn(row) {
      spell_plan.reaches_past_caster(aim: row.damage.aim)
    }),
    controls:,
    gates:,
    selects_area: strikes(fn(aim) { spell_plan.reaches_area(aim:) })
      || starts_children
      || {
      spell.finds_allies
      && list.any(heals, fn(heal) { spell_plan.reaches_area(aim: heal.aim) })
    },
    strikes_area: strikes_without_changes(fn(aim) {
      spell_plan.reaches_area(aim:)
    })
      || {
      !spell.finds_allies
      && list.any(changes, fn(aim) { spell_plan.reaches_area(aim:) })
    },
    acts_on_each_unit: starts_children || changes_allies,
    strikes_primary_target: strikes(fn(aim) {
      spell_plan.reaches_primary_target(aim:)
    }),
    ticks_on_area: list.any(proxies, fn(proxy) {
      starts_on_each_unit(proxy:) && option.is_some(proxy.period)
    }),
  )
}

/// Whether a Proxy starts its child on the units of the area, each struck unit or each ally.
fn starts_on_each_unit(proxy proxy: spell_plan.Proxy) -> Bool {
  case proxy.target {
    spell_plan.OnEachStruck | spell_plan.OnEachAlly -> True
    spell_plan.OnCaster | spell_plan.OnPrimaryTarget -> False
  }
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

/// How a unit counts as inside the spell's area at go `phase`: the hit shapes of the rows
/// that go names when the spell has any, capped by the area row's range, else the area row's
/// range and arc. `None` when the spell has hit rows and none names the go, or has no such
/// go: the go strikes nobody from the area.
pub fn inside(spell spell: SpellArea, phase phase: Int) -> Option(Inside) {
  use <- bool.guard(when: phase < 0, return: None)
  case list.drop(spell.inside_by_go, phase) {
    [inside, ..] -> inside
    [] -> None
  }
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
  use read <- result.try(area_row_of(tables:, id:, row:))
  case read {
    None -> Ok(None)
    Some(ByHealth(target_selection:)) ->
      Error(SelectionNeedsHealth(spell4_id: id, target_selection:))
    Some(ByMissingHealth(..)) ->
      Error(SelectionNeedsHealth(spell4_id: id, target_selection: 5))
    Some(Ordered(row: area_row)) -> {
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
/// (`hit_shapes_of`) that the client is drawing at the go's time (genesis_prime/shared/telegraph_window)
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
  use placed <- result.try(placed_rows(
    id:,
    rows: hit_rows,
    reading: CreatureReading,
  ))
  Ok(
    list.index_map(go_times_ms, fn(_, go) {
      shapes_at_go(placed:, go:, phased:, drawn: fn(row) {
        is_twin(row:) || telegraph_window.drawn_at(row:, go_times_ms:, go:)
      })
    }),
  )
}

/// How a unit counts as inside at go `go` of a cast with the hit rows `placed` (each with its
/// placements): `InsideRow` when the spell has no hit row, `None` when it has some and none
/// is kept. A row is kept when `drawn` holds for it and, when the client compares the cast's
/// phase with a row's (`phased`), when its phaseFlags name the go.
fn shapes_at_go(
  placed placed: List(#(telegraph_damage.TelegraphDamage, List(Placement))),
  go go: Int,
  phased phased: Bool,
  drawn drawn: fn(telegraph_damage.TelegraphDamage) -> Bool,
) -> Option(Inside) {
  use <- bool.guard(when: placed == [], return: Some(InsideRow))
  let struck =
    list.filter(placed, fn(found) {
      let #(row, _) = found
      {
        !phased
        || spell_effect.names_phase(phase_flags: row.phase_flags, phase: go)
      }
      && drawn(row)
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
  phase_count_of(spell: spell.spell)
}

/// `phase_count` of a spell no `SpellArea` holds yet.
fn phase_count_of(spell spell: Spell) -> Int {
  int.max(1, spell_plan.go_count(spell:))
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
      missing: "a player's ability whose drawn row is placed by the server (flag 0x1000 or 0x4000) is sent no initial or telegraph position in its 0x7ff and 0x7fd, so the client draws none of that row; only a creature's special is sent them",
    ),
    gap.Entry(
      area: "Proc spells with a hit row on the target",
      missing: "a hit row on the target of a spell a proc casts at another unit (ProcAim AtOtherUnit) is built only as a circle with no offset, since the strike does not know that unit's yaw, and the load does not tell whether the event has another unit, which the spell is then cast at the holder for; a spell aimed at its holder is built as a press's is",
    ),
    gap.Entry(
      area: "Periodic area Proxies",
      missing: "a Proxy with a tickTime aimed at the area casts the Spell4 it names (in dataBits00, or dataBits01 when that is 0) on the units inside the area at each tick, as the texts say (\"foes inside the field every Ns\", 574032 and 306769): the units are found over the connection's picture by the spell's area row and hit shapes, around the pose the cast started at (or the pose the primary target stood in at the go, for an area fixed at its target), and the order a Random row takes at a tick is seeded by the cast and the tick, a guess since the client names the order and ranks nothing; a Proxy that names a beneficial spell (Spell4TargetMechanics flags bit 0) is refused with its ability until the allies in the area can be found (Field Probes 41398); the Snare of Restrictor's field is shown to each creature found and slows none, since no rule reads a state's slow",
    ),
    gap.Entry(
      area: "Creature target and ground rows",
      missing: "a creature's hit row placed on the ground (targetTypeFlags bit 8, 34 listed spells with it alone) or on each unit the strike finds (bit 4, 3 listed spells) is refused, as is one placed on two units at once (flags 3 and 9); a player's ability whose hit row is placed on each struck unit (bit 4) or on two units at once is refused, and so is one whose row is placed on the target of a spell that is started on another unit with a shape that reads the unit's facing (the strike knows a unit's place, not its yaw) or that is pressed while its target mechanic names a target or a spot (the press reads neither)",
    ),
    gap.Entry(
      area: "Player hit rows by anchor",
      missing: "a player's drawn row placed otherwise than its hit rows is not compared with them, so the picture and the hit disagree when the caster has moved between the start and the go (three planned abilities)",
    ),
    gap.Entry(
      area: "Player hit rows by go",
      missing: "a player's cast strikes at a go with the hit rows its phase names for a cast whose phase the client compares (a Multiphase cast, or a channel whose spellChannelFlags has bit 1), and with every hit row for any other cast; the row's time window is not read (a creature's cast reads both), and a go whose phase no hit row names strikes nobody from the area, a guess the client's code does not settle: it compares a row's phase with a go only to launch client missiles, the window would strike nobody at the later gos of a spell that is not phased, such as Discharge 58832 at its second and third pulse, and the two rules strike the same units for every planned phased spell",
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
      area: "Player area orders",
      missing: "a player's area ordered by lowest health (Spell4AoeTargetConstraints targetSelection 4, which no planned ability names) is read as no area and refused for a phase that selects units from it; an area ordered by missing health (targetSelection 5) is built only for a friendly area (`SpellArea.finds_allies`) whose phases select units by its instant heals or by a Proxy with no tickTime that starts a child on each ally (Sentinel 54395, Mending Banner 33345, Mental Boon 33257 and Astral Infusion 35870; Warden 33392 and Barrier 78081 start a child whose hit row, a circle, is on the ally); Mental Boon says \"hurt allies\" (text 245408) and the order keeps an ally at full health a candidate after every hurt one, so a cast with fewer hurt allies than its count starts a child on unhurt ones too, a guess; an area that only a Proxy at the area uses never takes the caster as a candidate, since a Proxy names no caster of its own and no table field tells Affinity's \"yourself and an ally\" (text 316675) from Mending Banner's \"most injured ally\" (text 246918), a guess; the missing health is the maximum less the health as the caster's client was told of each ally, an amount and not a fraction, with ties to the nearer unit then the lower unit id and an ally at full health a candidate after every hurt one, all guesses, the client naming order 5 and ordering nothing; an area that finds the caster's allies (an instant heal aimed at it) selects the other Friendly players the caster has in sight, and the caster too as a candidate when a heal row of the phase is aimed at the area alone and none names the caster (Triage, Dual Fire and Regenerative Pulse, \"yourself or an ally\", text 195454; at distance 0 with no shape test when the area is centred on the caster, and from where it stands, by the area's own shape, when the area is centred on an ally a child cast was started on; the client names no order, so the caster's rank among units missing as much health, and first when every unit is at full health, is a guess), never the caster for a phase with a row that names it, which heals it by its flag, and an area whose valid targets hold bit 16 (the caster's party only) finds nobody, since every player has the group id 0; Furthest measures from the area's centre, Random orders by a mix of the cast id and the unit id (and, at a tick of a periodic Proxy, of the tick) and every go of a cast ranks alike, all guesses, the client naming the orders and ordering nothing",
    ),
    gap.Entry(
      area: "Player area around another player",
      missing: "a cast whose primary target is another player centres its area on the ground point of that player's place with yaw 0.0, a guess: the stored place carries the viewer's own facing and no message tells the player's, so a shape that reads a facing, or an area row under 360 degrees where no hit shape is drawn, is not built for a child cast on an ally (`start_placed`); only a child a Proxy starts on an ally has an area of its own centred on a player (Warden's 36660 and Barrier's 41369), and no press reaches another player's area: no beneficial spell that names its target and is pressed selects units from its area, and a hostile one is refused while no player is PvP flagged",
    ),
    gap.Entry(
      area: "Player area valid targets",
      missing: "a row aimed at the cast's primary target strikes that unit whatever bits 4 (only players) and 16 (only the caster's party) of the spell's valid targets say, where the area's own selection honours them (the primary target joins the selected units after the area's, `strike.select`)",
    ),
    gap.Entry(
      area: "Spell valid targets",
      missing: "a spell with an area row whose valid targets (Spell4ValidTargets targetBitmask) hold bit 8 (strike the dead), 32 (a creature cluster only) or 64 (units in combat only) is refused with its ability, since a strike picks the alive and the server holds no creature cluster; bit 128, which the client copies and no code reads, is read as clear, a guess; an area whose valid targets hold bit 4 (players only) or 16 (party members only) selects no creature, so a row aimed at that area alone lands on nobody, since the units a strike chooses from are creatures; an area whose valid targets hold bit 16 finds no ally either, since no player has a group (Defense Grid's 54475, Volatile Injection's 41756, Emergency Reserves' 32358 and Empowering Probes' 41533 are read and reach nobody); bit 256 (not a pet) excludes no unit, since the server stands no unit as a pet",
    ),
    gap.Entry(
      area: "Creature area orders and shapes",
      missing: "a creature's area that selects by a unit's health (Spell4AoeTargetConstraints targetSelection 4 and 5, 2 listed creature spells) is refused, since a creature's sight of a fighter holds no health; a hit row of shape 8 with a box (param03 or param05 above 0) is refused for a creature and a player, its box not read; Random's order is a guess, the client naming it and ordering nothing",
    ),
  ]
}
