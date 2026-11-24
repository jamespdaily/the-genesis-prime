-- The tiers a character holds above tier 1, in set then Spell4Base order, as the load
-- hands them to the ability builder's entry (genesis_prime/game/limited_action_set).
select
  action_set::int as action_set,
  spell4_base_id,
  tier::int as tier
from character_ability_tier
where character_id = $1
order by action_set, spell4_base_id;
