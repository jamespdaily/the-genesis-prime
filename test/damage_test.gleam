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
//// - The client rows: `table_rows -- Spell4Effects <id>`; each row's dataBits00 1065353216
////   is the float 1.0 and 0 is 0.0.

import attacker_support
import fixture_tables
import genesis_prime/game/damage.{
  Attacker, Attributes, Formula, OnCaster, Parameter, Unread,
}
import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import genesis_prime/table/spell4_effects
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import owned_test
import properties_support

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
        Parameter(kind: 19, value: 0.1),
      ]),
    )
    == Some(Unread(parameter_kind: 19))
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

pub fn unread_reads_the_attribute_kinds_and_still_names_each_vital_kind_and_18_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 3, 4, 5, 11], fn(kind) {
    assert damage.unread(formula: one_parameter(kind:, factor: 0.5)) == None
      as "a player's value reads the attribute kinds"
  })
  list.each([6, 7, 8, 9, 14, 15, 18, 19, 21], fn(kind) {
    assert damage.unread(formula: one_parameter(kind:, factor: 0.5))
      == Some(Unread(parameter_kind: kind))
      as "the caster's weapon damage, a vital of a unit or a passed-in value, which the area load does not read"
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

pub fn caster_unread_reads_the_attribute_kinds_and_still_names_6_9_and_18_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 3, 4, 5, 11], fn(kind) {
    assert damage.caster_unread(formula: one_parameter(kind:, factor: 0.5))
      == None
      as "an effect on its caster reads the attribute kinds"
  })
  list.each([6, 9, 18], fn(kind) {
    assert damage.caster_unread(formula: one_parameter(kind:, factor: 0.5))
      == Some(Unread(parameter_kind: kind))
      as "6 and 9 are the caster's weapon damage (0x140b0b580) and 18 a value passed in, which the server does not read"
  })
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
