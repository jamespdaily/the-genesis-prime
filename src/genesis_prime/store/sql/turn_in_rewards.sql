-- The rewards of a quest's turn-in, all or none, in one statement: the credits the character
-- `$1` of the account `$2` holds (the currency type `$4`) are set to `$6`, each stack of
-- the lists `$7` to `$10` at the same position (an item's guid, its Item2, the count it is
-- held with, the count it holds after) is raised, and a stack is inserted for each position of
-- the lists `$11` to `$14` (an Item2, a location, a bag index and a count). It changes only
-- while the character is still held by the login that asks, that is while its
-- `session_epoch` ($3) is still the one that login was told (load_character.sql), only while
-- the character holds exactly `$5` credits (the total the login holds, a missing row being 0)
-- and not more than `$6`, and only when each stack to raise is the character's, of its Item2,
-- with the count it is held with; otherwise it changes nothing and returns no row. The
-- account's id is in the statement, as for a load.
--
-- The rows it returns are one for each stack made, each with the credits held after and the
-- stack's Item2, in the order of the lists; one row with no stack when none is made. A place
-- that holds an item breaks the table's `character_item_one_per_slot` at the statement's end
-- and the statement changes nothing, the credits and the raised stacks included. Whether a
-- stack may hold its new count is the Item2's maxStackCount, which the rule checks.
--
-- The statement runs after lock_character_for_save.sql and save_place.sql in one
-- transaction, so it waits for a login that is raising the epoch and then reads the epoch that
-- login stored; the caller rolls the save of the place back when this statement returns no
-- row.
with grown as (
  select grow.item_guid, grow.item2_id, grow.held_count, grow.new_count
  from unnest($7::bigint[], $8::int[], $9::int[], $10::int[])
    as grow (item_guid, item2_id, held_count, new_count)
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
      from grown
      join character_item as held on held.item_guid = grown.item_guid
      where held.character_id = $1
        and held.item2_id = grown.item2_id
        and held.stack_count = grown.held_count
    ) = (select count(*) from grown)
),
paid as (
  insert into character_currency (character_id, currency_type_id, amount)
  select allowed.character_id, $4, $6
  from allowed
  on conflict (character_id, currency_type_id) do update
    set amount = excluded.amount
  returning amount
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
  select $1, new_stack.item2_id, new_stack.location::smallint, new_stack.bag_index, new_stack.stack_count
  from unnest($11::int[], $12::int[], $13::int[], $14::int[])
    with ordinality as new_stack (item2_id, location, bag_index, stack_count, position)
  where exists (select 1 from allowed)
  order by new_stack.position
  returning item_guid, item2_id, location::int as location, bag_index, stack_count
)
select
  paid.amount as amount,
  made.item_guid,
  made.item2_id,
  made.location,
  made.bag_index,
  made.stack_count
from paid
left join made on true
order by made.item_guid;
