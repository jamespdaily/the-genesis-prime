//// How the heals of a spell's ticking effects are split and described.
////
//// - **A go's heals** (`Spell4Effects.effectType.10` and `.118`): each Heal or HealShields
////   effect of the phase that reaches the caster (genesis_prime/game/spell_plan `Heal`)
////   whose gate against the caster passes is listed in the caster's target info with a
////   damage description of its amount (type Heal or HealShields, result Hit, the amount as
////   the raw, the scaled raw and the health change, and as the overheal what the amount
////   leaves over the vital's room), which the client shows as a floater and logs itself
////   as a heal with that overheal, and never applies (`spell.heal_result_log`). The amount
////   is worked out at the go from the caster's own shield, health and stats as they stood
////   before the go's own effects (genesis_prime/game/damage `amount_on_caster`: Energize
////   is 0.3 of the missing shield), and lands at the go plus the row's delay as
////   `CasterChangeStarts` with a `Heal` change carrying the vital, for the connection to
////   raise the player's health or shield by (genesis_prime/game/player_life `healed`): in
////   the go's step, after its 0x7f4, with no delay, else on a timer. A heal gives the
////   caster's node a life of its delay, so the 0x7fe waits for it; when the node's end and
////   a pending heal are due in the same millisecond the end lands the heal first. A node
////   taken off the caster, a persistence that stops holding and the caster's death drop a
////   pending heal with its timer; a later go of the cast heals again and cancels no
////   earlier heal. A periodic heal (a tickTime) heals the caster at each tick, after
////   the tick's 0x7f8 (`ticking_heals`). A periodic heal on another player in the caster's
////   sight ticks on that player: each tick tells its connection the row
////   (genesis_prime/game/strike `begin_tick`) and writes the 0x7f8 of what the player
////   applied (`cast_tick.tick_outcome`). A heal on a unit other than the caster lands
////   nothing here: another player is healed by the answer to the strike its go or its
////   tick told its connection (genesis_prime/game/strike `TellPlayerStrike`), and a
////   creature is not healed. When the round holds that player's answer, the go lists each
////   row the answer names on the player with the description of the answer's split (the
////   amount the player applied and what its vitals could not take as the overheal), never
////   arms it, and neither gates nor rolls the rows the strike told again
////   (`genesis_prime/game/cast/gate` `heal_told`, `heal_answered`); a row the answer does
////   not name, and a heal on a unit that has no answer, lands nothing and a debug line says
////   so. The server rolls no critical for a heal: the description is always a Hit, so the
////   seed draws nothing for it (the server's choice).

import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/state.{
  type Aimed, type Caster, type Effect, type Healed, type Product, type Reached,
  type State, type Struck, type TickingOn, CasterChangeStarts, CooldownKept,
  Deflected, Described, Heal, Healed, Healing, Hit, HitCreature, HitOtherPlayer,
  HitPlayer, Immune, Log, ModifierStart, Plain, TickingOn,
} as cast_state
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties
import genesis_prime/gap
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{type Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// The periodic damage rows of the go on each creature the round hit or found immune,
/// in the life it struck (`Hit.ticking`, `Immune.ticking`); a deflected unit takes none,
/// and a player's attacks and a heal told to another player carry none.
pub fn ticking_struck(struck struck: List(Struck)) -> List(TickingOn) {
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, unit: HitCreature(life:, ..), ticking:, ..)
      | Immune(unit_id:, unit: HitCreature(life:, ..), ticking:, ..) ->
        list.map(ticking, fn(row: spell_area.TickingDamage) {
          TickingOn(
            unit_id:,
            life:,
            effect_id: row.damage.effect_id,
            schedule: row.schedule,
            kind: cast_state.damage_tick(blow: row.damage),
          )
        })
      Hit(unit: HitPlayer, ..)
      | Immune(unit: HitPlayer, ..)
      | Hit(unit: HitOtherPlayer(..), ..)
      | Immune(unit: HitOtherPlayer(..), ..)
      | Deflected(..) -> []
    }
  })
}

