-- Puts `$12` of the stack of the item `$4` onto the stack of the item `$8`, in
-- one statement: the target's count is raised by `$12`, and the source's is
-- lowered by it, or the source is deleted when `$12` is all of it. The source is
-- the item held at `$5` and `$6` with the count `$7`, the target the item held at
-- `$9` and `$10` with the count `$11`, both of the character `$1` of the account
-- `$2`. It changes only while the character is still held by the login that asks,
-- that is while its `session_epoch` ($3) is still the one that login was told
-- (load_character.sql), only when both items are as the request holds them, and
-- only when `$12` is at least 1 and at most `$7`; otherwise it changes nothing and
-- returns no row. The account's id is in the statement, as for a load. The rows it
-- returns are the two items it changed: two, or none. Whether the target may hold
-- the sum is the Item2's maxStackCount, which the rule checks.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it
-- waits for a login that is raising the epoch and then reads the epoch that login
-- stored.
with matched as (
  select held.item_guid
  from character_item as held
  join character on character.character_id = held.character_id
  where held.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and $12 >= 1
    and $12 <= $7
    and (
      (
        held.item_guid = $4
        and held.location = $5
        and held.bag_index = $6
        and held.stack_count = $7
      ) or (
        held.item_guid = $8
        and held.location = $9
        and held.bag_index = $10
        and held.stack_count = $11
      )
    )
),
raised as (
  update character_item as target
  set stack_count = target.stack_count + $12
  where target.item_guid = $8
    and (select count(*) from matched) = 2
  returning target.item_guid
),
lowered as (
  update character_item as source
  set stack_count = source.stack_count - $12
  where source.item_guid = $4
    and source.stack_count > $12
    and (select count(*) from matched) = 2
  returning source.item_guid
),
removed as (
  delete from character_item as source
  where source.item_guid = $4
    and source.stack_count = $12
    and (select count(*) from matched) = 2
  returning source.item_guid
)
select item_guid from raised
union all
select item_guid from lowered
union all
select item_guid from removed;
