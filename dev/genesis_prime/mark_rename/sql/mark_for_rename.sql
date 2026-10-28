-- Marks the character with this name, in any case, as needing a rename, for a
-- developer's database: the client then offers the player a rename when the
-- character is played. No character of that name gives no row.
update character
set needs_rename = true
where lower(name) = lower($1)
returning character_id;
