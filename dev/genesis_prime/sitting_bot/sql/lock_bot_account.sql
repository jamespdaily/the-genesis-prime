-- Takes the row lock of the account with this login name until the transaction
-- ends, so two runs make the bot's character one after another, and the second
-- finds the first's.
select account_id
from account
where login_name = $1
for update;
