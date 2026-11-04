-- Content tables: data the server owns, which it loads once at start into
-- persistent terms (genesis_prime/content) and never queries during play, and
-- the first of them, `spawn`: every place a unit stands in a world.
--
-- Every content table has the same two columns for where a row comes from,
-- `source` (the content_source table) and `source_row` (the row's id in its
-- source file), and the same two checks: a row of the world database names its
-- row in the file, and any other row states its reason. So a server choice says
-- why, and a retail record names the record it came from.
--
-- `spawn` keeps every row of the world database's spawn.tsv, whatever the unit
-- (the selection of which ones start runs at load, so a change to it needs no
-- import), and the Virtual Defense Daguns of the Novice training simulation as
-- server choices: the world database has no record of them.
--
-- Every number that is a 32-bit float in message 0x262 is a `real` here, and
-- refuses NaN and the infinities as `character` does for its place (0007).
-- Each bound is the width of the field in message 0x262 (creature_id 18 bits,
-- display 17, outfit 15, world socket 14, checklist index 8, faction 14).
-- Values seen in the file: stat ids 0 to 22, `active_prop_id` up to 6.0e13
-- (so `bigint`), some stat values with fractions.
--
-- `content_source` is a table, not a type, so a new source is one insert in the
-- migration that needs it, and every content table refers to it.
create table content_source (name text primary key);
insert into content_source (name) values
  ('world_database'), ('retail_record'), ('server_choice'), ('game_master');

create table spawn (
  id integer primary key generated always as identity,
  source text not null,
  source_row integer,
  reason text,
  -- Message 0x262's unit type, 6 bits; 37 and above fail the client's read
  -- (opcode.0x262, world_data.entity_type).
  entity_type smallint not null,
  creature_id integer not null,
  world_id integer not null,
  -- 0 in 435 rows of the world database; the 0x262 sends no zone.
  area_id integer not null,
  x real not null,
  y real not null,
  z real not null,
  rotation_x real not null,
  rotation_y real not null,
  rotation_z real not null,
  display_info_id integer not null,
  outfit_info_id integer not null,
  -- The unit's faction and its base faction, 14 bits each (opcode.0x262).
  faction_id integer not null,
  base_faction_id integer not null,
  quest_checklist_index integer not null,
  active_prop_id bigint not null,
  world_socket_id integer not null,
  constraint spawn_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint spawn_id_is_positive check (id > 0),
  constraint spawn_source_row_is_unique unique (source_row),
  constraint spawn_source_row_is_positive check (source_row > 0),
  constraint spawn_entity_type_is_a_unit_type
    check (entity_type between 0 and 36),
  constraint spawn_creature_id_is_in_18_bits
    check (creature_id between 1 and 262143),
  constraint spawn_world_id_is_positive check (world_id > 0),
  constraint spawn_area_id_is_not_negative check (area_id >= 0),
  constraint spawn_position_is_finite
    check (
      x between -3.4028235e38 and 3.4028235e38
      and y between -3.4028235e38 and 3.4028235e38
      and z between -3.4028235e38 and 3.4028235e38
    ),
  constraint spawn_rotation_is_finite
    check (
      rotation_x between -3.4028235e38 and 3.4028235e38
      and rotation_y between -3.4028235e38 and 3.4028235e38
      and rotation_z between -3.4028235e38 and 3.4028235e38
    ),
  constraint spawn_display_info_id_is_in_17_bits
    check (display_info_id between 1 and 131071),
  constraint spawn_outfit_info_id_is_in_15_bits
    check (outfit_info_id between 0 and 32767),
  constraint spawn_quest_checklist_index_is_in_8_bits
    check (quest_checklist_index between 0 and 255),
  constraint spawn_active_prop_id_is_not_negative check (active_prop_id >= 0),
  constraint spawn_world_socket_id_is_in_14_bits
    check (world_socket_id between 0 and 16383),
  constraint spawn_faction_id_is_14_bits
    check (faction_id between 0 and 16383),
  constraint spawn_base_faction_id_is_14_bits
    check (base_faction_id between 0 and 16383),
  constraint spawn_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint spawn_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint spawn_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

-- The stats the world database recorded for a spawn, by their client index
-- (5 bits, opcode.0x262). Only health (0) and level (10) are read.
create table spawn_stat (
  spawn_id integer not null references spawn (id) on delete cascade,
  stat smallint not null,
  value real not null,
  primary key (spawn_id, stat),
  constraint spawn_stat_is_a_stat_index check (stat between 0 and 31),
  constraint spawn_stat_value_is_finite
    check (value between -3.4028235e38 and 3.4028235e38)
);

-- Each import of a world-database file: its name, the SHA-256 of its bytes
-- (lower-case hex), its row count and when. The setup check compares each file
-- listed here with the same file in GENESIS_WORLD_DATA.
create table content_import (
  file text primary key,
  sha256 text not null,
  rows integer not null,
  imported_at timestamptz not null,
  constraint content_import_sha256_is_lower_case_hex
    check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint content_import_rows_is_not_negative check (rows >= 0)
);

-- The 27 Virtual Defense Daguns (Creature2 73465) of the Dominion fight in
-- Warfare Woods (Quest2.10524): no record of them exists anywhere, so each
-- stands at the offset of one Virtual Battle Beast's point (rows 29113 to 29139
-- of spawn.tsv) from the centre of the Exile objective circle (WorldLocation2
-- 51739), applied to the centre of the Dominion one (WorldLocation2 52898),
-- facing as that row does. Display 26578 is the one entry of the Dagun's display
-- group (Creature2DisplayGroupEntry 27216), faction 1442 is Creature2.factionId,
-- and the rows hold no stats, so the load gives them the creature's own level
-- and health.
insert into spawn (
  source, reason, entity_type, creature_id, world_id, area_id, x, y, z,
  rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id,
  faction_id, base_faction_id, quest_checklist_index, active_prop_id,
  world_socket_id
)
select
  'server_choice',
  'the offset of world-database row ' || beast.row_id
    || ' from WorldLocation2 51739''s centre, applied to WorldLocation2 52898''s centre',
  0, 73465, 3460, 0, beast.x, beast.y, beast.z,
  beast.rotation_x, beast.rotation_y, beast.rotation_z, 26578, 0,
  1442, 1442, 0, 0, 0
