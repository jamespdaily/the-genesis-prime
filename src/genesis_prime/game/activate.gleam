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
//// - A spell with an effect the strike would apply, aimed at the target or an area, is
////   refused with result 285 and logged once, since the activate cast strikes no unit
////   (gap, #336).
//// - **The target's life** is judged before the range: the spell's target row says a dead
////   creature is refused 106 or a living one 107 (`CheckCastUnitTargetRange`,
////   `0x1403b2240`). A unit hostile to the player or in combat is offered no use at all
////   (`Withheld`, result 100).
//// - Gaps, each closed by the quests, zones and prerequisites issue (#334): the client's
////   per-unit vertical offset and the creature words 0x6c and 0x148 that make the client
////   pick no spell are not modelled; nor are the target row's crowd-control and
////   fight-state conditions and the unit word 0xc4 that bit 5 reads (`planned`).

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/creature2
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Spell4EffectsId, GameFormulaId, PrerequisiteId, Spell4ConditionsId,
  Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_conditions
import genesis_prime/world_map/creature_path
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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
    /// Creature2.flags bit 0: with no cast group a cast may target the creature only by
    /// its own activate spell (`CheckCastActivateSpell 0x1403b44b0`).
    only_own_spells: Bool,
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
    only_own_spells: int.bitwise_and(row.flags, 1) == 1,
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
  /// The spell's plan, its Activate effects in row order, the RavelSignal rows aimed at
  /// the target that the activate cast drops, and its Spell4 limits. A spell of a method
  /// the cast rule does not build is held too: the press is refused as an ability's is
  /// (`cast.verdict`).
  Planned(
    spell: Spell,
    effects: List(ActivateEffect),
    dropped_signals: List(Spell4EffectsId),
    limits: Limits,
  )
  /// The Spell4 table has no row for the spell: result 4.
  NoSpell4Row
  /// The spell's tree cannot be planned: the reason in words.
  CannotBePlanned(why: String)
}

/// The activate spells' plans and the Prerequisite rows of the columns, as the load
/// built them. A link column's prerequisite whose row the table lacks is not held (47
/// creatures name 33 such ids): the client fails a prerequisite it cannot find
/// (`Prerequisite.flags`), so the link is closed (`objective_link.of`).
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
        AnimPrerequisiteNotLoaded(error:) ->
          prerequisite.describe_load_error(error:)
      }
    })
  })
}

