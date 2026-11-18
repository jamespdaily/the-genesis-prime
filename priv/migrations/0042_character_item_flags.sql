-- The flags byte of each item a character holds, as the client reads it with the item
-- (message 0x111's shared item record): bit 0 is soulbound and bit 3 is no refund. The
-- server sets soulbound when a bind-on-equip item is put in a worn slot, and sends the
-- byte whole at every entry and when it changes. An item is made with 0.
--
-- The check allows bits 0 and 3 and nothing else.

alter table character_item
  add column item_flags smallint not null default 0,
  add constraint character_item_item_flags_are_set_bits check (
    item_flags >= 0 and (item_flags & ~9) = 0
  );

comment on column character_item.item_flags is
  'The flags byte of the item as the client reads it: bit 0 soulbound, bit 3 no refund; 0 for an item with none.';
