-- The names of the permissions an account holds.
select name
from permission
where account_id = $1
order by name;
