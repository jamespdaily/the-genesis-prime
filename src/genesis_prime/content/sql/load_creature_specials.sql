-- Every row of the creature_special table no import has retired, in creature id and list order: the one query
-- the load makes of the table at start (genesis_prime/content/creature_special). The
-- checks run on these rows, not in SQL.
select
  creature_id,
  spell4_id,
  order_index,
  cooldown_ms
from creature_special
where retired_by_import is null
order by creature_id, order_index;
