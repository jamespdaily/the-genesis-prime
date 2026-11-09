//// A player's unit as message 0x262 creates it (`genesis_prime/world_map/player_unit`).
//// Expected values come from these places.
//// - The client's own bytes for a live character: `vector.opcode.0x262.roxo_alive`
////   (the fact file), message 0x262's body for Roxo Stompstone (unit id 1,
////   type 20, character id 1, realm 1, race 3, class 1, gender 0, path 0,
////   faction 167 and base faction 167, every other value 0) with one kind 2
////   command at (4605.65, -7.571, 494.996), stat 0 (health) 136 and property 7
////   (Base Health) 136.0 twice, which the client's reader takes in all 1120
////   bits. The path is 0 there, as the PvP flags are, so the vector fits the
////   unit this module builds.
//// - The place: a kind 2 command at the saved position with its bit clear, then
////   a kind 14 command with the saved yaw, pitch and roll (0x1404586e0,
////   0x140715350); 0.5 is the 32 bits 0x3F000000, -0.25 is 0xBE800000 and 1.5
////   is 0x3FC00000 (IEEE 754 binary32).
//// - The health: the unit `create` makes holds no health and no gear property; the
////   health as stat 0 (`with_integer_stat`) and the gear as properties 7 (Base Health)
////   and the rest (`with_gear`) are put in by the connection's entry. The vector's 136
////   is the client's level-1 creature Base Health (0x1404585c0), which
////   `unit_support.bare_health` stands in for here. What a Novice set's gear adds
////   (ratings, armor, shield) is `world_entry_loadout_test`'s and `step_b_unit_test`'s.
//// - The level: stat 10 of the unit's stats is its level, and a unit created
////   without it is level 1 (0x140458140, 0x1404543c1).

import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/float32
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/store.{Character, CharacterId, NameStands}
import genesis_prime/table/id.{ClassId, RaceId, UnitProperty2Id}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None, Some}
import message_support
import owned_test
import place_support
import unit_support

/// Roxo Stompstone as the live character of the vector.
fn roxo() -> store.Character {
  Character(
    character_id: CharacterId(1),
    name: "Roxo Stompstone",
    gender: 0,
    race_id: RaceId(3),
    class_id: ClassId(1),
    faction_id: 167,
    level: 1,
    path: 0,
    place: Some(place_support.live_character_place()),
    look: [],
    bones: [],
    naming: NameStands,
  )
}

pub fn the_unit_of_the_live_character_is_the_clients_1120_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: roxo(),
        place: place_support.live_character_place(),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  let unit =
    player_unit.with_gear(
      record: unit,
      replacing: [],
      item_visuals: [],
      bases: [#(UnitProperty2Id(7), 136.0)],
      shield: None,
    )
  let assert Ok(body) =
    unit_create_player.encode(
      UnitCreatePlayer(
        ..unit,
        tail: UnitCreateTail(
          ..unit.tail,
          stats: [unit_fields.integer_stat(stat_id: 0, value: 136)],
          movement_commands: list.take(unit.tail.movement_commands, 1),
        ),
      ),
    )
    as "the unit encodes, with the vector's one stat, its one property and its one kind 2 command: the vector holds no stat 10, no kind 14 and no rating or armor property, and those are tested apart"
  assert body
    == message_support.hex(
      "0100000054000000000000004000e02105f0068007f006000230054007f006d006000730074007f006e006500630020000000000000000000000000000000001800800000000000010c44cfb639168913c70dfdffd908003000084210000842100000000008053e0140000000000000000000000004000000000000000000040000000000000000000000000",
    )
    as "vector.opcode.0x262.roxo_alive: the client's reader takes these 140 bytes for the live character, alive at its place, with Base Health"
}

pub fn the_unit_is_placed_at_its_position_and_turned_the_way_the_place_faces_test() -> Nil {
  use <- owned_test.run(10_000)
  let turned =
    start_place.turned(
      place_support.live_character_place(),
      Facing(yaw: 0.5, pitch: -0.25, roll: 1.5),
    )
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: roxo(),
        place: turned,
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  assert unit.tail.movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: float32.to_bits(4605.65),
        y: float32.to_bits(-7.571),
        z: float32.to_bits(494.996),
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0x3F000000,
        pitch: 0xBE800000,
        roll: 0x3FC00000,
        blends: 0,
      )),
    ]
    as "kind 2 places the unit at once (its bit is clear) and kind 14 turns it by the place's facing"
}

