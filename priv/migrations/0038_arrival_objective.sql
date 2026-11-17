-- Content table `arrival_objective`: the QuestObjective rows of type 5 (a scripted objective,
-- done only by the server's 0x361) whose text asks only to reach a place, loaded once at start
-- into a persistent term (genesis_prime/content) and never queried during play. It follows
-- the pattern of `held_objective` (0034): `source`, `source_row` and `reason`, and the same
-- checks.
--
-- A visible, required scripted objective that no creature links and that has a marker
-- completes in one of three ways (genesis_prime/game/objective, `script_of`): a row here is
-- done when the player stands at one of its markers, an objective a spell effect or an item
-- names stays open, and every other one is done when the quest is accepted. The client has
-- no rule that says which of these objectives only asks to go somewhere: every one draws its
-- marker as the destination whatever it asks, so each row is the server's choice, read from
-- the objective's text, with the text in its reason. The load checks each row against the
-- client's tables (genesis_prime/game/arrival_objective).

create table arrival_objective (
  objective_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint arrival_objective_pkey primary key (objective_id),
  constraint arrival_objective_id_is_positive check (objective_id > 0),
  constraint arrival_objective_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint arrival_objective_source_row_is_unique unique (source, source_row),
  constraint arrival_objective_source_row_is_positive check (source_row > 0),
  constraint arrival_objective_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint arrival_objective_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint arrival_objective_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into arrival_objective (objective_id, source, reason) values
  (4770, 'server_choice',
   'Quest2 3667 "The Tower", objective text "Investigate the Ancient Tower, which is generating the snowstorm"; asks only to reach a place, which the player''s position at its marker shows'),
  (4871, 'server_choice',
   'Quest2 3770 "Finish Him!", objective text "Go to the Escape Pod and flee the Skull''s Eye before it crashes"; asks only to reach a place, which the player''s position at its marker shows'),
  (6164, 'server_choice',
   'Quest2 4526 "Spatial Anomaly", objective text "Investigate ship wreckage near Settler''s Reach"; asks only to reach a place, which the player''s position at its marker shows'),
  (6579, 'server_choice',
   'Quest2 4727 "Seeking Forster", objective text "Locate Ranger Forster''s campsite"; asks only to reach a place, which the player''s position at its marker shows'),
  (7646, 'server_choice',
   'Quest2 5260 "Immediate Report", objective text "Go to the Thermock Chronicle House"; asks only to reach a place, which the player''s position at its marker shows'),
  (16347, 'server_choice',
   'Quest2 9068 "Occasionally, Power Uncorrupts", objective text "Enter the Harmonious Portal to get to the Keeper''s Sanctuary"; asks only to reach a place, which the player''s position at its marker shows'),
  (16585, 'server_choice',
   'Quest2 9165 "The Amenities of Lightreach", objective text "Find the Lightreach Mailbox in Lightreach Mission in Ellevar"; asks only to reach a place, which the player''s position at its marker shows'),
  (16586, 'server_choice',
   'Quest2 9165 "The Amenities of Lightreach", objective text "Find the Lightreach Taxi Kiosk in Lightreach Mission in Ellevar"; asks only to reach a place, which the player''s position at its marker shows'),
  (16587, 'server_choice',
   'Quest2 9165 "The Amenities of Lightreach", objective text "Find the Transmat Terminal in Lightreach Mission in Ellevar"; asks only to reach a place, which the player''s position at its marker shows'),
  (18158, 'server_choice',
   'Quest2 4520 "Tremor Ridge Kidnappings", objective text "Locate the Marauder camp in Deadstar Ravine"; asks only to reach a place, which the player''s position at its marker shows'),
  (18629, 'server_choice',
   'Quest2 9705 "Germinating Concern", objective text "Investigate the village of Quiet Downs"; asks only to reach a place, which the player''s position at its marker shows'),
  (18630, 'server_choice',
   'Quest2 9706 "Germinating Concern", objective text "Investigate the village of Quiet Downs"; asks only to reach a place, which the player''s position at its marker shows'),
  (18931, 'server_choice',
   'Quest2 9165 "The Amenities of Lightreach", objective text "Find the Rental Mount Vendor in Lightreach Mission in Ellevar"; asks only to reach a place, which the player''s position at its marker shows'),
  (18944, 'server_choice',
   'Quest2 9165 "The Amenities of Lightreach", objective text "Find a Radiant Legion Guard in Lightreach Mission in Ellevar"; asks only to reach a place, which the player''s position at its marker shows'),
  (19192, 'server_choice',
   'Quest2 7057 "Ready for the Big Time", objective text "Travel to Nexus from Shuttle Bay 46"; asks only to reach a place, which the player''s position at its marker shows'),
  (19336, 'server_choice',
   'Quest2 10115 "zTrack: Celestial River Rush", objective text "Go to Checkpoint 1 near the Verdant Vale in Celestion on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19337, 'server_choice',
   'Quest2 10115 "zTrack: Celestial River Rush", objective text "Go to Checkpoint 2 near Greenbough Glen in Celestion on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19338, 'server_choice',
   'Quest2 10115 "zTrack: Celestial River Rush", objective text "Go to Checkpoint 3 near Woodhaven in Celestion on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19339, 'server_choice',
   'Quest2 10115 "zTrack: Celestial River Rush", objective text "Go to the Finish Line near Thistlewood Thicket in Celestion on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19340, 'server_choice',
   'Quest2 10115 "zTrack: Celestial River Rush", objective text "Go to Checkpoint 4 on the Celestial Falls in Celestion on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19346, 'server_choice',
   'Quest2 10127 "Expedition: Infestation", objective text "Explore the X-82 Cargo Ship"; asks only to reach a place, which the player''s position at its marker shows'),
  (19357, 'server_choice',
   'Quest2 10132 "Expedition: The Gauntlet", objective text "Assess the situation on the ship"; asks only to reach a place, which the player''s position at its marker shows'),
  (19360, 'server_choice',
   'Quest2 10117 "zTrack: Whitevale Wipeout", objective text "Go to Checkpoint 1 near Thermock Lake East on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19361, 'server_choice',
   'Quest2 10117 "zTrack: Whitevale Wipeout", objective text "Go to Checkpoint 2 near Profitorium 9 on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19362, 'server_choice',
   'Quest2 10117 "zTrack: Whitevale Wipeout", objective text "Go to Checkpoint 3 near the ZubbleBubble Crash Site on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19363, 'server_choice',
   'Quest2 10117 "zTrack: Whitevale Wipeout", objective text "Go to Checkpoint 4 near the waterfall of Rimewater River on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19364, 'server_choice',
   'Quest2 10117 "zTrack: Whitevale Wipeout", objective text "Go to the Finish Line near Snow Sprout Farm on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19366, 'server_choice',
   'Quest2 10116 "zTrack: Savannah Speedway", objective text "Go to Checkpoint 1 near the Bloodfire Savannah in Deradune on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19367, 'server_choice',
   'Quest2 10116 "zTrack: Savannah Speedway", objective text "Go to Checkpoint 2 near Outreach Post in Deradune on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19368, 'server_choice',
   'Quest2 10116 "zTrack: Savannah Speedway", objective text "Go to Checkpoint 3 in Bloodtalon Perch in Deradune on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19369, 'server_choice',
   'Quest2 10116 "zTrack: Savannah Speedway", objective text "Go to Checkpoint 4 near the Feralplain Collective in Deradune on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (19371, 'server_choice',
   'Quest2 10116 "zTrack: Savannah Speedway", objective text "Go to the Finish Line on top of Metal Maw''s Cage in Deradune on a hoverboard"; asks only to reach a place, which the player''s position at its marker shows'),
  (21495, 'server_choice',
   'Quest2 10611 "The Greatest Race", objective text "Go to Checkpoint 1 near Academy Corner on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21496, 'server_choice',
   'Quest2 10611 "The Greatest Race", objective text "Go to the Finish Line near Fortune''s Ground on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21497, 'server_choice',
   'Quest2 10611 "The Greatest Race", objective text "Go to Checkpoint 2 near the Traverse Tunnels on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21498, 'server_choice',
   'Quest2 10611 "The Greatest Race", objective text "Go to Checkpoint 3 near the Court of Judgment on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21499, 'server_choice',
   'Quest2 10611 "The Greatest Race", objective text "Go to Checkpoint 4 near Fortune''s Ground on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21501, 'server_choice',
   'Quest2 10613 "The Greatest Race", objective text "Go to Checkpoint 1 near Spaceport Alpha on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21502, 'server_choice',
   'Quest2 10613 "The Greatest Race", objective text "Go to Checkpoint 2 near the Parade Grounds on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21503, 'server_choice',
   'Quest2 10613 "The Greatest Race", objective text "Go to Checkpoint 3 near Luminous Gardens on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21504, 'server_choice',
   'Quest2 10613 "The Greatest Race", objective text "Go to Checkpoint 4 near Legions Way on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows'),
  (21505, 'server_choice',
   'Quest2 10613 "The Greatest Race", objective text "Go to the Finish Line near Legions Way on your Cargo Racer"; asks only to reach a place, which the player''s position at its marker shows');
