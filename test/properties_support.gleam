//// A player's properties as the tests build them: the client's UnitProperty2 defaults,
//// built by the server's load of the fixture's rows, and the properties the 0x262 lists
//// from a loadout.

import fixture_tables
import genesis_prime/game/item_property.{Shield}
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/table/id.{type UnitProperty2Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// The client's defaults, by property id: every UnitProperty2 row of the fixture.
pub fn defaults() -> List(#(UnitProperty2Id, Float)) {
  unit_properties.defaults(tables: fixture_tables.shared())
}

/// A player of `level` whose 0x262 lists nothing: every property at its default.
pub fn fresh(level level: Int) -> Properties {
  unit_properties.new(defaults: defaults(), listed: [], level:)
}

/// A level-1 player wearing the loadout, as its 0x262 lists the gear, with the maximum
/// health 1.
pub fn wearing(loadout loadout: Loadout) -> Properties {
  unit_properties.new(
    defaults: defaults(),
    listed: listed_by(loadout:, max_health: 1),
    level: 1,
  )
}

/// The properties with `modifier` live from `source`, the changes it reports dropped.
pub fn with_modifier(
  properties properties: Properties,
  source source: unit_properties.Source,
  modifier modifier: unit_properties.Modifier,
) -> Properties {
  unit_properties.apply(properties:, source:, modifier:).0
}

/// The properties a player's 0x262 lists for its loadout's gear, in id order, each with
/// its base and value alike: `max_health` as Base Health (7), the Assault Rating (35),
/// Support Rating (36) and Armor (42), and the shield's ShieldCapacityMax (41),
/// ShieldMitigationMax (175), ShieldRegenPct (176) and ShieldRebootTime (178) when the
/// loadout holds a shield.
fn listed_by(
  loadout loadout: Loadout,
  max_health max_health: Int,
) -> List(UnitProperty) {
  let gear = loadout.properties
  let shield_properties = case gear.shield {
    Some(Shield(capacity_max:, mitigation_max:, regen_percent:, reboot_time_ms:)) -> [
      #(41, capacity_max),
      #(175, mitigation_max),
      #(176, regen_percent),
      #(178, int.to_float(reboot_time_ms)),
    ]
    None -> []
  }
  list.flatten([
    [
      #(7, int.to_float(max_health)),
      #(35, gear.assault_rating),
      #(36, gear.support_rating),
      #(42, gear.armor),
    ],
    shield_properties,
  ])
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(pair) {
    let bits = float32.to_bits(pair.1)
    UnitProperty(property_id: pair.0, base: bits, value: bits)
  })
}
