-- A character's name is unique regardless of case and is shown as it was
-- typed: the unique index is on the lower case of the name, and replaces the
-- constraint on the name as typed, which it makes redundant.
alter table character drop constraint character_name_key;

create unique index character_name_lower_key on character (lower(name));
