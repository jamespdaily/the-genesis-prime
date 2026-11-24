-- Takes every spent ability tier saved for the character with this id ($1), of
-- the account with this login name ($2), so the character enters with no points
-- spent, as it holds no saved action bar either.
delete from character_ability_tier
where character_id = $1
  and character_id in (
    select character_id
    from character
    join account using (account_id)
    where account.login_name = $2
  );
