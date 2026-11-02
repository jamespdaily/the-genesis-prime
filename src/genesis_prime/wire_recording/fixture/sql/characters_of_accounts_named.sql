-- The characters of the accounts with these login names, in the order of their
-- ids, with every column the fixture of a recorded session keeps
-- (genesis_prime/wire_recording/fixture): the id, the account it belongs to, the
-- session epoch that fences a stale save and the number of the last save of that
-- login, what the character list shows, where it stands and which way it faces,
-- its look and bones and its rename mark. `created_at` is left out:
-- it is the time a row was made, which no flow reads.
select
  character_id,
  account_id,
  session_epoch,
  save_sequence,
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
  rotation_yaw,
  rotation_pitch,
  rotation_roll,
  look_labels,
  look_values,
  bones,
  needs_rename
from character
where account_id in (
  select account_id from account where login_name = any($1)
)
order by character_id;
