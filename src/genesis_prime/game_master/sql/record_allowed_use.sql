-- Records one use of a command by an account that the rule allowed.
insert into game_master_use (account_id, command, arguments, outcome)
values ($1, $2, $3, 'allowed');
