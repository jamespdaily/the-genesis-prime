//// The value of a damage effect for a player (`genesis_prime/game/damage`), on the
//// raw columns of the client's Spell4Effects rows (`table_rows -- Spell4Effects
//// spellId=<id>`). Expected values come from these places.
//// - At level 1 with rating 0 the stat part is 0 and the value is level x the type 10
////   parameter: Kick 4.16 (row 140383), Zap 9.08 (125182), Telekinetic Strike 18.0
////   (62159), Crush's second spell 8.94 (95950), Paralytic Surge 8.14 (96125) and
////   Stagger's per-hit spell 3.0 (83829); each row's dataBits00 is the float 1.0
////   (bits 1065353216) and dataBits01 is 0.
//// - The level-1 gear's ratings: Assault Rating 203.0625 and Support Rating 55.6875
////   (`player.level1_gear_properties`), Assault Power and Support Power 0.25 of
////   each (`0x140462930`, `0x140462980`), the stat part rounded half away from zero
////   (`0x140566d40`).
//// - A parameter type the rule does not read fails the load of its spell.
//// - Parameter types 1 to 5 and 11 read the caster's Strength, Dexterity, Technology,
////   Magic, Wisdom and Stamina (UnitProperty2 0 to 4 and 40), summed with the powers
////   into the one stat part before it is rounded (`0x140566d40` cases 1 to 5 and 0xb,
////   which read the live value at unit + 0x5c4 + 8 x id, `0x140466a70`). A player starts
////   each at its UnitProperty2 defaultValue, 1.0 for all six (`0x1404584b0`).
//// - Types 6 and 9 are the caster's Weapon and Weapon DPS, which the server does not
////   read yet (`Spell4Effects.parameterType.6_9`).
//// - The stat part is summed, and 0.5 added or taken away, in 32-bit floats before it
////   is cut to a whole number (`0x140566d40`).
//// - The flat part is summed in 32-bit floats from unit values read as unsigned 32-bit
////   integers, and the stat part's whole number is kept as signed 16-bit (`0x140566ad0`,
////   `0x140565782`, `0x14056578e`, `0x1405659f5`).
//// - The client rows: `table_rows -- Spell4Effects <id>`; each row's dataBits00 1065353216
////   is the float 1.0 and 0 is 0.0.

import attacker_support
import fixture_tables
import genesis_prime/game/damage.{
  Attacker, Attributes, Formula, Known, OfTarget, OnCaster, Parameter, Unread,
  Vitals,
}
import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import genesis_prime/table/spell4_effects
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import properties_support
import qcheck

/// An effect row of the client: dataBits00 1.0 as a float, dataBits01 0, and the
/// parameters (type 12 Assault Power, type 13 Support Power, type 10 level).
fn row(
  assault assault: Float,
  support support: Float,
  per_level per_level: Float,
) -> damage.Formula {
  Formula(multiplier: 1.0, base: 0.0, parameters: [
    Parameter(kind: 12, value: assault),
    Parameter(kind: 13, value: support),
    Parameter(kind: 10, value: per_level),
  ])
}

fn level_one(rating rating: Float, support support: Float) -> damage.Attacker {
  Attacker(
    ..attacker_support.fresh(),
    assault_rating: rating,
    support_rating: support,
  )
}

/// The client's Spell4Effects row `id` from the fixture.
fn client_row(id id: Int) -> spell4_effects.Spell4Effects {
  let assert Ok(row) =
    spell4_effects.get(tables: fixture_tables.shared(), id: Spell4EffectsId(id))
    as "the fixture holds the row"
  row
}

/// The formula of the client's damage or heal row `id`, as the area load builds it.
fn client_formula(id id: Int) -> damage.Formula {
  let assert Ok(formula) = damage.formula_of(effect: client_row(id:))
    as "the row's dataBits00 is a finite float"
  formula
}

/// The formula of the client's Absorption row `id`, as the plan builds it.
fn client_absorption(id id: Int) -> damage.Formula {
  let assert Ok(formula) = damage.absorption_formula_of(effect: client_row(id:))
    as "the row's dataBits00 and dataBits01 are finite floats"
  formula
}

