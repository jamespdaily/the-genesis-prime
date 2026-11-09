-- The items a character holds in its equipped slots, inventory and bank, one row
-- each. `item_guid` is the item's identity for every later message about it
-- (opcode.0x111.guid): the database makes it when the row is inserted, never makes
-- it again, and it stays with the item when the item changes place. A guid is
-- unique in all 64 bits, which the client compares whole for a held item
-- (opcode.0x111.guid). Ability items (location 4) are not stored.
--
-- The checks name what the client has: the item id is the 18 bits the item added
-- message carries (opcode.0x111.ability_bag); a held item is at location 0
-- (equipped), 1 (inventory) or 2 (bank), with a bag index below the location's
-- slot count (31, 96 and 232; the client's equipped array is 31 long and its move
-- check refuses only indexes above 30); a stack count of 0 is read as 1, so only 1
-- or more is stored (opcode.0x111.shared_item_unnamed). Which inventory slots are
-- usable depends on the bags worn, so that is a rule of the game, not of the table.
create table character_item (
  item_guid bigint generated always as identity,
  character_id bigint not null,
  item2_id integer not null,
  location smallint not null,
  bag_index integer not null,
  stack_count integer not null,
  constraint character_item_pkey primary key (item_guid),
  constraint character_item_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_item_item2_id_fits_the_message
    check (item2_id between 1 and 262143),
  constraint character_item_location_is_held_by_the_client
    check (location in (0, 1, 2)),
  constraint character_item_bag_index_is_a_slot_of_its_location
    check (bag_index >= 0 and bag_index < case location
      when 0 then 31
      when 1 then 96
      else 232
    end),
  constraint character_item_stack_count_is_positive check (stack_count >= 1),
  -- One item in a place. It is deferrable so that one update can swap two items:
  -- a plain unique key is checked row by row and refuses the swap, and this one is
  -- checked at the statement's end. It is also the index that loads a character's
  -- items.
  constraint character_item_one_per_slot
    unique (character_id, location, bag_index) deferrable initially immediate
);
