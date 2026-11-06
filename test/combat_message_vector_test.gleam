//// The combat messages against bytes packed by hand from the layouts in the
//// fact file: `opcode.0x9a`, `opcode.0x111.ability_bag`, `opcode.0x1a0`,
//// `opcode.0x19d`, `opcode.0x262.creature` with `0x140095fb0`, `0x140096970`
//// for the ghost, `opcode.0x262.simple` for a static object, `opcode.0x7fc`, `opcode.0x7fd`, `opcode.0x7ff`,
//// `opcode.0x7f4` with `0x140094890`, `0x1400946c0` and `0x1400945e0`,
//// `opcode.0x7fe`, `opcode.0x801`, `opcode.0x937`, `opcode.0x92f`,
//// `opcode.0x938`, `opcode.0x88c`, `opcode.0x908`, `opcode.0x90a`,
//// `opcode.0x89a`, `opcode.0x1b3`, `opcode.0x15a`, `opcode.0x247.death` and
//// `movement_command.kind_4` with `movement_command.kind_0`. Each vector was
//// packed by a script that follows the bit stream's rule, the least
//// significant bit of the first byte first, field by field with the widths the
//// facts give, and shares no code with the codec; its tail of a unit's create
//// was checked first against the client's own body of
//// `vector.opcode.0x262.roxo_alive`, which it reproduces byte for byte. The
//// values are the ones named beside each vector. The bytes decode to the
//// values, the values encode back to them, and every shorter run of the bytes
//// ends inside a field.

import genesis_prime/message/ability_hold.{AbilityHold}
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/message/action_set.{ActionSet}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/bit_stream
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_ability.{CastAbility}
import genesis_prime/message/cast_result.{SpellCancelled, TargetRangeMax}
import genesis_prime/message/choose_resurrection.{ChooseResurrection}
import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_death.{CombatLogDeath}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_resurrect.{CombatLogResurrect}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/item_added.{ItemAdded}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_path.{MovementPath}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/relayed_movement
import genesis_prime/message/resurrection_window.{ResurrectionWindow}
import genesis_prime/message/shared_item.{SharedItem}
import genesis_prime/message/spell_cast_confirmed.{SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_damage_description.{SpellDamageDescription}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo, SpellGo}
import genesis_prime/message/spell_hit_entry.{SpellHitEntry}
import genesis_prime/message/spell_initial_position.{
  type SpellInitialPosition, SpellInitialPosition,
}
import genesis_prime/message/spell_missile_info.{SpellMissileInfo}
import genesis_prime/message/spell_position.{SpellPosition}
import genesis_prime/message/spell_started.{SpellStarted}
import genesis_prime/message/spell_target_info.{SpellTargetInfo}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition, SpellTelegraphPosition,
}
import genesis_prime/message/start_movement
import genesis_prime/message/static_unit_type
import genesis_prime/message/unit_combat_state.{UnitCombatState}
import genesis_prime/message/unit_create_creature.{UnitCreateCreature}
import genesis_prime/message/unit_create_ghost.{UnitCreateGhost}
import genesis_prime/message/unit_create_static.{UnitCreateStatic}
import genesis_prime/message/unit_create_tail.{
  type UnitCreateTail, UnitCreateTail,
}
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property
import genesis_prime/message/unit_stat.{type UnitStat}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/message/unit_target.{UnitTarget}
import genesis_prime/message/unit_threat.{UnitThreat}
import genesis_prime/world_map/static_object
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import message_support
import owned_test

/// A client cast id the way the design makes one: 2^31, a unit id times 2^11
/// and a count, so it is above the client's own counter (`0x140c1e71c`).
const client_cast_id = 0x80002803

const server_cast_id = 0x80002804

pub fn the_message_numbers_are_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_ability.message_id == 0x9A as "opcode.0x9a: message 0x9a (154)"
  assert ability_hold.message_id == 0x4DB
    as "opcode.0x4db: message 0x4db (1243)"
  assert item_added.message_id == 0x111 as "opcode.0x111.ability_bag: id 0x111"
  assert ability_tiers.message_id == 0x1A0
    as "opcode.0x1a0: message 0x1a0 (416)"
  assert action_set.message_id == 0x19D as "opcode.0x19d: message 0x19d (413)"
  assert unit_create_creature.message_id == 0x262
    as "opcode.0x262.creature: message 0x262 (610)"
  assert unit_create_ghost.message_id == 0x262
    as "0x140096970: entry 23 of message 0x262's type table"
  assert spell_cast_refused.message_id == 0x7FC
    as "opcode.0x7fc: message 0x7fc (2044)"
  assert spell_cast_confirmed.message_id == 0x7FD
    as "opcode.0x7fd: message 0x7fd (2045)"
  assert spell_started.message_id == 0x7FF
    as "opcode.0x7ff: message 0x7ff (2047)"
  assert spell_go.message_id == 0x7F4 as "opcode.0x7f4: message 0x7f4 (2036)"
  assert spell_finished.message_id == 0x7FE
    as "opcode.0x7fe: message 0x7fe (2046)"
  assert cancel_cast.message_id == 0x801 as "opcode.0x801: message 0x801 (2049)"
  assert unit_health.message_id == 0x937 as "opcode.0x937: message 0x937 (2359)"
  assert player_health.message_id == 0x92F
    as "opcode.0x92f: message 0x92f (2351)"
  assert unit_stat_changed.message_id == 0x938
    as "opcode.0x938: message 0x938 (2360)"
  assert unit_death_state.message_id == 0x88C
    as "opcode.0x88c: message 0x88c (2188)"
  assert unit_target.message_id == 0x908 as "opcode.0x908: message 0x908 (2312)"
  assert unit_threat.message_id == 0x90A as "opcode.0x90a: message 0x90a (2314)"
  assert unit_combat_state.message_id == 0x89A
    as "opcode.0x89a: message 0x89a (2202)"
  assert resurrection_window.message_id == 0x1B3
    as "opcode.0x1b3: message 0x1b3 (435)"
  assert choose_resurrection.message_id == 0x15A
    as "opcode.0x15a: message 0x15a (346)"
  assert combat_log.message_id == 0x247 as "opcode.0x247: message 0x247 (583)"
}

