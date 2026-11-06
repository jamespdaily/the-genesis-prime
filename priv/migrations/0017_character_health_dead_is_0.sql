-- A saved health of 0 is a character that left dead: its next entry is dead,
-- over the body at the saved place, and it comes back by its choice as after a
-- death in the world. NULL stays nothing saved (a character never saved enters
-- alive at full health) and a health above 0 is a character that left alive at
-- that health. The table refuses only a health below 0; the maximum comes from
-- the level and the client's tables at run time, so it holds no upper bound.
alter table character
  drop constraint character_health_is_positive,
  add constraint character_health_is_not_negative check (health >= 0);
