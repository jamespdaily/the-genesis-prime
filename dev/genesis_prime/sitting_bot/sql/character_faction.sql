-- The faction of the character with this name, found as the name's unique index
-- finds it (any case, under the ICU root collation: migration 0005). No character
-- of the name gives no row.
select faction_id
from character
where lower(name collate "und-x-icu") = lower($1 collate "und-x-icu");
