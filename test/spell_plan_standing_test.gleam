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
import genesis_prime/game/equip_spell
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
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
  let roots = equip_spell.roots(tables: fixture_tables.shared())
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

pub fn every_standing_root_is_planned_through_the_area_checker_or_left_out_with_an_unbuilt_reason_and_none_fails_the_load_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  // The load of the client's tables plans every root or fails (`client_tables.shared`).
  let tables = client_tables.shared()
  let roots = equip_spell.roots(tables:)
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
  assert list.all(left_out, fn(one) { spell_plan.is_unbuilt(error: one.error) })
    as "a root is left out only for what the server does not build"
  let assert Ok(abilities) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  assert list.all(abilities, fn(one) {
    !list.contains(left_out_ids, one.spell4_id)
  })
    as "a left-out root is not in the later abilities' list, which the ability book and the coverage's later abilities read"
}

pub fn the_coverage_lists_a_planned_standing_root_that_stands_only_in_part_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(report) = standing_root.measure(tables:)
  let planned = spell_plan.standing_plans(tables:)
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
}
