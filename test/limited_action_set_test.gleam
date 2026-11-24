//// The ability builder's save (`genesis_prime/game/limited_action_set`): which slots open at
//// which level, what a save is accepted or refused for, and the frames that answer it.
//// Expected values come from these places.
//// - `ActionSlotPrereq.prerequisiteIdUnlock`: slots 0, 1 and 2 open at level 1, slot 3 at 4,
////   slot 4 at 5, slot 5 at 7, slot 6 at 9 and slot 7 at 10 (the same levels as the
////   LevelUpUnlock rows 28 to 34); slot 8 (type 178), slot 9 (types 177 and 91) and slots 10
////   and 11 (level 100) open at no level 1 to 50. `table_rows ActionSlotPrereq` and
////   `table_rows Prerequisite 8235 22215 8236 8237 8238 8239 8240 8241 8243 8242 8244 8245`.
//// - `Prerequisite.prerequisiteTypeId.177`, `0x1404a5190` (the conditions the client keeps end
////   at the first of type 0), `0x1404a2090` (the comparison): a slot opens when every kept
////   condition holds at the unit's level.
//// - `lua.ActionSetLib.CodeEnumLimitedActionSetResult`: the result numbers. The client makes 25,
////   27 and 30 itself (`0x1407580e0`) and never sends them; 2, 13, 18 and 40 are the server's
////   mapping, which no client text shows.
//// - `opcode.0x19d`: a shortcut of type 4 names an ability by its Spell4Base id, type 0 empties
////   the slot it names, a result other than 1 raises ActionSetError, the bag index is the slot.
//// - `opcode.0xb2`: the answer's bit; the client only adds a combat log line for it.
//// - The sitting's saves (`limited_action_set_support.save_a` and the others): a Spellslinger of
////   level 4 placing its level 4 ability in slot 3.

import ability_book_support
import ability_points_support
import client_tables
import fixture_tables
import genesis_prime/game/ability_book
import genesis_prime/game/ability_book_frame
import genesis_prime/game/ability_points
import genesis_prime/game/limited_action_set.{
  Player, RowOutsideTable, RowRepeated,
}
import genesis_prime/game/loadout
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_tier
import genesis_prime/message/ability_tier
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/step.{LogDebug, LogWarning}
import genesis_prime/store.{ActionSets}
import genesis_prime/table/action_slot_prereq
import genesis_prime/table/character_creation
import genesis_prime/table/id.{ClassId, PrerequisiteId, Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4_base
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import limited_action_set_support as support
import message_support
import owned_test
import planted_table.{Integer}
import qcheck
import unitest

/// The slots 0 to 7 and the level each opens at (`ActionSlotPrereq.prerequisiteIdUnlock`).
const opening_levels = [
  #(0, 1),
  #(1, 1),
  #(2, 1),
  #(3, 4),
  #(4, 5),
  #(5, 7),
  #(6, 9),
  #(7, 10),
]

pub fn the_slots_open_at_the_levels_the_client_tables_give_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let unlocks = limited_action_set.unlocks(tables:)
  list.each(support.levels(from: 1, to: 50), fn(level) {
    let expected =
      list.filter_map(opening_levels, fn(slot) {
        case level >= slot.1 {
          True -> Ok(slot.0)
          False -> Error(Nil)
        }
      })
    assert limited_action_set.open_slots(unlocks:, level:) == expected
      as {
        "level "
        <> int.to_string(level)
        <> ": slots 0 to 7 open at their levels, slot 8 (type 178), slot 9 (types 177 and 91) and slots 10 and 11 (level 100) at none"
      }
  })
  // The real rows keep one condition and hold type 0 in the next two, so the cut at the
  // first type 0 is what the slots 0 to 7 are read through.
  let opened =
    list.filter(action_slot_prereq.all(tables), fn(slot) {
      list.any(opening_levels, fn(opening) { opening.0 == slot.slot_index })
    })
  assert list.map(opened, fn(slot) { slot.slot_index })
    == list.map(opening_levels, fn(opening) { opening.0 })
    as "ActionSlotPrereq holds one row for each of the slots 0 to 7"
  list.each(opened, fn(slot) {
    let row_id = slot.prerequisite_id_unlock
    let assert Ok(row) =
      prerequisite_table.get(tables:, id: PrerequisiteId(row_id))
      as "the table holds the slot's prerequisite"
    assert row.prerequisite_type_id1 == 0 && row.prerequisite_type_id2 == 0
      as {
        "Prerequisite "
        <> int.to_string(row_id)
        <> " holds type 0 after its first condition"
      }
    assert prerequisite.condition_types(row:) == [177]
      as {
        "Prerequisite "
        <> int.to_string(row_id)
        <> " of slot "
        <> int.to_string(slot.slot_index)
        <> " keeps one condition, of type 177"
      }
  })
}

/// The tables with a Prerequisite row `9000001` as the unlock of slot 3 (ActionSlotPrereq row 4),
/// a copy of Prerequisite 8237 (type 177, comparison 4, value 4) with these cells changed; no
/// client row holds these shapes, so each case builds its own.
fn slot_3_opens_by(
  changes: List(#(String, planted_table.Cell)),
) -> Result(table_store.Tables, table_store.LoadError) {
  let assert Ok(rows) =
    fixture_tables.add(
      rows: fixture_tables.rows(),
      table: "Prerequisite",
      copy_of: 8237,
      id: 9_000_001,
      with: changes,
    )
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "ActionSlotPrereq", id: 4, with: [
      #("prerequisiteIdUnlock", Integer(9_000_001)),
    ])
  fixture_tables.load(rows:)
}

