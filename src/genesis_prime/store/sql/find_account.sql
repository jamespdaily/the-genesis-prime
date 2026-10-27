-- The account with this login name, as the STS login needs it. The game
-- account id is read as its 8-4-4-4-12 text, the form the STS login's GUIDs
-- are parsed from.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
where login_name = $1;