pub fn a_hold_is_a_bag_index_a_target_and_a_held_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x4db: bag index 2 in 16 bits, target 0x12345 in 32, held 1 in 1 bit",
    body: message_support.hex("02 00 45 23 01 00 01"),
    value: AbilityHold(bag_index: 2, target_unit_id: 0x12345, held: 1),
    encode: ability_hold.encode,
    decode: ability_hold.decode,
  )
}

pub fn a_press_is_a_client_cast_id_a_bag_index_a_target_and_a_press_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x9a: cast id 0x80002803 in 32 bits, bag index 2 in 16, target 0x12345 in 32, press 1",
    body: message_support.hex("03 28 00 80 02 00 45 23 01 00 01"),
    value: CastAbility(
      client_cast_id:,
      bag_index: 2,
      target_unit_id: 0x12345,
      press: 1,
    ),
    encode: cast_ability.encode,
    decode: cast_ability.decode,
  )
}

pub fn an_ability_is_a_shared_item_at_location_4_and_a_reason_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x111.ability_bag: the shared item's 27 values in wire order (the item id 23148 is Shred's Spell4Base id, location 4, bag index 2, three lists of one count each, none of ids) and the reason 49 in 6 bits",
    body: message_support.hex(
      "08 07 06 05 04 03 02 01 18 17 16 15 14 13 12 11 6c 5a 10 10 00 00 00 08 01 00 00 10 01 00 00 c0 b9 b1 a9 a1 99 91 89 09 02 00 00 c0 ba b2 aa a2 9a 92 8a 02 00 00 fe 09 03 00 00 88 0b 04 00 00 10 04 00 00 18 04 00 00 68 24 00 00 80 24 00 00 80 43 01 00 00 44 01 00 00 9a 57 55 30 00 00 80 30 00 00 40 44 03 00 00 00 b1 00 00 00 31",
    ),
    value: ItemAdded(
      item: SharedItem(
        item_guid: 0x0102030405060708,
        field_2: 0x1112131415161718,
        item_id: 23_148,
        location: 4,
        bag_index: 2,
        stack_count: 0x21,
        charges: 0x22,
        field_8: 0x3132333435363738,
        field_9: 0x41,
        field_10: 0x5152535455565758,
        durability: 0x3FC00000,
        field_12: 0x61,
        field_13: 0x71,
        field_14: 0x81,
        field_15: 0x82,
        field_16: 0x83,
        field_17: 5,
        field_18: 0x91,
        field_19: 0x92,
        field_20: 6,
        field_21: 0xA1,
        field_22: 0xA2,
        field_23: 0x2ABCD,
        list_a: [0xC1, 0xC2],
        list_b: [0xD1],
        field_27: 0xB1,
      ),
      reason: 49,
    ),
    encode: item_added.encode,
    decode: item_added.decode,
  )
}

pub fn the_ability_book_tiers_are_a_count_and_a_base_a_tier_and_a_set_each_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1a0: a count of 2 in 32 bits, each a Spell4Base id in 18 bits, a tier in 4 and an action set in 3",
    body: message_support.hex("02 00 00 00 6c 5a 04 f2 b4 88 01"),
    value: AbilityTiers(tiers: [
      AbilityTier(spell4_base_id: 23_148, tier: 1, action_set_index: 0),
      AbilityTier(spell4_base_id: 23_161, tier: 1, action_set_index: 3),
    ]),
    encode: ability_tiers.encode,
    decode: ability_tiers.decode,
  )
}

