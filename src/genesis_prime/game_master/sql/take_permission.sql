-- Takes a permission from an account; an account that does not hold it is
-- left as it is.
delete from permission
where account_id = $1 and name = $2;
