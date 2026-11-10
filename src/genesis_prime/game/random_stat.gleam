//// The roll of an item with random stats: which row of each of its random stat groups
//// the item's entries take. The server rolls once, when it makes the item (a purchase or a
//// quest reward), and keeps the result as the item's random-stat word
//// (`genesis_prime/game/random_stat_word`); the client never rolls and never sends the word
//// back (`opcode.0x111.shared_item_random_stats`).
////
//// ```
//// entropy (4 bytes for each kind-2 entry)
////    |  each 4 bytes: a fraction below 1
////    v
//// entry i of the item's ItemStat, kind 2, group g
////    candidates = g's rows the client's builder accepts, minus the rows an earlier
////                 entry of the item took from g
////    row picked = the first whose running weight is above fraction x total weight
////    v
//// choices (entry's 1-based row in g, 0 for an entry that is not kind 2) -> the word
//// ```
////
//// Rules and their evidence:
//// - An entry of kind 2 names an ItemRandomStatGroup and a byte of the word picks its row,
////   in table order (0x14040e6d0, `ItemRandomStat.itemRandomStatGroupId`). The pick is by
////   the rows' weights: the client holds no rule for it (it never rolls), so the weighted
////   pick is the table's own meaning of `weight`, and every client row's weight is 1.
//// - One item's random stats are different stats: an entry never takes a row that an
////   earlier entry of the same group took (Jim's decision on issue 665, 2026-11-10). The
////   client adds two entries on one property when a word names it twice, so this is a
////   server choice and no client rule.
//// - A row the client's builder refuses (0x95) is no candidate, since a word naming it
////   makes the client drop every instance property of the item (0x70): a shield property on
////   an item that is no shield, a property that is no item property, or one off the
////   item's slot (`genesis_prime/game/item_property.takes_property`).
//// - An item with a group named more times than it has candidates gets no roll (word 0),
////   which the client reads as no data: Item2 37685 is a weapon whose ItemStat names the
////   shield group.
//// - Entries of kind 4 get no roll, so crafting and gathering work on the real client
////   (open issue #53) is where they are given a property. Loot is made by open issue #58.

import genesis_prime/game/hit
import genesis_prime/game/item_property
import genesis_prime/game/random_stat_word
import genesis_prime/table/item_random_stat.{type ItemRandomStat}
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// The bytes of entropy for each kind-2 entry: one fraction.
const bytes_per_entry = 4

/// The bytes of entropy one roll of the item needs: 4 for each kind-2 entry of its
/// ItemStat, 0 for an item with none, or for an item that gets no roll.
pub fn roll_bytes(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Int {
  case choices(tables:, item2_id:, fractions: []) {
    Ok(#(_, used)) -> used * bytes_per_entry
    Error(Nil) -> 0
  }
}

/// The random-stat word of one roll of the item: 0 for an item that gets no roll. The
/// `entropy` is exactly `roll_bytes` long.
pub fn roll(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  entropy entropy: BitArray,
) -> Int {
  case choices(tables:, item2_id:, fractions: fractions(entropy:)) {
    Ok(#(choices, _)) -> random_stat_word.of_choices(choices:)
    Error(Nil) -> 0
  }
}

/// The words of `count` rolls of the item, each from its own `roll_bytes` of `entropy`.
pub fn roll_many(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  count count: Int,
  entropy entropy: BitArray,
) -> List(Int) {
  let each = roll_bytes(tables:, item2_id:)
  list.repeat(Nil, count)
  |> list.index_map(fn(_, index) {
    let assert Ok(part) = bit_array.slice(entropy, index * each, each)
      as "the caller drew roll_bytes for each roll"
    roll(tables:, item2_id:, entropy: part)
  })
}

fn fractions(entropy entropy: BitArray) -> List(Float) {
  case entropy {
    <<number:size(32), rest:bits>> -> [
      hit.fraction(number),
      ..fractions(entropy: rest)
    ]
    _ -> []
  }
}

/// What a fold over the item's entries carries: the choices so far (last first), the
/// fractions not yet used, the positions taken in each group and the number of kind-2
/// entries seen.
type Fold {
  Fold(
    chosen: List(Int),
    left: List(Float),
    taken: Dict(Int, List(Int)),
    used: Int,
  )
}

/// Each entry's choice and the number of kind-2 entries, or `Error(Nil)` when a group is
/// named more times than it has candidates. An entry with no fraction left takes the first
/// candidate, which is how `roll_bytes` counts.
fn choices(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  fractions fractions: List(Float),
) -> Result(#(List(Int), Int), Nil) {
  use entries <- result.try(
    item_property.stat_entries_of(tables:, item2_id:)
    |> result.replace_error(Nil),
  )
  list.try_fold(
    entries,
    Fold(chosen: [], left: fractions, taken: dict.new(), used: 0),
    fn(fold, entry) {
      case entry {
        #(2, group_id) -> {
          let #(fraction, left) = case fold.left {
            [first, ..rest] -> #(first, rest)
            [] -> #(0.0, [])
          }
          use #(position, taken) <- result.map(pick(
            tables:,
            item2_id:,
            group_id:,
            taken: fold.taken,
            fraction:,
          ))
          Fold(
            chosen: [position, ..fold.chosen],
            left:,
            taken:,
            used: fold.used + 1,
          )
        }
        _ -> Ok(Fold(..fold, chosen: [0, ..fold.chosen]))
      }
    },
  )
  |> result.map(fn(fold) { #(list.reverse(fold.chosen), fold.used) })
}

/// The 1-based position in the group of the row an entry takes, and the positions taken
/// in each group so far.
fn pick(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  group_id group_id: Int,
  taken taken: Dict(Int, List(Int)),
  fraction fraction: Float,
) -> Result(#(Int, Dict(Int, List(Int))), Nil) {
  let held = result.unwrap(dict.get(taken, group_id), [])
  let candidates =
    item_property.random_group(tables:, group_id:)
    |> list.index_map(fn(row, index) { #(index + 1, row) })
    |> list.filter(fn(candidate) {
      let #(position, row) = candidate
      !list.contains(held, position) && accepted(tables:, item2_id:, row:)
    })
  case candidates {
    [] -> Error(Nil)
    _ -> {
      let total =
        list.fold(candidates, 0.0, fn(sum, candidate) {
          sum +. { candidate.1 }.weight
        })
      let position =
        weighted(candidates:, target: fraction *. total, before: 0.0)
      Ok(#(position, dict.insert(taken, group_id, [position, ..held])))
    }
  }
}

/// The position of the first candidate whose running weight is above the target, the
/// last when rounding leaves none.
fn weighted(
  candidates candidates: List(#(Int, ItemRandomStat)),
  target target: Float,
  before before: Float,
) -> Int {
  case candidates {
    [] -> panic as "pick keeps at least one candidate"
    [#(position, _)] -> position
    [#(position, row), ..rest] -> {
      let running = before +. row.weight
      case running >. target {
        True -> position
        False -> weighted(candidates: rest, target:, before: running)
      }
    }
  }
}

/// Whether the client's builder accepts the row for the item: a property row whose
/// property the item takes.
fn accepted(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  row row: ItemRandomStat,
) -> Bool {
  row.item_stat_type_enum == 1
  && item_property.takes_property(
    tables:,
    item2_id:,
    property_id: row.item_stat_data,
  )
}
