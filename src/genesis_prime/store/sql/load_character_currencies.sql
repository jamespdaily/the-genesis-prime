-- The currencies a character holds, one row each, by type. A currency with no row is 0.
select
  currency_type_id::int as currency_type_id,
  amount
from character_currency
where character_id = $1
order by currency_type_id;
