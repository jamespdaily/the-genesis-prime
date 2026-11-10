//// What an item costs in credits at a vendor, as the client's own price code gives it
//// (`opcode.0xbe`, GameFormula 1078): the price the server charges is the price the
//// client's window shows, which is the price the vendor's 0x090B sends.
////
//// ```
//// Item2 row, its Item2Category, Item2Family and Item2Type rows
////   mult  = the three vendorMultiplier values, multiplied
////   curve = GameFormula 1078 at the item's powerLevel
////   buy   = max(1, trunc(curve × quality × mult))      (base)
////   shown = trunc(buy × the vendor's buy multiplier)   (shown)
////   sell  = max(1, trunc(buy × GameFormula 1026's 0.15)) credits  (sell_price), or the row's
////           own SellToVendor amount in its one currency when its currency type columns are set
//// ```
////
//// - **A vendor's sale** is priced as `paid(sell_price, the vendor's sell multiplier)`: a
////   credit price is scaled by the multiplier, a price in any other currency is paid as the
////   row gives it (`0x14041bcc0.formula`).
//// - **Every product is a 32-bit float** (`message/float32`), as the client's code rounds
////   each step, so the price is the client's to the credit.
//// - **A proxy item** (Item2.flags 0x4000) takes its quality from the Item2 its row
////   names (GameFormula 1214) and keeps its own power level.
//// - **Only a credit price is read.** An item whose row names another currency, or a
////   trade skill additive, has no buy price here, and the error names the row: other
////   currencies and the additive are #333's. The computed sell price does not read those
////   columns (`0x14040bfb0` computes it from the computed buy price), so a row with no
////   SellToVendor currency type sells for that whatever they hold.
////
//// | Point | What happens |
//// |---|---|
//// | an Item2, Item2Category, Item2Family, Item2Type or GameFormula row is missing | the error names the table and the id; the vendor load stops |
//// | the row's currencyTypeIds are not both 0 | the error names the item; the vendor load stops |
//// | the row's tradeskillAdditiveId is not 0 | the error names the item; the vendor load stops |
//// | the curve has no value at the item's power level | the error names the formula and the level; the vendor load stops |

import genesis_prime/game/currency
import genesis_prime/game/item_property
import genesis_prime/message/float32
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Item2Id, GameFormulaId, Item2CategoryId, Item2FamilyId, Item2Id,
  Item2TypeId,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/float
import gleam/int
import gleam/result

/// The GameFormula row of the price curve (ItemPriceLevelCurve 0x14041d200).
const price_curve_formula = 1078

/// The GameFormula row whose dataint0 is the Item2 a proxy item takes its quality
/// from (`0x1404445d0.proxy`).
const proxy_formula = 1214

/// The GameFormula row whose datafloat0 is the fraction of the buy price an item sells for
/// (`0x14040bfb0`), read by `sell_price`.
pub const sell_fraction_formula = 1026

/// What an item sells for: an amount of one currency, a CurrencyType row's id.
pub type SellPrice {
  SellPrice(currency_type_id: Int, amount: Int)
}

/// Why an item has no price.
pub type PriceError {
  /// A row the formula reads is not in the client's tables.
  MissingRow(table: String, id: Int)
  /// The item is priced in a currency other than credits.
  OtherCurrency(item2_id: Item2Id)
  /// The row's two SellToVendor slots both hold an amount, which no client row does.
  TwoSellCurrencies(item2_id: Item2Id)
  /// The item's price has a trade skill additive.
  TradeskillAdditive(item2_id: Item2Id, additive_id: Int)
  /// The price curve has no value at the item's power level.
  NoCurveValue(formula: Int, level: Int)
}

