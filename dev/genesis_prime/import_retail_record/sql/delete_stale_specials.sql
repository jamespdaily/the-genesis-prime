-- Deletes the retail-record rows of `creature_special` that are not one of the rows the
-- import would write, whole (`$1` to the last parameter are the columns of those
-- rows). Rows of any other source are left alone.
delete from creature_special
where source = 'retail_record'
  and not exists (
    select 1
    from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
      as incoming (creature_id, spell4_id, order_index, cooldown_ms, reason)
    where incoming.creature_id = creature_special.creature_id
      and incoming.spell4_id = creature_special.spell4_id
      and incoming.order_index = creature_special.order_index
      and incoming.cooldown_ms = creature_special.cooldown_ms
      and incoming.reason = creature_special.reason
  );
