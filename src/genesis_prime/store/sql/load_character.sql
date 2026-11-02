-- The account's character with this id, as the world's entry needs it: the
-- same columns as the list, with the saved place, and the character taken by
-- this login: `session_epoch` is raised by one in the same statement, with
-- `save_sequence` back to 0 for the new login, and the new epoch returned, so
-- the login that read the character is the one that holds that epoch, and a
-- save made under an earlier epoch (an older login's) finds no row to change
-- (save_place.sql). The account's id is in the
-- statement, so another account's character, which a modified client could
-- name, is never taken. No row means the account has no such character.
update character
set session_epoch = session_epoch + 1, save_sequence = 0
where character_id = $1 and account_id = $2
returning
  character_id,
  session_epoch,
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
  needs_rename;
