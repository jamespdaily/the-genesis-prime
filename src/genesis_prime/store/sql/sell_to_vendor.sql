-- A sale to a vendor, all or none, in one statement: the amount the character `$1` of the
-- account `$2` holds of the currency type `$4` is set to `$6` (its row is made when the
-- character holds none), each stack of the lists `$7` to `$10` at the same position (an
-- item's guid, the location it is held at, the count it is held with, the count sold) that
-- is sold whole (the count sold is the count held) is deleted, and each that is sold in
-- part is lowered by the count sold. It changes only while the character is still held by
-- the login that asks, that is while its `session_epoch` ($3) is still the one that login
-- was told (load_character.sql), only while the character holds exactly `$5` of that
-- currency (the total the login holds, a missing row being 0) and not more than `$6`, and
-- only when every stack named is the character's, at the location named, with the count it
-- is held with; a stack that is missing, that another login moved or that holds another
-- count stops the whole sale, and it changes nothing and returns no row. The account's id
-- is in the statement, as for a load. The row it returns holds the amount after the sale.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it waits for
-- a login that is raising the epoch and then reads the epoch that login stored.
with sold as (
  select sale.item_guid, sale.location, sale.held_count, sale.sold_count
  from unnest($7::bigint[], $8::int[], $9::int[], $10::int[])
    as sale (item_guid, location, held_count, sold_count)
),
allowed as (
  select character.character_id
  from character
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and coalesce((
      select held.amount
      from character_currency as held
      where held.character_id = character.character_id
        and held.currency_type_id = $4
    ), 0) = $5
    and $6 >= $5
    and (
      select count(*)
      from sold
      join character_item as held on held.item_guid = sold.item_guid
      where held.character_id = $1
        and held.location = sold.location
        and held.stack_count = sold.held_count
        and sold.sold_count >= 1
        and sold.sold_count <= sold.held_count
    ) = (select count(*) from sold)
),
paid as (
  insert into character_currency (character_id, currency_type_id, amount)
  select allowed.character_id, $4, $6
  from allowed
  on conflict (character_id, currency_type_id) do update
    set amount = excluded.amount
  returning amount
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
select paid.amount as amount
from paid;
