-- A currency set to a total, in one statement: the amount the character `$1` of the account
-- `$2` holds of the currency type `$4` is set to `$6` (its row is made when the character
-- holds none; the total may be lower than the one held). It changes only while the character
-- is still held by the login that asks, that is while its `session_epoch` ($3) is still the
-- one that login was told (load_character.sql), and only while the character holds exactly
-- `$5` of that currency (the total the login holds, a missing row being 0); otherwise it
-- changes nothing and returns no row. The account's id is in the statement, as for a load.
-- The row it returns holds the amount after the change.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it waits for
-- a login that is raising the epoch and then reads the epoch that login stored.
with allowed as (
  select character.character_id
  from character
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and coalesce((
      select held.amount
      from character_currency as held
      where held.character_id = character.character_id
        and held.currency_type_id = $4
    ), 0) = $5
)
insert into character_currency (character_id, currency_type_id, amount)
select allowed.character_id, $4, $6
from allowed
on conflict (character_id, currency_type_id) do update
  set amount = excluded.amount
returning amount;
