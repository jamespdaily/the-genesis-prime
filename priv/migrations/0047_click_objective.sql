-- Content table `click_objective`: the QuestObjective rows of type 5 (a scripted objective, done
-- only by the server's 0x361) whose text asks only to click a creature, loaded once at start into
-- a persistent term (genesis_prime/content) and never queried during play. It follows the pattern
-- of `kill_objective` (0046): `source`, `source_row` and `reason`, and the same checks.
--
-- A visible, required scripted objective that no creature links is done in one of five ways
-- (genesis_prime/game/objective, `script_of`): a spell effect or an item names it, it is an
-- arrival row, it is a kill row, it is a row here, or it is done when the quest is accepted. The
-- client counts a unit of the objective's reward pane TargetGroup for an objective of any type
-- (0x140550c50), so a row here is done by activating a pane creature with its own activate spell,
-- and the creature stands at its marker (genesis_prime/world_map/objective_spawn). The client has
-- no rule that says which of these objectives only asks for a click, so each row is the server's
-- choice, read from the objective's text, with the text in its reason. A row is only a click on a
-- creature the client offers a click on (an activate spell for the player, no path lock, no
-- datacube, genesis_prime/shared/activate `offers_click`) that is not hostile to a player faction its
-- quest allows, whose spell the server builds, that starts in the world of its marker (a world with a
-- stored spawn, and a creature Friendly to both player factions with no quest or link does not start,
-- genesis_prime/world_map/spawn `left_out_of`): any other objective stays done when the quest is
-- accepted. The load checks each row against the client's tables
-- (genesis_prime/game/click_objective).

create table click_objective (
  objective_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint click_objective_pkey primary key (objective_id),
  constraint click_objective_id_is_positive check (objective_id > 0),
  constraint click_objective_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint click_objective_source_row_is_unique unique (source, source_row),
  constraint click_objective_source_row_is_positive check (source_row > 0),
  constraint click_objective_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint click_objective_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint click_objective_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into click_objective (objective_id, source, reason) values
  (7652, 'server_choice',
   'Quest2 5263 "The Emissary", objective text "Speak with the $(creature=21658) hiding near the Chronicle House"; asks only to click the creature of its reward pane (Creature2 21688, activate spell 40565), which the activation of it shows (count 1)'),
  (7653, 'server_choice',
   'Quest2 5263 "The Emissary", objective text "Speak with the $(creature=21658) hiding near Locus Dawn"; asks only to click the creature of its reward pane (Creature2 27100, activate spell 40565), which the activation of it shows (count 1)'),
  (7654, 'server_choice',
   'Quest2 5263 "The Emissary", objective text "Speak with the $(creature=21658) hiding near Snowfade Grounds"; asks only to click the creature of its reward pane (Creature2 27101, activate spell 40565), which the activation of it shows (count 1)'),
  (9002, 'server_choice',
   'Quest2 5918 "Eldan Decryption", objective text "Observe the $p(creature=26436) behavior in Leviathan''s Rest"; asks only to click the creature of its reward pane (Creature2 26436, activate spell 1817), which the activation of it shows (count 1)'),
  (16170, 'server_choice',
   'Quest2 6591 "The Face of Justice", objective text "Confront $(creature=30256) about poisoning the Stormseekers in the Larallen Highlands"; asks only to click the creature of its reward pane (Creature2 51440, activate spell 1817), which the activation of it shows (count 1)');