/// A level-1 player whose 0x262 lists each `#(property id, value)` of `listed`, every
/// other property at its UnitProperty2 default.
fn player_listing(listed listed: List(#(Int, Float))) -> damage.Attacker {
  damage.attacker_of(
    properties: unit_properties.new(
      defaults: properties_support.defaults(),
      listed: list.map(listed, fn(pair) {
        let bits = float32.to_bits(value: pair.1)
        UnitProperty(property_id: pair.0, base: bits, value: bits)
      }),
      level: 1,
    ),
    level: 1,
  )
}

/// A formula of the multiplier 1.0 and the base 0 with one parameter.
fn one_parameter(kind kind: Int, factor factor: Float) -> damage.Formula {
  Formula(multiplier: 1.0, base: 0.0, parameters: [
    Parameter(kind:, value: factor),
  ])
}

/// Each attribute kind and the UnitProperty2 it reads (`0x140566d40` cases 1 to 5 and
/// 0xb): Strength, Dexterity, Technology, Magic, Wisdom and Stamina.
const attribute_kinds = [
  #(1, 0),
  #(2, 1),
  #(3, 2),
  #(4, 3),
  #(5, 4),
  #(11, 40),
]

pub fn each_level_one_ability_hits_for_its_level_parameter_at_rating_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let none = level_one(rating: 0.0, support: 0.0)
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.0656, support: 0.0656, per_level: 4.16),
      attacker: none,
    ),
    with: 4.16,
    tolerating: 0.0001,
  )
    as "Kick, Spell4Effects 140383"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.1434, support: 0.1434, per_level: 9.08),
      attacker: none,
    ),
    with: 9.08,
    tolerating: 0.0001,
  )
    as "Zap, 125182"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.336, support: 0.0, per_level: 18.0),
      attacker: none,
    ),
    with: 18.0,
    tolerating: 0.0001,
  )
    as "Telekinetic Strike, 62159"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.0837, support: 0.0837, per_level: 8.94),
      attacker: none,
    ),
    with: 8.94,
    tolerating: 0.0001,
  )
    as "Crush's second spell, 95950"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.0935, support: 0.0935, per_level: 8.14),
      attacker: none,
    ),
    with: 8.14,
    tolerating: 0.0001,
  )
    as "Paralytic Surge, 96125"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.035, support: 0.035, per_level: 3.0),
      attacker: none,
    ),
    with: 3.0,
    tolerating: 0.0001,
  )
    as "Stagger's per-hit spell, 83829"
}

pub fn the_gear_ratings_add_a_rounded_stat_part_test() -> Nil {
  use <- owned_test.run(5000)
  let gear = level_one(rating: 203.0625, support: 55.6875)
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.336, support: 0.0, per_level: 18.0),
      attacker: gear,
    ),
    with: 35.0,
    tolerating: 0.0001,
  )
    as "Telekinetic Strike: Assault Power 50.77 x 0.336 = 17.06 rounds to 17, plus 18"
  assert float.loosely_equals(
    damage.value(
      formula: row(assault: 0.0656, support: 0.0656, per_level: 4.16),
      attacker: gear,
    ),
    with: 8.16,
    tolerating: 0.0001,
  )
    as "Kick: 0.0656 x 50.77 + 0.0656 x 13.92 = 4.24 rounds to 4, plus 4.16"
}

pub fn a_parameter_type_the_rule_does_not_read_is_named_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.unread(formula: row(
      assault: 0.0656,
      support: 0.0656,
      per_level: 4.16,
    ))
    == None
  assert damage.unread(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 18, value: 0.1),
      ]),
    )
    == Some(Unread(parameter_kind: 18))
    as "type 19 reads the target's health (0x140566ad0), which is not built"
}

pub fn spellslinger_insight_damage_row_96307_is_2_with_wisdom_at_its_default_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.value(
      formula: client_formula(id: 96_307),
      attacker: damage.attacker_of(
        properties: properties_support.fresh(level: 1),
        level: 1,
      ),
    )
    == 2.0
    as "Spellslinger - Insight - Tier 1 - Damage: Wisdom (type 5) x 1.5 at the default 1.0 is 1.5, rounded half away from zero to 2, plus dataBits01 0 x 1.0"
}

