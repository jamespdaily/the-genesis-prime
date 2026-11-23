-- Takes every item from the character with this id ($1), of the account with
-- this login name ($2), so the set of its new class can be given in their place.
delete from character_item
where character_id = $1
  and character_id in (
    select character_id
    from character
    join account using (account_id)
    where account.login_name = $2
  );
