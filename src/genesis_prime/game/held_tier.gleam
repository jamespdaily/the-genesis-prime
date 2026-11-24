//// The plans a press reads for a player who holds tiers above 1: the ability builder's tier
//// pips buy a tier of an ability, and the press then casts that tier's Spell4 row, as the
//// client's own prediction does. A tier is a Spell4 row of the ability's Spell4Base
//// (genesis_prime/game/spell_tier), and its plan is built at load (`spell_plan.tier_plans`).
////
//// ```
//// plans (tier 1, by Spell4Base) + tier plans (tiers 2 to 9, by Spell4 id) + the held tiers
////   ─▶ plans_of ─▶ the plans with each held ability's tier plan under its Spell4Base
////   ─▶ the cast rule (genesis_prime/game/cast) reads them as it reads any plans
//// ```
////
//// - **The client names a bag index, never a spell.** A press (0x9a) and a key (0x4db) name the
////   ability's bag index (`opcode.0x9a`, `opcode.0x4db`), so the server picks the Spell4 row: the
////   ability's Spell4Base, then the tier the player holds. The client predicts the press with
////   the book's tier it was told in 0x01A0 (`GetAbilityItemSpell` `0x1405a4b80`, which reads
////   the book's spell for the base: `GetSpellIdForTier` `0x1403bad30`), so its cast bar, global
////   cooldown and cooldown use that tier's row and the server's must be the same.
//// - **A held tier the plans cannot cast plays the best lower tier they can**, and tier 1 at
////   worst (`tier_played`): the plan of a tier the server does not build is left out
////   (`spell_plan.unplanned_tiers`), and the client keeps the held tier in its book, which only
////   0x01A0 changes. What the client predicts of the press (cast time, cooldown, costs, range, the
////   cooldown groups) is the same in the tier that plays as in the held tier for every tier left
////   out today; the tooltip, the effects of the unbuilt rows and four named differences are the
////   held tier's (the coverage measure lists them, `limited_action_set.gaps`).
//// - **The cooldown of a tier is its own**, keyed by the Spell4 id of the spell that started it
////   (`0x14046b1e0`), on the client and in the server's cooldown book: a player who changes
////   tier mid-cooldown presses a spell whose own cooldown is not running, and the global
////   cooldown and any shared cooldown group still hold. Both sides do the same, so nothing is
////   added here.
//// - **A cast under way is a value.** The press, the queued press, the held key and the open
////   threshold each hold their own `Spell`, so a save between two presses changes the second
////   press and not the first cast. A ChargeRelease threshold open across a save is not found
////   under the new Spell4 id, as on the client (`0x1403bfd60`).
//// - **A hold is the ability's, not the spell's:** the cast rule compares the Spell4Base of
////   the held ability, since the key up names the bag index and a tier change between the key
////   down and the key up gives another Spell4 id (genesis_prime/game/cast/press).

import genesis_prime/game/spell_plan.{type Plans, type TierPlans}
import genesis_prime/game/spell_tier.{type SpellTiers}
import genesis_prime/table/id.{type Spell4BaseId}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

/// The plans with, for each held ability that the plans hold, the plan of the tier it plays
/// (`tier_played`) in place of its tier 1 plan. A base the plans do not hold is left alone, and so
/// is one whose held tier plays tier 1: an alternate stored at a tier has no plan of its own
/// above tier 1, since the plans hold its tiers inside the ability that names it.
pub fn plans_of(
  plans plans: Plans,
  tier_plans tier_plans: TierPlans,
  tiers tiers: SpellTiers,
  held held: List(#(Spell4BaseId, Int)),
) -> Plans {
  list.fold(held, plans, fn(plans, entry) {
    let #(base, held_tier) = entry
    use <- bool.guard(when: !dict.has_key(plans, base.value), return: plans)
    let played = tier_played(tier_plans:, tiers:, base:, held_tier:)
    let plan =
      spell_tier.spell4_id(tiers:, base:, tier: played)
      |> result.try(fn(spell4_id) {
        spell_plan.in_tier_plans(tier_plans:, spell4_id:)
      })
    case plan {
      Ok(spell) -> dict.insert(plans, base.value, spell)
      Error(Nil) -> plans
    }
  })
}

/// The tier a held tier plays: the highest tier from the held one down to 2 whose row the tier
/// plans hold, else 1.
pub fn tier_played(
  tier_plans tier_plans: TierPlans,
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
  held_tier held_tier: Int,
) -> Int {
  use <- bool.guard(when: held_tier < 2, return: 1)
  int.range(from: 2, to: held_tier + 1, with: [], run: list.prepend)
  |> list.find(fn(tier) {
    spell_tier.spell4_id(tiers:, base:, tier:)
    |> result.try(fn(spell4_id) {
      spell_plan.in_tier_plans(tier_plans:, spell4_id:)
    })
    |> result.is_ok
  })
  |> result.unwrap(1)
}