pub fn each_attribute_kind_reads_its_own_property_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(attribute_kinds, fn(read) {
    let #(kind, property) = read
    assert damage.value(
        formula: one_parameter(kind:, factor: 1.0),
        attacker: player_listing(listed: [#(property, 3.0)]),
      )
      == 3.0
      as "the kind reads its own property at 3.0"
    list.each(attribute_kinds, fn(other) {
      case other.1 == property {
        True -> Nil
        False -> {
          assert damage.value(
              formula: one_parameter(kind:, factor: 1.0),
              attacker: player_listing(listed: [#(other.1, 3.0)]),
            )
            == 1.0
            as "another attribute at 3.0 leaves this kind at its own default 1.0"
        }
      }
    })
  })
}

pub fn the_attribute_and_power_products_are_summed_before_rounding_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 93496: Assault Power (12) x 0.5 and Strength (1) x 0.5, dataBits00 1.0 and
  // dataBits01 0. An Assault Rating (35) of 4.0 is an Assault Power of 1.0.
  assert damage.value(
      formula: client_formula(id: 93_496),
      attacker: player_listing(listed: [#(35, 4.0)]),
    )
    == 1.0
    as "0.5 x 1.0 + 0.5 x 1.0 = 1.0 rounds to 1; rounding each 0.5 apart would give 2"
  assert damage.value(
      formula: client_formula(id: 93_496),
      attacker: player_listing(listed: [#(0, 3.0), #(35, 4.0)]),
    )
    == 2.0
    as "0.5 x 1.0 + 0.5 x 3.0 = 2.0; rounding each part apart would give 1 + 2 = 3, and leaving Strength out 1"
}

pub fn the_stat_part_is_summed_and_rounded_in_32_bit_floats_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 108207 (e395- [Datascape] Earth Elemental - Knockout Combo, Spell4 46220):
  // Strength (1) x 3.6 and Assault Power (12) x 3.6, both 0x40666666, dataBits00 1.0 and
  // dataBits01 0. An Assault Rating (35) of 1.0 is an Assault Power of 0.25.
  // 0x140566d40 keeps the sum in a 32-bit float: 3.6f + 0.9f = 4.5f exactly, and
  // 4.5f + 0.5f = 5.0f, which it cuts to 5.
  assert damage.value(
      formula: client_formula(id: 108_207),
      attacker: player_listing(listed: [#(35, 1.0)]),
    )
    == 5.0
    as "in 64-bit floats the sum is 4.49999988, which rounds to 4"
}

pub fn a_creatures_stat_part_is_summed_and_cut_in_32_bit_floats_test() -> Nil {
  use <- owned_test.run(5000)
  // Creature2 50700 (Eldan Defense Probe, archetype 13, difficulty 5, tier 1) at level 25,
  // as the content load works its properties out (each product held as a 32-bit float):
  // CreatureLevel 25's value 0 is 0x43a8af4c and its value 35 is 0x44a8af4c; archetype 13
  // and difficulty 5 multiply both by 0x3f8ccccd and 0x3fe00000, tier 1 by 1.0. Strength
  // is 649.4363403320312 and the Assault Rating 2597.745361328125, whose Assault Power
  // (0.25 of it) is 649.4363403320312.
  // Row 115620 (Spell4Effects, spell 48982): dataBits00 1.0, dataBits01 0, Assault Power
  // (12) x 0x3f7c154d (0.9847000241279602) and the level (10) x 0x41ef3333
  // (29.899999618530273). 0x140566d40 multiplies in a 32-bit float: 649.43634 x 0.9847
  // is 639.49998 exactly, which a 32-bit float holds as 639.5; 639.5f + 0.5f = 640.0f,
  // cut to 640. GameFormula 712 is 70, 100, 1, 1 (0x428c0000, 0x42c80000, 0x3f800000,
  // 0x3f800000): the cap is (25 x 70 + 100) x 0.9847 = 1821.7, above 640. The row part
  // is 25 x 29.9 = 747.5, so the value is 640 + 747.5.
  let value =
    damage.creature_value(
      formula: client_formula(id: 115_620),
      creature: damage.Creature(
        level: 25,
        strength: 649.4363403320312,
        assault_power: 649.4363403320312,
      ),
      scaling: damage.CreatureScaling(
        per_level: 70.0,
        base: 100.0,
        overflow: 1.0,
        divisor: 1.0,
      ),
      multiplier: 1.0,
    )
  assert float.loosely_equals(value, with: 1387.5, tolerating: 0.0001)
    as "a 64-bit sum is 639.49998, which rounds to 639 and gives 1386.5"
}

pub fn a_creature_formula_runs_in_32_bit_floats_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x1405659f5: the creature path's cap, the exponential branch, the division by
  // GameFormula 712's fourth value and S + R are 32-bit floats, S and R divided apart.
  // Row 115620 (Spell4Effects, spell 48982) at level 25: Assault Power (12) x 0x3f7c154d
  // (0.9847000241279602), the level (10) x 0x41ef3333 (29.899999618530273), dataBits00
  // 1.0, dataBits01 0. GameFormula 712 is 70, 100, 1, 1. The cap c is
  // (25 x 70 + 100) x 0.9847 = 1821.695068359375 as a 32-bit float; R is 25 x 29.9 = 747.5.
  // An Assault Power of 1900 gives S = 1871 (1870.93 + 0.5, cut), above c, so S becomes
  // ((1 - e^(-(S - c) / c)) x 1 + 1) x (c / 1) held in 32 bits after each step, and
  // 32-bit 2617.8388671875 is the sum with 747.5 (the steps worked by hand in single
  // precision, each rounded once). The same steps in 64-bit floats give 2617.83874.
  let formula = client_formula(id: 115_620)
  let beast = fn(assault_power) {
    damage.Creature(level: 25, strength: 0.0, assault_power:)
  }
  let scaling = fn(divisor) {
    damage.CreatureScaling(
      per_level: 70.0,
      base: 100.0,
      overflow: 1.0,
      divisor:,
    )
  }
  assert damage.creature_value(
      formula:,
      creature: beast(1900.0),
      scaling: scaling(1.0),
      multiplier: 1.0,
    )
    == 2617.8388671875
    as "beyond the cap every step is a 32-bit float"
  // GameFormula 712's fourth value is 1.0 in the client's table, but the client divides
  // by whatever it holds. An Assault Power of 400 gives S = 394 (393.88 + 0.5), under c.
  // With a divisor of 3.0 (a value no row holds), S / 3 = 131.33333 and R / 3 =
  // 249.16667 are 32-bit floats each, and their 32-bit sum is 380.5; dividing the 64-bit
  // sum (394 + 747.5) / 3 gives 380.49999682.
  assert damage.creature_value(
      formula:,
      creature: beast(400.0),
      scaling: scaling(3.0),
      multiplier: 1.0,
    )
    == 380.5
    as "under the cap S and R are divided apart, each a 32-bit float"
}

pub fn a_row_base_is_read_as_an_unsigned_32_bit_integer_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140565782: the base (dataBits01) is `mov eax, r9d; cvtsi2ss xmm10, rax`, an
  // unsigned 32-bit integer made a 32-bit float, so -1000 (top bit set) is
  // 2^32 - 1000 = 4294966296, which a 32-bit float holds as 4294966272 (above 2^31
  // its steps are 256). The tables' integer columns are signed 32-bit values. No
  // damage, heal or shield row of the client has the top bit set in dataBits01 (293
  // other Spell4Effects rows have, none of effect type 8, 10, 12, 33, 118 or 138), so the
  // row is row 115620 changed, its two parameters made 0.0 so the base alone is read.
  let row =
    spell4_effects.Spell4Effects(
      ..client_row(id: 115_620),
      data_bits01: -1000,
      parameter_value00: 0.0,
      parameter_value01: 0.0,
    )
  let assert Ok(formula) = damage.formula_of(effect: row)
    as "the row's dataBits00 is the float 1.0"
  assert damage.value(formula:, attacker: attacker_support.fresh())
    == 4_294_966_272.0
    as "a player's row base is unsigned"
  assert damage.creature_value(
      formula:,
      creature: damage.Creature(level: 25, strength: 0.0, assault_power: 0.0),
      scaling: damage.CreatureScaling(
        per_level: 70.0,
        base: 100.0,
        overflow: 1.0,
        divisor: 1.0,
      ),
      multiplier: 1.0,
    )
    == 4_294_966_272.0
    as "a creature's row base is unsigned"
}

pub fn the_flat_part_is_summed_in_32_bit_floats_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 45661 (Spell4Effects, damage): dataBits00 1.0, dataBits01 0, type 7 (the
  // target's maximum health) x 0x3d75c28f. 0x140566ad0 makes the 25 a 32-bit float,
  // multiplies it by the parameter in a 32-bit float and sums from 0.0 in a 32-bit
  // float: 25 x 0.0600000023841858 is 1.50000005960464 exactly, which a 32-bit float
  // holds as 1.5.
  let formula = client_formula(id: 45_661)
  let unit = Vitals(health: 25, max_health: 25, shield: 0, max_shield: 0)
  assert damage.finish(
      partial: damage.partial(formula:, caster: caster()),
      target: unit,
    )
    == 1.5
    as "in 64-bit floats the product is 1.4999999665 for the same 0x3d75c28f"
  assert damage.value_on_caster(
      formula:,
      caster: OnCaster(..caster(), vitals: unit),
    )
    == 1.5
    as "an effect on its caster sums the same way"
}

pub fn a_unit_value_is_read_as_an_unsigned_32_bit_integer_and_held_in_32_bits_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 zero-extends each unit value and each difference (mov eax, eax;
  // cvtsi2ss xmm0, rax), so a difference below 0 counts as 2^32 less its size, and
  // a 32-bit float keeps 24 bits.
  let health_above_the_maximum =
    Vitals(health: 5001, max_health: 5000, shield: 0, max_shield: 0)
  assert damage.finish(
      partial: damage.partial(
        formula: one_parameter(kind: 21, factor: 0.5),
        caster: caster(),
      ),
      target: health_above_the_maximum,
    )
    == 2_147_483_648.0
    as "the target's maximum health less its health is -1, which is 4294967295 and 2^32 as a 32-bit float; half of it"
  assert damage.value_on_caster(
      formula: one_parameter(kind: 22, factor: 0.5),
      caster: OnCaster(
        ..caster(),
        vitals: Vitals(health: 1, max_health: 1, shield: 601, max_shield: 600),
      ),
    )
    == 2_147_483_648.0
    as "the maximum shield less the shield of the caster that is also the target"
  assert damage.finish(
      partial: damage.partial(
        formula: one_parameter(kind: 19, factor: 1.0),
        caster: caster(),
      ),
      target: Vitals(
        health: 16_777_217,
        max_health: 16_777_217,
        shield: 0,
        max_shield: 0,
      ),
    )
    == 16_777_216.0
    as "2^24 + 1 needs 25 bits, which a 32-bit float rounds to even"
}

pub fn a_stat_part_beyond_16_bits_wraps_as_a_signed_16_bit_number_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x14056578e (movsx eax, r10w) keeps the stat part's whole number as a signed 16-bit
  // value before it becomes a float, for a player and for a creature (the stat part is
  // the one fVar9 before ComputeEffectValue's creature branch).
  let strength = one_parameter(kind: 1, factor: 1.0)
  let with_strength = fn(strength_value) {
    Attacker(
      ..attacker_support.fresh(),
      attributes: Attributes(
        ..attacker_support.fresh().attributes,
        strength: strength_value,
      ),
    )
  }
  assert damage.value(formula: strength, attacker: with_strength(32_767.0))
    == 32_767.0
    as "the largest signed 16-bit number is kept"
  assert damage.value(formula: strength, attacker: with_strength(32_768.0))
    == -32_768.0
    as "32768 is -32768 as a signed 16-bit number"
  assert damage.value(formula: strength, attacker: with_strength(65_541.0))
    == 5.0
    as "65541 is 5"
  assert damage.value(formula: strength, attacker: with_strength(-32_769.0))
    == 32_767.0
    as "-32769 is 32767"
  assert damage.finish(
      partial: damage.partial(
        formula: strength,
        caster: OnCaster(..caster(), attacker: with_strength(32_768.0)),
      ),
      target: target(),
    )
    == -32_768.0
    as "the caster's side keeps the same whole number"
  assert damage.creature_value(
      formula: strength,
      creature: damage.Creature(
        level: 1,
        strength: 32_768.0,
        assault_power: 0.0,
      ),
      scaling: damage.CreatureScaling(
        per_level: 70.0,
        base: 100.0,
        overflow: 1.0,
        divisor: 1.0,
      ),
      multiplier: 1.0,
    )
    == -32_768.0
    as "a creature's stat part is cut the same way"
}

pub fn the_weapon_kinds_6_and_9_are_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  // The client's labels for the parameter kinds (0x140b0b580, printed by 0x1404de8d0 as
  // "[%.*f%% %s]") name 6 "Weapon" (text 184461) and 9 "Weapon DPS" (text 209247): the
  // caster's weapon damage, which the server does not read yet (#807).
  assert damage.unread(formula: client_formula(id: 49_028))
    == Some(Unread(parameter_kind: 6))
    as "row 49028: kind 6 x 2.25 beside its Strength x 1.0"
  assert damage.unread(formula: client_formula(id: 1369))
    == Some(Unread(parameter_kind: 6))
    as "Engineer Melee Auto Attack: kind 6 x 1.0"
  assert damage.unread(formula: client_formula(id: 77_124))
    == Some(Unread(parameter_kind: 9))
    as "Explorer - Offensive Path Ability - Eldan Relic: kind 9 x 7.0"
}

pub fn unread_reads_the_vital_kinds_and_still_names_6_9_and_18_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [1, 2, 3, 4, 5, 11, 7, 8, 14, 15, 16, 17, 19, 21, 22, 23, 25, 26],
    fn(kind) {
      assert damage.unread(formula: one_parameter(kind:, factor: 0.5)) == None
        as "0x140566ad0 reads the attribute kinds and each vital kind, of the caster or of the target"
    },
  )
  list.each([6, 9, 18], fn(kind) {
    assert damage.unread(formula: one_parameter(kind:, factor: 0.5))
      == Some(Unread(parameter_kind: kind))
      as "6 and 9 are the caster's weapon damage (0x140566ad0 sends them to its default case) and 18 a value passed in, which the area load does not read"
  })
}

pub fn a_fresh_players_attributes_are_the_tables_defaults_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.attacker_of(
      properties: properties_support.fresh(level: 1),
      level: 1,
    ).attributes
    == Attributes(
      strength: 1.0,
      dexterity: 1.0,
      technology: 1.0,
      magic: 1.0,
      wisdom: 1.0,
      stamina: 1.0,
    )
    as "UnitProperty2 0 to 4 and 40 have defaultValue 0x3f800000, which a player starts at"
}

