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
import cast_support
import client_tables
import fixture_tables
import genesis_prime/game/ability_book
import genesis_prime/game/ability_book_frame
import genesis_prime/game/ability_points
import genesis_prime/game/limited_action_set.{
  Player, RowOutsideTable, RowRepeated, StoredAmp, StoredSlot, StoredTier,
}
import genesis_prime/game/world_entry
import genesis_prime/message/ability_tier
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/shared/amp_spec
import genesis_prime/shared/loadout
import genesis_prime/shared/prerequisite
import genesis_prime/shared/spell_tier
import genesis_prime/step.{LogWarning}
import genesis_prime/store
import genesis_prime/table/action_slot_prereq
import genesis_prime/table/character_creation
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type ClassId, type Spell4BaseId, ClassId, EldanAugmentationId, GameFormulaId,
  PrerequisiteId, Spell4BaseId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import gleam/float
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
import spell_tables
import unitest
import world_entry_support

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

const quick_draw_alternate = 52_215

const ignite = 20_718

const spellslinger_innate = 31_213

/// Medic Paralytic Surge, whose tiers 2 to 8 the tests that use it take out of the tables
/// (`spell_tables.with_paralytic_surge_tiers_2_to_8_missing`): the client holds a row for every
/// tier, so a base with a tier that has no row is an edit.
const base_with_a_missing_tier = spell_tables.paralytic_surge

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
        [support.tiering([#(quick_draw, 2)])],
        support.ids_a,
        [#(quick_draw, 2)],
        #(0, 1),
        "level 10 gives 1 point: Quick Draw to tier 2 costs 1",
      ),
      Accepted(
        25,
        [support.tiering([#(quick_draw, 5), #(ignite, 3)])],
        support.ids_a,
        [#(ignite, 3), #(quick_draw, 5)],
        #(6, 16),
        "level 25 gives 16 points: Quick Draw to tier 5 costs 8 and Ignite to tier 3 costs 2",
      ),
      Accepted(
        15,
        [support.tiering([#(quick_draw, 3)])],
        support.ids_a,
        [#(quick_draw, 3)],
        #(4, 6),
        "tier 3 needs level 15 and costs 2 of the 6 points",
      ),
      Accepted(
        25,
        [
          support.tiering([#(quick_draw, 5), #(charged_shot, 5)]),
          support.tiering([#(quick_draw, 1), #(ignite, 5)]),
        ],
        support.ids_a,
        [#(charged_shot, 5), #(ignite, 5)],
        #(0, 16),
        "16 of 16 points spent, then Quick Draw falls to tier 1 and Ignite rises to tier 5 in one save: judged on the tiers the save leaves",
      ),
      Accepted(
        10,
        [
          support.tiering([#(quick_draw, 2)]),
          support.tiering([#(quick_draw, 2)]),
        ],
        support.ids_a,
        [#(quick_draw, 2)],
        #(0, 1),
        "the tier it already holds changes nothing",
      ),
      Accepted(
        10,
        [
          support.tiering([#(quick_draw, 2)]),
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
        [support.tiering([#(charged_shot, 3)])],
        support.ids_a,
        [#(charged_shot, 3)],
        #(4, 6),
        "Charged Shot at tier 3 costs 2 of the 6 points and holds no tier of its alternate 20685, which rides with it",
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
  // A level 10 Stalker picks the Assault chain 770 to 772 and the tier 1 AMP 863 (7 of 7 power),
  // sent with the pick first as the client's list holds them; then, at level 11, adds 782.
  let stalker = 5
  let #(four, first) =
    support.taken_as(
      class_id: stalker,
      saved: limited_action_set.none(),
      level: 10,
      body: support.amps_body(class_id: stalker, amp_ids: [863, 772, 771, 770]),
    )
  assert support.held_amp_ids(saved: four, set: 0) == [770, 771, 772, 863]
    as "the four AMPs are held, ascending"
  assert cast_support.ids(frames: support.frames_of(effects: first))
    == [0x019D, 0x01A0, 0x0169, 0x01A3, 0x00B2]
    as "opcode.0x1a3: the AMP list comes after the points (the event follows 0x0169) and before 0xB2"
  assert support.amp_lists_in(frames: support.frames_of(effects: first))
    == [#(0, [770, 771, 772, 863])]
    as "the list of set 0, ascending"
  let #(five, second) =
    support.taken_as(
      class_id: stalker,
      saved: four,
      level: 11,
      body: support.amps_body(class_id: stalker, amp_ids: [
        770,
        771,
        772,
        863,
        782,
      ]),
    )
  assert support.held_amp_ids(saved: five, set: 0) == [770, 771, 772, 782, 863]
    as "the second save keeps the first four and adds the fifth (8 of 8 power)"
  assert support.amp_lists_in(frames: support.frames_of(effects: second))
    == [#(0, [770, 771, 772, 782, 863])]
    as "the answer carries the whole list"
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
  use tables <- spell_tables.with_paralytic_surge_tiers_2_to_8_missing
  let refuse = fn(why, ids, result) {
    Refused(4, False, False, support.body(ids:, set: 0), result, why)
  }
  let refuse_tiers = fn(why, level, changes, result) {
    Refused(level, False, False, support.tiering(changes), result, why)
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
        "tier 5 of a base whose Spell4 rows hold tiers 1 and 9 only (Paralytic Surge with tiers 2 to 8 taken out): a tier with no row cannot be bought",
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
      refuse_tiers(
        "a tier change of Charged Shot's alternate 20685, which the book holds only as part of Charged Shot: the stock builder never offers it, and its book tier is Charged Shot's",
        15,
        [#(charged_shot_alternate, 3)],
        18,
      ),
      refuse_tiers(
        "a change of Charged Shot's alternate to tier 1 is refused as well: the builder never offers an alternate at any tier",
        15,
        [#(charged_shot_alternate, 1)],
        18,
      ),
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
          amps: amp_spec.specs(tables:),
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
  // AMP rows: a Stalker (class 5) holding the AMPs of `held` at level 10, then a save that is
  // refused. `names` is what the one warning says.
  let stalker = 5
  // The bar a save sends, from the class's own bar of 12 ids.
  let keep = fn(own: List(Int)) { own }
  let swapped = fn(own: List(Int)) {
    case own {
      [first, second, ..rest] -> [second, first, ..rest]
      _ -> panic as "a bar holds twelve ids"
    }
  }
  let twice = fn(own: List(Int)) {
    case own {
      [first, _, ..rest] -> [first, first, ..rest]
      _ -> panic as "a bar holds twelve ids"
    }
  }
  list.each(
    [
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [863],
        33,
        "category 3",
        False,
        False,
        "863 is tier 1 and 0 power is spent in tier 0 of category 3",
      ),
      AmpRefused(
        stalker,
        9,
        [],
        keep,
        0,
        [770],
        31,
        "770",
        False,
        False,
        "level 9 gives 0 power",
      ),
      AmpRefused(
        1,
        10,
        [],
        keep,
        0,
        [863],
        4,
        "863",
        False,
        False,
        "863 is a Stalker's, and a Warrior (class 1) picks it",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [12],
        35,
        "12",
        False,
        False,
        "12 has no row",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [771],
        34,
        "771",
        False,
        False,
        "771 needs 770",
      ),
      AmpRefused(
        stalker,
        10,
        [770, 771, 772],
        keep,
        0,
        [863],
        43,
        "770",
        False,
        False,
        "the list drops the held 770, 771 and 772: removing an AMP is the paid reset",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [770, 770],
        13,
        "770",
        False,
        False,
        "770 twice: the client never refuses a repeat, the server's mapping does",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        swapped,
        0,
        [863],
        33,
        "category 3",
        False,
        False,
        "a good bar change with a refused AMP list: the bar is not applied either",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        twice,
        0,
        [770],
        13,
        "",
        False,
        False,
        "a bad bar with a good AMP list: the bar's result, and no AMP is kept",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [770],
        27,
        "",
        True,
        False,
        "a good AMP list while dead",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        0,
        [770],
        30,
        "",
        False,
        True,
        "a good AMP list while in combat",
      ),
      AmpRefused(
        stalker,
        10,
        [],
        keep,
        1,
        [770],
        40,
        "",
        False,
        False,
        "the list in a save for set 1: only the active set is judged",
      ),
    ],
    fn(row) {
      let AmpRefused(
        class_id:,
        level:,
        held:,
        bar:,
        set:,
        amp_ids:,
        result:,
        names:,
        dead:,
        in_combat:,
        why:,
      ) = row
      let #(before, _) =
        support.taken_as(
          class_id:,
          saved: limited_action_set.none(),
          level:,
          body: support.amps_body(class_id:, amp_ids: held),
        )
      let player =
        Player(
          ..support.player_of(tables:, class_id:, level:),
          dead:,
          in_combat:,
        )
      let assert Ok(#(after, effects)) =
        limited_action_set.take(
          unlocks: limited_action_set.unlocks(tables:),
          tiers: spell_tier.tiers(tables:),
          amps: amp_spec.specs(tables:),
          player:,
          saved: before,
          class_bar: support.class_abilities_of(tables:, class_id:),
          body: support.body_with(
            ids: bar(support.own_bar(class_id:)),
            set:,
            tier_changes: [],
            amp_ids:,
          ),
        )
        as why
      let frames = support.frames_of(effects:)
      assert support.the_action_set(frames:).result == result as why
      assert limited_action_set.rows(saved: after)
        == limited_action_set.rows(saved: before)
        as { why <> ": the bar, the tiers and the AMPs are as before" }
      assert cast_support.ids(frames:) == [0x019D, 0x01A3, 0x00B2]
        as { why <> ": the held bar, the held list and 0xB2" }
      assert list.map(support.the_action_set(frames:).shortcuts, fn(shortcut) {
          shortcut.object_id
        })
        == support.held_ids_as(tables:, class_id:, saved: before)
        as { why <> ": the answer holds the held bar" }
      assert support.amp_lists_in(frames:)
        == [#(0, support.held_amp_ids(saved: before, set: 0))]
        as { why <> ": the answer holds the held list" }
      assert support.the_answer_bit(frames:) == 0 as why
      let assert [#(LogWarning, line)] = support.logs_of(effects:)
        as { why <> ": one warning" }
      assert string.contains(
        line,
        "0xB1 refused with result " <> int.to_string(result),
      )
        as why
      assert string.contains(line, names)
        as { why <> ": the warning names " <> names }
    },
  )
}

/// A refused AMP save: a Stalker or another class at a level, the AMPs held, the bar and set
/// the save names, the AMP ids it sends, the result, what the warning names, whether the
/// player is dead or in combat, and why.
type AmpRefused {
  AmpRefused(
    class_id: Int,
    level: Int,
    held: List(Int),
    bar: fn(List(Int)) -> List(Int),
    set: Int,
    amp_ids: List(Int),
    result: Int,
    names: String,
    dead: Bool,
    in_combat: Bool,
    why: String,
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
      body: support.tiering([#(quick_draw, 2)]),
    )
  let frames = support.frames_of(effects: accepted)
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x019D, 0x01A0, 0x0169, 0x01A3, 0x00B2]
    as "opcode.0xb2: 0x01A0 and 0x0169 come before 0xB2, so the redraw it triggers already shows the new book; opcode.0x1a3: every answer carries the set's list"
  assert support.amp_lists_in(frames:) == [#(0, [])]
    as "a player with no AMPs gets the empty list, as the answer carries the bar"
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
        tier: case
          base.value == quick_draw || base.value == quick_draw_alternate
        {
          True -> 2
          False -> 1
        },
        action_set_index: 0,
      )
    })
    as "opcode.0x1a0: every ability of the book in set 0 and no other set, Quick Draw and its alternate at 2"
  assert ability_points_support.points_in(frames:) == [#(0, 1)]
    as "level 10 gives 1 point, spent"
  assert support.the_answer_bit(frames:) == 1
  // The book's tier of an ability (`opcode.0x1a0`): the client reads an alternate's tier from its
  // own book entry (`0x1405e7e50`, `0x140565090`), so the server sends each alternate at the tier
  // of the ability that names it, whatever tier the alternate's own row holds.
  let tiers = spell_tier.tiers(tables:)
  let book_25 = support.player(tables:, level: 25).book
  list.each(
    [
      #(
        "Quick Draw saved at 5: it and its alternate both show 5",
        [#(quick_draw, 5)],
        [#(quick_draw, 5), #(quick_draw_alternate, 5)],
      ),
      #(
        "Quick Draw at tier 1: its alternate shows 1, though the alternate's own stored tier is 3",
        [#(quick_draw_alternate, 3)],
        [#(quick_draw, 1), #(quick_draw_alternate, 1)],
      ),
      #(
        "Quick Draw at 5 and the alternate stored at 3: the alternate shows the ability's 5",
        [#(quick_draw, 5), #(quick_draw_alternate, 3)],
        [#(quick_draw, 5), #(quick_draw_alternate, 5)],
      ),
      #("Charged Shot at 3: its alternate shows 3", [#(charged_shot, 3)], [
        #(charged_shot, 3),
        #(charged_shot_alternate, 3),
      ]),
      #("an ability with no alternate keeps its own tier", [#(ignite, 3)], [
        #(ignite, 3),
      ]),
    ],
    fn(row) {
      let #(why, stored, shown) = row
      let assert Ok(limited_action_set.Judged(saved:, ..)) =
        limited_action_set.entering(
          unlocks: limited_action_set.unlocks(tables:),
          amps: amp_spec.specs(tables:),
          class_id: ClassId(support.spellslinger),
          tiers:,
          points_total: 16,
          level: 25,
          book: book_25,
          rows: store.ActionSets(
            slots: [],
            tiers: list.map(stored, fn(held) {
              store.AbilityTierRow(
                action_set: 0,
                spell4_base_id: held.0,
                tier: held.1,
              )
            }),
            amps: [],
          ),
        )
        as why
      list.each(shown, fn(entry) {
        assert limited_action_set.book_tier_of(
            tiers:,
            saved:,
            set: 0,
            book: book_25,
            base: Spell4BaseId(entry.0),
          )
          == entry.1
          as { why <> ": Spell4Base " <> int.to_string(entry.0) }
      })
    },
  )
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
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x019D, 0x01A3, 0x00B2]
  assert support.amp_lists_in(frames:) == [#(0, [])]
    as "a refusal carries the held list, here empty"
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

pub fn amp_ids_in_a_save_are_judged_with_the_bar_and_the_tiers_as_one_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  // `save_d` carries the sitting's bar, two tier changes and the AMP ids 101 and 202; 101 is an
  // AMP of class 0, which no Spellslinger picks.
  let #(refused, effects) =
    support.taken(
      saved: limited_action_set.none(),
      level: 15,
      body: message_support.hex(support.save_d),
    )
  assert support.the_action_set(frames: support.frames_of(effects:)).result == 4
    as "101 is another class's AMP"
  assert support.held_ids(tables:, saved: refused) == support.class_bar
    as "the bar of the save is not kept"
  assert limited_action_set.held_tiers(saved: refused, set: 0) == []
    as "the two tier changes of the save are not kept either: one answer"
  assert support.held_amp_ids(saved: refused, set: 0) == []
  assert cast_support.ids(frames: support.frames_of(effects:))
    == [0x019D, 0x01A3, 0x00B2]
  assert support.amp_lists_in(frames: support.frames_of(effects:)) == [#(0, [])]
  assert support.the_answer_bit(frames: support.frames_of(effects:)) == 0
  // The same bar and tiers with a Spellslinger's AMPs 175 to 177 (tier 0, category 4) and 198
  // (tier 1): 7 of 12 power at level 15.
  let #(saved, effects) =
    support.taken(
      saved: limited_action_set.none(),
      level: 15,
      body: support.body_with(
        ids: support.ids_a,
        set: 0,
        tier_changes: [#(charged_shot, 2), #(quick_draw, 3)],
        amp_ids: [175, 176, 177, 198],
      ),
    )
  assert support.the_action_set(frames: support.frames_of(effects:)).result == 1
  assert support.held_ids(tables:, saved:) == support.ids_a
    as "the bar of the save is kept"
  assert limited_action_set.held_tiers(saved:, set: 0)
    == [#(Spell4BaseId(charged_shot), 2), #(Spell4BaseId(quick_draw), 3)]
    as "the two tier changes of the save are applied (opcode.0xb1: (20684, 2) and (27638, 3))"
  assert support.held_amp_ids(saved:, set: 0) == [175, 176, 177, 198]
    as "the four AMPs are kept"
  assert support.logs_of(effects:) == []
    as "nothing is dropped, so nothing is logged"
}

/// The points a level gives: 1 a level from level 10 (`XpPerLevel.abilityPointsPerLevel`).
fn points_of_level(level level: Int) -> Int {
  level - 9
}

/// The points the held tiers cost, from the client's Spell4 rows: each tier from 2 up to the
/// held one costs its row's `abilityPointCost` (`0x1403bb2b0`).
fn points_cost(
  tables tables: table_store.Tables,
  held held: List(#(Spell4BaseId, Int)),
) -> Int {
  let rows = spell4.all(tables)
  list.fold(held, 0, fn(spent, ability) {
    let #(base, tier) = ability
    list.fold(rows, spent, fn(spent, row) {
      case
        row.spell4_base_id_base_spell == base.value
        && row.tier_index >= 2
        && row.tier_index <= tier
      {
        True -> spent + row.ability_point_cost
        False -> spent
      }
    })
  })
}

pub fn any_accepted_tier_save_keeps_the_points_spent_within_the_levels_total_and_a_repeat_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
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
      let expected_points = case
        support.the_action_set(frames: support.frames_of(effects:)).result
      {
        1 -> [
          #(
            points_of_level(level:)
              - points_cost(
              tables:,
              held: limited_action_set.held_tiers(saved: after, set: 0),
            ),
            points_of_level(level:),
          ),
        ]
        _ -> []
      }
      assert ability_points_support.points_in(frames: support.frames_of(
          effects:,
        ))
        == expected_points
        as "an accepted save answers with the points left and the points the level gives (0x0169), a refused one with none"
      // A save that brings every ability back to tier 1 is a fall, which is always allowed. The
      // alternates are left out: the builder never offers one, so a change of one is refused.
      let alternates =
        list.filter_map(book, fn(base) {
          spell_tier.alternate_of(tiers: spell_tier.tiers(tables:), base:)
        })
      let #(fallen, fell) =
        support.taken(
          saved: after,
          level:,
          body: support.body_with(
            ids: support.class_bar,
            set: 0,
            tier_changes: list.filter_map(book, fn(base) {
              case list.contains(alternates, base) {
                True -> Error(Nil)
                False -> Ok(#(base.value, 1))
              }
            }),
            amp_ids: [],
          ),
        )
      assert support.the_action_set(frames: support.frames_of(effects: fell)).result
        == 1
        as "a save that returns every ability to tier 1 is accepted"
      assert limited_action_set.held_tiers(saved: fallen, set: 0) == []
        as "and holds no tier above 1"
      assert ability_points_support.points_in(frames: support.frames_of(
          effects: fell,
        ))
        == [#(points_of_level(level:), points_of_level(level:))]
        as "and spends no point"
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
          class_id: ClassId(class_id),
          points_total: ability_points.total(tables:, level:),
          book: ability_book.book(tables:, loadout: held, level:),
          dead: False,
          in_combat: False,
        )
      let assert Ok(#(saved, effects)) =
        limited_action_set.take(
          unlocks:,
          tiers: spell_tier.tiers(tables:),
          amps: amp_spec.specs(tables:),
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

pub fn every_ability_the_book_offers_has_tier_data_for_every_class_and_faction_at_level_50_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let tiers = spell_tier.tiers(tables:)
  list.each(novice_loadouts(tables:), fn(found) {
    let #(class_id, faction_id, held) = found
    let book = ability_book.book(tables:, loadout: held, level: 50)
    // An alternate shows the tier of the ability that names it, so no book may hold two
    // abilities that name one alternate: the client keeps one book entry for it. Five
    // alternates are named by several bases today, and only one of those is in any book
    // (`table_rows -- Spell4 spell4IdMechanicAlternateSpell`).
    let named =
      list.filter_map(book, fn(base) { spell_tier.alternate_of(tiers:, base:) })
    assert list.length(named) == list.length(list.unique(named))
      as {
        "class "
        <> int.to_string(class_id)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ": two bases of the book name one alternate"
      }
    list.each(book, fn(base) {
      assert result.is_ok(spell_tier.highest(tiers:, base:))
        as {
          "class "
          <> int.to_string(class_id)
          <> ", faction "
          <> int.to_string(faction_id)
          <> ": Spell4Base "
          <> int.to_string(base.value)
          <> " is in the book, so a tier purchase of it must find its tiers, not be refused with 41"
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
      amps: amp_spec.specs(tables:),
      class_id: ClassId(support.spellslinger),
      level: level_4.level,
      book: level_4.book,
      tiers: spell_tier.tiers(tables:),
      points_total: 0,
      rows: support.with_rows(slots: rows, tiers: [], amps: []),
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
        Refuses(RowOutsideTable(row: StoredSlot(outside(4, 0, Some(27_638))))),
      ),
      #(
        "a row of slot 12, which the table's check refuses",
        list.append(support.rows_of(set: 0, ids: support.ids_a), [
          outside(0, 12, Some(27_638)),
        ]),
        Refuses(RowOutsideTable(row: StoredSlot(outside(0, 12, Some(27_638))))),
      ),
      #(
        "an ability of id 262144, wider than the 18 bits of the message",
        [outside(0, 0, Some(262_144))],
        Refuses(RowOutsideTable(row: StoredSlot(outside(0, 0, Some(262_144))))),
      ),
      #(
        "two rows for slot 0 of set 0, which the primary key refuses",
        [outside(0, 0, Some(27_638)), outside(0, 0, Some(20_684))],
        Refuses(RowRepeated(row: StoredSlot(outside(0, 0, Some(20_684))))),
      ),
    ],
    fn(row) {
      let #(why, rows, expected) = row
      let held = case enter(rows) {
        Ok(limited_action_set.Judged(saved:, ..)) ->
          Holds(support.held_ids(tables:, saved:))
        Error(error) -> Refuses(error)
      }
      assert held == expected as why
    },
  )
  let assert Ok(limited_action_set.Judged(saved:, ..)) =
    enter(support.rows_of(set: 2, ids: support.ids_a))
    as "rows of set 2 are rows the table's checks hold"
  assert limited_action_set.rows(saved:)
    == support.with_rows(
      slots: support.rows_of(set: 2, ids: support.ids_a),
      tiers: [],
      amps: [],
    )
    as "the rows of set 2 are kept as set 2, each in its slot"
  assert support.held_ids(tables:, saved:) == support.class_bar
    as "a player who saved only set 2 has the class's bar in set 0"
  let assert Error(error) = enter([outside(4, 0, Some(27_638))])
    as "a row of set 4 ends the entry"
  assert string.contains(limited_action_set.describe_row(error:), "set 4")
    && string.contains(limited_action_set.describe_row(error:), "slot 0")
    as "the sentence names the row's set and slot"
  // AMP rows go through the same fold: a set above 3, an id of 0 or beyond 16 bits and a second
  // row for one AMP of one set are refused, each with a sentence that names the AMP.
  let amp = fn(set, id) {
    store.AmpRow(action_set: set, eldan_augmentation_id: id)
  }
  list.each(
    [
      #(
        "set 4",
        [amp(4, 770)],
        RowOutsideTable(row: StoredAmp(amp(4, 770))),
        "outside",
      ),
      #(
        "id 0",
        [amp(0, 0)],
        RowOutsideTable(row: StoredAmp(amp(0, 0))),
        "outside",
      ),
      #(
        "id 65536, wider than the 16 bits of the lists",
        [amp(0, 65_536)],
        RowOutsideTable(row: StoredAmp(amp(0, 65_536))),
        "outside",
      ),
      #(
        "a repeated key",
        [amp(0, 770), amp(0, 770)],
        RowRepeated(row: StoredAmp(amp(0, 770))),
        "twice",
      ),
    ],
    fn(row) {
      let #(why, amps, expected, says) = row
      let assert Error(error) =
        limited_action_set.entering(
          unlocks: limited_action_set.unlocks(tables:),
          amps: amp_spec.specs(tables:),
          class_id: ClassId(support.spellslinger),
          level: level_4.level,
          book: level_4.book,
          tiers: spell_tier.tiers(tables:),
          points_total: 0,
          rows: support.with_rows(
            slots: [],
            tiers: [],
            amps: list.map(amps, fn(held) {
              #(held.action_set, held.eldan_augmentation_id)
            }),
          ),
        )
        as why
      assert error == expected as why
      let sentence = limited_action_set.describe_row(error:)
      assert string.contains(sentence, "AMP")
        && string.contains(sentence, says)
        && string.contains(
          sentence,
          "set " <> int.to_string(amp_row_of(error:).action_set),
        )
        && string.contains(
          sentence,
          "AMP " <> int.to_string(amp_row_of(error:).eldan_augmentation_id),
        )
        as { why <> ": the sentence names the AMP, its set and its id" }
    },
  )
}

/// The AMP row an error names.
fn amp_row_of(error error: limited_action_set.RowError) -> store.AmpRow {
  case error {
    RowOutsideTable(row: StoredAmp(row)) | RowRepeated(row: StoredAmp(row)) ->
      row
    _ -> panic as "the error names an AMP row"
  }
}

/// A stored AMP list the entry judges: who holds it, the AMPs stored (set, EldanAugmentation
/// id), the sets the entry keeps whole and the result the client's check gives each set it
/// drops (`amp_spec.result_of`), with the reason.
type StoredAmps {
  StoredAmps(
    class_id: Int,
    level: Int,
    stored: List(#(Int, Int)),
    kept: List(Int),
    dropped: List(#(Int, Int)),
    why: String,
  )
}

pub fn entering_keeps_a_stored_amp_list_the_check_still_passes_and_drops_the_whole_set_that_it_refuses_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  // Spellslinger 220 to 222 are tier 0 of category 1, cost 1 and chained, 259 is its tier 1
  // and costs 4; the level gives 7 power at 10 and none at 9 (GameFormula 942); the check
  // is `0x1403d02a0`, whose results are `amp_spec.result_of`.
  let chain = [220, 221, 222, 259]
  let in_sets = fn(sets, ids) {
    list.flat_map(sets, fn(set) { list.map(ids, fn(id) { #(set, id) }) })
  }
  let judge = fn(tables, case_: StoredAmps) {
    let judged =
      support.judged_with_amps(
        tables:,
        class_id: case_.class_id,
        level: case_.level,
        amps: case_.stored,
      )
    assert list.filter([0, 1, 2, 3], fn(set) {
        limited_action_set.held_amps(saved: judged.saved, set:) != []
      })
      == case_.kept
      as case_.why
    assert list.map(judged.dropped_amps, fn(dropped) {
        #(dropped.set, amp_spec.result_of(refusal: dropped.refusal))
      })
      == case_.dropped
      as { case_.why <> ": one drop for each set the check refuses" }
    list.each(case_.kept, fn(set) {
      assert list.map(
          limited_action_set.held_amps(saved: judged.saved, set:),
          fn(id) { id.value },
        )
        == list.filter_map(case_.stored, fn(row) {
          case row.0 == set {
            True -> Ok(row.1)
            False -> Error(Nil)
          }
        })
        as { case_.why <> ": a kept list is whole, in id order" }
    })
  }
  list.each(
    [
      StoredAmps(
        7,
        10,
        in_sets([0, 2], chain),
        [0, 2],
        [],
        "L10 Spellslinger: 7 of 7 power, in set 0 and set 2 alike",
      ),
      StoredAmps(
        7,
        9,
        in_sets([0, 2], chain),
        [],
        [#(0, 31), #(2, 31)],
        "L9 gives no power: each set's list is dropped whole, none is kept",
      ),
      StoredAmps(
        7,
        10,
        list.append(in_sets([0], [220, 221, 222]), [#(0, 23)]),
        [],
        [#(0, 4)],
        "23 is a Warrior's AMP among a Spellslinger's: the whole list goes, not 23 alone",
      ),
      StoredAmps(
        7,
        10,
        in_sets([0], [259]),
        [],
        [#(0, 33)],
        "259 is a tier 1 AMP with 0 power spent in tier 0, under 3",
      ),
      StoredAmps(
        7,
        10,
        [#(0, 259), #(1, 220), #(1, 221)],
        [1],
        [#(0, 33)],
        "judging is for each set: set 0's refused list goes, set 1's good one stays",
      ),
      StoredAmps(
        7,
        10,
        [#(0, 220), #(0, 977)],
        [],
        [#(0, 35)],
        "977 has no row (the entry drops what the tables no longer hold, as the check refuses it)",
      ),
    ],
    fn(case_) { judge(tables, case_) },
  )
  // A row no client row holds: 221 moved to another class, and a power of 3 at level 10.
  {
    use tables <- fixture_tables.changed(
      table: "EldanAugmentation",
      id: 221,
      with: [#("classId", Integer(4))],
    )
    judge(
      tables,
      StoredAmps(
        7,
        10,
        in_sets([0], chain),
        [],
        [#(0, 4)],
        "221 is changed to Medic's: the table, not the entry, says whose it is",
      ),
    )
  }
  {
    use tables <- fixture_tables.changed(table: "GameFormula", id: 942, with: [
      #("dataint01", Integer(3)),
    ])
    judge(
      tables,
      StoredAmps(
        7,
        10,
        in_sets([0], chain),
        [],
        [#(0, 31)],
        "the power is 3 and the list costs 7: a changed table drops a list that was saved",
      ),
    )
  }
  // The entry warns once for each set it drops, and none for a list it keeps.
  let warnings = fn(level) {
    let assert world_entry.InTheWorld(effects:, ..) =
      world_entry_support.joined_with_action_sets(
        class_id: 7,
        level:,
        action_sets: support.with_rows(
          slots: [],
          tiers: [],
          amps: in_sets([0, 2], [220]),
        ),
        unset: [],
      )
      as "the entry puts the player in the world"
    list.filter_map(effects, fn(effect) {
      case effect {
        world_entry.Warn(text:) -> Ok(text)
        _ -> Error(Nil)
      }
    })
  }
  assert warnings(10) == [] as "a list the check passes warns of nothing"
  let dropped = warnings(9)
  assert list.length(dropped) == 2
    as "the entry warns once for each of the two sets it drops"
  assert list.all(dropped, string.contains(_, "NotEnoughPower"))
    && list.any(dropped, string.contains(_, "action set 0"))
    && list.any(dropped, string.contains(_, "action set 2"))
    as "each warning names its set and the check's refusal"
}

/// What a load of tier rows leads to: the tiers kept as (set, Spell4Base, tier) in set then
/// Spell4Base order, or the refused row.
type Tiering {
  Keeps(tiers: List(#(Int, Int, Int)))
  RefusesTier(error: limited_action_set.RowError)
}

/// The tiers a `Saved` holds as (set, Spell4Base, tier), in set then Spell4Base order.
fn kept_tiers(saved saved: limited_action_set.Saved) -> List(#(Int, Int, Int)) {
  list.flat_map([0, 1, 2, 3], fn(set) {
    list.map(limited_action_set.held_tiers(saved:, set:), fn(held) {
      #(set, { held.0 }.value, held.1)
    })
  })
}

/// One row of the entering table: a level, the points the level gives, the saved tiers
/// (set, Spell4Base, tier) and what the entry keeps, with the reason.
type TierCase {
  TierCase(
    why: String,
    level: Int,
    points: Int,
    saved: List(#(Int, Int, Int)),
    expected: Tiering,
  )
}

pub fn entering_keeps_a_saved_tier_the_player_still_holds_and_drops_one_the_book_the_tables_the_level_or_the_points_no_longer_allow_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- spell_tables.with_paralytic_surge_tiers_2_to_8_missing
  let tiers = spell_tier.tiers(tables:)
  // Charged Shot, Ignite, a third Spell4Base with nine tiers, Paralytic Surge with tiers 1 and 9
  // only, and Quick Draw: the abilities of the book these rows are judged against.
  let charged_shot = 20_684
  let ignite = 20_718
  let nine_tiers = 23_148
  let two_tiers = spell_tables.paralytic_surge
  let quick_draw = 27_638
  let unheld = 18_309
  let book =
    list.map(
      [charged_shot, ignite, nine_tiers, two_tiers, quick_draw],
      Spell4BaseId,
    )
  // Quick Draw, Charged Shot, Ignite and the third base cost 1, 1, 1, 5 for tiers 2 to 5, then
  // 1, 1, 1, 5 to tier 9: 8 points to tier 5, 2 to tier 3 and 16 to tier 9 (`Spell4.abilityPointCost`),
  // checked below against the rows. Paralytic Surge costs 5 for tier 9.
  let cost = fn(base, tier) {
    points_cost(tables:, held: [#(Spell4BaseId(base), tier)])
  }
  assert cost(quick_draw, 5) == 8
  assert cost(quick_draw, 3) == 2
  assert cost(ignite, 2) == 1
  assert cost(ignite, 9) == 16
  assert cost(two_tiers, 9) == 5
  assert cost(nine_tiers, 9) == 16
  assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(nine_tiers), tier: 9)
    |> result.is_ok
    as "the third base has a tier 9 row"
  assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(unheld), tier: 9)
    |> result.is_ok
    as "the base the book does not hold has a tier 9 row"
  assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(unheld), tier: 2)
    |> result.is_ok
    as "the base the book does not hold has a tier 2 row, so only the book drops it"
  assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(two_tiers), tier: 5)
    |> result.is_error
    as "Paralytic Surge has no row for tier 5 here"
  assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(quick_draw), tier: 10)
    |> result.is_error
    as "Quick Draw has no row for tier 10"
  let outside = fn(set, base, tier) {
    store.AbilityTierRow(action_set: set, spell4_base_id: base, tier:)
  }
  let cases = [
    TierCase(
      "level 25 gives 16 points: Quick Draw and Charged Shot at tier 5 cost 8 each, so both stay",
      25,
      16,
      [#(0, quick_draw, 5), #(0, charged_shot, 5)],
      Keeps([#(0, charged_shot, 5), #(0, quick_draw, 5)]),
    ),
    TierCase(
      "the same with Ignite at tier 2 is 17 of 16: the set costs more than the level gives, so every tier of it is reset to tier 1 and its points are refunded (the server's choice)",
      25,
      16,
      [#(0, quick_draw, 5), #(0, charged_shot, 5), #(0, ignite, 2)],
      Keeps([]),
    ),
    TierCase(
      "level 45 gives 36 points: tier 9 of Charged Shot, Ignite and the third base is 48 and Quick Draw's tier 3 makes 50, so every tier of the set is reset (the server's choice)",
      45,
      36,
      [
        #(0, charged_shot, 9),
        #(0, ignite, 9),
        #(0, nine_tiers, 9),
        #(0, quick_draw, 3),
      ],
      Keeps([]),
    ),
    TierCase(
      "a tier the book does not hold is dropped before the points are summed, so the rest of the 16 points' worth stays",
      25,
      16,
      [#(0, quick_draw, 5), #(0, charged_shot, 5), #(0, unheld, 9)],
      Keeps([#(0, charged_shot, 5), #(0, quick_draw, 5)]),
    ),
    TierCase(
      "a tier the level does not reach is dropped before the points are summed: at level 14 (5 points) Quick Draw's tier 5 needs level 25 and would make the sum 11, but it is dropped and the three tier-2 rows (3 points) stay",
      14,
      5,
      [
        #(0, charged_shot, 2),
        #(0, ignite, 2),
        #(0, nine_tiers, 2),
        #(0, quick_draw, 5),
      ],
      Keeps([
        #(0, charged_shot, 2),
        #(0, ignite, 2),
        #(0, nine_tiers, 2),
      ]),
    ),
    TierCase(
      "a set over its points is reset on its own: set 0 costs 17 of 16 and falls, set 2 costs 16 and stays",
      25,
      16,
      [
        #(0, quick_draw, 5),
        #(0, charged_shot, 5),
        #(0, ignite, 2),
        #(2, quick_draw, 5),
        #(2, charged_shot, 5),
      ],
      Keeps([#(2, charged_shot, 5), #(2, quick_draw, 5)]),
    ),
    TierCase(
      "a base the book does not hold is dropped",
      25,
      16,
      [#(0, unheld, 2)],
      Keeps([]),
    ),
    TierCase(
      "tier 5 of Paralytic Surge has no Spell4 row here and is dropped",
      50,
      41,
      [#(0, two_tiers, 5)],
      Keeps([]),
    ),
    TierCase(
      "tier 9 of Paralytic Surge has one and is kept",
      50,
      41,
      [#(0, two_tiers, 9)],
      Keeps([#(0, two_tiers, 9)]),
    ),
    TierCase(
      "tier 3 needs level 15 (Spell4TierRequirements): dropped at 14, which gives 5 points",
      14,
      5,
      [#(0, quick_draw, 3)],
      Keeps([]),
    ),
    TierCase(
      "and kept at 15, which gives 6",
      15,
      6,
      [#(0, quick_draw, 3)],
      Keeps([#(0, quick_draw, 3)]),
    ),
    TierCase(
      "tier 10 of Quick Draw has no Spell4 row, even at level 50",
      50,
      41,
      [#(0, quick_draw, 10)],
      Keeps([]),
    ),
    TierCase(
      "each set is judged on its own total, so both sets keep what 16 points buy",
      25,
      16,
      [
        #(0, quick_draw, 5),
        #(0, charged_shot, 5),
        #(2, quick_draw, 5),
        #(2, charged_shot, 5),
      ],
      Keeps([
        #(0, charged_shot, 5),
        #(0, quick_draw, 5),
        #(2, charged_shot, 5),
        #(2, quick_draw, 5),
      ]),
    ),
    TierCase(
      "a set 3 tier with no saved bar is kept, and its bar stays the class's",
      10,
      1,
      [#(3, quick_draw, 2)],
      Keeps([#(3, quick_draw, 2)]),
    ),
    TierCase(
      "a tier row of tier 1, which the table's check refuses",
      50,
      41,
      [#(0, quick_draw, 1)],
      RefusesTier(RowOutsideTable(row: StoredTier(outside(0, quick_draw, 1)))),
    ),
    TierCase(
      "a tier row of tier 16, wider than the 4 bits of the message",
      50,
      41,
      [#(0, quick_draw, 16)],
      RefusesTier(RowOutsideTable(row: StoredTier(outside(0, quick_draw, 16)))),
    ),
    TierCase(
      "a tier row of set 4",
      50,
      41,
      [#(4, quick_draw, 2)],
      RefusesTier(RowOutsideTable(row: StoredTier(outside(4, quick_draw, 2)))),
    ),
    TierCase(
      "a tier row of ability 0",
      50,
      41,
      [#(0, 0, 2)],
      RefusesTier(RowOutsideTable(row: StoredTier(outside(0, 0, 2)))),
    ),
    TierCase(
      "a tier row of ability 262144, wider than the 18 bits of the message",
      50,
      41,
      [#(0, 262_144, 2)],
      RefusesTier(RowOutsideTable(row: StoredTier(outside(0, 262_144, 2)))),
    ),
    TierCase(
      "two tier rows for one ability of one set, which the primary key refuses",
      50,
      41,
      [#(0, quick_draw, 2), #(0, quick_draw, 3)],
      RefusesTier(RowRepeated(row: StoredTier(outside(0, quick_draw, 3)))),
    ),
  ]
  list.each(cases, fn(case_) {
    assert ability_points.total(tables:, level: case_.level) == case_.points
      as { case_.why <> " (the points the level gives, XpPerLevel)" }
    let got =
      limited_action_set.entering(
        unlocks: limited_action_set.unlocks(tables:),
        amps: amp_spec.specs(tables:),
        class_id: ClassId(support.spellslinger),
        tiers:,
        points_total: case_.points,
        level: case_.level,
        book:,
        rows: support.with_rows(slots: [], tiers: case_.saved, amps: []),
      )
    let held = case got {
      Ok(limited_action_set.Judged(saved:, ..)) -> {
        assert limited_action_set.rows(saved:).slots == []
          as { case_.why <> " (no bar was saved, so none is)" }
        Keeps(kept_tiers(saved:))
      }
      Error(error) -> RefusesTier(error)
    }
    assert held == case_.expected as case_.why
  })
  let assert Error(error) =
    limited_action_set.entering(
      unlocks: limited_action_set.unlocks(tables:),
      amps: amp_spec.specs(tables:),
      class_id: ClassId(support.spellslinger),
      tiers:,
      points_total: 41,
      level: 50,
      book:,
      rows: support.with_rows(slots: [], tiers: [#(4, quick_draw, 2)], amps: []),
    )
    as "a tier row of set 4 ends the entry"
  assert string.contains(limited_action_set.describe_row(error:), "set 4")
    && string.contains(limited_action_set.describe_row(error:), "tier")
    as "the sentence names the row's set and says it is a tier row"
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

/// The Spell4Base ids the Spell4 rows give every tier from 2 to 9, sorted: the abilities a
/// saved tier can name that the entry keeps.
fn bases_with_nine_tiers(tables tables: table_store.Tables) -> List(Int) {
  let tiers = spell_tier.tiers(tables:)
  spell4.all(tables)
  |> list.map(fn(row) { row.spell4_base_id_base_spell })
  |> list.unique
  |> list.filter(fn(base) {
    list.all([2, 3, 4, 5, 6, 7, 8, 9], fn(tier) {
      result.is_ok(spell_tier.spell4_id(tiers:, base: Spell4BaseId(base), tier:))
    })
  })
  |> list.sort(int.compare)
}

/// The tier rows of one set the entry cannot drop from these draws (a place in the list of
/// abilities with nine tiers and a tier): the first draw of each ability, in Spell4Base order,
/// while the running cost stays within the points.
fn fitting_tier_rows(
  tables tables: table_store.Tables,
  set set: Int,
  draws draws: List(#(Int, Int, Int)),
  tiered tiered: List(Int),
  points_total points_total: Int,
) -> List(store.AbilityTierRow) {
  let #(_, kept) =
    list.map(draws, fn(draw) {
      #(list.drop(tiered, draw.1) |> list.first |> result.unwrap(0), draw.2)
    })
    |> list.unique
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.fold(#(0, []), fn(so_far, draw) {
      let #(spent, kept) = so_far
      let cost = points_cost(tables:, held: [#(Spell4BaseId(draw.0), draw.1)])
      case
        spent + cost <= points_total
        && !list.any(kept, fn(held: #(Int, Int)) { held.0 == draw.0 })
      {
        True -> #(spent + cost, [draw, ..kept])
        False -> so_far
      }
    })
  list.reverse(kept)
  |> list.map(fn(draw) {
    store.AbilityTierRow(action_set: set, spell4_base_id: draw.0, tier: draw.1)
  })
}

/// The AMP rows of one set the entry cannot drop from these draws, in id order: each drawn id
/// is added to the list when the client's check still accepts the list with it (the check is
/// `amp_spec.check`, which the entry runs on the whole list of a set).
fn fitting_amp_rows(
  specs specs: amp_spec.Specs,
  class_id class_id: ClassId,
  level level: Int,
  set set: Int,
  draws draws: List(Int),
) -> List(store.AmpRow) {
  list.unique(draws)
  |> list.sort(int.compare)
  |> list.fold([], fn(kept, id) {
    let listed = list.append(kept, [EldanAugmentationId(id)])
    case
      result.is_ok(amp_spec.check(
        specs:,
        class_id:,
        level:,
        held: [],
        picks: listed,
      ))
    {
      True -> listed
      False -> kept
    }
  })
  |> list.map(fn(id) {
    store.AmpRow(action_set: set, eldan_augmentation_id: id.value)
  })
}

/// The AMPs a list of draws names: a draw under 70 is a place in the tier 0 AMPs of the class,
/// taken with the AMPs it requires, and any other a place in `any`, taken alone; the first
/// draw of an id keeps its place.
fn drawn_amp_ids(
  tables tables: table_store.Tables,
  tier_zero tier_zero: List(Int),
  any any: List(Int),
  draws draws: List(#(Int, Int)),
) -> List(Int) {
  list.flat_map(draws, fn(draw) {
    let #(kind, place) = draw
    let ids = case kind < 70 {
      True -> tier_zero
      False -> any
    }
    case list.drop(ids, place % list.length(ids)) |> list.first {
      Ok(id) if kind < 70 -> with_requirements(tables:, id:)
      Ok(id) -> [id]
      Error(Nil) -> []
    }
  })
  |> list.unique
}

/// An AMP with the AMPs it requires before it, in the order a list holds them.
fn with_requirements(
  tables tables: table_store.Tables,
  id id: Int,
) -> List(Int) {
  let assert Ok(row) =
    eldan_augmentation.get(tables:, id: EldanAugmentationId(id))
    as "an AMP of the table has a row"
  case row.eldan_augmentation_id_required {
    0 -> [id]
    required -> list.append(with_requirements(tables:, id: required), [id])
  }
}

/// What an accepted AMP save holds, read from the client's rows and GameFormula 942 and not from
/// the rule: the list it sent in id order, at most the power the level gives (no power below
/// dataint0, else `trunc((level - dataint0) * datafloat0) + dataint01`, `0x1403cdbf0`), only
/// AMPs of the player's class, every AMP an AMP requires, and the same save again changing
/// nothing and answering the same frames.
fn assert_an_accepted_amp_save_is_sound(
  tables tables: table_store.Tables,
  class_id class_id: Int,
  level level: Int,
  amp_ids amp_ids: List(Int),
  body body: BitArray,
  after after: limited_action_set.Saved,
  effects effects: List(limited_action_set.Effect),
) -> Nil {
  let assert Ok(formula) = game_formula.get(tables:, id: GameFormulaId(942))
  let power = case level >= formula.dataint0 {
    True ->
      float.truncate(
        int.to_float(level - formula.dataint0) *. formula.datafloat0,
      )
      + formula.dataint01
    False -> 0
  }
  let row_of = fn(id) {
    let assert Ok(row) =
      eldan_augmentation.get(tables:, id: EldanAugmentationId(id))
      as "a held AMP has a row"
    row
  }
  let held = support.held_amp_ids(saved: after, set: 0)
  assert held == list.sort(list.unique(amp_ids), int.compare)
    as "an accepted save keeps the list it sent, ascending"
  assert list.fold(held, 0, fn(cost, id) { cost + row_of(id).power_cost })
    <= power
    as "the AMPs held cost no more than the power the level gives"
  list.each(held, fn(id) {
    assert row_of(id).class_id == class_id
      as "an AMP held is the player's class"
    assert row_of(id).eldan_augmentation_id_required == 0
      || list.contains(held, row_of(id).eldan_augmentation_id_required)
      as "an AMP held has the AMP it requires"
  })
  let #(again, repeated) =
    support.taken_as(class_id:, saved: after, level:, body:)
  assert limited_action_set.rows(saved: again)
    == limited_action_set.rows(saved: after)
    as "the same save again holds the same bar, tiers and AMPs"
  assert support.frames_of(effects: repeated) == support.frames_of(effects:)
    as "the same save again answers the same frames"
}

pub fn any_accepted_amp_list_stays_within_the_levels_power_the_players_class_and_a_repeat_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let classes = [1, 2, 3, 4, 5, 7]
  let rows = eldan_augmentation.all(tables)
  let ids_where = fn(keep) {
    list.filter(rows, keep) |> list.map(fn(row) { row.id })
  }
  // A drawn AMP is a kind and a place: mostly a tier 0 AMP of the player's class with the AMPs it
  // requires (which a list can hold), else any AMP of the class or one of five of class 0.
  let drawn_amp =
    qcheck.tuple2(qcheck.bounded_int(0, 99), qcheck.bounded_int(0, 999))
  let drawn_list =
    qcheck.generic_list(
      elements_from: drawn_amp,
      length_from: qcheck.bounded_int(0, 14),
    )
  qcheck.given(
    qcheck.tuple4(
      qcheck.bounded_int(0, 5),
      qcheck.bounded_int(1, 50),
      drawn_list,
      drawn_list,
    ),
    fn(drawn) {
      let #(class_at, level, first, second) = drawn
      let assert Ok(class_id) = list.drop(classes, class_at) |> list.first
      let tier_zero =
        ids_where(fn(row) { row.class_id == class_id && row.category_tier == 0 })
      let any =
        list.append(
          ids_where(fn(row) { row.class_id == class_id }),
          list.take(ids_where(fn(row) { row.class_id == 0 }), 5),
        )
      let ids_of = fn(draws) {
        drawn_amp_ids(tables:, tier_zero:, any:, draws:)
      }
      // The first save is judged on no AMPs held; the second holds whatever the first left and
      // sends the first list with more.
      let lists = [
        ids_of(first),
        list.unique(list.append(ids_of(first), ids_of(second))),
      ]
      list.fold(lists, limited_action_set.none(), fn(saved, amp_ids) {
        let body = support.amps_body(class_id:, amp_ids:)
        let #(after, effects) =
          support.taken_as(class_id:, saved:, level:, body:)
        case
          support.the_action_set(frames: support.frames_of(effects:)).result
        {
          1 ->
            assert_an_accepted_amp_save_is_sound(
              tables:,
              class_id:,
              level:,
              amp_ids:,
              body:,
              after:,
              effects:,
            )
          _ -> Nil
        }
        after
      })
      Nil
    },
  )
}

pub fn saved_sets_round_trip_through_their_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let unlocks = limited_action_set.unlocks(tables:)
  let tiered = bases_with_nine_tiers(tables:)
  let tiered_count = list.length(tiered)
  assert tiered_count > 4
    as "the Spell4 rows give several abilities all nine tiers"
  let level = 100
  let points_total = ability_points.total(tables:, level:)
  let drawn_set =
    qcheck.option_from(qcheck.fixed_length_list_from(
      qcheck.option_from(qcheck.bounded_int(1, 262_143)),
      12,
    ))
  // A drawn tier is a set, a place in the list of abilities with nine tiers and a tier from 2
  // to 9, so every drawn tier has a Spell4 row.
  let drawn_tier =
    qcheck.tuple3(
      qcheck.bounded_int(0, 3),
      qcheck.bounded_int(0, tiered_count - 1),
      qcheck.bounded_int(2, 9),
    )
  // A drawn AMP is a set and the id of an AMP row of the player's class; a set keeps the
  // draws the client's check accepts as a list (`fitting_amp_rows`).
  let class_amps =
    list.filter_map(eldan_augmentation.all(tables), fn(row) {
      case row.class_id == support.spellslinger {
        True -> Ok(row.id)
        False -> Error(Nil)
      }
    })
  assert class_amps != [] as "the client's rows hold AMPs of the Spellslinger"
  let drawn_amp =
    qcheck.tuple2(
      qcheck.bounded_int(0, 3),
      qcheck.map(qcheck.bounded_int(0, list.length(class_amps) - 1), fn(place) {
        let assert [id, ..] = list.drop(class_amps, place)
          as "the place is inside the list"
        id
      }),
    )
  qcheck.given(
    qcheck.tuple3(
      qcheck.tuple4(drawn_set, drawn_set, drawn_set, drawn_set),
      qcheck.generic_list(
        elements_from: drawn_tier,
        length_from: qcheck.bounded_int(0, 12),
      ),
      qcheck.generic_list(
        elements_from: drawn_amp,
        length_from: qcheck.bounded_int(0, 12),
      ),
    ),
    fn(drawn) {
      let #(sets, drawn_tiers, drawn_amps) = drawn
      // Each set keeps the draws the check accepts as a list, in id order: the AMPs the entry
      // cannot drop.
      let amp_rows =
        list.flat_map([0, 1, 2, 3], fn(set) {
          fitting_amp_rows(
            specs: amp_spec.specs(tables:),
            class_id: ClassId(support.spellslinger),
            level:,
            set:,
            draws: list.filter_map(drawn_amps, fn(amp) {
              case amp.0 == set {
                True -> Ok(amp.1)
                False -> Error(Nil)
              }
            }),
          )
        })
      let rows =
        [sets.0, sets.1, sets.2, sets.3]
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
      // Each set keeps the first draw of an ability and the draws that fit the level's
      // points, in Spell4Base order: the tiers the entry cannot drop.
      let tier_rows =
        list.flat_map([0, 1, 2, 3], fn(set) {
          fitting_tier_rows(
            tables:,
            set:,
            draws: list.filter(drawn_tiers, fn(tier) { tier.0 == set }),
            tiered:,
            points_total:,
          )
        })
      let book =
        list.append(
          list.filter_map(rows, fn(row) {
            option.to_result(row.spell4_base_id, Nil)
            |> result.map(Spell4BaseId)
          }),
          list.map(tiered, Spell4BaseId),
        )
      let held = store.ActionSets(slots: rows, tiers: tier_rows, amps: amp_rows)
      let assert Ok(limited_action_set.Judged(saved:, ..)) =
        limited_action_set.entering(
          unlocks:,
          amps: amp_spec.specs(tables:),
          class_id: ClassId(support.spellslinger),
          level:,
          book:,
          tiers: spell_tier.tiers(tables:),
          points_total:,
          rows: held,
        )
        as "rows the table's checks hold are read"
      assert limited_action_set.rows(saved:) == held
        as "a saved set is twelve rows, in set then slot order, and no set gives none; the tiers are a row for each above tier 1, in set then Spell4Base order; the AMPs are a row for each, in set then id order"
      let assert Ok(limited_action_set.Judged(saved: again, ..)) =
        limited_action_set.entering(
          unlocks:,
          amps: amp_spec.specs(tables:),
          class_id: ClassId(support.spellslinger),
          tiers: spell_tier.tiers(tables:),
          points_total:,
          level:,
          book:,
          rows: limited_action_set.rows(saved:),
        )
      assert again == saved as "the rows of the sets read back as the same sets"
    },
  )
}
