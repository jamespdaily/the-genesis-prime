-- Makes the bot's account when the database has none: the login name ($1), the
-- salt ($2) and verifier ($3) of its password and the game account id ($4) as
-- its 8-4-4-4-12 text. An account with the login name already there is left as
-- it is, so a run beside another, or after one, finds the same account.
insert into account (login_name, srp_salt, srp_verifier, game_account_id)
values ($1, $2, $3, $4::text::uuid)
on conflict (login_name) do nothing;
