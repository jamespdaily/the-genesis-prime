//// Which damage effects of a creature's attack spell apply to a creature, by each
//// effect's caster prerequisite: the one rule the content load (the creature kind's
//// check, genesis_prime/world_map/creature_kind, and the spawn's attack,
//// genesis_prime/world_map/spawn) reads them by.
////
//// ```
//// Spell4Effects of the spell, type 8 (Damage), in order
////   no caster prerequisite                       ─▶ applies
////   a prerequisite of type 179 (the difficulty)  ─▶ applies when the creature's difficulty passes it
////   a prerequisite of any other type             ─▶ the load refuses the spell (`unevaluated`)
////   a tickTime other than 0 (a periodic effect)  ─▶ the load refuses the spell (`unevaluated`)
//// the spell's cast prerequisite (Spell4.prerequisiteIdCasterCast)
////   none, or one condition of type 15            ─▶ answered
////   any other                                    ─▶ the load refuses the spell
//// each applying damage effect's formula (`formulas`, `loadable`)
////   a finite multiplier, parameters the creature formula reads ─▶ applies
////   otherwise                                    ─▶ the load refuses the spell
//// ```
////
//// - **Type 179** compares the unit's difficulty with the condition's object id,
////   unsigned: 1 equal, 2 not equal, 3 above, 4 at least, 5 below, 6 at most
////   (`0x14049eeb0`, decoded and checked by genesis_prime/game/prerequisite). A
////   creature's difficulty is its Creature2 row's (`0x14045ba40`).
//// - **One condition is read.** Prerequisite rows hold three; a row that keeps
////   a second condition (the client keeps those before the first of type 0,
////   `0x1404a5190`) is not evaluated, and the load refuses it as an unevaluated type.
//// - **No spend.** A spell whose Spell4 row holds an innate cost EMM id spends and
////   chooses its effects by the points spent (genesis_prime/game/spend), which a
////   creature's attack has none of, so the load refuses it
////   (`Spell4.innateCostEMMId0`).
//// - **The formula** is read for a creature's difficulty (`loadable`): an
////   auto-attack or special row whose formula names a parameter the creature formula does
////   not read (`damage.creature_unread`) is refused at the kind load, which the spawn load
////   would otherwise refuse later, and the spawn load takes the same rule (`formulas`).
//// - **The client applies no effect itself**: the server names the effect in
////   0x7f4, so the server follows the table's prerequisite (`Spell4Effects.184741`).

import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/game/spell_area
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string

/// The prerequisite type of the unit's difficulty (`0x14049eeb0`).
const difficulty_type = 179

