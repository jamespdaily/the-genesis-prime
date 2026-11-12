-- Every row of the tutorial_quest table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/tutorial_quest). The checks run on these
-- rows, not in SQL.
select
  quest_id,
  follows_quest_id
from tutorial_quest
order by quest_id;
