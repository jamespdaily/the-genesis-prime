-- Where each creature has spawns: one row for each creature, world, area and unit
-- type, with how many spawn rows stand there. The import chooses the unit types the
-- server fights with in code (genesis_prime/world_map/creature_unit_type).
select
  entity_type,
  creature_id,
  world_id,
  area_id,
  count(*)::int as spawns
from spawn
group by entity_type, creature_id, world_id, area_id
order by creature_id, world_id, area_id, entity_type;
