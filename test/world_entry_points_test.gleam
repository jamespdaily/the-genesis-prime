//// The ability points a character is sent on entering the world, and again when the Holocrypt's
//// join re-sends the loadout (`genesis_prime/game/world_entry`,
//// `genesis_prime/game/ability_points`). Expected values come from these places.
//// - `XpPerLevel.abilityPointsPerLevel`: 0 for IDs 1 to 9 and 1 for IDs 10 to 50, so the
////   total of a level is 0 at 3 and 9, 1 at 10, 2 at 11 and 41 at 50 (`table_rows -- XpPerLevel`).
//// - `opcode.0x169`: the points to spend, then the total; a join holds no tier, so they are
////   equal.
//// - `lua.Abilities.UpdateInterfaceMenuAlerts`: the Abilities button reads the points at the
////   handler of 0x025E (CharacterCreated), not on 0x0169's own event, so the message comes
////   before 0x025E and after 0x092C (`opcode.0x25e.entry_order`).

import ability_book_support as book_support
import ability_points_support as support
import cast_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/limited_action_set
import genesis_prime/game/world_entry
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/store
import genesis_prime/table/id.{Spell4BaseId}
import gleam/list
import limited_action_set_support as limited
import owned_test
import world_entry_support

/// A class and level, the tiers its player saved (set, Spell4Base, tier), the AMPs it saved
/// (set, EldanAugmentation id), the (to spend, total) pair its entry sends, the 0x01A3 it sends
/// as (set, ids) in order, and why.
type Entry {
  Entry(
    class_id: Int,
    level: Int,
    tiers: List(#(Int, Int, Int)),
    amps: List(#(Int, Int)),
    points: #(Int, Int),
    amp_lists: List(#(Int, List(Int))),
    why: String,
  )
}

fn entries() -> List(Entry) {
  [
    Entry(1, 3, [], [], #(0, 0), [], "Warrior 3: IDs 1 to 3 give none"),
    Entry(4, 9, [], [], #(0, 0), [], "Medic 9: IDs 1 to 9 give none"),
    Entry(7, 10, [], [], #(1, 1), [], "Spellslinger 10: ID 10 gives the first"),
    Entry(4, 11, [], [], #(2, 2), [], "Medic 11: IDs 10 and 11 give two"),
    Entry(1, 50, [], [], #(41, 41), [], "Warrior 50: IDs 10 to 50 give 41"),
    Entry(
      7,
      10,
      [#(0, 27_638, 2)],
      [],
      #(0, 1),
      [],
      "Spellslinger 10 saved Quick Draw at tier 2, which costs the one point (Spell4 abilityPointCost 1)",
    ),
    Entry(
      7,
      25,
      [#(0, 20_684, 5), #(0, 27_638, 5)],
      [],
      #(0, 16),
      [],
      "Spellslinger 25 saved Charged Shot and Quick Draw at tier 5, 8 points each of the 16",
    ),
    Entry(
      7,
      25,
      [#(0, 20_684, 5), #(0, 20_718, 2), #(0, 27_638, 5)],
      [],
      #(16, 16),
      [],
      "Spellslinger 25 saved 17 points of tiers, over the 16 the level gives: every tier of the set is reset (Jim's rule) and all 16 points are left",
    ),
    Entry(
      5,
      10,
      [],
      [#(0, 770), #(0, 771), #(0, 772), #(0, 863), #(2, 770)],
      #(1, 1),
      [#(0, [770, 771, 772, 863]), #(2, [770])],
      "Stalker 10 saved four AMPs in set 0 and one in set 2: one 0x01A3 for each set that holds AMPs, in set order",
    ),
  ]
}

/// The frames of the entry of this case's player.
fn entry_frames(case_ case_: Entry) -> List(Frame) {
  case case_.tiers, case_.amps {
    [], [] ->
      world_entry_support.entering(class_id: case_.class_id, level: case_.level).0
    tiers, amps -> {
      let assert world_entry.InTheWorld(effects:, ..) =
        world_entry_support.joined_with_action_sets(
          class_id: case_.class_id,
          level: case_.level,
          action_sets: limited.with_rows(slots: [], tiers:, amps:),
          unset: [],
        )
        as "the entry puts the player in the world"
      world_entry_support.frames_of(effects:)
    }
  }
}

pub fn entry_sends_one_0x0169_between_0x092c_and_0x025e_holding_the_levels_points_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(entries(), fn(case_) {
    let frames = entry_frames(case_:)
    assert support.points_in(frames:) == [case_.points] as case_.why
    let ids = cast_support.ids(frames:)
    assert limited.amp_lists_in(frames:) == case_.amp_lists as case_.why
    assert list.window(ids, 4 + list.length(case_.amp_lists))
      |> list.contains(
        list.flatten([
          [0x019B, 0x092C, 0x0169],
          list.map(case_.amp_lists, fn(_) { 0x01A3 }),
          [0x025E],
        ]),
      )
      as {
        case_.why
        <> ": 0x0169 follows 0x092C, the 0x01A3 of each set that holds AMPs follow it, and 0x025E comes last"
      }
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
      let ids = cast_support.ids(frames:)
      assert list.window(ids, 3) |> list.contains([0x019B, 0x092C, 0x0169])
        as { why <> ": 0x0169 follows 0x092C" }
      assert !list.contains(ids, 0x025E)
        as { why <> ": a join sends no 0x025E" }
    },
  )
  // A tier bought in the session is carried by the join: the bars and the tiers are rebuilt
  // from the saved rows, so Quick Draw is at tier 2 in set 0 and the point stays spent.
  let #(_, entered) = world_entry_support.entering(class_id: 7, level: 10)
  let #(spent, _) =
    limited.taken(
      saved: entered.action_sets,
      level: 10,
      body: limited.body_with(
        ids: limited.class_bar,
        set: 0,
        tier_changes: [#(27_638, 2)],
        amp_ids: [],
      ),
    )
  assert limited_action_set.held_tiers(saved: spent, set: 0)
    == [#(Spell4BaseId(27_638), 2)]
    as "the save in the session spent the point of level 10 on Quick Draw"
  let frames =
    world_entry_support.rejoining_from(
      entered: world_entry.Entered(..entered, action_sets: spent),
    )
  assert support.points_in(frames:) == [#(0, 1)]
    as "the join sends the level's point spent"
  assert list.filter(book_support.tiers_in(frames:), fn(entry) {
      entry.tier > 1
    })
    == [
      AbilityTier(spell4_base_id: 27_638, tier: 2, action_set_index: 0),
      AbilityTier(spell4_base_id: 52_215, tier: 2, action_set_index: 0),
    ]
    as "and Quick Draw at tier 2 in set 0 with its alternate 52215, which shows the tier of the ability that names it, and every other ability at tier 1 in each set"
  // AMPs picked in the session are carried by the join the same way: the entry rebuilds them
  // from the saved rows and sends the list of set 0 after the points.
  let #(_, stalker) = world_entry_support.entering(class_id: 5, level: 10)
  let #(picked, _) =
    limited.taken_as(
      class_id: 5,
      saved: stalker.action_sets,
      level: 10,
      body: limited.amps_body(class_id: 5, amp_ids: [770, 771, 772, 863]),
    )
  assert limited.held_amp_ids(saved: picked, set: 0) == [770, 771, 772, 863]
    as "the save in the session picked four AMPs"
  let frames =
    world_entry_support.rejoining_from(
      entered: world_entry.Entered(..stalker, action_sets: picked),
    )
  assert limited.amp_lists_in(frames:) == [#(0, [770, 771, 772, 863])]
    as "the join sends the picked AMPs of set 0"
  assert list.window(cast_support.ids(frames:), 3)
    |> list.contains([0x092C, 0x0169, 0x01A3])
    as "0x01A3 follows 0x0169"
  // The join judges the rows again at the level the session holds: a list that passed at 10
  // passes at 11, whose power is one more, so a rise in the session keeps the picks.
  let frames =
    world_entry_support.rejoining_from(
      entered: world_entry.Entered(
        ..stalker,
        action_sets: picked,
        character: store.Character(..stalker.character, level: 11),
      ),
    )
  assert limited.amp_lists_in(frames:) == [#(0, [770, 771, 772, 863])]
    as "the join at level 11 sends the picks of level 10"
}
