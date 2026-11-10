//// A faction's level toward another (`genesis_prime/game/faction_level`), as the client
//// works it out: GetFactionLevelTo `0x140787760` over the lineage `0x140717560`, and
//// Hostile as 0 to 2 (`0x140787830`). Expected levels name the client's
//// Faction2Relationship rows. Faction2: 166 (Dominion) and 167 (Exile) have parent 165,
//// 170 and 171 have parent 164.

import character_tables
import fixture_tables
import genesis_prime/game/faction_level
import owned_test
import planted_table.{Integer}

pub fn faction_level_walks_parents_as_the_client_test() -> Nil {
  use <- owned_test.run(10_000)
  let levels = faction_level.of(tables: character_tables.shared())
  let level = fn(from, to) { faction_level.level(levels:, from:, to:) }
  // Rows 771 (167, 171) and 770 (166, 170): level 10.
  assert level(167, 171) == 10
  assert level(166, 170) == 10
  assert !faction_level.hostile(levels:, from: 167, to: 171)
  assert !faction_level.hostile(levels:, from: 166, to: 170)
  // Rows 686 (167, 170) and 685 (166, 171): level 0, which is Hostile.
  assert level(167, 170) == 0
  assert level(166, 171) == 0
  assert faction_level.hostile(levels:, from: 167, to: 170)
  assert faction_level.hostile(levels:, from: 166, to: 171)
  // A relationship is filed under both orders: row 771 is also (171, 167).
  assert level(171, 167) == 10
  // Rows 2943 (1441, 167) level 0 and 2944 (1441, 166) level 10.
  assert level(167, 1441) == 0
  assert level(166, 1441) == 10
  // No row relates 167 or its parent to 174: level 5. A faction toward itself with no
  // row is 10.
  assert level(167, 174) == 5
  assert level(174, 174) == 10
  assert !faction_level.hostile(levels:, from: 167, to: 174)
  // The client's parent chain stops at a faction it has met: 165 given parent 166
  // (whose parent is 165) is a cycle, and the levels still come from the same rows.
  use cyclic <- fixture_tables.changed(table: "Faction2", id: 165, with: [
    #("faction2IdParent", Integer(166)),
  ])
  let walked = faction_level.of(tables: cyclic)
  assert faction_level.level(levels: walked, from: 167, to: 171) == 10
  assert faction_level.level(levels: walked, from: 167, to: 170) == 0
}
