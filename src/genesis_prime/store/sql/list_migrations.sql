-- The migration files the database has run, with the SHA-256 each file had
-- (lower-case hex) when it ran, which the server compares with the files in
-- priv/migrations at start (genesis_prime/migration). Fails with an undefined
-- table on a database that has no schema_migration, which the store answers as
-- a database with no record.
select name, sha256
from schema_migration
order by name;
