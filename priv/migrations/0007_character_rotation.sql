-- The way a character faces where it is saved, as the yaw, pitch and roll in
-- radians that message 0x262's movement command of kind 14 carries and that
-- the client's own movement update sends (0x140715350). A character that was
-- never saved facing a way holds 0, 0, 0.
--
-- Each is a 32-bit float, as the position beside it is. A float that is
-- infinite or not a number is refused, in the rotation and in the position: the
-- client places and turns the unit by them, and the server never writes one
-- (Postgres orders NaN above every number, so the bounds refuse it too). World 0
-- is no World row, so a character with no saved place has nothing else, which
-- now includes a facing, as for its zone and position (0006).
--
-- `save_sequence` is the number of the last save of the login that holds the
-- character, which each login resets to 0 when it raises `session_epoch`
-- (load_character.sql). A save names its login's epoch and its own sequence,
-- 1 for the first of a login, and is written only when its sequence is above
-- the stored one (save_place.sql), so two saves of one login that reach the
-- database out of order leave the later one's place.
alter table character
  add column rotation_yaw real not null default 0,
  add column rotation_pitch real not null default 0,
  add column rotation_roll real not null default 0,
  add column save_sequence integer not null default 0,
  add constraint character_rotation_is_finite
    check (
      rotation_yaw between -3.4028235e38 and 3.4028235e38
      and rotation_pitch between -3.4028235e38 and 3.4028235e38
      and rotation_roll between -3.4028235e38 and 3.4028235e38
    ),
  add constraint character_position_is_finite
    check (
      position_x between -3.4028235e38 and 3.4028235e38
      and position_y between -3.4028235e38 and 3.4028235e38
      and position_z between -3.4028235e38 and 3.4028235e38
    ),
  add constraint character_save_sequence_is_not_negative
    check (save_sequence >= 0),
  add constraint character_no_world_has_no_rotation
    check (
      world_id <> 0
      or (rotation_yaw = 0 and rotation_pitch = 0 and rotation_roll = 0)
    );
