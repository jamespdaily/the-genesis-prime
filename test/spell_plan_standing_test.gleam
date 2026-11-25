//// The plans of the spells a worn item puts on its wearer
//// (`genesis_prime/game/equip_spell`, `genesis_prime/game/spell_plan` `standing_plans`).
//// Expected values come from these places.
//// - `ItemSpecial.spell4IdOnEquip` of an Item2 row's `itemSpecialId00`: 91747 and 85762
////   name ItemSpecial 9402, whose equip spell is Spell4 82325 (the shield-depleted proc);
////   61522 names 9565, equip spell 83570 and use spell 83572; ItemSpecial 9261 names the
////   equip spell 81886 and only the rune Item2 80982 names it; ItemSpecial 3204 names the
////   equip spell 4436 and no Item2 row names it; Item2 15588 names ItemSpecial 4811, equip
////   spell 32599 (`table_rows -- Item2 ItemSpecial`).
//// - `item_property.is_slotted`: the flags of an item's type, category and family hold
////   0x400, and the proxy flag (`Item2.flags` 0x4000, Item2 15588) is refused
////   (`CheckItemEquipSlot 0x1403b11b0`); a rune (family 33, Item2 80982) holds no slot.
//// - `effect_row_read.first_unplayed`: the first row of a tree no cast plays. The five
////   roots below hold one (the review of the step's list, from the client's rows): Spell4
////   83579 row 220935 (type 14), 82334 row 216644 (type 5), 82321 row 216618 (type 14),
////   82318 row 216612 (type 138) and 82336 row 216649 (type 138).

import client_tables
import fixture_tables
import genesis_prime/coverage/standing_root
import genesis_prime/game/amp_spec
import genesis_prime/game/equip_spell
import genesis_prime/game/item_property
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest

type Row {
  Row(spell4_id: Int, root: Bool, why: String)
}

fn rows() -> List(Row) {
  [
    Row(
      82_325,
      True,
      "Item2 91747 (Item2Type 53, slotted) names ItemSpecial 9402, whose equip spell it is",
    ),
    Row(
      83_570,
      True,
      "Item2 61522 (slotted) names ItemSpecial 9565, whose equip spell it is",
    ),
    Row(
      81_886,
      False,
      "only the rune Item2 80982 (family 33, no slot) names ItemSpecial 9261",
    ),
    Row(
      83_572,
      False,
      "it is the use spell of ItemSpecial 9565, not an equip spell",
    ),
    Row(4436, False, "no Item2 row names ItemSpecial 3204, its only holder"),
    Row(
      32_599,
      False,
      "Item2 15588 carries the proxy flag 0x4000, which is_slotted refuses",
    ),
  ]
}

pub fn which_equip_spells_are_standing_roots_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(roots) = equip_spell.roots(tables: fixture_tables.shared())
  list.each(rows(), fn(row) {
    assert list.contains(roots, row.spell4_id) == row.root
      as {
        "Spell4 "
        <> int.to_string(row.spell4_id)
        <> case row.root {
          True -> " is a root: "
          False -> " is not a root: "
        }
        <> row.why
      }
  })
}

/// A worn item and the column that names a row no table holds, with the table and id the
/// load's error must name. No client row has any of these (every Item2 row of the client's
/// tables names a type, category, family and special its tables hold), so each is planted
/// on Item2 91747 (equip spell 82325).
type MissingRow {
  MissingRow(column: String, table: String, id: Int)
}

fn missing_rows() -> List(MissingRow) {
  [
    MissingRow("item2TypeId", "Item2Type", 999_001),
    MissingRow("item2CategoryId", "Item2Category", 999_002),
    MissingRow("item2FamilyId", "Item2Family", 999_003),
    MissingRow("itemSpecialId00", "ItemSpecial", 999_004),
  ]
}

