//// A player's Interrupt Armor (`genesis_prime/game/player_life` `armor_given`,
//// `armor_ended`, `properties_changed`) beside its properties
//// (`genesis_prime/game/unit_properties`), as the pure rules they are. Expected values
//// come from these places.
//// - `Spell4Effects.effectType.52`: a type 52 row raises the unit's Interrupt Armor
////   maximum (UnitProperty2 44, InterruptArmor_Threshold, default 0.0 for a player:
////   `table_rows -- UnitProperty2 44`) and its armor by dataBits00 points for its time;
////   dataBits01 1 takes the points back at the end and 0 keeps the armor, which the
////   maximum then clamps (the test spells 42697 'Modify +2 Remove', 42698 'Modify +2 No
////   Remove': grade guess).
//// - `opcode.0x938.interrupt_armor`: stat 21 is the current armor, and the client clamps
////   it to 0 and the maximum when a 0x938 arrives, unless the maximum is -1 (infinite).
////   So the maximum is sent before the armor rises and the armor before the maximum
////   falls, and the server clamps its own armor the same way.
//// - `opcode.0x93a`: an entry carries the property's base and value as 32-bit floats.
//// - The type 11 formula (`Spell4Effects.effectType.11.change`, `unit_properties`): a
////   change is x * 1.0 + n applied in start order, and the same source applied twice is
////   held once.
//// - A player starts a fight with no armor: its 0x262 holds no stat 21, so the client
////   shows 0 until a 0x938 says otherwise.

import genesis_prime/client_connection
import genesis_prime/game/player_life.{
  type Life, OwnInterruptArmor, Regeneration, ToClient, ToViewers,
}
import genesis_prime/game/unit_properties.{
  type Changed, type Properties, type Source, Changed, Source,
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

/// The armor rule's start: the maximum raised by the points (x * 1.0 + points), what the
/// life makes of the new maximum, then the armor given. Returns the life and properties
/// after it, the 0x93a entries the change reports and the life's effects in order.
fn started(
  life life: Life,
  properties properties: Properties,
  source source: Source,
  points points: Int,
  takes_back takes_back: Bool,
) -> #(
  Life,
  Properties,
  List(unit_properties.Changed),
  List(player_life.Effect),
) {
  let #(properties, changed) =
    unit_properties.apply(
      properties:,
      source:,
      modifier: unit_properties.interrupt_armor_modifier(points:),
    )
  let #(life, clamped) = player_life.properties_changed(life:, properties:)
  let #(life, given) =
    player_life.armor_given(life:, source:, points:, takes_back:)
  #(life, properties, changed, list.append(clamped, given))
}

/// The armor rule's end: the armor the end leaves, under the maximum that is left, told
/// first, then the maximum lowered and what is left of the armor clamped to it. Returns
/// the life and properties after it, the 0x93a entries the change reports and the life's
/// effects in order.
fn ended(
  life life: Life,
  properties properties: Properties,
  source source: Source,
) -> #(
  Life,
  Properties,
  List(unit_properties.Changed),
  List(player_life.Effect),
) {
  let #(without, changed) = unit_properties.remove(properties:, source:)
  let #(life, taken) =
    player_life.armor_ended(life:, source:, properties: without)
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
      takes_back: False,
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
    as "the life writes the armor once the maximum allows it: 0x938 stat 21 = 1 to the player and the news to each viewer"
  assert player_life.interrupt_armor(life:) == 1
  assert player_life.max_interrupt_armor(life:) == 1
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
      takes_back: True,
    )
  assert player_life.interrupt_armor(life:) == 2
  let #(life, properties, changed, effects) =
    ended(life:, properties:, source: grant)
  assert effects == told(armor: 0)
    as "stat 21 = 0 first: row 97340's dataBits01 1 takes the points back"
  assert changed == [property_44(base: 0.0, value: 0.0)]
    as "then 0x93a {44, 0.0, 0.0}, which the clamp at receipt of the 0x938 never sees: the armor is 0 already"
  assert player_life.interrupt_armor(life:) == 0
  assert player_life.max_interrupt_armor(life:) == 0
  assert unit_properties.value(
      properties:,
      property: unit_properties.interrupt_armor_threshold,
    )
    == 0.0
}

