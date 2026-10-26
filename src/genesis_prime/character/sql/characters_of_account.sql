-- Every character of one account, oldest first.
select
  id,
  account_id,
  name,
  creation_id,
  gender,
  race_id,
  class_id,
  faction_id,
  experience,
  level,
  path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  customisation_labels,
  customisation_values,
  bone_values,
  requires_rename,
  disabled
from character
where account_id = $1
order by id;
