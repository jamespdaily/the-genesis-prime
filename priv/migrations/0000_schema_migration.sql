-- The record of which migration files a database has run. `dev/apply_migrations.sh`
-- inserts a file's name and the SHA-256 of its bytes (lower-case hex) in the
-- transaction that runs the file, and the server at start compares the rows
-- with the files in priv/migrations (genesis_prime/migration): a file with no
-- row, a row with no file, or a row whose hash differs from its file's (an
-- applied migration edited after it ran) stops the server. This file sorts
-- before the others so that every file, itself included, is recorded in the
-- transaction that runs it.
create table schema_migration (
  name text primary key check (name <> ''),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  applied_at timestamptz not null default now()
);
