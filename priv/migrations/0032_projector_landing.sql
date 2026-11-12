-- Content table `projector_landing`: where each of the training simulation's four
-- projectors puts a player, loaded once at start into a persistent term
-- (genesis_prime/content) and never queried during play. It follows the pattern of
-- `tutorial_quest` (0031): `source`, `source_row` and `reason`, and the same checks.
--
-- A row says "a player of faction `faction_enum` (0 Exile, 1 Dominion) who uses Creature2
-- `creature_id` is put at WorldLocation2 `world_location2_id`", and names the
-- QuestObjective `objective_id` that asks for the use, so the load can check the pair.
-- The client names the projector's destination only through that objective (its text
-- and its marker); no client column ties a projector to a place, so the landing is the
-- server's choice (genesis_prime/game/projector checks each row at load: the creature
-- casts the projector spell, the landing is in World 3460, the objective is the
-- creature's use or a zone the landing lies in, and the objective's quest is the
-- faction's).

create table projector_landing (
  creature_id integer not null,
  faction_enum integer not null,
  objective_id integer not null,
  world_location2_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint projector_landing_pkey primary key (creature_id, faction_enum),
  constraint projector_landing_objective_is_unique unique (objective_id),
  constraint projector_landing_faction_is_exile_or_dominion
    check (faction_enum in (0, 1)),
  constraint projector_landing_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint projector_landing_ids_are_positive
    check (creature_id > 0 and objective_id > 0 and world_location2_id > 0),
  constraint projector_landing_source_row_is_unique unique (source, source_row),
  constraint projector_landing_source_row_is_positive check (source_row > 0),
  constraint projector_landing_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint projector_landing_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint projector_landing_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into projector_landing
  (creature_id, faction_enum, objective_id, world_location2_id, source, reason) values
  (73735, 0, 21325, 51615, 'server_choice',
   'Combat Projector, Exile: objective 21325 (type 12, use) of quest 10527 "continue to the Combat Simulation", which is Warfare Woods (zone 5967), where the fight circle 51739 lies; WorldLocation2 51615 is a place in zone 5967; no client column ties the projector to a place'),
  (73735, 1, 21356, 51615, 'server_choice',
   'Combat Projector, Dominion: objective 21356 (type 12, use) of quest 10532, the same text and place as 21325'),
  (73741, 0, 21344, 51617, 'server_choice',
   'Housing Projector, Exile: objective 21344 (type 17, zone 4965) of quest 10525 "continue to the Protostar Model Skyplot", whose only child zone is 5969; WorldLocation2 51617 is a place in zone 5969; no client column ties the projector to a place'),
  (73741, 1, 21377, 51617, 'server_choice',
   'Housing Projector, Dominion: objective 21377 (type 17, zone 4965) of quest 10526, the same zone and place as 21344'),
  (73743, 0, 21373, 51616, 'server_choice',
   'Mission Projector, Exile: objective 21373 (type 17, zone 4964) of quest 10540 "continue to the Mission Simulation", whose only child zone is 5968; WorldLocation2 51616 is a place in zone 5968; no client column ties the projector to a place'),
  (73743, 1, 21376, 51616, 'server_choice',
   'Mission Projector, Dominion: objective 21376 (type 17, zone 4964) of quest 10541, the same zone and place as 21373'),
  (73745, 0, 21298, 51658, 'server_choice',
   'Cryo Projector, Exile: objective 21298 (type 17, zone 5998) of quest 10520 "end the simulation and wake from cryosleep", the Exile Arkship Docking Bay; WorldLocation2 51658 is a place in zone 5998; no client column ties the projector to a place'),
  (73745, 1, 21311, 51657, 'server_choice',
   'Cryo Projector, Dominion: objective 21311 (type 17, zone 5999) of quest 10523, the Dominion Arkship Docking Bay; WorldLocation2 51657 is a place in zone 5999; no client column ties the projector to a place');
