//// Messages 0x968 (the account's entitlements) and 0x97f (the premium tier),
//// both server to client only. The client has no writer for either, so there
//// is no emulator vector: each expected body is written from the client's
//// reader, as the fact file's record gives it.
//// - 0x968: the reader 0x140080710 reads a 32-bit count, then per entry two
////   32-bit values, the Entitlement id and the count held (opcode.0x968).
//// - 0x97f: the reader 0x140080920 reads one value of 5 bits (opcode.0x97f).
//// The client's bit stream fills each byte from its least significant bit
//// (the first bit of a value is its lowest), so a 32-bit value is four bytes,
//// lowest first, and a 5-bit value 1 is the byte 0x01 (as the 5-bit reason of
//// vector.opcode.0x594.body).

import genesis_prime/message/account_entitlements.{AccountEntitlements}
import genesis_prime/message/bit_stream
import genesis_prime/message/held_entitlement.{HeldEntitlement}
import genesis_prime/message/premium_tier.{PremiumTier}
import message_support
import owned_test

pub fn account_entitlements_are_a_count_and_that_many_id_and_count_pairs_of_32_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x968, 0x140080710: count 1, then entitlement 12 held 4 times, three 32-bit values",
    body: <<1:size(32)-little, 12:size(32)-little, 4:size(32)-little>>,
    value: AccountEntitlements(entitlements: [
      HeldEntitlement(entitlement_id: 12, count: 4),
    ]),
    encode: account_entitlements.encode,
    decode: account_entitlements.decode,
  )
  assert account_entitlements.encode(AccountEntitlements(entitlements: []))
    == Ok(<<0:size(32)>>)
    as "opcode.0x968: a count of 0 and no entries is the whole body"
  assert account_entitlements.encode(
      AccountEntitlements(entitlements: [
        HeldEntitlement(entitlement_id: 12, count: 4),
        HeldEntitlement(entitlement_id: 22, count: 1),
      ]),
    )
    == Ok(<<
      2:size(32)-little,
      12:size(32)-little,
      4:size(32)-little,
      22:size(32)-little,
      1:size(32)-little,
    >>)
    as "0x140080710: each entry is its id and its count, in the order given"
}

pub fn the_premium_tier_is_one_value_of_5_bits_and_a_wider_one_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x97f, 0x140080920: tier 1 is the 5 bits 10000 in stream order, the byte 0x01",
    body: <<1>>,
    value: PremiumTier(tier: 1),
    encode: premium_tier.encode,
    decode: premium_tier.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x97f: the client accepts 0 to 31, so 31 is the 5 bits all set",
    body: <<0x1f>>,
    value: PremiumTier(tier: 31),
    encode: premium_tier.encode,
    decode: premium_tier.decode,
  )
  assert premium_tier.encode(PremiumTier(tier: 32))
    == Error(bit_stream.ValueDoesNotFit("tier", 5, 32))
    as "opcode.0x97f: the client's writer would mask 32 to 0, a tier of Basic, so a tier the field cannot hold is refused"
}

pub fn the_two_messages_hold_the_clients_message_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  assert account_entitlements.message_id == 0x0968
    as "opcode.0x968: registered at 0x14006de8a mov edx, 0x968"
  assert premium_tier.message_id == 0x097F
    as "opcode.0x97f: registered at 0x14006dfe1 mov edx, 0x97f"
}
