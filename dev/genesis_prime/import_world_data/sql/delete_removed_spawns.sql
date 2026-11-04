-- Deletes the world-database spawns whose row id is no longer in the file (`$1`
-- is every row id of the file), with their stats, and leaves every row of any
-- other source alone. Gives how many were deleted.
with removed as (
  delete from spawn
  where source = 'world_database'
    and source_row <> all($1::int[])
  returning 1
)
select count(*)::int as removed from removed;
