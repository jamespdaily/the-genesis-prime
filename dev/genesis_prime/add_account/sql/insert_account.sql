-- Adds an account; the database makes its id. The game account id is given
-- as its 8-4-4-4-12 text, a text parameter, so no UUID package is needed.
insert into account (login_name, srp_salt, srp_verifier, game_account_id)
values ($1, $2, $3, $4::text::uuid)
returning account_id;
