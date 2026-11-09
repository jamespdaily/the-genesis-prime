-- Every row of the vendor table in creature order: one of the two queries the load makes
-- of the vendor tables at start (genesis_prime/content/vendor). The checks run on these
-- rows, not in SQL.
select
  creature_id,
  buy_multiplier,
  sell_multiplier
from vendor
order by creature_id;
