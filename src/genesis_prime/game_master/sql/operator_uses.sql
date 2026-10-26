-- Every use made by the database's operator and not by an account, oldest
-- first: the first grants.
select
  command,
  arguments,
  outcome,
  refusal,
  refusal_permission
from game_master_use
where account_id is null
order by id;
