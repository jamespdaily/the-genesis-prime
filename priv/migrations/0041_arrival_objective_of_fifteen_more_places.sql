-- Fifteen more rows of `arrival_objective` (0038): visible, required scripted objectives
-- with a marker whose text asks only to find or reach a place, each done when the player
-- stands at one of its markers (genesis_prime/game/objective, `script_of`) instead of when
-- the quest is accepted. No earlier objective of its quest and not the giver's marker
-- circle holds the marker, so the objective does not complete the moment it opens. The
-- reach of each marker is the client's own (WorldLocation2 radius, as
-- `IsPlayerAtWorldLocation` tests it); eight are 1 m points, as 38 of the 42 rows of 0038
-- are.

insert into arrival_objective (objective_id, source, reason) values
  (7217, 'server_choice',
   'Quest2 5079 "Hot on the Icy Trail", objective text "Locate the first clue somewhere in Thermock Hold"; asks only to reach a place, which the player''s position at its marker shows (marker radius 57 m)'),
  (7342, 'server_choice',
   'Quest2 5119 "Following the Elder Voices", objective text "Find the musical voice of the Wise One in Snowfade Grounds"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (7423, 'server_choice',
   'Quest2 5079 "Hot on the Icy Trail", objective text "Locate the second clue somewhere outside Thermock Hold"; asks only to reach a place, which the player''s position at its marker shows (marker radius 65 m)'),
  (7424, 'server_choice',
   'Quest2 5079 "Hot on the Icy Trail", objective text "Locate the third clue somewhere in Whitespring Fields"; asks only to reach a place, which the player''s position at its marker shows (marker radius 64 m)'),
  (8074, 'server_choice',
   'Quest2 5362 "Missing in Action", objective text "Travel to $p(creature=23174)s last known position"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (8204, 'server_choice',
   'Quest2 5539 "Where Have All the Groomsmen Gone?", objective text "Find the wedding party caravan that was heading to Thermock Hold"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (9043, 'server_choice',
   'Quest2 5971 "Leader of the Pack", objective text "Search for survey data at the Exploration Society Camp in Howling Hills"; asks only to reach a place, which the player''s position at its marker shows (marker radius 20 m)'),
  (11479, 'server_choice',
   'Quest2 6785 "Boon of Hydris", objective text "Locate the origin of the relic somewhere in Lake Larallen"; asks only to reach a place, which the player''s position at its marker shows (marker radius 36 m)'),
  (12933, 'server_choice',
   'Quest2 6901 "The Reaper''s Harvest", objective text "Escape the blast in the Grimhold Quarantine Zone"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (14378, 'server_choice',
   'Quest2 7964 "An Ooze Ate My Brother!", objective text "Find $p(creature=39135) brother in Ghostwind Hollow"; asks only to reach a place, which the player''s position at its marker shows (2 markers of radius 160 m)'),
  (14544, 'server_choice',
   'Quest2 8044 "An Ooze Ate My Lover!", objective text "Find $p(creature=40081) lover within Ghostwind Hollow"; asks only to reach a place, which the player''s position at its marker shows (2 markers of radius 160 m)'),
  (16621, 'server_choice',
   'Quest2 9180 "Endgame", objective text "Search for Trinette at the Eldan Resonance Tower"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (17877, 'server_choice',
   'Quest2 9186 "Endgame", objective text "Find Stephanus the Traitor at the Eldan Resonance Tower"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (18072, 'server_choice',
   'Quest2 9315 "A Hop, Skip, and Jump", objective text "Reach the $(creature=53661) on the opposite tower in Exo-Site N22 in Celestion"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (18099, 'server_choice',
   'Quest2 9068 "Occasionally, Power Uncorrupts", objective text "Find a way down from the Keeper''s Sanctuary"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)');
