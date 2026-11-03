-- The character with this name ($2, found as the name's unique index finds it:
-- any case, under the ICU root collation, migration 0005) of the account with
-- this login name ($1). A character of that name that another account has gives
-- no row, so it is never taken for this account's.
select character_id
from character
join account using (account_id)
where account.login_name = $1
  and lower(character.name collate "und-x-icu") = lower($2 collate "und-x-icu");
