-- Adds an account and returns the GUID the database gave it.
insert into account (name, salt, verifier)
values ($1, $2, $3)
returning user_id::text as "user_id!";
