-- The quests recorded for the characters of the accounts with these login names,
-- in the order of their characters and quest ids, with every column the fixture
-- of a recorded session keeps (genesis_prime/wire_recording/fixture). A row of a
-- state but 1 and 2 has no active entry, so its active columns are NULL. Only a
-- completed row (state 3) has a time (`character_quest_completed_has_a_time`):
-- `completed_at_microseconds` is its Unix time in whole microseconds, the
-- column's own precision, and 0 for a row of another state, since squirrel cannot
-- type a computed column that may be NULL.
select
  character_id,
  quest_id,
  state::int as state,
  coalesce(floor(extract(epoch from completed_at) * 1000000), 0)::bigint
    as completed_at_microseconds,
  placeholder_objective_id,
  tracked,
  done_mask,
  progress,
  quest_ms_left,
  objective_ms_left,
  kill_mask
from character_quest
where character_id in (
  select character_id
  from character
  where account_id in (
    select account_id from account where login_name = any($1)
  )
)
order by character_id, quest_id;
