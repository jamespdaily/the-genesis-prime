//// A player's Interrupt Armor (`genesis_prime/game/player_life` `armor_followed`,
//// `properties_changed`) beside its properties (`genesis_prime/game/unit_properties`),
//// as the pure rules they are. Expected values come from these places.
//// - `UnitProperty2.InterruptArmor_Threshold` (44, default 0.0 for a player:
////   `table_rows -- UnitProperty2 44`) is the unit's Interrupt Armor maximum, and a raised
////   maximum is a raised armor: the Soldier's Clear the Lines (Spell4 36861, Spell4Effects
////   78035) raises property 44 by +2 with a type 11 row and no type 52 row, and its
////   tooltip (text 298981) says the Interrupt Armor rises by 2; a creature's armor is its
////   maximum until something wears it down (`creature_control`). Nothing wears a player's
////   armor down, so the armor is the maximum, and dataBits01 of a type 52 row (1 takes the
////   points back, 0 keeps them) makes no difference to it (`Spell4Effects.effectType.52`).
//// - `opcode.0x938.interrupt_armor`: stat 21 is the current armor, and the client clamps
////   it to 0 and the maximum when a 0x938 arrives, unless the maximum is -1 (infinite).
////   An armor above a lowered maximum stays until the next 0x938, so the armor is told
////   after the maximum rises and before it falls.
//// - `opcode.0x93a`: an entry carries the property's base and value as 32-bit floats.
//// - The type 11 formula (`Spell4Effects.effectType.11.change`, `unit_properties`): a
////   change is x * 1.0 + n applied in start order, and the same source applied twice is
////   held once.

import genesis_prime/client_connection
import genesis_prime/game/player_life.{
  type Life, OwnInterruptArmor, Regeneration, ToClient, ToViewers,
}
import genesis_prime/game/unit_properties.{
  type Changed, type Properties, type Source, Change, Changed, Source,
}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import gleam/list
import gleam/option.{None}
import owned_test
import properties_support

const regeneration =
  Regeneration(
    health_fraction: 0.025,
    health_multiplier: 1.0,
    health_tick_ms: 500,
    shield: None,
  )

/// A player of 1 health, the BaseHealth the tests' properties hold, so that a change of
/// the properties lowers nothing but the armor.
fn player() -> Life {
  player_life.new(health: 1, shield: 0, regeneration:)
}

fn source(effect_id effect_id: Int) -> Source {
  Source(cast_id: 1, effect_id: Spell4EffectsId(effect_id))
}

/// A player whose 0x262 lists property 44 with this base and value.
fn with_base(base base: Float) -> Properties {
  let bits = float32.to_bits(base)
  unit_properties.new(
    defaults: properties_support.defaults(),
    listed: [UnitProperty(property_id: 44, base: bits, value: bits)],
    level: 1,
  )
}

/// A player with base 2 for property 44 and its armor: the armor follows the maximum, so
/// the 0x262's 2 is an armor of 2 once the life takes the properties.
fn with_base_2() -> #(Life, Properties) {
  let properties = with_base(base: 2.0)
  let #(life, _) = player_life.properties_changed(life: player(), properties:)
  #(life, properties)
}

/// The change of an Interrupt Armor row of `points`: x * 1.0 + points on property 44.
fn started(
  life life: Life,
  properties properties: Properties,
  source source: Source,
  points points: Int,
) -> #(Life, Properties, List(Changed), List(player_life.Effect)) {
  change(
    life:,
    properties:,
    source:,
    modifier: unit_properties.interrupt_armor_modifier(points:),
  )
}

/// The properties with `modifier` live from `source`, then what the life makes of the new
/// maximum: the life and properties after it, the 0x93a entries the change reports and the
/// life's effects.
fn change(
  life life: Life,
  properties properties: Properties,
  source source: Source,
  modifier modifier: unit_properties.Modifier,
) -> #(Life, Properties, List(Changed), List(player_life.Effect)) {
  let #(properties, changed) =
    unit_properties.apply(properties:, source:, modifier:)
  let #(life, effects) = player_life.properties_changed(life:, properties:)
  #(life, properties, changed, effects)
}

/// The end of `source`'s change: the armor follows the maximum that is left, told first,
/// then the maximum lowered and what the life makes of it. Returns the life and
/// properties after it, the 0x93a entries the change reports and the life's effects in
/// order.
fn ended(
  life life: Life,
  properties properties: Properties,
  source source: Source,
) -> #(Life, Properties, List(Changed), List(player_life.Effect)) {
  let #(without, changed) = unit_properties.remove(properties:, source:)
  let #(life, taken) = player_life.armor_followed(life:, properties: without)
  let #(life, clamped) =
    player_life.properties_changed(life:, properties: without)
  #(life, without, changed, list.append(taken, clamped))
}