from (values
  (29113, 22.259363786621094, -874.3194607421875, 314.6367134277344, 0.969689, -0.052972727, 0),
  (29114, 55.04507378662109, -872.4375607421875, 321.3534534277344, 0.73901165, 0, 0),
  (29115, 68.88883378662109, -873.1170007421875, 308.35855342773436, 3.1198492, 0.10843395, 0),
  (29116, -4.867986213378913, -875.4285607421875, 318.6113634277344, -1.4217286, 0, 0),
  (29117, -2.910086213378918, -876.5668607421875, 269.84549342773437, 0.45911896, -0.035382833, 0),
  (29118, 62.04113378662109, -875.1356207421875, 266.71914342773437, -0.6019851, -0.036788017, 0),
  (29119, 9.35453378662109, -875.1991607421875, 304.77795342773436, -2.8980408, 0.05516354, 0),
  (29120, 55.4722237866211, -872.4413607421875, 323.81924342773436, -0.8221373, 0.08632926, 0),
  (29121, 67.3386237866211, -872.9974607421875, 308.8815334277344, 1.896174, 0.07294519, 0),
  (29122, 68.00666378662109, -875.1352607421875, 282.8051134277344, 3.0671954, -0.30481002, 0),
  (29123, 81.96807878662109, -873.9655607421874, 287.1403134277344, 2.2686727, 0.009670544, 0),
  (29124, 28.64569378662108, -877.9194607421875, 252.05501342773437, 0.7952723, -0, 0),
  (29125, 6.4676937866210835, -873.8731607421875, 328.7300134277344, 1.6185439, -0, 0),
  (29126, 21.1136937866211, -873.4965207421875, 315.01401342773437, -3.0390623, -0, 0),
  (29127, 57.112693786621094, -872.3322607421875, 320.97101342773436, 1.5744547, -0, 0),
  (29128, 7.992693786621089, -874.5932607421875, 307.9320134277344, 0.48829034, -0, 0),
  (29129, 33.60669378662109, -875.2249607421875, 296.2560134277344, 2.6542475, -0, 0),
  (29130, -3.73330621337891, -875.1345207421875, 317.56501342773436, -2.5319326, -0, 0),
  (29131, -8.992306213378896, -875.4689907421875, 287.0690134277344, 1.9416362, -0, 0),
  (29132, 37.104693786621084, -875.4689907421875, 310.5330134277344, -0.94117236, -0, 0),
  (29133, 10.922693786621096, -878.4079607421875, 264.7410134277344, 1.5279827, -0, 0),
  (29134, 43.136693786621095, -874.1772607421875, 325.1430134277344, 0.47906998, -0, 0),
  (29135, 3.8706937866211035, -876.1280607421875, 280.4850134277344, -0.25816834, -0, 0),
  (29136, 38.11569378662108, -875.1323607421875, 312.1383934277344, -0.69088703, 0.057492983, 0),
  (29137, -3.3356062133788953, -875.1921607421875, 319.7763934277344, -1.3988972, 0, 0),
  (29138, 32.7973537866211, -875.0747607421876, 292.81204342773435, 2.6542475, 0, 0),
  (29139, 84.83143378662109, -873.2308607421875, 290.5744134277344, 2.1459963, 0, 0)
) as beast (row_id, x, y, z, rotation_x, rotation_y, rotation_z)
order by beast.row_id;
