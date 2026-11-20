//// The hit shapes of a creature's cast at each of its gos (`genesis_prime/game/spell_area`
//// `hit_shapes_by_go`), on the client's committed rows. Expected values come from these places.
//// - `cast.multiphase_telegraph_rows` and Jim: a go strikes with the hit rows its phase names
////   (`TelegraphDamage.phaseFlags`: bit n is go n, -1 every go) that the client is drawing at the
////   go's time (`TelegraphDamage.telegraphTimeStartMs`); a named row not drawn strikes nobody; a
////   hit twin (flag 0x40) is never drawn, so it is read by its phase alone, a marked guess.
//// - The rows and go times, by `table_rows -- TelegraphDamage N`, `-- Spell4Telegraph spell4Id=N`
////   and `-- SpellPhase spell4IdOwner=N`; the shapes are the client's drawing
////   (`0x14054d170`): shape 4 a cone of param01 over param02 degrees from param00, shape 6 a box
////   twice param00 wide and param02 long, shape 0 a circle of param00, shape 7 a rectangle of
////   param00 by param02, shape 2 a box of param00 by param02.

import fixture_tables
import genesis_prime/game/area.{
  type Inside, type Placement, Box, Circle, Cone, InsideRow, InsideShapes,
  Placement, Rectangle,
}
import genesis_prime/game/spell_area
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import planted_table.{Integer}

/// The hit shapes of the spell at each of its gos, over these tables.
fn shapes_by_go(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  go_times_ms go_times_ms: List(Int),
) -> Result(List(Option(Inside)), spell_area.AreaError) {
  spell_area.hit_shapes_by_go(
    tables:,
    spell4_id: Spell4Id(spell4_id),
    go_times_ms:,
  )
}

/// A cone from `inner` to `outer` metres over `degrees`, `ahead` of the caster, turned `turn`
/// degrees.
fn cone(
  inner inner: Float,
  outer outer: Float,
  degrees degrees: Float,
  ahead ahead: Float,
  turn turn: Float,
) -> Placement {
  Placement(
    shape: Cone(inner:, outer:, degrees:),
    ahead:,
    aside: 0.0,
    turn_degrees: turn,
  )
}

/// A shape placed `ahead` of the caster, not turned.
fn placed(shape: area.Shape, ahead: Float) -> Placement {
  Placement(shape:, ahead:, aside: 0.0, turn_degrees: 0.0)
}

fn drawn(placements: List(Placement)) -> Option(Inside) {
  Some(InsideShapes(placements:))
}

pub fn a_cast_strikes_at_each_go_with_the_hit_rows_its_phase_names_and_the_client_is_drawing_test() -> Nil {
  use <- owned_test.run(60_000)
  let ice_cone = fn(turn) {
    cone(inner: 0.0, outer: 5.5, degrees: 20.0, ahead: 0.0, turn:)
  }
  let claw = drawn([placed(Rectangle(width: 3.0, length: 6.0), 0.0)])
  let twin = fn(ahead) { drawn([placed(Box(width: 4.0, length: 4.0), ahead)]) }
  let cone_45746 = fn(turn) {
    cone(inner: 5.0, outer: 7.0, degrees: 80.0, ahead: 0.0, turn:)
  }
  // Each case: why, the spell, its go times and, for each go, the shapes or none.
  [
    #(
      "Ice Breath: row 7956 names go 1 and row 7957 go 2, a 20 degree cone turned +10 and -10",
      55_635,
      [2600, 3000, 3500, 3800],
      [None, drawn([ice_cone(10.0)]), drawn([ice_cone(-10.0)]), None],
    ),
    #(
      "Claw Slam: row 7877 names every go and is drawn from the 0x7ff to the finish",
      55_632,
      [2900, 3300],
      [claw, claw],
    ),
    #(
      "45951: row 4664 (shape 6, 1 and 2, 4 ahead) names go 1 and row 4665 (a circle of 4) go 3",
      45_951,
      [200, 1000, 1200, 1800],
      [
        None,
        drawn([placed(Box(width: 2.0, length: 4.0), 4.0)]),
        None,
        drawn([placed(Circle(radius: 4.0), 0.0)]),
      ],
    ),
    #(
      "34286: row 344 (displayFlags 4) names every go and goes at the first, row 14534 (from 2,000 ms, displayFlags 8) names every go but the first: one cone at each go",
      34_286,
      [2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500],
      list.repeat(
        drawn([
          cone(inner: 3.0, outer: 15.0, degrees: 30.0, ahead: -1.0, turn: 0.0),
        ]),
        times: 8,
      ),
    ),
    #(
      "47033: go 2 names 5009 and 5010, which ended 50 ms before it, and 11144, which ends at it",
      47_033,
      [1500, 2500, 2750, 3200],
      [
        drawn([
          cone(inner: 2.5, outer: 6.0, degrees: 120.0, ahead: -4.0, turn: 0.0),
          cone(inner: 2.0, outer: 20.0, degrees: 4.0, ahead: 0.0, turn: 0.0),
          cone(inner: 2.0, outer: 20.0, degrees: 4.0, ahead: 0.0, turn: 60.0),
          cone(inner: 2.0, outer: 20.0, degrees: 4.0, ahead: 0.0, turn: -60.0),
        ]),
        None,
        drawn([
          cone(inner: 2.5, outer: 6.0, degrees: 120.0, ahead: -4.0, turn: 0.0),
        ]),
        None,
      ],
    ),
    #(
      "45746: go 1 row 4526, go 2 rows 4527, 4528 and 4532, go 3 rows 4529 to 4531",
      45_746,
      [1400, 2600, 3600, 4600],
      [
        None,
        drawn([placed(Circle(radius: 2.0), 0.0)]),
        drawn([
          cone_45746(0.0),
          cone_45746(240.0),
          cone_45746(120.0),
        ]),
        drawn([
          cone(inner: 9.0, outer: 11.0, degrees: 80.0, ahead: 0.0, turn: 330.0),
          cone(inner: 9.0, outer: 11.0, degrees: 80.0, ahead: 0.0, turn: 90.0),
          cone(inner: 9.0, outer: 11.0, degrees: 80.0, ahead: 0.0, turn: 210.0),
        ]),
      ],
    ),
    #(
      "39943: the hit shapes are the never-drawn twins 10908 to 10911, each by its phase alone; the drawn picture row 10912 is left out",
      39_943,
      [500, 1500, 1600, 1650, 1700],
      [None, twin(5.0), twin(9.0), twin(13.0), twin(17.0)],
    ),
    #(
      "54339: row 4310 (a circle of 3.5) ends at 3,000 ms, so go 4 at 4,500 names it and it has gone; go 5 names no row",
      54_339,
      [500, 1000, 1500, 2000, 4500, 5000],
      [
        drawn([placed(Circle(radius: 3.5), 0.0)]),
        drawn([placed(Circle(radius: 3.5), 0.0)]),
        drawn([placed(Circle(radius: 3.5), 0.0)]),
        drawn([placed(Circle(radius: 3.5), 0.0)]),
        None,
        None,
      ],
    ),
    #(
      "63569 has no telegraph row: its one go is read by the area row",
      63_569,
      [160],
      [Some(InsideRow)],
    ),
  ]
  |> list.each(fn(found) {
    let #(reason, spell4_id, go_times_ms, expected) = found
    assert shapes_by_go(
        tables: fixture_tables.shared(),
        spell4_id:,
        go_times_ms:,
      )
      == Ok(expected)
      as reason
  })
}

