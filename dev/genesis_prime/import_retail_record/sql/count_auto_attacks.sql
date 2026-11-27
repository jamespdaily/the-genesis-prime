-- Compares the retail-record rows of `creature_auto_attack` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another order, how many are the same, and
-- how many rows of the table the import would no longer write, which a run retires.
-- A row is the same when its creature, spell and order are. Rows of any other
-- source and rows a run has retired are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[])
    as t (creature_id, spell4_id, order_index)
),
existing as (
  select creature_id, spell4_id, order_index
  from creature_auto_attack
  where source = 'retail_record' and retired_by_import is null
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as retired,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and existing.order_index is distinct from incoming.order_index
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and existing.order_index is not distinct from incoming.order_index
  ))::int as unchanged
from incoming
full join existing
  on existing.creature_id = incoming.creature_id
  and existing.spell4_id = incoming.spell4_id;
