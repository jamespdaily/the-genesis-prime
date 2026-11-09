-- The quests a character has a record of, one row each: the quest log the client is
-- sent at every play (opcode.0x35f) and the two reset times that decide when a
-- periodic quest is offered again (genesis_prime/game/quest_log).
--
-- `state` is the quest's lua QuestState (1 to 7; 0 is "no row"): 1 and 2 are the
-- accepted and achieved states, which the client's active list holds, 3 is completed,
-- and the rest are the states its known list holds. A quest is in one list only
-- (opcode.0x35f.adds_not_replaces). An active row (state 1 or 2) holds the entry the
-- active list carries: the placeholder objective (0 for none), whether the quest is
-- tracked, the done mask, the progress of each objective and the time left of the
-- quest and of each objective, in milliseconds (0x1405fbdc0, 0x1406118a0,
-- quest_log.entry.flags); a row of any other state holds none of them. A completed
-- row holds the time it was completed, from which the login computes whether a
-- periodic quest was completed in its current period (0x1405fb350.completed_bit),
-- never stored.
--
-- The checks name what the client has: the quest id is the 15 bits the message
-- carries (opcode.0x35f); an active state is 1 or 2, for any other the client crashes
-- (opcode.0x35f.active_state_crash); a quest has at most six objectives (0x1405510d0,
-- kQuestMaxObjective), so six progress values and six done bits; each objective has
-- one timer.

create table character_quest (
  character_id bigint not null,
  quest_id integer not null,
  state smallint not null,
  completed_at timestamptz,
  placeholder_objective_id integer,
  tracked boolean,
  done_mask smallint,
  progress integer[],
  quest_ms_left integer,
  objective_ms_left integer[],
  constraint character_quest_pkey primary key (character_id, quest_id),
  constraint character_quest_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_quest_id_fits_15_bits check (quest_id between 1 and 32767),
  constraint character_quest_state_is_known check (state between 1 and 7),
  constraint character_quest_completed_has_a_time
    check ((state = 3) = (completed_at is not null)),
  constraint character_quest_active_has_its_entry check ((state in (1, 2)) = (
    placeholder_objective_id is not null and tracked is not null
    and done_mask is not null and progress is not null
    and quest_ms_left is not null and objective_ms_left is not null)),
  constraint character_quest_done_mask_fits_six_objectives
    check (done_mask between 0 and 63),
  constraint character_quest_progress_fits_six_objectives
    check (cardinality(progress) <= 6),
  constraint character_quest_progress_is_not_negative check (0 <= all (progress)),
  constraint character_quest_timers_match_progress
    check (cardinality(objective_ms_left) = cardinality(progress)),
  constraint character_quest_times_are_not_negative
    check (quest_ms_left >= 0 and 0 <= all (objective_ms_left)),
  constraint character_quest_placeholder_is_not_negative
    check (placeholder_objective_id >= 0)
);

-- The times of day the quests reset at, two server choices read at start into the
-- game_number record (genesis_prime/world_map/game_number). The client holds no
-- schedule (reset_schedule) and no retail record gives one: a daily quest resets
-- every day at 10:00 UTC, a weekly one every Tuesday at 10:00 UTC, which is the
-- project owner's decision of 2026-11-08. A monthly and a yearly quest reset at the
-- first daily reset of the month and of the year. `daily_quest_reset_ms` is the time
-- after 00:00 UTC, a whole number of milliseconds inside the day;
-- `weekly_quest_reset_ms` is the time after Monday 00:00 UTC, a whole number inside
-- the week.

insert into game_number_name (name, unit) values
  ('daily_quest_reset_ms', 'ms'),
  ('weekly_quest_reset_ms', 'ms');

alter table game_number
  add constraint game_number_daily_quest_reset_ms_is_a_whole_ms_inside_the_day
    check (name <> 'daily_quest_reset_ms'
      or (value >= 0 and value < 86400000 and value = trunc(value))),
  add constraint game_number_weekly_quest_reset_ms_is_a_whole_ms_inside_the_week
    check (name <> 'weekly_quest_reset_ms'
      or (value >= 0 and value < 604800000 and value = trunc(value)));

insert into game_number (name, value, unit, source, reason) values
  ('daily_quest_reset_ms', 36000000, 'ms', 'server_choice',
   'the client holds no reset schedule (reset_schedule) and no retail record was found: daily at 10:00 UTC, the project owner''s decision of 2026-11-08'),
  ('weekly_quest_reset_ms', 122400000, 'ms', 'server_choice',
   'the client holds no reset schedule (reset_schedule) and no retail record was found: weekly on Tuesday at 10:00 UTC, the project owner''s decision of 2026-11-08');
