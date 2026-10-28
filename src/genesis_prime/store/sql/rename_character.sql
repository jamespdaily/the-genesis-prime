-- Gives the account's marked character the name and clears the mark, in one
-- update. No row means the account has no such character or it is not marked.
-- A name that another character holds in any case breaks the unique index on
-- lower(name), which the caller reports as its own error, and the mark stays.
update character
set name = $3, needs_rename = false
where character_id = $1 and account_id = $2 and needs_rename
returning name;
