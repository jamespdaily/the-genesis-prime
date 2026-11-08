-- Stores the items a new character starts with, one row each, in the places
-- the lists give at the same position. The database gives each row its guid.
-- A place the character already holds an item in breaks
-- `character_item_one_per_slot`, and any other value its checks refuse breaks
-- that check; no ask of the create can, so the worker ends on either.
insert into character_item (character_id, item2_id, location, bag_index, stack_count)
select $1::bigint, item2_id, location::smallint, bag_index, stack_count
from unnest($2::int[], $3::int[], $4::int[], $5::int[])
  as new_item (item2_id, location, bag_index, stack_count);
