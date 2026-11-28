-- The account's characters as the character list needs them, in the order they
-- were created, each with the Item2 ids of the items it holds at location 0
-- (worn), in bag order.
select
  character_id,
  name,
  gender::int as gender,
  race_id::int as race_id,
  class_id::int as class_id,
  faction_id,
  level,
  path::int as path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  rotation_yaw,
  rotation_pitch,
  rotation_roll,
  look_labels,
  look_values,
  bones,
  needs_rename,
  array(
    select item2_id
    from character_item
    where character_item.character_id = character.character_id
      and location = 0
    order by bag_index
  ) as worn_item2_ids
from character
where account_id = $1
order by character_id;
