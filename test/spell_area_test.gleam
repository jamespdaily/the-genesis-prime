//// What the client's tables say a spell strikes (`genesis_prime/game/spell_area`),
//// on planted rows that hold the values of the client's own (`area_tables`). Expected
//// values come from these places.
//// - Kick's rows: `Spell4.58591.area` (area row 640: 5 units, 0 to 8 m, 180 degrees;
////   telegraph 168: a cone 1 to 7 m over 100 degrees on the caster, flag 0x200).
//// - The threshold stages: Spell4Thresholds 238, 9, 10, 1073 to 1075 and 125, 123, 124
////   name the stage spells of Shred, Relentless Strikes, Rampage and Charged Shot,
////   and the Proxy rows 83782, 177158, 177171, 177498, 182203 and 182204 name the
////   spells their stages start (`table_rows`, read on the client's tables).
//// - The load's refusals: the module's doc comment, which states each gap where it is
////   enforced (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`, `0x14054d170`).

import area_tables
import client_tables
import genesis_prime/game/area.{
  Box, Cone, InsideRow, InsideShapes, Placement, Row,
}
import genesis_prime/game/spell_area.{
  AimNotRead, MultiplierNotFinite, SelectionNotClosest, ShapeNotBuilt,
  TelegraphNotOnCaster, ValidTargetsNotAlive,
}
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{Spell4Id}
import gleam/list
import gleam/option.{Some}
import gleam/result
import owned_test
import spell_tables
import unitest

fn kick_area(plant plant: area_tables.Kick) -> spell_area.SpellArea {
  let assert Ok(areas) = area_tables.built(kick: plant)
    as "the planted Kick builds"
  let assert Ok(found) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
    as "Kick is in the areas"
  found
}

pub fn kick_has_its_area_row_its_cone_and_its_damage_aimed_at_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = kick_area(plant: area_tables.kick())
  assert kicked.row
    == Some(Row(min_range: 0.0, max_range: 8.0, degrees: 180.0, target_count: 5))
    as "Spell4.58591.area: row 640"
  assert kicked.shapes
    == [
      Placement(
        shape: Cone(inner: 1.0, outer: 7.0, degrees: 100.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: False,
      ),
    ]
    as "Spell4.58591.area: telegraph 168, a cone 1 to 7 m over 100 degrees, flag 0x200 so it does not grow"
  let assert Ok(phase) = spell_area.phase(spell: kicked, phase: 0)
  assert phase.selects_area as "Spell4Effects.targetFlags 4 aims at the area"
  let assert [effect] = phase.damage
  assert effect.aim == spell_plan.AimsAtArea
}

pub fn a_spell_with_a_telegraph_is_struck_by_its_hit_shapes_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = kick_area(plant: area_tables.kick())
  assert spell_area.inside(spell: kicked) == InsideShapes(kicked.shapes)
    as "Jim's choice: inside the telegraph, Kick is 7 m and 100 degrees (Spell4.58591.area), capped by the row's range"
}

pub fn a_spell_with_no_telegraph_row_is_read_by_its_area_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked =
    kick_area(
      plant: area_tables.Kick(..area_tables.kick(), has_telegraph: False),
    )
  assert spell_area.inside(spell: kicked) == InsideRow
    as "Crush's 42297 has no telegraph row (Spell4.32812.area)"
}

pub fn an_area_row_that_selects_in_another_order_than_closest_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), target_selection: 3),
    )
    == Error(SelectionNotClosest(spell4_id: 58_591, target_selection: 3))
    as "Spell4AoeTargetConstraints.targetSelection: only Closest (1) is built"
}

pub fn a_spell_whose_valid_targets_hold_a_bit_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(ValidTargetsNotAlive(target_bitmask: 0x8, ..)) =
    area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), target_bitmask: 0x8),
    )
    as "Spell4ValidTargets.targetBitmask: 0x8 would strike the dead; only 0 is built, and every planted base names row 1, so the first spell with an area row to be read is the one refused"
  Nil
}

pub fn a_hit_row_placed_on_another_unit_than_the_caster_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert area_tables.built(
      kick: area_tables.Kick(
        ..area_tables.kick(),
        telegraph_target_type_flags: 2,
      ),
    )
    == Error(TelegraphNotOnCaster(
      spell4_id: 58_591,
      telegraph_id: 168,
      target_type_flags: 2,
    ))
    as "0x14054d170: flag 1 places a shape on the caster; every row of the nine abilities has it"
}

pub fn a_shape_the_rule_does_not_build_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([1, 3, 5, 6], fn(shape) {
    assert area_tables.built(
        kick: area_tables.Kick(..area_tables.kick(), shape:),
      )
      == Error(ShapeNotBuilt(spell4_id: 58_591, telegraph_id: 168, shape:))
      as "TelegraphDamage.damageShapeEnum: 1 ring, 3, 5 pie and 6 are not built"
  })
}

pub fn a_damage_multiplier_that_is_not_a_finite_float_fails_the_load_naming_the_effect_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(0x7FC00000, 0x7FC00000),
      #(0x7F800000, 0x7F800000),
      #(0xFF800000, 0xFF800000 - 0x100000000),
      #(0xFFC00000, 0xFFC00000 - 0x100000000),
    ],
    fn(planted) {
      assert area_tables.built(
          kick: area_tables.Kick(
            ..area_tables.kick(),
            multiplier_bits: planted.0,
          ),
        )
        == Error(MultiplierNotFinite(
          spell4_id: 58_591,
          effect_id: 1,
          bits: planted.1,
        ))
        as "a quiet NaN, an infinity and the negative of each (the column reads as a signed 32-bit number) cannot be a float of the VM: the load names the effect instead of crashing"
    },
  )
  assert area_tables.built(
      kick: area_tables.Kick(
        ..area_tables.kick(),
        multiplier_bits: 0x80000000 + 0x3F800000,
      ),
    )
    |> result.is_ok
    as "the sign bit of a column that reads as a negative number is a float's own: -1.0 is finite (Spell4Effects columns are read as 32 bits)"
}

