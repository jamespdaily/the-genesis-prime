//// The property conversions of a player's properties (`genesis_prime/game/unit_properties`
//// `Conversion`). Expected values come from these places:
//// - `Spell4Effects.effectType.145`: property dataBits01 gains dataBits02 times property
////   dataBits00 while the effect lasts, and the client works out no property, so the
////   server computes the amount and sends the result; the tooltip 450095 reads "Multi-Hit
////   Severity Rating increased by 25% of Critical Severity Rating" for 229304 (47 to 60 at
////   0x3e800000, 0.25).
//// - The rows 226750 and 226751 of 86841: 7 (Base Health) to 42 (Armor) at 0x3e4ccccd
////   (0.2) and 42 to 7 at 0x3dcccccd (0.1), orderIndex 0 and 1.
//// - The server's choices, which the module's doc names with their gap: the source is the
////   source's value (after its changes), a conversion is worked out after every change of
////   the unit's properties, conversions apply in the order they started, and a conversion
////   pair runs once each with no loop.
//// - `unit_properties`' rule that a change that leaves a value as it was reports nothing,
////   and that ending a modifier works the values out again from the bases and the live
////   changes (`unit_properties_test`).
//// - `UnitProperty2` 7, 42, 47 and 60: default values 1.0, 0.0, 0.0 and 0.0
////   (`table_rows -- UnitProperty2 7 42 47 60`).

import genesis_prime/game/unit_properties.{
  type Properties, type Source, Changed, Conversion, Modifier, Source,
}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import gleam/float
import gleam/list
import owned_test
import properties_support

const base_health = UnitProperty2Id(7)

const armor = UnitProperty2Id(42)

const crit_severity = UnitProperty2Id(47)

const multi_hit = UnitProperty2Id(60)

/// 0.2 and 0.1 as rows 226750 and 226751 hold them: the 32-bit floats' values.
const a_fifth = 0.20000000298023224

const a_tenth = 0.10000000149011612

fn source(effect_id effect_id: Int) -> Source {
  Source(cast_id: 1, effect_id: Spell4EffectsId(effect_id))
}

fn started(
  properties properties: Properties,
  effect_id effect_id: Int,
  modifier modifier: unit_properties.Modifier,
) -> #(Properties, List(unit_properties.Changed)) {
  unit_properties.apply(properties:, source: source(effect_id:), modifier:)
}

