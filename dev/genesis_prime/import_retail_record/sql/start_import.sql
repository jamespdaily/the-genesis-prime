-- Records a run of the import with the counts the run will make and the SHA-256 of its
-- input, and gives the run's id: `$1` the digest, then the added, retired and kept counts of
-- the auto-attacks and of the specials.
insert into retail_record_import (
  input_sha256,
  auto_attacks_added, auto_attacks_retired, auto_attacks_kept,
  specials_added, specials_retired, specials_kept
)
values ($1, $2, $3, $4, $5, $6, $7)
returning id;
