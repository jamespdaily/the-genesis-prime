//// What a character holds of each currency: the saved rows, the 15 amounts world entry sends
//// in 0x025E (genesis_prime/game/character_state) and the 0x0919 that gives the client a
//// new total (`opcode.0x919`, `opcode.0x25e`).
////
//// ```
//// store.CharacterLoaded.currencies ─▶ from_held ─▶ Currencies ─▶ bytes        (0x025E's 15 × u64, types 1 to 15)
//// a sale's or a buy's new total    ─▶ with_amount ─▶ Currencies ─▶ changed_frame (0x0919 kind type − 1)
//// a sale's payment                 ─▶ added(held, paid, cap(tables, type)) ─▶ the new total
//// ```
////
//// - **Credits** are currency type 1, the first of the 15 (`opcode.0x25e`).
//// - **0x0919 carries the new total**, not a change: its kind is the currency type - 1 (0 sets
////   credits), and the client drops kinds 14 to 21 (`opcode.0x919`). Its two 32-bit fields
////   are 0.
//// - **The cap** is the client's GetCurrencyCap (`0x1403b59f0`, `GetCurrencyCap.entitlement_14`):
////   credits GameFormula 1115 (500,000), Renown GameFormula 1116 (5,000), any other type its
////   CurrencyType capAmount, where 0 or no row is no cap. The client does not clamp
////   (`0x1403b5730`); `added` does, as the server's choice: the total stops at the cap and
////   the excess is lost. A purchase only lowers a total.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/store
import genesis_prime/table/currency_type
import genesis_prime/table/game_formula
import genesis_prime/table/id.{CurrencyTypeId, GameFormulaId}
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result

/// The amounts held, by currency type (1 to 15); a type with no row is 0.
pub type Currencies {
  Currencies(amounts: Dict(Int, Int))
}

/// The currency type of credits.
pub const credits_type = 1

/// The number of currency types 0x025E holds amounts for (`opcode.0x25e`).
const currency_types = 15

/// The GameFormula row whose dataint0 is the most credits a character holds
/// (`GetCurrencyCap.entitlement_14`).
const credit_cap_formula = 1115

/// The GameFormula row whose dataint0 is the most Renown a character holds
/// (`GetCurrencyCap.entitlement_14`).
const renown_cap_formula = 1116

/// What the tables must hold at load for the caps: the GameFormula rows of credits and
/// Renown.
pub fn requirements() -> List(table_store.Requirement) {
  [
    cap_requirement(
      from_table: "the server's credit cap",
      id: credit_cap_formula,
    ),
    cap_requirement(
      from_table: "the server's Renown cap",
      id: renown_cap_formula,
    ),
  ]
}

fn cap_requirement(
  from_table from_table: String,
  id id: Int,
) -> table_store.Requirement {
  table_store.Requirement(
    from_table:,
    column: "GameFormula id",
    to_table: "GameFormula",
    missing: fn(tables) {
      case game_formula.get(tables:, id: GameFormulaId(id)) {
        Ok(_) -> []
        Error(Nil) -> [id]
      }
    },
  )
}

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
  held(currencies:, currency_type_id: credits_type)
}

/// The currencies with `total` held of a currency type.
pub fn with_amount(
  currencies currencies: Currencies,
  currency_type_id currency_type_id: Int,
  total total: Int,
) -> Currencies {
  Currencies(amounts: dict.insert(currencies.amounts, currency_type_id, total))
}

/// What is held of a currency type, 0 when there is no row.
pub fn held(
  currencies currencies: Currencies,
  currency_type_id currency_type_id: Int,
) -> Int {
  result.unwrap(dict.get(currencies.amounts, currency_type_id), 0)
}

/// The most a character holds of a currency type (the client's GetCurrencyCap), or None
/// when the type has no cap.
pub fn cap(
  tables tables: table_store.Tables,
  currency_type_id currency_type_id: Int,
) -> Option(Int) {
  case currency_type_id {
    1 -> Some(formula_cap(tables:, formula: credit_cap_formula))
    2 -> Some(formula_cap(tables:, formula: renown_cap_formula))
    _ ->
      case currency_type.get(tables:, id: CurrencyTypeId(currency_type_id)) {
        Ok(row) if row.cap_amount > 0 -> Some(row.cap_amount)
        Ok(_) | Error(Nil) -> option.None
      }
  }
}

fn formula_cap(tables tables: table_store.Tables, formula formula: Int) -> Int {
  let assert Ok(row) = game_formula.get(tables:, id: GameFormulaId(formula))
    as "the cap's GameFormula row is required at load (requirements)"
  row.dataint0
}

/// The total held after `paid` is added to `held` under `cap`: it stops at the cap, and a
/// total already at the cap stays.
pub fn added(held held: Int, paid paid: Int, cap cap: Option(Int)) -> Int {
  case cap {
    option.None -> held + paid
    option.Some(cap) -> int.max(held, int.min(cap, held + paid))
  }
}

/// The 15 amounts of 0x025E, 8 bytes each, little-endian, type 1 first.
pub fn bytes(currencies currencies: Currencies) -> BitArray {
  int.range(from: 0, to: currency_types, with: [], run: list.prepend)
  |> list.reverse
  |> list.map(fn(index) {
    <<held(currencies:, currency_type_id: index + 1):little-size(64)>>
  })
  |> bit_array.concat
}

/// The 0x0919 that sets the client's amount of a currency type to `total`: kind type - 1
/// (`opcode.0x919`).
pub fn changed_frame(
  currency_type_id currency_type_id: Int,
  total total: Int,
) -> Frame {
  let assert Ok(body) =
    currency_changed.encode(CurrencyChanged(
      kind: currency_type_id - 1,
      total:,
      field_3: 0,
      field_4: 0,
    ))
    as "a total below 2^64 fits the message"
  Frame(message_id: currency_changed.message_id, body:)
}
