-- A sale to a vendor, all or none, in one statement: the credits of the character `$1` of
-- the account `$2` are set to `$5`, each stack of the lists `$6` to `$8` at the same
-- position (an item's guid, the count it is held with, the count sold) that is sold whole
-- (the count sold is the count held) is deleted, and each that is sold in part is lowered
-- by the count sold. It changes only while the character is still held by the login that
-- asks, that is while its `session_epoch` ($3) is still the one that login was told
-- (load_character.sql), only while the character holds exactly `$4` credits (the total the
-- login holds) and not more than `$5`, and only when every stack named is the character's,
-- at an inventory place (location 1), with the count it is held with; a stack that is
-- missing, that another login moved or that holds another count stops the whole sale, and
-- it changes nothing and returns no row. The account's id is in the statement, as for a
-- load. The row it returns holds the credits after the sale.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it waits for
-- a login that is raising the epoch and then reads the epoch that login stored.
with sold as (
  select sale.item_guid, sale.held_count, sale.sold_count
  from unnest($6::bigint[], $7::int[], $8::int[])
    as sale (item_guid, held_count, sold_count)
),
allowed as (
  select credits.character_id
  from character
  join character_currency as credits on credits.character_id = character.character_id
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and credits.currency_type_id = 1
    and credits.amount = $4
    and $5 >= credits.amount
    and (
      select count(*)
      from sold
      join character_item as held on held.item_guid = sold.item_guid
      where held.character_id = $1
        and held.location = 1
        and held.stack_count = sold.held_count
        and sold.sold_count >= 1
        and sold.sold_count <= sold.held_count
    ) = (select count(*) from sold)
),
paid as (
  update character_currency as credits
  set amount = $5
  from allowed
  where credits.character_id = allowed.character_id
    and credits.currency_type_id = 1
  returning credits.amount
),
removed as (
  delete from character_item as held
  using sold
  where held.item_guid = sold.item_guid
    and held.character_id = $1
    and sold.sold_count = sold.held_count
    and exists (select 1 from allowed)
  returning held.item_guid
),
lowered as (
  update character_item as held
  set stack_count = sold.held_count - sold.sold_count
  from sold
  where held.item_guid = sold.item_guid
    and held.character_id = $1
    and sold.sold_count < sold.held_count
    and exists (select 1 from allowed)
  returning held.item_guid
)
select paid.amount as credits
from paid;
