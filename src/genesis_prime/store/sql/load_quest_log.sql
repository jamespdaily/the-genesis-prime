-- The quests a character has a record of, in quest id order, as the load hands
-- them to the quest log's decode (genesis_prime/game/quest_log). A row of any state
-- but 1 and 2 has no active entry, so its active columns are NULL (the table's
-- `character_quest_active_has_its_entry`). Only a completed row has a time
-- (`character_quest_completed_has_a_time`): `completed_at` is its whole Unix seconds,
-- and 0 for a row of another state, which the decode does not read, since squirrel
-- cannot type a timestamptz or a computed column that may be NULL.
select
  quest_id,
  state::int as state,
  coalesce(extract(epoch from completed_at), 0)::bigint as completed_at,
  placeholder_objective_id,
  tracked,
  done_mask,
  progress,
  quest_ms_left,
  objective_ms_left,
  kill_mask
from character_quest
where character_id = $1
order by quest_id;
