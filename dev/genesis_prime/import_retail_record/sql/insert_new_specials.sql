-- Stub: writes nothing.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, import_id)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[], $5::int[]) as incoming (creature_id, spell4_id, order_index, cooldown_ms)
where false;
