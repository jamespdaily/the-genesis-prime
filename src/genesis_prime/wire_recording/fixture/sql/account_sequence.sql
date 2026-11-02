-- Where the account id sequence stands: the last value it gave (or the value it
-- gives first, when it has given none) and whether it has given one, which the
-- fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
-- with `setval`, so an account a replay makes gets the id it got live.
select last_value, is_called from account_account_id_seq;
