-- Takes the account's row lock until the transaction ends, so the creates of
-- one account run one after another and each counts the characters the one
-- before it made. No row means no such account.
select account_id
from account
where account_id = $1
for update;
