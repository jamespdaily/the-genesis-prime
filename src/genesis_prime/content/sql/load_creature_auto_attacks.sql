-- Every row of the creature_auto_attack table no import has retired, in creature id and turn order: the one
-- query the load makes of the table at start (genesis_prime/content/creature_auto_attack).
-- The checks run on these rows, not in SQL.
select
  creature_id,
  spell4_id,
  order_index
from creature_auto_attack
where retired_by_import is null
order by creature_id, order_index;
