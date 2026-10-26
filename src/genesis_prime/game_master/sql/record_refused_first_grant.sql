-- Records a first grant that was refused because an account holds the
-- permission already. `arguments` names the account that was to be given it,
-- and the permission is the one that was held.
insert into game_master_use (
  command, arguments, outcome, refusal, refusal_permission
)
values ('first_grant', $1, 'refused', 'first_grant_over', $2);
