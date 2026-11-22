//// The ability points a level rise sends (`genesis_prime/game/connection/experience`,
//// `genesis_prime/game/ability_points`), on the game connection and the client's committed
//// rows. Expected values come from these places.
//// - `XpPerLevel.abilityPointsPerLevel`: 0 for IDs 1 to 9 and 1 for IDs 10 to 50, so the
////   total is 0 up to level 9, 1 at 10, 2 at 11 and 41 at 50 (`table_rows -- XpPerLevel`).
//// - `opcode.0x169`: the points to spend, then the total; the server saves no tier, so
////   they are equal. A rise that leaves the total as it was sends nothing, and a gain over
////   several levels sends one frame, of the last level.
//// - `lua.Abilities.UpdateInterfaceMenuAlerts`, `0x1403d9a60`, `0x14045edd0`: the client's
////   fanfare timer starts when it applies the 0x0938 stat 10 and raises PlayerLevelChange,
////   which re-reads the points 2000 ms later, so 0x0169 follows that 0x0938.
//// - `XpPerLevel.minXpForLevel`: the experience a level starts at, which the saved
////   experience of each case is one short of.
//// - The abilities a rise grants (0x0111, 0x01A0) are the book's own frames
////   (`experience_book_test`); the ids here leave them out, so a row the fixture's SpellLevel
////   gains does not change what this test says about the points.

import ability_book_support as book_support
import ability_points_support as support
import client_tables
import experience_support
import game_connection_support as connection_support
import gleam/list
import owned_test
import unitest

/// A class rising from one level to another: the ids written and the 0x0169 among them.
type Rise {
  Rise(
    class_id: Int,
    from: Int,
    to: Int,
    ids: List(Int),
    points: List(#(Int, Int)),
    why: String,
  )
}

const without_points = [0x01AC, 0x0938, 0x093A]

const with_points = [0x01AC, 0x0938, 0x0169, 0x093A]

fn rises() -> List(Rise) {
  [
    Rise(4, 1, 2, without_points, [], "Medic 1 to 2: both levels hold 0 and 0"),
    Rise(4, 8, 9, without_points, [], "Medic 8 to 9: both levels hold 0 and 0"),
    Rise(
      4,
      9,
      10,
      with_points,
      [#(1, 1)],
      "Medic 9 to 10: ID 10 gives the first",
    ),
    Rise(
      7,
      9,
      10,
      with_points,
      [#(1, 1)],
      "Spellslinger 9 to 10: the class does not change the total",
    ),
    Rise(
      4,
      10,
      11,
      with_points,
      [#(2, 2)],
      "Medic 10 to 11: ID 11 gives one more",
    ),
    Rise(
      4,
      8,
      11,
      with_points,
      [#(2, 2)],
      "Medic 8 to 11: one frame of the last level's total in one gain",
    ),
    Rise(
      4,
      49,
      50,
      with_points,
      [#(41, 41)],
      "Medic 49 to 50: the last of IDs 10 to 50",
    ),
  ]
}

/// The ids without the 0x0111 and 0x01A0 of the abilities a rise grants.
fn without_the_book(ids ids: List(Int)) -> List(Int) {
  list.filter(ids, fn(id) { id != 0x0111 && id != 0x01A0 })
}

pub fn a_level_rise_sends_the_new_total_after_the_level_only_when_the_rise_changes_it_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(rises(), fn(rise) {
    let #(_, taken) =
      book_support.level_up(
        class_id: rise.class_id,
        from: rise.from,
        to: rise.to,
      )
    let frames = book_support.written(taken:)
    assert without_the_book(ids: connection_support.written_ids(taken))
      == rise.ids
      as rise.why
    assert support.points_in(frames:) == rise.points as rise.why
    assert list.map(experience_support.level_writes(taken:), fn(written) {
        written.1
      })
      == [rise.to]
      as "the 0x0938 whose stat 10 is the new level, which the client's fanfare timer starts at"
  })
}

/// A kill of a level 50 creature of the tests' Creature2: XpPerLevel row 50 gives 75000 x
/// 0.25 x 0.2 x 1.4 = 5250 experience at a gap of 4 or more (`experience`'s formula).
const level_50_kill = 50

pub fn a_second_gain_sends_only_the_change_it_makes_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, first) = book_support.level_up(class_id: 4, from: 9, to: 10)
  assert support.points_in(frames: book_support.written(taken: first))
    == [#(1, 1)]
    as "the rise to 10 sends the first point"
  // Level 10 starts at 23860 and level 11 at 32470 (XpPerLevel.minXpForLevel): one kill of
  // 5250 leaves the player at 10 and the second takes it to 11.
  let #(state, same_level) =
    book_support.another_kill(state:, level: level_50_kill)
  assert connection_support.written_ids(same_level) == [0x01AC]
    as "a kill that makes no rise writes only its experience"
  let #(_, second_rise) =
    book_support.another_kill(state:, level: level_50_kill)
  assert connection_support.written_ids(second_rise) == with_points
    as "the rise from 10 to 11 sends its points after the level, though the first rise already did"
  assert support.points_in(frames: book_support.written(taken: second_rise))
    == [#(2, 2)]
    as "the rise compares with the level the last gain left, 10, not the one the player entered at, 9"
}

pub fn a_warrior_rising_to_10_gets_the_points_before_the_ability_the_level_grants_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(_, taken) =
    support.level_up_on(
      tables: client_tables.shared(),
      class_id: 1,
      from: 9,
      to: 10,
    )
  assert connection_support.written_ids(taken)
    == [0x01AC, 0x0938, 0x0169, 0x0111, 0x0111, 0x01A0, 0x093A]
    as "the points follow the level; the two abilities the level-10 rows grant and their book entry follow them"
  let frames = book_support.written(taken:)
  assert support.points_in(frames:) == [#(1, 1)]
    as "XpPerLevel.abilityPointsPerLevel: ID 10 gives the first point"
  assert list.map(book_support.added_in(frames:), fn(added) { added.base })
    == [23_169, 35_526]
    as "SpellLevel 938 (Spell4 38787, base 23169) and 943 (Spell4 54475, base 35526) are the Warrior's rows at level 10"
}
