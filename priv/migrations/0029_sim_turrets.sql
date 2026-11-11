-- The two Sim-Turrets of the training simulation start as creatures that fight: each
-- gets the faction its own side's player may attack, and a creature_kind row with its
-- charge as its attack.
--
-- Creature2 73494 (the turret Exiles fight, objective 21288) and 74862 (the turret
-- Dominion fight, objective 21316) both give faction 219 in their own rows, which is
-- Friendly to both player factions, so neither could attack them (0x1403ad540).
-- Faction 1441 is Hostile to Exile (Faction2Relationship 2943: 1441 to 167, level 0)
-- and Friendly to Dominion (2944: 1441 to 166, level 10); faction 1442 is the
-- opposite (2946: 1442 to 166, level 0; 2947: 1442 to 167, level 10).
insert into creature_faction (creature_id, faction_id, source, reason) values
  (73494, 1441, 'server_choice',
   'the turret must be attackable by Exile only; Creature2.73494 gives faction 219, Friendly to both (0x1403ad540), and Faction2Relationship 2943 and 2944 make 1441 Hostile to Exile (167) and Friendly to Dominion (166)'),
  (74862, 1442, 'server_choice',
   'the turret must be attackable by Dominion only; Creature2.74862 gives faction 219, Friendly to both (0x1403ad540), and Faction2Relationship 2946 and 2947 make 1442 Hostile to Dominion (166) and Friendly to Exile (167)');

-- The charge each turret fights with: Spell4 85469 and 86978, each with a cast time of
-- 8000 ms and a telegraph (TelegraphDamage 16212, a rectangle 3 wide and 30 long), and
-- the time between two charges, a server choice. The client holds no respawn time for
-- a creature (`death.creature_respawn`), so the default's 60 s is repeated.
insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values
  (73494, 60000, 85469, 3000, 'server_choice',
   'the Sim-Turret fights with its charge, Spell4.85469 (castTime 8000, Spell4Telegraph 57886); respawn as the default (death.creature_respawn); the interval is a server choice'),
  (74862, 60000, 86978, 3000, 'server_choice',
   'the Sim-Turret fights with its charge, Spell4.86978 (castTime 8000, Spell4Telegraph 57885); respawn as the default (death.creature_respawn); the interval is a server choice');
