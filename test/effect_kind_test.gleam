//// The decode of effect type 79 (genesis_prime/game/effect_kind). Expected values and
//// their sources:
//// - `Spell4Effects.effectType.79` (fairly sure): SpellEffectImmunity; `dataBits00` is the
////   effect type made immune (8 is Damage), the enum at `0x140c34140`; spell 85474's
////   row 224666 is one. The client has no class for it and reads nothing, so the server
////   does not read it either and the coverage measure counts it unhandled.

import genesis_prime/game/effect_kind.{Damage, Immunity}
import owned_test

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
