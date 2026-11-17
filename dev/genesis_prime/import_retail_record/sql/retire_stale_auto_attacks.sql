-- Retires the retail-record rows of `creature_auto_attack` that no run has retired and that
-- are not one of the rows the import would write, whole (`$1` is the run that retires them;
-- `$2` to the last parameter are the columns of the rows to write). Rows of any other
-- source are left alone.
update creature_auto_attack
set retired_by_import = $1
where source = 'retail_record'
  and retired_by_import is null
  and not exists (
    select 1
    from unnest($2::int[], $3::int[], $4::smallint[], $5::text[])
      as incoming (creature_id, spell4_id, order_index, reason)
    where incoming.creature_id = creature_auto_attack.creature_id
      and incoming.spell4_id = creature_auto_attack.spell4_id
      and incoming.order_index = creature_auto_attack.order_index
      and incoming.reason = creature_auto_attack.reason
  );