/// Why the activations cannot be built from the tables.
type BuildError {
  NoDefaultSpellFormula
  PrerequisiteNotLoaded(error: spell_plan.PlanError)
  AnimPrerequisiteNotLoaded(error: prerequisite.LoadError)
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
    |> list.unique
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
  use anim_prerequisites <- result.try(
    list.try_fold(
      anim_prerequisite_ids(tables:),
      [],
      fn(loaded, prerequisite_id) {
        case
          prerequisite.load(
            id: PrerequisiteId(prerequisite_id),
            rows:,
            arcs:,
            quests:,
          )
        {
          Ok(held) -> Ok([#(prerequisite_id, held), ..loaded])
          // The client fails a prerequisite it has no row for (`Prerequisite.flags`), so
          // such a link is closed; the tables name rows they lack (see `Activations`).
          Error(prerequisite.NoPrerequisiteRow(..)) -> Ok(loaded)
          Error(error) -> Error(AnimPrerequisiteNotLoaded(error:))
        }
      },
    ),
  )
  let spell_ids =
    [default_spell, ..list.map(columns, fn(column) { column.spell4_id })]
    |> list.filter(fn(spell4_id) { spell4_id != 0 })
    |> list.unique
  let sources = spell_plan.sources_of(tables:)
  Ok(Activations(
    prerequisites: list.filter_map(prerequisites, fn(entry) {
      option.to_result(entry.1, Nil)
      |> result.map(fn(loaded) { #(entry.0, loaded) })
    })
      |> list.append(anim_prerequisites)
      |> dict.from_list,
    spells: list.map(spell_ids, fn(spell4_id) {
      #(spell4_id, planned(tables:, sources:, spell4_id:))
    })
      |> dict.from_list,
    default_spell:,
  ))
}

/// The ids of the Prerequisite rows the creatures' link columns name
/// (`Creature2.prerequisiteIdAnimState`).
fn anim_prerequisite_ids(tables tables: table_store.Tables) -> List(Int) {
  creature2.all(tables)
  |> list.map(fn(row) { row.prerequisite_id_anim_state })
  |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
  |> list.unique
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
          case
            unread_target_bits(
              tables:,
              conditions_id: row.spell4_conditions_id_target,
            )
          {
            Some(#(mask, unread)) ->
              CannotBePlanned(
                why: "the spell "
                <> int.to_string(spell4_id)
                <> " tests the bits "
                <> int.to_string(unread)
                <> " of its target conditions row "
                <> int.to_string(row.spell4_conditions_id_target)
                <> " (mask "
                <> int.to_string(mask)
                <> "), which the activate cast does not read",
              )
            None -> planned_rows(spell:, sources:, spell4_id:, row:)
          }
      }
  }
}

/// The mask of a Spell4Conditions row of a target and its bits that the activate cast
/// does not read (`spell_plan.target_mask_read`), when it has any.
///
/// Gap: the client also tests the unit's crowd-control state, its fight state and the
/// creature word 0x1e4 against such a row, and the meaning of the unit word 0xc4 that
/// bit 5 tests is not decoded, so bit 5 passes (#334); no activate spell of the tables
/// tests a bit outside the ones read, so the spell that does is not planned.
fn unread_target_bits(
  tables tables: table_store.Tables,
  conditions_id conditions_id: Int,
) -> Option(#(Int, Int)) {
  case conditions_id {
    0 -> None
    id ->
      case spell4_conditions.get(tables:, id: Spell4ConditionsId(id)) {
        Error(Nil) -> None
        Ok(row) ->
          case
            int.bitwise_and(
              row.condition_mask,
              int.bitwise_not(spell_plan.target_mask_read),
            )
          {
            0 -> None
            unread -> Some(#(row.condition_mask, unread))
          }
      }
  }
}

fn planned_rows(
  spell spell: Spell,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
  row row: spell4.Spell4,
) -> Planned {
  case activate_rows_of(sources:, spell4_id:) {
    Error(AimedAtTarget(effect_id:)) ->
      CannotBePlanned(
        why: "the effect "
        <> int.to_string(effect_id)
        <> " of the spell "
        <> int.to_string(spell4_id)
        <> " aims at the target or an area, and the activate cast strikes no one",
      )
    Ok(ActivateRows(effects:, dropped_signals:)) ->
      Planned(
        spell:,
        effects:,
        dropped_signals:,
        limits: Limits(
          min: row.target_min_range,
          max: row.target_max_range,
          vertical: row.target_vertical_range,
        ),
      )
  }
}

/// An effect of an activate spell that aims at the target or an area and that the strike
/// would apply.
type AimedAtTarget {
  AimedAtTarget(effect_id: Int)
}

/// What an activate spell's rows leave for the activate cast.
type ActivateRows {
  ActivateRows(
    effects: List(ActivateEffect),
    dropped_signals: List(Spell4EffectsId),
  )
}

/// The Activate rows of the spell and the RavelSignal rows it drops, or the first effect
/// that aims at the target or an area and that the strike would apply.
///
/// Gap: the activate cast carries out the caster's effects and the Activate rows and
/// strikes no unit, so a spell with such an effect would lose it without a word; it is
/// refused instead, until the issue for spells in depth (#336) builds the strike of an
/// activate cast. An effect is one the strike applies when `effect_kind.is_row_read`
/// holds for its type and aim: the strike lists a Fluff or Scale row as a life on each
/// struck unit (genesis_prime/game/cast `aimed_at`) and starts a Proxy's spell at it. A
/// row of a type no rule reads is dropped by every cast, so it does not refuse the spell.
///
/// A RavelSignal row aimed at the target does not refuse the spell, and the activate cast
/// drops it: the row starts a script on the server (`Spell4Effects.effectType.81`), and
/// the server has none to start until the issue for spells in depth (#336) builds them;
/// the client holds no script for it, so what it shows is not lost. The tutorial mine's
/// activate spell 85452 holds two such rows. They are returned, and the cast logs them
/// once when it drops them (`cast.activation_started`).
fn activate_rows_of(
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Result(ActivateRows, AimedAtTarget) {
  let #(activates, others) =
    spell_plan.effects_of(sources:, spell4_id:)
    |> list.partition(fn(effect) {
      effect_kind.kind_of(effect_type: effect.effect_type)
      == effect_kind.Activate
    })
  let #(signals, others) =
    list.partition(others, fn(effect) {
      spell_plan.aim_of(target_flags: effect.target_flags)
      != spell_plan.AimsAtCaster
      && effect_kind.kind_of(effect_type: effect.effect_type)
      == effect_kind.RavelSignal
    })
  case
    list.find(others, fn(effect) {
      spell_plan.aim_of(target_flags: effect.target_flags)
      != spell_plan.AimsAtCaster
      && effect_kind.is_row_read(
        effect_type: effect.effect_type,
        target_flags: effect.target_flags,
      )
    })
  {
    Ok(effect) -> Error(AimedAtTarget(effect_id: effect.id))
    Error(Nil) ->
      Ok(ActivateRows(
        effects: list.map(activates, fn(effect) {
          ActivateEffect(
            effect_id: Spell4EffectsId(effect.id),
            delay_ms: effect.delay_time,
          )
        }),
        dropped_signals: list.map(signals, fn(effect) {
          Spell4EffectsId(effect.id)
        }),
      ))
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
  /// A creature or static object the player can see: the id of its Creature2 row, what
  /// the row says of its activate cast, the checklist index its 0x262 carried (the bit a
  /// type 94 condition of its activate pick reads), whether the player's quest log opens
  /// the creature's link to an objective, where it stands now (a creature that walks a
  /// path stands where its path puts it at the press), whether it lives, and why the
  /// client offers no use of it, if it does not.
  Usable(
    creature_id: Int,
    creature: Creature,
    checklist_index: Int,
    link: Link,
    body: Body,
    alive: Bool,
    /// Whether the creature is in combat, which a cast's target conditions may test (bit 1
    /// of the target row's mask).
    in_combat: Bool,
    withheld: Option(Withheld),
  )
}

/// Why the client offers a unit no use of it (`PickInteractionKind`, `0x14047a060`): the
/// press is refused with result 100.
pub type Withheld {
  /// The unit is hostile to the player: the client skips the interaction kinds of a use.
  HostileToPlayer
  /// The unit is in combat: the client gives it no click at all.
  InCombat
}

/// Whether the player's quest log opens a creature's link to an objective, which the
/// client's offer of the creature's activation waits for (`0x14046c4d0`).
pub type Link {
  /// The creature has no quest animation column and no animation prerequisite: nothing
  /// holds its activation back.
  NoLink
  /// The creature's link is open: the client offers its activation.
  OpenLink
  /// The creature's link is closed: the client offers it nothing at all, and the server
  /// takes no activation of it.
  ClosedLink
  /// The creature's animation prerequisite has a condition of this PrerequisiteType that
  /// the server does not read, so the client's offer cannot be told: the server takes no
  /// activation of it.
  UnreadLink(prerequisite_type: Int)
}

/// The range of the client's use of a unit whose creature has no activate spell (0xb3):
/// the interaction entry of kind 39 holds range 0.0, which ClickInteraction replaces by
/// 5.0 (`0x14039d2c0`, `0x140c48c48`), tested edge to edge in three dimensions with no
/// height limit (`0x1403ebe80`).
pub const use_limits = Limits(min: 0.0, max: 5.0, vertical: -1.0)

/// A unit's body for the range test: where it stands (y is up) and its hit radius.
pub type Body {
  Body(place: Place, radius: Float)
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
  float.max(
    creature_path.distance(from: from.place, to: to.place)
      -. from.radius
      -. to.radius,
    0.0,
  )
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
    float.absolute_value(
      start_place.y(target.place) -. start_place.y(caster.place),
    )
    -. caster.radius
    -. target.radius
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

/// Why the cast group rule does not pass a target.
pub type CastGroupRefusal {
  /// Result 89 (TargetGroup).
  OutsideGroup
  /// The creature's activate pick holds a condition the server does not read, so whether
  /// its activate spell is the cast spell cannot be told.
  PickUnread(prerequisite_type: Int)
  /// A cast group tests a player by words the server does not hold (a player's faction
  /// and race), so the group's verdict cannot be told.
  PlayerUnread
}

/// The client's cast group rule for a cast of `spell4_id` at a unit (`CheckCastActivateSpell
/// 0x1403b44b0`), which runs after the target's conditions and before the faction test and
/// the range. In order:
/// - a creature whose activate spell is the cast spell passes;
/// - else a cast group decides: `in_cast_group(cast_group_id, unit_id)` for a member, 89
///   for a non-member;
/// - else a creature whose Creature2.flags bit 0 is set is refused 89;
/// - else the cast passes.
///
/// `picked` is the creature's activate pick, read only when the outcome depends on it: a
/// group that holds the unit, and a creature with no flag bit 0 and no group, pass whatever
/// the pick is.
pub fn passes_cast_group(
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  unit_id unit_id: Int,
  target target: Target,
  picked picked: fn() -> Pick,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> Result(Nil, CastGroupRefusal) {
  case target {
    Unseen -> Error(OutsideGroup)
    AnotherPlayer ->
      case cast_group_id {
        0 -> Ok(Nil)
        _ -> Error(PlayerUnread)
      }
    Usable(creature:, ..) -> {
      let holds = cast_group_id != 0 && in_cast_group(cast_group_id, unit_id)
      let needs_pick = case cast_group_id {
        0 -> creature.only_own_spells
        _ -> !holds
      }
      use <- bool.guard(when: !needs_pick, return: Ok(Nil))
      case picked() {
        Picked(spell4_id: own) if own == spell4_id -> Ok(Nil)
        Picked(..) | NoActivateSpell -> Error(OutsideGroup)
        Unread(prerequisite_type:) -> Error(PickUnread(prerequisite_type:))
      }
    }
  }
}