/// Why a damage effect's caster prerequisite is not one the server evaluates.
pub type Unevaluated {
  /// The prerequisite row is missing from the client's table.
  NoPrerequisiteRow(spell4_effects_id: Int, prerequisite_id: Int)
  /// The prerequisite's condition is of a type other than 179, or it holds more
  /// than one condition.
  OtherType(spell4_effects_id: Int, prerequisite_id: Int, type_id: Int)
  /// The prerequisite nests itself through the rows it nests (type 11): the ids from the
  /// named row to the one that repeats.
  NestedCycle(spell4_effects_id: Int, path: List(Int))
  /// The prerequisite nests a row with a type 108 condition naming a PositionalRequirement
  /// row the client's table lacks.
  NoPositionalRequirementRow(
    spell4_effects_id: Int,
    positional_requirement_id: Int,
  )
  /// The prerequisite nests a row with a quest condition (types 6, 68, 43 and 22 to 36)
  /// whose quest has an objective slot naming a QuestObjective row the client's table
  /// lacks.
  NoQuestObjectiveRow(spell4_effects_id: Int, objective_id: Int)
  /// The damage effect holds a tickTime, so it strikes every tick for its duration
  /// (`Spell4Effects.tickTime`), which a creature's attack, one blow per effect, does
  /// not do.
  PeriodicDamage(spell4_effects_id: Int, tick_ms: Int)
  /// The spell's Spell4 row holds an innate cost EMM id, which would choose its
  /// damage effects by points a creature's attack does not spend.
  SpendsByEmmId(spell4_id: Int, emm_id: Int)
  /// The spell's caster cast prerequisite (`Spell4.prerequisiteIdCasterCast`) is a row the
  /// client's table lacks, holds a condition of a type other than 15 (a unit that is the
  /// target of a live cast, the one the charge's own cast answers), or holds more than one.
  CastPrerequisiteNotAnswered(
    spell4_id: Int,
    prerequisite_id: Int,
    type_id: Int,
  )
  /// A damage effect's formula names a parameter the creature formula does not read
  /// (genesis_prime/game/damage `creature_unread`): the type of the first it does not.
  FormulaNotRead(spell4_effects_id: Int, parameter_kind: Int)
  /// A damage effect's multiplier, dataBits00 read as a 32-bit float, is not finite
  /// (genesis_prime/game/damage `formula_of`).
  MultiplierNotFinite(spell4_effects_id: Int, bits: Int)
  /// The special's Spell4 has no row in the client's table.
  NoSpellRow(spell4_id: Int)
  /// The special's cast time is 0: a special is a cast with a cast bar.
  NotACast(spell4_id: Int)
  /// The special's Spell4 names a target conditions row (`spell4CCConditionsIdTarget`), a
  /// state its target must or must not hold, which no creature special reads.
  TargetConditionNotRead(spell4_id: Int, conditions_id: Int)
  /// The plan cannot read the special (genesis_prime/game/spell_plan `spell_alone`).
  NotPlanned(spell4_id: Int, error: spell_plan.PlanError)
  /// The special has no go time: a spell held until its release.
  NoGo(spell4_id: Int)
  /// The special's go times (milliseconds from the cast's start) do not rise.
  GosDoNotRise(spell4_id: Int, times_ms: List(Int))
  /// No damage row of the special names a go, so the cast strikes nobody.
  NoStrikePhase(spell4_id: Int)
  /// The special's damage rows name several gos (indexes in the spell's gos), which the
  /// creature's fight does not run.
  SeveralStrikes(spell4_id: Int, gos: List(Int))
  /// The special's damage rows name one go and it is not the last, which the creature's
  /// fight does not run.
  StrikesBeforeTheLastGo(spell4_id: Int, go: Int, last_go: Int)
  /// An effect row of the special is of a type other than damage (8) and NpcExecutionDelay
  /// (35).
  OtherEffectType(spell4_effects_id: Int, effect_type: Int)
  /// The special has no area row, so its telegraph selects nobody.
  NoAreaRow(spell4_id: Int)
  /// The special's area cannot be read from the tables.
  AreaNotRead(spell4_id: Int, error: spell_area.AreaError)
  /// An NpcExecutionDelay row the plan does not apply: aimed at a unit other than the caster,
  /// with no duration, or selected by no phase.
  DelayNotApplied(spell4_effects_id: Int)
  /// An NpcExecutionDelay row that names a go other than the strike go.
  DelayNamesAnotherGo(spell4_effects_id: Int, gos: List(Int), strike_go: Int)
  /// An NpcExecutionDelay row behind a prerequisite, which no rule reads for a delay.
  DelayBehindPrerequisite(spell4_effects_id: Int, prerequisite_id: Int)
}

const damage_effects_key: table_store.DerivedKey(Dict(Int, List(Spell4Effects))) =
  table_store.DerivedKey("CreatureDamageEffects")

/// The damage effects (type 8) of each spell, in the order they take effect
/// (`Spell4Effects.orderIndex`, then the row id), as a value the tables' load builds once
/// (genesis_prime/table/loader/store `derived`): the content load asks for them once for
/// every spell of every creature, and the table holds one row per effect of every spell.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: damage_effects_key, build: fn(tables) {
    Ok(
      spell4_effects.all(tables)
      |> list.filter(fn(effect) {
        effect_kind.kind_of(effect.effect_type) == effect_kind.Damage
      })
      |> list.group(fn(effect) { effect.spell_id })
      |> dict.map_values(fn(_, effects) {
        list.sort(effects, fn(first, second) {
          int.compare(first.order_index, second.order_index)
          |> order.break_tie(int.compare(first.id, second.id))
        })
      }),
    )
  })
}

