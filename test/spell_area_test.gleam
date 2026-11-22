//// What the client's tables say a spell strikes (`genesis_prime/game/spell_area`),
//// on the client's own rows (`spell_tables.fixture_areas`). Expected values come from
//// these places.
//// - Kick's rows: `Spell4.58591.area` (area row 640: 5 units, 0 to 8 m, 180 degrees;
////   telegraph 168: a cone 1 to 7 m over 100 degrees on the caster, flag 0x200).
//// - The spells that hold each case of the hit shapes and the damage rows, named in the
////   test that reads them (`table_rows`, read on the client's tables).
//// - The threshold stages: Spell4Thresholds 238, 9, 10, 1073 to 1075 and 125, 123, 124
////   name the stage spells of Shred, Relentless Strikes, Rampage and Charged Shot,
////   and the Proxy rows 83782, 177158, 177171, 177498, 182203 and 182204 name the
////   spells their stages start (`table_rows`, read on the client's tables).
//// - The load's refusals: the module's doc comment, which states each gap where it is
////   enforced (`Spell4AoeTargetConstraints.targetSelection`,
////   `Spell4ValidTargets.targetBitmask`, `0x14054d170`). Each refusal edits one value
////   of Kick, because no spell of a level-1 tree holds the case: the whole tables hold
////   such rows, but only for spells outside the trees, which the load never reads.

import area_tables
import client_shape_rows
import client_tables
import fixture_tables
import genesis_prime/game/area.{
  type Inside, type Placement, type Row, Box, Circle, Cone, InsideRow,
  InsideShapes, Placement, Rectangle, Row,
}
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/spell_area.{
  AimNotRead, FormulaNotRead, MultiplierNotFinite, Once, Periodic, PlacedApart,
  SelectionNeedsHealth, SelectionNotBuilt, ShapeNotBuilt, TargetingNotBuilt,
  TelegraphNotOnCaster, TelegraphOnStruckUnits, TickingNoTick,
  TickingUntilRemoved, ValidTargetsNotAlive,
}
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan
import genesis_prime/game/spend.{EqualTo}
import genesis_prime/game/target_mechanic
import genesis_prime/game/telegraph_window
import genesis_prime/game/ticking
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{
  Spell4BaseId, Spell4EffectsId, Spell4Id, TelegraphDamageId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/telegraph_damage
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

/// The area of a spell of the fixture's rows.
fn fixture_area(spell4_id spell4_id: Int) -> spell_area.SpellArea {
  let assert Ok(found) =
    spell_area.of_spell(
      areas: spell_tables.fixture_areas(),
      spell4_id: Spell4Id(spell4_id),
    )
    as "the spell is in the fixture's areas"
  found
}

/// Kick's area as the client's rows build it.
fn client_kick() -> spell_area.SpellArea {
  fixture_area(spell4_id: 58_591)
}

pub fn kick_read_from_the_clients_rows_builds_the_fixtures_area_test() -> Nil {
  use <- owned_test.run(60_000)
  assert area_tables.kick_rows(kick: area_tables.kick())
    == spell_tables.fixture_rows()
    as "Kick read from Spell4 58591's rows (area row 640, valid targets 1, telegraph 168, effect 140383) and written back leaves every row as the client holds it"
  let assert Ok(areas) = area_tables.built(kick: area_tables.kick())
    as "the client's Kick rows build"
  let assert Ok(built) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
    as "Kick is in the areas"
  assert built == client_kick()
    as "Spell4.58591.area: the area built from the rows Kick reads is the area the fixture's own load builds"
}

pub fn kick_has_its_area_row_its_cone_and_its_damage_aimed_at_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = client_kick()
  assert kicked.row
    == Some(Row(
      min_range: 0.0,
      max_range: 8.0,
      degrees: 180.0,
      target_count: 5,
      order: area.Nearest,
    ))
    as "Spell4.58591.area: row 640"
  assert shapes_at_go_0(spell: kicked)
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

/// The hit shapes the spell strikes with at its first go: empty for a spell read by its area row.
fn shapes_at_go_0(spell spell: spell_area.SpellArea) -> List(Placement) {
  case spell_area.inside(spell:, phase: 0) {
    Some(InsideShapes(placements:)) -> placements
    Some(InsideRow) | None -> []
  }
}

/// The shape, the offset ahead and the offset aside of each hit shape of a real
/// spell, in the order the build keeps them.
fn real_shapes(spell4_id spell4_id: Int) -> List(#(area.Shape, Float, Float)) {
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(found) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
    as "the spell is in the areas of the level-1 abilities"
  list.map(shapes_at_go_0(spell: found), fn(placement) {
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
  let level_one_spells =
    dict.values(spell_plan.plans(tables: client_tables.shared()))
    |> list.flat_map(spell_plan.tree(spell: _, started: fn(_) { True }))
    |> list.map(fn(spell) { spell.spell4_id.value })
  assert list.length(
      list.filter(dict.values(areas), fn(found) {
        option.is_some(found.spell.channel)
        && list.contains(level_one_spells, found.spell4_id.value)
      }),
    )
    == list.length(channels)
    as "Electrocute and Discharge are the only Channeled spells among the level-1 abilities' trees"
}

pub fn a_spell_with_a_telegraph_is_struck_by_its_hit_shapes_test() -> Nil {
  use <- owned_test.run(60_000)
  let kicked = client_kick()
  assert spell_area.inside(spell: kicked, phase: 0)
    == Some(InsideShapes(shapes_at_go_0(spell: kicked)))
    as "Jim's choice: inside the telegraph, Kick is 7 m and 100 degrees (Spell4.58591.area), capped by the row's range"
}

/// A rectangle of a hit row whose shape is 7, placed 1 m ahead (`TelegraphDamage` 2996 to 2998).
fn fissure_rectangle(width width: Float) -> Option(Inside) {
  Some(
    InsideShapes([
      Placement(
        shape: Rectangle(width:, length: 14.0),
        ahead: 1.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ]),
  )
}

/// A cone of a hit row whose shape is 8 with no box, as Pulse Blast's rows hold them
/// (`TelegraphDamage` 213, 217, 218, 3299 to 3301).
fn pulse_cone(
  inner inner: Float,
  outer outer: Float,
  degrees degrees: Float,
  ahead ahead: Float,
) -> Placement {
  Placement(
    shape: Cone(inner:, outer:, degrees:),
    ahead:,
    aside: 0.0,
    turn_degrees: 0.0,
  )
}

pub fn a_players_phased_cast_holds_at_each_go_the_hit_rows_that_go_names_test() -> Nil {
  use <- owned_test.run(60_000)
  // `table_rows -- TelegraphDamage 2996 2997 2998 213 217 218 3299 3300 3301`: phaseFlags are
  // bit masks (1 is go 0, 2 is go 1, 4 is go 2, 8 is go 3). The comparison of a row's phase
  // with a go is a marked guess (`opcode.0x7f4.phase` is the client's only use of it).
  list.each(
    [
      #(
        41_844,
        [
          fissure_rectangle(width: 10.0),
          fissure_rectangle(width: 6.0),
          fissure_rectangle(width: 2.0),
          None,
        ],
        "Fissure's child: rows 2998, 2997 and 2996 (phaseFlags 1, 2, 4) are 10, 6 and 2 wide at gos 0, 1 and 2, and a go past the last has no rows",
      ),
      #(
        37_302,
        [
          None,
          Some(
            InsideShapes([
              pulse_cone(inner: 5.0, outer: 29.0, degrees: 10.0, ahead: -4.0),
            ]),
          ),
          Some(
            InsideShapes([
              pulse_cone(inner: 4.0, outer: 18.0, degrees: 30.0, ahead: -3.0),
            ]),
          ),
          Some(
            InsideShapes([
              pulse_cone(inner: 3.0, outer: 13.0, degrees: 60.0, ahead: -2.0),
            ]),
          ),
        ],
        "Pulse Blast's child: rows 213, 217 and 218 (phaseFlags 2, 4, 8) are the cones of 10, 30 and 60 degrees at gos 1, 2 and 3, and no row names go 0",
      ),
      #(
        42_276,
        [
          None,
          Some(
            InsideShapes([
              pulse_cone(inner: 5.0, outer: 29.0, degrees: 10.0, ahead: -4.0),
              pulse_cone(inner: 4.0, outer: 18.0, degrees: 30.0, ahead: -3.0),
              pulse_cone(inner: 3.0, outer: 13.0, degrees: 60.0, ahead: -2.0),
            ]),
          ),
        ],
        "Pulse Blast's first spell: rows 3299, 3300 and 3301 all hold phaseFlags 2, so they are struck together at go 1 and none names go 0",
      ),
    ],
    fn(row) {
      let #(spell4_id, expected, reason) = row
      let found = fixture_area(spell4_id:)
      assert list.index_map(expected, fn(_, phase) {
          spell_area.inside(spell: found, phase:)
        })
        == expected
        as reason
    },
  )
  assert spell_area.inside(spell: fixture_area(spell4_id: 41_844), phase: -1)
    == None
    as "a go below 0 is none: dropping from the list would hand back go 0's rows"
}

pub fn a_cast_whose_phase_the_client_does_not_compare_holds_every_hit_row_at_each_go_test() -> Nil {
  use <- owned_test.run(60_000)
  // Discharge's spell 58832 is a channel of three pulses whose spellChannelFlags is 0
  // (`table_rows -- Spell4 58832`), so the client does not compare a row's phase with a pulse.
  // Its one hit row, 2462 (a cone, phaseFlags -1), is drawn from 0 to 0 ms, a window that holds
  // the first pulse only: dropping the row by its window would strike nobody at pulses 1 and 2.
  let discharge = fixture_area(spell4_id: 58_832)
  assert spell_area.phase_count(spell: discharge) == 3
    as "Discharge has three pulses"
  let cone =
    Some(
      InsideShapes([
        pulse_cone(inner: 1.0, outer: 15.0, degrees: 50.0, ahead: 0.0),
      ]),
    )
  assert list.map([0, 1, 2], fn(phase) {
      spell_area.inside(spell: discharge, phase:)
    })
    == [cone, cone, cone]
    as "TelegraphDamage 2462 is struck at every pulse: the window draws a picture and ties nothing to a strike"
}

pub fn every_phase_of_every_planned_spell_that_selects_the_area_has_hit_shapes_when_the_spell_has_hit_rows_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // A go that selects units from the area but whose hit rows name no phase would strike nobody
  // without a word: a spell whose rows name none of its gos must not select the area at one.
  let areas = spell_area.areas(tables: client_tables.shared())
  let silent =
    dict.values(areas)
    |> list.flat_map(fn(found) {
      spell_plan.go_numbers(go_count: spell_area.phase_count(spell: found))
      |> list.filter_map(fn(phase) {
        let assert Ok(strike) =
          spell_area.phase(spell: found, phase:, spent: None)
          as "a go below the count is one the spell holds"
        case
          strike.selects_area && spell_area.inside(spell: found, phase:) == None
        {
          True -> Ok(#(found.spell4_id.value, phase))
          False -> Error(Nil)
        }
      })
    })
  assert silent == []
    as "a go that selects the area names no hit row, so it strikes nobody from the area"
}

pub fn the_window_the_client_draws_a_row_in_holds_the_go_its_phase_names_for_every_planned_phased_spell_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // A player's cast reads a hit row by its phase alone (a marked guess). It agrees with the
  // rule a creature's cast uses, phase and the row's time window, while every row that names a
  // go is drawn at that go's time: a row that does not is the case where the two rules strike
  // different units, and then the choice of the phase alone is to be reopened.
  let tables = client_tables.shared()
  let links = spell_area.telegraph_links_by_spell(tables:)
  let differs =
    dict.values(spell_plan.plans_with_later(tables:))
    |> list.flat_map(fn(plan) {
      spell_plan.tree(spell: plan, started: fn(_) { True })
    })
    |> list.flat_map(fn(spell) {
      let assert Ok(row) = spell4.get(tables:, id: spell.spell4_id)
        as "the planned spell has its Spell4 row"
      let assert Ok(base) = spell4_base.get(tables:, id: spell.spell4_base_id)
        as "the planned spell has its Spell4Base row"
      let go_times_ms = spell_plan.go_times_ms(spell)
      case spell_plan.compares_telegraph_phase(row:, base:) {
        False -> []
        True ->
          list.flat_map(
            spell_area.hit_rows_of(tables:, links:, id: spell.spell4_id.value),
            fn(hit) {
              list.index_map(go_times_ms, fn(_, go) { go })
              |> list.filter(fn(go) {
                spell_effect.names_phase(
                  phase_flags: hit.phase_flags,
                  phase: go,
                )
                && !spell_area.is_twin(row: hit)
                && !telegraph_window.drawn_at(row: hit, go_times_ms:, go:)
              })
              |> list.map(fn(go) { #(spell.spell4_id.value, hit.id, go) })
            },
          )
      }
    })
    |> list.unique
  assert differs == []
    as "a hit row names a go its time window does not hold, so a player's phase-only rule and a creature's phase-and-window rule strike different units: reopen the choice to read a player's rows by phase alone"
}

pub fn a_client_spell_with_no_telegraph_row_is_read_by_its_area_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let found = fixture_area(spell4_id: 42_297)
  assert found.row
    == Some(Row(
      min_range: 0.0,
      max_range: 4.0,
      degrees: 360.0,
      target_count: 4,
      order: area.Nearest,
    ))
    as "Spell4.42297.area: Spell4AoeTargetConstraints 704 (angle 360, 4 units, 0 to 4 m)"
  assert shapes_at_go_0(spell: found) == []
    as "Spell4Telegraph holds no row of spell 42297, so it has no hit shape"
  assert spell_area.inside(spell: found, phase: 0) == Some(InsideRow)
    as "Spell4.42297.area: a spell with an area row and no telegraph row is read by the row"
}

pub fn a_client_spell_leaves_out_a_drawn_row_with_bit_0x20_while_another_is_drawn_test() -> Nil {
  use <- owned_test.run(60_000)
  assert shapes_at_go_0(spell: fixture_area(spell4_id: 29_874))
    == [
      Placement(
        shape: Rectangle(width: 0.8999999761581421, length: 19.0),
        ahead: 1.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ]
    as "TelegraphDamage.telegraphDamageFlags.0x20.rows: spell 29874's TelegraphDamage 310 (flags 0x200) is drawn without 0x20, so it is the hit shape; 311 and 312 (flags 0x220, offsets aside of 1.2 and -1.2) are the pictures of the side beams and are left out"
}

pub fn a_telegraph_link_to_a_row_the_table_lacks_is_left_out_as_the_client_leaves_it_out_test() -> Nil {
  use <- owned_test.run(60_000)
  fixture_tables.added(
    table: "Spell4Telegraph",
    copy_of: 69,
    id: 99_001,
    with: [
      #("spell4Id", Integer(29_874)),
      #("telegraphDamageId", Integer(999_999)),
    ],
    body: fn(tables) {
      assert spell_area.hit_shapes_of(
          tables:,
          links: spell_area.telegraph_links_by_spell(tables:),
          id: 29_874,
          reading: spell_area.PlayerReading,
        )
        == Ok([
          Placement(
            shape: Rectangle(width: 0.8999999761581421, length: 19.0),
            ahead: 1.0,
            aside: 0.0,
            turn_degrees: 0.0,
          ),
        ])
        as "0x14055e180 (BuildSpellTables) adds a Spell4Telegraph link to its spell's telegraph list only when GetTelegraphDamageRow finds the row, so a link to a row the table lacks adds no shape and the spell keeps the shapes of its other rows"
    },
  )
}

pub fn a_client_spell_whose_drawn_rows_all_have_bit_0x20_keeps_them_all_test() -> Nil {
  use <- owned_test.run(60_000)
  assert shapes_at_go_0(spell: fixture_area(spell4_id: 58_586))
    == [
      Placement(
        shape: Circle(radius: 1.25),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
      Placement(
        shape: Circle(radius: 0.8999999761581421),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
      Placement(
        shape: Circle(radius: 0.75),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ]
    as "TelegraphDamage.telegraphDamageFlags.0x20.rows: spell 58586's TelegraphDamage 9457, 10882 and 10883 (radii 1.25, 0.9 and 0.75, flags 0x3008220) each hold 0x20 and no row is drawn without it, so all three are kept, in the order of Spell4Telegraph 25023, 27783 and 27784"
}

pub fn a_client_spell_with_a_never_drawn_row_strikes_through_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  assert spell_area.hit_shapes_of(
      tables:,
      links: spell_area.telegraph_links_by_spell(tables:),
      id: 36_373,
      reading: spell_area.PlayerReading,
    )
    == Ok([
      Placement(
        shape: Box(width: 8.0, length: 8.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ])
    as "the never-drawn twin row (flag 0x40) is the hit shape: spell 36373's TelegraphDamage 2481 (flags 0x40, a 8 by 8 m box on the caster) alone; its other row 1721 (flags 0x200, targetTypeFlags 8) is drawn and would be chosen, and refused as not on the caster, if the twin rule did not hold"
}

pub fn a_client_damage_row_with_target_flags_2_and_readable_parameters_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let found = fixture_area(spell4_id: 38_781)
  let assert Ok(damage) =
    list.find(found.damage, fn(effect) {
      effect.effect_id == Spell4EffectsId(83_829)
    })
    as "spell 38781 holds Spell4Effects 83829 among its damage effects"
  assert damage.aim == spell_plan.AimsAtPrimaryTarget
    as "Spell4Effects 83829 has targetFlags 2, which aims at the cast's target"
  let assert Ok(row) =
    spell4_effects.get(
      tables: fixture_tables.shared(),
      id: Spell4EffectsId(83_829),
    )
    as "the fixture holds Spell4Effects 83829"
  assert spell_tables.measure_reads(effect: row, place: spell_tables.pressed)
    as "a finite multiplier, targetFlags 2 and the parameter types 12, 13 and 10 are read by the area load, and so by the measure"
}

pub fn a_spell_whose_valid_targets_hold_a_bit_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // No level-1 tree spell names a Spell4ValidTargets row with a bit.
  let assert Error(ValidTargetsNotAlive(target_bitmask: 0x8, ..)) =
    area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), target_bitmask: 0x8),
    )
    as "Spell4ValidTargets.targetBitmask: 0x8 would strike the dead; only 0 is built, and Kick's row 1 is the row the edit changes"
  Nil
}

pub fn a_hit_row_placed_on_another_unit_than_the_caster_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // The flags the player's reading refuses: 4 each struck unit, 6 the target and each struck
  // unit, 10 the target and the held position (3 and 9 are rows of the flag-8 test). No level-1
  // tree spell has such a TelegraphDamage row.
  list.each(
    [
      #(
        4,
        "a row on each struck unit, which the cast cannot know when it starts",
      ),
      #(6, "the target and each struck unit at once"),
      #(10, "the target and the held position at once"),
    ],
    fn(row) {
      let #(target_type_flags, reason) = row
      assert area_tables.built(
          kick: area_tables.Kick(
            ..area_tables.kick(),
            telegraph_target_type_flags: target_type_flags,
          ),
        )
        == Error(TelegraphNotOnCaster(
          spell4_id: 58_591,
          telegraph_id: 168,
          target_type_flags:,
        ))
        as reason
    },
  )
}

