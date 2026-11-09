-- Saves where a character stands: its world, zone, position and facing, and the
-- health, experience and level it has, in one statement, so they are saved
-- together or not at all; the experience is $15 and the level it makes $16.
-- The health is $13 when $14 is true, and NULL (nothing saved: the next entry
-- is alive at full health) when it is false, since
-- squirrel cannot type a parameter that may be NULL. A dead player saves 0,
-- which its next entry is dead at. It writes only
-- while the character is still held by the login that made the save, that is
-- while its `session_epoch` is still the one that login raised it to
-- (load_character.sql), and only when the save is newer than the last one stored
-- for that login: `save_sequence` ($12) is above the stored one. A login that
-- came after raised the epoch, so a save from an older login matches no row and
-- changes nothing; a save of this login that comes after a newer one of its own
-- matches none either. The account's id is in the statement, as for a load. No
-- row means the epoch moved on, a newer save was stored first, or the account
-- has no such character.
update character
set
  world_id = $4,
  world_zone_id = $5,
  position_x = $6,
  position_y = $7,
  position_z = $8,
  rotation_yaw = $9,
  rotation_pitch = $10,
  rotation_roll = $11,
  save_sequence = $12,
  health = case when $14 then $13::int end,
  experience = $15::int,
  level = $16::int
where character_id = $1 and account_id = $2 and session_epoch = $3
  and save_sequence < $12
returning character_id;