/// The damage effects (type 8) of the spell, in the order they take effect, from the value
/// the tables' load built.
pub fn damage_effects(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(Spell4Effects) {
  table_store.derived(tables:, key: damage_effects_key)
  |> dict.get(spell4_id)
  |> result.unwrap([])
}

/// The prerequisite type of a unit that is the target of a live cast
/// (`game/prerequisite`, TargetOfLiveCast): the one cast prerequisite a creature's
/// attack answers, since a charge is itself such a cast.
const target_of_live_cast_type = 15

/// A cast prerequisite of the spell's Spell4 row that holds one condition of type 15, or
/// none; `Ok(Nil)` for a spell with no Spell4 row.
fn answers_its_cast_prerequisite(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> Ok(Nil)
    Ok(row) ->
      case row.prerequisite_id_caster_cast {
        0 -> Ok(Nil)
        id ->
          case prerequisite.get(tables, PrerequisiteId(id)) {
            Error(Nil) ->
              Error(CastPrerequisiteNotAnswered(
                spell4_id:,
                prerequisite_id: id,
                type_id: 0,
              ))
            Ok(prerequisite_row) ->
              case game_prerequisite.condition_types(row: prerequisite_row) {
                [type_id] if type_id == target_of_live_cast_type -> Ok(Nil)
                [type_id, ..] ->
                  Error(CastPrerequisiteNotAnswered(
                    spell4_id:,
                    prerequisite_id: id,
                    type_id:,
                  ))
                [] ->
                  Error(CastPrerequisiteNotAnswered(
                    spell4_id:,
                    prerequisite_id: id,
                    type_id: 0,
                  ))
              }
          }
      }
  }
}

/// An innate cost EMM id of the spell's Spell4 row, a spend a creature's attack
/// cannot make; `Ok(Nil)` for a spell with none or with no Spell4 row.
fn spends_nothing(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> Ok(Nil)
    Ok(row) ->
      case
        list.find(
          [row.innate_cost_emm_id0, row.innate_cost_emm_id1],
          fn(emm_id) { emm_id != 0 },
        )
      {
        Ok(emm_id) -> Error(SpendsByEmmId(spell4_id:, emm_id:))
        Error(Nil) -> Ok(Nil)
      }
  }
}

/// The first reason the spell is not one the server applies to a creature: an
/// innate cost EMM id, or a damage effect whose caster prerequisite it does not
/// evaluate; `Ok(Nil)` when there is none.
pub fn evaluated(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  use Nil <- result.try(spends_nothing(tables:, spell4_id:))
  use Nil <- result.try(answers_its_cast_prerequisite(tables:, spell4_id:))
  damage_effects(tables:, spell4_id:)
  |> list.try_each(fn(effect) {
    use Nil <- result.try(strikes_once(effect:))
    condition(tables:, effect:) |> result.replace(Nil)
  })
}

/// The first reason the spell is not one the creature's fight can cast as a special, or
/// `Ok(Nil)`: it has a cast time (a cast bar); the attack rule evaluates it (`evaluated`);
/// it names no target conditions; the plan reads it; its damage rows name exactly one go,
/// the last; it holds rows of damage (8) and NpcExecutionDelay (35) alone; its area reads;
/// and each delay row aims at the caster alone with a duration, names the strike go alone
/// and sits behind no prerequisite. A cast with several hits or hits before its last go is
/// one a later step of the creature-casts plan runs. `sources` are the plan's rows
/// (`spell_plan.sources_of`), grouped once by the load.
pub fn special_checked(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  use row <- result.try(
    spell4.get(tables:, id: Spell4Id(spell4_id))
    |> result.replace_error(NoSpellRow(spell4_id:)),
  )
  use Nil <- result.try(case row.cast_time > 0 {
    True -> Ok(Nil)
    False -> Error(NotACast(spell4_id:))
  })
  use Nil <- result.try(evaluated(tables:, spell4_id:))
  use Nil <- result.try(case row.spell4_cc_conditions_id_target {
    0 -> Ok(Nil)
    conditions_id -> Error(TargetConditionNotRead(spell4_id:, conditions_id:))
  })
  use spell <- result.try(
    spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
    |> result.map_error(fn(error) { NotPlanned(spell4_id:, error:) }),
  )
  let times_ms = spell_plan.go_times_ms(spell:)
  use Nil <- result.try(gos_rise(spell4_id:, times_ms:))
  let effects = spell_plan.effects_of(sources:, spell4_id:)
  let go_count = list.length(times_ms)
  use strike_go <- result.try(strike_go_of(spell4_id:, effects:, go_count:))
  use Nil <- result.try(only_damage_and_delay(effects:))
  use Nil <- result.try(area_read(tables:, spell4_id:))
  delays_checked(sources:, tables:, spell4_id:, effects:, strike_go:, go_count:)
}

