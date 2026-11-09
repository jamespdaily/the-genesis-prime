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
//// ```
////
//// - **Every product is a 32-bit float** (`message/float32`), as the client's code rounds
////   each step, so the price is the client's to the credit.
//// - **A proxy item** (Item2.flags 0x4000) takes its quality from the Item2 its row
////   names (GameFormula 1214) and keeps its own power level.
//// - **Only a credit price is read.** An item whose row names another currency, or a
////   trade skill additive, is refused with the row named: other currencies and the
////   additive are #333's.
////
//// | Point | What happens |
//// |---|---|
//// | an Item2, Item2Category, Item2Family, Item2Type or GameFormula row is missing | the error names the table and the id; the vendor load stops |
//// | the row's currencyTypeIds are not both 0 | the error names the item; the vendor load stops |
//// | the row's tradeskillAdditiveId is not 0 | the error names the item; the vendor load stops |

import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store

/// Why an item has no credit price.
pub type PriceError {
  /// A row the formula reads is not in the client's tables.
  MissingRow(table: String, id: Int)
  /// The item is priced in a currency other than credits.
  OtherCurrency(item2_id: Item2Id)
  /// The item's price has a trade skill additive.
  TradeskillAdditive(item2_id: Item2Id, additive_id: Int)
}

/// The item's buy price in credits at a vendor multiplier of 1.0.
pub fn base(
  tables _tables: table_store.Tables,
  item2_id _item2_id: Item2Id,
) -> Result(Int, PriceError) {
  panic as "shape: #583 the item's buy price"
}

/// The price the vendor's window shows and the vendor charges for a buy price: the buy
/// price times the vendor's buy multiplier, truncated.
pub fn shown(base _base: Int, buy_multiplier _buy_multiplier: Float) -> Int {
  panic as "shape: #583 the shown price"
}

/// A sentence that says why the item has no price, for the load's refusal.
pub fn describe(error _error: PriceError) -> String {
  panic as "shape: #583 the price error's sentence"
}
