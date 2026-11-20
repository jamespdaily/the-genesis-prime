-- The action slots saved for the characters of the accounts with these login names,
-- in the order of their characters, sets and slots, with every column the fixture
-- of a recorded session keeps (genesis_prime/wire_recording/fixture): the
-- character, the set, the slot and the ability, NULL for an empty slot.
select
  character_id,
  action_set::int as action_set,
  slot::int as slot,
  spell4_base_id
from character_action_slot
where character_id in (
  select character_id
  from character
  where account_id in (
    select account_id from account where login_name = any($1)
  )
)
order by character_id, action_set, slot;