/// A properties holding the 0x262's base for these properties, a level-1 player.
fn holding(bases bases: List(#(Int, Float))) -> Properties {
  unit_properties.new(
    defaults: properties_support.defaults(),
    listed: list.map(bases, fn(base) {
      let bits = float32.to_bits(base.1)
      UnitProperty(property_id: base.0, base: bits, value: bits)
    }),
    level: 1,
  )
}

/// A type 11 row's change that adds `flat` to the property.
fn adds(
  property property: id.UnitProperty2Id,
  flat flat: Float,
) -> unit_properties.Modifier {
  Modifier(property:, mode: 3, multiplier: 1.0, flat:, per_level: 0.0)
}

/// Whether two numbers are the same to a ten-thousandth: 0.2 and 0.1 are 32-bit floats in
/// the rows, so a product carries their rounding.
fn near(first first: Float, second second: Float) -> Bool {
  float.absolute_value(first -. second) <. 0.0001
}

pub fn a_conversion_adds_its_share_of_the_sources_value_to_the_target_test() -> Nil {
  use <- owned_test.run(5000)
  // Property 47 at 100 and 229304's share 0.25 give property 60 a value of its base 0
  // plus 25.
  let #(_, changed) =
    started(
      properties: holding(bases: [#(47, 100.0)]),
      effect_id: 229_304,
      modifier: Conversion(from: crit_severity, to: multi_hit, share: 0.25),
    )
  assert changed == [Changed(property: multi_hit, base: 0.0, value: 25.0)]
    as "fact 145: property dataBits01 gains dataBits02 times property dataBits00; the change reports 60's base and value, and 47 is not named"
}

pub fn a_change_of_the_source_that_starts_after_the_conversion_moves_the_target_in_the_same_change_test() -> Nil {
  use <- owned_test.run(5000)
  let #(properties, _) =
    started(
      properties: holding(bases: [#(47, 100.0)]),
      effect_id: 229_304,
      modifier: Conversion(from: crit_severity, to: multi_hit, share: 0.25),
    )
  // A type 11 change that adds 40 to property 47 starts later: 47 is 140 and 60 is
  // 0.25 x 140 = 35, both in the one report.
  let #(properties, rose) =
    started(
      properties:,
      effect_id: 1,
      modifier: adds(property: crit_severity, flat: 40.0),
    )
  assert rose
    == [
      Changed(property: crit_severity, base: 100.0, value: 140.0),
      Changed(property: multi_hit, base: 0.0, value: 35.0),
    ]
    as "the target rises by the share of the source's rise, 0.25 x 40 = 10, in the same reported change, in property order"
  let #(properties, ended) =
    unit_properties.remove(properties:, source: source(effect_id: 1))
  assert ended
    == [
      Changed(property: crit_severity, base: 100.0, value: 100.0),
      Changed(property: multi_hit, base: 0.0, value: 25.0),
    ]
    as "its end lowers both back"
  assert unit_properties.value(properties:, property: multi_hit) == 25.0
}

pub fn two_conversions_apply_in_the_order_they_started_after_every_change_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows 226750 (7 to 42 at 0.2) and 226751 (42 to 7 at 0.1) of 86841, with Base Health
  // 1,000 and Armor 0: the first adds 0.2 x 1,000 = 200 to Armor, the second adds 0.1 x
  // 200 = 20 to Base Health.
  let #(properties, _) =
    started(
      properties: holding(bases: [#(7, 1000.0), #(42, 0.0)]),
      effect_id: 226_750,
      modifier: Conversion(from: base_health, to: armor, share: a_fifth),
    )
  let #(properties, _) =
    started(
      properties:,
      effect_id: 226_751,
      modifier: Conversion(from: armor, to: base_health, share: a_tenth),
    )
  assert near(
    first: unit_properties.value(properties:, property: armor),
    second: 200.0,
  )
    as "42 = 0 + 0.2 x 1,000"
  assert near(
    first: unit_properties.value(properties:, property: base_health),
    second: 1020.0,
  )
    as "7 = 1,000 + 0.1 x 200: each conversion runs once, in start order, with no loop"
  assert unit_properties.base(properties:, property: base_health) == 1000.0
    as "a conversion changes the value and never the base"
}

pub fn a_conversion_whose_source_is_zero_reports_no_change_when_it_starts_or_ends_test() -> Nil {
  use <- owned_test.run(5000)
  // Property 47's default is 0, so a level-1 Engineer's 229304 adds 0 to property 60.
  let #(properties, started_changes) =
    started(
      properties: properties_support.fresh(level: 1),
      effect_id: 229_304,
      modifier: Conversion(from: crit_severity, to: multi_hit, share: 0.25),
    )
  assert started_changes == []
    as "a change that leaves a value as it was reports nothing"
  let #(properties, ended_changes) =
    unit_properties.remove(properties:, source: source(effect_id: 229_304))
  assert ended_changes == []
  assert unit_properties.value(properties:, property: multi_hit) == 0.0
}

pub fn ending_a_conversion_works_the_values_out_again_from_the_bases_and_the_live_changes_test() -> Nil {
  use <- owned_test.run(5000)
  let #(properties, _) =
    started(
      properties: holding(bases: [#(47, 100.0)]),
      effect_id: 1,
      modifier: adds(property: crit_severity, flat: 40.0),
    )
  let #(properties, _) =
    started(
      properties:,
      effect_id: 229_304,
      modifier: Conversion(from: crit_severity, to: multi_hit, share: 0.25),
    )
  assert unit_properties.value(properties:, property: multi_hit) == 35.0
    as "the conversion takes the source's value after the change that started first"
  let #(properties, ended) =
    unit_properties.remove(properties:, source: source(effect_id: 229_304))
  assert ended == [Changed(property: multi_hit, base: 0.0, value: 0.0)]
    as "ending the conversion takes the amount off the target and leaves the source's change"
  assert unit_properties.value(properties:, property: crit_severity) == 140.0
    as "the change that is still live stays applied to the base"
  assert unit_properties.entries(changed: ended)
    == [UnitProperty(property_id: 60, base: 0x00000000, value: 0x00000000)]
}