pub fn a_modifier_on_strength_reaches_the_formula_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 124962 (Spell4 52782) is a type 11 row on property 0 with dataBits01 1,
  // the multiplier 1.0 (dataBits02 1065353216) and the flat 1.0 (dataBits03 1065353216).
  let fresh = properties_support.fresh(level: 1)
  let modified =
    properties_support.with_modifier(
      properties: fresh,
      source: unit_properties.Source(
        cast_id: 1,
        effect_id: Spell4EffectsId(124_962),
      ),
      modifier: unit_properties.Change(
        property: UnitProperty2Id(0),
        mode: 1,
        multiplier: 1.0,
        flat: 1.0,
        per_level: 0.0,
      ),
    )
  let strength = one_parameter(kind: 1, factor: 1.0)
  assert damage.attacker_of(properties: modified, level: 1).attributes.strength
    == 2.0
    as "1.0 x 1.0 + 1.0"
  assert damage.value(
      formula: strength,
      attacker: damage.attacker_of(properties: fresh, level: 1),
    )
    == 1.0
  assert damage.value(
      formula: strength,
      attacker: damage.attacker_of(properties: modified, level: 1),
    )
    == 2.0
    as "the formula reads the live value of Strength, not its base"
}

pub fn an_attribute_factor_counts_as_a_stat_part_and_a_weapon_factor_as_an_amount_for_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let magic_absorb = client_absorption(id: 46_275)
  assert !damage.gives_nothing(formula: magic_absorb)
    as "row 46275: Magic x 10.0 sits outside the dataBits00 product, so a multiplier of 0.0 does not zero it"
  assert damage.value_on_caster(
      formula: magic_absorb,
      caster: OnCaster(
        ..attacker_support.novice_on_itself(),
        attacker: attacker_support.fresh(),
      ),
    )
    == 10.0
    as "Magic 1.0 x 10.0, plus (0.0 + 0) x 0.0"
  assert !damage.gives_nothing(formula: client_formula(id: 77_124))
    as "Eldan Relic: kind 9 x 7.0 is the caster's Weapon DPS (text 209247), an amount the client lacks, not nothing"
  assert !damage.gives_nothing(formula: client_formula(id: 1369))
    as "Engineer Melee Auto Attack: kind 6 x 1.0 is the caster's Weapon (text 184461), an amount the client lacks, not nothing"
}

