-- What the character list reads of a character. The list shows each
-- character's name, level, faction frame, class icon and path icon, and the
-- model comes from its race, gender and class
-- (lua.CharacterSelection.OnLoadFromCharacter.list); the entry also carries
-- where the character stands (opcode.0x117). No two characters need different
-- names here: a name's uniqueness belongs to the flow that creates the
-- character.
--
-- Each check is what the client's code allows or what the entry's field can
-- carry (its width in the message, ReadCharacterListEntry 0x14007f720):
-- - name 1 to 32 characters: the client copies at most 32 characters of a name
--   (CopyCharacterListEntry 0x1400201f0), and a name of none shows nothing;
-- - class 1 to 20: the client shows ClassIcon_<class> for the classes 1 to 20;
-- - path 0 to 3: the client shows PathIcon_<path + 1> up to 4, so paths 0 to 3;
-- - gender (2 bits), race (5 bits) and the two world ids (15 bits) fit the
--   entry's fields, so the list can always be written;
-- - faction and level are 32 bits in the entry and never negative.
alter table character
  add column name text not null
    constraint character_name_shown_by_the_client
      check (char_length(name) between 1 and 32),
  add column gender smallint not null
    constraint character_gender_fits_the_entry check (gender between 0 and 3),
  add column race_id smallint not null
    constraint character_race_fits_the_entry check (race_id between 0 and 31),
  add column class_id smallint not null
    constraint character_class_shown_by_the_client check (class_id between 1 and 20),
  add column faction_id integer not null
    constraint character_faction_not_negative check (faction_id >= 0),
  add column level integer not null
    constraint character_level_not_negative check (level >= 0),
  add column path smallint not null
    constraint character_path_shown_by_the_client check (path between 0 and 3),
  add column world_id integer not null
    constraint character_world_fits_the_entry check (world_id between 0 and 32767),
  add column world_zone_id integer not null
    constraint character_world_zone_fits_the_entry check (world_zone_id between 0 and 32767),
  add column position_x real not null,
  add column position_y real not null,
  add column position_z real not null;