/// The periodic heal rows among the effects a go reached, each ticking on the unit it
/// reaches when that unit is the caster or another player in the caster's sight, whose
/// connection applies the tick (genesis_prime/game/strike `begin_tick`); a row that reaches
/// any other unit is left with the debug line of `healed_on`.
pub fn ticking_heals(
  reached reached: List(Reached),
  caster caster: Caster,
  passed_in passed_in: Option(Float),
) -> List(TickingOn) {
  list.filter_map(reached, fn(entry) {
    case entry.effect.kind, ticks_on(caster:, unit_id: entry.unit_id) {
      spell_plan.HealEffect(heal: spell_plan.TickingHeal(
        effect_id:,
        vital:,
        formula:,
        schedule:,
        ..,
      )),
        True
      ->
        Ok(TickingOn(
          unit_id: entry.unit_id,
          life: 0,
          effect_id:,
          schedule:,
          kind: cast_state.heal_tick(vital:, formula:, passed_in:),
        ))
      spell_plan.HealEffect(..), _
      | spell_plan.ProxyEffect(..), _
      | spell_plan.GainEffect(..), _
      | spell_plan.LastingEffect(..), _
      | spell_plan.RemoveEffect(..), _
      | spell_plan.ModifierEffect(..), _
      | spell_plan.ForcedMoveEffect(..), _
      | spell_plan.StruckMoveEffect(..), _
      | spell_plan.DespawnEffect(..), _
      | spell_plan.UnitStateEffect(..), _
      | spell_plan.CooldownEffect(..), _
      | spell_plan.StealthEffect(..), _
      | spell_plan.RemoveStealthEffect(..), _
      | spell_plan.ProcEffect(..), _
      | spell_plan.DelayEffect(..), _
      | spell_plan.QuestAdvanceEffect(..), _
      | spell_plan.ControlEffect(..), _
      -> Error(Nil)
    }
  })
}

/// Whether a periodic heal reaching the unit ticks on it: the caster, or another player in
/// the caster's sight.
fn ticks_on(caster caster: Caster, unit_id unit_id: Int) -> Bool {
  unit_id == caster.unit_id || dict.has_key(caster.players_in_sight, unit_id)
}

/// What a heal row reaching `unit_id` comes to: for a heal applied at once (a periodic
/// one ticks, `ticking_heals`) on the caster, the `Healing` with the amount the caster's own
/// vitals and stats give: the caster as it stood before the go's own effects, the rule of
/// every gate of the go (`cast_tick.subject_of`), and the overheal the vital's room leaves;
/// for a heal on a player that answered it, the `Described` heal of the answer's split.
/// A row's units are those its aim names (`cast_gate.units_aimed_at`) and only the caster
/// is healed here: a heal aimed at another player the round holds the answer of is
/// `Described` by the split of the answer's heal of the row, and one aimed at any other
/// unit (a creature, a player with no answer or whose answer does not name the row) is left
/// `Plain`, with a debug line naming its row, since another player is healed by its answer
/// to the strike its go told it and a creature is not healed. The plan refuses a heal that
/// names the primary target in a child started on each struck unit
/// (`spell_plan.not_on_a_struck_unit`).
pub fn healed_on(
  row row: spell_plan.Heal,
  unit_id unit_id: Int,
  caster caster: Caster,
  passed_in passed_in: Option(Float),
  struck struck: List(Struck),
) -> #(Product, List(Effect)) {
  case row, unit_id == caster.unit_id {
    spell_plan.Heal(effect_id:, vital:, formula:, delay_ms:, ..), True -> {
      let amount =
        damage.amount_on_caster(
          formula:,
          caster: on_caster_of(caster:, passed_in:),
        )
      #(
        Healing(healed: Healed(
          effect_id:,
          vital:,
          delay_ms:,
          amount:,
          split: split_of(vital:, amount:, caster:),
        )),
        [],
      )
    }
    spell_plan.TickingHeal(..), True -> #(Plain, [])
    spell_plan.Heal(effect_id:, ..), False ->
      case answered(struck:, unit_id:, effect_id:) {
        Ok(landed) -> #(Described(healed: applied(landed:)), [])
        Error(Nil) -> #(Plain, [not_landed_log(effect_id:, unit_id:)])
      }
    spell_plan.TickingHeal(effect_id:, ..), False ->
      case ticks_on(caster:, unit_id:) {
        True -> #(Plain, [])
        False -> #(Plain, [not_landed_log(effect_id:, unit_id:)])
      }
  }
}

/// The heal a player applied, as its answer's split gives it: the amount it took and the
/// overheal its vitals had no room for.
pub fn applied(landed landed: strike_tell.HealLanded) -> Healed {
  Healed(
    effect_id: landed.effect_id,
    vital: landed.vital,
    delay_ms: 0,
    amount: landed.split.amount,
    split: landed.split,
  )
}

/// What the player `unit_id` answered for the heal row `effect_id`, when the round holds
/// its answer and the answer lists the row.
fn answered(
  struck struck: List(Struck),
  unit_id unit_id: Int,
  effect_id effect_id: Spell4EffectsId,
) -> Result(strike_tell.HealLanded, Nil) {
  use heals <- result.try(cast_gate.player_answer(struck:, unit_id:))
  list.find(heals, fn(landed) { landed.effect_id == effect_id })
}

/// The debug line of a heal row that lands nothing on a unit other than the caster.
fn not_landed_log(
  effect_id effect_id: Spell4EffectsId,
  unit_id unit_id: Int,
) -> Effect {
  Log(
    level: LogDebug,
    text: "the Heal or HealShields effect "
      <> int.to_string(effect_id.value)
      <> " is aimed at the unit "
      <> int.to_string(unit_id)
      <> ", not the caster, so it lands nothing here: another player is healed only by its answer to the heal strike",
  )
}