pub fn the_unit_carries_the_visuals_and_bones_it_is_given_and_the_path_never_reaches_its_pvp_flags_test() -> Nil {
  use <- owned_test.run(10_000)
  let visual =
    ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0)
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: Character(..roxo(), path: 3, bones: [0x3F800001, 0x3F800002]),
        place: place_support.live_character_place(),
        unit_id: 9,
        body: [visual],
      ),
      realm_id: 4,
    )
  assert unit.tail.item_visuals == [visual]
    as "opcode.0x262: the body is the character list's visuals, as given"
  assert unit.bone_values == [0x3F800001, 0x3F800002]
    as "opcode.0x262.player_fields: the stored bone values"
  assert unit.pvp_flags == 0
    as "0x1403b48b0: the 3 bits are the unit's PvP flags, not the path 3, which would PvP-flag a Settler or an Explorer"
  assert unit.unit_id == 9 && unit.realm_id == 4
}

pub fn the_unit_holds_the_maximum_health_it_was_made_with_as_stat_0_and_base_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: roxo(),
        place: place_support.live_character_place(),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  assert unit.tail.properties == []
    as "create writes no property: the gear's come only through with_gear"
  let unit =
    player_unit.with_gear(
      record: player_unit.with_integer_stat(
        record: unit,
        stat_id: unit_fields.health_stat,
        value: 777,
      ),
      replacing: [],
      item_visuals: [],
      bases: [#(UnitProperty2Id(7), 777.0)],
      shield: None,
    )
  assert list.contains(
    unit.tail.stats,
    unit_fields.integer_stat(stat_id: 0, value: 777),
  )
    as "0x140458140: stat 0 is the unit's health; it is above 0, so the creation check (0x140457bc5) does not create the unit dead"
  assert list.contains(
    unit.tail.properties,
    UnitProperty(
      property_id: 7,
      base: float32.to_bits(777.0),
      value: float32.to_bits(777.0),
    ),
  )
    as "0x1404584b0: property 7 (Base Health) is what Unit:GetMaxHealth reads, base and value alike"
}

pub fn the_unit_carries_its_characters_level_as_stat_10_test() -> Nil {
  use <- owned_test.run(10_000)
  let unit =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: Character(..roxo(), level: 3),
        place: place_support.live_character_place(),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  assert list.contains(
    unit.tail.stats,
    unit_fields.integer_stat(stat_id: 10, value: 3),
  )
    as "0x140458140: stat 10, in the integer form, is the unit's level; a unit created without it is level 1 (0x1404543c1), so a level 3 character needs it"
  assert unit.tail.stats == [unit_fields.integer_stat(stat_id: 10, value: 3)]
    as "create writes the level and no other stat: the health is the connection's (with_integer_stat)"
}

pub fn the_players_own_record_can_show_less_health_than_the_maximum_test() -> Nil {
  use <- owned_test.run(10_000)
  let unit =
    player_unit.with_gear(
      record: player_unit.with_integer_stat(
        record: player_unit.create(
          unit: unit_support.bare_unit(
            character: roxo(),
            place: place_support.live_character_place(),
            unit_id: 1,
            body: [],
          ),
          realm_id: 1,
        ),
        stat_id: unit_fields.health_stat,
        value: unit_support.bare_health,
      ),
      replacing: [],
      item_visuals: [],
      bases: [#(UnitProperty2Id(7), 136.0)],
      shield: None,
    )
  let hurt =
    player_unit.with_integer_stat(
      record: unit,
      stat_id: unit_fields.health_stat,
      value: 100,
    )
  assert unit_fields.stat(tail: hurt.tail, stat_id: unit_fields.health_stat)
    == Ok(100)
    as "opcode.0x262: stat 0 is the health the client shows"
  assert hurt.tail.properties == unit.tail.properties
    as "property 7, Base Health, stays the maximum Unit:GetMaxHealth reads (vector.opcode.0x262.health)"
  assert unit_fields.stat(tail: hurt.tail, stat_id: unit_fields.level_stat)
    == unit_fields.stat(tail: unit.tail, stat_id: unit_fields.level_stat)
    as "the other stats stand"
  assert player_unit.with_integer_stat(
      record: unit,
      stat_id: unit_fields.health_stat,
      value: unit_support.bare_health,
    )
    == unit
    as "at the health it already shows the record is the same"
}
