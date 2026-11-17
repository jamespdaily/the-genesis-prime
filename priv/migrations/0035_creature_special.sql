-- Content table `creature_special`: the spells a kind of creature casts besides its attack,
-- loaded once at start (genesis_prime/content) with the `creature_kind` rows and never
-- queried during play. It follows the pattern of `creature_kind` (0009): `source`,
-- `source_row` and `reason`, and the same checks.
--
-- A row is one spell of one creature, keyed by the creature's Creature2 id and the Spell4.
-- `order_index` is the place in the creature's list: the creature casts the first listed
-- special that is ready, else its attack. `cooldown_ms` is the time in milliseconds from
-- a cast's start until the creature may cast the spell again.
--
-- The client names no spell for a creature and no cadence, so each row is a retail record
-- of the creature's abilities, and its cooldown a server choice marked as a guess in
-- `reason`. The load checks each row against the client's tables
-- (genesis_prime/world_map/creature_special).

create table creature_special (
  creature_id integer not null,
  spell4_id integer not null,
  order_index smallint not null,
  cooldown_ms integer not null,
  source text not null,
  source_row integer,
  reason text not null,
  constraint creature_special_pkey primary key (creature_id, spell4_id),
  constraint creature_special_order_index_is_unique
    unique (creature_id, order_index),
  constraint creature_special_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint creature_special_creature_id_is_in_18_bits
    check (creature_id between 1 and 262143),
  constraint creature_special_spell4_id_is_positive check (spell4_id > 0),
  constraint creature_special_order_index_is_not_negative
    check (order_index >= 0),
  constraint creature_special_cooldown_ms_is_positive check (cooldown_ms > 0),
  constraint creature_special_source_row_is_positive check (source_row > 0),
  constraint creature_special_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint creature_special_reason_says_something
    check (length(trim(reason)) > 0)
);

insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason)
select creature_id, 55317, 0, 10000, 'retail_record',
  'Jabbithole npc page /npcs/rootbrute-grimspore-1 (captured 20170916002802), Abilities tab, Earthen Roar tier 2 (Spell4 55317); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'
from unnest(array[12212, 13118, 13549]) as creature (creature_id);

insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason)
select creature_id, 55296, 0, 10000, 'retail_record',
  'Jabbithole npc pages /npcs/mysthoof-trampler-27 (captured 20170917060736) and /npcs/mysthoof-doe-27 (captured 20170917061151), Abilities tab, Crash tier 2 (Spell4 55296); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'
from unnest(array[27687, 28623]) as creature (creature_id);

insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason) values
  (24057, 55327, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/venombite-spider-12 (captured 20150416142809), Abilities tab, Venomous Mandible tier 2 (Spell4 55327); the cooldown of 10000 ms is a guess: the client holds no cadence for a special'),
  (25979, 55330, 0, 10000, 'retail_record',
   'Jabbithole npc page /npcs/saltwater-snoglug-22 (captured 20170914034737), Abilities tab, Slime Spray tier 2 (Spell4 55330); the cooldown of 10000 ms is a guess: the client holds no cadence for a special');
