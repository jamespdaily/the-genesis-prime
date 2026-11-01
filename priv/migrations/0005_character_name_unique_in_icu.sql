-- A character's name is unique ignoring case on any database locale. The first
-- index folded case with `lower(name)`, which takes its rules from the
-- database's LC_CTYPE: on a database made with C, "Éb Cd" and "éB cD" folded to
-- different strings, so both were allowed. Folding under the ICU collation
-- "und-x-icu" (the root locale) does not depend on the database's locale, and
-- the setup check refuses a Postgres built without ICU. The index keeps its
-- name, which the store maps to a name already taken.
drop index character_name_unique;
create unique index character_name_unique
  on character (lower(name collate "und-x-icu"));
