//// The reward properties the player holds: the integer values the client
//// reads for the bag slots it unlocks, which the server sends in 0x92C at
//// world entry (`opcode.0x92c`) and checks a worn bag's slot against
//// (`inventory`). The values are the client's own rule over the loaded
//// RewardPropertyPremiumModifier rows, so the message and the check cannot
//// differ.
////
//// ```
//// tables, premium system, tier ─▶ premium_values ─▶ BagSlots, then BankSlots
//// tables, premium system, tier ─▶ bag_slots      ─▶ the BagSlots value, 0 when no row gives one
//// ```
////
//// - **The rule** (`opcode.0x92c.bag_slots`, `RewardPropertyPremiumModifier.
////   rewardPropertyId`): the rows of the property for the premium system at or
////   below the tier that carry up (flags bit 1) or sit at the tier add up, and
////   a row that names an entitlement adds to the most values only, so it adds
////   nothing to a current value.
//// - **Two properties** are sent: BagSlots (26) and BankSlots (13), both
////   integers with data 0. The other properties of the tier turn on client
////   features the server does not serve; each joins the message in the step
////   that serves its feature.

import genesis_prime/message/reward_properties.{type RewardProperties}
import genesis_prime/table/loader/store as table_store

/// The RewardProperty id of BagSlots (`AccountItemLib.CodeEnumRewardProperty.
/// BagSlots`): how many of the four bag slots of the character window are
/// unlocked.
pub const bag_slots_property = 26

/// The RewardProperty id of BankSlots: how many bank bag slots are unlocked.
pub const bank_slots_property = 13

/// The premium system whose rows the server reads: 1, Hybrid, the one the
/// client's start-up tier belongs to (`opcode.0x92c.bag_slots`).
pub const hybrid_system = 1

/// One reward property's current integer value; its data is 0.
pub type Value {
  Value(property_id: Int, value: Int)
}

/// BagSlots then BankSlots as the premium system gives them at the tier, 0 for
/// a property no row gives.
pub fn premium_values(
  tables _tables: table_store.Tables,
  system _system: Int,
  tier _tier: Int,
) -> List(Value) {
  panic as "shape: #587 the reward property values of a premium tier"
}

/// The BagSlots value at the tier: how many bag slots (equipped 17 to 20) may
/// hold a bag, 0 when no row gives one (`0x1403b4dd0`).
pub fn bag_slots(
  tables _tables: table_store.Tables,
  system _system: Int,
  tier _tier: Int,
) -> Int {
  panic as "shape: #587 the BagSlots value of a premium tier"
}

/// The 0x92C body for the values: one entry for each, data 0, no modifiers.
pub fn message(values _values: List(Value)) -> RewardProperties {
  panic as "shape: #587 the reward properties message"
}
