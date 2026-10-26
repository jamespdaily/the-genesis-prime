-- Adds an account and returns the GUID the database gave it and its creation
-- time, as text.
insert into account (name, salt, verifier)
values ($1, $2, $3)
returning
  id as "id!",
  user_id::text as "user_id!",
  to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as "created!";
