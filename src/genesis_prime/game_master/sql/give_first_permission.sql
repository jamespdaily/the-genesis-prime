-- Gives an account a permission only while no account holds it, and returns
-- the account id when it did. The advisory lock on the permission's name
-- makes two first grants of it wait for one another, so both cannot find it
-- unheld.
with locked as (
  select pg_advisory_xact_lock(hashtext($2::text))
)
insert into permission (account_id, name)
select $1::bigint, $2::text
from locked
where not exists (select 1 from permission where name = $2::text)
returning account_id as "account_id!";
