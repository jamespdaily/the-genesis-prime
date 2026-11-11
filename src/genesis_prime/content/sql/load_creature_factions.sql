-- Every row of the creature_faction table in creature id order: the one query the
-- load makes of the table at start (genesis_prime/content/creature_faction). The
-- checks run on these rows, not in SQL.
select
  creature_id,
  faction_id
from creature_faction
order by creature_id;