/// The anchor Kick's spell gets when its row 168 has these flags, or why the areas do not build.
fn kick_anchor(
  target_type_flags target_type_flags: Int,
  telegraph_damage_flags telegraph_damage_flags: Int,
) -> Result(area.Anchor, spell_area.AreaError) {
  area_tables.built(
    kick: area_tables.Kick(
      ..area_tables.kick(),
      telegraph_target_type_flags: target_type_flags,
      telegraph_damage_flags:,
    ),
  )
  |> result.map(fn(areas) {
    let assert Ok(found) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
      as "Kick is in its own areas"
    found.anchor
  })
}

pub fn a_player_hit_row_placed_by_flag_0_or_2_is_anchored_on_the_cast_target_and_fixed_when_the_client_draws_it_at_a_position_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kick's row 168 changed (synthetic: the client's trees hold each pair): a row with neither
  // 0x4000 nor 0x1000 is placed by its targetTypeFlags, where 0 or bit 2 is the unit of cast
  // 0x158, the 0x7ff's primary target; a row with 0x4000 or 0x1000 stays at the entry
  // (`0x140546e60.placement_branches`, `0x14054b1b0.fixed_placement`,
  // `0x14054b1b0.follows_caster`). Kick is a pressed spell of target mechanic kind 2, the
  // caster, so the targeting rule lets each row through.
  list.each([0, 2], fn(target_type_flags) {
    list.each(
      [
        #(
          0x200,
          area.FollowsTarget,
          "a target row with no placing flag follows its unit",
        ),
        #(
          0x1200,
          area.FixedAtTarget,
          "a target row with 0x1000 stays at the 0x7ff's entry",
        ),
        #(
          0x4200,
          area.FixedAtTarget,
          "a target row with 0x4000 stays at its telegraph position",
        ),
      ],
      fn(row) {
        let #(telegraph_damage_flags, anchor, reason) = row
        assert kick_anchor(target_type_flags:, telegraph_damage_flags:)
          == Ok(anchor)
          as reason
      },
    )
  })
  let sentence =
    spell_area.describe(error: TelegraphNotOnCaster(58_591, 168, 4))
  list.each(["(1)", "(0 and 2)", "(8)"], fn(named) {
    assert string.contains(sentence, named)
      as "the refusal names the flags a player's row may have: 1, 0 and 2, and 8"
  })
}

