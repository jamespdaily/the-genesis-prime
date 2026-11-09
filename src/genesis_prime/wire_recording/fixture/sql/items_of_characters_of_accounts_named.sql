-- The items held by the characters of the accounts with these login names, in
-- the order of their guids, with every column the fixture of a recorded session
-- keeps (genesis_prime/wire_recording/fixture): the guid, the character that
-- holds it, the item's id, its place and its stack count.
select
  item_guid,
  character_id,
  item2_id,
  location::int as location,
  bag_index,
  stack_count
from character_item
where character_id in (
  select character_id
  from character
  where account_id in (
    select account_id from account where login_name = any($1)
  )
)
order by item_guid;
