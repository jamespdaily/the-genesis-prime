-- Content table `tutorial_quest`: the training simulation's quests that no creature gives,
-- and the quest each follows, loaded once at start into a persistent term
-- (genesis_prime/content) and never queried during play. It follows the pattern of
-- `zone_welcome` (0020): `source`, `source_row` and `reason`, and the same checks.
--
-- A row says "the server gives Quest2 `quest_id` to a character of its faction once the
-- character has completed Quest2 `follows_quest_id`" (none: when the character enters
-- World 3460). The client starts none of them: no giver, no receiver, no communicator
-- row delivers them, and Quest2 has no next-quest column, so the server adds each with
-- a quest state message (genesis_prime/game/tutorial). The order is the server's choice,
-- read from the objectives' text: Quest2 rows 10527 and 10532 go on to the jump, the
-- hoverboard and the Combat Projector's "continue to the Combat Simulation", 10518 and
-- 10524 are the fights, and 10529 and 10533 end by sending the player to the creature
-- that gives the quest after the fights (the load checks each row's Quest2 row, that no
-- creature gives or receives it, and that each faction's rows make one chain,
-- genesis_prime/game/tutorial).

create table tutorial_quest (
  quest_id integer not null,
  follows_quest_id integer,
  source text not null,
  source_row integer,
  reason text,
  constraint tutorial_quest_pkey primary key (quest_id),
  constraint tutorial_quest_follows_a_tutorial_quest
    foreign key (follows_quest_id) references tutorial_quest (quest_id),
  constraint tutorial_quest_is_followed_once unique (follows_quest_id),
  constraint tutorial_quest_does_not_follow_itself
    check (follows_quest_id is distinct from quest_id),
  constraint tutorial_quest_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint tutorial_quest_ids_are_positive
    check (quest_id > 0 and follows_quest_id > 0),
  constraint tutorial_quest_source_row_is_unique unique (source, source_row),
  constraint tutorial_quest_source_row_is_positive check (source_row > 0),
  constraint tutorial_quest_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint tutorial_quest_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint tutorial_quest_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into tutorial_quest (quest_id, follows_quest_id, source, reason) values
  (10513, null, 'server_choice',
   'Exile "Navigating Nexus" part 1 (questPlayerFactionEnum 0): the first quest of the simulation, begun at the entry to World 3460 (Rider''s Reef, its circles are the objectives); no creature gives it'),
  (10521, null, 'server_choice',
   'Dominion "Navigating Nexus" part 1 (questPlayerFactionEnum 1): the same objectives as 10513; no creature gives it'),
  (10527, 10513, 'server_choice',
   'Exile "Navigating Nexus" part 2: the objectives go on from the circles to the jump, the hoverboard run and the Combat Projector; no table links it to 10513'),
  (10532, 10521, 'server_choice',
   'Dominion "Navigating Nexus" part 2: the same objectives as 10527; no table links it to 10521'),
  (10518, 10527, 'server_choice',
   'Exile "The Face of the Enemy": the first fight, after the Combat Projector''s "continue to the Combat Simulation" that ends 10527; no prerequisite column of 10518 names 10527'),
  (10524, 10532, 'server_choice',
   'Dominion "The Face of the Enemy": the first fight, after the Combat Projector that ends 10532; no prerequisite column of 10524 names 10532'),
  (10529, 10518, 'server_choice',
   'Exile "The Face of the Enemy" objective "Accept the Quest from Dorian Walker to continue the simulation": Creature2 73491 gives 10525, which needs 10518, so it follows 10518'),
  (10533, 10524, 'server_choice',
   'Dominion "The Face of the Enemy" objective to talk to Artemis Zin (Creature2 74861) to continue the simulation: it follows 10524');
