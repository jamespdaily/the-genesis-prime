//// A Simple unit (a world spawn of type 10, shown to the player as a `ShownObject`) for
//// the tests of a click, an accept and a turn-in on one. The expected values are in the
//// tests, each from the client's rows and code.
////
//// - Creature2 12545 gives and receives quest 3689 (`questIdGiven00`, `questIdReceive00`),
////   an auto-complete quest of level 3 with no objective; Creature2 73422 and 73604 are
////   the talk targets of quests 10525 and 10528 (a type 18 checklist and a type 3 talk);
////   Creature2 73606 gives and receives no quest.
//// - Faction2 170 is Hostile to the Exile faction 167 and 219 is not, as the Faction2
////   rows give them (`faction_level.hostile`, the client's `0x14045a950`).
//// - Creature2DisplayInfo 25703's hitRadius is 0x3f800000, 1.0; Race 3's is 1.2.

import game_connection_support as connection_support
import genesis_prime/game/connection as game_connection
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_life.{type Hostile}
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/static_object.{type Created, StaticObject}
import gleam/dict
import spawn_support
import vendor_support

/// The unit id the tests' Simple unit is shown as.
pub const unit = 40

/// The hit radius of the display the connection tests give the unit (Creature2DisplayInfo
/// 25703), and the one the rule tests' pictures give it.
pub const radius = 1.0

/// The display of the connection tests' unit.
pub const display_info = 25_703

/// The place `gap` from the player's edge straight ahead of the player at the entry place.
fn gap_from_player(gap gap: Float) -> start_place.Place {
  let entry = connection_support.entry_place()
  start_place.moved(
    place: entry,
    x: start_place.x(entry),
    y: start_place.y(entry),
    z: start_place.z(entry) -. { gap +. vendor_support.player_radius +. radius },
  )
}

/// A picture holding the Simple unit as unit 40, `gap` from the player's edge, for the
/// rules that read a picture.
pub fn picture(
  creature_id creature_id: Int,
  faction_id faction_id: Int,
  checklist_index checklist_index: Int,
  gap gap: Float,
  hostile_to hostile_to: Hostile,
) -> shown.Picture {
  dict.from_list([
    #(
      unit,
      shown.ShownObject(
        creature_id: Creature2Id(creature_id),
        faction_id:,
        checklist_index:,
        place: gap_from_player(gap:),
        hit_radius: radius,
        hostile_to:,
      ),
    ),
  ])
}

/// The 0x262 the map writes for the Simple unit as unit 40, `gap` from the player's edge.
pub fn created(
  creature_id creature_id: Int,
  faction_id faction_id: Int,
  gap gap: Float,
) -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(number: unit, place: gap_from_player(gap:)),
      creature_id: Creature2Id(creature_id),
      faction_id:,
      base_faction_id: faction_id,
      display_info_id: display_info,
    ),
    unit_id: unit,
    server_time_estimate_start: 0,
  )
}

/// The connection once the map has told it its player sees the Simple unit.
pub fn seen_by(
  state state: game_connection.State,
  creature_id creature_id: Int,
  faction_id faction_id: Int,
  gap gap: Float,
) -> game_connection.State {
  connection_support.feed(
    state:,
    event: connection_support.sent_by_the_map(
      ObjectsSeen(units: [created(creature_id:, faction_id:, gap:)]),
    ),
  ).0
}
