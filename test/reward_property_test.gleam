//// The reward properties a premium tier gives (`genesis_prime/game/reward_property`).
//// Expected values come from these places.
//// - `opcode.0x92c.bag_slots`: the value of a reward property is the sum of the
////   RewardPropertyPremiumModifier rows of the property whose premiumSystemEnum is
////   the system and whose tier is at or below the player's, counting a row below
////   the tier only when its flags hold bit 1 (it carries up), and counting a row
////   that names an entitlement (entitlementIdModifierCount above 0) for the
////   "most" values only, so it adds nothing to a current value. BagSlots is
////   property 26 and BankSlots 13, the client's
////   `AccountItemLib.CodeEnumRewardProperty` names.
//// - The rows are the client's own, roots of the fixture (id: system, tier,
////   property, modifierValueInt, flags):
////   109: 1, 0, 26, 4, carries up. 110: 2, 0, 26, 2. 111: 2, 1, 26, 4, carries up.
////   30: 1, 0, 13, 2. 31: 1, 1, 13, 2. 33: 2, 1, 13, 7. 67: 1, 0, 13, 0, carries up
////   with entitlement count 27.
//// - So Hybrid (system 1) at tier 1 holds BagSlots 4 (row 109 carried up) and
////   BankSlots 2 (row 31 at the tier; row 30 does not carry up and row 67 names an
////   entitlement). System 2 at tier 1 holds BagSlots 4 (row 111 at the tier; row
////   110 does not carry up) and BankSlots 7 (row 33).

import fixture_tables
import genesis_prime/game/reward_property.{Value}
import owned_test

pub fn hybrid_tier_1_gives_four_bag_slots_and_two_bank_slots_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  assert reward_property.premium_values(tables:, system: 1, tier: 1)
    == [Value(property_id: 26, value: 4), Value(property_id: 13, value: 2)]
  assert reward_property.bag_slots(tables:, system: 1, tier: 1) == 4
  // A row below the tier that does not carry up is left out, and one that does
  // is not added twice.
  assert reward_property.premium_values(tables:, system: 2, tier: 1)
    == [Value(property_id: 26, value: 4), Value(property_id: 13, value: 7)]
  // At tier 0 the Hybrid rows 109 and 30 sit at the tier.
  assert reward_property.premium_values(tables:, system: 1, tier: 0)
    == [Value(property_id: 26, value: 4), Value(property_id: 13, value: 2)]
}
