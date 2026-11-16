//// The decode of a currency type number into one kind (genesis_prime/game/currency_kind).
//// Expected values and their sources:
//// - `lua.Money.CodeEnumCurrencyType`: currency 1 is the credits, 2 Renown.
//// - `CurrencyType.capAmount`: the client's CurrencyType rows are 1 to 7 and 9 to 14; there
////   is no row 8.
//// - `0x14040bee0` and `0x14040bfb0`: a price slot's currency 0 means the slot is unused.

import client_tables
import genesis_prime/game/currency_kind.{Credits, NoCurrency, Other, Renown}
import genesis_prime/table/currency_type
import gleam/int
import gleam/list
import owned_test
import unitest

pub fn each_currency_number_decodes_to_its_kind_and_any_other_carries_the_number_test() -> Nil {
  use <- owned_test.run(10_000)
  assert currency_kind.kind_of(number: 0) == NoCurrency
    as "0x14040bee0: a currency of 0 is an unused slot"
  assert currency_kind.kind_of(number: 1) == Credits
    as "lua.Money.CodeEnumCurrencyType: 1 is the credits"
  assert currency_kind.kind_of(number: 2) == Renown
    as "lua.Money.CodeEnumCurrencyType: 2 is Renown"
  let others = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 99, -1]
  assert list.map(others, fn(number) { currency_kind.kind_of(number:) })
    == list.map(others, fn(number) { Other(number:) })
    as "CurrencyType rows 3 to 14 and any number outside them are no kind the server reads, so each carries its number"
}

pub fn credits_type_is_the_number_that_decodes_to_credits_test() -> Nil {
  use <- owned_test.run(10_000)
  assert currency_kind.kind_of(number: currency_kind.credits_type) == Credits
    as "lua.Money.CodeEnumCurrencyType: the one number 1 is named once and decodes to Credits"
}

pub fn only_credits_is_credits_and_only_a_currency_of_0_names_none_test() -> Nil {
  use <- owned_test.run(10_000)
  let kinds = [NoCurrency, Credits, Renown, Other(number: 4), Other(number: 8)]
  assert list.map(kinds, currency_kind.is_credits)
    == [False, True, False, False, False]
    as "0x14041bcc0.formula: only a credits slot is scaled by the vendor multiplier"
  assert list.map(kinds, currency_kind.names_a_currency)
    == [False, True, True, True, True]
    as "0x14040bee0, 0x14040bfb0: a slot of currency 0 is unused, any other number is a currency"
}

pub fn every_currency_row_of_the_client_decodes_and_row_8_is_other_8_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = currency_type.all(client_tables.shared())
  let ids = list.map(rows, fn(row) { row.id }) |> list.sort(by: int.compare)
  assert ids == [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14]
    as "CurrencyType.capAmount: 13 rows, 1 to 14 without 8"
  let kinds =
    list.map(ids, fn(number) { #(number, currency_kind.kind_of(number:)) })
  assert kinds
    == [
      #(1, Credits),
      #(2, Renown),
      #(3, Other(number: 3)),
      #(4, Other(number: 4)),
      #(5, Other(number: 5)),
      #(6, Other(number: 6)),
      #(7, Other(number: 7)),
      #(9, Other(number: 9)),
      #(10, Other(number: 10)),
      #(11, Other(number: 11)),
      #(12, Other(number: 12)),
      #(13, Other(number: 13)),
      #(14, Other(number: 14)),
    ]
    as "every row of the client's table decodes, only 1 and 2 to a named kind"
  assert currency_kind.kind_of(number: 8) == Other(number: 8)
    as "CurrencyType.capAmount: no row 8, so the number is carried like any other"
}
