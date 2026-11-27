-- Stub: writes nothing.
insert into creature_auto_attack (creature_id, spell4_id, order_index, source, import_id)
select creature_id, spell4_id, order_index, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[]) as incoming (creature_id, spell4_id, order_index)
where false;
