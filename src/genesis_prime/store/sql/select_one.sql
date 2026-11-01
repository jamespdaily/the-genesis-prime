-- The readiness probe: a read that needs no table, so it succeeds exactly when
-- the pool can run a query on a connection.
select 1 as one;
