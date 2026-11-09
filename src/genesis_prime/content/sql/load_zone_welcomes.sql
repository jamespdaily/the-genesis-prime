-- Every row of the zone_welcome table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/zone_welcome). The checks run on these
-- rows, not in SQL.
select
  world_zone_id,
  tutorial_id
from zone_welcome
order by world_zone_id;