/// What a heal of the formula's `amount` comes to for the caster's `vital`: the amount
/// after its heal multipliers, what the shield and the health each take and the overheal
/// the vitals' room leaves, by the very function the life raises the vital by
/// (genesis_prime/game/player_life `healed`), so the 0x7f4 tells what the health does,
/// which the client's heal log reads as nHealAmount and nOverheal
/// (`spell.heal_result_log`). The room is that of the vitals before the go, so two heal
/// rows of one go, or a heal that lands after a delay, each measure it from there and not
/// from what the other rows or the time in between changed.
pub fn split_of(
  vital vital: effect_kind.Vital,
  amount amount: Int,
  caster caster: Caster,
) -> heal_split.Split {
  heal_split.split(
    vital:,
    amount:,
    scaling: caster.heal_scaling,
    health_room: caster.vitals.max_health - caster.vitals.health,
    shield_room: caster.vitals.max_shield - caster.vitals.shield,
  )
}

/// What a formula reads of the caster when it is also the target of its effect: the stats
/// and the vitals it had before the go's own effects (`cast_tick.subject_of`). The
/// passed-in value is the cast's own when it has one (an item's), else the caster's at its
/// level.
pub fn on_caster_of(
  caster caster: Caster,
  passed_in passed_in: Option(Float),
) -> damage.OnCaster {
  damage.on_caster_with(stats: caster.stats, vitals: caster.vitals, passed_in:)
}

/// The damage description of a heal: the split's amount as the raw, the scaled raw and the
/// health change, the part the vitals had no room for as the overkill, a Hit of damage type Heal
/// (4) or HealShields (5), nothing absorbed or killed and no hit entries
/// (`Spell4Effects.effectType.10`, `.118`, `GameLib.CodeEnumDamageType`,
/// `GameLib.CodeEnumCombatResult`). The client builds the heal's combat log line from the
/// health change and the overkill (`spell.heal_result_log`); the raw values are the
/// server's choice.
pub fn heal_description(healed healed: Healed) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: healed.split.amount,
    scaled_raw_damage: healed.split.amount,
    absorbed: 0,
    shield_absorbed: 0,
    health_damage_with_overkill: healed.split.amount,
    overkill: healed.split.overheal,
    glance: 0,
    killed: 0,
    combat_result: combat_result.Hit,
    damage_type: case healed.vital {
      effect_kind.Health -> damage_type.Heal
      effect_kind.Shield -> damage_type.HealShields
    },
    hits: [],
  )
}

/// The heals a go applies: a heal with no delay lands in this step, after the go's
/// 0x7f4, and any other on a timer of its delay (the client adds the delay before it
/// applies a result, `0x1405d77a0`). Each go's heal is its own, so a later go of the cast
/// heals again and no earlier heal is cancelled; a pending heal is dropped with the node
/// of the cast on the caster (`cast_proc.effects_ended`), and lands when the node ends by time
/// (`cast_tick.heals_landed_at_node_end`).
pub fn heals_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
) -> #(State, List(Effect)) {
  list.fold(aimed.reached, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    case entry.product {
      Healing(healed:) -> {
        let #(cast, armed) = heal_armed(cast:, cast_id:, healed:)
        #(cast, list.append(effects, armed))
      }
      // A heal that lands nothing (a periodic one ticks; another unit's is not built),
      // another player's heal, which that player applied itself, and any effect that is no
      // heal.
      Plain | Described(..) | CooldownKept(..) -> so_far
    }
  })
}

/// One heal applied by a go: in this step with no delay, else on a timer of its delay.
fn heal_armed(
  cast cast: State,
  cast_id cast_id: Int,
  healed healed: Healed,
) -> #(State, List(Effect)) {
  let source = unit_properties.Source(cast_id:, effect_id: healed.effect_id)
  let change = Heal(vital: healed.vital, amount: healed.amount)
  case healed.delay_ms > 0 {
    True -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: ModifierStart(source:, change:),
          after_ms: healed.delay_ms,
        )
      #(cast, [start])
    }
    False -> #(cast, [CasterChangeStarts(source:, change:)])
  }
}

/// What a heal does not reach.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Casting",
      missing: "A heal aimed at a creature, or at another player with a delay, lands nothing, with a debug line, because the server heals the caster by its own rule and another player only by its answer to an instant row at the go or a periodic row at each tick. A periodic heal on another player in the caster's sight ticks on it; one on a player not in sight lands nothing. A row aimed at the caster and at another player keeps its caster gate at the go, so the player's heal, which it applied, is listed only while that gate still passes.",
    ),
  ]
}
