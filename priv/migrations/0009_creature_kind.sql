-- Content table `creature_kind`: what the server chooses for a kind of creature,
-- loaded once at start into a persistent term (genesis_prime/content) and never
-- queried during play. It follows the pattern of `spawn` (0008): the same two
-- columns for where a row comes from, `source` and `source_row`, and the same two
-- checks, so a server choice states its reason and a row of the world database
-- names its source row.
--
-- A row is keyed by the creature's Creature2 id. Row 0 is the default every
-- creature without a row of its own takes, so a creature has a kind whatever its
-- id, and a table with no row 0 stops the start.
--
-- `respawn_ms` is how long a creature that died stays dead before it stands at its
-- spawn again, and how long a spawn whose creature crashed waits for its next one.
-- Later steps add the columns of the creature's own attack to this table.

create table creature_kind (
  creature_id integer primary key,
  respawn_ms integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint creature_kind_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint creature_kind_creature_id_is_in_18_bits
    check (creature_id between 0 and 262143),
  constraint creature_kind_respawn_ms_is_positive check (respawn_ms > 0),
  constraint creature_kind_source_row_is_positive check (source_row > 0),
  constraint creature_kind_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint creature_kind_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint creature_kind_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

-- The default: 60 seconds, a server choice. The client holds no respawn time for a
-- creature: no table column names one, and a creature comes back only as the
-- server sends it (`death.creature_respawn`).
insert into creature_kind (creature_id, respawn_ms, source, reason) values
  (0, 60000, 'server_choice',
   'no table holds a respawn time for a creature (death.creature_respawn)');
