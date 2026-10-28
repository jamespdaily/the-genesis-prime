-- The account's character with this id, as the world's entry needs it: the
-- same columns as the list, with the saved place. The account's id is in the
-- statement, so another account's character, which a modified client could
-- name, is never read. No row means the account has no such character.
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
  look_labels,
  look_values,
  bones,
  needs_rename
from character
where character_id = $1 and account_id = $2;
