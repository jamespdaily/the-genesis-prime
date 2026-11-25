-- The AMPs a character holds, in set then EldanAugmentation order, as the load hands them
-- to the ability builder's entry (genesis_prime/game/limited_action_set).
select
  action_set::int as action_set,
  eldan_augmentation_id
from character_action_amp
where character_id = $1
order by action_set, eldan_augmentation_id;
