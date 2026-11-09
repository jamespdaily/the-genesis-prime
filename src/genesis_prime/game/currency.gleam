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

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/store
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// The amounts held, by currency type (1 to 15); a type with no row is 0.
pub type Currencies {
  Currencies(amounts: Dict(Int, Int))
}

/// The currency type of credits.
pub const credits_type = 1

/// The number of currency types 0x025E holds amounts for (`opcode.0x25e`).
const currency_types = 15

/// The kind of a 0x0919 that sets credits (`opcode.0x919`).
const credits_kind = 0

/// The currencies the saved rows give.
pub fn from_held(held held: List(store.HeldCurrency)) -> Currencies {
  Currencies(
    amounts: dict.from_list(
      list.map(held, fn(row) { #(row.currency_type_id, row.amount) }),
    ),
  )
}

/// The credits held.
pub fn credits(currencies currencies: Currencies) -> Int {
  amount(currencies:, currency_type_id: credits_type)
}

/// The currencies with the credits `credits`.
pub fn with_credits(
  currencies currencies: Currencies,
  credits credits: Int,
) -> Currencies {
  Currencies(amounts: dict.insert(currencies.amounts, credits_type, credits))
}

/// What is held of a currency type, 0 when there is no row.
fn amount(
  currencies currencies: Currencies,
  currency_type_id currency_type_id: Int,
) -> Int {
  result.unwrap(dict.get(currencies.amounts, currency_type_id), 0)
}

/// The 15 amounts of 0x025E, 8 bytes each, little-endian, type 1 first.
pub fn bytes(currencies currencies: Currencies) -> BitArray {
  list.repeat(Nil, currency_types)
  |> list.index_map(fn(_, index) {
    <<amount(currencies:, currency_type_id: index + 1):little-size(64)>>
  })
  |> bit_array.concat
}

/// The 0x0919 that sets the client's credits to `total`.
pub fn changed_frame(total total: Int) -> Frame {
  let assert Ok(body) =
    currency_changed.encode(CurrencyChanged(
      kind: credits_kind,
      total:,
      field_3: 0,
      field_4: 0,
    ))
    as "a total below 2^64 fits the message"
  Frame(message_id: currency_changed.message_id, body:)
}
