-- Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
-- parameter their columns) that the table has no unretired retail-record row for, as
-- retail-record rows with no source row. A row of another source with the same creature and
-- spell, or the same place in the creature's list, is refused by the table's own keys.
insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason, import_id)
select creature_id, spell4_id, order_index, 'retail_record', reason, $1
from unnest($2::int[], $3::int[], $4::smallint[], $5::text[])
  as incoming (creature_id, spell4_id, order_index, reason)
where not exists (
  select 1
  from creature_auto_attack as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
    and existing.retired_by_import is null
);
