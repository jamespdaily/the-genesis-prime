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
import fixture_tables
import genesis_prime/game/area.{
  Box, Cone, InsideRow, InsideShapes, Placement, Rectangle, Row,
}
import genesis_prime/game/crowd_control
import genesis_prime/game/spell_area.{
  AimNotRead, FormulaNotRead, MultiplierNotFinite, SelectionNotClosest,
  ShapeNotBuilt, TelegraphNotOnCaster, ValidTargetsNotAlive,
}
import genesis_prime/game/spell_plan
import genesis_prime/game/spend.{EqualTo}
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import owned_test
import planted_table.{Integer}
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

/// Kick's area as the client's rows build it.
fn client_kick() -> spell_area.SpellArea {
  let assert Ok(found) =
    spell_area.of_spell(
      areas: spell_tables.fixture_areas(),
      spell4_id: Spell4Id(58_591),
    )
    as "Kick is in the areas"
  found
}

pub fn kick_has_its_area_row_its_cone_and_its_damage_aimed_at_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = client_kick()
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
      ),
    ]
    as "Spell4.58591.area: telegraph 168, a cone 1 to 7 m over 100 degrees, flag 0x200 so it does not grow"
  let assert Ok(phase) = spell_area.phase(spell: kicked, phase: 0, spent: None)
  assert phase.selects_area as "Spell4Effects.targetFlags 4 aims at the area"
  let assert [effect] = phase.damage
  assert effect.aim == spell_plan.AimsAtArea
}

/// The shape, the offset ahead and the offset aside of each hit shape of a real
/// spell, in the order the build keeps them.
fn real_shapes(spell4_id spell4_id: Int) -> List(#(area.Shape, Float, Float)) {
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(found) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
    as "the spell is in the areas of the level-1 abilities"
  list.map(found.shapes, fn(placement) {
    #(placement.shape, placement.ahead, placement.aside)
  })
}

pub fn gamma_rays_centre_spell_strikes_through_its_own_row_and_each_side_spell_through_its_own_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert real_shapes(spell4_id: 29_874)
    == [#(Rectangle(width: 0.8999999761581421, length: 19.0), 1.0, 0.0)]
    as "Spell4.29874.area: the centre spell has the drawn rows 310 (flags 512), 311 and 312 (flags 544, bit 0x20, drawn as copies of the side beams); it strikes through 310 only (TelegraphDamage.telegraphDamageFlags.0x20.rows)"
  assert real_shapes(spell4_id: 34_775)
    == [
      #(
        Rectangle(width: 0.8999999761581421, length: 20.0),
        0.0,
        1.2000000476837158,
      ),
    ]
    as "Spell4.29874.area: the side spell 34775 strikes through its never-drawn row 2451 (flags 576)"
  assert real_shapes(spell4_id: 35_886)
    == [
      #(
        Rectangle(width: 0.8999999761581421, length: 20.0),
        0.0,
        -1.2000000476837158,
      ),
    ]
    as "Spell4.29874.area: the side spell 35886 strikes through its never-drawn row 2452 (flags 576)"
}

pub fn every_pulse_of_electrocutes_channel_strikes_through_its_one_damage_effect_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(electrocute) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(41_276))
    as "Electrocute is in the areas of the level-1 abilities"
  // Spell4.41276: channelInitialDelay 500, channelMaxTime 3000 and channelPulseTime
  // 500 give the pulses 0 to 5 of the recording's cast 2147485756 (0x7f4 phases 0 to 5).
  list.each([0, 1, 2, 3, 4, 5], fn(pulse) {
    let assert Ok(strike) =
      spell_area.phase(spell: electrocute, phase: pulse, spent: None)
      as {
        "Spell4.41276.area: the channel has a go at its pulse "
        <> int.to_string(pulse)
        <> " (pulses 0 to 5)"
      }
    assert strike.selects_area
      && list.map(strike.damage, fn(effect) { effect.effect_id })
      == [Spell4EffectsId(92_587)]
      as {
        "Spell4Effects 92587: targetFlags 4 aims at the area and phaseFlags -1 fires it in every phase, pulse "
        <> int.to_string(pulse)
      }
  })
}