pub fn a_hit_row_of_a_spell_started_on_a_struck_unit_is_built_only_when_its_centre_is_that_units_place_test() -> Nil {
  use <- owned_test.run(60_000)
  // `strike.select` centres a spell started on another unit on that unit's shown place at yaw
  // 0.0 (a Proxy on each struck unit, a proc aimed at another unit), and a press, a Proxy on
  // the caster or a proc aimed at its holder on the caster (`cast.proc_started`).
  // `area.in_shape` reads a circle only through its origin, which an offset moves along
  // the unit's yaw, so a circle with no offset is the same at any yaw and under any
  // `turn_degrees`; any other shape reads the yaw (`0x14054b1b0.follows_caster`).
  let placed = fn(shape, ahead, aside, turn_degrees) {
    Placement(shape:, ahead:, aside:, turn_degrees:)
  }
  let circle = placed(Circle(radius: 4.0), 0.0, 0.0, 0.0)
  let turned_circle = placed(Circle(radius: 4.0), 0.0, 0.0, 90.0)
  let circle_ahead = placed(Circle(radius: 4.0), 2.0, 0.0, 0.0)
  let circle_aside = placed(Circle(radius: 4.0), 0.0, 2.0, 0.0)
  // TelegraphDamage 7594, 7721 and 9343 (targetTypeFlags 2) hold an xPositionOffset of -0.0
  // (`table_rows -- TelegraphDamage 7594 7721 9343`), which moves nothing.
  let circle_negative_zero_aside = placed(Circle(radius: 4.0), 0.0, -0.0, 0.0)
  let box = placed(Box(width: 14.0, length: 14.0), 0.0, 0.0, 0.0)
  let cone = placed(Cone(inner: 1.0, outer: 7.0, degrees: 100.0), 0.0, 0.0, 0.0)
  let rectangle = placed(Rectangle(width: 2.0, length: 6.0), 0.0, 0.0, 0.0)
  let every_anchor = [
    area.FollowsCaster,
    area.FixedAtCaster,
    area.FollowsTarget,
    area.FixedAtTarget,
  ]
  let on_the_caster = [area.FollowsCaster, area.FixedAtCaster]
  let on_the_target = [area.FollowsTarget, area.FixedAtTarget]
  let on_the_caster_or_press = [
    spell_plan.Pressed,
    spell_plan.Proxied(target: spell_plan.OnCaster),
    spell_plan.FromProc(aim: spell_plan.AtHolder),
  ]
  let on_another_unit = [
    spell_plan.Proxied(target: spell_plan.OnEachStruck),
    spell_plan.FromProc(aim: spell_plan.AtOtherUnit),
  ]
  list.each(
    [
      #(
        on_the_caster_or_press,
        every_anchor,
        [box],
        True,
        "the primary target is the caster, so every anchor is the caster's place",
      ),
      #(
        on_the_caster_or_press,
        every_anchor,
        [cone, rectangle],
        True,
        "a cone and a rectangle too",
      ),
      #(
        on_another_unit,
        on_the_caster,
        [box],
        True,
        "a row on the caster is centred on the caster, whatever the start",
      ),
      #(
        on_another_unit,
        on_the_caster,
        [cone, circle_aside],
        True,
        "a cone and an offset circle on the caster",
      ),
      #(
        on_another_unit,
        on_the_target,
        [],
        True,
        "no hit shape, as Crush's second spell",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle],
        True,
        "a circle with no offset is the unit's place",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle, turned_circle],
        True,
        "a circle turned about its own centre is the same circle",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle_negative_zero_aside],
        True,
        "an x offset of -0.0 moves nothing, as 0.0 does not",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle_aside],
        False,
        "an x offset moves along the unit's yaw, which is not known",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle_ahead],
        False,
        "a z offset moves along the unit's yaw",
      ),
      #(
        on_another_unit,
        on_the_target,
        [circle, circle_ahead],
        False,
        "one offset circle among others",
      ),
      #(
        on_another_unit,
        on_the_target,
        [box],
        False,
        "a box is turned by the unit's yaw",
      ),
      #(
        on_another_unit,
        on_the_target,
        [cone],
        False,
        "a cone is turned by the unit's yaw",
      ),
      #(
        on_another_unit,
        on_the_target,
        [rectangle],
        False,
        "a rectangle is turned by the unit's yaw",
      ),
    ],
    fn(row) {
      let #(starts, anchors, shapes, expected, reason) = row
      list.each(starts, fn(start) {
        list.each(anchors, fn(anchor) {
          assert spell_area.start_placed(anchor:, start:, shapes:) == expected
            as reason
        })
      })
    },
  )
}

pub fn a_proc_spell_aimed_at_its_holder_is_placed_as_a_press_and_one_aimed_at_another_unit_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // `cast.proc_started` casts a proc's spell at the unit the proc is aimed at: the holder for
  // dataBits03 bits 1, 2, 8 and 16 and none, the event's other unit for bit 4
  // (`spell_plan.ProcAim`). A circle with an x offset on the target is centred right on the
  // holder, whose yaw the strike knows, and wrong on another unit, whose yaw it does not.
  let circle_aside =
    Placement(
      shape: Circle(radius: 4.0),
      ahead: 0.0,
      aside: 2.0,
      turn_degrees: 0.0,
    )
  list.each(
    [
      #(1, True, "a proc aimed at its holder places its row as a press does"),
      #(
        4,
        False,
        "a proc aimed at the event's other unit has that unit's unknown yaw",
      ),
    ],
    fn(row) {
      let #(aim_bits, built, reason) = row
      let spell =
        spell_tables.planned_with_row(
          row: spell_tables.effect_row_with(
            id: 300_001,
            effect_type: 14,
            target_flags: 1,
            columns: [
              #("dataBits03", Integer(aim_bits)),
              ..spell_tables.proc_columns(kind: 217)
            ],
          ),
        )
      let assert [start] =
        spell_plan.tree_started(spell:, started: fn(_) { True })
        |> list.filter_map(fn(started) {
          case started.1 {
            spell_plan.FromProc(..) -> Ok(started.1)
            _ -> Error(Nil)
          }
        })
        as "the planted Proc starts one spell"
      assert spell_area.start_placed(
          anchor: area.FollowsTarget,
          start:,
          shapes: [circle_aside],
        )
        == built
        as reason
    },
  )
}

pub fn a_pressed_spell_whose_hit_row_needs_a_target_or_a_spot_the_press_does_not_give_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kick's target mechanic row 6 changed (synthetic: no client ability changes verdict by this
  // rule). `target_mechanic.kind_of` names each `targetType` (`Spell4TargetMechanics.targetType`,
  // `0x14055bdc0`); the press names the caster as the primary target (`cast` `press_of`) and
  // the 0x9b ground cast is not routed, so a row placed on the cast's target of a spell that
  // is not cast at the caster would strike around the caster.
  let built = fn(target_type, telegraph_target_type_flags) {
    area_tables.built(
      kick: area_tables.Kick(
        ..area_tables.kick(),
        target_type:,
        telegraph_target_type_flags:,
      ),
    )
    |> result.replace(Nil)
  }
  list.each(
    [
      #(0, Ok(Nil), "kind 0 takes the caster"),
      #(2, Ok(Nil), "kind 2 takes the caster"),
      #(6, Ok(Nil), "kind 6 takes the caster"),
      #(7, Ok(Nil), "kind 7 takes the caster"),
      #(1, Error(target_mechanic.Targeted), "kind 1 needs a target unit"),
      #(3, Error(target_mechanic.Targeted), "kind 3 needs a target unit"),
      #(5, Error(target_mechanic.Targeted), "kind 5 needs a target unit"),
      #(8, Error(target_mechanic.Targeted), "kind 8 needs a target unit"),
      #(4, Error(target_mechanic.Ground), "kind 4 is placed on the ground"),
      #(
        9,
        Error(target_mechanic.Unread(target_type: 9)),
        "the picker has no case for kind 9",
      ),
    ],
    fn(row) {
      let #(target_type, expected, reason) = row
      assert built(target_type, 2)
        == result.map_error(expected, fn(kind) {
          TargetingNotBuilt(spell4_id: 58_591, kind:)
        })
        as reason
      assert built(target_type, 1) == Ok(Nil)
        as "a row on the caster is built whatever the spell is cast at"
    },
  )
  let sentence =
    spell_area.describe(error: TargetingNotBuilt(
      spell4_id: 58_591,
      kind: target_mechanic.Targeted,
    ))
  assert string.contains(sentence, "a unit the cast names")
    && string.contains(sentence, "press does not read its target")
    as "the sentence names the kind and says the press does not read the target"
}

pub fn a_player_hit_row_placed_by_flag_8_is_anchored_at_the_cast_start_and_a_flag_1_row_follows_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kick's row 168 changed (synthetic: the client's rows of the trees hold each pair of
  // flags): the client places a row with neither 0x4000 nor 0x1000 by its targetTypeFlags
  // (bit 1 the caster, bit 8 the position the cast holds); a row with 0x4000 or 0x1000 stays
  // at the entry, and a bit-8 row is at the held position whatever its placing
  // (`0x140546e60.placement_branches`, `0x14054b1b0.fixed_placement`).
  list.each(
    [
      #(
        1,
        0x200,
        Ok(area.FollowsCaster),
        "a caster row with no placing flag follows the caster",
      ),
      #(
        1,
        0x1200,
        Ok(area.FixedAtCaster),
        "a caster row with 0x1000 stays at the 0x7ff's entry",
      ),
      #(
        1,
        0x4200,
        Ok(area.FixedAtCaster),
        "a caster row with 0x4000 stays at its telegraph position",
      ),
      #(
        8,
        0x200,
        Ok(area.FixedAtCaster),
        "a bit-8 row is at the position the cast holds",
      ),
      #(
        8,
        0x1200,
        Ok(area.FixedAtCaster),
        "a bit-8 row with 0x1000 is at the held position too",
      ),
      #(
        8,
        0x4200,
        Ok(area.FixedAtCaster),
        "a bit-8 row with 0x4000 is at the held position too",
      ),
      #(
        3,
        0x200,
        Error(TelegraphNotOnCaster(58_591, 168, 3)),
        "the caster and the target at once is not built",
      ),
      #(
        9,
        0x200,
        Error(TelegraphNotOnCaster(58_591, 168, 9)),
        "the caster and the held position at once is not built",
      ),
    ],
    fn(row) {
      let #(target_type_flags, telegraph_damage_flags, expected, reason) = row
      assert kick_anchor(target_type_flags:, telegraph_damage_flags:)
        == expected
        as reason
    },
  )
  assert string.contains(
    spell_area.describe(error: TelegraphNotOnCaster(58_591, 168, 3)),
    "(8)",
  )
    as "the refusal names flag 8 among the flags a player's row may have"
}

