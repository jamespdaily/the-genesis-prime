-- The account with this login name, which is stored in lower case. No account
-- of the name gives no row.
select account_id from account where login_name = $1;
