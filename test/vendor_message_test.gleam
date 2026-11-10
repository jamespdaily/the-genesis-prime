//// The two messages of a vendor purchase through the generated codec: the client's
//// 0xBE (`opcode.0xbe`: the unique id of the stock item and the quantity of lots, 32
//// bits each) and the server's 0x919 (`opcode.0x919`: the currency kind in 5 bits,
//// the total in 64, and two 32-bit fields the client gives no use). Every value of
//// the widths the fields hold round-trips.

import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/vendor_purchase.{VendorPurchase}
import gleam/result
import owned_test
import qcheck

pub fn the_0x919_and_0xbe_codecs_round_trip_test() -> Nil {
  use <- owned_test.run(10_000)
  use #(kind, total, field_3, field_4) <- qcheck.given(qcheck.tuple4(
    qcheck.bounded_int(from: 0, to: 31),
    qcheck.bounded_int(from: 0, to: 9_223_372_036_854_775_807),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
  ))
  let changed = CurrencyChanged(kind:, total:, field_3:, field_4:)
  assert currency_changed.encode(changed)
    |> result_decode(currency_changed.decode)
    == Ok(changed)
    as "opcode.0x919: the kind in 5 bits, the total in 64 and two fields of 32"
  let purchase = VendorPurchase(unique_id: field_3, quantity: field_4)
  assert vendor_purchase.encode(purchase)
    |> result_decode(vendor_purchase.decode)
    == Ok(purchase)
    as "opcode.0xbe: the unique id and the quantity, 32 bits each"
}

fn result_decode(
  encoded: Result(BitArray, encode_error),
  decode: fn(BitArray) -> Result(a, decode_error),
) -> Result(a, Nil) {
  use body <- result.try(result.replace_error(encoded, Nil))
  result.replace_error(decode(body), Nil)
}
