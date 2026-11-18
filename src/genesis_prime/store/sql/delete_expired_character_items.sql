-- Deletes the items of the character `$1` that run out at the Unix millisecond `$2` or
-- earlier, and returns the guid of each: an item the character held that ran out while it
-- was logged out is gone before world entry reads the items. It runs on the transaction of
-- load_character.sql, after the statement that raised the epoch took the character's row, so
-- no save or request of an older login runs between the delete and the read of the items.
delete from character_item
where character_id = $1
  and expires_at_unix_ms is not null
  and expires_at_unix_ms <= $2
returning item_guid;
