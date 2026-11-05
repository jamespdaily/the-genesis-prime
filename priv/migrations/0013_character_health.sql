-- The health a character left with, saved with its place (save_place.sql) and
-- read at entry (load_character.sql). NULL is nothing saved: the character
-- enters at full health, as every character did before this column, so no row
-- needs a backfill, and a save made while the player is dead writes NULL rather
-- than a made-up number (the death step's "full on coming back", the server's
-- choice). A saved health is above 0: the table refuses 0 and below, and a NULL
-- passes the check. The maximum comes from the level and the client's tables at
-- run time, so the table holds no upper bound; entry caps the saved value at it.
alter table character
  add column health integer,
  add constraint character_health_is_positive
    check (health > 0);