pub fn a_channel_of_the_level_1_abilities_has_a_phase_for_each_pulse_and_none_after_the_last_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  // Spell4 41276: (3000 - 500 + 500) / 500 pulses, the recording's phases 0 to 5.
  // Spell4 58832: (1250 - 410 + 410) / 410 pulses, three gos of Discharge
  // (`cast_hold_test`: a go for each of its three pulses).
  let channels = [#(41_276, 6), #(58_832, 3)]
  list.each(channels, fn(channel) {
    let #(spell4_id, pulses) = channel
    let assert Ok(found) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
      as "the channel is in the areas of the level-1 abilities"
    list.each(
      list.index_map(list.repeat(Nil, pulses), fn(_, pulse) { pulse }),
      fn(pulse) {
        assert result.is_ok(spell_area.phase(
          spell: found,
          phase: pulse,
          spent: None,
        ))
          as {
            "Spell4."
            <> int.to_string(spell4_id)
            <> " has a go at pulse "
            <> int.to_string(pulse)
          }
      },
    )
    assert spell_area.phase(spell: found, phase: pulses, spent: None)
      == Error(Nil)
      as {
        "Spell4."
        <> int.to_string(spell4_id)
        <> " has no go after its pulse "
        <> int.to_string(pulses - 1)
      }
  })
  assert list.length(
      list.filter(dict.values(areas), fn(found) {
        option.is_some(found.spell.channel)
      }),
    )
    == list.length(channels)
    as "Electrocute and Discharge are the only Channeled spells among the level-1 abilities' trees"
}

/// The offsets aside of the planted Kick's hit shapes, whose telegraph rows have
/// `telegraph_flags`: the planted row at index i has the x offset i
/// (`area_tables.Kick`).
fn planted_asides(telegraph_flags telegraph_flags: List(Int)) -> List(Float) {
  let assert Ok(areas) =
    area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), telegraph_flags:),
    )
    as "the planted Kick builds"
  let assert Ok(found) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
    as "Kick is in the areas"
  list.map(found.shapes, fn(placement) { placement.aside })
}

pub fn a_drawn_row_with_bit_0x20_is_left_out_while_the_spell_has_another_drawn_row_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planted_asides(telegraph_flags: [0x220, 0x200, 0x220]) == [1.0]
    as "TelegraphDamage.telegraphDamageFlags.0x20.rows: a drawn row with 0x20 is the picture of another spell's beam; the spell strikes through the drawn row without it"
}

pub fn a_spell_whose_drawn_rows_all_have_bit_0x20_keeps_them_all_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planted_asides(telegraph_flags: [0x220, 0x20, 0x220])
    == [0.0, 1.0, 2.0]
    as "TelegraphDamage.telegraphDamageFlags.0x20.rows: a spell with no child telegraph has every drawn row marked 0x20 (368 area spells); leaving them all out would leave it with no shape, so it keeps them all"
}

pub fn a_spell_with_a_never_drawn_row_strikes_through_it_whatever_its_drawn_rows_hold_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planted_asides(telegraph_flags: [0x200, 0x240, 0x220]) == [1.0]
    as "Spell4.38791.area: the never-drawn row (flag 0x40) is the hit shape, as before"
  assert planted_asides(telegraph_flags: [0x200, 0x260]) == [1.0]
    as "a never-drawn row that also has bit 0x20 is still the hit shape"
}

pub fn a_spell_with_a_telegraph_is_struck_by_its_hit_shapes_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = client_kick()
  assert spell_area.inside(spell: kicked) == InsideShapes(kicked.shapes)
    as "Jim's choice: inside the telegraph, Kick is 7 m and 100 degrees (Spell4.58591.area), capped by the row's range"
}

