-- The moment each timed item a character holds runs out, in Unix milliseconds: an item whose
-- Item2 row has an expirationTimeMinutes above 0 is made with the moment its lifetime ends,
-- and the countdown runs in real time, also while its owner is logged out. NULL is an item
-- with no moment: one whose row has no lifetime, and a timed row saved before this column
-- existed, which then never runs out. A split keeps its source's moment and a merge keeps
-- the earlier of the two.
--
-- The check keeps the moment 0 or more.

alter table character_item
  add column expires_at_unix_ms bigint,
  add constraint character_item_expires_at_not_negative check (
    expires_at_unix_ms is null or expires_at_unix_ms >= 0
  );

comment on column character_item.expires_at_unix_ms is
  'The moment the item runs out, in Unix milliseconds; empty for an item that does not.';
