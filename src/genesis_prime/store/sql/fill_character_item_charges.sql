-- Gives the items of the lists `$4` and `$5` at the same position (an item's guid and the
-- charges to give it) their charges, in one statement: only the items of the character `$1`
-- of the account `$2` that hold none (charges null), and only while the character is still
-- held by the login that asks, that is while its `session_epoch` ($3) is still the one that
-- login was told (load_character.sql). A row that already holds charges, another
-- character's row and a stale login change nothing, so a replay changes no row. The rows it
-- returns are the rows it set; a list with every item set returns them all.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it waits for
-- a login that is raising the epoch and then reads the epoch that login stored.
update character_item as held
set charges = fill.charges
from unnest($4::bigint[], $5::int[]) as fill (item_guid, charges), character
where held.item_guid = fill.item_guid
  and held.character_id = $1
  and held.charges is null
  and character.character_id = held.character_id
  and character.account_id = $2
  and character.session_epoch = $3
returning held.item_guid;
