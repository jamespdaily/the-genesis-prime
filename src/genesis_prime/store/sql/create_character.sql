-- Makes a character of an account: level 1, no world, zone or position (the
-- world's entry gives them), and the values the create request gave. It makes
-- none, and gives no row, when the account already has as many characters as
-- its slots. A name that another character holds in any case breaks the unique
-- index on lower(name), which the caller reports as its own error.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z,
  look_labels, look_values, bones
)
select
  $1::bigint, $2::text, $3::int, $4::int, $5::int, $6::int, 1, $7::int, 0, 0,
  0, 0, 0, $8::bigint[], $9::bigint[], $10::bigint[]
where (select count(*) from character where account_id = $1::bigint) < $11::bigint
returning character_id;
