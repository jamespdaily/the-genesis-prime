//// What the sitting bot prints of the messages a cast sends it: a buff's start, its
//// heal in a go and in a tick with the amount, overheal and absorbed, the units taken
//// off it, its property changes, its end, and the bot's own vitals. The frames are
//// the server's own writers'; each expected line states the rule it checks.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type.{type DamageType}
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick.{SpellEffectTick}
import genesis_prime/message/spell_go.{SpellGo}
import genesis_prime/message/spell_position.{SpellPosition}
import genesis_prime/message/spell_started.{SpellStarted}
import genesis_prime/message/spell_target_info.{SpellTargetInfo}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/message/unit_properties_changed.{UnitPropertiesChanged}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat_absorption.{UnitStatAbsorption}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/sitting_bot/effects
import gleam/list
import owned_test

const cast_id = 77

const buff_spell4_id = 19_033

const caster_unit_id = 0x2001

const bot_unit_id = 0x3001

fn started_frame() -> Frame {
  cast_frame.started_frame(start: SpellStarted(
    cast_id:,
    spell4_id: buff_spell4_id,
    root_spell4_id: buff_spell4_id,
    parent_spell4_id: 0,
    caster_unit_id:,
    caster_item_level: 0,
    primary_target_unit_id: bot_unit_id,
    position: SpellPosition(x: 0, y: 0, z: 0),
    yaw: 0,
    initial_positions: [],
    telegraph_positions: [],
    own_cast: 1,
    creature_activate: 0,
  ))
}

fn description(
  damage_type damage_type: DamageType,
  amount amount: Int,
  overkill overkill: Int,
  absorbed absorbed: Int,
) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: amount,
    scaled_raw_damage: amount,
    absorbed:,
    shield_absorbed: 0,
    health_damage_with_overkill: amount,
    overkill:,
    glance: 0,
    killed: 0,
    combat_result: combat_result.Hit,
    damage_type:,
    hits: [],
  )
}

fn go_frame() -> Frame {
  cast_frame.went_frame(go: SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: SpellPosition(x: 0, y: 0, z: 0),
    targets: [
      SpellTargetInfo(
        unit_id: bot_unit_id,
        index: 0,
        flags: 0,
        instance_count: 1,
        combat_result: combat_result.Hit,
        effects: [
          SpellEffectInfo(
            spell4_effects_id: 100,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 0,
            result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
          ),
          SpellEffectInfo(
            spell4_effects_id: 101,
            instance_id: 2,
            delay_ms: 0,
            lifetime_ms: 0,
            result: spell_effect_result.Damage(
              SpellEffectDamage(description: description(
                damage_type: damage_type.Heal,
                amount: 40,
                overkill: 15,
                absorbed: 0,
              )),
            ),
          ),
        ],
      ),
    ],
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase: 0,
  ))
}

fn tick_frame() -> Frame {
  cast_frame.ticked_frame(
    tick: SpellEffectTick(
      cast_id:,
      spell4_effects_id: 102,
      unit_id: bot_unit_id,
      descriptions: [
        description(
          damage_type: damage_type.HealShields,
          amount: 25,
          overkill: 0,
          absorbed: 5,
        ),
      ],
    ),
  )
}

fn removed_frame() -> Frame {
  cast_frame.targets_removed_frame(
    removed: SpellTargetsRemoved(cast_id:, unit_ids: [bot_unit_id]),
  )
}

fn properties_frame() -> Frame {
  let assert Ok(body) =
    unit_properties_changed.encode(
      UnitPropertiesChanged(unit_id: bot_unit_id, properties: [
        UnitProperty(property_id: 7, base: 0x44160000, value: 0x442F0000),
      ]),
    )
  Frame(message_id: unit_properties_changed.message_id, body:)
}

fn own_health_frame() -> Frame {
  let assert Ok(body) =
    player_health.encode(PlayerHealth(
      unit_id: bot_unit_id,
      health: 640,
      reason_mask: 0,
    ))
  Frame(message_id: player_health.message_id, body:)
}

fn absorption_frame() -> Frame {
  let assert Ok(body) =
    unit_stat_changed.encode(UnitStatChanged(
      unit_id: bot_unit_id,
      change: unit_stat_change.Absorption(UnitStatAbsorption(value: 90)),
    ))
  Frame(message_id: unit_stat_changed.message_id, body:)
}

fn lines_of(frames: List(Frame)) -> List(String) {
  let #(_book, lines) =
    list.fold(frames, #(effects.new_book(), []), fn(so_far, frame) {
      let #(book, lines) = so_far
      let #(book, read) = effects.read(book:, frame:)
      #(book, list.append(lines, list.map(read, effects.describe)))
    })
  lines
}

pub fn a_buff_from_its_start_to_its_end_prints_each_heal_with_its_overheal_and_absorb_and_names_the_spell_and_caster_test() -> Nil {
  use <- owned_test.run(5000)
  assert lines_of([
      started_frame(),
      go_frame(),
      tick_frame(),
      removed_frame(),
      properties_frame(),
      cast_frame.finished_frame(cast_id:),
    ])
    == [
      "cast 0x7ff: cast 77 of spell 19033 (root 19033, parent 0) by unit 8193",
      "cast 0x7f4: cast 77 of spell 19033 goes, phase 0; unit 12289: effect 100 bit, effect 101 heal amount 40 overheal 15 absorbed 0 shield absorbed 0 result 2",
      "cast 0x7f8: cast 77 of spell 19033 ticks effect 102 on unit 12289: effect 102 heal shields amount 25 overheal 0 absorbed 5 shield absorbed 0 result 2",
      "cast 0x811: cast 77 of spell 19033 loses units 12289",
      "properties 0x93a: unit 12289 property 7 base 600.0 value 700.0",
      "cast 0x7fe: cast 77 of spell 19033 by unit 8193 ends",
    ]
    as "each frame of the buff is one line that names the spell and caster of the cast's 0x7ff, and a heal gives its amount, overheal and absorbed"
}

pub fn the_bots_own_health_and_absorption_print_one_line_each_test() -> Nil {
  use <- owned_test.run(5000)
  assert lines_of([own_health_frame(), absorption_frame()])
    == [
      "own health 0x92f: unit 12289 health 640",
      "stat 0x938: unit 12289 absorption 90",
    ]
    as "0x92f is the bot's health and 0x938 of stat 22 its absorption"
}

pub fn a_go_of_a_cast_the_bot_never_saw_start_names_spell_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert lines_of([go_frame()])
    == [
      "cast 0x7f4: cast 77 of spell 0 goes, phase 0; unit 12289: effect 100 bit, effect 101 heal amount 40 overheal 15 absorbed 0 shield absorbed 0 result 2",
    ]
    as "no 0x7ff, so no spell: the line says spell 0 and still gives the heal"
}
