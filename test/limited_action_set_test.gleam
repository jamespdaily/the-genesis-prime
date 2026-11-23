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

import client_tables
import fixture_tables
import genesis_prime/game/ability_book
import genesis_prime/game/limited_action_set.{
  Player, RowOutsideTable, RowRepeated,
}
import genesis_prime/game/loadout
import genesis_prime/game/prerequisite
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

/// A row of the accepted table: the level, the bodies sent in turn from no saved set, and the
/// ids the bar holds after them.
type Accepted {
  Accepted(level: Int, bodies: List(BitArray), expected: List(Int), why: String)
}

pub fn a_save_the_stock_builder_sends_is_accepted_and_becomes_the_set_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let zeros = list.repeat(0, 12)
  list.each(
    [
      Accepted(
        4,
        [message_support.hex(support.save_a)],
        support.ids_a,
        "the sitting's save, sequence 16176",
      ),
      Accepted(
        4,
        [
          message_support.hex(support.save_a),
          message_support.hex(support.save_b),
        ],
        support.ids_b,
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
        "one removed, sequence 16356",
      ),
      Accepted(
        4,
        [message_support.hex(support.save_a), support.body(ids: zeros, set: 0)],
        zeros,
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
        "an alternate in the book is accepted: the client's book holds alternates",
      ),
    ],
    fn(case_) {
      let Accepted(level:, bodies:, expected:, why:) = case_
      let saved =
        list.fold(bodies, limited_action_set.none(), fn(saved, body) {
          let #(saved, effects) = support.taken(saved:, level:, body:)
          assert support.the_action_set(frames: support.frames_of(effects:)).result
            == 1
            as { why <> ": every save of the row is accepted" }
          saved
        })
      assert support.held_ids(tables:, saved:) == expected as why
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
  list.each(
    [
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
      let assert Ok(#(after, effects)) =
        limited_action_set.take(
          unlocks: limited_action_set.unlocks(tables:),
          player: Player(..support.player(tables:, level:), dead:, in_combat:),
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
    },
  )
}

pub fn the_answer_is_the_set_then_0xb2_and_a_refusal_carries_the_result_and_the_held_set_test() -> Nil {
  use <- owned_test.run(60_000)
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
  // Accepted from no set: the set 0, unlocked, result 1, the twelve shortcuts, then bit 1.
  let #(_, accepted) =
    support.taken(
      saved: limited_action_set.none(),
      level: 4,
      body: message_support.hex(support.save_a),
    )
  let frames = support.frames_of(effects: accepted)
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x019D, 0x00B2]
    as "the set, then the answer: no tiers and no points"
  assert support.the_action_set(frames:)
    == action_set.ActionSet(
      action_set_index: 0,
      unlocked: 1,
      result: 1,
      shortcuts: shortcuts(support.ids_a),
    )
  assert support.the_answer_bit(frames:) == 1
  assert support.logs_of(effects: accepted) == []
  // Refused from the set of A: the result, the twelve shortcuts of the held set, bit 0, a warning.
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

pub fn tier_changes_and_amps_in_a_save_are_dropped_and_the_bar_is_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let #(saved, effects) =
    support.taken(
      saved: limited_action_set.none(),
      level: 10,
      body: message_support.hex(support.save_d),
    )
  assert support.held_ids(tables:, saved:) == support.ids_a
    as "the bar of the save is kept"
  let #(_, plain) =
    support.taken(
      saved: limited_action_set.none(),
      level: 10,
      body: message_support.hex(support.save_a),
    )
  assert support.frames_of(effects:) == support.frames_of(effects: plain)
    as "the answer is the accepted answer of a save with no edits"
  let assert [#(LogDebug, line)] = support.logs_of(effects:) as "one debug line"
  assert string.contains(line, "2 tier changes and 2 AMPs")
    as "it says how many were not applied"
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
          book: ability_book.book(tables:, loadout: held, level:),
          dead: False,
          in_combat: False,
        )
      let assert Ok(#(saved, effects)) =
        limited_action_set.take(
          unlocks:,
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
