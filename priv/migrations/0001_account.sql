-- The accounts the login serves. The password is never stored: `salt` and
-- `verifier` are the SRP-6a values the STS login checks the client's proof
-- against (src/genesis_prime/login/srp.gleam). `id` is the number the log
-- names the account by. `name` is lower case, as the client sends it.
-- `user_id` is the GUID the STS login names the account by.
create table account (
  id bigint generated always as identity primary key,
  name text not null unique check (name <> ''),
  salt bytea not null,
  verifier bytea not null,
  user_id uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);
