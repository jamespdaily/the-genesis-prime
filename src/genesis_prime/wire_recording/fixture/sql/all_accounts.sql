-- Every account, in the order of its id, with every column the fixture of a
-- recorded session keeps (genesis_prime/wire_recording/fixture): the id the
-- session's rows name, the login name, the SRP salt and verifier and the game
-- account's GUID as its 8-4-4-4-12 text. `created_at` is left out: it is the
-- time a row was made, which no flow reads.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
order by account_id;
