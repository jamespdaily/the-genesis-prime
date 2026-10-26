//// How many characters an account may hold. The client's character select
//// shows the slots as the CharacterSlots reward value of the account's premium
//// system plus the account's count of entitlement 12 (BaseCharacterSlots)
//// (lua.CharacterSelection.OnLoadFromCharacter). The server grants no
//// entitlement and does not carry the client's gmode, so every account has the
//// Hybrid system's value (RewardPropertyPremiumModifier.rewardPropertyId).

import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/reward_property_premium_modifier
import gleam/list

/// The premium system of gmode 0, the client's default: Hybrid.
const hybrid_system = 1

/// The premium tier every account has: 0, the base tier, which no row of
/// CharacterSlots changes by tier.
const base_tier = 0

/// The id of the CharacterSlots reward property
/// (AccountItemLib.CodeEnumRewardProperty).
const character_slots_property = 29

/// The characters an account may hold: the sum of the integer values of the
/// Hybrid system's CharacterSlots rows at the base tier that name no
/// entitlement (row 117, which is 2). A row that names an entitlement adds to
/// the most slots only, never to the slots in use.
pub fn hybrid(tables tables: Tables) -> Int {
  reward_property_premium_modifier.all(tables)
  |> list.filter(fn(row) {
    row.premium_system_enum == hybrid_system
    && row.tier == base_tier
    && row.reward_property_id == character_slots_property
    && row.entitlement_id_modifier_count == 0
  })
  |> list.fold(0, fn(sum, row) { sum + row.modifier_value_int })
}
