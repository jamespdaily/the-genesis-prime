-- Deletes the account's character with this id. The account's id is in the
-- statement, so another account's character, which a modified client could
-- name, is never touched. No row means the account has no such character.
delete from character
where character_id = $1 and account_id = $2
returning character_id;