fn levels_slot_3_is_open_at(tables tables: table_store.Tables) -> List(Int) {
  let unlocks = limited_action_set.unlocks(tables:)
  list.filter(support.levels(from: 1, to: 12), fn(level) {
    list.contains(limited_action_set.open_slots(unlocks:, level:), 3)
  })
}

pub fn a_slot_row_the_rule_does_not_read_never_opens_and_a_missing_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(120_000)
  // (the row's changed cells, the levels 1 to 12 at which slot 3 opens, why)
  list.each(
    [
      #(
        [],
        [4, 5, 6, 7, 8, 9, 10, 11, 12],
        "type 177, comparison 4, value 4, as the client holds it",
      ),
      #(
        [#("prerequisiteTypeId2", Integer(91))],
        [4, 5, 6, 7, 8, 9, 10, 11, 12],
        "a type 91 condition after the first type 0 is cut by the client's reader and never read",
      ),
      #(
        [#("prerequisiteTypeId1", Integer(91))],
        [],
        "a type 91 condition before the cut is a condition the rule does not read",
      ),
      #(
        [#("flags", Integer(1))],
        [],
        "the OR flag: any one condition is enough, which the rule does not read",
      ),
      #(
        [#("prerequisiteComparisonId0", Integer(5)), #("value0", Integer(3))],
        [1, 2],
        "the relation is read, not assumed: less than 3 opens at levels 1 and 2",
      ),
    ],
    fn(case_) {
      let #(changes, expected, why) = case_
      let assert Ok(tables) = slot_3_opens_by(changes) as why
      assert levels_slot_3_is_open_at(tables:) == expected as why
    },
  )
  // A missing row fails the load and names the row.
  let assert Ok(without_slot_5) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "ActionSlotPrereq",
      id: 6,
    )
  let assert Error(error) = fixture_tables.load(rows: without_slot_5)
    as "a bar with no row for slot 5 does not load"
  assert string.contains(table_store.describe(error), "no row for slot 5")
    as "the load names the slot"
  let assert Ok(without_8237) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "Prerequisite",
      id: 8237,
    )
  let assert Error(error) = fixture_tables.load(rows: without_8237)
    as "slot 3's Prerequisite row is missing"
  assert string.contains(table_store.describe(error), "Prerequisite 8237")
    as "the load names the missing Prerequisite row"
  let assert Ok(slot_2_twice) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "ActionSlotPrereq",
      id: 4,
      with: [#("slotIndex", Integer(2))],
    )
  let assert Error(error) = fixture_tables.load(rows: slot_2_twice)
    as "two rows for slot 2 do not load"
  assert string.contains(table_store.describe(error), "slot 2")
    as "the load names the slot"
  let assert Ok(slot_12) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "ActionSlotPrereq",
      id: 12,
      with: [#("slotIndex", Integer(12))],
    )
  let assert Error(error) = fixture_tables.load(rows: slot_12)
    as "a row for slot 12 does not load: the client's own load refuses more than 12 slots"
  assert string.contains(table_store.describe(error), "names slot 12")
    as "the load names the slot"
}

/// Quick Draw, Charged Shot (and its alternate), Ignite and the Spellslinger's innate: the
/// Spell4Base ids of the tier rows the tests spend points on (`table_rows -- Spell4
/// spell4BaseIdBaseSpell=27638`, 20684, 20685, 20718, and Class 7's first innate, Spell4
/// 47273).
const quick_draw = 27_638

const charged_shot = 20_684

const charged_shot_alternate = 20_685

const ignite = 20_718

const spellslinger_innate = 31_213

/// A Medic's level 1 ability whose Spell4 rows hold tiers 1 and 9 only (`table_rows -- Spell4
/// spell4BaseIdBaseSpell=26543`: 42352 and 51989).
const base_with_a_missing_tier = 26_543

