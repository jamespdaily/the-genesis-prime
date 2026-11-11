-- Saves where a character stands: its world, zone, position and facing, and the
-- health, experience and level it has, and its quest log, in one statement, so
-- they are saved together or not at all; the experience is $15 and the level it
-- makes $16. The health is $13 when $14 is true, and NULL (nothing saved: the
-- next entry is alive at full health) when it is false, since
-- squirrel cannot type a parameter that may be NULL. A dead player saves 0,
-- which its next entry is dead at. It writes only
-- while the character is still held by the login that made the save, that is
-- while its `session_epoch` is still the one that login raised it to
-- (load_character.sql), and only when the save is newer than the last one stored
-- for that login: `save_sequence` ($12) is above the stored one. A login that
-- came after raised the epoch, so a save from an older login matches no row and
-- changes nothing; a save of this login that comes after a newer one of its own
-- matches none either. The account's id is in the statement, as for a load. No
-- row means the epoch moved on, a newer save was stored first, or the account
-- has no such character.
--
-- The quest log is $17, a JSON array with one object for each quest the character
-- has a record of, whose keys are the columns of `character_quest` (a completed
-- time in whole Unix seconds): it is unpacked here so that squirrel needs no array
-- of arrays. The log is the whole log, so a row the character no longer has is
-- deleted and a row that changed is written, both only through the row the fence
-- above matched, so a save the fence refuses writes no quest row either. A row
-- that did not change is not written. The statement runs after
-- lock_character_for_save.sql in one transaction: a statement takes its snapshot
-- before it waits for a row another save holds, so without the lock a save that
-- waited would delete or keep quest rows by the log the earlier save had not yet
-- written, and leave a quest the later log dropped.
with saved as (
  update character
  set
    world_id = $4,
    world_zone_id = $5,
    position_x = $6,
    position_y = $7,
    position_z = $8,
    rotation_yaw = $9,
    rotation_pitch = $10,
    rotation_roll = $11,
    save_sequence = $12,
    health = case when $14 then $13::int end,
    experience = $15::int,
    level = $16::int
  where character_id = $1 and account_id = $2 and session_epoch = $3
    and save_sequence < $12
  returning character_id
),
incoming as (
  select *
  from jsonb_to_recordset($17::jsonb) as quest(
    quest_id integer,
    state smallint,
    completed_at bigint,
    placeholder_objective_id integer,
    tracked boolean,
    done_mask smallint,
    progress bigint[],
    quest_ms_left integer,
    objective_ms_left integer[]
  )
),
gone as (
  delete from character_quest as held
  using saved
  where held.character_id = saved.character_id
    and not exists (
      select 1 from incoming where incoming.quest_id = held.quest_id
    )
),
put as (
  insert into character_quest (
    character_id,
    quest_id,
    state,
    completed_at,
    placeholder_objective_id,
    tracked,
    done_mask,
    progress,
    quest_ms_left,
    objective_ms_left
  )
  select
    saved.character_id,
    incoming.quest_id,
    incoming.state,
    to_timestamp(incoming.completed_at),
    incoming.placeholder_objective_id,
    incoming.tracked,
    incoming.done_mask,
    incoming.progress,
    incoming.quest_ms_left,
    incoming.objective_ms_left
  from saved
  cross join incoming
  on conflict (character_id, quest_id) do update
  set
    state = excluded.state,
    completed_at = excluded.completed_at,
    placeholder_objective_id = excluded.placeholder_objective_id,
    tracked = excluded.tracked,
    done_mask = excluded.done_mask,
    progress = excluded.progress,
    quest_ms_left = excluded.quest_ms_left,
    objective_ms_left = excluded.objective_ms_left
  where (
    character_quest.state,
    character_quest.completed_at,
    character_quest.placeholder_objective_id,
    character_quest.tracked,
    character_quest.done_mask,
    character_quest.progress,
    character_quest.quest_ms_left,
    character_quest.objective_ms_left
  ) is distinct from (
    excluded.state,
    excluded.completed_at,
    excluded.placeholder_objective_id,
    excluded.tracked,
    excluded.done_mask,
    excluded.progress,
    excluded.quest_ms_left,
    excluded.objective_ms_left
  )
)
select character_id from saved;
