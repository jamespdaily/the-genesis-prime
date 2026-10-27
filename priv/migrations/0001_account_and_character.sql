-- The accounts and their characters: what a login and a character list need
-- to begin. The flows that use each column add the columns they need.

-- One player's login. The SRP salt and verifier are what the STS login checks
-- the password against; the password itself is never kept.
create table account (
  account_id bigint generated always as identity primary key,
  login_name text not null unique check (login_name <> ''),
  srp_salt bytea not null check (length(srp_salt) > 0),
  srp_verifier bytea not null check (length(srp_verifier) > 0),
  -- The game account's GUID, which the client carries from the STS login to
  -- the auth server.
  game_account_id uuid not null unique,
  created_at timestamptz not null default now()
);

-- One character of an account. `session_epoch` fences a stale writer: each
-- login that takes the character raises it, and a save names the epoch it
-- was made under, so a save from an older session changes nothing.
create table character (
  character_id bigint generated always as identity primary key,
  account_id bigint not null references account (account_id),
  session_epoch bigint not null default 0 check (session_epoch >= 0),
  created_at timestamptz not null default now()
);

create index character_account on character (account_id);
