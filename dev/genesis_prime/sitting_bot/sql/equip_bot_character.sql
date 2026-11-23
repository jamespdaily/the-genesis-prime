-- Makes the character with this id ($1), of the account with this login name
-- ($5), a character of class $2 and faction $3 at level $4: it holds no saved
-- experience, so its level is the one given, and no saved health, so it enters
-- at full health. Only a character of that account is changed: no character of
-- that id of that account gives no row.
update character
set
  class_id = $2,
  faction_id = $3,
  level = $4,
  experience = null,
  health = null
where character_id = $1
  and account_id in (select account_id from account where login_name = $5)
returning character_id;
