-- Every row of the arrival_objective table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/arrival_objective). The checks run on these
-- rows, not in SQL.
select
  objective_id
from arrival_objective
order by objective_id;
