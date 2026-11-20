//// The hit shapes of five client TelegraphDamage rows of shapes 1, 3, 5 and 6, as
//// `0x14054d170.shapes_1_3_5_6` draws them: the placements `spell_area` must build from
//// each row, and the placements `area` is tested on.
//// - 3852: shape 1, a ring from 3 to 5 m.
//// - 3029: shape 5, a circle to 7 m missing a 90 degree slice, turned 150.
//// - 6957: shape 5, a ring from 4 to 13 m missing a 105 degree slice, turned 180.
//// - 2920: shape 3, a cross of two boxes 2.5 wide and 18 long.
//// - 4664: shape 6, params 1, 17 and 2 placed 4 ahead: the unhalved box.

import genesis_prime/game/area.{type Placement, Box, Cone, Placement}

/// The ids of the rows `placements_of` knows.
pub const row_ids = [3852, 3029, 6957, 2920, 4664]

/// The placements of TelegraphDamage row `row_id` on the caster: the client's drawing,
/// worked by hand from the row's params, turn and offset.
pub fn placements_of(row_id row_id: Int) -> List(Placement) {
  let on_caster = fn(shape, turn_degrees, ahead) {
    Placement(shape:, ahead:, aside: 0.0, turn_degrees:)
  }
  case row_id {
    3852 -> [on_caster(Cone(inner: 3.0, outer: 5.0, degrees: 360.0), 0.0, 0.0)]
    3029 -> [
      on_caster(Cone(inner: 0.0, outer: 7.0, degrees: 270.0), 330.0, 0.0),
    ]
    6957 -> [
      on_caster(Cone(inner: 4.0, outer: 13.0, degrees: 255.0), 360.0, 0.0),
    ]
    2920 -> [
      on_caster(Box(width: 2.5, length: 18.0), 0.0, 0.0),
      on_caster(Box(width: 18.0, length: 2.5), 0.0, 0.0),
    ]
    4664 -> [on_caster(Box(width: 2.0, length: 4.0), 0.0, 4.0)]
    _ -> panic as "a row of shapes 1, 3, 5 or 6 the support holds"
  }
}
