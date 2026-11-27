-- Stub: counts nothing.
select (-1)::int as inserted, (-1)::int as retired, (-1)::int as changed, (-1)::int as unchanged
from unnest($1::int[], $2::int[], $3::smallint[]) as t (creature_id, spell4_id, order_index) limit 1;