pub fn the_anchor_of_a_planned_spell_is_read_from_its_hit_rows_on_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  // Rows by `table_rows -- Spell4Telegraph spell4Id=<id>` and `-- TelegraphDamage <id>`.
  list.each(
    [
      #(
        41_844,
        area.FixedAtCaster,
        "Fissure's child: rows 2996, 2997 and 2998, flag 8",
      ),
      #(
        58_501,
        area.FixedAtCaster,
        "Bum Rush's child: the never-drawn twins 724, 1767 and 1768, flag 8, whose drawn row 723 is flag 1 and is not compared",
      ),
      #(
        44_641,
        area.FixedAtCaster,
        "Concentrated Blade: the twin 4081, flag 8, beside the drawn row 4080, flag 1",
      ),
      #(32_128, area.FixedAtCaster, "Leap: row 3390, flag 8"),
      #(44_471, area.FixedAtCaster, "Personal Defense Unit: row 4029, flag 8"),
      #(41_551, area.FixedAtCaster, "Urgency: row 1721, flag 8"),
      #(39_269, area.FixedAtCaster, "Razor Disk's child: the twin 2123, flag 8"),
      #(
        58_868,
        area.FixedAtCaster,
        "Nullifier, castable before flag 8 was read: row 2789, flags 1 with 0x1200 (0x1000 fixes it where the 0x7ff puts it); its phase holds no damage row and selects no area, so no strike of it moves",
      ),
      #(
        42_676,
        area.FollowsCaster,
        "Pounce: the twin 3579, flag 1, beside the drawn row 3578, flag 8, which is not compared",
      ),
      #(58_591, area.FollowsCaster, "Kick: row 168, flag 1"),
      #(
        47_202,
        area.FixedAtTarget,
        "Flash Bang's child: row 1766, targetTypeFlags 2, flags 0x1200",
      ),
      #(
        35_360,
        area.FixedAtTarget,
        "Rapid Fire: the twin 204 (0x801040) and the drawn row 137 (0xc81620), each with 0x1000 and targetTypeFlags 2",
      ),
      #(
        76_838,
        area.FixedAtTarget,
        "Rapid Fire's alternate under Spell Surge: the same twin 204 and drawn row 137",
      ),
      #(
        41_343,
        area.FollowsTarget,
        "Bio Shell's child: row 15498, targetTypeFlags 2, flags 0x1140220 with neither 0x1000 nor 0x4000",
      ),
      #(
        42_297,
        area.FollowsTarget,
        "Crush's second spell has no hit row, so it is centred on its primary target as before",
      ),
    ],
    fn(row) {
      let #(spell4_id, anchor, reason) = row
      let assert Ok(found) =
        spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
        as "the spell is a spell of a planned ability's tree"
      assert found.anchor == anchor as reason
    },
  )
  let assert Ok(nullifier) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_868))
    as "Nullifier is a spell of a planned ability's tree"
  let assert Ok(phase) =
    spell_area.phase(spell: nullifier, phase: 0, spent: None)
    as "Nullifier has a first phase"
  assert phase.damage == [] && !phase.selects_area
    as "Spell4Effects 141450 and 175305 are no damage row and select no area, so the anchor Nullifier's row gives moves no strike"
}

pub fn a_shape_the_rule_does_not_build_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // No level-1 tree spell has a hit row of shape 1, 3, 5 or 6.
  list.each([1, 3, 5, 6], fn(shape) {
    assert area_tables.built(
        kick: area_tables.Kick(..area_tables.kick(), shape:),
      )
      == Error(ShapeNotBuilt(spell4_id: 58_591, telegraph_id: 168, shape:))
      as "TelegraphDamage.damageShapeEnum: 1 ring, 3, 5 pie and 6 are not built"
  })
}

pub fn a_spell_whose_caster_rows_are_not_placed_alike_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 54838's rows 7814 and 7815 both have flag 0x1000, so the client draws both where the
  // 0x7ff puts them and the hit is centred on that pose (`0x14054b1b0.fixed_placement`). Synthetic:
  // no client spell holds one fixed and one following caster row, so row 7815 is changed to
  // flags 0x0, which the client places on the caster each frame (`0x14054b1b0.follows_caster`):
  // no one centre is where both pictures are.
  let assert Ok(Some(spell_area.CreatureArea(anchor:, ..))) =
    spell_area.area_of_spell(
      tables: fixture_tables.shared(),
      spell4_id: Spell4Id(54_838),
    )
    as "the unchanged spell loads"
  assert anchor == area.FixedAtCaster as "both rows are fixed"
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 7815,
    with: [#("telegraphDamageFlags", Integer(0))],
  )
  assert spell_area.area_of_spell(tables:, spell4_id: Spell4Id(54_838))
    == Error(PlacedApart(
      spell4_id: 54_838,
      telegraph_id: 7814,
      other_telegraph_id: 7815,
    ))
    as "the refusal names the spell and a row of each placing"
}

/// The anchor the creature reading builds for a spell of these tables, or its refusal.
fn creature_anchor(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(area.Anchor, spell_area.AreaError) {
  spell_area.area_of_spell(tables:, spell4_id: Spell4Id(spell4_id))
  |> result.map(fn(found) {
    let assert Some(spell_area.CreatureArea(anchor:, ..)) = found
      as "the spell has an area row"
    anchor
  })
}

pub fn a_creature_row_is_anchored_by_who_it_is_placed_on_and_how_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client places a row by targetTypeFlags (1 the caster, 0 or bit 2 the cast's target) and by
  // TelegraphDamage flags (0x4000 or 0x1000 fixes it at the entry; else it follows its unit)
  // (`0x140546e60.placement_branches`). Rows by `table_rows`: 4796 (tt 2, flags 0), 5671 and 5672
  // (tt 2, flags 0), 7874 (tt 2, 0x905000), 2376 (tt 0, 0x1000), 9129 (tt 2, 0x5000).
  let tables = fixture_tables.shared()
  list.each(
    [
      #(46_353, area.FollowsTarget, "row 4796, tt 2, flags 0"),
      #(48_590, area.FollowsTarget, "rows 5671 and 5672, tt 2, flags 0"),
      #(61_226, area.FollowsTarget, "its ring rows, tt 2"),
      #(55_846, area.FixedAtTarget, "row 7874, tt 2, flags 0x905000"),
      #(39_641, area.FixedAtTarget, "row 2376, tt 0, flags 0x1000"),
      #(61_275, area.FixedAtTarget, "row 9129, tt 2, flags 0x5000"),
      #(85_469, area.FollowsCaster, "a caster row that follows"),
      #(55_317, area.FixedAtCaster, "a caster row that is fixed"),
    ],
    fn(row) {
      let #(spell4_id, anchor, reason) = row
      assert creature_anchor(tables:, spell4_id:) == Ok(anchor) as reason
    },
  )
  {
    use tables <- fixture_tables.changed(
      table: "TelegraphDamage",
      id: 4796,
      with: [#("targetTypeFlags", Integer(0))],
    )
    assert creature_anchor(tables:, spell4_id: 46_353) == Ok(area.FollowsTarget)
      as "row 4796 with targetTypeFlags 0 is placed on the target too"
  }
  // Laser Bolt's tiers: area rows 116 (range 10, 10 units, 360 degrees) and 210 (range 12) and
  // the circles of TelegraphDamage 7874 (4) and 7875 (6).
  list.each([#(55_846, 10.0, 4.0), #(55_847, 12.0, 6.0)], fn(tier) {
    let #(spell4_id, max_range, radius) = tier
    let assert Ok(Some(spell_area.CreatureArea(row:, inside:, ..))) =
      spell_area.area_of_spell(tables:, spell4_id: Spell4Id(spell4_id))
      as "Laser Bolt's tiers load"
    assert row
      == Row(
        min_range: 0.0,
        max_range:,
        degrees: 360.0,
        target_count: 10,
        order: area.Nearest,
      )
    assert inside
      == InsideShapes(placements: [
        Placement(
          shape: Circle(radius:),
          ahead: 0.0,
          aside: 0.0,
          turn_degrees: 0.0,
        ),
      ])
  })
}

pub fn a_row_placed_on_each_struck_unit_or_on_the_ground_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Bit 4 places a row on each unit the strike finds, which the cast cannot know at its start
  // (TelegraphDamage 14428 of Spell4 46696 and the twin 14629 of 39905, both tt 4); bit 8 places
  // it on the ground, a position the cast holds (`0x140546e60.placement_branches`). The changed
  // rows are synthetic: no loadable special holds one.
  assert creature_anchor(tables: fixture_tables.shared(), spell4_id: 46_696)
    == Error(TelegraphOnStruckUnits(
      spell4_id: 46_696,
      telegraph_id: 14_428,
      target_type_flags: 4,
    ))
  assert creature_anchor(tables: fixture_tables.shared(), spell4_id: 39_905)
    == Error(TelegraphOnStruckUnits(
      spell4_id: 39_905,
      telegraph_id: 14_629,
      target_type_flags: 4,
    ))
  list.each(
    [
      #(5, TelegraphOnStruckUnits(55_846, 7874, 5), "bit 4 among others"),
      #(8, TelegraphNotOnCaster(55_846, 7874, 8), "the ground"),
      #(3, TelegraphNotOnCaster(55_846, 7874, 3), "caster and target at once"),
      #(9, TelegraphNotOnCaster(55_846, 7874, 9), "caster and ground at once"),
    ],
    fn(row) {
      let #(target_type_flags, refusal, reason) = row
      use tables <- fixture_tables.changed(
        table: "TelegraphDamage",
        id: 7874,
        with: [#("targetTypeFlags", Integer(target_type_flags))],
      )
      assert creature_anchor(tables:, spell4_id: 55_846) == Error(refusal)
        as reason
    },
  )
}

pub fn a_spell_whose_rows_are_not_placed_alike_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Laser Bolt's row 7874 is a fixed row on the target. Each case links one more row placed
  // otherwise: a caster row (7880, tt 1, fixed), a following target row (4796), and a copy of
  // 7874 with the never-drawn flag 0x40 on the caster, which becomes the hit while the picture
  // stays on the target; and, beside a twin placed as 7874 is, a drawn row on each struck unit,
  // which no anchor serves and is refused as a hit row on them is. Synthetic: none of the
  // loadable specials mixes them.
  let linked = fn(rows, link_id, telegraph_damage_id) {
    let assert Ok(rows) =
      fixture_tables.add(
        rows:,
        table: "Spell4Telegraph",
        copy_of: 16_625,
        id: link_id,
        with: [#("telegraphDamageId", Integer(telegraph_damage_id))],
      )
      as "Spell4Telegraph 16625 is Laser Bolt's own link"
    rows
  }
  let copy_of_7874 = fn(rows, id, flags, target_type_flags) {
    let assert Ok(rows) =
      fixture_tables.add(
        rows:,
        table: "TelegraphDamage",
        copy_of: 7874,
        id:,
        with: [
          #("telegraphDamageFlags", Integer(flags)),
          #("targetTypeFlags", Integer(target_type_flags)),
        ],
      )
      as "TelegraphDamage 7874 is Laser Bolt's row"
    rows
  }
  let with_caster_twin =
    copy_of_7874(fixture_tables.rows(), 99_002, 0x905040, 1)
  let with_target_twin =
    copy_of_7874(fixture_tables.rows(), 99_002, 0x905040, 2)
    |> copy_of_7874(99_003, 0x905000, 4)
  list.each(
    [
      #(
        linked(fixture_tables.rows(), 99_001, 7880),
        PlacedApart(55_846, 7874, 7880),
        "a caster row beside a target row",
      ),
      #(
        linked(fixture_tables.rows(), 99_001, 4796),
        PlacedApart(55_846, 7874, 4796),
        "a fixed target row beside a following one",
      ),
      #(
        linked(with_caster_twin, 99_001, 99_002),
        PlacedApart(55_846, 99_002, 7874),
        "a hit twin placed apart from the drawn row",
      ),
      #(
        linked(with_target_twin, 99_001, 99_002) |> linked(99_004, 99_003),
        TelegraphOnStruckUnits(55_846, 99_003, 4),
        "a drawn row on each struck unit beside a twin on the target",
      ),
    ],
    fn(row) {
      let #(rows, refusal, reason) = row
      use tables <- fixture_tables.on_rows(rows:, reaching: [])
      assert creature_anchor(tables:, spell4_id: 55_846) == Error(refusal)
        as reason
    },
  )
}

