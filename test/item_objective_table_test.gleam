//// What the load refuses of an item_objective row (`genesis_prime/game/item_objective_table`
//// `select`): a row names a visible, required, marked scripted objective of count 1 that
//// nothing else completes, and the Item2 and Creature2 rows its text names. Expected values
//// are the rules of `objective.visible_script_broken` (`QuestObjective.type.5`,
//// `QuestObjective.flags.8`, flag 0x20, the creature links) and `objective_action.named`
//// (`Spell4Effects.effectType.42`, `0x140398cc0`), on the client's fixture rows:
//// - objective 4770 (quest 3667, type 5, count 1, one marker): the row every case starts from;
//// - 4120 is type 22, 18311 a hidden type 5, 6150 a type 5 of count 6;
//// - 4849 is named by Spell4Effects 89873 and 6589 by Item2 12448.
//// Three more are edited: 9658 made optional, 9659 a marked type 5 that Creature2 27768's
//// quest columns link, and 4202 a type 5 with its marker taken away.

import genesis_prime/content/refusal
import genesis_prime/game/item_objective.{BuyFrom, Wear}
import genesis_prime/game/item_objective_table.{Buy, Equip, Row}
import genesis_prime/table/id.{Creature2Id, Item2Id}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import quest_support

/// Item2 12631 and the Master Control Panel, Creature2 11194: rows of the client's tables.
const item = 12_631

const vendor = 11_194

/// The objective of quest 3667 every case starts from.
const tower = 4770

pub fn item_objective_select_refuses_what_the_client_does_not_allow_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 0x20),
    #(9658, "data", 0),
    #(9658, "count", 1),
    #(9659, "type", 5),
    #(9659, "flags", 0),
    #(9659, "data", 0),
    #(9659, "count", 1),
    #(9659, "worldLocationsIdIndicator00", 21_383),
    #(4202, "worldLocationsIdIndicator00", 0),
  ])
  let equip = fn(objective_id) {
    Row(objective_id:, kind: Equip, item2_id: item, creature2_id: None)
  }
  let buy = fn(objective_id) {
    Row(objective_id:, kind: Buy, item2_id: item, creature2_id: Some(vendor))
  }
  // (reason, the rows, the objectives the arrival and held tables hold, the objectives refused)
  let cases = [
    #("an equip of a visible marked type 5", [equip(tower)], [], []),
    #("a buy of the same", [buy(tower)], [], []),
    #("an objective that is not type 5", [equip(4120)], [], [4120]),
    #("a hidden objective", [equip(18_311)], [], [18_311]),
    #("an optional objective", [equip(9658)], [], [9658]),
    #("an objective no marker shows", [equip(4202)], [], [4202]),
    #("an objective a creature links", [equip(9659)], [], [9659]),
    #("a count above 1", [equip(6150)], [], [6150]),
    #("an objective a spell effect names", [equip(4849)], [], [4849]),
    #("an objective an item names", [equip(6589)], [], [6589]),
    #("an objective the arrival or held tables list", [equip(tower)], [tower], [
      tower,
    ]),
    #(
      "an Item2 the client lacks",
      [Row(..equip(tower), item2_id: 4_000_000)],
      [],
      [tower],
    ),
    #(
      "a Creature2 the client lacks",
      [Row(..buy(tower), creature2_id: Some(4_000_000))],
      [],
      [tower],
    ),
    #("a buy with no vendor", [Row(..buy(tower), creature2_id: None)], [], [
      tower,
    ]),
    #(
      "an equip with a vendor",
      [Row(..equip(tower), creature2_id: Some(vendor))],
      [],
      [tower],
    ),
    #("two rows for one objective", [equip(tower), buy(tower)], [], [tower]),
  ]
  let wrong =
    list.filter_map(cases, fn(row) {
      let #(reason, rows, taken, refused) = row
      let got = case
        item_objective_table.select(rows:, tables:, taken: set.from_list(taken))
      {
        Ok(_) -> []
        Error(refusals) ->
          list.map(refusals, fn(refused) {
            assert refused.table == "item_objective"
            let assert refusal.RowId(id) = refused.row
            id
          })
          |> list.unique
      }
      case got == refused {
        True -> Error(Nil)
        False -> Ok(#(reason, got))
      }
    })
  assert wrong == []
    as "a row is refused exactly when its objective is not a visible, required, marked, unlinked type 5 of count 1 that nothing else completes, or its Item2 or Creature2 is missing, or its columns disagree on the kind"
  assert item_objective_table.select(
      rows: [equip(tower)],
      tables:,
      taken: set.new(),
    )
    == Ok(dict.from_list([#(tower, Wear(item2_id: Item2Id(item)))]))
    as "an equip names its item"
  assert item_objective_table.select(
      rows: [buy(tower)],
      tables:,
      taken: set.new(),
    )
    == Ok(
      dict.from_list([
        #(tower, BuyFrom(item2_id: Item2Id(item), vendor: Creature2Id(vendor))),
      ]),
    )
    as "a buy names its item and its vendor"
}
