-- The experience a character has, saved with its place (save_place.sql, with
-- the level it gives) and read at entry (load_character.sql), and the numbers a
-- kill's experience is worked out from.
--
-- NULL is nothing saved, the pattern of `health` (0013): the character enters
-- with the least experience of its level, which is what the client was sent
-- before this column, so no row needs a backfill (the migration cannot read the
-- client's XpPerLevel table). A saved experience is not negative, and an
-- integer holds at most 2^31 - 1, so the database refuses the value the client's
-- 0x25E breaks on (2^31 or more, opcode.0x25e.safe_body). The levels the
-- experience reaches are the client's table's, so the table holds no other bound.
alter table character
  add column experience integer,
  add constraint character_experience_is_not_negative
    check (experience >= 0);

-- A kill's experience is the base quest experience of the creature's level (the
-- client's XpPerLevel.baseQuestXpPerLevel) times a fraction, the creature's
-- difficulty weight (Creature2Difficulty.clusterContributionValueDifficulty) and
-- a multiplier for how far the creature's level is from the player's. The client
-- decides none of it: the server sends the amount in 0x1ac (0x14050cbf0), so each
-- number is a server choice that states its reason. A multiplier is not a
-- fraction (the highest is above 1), so its unit is new.
alter table game_number
  drop constraint game_number_unit_is_known,
  add constraint game_number_unit_is_known
    check (unit in ('units', 'ms', 'threat', 'fraction', 'multiplier'));

insert into game_number_name (name, unit) values
  ('kill_experience_fraction', 'fraction'),
  ('kill_experience_multiplier_below_4', 'multiplier'),
  ('kill_experience_multiplier_below_3', 'multiplier'),
  ('kill_experience_multiplier_below_2', 'multiplier'),
  ('kill_experience_multiplier_below_1', 'multiplier'),
  ('kill_experience_multiplier_same', 'multiplier'),
  ('kill_experience_multiplier_above_1', 'multiplier'),
  ('kill_experience_multiplier_above_2', 'multiplier'),
  ('kill_experience_multiplier_above_3', 'multiplier'),
  ('kill_experience_multiplier_above_4', 'multiplier');

insert into game_number (name, value, unit, source, reason) values
  ('kill_experience_fraction', 0.25, 'fraction', 'server_choice',
   'no client value says how much experience a kill gives (the server sends the amount in 0x1ac, opcode.0x1ac, 0x14050cbf0); a quarter of the base quest experience of the creature''s level is a server choice, weighed by the creature''s Creature2Difficulty clusterContributionValueDifficulty though no client code shows that column feeds experience'),
  ('kill_experience_multiplier_below_4', 0, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 4 or more levels below the player gives none, a server choice'),
  ('kill_experience_multiplier_below_3', 0.25, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 3 levels below the player gives a quarter, a server choice'),
  ('kill_experience_multiplier_below_2', 0.5, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 2 levels below the player gives half, a server choice'),
  ('kill_experience_multiplier_below_1', 0.75, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 1 level below the player gives three quarters, a server choice'),
  ('kill_experience_multiplier_same', 1.0, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature of the player''s level gives the whole amount, a server choice'),
  ('kill_experience_multiplier_above_1', 1.1, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 1 level above the player gives a tenth more, a server choice'),
  ('kill_experience_multiplier_above_2', 1.2, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 2 levels above the player gives a fifth more, a server choice'),
  ('kill_experience_multiplier_above_3', 1.3, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 3 levels above the player gives three tenths more, a server choice'),
  ('kill_experience_multiplier_above_4', 1.4, 'multiplier', 'server_choice',
   'no client value says how a level gap scales a kill''s experience (opcode.0x1ac); a creature 4 or more levels above the player gives two fifths more, a server choice');

-- The fraction lies above 0 and at most 1, so a kill gives some experience and
-- never more than the base amount; a multiplier is not negative, so a kill never
-- takes experience away. Each rule is scoped to its names.
alter table game_number
  add constraint game_number_kill_experience_fraction_is_above_0_up_to_1
    check (name <> 'kill_experience_fraction' or (value > 0 and value <= 1)),
  add constraint game_number_kill_experience_multiplier_is_not_negative
    check (name !~ '^kill_experience_multiplier_' or value >= 0);