/// The go times of a special: at least one, each above the one before.
fn gos_rise(
  spell4_id spell4_id: Int,
  times_ms times_ms: List(Int),
) -> Result(Nil, Unevaluated) {
  case times_ms {
    [] -> Error(NoGo(spell4_id:))
    [_, ..after] ->
      case
        list.zip(times_ms, after)
        |> list.all(fn(pair) { pair.0 < pair.1 })
      {
        True -> Ok(Nil)
        False -> Error(GosDoNotRise(spell4_id:, times_ms:))
      }
  }
}

/// The indexes of the gos a row's phase flags name: bit n is go n, and a bit at or above
/// the go count names no go (`Spell4Effects.phaseFlags`).
fn gos_named(
  phase_flags phase_flags: Int,
  go_count go_count: Int,
) -> List(Int) {
  int.range(from: 0, to: go_count, with: [], run: fn(gos, go) { [go, ..gos] })
  |> list.reverse
  |> list.filter(fn(go) {
    spell_effect.has_flag(
      flags: phase_flags,
      bit: spell_effect.phase_bit(phase: go),
    )
  })
}

/// The one go the damage rows name, which has to be the last.
fn strike_go_of(
  spell4_id spell4_id: Int,
  effects effects: List(Spell4Effects),
  go_count go_count: Int,
) -> Result(Int, Unevaluated) {
  let named =
    list.filter(effects, fn(effect) {
      effect_kind.kind_of(effect.effect_type) == effect_kind.Damage
    })
    |> list.flat_map(fn(effect) {
      gos_named(phase_flags: effect.phase_flags, go_count:)
    })
    |> list.unique
    |> list.sort(int.compare)
  case named {
    [] -> Error(NoStrikePhase(spell4_id:))
    [go] if go == go_count - 1 -> Ok(go)
    [go] ->
      Error(StrikesBeforeTheLastGo(spell4_id:, go:, last_go: go_count - 1))
    gos -> Error(SeveralStrikes(spell4_id:, gos:))
  }
}

/// The spell's effect rows are of damage and NpcExecutionDelay alone: the first other row
/// is the refusal.
fn only_damage_and_delay(
  effects effects: List(Spell4Effects),
) -> Result(Nil, Unevaluated) {
  list.try_each(effects, fn(effect) {
    case effect_kind.kind_of(effect.effect_type) {
      effect_kind.Damage | effect_kind.NpcExecutionDelay -> Ok(Nil)
      effect_kind.Proxy
      | effect_kind.VitalModifier
      | effect_kind.Fluff
      | effect_kind.ForceRemove
      | effect_kind.CrowdControl
      | effect_kind.PropertyModifier
      | effect_kind.ForcedMove
      | effect_kind.CooldownModifier
      | effect_kind.Stealth
      | effect_kind.RemoveStealth
      | effect_kind.Heal(..)
      | effect_kind.ShieldOverload
      | effect_kind.Proc
      | effect_kind.InterruptArmor
      | effect_kind.Scale
      | effect_kind.ItemVisualSwap
      | effect_kind.RavelSignal
      | effect_kind.PropertyConversion
      | effect_kind.FullScreenEffect
      | effect_kind.DisguiseOutfit
      | effect_kind.Absorption
      | effect_kind.Activate
      | effect_kind.Immunity
      | effect_kind.Despawn
      | effect_kind.UnitState
      | effect_kind.QuestAdvance
      | effect_kind.Unread(..) ->
        Error(OtherEffectType(
          spell4_effects_id: effect.id,
          effect_type: effect.effect_type,
        ))
    }
  })
}

/// The spell has an area row its telegraph can be read from.
fn area_read(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  case spell_area.area_of_spell(tables:, spell4_id: Spell4Id(spell4_id)) {
    Error(error) -> Error(AreaNotRead(spell4_id:, error:))
    Ok(None) -> Error(NoAreaRow(spell4_id:))
    Ok(Some(_)) -> Ok(Nil)
  }
}

