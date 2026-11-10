-- A purchase from a vendor, all or none, in one statement: the amount the character `$1` of
-- the account `$2` holds of the currency type `$4` is lowered by `$6`, each stack of the
-- lists `$8` to `$10` at the same position (an item's guid, the count it is held with, the
-- count it holds after) is raised, and a stack of the Item2 `$7` is inserted at each place
-- of the lists `$11` to `$13` (a location, a bag index and a count). It changes only while
-- the character is still held by the login that asks, that is while its `session_epoch`
-- ($3) is still the one that login was told (load_character.sql), only while the character
-- holds exactly `$5` of that currency (the total the login holds) and at least `$6`, and
-- only when each stack to raise is the character's, of the Item2 `$7`, with the count it is
-- held with; otherwise it changes nothing and returns no row. The account's id is in the
-- statement, as for a load.
--
-- The rows it returns are one for each stack made, each with the amount left; one row with
-- no stack when none is made. A place that holds an item breaks the table's
-- `character_item_one_per_slot` at the statement's end and the statement changes nothing,
-- the currency and the raised stacks included. Whether a stack may hold its new count is the
-- Item2's maxStackCount, which the rule checks. The statement runs after
-- lock_character_for_save.sql in one transaction, so it waits for a login that is raising
-- the epoch and then reads the epoch that login stored.
with grown as (
  select grow.item_guid, grow.held_count, grow.new_count
  from unnest($8::bigint[], $9::int[], $10::int[])
    as grow (item_guid, held_count, new_count)
),
allowed as (
  select balance.character_id
  from character
  join character_currency as balance on balance.character_id = character.character_id
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and balance.currency_type_id = $4
    and balance.amount = $5
    and $6 >= 0
    and balance.amount >= $6
    and (
      select count(*)
      from grown
      join character_item as held on held.item_guid = grown.item_guid
      where held.character_id = $1
        and held.item2_id = $7
        and held.stack_count = grown.held_count
    ) = (select count(*) from grown)
),
spent as (
  update character_currency as balance
  set amount = balance.amount - $6
  from allowed
  where balance.character_id = allowed.character_id
    and balance.currency_type_id = $4
  returning balance.amount
),
raised as (
  update character_item as held
  set stack_count = grown.new_count
  from grown
  where held.item_guid = grown.item_guid
    and held.character_id = $1
    and exists (select 1 from allowed)
  returning held.item_guid
),
made as (
  insert into character_item (character_id, item2_id, location, bag_index, stack_count)
  select $1, $7, new_stack.location::smallint, new_stack.bag_index, new_stack.stack_count
  from unnest($11::int[], $12::int[], $13::int[])
    as new_stack (location, bag_index, stack_count)
  where exists (select 1 from allowed)
  returning item_guid, location::int as location, bag_index, stack_count
)
select
  spent.amount as amount,
  made.item_guid,
  made.location,
  made.bag_index,
  made.stack_count
from spent
left join made on true
order by made.item_guid;
