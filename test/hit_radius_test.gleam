//// A unit's hit radius (`genesis_prime/game/hit_radius`), on the client's own rows.
//// Expected values come from these places.
//// - A creature's: Creature2DisplayInfo 26120 (the Scrab Striker's display, creature
////   24054), hitRadius 2.8 (f32 0x40333333), and 26565 (the Virtual Battle Beast's,
////   creature 73464), hitRadius 3.0 (`unit.hit_radius`,
////   `table_rows Creature2DisplayInfo 26120 26565`).

import client_tables
import genesis_prime/game/hit_radius
import genesis_prime/table/creature2_display_info
import genesis_prime/table/id.{Creature2DisplayInfoId}
import owned_test
import unitest

fn display(id id: Int) -> creature2_display_info.Creature2DisplayInfo {
  let assert Ok(row) =
    creature2_display_info.get(
      tables: client_tables.shared(),
      id: Creature2DisplayInfoId(id),
    )
    as "the display row is in the client's table"
  row
}

pub fn a_creatures_radius_is_its_display_rows_hit_radius_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert hit_radius.of_creature(display: display(id: 26_120))
    == 2.799999952316284
    as "Creature2DisplayInfo 26120: hitRadius 2.8"
  assert hit_radius.of_creature(display: display(id: 26_565)) == 3.0
    as "Creature2DisplayInfo 26565: hitRadius 3.0, the Beast's"
}