pub fn a_spell_with_no_telegraph_row_is_read_by_its_area_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked =
    kick_area(
      plant: area_tables.Kick(..area_tables.kick(), telegraph_flags: []),
    )
  assert spell_area.inside(spell: kicked) == InsideRow
    as "Crush's 42297 has no telegraph row (Spell4.32812.area)"
}

pub fn an_area_row_that_selects_in_another_order_than_closest_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(SelectionNotClosest(spell4_id:, target_selection: 3)) =
    area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), target_selection: 3),
    )
    as "Spell4AoeTargetConstraints.targetSelection: only Closest (1) is built"
  assert list.contains([58_591, 70_033, 70_045, 70_054], spell4_id)
    as "the refusal names a spell of row 640: Kick 58591 and Relentless Strikes' stage spells 70033, 70045 and 70054 share it (Spell4.58591.area)"
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
          effect_id: 140_383,
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
    == Error(AimNotRead(spell4_id: 58_591, effect_id: 140_383, target_flags: 3))
    as "Spell4Effects.targetFlags: 1, 2, 4 and 6 are the values the rows hold"
}

pub fn a_damage_row_the_area_load_refuses_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each planted Kick holds one damage row the area load refuses, and the measure asks the
  // same function (`spell_area.damage_row_of`) whether it reads the row.
  list.each(
    [
      #(
        area_tables.Kick(..area_tables.kick(), multiplier_bits: 0x7F800000),
        MultiplierNotFinite(
          spell4_id: 58_591,
          effect_id: 140_383,
          bits: 0x7F800000,
        ),
        "dataBits00 0x7F800000 is an infinity, not a multiplier",
      ),
      #(
        area_tables.Kick(..area_tables.kick(), effect_target_flags: 3),
        AimNotRead(spell4_id: 58_591, effect_id: 140_383, target_flags: 3),
        "Spell4Effects.targetFlags: 1, 2, 4 and 6 are the values the rows hold",
      ),
      #(
        area_tables.Kick(..area_tables.kick(), parameters: [#(7, 0.5)]),
        FormulaNotRead(spell4_id: 58_591, effect_id: 140_383, parameter_kind: 7),
        "0x140565600: a player's value reads the parameter types 0, 10, 12 and 13, so a non-zero type 7 is refused",
      ),
    ],
    fn(planted) {
      let #(kick, error, why) = planted
      assert area_tables.built(kick:) == Error(error) as why
      assert !area_tables.read_by_the_measure(kick:)
        as "a row the area load refuses is not read"
    },
  )
  let readable =
    area_tables.Kick(..area_tables.kick(), effect_target_flags: 2, parameters: [
      #(10, 0.5),
    ])
  assert result.is_ok(area_tables.built(kick: readable))
    as "a finite multiplier, flags 2 and a level parameter (type 10) are read by the area load"
  assert area_tables.read_by_the_measure(kick: readable) as "and by the measure"
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
  let assert Ok(phase) = spell_area.phase(spell: crush, phase: 0, spent: None)
  assert phase.selects_area && phase.damage == []
    as "Crush's first spell has only a Proxy on its area: it selects and strikes nothing itself (Spell4.32812.area)"
  let assert Ok(stagger) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(38_780))
  assert spell_area.phase_count(spell: stagger) == 4
    && list.all([0, 1, 2, 3], fn(phase) {
      let assert Ok(strike) =
        spell_area.phase(spell: stagger, phase:, spent: None)
        as "each of its four phases is one it holds"
      strike.selects_area
    })
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
      ),
      Placement(
        shape: Cone(inner: 1.0, outer: 10.75, degrees: 62.5),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ]
    as "Spell4.42352.area: telegraph 2888, a box 8 wide and 8 long centred 9.3 m ahead and turned 45 degrees, and 2889, a cone from 1 to 10.75 m over 62.5 degrees, both with flag 0x200; it has no never-drawn twin, so both drawn shapes are its hit shapes"
}

