-- The numbers a player's health regenerates by out of combat
-- (genesis_prime/game/player_life), two server choices read at start into the
-- game_number record (genesis_prime/world_map/game_number). The client's text
-- 149418 says only that health regenerates slowly out of combat and holds no rate;
-- the multiplier it does hold, HealthRegenMultiplier (UnitProperty2 8, default
-- 1.0), is read from the client's table, not stored here.

insert into game_number (name, value, unit, source, source_row, reason) values
  ('health_regen_fraction', 0.025, 'fraction', 'server_choice', null,
   'no client value: text 149418 says only that health regenerates slowly out of combat'),
  ('health_regen_tick_ms', 500, 'ms', 'server_choice', null,
   'the shield''s own tick (UnitProperty2 177 default) taken for health too');
