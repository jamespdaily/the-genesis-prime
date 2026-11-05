-- Content table `class_resource`: the numbers of each playable class's resource
-- the client lacks, one row each, loaded once at start into a persistent term
-- (genesis_prime/content) and never queried during play. It follows the pattern of
-- `game_number` (0010): `source`, `source_row` and `reason`, and the same checks.
--
-- A row is keyed by the class's Class id and the number's name, the field the load
-- selects it into (genesis_prime/game/class_resource), and states its unit, which
-- the load checks against the name. The slot each class's resource lives in and
-- whether it starts full or empty are the client's own, and stay in code.
--
-- The client holds no player's maximum and no refill rate
-- (`UnitProperty2.ResourceMax_0`), so each comes from a retail record or is the
-- server's choice, and says so.

create table class_resource (
  class_id integer not null,
  name text not null,
  value double precision not null,
  unit text not null,
  source text not null,
  source_row integer,
  reason text,
  constraint class_resource_pkey primary key (class_id, name),
  constraint class_resource_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint class_resource_class_id_is_in_5_bits
    check (class_id between 1 and 31),
  constraint class_resource_name_is_snake_case check (name ~ '^[a-z][a-z0-9_]*$'),
  constraint class_resource_value_is_finite
    check (value not in ('NaN', 'Infinity', '-Infinity')),
  constraint class_resource_unit_is_known check (unit in ('points', 'ms')),
  constraint class_resource_source_row_is_unique unique (source, source_row),
  constraint class_resource_source_row_is_positive check (source_row > 0),
  constraint class_resource_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint class_resource_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint class_resource_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into class_resource (class_id, name, value, unit, source, reason) values
  (1, 'max', 1000, 'points', 'retail_record',
   'Kinetic Energy: the client draws the Warrior bar in 3 sections to 1000, marks every 250 (ClassResources.lua); wildstaronline-archive Warrior page, Wayback 20210918201349'),
  (2, 'max', 100, 'points', 'retail_record',
   'Volatility: Tenton Hammer Engineer guide, "You can reach a maximum of 100 Volatility"'),
  (3, 'max', 5, 'points', 'server_choice',
   'Psi Points: the client draws 5 pips and Mind Burst''s tooltip lists 1PP to 5PP; it holds no maximum (UnitProperty2.ResourceMax_0)'),
  (4, 'max', 4, 'points', 'server_choice',
   'Actuators: the client draws 4 nodes; it holds no maximum (UnitProperty2.ResourceMax_0)'),
  (4, 'refill_after_combat_ms', 3000, 'ms', 'server_choice',
   'Jim''s choice at the step''s design: retail says only "quickly restore to a full four charges" out of combat (wildstaronline-archive Medic page, Wayback 20210918192013)'),
  (5, 'max', 100, 'points', 'retail_record',
   'Suit Power: gamegeex beta blog, Impale "cost 35 of out of the 100 energy your nano suit holds"'),
  (5, 'regen_amount', 7, 'points', 'retail_record',
   'psynister.wordpress.com/2014/07/24/wildstar-leveling-stalker-dps-1-25/: "By default, Suit Power restores at a rate of 7 SP per 1 second", in and out of combat'),
  (5, 'regen_period_ms', 1000, 'ms', 'retail_record',
   'the same record: 7 SP per 1 second'),
  (5, 'regen_tick_ms', 1000, 'ms', 'server_choice',
   'one tick a second; the client holds no regeneration of its own (regen.client)'),
  (7, 'max', 100, 'points', 'retail_record',
   'Spell Power: 4 circles (tentonhammer.com/guides/spellslinger-class-guide) of 25, an inference: every live Spell4 row of a Surge costs 25 of vital 19 (innateCostType0 or 1 = 19: 162 rows, gleam run -m genesis_prime/table_rows -- Spell4 innateCostType0=19)'),
  (7, 'regen_amount', 25, 'points', 'retail_record',
   'tentonhammer.com/guides/spellslinger-class-guide: "recharges at the same rate in or out of combat and takes around 12 seconds from empty to one full circle", a circle being 25'),
  (7, 'regen_period_ms', 12000, 'ms', 'retail_record',
   'the same record: around 12 seconds a circle'),
  (7, 'regen_tick_ms', 1000, 'ms', 'server_choice',
   'one tick a second; the client holds no regeneration of its own (regen.client)');
