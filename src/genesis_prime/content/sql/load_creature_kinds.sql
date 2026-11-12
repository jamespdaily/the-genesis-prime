-- Every row of the creature_kind table in creature id order, row 0 the default
-- first: the one query the load makes of the table at start
-- (genesis_prime/content/creature_kind). The checks run on these rows, not in SQL.
select
  creature_id,
  respawn_ms,
  attack_spell4_id,
  attack_interval_ms,
  guard_spell4_id,
  opening_spell4_id
from creature_kind
order by creature_id;
