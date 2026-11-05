-- The rules the code assumes, held by the table that holds the rows.
--
-- A character's name is a full name by the client's text rule 0
-- (CheckTextRule 0x1403e1170, rule 0; genesis_prime/game/character_name): 5 to 30
-- characters, letters and exactly one space, the space neither first nor last,
-- where a letter is A to Z, a to z or one of the 53 Latin-1 and Latin Extended
-- letters the client lists (IsTextRuleLetter 0x1403e09d0). The check replaces
-- the first migration's 1 to 32 characters (0002), so the table is the one copy
-- of the rule, and the store maps its refusal to the client's name-length
-- result. `char_length` counts characters, as the client's bound does.
alter table character
  drop constraint character_name_shown_by_the_client,
  add constraint character_name_follows_rule_0 check (
    char_length(name) between 5 and 30
    and name ~ '^[A-Za-zÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ]+ [A-Za-zÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ]+$'
  );

-- The seed rows of `class_resource` and `game_number` are checked one row at a
-- time by the table, so a bad row fails the migration that inserts it instead of
-- committing and stopping the next start. A number a class's resource takes is
-- above 0, a time is a whole number of milliseconds, and each name has the one
-- unit the server reads it in. A name the server does not read passes the unit
-- check; the load refuses it by name, with the rows it has to see together.
alter table class_resource
  add constraint class_resource_value_is_positive check (value > 0),
  add constraint class_resource_time_is_whole_ms
    check (unit <> 'ms' or value = trunc(value)),
  add constraint class_resource_name_has_its_unit check (
    unit = case name
      when 'max' then 'points'
      when 'regen_amount' then 'points'
      when 'drain_amount' then 'points'
      when 'regen_period_ms' then 'ms'
      when 'regen_tick_ms' then 'ms'
      when 'refill_after_combat_ms' then 'ms'
      when 'drain_period_ms' then 'ms'
      when 'drain_tick_ms' then 'ms'
      when 'drain_after_ms' then 'ms'
      when 'empty_after_combat_ms' then 'ms'
      else unit
    end
  );

alter table game_number
  add constraint game_number_name_has_its_unit check (
    unit = case name
      when 'aggro_range' then 'units'
      when 'leash_range' then 'units'
      when 'aggro_threat' then 'threat'
      when 'chase_stop_fraction' then 'fraction'
      else unit
    end
  );

-- Constraints the schema names, so the code can map each by a name that does
-- not change with Postgres's rule for a default.
alter table account
  rename constraint account_login_name_key to account_login_name_is_unique;
alter table account
  rename constraint account_game_account_id_key
    to account_game_account_id_is_unique;
alter table account
  rename constraint account_login_name_check to account_login_name_is_not_empty;
alter table account
  rename constraint account_srp_salt_check to account_srp_salt_is_not_empty;
alter table account
  rename constraint account_srp_verifier_check
    to account_srp_verifier_is_not_empty;
alter table character
  rename constraint character_session_epoch_check
    to character_session_epoch_is_not_negative;
alter table character
  rename constraint character_account_id_fkey to character_account_is_an_account;
alter table spawn_stat
  rename constraint spawn_stat_spawn_id_fkey to spawn_stat_spawn_is_a_spawn;
