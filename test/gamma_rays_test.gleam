//// Who Gamma Rays strikes (`genesis_prime/game/strike` over the client's own area
//// rows), on the geometry of the recorded sitting where Jim's Medic cast it at
//// creature 164 (Creature2 24054, standing at (-8126.622, -187.724)). Expected values
//// come from these places.
//// - The spells and their beams: `Spell4.29874.area`. The centre spell 29874 strikes
////   through the 0.9 m wide strip of row 310; 34775 through row 2451 (1.2 m to one
////   side) and 35886 through row 2452 (1.2 m to the other), each started on the
////   caster.
//// - The creature's hit radius: Creature2DisplayInfo 26120 (the only display of its
////   display group 28463), hitRadius 2.8 (`unit.hit_radius`).
//// - The casts' positions and facings: the recording's 0x07FF casts (`gamma_geom.py`
////   of the step's geometry check): casts 1 and 2 at (-8123.164, -189.015) facing yaw
////   2.3550, casts 3 and 4 at (-8127.179, -190.591) facing yaw -2.9477. The creature's
////   distance ahead and to the side of each cast, from that script: 3.360 ahead and
////   1.528 aside for casts 1 and 2, 2.921 ahead and 0.005 aside for casts 3 and 4.
//// - A strip is reached when the creature's centre is within half its width plus the
////   creature's hit radius of the strip's line: 0.45 + 2.8 = 3.25 m. The side strips
////   lie 1.2 m either side of the centre one, so a creature 1.528 m aside is 0.328 m
////   from one side strip and 2.728 m from the other: both within 3.25 m.

import attacker_support
import client_tables
import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/cast.{GoAsked}
import genesis_prime/game/shown.{Exile, ShownCreature}
import genesis_prime/game/spell_area
import genesis_prime/game/strike.{type Attacker, Attacker}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/creature2_display_info
import genesis_prime/table/id.{Creature2DisplayInfoId, Creature2Id, Spell4Id}
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import place_support
import properties_support
import unitest

const centre_spell = 29_874

const left_spell = 34_775

const right_spell = 35_886

fn gamma_caster(x x: Float, z z: Float, yaw yaw: Float) -> Attacker {
  Attacker(
    unit_id: 1,
    connection: ConnectionId(2),
    pose: Pose(at: Point(x:, z:), yaw:),
    place: place_support.at(world_id: 3460, world_zone_id: 5967, x:, y: 0.0, z:),
    move_seq: 1,
    stay: map_support.stay(count: 1),
    hit_radius: place_support.player_hit_radius,
    faction: Exile,
    stats: attacker_support.fresh(),
    properties: properties_support.fresh(level: 1),
  )
}

/// The hit radius of the Scrab Striker's display (Creature2DisplayInfo 26120), read
/// from the client's row.
fn striker_hit_radius() -> Float {
  let assert Ok(display) =
    creature2_display_info.get(
      tables: client_tables.shared(),
      id: Creature2DisplayInfoId(26_120),
    )
    as "Creature2DisplayInfo 26120 is the display of creature 24054"
  display.hit_radius
}

fn striker_at(x x: Float, z z: Float) -> shown.Shown {
  ShownCreature(
    creature_id: Creature2Id(73_464),
    faction_id: 0,
    checklist_index: 0,
    path: creature_path.Standing(at: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x:,
      y: -995.0,
      z:,
    )),
    life: 420,
    alive: True,
    hit_radius: striker_hit_radius(),
    attackable: Attackable(exile: True, dominion: True),
    hostile_to: Hostile(exile: False, dominion: False),
    in_combat: False,
    held: [],
  )
}

/// The units each of Gamma Rays' three spells strikes when the caster casts it, in
/// the order centre, left, right.
fn struck_by_the_three(
  caster caster: Attacker,
  picture picture: shown.Picture,
) -> List(List(Int)) {
  let areas = spell_area.areas(tables: client_tables.shared())
  list.map([centre_spell, left_spell, right_spell], fn(spell4_id) {
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(spell4_id),
        primary_target: caster.unit_id,
        spent: None,
      ),
      attacker: caster,
      picture:,
      areas:,
      now_ms: 0,
    ).units
    |> list.map(fn(aimed) { aimed.unit_id })
  })
}

pub fn gamma_rays_on_the_recordings_creature_strikes_it_with_each_of_its_three_beams_in_casts_1_and_2_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let picture = dict.from_list([#(164, striker_at(x: -8126.622, z: -187.724))])
  assert struck_by_the_three(
      caster: gamma_caster(x: -8123.164, z: -189.015, yaw: 2.355),
      picture:,
    )
    == [[164], [164], [164]]
    as "the creature is 1.528 m from the centre strip's line, 0.328 m from one side strip's and 2.728 m from the other's, all within 0.45 + 2.8 m, 2.8 being Creature2DisplayInfo 26120's hitRadius (Spell4.29874.area, unit.hit_radius)"
}

pub fn gamma_rays_on_the_recordings_creature_strikes_it_with_each_of_its_three_beams_in_casts_3_and_4_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let picture = dict.from_list([#(164, striker_at(x: -8126.622, z: -187.724))])
  assert struck_by_the_three(
      caster: gamma_caster(x: -8127.179, z: -190.591, yaw: -2.9477),
      picture:,
    )
    == [[164], [164], [164]]
    as "the creature is 0.005 m aside, 1.2 m from each side strip's line, within 0.45 + 2.8 m (2.8: Creature2DisplayInfo 26120's hitRadius)"
}

pub fn a_creature_beside_one_side_beam_takes_that_beam_and_not_the_centre_spell_through_the_drawn_copy_of_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // 5 m ahead of the caster of casts 3 and 4 and 4 m aside to the side where
  // 2451's strip lies (the strip 1.2 m aside is 2.8 m from it, the centre strip is
  // 4 m, the other side strip 5.2 m): (x, z) = caster + 5 x (-sin yaw, -cos yaw)
  // - 4 x (cos yaw, -sin yaw), worked out for yaw -2.9477.
  let picture = dict.from_list([#(165, striker_at(x: -8122.291, z: -186.455))])
  assert struck_by_the_three(
      caster: gamma_caster(x: -8127.179, z: -190.591, yaw: -2.9477),
      picture:,
    )
    == [[], [165], []]
    as "Spell4.29874.area: 2.8 m from 2451's strip is within 0.45 + 2.8 m (2.8: Creature2DisplayInfo 26120's hitRadius), 4 m from the centre's and 5.2 m from 2452's is not; the centre spell's drawn copies 311 and 312 do not strike (TelegraphDamage.telegraphDamageFlags.0x20.rows)"
}
