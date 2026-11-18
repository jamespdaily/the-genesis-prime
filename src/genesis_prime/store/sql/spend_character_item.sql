-- Lowers the stack count and the charges of the item `$4` of the character `$1` of
-- the account `$2` to `$8` and `$9`, in one statement. It lowers only while the
-- character is still held by the login that asks, that is while its `session_epoch`
-- ($3) is still the one that login was told (load_character.sql), and only when the
-- item is as the request holds it, at the place `$5` and `$6` with the count `$7` and
-- the charges `$10`; otherwise it changes nothing and returns no row. The account's id
-- is in the statement, as for a load. The row it returns is the item it lowered.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it
-- waits for a login that is raising the epoch and then reads the epoch that login
-- stored.
update character_item as item
set stack_count = $8,
    charges = $9
from character
where character.character_id = item.character_id
  and item.item_guid = $4
  and item.character_id = $1
  and character.account_id = $2
  and character.session_epoch = $3
  and item.location = $5
  and item.bag_index = $6
  and item.stack_count = $7
  and item.charges = $10
returning item.item_guid;
