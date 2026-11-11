-- The creatures of a named group an active quest's kill objective has had killed: one
-- 7-bit value for each of the quest's six objective slots (`kQuestMaxObjective`,
-- 0x1405510d0). The objective's reward pane is a TargetGroup whose data0 to data6 name up to
-- 7 creatures, the zero words skipped; bit i of a slot is set once the player's blow has
-- killed the i-th creature counted by position among the non-zero words.
-- The server keeps it and never sends it: the client is sent only the objective's
-- progress, which stays 0 until every creature of the group is dead
-- (genesis_prime/game/objective).
--
-- Like the rest of an active entry, an active row (state 1 or 2) holds the six values
-- and a row of any other state holds none (`character_quest_active_has_its_entry`).

alter table character_quest
  add column kill_mask smallint[];

update character_quest set kill_mask = '{0,0,0,0,0,0}' where state in (1, 2);

alter table character_quest
  add constraint character_quest_kill_mask_fits_7_bits
    check (0 <= all (kill_mask) and 127 >= all (kill_mask)),
  add constraint character_quest_active_has_its_kill_mask
    check ((state in (1, 2)) = (kill_mask is not null)),
  add constraint character_quest_kill_mask_has_six_slots
    check (kill_mask is null or cardinality(kill_mask) = 6);
