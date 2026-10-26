//// How many characters an account may hold. The client's character select
//// shows the slots as the CharacterSlots reward value of the account's premium
//// system plus the account's count of entitlement 12 (BaseCharacterSlots)
//// (lua.CharacterSelection.OnLoadFromCharacter). The server grants no
//// entitlement and does not carry the client's gmode, so every account has the
//// Hybrid system's value (RewardPropertyPremiumModifier.rewardPropertyId).

import genesis_prime/table/loader/store.{type Requirement, type Tables}
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

/// The rows the server requires of the tables for `hybrid`: a CharacterSlots
/// row of the Hybrid system at the base tier that names no entitlement. An
/// account with none has no slots to give, so the load fails instead of
/// giving every account 0 slots.
pub fn requirements() -> List(Requirement) {
  [
    store.Requirement(
      from_table: "the server's character slots",
      column: "rewardPropertyId",
      to_table: "RewardPropertyPremiumModifier",
      missing: fn(tables) {
        case slot_rows(tables) {
          [] -> [character_slots_property]
          [_, ..] -> []
        }
      },
    ),
  ]
}

/// The characters an account may hold: the sum of the integer values of the
/// Hybrid system's CharacterSlots rows at the base tier that name no
/// entitlement (row 117, which is 2). A row that names an entitlement adds to
/// the most slots only, never to the slots in use. The load checked that a
/// row exists (`requirements`).
pub fn hybrid(tables tables: Tables) -> Int {
  let assert [_, ..] as rows = slot_rows(tables)
    as "the load checked that the Hybrid system has a CharacterSlots row at the base tier"
  list.fold(rows, 0, fn(sum, row) { sum + row.modifier_value_int })
}

fn slot_rows(
  tables: Tables,
) -> List(reward_property_premium_modifier.RewardPropertyPremiumModifier) {
  reward_property_premium_modifier.all(tables)
  |> list.filter(fn(row) {
    row.premium_system_enum == hybrid_system
    && row.tier == base_tier
    && row.reward_property_id == character_slots_property
    && row.entitlement_id_modifier_count == 0
  })
}
