//// The rows of the `item_objective` content table the load checks: the visible scripted
//// objectives that ask the player to wear an item or to buy one from a vendor
//// (genesis_prime/game/item_objective). Each row names the Item2 the objective's text names,
//// and for a buy the vendor's Creature2, a server's rule graded by the text.
////
//// ```
//// content.load: rows ─▶ select(rows, tables, taken) ─▶ Dict(objective id, Wanted) | refusals (the load stops)
//// each connection's settings ─▶ the dict ─▶ objective.settle      ─▶ an Equip row is done while the item is worn
////                                        └▶ objective.purchased  ─▶ a Buy row counts the item bought from its vendor
//// ```
////
//// - **A row must be a script the rules would otherwise stand in for.** The objective is a
////   visible, required, marked script no creature links (`objective.visible_script_broken`
////   is empty in every quest that lists it) with a count of 1, and no spell effect or item
////   names it (`objective_action.named`).
//// - **A row names the tables' rows its text names:** an Item2 row, and for a buy a Creature2
////   row; an equip row names no creature.
//// - **A row is in one table only:** an objective is in no other row of this table, in the
////   arrival objectives or in the held objectives (`taken`).
////
//// The failure points are those of `objective_row`.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/item_objective.{type Wanted, BuyFrom, Wear}
import genesis_prime/game/objective
import genesis_prime/game/objective_action
import genesis_prime/game/objective_row
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// The table's name in the log and in a refusal.
pub const table = "item_objective"

/// What the objective asks of the player, as the table's `kind` column says.
pub type Kind {
  /// Wear the item.
  Equip
  /// Buy the item from the vendor.
  Buy
}

/// One row of the item_objective table as the load reads it: the QuestObjective id, what it
/// asks, the Item2 id of its item and the vendor's Creature2 id (only a buy has one).
pub type Row {
  Row(objective_id: Int, kind: Kind, item2_id: Int, creature2_id: Option(Int))
}

/// The objectives the rows ask for and what each asks, or every row the load refuses.
/// `taken` is the QuestObjective ids of the arrival and held tables, which a row may not
/// repeat.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
  taken taken: Set(Int),
) -> Result(Dict(Int, Wanted), List(Refusal)) {
  let by_objective =
    dict.from_list(list.map(rows, fn(row) { #(row.objective_id, row) }))
  let twice =
    list.filter_map(
      list.unique(list.map(rows, fn(row) { row.objective_id })),
      fn(objective_id) {
        case list.count(rows, fn(row) { row.objective_id == objective_id }) {
          1 -> Error(Nil)
          _ ->
            Ok(Refusal(
              table:,
              row: RowId(objective_id),
              rule: "the objective is in more than one row",
            ))
        }
      },
    )
  let selected =
    objective_row.select(
      table:,
      ids: list.map(rows, fn(row) { row.objective_id }),
      tables:,
      broken: fn(tables, quest, index, listed_objective) {
        let assert Ok(row) =
          dict.get(by_objective, listed_objective.objective_id)
          as "the objective was listed from a row of this table"
        list.flatten([
          objective.visible_script_broken(
            tables:,
            quest_id: quest.id,
            index:,
            objective: listed_objective,
          ),
          case listed_objective.marked {
            True -> []
            False -> [
              "no marker names a WorldLocation2 row, so the objective is not a visible marked script",
            ]
          },
          case listed_objective.count {
            1 -> []
            count -> [
              "its count is " <> int.to_string(count) <> ", not 1",
            ]
          },
          case objective_action.named(tables:, quest_id: quest.id, index:) {
            True -> [
              "a spell effect or an item names it, so a cast advances it",
            ]
            False -> []
          },
          case set.contains(taken, row.objective_id) {
            True -> ["the arrival or held table lists it"]
            False -> []
          },
          row_broken(row:, tables:),
        ])
      },
    )
  case selected, twice {
    Ok(_), [] ->
      Ok(
        dict.map_values(by_objective, fn(_, row) {
          let assert Ok(wanted) = wanted_of(row:)
            as "row_broken refused every row whose columns disagree"
          wanted
        }),
      )
    Ok(_), refusals -> Error(refusals)
    Error(refusals), _ -> Error(list.append(refusals, twice))
  }
}

/// How a row's columns disagree on its kind.
type Disagreement {
  BuyNamesNoVendor
  EquipNamesAVendor
}

/// What the row asks: a buy holds its vendor and an equip none, or the way its columns
/// disagree.
fn wanted_of(row row: Row) -> Result(Wanted, Disagreement) {
  case row.kind, row.creature2_id {
    Buy, Some(vendor) ->
      Ok(BuyFrom(item2_id: Item2Id(row.item2_id), vendor: Creature2Id(vendor)))
    Buy, None -> Error(BuyNamesNoVendor)
    Equip, None -> Ok(Wear(item2_id: Item2Id(row.item2_id)))
    Equip, Some(_) -> Error(EquipNamesAVendor)
  }
}

/// The rules the row's own columns break against the client's tables.
fn row_broken(row row: Row, tables tables: table_store.Tables) -> List(String) {
  list.flatten([
    case item2.get(tables:, id: Item2Id(row.item2_id)) {
      Ok(_) -> []
      Error(Nil) -> [
        "the client's Item2 table has no row " <> int.to_string(row.item2_id),
      ]
    },
    case wanted_of(row:) {
      Error(BuyNamesNoVendor) -> ["a buy names no vendor Creature2"]
      Error(EquipNamesAVendor) -> ["an equip names a vendor Creature2"]
      Ok(Wear(..)) -> []
      Ok(BuyFrom(vendor:, ..)) ->
        case creature2.get(tables:, id: vendor) {
          Ok(_) -> []
          Error(Nil) -> [
            "the client's Creature2 table has no row "
            <> int.to_string(vendor.value),
          ]
        }
    },
  ])
}
