//// The amount of an Absorption row for a player that casts it on itself
//// (`genesis_prime/game/damage` `absorption_formula_of`, `amount_on_caster`). Expected
//// values come from these places.
//// - `Spell4Effects.effectType.29`: the amount is dataBits00 (a float multiplier) x
////   (dataBits01, a flat float amount, plus the flat parameters) plus the stat part, as
////   the tooltips read them: row 183643 ('Granted 45 Absorb', text 581159) has dataBits00
////   1.0 and dataBits01 1110704128 (45.0) and no parameter; row 178144 (Spectral Form,
////   tooltip 504979 'Grant $(eff=178144.input0pct) absorb') has dataBits00 1.0, dataBits01
////   0 and Assault Power x 2.531 and Support Power x 2.531; row 97347 has dataBits00 0,
////   dataBits01 0 and Support Power x 4.0 (`table_rows -- Spell4Effects 178144 183643
////   97347`). That type 29 takes the row part this way is the server's choice: ComputeEffectValue
////   gives type 29 none (the effect type's gap).
//// - `player.level1_gear_properties`: a level-1 Novice's Assault Rating 203.0625 and Support
////   Rating 55.6875, so Assault Power 50.765625 and Support Power 13.921875 (GameFormula
////   1266: 0.25 of a rating, `0x140462930`, `0x140462980`).
//// - `0x140566d40`: the stat part is rounded half away from zero.
//// By hand: Spectral Form is round(2.531 x 50.765625 + 2.531 x 13.921875) =
//// round(128.4878 + 35.2363) = round(163.724) = 164.

import attacker_support
import genesis_prime/game/damage.{Attacker, OnCaster}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import owned_test
import spell_tables

const one_as_float_bits = 1_065_353_216

const forty_five_as_float_bits = 1_110_704_128

/// 10.0 as 32 float bits.
const ten_as_float_bits = 1_092_616_192

fn row(
  id id: Int,
  data_bits00 data_bits00: Int,
  data_bits01 data_bits01: Int,
) -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(
      id:,
      spell: 58_586,
      effect_type: 29,
      target_flags: 1,
    ),
    data_bits00:,
    data_bits01:,
  )
}

fn amount(effect effect: Spell4Effects, caster caster: damage.OnCaster) -> Int {
  let assert Ok(formula) = damage.absorption_formula_of(effect:)
    as "the row's numbers are finite"
  damage.amount_on_caster(formula:, caster:)
}

pub fn spectral_forms_absorb_at_level_one_is_164_test() -> Nil {
  use <- owned_test.run(5000)
  let spectral_form =
    Spell4Effects(
      ..row(id: 178_144, data_bits00: one_as_float_bits, data_bits01: 0),
      parameter_type00: 12,
      parameter_type01: 13,
      parameter_value00: 2.5309998989105225,
      parameter_value01: 2.5309998989105225,
    )
  assert amount(
      effect: spectral_form,
      caster: attacker_support.novice_on_itself(),
    )
    == 164
    as "round(2.531 x 50.765625 + 2.531 x 13.921875) = round(163.724)"
}

pub fn a_flat_absorption_is_its_multiplier_times_its_float_amount_test() -> Nil {
  use <- owned_test.run(5000)
  assert amount(
      effect: row(
        id: 183_643,
        data_bits00: one_as_float_bits,
        data_bits01: forty_five_as_float_bits,
      ),
      caster: attacker_support.novice_on_itself(),
    )
    == 45
    as "row 183643: 1.0 x 45.0, 'Granted 45 Absorb'"
  let stat_only =
    Spell4Effects(
      ..row(id: 97_347, data_bits00: 0, data_bits01: 0),
      parameter_type00: 13,
      parameter_value00: 4.0,
    )
  assert amount(effect: stat_only, caster: attacker_support.novice_on_itself())
    == 56
    as "row 97347: dataBits00 0 gives no row part, the stat part alone: round(4.0 x 13.921875) = round(55.6875)"
  let level_flat =
    Spell4Effects(
      ..row(
        id: 99_000,
        data_bits00: one_as_float_bits,
        data_bits01: ten_as_float_bits,
      ),
      parameter_type00: 10,
      parameter_value00: 2.0,
    )
  assert amount(
      effect: level_flat,
      caster: OnCaster(
        ..attacker_support.novice_on_itself(),
        attacker: Attacker(
          ..attacker_support.novice_on_itself().attacker,
          level: 5,
        ),
      ),
    )
    == 20
    as "the flat part reads the level (kind 10) as a damage row's does: 1.0 x (10.0 + 2.0 x 5)"
}
