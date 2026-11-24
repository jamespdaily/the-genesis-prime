//// The tiers of an ability (stub).

import genesis_prime/table/id.{type Spell4BaseId, type Spell4Id}
import genesis_prime/table/loader/store as table_store

pub opaque type SpellTiers {
  SpellTiers
}

const tiers_key: table_store.DerivedKey(SpellTiers) =
  table_store.DerivedKey("SpellTiers")

pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: tiers_key, build: fn(_) { Ok(SpellTiers) })
}

pub fn tiers(tables tables: table_store.Tables) -> SpellTiers {
  table_store.derived(tables:, key: tiers_key)
}

pub fn highest(
  tiers _tiers: SpellTiers,
  base _base: Spell4BaseId,
) -> Result(Int, Nil) {
  Error(Nil)
}

pub fn spell4_id(
  tiers _tiers: SpellTiers,
  base _base: Spell4BaseId,
  tier _tier: Int,
) -> Result(Spell4Id, Nil) {
  Error(Nil)
}

pub fn level_needed(
  tiers _tiers: SpellTiers,
  tier _tier: Int,
) -> Result(Int, Nil) {
  Error(Nil)
}

pub fn change_cost(
  tiers _tiers: SpellTiers,
  base _base: Spell4BaseId,
  from _from: Int,
  to _to: Int,
) -> Result(Int, Nil) {
  Error(Nil)
}

pub fn spent(
  tiers _tiers: SpellTiers,
  held _held: List(#(Spell4BaseId, Int)),
) -> Int {
  0
}
