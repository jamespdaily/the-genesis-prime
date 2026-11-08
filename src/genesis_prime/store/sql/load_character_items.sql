-- The items a character holds in its equipped slots, inventory and bank, in
-- the order world entry sends them: by location, then bag index.
select
  item_guid,
  item2_id,
  location::int as location,
  bag_index,
  stack_count
from character_item
where character_id = $1
order by location, bag_index;
