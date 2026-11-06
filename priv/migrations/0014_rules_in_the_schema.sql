-- The rules the code assumes, held by the table that holds the rows.
--
-- The name check below counts characters and matches letters as UTF-8 text, so
-- the migration refuses a database of another encoding.
do $$ begin if current_setting('server_encoding') <> 'UTF8' then raise exception 'migration 0014 needs a UTF8 database, not %', current_setting('server_encoding'); end if; end $$;

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
-- above 0 and a time is a whole number of milliseconds. Each name the server
-- reads is listed once in a reference table of its own with its one unit, and a
-- row's name and unit are a composite foreign key to it, so a row with another
-- unit, or with a name nobody listed, is refused by the same constraint. A new
-- name is one insert into the reference table.
create table class_resource_name (
  name text primary key,
  unit text not null,
  constraint class_resource_name_has_one_unit unique (name, unit)
);

insert into class_resource_name (name, unit) values
  ('max', 'points'),
  ('regen_amount', 'points'),
  ('regen_period_ms', 'ms'),
  ('regen_tick_ms', 'ms'),
  ('refill_after_combat_ms', 'ms'),
  ('drain_amount', 'points'),
  ('drain_period_ms', 'ms'),
  ('drain_tick_ms', 'ms'),
  ('drain_after_ms', 'ms'),
  ('empty_after_combat_ms', 'ms');

alter table class_resource
  add constraint class_resource_value_is_positive check (value > 0),
  add constraint class_resource_time_is_whole_ms
    check (unit <> 'ms' or value = trunc(value)),
  add constraint class_resource_name_has_its_unit
    foreign key (name, unit) references class_resource_name (name, unit);

create table game_number_name (
  name text primary key,
  unit text not null,
  constraint game_number_name_has_one_unit unique (name, unit)
);

insert into game_number_name (name, unit) values
  ('aggro_range', 'units'),
  ('leash_range', 'units'),
  ('aggro_threat', 'threat'),
  ('chase_stop_fraction', 'fraction');

-- A threat above 0 shows a creature hostile (0x14045a950), and a chase stops
-- strictly inside the creature's reach: each rule is scoped to its name.
alter table game_number
  add constraint game_number_name_has_its_unit
    foreign key (name, unit) references game_number_name (name, unit),
  add constraint game_number_aggro_threat_is_positive
    check (name <> 'aggro_threat' or value > 0),
  add constraint game_number_chase_stop_fraction_is_between_0_and_1
    check (name <> 'chase_stop_fraction' or (value > 0 and value < 1));

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
