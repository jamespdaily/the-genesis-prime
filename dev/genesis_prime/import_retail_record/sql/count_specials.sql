-- Compares the retail-record rows of `creature_special` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another value, how many are the same, and
-- how many rows of the table the import would no longer write, which a run retires.
-- Rows of any other source and rows a run has retired are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
    as t (creature_id, spell4_id, order_index, cooldown_ms, reason)
),
existing as (
  select creature_id, spell4_id, order_index, cooldown_ms, reason
  from creature_special
  where source = 'retail_record' and retired_by_import is null
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as retired,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms, existing.reason) is distinct from (incoming.order_index, incoming.cooldown_ms, incoming.reason)
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms, existing.reason) is not distinct from (incoming.order_index, incoming.cooldown_ms, incoming.reason)
  ))::int as unchanged
from incoming
full join existing
  on existing.creature_id = incoming.creature_id
  and existing.spell4_id = incoming.spell4_id;
