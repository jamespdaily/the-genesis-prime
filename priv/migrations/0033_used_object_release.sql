-- How long a used quest object, and the creatures standing at its place, stay out of
-- every player's sight after a use credited a quest objective, in milliseconds. The
-- client holds no value for it (the object's own respawn is the creature's death
-- time, a different case), and no retail record gives one, so thirty seconds is a
-- server choice. The wait applies to that one restart: the next creature at the
-- spawn lives and dies by its kind's own times (genesis_prime/world_map/map).
--
-- The name and its unit go into `game_number_name` first, which the row's unit is
-- checked against (migration 0014). A release time is a whole number of milliseconds
-- above 0: the spawn starts a timer of that many.

insert into game_number_name (name, unit) values
  ('used_object_release_ms', 'ms');

insert into game_number (name, value, unit, source, reason) values
  ('used_object_release_ms', 30000, 'ms', 'server_choice',
   'no client or retail value says how long a used quest object stays gone; 30 seconds is a server choice');

alter table game_number
  add constraint game_number_used_object_release_ms_is_a_whole_positive_ms
    check (name <> 'used_object_release_ms' or (value > 0 and value = trunc(value)));
