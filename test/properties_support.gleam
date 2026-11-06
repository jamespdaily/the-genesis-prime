//// A player's properties as the tests build them: the client's UnitProperty2 defaults
//// of the properties the rules name (`spell_tables.unit_property_defaults`) and the
//// properties the 0x262 lists from a loadout (`player_unit.gear_properties`).

import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/table/id.{type UnitProperty2Id, UnitProperty2Id}
import genesis_prime/world_map/player_unit
import gleam/list
import spell_tables

/// The client's defaults, by property id.
pub fn defaults() -> List(#(UnitProperty2Id, Float)) {
  list.map(spell_tables.unit_property_defaults(), fn(property) {
    #(UnitProperty2Id(property.0), property.1)
  })
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
