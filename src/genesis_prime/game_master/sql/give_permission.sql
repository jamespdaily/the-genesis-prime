-- Gives an account a permission; an account that holds it already keeps it.
-- An account that does not exist breaks the foreign key.
insert into permission (account_id, name)
values ($1, $2)
on conflict do nothing;
