//// A planned spell holds its effect rows as one list (`spell_plan.Spell.effects`), each an
//// envelope (`genesis_prime/game/spell_effect`) around a kind. Expected values come from
//// these places.
//// - The order the gates draw their rolls and a go lists its effects in
////   (`cast/gate.rolls_needed`, `cast/control.lasting_applied`): the Proxies, the gains,
////   the lasting rows, the removes, the property changes (armor last), the caster's forced
////   moves, the struck units' moves, the cooldown changes, the stealth rows, the stealth
////   removals, the procs, the heals and the crowd-control rows, each kind in the order of
////   its rows (`Spell4Effects`, by orderIndex and ID).
//// - `Spell4Effects.targetFlags`: bit 1 the caster, bit 2 the primary target; 3 names both.
//// - `genesis_prime/game/ticking`: a periodic row's schedule has count durationTime / tickTime
////   rounded down, from its delayTime.
//// - The client's own Spell4Effects rows, one of each effect type the plan reads
////   (`genesis_prime/game/effect_kind`).
//// The rows are planted on Telekinetic Strike's spell (`spell_tables`).

import fixture_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{
  Applied, ControlEffect, CooldownEffect, DelayEffect, DespawnEffect,
  ForcedMoveEffect, GainEffect, HealEffect, Held, LastingEffect, LeftOut,
  ModifierEffect, ProcEffect, ProxyEffect, QuestAdvanceEffect, ReadByActivation,
  ReadByArea, ReadEffects, ReadProc, ReadProxy, RemoveEffect,
  RemoveStealthEffect, StealthEffect, StruckMoveEffect, UnitStateEffect,
}
import genesis_prime/table/spell4_effects
import gleam/bool
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables

fn row(
  id id: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  spell_tables.effect_row_with(id:, effect_type:, target_flags:, columns:)
}

/// The planted spell with these rows beside the ones of `spell_tables.planted_effects`.
fn planted_with(extra extra: List(List(Cell))) -> spell_plan.Spell {
  let rows =
    spell_tables.rows_with_effects(
      effects: [
        spell_tables.planted_effects(),
        extra,
      ]
      |> list.flatten,
    )
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
    as "the planted spell loads"
  spell
}

/// The effect ids of the planted rows in the list, in its order.
fn planted_ids(spell spell: spell_plan.Spell) -> List(Int) {
  spell_tables.listed_effect_ids(spell:)
  |> list.filter(fn(id) { !spell_tables.client_row(id:) })
}

pub fn effects_follow_the_kind_rank_then_row_order_test() -> Nil {
  use <- owned_test.run(60_000)
  // Ids run against the rank, so the list can follow only the rank: the crowd-control row
  // (90004) comes before the property change (90005), a Proxy (90012) after the gain, and
  // the armor (89999) before the plain property change (90005).
  let spell =
    planted_with(extra: [
      row(id: 89_999, effect_type: 52, target_flags: 1, columns: [
        #("dataBits00", Integer(2)),
        #("durationTime", Integer(5000)),
      ]),
      row(id: 90_020, effect_type: 3, target_flags: 2, columns: []),
      row(id: 90_021, effect_type: 1, target_flags: 1, columns: [
        #("dataBits00", Integer(6)),
        #("dataBits02", Integer(5)),
      ]),
    ])
  assert planted_ids(spell:)
    == [
      90_012,
      90_001,
      90_021,
      90_002,
      90_013,
      90_003,
      90_005,
      89_999,
      90_006,
      90_020,
      90_007,
      90_018,
      90_009,
      90_011,
      90_010,
      90_014,
      90_004,
    ]
    as "a Proxy, the gains, the lasting rows, the removes, the property changes with the armor last, the caster's forced move, the struck units' move, the cooldown change, stealth, the stealth removal, the proc, the heals, then the crowd-control row; a kind in the order of its rows"
}

/// The planted outcome a row's reading names: the variants it plans, in order.
fn outcome_of(reading reading: spell_plan.RowReading) -> Result(String, Nil) {
  case reading {
    Applied(row) | Held(row) ->
      case row {
        ReadEffects(effects:) ->
          Ok(string.join(list.map(effects, kind_name), "+"))
        ReadProc(..) -> Ok("ReadProc")
        ReadProxy(..) -> Ok("ReadProxy")
      }
    ReadByArea -> Ok("ReadByArea")
    ReadByActivation -> Ok("ReadByActivation")
    LeftOut(..) -> Error(Nil)
  }
}

fn kind_name(
  planned planned: spell_effect.PlannedEffect(spell_plan.Kind),
) -> String {
  case planned.kind {
    ProxyEffect(..) -> "ProxyEffect"
    GainEffect(..) -> "GainEffect"
    LastingEffect(..) -> "LastingEffect"
    RemoveEffect(..) -> "RemoveEffect"
    ModifierEffect(..) -> "ModifierEffect"
    ForcedMoveEffect(..) -> "ForcedMoveEffect"
    StruckMoveEffect(..) -> "StruckMoveEffect"
    CooldownEffect(..) -> "CooldownEffect"
    StealthEffect(..) -> "StealthEffect"
    RemoveStealthEffect(..) -> "RemoveStealthEffect"
    ProcEffect(..) -> "ProcEffect"
    HealEffect(..) -> "HealEffect"
    ControlEffect(..) -> "ControlEffect"
    DespawnEffect(..) -> "DespawnEffect"
    UnitStateEffect(..) -> "UnitStateEffect"
    DelayEffect(..) -> "DelayEffect"
    QuestAdvanceEffect(..) -> "QuestAdvanceEffect"
  }
}