pub fn an_action_set_is_an_index_a_value_a_result_and_its_shortcuts_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x19d: set 0 in 3 bits, value 2 in 2, result 1 in 6, a count of 2 in 6, each a type in 4, a location in 9, a bag index in 32 and an object id in 32",
    body: message_support.hex(
      "30 10 88 00 00 00 00 00 9b 16 00 00 11 78 01 00 00 c8 d3 02 00 00",
    ),
    value: ActionSet(action_set_index: 0, field_2: 2, result: 1, shortcuts: [
      ActionShortcut(
        shortcut_type: 4,
        location: 4,
        bag_index: 0,
        object_id: 23_148,
      ),
      ActionShortcut(
        shortcut_type: 4,
        location: 4,
        bag_index: 47,
        object_id: 23_161,
      ),
    ]),
    encode: action_set.encode,
    decode: action_set.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x19d: the last set the client takes, 3, with no shortcuts",
    body: message_support.hex("2b 00 00"),
    value: ActionSet(action_set_index: 3, field_2: 1, result: 1, shortcuts: []),
    encode: action_set.encode,
    decode: action_set.decode,
  )
}

pub fn a_creature_is_created_as_type_0_with_its_row_id_and_the_players_tail_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x262.creature and 0x140095fb0: unit 0x1001, type 0 in 6 bits, Creature2 73464 in 18, checklist 0 in 8, stats 0 = 52 and 10 = 1, kind 2 then kind 14, both factions 1441, display 26565",
    body: message_support.hex(
      "01 10 00 00 00 be 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    ),
    value: UnitCreateCreature(
      unit_id: 0x1001,
      creature_id: 73_464,
      checklist_index: 0,
      tail: UnitCreateTail(
        create_flags: 0,
        stats: [
          unit_fields.integer_stat(stat_id: 0, value: 52),
          unit_fields.integer_stat(stat_id: 10, value: 1),
        ],
        server_time_estimate_start: 0,
        movement_commands: [
          start_movement.Position(UnitPositionCommand(
            x: 0xC3038000,
            y: 0xC45AD000,
            z: 0x43A6C000,
            blends: 0,
          )),
          start_movement.Rotation(MovementRotation(
            yaw: 0x3FC00000,
            pitch: 0,
            roll: 0,
            blends: 0,
          )),
        ],
        properties: [],
        item_visuals: [],
        cast_id: 0,
        faction_id: 1441,
        base_faction_id: 1441,
        tagged_by_unit_id: 0,
        tagged_by_group_id: 0,
        field_14: 0,
        world_object_id: 0,
        world_socket_id: 0,
        cluster_id: 0,
        field_20: 0,
        minimap_marker_id: 0,
        display_info_id: 26_565,
        outfit_info_id: 0,
      ),
    ),
    encode: unit_create_creature.encode,
    decode: unit_create_creature.decode,
  )
}

