-- Every row of the projector_landing table in key order: the one query the load makes
-- of the table at start (genesis_prime/content/projector_landing). The checks run on
-- these rows, not in SQL.
select
  creature_id,
  faction_enum,
  objective_id,
  world_location2_id
from projector_landing
order by creature_id, faction_enum;
