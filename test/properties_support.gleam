//// A player's properties as the tests build them: the client's UnitProperty2 defaults,
//// built by the server's load of the fixture's rows, and the properties the 0x262 lists
//// from a loadout.

import character_support
import fixture_tables
import genesis_prime/game/gear.{type Gear}
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/shared/item_property.{Shield}
import genesis_prime/shared/loadout.{type Loadout}
import genesis_prime/shared/player_unit
import genesis_prime/shared/unit_properties.{type Properties}
import genesis_prime/table/id.{type UnitProperty2Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import place_support
import unit_support

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
  listing(level: 1, listed: listed_by(loadout:, max_health: 1))
}

/// The properties with `modifier` live from `source`, the changes it reports dropped.
pub fn with_modifier(
  properties properties: Properties,
  source source: unit_properties.Source,
  modifier modifier: unit_properties.Modifier,
) -> Properties {
  unit_properties.apply(properties:, source:, modifier:).0
}

/// A level-1 player wearing the loadout, as its 0x262 lists it: the gear's properties as
/// `wearing` lists them and the literal 26 rows of `base_combat_rows`, which include the 24
/// the entry leaves out for equalling their default (`entered` makes the unit as the entry
/// does, from `gear.bases`).
pub fn wearing_with_base_combat(loadout loadout: Loadout) -> Properties {
  listing(
    level: 1,
    listed: list.append(listed_by(loadout:, max_health: 1), base_combat_rows),
  )
}

/// The properties a player's 0x262 lists for its loadout's gear, in id order, as (id, number): `max_health` as Base Health (7), the Assault Rating (35),
/// Support Rating (36) and Armor (42), and the shield's ShieldCapacityMax (41),
/// ShieldMitigationMax (175), ShieldRegenPct (176) and ShieldRebootTime (178) when the
/// loadout holds a shield.
fn listed_by(
  loadout loadout: Loadout,
  max_health max_health: Int,
) -> List(#(Int, Float)) {
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
}

/// The 26 combat properties a player holds and the value of each in CreatureLevel
/// row 101, the row properties 100 and above read (`0x1404585c0`, `CreatureLevel 101`):
/// BaseAvoidChance and BaseCritChance 0.05, CCDurationModifier 1.0, the other 23 0.0.
pub const base_combat_rows = [
  #(101, 0.05),
  #(102, 0.05),
  #(103, 0.0),
  #(104, 0.0),
  #(105, 0.0),
  #(144, 0.0),
  #(145, 0.0),
  #(146, 0.0),
  #(147, 0.0),
  #(148, 0.0),
  #(149, 0.0),
  #(150, 0.0),
  #(151, 0.0),
  #(152, 0.0),
  #(153, 0.0),
  #(154, 0.0),
  #(155, 0.0),
  #(156, 0.0),
  #(157, 0.0),
  #(158, 0.0),
  #(164, 0.0),
  #(165, 1.0),
  #(166, 0.0),
  #(167, 0.0),
  #(195, 0.0),
  #(196, 0.0),
]

/// A player of `level` whose 0x262 lists exactly `listed`, each as its base and value
/// (id, number): every other property at its default.
pub fn listing(
  level level: Int,
  listed listed: List(#(Int, Float)),
) -> Properties {
  unit_properties.new(
    defaults: defaults(),
    listed: list.map(listed, fn(pair) {
      let bits = float32.to_bits(pair.1)
      UnitProperty(property_id: pair.0, base: bits, value: bits)
    }),
    level:,
  )
}

/// A player of `level` as its entry makes it: the bases of the gear `worn` as its 0x262
/// lists them (`player_unit.with_gear` leaves out each equal to its default), every other
/// property at its default.
pub fn entered(worn worn: Gear, level level: Int) -> Properties {
  let tables = fixture_tables.shared()
  let assert Ok(bases) =
    gear.bases(tables:, gear: worn, level:, focus_pool: 0.0)
    as "the fixture holds CreatureLevel rows for the level"
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: character_support.character(number: 1),
        place: place_support.live_character_place(),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
    |> player_unit.with_gear(
      replacing: [],
      item_visuals: [],
      bases:,
      defaults: defaults(),
      shield: None,
    )
  unit_properties.new(
    defaults: defaults(),
    listed: unit.tail.properties,
    level:,
  )
}