/// The tail of the static objects' vectors: the creature vector's place,
/// `stats`, `properties`, factions, world object link and outfit as given.
fn static_tail(
  stats stats: List(UnitStat),
  properties properties: List(unit_property.UnitProperty),
  faction_id faction_id: Int,
  base_faction_id base_faction_id: Int,
  world_object_id world_object_id: Int,
  world_socket_id world_socket_id: Int,
  outfit_info_id outfit_info_id: Int,
) -> UnitCreateTail {
  UnitCreateTail(
    create_flags: 0,
    stats:,
    server_time_estimate_start: 0,
    movement_commands: [
      start_movement.Position(UnitPositionCommand(
        x: 0xC3038000,
        y: 0xC45AD000,
        z: 0x43A6C000,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0x3FC00000,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ],
    properties:,
    item_visuals: [],
    cast_id: 0,
    faction_id:,
    base_faction_id:,
    tagged_by_unit_id: 0,
    tagged_by_group_id: 0,
    field_14: 0,
    world_object_id:,
    world_socket_id:,
    cluster_id: 0,
    field_20: 0,
    minimap_marker_id: 0,
    display_info_id: 26_565,
    outfit_info_id:,
  )
}

pub fn a_static_object_is_created_as_type_10_11_or_32_with_a_creatures_type_data_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x262.simple and 0x140095fb0: types 10, 11 and 32 read a creature's type
  // data, the Creature2 id in 18 bits and the checklist index in 8, then the tail;
  // its second tagged value holds the world object id in 64 bits and the
  // WorldSocket id in 14 (opcode.0x262.unit_fields, 0x14043e900).
  message_support.assert_codec(
    name: "type 10: unit 0x2001, Creature2 73707, checklist 0, no stats, both factions 0, no world object",
    body: message_support.hex(
      "01 20 00 00 ca fa 47 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    ),
    value: UnitCreateStatic(
      unit_id: 0x2001,
      unit_type: static_unit_type.Simple,
      creature_id: 73_707,
      checklist_index: 0,
      tail: static_tail(
        stats: [],
        properties: [],
        faction_id: 0,
        base_faction_id: 0,
        world_object_id: 0,
        world_socket_id: 0,
        outfit_info_id: 0,
      ),
    ),
    encode: unit_create_static.encode,
    decode: unit_create_static.decode,
  )
  message_support.assert_codec(
    name: "type 11: unit 0x2002, Creature2 72051, checklist 4, stat 10 = 1 alone, factions 1441 and 1442, world object 0x369123456789 on socket 0x1234, outfit 0x2a",
    body: message_support.hex(
      "02 20 00 00 cb 5c 46 04 00 41 11 00 00 00 00 00 00 00 20 04 00 e0 c0 30 00 b4 16 31 00 b0 e9 10 07 00 00 fc 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 b4 10 2d 00 00 00 00 00 00 00 00 00 00 00 00 50 e2 59 d1 48 a4 0d 00 00 8d 14 00 00 00 00 00 00 00 40 f1 19 15 00",
    ),
    value: UnitCreateStatic(
      unit_id: 0x2002,
      unit_type: static_unit_type.Platform,
      creature_id: 72_051,
      checklist_index: 4,
      tail: static_tail(
        stats: [unit_fields.integer_stat(stat_id: 10, value: 1)],
        properties: [],
        faction_id: 1441,
        base_faction_id: 1442,
        world_object_id: 0x369123456789,
        world_socket_id: 0x1234,
        outfit_info_id: 0x2A,
      ),
    ),
    encode: unit_create_static.encode,
    decode: unit_create_static.decode,
  )
  message_support.assert_codec(
    name: "type 32: unit 0x2003, Creature2 73500, stats 0 = 442 and 10 = 3, Base Health 442.0 (0x43DD0000) in both words, both factions 1441",
    body: message_support.hex(
      "03 20 00 00 20 c7 47 00 00 02 a0 1b 00 00 a0 18 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 10 70 00 00 d0 3d 04 00 d0 3d 04 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    ),
    value: UnitCreateStatic(
      unit_id: 0x2003,
      unit_type: static_unit_type.SimpleCollidable,
      creature_id: 73_500,
      checklist_index: 0,
      tail: static_tail(
        stats: [
          unit_fields.integer_stat(stat_id: 0, value: 442),
          unit_fields.integer_stat(stat_id: 10, value: 3),
        ],
        properties: [
          unit_property.UnitProperty(
            property_id: 7,
            base: 0x43DD0000,
            value: 0x43DD0000,
          ),
        ],
        faction_id: 1441,
        base_faction_id: 1441,
        world_object_id: 0,
        world_socket_id: 0,
        outfit_info_id: 0,
      ),
    ),
    encode: unit_create_static.encode,
    decode: unit_create_static.decode,
  )
}

pub fn only_types_10_11_and_32_are_static_objects_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140649e20 and world_data.entity_type: the 6-bit unit type's 10 Simple, 11
  // Platform and 32 SimpleCollidable are the types drawn from a Creature2 row and a
  // display; every other value is another kind of unit.
  let found =
    int.range(from: 0, to: 64, with: [], run: fn(found, number) {
      case static_object.unit_type_of(entity_type: number) {
        Ok(unit_type) -> [#(number, unit_type), ..found]
        Error(Nil) -> found
      }
    })
  assert list.reverse(found)
    == [
      #(10, static_object.Simple),
      #(11, static_object.Platform),
      #(32, static_object.SimpleCollidable),
    ]
    as "the three unit types of a static object, and no other of the 64"
  assert list.map([10, 11, 32, 0, 23], static_unit_type.from_value)
    == [
      static_unit_type.Simple,
      static_unit_type.Platform,
      static_unit_type.SimpleCollidable,
      static_unit_type.Other(0),
      static_unit_type.Other(23),
    ]
    as "the codec names the three; any other is Other"
}

pub fn a_ghost_is_created_as_type_23_with_a_players_data_less_three_values_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "0x140096970: unit 0x1002, type 23, character 0x0102030405060708, realm 0x99, 'Ab Cd', race 3, class 2, gender 1, a 64-bit value, 'Gd', a 4-bit value, one 64-bit and one 32-bit list item, title 0x155, then the tail the player's create has",
    body: message_support.hex(
      "02 10 00 00 17 c2 81 41 01 c1 80 40 40 26 a0 10 04 20 06 00 02 30 04 40 06 30 44 18 17 16 15 14 13 12 11 04 47 00 64 00 15 50 4e 4c 4a 48 46 44 42 02 9a 19 99 98 aa 00 00 00 00 00 00 08 01 00 38 30 0c 00 ad 45 0c 00 6c 3a c4 01 00 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 38 05 4e 01 00 00 00 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00",
    ),
    value: UnitCreateGhost(
      unit_id: 0x1002,
      character_id: 0x0102030405060708,
      realm_id: 0x99,
      name: "Ab Cd",
      race_id: 3,
      class_id: 2,
      gender: 1,
      field_9: 0x1112131415161718,
      field_10: "Gd",
      field_11: 5,
      field_12: [0x2122232425262728],
      field_13: [0x31323334],
      title_id: 0x155,
      tail: UnitCreateTail(
        create_flags: 0,
        stats: [],
        server_time_estimate_start: 0,
        movement_commands: [
          start_movement.Position(UnitPositionCommand(
            x: 0xC3038000,
            y: 0xC45AD000,
            z: 0x43A6C000,
            blends: 0,
          )),
          start_movement.Rotation(MovementRotation(
            yaw: 0x3FC00000,
            pitch: 0,
            roll: 0,
            blends: 0,
          )),
        ],
        properties: [],
        item_visuals: [],
        cast_id: 0,
        faction_id: 167,
        base_faction_id: 167,
        tagged_by_unit_id: 0,
        tagged_by_group_id: 0,
        field_14: 0,
        world_object_id: 0,
        world_socket_id: 0,
        cluster_id: 0,
        field_20: 0,
        minimap_marker_id: 0,
        display_info_id: 0,
        outfit_info_id: 0,
      ),
    ),
    encode: unit_create_ghost.encode,
    decode: unit_create_ghost.decode,
  )
}

pub fn a_refused_cast_is_the_clients_id_the_spell_and_a_result_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7fc: client cast id in 32 bits, Spell4 38765 in 18, result 105 (TargetRangeMax) in 9",
    body: message_support.hex("03 28 00 80 6d 97 a4 01"),
    value: SpellCastRefused(
      client_cast_id:,
      spell4_id: 38_765,
      result: TargetRangeMax,
    ),
    encode: spell_cast_refused.encode,
    decode: spell_cast_refused.decode,
  )
}