pub fn a_damage_multiplier_that_is_not_a_finite_float_fails_the_load_naming_the_effect_test() -> Nil {
  use <- owned_test.run(60_000)
  // No level-1 tree spell holds a damage multiplier that is a NaN or an infinity.
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
  // No level-1 tree spell has a damage effect with targetFlags 9.
  assert area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), effect_target_flags: 9),
    )
    == Error(AimNotRead(spell4_id: 58_591, effect_id: 140_383, target_flags: 9))
    as "Spell4Effects.targetFlags: 1 to 7 are the aims the plan reads; 9 holds bit 8"
}

/// Spell4Effects 61198 as the client holds it, with a formula the player's value reads
/// (the row itself holds parameter type 4, which the area load refuses as a formula):
/// spell 32475, aimed at the cast's target (targetFlags 2), damage type 3, delayTime 1500,
/// durationTime 6000 and phaseFlags 1. The test sets its tickTime.
fn periodic_damage_row(tick_ms tick_ms: Int) -> spell4_effects.Spell4Effects {
  spell4_effects.Spell4Effects(
    ..spell_tables.blank_effect(
      id: 61_198,
      spell: 32_475,
      effect_type: 8,
      target_flags: 2,
    ),
    damage_type: 3,
    delay_time: 1500,
    tick_time: tick_ms,
    duration_time: 6000,
    phase_flags: 1,
    threat_multiplier: 1.0,
  )
}

pub fn a_damage_row_with_a_tick_time_ticks_on_its_schedule_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(Periodic(effect: row)) =
    spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 32_475,
      effect: periodic_damage_row(tick_ms: 1500),
    )
    as "Spell4Effects 61198 holds tickTime 1500: the client never times ticks, each is its own 0x7f8 from the server (spell.tick_timing)"
  assert #(row.damage.effect_id, row.schedule)
    == #(
      Spell4EffectsId(61_198),
      ticking.Schedule(
        delay_ms: 1500,
        tick_ms: 1500,
        duration_ms: 6000,
        count: 4,
      ),
    )
    as "delayTime 1500, tickTime 1500 and durationTime 6000: four ticks, the first a tick after the delay"
}

pub fn a_damage_row_with_no_tick_time_is_read_as_one_strike_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(Once(effect:)) =
    spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 32_475,
      effect: periodic_damage_row(tick_ms: 0),
    )
    as "the refusal keys on tickTime alone"
  assert #(
      effect.effect_id,
      effect.damage_type,
      effect.delay_ms,
      effect.phase_flags,
      effect.aim,
    )
    == #(Spell4EffectsId(61_198), 3, 1500, 1, spell_plan.AimsAtPrimaryTarget)
    as "Spell4Effects 61198: damageType 3, delayTime 1500, phaseFlags 1, targetFlags 2 (the cast's target)"
}

/// The client's Spell4Effects row `id` from the fixture.
fn fixture_effect(id id: Int) -> spell4_effects.Spell4Effects {
  let assert Ok(row) =
    spell4_effects.get(tables: fixture_tables.shared(), id: Spell4EffectsId(id))
    as "the fixture holds the row"
  row
}

pub fn the_area_load_builds_a_damage_row_that_names_an_attribute_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(Once(effect:)) =
    spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 42_355,
      effect: fixture_effect(id: 96_307),
    )
    as "Spellslinger - Insight - Tier 1 - Damage: a player's value reads Wisdom (type 5) (Spell4Effects.effectType.8.attribute_kinds)"
  assert list.contains(
    effect.formula.parameters,
    damage.Parameter(kind: 5, value: 1.5),
  )
    as "row 96307's parameterType00 5 and parameterValue00 0x3fc00000 (1.5)"
}

pub fn a_ticking_row_that_names_an_attribute_ticks_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(Periodic(effect: row)) =
    spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 29_550,
      effect: fixture_effect(id: 52_057),
    )
    as "row 52057 names Magic (type 4), which is read, and tickTime 1000"
  assert #(row.damage.effect_id, row.schedule.tick_ms)
    == #(Spell4EffectsId(52_057), 1000)
    as "row 52057's tickTime 1000"
}

pub fn until_removed_periodic_rows_are_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // No spell of a level-1 tree holds a damage row with a tickTime, so Mind Burst's second
  // damage row (61994, tickTime 0 in the client) is given one, with flags bit 2: the row
  // lasts until removed, which no schedule ends (issue 803).
  let area =
    mind_burst_with(table: "Spell4Effects", id: 61_994, with: [
      #("tickTime", Integer(1000)),
      #("durationTime", Integer(0)),
      #("flags", Integer(2)),
    ])
  let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
    as "Mind Burst has one phase"
  assert #(
      list.map(phase.damage, fn(effect) { effect.effect_id }),
      phase.ticking,
    )
    == #(
      [
        Spell4EffectsId(61_993),
        Spell4EffectsId(61_995),
        Spell4EffectsId(61_996),
        Spell4EffectsId(61_997),
      ],
      [],
    )
    as "Spell4.32809 holds damage rows 61993 to 61997: the until-removed row is left out, the other four stay, and the load goes on"
  assert spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 32_809,
      effect: spell4_effects.Spell4Effects(
        ..fixture_effect(id: 61_994),
        tick_time: 1000,
        duration_time: 0,
        flags: 2,
      ),
    )
    == Error(TickingUntilRemoved(spell4_id: 32_809, effect_id: 61_994))
    as "the area load's reader names why it leaves the row out"
  // Energize's row 228914 (a HealShields row on the caster, tickTime 0 in the client) is
  // given a tickTime and flags bit 2.
  let assert Ok(plans) =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 228_914,
      with: [
        #("tickTime", Integer(1000)),
        #("durationTime", Integer(0)),
        #("flags", Integer(2)),
      ],
      body: fn(tables) { spell_plan.build(tables:) },
    )
    as "the plan load goes on past an until-removed heal row"
  let assert Ok(medic) = spell_plan.in_plans(plans:, base: Spell4BaseId(46_615))
    as "the plans hold the Medic's innate"
  let assert Ok(energize) =
    list.find(spell_plan.tree(spell: medic, started: fn(_) { True }), fn(spell) {
      spell.spell4_id == Spell4Id(69_450)
    })
    as "its tree holds Energize, spell 69450"
  assert spell_plan.payloads(spell: energize, as_kind: spell_plan.as_heal) == []
    as "Energize's one heal row lasts until removed, so the plan leaves it out"
  assert spell_tables.read_row(
      effect: spell4_effects.Spell4Effects(
        ..fixture_effect(id: 228_914),
        tick_time: 1000,
        duration_time: 0,
        flags: 2,
      ),
      place: spell_tables.pressed,
    )
    == Ok(spell_plan.LeftOut(why: spell_plan.HealUntilRemoved))
    as "the plan's heal reader names why it leaves the row out (HealUntilRemoved)"
  // A life shorter than one tick has no tick, and the load fails.
  let assert Ok(short) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4Effects",
      id: 61_994,
      with: [#("tickTime", Integer(1000)), #("durationTime", Integer(500))],
    )
    as "the fixture holds row 61994"
  let assert Error(table_store.DerivationFailed(name: "SpellAreas", reason:)) =
    fixture_tables.load(rows: short)
    as "durationTime 500 under tickTime 1000 fails the area load"
  assert reason
    == spell_area.describe(TickingNoTick(
      spell4_id: 32_809,
      effect_id: 61_994,
      tick_ms: 1000,
      duration_ms: 500,
    ))
    as "the load names the spell, the row, its tickTime and its durationTime"
}

