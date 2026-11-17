-- Deletes the retail-record rows of `creature_auto_attack` that are not one of the rows the
-- import would write, whole (`$1` to the last parameter are the columns of those
-- rows). Rows of any other source are left alone.
delete from creature_auto_attack
where source = 'retail_record'
  and not exists (
    select 1
    from unnest($1::int[], $2::int[], $3::smallint[], $4::text[])
      as incoming (creature_id, spell4_id, order_index, reason)
    where incoming.creature_id = creature_auto_attack.creature_id
      and incoming.spell4_id = creature_auto_attack.spell4_id
      and incoming.order_index = creature_auto_attack.order_index
      and incoming.reason = creature_auto_attack.reason
  );