pub fn a_channel_compares_a_hit_rows_phase_only_when_its_channel_flags_have_bit_1_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 31546 is a channel of nine pulses (channelPulseTime 500, spellChannelFlags 0). Its one
  // hit row, 2151, names pulse 0 alone (phaseFlags 1), has no end and displayFlags 14, so the
  // client draws it through every pulse, comparing its phase only for a Multiphase cast or a
  // channel whose spellChannelFlags has bit 1 (`opcode.0x7f4.phase`, `0x1405458e0`).
  let go_times_ms = [500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500]
  let circle = drawn([placed(Circle(radius: 3.0), 0.0)])
  assert shapes_by_go(
      tables: fixture_tables.shared(),
      spell4_id: 31_546,
      go_times_ms:,
    )
    == Ok(list.repeat(circle, times: 9))
    as "a channel with flags 0 strikes with the row at every pulse"
  // Synthetic: spellChannelFlags 1 on the real row makes the client compare the phase.
  use tables <- fixture_tables.changed(table: "Spell4", id: 31_546, with: [
    #("spellChannelFlags", Integer(1)),
  ])
  assert shapes_by_go(tables:, spell4_id: 31_546, go_times_ms:)
    == Ok([circle, ..list.repeat(None, times: 8)])
    as "a channel with bit 1 strikes with the row at the pulse its phase names"
}

pub fn a_hit_row_timed_from_a_go_is_refused_and_a_named_row_not_drawn_leaves_the_go_with_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let go_times_ms = [2600, 3000, 3500, 3800]
  // Synthetic: no client row among the 63 specials that strike at several gos has flag 0x2000
  // (the only one, row 78, is a never-drawn twin), so row 7957's telegraphDamageFlags (0x101000)
  // gains 0x2000. The client times such a row from a go
  // (`TelegraphDamage.telegraphDamageFlags.0x2000`), which the load does not read.
  {
    use tables <- fixture_tables.changed(
      table: "TelegraphDamage",
      id: 7957,
      with: [#("telegraphDamageFlags", Integer(0x103000))],
    )
    assert shapes_by_go(tables:, spell4_id: 55_635, go_times_ms:)
      == Error(spell_area.TelegraphTimedFromAGo(
        spell4_id: 55_635,
        telegraph_id: 7957,
      ))
      as "the refusal names the spell and the row"
  }
  // Synthetic: row 7957 ends at 3,800 ms, and at 3,400 it has gone when go 2 falls at 3,500,
  // though its phase names go 2. Jim: a named row not drawn at the go strikes nobody.
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 7957,
    with: [#("telegraphTimeEndMs", Integer(3400))],
  )
  let assert Ok([_, go_1, go_2, _]) =
    shapes_by_go(tables:, spell4_id: 55_635, go_times_ms:)
    as "the changed row still reads"
  assert go_2 == None as "go 2 names only row 7957, which has gone"
  assert go_1
    == drawn([
      cone(inner: 0.0, outer: 5.5, degrees: 20.0, ahead: 0.0, turn: 10.0),
    ])
    as "go 1 still strikes with row 7956"
}