pub fn a_spell_with_an_until_removed_damage_row_is_refused_by_the_checker_while_the_load_leaves_it_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mind Burst's second damage row (61994, tickTime 0 in the client) is given a tickTime and
  // flags bit 2, as in the test above: the row lasts until removed, which no schedule ends.
  let changes = [
    #("tickTime", Integer(1000)),
    #("durationTime", Integer(0)),
    #("flags", Integer(2)),
  ]
  let spell =
    spell_tables.mind_burst_in(areas: spell_tables.fixture_areas()).spell
  assert spell_area.checker(tables: fixture_tables.shared())(
      spell,
      spell_plan.Pressed,
    )
    == Ok(Nil)
    as "Mind Burst as the client has it passes the checker"
  let verdict =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 61_994,
      with: changes,
      body: fn(tables) {
        spell_area.checker(tables:)(spell, spell_plan.Pressed)
      },
    )
  let assert Error(spell_plan.AreaNotBuilt(spell4_id:, reason:)) = verdict
    as "an until-removed damage row refuses the spell, so no ability holds a press that strikes nothing"
  assert spell4_id == 32_809 as "the refusal names Mind Burst's Spell4 row"
  assert string.contains(
    reason,
    "periodic damage effect 61994 that lasts until removed",
  )
    as { "the sentence names the row: " <> reason }
}

pub fn a_damage_row_the_area_load_refuses_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // No level-1 tree spell holds a damage row with an infinite multiplier, targetFlags 9 or a
  // parameter of type 18. Each edited Kick holds one damage row the area load refuses, and the measure asks the
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
        area_tables.Kick(..area_tables.kick(), effect_target_flags: 9),
        AimNotRead(spell4_id: 58_591, effect_id: 140_383, target_flags: 9),
        "Spell4Effects.targetFlags: 1 to 7 are the aims the plan reads; 9 holds bit 8",
      ),
      #(
        area_tables.Kick(..area_tables.kick(), parameters: [#(18, 0.5)]),
        FormulaNotRead(
          spell4_id: 58_591,
          effect_id: 140_383,
          parameter_kind: 18,
        ),
        "0x140566ad0: type 18 is a value passed in by the caller, which a player's damage row has none of, so a non-zero type 18 is refused",
      ),
    ],
    fn(planted) {
      let #(kick, error, why) = planted
      assert area_tables.built(kick:) == Error(error) as why
      assert !area_tables.read_by_the_measure(kick:)
        as "a row the area load refuses is not read"
    },
  )
}

pub fn a_client_damage_row_naming_a_vital_kind_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140566ad0: type 7 is the target's max health. Kick's damage row with that one
  // parameter builds, and the measure reads it while it aims past the caster. Aimed at the
  // caster alone (targetFlags 1) the row loads but strikes nobody, so the measure does not
  // count it as read (#831).
  let vital = area_tables.Kick(..area_tables.kick(), parameters: [#(7, 0.5)])
  let assert Ok(_) = area_tables.built(kick: vital)
    as "the area load builds a row that names a vital kind"
  assert area_tables.read_by_the_measure(kick: vital)
    as "a row that names a vital kind and strikes past its caster is read"
  let on_caster = area_tables.Kick(..vital, effect_target_flags: 1)
  let assert Ok(_) = area_tables.built(kick: on_caster)
    as "the same row aimed at the caster alone still loads"
  assert !area_tables.read_by_the_measure(kick: on_caster)
    as "a row aimed at the caster alone strikes nobody, so it is not counted as read"
}

pub fn a_vital_kind_row_that_lasts_until_removed_is_still_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // A periodic row with flags bit 2 and no durationTime has no schedule (#803), whatever
  // its formula names.
  assert spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 32_809,
      effect: spell4_effects.Spell4Effects(
        ..fixture_effect(id: 61_994),
        tick_time: 1000,
        duration_time: 0,
        flags: 2,
        parameter_type00: 7,
        parameter_value00: 0.5,
      ),
    )
    == Error(TickingUntilRemoved(spell4_id: 32_809, effect_id: 61_994))
    as "a kind 7 row that lasts until removed is left out for its schedule, not its formula"
}

pub fn the_clients_tables_build_every_areas_kick_has_5_units_8_m_180_degrees_and_a_cone_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(kicked) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
    as "Kick is in the areas"
  assert kicked.row
    == Some(Row(
      min_range: 0.0,
      max_range: 8.0,
      degrees: 180.0,
      target_count: 5,
      order: area.Nearest,
    ))
    as "Spell4.58591.area: row 640"
  let assert [Placement(shape: Cone(inner:, outer:, degrees:), ..)] =
    shapes_at_go_0(spell: kicked)
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
  assert shapes_at_go_0(spell: surge)
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
      spell_plan.AimsAtPrimaryTargetAndArea,
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
      == crowd_control.Row(
        state:,
        delay_ms:,
        duration_ms:,
        armor_removed: 1,
        until_removed: False,
      )
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

// ---- the property modifiers aimed at other units ----

/// A spell of the client's rows that no level-1 ability's tree holds, planned on its own
/// (`spell_plan.spell_alone`) and set in an area with no row and no damage effect: the
/// spells the tests below read hold no damage row, and what they ask is only what a phase
/// of the plan selects.
fn planned_alone(spell4_id spell4_id: Int) -> spell_area.SpellArea {
  let tables = fixture_tables.shared()
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id:,
      chain: [],
    )
    as "the spell plans on its own from the client's rows"
  spell_area.SpellArea(
    spell4_id: Spell4Id(spell4_id),
    row: None,
    inside_by_go: [Some(InsideRow)],
    anchor: area.FollowsTarget,
    damage: [],
    ticking: [],
    spell:,
  )
}

pub fn phase_with_a_union_damage_row_selects_the_area_and_strikes_the_target_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 11846 (`table_rows -- Spell4Effects 11846`): spell 6518, effectType 8,
  // targetFlags 7 (the caster, the primary target and the area), phaseFlags 1.
  let tables = fixture_tables.shared()
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(11_846))
    as "the fixture holds the client's row"
  let assert Ok(Once(effect: damage)) =
    spell_area.damage_row_of(tables:, spell4_id: 6518, effect: row)
    as "a damage row aimed by flags 7 is read, and it strikes once"
  assert damage.aim == spell_plan.AimsAtCasterPrimaryTargetAndArea
    as "targetFlags 7 hold all three bits"
  let planned = planned_alone(spell4_id: 6518)
  let area = spell_area.SpellArea(..planned, damage: [damage])
  let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
  assert phase.selects_area
    as "bit 4 aims at the area, so the phase selects its units"
  assert phase.strikes_primary_target
    as "bit 2 aims at the cast's target, so the phase strikes it"
  assert phase.damage == [damage]
    as "the row is in the phase's damage, to land on the units the phase selects"
}

pub fn a_modifier_only_child_aimed_at_the_target_strikes_the_primary_target_test() -> Nil {
  use <- owned_test.run(60_000)
  // Medic Fissure's child 41886 holds one row, 94370 (`table_rows -- Spell4Effects
  // 94370`): a UnitPropertyModifier of property 160, targetFlags 2, no damage and no
  // crowd control. Its base 26081 holds target mechanic 3, a spell cast on a unit
  // (`Spell4TargetMechanics.targetType`), so the row's unit is the one it is cast on.
  let fissure = planned_alone(spell4_id: 41_886)
  let assert Ok(phase) = spell_area.phase(spell: fissure, phase: 0, spent: None)
  assert list.map(
      spell_plan.in_phase(
        spell: fissure.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_modifier,
      ),
      fn(modifier) { modifier.effect_id },
    )
    == [Spell4EffectsId(94_370)]
    as "Spell4Effects 94370 is the child's one property row"
  assert phase.strikes_primary_target
    as "Spell4Effects 94370: targetFlags 2 aims at the cast's target, so the phase strikes the primary target"
  assert !phase.selects_area as "targetFlags 2 does not aim at the area"
  assert phase.damage == [] && phase.controls == []
    as "the child holds no damage and no crowd control, so only the property row asks for the unit"
}

pub fn a_modifier_only_spell_aimed_at_the_area_selects_the_areas_units_test() -> Nil {
  use <- owned_test.run(60_000)
  // Warrior Defense Grid - Aura 54475 holds the rows 129039, 183223 and 183224
  // (`table_rows -- Spell4Effects 129039 183223 183224`): UnitPropertyModifier rows of
  // properties 159, 160 and 161, targetFlags 4, phaseFlags 1, and no damage or crowd
  // control row at other units. Its area row is 391 (`table_rows -- Spell4 54475`).
  let aura = planned_alone(spell4_id: 54_475)
  let assert Ok(phase) = spell_area.phase(spell: aura, phase: 0, spent: None)
  assert list.map(
      spell_plan.in_phase(
        spell: aura.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_modifier,
      ),
      fn(modifier) { modifier.effect_id.value },
    )
    == [129_039, 183_223, 183_224]
    as "the three type 11 rows aimed at the area are the aura's property rows"
  assert phase.selects_area
    as "targetFlags 4 aims at the area, so the phase selects the area's units"
  assert !phase.strikes_primary_target
    as "targetFlags 4 does not aim at the cast's target"
}

pub fn an_absorb_and_an_armor_row_aimed_at_the_target_strike_nobody_test() -> Nil {
  use <- owned_test.run(60_000)
  // Esper Phantasmal Armor 76618 holds an Absorption row 198734 and a
  // ModifyInterruptArmor row 198735, both targetFlags 2, phaseFlags 1, and no damage,
  // crowd-control or type 11 row (`table_rows -- Spell4Effects spellId=76618`). Only a
  // type 11 row aimed at other units names creatures to change.
  let armor = planned_alone(spell4_id: 76_618)
  let assert Ok(phase) = spell_area.phase(spell: armor, phase: 0, spent: None)
  assert list.map(
      spell_plan.in_phase(
        spell: armor.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_modifier,
      ),
      fn(modifier) {
        #(modifier.effect_id.value, spell_plan.modifier_aim(modifier:))
      },
    )
    == [
      #(198_734, spell_plan.AimsAtPrimaryTarget),
      #(198_735, spell_plan.AimsAtPrimaryTarget),
    ]
    as "the plan holds both rows, aimed at the cast's target"
  assert !phase.strikes_primary_target && !phase.selects_area
    as "an absorb or an armor row aimed at the target is no property change of a struck unit, so the phase strikes nobody"
}

