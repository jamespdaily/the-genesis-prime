//// How the heals of a spell's ticking effects are split and described.

import genesis_prime/game/cast/state.{
  type Caster, type Effect, type Healed, type Struck, type TickingOn, DamageTick,
  Deflected, HealTick, Healed, Hit, HitCreature, HitPlayer, Immune, Log,
  TickingOn,
}
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/step.{LogDebug}
import gleam/int
import gleam/list

/// The periodic damage rows of the go on each creature the round hit or found immune,
/// in the life it struck (`Hit.ticking`, `Immune.ticking`); a deflected unit takes none,
/// and a player's attacks carry none.
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
            kind: DamageTick(blow: row.damage),
          )
        })
      Hit(unit: HitPlayer, ..) | Immune(unit: HitPlayer, ..) | Deflected(..) -> []
    }
  })
}

/// The periodic heal rows of the go aimed at the caster, each ticking on it; one aimed
/// at another unit is left with the debug line of `healed_by`.
pub fn ticking_heals(
  entries entries: List(#(spell_plan.Heal, Int)),
  caster caster: Caster,
) -> List(TickingOn) {
  entries
  |> list.filter_map(fn(entry) {
    case entry.0, entry.1 == caster.unit_id {
      spell_plan.TickingHeal(effect_id:, vital:, formula:, schedule:, ..), True
      ->
        Ok(TickingOn(
          unit_id: caster.unit_id,
          life: 0,
          effect_id:,
          schedule:,
          kind: HealTick(vital:, formula:),
        ))
      spell_plan.TickingHeal(..), False | spell_plan.Heal(..), _ -> Error(Nil)
    }
  })
}

/// The heals a go applies at once (a periodic one ticks, `ticking_heals`), each on the
/// caster, with the amount the caster's own
/// vitals and stats give: the caster as it stood before the go's own effects, the rule of
/// every gate of the go (`subject_of`), and the overheal the vital's room leaves. A row's
/// units are those its aim names (`units_aimed_at`) and only the caster is healed: the
/// server gives no other unit a heal, so a heal aimed at another unit (the primary target
/// of a cast on someone else, a unit the round hit) is left, with a debug line naming its
/// row (other players come with #570). The plan refuses a heal that names the primary
/// target in a child started on each struck unit (`spell_plan.not_on_a_struck_unit`).
pub fn healed_by(
  entries entries: List(#(spell_plan.Heal, Int)),
  caster caster: Caster,
) -> #(List(#(Healed, Int)), List(Effect)) {
  let on_caster = on_caster_of(caster:)
  let healed =
    list.filter_map(entries, fn(entry) {
      case entry.0, entry.1 == caster.unit_id {
        spell_plan.Heal(effect_id:, vital:, formula:, delay_ms:, ..), True -> {
          let amount = damage.amount_on_caster(formula:, caster: on_caster)
          Ok(#(
            Healed(
              effect_id:,
              vital:,
              delay_ms:,
              amount:,
              split: split_of(vital:, amount:, caster:),
            ),
            caster.unit_id,
          ))
        }
        spell_plan.Heal(..), False | spell_plan.TickingHeal(..), _ -> Error(Nil)
      }
    })
  let left =
    list.filter_map(entries, fn(entry) {
      case entry.0, entry.1 == caster.unit_id {
        spell_plan.Heal(effect_id:, ..), False
        | spell_plan.TickingHeal(effect_id:, ..), False
        ->
          Ok(Log(
            level: LogDebug,
            text: "the Heal or HealShields effect "
              <> int.to_string(effect_id.value)
              <> " is aimed at the unit "
              <> int.to_string(entry.1)
              <> ", not the caster, and heals on other units are not built (#570), so it lands nothing",
          ))
        spell_plan.Heal(..), True | spell_plan.TickingHeal(..), True ->
          Error(Nil)
      }
    })
  #(healed, left)
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
/// and the vitals it had before the go's own effects (`subject_of`).
pub fn on_caster_of(caster caster: Caster) -> damage.OnCaster {
  damage.OnCaster(attacker: caster.stats, vitals: caster.vitals)
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