/// What the plan may make of a row of the kind: the variant it plans, or the reading that
/// leaves it to the spell (a Proxy's child and a Proc's spell are planned by the spell that
/// holds the row) or to the strike or the activation (damage and activate rows).
fn outcomes_of(kind kind: effect_kind.Kind) -> List(String) {
  case kind {
    effect_kind.Proxy -> ["ReadProxy"]
    effect_kind.Damage -> ["ReadByArea"]
    effect_kind.VitalModifier -> ["GainEffect"]
    effect_kind.Fluff
    | effect_kind.Scale
    | effect_kind.RavelSignal
    | effect_kind.ShieldOverload
    | effect_kind.ItemVisualSwap -> ["LastingEffect"]
    effect_kind.ForceRemove -> ["RemoveEffect"]
    effect_kind.CrowdControl -> ["ControlEffect"]
    effect_kind.PropertyModifier
    | effect_kind.PropertyConversion
    | effect_kind.DisguiseOutfit
    | effect_kind.Absorption
    | effect_kind.InterruptArmor -> [
      "ModifierEffect",
      "ModifierEffect+ModifierEffect",
    ]
    effect_kind.ForcedMove -> [
      "ForcedMoveEffect",
      "StruckMoveEffect",
      "ForcedMoveEffect+StruckMoveEffect",
    ]
    effect_kind.CooldownModifier -> ["CooldownEffect"]
    effect_kind.Stealth -> ["StealthEffect"]
    effect_kind.RemoveStealth -> ["RemoveStealthEffect"]
    effect_kind.Heal(..) -> ["HealEffect"]
    effect_kind.Proc -> ["ReadProc"]
    effect_kind.Activate -> ["ReadByActivation"]
    effect_kind.Despawn -> ["DespawnEffect"]
    effect_kind.NpcExecutionDelay -> ["DelayEffect"]
    effect_kind.QuestAdvance -> ["QuestAdvanceEffect"]
    effect_kind.Immunity | effect_kind.UnitState | effect_kind.Unread(..) -> []
  }
}

pub fn every_read_effect_kind_plans_one_variant_or_names_why_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let effects = spell4_effects.all(fixture_tables.shared())
  let kinds =
    list.map(effects, fn(effect) { effect_kind.kind_of(effect.effect_type) })
    |> list.unique
    |> list.filter(fn(kind) { outcomes_of(kind:) != [] })
  assert list.length(kinds) == 25
    as "the client's table holds a row of each of the 25 kinds the plan reads"
  list.each(kinds, fn(kind) {
    let outcome =
      list.find_map(effects, fn(effect) {
        use <- bool.guard(
          when: effect_kind.kind_of(effect.effect_type) != kind,
          return: Error(Nil),
        )
        spell_tables.read_row(effect:, place: spell_tables.pressed_hitting_foes)
        |> result.replace_error(Nil)
        |> result.try(fn(reading) { outcome_of(reading:) })
      })
    let assert Ok(outcome) = outcome
      as { "a client row of the kind " <> string.inspect(kind) <> " is read" }
    assert list.contains(outcomes_of(kind:), outcome)
      as { string.inspect(kind) <> " plans " <> outcome }
  })
}

pub fn a_control_aimed_at_caster_and_target_is_in_both_control_views_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    planted_with(extra: [
      row(id: 90_030, effect_type: 4, target_flags: 3, columns: [
        #("durationTime", Integer(1000)),
      ]),
    ])
  let ids = fn(controls: List(spell_plan.CrowdControl)) {
    list.map(controls, fn(control) { control.effect_id.value })
    |> list.filter(fn(id) { !spell_tables.client_row(id:) })
  }
  assert ids(spell_plan.controls_in_phase(spell:, phase: 0, spent: None))
    == [90_004, 90_030]
    as "the strike side holds the row aimed at the primary target (90004) and the one aimed at the caster and the target"
  assert ids(spell_plan.restrictions_in_phase(spell:, phase: 0, spent: None))
    == [90_030]
    as "the caster's side holds the row that names the caster"
  assert list.count(planted_ids(spell:), fn(id) { id == 90_030 }) == 1
    as "the list holds the row once"
}

pub fn a_ticking_heal_and_a_ticking_gain_keep_their_tick_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    planted_with(extra: [
      row(id: 90_040, effect_type: 1, target_flags: 1, columns: [
        #("dataBits00", Integer(6)),
        #("dataBits02", Integer(5)),
        #("tickTime", Integer(500)),
        #("durationTime", Integer(4000)),
      ]),
    ])
  let assert [spell_plan.TickingHeal(schedule:, ..)] =
    spell_plan.in_phase(
      spell:,
      phase: 0,
      spent: None,
      as_kind: spell_plan.as_heal,
    )
    |> list.filter(fn(heal) { heal.effect_id.value == 90_014 })
    as "the heals view holds the ticking heal"
  assert schedule.tick_ms == 1000
    && schedule.duration_ms == 8000
    && schedule.count == 8
    as "the heal's tick 1000 and life 8000 give 8 ticks"
  let assert [spell_plan.TickingGain(tick_ms:, duration_ms:, ..)] =
    spell_plan.in_phase(
      spell:,
      phase: 0,
      spent: None,
      as_kind: spell_plan.as_gain,
    )
    |> list.filter(fn(gain) { gain.effect_id.value == 90_040 })
    as "the gains view holds the ticking gain"
  assert tick_ms == 500 && duration_ms == 4000
}