/// The stage spells of the level-1 RapidTap and ChargeRelease abilities and the spells
/// their Proxies start, which hold a damage effect aimed at the area on the client's
/// tables: Spell4Thresholds 238 (Shred 38765 casts 38766, whose Proxy 83782 starts
/// 39467), 9 and 10 (Relentless Strikes 32078 casts 32079 and 32080, Proxies 177158 and
/// 177171 start 70045 and 70054), 1073 to 1075 (Rampage 58524 casts 66987, 71125 and
/// 71126, Proxies 177498, 182203 and 182204 start 71392 to 71394) and 125, 123 and 124
/// (Charged Shot 34718 casts 34720, 34722 and 36691, which hold their own damage).
/// `table_rows -- Spell4Effects spellId=<id>` gives each one's effect (effectType 8,
/// targetFlags 4).
const stage_spells_that_strike = [
  34_720, 34_722, 36_691, 70_045, 70_054, 71_392, 71_393, 71_394, 39_467,
]

/// The stage spells of the same abilities that hold no damage effect and whose Proxy
/// is not aimed at the area (Spell4Effects 83782, 177158, 177171, 177498, 182203 and
/// 182204: effectType 26, targetFlags 1, on the caster): the spell is cast and has no
/// area row.
const stage_spells_that_only_start_others = [
  32_079, 32_080, 38_766, 66_987, 71_125, 71_126,
]

/// Whether each spell's area holds an area row, or `Error(Nil)` for a spell with no
/// area at all.
fn area_rows_held(
  areas areas: spell_area.Areas,
  spells spells: List(Int),
) -> List(#(Int, Result(Bool, Nil))) {
  list.map(spells, fn(spell4_id) {
    #(
      spell4_id,
      spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
        |> result.map(fn(area) { option.is_some(area.row) }),
    )
  })
}

/// What `area_rows_held` gives for these spells when each has an area, with an area
/// row or without one.
fn all_held(
  spells spells: List(Int),
  row row: Bool,
) -> List(#(Int, Result(Bool, Nil))) {
  list.map(spells, fn(spell4_id) { #(spell4_id, Ok(row)) })
}

pub fn every_threshold_stage_spell_and_its_proxies_have_an_area_on_the_fixtures_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let areas = spell_tables.fixture_areas()
  let with_row = [39_467, 70_045, 70_054]
  assert area_rows_held(areas:, spells: with_row)
    == all_held(spells: with_row, row: True)
    as "Spell4Effects 86439: the stage's Proxy 39467 strikes, aimed at the area (targetFlags 4), so it holds Spell4 39467's area row 694; Relentless Strikes' stage spells 70045 and 70054 proxy 53865 at the area (177099, 177122, targetFlags 4), so they hold their row 640"
  assert area_rows_held(areas:, spells: stage_spells_that_strike)
    == all_held(spells: stage_spells_that_strike, row: True)
    as "each stage spell or Proxy that holds a damage effect aimed at the area (Spell4Effects 80977 to 86439, targetFlags 4) is in the areas with its area row"
  assert area_rows_held(areas:, spells: stage_spells_that_only_start_others)
    == all_held(spells: stage_spells_that_only_start_others, row: False)
    as "Spell4Thresholds 238, 9, 10, 1073 to 1075 and 125, 123, 124 name the stage spells and Spell4Effects 83782, 177158, 177171, 177498, 182203 and 182204 start their Proxies: each is cast, so each is in the areas, with no area row of its own"
  let assert Ok(proxy) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(39_467))
  let assert Ok(phase) = spell_area.phase(spell: proxy, phase: 0, spent: None)
  assert phase.selects_area
    && list.map(phase.damage, fn(effect) { effect.aim })
    == [spell_plan.AimsAtArea]
    as "Spell4Effects 86439: the stage's Proxy 39467 holds one damage effect aimed at the area (targetFlags 4)"
}

