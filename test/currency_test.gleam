//// What a character holds of a currency and the 0x919 that sets it (`genesis_prime/game/currency`).
//// Expected values come from these places.
//// - `0x1403b59f0`, `GetCurrencyCap.entitlement_14`: the cap of credits is GameFormula 1115's
////   dataint0 (500,000), of Renown (type 2) GameFormula 1116's (5,000), of any other type its
////   CurrencyType row's capAmount, where 0 is no cap.
//// - `opcode.0x919`: the message sets the client's amount of the currency of kind type - 1 to
////   the total; its two 32-bit fields are 0.
//// - `opcode.0xdd`: the message prints "You receive X" for the amount in its second field, in
////   the currency type of its first (4 bits, the type id itself); an amount of 0 or less does
////   nothing, and its third field is the Signature part, 0 from the server.
//// - `opcode.0xdd.with_0x919`: 0xdd changes no total, so one 0xdd beside the 0x919 counts
////   nothing twice.

import character_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/currency_gained.{CurrencyGained}
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

fn total_of(frame frame: Frame) -> currency_changed.CurrencyChanged {
  assert frame.message_id == currency_changed.message_id
  let assert Ok(changed) = currency_changed.decode(frame.body)
    as "the frame is a 0x919 body"
  changed
}

fn gain_of(frame frame: Frame) -> currency_gained.CurrencyGained {
  assert frame.message_id == currency_gained.message_id
  let assert Ok(gained) = currency_gained.decode(frame.body)
    as "the frame is a 0xdd body"
  gained
}

pub fn a_gain_sends_the_total_then_the_gain_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [total, gain] =
    currency.total_frames(currency_type_id: 1, before: 1000, total: 1500)
    as "opcode.0xdd.with_0x919: a gain is the 0x919 total, then one 0xdd"
  assert total_of(frame: total)
    == CurrencyChanged(kind: 0, total: 1500, field_3: 0, field_4: 0)
    as "opcode.0x919: credits are kind 0, and the total is the new amount held"
  assert gain_of(frame: gain)
    == CurrencyGained(currency_type_id: 1, amount: 500, signature_amount: 0)
    as "opcode.0xdd: the type, the amount gained (1500 - 1000) and a Signature part of 0"
}

pub fn a_gain_stopped_at_the_cap_sends_what_was_gained_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [_, gain] =
    currency.total_frames(currency_type_id: 1, before: 499_900, total: 500_000)
    as "a gain below the cap's excess still gives a 0xdd"
  assert gain_of(frame: gain).amount == 100
    as "opcode.0xdd: the line shows the amount sent, so it is what the player gained (500,000 - 499,900), not what was offered"
}

pub fn no_gain_sends_the_total_alone_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [total] =
    currency.total_frames(currency_type_id: 1, before: 500_000, total: 500_000)
    as "opcode.0xdd: an amount of 0 or less does nothing, so a total at the cap (GameFormula 1115) gives no 0xdd"
  assert total_of(frame: total).total == 500_000
}

pub fn the_gain_names_the_currency_type_not_the_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [total, gain] =
    currency.total_frames(currency_type_id: 4, before: 10, total: 25)
    as "a gain of Crafting Vouchers is a total and a gain"
  assert total_of(frame: total).kind == 3
    as "opcode.0x919: the kind is the currency type - 1"
  assert gain_of(frame: gain)
    == CurrencyGained(currency_type_id: 4, amount: 15, signature_amount: 0)
    as "opcode.0xdd: the 4-bit field is the currency type id itself, not the kind"
}

pub fn currency_gained_encodes_the_clients_layout_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(body) =
    currency_gained.encode(CurrencyGained(
      currency_type_id: 1,
      amount: 500,
      signature_amount: 0,
    ))
    as "the three values fit their fields"
  // opcode.0xdd: the client reads 4 bits, then two 64-bit values, each least significant
  // bit first from bit 0 (0x14006c090). The type 1 is the low nibble of byte 0; the amount
  // 500 = 0x1F4 starts at bit 4, so byte 0 is 0x41 (0x4 above the nibble 1) and byte 1 is
  // 0x1F; the 132 bits end in the 17th byte, padded with zero bits.
  assert body == <<0x41, 0x1F, 0:size(120)>>
}
