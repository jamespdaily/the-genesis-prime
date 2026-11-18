-- Every row of the kill_objective table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/kill_objective). The checks run on these
-- rows, not in SQL.
select
  objective_id
from kill_objective
order by objective_id;
