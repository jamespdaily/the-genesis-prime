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
////   earlier entry of the same group took. The client adds two entries on one property
////   when a word names it twice, so this is a server choice and no client rule.
//// - A row the client's builder refuses (0x95) is no candidate, since a word naming it
////   makes the client drop every instance property of the item (0x70): a shield property on
////   an item that is no shield, a property that is no item property, or one off the
////   item's slot (`genesis_prime/game/item_property.takes_property`).
//// - An item with a group named more times than it has candidates gets no roll (word 0),
////   which the client reads as no data: Item2 37685 is a weapon whose ItemStat names the
////   shield group.
//// - An item with an entry of kind 4 gets no roll (word 0), because the client's builder
////   fails a word with data whose kind-4 choice is 0 (0x14040e6d0, 0x50). Crafting and
////   gathering work on the real client (open issue #53) fills a kind-4 entry; loot is made
////   by open issue #58.
//// - A proxy item (Item2.flags 0x4000) gets no roll: the client takes its stats from the
////   Item2 row GameFormula 1214 names, which has no ItemStat (`0x1404445d0.proxy`).

import genesis_prime/game/item_property
import genesis_prime/game/random_stat_word
import genesis_prime/random
import genesis_prime/store.{type NewStack}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/item_random_stat.{type ItemRandomStat}
import genesis_prime/table/loader/store as table_store
import gleam/bool
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

/// The bytes of entropy that rolling each of `stacks` made stacks of the item takes.
pub fn stacks_bytes(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  stacks stacks: List(NewStack),
) -> Int {
  list.length(stacks) * roll_bytes(tables:, item2_id:)
}

/// The stacks with each one's word rolled from the front of `entropy`, which holds at
/// least `stacks_bytes`, and the entropy left after them.
pub fn roll_stacks(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  stacks stacks: List(NewStack),
  entropy entropy: BitArray,
) -> #(List(NewStack), BitArray) {
  let each = roll_bytes(tables:, item2_id:)
  let #(left, rolled) =
    list.map_fold(stacks, entropy, fn(left, stack) {
      let assert <<part:bytes-size(each), rest:bytes>> = left
        as "the caller drew stacks_bytes"
      #(
        rest,
        store.NewStack(
          ..stack,
          random_stats: roll(tables:, item2_id:, entropy: part),
        ),
      )
    })
  #(rolled, left)
}

fn fractions(entropy entropy: BitArray) -> List(Float) {
  case entropy {
    <<number:size(32), rest:bits>> -> [
      random.fraction(number),
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

/// Each entry's choice and the number of kind-2 entries, or `Error(Nil)` for an item that
/// gets no roll: a proxy, an item with a kind-4 entry, or one whose group is named more
/// times than it has candidates. An entry with no fraction left takes the first candidate,
/// which is how `roll_bytes` counts. An item or ItemStat row the tables lack crashes.
fn choices(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  fractions fractions: List(Float),
) -> Result(#(List(Int), Int), Nil) {
  let assert Ok(item) = item2.get(tables:, id: Item2Id(item2_id))
    as "the item is a row of the Item2 table"
  let assert Ok(entries) = item_property.stat_entries_of(tables:, item2_id:)
    as "the item's ItemStat is a row of the ItemStat table"
  use <- bool.guard(item_property.is_proxy(item), Error(Nil))
  use <- bool.guard(list.any(entries, fn(entry) { entry.0 == 4 }), Error(Nil))
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
/// property the item takes. A property the tables or the builder's reading cannot
/// settle crashes.
fn accepted(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  row row: ItemRandomStat,
) -> Bool {
  use <- bool.guard(row.item_stat_type_enum != 1, False)
  let assert Ok(takes) =
    item_property.takes_property(
      tables:,
      item2_id:,
      property_id: row.item_stat_data,
    )
    as "the builder accepts or refuses the property"
  takes
}
