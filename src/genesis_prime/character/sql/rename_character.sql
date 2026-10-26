-- Gives a character of the account a new name, clears its need to be renamed
-- and returns it. No row is returned when the account has no such character.
update character
set name = $3, requires_rename = false
where id = $1 and account_id = $2
returning
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
  disabled;
