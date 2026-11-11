-- The progress of a checklist objective is the 32-bit mask of the targets the character has
-- counted, the whole mask the client is sent (opcode.0x35f, opcode.0x361): its bit count is
-- the objective's progress and its bit 31 makes it a value up to 2^32 - 1, which `integer`
-- cannot hold. So each progress value is a bigint, of 0 to 4294967295.
--
-- The spawn table no longer holds the world data's quest checklist index: every target of one
-- objective must hold its own bit of the mask, and the world data gives the targets of 90
-- objectives the same index, so the load works each unit's index out from the client's tables
-- (genesis_prime/world_map/checklist_index).

alter table character_quest
  alter column progress type bigint[],
  drop constraint character_quest_progress_is_not_negative,
  add constraint character_quest_progress_fits_32_bits
    check (0 <= all (progress) and 4294967295 >= all (progress));

alter table spawn
  drop column quest_checklist_index;