pub fn every_threshold_stage_spell_and_its_proxies_have_an_area_on_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  assert area_rows_held(areas:, spells: stage_spells_that_strike)
    == all_held(spells: stage_spells_that_strike, row: True)
    as "each stage spell or Proxy that holds a damage effect aimed at the area (Spell4Effects 80977 to 86439, targetFlags 4) is in the areas with its area row"
  assert area_rows_held(areas:, spells: stage_spells_that_only_start_others)
    == all_held(spells: stage_spells_that_only_start_others, row: False)
    as "a stage spell with no damage and no Proxy aimed at the area is cast, so it is in the areas, with no area row"
  let assert Ok(proxy) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(39_467))
  let assert Ok(phase) = spell_area.phase(spell: proxy, phase: 0, spent: None)
  assert phase.selects_area
    && list.map(phase.damage, fn(effect) { effect.aim })
    == [spell_plan.AimsAtArea]
    as "Spell4Effects 86439: the stage's Proxy 39467 holds one damage effect aimed at the area (targetFlags 4)"
}

// ---- a spell with an innate cost EMM id chooses its damage by n ----

/// Mind Burst's area built from the client's rows with one row changed.
fn mind_burst_with(
  table table: String,
  id id: Int,
  with changes: List(#(String, planted_table.Cell)),
) -> spell_area.SpellArea {
  let assert Ok(areas) =
    fixture_tables.changed(table:, id:, with: changes, body: fn(tables) {
      spell_area.build(tables:)
    })
    as "the changed rows build their areas"
  spell_tables.mind_burst_in(areas:)
}

fn damage_of(
  area area: spell_area.SpellArea,
  spent spent: option.Option(Int),
) -> List(spell_area.DamageEffect) {
  let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent:)
    as "Mind Burst has one phase"
  phase.damage
}

pub fn mind_burst_tags_its_five_damage_effects_with_their_emm_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  let area = spell_tables.mind_burst_in(areas: spell_tables.fixture_areas())
  assert list.map(damage_of(area:, spent: None), fn(effect) {
      #(effect.effect_id, effect.tag)
    })
    == [
      #(Spell4EffectsId(61_993), EqualTo(value: 0)),
      #(Spell4EffectsId(61_994), EqualTo(value: 1)),
      #(Spell4EffectsId(61_995), EqualTo(value: 2)),
      #(Spell4EffectsId(61_996), EqualTo(value: 3)),
      #(Spell4EffectsId(61_997), EqualTo(value: 4)),
    ]
    as "Spell4.32809: 61993 to 61997 hold emmComparison 0 and emmValue 0 to 4"
}

pub fn a_phase_with_n_holds_only_the_damage_effects_n_chooses_test() -> Nil {
  use <- owned_test.run(60_000)
  let area = spell_tables.mind_burst_in(areas: spell_tables.fixture_areas())
  list.each([0, 1, 2, 3, 4], fn(spent) {
    assert list.map(damage_of(area:, spent: Some(spent)), fn(effect) {
        effect.effect_id.value
      })
      == [61_993 + spent]
      as "Spell4Effects.emmComparison 0: the effect whose emmValue equals n applies and no other"
  })
}

