-- Marks the character with this name as needing a rename, for a developer's
-- database: the client then offers the player a rename when the character is
-- played. The name is found as the name's unique index finds it, in any case,
-- under the ICU root collation (migration 0005), so no two names differ only in
-- case here either. No character of that name gives no row.
update character
set needs_rename = true
where lower(name collate "und-x-icu") = lower($1 collate "und-x-icu")
returning character_id;
