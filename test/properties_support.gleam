//// A player's properties as the tests build them: the client's UnitProperty2 defaults,
//// built by the server's load of the fixture's rows, and the properties the 0x262 lists
//// from a loadout (`player_unit.gear_properties`).

import fixture_tables
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/table/id.{type UnitProperty2Id}
import genesis_prime/world_map/player_unit

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
    listed: player_unit.gear_properties(loadout:, max_health: 1),
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
