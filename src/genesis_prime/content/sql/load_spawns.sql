-- Every row of the spawn table with its health (stat 0) and level (stat 10)
-- when the row has them, in world and id order: the one query the load makes of
-- the table at start (genesis_prime/content/spawn). The selection of which
-- rows start runs on these rows, not in SQL.
select
  spawn.id,
  spawn.entity_type,
  spawn.creature_id,
  spawn.world_id,
  spawn.area_id,
  spawn.x,
  spawn.y,
  spawn.z,
  spawn.rotation_x,
  spawn.rotation_y,
  spawn.rotation_z,
  spawn.display_info_id,
  spawn.outfit_info_id,
  spawn.faction_id,
  spawn.base_faction_id,
  spawn.quest_checklist_index,
  spawn.active_prop_id,
  spawn.world_socket_id,
  health.value as health,
  level.value as level
from spawn
left join spawn_stat as health
  on health.spawn_id = spawn.id and health.stat = 0
left join spawn_stat as level
  on level.spawn_id = spawn.id and level.stat = 10
order by spawn.world_id, spawn.id;