pub fn the_value_on_its_caster_reads_the_casters_attributes_test() -> Nil {
  use <- owned_test.run(5000)
  let on_itself = fn(attacker) {
    OnCaster(..attacker_support.novice_on_itself(), attacker:)
  }
  let water_shield = client_absorption(id: 68_969)
  assert damage.value_on_caster(
      formula: water_shield,
      caster: on_itself(attacker_support.fresh()),
    )
    == 5.0
    as "Water Shield - Pell Water: Magic 1.0 x 5.0"
  assert damage.value_on_caster(
      formula: water_shield,
      caster: on_itself(player_listing(listed: [#(3, 2.0)])),
    )
    == 10.0
    as "Water Shield - Pell Water: Magic 2.0 x 5.0"
  assert damage.value_on_caster(
      formula: client_formula(id: 94_299),
      caster: on_itself(attacker_support.fresh()),
    )
    == 2.0
    as "Esper - Tech - Rank 3 - Shield Heal Proc: Technology 1.0 x 1.5 rounds half away from zero to 2"
}

/// A caster at 500 of 736 health and 250 of 450 shield, with the level-1 Novice's stats.
fn caster() -> damage.OnCaster {
  OnCaster(
    attacker: attacker_support.fresh(),
    vitals: Vitals(health: 500, max_health: 736, shield: 250, max_shield: 450),
  )
}

/// A target at 3000 of 5000 health and 200 of 600 shield.
fn target() -> damage.Vitals {
  Vitals(health: 3000, max_health: 5000, shield: 200, max_shield: 600)
}

pub fn a_target_kind_is_left_for_the_target_and_finished_with_its_vitals_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 reads these of param_2, the target: 7 the maximum health (slot 0x48), 15
  // the shield (0x70), 17 the maximum shield (0x78), 19 the health (0x40), 21 the
  // maximum health less the health and 22 the maximum shield less the shield.
  let expected = [
    #(7, 5000.0),
    #(15, 200.0),
    #(17, 600.0),
    #(19, 3000.0),
    #(21, 2000.0),
    #(22, 400.0),
  ]
  list.each(expected, fn(entry) {
    let formula = one_parameter(kind: entry.0, factor: 0.5)
    let partial = damage.partial(formula:, caster: caster())
    assert partial.terms == [OfTarget(kind: entry.0, factor: 0.5)]
      as "the caster's side leaves the target's kind for the target"
    assert damage.finish(partial:, target: target()) == 0.5 *. entry.1
      as "M x (S + (base + factor x the target's slot) x dataBits00)"
  })
  let with_row_part =
    Formula(multiplier: 2.0, base: 10.0, parameters: [
      Parameter(kind: 7, value: 0.1),
    ])
  assert damage.finish(
      partial: damage.partial(formula: with_row_part, caster: caster()),
      target: target(),
    )
    == 1020.0
    as "0x140565600: the flat 10 and the target's 0.1 x 5000 are added, then multiplied by 2.0"
}

pub fn a_caster_kind_is_worked_out_from_the_casters_vitals_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 reads these of param_1, the caster: 8 the maximum health, 14 the shield,
  // 16 the maximum shield, 23 the health, 25 the maximum health less the health (736 -
  // 500) and 26 the maximum shield less the shield (450 - 250).
  let expected = [
    #(8, 736.0),
    #(14, 250.0),
    #(16, 450.0),
    #(23, 500.0),
    #(25, 236.0),
    #(26, 200.0),
  ]
  list.each(expected, fn(entry) {
    let partial =
      damage.partial(
        formula: one_parameter(kind: entry.0, factor: 1.0),
        caster: caster(),
      )
    assert partial.terms == [Known(entry.1)]
      as "the caster's side works the term out"
    assert damage.finish(partial:, target: target()) == entry.1
    assert damage.finish(
        partial:,
        target: Vitals(health: 1, max_health: 2, shield: 3, max_shield: 4),
      )
      == entry.1
      as "whatever the target holds"
  })
}

pub fn a_formula_naming_both_sides_reads_each_from_its_own_unit_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 sends 7 to the target and 8 to the caster. Six rows of the client's
  // tables name both.
  let formula =
    Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 7, value: 0.1),
      Parameter(kind: 8, value: 0.02),
    ])
  let partial =
    damage.partial(
      formula:,
      caster: OnCaster(
        ..caster(),
        vitals: Vitals(health: 1000, max_health: 1000, shield: 0, max_shield: 0),
      ),
    )
  assert float.loosely_equals(
    damage.finish(partial:, target: target()),
    with: 520.0,
    tolerating: 0.0001,
  )
    as "0.1 x the target's 5000 + 0.02 x the caster's 1000"
}

