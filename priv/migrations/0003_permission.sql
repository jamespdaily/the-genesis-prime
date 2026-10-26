-- What each account may do as a game master, and the record of every use of a
-- game master command. A new account has no row in `permission`. `name` is
-- the permission's name as `game_master/permission.gleam` writes it.
create table permission (
  account_id bigint not null references account (id),
  name text not null check (name <> ''),
  granted_at timestamptz not null default now(),
  primary key (account_id, name)
);

-- One row for each use of a command, allowed or refused. `account_id` is the
-- account that used it, `command` the command's name and `arguments` what it
-- was given, as text. The first grant of a permission is made by the database's
-- operator and not by an account, so only `first_grant` has no `account_id`,
-- and its `arguments` name the account given the permission. `outcome` is
-- `allowed` or `refused`; a refused use also names why in `refusal`
-- (`missing_permission`, `unknown_permission` or `first_grant_over`) and the
-- permission it is about in `refusal_permission`, and an allowed use has
-- neither.
create table game_master_use (
  id bigint generated always as identity primary key,
  account_id bigint references account (id),
  command text not null check (command <> ''),
  arguments text not null,
  outcome text not null check (outcome in ('allowed', 'refused')),
  refusal text check (refusal in ('missing_permission', 'unknown_permission', 'first_grant_over')),
  refusal_permission text,
  used_at timestamptz not null default now(),
  check (account_id is not null or command = 'first_grant'),
  check (
    (outcome = 'allowed' and refusal is null and refusal_permission is null)
    or (outcome = 'refused' and refusal is not null and refusal_permission is not null)
  )
);

create index game_master_use_by_account on game_master_use (account_id, id);
