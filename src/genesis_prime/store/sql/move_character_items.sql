-- Moves held items to other places, all or none, in one statement: the moves are
-- the lists $4 to $8 at the same position (an item's guid, the location and bag
-- index it is held at, the location and bag index it goes to). It moves only
-- while the character is still held by the login that asks, that is while its
-- `session_epoch` ($3) is still the one that login was told (load_character.sql),
-- and only when every item is at the place its move leaves; otherwise it changes
-- nothing and returns no row. The account's id ($2) is in the statement, as for a
-- load. The rows it returns are the items it moved: as many as the moves, or none.
--
-- The places are swapped by one update under the table's deferrable unique key
-- `character_item_one_per_slot`, which is checked at the statement's end, so two
-- items that trade places pass it together. A place a check of the table refuses
-- breaks that check and nothing is moved. The statement runs after
-- lock_character_for_save.sql in one transaction, so it waits for a login that
-- is raising the epoch and then reads the epoch that login stored.
with incoming as (
  select *
  from unnest($4::bigint[], $5::int[], $6::int[], $7::int[], $8::int[])
    as move (item_guid, from_location, from_index, to_location, to_index)
),
matched as (
  select held.item_guid, incoming.to_location, incoming.to_index
  from incoming
  join character_item as held on held.item_guid = incoming.item_guid
  join character on character.character_id = held.character_id
  where held.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and held.location = incoming.from_location
    and held.bag_index = incoming.from_index
)
update character_item as held
set location = matched.to_location::smallint, bag_index = matched.to_index
from matched
where held.item_guid = matched.item_guid
  and (select count(*) from matched) = (select count(*) from incoming)
returning held.item_guid;