pub fn a_periodic_damage_row_strikes_with_its_schedule_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Spell 38514 (Atomic Surge) is no level-1 ability, and no level-1 tree spell holds a
  // periodic damage row, so the area load never holds it: its row goes through the load's
  // own reader, and the phase is shown on Mind Burst given the row's timing.
  let assert Ok(row) =
    spell4_effects.get(
      tables: client_tables.shared(),
      id: Spell4EffectsId(82_888),
    )
    as "the client's tables hold row 82888"
  let assert Ok(Periodic(effect: read)) =
    spell_area.damage_row_of(
      tables: client_tables.shared(),
      spell4_id: 38_514,
      effect: row,
    )
    as "a damage row with a tickTime and a life of whole ticks is read"
  assert #(read.damage.effect_id, read.damage.aim, read.schedule)
    == #(
      Spell4EffectsId(82_888),
      spell_plan.AimsAtPrimaryTarget,
      ticking.Schedule(
        delay_ms: 1000,
        tick_ms: 1000,
        duration_ms: 4000,
        count: 4,
      ),
    )
    as "Spell4Effects 82888 (table_rows -- Spell4Effects spellId=38514): effectType 8, targetFlags 2, delayTime 1000, tickTime 1000, durationTime 4000; tick k lands 1000 + k * 1000 ms after the go (spell.tick_timing, a guess)"
  let area =
    mind_burst_with(table: "Spell4Effects", id: 61_994, with: [
      #("delayTime", Integer(1000)),
      #("tickTime", Integer(1000)),
      #("durationTime", Integer(4000)),
      #("targetFlags", Integer(2)),
    ])
  let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
    as "Mind Burst has one phase"
  assert list.map(phase.ticking, fn(ticking_row) {
      #(
        ticking_row.damage.effect_id,
        ticking_row.damage.aim,
        ticking_row.schedule,
      )
    })
    == [
      #(
        Spell4EffectsId(61_994),
        spell_plan.AimsAtPrimaryTarget,
        ticking.Schedule(
          delay_ms: 1000,
          tick_ms: 1000,
          duration_ms: 4000,
          count: 4,
        ),
      ),
    ]
    as "Mind Burst's row 61994 (targetFlags 4 in the client) given 82888's aim and timing: its phase ticks it on the cast's target"
  assert phase.strikes_primary_target
    as "a ticking row aimed at the cast's target makes the phase strike it"
}

pub fn a_throw_only_spell_aimed_at_the_target_strikes_the_primary_target_test() -> Nil {
  use <- owned_test.run(60_000)
  // Generic Knockback - 10 m 36010 holds one row, 73826 (`table_rows -- Spell4Effects
  // 73826`): a ForcedMove of targetFlags 2 and phaseFlags -1, no damage, crowd control
  // or property row. Only a throw asks for the unit it moves.
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: 36_010,
      chain: [],
    )
    as "the spell plans on its own from the client's rows"
  let knockback =
    spell_area.SpellArea(
      spell4_id: Spell4Id(36_010),
      row: None,
      inside_by_go: [Some(InsideRow)],
      anchor: area.FollowsTarget,
      damage: [],
      ticking: [],
      spell:,
    )
  let assert Ok(phase) =
    spell_area.phase(spell: knockback, phase: 0, spent: None)
  assert list.map(
      spell_plan.in_phase(
        spell: knockback.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_struck_move,
      ),
      fn(row) { row.effect_id.value },
    )
    == [73_826]
    as "Spell4Effects 73826 is the spell's one throw"
  assert phase.strikes_primary_target
    as "Spell4Effects 73826: targetFlags 2 aims at the cast's target, so the phase strikes the primary target"
  assert !phase.selects_area as "targetFlags 2 does not aim at the area"
  assert phase.damage == [] && phase.controls == []
    as "the spell holds no damage and no crowd control, so only the throw asks for the unit"
}

pub fn a_despawn_aimed_at_the_target_makes_the_phase_strike_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 99864 (Spell4 43559, `table_rows -- Spell4Effects 99864`) is a type 97 row
  // of targetFlags 2 and the spell's only effect, so no damage row asks for the unit; the
  // row is planted in a spell of the plan's tables.
  let spell = spell_tables.despawn_only_area(target_flags: 2)
  assert list.map(
      spell_plan.in_phase(
        spell: spell.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_despawn,
      ),
      fn(row) { row.effect_id.value },
    )
    == [99_097]
    as "the planted row is the spell's one despawn"
  let assert Ok(phase) = spell_area.phase(spell:, phase: 0, spent: None)
  assert phase.strikes_primary_target
    as "targetFlags 2 aims at the cast's target, so the phase strikes the primary target"
  assert !phase.selects_area as "targetFlags 2 does not aim at the area"
  assert phase.damage == [] && phase.controls == []
    as "no damage and no crowd control: only the despawn asks for the unit"
}

pub fn a_despawn_aimed_at_the_area_makes_the_phase_select_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 91427 (Spell4 40913, `table_rows -- Spell4Effects 91427`) is a type 97 row
  // of targetFlags 4, the area, with a delay of 4000.
  let spell = spell_tables.despawn_only_area(target_flags: 4)
  let assert Ok(phase) = spell_area.phase(spell:, phase: 0, spent: None)
  assert phase.selects_area
    as "targetFlags 4 aims at the area, so the phase selects it"
  assert !phase.strikes_primary_target as "and not the primary target alone"
}

/// Spell4 55317 (Rootbrute Grimspore's Earthen Roar) with its hit row 7880, a cone on the
/// caster (flags 0x105000, targetTypeFlags 1), changed to `edits`: what the creature reading
/// makes of its shapes, or the refusal.
fn roar_shapes_with(
  edits edits: List(#(String, planted_table.Cell)),
  reading reading: spell_area.Reading,
) -> Result(List(Placement), spell_area.AreaError) {
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 7880,
    with: edits,
  )
  spell_area.hit_shapes_of(
    tables:,
    links: spell_area.telegraph_links_by_spell(tables:),
    id: 55_317,
    reading:,
  )
}

/// The edits that give row 7880 the shape, params, turn and offset of the client's
/// TelegraphDamage row `row_id`, and its shape number.
fn edits_of_row(
  row_id row_id: Int,
) -> #(List(#(String, planted_table.Cell)), Int) {
  let assert Ok(row) =
    telegraph_damage.get(
      tables: fixture_tables.shared(),
      id: TelegraphDamageId(row_id),
    )
    as "the row is a root of the fixture"
  #(
    [
      #("damageShapeEnum", Integer(row.damage_shape_enum)),
      #("param00", planted_table.Float(row.param00)),
      #("param01", planted_table.Float(row.param01)),
      #("param02", planted_table.Float(row.param02)),
      #("zPositionOffset", planted_table.Float(row.z_position_offset)),
      #("rotationDegrees", planted_table.Float(row.rotation_degrees)),
    ],
    row.damage_shape_enum,
  )
}

pub fn the_creature_reading_builds_shapes_1_3_5_and_6_from_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case is a real TelegraphDamage row's shape, params, turn and offset (read from the
  // fixture) put on row 7880, which keeps its flags and its targetTypeFlags 1 (the real row
  // 2920 has targetTypeFlags 2, a unit but the caster, which a creature's hit is not placed
  // on before it can be). The expected placements are `0x14054d170.shapes_1_3_5_6`: shape 1 a
  // ring, so a cone of 360 degrees; 3 two boxes, the second with width and length swapped;
  // 5 the arc of 360 less param02 with the facing turned by 180 degrees; 6 the unhalved box,
  // 2 p0 by 2 p2 where shape 2 is p0 by p2.
  list.each(client_shape_rows.row_ids, fn(row_id) {
    let wanted = client_shape_rows.placements_of(row_id:)
    let #(edits, shape) = edits_of_row(row_id:)
    assert roar_shapes_with(edits:, reading: spell_area.CreatureReading)
      == Ok(wanted)
      as "the creature reading builds the shape the client draws for the row"
    assert roar_shapes_with(edits:, reading: spell_area.PlayerReading)
      == Error(ShapeNotBuilt(spell4_id: 55_317, telegraph_id: 7880, shape:))
      as "a player's ability still refuses the shape (a level-1 tree holds none)"
  })
}

pub fn the_creature_reading_takes_orders_2_and_3_and_refuses_4_and_5_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 55317's area row is Spell4AoeTargetConstraints 116, which selects in order 1.
  // Orders 4 and 5 (LowestAbsoluteHealth, MissingMostHealth) need a unit's health, which a
  // creature's sighting of a fighter does not hold (`Spell4AoeTargetConstraints.targetSelection`).
  let creature_order = fn(selection) {
    use tables <- fixture_tables.changed(
      table: "Spell4AoeTargetConstraints",
      id: 116,
      with: [#("targetSelection", Integer(selection))],
    )
    spell_area.area_of_spell(tables:, spell4_id: Spell4Id(55_317))
    |> result.map(option.map(_, fn(found) { found.row.order }))
  }
  assert creature_order(1) == Ok(Some(area.Nearest))
  assert creature_order(2) == Ok(Some(area.Furthest))
  assert creature_order(3) == Ok(Some(area.Random))
  assert creature_order(4)
    == Error(SelectionNeedsHealth(spell4_id: 55_317, target_selection: 4))
  assert creature_order(5)
    == Error(SelectionNeedsHealth(spell4_id: 55_317, target_selection: 5))
  assert creature_order(0)
    == Error(SelectionNotBuilt(spell4_id: 55_317, target_selection: 0))
    as "order 0, None, is no order and is refused"
}

/// The result of building the areas with Kick's area row ordered `selection`, its damage and
/// crowd-control rows aimed by `effect_target_flags` and its valid targets `target_bitmask`:
/// Kick's own area row with the order it builds, or the refusal.
fn kick_built_with(
  selection selection: Int,
  effect_target_flags effect_target_flags: Int,
  target_bitmask target_bitmask: Int,
) -> Result(Option(Row), spell_area.AreaError) {
  area_tables.built(
    kick: area_tables.Kick(
      ..area_tables.kick(),
      target_selection: selection,
      effect_target_flags:,
      control_target_flags: effect_target_flags,
      target_bitmask:,
    ),
  )
  |> result.map(fn(areas) {
    let assert Ok(found) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(58_591))
      as "Kick is in the areas"
    found.row
  })
}

