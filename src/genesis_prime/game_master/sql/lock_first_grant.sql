-- Takes, until the transaction ends, the lock that makes first grants of one
-- permission wait for one another. It is its own statement, run before
-- `give_first_permission`, so the next statement sees what a first grant that
-- held the lock has committed.
select 1 as "locked!"
from (select pg_advisory_xact_lock(hashtext($1::text))) as lock;
