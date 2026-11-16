-- Every row of the held_objective table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/held_objective). The checks run on these
-- rows, not in SQL.
select
  objective_id
from held_objective
order by objective_id;