/// The two writes of an armor: to the player's client and to each viewer.
fn told(armor armor: Int) -> List(player_life.Effect) {
  [
    ToClient(OwnInterruptArmor(armor:)),
    ToViewers(client_connection.InterruptArmor(armor:)),
  ]
}

fn property_44(base base: Float, value value: Float) -> Changed {
  Changed(property: UnitProperty2Id(44), base:, value:)
}

pub fn an_interrupt_armor_start_raises_the_maximum_then_the_armor_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, properties, changed, effects) =
    started(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: source(effect_id: 199_192),
      points: 1,
    )
  assert changed == [property_44(base: 0.0, value: 1.0)]
    as "0x93a {44, base 0.0, value 1.0}: UnitProperty2 44's default is 0.0 and the row adds 1"
  assert unit_properties.entries(changed:)
    == [
      UnitProperty(
        property_id: 44,
        base: float32.to_bits(0.0),
        value: float32.to_bits(1.0),
      ),
    ]
  assert effects == told(armor: 1)
    as "the armor follows the maximum: 0x938 stat 21 = 1 to the player and the news to each viewer, written after the 0x93a the maximum goes in"
  assert player_life.interrupt_armor(life:) == 1
  assert unit_properties.value(
      properties:,
      property: unit_properties.interrupt_armor_threshold,
    )
    == 1.0
}

pub fn an_interrupt_armor_end_that_takes_back_lowers_the_armor_then_the_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  let grant = source(effect_id: 97_340)
  let #(life, properties, _, _) =
    started(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: grant,
      points: 2,
    )
  assert player_life.interrupt_armor(life:) == 2
  let #(life, properties, changed, effects) =
    ended(life:, properties:, source: grant)
  assert effects == told(armor: 0)
    as "stat 21 = 0 is written with the end, before the maximum falls"
  assert changed == [property_44(base: 0.0, value: 0.0)]
    as "then 0x93a {44, 0.0, 0.0}, which the client's clamp never sees an armor above"
  assert player_life.interrupt_armor(life:) == 0
  assert unit_properties.value(
      properties:,
      property: unit_properties.interrupt_armor_threshold,
    )
    == 0.0
}

pub fn an_interrupt_armor_end_that_keeps_clamps_the_armor_to_the_new_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  // Base 2 and a grant of 3: the maximum 5 and the armor 5, and at the end the maximum is
  // 2 again and the armor follows it. Row 97343's dataBits01 0 keeps the armor, which
  // makes no difference while nothing wears armor down.
  let grant = source(effect_id: 97_343)
  let #(life, properties) = with_base_2()
  assert player_life.interrupt_armor(life:) == 2
    as "the armor is the maximum, 2"
  let #(life, properties, _, effects) =
    started(life:, properties:, source: grant, points: 3)
  assert effects == told(armor: 5)
    as "2 and 3 raise the maximum and the armor to 5"
  let #(life, _, changed, effects) = ended(life:, properties:, source: grant)
  assert changed == [property_44(base: 2.0, value: 2.0)]
    as "the maximum falls back to 2"
  assert effects == told(armor: 2)
    as "and the armor goes with it, told before the maximum falls"
  assert player_life.interrupt_armor(life:) == 2
  // With base 0 the same grant leaves nothing: 1 and then 0.
  let #(life, properties, _, effects) =
    started(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: grant,
      points: 1,
    )
  assert effects == told(armor: 1)
  let #(life, _, _, effects) = ended(life:, properties:, source: grant)
  assert effects == told(armor: 0)
  assert player_life.interrupt_armor(life:) == 0
}

pub fn two_interrupt_armor_grants_add_and_end_one_at_a_time_test() -> Nil {
  use <- owned_test.run(5000)
  let first = source(effect_id: 97_340)
  let second = source(effect_id: 97_341)
  let properties = properties_support.fresh(level: 1)
  let #(life, properties, _, _) =
    started(life: player(), properties:, source: first, points: 1)
  let #(life, properties, changed, effects) =
    started(life:, properties:, source: second, points: 2)
  assert changed == [property_44(base: 0.0, value: 3.0)]
    as "x * 1.0 + 1, then x * 1.0 + 2 in start order: 3"
  assert effects == told(armor: 3)
  let #(life, properties, changed, effects) =
    ended(life:, properties:, source: first)
  assert effects == told(armor: 2)
    as "the +1 ends and the armor follows the maximum"
  assert changed == [property_44(base: 0.0, value: 2.0)]
    as "the maximum is the +2 alone"
  assert player_life.interrupt_armor(life:) == 2
  let #(life, _, _, effects) = ended(life:, properties:, source: second)
  assert effects == told(armor: 0)
  assert player_life.interrupt_armor(life:) == 0
}