pub fn a_confirmed_cast_is_both_ids_a_target_a_place_and_two_lists_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7fd: client id, server id, target 0x12345, position (1, 2, -3), yaw 1.5, a count of 1 initial position, a count of 1 telegraph position",
    body: message_support.hex(
      "03 28 00 80 04 28 00 80 45 23 01 00 00 00 80 3f 00 00 00 40 00 00 40 c0 00 00 c0 3f 01 01 10 00 00 01 00 00 80 40 00 00 a0 40 00 00 c0 40 00 00 00 3f 07 00 00 00 01 08 00 01 10 00 00 02 00 00 e0 40 00 00 00 41 00 00 10 41 00 00 80 3e 09 00 00 00",
    ),
    value: SpellCastConfirmed(
      client_cast_id:,
      server_cast_id:,
      primary_target_unit_id: 0x12345,
      position: SpellPosition(x: 0x3F800000, y: 0x40000000, z: 0xC0400000),
      yaw: 0x3FC00000,
      initial_positions: [initial_position()],
      telegraph_positions: [telegraph_position()],
    ),
    encode: spell_cast_confirmed.encode,
    decode: spell_cast_confirmed.decode,
  )
}

pub fn a_cast_start_is_the_cast_its_spells_its_caster_a_place_and_two_lists_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7ff: cast id, Spell4 id, root, parent in 18 bits each, caster 0x1001, a 16-bit value, target, position, yaw, one initial and one telegraph position, two bits",
    body: message_support.hex(
      "04 28 00 80 6d 97 b8 5d f2 76 49 00 04 00 00 8d 44 d1 48 00 00 00 00 e0 0f 00 00 00 10 00 00 10 30 00 00 f0 4f 40 00 04 00 40 00 00 00 20 10 00 00 28 10 00 00 30 10 00 00 c0 cf 01 00 00 40 00 02 40 00 04 00 80 00 00 00 38 10 00 00 40 10 00 00 44 10 00 00 a0 4f 02 00 00 40",
    ),
    value: SpellStarted(
      cast_id: server_cast_id,
      spell4_id: 38_765,
      root_spell4_id: 38_766,
      parent_spell4_id: 38_767,
      caster_unit_id: 0x1001,
      field_6: 0x1234,
      primary_target_unit_id: 0x12345,
      position: SpellPosition(x: 0x3F800000, y: 0x40000000, z: 0xC0400000),
      yaw: 0x3FC00000,
      initial_positions: [initial_position()],
      telegraph_positions: [telegraph_position()],
      field_12: 1,
      field_13: 0,
    ),
    encode: spell_started.encode,
    decode: spell_started.decode,
  )
}

pub fn a_go_holds_targets_with_effects_of_both_tags_and_the_phase_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7f4: cast id, ignore cooldown 0, destination (1, 2, 3), one target info with an effect of tag 0 (one bit) and one of tag 1 (a damage description with one hit entry, 0x140094890, 0x1400946c0, 0x1400945e0), one initial position, one telegraph position, one missile info, phase 0",
    body: spell_go_bytes(),
    value: spell_go(),
    encode: spell_go.encode,
    decode: spell_go.decode,
  )
}

pub fn a_finished_cast_is_its_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7fe: the cast id in 32 bits",
    body: message_support.hex("04 28 00 80"),
    value: SpellFinished(cast_id: server_cast_id),
    encode: spell_finished.encode,
    decode: spell_finished.decode,
  )
}

pub fn a_cancelled_cast_is_its_id_a_result_and_a_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x801: cast id in 32 bits, reason 6 (SpellCancelled) in 9, the bit the sender always sets",
    body: message_support.hex("04 28 00 80 06 02"),
    value: CancelCast(
      cast_id: server_cast_id,
      reason: SpellCancelled,
      field_3: 1,
    ),
    encode: cancel_cast.encode,
    decode: cancel_cast.decode,
  )
}

