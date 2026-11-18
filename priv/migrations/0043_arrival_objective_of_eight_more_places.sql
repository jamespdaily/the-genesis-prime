-- Eight more rows of `arrival_objective` (0038): visible, required scripted objectives
-- with a marker whose text asks only to find or reach a place, each done when the player
-- stands at one of its markers (genesis_prime/game/objective, `script_of`) instead of when
-- the quest is accepted. No earlier objective of its quest and not the giver's marker
-- circle holds the marker, so the objective does not complete the moment it opens. The
-- reach of each marker is the client's own (WorldLocation2 radius, as
-- `IsPlayerAtWorldLocation` tests it); four are 1 m points, as 38 of the 42 rows of 0038
-- are. The giver creature of each row's quest is spawned in the marker's world, so a
-- player can take the quest.

insert into arrival_objective (objective_id, source, reason) values
  (7342, 'server_choice',
   'Quest2 5119 "Following the Elder Voices", objective text "Find the musical voice of the Wise One in Snowfade Grounds"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (8074, 'server_choice',
   'Quest2 5362 "Missing in Action", objective text "Travel to $p(creature=23174)s last known position"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (8204, 'server_choice',
   'Quest2 5539 "Where Have All the Groomsmen Gone?", objective text "Find the wedding party caravan that was heading to Thermock Hold"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)'),
  (9043, 'server_choice',
   'Quest2 5971 "Leader of the Pack", objective text "Search for survey data at the Exploration Society Camp in Howling Hills"; asks only to reach a place, which the player''s position at its marker shows (marker radius 20 m)'),
  (11479, 'server_choice',
   'Quest2 6785 "Boon of Hydris", objective text "Locate the origin of the relic somewhere in Lake Larallen"; asks only to reach a place, which the player''s position at its marker shows (marker radius 36 m)'),
  (14378, 'server_choice',
   'Quest2 7964 "An Ooze Ate My Brother!", objective text "Find $p(creature=39135) brother in Ghostwind Hollow"; asks only to reach a place, which the player''s position at its marker shows (2 markers of radius 160 m)'),
  (14544, 'server_choice',
   'Quest2 8044 "An Ooze Ate My Lover!", objective text "Find $p(creature=40081) lover within Ghostwind Hollow"; asks only to reach a place, which the player''s position at its marker shows (2 markers of radius 160 m)'),
  (18099, 'server_choice',
   'Quest2 9068 "Occasionally, Power Uncorrupts", objective text "Find a way down from the Keeper''s Sanctuary"; asks only to reach a place, which the player''s position at its marker shows (marker radius 1 m)');