pub fn a_worn_item_whose_type_category_family_or_special_row_is_missing_fails_the_load_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(missing_rows(), fn(missing) {
    let assert Ok(rows) =
      fixture_tables.change_all(rows: fixture_tables.rows(), edits: [
        #("Item2", 91_747, [#(missing.column, Integer(missing.id))]),
      ])
    let expected = item_property.NoRow(table: missing.table, id: missing.id)
    let why = "Item2 91747 with a missing " <> missing.table <> " row"
    let assert Ok(tables) =
      fixture_tables.edited(
        rows:,
        entries: server_table.entries(),
        requirements: [],
        derivations: [],
      )
    assert equip_spell.roots(tables:) == Error(expected)
      as { why <> ": the roots return the error naming the table and the id" }
    assert spell_plan.standing_unplanned(
        tables:,
        area_checked: spell_area.checker,
      )
      == Error(spell_plan.EquipItemNotRead(error: expected))
      as { why <> ": the plans fail with the item's error, not an unbuilt one" }
    assert spell_plan.refusal_of(error: spell_plan.EquipItemNotRead(expected)).outcome
      == spell_plan.FailsLoad
      as { why <> ": it is no unbuilt reason" }
    let assert Error(load_error) =
      fixture_tables.load(rows: fixture_tables.closure(rows:, roots: []))
      as { why <> ": the tables' load fails" }
    let message = table_store.describe(load_error)
    assert string.contains(message, missing.table)
      && string.contains(message, int.to_string(missing.id))
      as {
        why <> ": the load's message names the table and the id: " <> message
      }
    assert spell_plan.describe(error: spell_plan.EquipItemNotRead(expected))
      == item_property.describe(error: expected)
      as { why <> ": the plans' sentence is the item's" }
  })
}

pub fn every_standing_root_is_planned_through_the_area_checker_or_left_out_with_an_unbuilt_reason_and_none_fails_the_load_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  // The load of the client's tables plans every root or fails (`client_tables.shared`).
  let tables = client_tables.shared()
  let assert Ok(roots) = equip_spell.roots(tables:)
  let planned = spell_plan.standing_plans(tables:)
  let assert Ok(left_out) =
    spell_plan.standing_unplanned(tables:, area_checked: spell_area.checker)
  let left_out_ids = list.map(left_out, fn(one) { one.spell4_id })
  assert roots != []
    as "the client's tables hold worn items with an equip spell"
  assert list.all(roots, fn(root) {
    dict.has_key(planned, root) != list.contains(left_out_ids, root)
  })
    as "each root is planned or left out, never both and never neither"
  assert list.length(left_out_ids) + dict.size(planned) == list.length(roots)
    as "the plans and the left-out list hold the roots and nothing else"
  assert list.all(left_out, fn(one) {
    spell_plan.refusal_of(error: one.error).outcome == spell_plan.LeavesOut
  })
    as "a root is left out only for what the server does not build"
  let assert Ok(abilities) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  assert list.all(abilities, fn(one) {
    !list.contains(left_out_ids, one.spell4_id)
  })
    as "a left-out root is not in the later abilities' list, which the ability book and the coverage's later abilities read"
  // The spells of the AMPs of the playable classes are roots of their own plans.
  let assert Ok(amp_found) = amp_spec.roots(tables:)
  let amp_roots =
    list.append(
      amp_found.spells,
      list.map(amp_found.unlocking, fn(unlocking) { unlocking.spell4_id.value }),
    )
  let amp_planned = spell_plan.amp_plans(tables)
  let amp_left_out = spell_plan.unplanned_amps(tables)
  let amp_left_out_ids = list.map(amp_left_out, fn(one) { one.spell4_id })
  assert amp_roots != []
    as "the client's tables hold AMPs of the playable classes"
  assert list.all(amp_roots, fn(root) {
    dict.has_key(amp_planned, root) != list.contains(amp_left_out_ids, root)
  })
    as "each AMP spell is planned or left out, never both and never neither"
  assert list.length(amp_left_out_ids) + dict.size(amp_planned)
    == list.length(amp_roots)
    as "the AMP plans and the left-out list hold the AMP spells and nothing else"
  assert list.all(amp_left_out, fn(one) {
    spell_plan.refusal_of(error: one.error).outcome == spell_plan.LeavesOut
  })
    as "an AMP spell is left out only for what the server does not build"
  let unlocking =
    list.filter(amp_left_out, fn(one) {
      case one.error {
        spell_plan.AmpUnlocksClassAbility(..) -> True
        _ -> False
      }
    })
  assert list.length(unlocking) == 18
    as "the 18 AMPs the client's type 227 Prerequisite rows name are each left out as unlocking a class ability"
  assert list.all(unlocking, fn(one) {
    string.ends_with(
      spell_plan.describe(error: one.error),
      " unlocks a class ability, not built",
    )
  })
    as "with the reason stated"
  assert list.all(abilities, fn(one) {
    !list.contains(amp_left_out_ids, one.spell4_id)
  })
    as "a left-out AMP spell is not in the later abilities' list"
  assert list.all(left_out_ids, fn(id) { !list.contains(amp_left_out_ids, id) })
    as "and not in the equip spells' list"
}