pub fn a_formula_with_no_target_kind_finishes_to_the_value_it_has_today_test() -> Nil {
  use <- owned_test.run(5000)
  let on_caster = fn(attacker) { OnCaster(..caster(), attacker:) }
  // Kick 4.16, Zap 9.08, Telekinetic Strike 18.0, Crush 8.94, Paralytic Surge 8.14 and
  // Stagger 3.0 at level 1 and rating 0 (the header's rows), each a level-only formula.
  list.each(
    [
      #(140_383, 4.16),
      #(125_182, 9.08),
      #(62_159, 18.0),
      #(95_950, 8.94),
      #(96_125, 8.14),
      #(83_829, 3.0),
    ],
    fn(entry) {
      let formula = client_formula(id: entry.0)
      let partial =
        damage.partial(formula:, caster: on_caster(attacker_support.fresh()))
      assert float.loosely_equals(
        damage.finish(partial:, target: target()),
        with: entry.1,
        tolerating: 0.0001,
      )
        as "the level-1 value of the row"
      assert damage.finish(partial:, target: target())
        == damage.value(formula:, attacker: attacker_support.fresh())
        as "exactly the value a formula with no target kind has today"
    },
  )
  let stat_formula = row(assault: 0.0656, support: 0.0656, per_level: 4.16)
  assert damage.finish(
      partial: damage.partial(
        formula: stat_formula,
        caster: on_caster(attacker_support.novice()),
      ),
      target: Vitals(health: 9, max_health: 9, shield: 9, max_shield: 9),
    )
    == damage.value(formula: stat_formula, attacker: attacker_support.novice())
    as "a formula with stat kinds too"
}

