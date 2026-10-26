-- The characters of the accounts. `account_id` is the id of the account that
-- owns the character. `creation_id` is the client's CharacterCreation row the
-- character was made from, and `gender`, `race_id`, `class_id` and `faction_id`
-- are that row's sex, raceId, classId and factionId when it was made. A
-- position is three numbers that a 32-bit float holds exactly. `experience` is
-- the character's experience, which a new character takes from the row's xp. The three
-- arrays hold what the create request carried: the customisation labels and
-- their values, and the bone values as the bits of 32-bit floats.
create table character (
  id bigint generated always as identity primary key,
  account_id bigint not null references account (id),
  name text not null unique check (name <> ''),
  creation_id integer not null,
  gender smallint not null check (gender between 0 and 3),
  race_id smallint not null check (race_id between 0 and 31),
  class_id smallint not null check (class_id between 0 and 31),
  faction_id integer not null,
  experience bigint not null check (experience >= 0),
  level integer not null check (level >= 1),
  path smallint not null check (path between 0 and 7),
  world_id integer not null check (world_id between 0 and 32767),
  world_zone_id integer not null check (world_zone_id between 0 and 32767),
  position_x double precision not null,
  position_y double precision not null,
  position_z double precision not null,
  customisation_labels bigint[] not null,
  customisation_values bigint[] not null,
  bone_values bigint[] not null,
  requires_rename boolean not null default false,
  disabled boolean not null default false,
  created_at timestamptz not null default now(),
  check (cardinality(customisation_labels) = cardinality(customisation_values))
);

create index character_account_id on character (account_id);
