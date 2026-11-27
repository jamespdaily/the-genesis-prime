-- Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
-- parameter their columns) that the table has no unretired retail-record row for, as
-- retail-record rows with no source row. A row of another source with the same creature and
-- spell, or the same place in the creature's list, is refused by the table's own keys.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, import_id)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[], $5::int[])
  as incoming (creature_id, spell4_id, order_index, cooldown_ms)
where not exists (
  select 1
  from creature_special as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
    and existing.retired_by_import is null
);
