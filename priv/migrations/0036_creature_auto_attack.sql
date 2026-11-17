-- Content table `creature_auto_attack`: the auto-attacks a kind of creature strikes with in
-- turn, loaded once at start (genesis_prime/content) with the `creature_kind` and
-- `creature_special` rows and never queried during play. It follows the pattern of
-- `creature_special` (0035): `source`, `source_row` and `reason`, and the same checks.
--
-- A row is one auto-attack of one creature, keyed by the creature's Creature2 id and the
-- Spell4. `order_index` is the place in the creature's turn: the creature strikes the
-- first listed auto-attack first, then each next one, then the first again. A creature
-- with no row here strikes with the attack of its `creature_kind` (the default kind's
-- Spell4 5649 unless it has a row of its own); a creature with rows here and a
-- `creature_kind` row of its own is refused by the load, so one place names its attack.
--
-- The client's Spell4 descriptions mark a creature's auto-attacks (`[AUTO-ATTACK]`,
-- "Auto-Attack #1", "#2") but no client table links a creature to a spell, so each row is
-- a retail record of the creature's abilities, and the order of several auto-attacks a
-- server choice marked as a guess in `reason`. The load checks each row against the
-- client's tables (genesis_prime/world_map/creature_auto_attack).

create table creature_auto_attack (
  creature_id integer not null,
  spell4_id integer not null,
  order_index smallint not null,
  source text not null,
  source_row integer,
  reason text not null,
  constraint creature_auto_attack_pkey primary key (creature_id, spell4_id),
  constraint creature_auto_attack_order_index_is_unique
    unique (creature_id, order_index),
  constraint creature_auto_attack_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint creature_auto_attack_creature_id_is_in_18_bits
    check (creature_id between 1 and 262143),
  constraint creature_auto_attack_spell4_id_is_positive check (spell4_id > 0),
  constraint creature_auto_attack_order_index_is_not_negative
    check (order_index >= 0),
  constraint creature_auto_attack_source_row_is_positive check (source_row > 0),
  constraint creature_auto_attack_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint creature_auto_attack_reason_says_something
    check (length(trim(reason)) > 0)
);

-- Each row below: the creature's own Jabbithole page lists the pair in its Abilities tab at
-- tier 0 and the client's Spell4 descriptions number them "Auto-Attack #1" and "#2"; the
-- order is #1 then #2, a guess: no client table holds the order a creature strikes in.

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select creature_id, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/yeti-snowstalker-1 (captured 20150416221041), Abilities tab, Maul (Spell4 33251) and Slam (33252) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from unnest(array[51126, 11945]) as creature (creature_id),
  (values (33251, 0), (33252, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select 11910, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/skeech-scratcher-1 (captured 20170902053341), Abilities tab, Punch (Spell4 5649) and Jab (5652) listed at tier 0; Spell4 descriptions "Auto Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from (values (5649, 0), (5652, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select 24058, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/bloodstone-oxian-12 (captured 20150416103144), Abilities tab, Ram (Spell4 32761) and Bash (32762) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from (values (32761, 0), (32762, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select 24054, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/scrab-striker-12 (captured 20170915173026), Abilities tab, Pinch (Spell4 25870) and Snap (25871) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from (values (25870, 0), (25871, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select 26026, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/malverine-stalker-22 (captured 20160718025408), Abilities tab, Swipe (Spell4 6616) and Claw (6617) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from (values (6616, 0), (6617, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select creature_id, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/rootbrute-grimspore-1 (captured 20170916002802), Abilities tab, Swipe (Spell4 33247) and Swing (33248) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from unnest(array[12212, 13118, 13549]) as creature (creature_id),
  (values (33247, 0), (33248, 1)) as attack (spell4_id, order_index);

insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select 36173, spell4_id, order_index, 'retail_record',
  'Jabbithole npc page /npcs/elderoot-deathcap-27 (captured 20170917055401), Abilities tab, Swipe (Spell4 33247) and Swing (33248) listed at tier 0; Spell4 descriptions "Auto-Attack #1" and "#2"; the order #1 then #2 is a guess: the client holds no strike order'
from (values (33247, 0), (33248, 1)) as attack (spell4_id, order_index);
