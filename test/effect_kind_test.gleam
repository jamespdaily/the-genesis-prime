//// The decode of effect type 79 (genesis_prime/game/effect_kind). Expected values and
//// their sources:
//// - `Spell4Effects.effectType.79` (fairly sure): SpellEffectImmunity; `dataBits00` is the
////   effect type made immune (8 is Damage), the enum at `0x140c34140`; spell 85474's
////   row 224666 is one. The client has no class for it and reads nothing, so the server
////   does not read it either and the coverage measure counts it unhandled.

import genesis_prime/game/effect_kind.{Damage, Immunity}
import gleam/list
import owned_test

pub fn kind_of_names_type_42_and_its_row_read_follows_its_aim_test() -> Nil {
  use <- owned_test.run(10_000)
  assert effect_kind.kind_of(effect_type: 42) == effect_kind.QuestAdvance
    as "Spell4Effects.effectType.42: QuestAdvanceObjective, enum 0x140c34140"
  assert effect_kind.is_read(effect_type: 42)
    as "a rule of the server reads it, so the coverage measure counts it handled"
  // The aim is a guess (`Spell4Effects.targetFlags`): the caster's bit or the primary target
  // alone, the units a quest log belongs to.
  assert list.map([0, 1, 2, 3, 4, 5, 6, 7, 8], fn(target_flags) {
      effect_kind.is_row_read(effect_type: 42, target_flags:)
    })
    == [False, True, True, True, False, True, False, True, False]
    as "1, 3, 5 and 7 hold the caster's bit and 2 names the primary target alone; 4, 6, 0 and 8 reach no one a quest log is kept for"
  assert effect_kind.kind_of(effect_type: 79) == Immunity
    && effect_kind.kind_of(effect_type: 43) == effect_kind.Unread(43)
    as "the kinds around it do not move: Immunity stays and an unread type stays unread"
}

pub fn effect_type_79_decodes_to_immunity_test() -> Nil {
  use <- owned_test.run(10_000)
  assert effect_kind.kind_of(effect_type: 79) == Immunity
    as "Spell4Effects.effectType.79 is SpellEffectImmunity"
  assert effect_kind.immune_to(effect_type: 79, data_bits00: 8) == Ok(Damage)
    as "0x140c34140: dataBits00 8 is the Damage effect type"
  assert effect_kind.immune_to(effect_type: 8, data_bits00: 8) == Error(Nil)
    as "only an effect of type 79 is an immunity"
}

pub fn effect_type_79_stays_unread_for_the_coverage_measure_test() -> Nil {
  use <- owned_test.run(10_000)
  assert !effect_kind.is_read(effect_type: 79)
    as "the client reads nothing of type 79, so no rule of the server does"
  assert !effect_kind.is_row_read(effect_type: 79, target_flags: 1)
  assert !effect_kind.is_row_read(effect_type: 79, target_flags: 2)
}

pub fn type_35_is_npc_execution_delay_test() -> Nil {
  use <- owned_test.run(10_000)
  assert effect_kind.kind_of(effect_type: 35) == effect_kind.NpcExecutionDelay
    as "Spell4Effects.effectType.35: the effect switch 0x140718120 has no case 35, so the server reads the row as a hold of its caster"
  assert effect_kind.is_read(effect_type: 35)
    as "a rule of the server reads it, so the coverage measure counts it handled"
  assert effect_kind.is_row_read(effect_type: 35, target_flags: 1)
    as "3264 of its 3288 rows aim at the caster alone (table_rows -- Spell4Effects effectType=35)"
  assert !effect_kind.is_row_read(effect_type: 35, target_flags: 2)
    && !effect_kind.is_row_read(effect_type: 35, target_flags: 4)
    as "19 rows aim at the target and 5 at the area: no creature rule holds another unit"
}

pub fn type_98_is_summon_pet_and_stays_unread_for_the_coverage_measure_test() -> Nil {
  use <- owned_test.run(10_000)
  assert effect_kind.kind_of(effect_type: 98) == effect_kind.SummonPet
    as "Spell4Effects.effectType.98 is SummonPet, enum 0x140c34140"
  assert !effect_kind.is_read(effect_type: 98)
    as "the client reads nothing of type 98 and no rule of the server builds a summoned unit"
  assert !effect_kind.is_row_read(effect_type: 98, target_flags: 1)
  assert !effect_kind.is_row_read(effect_type: 98, target_flags: 2)
  assert effect_kind.kind_of(effect_type: 97) == effect_kind.Despawn
    && effect_kind.kind_of(effect_type: 99) == effect_kind.Unread(99)
    as "the types around it do not move"
}
