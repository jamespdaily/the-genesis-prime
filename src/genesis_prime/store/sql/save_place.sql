-- Saves where a character stands: its world, zone, position and facing, only
-- while the character is still held by the login that made the save, that is
-- while its `session_epoch` is still the one that login raised it to
-- (load_character.sql). A login that came after raised the epoch, so a save
-- from an older login matches no row and changes nothing. The account's id is
-- in the statement, as for a load. No row means the epoch moved on or the
-- account has no such character.
update character
set
  world_id = $4,
  world_zone_id = $5,
  position_x = $6,
  position_y = $7,
  position_z = $8,
  rotation_yaw = $9,
  rotation_pitch = $10,
  rotation_roll = $11
where character_id = $1 and account_id = $2 and session_epoch = $3
returning character_id;
