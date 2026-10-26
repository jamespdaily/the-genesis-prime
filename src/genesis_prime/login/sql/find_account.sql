-- The account of a lower-case name, if there is one. Its GUID and its
-- creation time are returned as text.
select
  id,
  name,
  salt,
  verifier,
  user_id::text as "user_id!",
  to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as "created!"
from account
where name = $1;
