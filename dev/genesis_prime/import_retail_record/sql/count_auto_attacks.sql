-- Compares the retail-record rows of `creature_auto_attack` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another value, how many are the same, and
-- how many rows of the table the import would no longer write. Rows of any other
-- source are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[], $4::text[])
    as t (creature_id, spell4_id, order_index, reason)
),
existing as (
  select creature_id, spell4_id, order_index, reason
  from creature_auto_attack
  where source = 'retail_record'
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as removed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.reason) is distinct from (incoming.order_index, incoming.reason)
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.reason) is not distinct from (incoming.order_index, incoming.reason)
  ))::int as unchanged
from incoming
full join existing
  on existing.creature_id = incoming.creature_id
  and existing.spell4_id = incoming.spell4_id;
