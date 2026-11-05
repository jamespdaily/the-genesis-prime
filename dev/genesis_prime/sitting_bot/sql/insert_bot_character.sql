-- Makes the bot's character for the account with this login name ($1), named $2,
-- unless the account already has a character of that name (found as the name's
-- unique index finds it: any case, under the ICU root collation, migration
-- 0005). The race, sex, class and faction are those of CharacterCreation row 466
-- (race 1, sex 1, class 1, faction 167); it has no saved place (world 0).
-- A name another account's character holds breaks the name's unique index and
-- is refused, so the bot never takes another account's character.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z
)
select account_id, $2::text, 1, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0
from account
where login_name = $1
  and not exists (
    select 1
    from character
    where character.account_id = account.account_id
      and lower(character.name collate "und-x-icu")
        = lower($2::text collate "und-x-icu")
  );
