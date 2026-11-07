-- Every row of the server_proxy table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/server_proxy). The checks run on these
-- rows, not in SQL.
select
  spell4_base_id,
  phase,
  spell4_id
from server_proxy
order by spell4_base_id, phase, spell4_id;