pub fn the_flat_terms_are_summed_in_parameter_order_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 adds each parameter's term to a running sum in parameter order, in
  // 32-bit floats. 2^24 + 1 is 2^24 (a tie to even) and 1 + 1 + 2^24 is 2^24 + 2.
  let formula = fn(first_kind) {
    Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: first_kind, value: 1.0),
      Parameter(kind: 10, value: 1.0),
      Parameter(kind: 10, value: 1.0),
      Parameter(kind: 0, value: 0.0),
    ])
  }
  let big = 16_777_216
  let big_unit = Vitals(health: big, max_health: big, shield: 0, max_shield: 0)
  assert damage.finish(
      partial: damage.partial(
        formula: formula(23),
        caster: OnCaster(..caster(), vitals: big_unit),
      ),
      target: target(),
    )
    == 16_777_216.0
    as "the caster's health first: 2^24, plus 1, plus 1"
  assert damage.finish(
      partial: damage.partial(formula: formula(19), caster: caster()),
      target: big_unit,
    )
    == 16_777_216.0
    as "the target's health first: the same order, the same sum"
  assert damage.finish(
      partial: damage.partial(
        formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
          Parameter(kind: 10, value: 1.0),
          Parameter(kind: 10, value: 1.0),
          Parameter(kind: 19, value: 1.0),
          Parameter(kind: 0, value: 0.0),
        ]),
        caster: caster(),
      ),
      target: big_unit,
    )
    == 16_777_218.0
    as "the health last: 1 + 1 + 2^24"
}