/// Each NpcExecutionDelay row of the spell is one the plan applies, names the strike go and
/// no other, and sits behind no prerequisite.
fn delays_checked(
  sources sources: spell_plan.Sources,
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effects effects: List(Spell4Effects),
  strike_go strike_go: Int,
  go_count go_count: Int,
) -> Result(Nil, Unevaluated) {
  let place =
    spell_plan.RowPlace(
      struck_by: None,
      spends_all: False,
      hits_foes: True,
      throws_target: False,
    )
  list.filter(effects, fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.NpcExecutionDelay
  })
  |> list.try_each(fn(effect) {
    use reading <- result.try(
      spell_plan.read_row(tables:, sources:, place:, effect:)
      |> result.map_error(fn(error) { NotPlanned(spell4_id:, error:) }),
    )
    use delay <- result.try(case reading {
      spell_plan.Applied(spell_plan.ReadEffects(effects: planned)) ->
        list.find_map(planned, fn(one) { spell_plan.as_delay(one.kind) })
        |> result.replace_error(DelayNotApplied(spell4_effects_id: effect.id))
      spell_plan.Applied(spell_plan.ReadProc(..))
      | spell_plan.Applied(spell_plan.ReadProxy(..))
      | spell_plan.Held(..)
      | spell_plan.LeftOut(..)
      | spell_plan.ReadByArea
      | spell_plan.ReadByActivation ->
        Error(DelayNotApplied(spell4_effects_id: effect.id))
    })
    use Nil <- result.try(
      case gos_named(phase_flags: delay.phase_flags, go_count:) {
        [go] if go == strike_go -> Ok(Nil)
        gos ->
          Error(DelayNamesAnotherGo(
            spell4_effects_id: effect.id,
            gos:,
            strike_go:,
          ))
      },
    )
    case
      list.find(
        [
          effect.prerequisite_id_caster_apply,
          effect.prerequisite_id_target_apply,
          effect.prerequisite_id_caster_persistence,
          effect.prerequisite_id_target_persistence,
          effect.prerequisite_id_target_suspend,
        ],
        fn(prerequisite_id) { prerequisite_id != 0 },
      )
    {
      Ok(prerequisite_id) ->
        Error(DelayBehindPrerequisite(
          spell4_effects_id: effect.id,
          prerequisite_id:,
        ))
      Error(Nil) -> Ok(Nil)
    }
  })
}

/// The damage effects of the spell that apply to a creature of `difficulty`.
fn applying(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  difficulty difficulty: Int,
) -> Result(List(Spell4Effects), Unevaluated) {
  damage_effects(tables:, spell4_id:)
  |> list.try_fold([], fn(applying, effect) {
    use Nil <- result.try(strikes_once(effect:))
    use found <- result.try(condition(tables:, effect:))
    case found {
      Unconditional -> Ok([effect, ..applying])
      Gated(prerequisite:) ->
        case
          game_prerequisite.check(
            prerequisite:,
            subject: game_prerequisite.of_difficulty(difficulty:),
          )
        {
          game_prerequisite.Passes -> Ok([effect, ..applying])
          game_prerequisite.Fails -> Ok(applying)
          game_prerequisite.NotRead(prerequisite_type:) ->
            Error(OtherType(
              spell4_effects_id: effect.id,
              prerequisite_id: game_prerequisite.id(prerequisite:).value,
              type_id: prerequisite_type,
            ))
        }
    }
  })
  |> result.map(list.reverse)
}

