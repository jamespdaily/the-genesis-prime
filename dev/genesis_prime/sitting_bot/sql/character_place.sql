-- The character with this name, found as the name's unique index finds it (any
-- case, under the ICU root collation: migration 0005), and the place it is
-- saved at. World 0 is no place (migration 0006). No character of the name
-- gives no row.
select character_id, world_id, world_zone_id, position_x, position_y, position_z
from character
where lower(name collate "und-x-icu") = lower($1 collate "und-x-icu");
