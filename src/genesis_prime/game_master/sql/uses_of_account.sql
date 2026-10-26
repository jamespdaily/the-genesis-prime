-- Every use of a command by an account, oldest first.
select
  account_id as "account_id!",
  command,
  arguments,
  outcome,
  refusal,
  refusal_permission
from game_master_use
where account_id = $1
order by id;
