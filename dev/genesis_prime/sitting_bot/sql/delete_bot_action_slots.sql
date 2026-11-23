-- Takes every action bar slot saved for the character with this id ($1), of the
-- account with this login name ($2), so it shows its new class's bar.
delete from character_action_slot
where character_id = $1
  and character_id in (
    select character_id
    from character
    join account using (account_id)
    where account.login_name = $2
  );
