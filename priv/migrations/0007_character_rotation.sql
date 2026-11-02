-- The way a character faces where it is saved, as the yaw, pitch and roll in
-- radians that message 0x262's movement command of kind 14 carries and that
-- the client's own movement update sends (0x140715350). A character that was
-- never saved facing a way holds 0, 0, 0.
--
-- Each is a 32-bit float, as the position beside it is. A float that is
-- infinite or not a number is refused: the client turns the unit by it, and
-- the server never writes one (Postgres orders NaN above every number, so the
-- bounds refuse it too). World 0 is no World row, so a character with no saved
-- place has nothing else, which now includes a facing, as for its zone and
-- position (0006).
alter table character
  add column rotation_yaw real not null default 0,
  add column rotation_pitch real not null default 0,
  add column rotation_roll real not null default 0,
  add constraint character_rotation_is_finite
    check (
      rotation_yaw between -3.4028235e38 and 3.4028235e38
      and rotation_pitch between -3.4028235e38 and 3.4028235e38
      and rotation_roll between -3.4028235e38 and 3.4028235e38
    ),
  add constraint character_no_world_has_no_rotation
    check (
      world_id <> 0
      or (rotation_yaw = 0 and rotation_pitch = 0 and rotation_roll = 0)
    );
