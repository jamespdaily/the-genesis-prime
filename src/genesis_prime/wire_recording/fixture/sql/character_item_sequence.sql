-- Where the item guid sequence stands: the last value it gave (or the value it
-- gives first, when it has given none) and whether it has given one, which the
-- fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
-- with `setval`, so an item a replay makes gets the guid it got live.
select last_value, is_called from character_item_item_guid_seq;
