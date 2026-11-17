-- The specials of the creatures 0036 gives auto-attacks, as their Jabbithole pages list them
-- in the Abilities tab, each cast again after a cooldown of 10000 ms, a guess like the rows of
-- 0035: the client holds no cadence for a special. Bloodstone Oxian and Malverine Stalker
-- cast one cone of 3000 ms; Elderoot Deathcap casts the Earthen Roar of the Rootbrute
-- Grimspores, tier 1 (Spell4 55317) over tier 2 (55318), the server's choice. Venombite
-- Hatchling casts Venomous Mandible and has no auto-attack row: the auto-attacks its page
-- lists, Pinch (Spell4 6651) and Slice (6652), name a damage parameter the creature
-- formula does not read, so it keeps the default attack.

insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason) values
  (24058, 55308, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/bloodstone-oxian-12 (captured 20150416103144), Abilities tab, Reaching Bite listed at tier 1 (Spell4 55308); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'),
  (26026, 55283, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/malverine-stalker-22 (captured 20160718025408), Abilities tab, Whirl listed at tier 1 (Spell4 55283); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'),
  (24051, 55327, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/venombite-hatchling-12 (captured 20170915172422), Abilities tab, Venomous Mandible listed at tier 1 (Spell4 55327); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'),
  (36173, 55317, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/elderoot-deathcap-27 (captured 20170917055401), Abilities tab, Earthen Roar listed at tier 1 (Spell4 55317); the cooldown of 10000 ms is a guess: the client holds no cadence for a special');
