-- The charges each item a character holds has left, as the client reads them with the item
-- (message 0x111's shared item record): the client refuses to use an item whose Item2 row
-- has maxCharges above 0 while the item holds 0. An item is made with its row's charges
-- (0 for a row with none, and for a proxy row, whose charges the client takes from its
-- source row), and a split keeps its source's.
--
-- NULL holds an item saved before this column existed: its charges are not known to the
-- row. World entry gives each such item its row's charges, once, and stores them
-- (fill_character_item_charges.sql), so no item is NULL after a login. Any other value is
-- 0 or more.

alter table character_item
  add column charges integer,
  add constraint character_item_charges_not_negative check (
    charges is null or charges >= 0
  );

comment on column character_item.charges is
  'The charges the item has left as the client reads them; 0 for an item with none; empty where none are recorded.';
