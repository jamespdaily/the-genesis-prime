-- Content table `creature_faction`: the faction the server chooses for a creature in
-- place of the one its Creature2 row and the world database give, loaded once at
-- start into a persistent term (genesis_prime/content) and never queried during
-- play. It follows the pattern of `creature_kind` (0009): the same two columns for
-- where a row comes from, `source` and `source_row`, and the same checks, so a
-- server choice states its reason and a row of the world database names its source
-- row.
--
-- A row is keyed by the creature's Creature2 id. A creature with no row keeps the
-- faction of its own row. A started unit of a creature with a row stands with that
-- faction as both its faction and its base faction, so combat, the left-out rule,
-- the 0x262 and the kill credit read one value.
--
-- `faction_id` is 14 bits wide in message 0x262 (opcode.0x262).

create table creature_faction (
  creature_id integer primary key,
  faction_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint creature_faction_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint creature_faction_creature_id_is_in_18_bits
    check (creature_id between 0 and 262143),
  constraint creature_faction_faction_id_is_in_14_bits
    check (faction_id between 1 and 16383),
  constraint creature_faction_source_row_is_unique unique (source, source_row),
  constraint creature_faction_source_row_is_positive check (source_row > 0),
  constraint creature_faction_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint creature_faction_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint creature_faction_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

-- The tutorial boss, the Virtual Eldan Defense Construct (Creature2 73499, objectives
-- 21296 and 21310), takes faction 233 "Bot Aggressive". Its Creature2 row gives faction
-- 219, which is Friendly to both player factions, so neither side may attack it
-- (0x1403ad540). Faction2Relationship 746 makes 233 Hostile to faction 165, the parent
-- of both player factions (166 and 167), at level 0, and no row nearer in the walk
-- relates 233 to either.
insert into creature_faction (creature_id, faction_id, source, reason) values
  (73499, 233, 'server_choice',
   'the boss must be attackable by both player factions of the shared instance; Creature2.73499 gives faction 219, Friendly to both (0x1403ad540), and Faction2Relationship.746 makes 233 Hostile to 165, the parent of both');
