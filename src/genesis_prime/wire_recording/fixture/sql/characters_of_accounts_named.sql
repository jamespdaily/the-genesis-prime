-- The characters of the accounts with these login names, in the order of their
-- ids, with every column the fixture of a recorded session keeps
-- (genesis_prime/wire_recording/fixture): the id, the account it belongs to, the
-- session epoch that fences a stale save, what the character list shows, where
-- it stands, its look and bones and its rename mark. `created_at` is left out:
-- it is the time a row was made, which no flow reads.
select
  character_id,
  account_id,
  session_epoch,
  name,
  gender::int as gender,
  race_id::int as race_id,
  class_id::int as class_id,
  faction_id,
  level,
  path::int as path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  look_labels,
  look_values,
  bones,
  needs_rename
from character
where account_id in (
  select account_id from account where login_name = any($1)
)
order by character_id;
