-- The numbers a player's health regenerates by out of combat
-- (genesis_prime/game/player_life), two server choices read at start into the
-- game_number record (genesis_prime/world_map/game_number). The client's text
-- 149418 says only that health regenerates slowly out of combat and holds no rate;
-- the multiplier it does hold, HealthRegenMultiplier (UnitProperty2 8, default
-- 1.0), is read from the client's table, not stored here.
--
-- Each name is listed with its one unit before its row (migration 0014). A tick
-- adds part of the maximum, never all of it, and a time is a whole number of
-- milliseconds, since the load turns it into an integer and a tick of 0 would
-- fire again at once.

insert into game_number_name (name, unit) values
  ('health_regen_fraction', 'fraction'),
  ('health_regen_tick_ms', 'ms');

alter table game_number
  add constraint game_number_health_regen_fraction_is_between_0_and_1
    check (name <> 'health_regen_fraction' or (value > 0 and value < 1)),
  add constraint game_number_health_regen_tick_ms_is_a_whole_positive_ms
    check (name <> 'health_regen_tick_ms' or (value >= 1 and value = trunc(value)));

insert into game_number (name, value, unit, source, source_row, reason) values
  ('health_regen_fraction', 0.025, 'fraction', 'server_choice', null,
   'no client value: text 149418 says only that health regenerates slowly out of combat'),
  ('health_regen_tick_ms', 500, 'ms', 'server_choice', null,
   'the shield''s own tick (UnitProperty2 177 default) taken for health too');
