-- Deletes a character of the account and returns its id. No row is returned
-- when the account has no such character.
delete from character
where id = $1 and account_id = $2
returning id;
