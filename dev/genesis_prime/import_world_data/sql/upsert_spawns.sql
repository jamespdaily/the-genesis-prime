-- Writes one batch of the world database's spawn rows (one array for each
-- column, in the order of the rows) as `world_database` rows keyed by their row id
-- in the file: a row not in the table is inserted, a row whose values differ is
-- updated and keeps its id, and a row that is the same is left alone. Gives how
-- many were inserted and how many changed. A row the schema refuses fails the
-- statement, naming the constraint.
with incoming as (
  select *
  from unnest(
    $1::int[], $2::smallint[], $3::int[], $4::int[], $5::int[],
    $6::real[], $7::real[], $8::real[], $9::real[], $10::real[], $11::real[],
    $12::int[], $13::int[], $14::int[], $15::int[], $16::int[], $17::bigint[],
    $18::int[]
  ) as t (
    source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  )
),
written as (
  insert into spawn (
    source, source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  )
  select
    'world_database', source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  from incoming
  on conflict (source_row) do update set
    entity_type = excluded.entity_type,
    creature_id = excluded.creature_id,
    world_id = excluded.world_id,
    area_id = excluded.area_id,
    x = excluded.x,
    y = excluded.y,
    z = excluded.z,
    rotation_x = excluded.rotation_x,
    rotation_y = excluded.rotation_y,
    rotation_z = excluded.rotation_z,
    display_info_id = excluded.display_info_id,
    outfit_info_id = excluded.outfit_info_id,
    faction_id = excluded.faction_id,
    base_faction_id = excluded.base_faction_id,
    quest_checklist_index = excluded.quest_checklist_index,
    active_prop_id = excluded.active_prop_id,
    world_socket_id = excluded.world_socket_id
  where (
    spawn.entity_type, spawn.creature_id, spawn.world_id, spawn.area_id,
    spawn.x, spawn.y, spawn.z, spawn.rotation_x, spawn.rotation_y,
    spawn.rotation_z, spawn.display_info_id, spawn.outfit_info_id,
    spawn.faction_id, spawn.base_faction_id, spawn.quest_checklist_index,
    spawn.active_prop_id, spawn.world_socket_id
  ) is distinct from (
    excluded.entity_type, excluded.creature_id, excluded.world_id,
    excluded.area_id, excluded.x, excluded.y, excluded.z, excluded.rotation_x,
    excluded.rotation_y, excluded.rotation_z, excluded.display_info_id,
    excluded.outfit_info_id, excluded.faction_id, excluded.base_faction_id,
    excluded.quest_checklist_index, excluded.active_prop_id,
    excluded.world_socket_id
  )
  returning (xmax = 0) as inserted
)
select
  (count(*) filter (where inserted))::int as inserted,
  (count(*) filter (where not inserted))::int as changed
from written;
