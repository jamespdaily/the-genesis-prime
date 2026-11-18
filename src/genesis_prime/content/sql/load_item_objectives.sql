-- Every row of the item_objective table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/item_objective). The checks run on these
-- rows, not in SQL.
select
  objective_id,
  kind,
  item2_id,
  creature2_id
from item_objective
order by objective_id;