pub fn the_coverage_lists_a_planned_standing_root_that_stands_only_in_part_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(report) = standing_root.measure(tables:)
  let planned = spell_plan.standing_plans(tables:)
  assert report.roots == report.planned + list.length(report.left_out)
    as "the report's roots are the planned ones and the left-out ones"
  let assert Ok(roots) = equip_spell.roots(tables:)
  assert report.roots == list.length(roots)
    as "and are the equip spells of the client's worn items, counted from the items"
  list.each(
    [
      #(83_579, "the row 220935 (type 14)"),
      #(82_334, "the row 216644 (type 5)"),
      #(82_321, "the row 216618 (type 14)"),
      #(82_318, "the row 216612 (type 138)"),
      #(82_336, "the row 216649 (type 138)"),
    ],
    fn(expected) {
      let #(spell4_id, row) = expected
      assert dict.has_key(planned, spell4_id)
        as { "Spell4 " <> int.to_string(spell4_id) <> " is planned" }
      let assert Ok(#(_, why)) =
        list.find(report.in_part, fn(entry) { entry.0 == spell4_id })
        as {
          "Spell4 "
          <> int.to_string(spell4_id)
          <> " is listed as standing only in part"
        }
      assert string.contains(why, row)
        as { "Spell4 " <> int.to_string(spell4_id) <> " is listed by " <> row }
    },
  )
  assert list.all(report.in_part, fn(entry) { dict.has_key(planned, entry.0) })
    as "only a planned root stands in part"
  assert list.all(report.left_out, fn(entry) {
    !dict.has_key(planned, entry.0) && entry.1 != ""
  })
    as "a left-out root is named with its reason"
  assert string.contains(standing_root.render(report:), "Standing")
    as "the measure prints a line of its own"
  // The spells of the AMPs the plans leave out are listed the same way, apart from the worn
  // items' roots.
  let amps = standing_root.measure_amps(tables:)
  let assert Ok(amp_found) = amp_spec.roots(tables:)
  assert amps.roots
    == list.length(amp_found.spells) + list.length(amp_found.unlocking)
    as "the AMP report's roots are the AMP spells and the unlocking AMPs, counted from the AMP rows"
  assert amps.roots == amps.planned + list.length(amps.left_out)
  assert list.map(amps.left_out, fn(entry) { entry.0 })
    == list.map(spell_plan.unplanned_amps(tables), fn(one) { one.spell4_id })
    as "each AMP spell the plans leave out is listed, with a reason"
  assert list.all(amps.left_out, fn(entry) { entry.1 != "" })
  assert list.count(amps.left_out, fn(entry) {
      string.ends_with(entry.1, " unlocks a class ability, not built")
    })
    == 18
    as "the AMP line lists the 18 AMPs that unlock a class ability, with their reason"
  assert list.all(amps.in_part, fn(entry) {
    dict.has_key(spell_plan.amp_plans(tables), entry.0)
  })
    as "only a planned AMP spell stands in part"
  assert string.contains(standing_root.render(report: amps), "AMP")
    as "the measure prints a line of its own for the AMPs"
}
