-- Records one use of a command by an account that the rule refused, with why
-- and the permission the refusal is about.
insert into game_master_use (
  account_id, command, arguments, outcome, refusal, refusal_permission
)
values ($1, $2, $3, 'refused', $4, $5);
