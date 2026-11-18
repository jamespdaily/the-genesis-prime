-- The items a character holds in its equipped slots, inventory and bank, in
-- the order world entry sends them: by location, then bag index. A row saved before the
-- charges column has no charges (null), which world entry fills. `item_flags` is the
-- item's flags byte as the client reads it.
select
  item_guid,
  item2_id,
  location::int as location,
  bag_index,
  stack_count,
  random_stats,
  charges,
  item_flags::int as item_flags
from character_item
where character_id = $1
order by location, bag_index;