/// The sitting's first bar with these tier changes, set 0.
fn tiering(changes changes: List(#(Int, Int))) -> BitArray {
  support.body_with(
    ids: support.ids_a,
    set: 0,
    tier_changes: changes,
    amp_ids: [],
  )
}

/// A row of the accepted table: the level, the bodies sent in turn from no saved set, the
/// ids the bar holds after them, the tiers above 1 the set holds (Spell4Base, tier) and the
/// 0x0169 (points to spend, total) the last answer holds.
type Accepted {
  Accepted(
    level: Int,
    bodies: List(BitArray),
    expected: List(Int),
    tiers: List(#(Int, Int)),
    points: #(Int, Int),
    why: String,
  )
}

pub fn a_save_the_stock_builder_sends_is_accepted_and_becomes_the_set_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let zeros = list.repeat(0, 12)
  list.each(
    [
      Accepted(
        10,
        [tiering([#(quick_draw, 2)])],
        support.ids_a,
        [#(quick_draw, 2)],
        #(0, 1),
        "level 10 gives 1 point: Quick Draw to tier 2 costs 1",
      ),
      Accepted(
        25,
        [tiering([#(quick_draw, 5), #(ignite, 3)])],
        support.ids_a,
        [#(ignite, 3), #(quick_draw, 5)],
        #(6, 16),
        "level 25 gives 16 points: Quick Draw to tier 5 costs 8 and Ignite to tier 3 costs 2",
      ),
      Accepted(
        15,
        [tiering([#(quick_draw, 3)])],
        support.ids_a,
        [#(quick_draw, 3)],
        #(4, 6),
        "tier 3 needs level 15 and costs 2 of the 6 points",
      ),
      Accepted(
        25,
        [
          tiering([#(quick_draw, 5), #(charged_shot, 5)]),
          tiering([#(quick_draw, 1), #(ignite, 5)]),
        ],
        support.ids_a,
        [#(charged_shot, 5), #(ignite, 5)],
        #(0, 16),
        "16 of 16 points spent, then Quick Draw falls to tier 1 and Ignite rises to tier 5 in one save: judged on the tiers the save leaves",
      ),
      Accepted(
        10,
        [tiering([#(quick_draw, 2)]), tiering([#(quick_draw, 2)])],
        support.ids_a,
        [#(quick_draw, 2)],
        #(0, 1),
        "the tier it already holds changes nothing",
      ),
      Accepted(
        10,
        [
          tiering([#(quick_draw, 2)]),
          support.body(
            ids: [0, 20_684, 20_325, 20_718, 0, 0, 0, 0, 0, 0, 0, 0],
            set: 0,
          ),
        ],
        [0, 20_684, 20_325, 20_718, 0, 0, 0, 0, 0, 0, 0, 0],
        [#(quick_draw, 2)],
        #(0, 1),
        "a save that takes Quick Draw off the bar and carries no tier change keeps its tier and its point spent: a tier belongs to the ability in the set",
      ),
      Accepted(
        15,
        [tiering([#(charged_shot_alternate, 3)])],
        support.ids_a,
        [#(charged_shot_alternate, 3)],
        #(6, 6),
        "Charged Shot's alternate costs 0 at every tier (Spell4 abilityPointCost): tier 3 is bought and no point is spent",
      ),
      Accepted(
        4,
        [message_support.hex(support.save_a)],
        support.ids_a,
        [],
        #(0, 0),
        "the sitting's save, sequence 16176",
      ),
      Accepted(
        4,
        [
          message_support.hex(support.save_a),
          message_support.hex(support.save_b),
        ],
        support.ids_b,
        [],
        #(0, 0),
        "a swap and a removal of the set of the first save, sequence 16317",
      ),
      Accepted(
        4,
        [
          message_support.hex(support.save_a),
          message_support.hex(support.save_b),
          message_support.hex(support.save_c),
        ],
        support.ids_c,
        [],
        #(0, 0),
        "one removed, sequence 16356",
      ),
      Accepted(
        4,
        [message_support.hex(support.save_a), support.body(ids: zeros, set: 0)],
        zeros,
        [],
        #(0, 0),
        "all twelve empty is a saved set of nothing, not no set",
      ),
      Accepted(
        10,
        [
          support.body(
            ids: [27_638, 20_684, 20_325, 0, 0, 0, 0, 23_012, 0, 0, 0, 0],
            set: 0,
          ),
        ],
        [27_638, 20_684, 20_325, 0, 0, 0, 0, 23_012, 0, 0, 0, 0],
        [],
        #(1, 1),
        "a level 6 ability in slot 7 (the committed rows hold no level 10 ability), which opens at level 10",
      ),
      Accepted(
        4,
        [
          support.body(
            ids: [52_215, 20_684, 20_325, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            set: 0,
          ),
        ],
        [52_215, 20_684, 20_325, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [],
        #(0, 0),
        "an alternate in the book is accepted: the client's book holds alternates",
      ),
    ],
    fn(case_) {
      let Accepted(level:, bodies:, expected:, tiers:, points:, why:) = case_
      let #(saved, last) =
        list.fold(bodies, #(limited_action_set.none(), []), fn(held, body) {
          let #(saved, effects) = support.taken(saved: held.0, level:, body:)
          assert support.the_action_set(frames: support.frames_of(effects:)).result
            == 1
            as { why <> ": every save of the row is accepted" }
          #(saved, effects)
        })
      assert support.held_ids(tables:, saved:) == expected as why
      assert limited_action_set.held_tiers(saved:, set: 0)
        == list.map(tiers, fn(held) { #(Spell4BaseId(held.0), held.1) })
        as { why <> ": the tiers above 1 the set holds" }
      assert ability_points_support.points_in(frames: support.frames_of(
          effects: last,
        ))
        == [points]
        as { why <> ": the points to spend and the total, opcode.0x169" }
    },
  )
  // The same body twice gives the same set and the same frames.
  let #(once, first) =
    support.taken(
      saved: limited_action_set.none(),
      level: 4,
      body: message_support.hex(support.save_a),
    )
  let #(twice, second) =
    support.taken(
      saved: once,
      level: 4,
      body: message_support.hex(support.save_a),
    )
  assert support.held_ids(tables:, saved: twice)
    == support.held_ids(tables:, saved: once)
    as "a save of the held bar changes nothing"
  assert support.frames_of(effects: second) == support.frames_of(effects: first)
    as "and answers the same frames"
}

/// A refusal: the level, who the player is, the body and the result the client's name for the
/// check carries.
type Refused {
  Refused(
    level: Int,
    dead: Bool,
    in_combat: Bool,
    body: BitArray,
    result: Int,
    why: String,
  )
}

/// The ids of the sitting's first save with one slot changed.
fn a_with(slot slot: Int, id id: Int) -> List(Int) {
  list.index_map(support.ids_a, fn(held, at) {
    case at == slot {
      True -> id
      False -> held
    }
  })
}

pub fn a_save_the_server_refuses_gets_the_clients_result_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let refuse = fn(why, ids, result) {
    Refused(4, False, False, support.body(ids:, set: 0), result, why)
  }
  let refuse_tiers = fn(why, level, changes, result) {
    Refused(level, False, False, tiering(changes), result, why)
  }
  list.each(
    [
      refuse_tiers(
        "tier 0 is no tier of any ability",
        10,
        [#(quick_draw, 0)],
        41,
      ),
      refuse_tiers(
        "tier 10 is above the highest: the client's writer drops it",
        50,
        [#(quick_draw, 10)],
        41,
      ),
      refuse_tiers(
        "tier 2 of an innate whose base holds one tier",
        10,
        [#(spellslinger_innate, 2)],
        41,
      ),
      refuse_tiers(
        "tier 5 of a base whose Spell4 rows hold tiers 1 and 9 only: a tier with no row cannot be bought",
        25,
        [#(base_with_a_missing_tier, 5)],
        41,
      ),
      refuse_tiers("tier 3 needs level 15", 14, [#(quick_draw, 3)], 41),
      refuse_tiers(
        "tier 3 at level 10: the level check comes before the points check, so 41 and not 42",
        10,
        [#(quick_draw, 3)],
        41,
      ),
      refuse_tiers("tier 2 needs level 10", 9, [#(quick_draw, 2)], 41),
      refuse_tiers("tier 4 needs level 20", 15, [#(quick_draw, 4)], 41),
      refuse_tiers(
        "two abilities to tier 2 cost 2 points and level 10 has 1",
        10,
        [#(quick_draw, 2), #(ignite, 2)],
        42,
      ),
      refuse_tiers(
        "an ability the book does not hold (a Medic's, Spell4Base 26038)",
        10,
        [#(26_038, 2)],
        18,
      ),
      refuse_tiers(
        "an ability twice",
        10,
        [#(quick_draw, 2), #(quick_draw, 2)],
        13,
      ),
      Refused(
        10,
        False,
        False,
        support.body_with(
          ids: [20_684, 20_684, 20_325, 20_718, 0, 0, 0, 0, 0, 0, 0, 0],
          set: 0,
          tier_changes: [#(quick_draw, 2)],
          amp_ids: [],
        ),
        13,
        "a good tier change in a save whose bar repeats an id: the bar's result, and the tier not applied",
      ),
      Refused(
        10,
        False,
        False,
        support.body_with(
          ids: support.ids_b,
          set: 0,
          tier_changes: [#(quick_draw, 0)],
          amp_ids: [],
        ),
        41,
        "a good bar with a bad tier: the bar is not applied either",
      ),
      refuse(
        "20718 in slot 4, which opens at level 5",
        a_with(slot: 4, id: 20_718),
        2,
      ),
      refuse(
        "20718 in slot 7, which opens at level 10",
        a_with(slot: 7, id: 20_718),
        2,
      ),
      refuse(
        "an ability of level 6 the level 4 book lacks",
        a_with(slot: 0, id: 23_012),
        18,
      ),
      refuse(
        "a Medic ability (Spell4Base 26038)",
        a_with(slot: 0, id: 26_038),
        18,
      ),
      refuse("an id no row has", a_with(slot: 0, id: 99_999_999), 18),
      refuse("an id above 18 bits", a_with(slot: 0, id: 262_144), 18),
      refuse("an ability in the gadget slot", a_with(slot: 8, id: 20_684), 18),
      refuse("an ability in the path slot", a_with(slot: 9, id: 20_684), 18),
      refuse(
        "an id twice",
        [20_684, 20_684, 20_325, 20_718, 0, 0, 0, 0, 0, 0, 0, 0],
        13,
      ),
      Refused(
        3,
        False,
        False,
        message_support.hex(support.save_a),
        2,
        "20718 in slot 3 at level 3: slot 3 opens at level 4 and the level 3 book lacks 20718, and the slot is checked first",
      ),
      Refused(
        4,
        False,
        False,
        support.body(ids: support.ids_a, set: 1),
        40,
        "set 1: only the active set is judged",
      ),
      Refused(
        4,
        False,
        False,
        support.body(ids: support.ids_a, set: 7),
        40,
        "set 7, which the client never sends",
      ),
      refuse("11 entries", list.take(support.ids_a, 11), 25),
      refuse("no entries", [], 25),
      Refused(
        4,
        True,
        False,
        message_support.hex(support.save_a),
        27,
        "the player is dead",
      ),
      Refused(
        4,
        False,
        True,
        message_support.hex(support.save_a),
        30,
        "the player is in combat",
      ),
      Refused(
        4,
        True,
        False,
        support.body(ids: support.ids_a, set: 1),
        27,
        "two faults: dead is checked before the set",
      ),
    ],
    fn(case_) {
      let Refused(level:, dead:, in_combat:, body:, result:, why:) = case_
      let #(held, _) =
        support.taken(
          saved: limited_action_set.none(),
          level:,
          body: message_support.hex(support.save_a),
        )
      let player = support.player(tables:, level:)
      // The Medic's ability with a missing tier is in the book so that its tier, and not
      // its absence from the book, is what the save is refused for.
      let player =
        Player(..player, dead:, in_combat:, book: [
          Spell4BaseId(base_with_a_missing_tier),
          ..player.book
        ])
      let assert Ok(#(after, effects)) =
        limited_action_set.take(
          unlocks: limited_action_set.unlocks(tables:),
          tiers: spell_tier.tiers(tables:),
          player:,
          saved: held,
          class_bar: support.class_abilities(tables:),
          body:,
        )
        as why
      assert support.the_action_set(frames: support.frames_of(effects:)).result
        == result
        as why
      assert support.held_ids(tables:, saved: after)
        == support.held_ids(tables:, saved: held)
        as { why <> ": the set held is unchanged" }
      assert limited_action_set.held_tiers(saved: after, set: 0)
        == limited_action_set.held_tiers(saved: held, set: 0)
        as { why <> ": the tiers held are unchanged" }
    },
  )
}

pub fn the_answer_is_the_set_then_0xb2_and_a_refusal_carries_the_result_and_the_held_set_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let shortcuts = fn(ids: List(Int)) {
    list.index_map(ids, fn(id, slot) {
      case id {
        0 ->
          ActionShortcut(
            shortcut_type: 0,
            location: 0,
            bag_index: slot,
            object_id: 0,
          )
        id ->
          ActionShortcut(
            shortcut_type: 4,
            location: 4,
            bag_index: slot,
            object_id: id,
          )
      }
    })
  }
  // Accepted from no set at level 10 with Quick Draw to tier 2: the set 0, unlocked, result 1,
  // the twelve shortcuts, then the book's tiers, the points, and bit 1.
  let #(_, accepted) =
    support.taken(
      saved: limited_action_set.none(),
      level: 10,
      body: tiering([#(quick_draw, 2)]),
    )
  let frames = support.frames_of(effects: accepted)
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x019D, 0x01A0, 0x0169, 0x00B2]
    as "opcode.0x169 comes before 0xB2, which clears the client's own count of points"
  assert support.the_action_set(frames:)
    == action_set.ActionSet(
      action_set_index: 0,
      unlocked: 1,
      result: 1,
      shortcuts: shortcuts(support.ids_a),
    )
  let book = support.player(tables:, level: 10).book
  assert ability_book_support.tiers_in(frames:)
    == list.map(book, fn(base) {
      ability_tier.AbilityTier(
        spell4_base_id: base.value,
        tier: case base.value == quick_draw {
          True -> 2
          False -> 1
        },
        action_set_index: 0,
      )
    })
    as "opcode.0x1a0: every ability of the book in set 0 and no other set, Quick Draw at 2"
  assert ability_points_support.points_in(frames:) == [#(0, 1)]
    as "level 10 gives 1 point, spent"
  assert support.the_answer_bit(frames:) == 1
  assert support.logs_of(effects: accepted) == []
  // The entry's 0x01A0 names every ability in each of the four sets at tier 1.
  assert ability_book_support.tiers_in(frames: [
      ability_book_frame.tiers(
        abilities: book,
        sets: ability_book_frame.every_set(),
        tier_of: ability_book_frame.first_tier_of,
      ),
    ])
    == ability_book_support.tiers_of(
      bases: list.map(book, fn(base) { base.value }),
    )
    as "the entry sends sets 0 to 3 at tier 1"
  // Refused from the set of A: the result, the twelve shortcuts of the held set, bit 0, a
  // warning, and no tiers or points.
  let #(held, _) =
    support.taken(
      saved: limited_action_set.none(),
      level: 4,
      body: message_support.hex(support.save_a),
    )
  let too_early = support.body(ids: a_with(slot: 4, id: 20_718), set: 0)
  let #(_, refused) = support.taken(saved: held, level: 4, body: too_early)
  let frames = support.frames_of(effects: refused)
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x019D, 0x00B2]
  assert support.the_action_set(frames:)
    == action_set.ActionSet(
      action_set_index: 0,
      unlocked: 1,
      result: 2,
      shortcuts: shortcuts(support.ids_a),
    )
  assert support.the_answer_bit(frames:) == 0
  let assert [#(LogWarning, line)] = support.logs_of(effects: refused)
    as "one warning line"
  assert string.contains(line, "0xB1 refused with result 2")
  // Refused from no set: the held bar is the class's.
  let #(_, from_none) =
    support.taken(saved: limited_action_set.none(), level: 4, body: too_early)
  assert support.the_action_set(frames: support.frames_of(effects: from_none)).shortcuts
    == shortcuts(support.class_bar)
    as "the class's bar is the held bar of a player who saved none"
}

pub fn amp_ids_in_a_save_are_dropped_and_the_bar_is_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let #(saved, effects) =
    support.taken(
      saved: limited_action_set.none(),
      level: 15,
      body: message_support.hex(support.save_d),
    )
  assert support.held_ids(tables:, saved:) == support.ids_a
    as "the bar of the save is kept"
  assert limited_action_set.held_tiers(saved:, set: 0)
    == [#(Spell4BaseId(charged_shot), 2), #(Spell4BaseId(quick_draw), 3)]
    as "the two tier changes of the save are applied (opcode.0xb1: (20684, 2) and (27638, 3))"
  let #(_, without_amps) =
    support.taken(
      saved: limited_action_set.none(),
      level: 15,
      body: tiering([#(charged_shot, 2), #(quick_draw, 3)]),
    )
  assert support.frames_of(effects:) == support.frames_of(effects: without_amps)
    as "the AMP ids change nothing in the answer"
  assert support.logs_of(effects: without_amps) == []
    as "a tier change that is applied is not logged as dropped"
  let assert [#(LogDebug, line)] = support.logs_of(effects:) as "one debug line"
  assert string.contains(line, "2 AMPs")
    as "it says how many AMPs were not applied"
  assert !string.contains(line, "tier") as "and names no tier change"
}

/// The points a level gives: 1 a level from level 10 (`XpPerLevel.abilityPointsPerLevel`).
fn points_of_level(level level: Int) -> Int {
  level - 9
}

pub fn any_accepted_tier_save_keeps_the_points_spent_within_the_levels_total_and_a_repeat_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // A tier change is a place in the book (taken modulo its length, so every change names a
  // held ability) and a tier from 0 to 10, which holds the tiers the rule refuses.
  let change =
    qcheck.tuple2(qcheck.bounded_int(0, 40), qcheck.bounded_int(0, 10))
  let save =
    qcheck.generic_list(
      elements_from: change,
      length_from: qcheck.bounded_int(0, 4),
    )
  let saves =
    qcheck.generic_list(
      elements_from: save,
      length_from: qcheck.bounded_int(0, 8),
    )
  qcheck.given(qcheck.tuple2(qcheck.bounded_int(10, 50), saves), fn(drawn) {
    let #(level, saves) = drawn
    let book = support.player(tables:, level:).book
    let book_size = list.length(book)
    list.fold(saves, limited_action_set.none(), fn(saved, changes) {
      let named =
        list.filter_map(changes, fn(change) {
          list.drop(book, change.0 % book_size)
          |> list.first
          |> result.map(fn(base) { #(base.value, change.1) })
        })
      let body =
        support.body_with(
          ids: support.class_bar,
          set: 0,
          tier_changes: named,
          amp_ids: [],
        )
      let #(after, effects) = support.taken(saved:, level:, body:)
      let #(again, repeated) = support.taken(saved: after, level:, body:)
      assert limited_action_set.points_spent(
          tiers: spell_tier.tiers(tables:),
          saved: after,
        )
        <= points_of_level(level:)
        as "the points the held tiers cost never exceed the points the level gives"
      list.each(limited_action_set.held_tiers(saved: after, set: 0), fn(held) {
        assert held.1 >= 2 && held.1 <= 9
          as "a held tier is 2 to 9 (tier 1 is no entry, the client's writer drops tier 10)"
        assert level >= 5 * held.1
          as "a held tier passes its level gate: tier n needs level 5n (Spell4TierRequirements)"
      })
      assert limited_action_set.rows(saved: again)
        == limited_action_set.rows(saved: after)
        as "the same save again holds the same bar"
      assert limited_action_set.held_tiers(saved: again, set: 0)
        == limited_action_set.held_tiers(saved: after, set: 0)
        as "the same save again holds the same tiers"
      assert support.frames_of(effects: repeated) == support.frames_of(effects:)
        as "the same save again answers the same frames"
      after
    })
    Nil
  })
}

/// The CharacterCreation start enum of the Novice (PreTutorial) rows, the ones the
/// loadouts are built from (`Item2.novice_set`).
const novice_start = 4

/// The Novice loadouts of every class and faction the client's CharacterCreation rows
/// let a player start in (an enabled row that is not costume-only, of the Novice
/// start), one for each pair, as `#(class_id, faction_id, loadout)`. The pairs come
/// from the rows, not from the loadouts, so a pair with no loadout fails here.
fn novice_loadouts(
  tables tables: table_store.Tables,
) -> List(#(Int, Int, loadout.Loadout)) {
  let pairs =
    character_creation.all(tables)
    |> list.filter(fn(row) {
      row.character_creation_start_enum == novice_start
      && row.enabled
      && !row.costume_only
    })
    |> list.map(fn(row) { #(row.class_id, row.faction_id) })
    |> list.unique
  assert pairs != [] as "the client's CharacterCreation holds Novice starts"
  list.map(pairs, fn(pair) {
    let #(class_id, faction_id) = pair
    let assert Ok(held) =
      loadout.of(tables:, class_id: ClassId(class_id), faction_id:)
      as {
        "class "
        <> int.to_string(class_id)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ": a player can start as this pair, so it has a loadout"
      }
    #(class_id, faction_id, held)
  })
}

pub fn every_classs_entry_bar_fits_the_slots_open_at_level_1_and_is_accepted_at_every_level_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let unlocks = limited_action_set.unlocks(tables:)
  let level_1_slots = limited_action_set.open_slots(unlocks:, level: 1)
  list.each(novice_loadouts(tables:), fn(found) {
    let #(class_id, faction_id, held) = found
    let name =
      "class "
      <> int.to_string(class_id)
      <> ", faction "
      <> int.to_string(faction_id)
    let entry_bar =
      support.ids_of(bar: limited_action_set.bar_of(
        saved: limited_action_set.none(),
        set: limited_action_set.first_set(),
        class_bar: held.abilities,
      ))
    let filled =
      list.index_map(entry_bar, fn(id, slot) { #(slot, id) })
      |> list.filter(fn(placed) { placed.1 != 0 })
      |> list.map(fn(placed) { placed.0 })
    assert list.all(filled, fn(slot) { list.contains(level_1_slots, slot) })
      as { name <> ": the entry bar fills only slots open at level 1" }
    assert list.length(filled) == 3
      as {
        name
        <> ": three level 1 abilities (SpellLevel rows of characterLevel 1)"
      }
    list.each(support.levels(from: 1, to: 50), fn(level) {
      let player =
        Player(
          level:,
          points_total: ability_points.total(tables:, level:),
          book: ability_book.book(tables:, loadout: held, level:),
          dead: False,
          in_combat: False,
        )
      let assert Ok(#(saved, effects)) =
        limited_action_set.take(
          unlocks:,
          tiers: spell_tier.tiers(tables:),
          player:,
          saved: limited_action_set.none(),
          class_bar: held.abilities,
          body: support.body(ids: entry_bar, set: 0),
        )
        as "the body is one the client's reader accepts"
      assert support.the_action_set(frames: support.frames_of(effects:)).result
        == 1
        as {
          name
          <> ", level "
          <> int.to_string(level)
          <> ": a Save of the bar as it is, which the stock builder sends, is never refused"
        }
      assert support.ids_of(bar: limited_action_set.bar_of(
          saved:,
          set: limited_action_set.first_set(),
          class_bar: held.abilities,
        ))
        == entry_bar
    })
  })
}

pub fn every_ability_the_book_offers_the_bar_is_a_class_ability_of_its_own_class_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(novice_loadouts(tables:), fn(found) {
    let #(class_id, faction_id, held) = found
    let book = ability_book.book(tables:, loadout: held, level: 50)
    let innate = case held.innate {
      Some(innate) -> [innate.active_base]
      None -> []
    }
    let abilities =
      list.append(
        held.abilities,
        list.map(held.later, fn(unlock) { unlock.base }),
      )
    let counts =
      "class "
      <> int.to_string(class_id)
      <> ", faction "
      <> int.to_string(faction_id)
      <> ": "
      <> int.to_string(list.length(abilities))
      <> " bag abilities, "
      <> int.to_string(
        list.length(book) - list.length(abilities) - list.length(innate),
      )
      <> " alternates"
    list.each(book, fn(base) {
      let assert Ok(row) = spell4_base.get(tables:, id: base)
        as {
          counts <> ": Spell4Base " <> int.to_string(base.value) <> " has a row"
        }
      assert row.spell4_spell_types_id_spell_type == 5
        as {
          counts
          <> ": Spell4Base "
          <> int.to_string(base.value)
          <> " is a Class - Ability spell (Spell4SpellTypes 5), which the client's slot check takes in slots 0 to 7"
        }
    })
    list.each(abilities, fn(base) {
      let assert Ok(row) = spell4_base.get(tables:, id: base) as counts
      assert row.class_id_player == class_id
        as {
          counts
          <> ": Spell4Base "
          <> int.to_string(base.value)
          <> " is of the class"
        }
    })
  })
}

/// What a load of rows leads to: the ids of set 0 the player holds, or the refused row.
type Entering {
  Holds(set_zero: List(Int))
  Refuses(error: limited_action_set.RowError)
}

pub fn entering_keeps_a_saved_ability_the_player_still_holds_and_drops_one_the_player_no_longer_holds_or_a_slot_no_longer_open_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let level_4 = support.player(tables:, level: 4)
  let enter = fn(rows) {
    limited_action_set.entering(
      unlocks: limited_action_set.unlocks(tables:),
      level: level_4.level,
      book: level_4.book,
      rows: ActionSets(slots: rows),
    )
  }
  let no_slots = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let zeros = fn(count) { list.repeat(0, count) }
  let outside = fn(set, slot, id) {
    store.ActionSlotRow(action_set: set, slot:, spell4_base_id: id)
  }
  list.each(
    [
      #(
        "all of A: slots 0 to 3 hold abilities of the level 4 book, open at level 4",
        support.rows_of(set: 0, ids: support.ids_a),
        Holds(support.ids_a),
      ),
      #(
        "23468 (level 10) saved in slot 3, which opens at 4: the level 4 book does not hold it",
        support.rows_of(set: 0, ids: [
          27_638,
          20_684,
          20_325,
          23_468,
          ..zeros(8)
        ]),
        Holds([27_638, 20_684, 20_325, ..zeros(9)]),
      ),
      #(
        "20718 saved in slot 5, which opens at 7: a level 4 player has no such slot",
        support.rows_of(set: 0, ids: [
          27_638,
          20_684,
          20_325,
          0,
          0,
          20_718,
          ..zeros(6)
        ]),
        Holds([27_638, 20_684, 20_325, ..zeros(9)]),
      ),
      #(
        "a Medic ability (Class 4, 26038) in slot 0 of a Spellslinger",
        support.rows_of(set: 0, ids: [26_038, 20_684, 20_325, ..zeros(9)]),
        Holds([0, 20_684, 20_325, ..zeros(9)]),
      ),
      #(
        "seven rows of a set: the five slots with no row are empty and the others stay",
        support.rows_of(set: 0, ids: [27_638, 20_684, 20_325, 20_718, 0, 0, 0]),
        Holds(support.ids_a),
      ),
      #(
        "[27638, empty, 20325]: the filled slot after an empty one keeps its slot",
        support.rows_of(set: 0, ids: [27_638, 0, 20_325, ..zeros(9)]),
        Holds([27_638, 0, 20_325, ..zeros(9)]),
      ),
      #(
        "a saved empty set: a saved set with nothing in it is not the class's bar",
        support.rows_of(set: 0, ids: no_slots),
        Holds(no_slots),
      ),
      #(
        "a row of set 4, which the table's check refuses",
        [outside(4, 0, Some(27_638))],
        Refuses(RowOutsideTable(row: outside(4, 0, Some(27_638)))),
      ),
      #(
        "a row of slot 12, which the table's check refuses",
        list.append(support.rows_of(set: 0, ids: support.ids_a), [
          outside(0, 12, Some(27_638)),
        ]),
        Refuses(RowOutsideTable(row: outside(0, 12, Some(27_638)))),
      ),
      #(
        "an ability of id 262144, wider than the 18 bits of the message",
        [outside(0, 0, Some(262_144))],
        Refuses(RowOutsideTable(row: outside(0, 0, Some(262_144)))),
      ),
      #(
        "two rows for slot 0 of set 0, which the primary key refuses",
        [outside(0, 0, Some(27_638)), outside(0, 0, Some(20_684))],
        Refuses(RowRepeated(row: outside(0, 0, Some(20_684)))),
      ),
    ],
    fn(row) {
      let #(why, rows, expected) = row
      let held = case enter(rows) {
        Ok(saved) -> Holds(support.held_ids(tables:, saved:))
        Error(error) -> Refuses(error)
      }
      assert held == expected as why
    },
  )
  let assert Ok(saved) = enter(support.rows_of(set: 2, ids: support.ids_a))
    as "rows of set 2 are rows the table's checks hold"
  assert limited_action_set.rows(saved:)
    == ActionSets(slots: support.rows_of(set: 2, ids: support.ids_a))
    as "the rows of set 2 are kept as set 2, each in its slot"
  assert support.held_ids(tables:, saved:) == support.class_bar
    as "a player who saved only set 2 has the class's bar in set 0"
  let assert Error(error) = enter([outside(4, 0, Some(27_638))])
    as "a row of set 4 ends the entry"
  assert string.contains(limited_action_set.describe_row(error:), "set 4")
    && string.contains(limited_action_set.describe_row(error:), "slot 0")
    as "the sentence names the row's set and slot"
}

/// A drawn set as the slots a player can hold: slots 8 and 9 never open (their
/// prerequisites are types the server does not read), every other slot is open at level
/// 100, and an ability is in one place of its set, as the table's unique key holds.
fn holdable(drawn drawn: List(Option(Int))) -> List(Option(Int)) {
  list.index_map(drawn, fn(slot, at) {
    case at {
      8 | 9 -> None
      _ -> slot
    }
  })
  |> list.fold([], fn(so_far, slot) {
    case slot {
      Some(_) ->
        case list.contains(so_far, slot) {
          True -> [None, ..so_far]
          False -> [slot, ..so_far]
        }
      None -> [None, ..so_far]
    }
  })
  |> list.reverse
}

pub fn saved_sets_round_trip_through_their_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let unlocks = limited_action_set.unlocks(tables:)
  let drawn_set =
    qcheck.option_from(qcheck.fixed_length_list_from(
      qcheck.option_from(qcheck.bounded_int(1, 262_143)),
      12,
    ))
  qcheck.given(
    qcheck.tuple4(drawn_set, drawn_set, drawn_set, drawn_set),
    fn(drawn) {
      let rows =
        [drawn.0, drawn.1, drawn.2, drawn.3]
        |> list.index_map(fn(set, number) { #(number, set) })
        |> list.flat_map(fn(numbered) {
          case numbered.1 {
            None -> []
            Some(slots) ->
              list.index_map(holdable(drawn: slots), fn(held, slot) {
                store.ActionSlotRow(
                  action_set: numbered.0,
                  slot:,
                  spell4_base_id: held,
                )
              })
          }
        })
      let book =
        list.filter_map(rows, fn(row) {
          option.to_result(row.spell4_base_id, Nil)
          |> result.map(Spell4BaseId)
        })
      let assert Ok(saved) =
        limited_action_set.entering(
          unlocks:,
          level: 100,
          book:,
          rows: ActionSets(slots: rows),
        )
        as "rows the table's checks hold are read"
      assert limited_action_set.rows(saved:) == ActionSets(slots: rows)
        as "a saved set is twelve rows, in set then slot order, and no set gives none"
      assert limited_action_set.entering(
          unlocks:,
          level: 100,
          book:,
          rows: limited_action_set.rows(saved:),
        )
        == Ok(saved)
        as "the rows of the sets read back as the same sets"
    },
  )
}
