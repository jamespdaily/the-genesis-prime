-- The account's characters as the character list needs them, in the order they
-- were created.
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
  position_z
from character
where account_id = $1
order by character_id;
