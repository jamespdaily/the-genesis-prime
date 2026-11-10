-- The random-stat word of each item a character holds. The client reads one 64-bit word with
-- an item (message 0x111, the buyback entry): version 1 in the top byte and, in the low five
-- bytes, one choice byte for each entry of the item's stat row, the row's place in that
-- entry's random stat group. The word is chosen when the item is made, stored with it and
-- sent as it is; the client never sends it back.
--
-- 0 holds an item with no random stats, which the client reads as no data. Any other
-- value is one the client keeps: version 1 (a version 0 word with choices the client clears
-- to none, and the other versions it reads as 1), nothing in bits 40 to 55 (the word's
-- unused bytes) and at least one choice byte (a word with none is no roll). Whether a choice
-- byte fits its group is a fact of the client's tables, which the roll writes and the
-- loader of the item's properties checks.

alter table character_item
  add column random_stats bigint not null default 0,
  add constraint character_item_random_stats_version check (
    random_stats = 0
    or (
      random_stats >> 56 = 1
      and random_stats & x'00ffff0000000000'::bigint = 0
      and random_stats & x'000000ffffffffff'::bigint <> 0
    )
  );

comment on column character_item.random_stats is
  'The item''s random-stat choices as the client reads them: version 1 in the top byte and one choice byte for each entry of the item''s stat row in the low five bytes; 0 when the item has none.';
