-- Puts a character at a place for a developer's database, before the character
-- logs in: its world, zone and position, facing the way a character never saved
-- facing a way does (yaw, pitch and roll 0: migration 0007). A login resets the
-- save sequence, so no save is fenced by this write. No character of that id
-- gives no row.
update character
set
  world_id = $2,
  world_zone_id = $3,
  position_x = $4,
  position_y = $5,
  position_z = $6,
  rotation_yaw = 0,
  rotation_pitch = 0,
  rotation_roll = 0
where character_id = $1
returning character_id;
