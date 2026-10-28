-- What a create request keeps of a character beyond its creation row: the look
-- (the customisation labels with their values) and the bone values, and the
-- uniqueness of a name.
--
-- The labels, their values and the bone values are the 32-bit numbers the
-- client sends (opcode.0x25b), kept in bigint so every one fits unchanged; a
-- bone value is a float's 32 bits. The client sends at most 27 labels (the
-- label table's size) and at most 48 bone values (opcode.0x25b.counts), and
-- each label has its value.
--
-- A name is unique ignoring case: the client's names are letters and one space
-- (text rule 0, 0x1403e1170), and `lower` folds the Latin-1 letters it lists
-- under the database's UTF-8 locale.
alter table character
  add column look_labels bigint[] not null default '{}',
  add column look_values bigint[] not null default '{}',
  add column bones bigint[] not null default '{}',
  add constraint character_look_pairs
    check (
      cardinality(look_labels) = cardinality(look_values)
      and cardinality(look_labels) <= 27
    ),
  add constraint character_bones_at_most_48
    check (cardinality(bones) <= 48);

create unique index character_name_unique on character (lower(name));