pub fn a_source_started_twice_is_held_once_and_ended_once_test() -> Nil {
  use <- owned_test.run(5000)
  let grant = source(effect_id: 199_192)
  let #(life, properties, _, _) =
    started(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: grant,
      points: 1,
    )
  let #(life, properties, changed, effects) =
    started(life:, properties:, source: grant, points: 1)
  assert changed == [] && effects == []
    as "a later go of the same cast names the same source again: nothing changes, nothing is written"
  assert player_life.interrupt_armor(life:) == 1
  let #(life, properties, _, effects) = ended(life:, properties:, source: grant)
  assert effects == told(armor: 0)
  let #(life, _, changed, effects) = ended(life:, properties:, source: grant)
  assert changed == [] && effects == []
    as "an end for a source no longer held changes nothing"
  assert player_life.interrupt_armor(life:) == 0
}

pub fn a_type_11_raising_property_44_raises_the_armor_too_test() -> Nil {
  use <- owned_test.run(5000)
  // The Soldier's Clear the Lines (Spell4 36861, row 78035): x * 1.0 + 2 on property 44
  // with no type 52 row, and its tooltip says the Interrupt Armor rises by 2 (text 298981).
  let row = source(effect_id: 78_035)
  let #(life, properties, changed, effects) =
    change(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: row,
      modifier: Change(
        property: UnitProperty2Id(44),
        mode: 3,
        multiplier: 1.0,
        flat: 2.0,
        per_level: 0.0,
      ),
    )
  assert changed == [property_44(base: 0.0, value: 2.0)]
  assert effects == told(armor: 2)
    as "stat 21 rises with the maximum, 0x938 to the player and the news to each viewer"
  assert player_life.interrupt_armor(life:) == 2
  let #(life, _, _, effects) = ended(life:, properties:, source: row)
  assert effects == told(armor: 0) as "and falls with it"
  assert player_life.interrupt_armor(life:) == 0
}

pub fn a_lowered_interrupt_armor_maximum_from_a_property_change_lowers_the_armor_test() -> Nil {
  use <- owned_test.run(5000)
  // A type 11 row on property 44 (x 1.0 + 5), an armor row of 3 on top of it, the armor
  // row's end, then the type 11's end.
  let type_11 = source(effect_id: 99_011)
  let grant = source(effect_id: 99_052)
  let #(life, properties, _, effects) =
    change(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: type_11,
      modifier: Change(
        property: unit_properties.interrupt_armor_threshold,
        mode: 3,
        multiplier: 1.0,
        flat: 5.0,
        per_level: 0.0,
      ),
    )
  assert effects == told(armor: 5)
  let #(life, properties, _, effects) =
    started(life:, properties:, source: grant, points: 3)
  assert effects == told(armor: 8)
  let #(life, properties, _, effects) = ended(life:, properties:, source: grant)
  assert effects == told(armor: 5)
    as "the armor row's end lowers the maximum from 8 to 5 and the armor with it"
  let #(life, _, changed, effects) = ended(life:, properties:, source: type_11)
  assert changed == [property_44(base: 0.0, value: 0.0)]
  assert effects == told(armor: 0)
    as "the type 11's end takes the maximum to 0 and the armor with it, and the player and its viewers are told"
  assert player_life.interrupt_armor(life:) == 0
}

pub fn an_infinite_maximum_does_not_clamp_the_armor_test() -> Nil {
  use <- owned_test.run(5000)
  // -1 is no clamp (`opcode.0x938.interrupt_armor`): there is no number for the armor to
  // follow, so it shows 0 and nothing is written for it, and a change of the properties
  // that leaves the maximum infinite changes nothing either.
  let infinite = with_base(base: -1.0)
  let #(life, effects) =
    player_life.properties_changed(life: player(), properties: infinite)
  assert player_life.interrupt_armor(life:) == 0 && effects == []
  let #(life, effects) =
    player_life.properties_changed(life:, properties: infinite)
  assert player_life.interrupt_armor(life:) == 0 && effects == []
}
