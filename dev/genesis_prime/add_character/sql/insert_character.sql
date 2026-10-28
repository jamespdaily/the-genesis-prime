-- Adds a character to the account with this login name, for a developer's
-- database. The race, sex, class and faction are the values of one
-- CharacterCreation row; the level, path, world, zone and position are what a
-- new character of the character list needs and no more. The database makes
-- the id; no account of that name gives no row.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z
)
select
  account_id, $2, $3, $4, $5, $6, 1, 0, 0, 0, 0, 0, 0
from account
where login_name = $1
returning character_id;