/// A parameter kind the formula reads: none, a stat, the level or a vital.
fn kind_generator() -> qcheck.Generator(Int) {
  qcheck.from_generators(
    qcheck.constant(0),
    list.map(
      [
        1, 2, 3, 4, 5, 10, 11, 12, 13, 7, 8, 14, 15, 16, 17, 19, 21, 22, 23, 25,
        26,
      ],
      qcheck.constant,
    ),
  )
}

fn parameter_generator() -> qcheck.Generator(damage.Parameter) {
  qcheck.map2(
    kind_generator(),
    qcheck.bounded_float(from: -2.0, to: 2.0),
    fn(kind, value) { Parameter(kind:, value:) },
  )
}

pub fn finishing_on_the_caster_equals_the_casters_own_value_property_test() -> Nil {
  use <- owned_test.run(60_000)
  let generator = {
    use parameters <- qcheck.bind(qcheck.fixed_length_list_from(
      parameter_generator(),
      4,
    ))
    use multiplier <- qcheck.bind(qcheck.bounded_float(from: 0.0, to: 3.0))
    use base <- qcheck.bind(qcheck.bounded_float(from: -50.0, to: 500.0))
    use ratings <- qcheck.bind(qcheck.tuple2(
      qcheck.bounded_float(from: 0.0, to: 3000.0),
      qcheck.bounded_float(from: 0.0, to: 3000.0),
    ))
    use vitals <- qcheck.map(qcheck.tuple4(
      qcheck.bounded_int(from: 1, to: 200_000),
      qcheck.bounded_int(from: 0, to: 200_000),
      qcheck.bounded_int(from: 0, to: 60_000),
      qcheck.bounded_int(from: 0, to: 60_000),
    ))
    #(Formula(multiplier:, base:, parameters:), ratings, vitals)
  }
  use #(formula, ratings, vitals) <- qcheck.given(generator)
  let max_health = vitals.0
  let max_shield = vitals.2
  let caster =
    OnCaster(
      attacker: Attacker(
        ..attacker_support.fresh(),
        assault_rating: ratings.0,
        support_rating: ratings.1,
      ),
      vitals: Vitals(
        health: int.min(vitals.1, max_health),
        max_health:,
        shield: int.min(vitals.3, max_shield),
        max_shield:,
      ),
    )
  assert damage.finish(
      partial: damage.partial(formula:, caster:),
      target: caster.vitals,
    )
    == damage.value_on_caster(formula:, caster:)
    as "a unit that is both caster and target reads each kind from the one unit, in the same 32-bit order"
}

pub fn a_creatures_formula_still_refuses_a_vital_kind_test() -> Nil {
  use <- owned_test.run(5000)
  // A creature's formula reads Strength (1), Assault Power (12) and the level (10) only.
  // The attack spells the server gives creatures today (Spell4 5649, 85469 and 86978)
  // name no vital kind in any parameter, so no creature row meets this refusal.
  assert damage.creature_unread(formula: one_parameter(kind: 7, factor: 0.5))
    == Some(damage.Unread(parameter_kind: 7))
    as "kind 7 is a vital kind and is not read for a creature caster"
  assert damage.creature_unread(formula: one_parameter(kind: 23, factor: 0.5))
    == Some(damage.Unread(parameter_kind: 23))
}
