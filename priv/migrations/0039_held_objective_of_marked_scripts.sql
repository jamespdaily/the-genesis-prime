-- The visible scripted objectives with a marker that sit in a quest of an instance run, an
-- adventure or a dungeon (Quest2 questContentFinderTypeEnum 1 to 3): the server has no event
-- for those runs, so each stays open as a held_objective row does (0034), whether it is
-- done by a place, by a spell or by the quest being accepted.

insert into held_objective (objective_id, kind, source, reason) values
  (9884, 'instance_run', 'server_choice',
   'Quest2 6433 "Asteroid 3C48 [GROUP 5+]", objective text "Complete the Arm a Geddon public event on Asteroid 3C48"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 1)'),
  (11491, 'instance_run', 'server_choice',
   'Quest2 6794 "The Sunken Temple [GROUP 2+]", objective text "Route the circuitry to power the Generator in the Water Temple"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 1)'),
  (12524, 'instance_run', 'server_choice',
   'Quest2 6803 "Expedition: Shade''s Secret", objective text "Learn the secret of Zarkhov''s Shade"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (18629, 'instance_run', 'server_choice',
   'Quest2 9705 "Germinating Concern", objective text "Investigate the village of Quiet Downs"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (18630, 'instance_run', 'server_choice',
   'Quest2 9706 "Germinating Concern", objective text "Investigate the village of Quiet Downs"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (18664, 'instance_run', 'server_choice',
   'Quest2 9745 "Decoding Sim Core N-12 [GROUP 5+]", objective text "Complete the War of the Wilds adventure in Sim Core N-12"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 2)'),
  (19343, 'instance_run', 'server_choice',
   'Quest2 10125 "Expedition: Outpost M-13", objective text "Save Outpost M-13"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19344, 'instance_run', 'server_choice',
   'Quest2 10126 "Expedition: They Came from Fragment Zero!", objective text "Find out what happened to $p(creature=68637) crew"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19346, 'instance_run', 'server_choice',
   'Quest2 10127 "Expedition: Infestation", objective text "Explore the X-82 Cargo Ship"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19351, 'instance_run', 'server_choice',
   'Quest2 10130 "Expedition: Deep Space Exploration", objective text "Assess the situation on the Starhelm command deck"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19352, 'instance_run', 'server_choice',
   'Quest2 10130 "Expedition: Deep Space Exploration", objective text "Escape from the Steel Serpent and return to the Galactic Observer with your crew"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19354, 'instance_run', 'server_choice',
   'Quest2 10131 "Expedition: Deep Space Exploration", objective text "Assess the situation on the Starhelm command deck"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19355, 'instance_run', 'server_choice',
   'Quest2 10131 "Expedition: Deep Space Exploration", objective text "Escape from the Steel Serpent and return to the Galactic Observer with your crew"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19357, 'instance_run', 'server_choice',
   'Quest2 10132 "Expedition: The Gauntlet", objective text "Assess the situation on the ship"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)'),
  (19358, 'instance_run', 'server_choice',
   'Quest2 10132 "Expedition: The Gauntlet", objective text "Survive the trials of the Gauntlet"; the quest is an instance run, which the server has no event for yet, so the objective stays open (Quest2 questContentFinderTypeEnum is 3)');