/// The damage effects of the spell that apply to a creature of `difficulty`, each with the
/// formula its damage comes from: `applying`, then each effect's formula
/// (`damage.formula_of`) with a multiplier that is finite and parameters the creature
/// formula reads (`damage.creature_unread`). The one rule the kind load, the spawn load and
/// the import of the retail record all take a creature's spell by.
pub fn formulas(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  difficulty difficulty: Int,
) -> Result(List(#(Spell4Effects, damage.Formula)), Unevaluated) {
  use effects <- result.try(applying(tables:, spell4_id:, difficulty:))
  list.try_map(effects, fn(effect) {
    use formula <- result.try(
      damage.formula_of(effect:)
      |> result.replace_error(MultiplierNotFinite(
        spell4_effects_id: effect.id,
        bits: effect.data_bits00,
      )),
    )
    case damage.creature_unread(formula:) {
      Some(damage.Unread(parameter_kind:)) ->
        Error(FormulaNotRead(spell4_effects_id: effect.id, parameter_kind:))
      None -> Ok(#(effect, formula))
    }
  })
}

/// Whether a creature of `difficulty` can strike with the spell: the damage effects it
/// applies are ones the server evaluates (`applying`) and their formulas read for a
/// creature (`formulas`). `Error` names the first that is not, as the spawn load would
/// refuse it, so the kind load can refuse a row before any spawn starts.
pub fn loadable(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  difficulty difficulty: Int,
) -> Result(Nil, Unevaluated) {
  formulas(tables:, spell4_id:, difficulty:) |> result.replace(Nil)
}

/// A damage effect with no tickTime, which strikes once; a tickTime is a periodic
/// effect, which one blow per effect would strike once instead of every tick.
fn strikes_once(effect effect: Spell4Effects) -> Result(Nil, Unevaluated) {
  case effect.tick_time {
    0 -> Ok(Nil)
    tick_ms -> Error(PeriodicDamage(spell4_effects_id: effect.id, tick_ms:))
  }
}

/// An effect's caster prerequisite as the server evaluates it.
type Condition {
  Unconditional
  /// A row whose one kept condition is of type 179.
  Gated(prerequisite: game_prerequisite.Prerequisite)
}

fn condition(
  tables tables: table_store.Tables,
  effect effect: Spell4Effects,
) -> Result(Condition, Unevaluated) {
  case effect.prerequisite_id_caster_apply {
    0 -> Ok(Unconditional)
    id -> {
      use row <- result.try(
        prerequisite.get(tables, PrerequisiteId(id))
        |> result.replace_error(NoPrerequisiteRow(
          spell4_effects_id: effect.id,
          prerequisite_id: id,
        )),
      )
      case game_prerequisite.condition_types(row:) {
        [type_id] if type_id == difficulty_type -> loaded(tables:, effect:, id:)
        [type_id, ..] ->
          Error(OtherType(
            spell4_effects_id: effect.id,
            prerequisite_id: id,
            type_id:,
          ))
        [] ->
          Error(OtherType(
            spell4_effects_id: effect.id,
            prerequisite_id: id,
            type_id: 0,
          ))
      }
    }
  }
}

/// The prerequisite with its nested rows loaded from the client's tables.
fn loaded(
  tables tables: table_store.Tables,
  effect effect: Spell4Effects,
  id id: Int,
) -> Result(Condition, Unevaluated) {
  game_prerequisite.load(
    id: PrerequisiteId(id),
    rows: game_prerequisite.table_rows(tables:),
    arcs: game_prerequisite.table_arcs(tables:),
    quests: game_prerequisite.table_quests(tables:),
  )
  |> result.map(fn(loaded) { Gated(prerequisite: loaded) })
  |> result.map_error(fn(error) {
    case error {
      game_prerequisite.NoPrerequisiteRow(..) ->
        NoPrerequisiteRow(spell4_effects_id: effect.id, prerequisite_id: id)
      game_prerequisite.PrerequisiteCycle(path:) ->
        NestedCycle(
          spell4_effects_id: effect.id,
          path: list.map(path, fn(on_the_way) { on_the_way.value }),
        )
      game_prerequisite.NoPositionalRequirementRow(id: arc_id) ->
        NoPositionalRequirementRow(
          spell4_effects_id: effect.id,
          positional_requirement_id: arc_id,
        )
      game_prerequisite.NoQuestObjectiveRow(objective_id:) ->
        NoQuestObjectiveRow(spell4_effects_id: effect.id, objective_id:)
    }
  })
}

/// A sentence for the load's refusal.
pub fn describe(unevaluated unevaluated: Unevaluated) -> String {
  case unevaluated {
    NoPrerequisiteRow(spell4_effects_id:, prerequisite_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " names caster prerequisite "
      <> int.to_string(prerequisite_id)
      <> ", which the client's Prerequisite table does not hold"
    OtherType(spell4_effects_id:, prerequisite_id:, type_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has caster prerequisite "
      <> int.to_string(prerequisite_id)
      <> " of type "
      <> int.to_string(type_id)
      <> ", which the server does not evaluate (only one condition of type 179, the difficulty)"
    NestedCycle(spell4_effects_id:, path:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a caster prerequisite whose rows nest each other round a cycle: "
      <> string.join(list.map(path, int.to_string), " to ")
    NoPositionalRequirementRow(spell4_effects_id:, positional_requirement_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a caster prerequisite with a type 108 condition naming PositionalRequirement "
      <> int.to_string(positional_requirement_id)
      <> ", which the client's table does not hold"
    NoQuestObjectiveRow(spell4_effects_id:, objective_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a caster prerequisite with a quest condition whose quest names QuestObjective "
      <> int.to_string(objective_id)
      <> ", which the client's table does not hold"
    PeriodicDamage(spell4_effects_id:, tick_ms:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has tickTime "
      <> int.to_string(tick_ms)
      <> ", a periodic damage effect, which a creature's attack does not strike every tick"
    SpendsByEmmId(spell4_id:, emm_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has innate cost EMM id "
      <> int.to_string(emm_id)
      <> ", which chooses its effects by points a creature's attack does not spend"
    CastPrerequisiteNotAnswered(spell4_id:, prerequisite_id:, type_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has cast prerequisite "
      <> int.to_string(prerequisite_id)
      <> " of type "
      <> int.to_string(type_id)
      <> ", which a creature's attack does not answer (only one condition of type 15, the target of a live cast, or none; type 0 is a row the client's table lacks or empty)"
    FormulaNotRead(spell4_effects_id:, parameter_kind:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " reads parameter type "
      <> int.to_string(parameter_kind)
      <> ", which the creature formula does not read"
    MultiplierNotFinite(spell4_effects_id:, bits:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a multiplier, dataBits00 "
      <> int.to_string(bits)
      <> ", that is not a finite 32-bit float"
    NoSpellRow(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has no row in the client's Spell4 table"
    NotACast(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has a cast time of 0 (castTime), and a special is a cast with a cast bar"
    TargetConditionNotRead(spell4_id:, conditions_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has target conditions row "
      <> int.to_string(conditions_id)
      <> " (spell4CCConditionsIdTarget), a state its target must or must not hold, which no creature special reads"
    NotPlanned(spell4_id:, error:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " cannot be planned: "
      <> spell_plan.describe(error:)
    NoGo(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has no go time: its cast is held until its release"
    GosDoNotRise(spell4_id:, times_ms:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has go times in milliseconds that do not rise: "
      <> string.join(list.map(times_ms, int.to_string), ", ")
    NoStrikePhase(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has no damage row whose phaseFlags name a go, so its cast strikes nobody"
    SeveralStrikes(spell4_id:, gos:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " strikes at "
      <> gos_sentence(gos:)
      <> ", which a creature's fight does not run: the step 'A creature's cast with several hits, or hits before its last go, strikes at each hit's phase' of issue 801 closes it"
    StrikesBeforeTheLastGo(spell4_id:, go:, last_go:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " strikes at go "
      <> int.to_string(go)
      <> " but its last go is go "
      <> int.to_string(last_go)
      <> ", which a creature's fight does not run: the step 'A creature's cast with several hits, or hits before its last go, strikes at each hit's phase' of issue 801 closes it"
    OtherEffectType(spell4_effects_id:, effect_type:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has effect type "
      <> int.to_string(effect_type)
      <> ", which a creature's special does not apply (only damage, type 8, and NpcExecutionDelay, type 35)"
    NoAreaRow(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has no area row (spell4AoeTargetConstraintsId 0), so its telegraph selects nobody"
    AreaNotRead(spell4_id:, error:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has an area the load cannot read: "
      <> spell_area.describe(error:)
    DelayNotApplied(spell4_effects_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " is an NpcExecutionDelay row the plan does not apply: it has to aim at the caster alone, with a durationTime and a phaseFlags that names a go"
    DelayNamesAnotherGo(spell4_effects_id:, gos:, strike_go:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " is an NpcExecutionDelay row that names "
      <> gos_sentence(gos:)
      <> ", and the creature's hold follows the strike go, go "
      <> int.to_string(strike_go)
      <> " alone"
    DelayBehindPrerequisite(spell4_effects_id:, prerequisite_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " is an NpcExecutionDelay row behind prerequisite "
      <> int.to_string(prerequisite_id)
      <> ", which no creature rule reads for a hold"
  }
}

/// "go 1" and "go 1 and go 2" and "go 1, go 2 and go 3" for the gos' indexes, "no go" for none.
fn gos_sentence(gos gos: List(Int)) -> String {
  let named = list.map(gos, fn(go) { "go " <> int.to_string(go) })
  case list.reverse(named) {
    [] -> "no go"
    [only] -> only
    [last, ..before] ->
      string.join(list.reverse(before), ", ") <> " and " <> last
  }
}
