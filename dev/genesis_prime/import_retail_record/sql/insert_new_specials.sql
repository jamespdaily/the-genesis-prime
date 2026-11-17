-- Writes the rows the import wants (`$1` to the last parameter are their columns)
-- that the table has no retail-record row for, as retail-record rows with no source
-- row. A row of another source with the same creature and spell, or the same place in
-- the creature's list, is refused by the table's own keys.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', reason
from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
  as incoming (creature_id, spell4_id, order_index, cooldown_ms, reason)
where not exists (
  select 1
  from creature_special as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
);