/// The item's buy price in credits at a vendor multiplier of 1.0.
pub fn base(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Result(Int, PriceError) {
  let Item2Id(raw_id) = item2_id
  use item <- result.try(
    item2.get(tables:, id: item2_id)
    |> result.replace_error(MissingRow(table: "Item2", id: raw_id)),
  )
  use <- bool.guard(
    item.currency_type_id0 != 0 || item.currency_type_id1 != 0,
    Error(OtherCurrency(item2_id:)),
  )
  use <- bool.guard(
    item.tradeskill_additive_id != 0,
    Error(TradeskillAdditive(
      item2_id:,
      additive_id: item.tradeskill_additive_id,
    )),
  )
  computed_buy(tables:, item:)
}

/// The price the client computes from the row's curve, quality and multipliers, whatever
/// currency the row's own buy columns name (`0x14040bee0`): the buy price when they are
/// both 0, and the price the computed sell price is a fraction of (`0x14040bfb0`).
fn computed_buy(
  tables tables: table_store.Tables,
  item item: item2.Item2,
) -> Result(Int, PriceError) {
  use category <- result.try(
    item2_category.get(tables:, id: Item2CategoryId(item.item2_category_id))
    |> result.replace_error(MissingRow(
      table: "Item2Category",
      id: item.item2_category_id,
    )),
  )
  use family <- result.try(
    item2_family.get(tables:, id: Item2FamilyId(item.item2_family_id))
    |> result.replace_error(MissingRow(
      table: "Item2Family",
      id: item.item2_family_id,
    )),
  )
  use type_row <- result.try(
    item2_type.get(tables:, id: Item2TypeId(item.item2_type_id))
    |> result.replace_error(MissingRow(
      table: "Item2Type",
      id: item.item2_type_id,
    )),
  )
  use quality <- result.try(quality(tables:, item:))
  use curve_row <- result.try(
    game_formula.get(tables:, id: GameFormulaId(price_curve_formula))
    |> result.replace_error(MissingRow(
      table: "GameFormula",
      id: price_curve_formula,
    )),
  )
  use curve <- result.try(
    item_property.curve(row: curve_row, level: item.power_level)
    |> result.replace_error(NoCurveValue(
      formula: price_curve_formula,
      level: item.power_level,
    )),
  )
  let multiplier =
    float32.product(
      left: float32.product(
        left: category.vendor_multiplier,
        right: family.vendor_multiplier,
      ),
      right: type_row.vendor_multiplier,
    )
  let price =
    float32.product(
      left: float32.product(left: float32.rounded(value: curve), right: quality),
      right: multiplier,
    )
  Ok(int.max(1, float.truncate(price)))
}

/// The quality the price multiplies by: the item's quality id as a float, 1.0 for
/// quality 0 (0x14040bee0). A proxy item's quality is its proxy row's.
fn quality(
  tables tables: table_store.Tables,
  item item: item2.Item2,
) -> Result(Float, PriceError) {
  use source <- result.try(case item_property.is_proxy(item) {
    False -> Ok(item)
    True -> {
      use formula <- result.try(
        game_formula.get(tables:, id: GameFormulaId(proxy_formula))
        |> result.replace_error(MissingRow(
          table: "GameFormula",
          id: proxy_formula,
        )),
      )
      item2.get(tables:, id: Item2Id(formula.dataint0))
      |> result.replace_error(MissingRow(table: "Item2", id: formula.dataint0))
    }
  })
  Ok(case source.item_quality_id {
    0 -> 1.0
    quality -> int.to_float(quality)
  })
}

/// The item's sell price at a vendor multiplier of 1.0 (`0x14040d160`): the computed buy
/// price times GameFormula 1026's fraction, at least 1, in credits when neither of the row's
/// SellToVendor currency types is set; else the row's first SellToVendor slot, in its
/// currency. The client's sale check reads the first slot's amount alone (`0x1403d6a10`), so
/// the second slot never prices an item, and a first amount of 0 is a price of 0, which the
/// sale refuses. A row with an amount in both slots is `TwoSellCurrencies`. Whether the item
/// may be sold at all is `item_property.sellable`'s.
pub fn sell_price(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Result(SellPrice, PriceError) {
  let Item2Id(raw_id) = item2_id
  use item <- result.try(
    item2.get(tables:, id: item2_id)
    |> result.replace_error(MissingRow(table: "Item2", id: raw_id)),
  )
  let first =
    SellPrice(
      currency_type_id: item.currency_type_id0_sell_to_vendor,
      amount: item.currency_amount0_sell_to_vendor,
    )
  let second =
    SellPrice(
      currency_type_id: item.currency_type_id1_sell_to_vendor,
      amount: item.currency_amount1_sell_to_vendor,
    )
  case first.currency_type_id != 0 || second.currency_type_id != 0 {
    False -> computed_sell(tables:, item:)
    True if first.amount > 0 && second.amount > 0 ->
      Error(TwoSellCurrencies(item2_id:))
    True -> Ok(first)
  }
}

/// The price the client computes for a row with no SellToVendor currency type
/// (`0x14040bfb0`): the computed buy price times GameFormula 1026's fraction, at least 1.
fn computed_sell(
  tables tables: table_store.Tables,
  item item: item2.Item2,
) -> Result(SellPrice, PriceError) {
  use buy <- result.try(computed_buy(tables:, item:))
  use fraction_row <- result.try(
    game_formula.get(tables:, id: GameFormulaId(sell_fraction_formula))
    |> result.replace_error(MissingRow(
      table: "GameFormula",
      id: sell_fraction_formula,
    )),
  )
  Ok(SellPrice(
    currency_type_id: currency.credits_type,
    amount: int.max(1, shown(base: buy, multiplier: fraction_row.datafloat0)),
  ))
}

/// The price the vendor pays for one item at its sell multiplier: a credit price is
/// `shown(amount, multiplier)`, a price in another currency is unchanged
/// (`0x14041bcc0.formula`).
pub fn paid(price price: SellPrice, multiplier multiplier: Float) -> SellPrice {
  use <- bool.guard(price.currency_type_id != currency.credits_type, price)
  SellPrice(..price, amount: shown(base: price.amount, multiplier:))
}

/// The price the vendor's window shows and the vendor pays or charges for a base price: the
/// base price times the vendor's buy or sell multiplier, truncated.
pub fn shown(base base: Int, multiplier multiplier: Float) -> Int {
  float.truncate(float32.product(
    left: float32.rounded(value: int.to_float(base)),
    right: float32.rounded(value: multiplier),
  ))
}

/// A sentence that says why the item has no price, for the load's refusal.
pub fn describe(error error: PriceError) -> String {
  case error {
    MissingRow(table:, id:) ->
      "the client's " <> table <> " has no row " <> int.to_string(id)
    OtherCurrency(item2_id: Item2Id(item)) ->
      "Item2 "
      <> int.to_string(item)
      <> " is priced in a currency other than credits, which #333 builds"
    TwoSellCurrencies(item2_id: Item2Id(item)) ->
      "Item2 "
      <> int.to_string(item)
      <> " has an amount in both sell currency slots"
    TradeskillAdditive(item2_id: Item2Id(item), additive_id:) ->
      "Item2 "
      <> int.to_string(item)
      <> " has tradeskill additive "
      <> int.to_string(additive_id)
      <> ", whose price bonus #333 builds"
    NoCurveValue(formula:, level:) ->
      "the curve of GameFormula "
      <> int.to_string(formula)
      <> " has no value at power level "
      <> int.to_string(level)
  }
}
