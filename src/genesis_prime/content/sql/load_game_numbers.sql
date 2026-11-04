-- Every row of the game_number table in name order: the one query the load makes
-- of the table at start (genesis_prime/content/game_number). The checks run on
-- these rows, not in SQL.
select
  name,
  value,
  unit
from game_number
order by name;