pub fn an_interrupt_armor_end_that_keeps_clamps_the_armor_to_the_new_maximum_test() -> Nil {
  use <- owned_test.run(5000)
  // Base 2 and a kept grant of 3: the maximum 5 and the armor 3 (the armor starts at 0),
  // and at the end the maximum is 2 again and the armor is clamped to it.
  let grant = source(effect_id: 97_343)
  let #(life, properties, _, effects) =
    started(
      life: player_life.properties_changed(
        life: player(),
        properties: with_base(base: 2.0),
      ).0,
      properties: with_base(base: 2.0),
      source: grant,
      points: 3,
      takes_back: False,
    )
  assert effects == told(armor: 3) as "0 + 3, under the maximum 2 + 3 = 5"
  assert player_life.max_interrupt_armor(life:) == 5
  let #(life, _, changed, effects) = ended(life:, properties:, source: grant)
  assert changed == [property_44(base: 2.0, value: 2.0)]
    as "row 97343's dataBits01 0 keeps the armor: only the maximum falls back to 2"
  assert effects == told(armor: 2)
    as "and the armor, 3, is clamped to the new maximum 2 and told with the end, before the maximum falls: the client holds no armor above its maximum"
  assert player_life.interrupt_armor(life:) == 2
  // With base 0 the same grant leaves nothing: 1 and then 0.
  let #(life, properties, _, effects) =
    started(
      life: player(),
      properties: properties_support.fresh(level: 1),
      source: grant,
      points: 1,
      takes_back: False,
    )
  assert effects == told(armor: 1)
  let #(life, _, _, effects) = ended(life:, properties:, source: grant)
  assert effects == told(armor: 0)
    as "the maximum falls to 0 and takes the kept armor with it"
  assert player_life.interrupt_armor(life:) == 0
}

pub fn two_interrupt_armor_grants_add_and_end_one_at_a_time_test() -> Nil {
  use <- owned_test.run(5000)
  let first = source(effect_id: 97_340)
  let second = source(effect_id: 97_341)
  let properties = properties_support.fresh(level: 1)
  let #(life, properties, _, _) =
    started(
      life: player(),
      properties:,
      source: first,
      points: 1,
      takes_back: True,
    )
  let #(life, properties, changed, effects) =
    started(life:, properties:, source: second, points: 2, takes_back: True)
  assert changed == [property_44(base: 0.0, value: 3.0)]
    as "x * 1.0 + 1, then x * 1.0 + 2 in start order: 3"
  assert effects == told(armor: 3) as "1 + 2, under the maximum 3"
  let #(life, properties, changed, effects) =
    ended(life:, properties:, source: first)
  assert effects == told(armor: 2) as "the +1 ends and takes its point back"
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
      takes_back: True,
    )
  let #(life, properties, changed, effects) =
    started(life:, properties:, source: grant, points: 1, takes_back: True)
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

pub fn a_lowered_interrupt_armor_maximum_from_a_property_change_clamps_the_armor_test() -> Nil {
  use <- owned_test.run(5000)
  // A type 11 row on property 44 (x 1.0 + 5), a kept armor of 3 on top of it, the armor's
  // end (kept: the armor stays 3 under the maximum 5), then the type 11's end: the
  // maximum falls to 0 and takes the armor with it.
  let type_11 = source(effect_id: 99_011)
  let grant = source(effect_id: 99_052)
  let properties = properties_support.fresh(level: 1)
  let #(properties, _) =
    unit_properties.apply(
      properties:,
      source: type_11,
      modifier: unit_properties.Modifier(
        property: unit_properties.interrupt_armor_threshold,
        mode: 3,
        multiplier: 1.0,
        flat: 5.0,
        per_level: 0.0,
      ),
    )
  let #(life, _) = player_life.properties_changed(life: player(), properties:)
  assert player_life.max_interrupt_armor(life:) == 5
  let #(life, properties, _, _) =
    started(life:, properties:, source: grant, points: 3, takes_back: False)
  let #(life, properties, _, effects) = ended(life:, properties:, source: grant)
  assert player_life.interrupt_armor(life:) == 3 && effects == []
    as "the maximum 8 falls to 5 and the armor 3 is under it: nothing to write"
  let #(properties, changed) =
    unit_properties.remove(properties:, source: type_11)
  let #(life, effects) = player_life.properties_changed(life:, properties:)
  assert changed == [property_44(base: 0.0, value: 0.0)]
  assert player_life.interrupt_armor(life:) == 0
  assert effects == told(armor: 0)
    as "the armor follows the maximum down, and the player and its viewers are told"
}

pub fn an_infinite_maximum_does_not_clamp_the_armor_test() -> Nil {
  use <- owned_test.run(5000)
  // -1 is no clamp (`opcode.0x938.interrupt_armor`).
  let infinite = with_base(base: -1.0)
  let #(life, _) =
    player_life.properties_changed(life: player(), properties: infinite)
  assert player_life.max_interrupt_armor(life:) == -1
  let #(life, effects) =
    player_life.armor_given(
      life:,
      source: source(effect_id: 1),
      points: 7,
      takes_back: True,
    )
  assert player_life.interrupt_armor(life:) == 7
    as "7 under an infinite maximum is 7"
  assert effects == told(armor: 7)
  let #(life, effects) =
    player_life.properties_changed(life:, properties: infinite)
  assert player_life.interrupt_armor(life:) == 7 && effects == []
    as "a property change that leaves the maximum infinite clamps nothing"
}
