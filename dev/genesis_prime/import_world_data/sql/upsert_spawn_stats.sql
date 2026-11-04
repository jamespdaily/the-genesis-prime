-- Makes the stats of one batch of spawn rows the file's: the stat triples (the
-- row id in the file, the stat index and its value) are written, a stat a row
-- had that the file no longer gives is deleted, and a stat that is the same is
-- left alone. `$4` is the row ids of the whole batch, so a row with no stats in
-- the file loses the stats it had. Gives how many stats were written (inserted
-- or changed) and how many were deleted.
with incoming as (
  select *
  from unnest($1::int[], $2::smallint[], $3::real[])
    as t (source_row, stat, value)
),
mapped as (
  select spawn.id as spawn_id, incoming.stat, incoming.value
  from incoming
  join spawn on spawn.source_row = incoming.source_row
),
deleted as (
  delete from spawn_stat
  using spawn
  where spawn_stat.spawn_id = spawn.id
    and spawn.source_row = any($4::int[])
    and not exists (
      select 1 from mapped
      where mapped.spawn_id = spawn_stat.spawn_id
        and mapped.stat = spawn_stat.stat
    )
  returning 1
),
written as (
  insert into spawn_stat (spawn_id, stat, value)
  select spawn_id, stat, value from mapped
  on conflict (spawn_id, stat) do update set value = excluded.value
  where spawn_stat.value is distinct from excluded.value
  returning 1
)
select
  (select count(*) from written)::int as written,
  (select count(*) from deleted)::int as deleted;
