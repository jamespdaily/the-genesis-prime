-- Content table `game_number`: the numbers of a fight the server chooses, one row
-- each, loaded once at start into a persistent term (genesis_prime/content) and
-- never queried during play. It follows the pattern of `spawn` (0008) and
-- `creature_kind` (0009): `source`, `source_row` and `reason`, and the same checks.
--
-- A row is keyed by its name, the field of the record the load selects it into
-- (genesis_prime/world_map/game_number), and states its unit, which the load
-- checks against the name.
--
-- `creature_kind` gains the creature's own attack: the Spell4 it casts and how
-- often, in milliseconds.

create table game_number (
  name text primary key,
  value double precision not null,
  unit text not null,
  source text not null,
  source_row integer,
  reason text,
  constraint game_number_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint game_number_name_is_snake_case check (name ~ '^[a-z][a-z0-9_]*$'),
  constraint game_number_value_is_finite
    check (value not in ('NaN', 'Infinity', '-Infinity')),
  constraint game_number_unit_is_known
    check (unit in ('units', 'ms', 'threat', 'fraction')),
  constraint game_number_source_row_is_unique unique (source, source_row),
  constraint game_number_source_row_is_positive check (source_row > 0),
  constraint game_number_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint game_number_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint game_number_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into game_number (name, value, unit, source, reason) values
  ('aggro_range', 10, 'units', 'server_choice',
   'no client range (creature.ai_data); among the 27 Battle Beasts the median has 1 neighbour within 10; melee range is 6.5 to 8'),
  ('leash_range', 55, 'units', 'server_choice',
   'the radius of the objective circle (WorldLocation2 51739, 52898)'),
  ('aggro_threat', 1, 'threat', 'server_choice',
   'any threat above 0 shows the creature hostile (0x14045a950)'),
  ('chase_stop_fraction', 0.5, 'fraction', 'server_choice',
   'the creature stops at half its reach, so one step by the target keeps it in reach');

alter table creature_kind
  add column attack_spell4_id integer,
  add column attack_interval_ms integer;

update creature_kind
set
  attack_spell4_id = 5649,
  attack_interval_ms = 1500,
  reason = 'no table holds a respawn time for a creature (death.creature_respawn); attack: no client link (Spell4.5649), interval a server choice'
where creature_id = 0;

alter table creature_kind
  alter attack_spell4_id set not null,
  alter attack_interval_ms set not null,
  add constraint creature_kind_attack_spell4_id_is_positive
    check (attack_spell4_id > 0),
  add constraint creature_kind_attack_interval_ms_is_positive
    check (attack_interval_ms > 0);
