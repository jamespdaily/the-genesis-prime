-- Gives an account a permission only while no account holds it, and returns
-- the account id when it did. It runs after `lock_first_grant` in the same
-- transaction, so two first grants of one permission cannot both find it
-- unheld.
insert into permission (account_id, name)
select $1::bigint, $2::text
where not exists (select 1 from permission where name = $2::text)
returning account_id as "account_id!";
