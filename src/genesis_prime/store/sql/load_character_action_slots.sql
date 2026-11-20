-- The slots of the action sets a character has saved, in set then slot order, as the
-- load hands them to the ability builder's entry (genesis_prime/game/limited_action_set).
-- An empty slot has a NULL ability.
select
  action_set::int as action_set,
  slot::int as slot,
  spell4_base_id
from character_action_slot
where character_id = $1
order by action_set, slot;
