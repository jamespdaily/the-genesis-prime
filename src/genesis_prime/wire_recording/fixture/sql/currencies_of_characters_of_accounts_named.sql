-- The currencies held by the characters of the accounts with these login names,
-- in the order of their characters and types, with every column the fixture of a
-- recorded session keeps (genesis_prime/wire_recording/fixture): the character
-- that holds it, the currency type and the amount.
select
  character_id,
  currency_type_id::int as currency_type_id,
  amount
from character_currency
where character_id in (
  select character_id
  from character
  where account_id in (
    select account_id from account where login_name = any($1)
  )
)
order by character_id, currency_type_id;
