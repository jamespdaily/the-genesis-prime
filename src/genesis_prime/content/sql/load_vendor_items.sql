-- Every row of the vendor_item table in creature and position order: the other query the
-- load makes of the vendor tables at start (genesis_prime/content/vendor). The checks run
-- on these rows, not in SQL.
select
  creature_id,
  position,
  item_id
from vendor_item
order by creature_id, position;
