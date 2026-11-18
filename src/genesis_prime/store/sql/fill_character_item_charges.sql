-- Gives the items of the lists `$4` and `$5` at the same position (an item's guid and the
-- charges to give it) their charges, all or none, in one statement: it changes rows only
-- while the character `$1` of the account `$2` is still held by the login that asks, that
-- is while its `session_epoch` ($3) is still the one that login was told (load_character.sql),
-- and only when every item named is the character's and holds none (charges null). A row
-- that already holds charges, another character's row and a stale login stop the whole fill,
-- which changes nothing and returns no row, so a replay changes no row. The rows it returns
-- are the rows it set, one for each item named.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it waits for
-- a login that is raising the epoch and then reads the epoch that login stored.
with fills as (
  select fill.item_guid, fill.charges
  from unnest($4::bigint[], $5::int[]) as fill (item_guid, charges)
),
allowed as (
  select character.character_id
  from character
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and (
      select count(*)
      from fills
      join character_item as held on held.item_guid = fills.item_guid
      where held.character_id = $1
        and held.charges is null
    ) = (select count(*) from fills)
)
update character_item as held
set charges = fills.charges
from fills, allowed
where held.item_guid = fills.item_guid
  and held.character_id = allowed.character_id
returning held.item_guid;