pub fn a_phase_computes_its_area_flags_from_the_effects_n_leaves_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's Mind Burst has every damage effect aimed at the area (targetFlags 4).
  // Its effect 61993, the one n 0 chooses, is aimed at the cast's target here
  // (targetFlags 2): no client row has an effect of n 0 aimed anywhere else.
  let area =
    mind_burst_with(table: "Spell4Effects", id: 61_993, with: [
      #("targetFlags", Integer(2)),
    ])
  let flags = fn(spent) {
    let assert Ok(phase) =
      spell_area.phase(spell: area, phase: 0, spent: Some(spent))
      as "Mind Burst has one phase"
    #(phase.selects_area, phase.strikes_primary_target)
  }
  assert flags(0) == #(False, True)
    as "Spell4Effects.emmComparison: at n 0 only the effect aimed at the target is chosen, so the phase selects no area"
  assert flags(1) == #(True, False)
    as "from n 1 only the area-aimed effect is chosen, so the phase strikes no primary target"
  let assert Ok(all) = spell_area.phase(spell: area, phase: 0, spent: None)
  assert #(all.selects_area, all.strikes_primary_target) == #(True, True)
    as "a cast with no n chooses nothing, so both flags hold as for every effect"
  // Effect 61993 holds the n 1 here, so no effect holds n 0 (the client's rows hold one
  // for each n from 0 to 4).
  let only_from_1 =
    mind_burst_with(table: "Spell4Effects", id: 61_993, with: [
      #("emmValue", Integer(1)),
    ])
  let assert Ok(none_at_0) =
    spell_area.phase(spell: only_from_1, phase: 0, spent: Some(0))
  assert none_at_0.damage == []
    && !none_at_0.selects_area
    && !none_at_0.strikes_primary_target
    as "the only area-aimed effect is excluded at n 0, so the phase selects no area"
}

// ---- the kit's crowd-control rows ----

/// The kit's six CCStateSet rows as the client's tables hold them
/// (`table_rows -- Spell4Effects 100836 125183 83827 96126 140382 95949`): the Spell4,
/// the effect, the state (dataBits00), delayTime, durationTime and targetFlags. Every
/// row removes 1 Interrupt Armor (dataBits03).
fn kit_controls() -> List(
  #(Int, Int, crowd_control_state.CrowdControlState, Int, Int, spell_plan.Aim),
) {
  [
    #(30_436, 100_836, crowd_control_state.Stun, 0, 3250, spell_plan.AimsAtArea),
    #(41_438, 125_183, crowd_control_state.Stun, 0, 2500, spell_plan.AimsAtArea),
    #(38_780, 83_827, crowd_control_state.Stun, 0, 2500, spell_plan.AimsAtArea),
    #(42_352, 96_126, crowd_control_state.Stun, 0, 2700, spell_plan.AimsAtArea),
    #(
      58_591,
      140_382,
      crowd_control_state.Knockdown,
      166,
      3000,
      spell_plan.AimsAtArea,
    ),
    #(
      42_297,
      95_949,
      crowd_control_state.Knockdown,
      0,
      4000,
      spell_plan.AimsAtBoth,
    ),
  ]
}

pub fn each_kit_crowd_control_row_decodes_as_a_stun_or_a_knockdown_with_its_time_and_aim_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  list.each(kit_controls(), fn(kit) {
    let #(spell4_id, effect_id, state, delay_ms, duration_ms, aim) = kit
    let assert Ok(area) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
      as "the spell is in a level-1 ability's tree"
    let assert [control] =
      spell_plan.controls_in_phase(spell: area.spell, phase: 0, spent: None)
      as "one CCStateSet row fires in the spell's first phase"
    assert control.effect_id == Spell4EffectsId(effect_id)
    assert control.row
      == crowd_control.Row(state:, delay_ms:, duration_ms:, armor_removed: 1)
    assert control.aim == aim
  })
}

pub fn gates_stun_and_staggers_stun_select_their_area_and_strike_though_they_carry_no_damage_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  list.each([30_436, 38_780], fn(spell4_id) {
    let assert Ok(area) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
      as "the spell is in a level-1 ability's tree"
    let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
    assert phase.damage == [] && list.length(phase.controls) == 1
      as "no damage effect and one stun (Spell4Effects 100836, 83827)"
    assert phase.selects_area
      as "the stun is aimed at the area (targetFlags 4), so the phase selects the area's units"
  })
}

pub fn crushs_knockdown_aimed_at_both_selects_the_area_and_strikes_the_primary_target_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(area) = spell_area.of_spell(areas:, spell4_id: Spell4Id(42_297))
    as "Crush's second spell"
  let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
  assert phase.selects_area && phase.strikes_primary_target
    as "Spell4Effects 95949: targetFlags 6 aims at the cast's target and the area"
}
