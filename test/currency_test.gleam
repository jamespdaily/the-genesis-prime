//// What a character holds of a currency and the 0x919 that sets it (`genesis_prime/game/currency`).
//// Expected values come from these places.
//// - `0x1403b59f0`, `GetCurrencyCap.entitlement_14`: the cap of credits is GameFormula 1115's
////   dataint0 (500,000), of Renown (type 2) GameFormula 1116's (5,000), of any other type its
////   CurrencyType row's capAmount, where 0 is no cap.
//// - `opcode.0x919`: the message sets the client's amount of the currency of kind type - 1 to
////   the total; its two 32-bit fields are 0.

import character_tables
import genesis_prime/game/currency
import genesis_prime/message/currency_changed.{CurrencyChanged}
import gleam/option.{None, Some}
import owned_test

pub fn the_cap_of_credits_and_renown_is_their_game_formula_and_of_another_type_its_currency_type_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  assert currency.cap(tables:, currency_type_id: 1) == Some(500_000)
    as "GetCurrencyCap.entitlement_14: credits are GameFormula 1115's dataint0, 500000"
  assert currency.cap(tables:, currency_type_id: 2) == Some(5000)
    as "GetCurrencyCap.entitlement_14: Renown is GameFormula 1116's dataint0, 5000"
  assert currency.cap(tables:, currency_type_id: 6) == Some(5000)
    as "0x1403b59f0: Shade's Eve (CurrencyType 6) is not credits or Renown, so its cap is its row's capAmount, 5000"
  assert currency.cap(tables:, currency_type_id: 7) == None
    as "0x1403b59f0: Glory (CurrencyType 7) has capAmount 0, which is no cap"
}

pub fn a_0x919_for_a_currency_carries_kind_type_minus_1_and_the_new_total_test() -> Nil {
  use <- owned_test.run(10_000)
  let frame = currency.changed_frame(currency_type_id: 7, total: 160)
  assert frame.message_id == currency_changed.message_id
  assert currency_changed.decode(frame.body)
    == Ok(CurrencyChanged(kind: 6, total: 160, field_3: 0, field_4: 0))
    as "opcode.0x919: Glory is currency type 7, so kind 6; the total is the new amount held, and both 32-bit fields are 0"
}
