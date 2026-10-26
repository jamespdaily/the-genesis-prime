-- Records a first grant that gave a permission. The database's operator made
-- it, so no account is named; `arguments` names the account that was given
-- the permission.
insert into game_master_use (command, arguments, outcome)
values ('first_grant', $1, 'allowed');