pub fn a_units_health_is_its_id_its_health_and_a_dead_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x937: unit id, health 40 in 32 bits, dead bit 0",
    body: message_support.hex("01 20 00 00 28 00 00 00 00"),
    value: UnitHealth(unit_id: 0x2001, health: 40, dead: 0),
    encode: unit_health.encode,
    decode: unit_health.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x937: health 0 with the dead bit 1, which marks the unit dead",
    body: message_support.hex("01 20 00 00 00 00 00 00 01"),
    value: UnitHealth(unit_id: 0x2001, health: 0, dead: 1),
    encode: unit_health.encode,
    decode: unit_health.decode,
  )
}

pub fn the_players_health_is_its_id_its_health_and_an_18_bit_mask_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x92f: unit id, health 600, reason mask 0x40 (falling) in 18 bits",
    body: message_support.hex("01 10 00 00 58 02 00 00 40 00 00"),
    value: PlayerHealth(unit_id: 0x1001, health: 600, reason_mask: 0x40),
    encode: player_health.encode,
    decode: player_health.decode,
  )
}

pub fn a_stat_change_is_a_unit_a_stat_in_5_bits_and_a_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x938: unit id, stat 20 (shield) in 5 bits, value 123 in 32",
    body: message_support.hex("01 10 00 00 74 0f 00 00 00"),
    value: UnitStatChanged(
      unit_id: 0x1001,
      change: unit_stat_change.Shield(UnitStatShield(value: 123)),
    ),
    encode: unit_stat_changed.encode,
    decode: unit_stat_changed.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x938.interrupt_armor: stat 21 (Interrupt Armor) in the same 5 bits, value 123 in 32",
    body: message_support.hex("01 10 00 00 75 0f 00 00 00"),
    value: UnitStatChanged(
      unit_id: 0x1001,
      change: unit_stat_change.InterruptArmor(UnitStatInterruptArmor(value: 123)),
    ),
    encode: unit_stat_changed.encode,
    decode: unit_stat_changed.decode,
  )
}

pub fn a_death_state_is_a_unit_a_dead_bit_a_5_bit_value_and_a_32_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x88c: unit id, dead 1, the 5-bit value 0, the 32-bit value 0",
    body: message_support.hex("01 20 00 00 01 00 00 00 00"),
    value: UnitDeathState(unit_id: 0x2001, dead: 1, field_3: 0, field_4: 0),
    encode: unit_death_state.encode,
    decode: unit_death_state.decode,
  )
}

pub fn a_target_and_a_threat_entry_are_three_32_bit_values_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x908: unit id, target unit id, threat 15, each in 32 bits",
    body: message_support.hex("01 20 00 00 01 10 00 00 0f 00 00 00"),
    value: UnitTarget(unit_id: 0x2001, target_unit_id: 0x1001, threat: 15),
    encode: unit_target.encode,
    decode: unit_target.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x90a: unit id, other unit id, threat 0 (which erases the entry), each in 32 bits",
    body: message_support.hex("01 20 00 00 01 10 00 00 00 00 00 00"),
    value: UnitThreat(unit_id: 0x2001, other_unit_id: 0x1001, threat: 0),
    encode: unit_threat.encode,
    decode: unit_threat.decode,
  )
}

pub fn the_combat_flag_is_a_unit_and_a_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x89a: unit id in 32 bits, in-combat bit 1",
    body: message_support.hex("01 20 00 00 01"),
    value: UnitCombatState(unit_id: 0x2001, in_combat: 1),
    encode: unit_combat_state.encode,
    decode: unit_combat_state.decode,
  )
}

pub fn a_resurrection_window_is_the_ghost_three_timers_and_the_choices_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1b3 and 0x14008def0: ghost 0x1002, cost 0, penalty 0, dead 1, choices 3 (Wake Here and Holocrypt), no caster, cooldown 0, forced release 0",
    body: message_support.hex(
      "02 10 00 00 00 00 00 00 00 00 00 00 07 00 00 00 00 00 00 00 00 00",
    ),
    value: ResurrectionWindow(
      ghost_unit_id: 0x1002,
      wake_here_cost: 0,
      death_penalty_ms: 0,
      dead: 1,
      choices: 3,
      caster_asked: 0,
      wake_here_cooldown_ms: 0,
      forced_release_ms: 0,
    ),
    encode: resurrection_window.encode,
    decode: resurrection_window.decode,
  )
  message_support.assert_codec(
    name: "0x14008def0: three 32-bit values, a bit, 8 bits, a bit and two 32-bit values, each distinct",
    body: message_support.hex(
      "02 10 00 00 11 00 00 00 22 00 00 00 07 ce 00 00 00 10 01 00 00 00",
    ),
    value: ResurrectionWindow(
      ghost_unit_id: 0x1002,
      wake_here_cost: 0x11,
      death_penalty_ms: 0x22,
      dead: 1,
      choices: 3,
      caster_asked: 1,
      wake_here_cooldown_ms: 0x33,
      forced_release_ms: 0x44,
    ),
    encode: resurrection_window.encode,
    decode: resurrection_window.decode,
  )
}

