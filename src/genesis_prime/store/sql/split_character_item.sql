-- Takes `$8` off the stack of the item `$4` and makes a new stack of them at the
-- place `$9` and `$10`, in one statement. The source is the item the login holds
-- at `$5` and `$6` with the count `$7`; it is lowered only while the character is
-- still held by the login that asks, that is while its `session_epoch` ($3) is
-- still the one that login was told (load_character.sql), and only when that item
-- is as the request holds it, of the character `$1` of the account `$2`, and
-- `$8` is at least 1 and less than `$7`, which leaves the source at 1 or more.
-- Otherwise it changes nothing and returns no row. The account's id is in the
-- statement, as for a load. The row it returns is the new stack's, whose guid
-- the database makes (opcode.0x111.guid). The new stack keeps the source's random-stat word,
-- so a split never loses a roll.
--
-- A place that holds an item breaks the table's `character_item_one_per_slot` at
-- the statement's end and the statement changes nothing, the source included. The
-- statement runs after lock_character_for_save.sql in one transaction, so it waits
-- for a login that is raising the epoch and then reads the epoch that login
-- stored.
with lowered as (
  update character_item as source
  set stack_count = source.stack_count - $8
  from character
  where character.character_id = source.character_id
    and source.item_guid = $4
    and source.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and source.location = $5
    and source.bag_index = $6
    and source.stack_count = $7
    and $8 >= 1
    and $8 < $7
  returning source.item2_id, source.random_stats
)
insert into character_item (character_id, item2_id, location, bag_index, stack_count, random_stats)
select $1, lowered.item2_id, $9, $10, $8, lowered.random_stats
from lowered
returning item_guid;
