-- The objects an active quest's objectives have counted, so that an object the player used
-- counts once for an objective and a relog does not let it count again. Two arrays of one
-- length, read together: entry i says the objective at index `used_objective[i]` of the quest
-- has counted the spawn `used_spawn[i]`, the id of the spawn table's row of the object or
-- creature. A row of any state but 1 and 2 holds none. The server writes the entries in
-- objective then spawn order and none for an objective that is done.
--
-- The arrays name no foreign key: an array holds none. A spawn the world no longer has is
-- left to the server's load, which drops its entry.

alter table character_quest
  add column used_objective smallint[] not null default '{}',
  add column used_spawn integer[] not null default '{}';

alter table character_quest
  add constraint character_quest_used_match
    check (cardinality(used_objective) = cardinality(used_spawn)),
  add constraint character_quest_used_objective_in_six
    check (0 <= all (used_objective) and 5 >= all (used_objective)),
  add constraint character_quest_used_spawn_is_positive
    check (1 <= all (used_spawn)),
  add constraint character_quest_used_only_when_active
    check (state in (1, 2) or cardinality(used_objective) = 0);
