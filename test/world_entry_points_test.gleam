//// The ability points a character is sent on entering the world, and again when the Holocrypt's
//// join re-sends the loadout (`genesis_prime/game/world_entry`,
//// `genesis_prime/game/ability_points`). Expected values come from these places.
//// - `XpPerLevel.abilityPointsPerLevel`: 0 for IDs 1 to 9 and 1 for IDs 10 to 50, so the
////   total of a level is 0 at 3 and 9, 1 at 10, 2 at 11 and 41 at 50 (`table_rows -- XpPerLevel`).
//// - `opcode.0x169`: the points to spend, then the total; the server saves no tier, so they
////   are equal.
//// - `lua.Abilities.UpdateInterfaceMenuAlerts`: the Abilities button reads the points at the
////   handler of 0x025E (CharacterCreated), not on 0x0169's own event, so the message comes
////   before 0x025E and after 0x092C (`opcode.0x25e.entry_order`).

import ability_points_support as support
import gleam/list
import owned_test
import world_entry_support

/// A class and level, the (to spend, total) pair its entry sends, and why.
type Entry {
  Entry(class_id: Int, level: Int, points: #(Int, Int), why: String)
}

fn entries() -> List(Entry) {
  [
    Entry(1, 3, #(0, 0), "Warrior 3: IDs 1 to 3 give none"),
    Entry(4, 9, #(0, 0), "Medic 9: IDs 1 to 9 give none"),
    Entry(7, 10, #(1, 1), "Spellslinger 10: ID 10 gives the first"),
    Entry(4, 11, #(2, 2), "Medic 11: IDs 10 and 11 give two"),
    Entry(1, 50, #(41, 41), "Warrior 50: IDs 10 to 50 give 41"),
  ]
}

pub fn entry_sends_one_0x0169_between_0x092c_and_0x025e_holding_the_levels_points_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(entries(), fn(case_) {
    let #(frames, _) =
      world_entry_support.entering(class_id: case_.class_id, level: case_.level)
    assert support.points_in(frames:) == [case_.points] as case_.why
    let ids = support.ids_of(frames:)
    assert list.window(ids, 4)
      |> list.contains([0x019B, 0x092C, 0x0169, 0x025E])
      as { case_.why <> ": 0x0169 follows 0x092C and comes before 0x025E" }
    assert list.take_while(ids, fn(id) { id != 0x01A0 })
      |> list.contains(0x0169)
      as { case_.why <> ": it comes before the entry's 0x01A0" }
  })
}

pub fn a_rejoin_sends_the_points_of_the_level_the_session_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Holocrypt's join re-sends the loadout (the world_entry module doc), and with the
  // entry's frames the points of the level the session holds; it is a join, not a play, so
  // no 0x025E follows.
  list.each(
    [
      #(9, 10, #(1, 1), "Medic 9 rose to 10 in the session"),
      #(3, 4, #(0, 0), "Medic 3 rose to 4 in the session"),
    ],
    fn(case_) {
      let #(entered_at, risen_to, points, why) = case_
      let frames =
        world_entry_support.rejoining(class_id: 4, entered_at:, risen_to:)
      assert support.points_in(frames:) == [points] as why
      let ids = support.ids_of(frames:)
      assert list.window(ids, 3) |> list.contains([0x019B, 0x092C, 0x0169])
        as { why <> ": 0x0169 follows 0x092C" }
      assert !list.contains(ids, 0x025E)
        as { why <> ": a join sends no 0x025E" }
    },
  )
}