pub fn a_resurrect_choice_is_the_player_a_choice_in_7_bits_and_a_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x15a: unit id in 32 bits, choice 2 (Holocrypt) in 7, a 32-bit value 0",
    body: message_support.hex("01 10 00 00 02 00 00 00 00"),
    value: ChooseResurrection(unit_id: 0x1001, choice: 2, field_3: 0),
    encode: choose_resurrection.encode,
    decode: choose_resurrection.decode,
  )
}

pub fn a_combat_log_death_and_resurrection_are_a_type_in_6_bits_and_a_unit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x247.death: type 22 in 6 bits, unit id in 32",
    body: message_support.hex("56 00 04 00 00"),
    value: CombatLog(
      entry: combat_log_entry.Death(CombatLogDeath(unit_id: 0x1001)),
    ),
    encode: combat_log.encode,
    decode: combat_log.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x247.death: type 23 in 6 bits, unit id in 32",
    body: message_support.hex("57 00 04 00 00"),
    value: CombatLog(
      entry: combat_log_entry.Resurrect(CombatLogResurrect(unit_id: 0x1001)),
    ),
    encode: combat_log.encode,
    decode: combat_log.decode,
  )
}

pub fn a_creatures_move_is_a_time_command_then_a_path_command_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x638 with movement_command.kind_0 and kind_4: a kind 0 time 0xFF00, then a kind 4 of two points, speed 0x4900 (10.0 as a half float), path type 0 (straight), mode 0, value 0, bit 0",
    body: message_support.hex(
      "01 20 00 00 00 ff 00 00 08 00 f0 0f 00 40 04 00 00 00 fc 01 00 00 00 02 00 00 02 02 00 00 04 02 00 00 05 02 00 00 06 02 48 02 00 00 00 00 00",
    ),
    value: UnitMovement(
      unit_id: 0x2001,
      server_time: 0xFF00,
      reset_movement: 0,
      kept: 0,
      commands: [
        relayed_movement.Time(MovementTime(time: 0xFF00)),
        relayed_movement.Path(MovementPath(
          points: [
            MovementFloatVector(x: 0x3F800000, y: 0x40000000, z: 0x40400000),
            MovementFloatVector(x: 0x40800000, y: 0x40A00000, z: 0x40C00000),
          ],
          speed: 0x4900,
          path_type: 0,
          mode: 0,
        )),
      ],
    ),
    encode: unit_movement.encode,
    decode: unit_movement.decode,
  )
  message_support.assert_codec(
    name: "movement_command.kind_4: a curve (path type 1) of three points, the slowest speed the client takes, 168 times 2^-24 (0x00A8, 1.0014e-5), mode 5, the value and bit the server writes as 0, with the reset and keep bits set",
    body: message_support.hex(
      "01 20 00 00 00 ff 00 00 07 32 00 00 00 e0 0f 00 00 e0 0f 00 00 e0 0f 00 00 00 10 00 00 00 10 00 00 00 10 00 00 10 10 00 00 10 10 00 00 10 10 2a 40 05 00 00 00 00",
    ),
    value: UnitMovement(
      unit_id: 0x2001,
      server_time: 0xFF00,
      reset_movement: 1,
      kept: 1,
      commands: [
        relayed_movement.Path(MovementPath(
          points: [
            MovementFloatVector(x: 0x3F800000, y: 0x3F800000, z: 0x3F800000),
            MovementFloatVector(x: 0x40000000, y: 0x40000000, z: 0x40000000),
            MovementFloatVector(x: 0x40400000, y: 0x40400000, z: 0x40400000),
          ],
          speed: 0x00A8,
          path_type: 1,
          mode: 5,
        )),
      ],
    ),
    encode: unit_movement.encode,
    decode: unit_movement.decode,
  )
}

pub fn the_cast_results_the_design_uses_are_named_as_the_client_names_them_test() -> Nil {
  use <- owned_test.run(5000)
  assert list_of_results() == [4, 6, 13, 14, 15, 16, 91, 105, 169, 285, 317]
    as "Spell.CodeEnumCastResult: 4 SpellUnknown, 13 SpellAlreadyCasting, 14 SpellGlobalCooldown, 15 SpellCooldown, 16 SpellGroupCooldown, 91 NoTarget, 105 TargetRangeMax, 169 WeaponSlot, 285 IllegalSpellCast, 317 Queued; opcode.0x801: 6 SpellCancelled"
  assert combat_result.to_value(combat_result.Hit) == 2
    as "GameLib.CodeEnumCombatResult: Hit 2"
  assert combat_result.to_value(combat_result.Avoid) == 0
    as "GameLib.CodeEnumCombatResult: Avoid 0, which shows no number"
  assert damage_type.to_value(damage_type.Physical) == 1
    as "GameLib.CodeEnumDamageType: Physical 1"
}

fn list_of_results() -> List(Int) {
  [
    cast_result.SpellUnknown,
    cast_result.SpellCancelled,
    cast_result.SpellAlreadyCasting,
    cast_result.SpellGlobalCooldown,
    cast_result.SpellCooldown,
    cast_result.SpellGroupCooldown,
    cast_result.NoTarget,
    cast_result.TargetRangeMax,
    cast_result.WeaponSlot,
    cast_result.IllegalSpellCast,
    cast_result.Queued,
  ]
  |> list.map(cast_result.to_value)
}

