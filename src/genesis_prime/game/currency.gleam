//// What a character holds of each currency: the saved rows, the 15 amounts world entry sends
//// in 0x025E (genesis_prime/game/character_state) and the 0x0919 that gives the client a
//// new total (`opcode.0x919`, `opcode.0x25e`).
////
//// ```
//// store.CharacterLoaded.currencies ─▶ from_held ─▶ Currencies ─▶ bytes        (0x025E's 15 × u64, types 1 to 15)
//// a buy's new total                ─▶ with_credits ─▶ Currencies ─▶ changed_frame (0x0919 kind 0)
//// ```
////
//// - **Credits** are currency type 1, the first of the 15 (`opcode.0x25e`). Only credits are
////   held now; the other types stay 0 until their step (#333).
//// - **0x0919 carries the new total**, not a change: kind 0 sets credits, and the client
////   drops kinds 14 to 21 (`opcode.0x919`). Its two 32-bit fields are 0.
//// - **The credit cap** (GameFormula 1115, 500000) is applied by the step that adds credits;
////   a purchase only lowers the total.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/store
import gleam/dict.{type Dict}
import gleam/list

/// The amounts held, by currency type (1 to 15); a type with no row is 0.
pub type Currencies {
  Currencies(amounts: Dict(Int, Int))
}

/// The currency type of credits.
pub const credits_type = 1

/// The currencies the saved rows give.
pub fn from_held(held held: List(store.HeldCurrency)) -> Currencies {
  Currencies(
    amounts: dict.from_list(
      list.map(held, fn(row) { #(row.currency_type_id, row.amount) }),
    ),
  )
}

/// The credits held.
pub fn credits(currencies _currencies: Currencies) -> Int {
  panic as "shape: #583 the credits"
}

/// The currencies with the credits `credits`.
pub fn with_credits(
  currencies _currencies: Currencies,
  credits _credits: Int,
) -> Currencies {
  panic as "shape: #583 the credits set"
}

/// The 15 amounts of 0x025E, 8 bytes each, little-endian, type 1 first.
pub fn bytes(currencies _currencies: Currencies) -> BitArray {
  panic as "shape: #583 the 0x025E bytes"
}

/// The 0x0919 that sets the client's credits to `total`.
pub fn changed_frame(total _total: Int) -> Frame {
  panic as "shape: #583 the 0x0919 frame"
}
