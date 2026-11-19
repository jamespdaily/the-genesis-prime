-- A purchase from a vendor, all or none, in one statement: the amount the character `$1` of
-- the account `$2` holds of the currency type `$4` is lowered by `$6`, each stack of the
-- lists `$8` to `$10` at the same position (an item's guid, the count it is held with, the
-- count it holds after) is raised, and a stack of the Item2 `$7` is inserted at each place
-- of the lists `$11` to `$17` (a location, a bag index, a count, the item's random-stat word, its charges, its flags byte and the Unix milliseconds it runs out, -1 for never). It changes only while
-- the character is still held by the login that asks, that is while its `session_epoch`
-- ($3) is still the one that login was told (load_character.sql), only while the character
-- holds exactly `$5` of that currency (the total the login holds) and at least `$6`, and
-- only when each stack to raise is the character's, of the Item2 `$7`, with the count it is
-- held with; otherwise it changes nothing and returns no row. A character with no row for the
-- currency holds 0 of it, so it passes only at a `$6` of 0, and then the statement makes the
-- row at 0. The account's id is in the statement, as for a load.
--
-- The rows it returns are one for each stack made, each with the amount left and the word, charges, flags byte and moment it
-- runs out it was made with; one row with
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
    and $6 >= 0
    and $5 >= $6
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
  insert into character_currency (character_id, currency_type_id, amount)
  select allowed.character_id, $4, 0
  from allowed
  on conflict (character_id, currency_type_id) do update
    set amount = character_currency.amount - $6
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
  insert into character_item (character_id, item2_id, location, bag_index, stack_count, random_stats, charges, item_flags, expires_at_unix_ms)
  select $1, $7, new_stack.location::smallint, new_stack.bag_index, new_stack.stack_count, new_stack.random_stats, new_stack.charges, new_stack.item_flags::smallint, nullif(new_stack.expires_at_unix_ms, -1)
  from unnest($11::int[], $12::int[], $13::int[], $14::bigint[], $15::int[], $16::int[], $17::bigint[])
    as new_stack (location, bag_index, stack_count, random_stats, charges, item_flags, expires_at_unix_ms)
  where exists (select 1 from allowed)
  returning item_guid, location::int as location, bag_index, stack_count, random_stats, charges, item_flags::int as item_flags, expires_at_unix_ms
)
select
  spent.amount as amount,
  made.item_guid,
  made.location,
  made.bag_index,
  made.stack_count,
  made.random_stats,
  made.charges,
  made.item_flags,
  made.expires_at_unix_ms
from spent
left join made on true
order by made.item_guid;