pub fn a_players_row_builds_orders_2_and_3_reads_4_and_5_as_no_area_and_refuses_0_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Some(kick_row) = client_kick().row
    as "Kick's area row 640 is built"
  // Each case is Kick's row 640 with `targetSelection` edited. Flag 1 on Kick's damage row
  // aims it at the caster alone, so no go selects the area and a row ordered by health is
  // read as no area. Orders 2 to 5 are named, never ordered, by the client
  // (`Spell4AoeTargetConstraints.targetSelection`): the rows build as a guess the gap states.
  let cases = [
    #(1, 4, 0, Ok(Some(kick_row)), "Closest is the order Kick's row holds"),
    #(
      2,
      4,
      0,
      Ok(Some(Row(..kick_row, order: area.Furthest))),
      "Furthest builds with the row's range, arc and count unchanged",
    ),
    #(
      3,
      4,
      0,
      Ok(Some(Row(..kick_row, order: area.Random))),
      "Random builds with the row's range, arc and count unchanged",
    ),
    #(4, 1, 0, Ok(None), "LowestAbsoluteHealth is read as no area"),
    #(5, 1, 0, Ok(None), "MissingMostHealth is read as no area"),
    #(
      5,
      1,
      16,
      Error(ValidTargetsNotAlive(spell4_id: 58_591, target_bitmask: 16)),
      "the valid targets of a row read as no area are still refused",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(selection, flags, bitmask, wanted, reason) = case_
    assert kick_built_with(
        selection:,
        effect_target_flags: flags,
        target_bitmask: bitmask,
      )
      == wanted
      as reason
  })
  let assert Error(SelectionNotBuilt(spell4_id:, target_selection: 0)) =
    kick_built_with(selection: 0, effect_target_flags: 4, target_bitmask: 0)
    as "order 0, None, is no order and is refused for a player"
  assert list.contains([58_591, 70_033, 70_045, 70_054], spell4_id)
    as "the refusal names a spell of row 640: Kick 58591 and Relentless Strikes' stage spells 70033, 70045 and 70054 share it (Spell4.58591.area)"
}

pub fn a_players_phase_that_selects_the_area_by_health_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // A row ordered by health is read as no area, so a phase that selects units from it would
  // strike nobody: refused. A phase aimed at the cast's own target (flag 2) reads no order,
  // so its row builds, which shows the check reads the phase and not the row alone.
  list.each([4, 5], fn(selection) {
    let assert Error(SelectionNeedsHealth(spell4_id:, target_selection:)) =
      kick_built_with(selection:, effect_target_flags: 4, target_bitmask: 0)
      as "Kick's damage aimed at the area selects units by health: refused by name"
    assert target_selection == selection
    assert list.contains([58_591, 70_033, 70_045, 70_054], spell4_id)
      as "the refusal names a spell of row 640"
    assert kick_built_with(
        selection:,
        effect_target_flags: 2,
        target_bitmask: 0,
      )
      == Ok(None)
      as "a phase that strikes only the cast's own target reads no order"
  })
}

pub fn the_clients_rows_hold_collapse_by_furthest_and_the_heals_by_health_and_no_go_of_them_selects_by_health_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let area_of = fn(spell4_id) {
    let assert Ok(found) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
      as "the spell is in the areas of the abilities the orders free"
    found
  }
  let selects_at_any_go = fn(found: spell_area.SpellArea) {
    list.any(
      spell_plan.go_numbers(go_count: spell_area.phase_count(spell: found)),
      fn(phase) {
        let assert Ok(strike) =
          spell_area.phase(spell: found, phase:, spent: None)
          as "the go is one of the spell's"
        strike.selects_area
      },
    )
  }
  // Spell4AoeTargetConstraints 677 (selection 2, 3 units, 0 to 10 m), 660 (5), 661 (5), 637
  // (5) and 638 (1, 5 units, 0 to 25 m, 45 degrees); `table_rows -- Spell4AoeTargetConstraints
  // 677 660 661 637 638`. The texts 320951 ("Pull the 3 furthest foes") and 245146, 361096,
  // 315701 and 315089 name allies for the by-health rows.
  let collapse = area_of(39_372)
  assert option.map(collapse.row, fn(row) {
      #(row.order, row.target_count, row.max_range)
    })
    == Some(#(area.Furthest, 3, 10.0))
    as "Collapse pulls the 3 furthest foes inside 10 m (text 320951)"
  assert selects_at_any_go(collapse)
    as "Collapse's go selects units from its area"
  list.each([36_897, 41_382, 39_223, 39_068], fn(spell4_id) {
    let found = area_of(spell4_id)
    assert found.row == None
      as "a row ordered by health picks allies, which the server does not find, so it is no area"
    assert !selects_at_any_go(found)
      as "no go of a heal ordered by health selects units from the area"
  })
  let damage_child = area_of(39_379)
  assert option.map(damage_child.row, fn(row) {
      #(row.order, row.target_count, row.max_range)
    })
    == Some(#(area.Nearest, 5, 25.0))
    as "Dual Fire's damage child strikes up to 5 foes in its 25 m cone"
  assert selects_at_any_go(damage_child)
    as "Dual Fire's damage child selects its units from the area"
}

pub fn a_spell_ordered_beyond_closest_that_holds_a_proxy_naming_its_spell_in_data_bits01_is_refused_and_a_closest_one_is_not_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  // Restrictor 38279's field 38287 has the Random area row 391 and the Proxy 131274 (dataBits00
  // 0, Snare 77118 in dataBits01, tickTime 500), which the plan does not start: a press would
  // blink and the field would never snare. Nullifier 58868 holds the same Proxy shape (row
  // 141450 naming 77099) on a Closest area row and is planned; the rule widens to it only by
  // a decision, since that would unplan an ability that casts today
  // (`table_rows -- Spell4Effects 131274 141450 -- Spell4AoeTargetConstraints 391 -- Spell4
  // 77118 77099`).
  let assert Ok(restrictor) =
    list.find(left_out, fn(one) { one.spell4_id == 38_279 })
    as "Restrictor stays unplanned"
  let sentence = spell_plan.describe(error: restrictor.error)
  list.each(
    [
      "Proxy effect 131274",
      "Spell4 row 77118 in dataBits01",
      "with no spell in dataBits00",
    ],
    fn(part) {
      assert string.contains(sentence, part)
        as { "Restrictor's refusal names " <> part <> ": " <> sentence }
    },
  )
  let nullifier_abilities =
    dict.values(spell_plan.plans_with_later(tables:))
    |> list.filter(fn(ability) {
      list.any(
        spell_plan.tree(spell: ability, started: fn(_) { True }),
        fn(spell) { spell.spell4_id == Spell4Id(58_868) },
      )
    })
  assert list.length(nullifier_abilities) == 1
    as "the plans hold one ability whose tree holds Nullifier's field 58868"
  assert list.all(nullifier_abilities, fn(ability) {
    !list.any(left_out, fn(one) { one.spell4_id == ability.spell4_id.value })
  })
    as "Nullifier's ability is not listed unplanned"
  let assert Ok(field) =
    spell_area.of_spell(
      areas: spell_area.areas(tables:),
      spell4_id: Spell4Id(58_868),
    )
    as "Nullifier's field is in the areas"
  assert option.map(field.row, fn(row) { row.order }) == Some(area.Nearest)
    as "Nullifier's area row 119 is Closest, so the Proxy rule leaves it planned"
}

pub fn a_shape_8_with_a_box_is_refused_by_name_for_a_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x14054d170 case 8 reads a box of param03 to param05 when its width (param03) or its length (param05)
  // is above 0 (its height, param04, is never tested); the box geometry is not read, so such a row is refused,
  // for a creature as for a player. No listed spell has one.
  let shape_8 = [
    #("damageShapeEnum", Integer(8)),
    #("param00", planted_table.Float(0.0)),
    #("param01", planted_table.Float(5.5)),
    #("param02", planted_table.Float(40.0)),
  ]
  assert roar_shapes_with(edits: shape_8, reading: spell_area.CreatureReading)
    == Ok([
      Placement(
        shape: Cone(inner: 0.0, outer: 5.5, degrees: 40.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ])
    as "a shape 8 with no box is the long cone"
  list.each(["param03", "param05"], fn(column) {
    assert roar_shapes_with(
        edits: [#(column, planted_table.Float(2.0)), ..shape_8],
        reading: spell_area.CreatureReading,
      )
      == Error(ShapeNotBuilt(spell4_id: 55_317, telegraph_id: 7880, shape: 8))
      as "a box width or length refuses the row"
  })
}

/// The effect ids of the damage rows of go `phase` of `spell4_id` in the areas, in order.
fn damage_ids_at(
  areas areas: spell_area.Areas,
  spell4_id spell4_id: Int,
  phase phase: Int,
) -> List(Int) {
  let assert Ok(found) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(spell4_id))
    as "the spell is in the areas of the level-1 abilities"
  let assert Ok(strike) = spell_area.phase(spell: found, phase:, spent: None)
    as "the channel has a go at the pulse"
  list.map(strike.damage, fn(effect) { effect.effect_id.value })
}

pub fn discharge_strikes_its_damage_row_141368_at_each_of_its_three_pulses_and_at_its_first_only_with_spellchannelflags_bit_1_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 58832 (castMethod 1, spellChannelFlags 0, 3 pulses of 410 ms) holds Damage row
  // 141368 (phaseFlags 1, no tickTime); the texts 508497, 575012, 641194 and 641197 say
  // "every 0.41s".
  list.each([0, 1, 2], fn(pulse) {
    assert damage_ids_at(
        areas: spell_tables.fixture_areas(),
        spell4_id: 58_832,
        phase: pulse,
      )
      == [141_368]
      as "Discharge's damage row strikes at every pulse"
  })
  // Synthetic: spellChannelFlags 1 on the real row makes a phaseFlags 1 row name its first
  // pulse alone (`Spell4Effects.phaseFlags.channel`, the pattern of
  // `spell_area_go_test`).
  use tables <- fixture_tables.changed(table: "Spell4", id: 58_832, with: [
    #("spellChannelFlags", Integer(1)),
  ])
  let assert Ok(areas) = spell_area.build(tables:)
    as "the edited fixture builds its areas"
  assert list.map([0, 1, 2], fn(pulse) {
      damage_ids_at(areas:, spell4_id: 58_832, phase: pulse)
    })
    == [[141_368], [], []]
    as "with bit 1 the row strikes at its first pulse only"
}

pub fn blade_dance_strikes_its_five_damage_rows_together_at_each_of_its_five_pulses_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Spell4 33009 (castMethod 1, spellChannelFlags 0, 5 pulses of 500 ms; text 244913 "every
  // 0.5s") holds the damage row 79030 and the tier rows 219327 to 219330, all phaseFlags 1
  // with no tickTime. A cast with no points spent keeps every row (`spend`); the tier a cast
  // takes is chosen by each row's caster prerequisite, which the area does not read.
  let areas = spell_area.areas(tables: client_tables.shared())
  list.each([0, 1, 2, 3, 4], fn(pulse) {
    assert damage_ids_at(areas:, spell4_id: 33_009, phase: pulse)
      == [79_030, 219_327, 219_328, 219_329, 219_330]
      as "every damage row strikes at every pulse"
  })
}