pub fn a_damage_effect_aimed_by_a_flag_value_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), effect_target_flags: 3),
    )
    == Error(AimNotRead(spell4_id: 58_591, effect_id: 1, target_flags: 3))
    as "Spell4Effects.targetFlags: 1, 2, 4 and 6 are the values the rows hold"
}

pub fn the_clients_tables_build_every_areas_kick_has_5_units_8_m_180_degrees_and_a_cone_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(kicked) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
    as "Kick is in the areas"
  assert kicked.row
    == Some(Row(min_range: 0.0, max_range: 8.0, degrees: 180.0, target_count: 5))
    as "Spell4.58591.area: row 640"
  let assert [Placement(shape: Cone(inner:, outer:, degrees:), ..)] =
    kicked.shapes
    as "Kick's 168 is its one hit shape: a cone"
  assert inner == 1.0 && outer == 7.0 && degrees == 100.0
    as "Spell4.58591.area: 1 to 7 m over 100 degrees"
  let assert Ok(crush) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(32_812))
  let assert Ok(phase) = spell_area.phase(spell: crush, phase: 0)
  assert phase.selects_area && phase.damage == []
    as "Crush's first spell has only a Proxy on its area: it selects and strikes nothing itself (Spell4.32812.area)"
  let assert Ok(stagger) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(38_780))
  assert list.length(stagger.phases) == 4
    && list.all(stagger.phases, fn(phase) { phase.selects_area })
    as "Stagger's 38780 selects at each of its four phases (Spell4.38791.area)"
  let assert Ok(surge) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(42_352))
    as "Paralytic Surge is in the areas"
  assert surge.shapes
    == [
      Placement(
        shape: Box(width: 8.0, length: 8.0),
        ahead: 9.300000190734863,
        aside: 0.0,
        turn_degrees: 45.0,
        grows_by_hit_radius: False,
      ),
      Placement(
        shape: Cone(inner: 1.0, outer: 10.75, degrees: 62.5),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: False,
      ),
    ]
    as "Spell4.42352.area: telegraph 2888, a box 8 wide and 8 long centred 9.3 m ahead and turned 45 degrees, and 2889, a cone from 1 to 10.75 m over 62.5 degrees, both with flag 0x200; it has no never-drawn twin, so both drawn shapes are its hit shapes"
}

/// The stage spells of the level-1 RapidTap and ChargeRelease abilities and the spells
/// their Proxies start: Spell4Thresholds 238 (Shred 38765 casts 38766, whose Proxy
/// 83782 starts 39467), 9 and 10 (Relentless Strikes 32078 casts 32079 and 32080,
/// Proxies 177158 and 177171 start 70045 and 70054), 1073 to 1075 (Rampage 58524 casts
/// 66987, 71125 and 71126, Proxies 177498, 182203 and 182204 start 71392 to 71394) and
/// 125, 123 and 124 (Charged Shot 34718 casts 34720, 34722 and 36691, which have no
/// Proxy).
const stage_spells_and_their_proxies = [
  38_766, 39_467, 32_079, 70_045, 32_080, 70_054, 66_987, 71_392, 71_125, 71_393,
  71_126, 71_394, 34_720, 34_722, 36_691,
]

fn spells_without_an_area(
  areas areas: spell_area.Areas,
  spells spells: List(Int),
) -> List(Int) {
  list.filter(spells, fn(spell4_id) {
    result.is_error(spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id)))
  })
}

pub fn every_threshold_stage_spell_and_its_proxies_have_an_area_on_the_planted_trees_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(areas) =
    spell_tables.with_loaded_deriving(
      rows: spell_tables.rows(),
      derivations: [spell_plan.derivation()],
      body: fn(tables) { spell_area.build(tables:) },
    )
    as "the planted trees build their areas"
  assert spells_without_an_area(areas:, spells: stage_spells_and_their_proxies)
    == []
    as "Spell4Thresholds 238, 9, 10, 1073 to 1075 and 125, 123, 124 name the stage spells; Spell4Effects 83782, 177158, 177171, 177498, 182203 and 182204 start their Proxies: every one is cast and strikes by its own area"
  let assert Ok(proxy) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(39_467))
  let assert Ok(phase) = spell_area.phase(spell: proxy, phase: 0)
  assert phase.selects_area
    && list.map(phase.damage, fn(effect) { effect.aim })
    == [spell_plan.AimsAtArea]
    as "Spell4Effects 86439: the stage's Proxy 39467 holds one damage effect aimed at the area (targetFlags 4), on Spell4 39467's area row 694"
}

pub fn every_threshold_stage_spell_and_its_proxies_have_an_area_on_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  assert spells_without_an_area(areas:, spells: stage_spells_and_their_proxies)
    == []
    as "Spell4Thresholds 238, 9, 10, 1073 to 1075 and 125, 123, 124 name the stage spells; Spell4Effects 83782, 177158, 177171, 177498, 182203 and 182204 start their Proxies: every one is cast and strikes by its own area"
  let assert Ok(proxy) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(39_467))
  let assert Ok(phase) = spell_area.phase(spell: proxy, phase: 0)
  assert phase.selects_area
    && list.map(phase.damage, fn(effect) { effect.aim })
    == [spell_plan.AimsAtArea]
    as "Spell4Effects 86439: the stage's Proxy 39467 holds one damage effect aimed at the area (targetFlags 4)"
}
