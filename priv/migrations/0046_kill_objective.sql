-- Content table `kill_objective`: the QuestObjective rows of type 5 (a scripted objective, done
-- only by the server's 0x361) whose text asks only to kill, loaded once at start into a
-- persistent term (genesis_prime/content) and never queried during play. It follows the pattern
-- of `arrival_objective` (0038): `source`, `source_row` and `reason`, and the same checks.
--
-- A visible, required scripted objective that no creature links is done in one of four ways
-- (genesis_prime/game/objective, `script_of`): a spell effect or an item names it, it is an
-- arrival row, it is a row here, or it is done when the quest is accepted. The client counts a
-- unit of the objective's reward pane TargetGroup for an objective of any type (0x140550c50),
-- so a row here is done by killing the pane's creatures, and they stand at its marker
-- (genesis_prime/world_map/objective_spawn). The client has no rule that says which of these
-- objectives only asks for a kill, so each row is the server's choice, read from the
-- objective's text, with the text in its reason. A row is only a kill (kill, slay, defeat,
-- destroy, run over): an objective whose text adds a condition the server does not check, or
-- whose marker is in a world with no stored spawn, or whose pane lists no creature that the
-- server starts as one a player can fight, stays done when the quest is accepted. The load
-- checks each row against the client's tables (genesis_prime/game/kill_objective).

create table kill_objective (
  objective_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint kill_objective_pkey primary key (objective_id),
  constraint kill_objective_id_is_positive check (objective_id > 0),
  constraint kill_objective_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint kill_objective_source_row_is_unique unique (source, source_row),
  constraint kill_objective_source_row_is_positive check (source_row > 0),
  constraint kill_objective_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint kill_objective_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint kill_objective_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into kill_objective (objective_id, source, reason) values
  (8010, 'server_choice',
   'Quest2 5444 "Explosive Mammodin", objective text "Kill poachers in the Bloodfire Savannah"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 7)'),
  (8281, 'server_choice',
   'Quest2 5535 "Road Kill", objective text "Run over Squirg Zombies in Genesis Installation"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 25)'),
  (8537, 'server_choice',
   'Quest2 5722 "Road Kill", objective text "Run over Squirg Zombies in Inception''s Hold"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 25)'),
  (8866, 'server_choice',
   'Quest2 5895 "Primal Powers and Triton''s Dread", objective text "Kill $(creature=26037) at Silverscale Station"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)'),
  (8867, 'server_choice',
   'Quest2 5896 "Primal Powers and Triton''s Dread", objective text "Kill $(creature=26037) at Silverscale Station"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)'),
  (9252, 'server_choice',
   'Quest2 6047 "The Root of Treachery", objective text "Defeat $(creature=33767) in Wildvine Sanctum"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)'),
  (14676, 'server_choice',
   'Quest2 6237 "The Sisters of Toria", objective text "Defeat $(creature=28256) at the Torine Hunting Grounds"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)'),
  (14681, 'server_choice',
   'Quest2 6242 "Wild Women of the Jungle", objective text "Defeat $(creature=28256) at the Torine Hunting Grounds"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)'),
  (15996, 'server_choice',
   'Quest2 3170 "Blood for Blood", objective text "Slay $(creature=9635) in Zonaga''s Lair and retrieve its head"; asks only to kill the creatures of its reward pane, which the kill of one of them shows (count 1)');