fn initial_position() -> SpellInitialPosition {
  SpellInitialPosition(
    unit_id: 0x1001,
    field_2: 1,
    position: SpellPosition(x: 0x40800000, y: 0x40A00000, z: 0x40C00000),
    field_4: 0x3F000000,
    field_5: 7,
  )
}

fn telegraph_position() -> SpellTelegraphPosition {
  SpellTelegraphPosition(
    field_1: 8,
    unit_id: 0x1001,
    field_3: 2,
    position: SpellPosition(x: 0x40E00000, y: 0x41000000, z: 0x41100000),
    field_5: 0x3E800000,
    field_6: 9,
  )
}

fn spell_go() -> SpellGo {
  SpellGo(
    cast_id: server_cast_id,
    ignore_cooldown: 0,
    destination: SpellPosition(x: 0x3F800000, y: 0x40000000, z: 0x40400000),
    targets: [
      SpellTargetInfo(
        unit_id: 0x2001,
        index: 0,
        flags: 1,
        instance_count: 2,
        combat_result: combat_result.Hit,
        effects: [
          SpellEffectInfo(
            spell4_effects_id: 83_788,
            instance_id: 0x41,
            delay_ms: 0x42,
            field_4: 0x43,
            result: spell_effect_result.Bit(SpellEffectBit(field_2: 1)),
          ),
          SpellEffectInfo(
            spell4_effects_id: 83_789,
            instance_id: 0x51,
            delay_ms: 0x52,
            field_4: 0x53,
            result: spell_effect_result.Damage(
              SpellEffectDamage(
                description: SpellDamageDescription(
                  raw_damage: 12,
                  scaled_raw_damage: 12,
                  absorbed: 0,
                  shield_absorbed: 0,
                  health_damage_with_overkill: 12,
                  overkill: 0,
                  glance: 0,
                  killed: 0,
                  combat_result: combat_result.Hit,
                  damage_type: damage_type.Physical,
                  hits: [
                    SpellHitEntry(
                      field_1: 1,
                      field_2: 2,
                      field_3: 3,
                      field_4: 4,
                      field_5: 5,
                      field_6: 6,
                      field_7: 7,
                      kind: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
    initial_positions: [initial_position()],
    telegraph_positions: [telegraph_position()],
    missiles: [
      SpellMissileInfo(
        field_1: SpellPosition(x: 0x3F800000, y: 0x3F800000, z: 0x3F800000),
        field_2: 5,
        field_3: 6,
        field_4: SpellPosition(x: 0x40000000, y: 0x40000000, z: 0x40000000),
        field_5: 1,
      ),
    ],
    phase: 0,
  )
}

fn spell_go_bytes() -> BitArray {
  message_support.hex(
    "04 28 00 80 00 00 00 7f 00 00 00 80 00 00 80 80 02 02 40 00 00 00 02 04 00 44 80 e9 28 41 00 00 00 42 00 00 00 43 00 00 00 6c 3a 4a 14 00 00 80 14 00 00 c0 14 00 00 40 0c 00 00 00 0c 00 00 00 00 00 00 00 00 00 00 00 0c 00 00 00 00 00 00 00 00 00 00 00 24 01 01 00 00 00 02 00 00 00 03 00 00 00 04 00 00 00 05 00 00 00 06 00 00 00 07 00 00 00 0b 08 80 00 00 08 00 00 00 04 02 00 00 05 02 00 00 06 02 00 00 f8 39 00 00 00 08 40 00 08 80 00 00 10 00 00 00 07 02 00 00 08 02 00 80 08 02 00 00 f4 49 00 00 00 08 00 00 00 fc 01 00 00 fc 01 00 00 fc 29 00 00 00 30 00 00 00 00 00 00 00 02 00 00 00 02 00 00 00 0a 00",
  )
}

// ---- what the client's reader refuses ----

/// The bit of the go's vector at which the second effect's tag starts (found
/// by packing the vector up to it: 446).
const second_effect_tag_bit = 446

pub fn an_effect_info_tag_of_2_or_3_fails_the_read_as_the_clients_does_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([2, 3], fn(tag) {
    let body =
      message_support.set_bits(
        body: spell_go_bytes(),
        at: second_effect_tag_bit,
        width: 2,
        to: tag,
      )
    assert spell_go.decode(body)
      == Error(bit_stream.UnexpectedValue(
        field: "spell_effect_result",
        value: tag,
      ))
      as "0x140094890: a tag of 2 or 3 gives 0x80004005, so the message is not read"
  })
  assert spell_go.decode(message_support.set_bits(
      body: spell_go_bytes(),
      at: second_effect_tag_bit,
      width: 2,
      to: 1,
    ))
    == Ok(spell_go())
    as "the packed tag is 1 in this position, so the same bits set to 1 read as the vector"
}
